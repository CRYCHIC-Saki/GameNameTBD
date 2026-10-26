class_name TDRestaurantWorld
extends Node2D

signal fixture_used(piece_id: String, code: String)
signal back_requested
signal pause_requested
signal kitchen_requested
signal object_requested(action: String)
var player_mode: bool = false
var business: TDShopSession
var _business_guests: Dictionary = {}

const CHEF := preload("res://assets/kitchen/chef-v1.png")
const INTERACTION_RADIUS := 78.0
const BRUSHES: Array[String] = ["+", ".", "R", "O", "D", "#"]

var save_path: String = ""
var guest_speed: float = 150.0
var layout: TDRestaurantLayout
var catalog: TDRestaurantCatalog
var _player: TDKitchenPlayer
var _floor: Sprite2D
var _blockers: StaticBody2D
var _fixtures: Node2D
var _guests: Node2D
var _status: Label
var _editing: bool = false
var _dirty: bool = false
var _selected: String = ""
var _tool: String = "select"
var _armed_kind: String = "dining_table"
var _brush: String = "."
var _culture: String = "chinese"
var _tier: String = "low"
var _store: TDRestaurantStore
var _theme: Theme
var _closed: bool = false
var _edit_box: HFlowContainer
var _edit_button: Button
var _kind_button: Button
var _brush_button: Button
var _style_button: Button
var _tier_button: Button
var _greeter_button: Button
var _cashier_button: Button
var _bar: Panel
var _bar_box: VBoxContainer
var _play_row: HFlowContainer
var _service_buttons: Array[Button] = []
var session: TDPhase3Session
var _covered: bool = false
var _observing: bool = false
var _observe_banner: Label
var _held_ticket: String = ""
var _runner_on: bool = false
var _runner_pos := Vector2.ZERO
var _runner_goal := Vector2i(-1, -1)
var _runner_points := PackedVector2Array()
var _runner_index: int = 0
var _runner_ticket: String = ""
var _runner_button: Button
var _crew_time: float = 0.0
var _waiter_feet: Array[Vector2] = []
var _iso: TDRestaurantIsoView
var _board: TDEconomyBoard
var _pantry: TDPantryBoard

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_theme = TDUI.theme()
	catalog = TDRestaurantCatalog.new()
	var loaded := catalog.load_file()
	if not loaded.ok:
		_build_status_bar()
		_set_status(loaded.message)
		return
	if layout == null:
		layout = catalog.default_layout()
	_culture = layout.culture
	_tier = layout.tier
	var warning := ""
	if save_path != "":
		_store = TDRestaurantStore.new(save_path)
		var read := _store.load_layout(catalog)
		if read.ok:
			layout = _store.loaded_layout
			_culture = layout.culture
			_tier = layout.tier
		elif read.code != "NOT_FOUND":
			warning = read.message
	elif session != null and session.ready and session.scaled_interior:
		var grid := session.interior_grid()
		var sized := TDRestaurantLayout.make_sized(catalog, grid.x, grid.y, session.interior_culture())
		if sized != null:
			layout = sized
			_culture = layout.culture
			_tier = layout.tier
		else:
			warning = TDRestaurantLayout.floor_error
	_build_world()
	_build_status_bar()
	_rebuild()
	teleport_player(_spawn_cell())
	if warning != "" and save_path != "":
		_set_status("布置档没有读入：" + warning)
	elif warning != "":
		_set_status(warning)
	else:
		var room := "斜角看地面和两面墙。WASD 沿过道走，E 互动。站在门口按 E 进后厨。后厨按 V 看餐厅。装修计入客流评价，不写入原来的营业账。"
		if session != null and session.scaled_interior:
			room = "店内按地图面积生成，%d×%d格。%s" % [layout.columns, layout.rows, room]
		_set_status(room)
	_pull_layout_staff()
	if player_mode:
		_set_status("WASD 走动 · 招工处可雇厨师或服务员 · 门牌、账本、装修桌或门按 E · B 菜谱 · Esc 暂停")
		_iso.interaction_markers=interaction_points()

func _process(delta: float) -> void:
	if _player != null:
		_player.z_index = int(_player.position.y)
	if player_mode and not get_tree().paused:
		_crew_time += delta
		_sync_business_guests()
	elif not get_tree().paused:
		_tick_service(delta)
	for guest: TDRestaurantGuest in guest_nodes():
		_place_seated(guest)
		guest.z_index = int(guest.position.y)
		if not guest.service_active and guest.finished and guest.seat_id != "" and not guest.has_meta("announced"):
			guest.set_meta("announced", true)
			var seat := layout.piece(guest.seat_id)
			_set_status("客人走到了%s" % String(seat.get("name", "座位")))
		elif guest.service_active and not player_mode:
			_watch_service(guest)
	if not get_tree().paused and not player_mode:
		_tick_runner(delta)
	if _iso != null:
		_iso.editing = _editing
		_iso.selected_id = _selected
		_iso.runner_visible = _runner_on
		_iso.runner_point = _runner_pos
		_iso.runner_label = _runner_caption()
		_iso.pass_point = layout.cell_center(pass_cell()) if _pass_has_plate() else Vector2(-1, -1)
		_iso.held_label = _held_caption()
		_iso.crew_people = _crew_points(0.0 if get_tree().paused else delta)
		_iso.sync(_player, guest_nodes())
	if _editing:
		queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if _closed or layout == null:
		return
	if event.is_action_pressed("pause") and not event.is_echo():
		pause_requested.emit()
		get_viewport().set_input_as_handled()
		return
	if get_tree().paused:
		return
	if event.is_action_pressed("world_interact") and not event.is_echo():
		if request_interaction():
			get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
	if _closed or not _editing or layout == null or _iso == null or get_tree().paused:
		return
	if not event is InputEventMouseButton:
		return
	var click := event as InputEventMouseButton
	if not click.pressed or click.button_index not in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		return
	if _pointer_on_chrome(click.position):
		return
	_click_cell(_iso.pick_cell(_screen_to_room(click.position)), click.button_index)
	get_viewport().set_input_as_handled()

func _screen_to_room(screen: Vector2) -> Vector2:
	var camera := _iso.get_node_or_null("IsoCamera") as Camera2D
	if camera == null or not camera.enabled:
		return screen
	var view := get_viewport().get_visible_rect().size
	return camera.position + (screen - view * 0.5) / camera.zoom

func _pointer_on_chrome(screen: Vector2) -> bool:
	if _board != null and is_instance_valid(_board):
		return true
	return _bar != null and Rect2(_bar.position, _bar.size).has_point(screen)

func _draw() -> void:
	if _iso != null or not _editing or layout == null:
		return
	var line := Color(1, 1, 1, 0.2)
	var width := float(layout.columns * layout.cell_px)
	var height := float(layout.rows * layout.cell_px)
	for x in layout.columns + 1:
		var column := float(x * layout.cell_px)
		draw_line(Vector2(column, 0), Vector2(column, height), line)
	for y in layout.rows + 1:
		var row := float(y * layout.cell_px)
		draw_line(Vector2(0, row), Vector2(width, row), line)
	var selected := layout.piece(_selected)
	if not selected.is_empty():
		draw_rect(Rect2(int(selected["x"]) * layout.cell_px, int(selected["y"]) * layout.cell_px, int(selected["w"]) * layout.cell_px, int(selected["h"]) * layout.cell_px), Color("f0cc70"), false, 3.0)

func close() -> void:
	_closed = true
	if session != null:
		session.floor.clear()
	if _iso != null:
		_iso.shutdown()
	set_process(false)
	set_process_input(false)
	set_process_unhandled_input(false)
	set_process_unhandled_key_input(false)
	if _player != null:
		_player.set_controls_enabled(false)
	if _pantry != null and is_instance_valid(_pantry):
		_pantry.queue_free()

func player_position() -> Vector2:
	return _player.position if _player != null else Vector2.ZERO

func _feet_inside_room(proposed: Vector2) -> bool:
	return layout != null and layout.feet_inside(proposed)

func cell_of_player() -> Vector2i:
	return _cell_at(player_position())

func teleport_player(cell: Vector2i) -> void:
	if _player == null or layout == null:
		return
	_player.position = layout.cell_center(cell)
	_player.velocity = Vector2.ZERO

func fixture_count() -> int:
	return _fixtures.get_child_count() if _fixtures != null else 0

func guest_nodes() -> Array[TDRestaurantGuest]:
	var result: Array[TDRestaurantGuest] = []
	if _guests == null:
		return result
	for child: Node in _guests.get_children():
		if child is TDRestaurantGuest:
			result.append(child)
	return result

func request_interaction() -> bool:
	if _closed or _player == null or layout == null or get_tree().paused or _covered:
		return false
	if player_mode:
		var nearest: Dictionary={};var distance:float=1.6
		for entry: Dictionary in interaction_points():
			var gap:=Vector2(cell_of_player()).distance_to(entry.cell)
			if gap<distance: nearest=entry;distance=gap
		if nearest.is_empty(): return false
		object_requested.emit(str(nearest.action))
		return true
	if _held_ticket != "" and _player_at_seat(_held_ticket):
		_set_status(deliver_held_plate().message)
		return true
	if _held_ticket == "" and cell_of_player() == pass_cell() and _pass_has_plate():
		_set_status(pickup_pass_plate().message)
		return true
	if _held_ticket != "" and cell_of_player() == pass_cell():
		_session().floor.release_plate(_held_ticket)
		_held_ticket = ""
		_set_status("把菜放回传菜口。")
		return true
	if cell_of_player() == layout.entrance():
		kitchen_requested.emit()
		_set_status("走进后厨。出餐后菜放在门口里侧的传菜口，要端到客人坐下的那一桌。按 V 只看餐厅，时间继续走。")
		return true
	var nearest := _nearest_piece()
	if nearest.is_empty():
		return false
	var code := layout.interact_code(String(nearest["id"]))
	_set_status(_interact_message(nearest, code))
	fixture_used.emit(String(nearest["id"]), code)
	return true

func spawn_guest() -> TDOutcome:
	if layout == null:
		return TDOutcome.new(false, "NOT_READY", "餐厅还没准备好")
	var occupied: Array = []
	for guest: TDRestaurantGuest in guest_nodes():
		if guest.seat_id != "":
			occupied.append(guest.seat_id)
	var route := layout.route_guest(occupied)
	if not bool(route["ok"]):
		_set_status(String(route["message"]))
		return TDOutcome.new(false, String(route["code"]), String(route["message"]))
	var guest := TDRestaurantGuest.new()
	guest.name = "Guest"
	guest.seat_id = String(route["seat_id"])
	guest.speed = guest_speed
	guest.process_mode = Node.PROCESS_MODE_PAUSABLE
	_guests.add_child(guest)
	guest.set_path(route["path"], layout.cell_px)
	_set_status(String(route["message"]))
	return TDOutcome.new(true, "SEATED", guest.seat_id)

func place_kind(kind: String, x: int, y: int) -> TDOutcome:
	return _apply(layout.place(kind, x, y, 0))

func paint_cell(x: int, y: int, symbol: String) -> TDOutcome:
	return _apply(layout.paint(x, y, symbol))

func nudge_selected(dx: int, dy: int) -> TDOutcome:
	var current := layout.piece(_selected)
	if current.is_empty():
		return _note(TDOutcome.new(false, "MISSING", "先点选一件家具"))
	return _apply(layout.move_piece(_selected, int(current["x"]) + dx, int(current["y"]) + dy))

func remove_selected() -> TDOutcome:
	if _selected == "":
		return _note(TDOutcome.new(false, "MISSING", "先点选一件家具"))
	var result := layout.remove_piece(_selected)
	if result.ok:
		_selected = ""
	return _apply(result)

func _pull_layout_staff() -> void:
	var active := _session()
	if active == null or layout == null:
		return
	for role: String in ["greeter", "cashier"]:
		if layout.staff_hired(role) and not active.staff_on(role):
			var paid := active.employ(role)
			if not paid.ok:
				layout.set_staff(role, false)
	_push_session_staff()

func _push_session_staff() -> void:
	var active := _session()
	if active == null or layout == null:
		return
	for role: String in ["greeter", "cashier"]:
		layout.set_staff(role, active.staff_on(role))
	_refresh_buttons()

func hire_role(role: String, hired: bool) -> TDOutcome:
	var active := _session()
	if active == null:
		var fallback := layout.set_staff(role, hired)
		if fallback.ok:
			_dirty = true
			_refresh_buttons()
		return _note(fallback)
	var result := active.employ(role) if hired else active.dismiss(role)
	if not result.ok:
		return _note(result)
	if layout.staff_hired(role) or ["greeter", "cashier"].has(role):
		var placed := layout.set_staff(role, active.staff_on(role))
		if placed.ok:
			_dirty = true
	if not hired and role == "runner" and _runner_ticket != "":
		active.floor.release_plate(_runner_ticket)
		_runner_ticket = ""
	_refresh_buttons()
	return _note(result)

func restyle_selected() -> TDOutcome:
	if _selected == "":
		return _note(TDOutcome.new(false, "MISSING", "先点选一件家具"))
	var result := layout.restyle_piece(_selected, _culture, _tier)
	if result.ok:
		_dirty = true
		_rebuild()
	return _note(result)

func restyle_venue() -> TDOutcome:
	var result := layout.apply_venue_style(_culture, _tier)
	if result.ok:
		_dirty = true
		_culture = layout.culture
		_tier = layout.tier
		_rebuild()
		result = TDOutcome.new(true, result.code, result.message + "。原来的营业账不变，客流评价会用这套装修。")
	return _note(result)

func reset_layout() -> void:
	layout = catalog.default_layout()
	_culture = layout.culture
	_tier = layout.tier
	_selected = ""
	_dirty = true
	_clear_guests()
	_rebuild()
	_set_status("已恢复默认布置。点保存后才会写入文件。")

func save_current() -> TDOutcome:
	if save_path == "":
		return _note(TDOutcome.new(false, "NO_PATH", "当前入口没有布置存档路径"))
	if _store == null:
		_store = TDRestaurantStore.new(save_path)
	var result := _store.save_layout(layout)
	if result.ok:
		_dirty = false
	return _note(result)

func _build_world() -> void:
	_floor = Sprite2D.new()
	_floor.name = "Floor"
	_floor.centered = false
	_floor.z_index = -10
	add_child(_floor)
	_blockers = StaticBody2D.new()
	_blockers.name = "Blockers"
	# Rooms coexist to keep service/QTE state alive; visibility does not disable physics.
	_blockers.collision_layer = 4
	_blockers.collision_mask = 0
	add_child(_blockers)
	_fixtures = Node2D.new()
	_fixtures.name = "Fixtures"
	add_child(_fixtures)
	_guests = Node2D.new()
	_guests.name = "Guests"
	add_child(_guests)
	_player = TDKitchenPlayer.new()
	_player.name = "Player"
	_player.process_mode = Node.PROCESS_MODE_PAUSABLE
	_player.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	_player.collision_layer = 8
	_player.collision_mask = 4
	var sprite := Sprite2D.new()
	sprite.name = "Sprite2D"
	sprite.texture = CHEF
	sprite.scale = Vector2(0.07, 0.07)
	sprite.position = Vector2(0, -47)
	_player.add_child(sprite)
	var feet := CollisionShape2D.new()
	var capsule := CapsuleShape2D.new()
	capsule.radius = 12.0
	capsule.height = 28.0
	feet.shape = capsule
	_player.add_child(feet)
	sprite.visible = false
	if player_mode:
		_player.confine_to = _feet_inside_room
	add_child(_player)
	_iso = TDRestaurantIsoView.new()
	_iso.name = "IsoView"
	add_child(_iso)

func _build_status_bar() -> void:
	var layer := CanvasLayer.new()
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	var panel := Panel.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_bar = panel
	layer.add_child(panel)
	get_viewport().size_changed.connect(_fit_bar)
	_observe_banner = Label.new()
	_observe_banner.text = "正在看餐厅 · 再按 V 回后厨 · 客人和灶台的时间都在走"
	_observe_banner.position = Vector2(24, 12)
	_observe_banner.size = Vector2(900, 32)
	_observe_banner.visible = false
	_observe_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_observe_banner.add_theme_font_size_override("font_size", 18)
	_observe_banner.add_theme_color_override("font_color", Color("f0cc70"))
	layer.add_child(_observe_banner)
	var box := VBoxContainer.new()
	_bar_box = box
	box.position = Vector2(10, 8)
	box.size = Vector2(1260, 152)
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	_status = Label.new()
	_status.custom_minimum_size = Vector2(1240, 32)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 15)
	box.add_child(_status)
	var play := HFlowContainer.new()
	_play_row = play
	play.add_theme_constant_override("h_separation", 6)
	play.add_theme_constant_override("v_separation", 4)
	box.add_child(play)
	play.add_child(_button("返回", _back))
	play.add_child(_button("暂停", func() -> void: pause_requested.emit()))
	if layout == null:
		_fit_bar()
		return
	_edit_button = _button("布置", _toggle_edit)
	play.add_child(_edit_button)
	_add_service_button(play, "试来客", spawn_guest)
	_add_service_button(play, "全程来客", spawn_service_guest)
	_add_service_button(play, "接下", _accept_order)
	_add_service_button(play, "拒绝", _refuse_order)
	_add_service_button(play, "认真上菜", func() -> void: _serve(92.0))
	_add_service_button(play, "马虎上菜", func() -> void: _serve(35.0))
	_add_service_button(play, "客流面板", _open_board)
	_add_service_button(play, "备料", _open_pantry)
	_add_service_button(play, "去厨房", func() -> void: kitchen_requested.emit())
	_greeter_button = _button("雇用迎宾", func() -> void: hire_role("greeter", not layout.staff_hired("greeter")))
	_cashier_button = _button("雇用收银", func() -> void: hire_role("cashier", not layout.staff_hired("cashier")))
	play.add_child(_greeter_button)
	play.add_child(_cashier_button)
	_runner_button = _button("雇用传菜员", func() -> void: hire_role("runner", not _session().staff_on("runner")))
	play.add_child(_runner_button)
	_service_buttons.append(_runner_button)
	_service_buttons.append(_greeter_button)
	_service_buttons.append(_cashier_button)
	play.add_child(_button("保存", save_current))
	_edit_box = HFlowContainer.new()
	_edit_box.visible = false
	_edit_box.add_theme_constant_override("h_separation", 6)
	_edit_box.add_theme_constant_override("v_separation", 4)
	box.add_child(_edit_box)
	_edit_box.add_child(_button("选择", func() -> void: _set_tool("select")))
	_kind_button = _button("家具", _cycle_kind)
	_brush_button = _button("笔刷", _cycle_brush)
	_style_button = _button("风格", _cycle_culture)
	_tier_button = _button("档次", _cycle_tier)
	_edit_box.add_child(_kind_button)
	_edit_box.add_child(_brush_button)
	_edit_box.add_child(_style_button)
	_edit_box.add_child(_tier_button)
	_edit_box.add_child(_button("这件换风格", restyle_selected))
	_edit_box.add_child(_button("全店套用", restyle_venue))
	_edit_box.add_child(_button("上", func() -> void: nudge_selected(0, -1)))
	_edit_box.add_child(_button("下", func() -> void: nudge_selected(0, 1)))
	_edit_box.add_child(_button("左", func() -> void: nudge_selected(-1, 0)))
	_edit_box.add_child(_button("右", func() -> void: nudge_selected(1, 0)))
	_edit_box.add_child(_button("转向", _rotate_selected))
	_edit_box.add_child(_button("拆除", remove_selected))
	_edit_box.add_child(_button("恢复默认", reset_layout))
	if player_mode:
		_play_row.hide()
		_edit_box.get_child(_edit_box.get_child_count()-1).hide()
		_edit_box.add_child(_button("完成布置",_toggle_edit))
	_fit_bar()

func _rebuild() -> void:
	if layout == null or _floor == null:
		return
	_floor.texture = TDRestaurantArt.floor_texture(layout)
	_floor.visible = false
	if _iso != null:
		_iso.set_room(layout)
	if session != null and session.ready:
		session.set_player_pieces(layout.pieces())
	_free_children(_blockers)
	_free_children(_fixtures)
	for y in layout.rows:
		for x in layout.columns:
			if not layout.is_walkable(x, y):
				var shape := RectangleShape2D.new()
				shape.size = Vector2(layout.cell_px, layout.cell_px)
				var collider := CollisionShape2D.new()
				collider.shape = shape
				collider.position = layout.cell_center(Vector2i(x, y))
				_blockers.add_child(collider)
	for item: Variant in layout.pieces():
		_add_fixture(item)
	if _player != null and not layout.is_walkable(cell_of_player().x, cell_of_player().y):
		teleport_player(layout.entrance())
	_refresh_buttons()
	queue_redraw()

func _add_fixture(item: Dictionary) -> void:
	var node := Node2D.new()
	node.position = Vector2(int(item["x"]) * layout.cell_px, int(item["y"]) * layout.cell_px)
	node.z_index = (int(item["y"]) + int(item["h"])) * layout.cell_px
	var parts := String(item["style_id"]).split("_")
	var culture := parts[0] if parts.size() == 2 else "plain"
	var tier := parts[1] if parts.size() == 2 else "low"
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.texture = TDRestaurantArt.piece_texture(String(item["kind"]), String(item["surface"]), culture, tier, int(item["w"]) * layout.cell_px, int(item["h"]) * layout.cell_px)
	sprite.visible = false
	node.add_child(sprite)
	var label := Label.new()
	label.text = String(item["name"])
	label.position = Vector2(4, 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.theme = _theme
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.visible = false
	node.add_child(label)
	_fixtures.add_child(node)

func _click_cell(cell: Vector2i, button: int = MOUSE_BUTTON_LEFT) -> void:
	if cell.x < 0 or cell.y < 0 or cell.x >= layout.columns or cell.y >= layout.rows:
		_set_status("点在房间外面了。")
		return
	var hit := _piece_at(cell)
	if button == MOUSE_BUTTON_RIGHT:
		if hit == "":
			_set_status("这里没有家具。")
			return
		_selected = hit
		remove_selected()
		return
	if _tool == "paint":
		paint_cell(cell.x, cell.y, _brush)
		return
	if _tool == "place" and hit == "":
		place_kind(_armed_kind, cell.x, cell.y)
		return
	_selected = hit
	queue_redraw()
	if _selected == "":
		_set_status("这格是空的。先点「放置」，再点空地新增。")
	else:
		var selected := layout.piece(_selected)
		_set_status("选中%s。方向键移动，右键或「拆除」删掉它。" % String(selected["name"]))

func _apply(result: TDOutcome) -> TDOutcome:
	if result.ok:
		_dirty = true
		if result.data.has("id"):
			_selected = String(result.data["id"])
		_clear_guests()
		_rebuild()
	return _note(result)

func _nearest_piece() -> Dictionary:
	var best: Dictionary = {}
	var shortest := INTERACTION_RADIUS
	for item: Variant in layout.pieces():
		var current: Dictionary = item
		var anchor := layout.cell_center(_anchor(current))
		var distance := _player.position.distance_to(anchor)
		if distance <= shortest:
			shortest = distance
			best = current
	return best

func _anchor(piece: Dictionary) -> Vector2i:
	if bool(piece["has_approach"]):
		return Vector2i(int(piece["approach_x"]), int(piece["approach_y"]))
	return Vector2i(int(piece["x"]) + int((int(piece["w"]) - 1) / 2.0), int(piece["y"]))

func _piece_at(cell: Vector2i) -> String:
	for item: Variant in layout.pieces():
		var current: Dictionary = item
		if cell.x >= int(current["x"]) and cell.y >= int(current["y"]) and cell.x < int(current["x"]) + int(current["w"]) and cell.y < int(current["y"]) + int(current["h"]):
			return String(current["id"])
	return ""

func _interact_message(piece: Dictionary, code: String) -> String:
	if code == "NEED_GREETER":
		return "迎宾台还没有迎宾。雇用会从现金里付当天工资。"
	if code == "NEED_CASHIER":
		return "收银台还没有收银员。雇用会从现金里付当天工资。"
	match String(piece["kind"]):
		"storefront":
			return "门面。可换成中式、日式、法式等，以及低端或高端。朴素、现代、生活是通配风格。"
		"welcome_desk":
			return "迎宾在岗，试来客会从门口走到这里，再去空位。"
		"kiosk":
			return "自助点餐机可以直接使用，不必雇人。客人点的菜和这个人绑在一起，后厨能看到。"
		"order_counter":
			return "点餐台。点下的菜就是后厨那一单，客人坐下后才等上菜。"
		"hotpot_table":
			return "火锅桌，桌面上是电磁炉。"
		"waiting_seat":
			return "等候座。客人入座时优先去用餐区。"
		"screen":
			return "屏风，用来隔开等候区。"
		_:
			if String(piece["seat_use"]) == "dining":
				return "%s可以入座。" % String(piece["name"])
			return String(piece["name"])

func _toggle_edit() -> void:
	_editing = not _editing
	_edit_box.visible = _editing
	for button: Button in _service_buttons:
		button.visible = not _editing
	_edit_button.text = "完成布置" if _editing else "布置"
	_tool = "select"
	_fit_bar()
	queue_redraw()
	_set_status("左键点家具选中。点「放置」后再点空地新增。右键或「拆除」删掉点中的那件。" if _editing else "回到走动。E 可以查看家具。")

func _cycle_kind() -> void:
	var kinds := catalog.kinds()
	var index := kinds.find(_armed_kind)
	_armed_kind = kinds[(index + 1) % kinds.size()]
	_tool = "place"
	_refresh_buttons()
	_set_status("再点一格空地，放下%s。点到已有家具会改成选中，右键拆除。" % String(catalog.furniture(_armed_kind)["name"]))

func _cycle_brush() -> void:
	var index := BRUSHES.find(_brush)
	_brush = BRUSHES[(index + 1) % BRUSHES.size()]
	_tool = "paint"
	_refresh_buttons()
	_set_status("下一次点击把格子改成%s。顾客只能走门口和过道。" % _brush_name(_brush))

func _cycle_culture() -> void:
	var cultures := catalog.cultures()
	var index := cultures.find(_culture)
	_culture = cultures[(index + 1) % cultures.size()]
	_refresh_buttons()
	_set_status("当前选择%s。可只换选中的一件，或全店套用。" % catalog.culture_name(_culture))

func _cycle_tier() -> void:
	_tier = "high" if _tier == "low" else "low"
	_refresh_buttons()
	_set_status("当前档次是%s。高端只是更亮的占位外观。" % catalog.tier_name(_tier))

func _rotate_selected() -> void:
	if _selected == "":
		_set_status("先点选一件家具")
		return
	_apply(layout.rotate_piece(_selected))

func _set_tool(next: String) -> void:
	_tool = next
	_set_status("点击家具即可选中。" if next == "select" else next)

func _refresh_buttons() -> void:
	if layout == null:
		return
	var greeter_wage := 8
	var cashier_wage := 8
	if session != null and session.ready:
		greeter_wage = session.catalog.wage_of("greeter")
		cashier_wage = session.catalog.wage_of("cashier")
	if _greeter_button != null:
		_greeter_button.text = "辞退迎宾" if layout.staff_hired("greeter") else "雇用迎宾（%d元）" % greeter_wage
	if _cashier_button != null:
		_cashier_button.text = "辞退收银" if layout.staff_hired("cashier") else "雇用收银（%d元）" % cashier_wage
	if _runner_button != null:
		var runner_wage := 7
		var runner_on := false
		if session != null and session.ready:
			runner_wage = session.catalog.wage_of("runner")
			runner_on = session.staff_on("runner")
		_runner_button.text = "辞退传菜员" if runner_on else "雇用传菜员（%d元）" % runner_wage
	if _kind_button != null:
		_kind_button.text = "放置：" + String(catalog.furniture(_armed_kind).get("name", _armed_kind))
	if _brush_button != null:
		_brush_button.text = "笔刷：" + _brush_name(_brush)
	if _style_button != null:
		_style_button.text = "风格：" + catalog.culture_name(_culture)
	if _tier_button != null:
		_tier_button.text = "档次：" + catalog.tier_name(_tier)

func _brush_name(symbol: String) -> String:
	match symbol:
		"+":
			return "门口"
		".":
			return "过道"
		"R":
			return "接待"
		"O":
			return "点餐"
		"D":
			return "用餐"
		"#":
			return "墙"
		_:
			return symbol

func _back() -> void:
	if _dirty and save_path != "":
		var saved := save_current()
		if not saved.ok:
			return
	back_requested.emit()

func _clear_guests() -> void:
	if _guests != null:
		_free_children(_guests)

func _free_children(node: Node) -> void:
	for child: Node in node.get_children():
		node.remove_child(child)
		child.free()

func _cell_at(point: Vector2) -> Vector2i:
	if layout == null:
		return Vector2i(-1, -1)
	return Vector2i(floori(point.x / layout.cell_px), floori(point.y / layout.cell_px))

func _add_service_button(row: HFlowContainer, text: String, action: Callable) -> void:
	var button := _button(text, action)
	row.add_child(button)
	_service_buttons.append(button)

func _fit_bar() -> void:
	if _bar == null:
		return
	var height := 220 if _editing else (68 if player_mode else 168)
	var view_size := get_viewport().get_visible_rect().size
	_bar.size = Vector2(view_size.x, height)
	_bar.position = Vector2(0, view_size.y - height)
	if _bar_box != null:
		_bar_box.size = Vector2(view_size.x - 20, height - 16)
	if _status != null:
		_status.custom_minimum_size.x = view_size.x - 40

func _spawn_cell() -> Vector2i:
	var door := layout.entrance()
	var inside := door + Vector2i.RIGHT
	if layout.is_walkable(inside.x, inside.y):
		return inside
	return door

func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.theme = _theme
	button.custom_minimum_size = Vector2(104, 32)
	button.add_theme_font_size_override("font_size", 14)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#213f3d")
	style.border_color = Color("#507064")
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	button.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate() as StyleBoxFlat
	hover.bg_color = Color("#355d56")
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_stylebox_override("focus", style)
	button.pressed.connect(callback)
	return button

func _note(result: TDOutcome) -> TDOutcome:
	_set_status(result.message)
	return result

func _set_status(text: String) -> void:
	if _status != null:
		_status.text = text

func pump_service(steps: int, step_sec: float = 0.2) -> void:
	for _index in steps:
		_tick_service(step_sec)
		for guest: TDRestaurantGuest in guest_nodes():
			_place_seated(guest)
			if guest.service_active:
				_watch_service(guest)
		_tick_runner(step_sec)

func spawn_service_guest(forced_dish: String = "") -> TDOutcome:
	var active := _session()
	if active == null or layout == null:
		return TDOutcome.new(false, "NOT_READY", "客流数据还没准备好")
	active.set_player_pieces(layout.pieces())
	var occupied: Array = []
	for guest: TDRestaurantGuest in guest_nodes():
		if guest.seat_id != "":
			occupied.append(guest.seat_id)
	var npc := active.make_visit_npc()
	var order := active.roll_order(npc, forced_dish)
	var dish: Dictionary = order["dish"]
	if dish.is_empty():
		return TDOutcome.new(false, "NO_DISH", "没有可点的菜")
	var route := TDRestaurantService.plan(layout, occupied, bool(order["off_menu"]), layout.staff_hired("cashier"))
	if not bool(route["ok"]):
		_set_status(String(route["message"]))
		return TDOutcome.new(false, String(route["code"]), String(route["message"]))
	var guest := TDRestaurantGuest.new()
	guest.name = "ServiceGuest"
	guest.seat_id = String(route["seat_id"])
	guest.speed = guest_speed
	guest.process_mode = Node.PROCESS_MODE_PAUSABLE
	_guests.add_child(guest)
	guest.begin_service(route["stages"], layout.cell_px, String(dish["id"]), String(dish["name"]), bool(order["off_menu"]), npc)
	guest.ticket_id = active.floor.open_ticket(guest.dish_id, guest.dish_name, guest.off_menu, guest.seat_id, String(npc.get("id", "客人")))
	_set_status("%s进门，%s%s。" % [String(npc["id"]), "菜单上没有的" if bool(order["off_menu"]) else "", String(dish["name"])])
	return TDOutcome.new(true, "VISIT", String(dish["id"]))

func _session() -> TDPhase3Session:
	if session == null:
		session = TDPhase3Session.new()
	if not session.ready:
		var loaded := session.load_default()
		if not loaded.ok:
			_set_status(loaded.message)
			return null
	return session

func _tick_service(delta: float) -> void:
	for guest: TDRestaurantGuest in guest_nodes():
		if guest.service_active:
			guest.service_tick(delta)
	_sync_tickets()
	var active := session if session != null and session.ready else null
	if active == null:
		return
	var expired := active.floor.tick(delta)
	for ticket_id: String in expired:
		var guest := _guest_by_ticket(ticket_id)
		if guest == null:
			continue
		guest.leave_hungry()
		_set_status("%s等不及%s，起身离开。" % [String(guest.profile.get("id", "客人")), guest.dish_name])

func _watch_service(guest: TDRestaurantGuest) -> void:
	var shown := String(guest.get_meta("shown_phase", ""))
	if shown == guest.phase:
		if guest.phase == "pay" and guest.is_waiting() and layout.staff_hired("cashier"):
			guest.clear_wait()
		return
	guest.set_meta("shown_phase", guest.phase)
	if guest.phase == "leave" and guest.accepted and guest.review_score < 0.0:
		var served_meal := not guest.walkout
		var reason := "timeout" if guest.walkout else ""
		var meal_quality := guest.quality if served_meal else 0.0
		var result := _session().settle_visit(guest.profile, guest.dish_id, meal_quality, _session().decor_from_pieces(layout.pieces()), served_meal, reason)
		var meal: Dictionary = result["meal"]
		guest.review_score = float(meal["overall"])
		if guest.review_score < 0.0:
			guest.review_score = 0.0
		last_visit = result
	if guest.phase == "pay" and guest.is_waiting() and layout.staff_hired("cashier"):
		guest.clear_wait()
	_set_status(_phase_text(guest))

func _accept_order() -> void:
	var guest := _waiting_guest("order")
	if guest == null:
		_set_status("没有客人在等你接单。")
		return
	guest.clear_wait()
	_sync_tickets()
	_set_status("接下了%s。客人入座后，后厨才能把这盘菜端给这个人。" % guest.dish_name)

func _refuse_order() -> void:
	var guest := _waiting_guest("order")
	if guest == null:
		_set_status("没有客人在等你决定点单。")
		return
	_session().floor.mark_refused(guest.ticket_id)
	guest.refuse_order()
	var result := _session().settle_visit(guest.profile, guest.dish_id, 0.0, _session().decor_from_pieces(layout.pieces()), false)
	last_visit = result
	_set_status("拒绝了%s，不会学会这道菜。" % guest.dish_name)

func _serve(quality: float) -> TDOutcome:
	var result := serve_waiting(quality)
	_set_status(result.message)
	return result

func serve_waiting(quality: float) -> TDOutcome:
	var active := _session()
	if active == null:
		return TDOutcome.new(false, "NOT_READY", "客流数据还没准备好")
	_sync_tickets()
	var plated := active.floor.hold_plate("", quality)
	if not plated.ok:
		return plated
	var who := String((plated.data as Dictionary).get("npc_id", "客人"))
	plated.message = "这盘菜放在传菜口，要端给坐着的%s。走到门口里侧按 E 端起。" % who
	return plated

func deliver_to_guest(dish_id: String, quality: float, failed: bool) -> TDOutcome:
	var active := _session()
	if active == null:
		return TDOutcome.new(false, "NOT_READY", "客流数据还没准备好")
	_sync_tickets()
	var target := "" if failed or dish_id == "" else dish_id
	if not failed and dish_id == "":
		return TDOutcome.new(false, "UNKNOWN_DISH", "这盘菜对不上菜单，没有放上传菜口。")
	var plated := active.floor.hold_plate(target, quality)
	if not plated.ok:
		return plated
	var who := String((plated.data as Dictionary).get("npc_id", "客人"))
	if failed:
		plated.message = "这盘没做成，放在传菜口，要端给坐着等的%s。" % who
	else:
		plated.message = "%s的菜放在门口里侧的传菜口。走到那里按 E 端起，再到这桌座位旁按 E。雇了传菜员会自己端过去。" % who
	return plated

func pass_cell() -> Vector2i:
	return _spawn_cell()

func approach_cell(seat_id: String) -> Vector2i:
	if layout == null:
		return Vector2i(-1, -1)
	var seat := layout.piece(seat_id)
	if seat.is_empty():
		return Vector2i(-1, -1)
	return Vector2i(int(seat["approach_x"]), int(seat["approach_y"]))

func pickup_pass_plate() -> TDOutcome:
	var active := _session()
	if active == null:
		return TDOutcome.new(false, "NOT_READY", "客流数据还没准备好")
	if _held_ticket != "":
		return TDOutcome.new(false, "HANDS_FULL", "手上已经有一盘菜。")
	if cell_of_player() != pass_cell():
		return TDOutcome.new(false, "TOO_FAR", "先走到门口里侧的传菜口。")
	var plate := active.floor.pass_plate()
	if plate.is_empty():
		return TDOutcome.new(false, "NO_PLATE", "传菜口还没有菜。")
	var claimed := active.floor.claim_plate(String(plate["id"]), "player")
	if not claimed.ok:
		return claimed
	_held_ticket = String(plate["id"])
	claimed.message = "端起%s，送到%s那桌座位旁边，再按 E。" % [String(plate["dish_name"]), String(plate["npc_id"])]
	return claimed

func deliver_held_plate() -> TDOutcome:
	if _held_ticket == "":
		return TDOutcome.new(false, "NO_PLATE", "手上没有菜。")
	if not _player_at_seat(_held_ticket):
		return TDOutcome.new(false, "TOO_FAR", "走到这盘菜对应的座位旁边再放下。")
	var result := _handoff(_held_ticket, false)
	if result.ok:
		_held_ticket = ""
	return result

func set_floor_cover(covered: bool) -> void:
	_covered = covered
	visible = not covered
	set_process_unhandled_input(not covered)
	if _iso != null:
		_iso.set_presented(not covered)
	_lock_player()
	if player_mode:
		for child: Node in get_children():
			if child is CanvasLayer: child.visible=not covered

func set_observe(observing: bool) -> void:
	_observing = observing
	if _observe_banner != null:
		_observe_banner.visible = observing
	_lock_player()

func _lock_player() -> void:
	if _player == null:
		return
	_player.set_controls_enabled(not _closed and not _covered and not _observing)

func _place_seated(guest: TDRestaurantGuest) -> void:
	if layout == null or guest.seat_id == "":
		guest.seated = false
		return
	if guest.phase != "wait_serve" and guest.phase != "eat":
		guest.seated = false
		return
	var seat := layout.piece(guest.seat_id)
	if seat.is_empty():
		guest.seated = false
		return
	guest.seated = true
	guest.position = layout.cell_center(layout.sit_cell(seat))

func _tick_runner(delta: float) -> void:
	var active := session if session != null and session.ready else null
	if active == null or not active.staff_on("runner"):
		if _runner_ticket != "" and active != null:
			active.floor.release_plate(_runner_ticket)
		_runner_ticket = ""
		_runner_on = false
		return
	_runner_on = true
	if _runner_pos == Vector2.ZERO:
		_runner_pos = layout.cell_center(pass_cell())
	if _runner_ticket == "":
		var plate := active.floor.pass_plate()
		if plate.is_empty():
			_step_runner(pass_cell(), delta)
			return
		var claimed := active.floor.claim_plate(String(plate["id"]), "runner")
		if not claimed.ok:
			return
		_runner_ticket = String(plate["id"])
	var guest := _guest_by_ticket(_runner_ticket)
	if guest == null or guest.phase != "wait_serve" or not guest.seated:
		active.floor.release_plate(_runner_ticket)
		_runner_ticket = ""
		return
	var goal := approach_cell(guest.seat_id)
	if _cell_at(_runner_pos) == goal:
		_handoff(_runner_ticket, true)
		_runner_ticket = ""
		_runner_goal = Vector2i(-1, -1)
		return
	_step_runner(goal, delta)

func _step_runner(goal: Vector2i, delta: float) -> void:
	if layout == null:
		return
	if _runner_goal != goal:
		var cells := layout.path(_cell_at(_runner_pos), goal)
		if cells.is_empty():
			return
		_runner_goal = goal
		_runner_points = PackedVector2Array()
		for cell: Vector2i in cells:
			_runner_points.append(layout.cell_center(cell))
		_runner_index = 1 if _runner_points.size() > 1 else 0
	if _runner_index >= _runner_points.size():
		_runner_pos = layout.cell_center(goal)
		return
	var target := _runner_points[_runner_index]
	_runner_pos = _runner_pos.move_toward(target, _runner_speed() * delta)
	if _runner_pos.distance_to(target) <= 1.0:
		_runner_pos = target
		_runner_index += 1

func _runner_speed() -> float:
	var shift := 0
	if session != null and session.ready and session.staff_on("runner"):
		var card := session.staff_card("home", "runner")
		shift = int(card["shift"])
	return clampf(130.0 + float(shift) * 5.0, 70.0, 180.0)

func _handoff(ticket_id: String, by_runner: bool) -> TDOutcome:
	var active := _session()
	if active == null:
		return TDOutcome.new(false, "NOT_READY", "客流数据还没准备好")
	var quality := 0.0
	for item: Variant in active.floor.tickets:
		var ticket: Dictionary = item
		if String(ticket["id"]) != ticket_id:
			continue
		quality = float(ticket.get("plate_quality", 0))
		break
	if by_runner:
		var card := active.staff_card("home", "runner")
		quality = float(TDBranchSim.service_quality(roundi(quality), int(card["mood"]), String(card["drive"]), String(card["care"]), int(card["wage"]), int(card["recommended"])))
		active.floor.set_plate_quality(ticket_id, quality)
	var result := active.floor.finish_plate(ticket_id)
	if not result.ok:
		return result
	var guest := _guest_by_ticket(ticket_id)
	if guest == null:
		return TDOutcome.new(false, "NO_GUEST", "客人已经不在座位上。")
	guest.quality = quality
	guest.clear_wait()
	_sync_tickets()
	var who := "传菜员" if by_runner else "你"
	result.message = "%s把%s端到%s的座位上，质量按%.0f计。客人开始吃。" % [who, guest.dish_name, String(guest.profile.get("id", "客人")), quality]
	_set_status(result.message)
	return result

func _player_at_seat(ticket_id: String) -> bool:
	var guest := _guest_by_ticket(ticket_id)
	if guest == null:
		return false
	return cell_of_player() == approach_cell(guest.seat_id)

func _pass_has_plate() -> bool:
	return session != null and session.ready and not session.floor.pass_plate().is_empty()

func _held_caption() -> String:
	if _held_ticket == "" or session == null:
		return ""
	for item: Variant in session.floor.tickets:
		var ticket: Dictionary = item
		if String(ticket["id"]) == _held_ticket:
			return String(ticket["dish_name"])
	return ""

func _runner_caption() -> String:
	if _runner_ticket == "" or session == null:
		return "传菜"
	for item: Variant in session.floor.tickets:
		var ticket: Dictionary = item
		if String(ticket["id"]) == _runner_ticket:
			return String(ticket["dish_name"])
	return "传菜"

func _sync_tickets() -> void:
	var active := session if session != null and session.ready else null
	if active == null:
		return
	for guest: TDRestaurantGuest in guest_nodes():
		if guest.ticket_id == "":
			continue
		active.floor.sync(guest.ticket_id, guest.phase, guest.is_waiting(), guest.accepted, guest.quality, guest.review_score)

func _guest_by_ticket(ticket_id: String) -> TDRestaurantGuest:
	for guest: TDRestaurantGuest in guest_nodes():
		if guest.ticket_id == ticket_id:
			return guest
	return null

func _waiting_guest(phase: String) -> TDRestaurantGuest:
	for guest: TDRestaurantGuest in guest_nodes():
		if guest.service_active and guest.phase == phase and guest.is_waiting():
			return guest
	return null

func _phase_text(guest: TDRestaurantGuest) -> String:
	match guest.phase:
		"welcome":
			return "客人到了迎宾台。"
		"order":
			return "客人在点%s。%s" % [guest.dish_name, "菜单里没有，可以接下或拒绝。" if guest.off_menu else "菜单里有，会自动入座。"]
		"seat":
			return "客人走向座位。"
		"wait_serve":
			return "%s已经坐在座位上，等%s。菜要从传菜口端到这桌旁边。" % [String(guest.profile.get("id", "客人")), guest.dish_name]
		"eat":
			return "客人正在吃%s。" % guest.dish_name
		"pay":
			if guest.review_score >= 0.0:
				return "客人埋单，总体评价%.1f。" % guest.review_score
			return "客人去收银台。没雇收银员的话会等着。"
		"leave":
			if guest.review_score >= 0.0:
				return "客人埋单后离开，总体评价%.1f。" % guest.review_score
			return "客人离开。"
		"gone":
			return "这桌结束。"
		_:
			return guest.phase

func _open_board() -> void:
	var active := _session()
	if active == null:
		return
	active.set_player_pieces(layout.pieces())
	_close_pantry()
	if _board != null and is_instance_valid(_board):
		_board.queue_free()
	_board = TDEconomyBoard.new()
	_board.session = active
	_board.closed.connect(func() -> void:
		if _board != null:
			_board.queue_free()
	)
	_board.day_closed.connect(_push_session_staff)
	add_child(_board)

func _open_pantry() -> void:
	var active := _session()
	if active == null:
		return
	if _board != null and is_instance_valid(_board):
		_board.queue_free()
	_close_pantry()
	_pantry = TDPantryBoard.new()
	_pantry.session = active
	_pantry.closed.connect(_close_pantry)
	add_child(_pantry)

func _close_pantry() -> void:
	if _pantry != null and is_instance_valid(_pantry):
		_pantry.queue_free()
	_pantry = null

func _crew_points(delta: float) -> Array:
	var people: Array = []
	if layout == null or layout.crew == null:
		return people
	var posts: Array[Vector2] = []
	var jobs: Array[Vector2] = []
	var servers := layout.crew.waiters()
	for index: int in servers.size():
		posts.append(_waiter_post(index))
	for guest: TDRestaurantGuest in guest_nodes():
		if guest.phase != "wait_serve" or guest.seat_id == "":
			continue
		var cell := approach_cell(guest.seat_id)
		if layout.is_walkable(cell.x, cell.y):
			jobs.append(layout.cell_center(cell))
	while _waiter_feet.size() < servers.size():
		_waiter_feet.append(posts[_waiter_feet.size()])
	while _waiter_feet.size() > servers.size():
		_waiter_feet.pop_back()
	for index: int in servers.size():
		var server: Dictionary = servers[index]
		var target: Vector2 = posts[index]
		if index < jobs.size():
			target = jobs[index]
		var current := _waiter_feet[index].move_toward(target, 90.0 * maxf(delta, 0.0))
		_waiter_feet[index] = current
		people.append({
			"point": current,
			"label": "服务员 %s %d级" % [String(server["name"]), int(server.get("level", 1))],
			"color": Color("#2f7a68"),
			"moving": current.distance_to(target) > 0.5,
		})
	return people

func _waiter_post(index: int) -> Vector2:
	return _staff_spot(Vector2i(layout.columns - 2, layout.rows - 3), index)

func _staff_spot(origin: Vector2i, slot: int) -> Vector2:
	var offsets: Array[Vector2i] = [
		Vector2i.ZERO, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN,
		Vector2i(-2, 0), Vector2i(2, 0), Vector2i(0, 2), Vector2i(0, -2),
	]
	for step: int in offsets.size():
		var cell := origin + offsets[(slot + step) % offsets.size()]
		if layout.is_walkable(cell.x, cell.y):
			return layout.cell_center(cell)
	return layout.cell_center(Vector2i(clampi(origin.x, 1, layout.columns - 2), clampi(origin.y, 1, layout.rows - 2)))

func interaction_points() -> Array[Dictionary]:
	if layout==null: return []
	return [
		{"action":"town","name":"店门 · 小镇","cell":Vector2(layout.entrance())},
		{"action":"menu","name":"营业牌","cell":Vector2(1,3)},
		{"action":"ledger","name":"账本","cell":Vector2(5,2)},
		{"action":"recipes","name":"菜谱架","cell":Vector2(3,2)},
		{"action":"decorate","name":"装修桌","cell":Vector2(1,layout.rows-3)},
		{"action":"rest","name":"休息处","cell":Vector2(layout.columns-2,layout.rows-4)},
		{"action":"hire","name":"招工处","cell":Vector2(layout.columns-3,layout.rows-4)},
		{"action":"kitchen","name":"后厨","cell":Vector2(layout.columns-2,layout.rows-2)}]

func _sync_business_guests() -> void:
	if business==null or layout==null: return
	var orders: Array=business.snapshot().orders
	for order: Dictionary in orders:
		if order.status not in ["WAITING","COOKING"]: continue
		if _business_guests.has(order.id): continue
		var occupied: Array=[]
		for current: TDRestaurantGuest in guest_nodes(): occupied.append(current.seat_id)
		var seat: Dictionary={};var route: Array=[]
		for piece: Dictionary in layout.pieces():
			if piece.seat_use!="dining" or piece.id in occupied: continue
			var path:=layout.path(layout.entrance(),Vector2i(piece.approach_x,piece.approach_y))
			if not path.is_empty(): seat=piece;route=path;break
		var guest:=TDRestaurantGuest.new()
		guest.ticket_id=order.id;guest.dish_name=business.recipe_name(order.recipe_id);guest.phase="approach"
		guest.seat_id=str(seat.get("id",""));guest.process_mode=Node.PROCESS_MODE_PAUSABLE
		_guests.add_child(guest)
		guest.set_path(route if not route.is_empty() else [layout.entrance(),Vector2i(1,1)],layout.cell_px)
		_business_guests[order.id]=guest
	for id: String in _business_guests.keys():
		var guest: TDRestaurantGuest=_business_guests[id]
		if not is_instance_valid(guest): _business_guests.erase(id);continue
		if guest.phase=="approach" and guest.finished: guest.phase="wait_serve"
		var status: String="CANCELLED"
		for order: Dictionary in orders:
			if order.id==id: status=order.status;break
		if status in ["WAITING","COOKING"]: continue
		if guest.phase!="leave":
			guest.phase="leave";guest.seated=false
			var cell:=_cell_at(guest.position)
			var seat:=layout.piece(guest.seat_id)
			if not layout.is_walkable(cell.x,cell.y) and not seat.is_empty(): cell=Vector2i(seat.approach_x,seat.approach_y)
			guest.set_path(layout.path(cell,layout.entrance()),layout.cell_px)
		elif guest.finished:
			_guests.remove_child(guest);guest.queue_free();_business_guests.erase(id)

var last_visit: Dictionary = {}
