class_name TDRestaurantWorld
extends Node2D

signal fixture_used(piece_id: String, code: String)
signal back_requested
signal pause_requested
signal kitchen_requested
signal object_requested(action: String)
signal layout_changed
signal status_reported(text: String)
var player_mode: bool = false
var business: TDShopSession
var _business_guests: Dictionary = {}
var unified_dining_clock: bool=false

const CHEF := preload("res://assets/redraw-v1/chef.png")
const INTERACTION_RADIUS := 78.0
const BRUSHES: Array[String] = ["wood", "tile", "stone", "carpet", "paper", "stripe", "floral", "brick", "#", ".", "+"]

var save_path: String = ""
var guest_speed: float = 180.0
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
var _place_rotation: int = 0
var _brush: String = "wood"
var _hover_cell := Vector2i(-1, -1)
var _hover_label: Label
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
var _status_left: float=0.0
var _decoration_backdrop: ColorRect
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
class Waiter:
	var feet: Vector2
	var plate := ""
	var pickup_ticket := ""
	var route := PackedVector2Array()
	var waypoint := 0
	var goal := Vector2i(-1, -1)
	var destination := Vector2.INF

var _waiters: Dictionary = {}
var _wall_posts: Array[Vector2i] = []
var _iso: TDRestaurantIsoView
var _board: TDEconomyBoard
var _pantry: TDPantryBoard
var _order_board: Label
var _order_plate: Panel
var _order_scroll: ScrollContainer
var _info_top: float = 120.0
var characters: TDCharacterRoster
var story_frozen: bool = false
var _visit_seconds: float = 0.0
var _finished_visits: Dictionary = {}
var _visit_day: int = 0
var floor_service: bool = false
var _talk_layer: CanvasLayer
var _talk_view: TDDialogueView
var _plate_order: String = ""
var decoration_progression: TDLevelProgression
var _decor_panel: TDDecorationPanel
var _context_menu: Control
var _delete_button: Button
var _rotate_button: Button
var _drag_candidate: bool=false
var _dragging: bool=false
var _drag_start := Vector2.ZERO
var _drag_offset := Vector2.ZERO
var _drag_cell := Vector2i(-1,-1)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_theme = TDUI.theme()
	var backdrop_layer := CanvasLayer.new()
	backdrop_layer.name = "DecorationBackdrop"
	backdrop_layer.layer = -1
	add_child(backdrop_layer)
	_decoration_backdrop = ColorRect.new()
	_decoration_backdrop.color = Color.BLACK
	_decoration_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_decoration_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_decoration_backdrop.hide()
	backdrop_layer.add_child(_decoration_backdrop)
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
	_hover_label = Label.new()
	_hover_label.visible = false
	_hover_label.position = Vector2(16, 168)
	_hover_label.size = Vector2(440, 110)
	_hover_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hover_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_label.theme = _theme
	_hover_label.z_index = 30
	_hover_label.add_theme_font_size_override("font_size", TDUI.FONT_CAPTION)
	_hover_label.add_theme_color_override("font_color", Color("#fff6df"))
	_hover_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.88))
	_hover_label.add_theme_constant_override("shadow_offset_x", 1)
	_hover_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_hover_label)
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
	if not player_mode or session != null: _pull_layout_staff()
	if player_mode:
		_set_status("")
		_iso.interaction_markers=interaction_points()

func _process(delta: float) -> void:
	if player_mode:
		if not get_tree().paused and is_visible_in_tree(): _status_left=maxf(0.0,_status_left-delta)
		if _bar!=null: _bar.visible=not player_mode and not _editing and _status_left>0 and not _status.text.is_empty()
	if _player != null:
		_player.z_index = int(_player.position.y)
	for guest: TDRestaurantGuest in guest_nodes(): guest.frozen=story_frozen or (_talk_open() and str(_talk_view.talk.context.get("ticket_id",""))==guest.ticket_id)
	if player_mode and not get_tree().paused and not story_frozen:
		if not unified_dining_clock: _visit_seconds+=delta
		if not unified_dining_clock: _sync_business_guests()
		if business != null:
			var crew_note := business.take_crew_note()
			if not crew_note.is_empty():
				_set_status(crew_note)
	elif not get_tree().paused and not story_frozen and not player_mode:
		_tick_service(delta)
	for guest: TDRestaurantGuest in guest_nodes():
		_place_seated(guest)
		guest.z_index = int(guest.position.y)
		if not player_mode and not guest.service_active and guest.finished and guest.seat_id != "" and not guest.has_meta("announced"):
			guest.set_meta("announced", true)
			var seat := layout.piece(guest.seat_id)
			_set_status("客人走到了%s" % String(seat.get("name", "座位")))
		elif guest.service_active and not player_mode:
			_watch_service(guest)
	if player_mode:
		_runner_on = false
	elif not get_tree().paused and not story_frozen:
		_tick_runner(delta)
	if _iso != null:
		_iso.editing = _editing
		_iso.selected_id = _selected
		_iso.runner_visible = _runner_on
		_iso.runner_point = _runner_pos
		_iso.runner_label = _runner_caption()
		_iso.pass_point = Vector2(-1, -1)
		_iso.hatch_plates = _hatch_plate_count()
		_iso.held_label = _held_caption()
		_iso.pass_items = business.table_service.pass_items() if _physical_service() else []
		_iso.player_plate = business.table_service.held_item(_plate_order) if _physical_service() else {}
		_iso.crew_people = _crew_points(0.0 if get_tree().paused or story_frozen or unified_dining_clock else delta)
		_iso.sync(_player, guest_nodes(),get_tree().paused or story_frozen)
		if player_mode: _iso.nearby_action=str(nearby_object().get("action",""))
	if _editing:
		if get_tree().paused or story_frozen or _covered:
			_reset_drag()
			_context_menu.hide()
		_position_context()
		queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if _closed or layout == null:
		return
	if _talk_open():
		if event.is_action_pressed("pause") and not event.is_echo():
			_talk_view.finish_now()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause") and not event.is_echo():
		pause_requested.emit()
		get_viewport().set_input_as_handled()
		return
	if get_tree().paused:
		return
	if _physical_service() and not _covered and not _editing and not story_frozen and event.is_action_pressed("world_retrieve") and not event.is_echo() and _at_service_window():
		var plate_id: String=_plate_order if _plate_order!="" else _unplated_order()
		var result:=business.table_service.discard(plate_id,"player" if _plate_order!="" else "")
		if result.ok: _plate_order=""
		_set_status(result.message);get_viewport().set_input_as_handled();return
	if event.is_action_pressed("world_interact") and not event.is_echo():
		if request_interaction():
			get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
	if _talk_open():
		return
	if _closed or _covered or not _editing or layout == null or _iso == null or get_tree().paused:
		return
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _drag_candidate:
			if motion.position.distance_to(_drag_start)>=6.0: _dragging=true
			if _dragging: _preview_drag(motion.position)
			return
		if _pointer_on_chrome(motion.position):
			_clear_hover()
			return
		_hover_at(_iso.pick_cell(_screen_to_room(motion.position)))
		return
	if not event is InputEventMouseButton:
		return
	var click := event as InputEventMouseButton
	if not click.pressed and click.button_index==MOUSE_BUTTON_LEFT and _drag_candidate:
		_finish_drag(click.position)
		get_viewport().set_input_as_handled()
		return
	if click.pressed and click.button_index==MOUSE_BUTTON_RIGHT and _drag_candidate:
		_cancel_decoration()
		get_viewport().set_input_as_handled()
		return
	if _pointer_on_chrome(click.position):
		return
	if click.pressed and click.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		if not _drag_candidate: _spin(1 if click.button_index == MOUSE_BUTTON_WHEEL_UP else -1)
		get_viewport().set_input_as_handled()
		return
	if not click.pressed or click.button_index not in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		return
	var room_point:=_screen_to_room(click.position)
	var model_hit:=_iso.pick_piece(room_point) if _tool=="select" else ""
	if click.button_index==MOUSE_BUTTON_LEFT and model_hit!="":
		_select_furniture(model_hit)
		var item:=layout.piece(model_hit)
		_drag_candidate=true
		_drag_start=click.position
		_drag_offset=room_point-TDRestaurantIsoView.project(float(item.x)+.5,float(item.y)+.5)
	else:
		_click_cell(_iso.pick_cell(room_point), click.button_index)
	get_viewport().set_input_as_handled()

func _screen_to_room(screen: Vector2) -> Vector2:
	return _iso.get_global_transform_with_canvas().affine_inverse()*screen

func _pointer_on_chrome(screen: Vector2) -> bool:
	if _board != null and is_instance_valid(_board):
		return true
	for control: Control in [_decor_panel,_delete_button,_rotate_button,_bar]:
		if control!=null and control.is_visible_in_tree() and control.get_global_rect().has_point(screen): return true
	return false

func _preview_drag(screen: Vector2) -> void:
	_context_menu.hide()
	if _pointer_on_chrome(screen):
		_clear_hover();_iso.dragged_id=""
		return
	_drag_cell=_iso.pick_cell(_screen_to_room(screen)-_drag_offset)
	var preview:=layout.preview_move(_selected,_drag_cell.x,_drag_cell.y)
	var item: Dictionary=preview.piece
	if item.is_empty(): _reset_drag();return
	_show_ghost(_drag_cell,int(item.w),int(item.h),bool(preview.ok))
	_iso.ghost_piece=item
	_iso.dragged_id=_selected
	_set_status("松开放下 · 右键取消" if preview.ok else str(preview.message)+" · 松开保留原位")

func _finish_drag(screen: Vector2) -> void:
	var moving:=_dragging
	var valid_area:=not _pointer_on_chrome(screen)
	var target:=_iso.pick_cell(_screen_to_room(screen)-_drag_offset)
	_reset_drag()
	if moving and valid_area:
		var result:=_apply(layout.move_piece(_selected,target.x,target.y))
		_set_status("已移动，按住家具可继续拖动。" if result.ok else result.message+"，家具保留原位。")
	_context_menu.visible=not layout.piece(_selected).is_empty()
	_position_context()

func _reset_drag() -> void:
	_drag_candidate=false;_dragging=false
	_drag_cell=Vector2i(-1,-1)
	if _iso!=null: _iso.dragged_id=""
	_clear_hover()

func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT and _iso!=null:
		_reset_drag()
		if _context_menu!=null: _context_menu.hide()

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
	if business!=null and business.dining_tick==advance_dining:
		business.dining_tick=Callable();business.dining_boundary=Callable()
	_reset_drag()
	_dismiss_talk()
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

func _npc_clear_step(proposed: Vector2) -> bool:
	if _editing: return true
	for guest: TDRestaurantGuest in guest_nodes():
		if guest.visible and not TDInteractionRange.npc_clear(_player.position,proposed,guest.position,24.0): return false
	for waiter: Waiter in _waiters.values():
		if not TDInteractionRange.npc_clear(_player.position,proposed,waiter.feet,24.0): return false
	return true

func _standing_inside_solid(cell: Vector2i) -> bool:
	if layout == null:
		return false
	if cell.x < 0 or cell.y < 0 or cell.x >= layout.columns or cell.y >= layout.rows:
		return true
	if layout.furniture_blocks(cell.x, cell.y):
		return true
	# Open facade floor is the doorway and the ground in front of the drawn walls.
	var outer: bool=cell.x==0 or cell.y==0 or cell.x==layout.columns-1 or cell.y==layout.rows-1
	return not layout.is_walkable(cell.x, cell.y) and not (outer and layout.cell_zone(cell.x, cell.y)=="facade")

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

var authored_interaction: Callable

func request_interaction() -> bool:
	if _closed or _player == null or layout == null or get_tree().paused or _covered or _editing:
		return false
	if _talk_open():
		return true
	if player_mode:
		# Actual floor duties retain their explicit E action; casual dialogue never steals a fixture.
		if floor_service and _floor_act():
			return true
		var object:=nearby_object()
		if not object.is_empty():
			if _physical_service() and _plate_order!="" and object.action in ["town","kitchen"]:
				_set_status("请先把手上的菜送到客人桌边，或在出餐口按 E 放回。");return true
			object_requested.emit(str(object.action));return true
		var faced := _faced_guest()
		if faced != null and not _editing:
			var conversation: TDDialogue
			if characters!=null and faced.character_id!="":
				if authored_interaction.is_valid() and authored_interaction.call(faced.character_id): return true
				conversation=characters.conversation(faced.character_id)
				conversation.context.ticket_id=faced.ticket_id
			else:
				conversation=TDGuestVisit.conversation(_guest_name(faced),str(faced.get_meta("recipe_label",faced.dish_name)),faced.phase,"guest%d"%faced.appearance_id,business.order(faced.ticket_id))
			_open_talk(conversation)
			return true
		if faced != null:
			_set_status(_guest_brief(faced))
			return true
		return false
	if _held_ticket != "" and _player_at_seat(_held_ticket):
		_set_status(deliver_held_plate().message)
		return true
	if _held_ticket == "" and cell_of_player() == pass_cell() and _pass_has_plate():
		_set_status(pickup_pass_plate().message)
		return true
	if _held_ticket != "" and cell_of_player() == pass_cell():
		_session().floor.release_plate(_held_ticket)
		_held_ticket = ""
		_set_status("把菜放回出餐口。")
		return true
	if cell_of_player() == layout.entrance():
		kitchen_requested.emit()
		_set_status("后厨")
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
	return _apply(layout.place(kind, x, y, _place_rotation,_culture+"_"+_tier))

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
		if _context_menu!=null: _context_menu.hide()
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
	_player.walk_speed=180.0
	_player.vertical_stride_multiplier=1.6
	_player.npc_step_clear=_npc_clear_step
	_player.motion_transform=Transform2D(Vector2(TDRestaurantIsoView.HALF_W,TDRestaurantIsoView.HALF_H)/layout.cell_px,Vector2(-TDRestaurantIsoView.HALF_W,TDRestaurantIsoView.HALF_H)/layout.cell_px,Vector2.ZERO).affine_inverse()
	_player.input_transform=Transform2D.IDENTITY
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
	add_child(_player)
	_iso = TDRestaurantIsoView.new()
	_iso.follow_player=player_mode
	_iso.name = "IsoView"
	add_child(_iso)

func _build_status_bar() -> void:
	var layer := CanvasLayer.new()
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	var panel := Panel.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel",TDUI.wood(TDUI.Surface.CARD,0))
	_bar = panel
	panel.visible = not player_mode
	layer.add_child(panel)
	get_viewport().size_changed.connect(_fit_bar)
	_observe_banner = Label.new()
	_observe_banner.text = "V 返回后厨"
	_observe_banner.position = Vector2(24, 12)
	_observe_banner.size = Vector2(900, 32)
	_observe_banner.visible = false
	_observe_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_observe_banner.add_theme_font_size_override("font_size", TDUI.FONT_BODY)
	_observe_banner.add_theme_color_override("font_color", Color("f0cc70"))
	layer.add_child(_observe_banner)
	_order_plate = Panel.new()
	_order_plate.name="DiningInfo"
	_order_plate.position = Vector2(14, _info_top)
	_order_plate.size = Vector2(420, 188)
	_order_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_order_plate.visible = false
	var plate_style:=TDUI.wood(TDUI.Surface.CARD,0)
	_order_plate.add_theme_stylebox_override("panel", plate_style)
	layer.add_child(_order_plate)
	_order_scroll=ScrollContainer.new()
	_order_scroll.name="DetailsScroll"
	_order_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	_order_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO
	_order_scroll.position=Vector2(12,12);_order_scroll.size=Vector2(396,164)
	_order_plate.add_child(_order_scroll)
	_order_board = Label.new()
	_order_board.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_order_board.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_order_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_order_board.visible = false
	_order_board.add_theme_font_size_override("font_size", TDUI.FONT_CAPTION)
	_order_board.add_theme_color_override("font_color", TDUI.INK)
	_order_board.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
	_order_board.add_theme_constant_override("line_spacing",4)
	_order_scroll.add_child(_order_board)
	_order_board.minimum_size_changed.connect(_fit_order_board)
	var box := VBoxContainer.new()
	_bar_box = box
	box.position = Vector2(10, 8)
	box.size = Vector2(1260, 152)
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	_status = Label.new()
	_status.custom_minimum_size = Vector2(1240, 32)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", TDUI.FONT_CAPTION)
	_status.add_theme_color_override("font_color",TDUI.INK)
	box.add_child(_status)
	var play := HFlowContainer.new()
	_play_row = play
	play.add_theme_constant_override("h_separation", 6)
	play.add_theme_constant_override("v_separation", 4)
	box.add_child(play)
	var back := _button("返回", _back)
	play.add_child(back)
	if player_mode:
		back.visible = false
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
	if player_mode:
		for button: Button in _service_buttons:
			button.visible = false
	play.add_child(_button("保存", save_current))
	_edit_box = HFlowContainer.new()
	_edit_box.hide()
	box.add_child(_edit_box)
	_build_decoration_ui(layer)
	if player_mode: _play_row.hide()
	_fit_bar()

func _build_decoration_ui(layer: CanvasLayer) -> void:
	_decor_panel=TDDecorationPanel.new();_decor_panel.name="DecorationCatalog"
	_decor_panel.catalog=catalog;_decor_panel.culture=_culture;_decor_panel.tier=_tier
	_decor_panel.progression=decoration_progression
	layer.add_child(_decor_panel);_decor_panel.hide()
	_decor_panel.minimum_size_changed.connect(_fit_bar,CONNECT_DEFERRED)
	_decor_panel.item_chosen.connect(_choose_decoration)
	_decor_panel.category_changed.connect(_cancel_decoration)
	_decor_panel.done.connect(_toggle_edit)
	_context_menu=Control.new();_context_menu.name="FurnitureActions"
	_context_menu.process_mode=Node.PROCESS_MODE_PAUSABLE
	_context_menu.mouse_filter=Control.MOUSE_FILTER_IGNORE
	layer.add_child(_context_menu);_context_menu.hide()
	var frame:=Panel.new();frame.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var border:=StyleBoxFlat.new();border.bg_color=Color.TRANSPARENT
	border.border_color=Color("e9c780");border.set_border_width_all(1)
	frame.add_theme_stylebox_override("panel",border);_context_menu.add_child(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_delete_button=_furniture_icon("×","删除家具",remove_selected,Color("914b47"))
	_rotate_button=_furniture_icon("↶","逆时针旋转90°",_rotate_selected,Color("355d56"))
	_delete_button.name="DeleteFurniture";_rotate_button.name="RotateFurniture"

func _furniture_icon(symbol: String, hint: String, action: Callable, color: Color) -> Button:
	var button:=Button.new();button.text=symbol;button.tooltip_text=hint
	button.theme=_theme;button.focus_mode=Control.FOCUS_NONE
	button.custom_minimum_size=Vector2(32,32);button.size=Vector2(32,32)
	button.add_theme_font_size_override("font_size",TDUI.FONT_SECTION)
	for state: String in ["normal","hover","pressed","focus"]:
		var style:=StyleBoxFlat.new();style.bg_color=color.lightened(.14) if state=="hover" else color
		style.border_color=Color("ecd5a2");style.set_border_width_all(1);style.set_corner_radius_all(5)
		button.add_theme_stylebox_override(state,style)
	button.pressed.connect(action);_context_menu.add_child(button)
	return button

func _cancel_decoration() -> void:
	_reset_drag()
	_tool="select"
	_culture=layout.culture;_tier=layout.tier
	_selected=""
	if _decor_panel!=null: _decor_panel.clear_selection()
	_clear_hover()
	if _context_menu!=null: _context_menu.hide()
	_set_status("选择家具或饰面，点击已摆好的家具可转向或删除。")

func _choose_decoration(id: String, finish: bool) -> void:
	var choice: Dictionary={} if finish else _decor_panel.furniture_choice(id)
	var reward_id := id if finish else str(choice.get("kind",id))
	if decoration_progression!=null and not decoration_progression.decoration_unlocked(reward_id): return
	if not finish and choice.is_empty(): return
	_reset_drag()
	_selected="";_context_menu.hide()
	_clear_hover()
	if finish:
		_tool="select"
		_apply(layout.set_surface_finish(id))
		return
	_armed_kind=choice.kind;_tool="place";_place_rotation=0
	_culture=str(choice.style_id).get_slice("_",0);_tier=str(choice.style_id).get_slice("_",1)
	_set_status("%s：移动鼠标查看预览，左键放置，右键取消。"%str(catalog.furniture(_armed_kind).name))

func _select_furniture(id: String) -> void:
	_selected=id;_tool="select";_clear_hover()
	_decor_panel.clear_selection()
	var piece:=layout.piece(id)
	_context_menu.visible=_editing and not piece.is_empty()
	if not piece.is_empty(): _set_status("%s · 按住拖动 · 左上删除 / 右上逆时针旋转 · 右键取消"%piece.name)
	_position_context();queue_redraw()

func _position_context() -> void:
	if _context_menu==null or not _context_menu.visible or _iso==null: return
	var piece:=layout.piece(_selected)
	if piece.is_empty(): _context_menu.hide();return
	var transform:=_iso.get_global_transform_with_canvas()
	var bounds:=TDFurnitureModel.bounds(piece)
	var point:=transform*(TDFurnitureModel.center(piece)+bounds.position)-Vector2(8,8)
	var extent:=transform.basis_xform(bounds.size)+Vector2(16,16)
	if extent.x<80: point.x-=(80-extent.x)*.5;extent.x=80
	var view:=get_viewport().get_visible_rect().size
	_context_menu.size=extent
	_context_menu.position=Vector2(clampf(point.x,18,maxf(18,view.x-extent.x-18)),clampf(point.y,18,maxf(18,view.y-_decor_panel.size.y-extent.y-18)))
	_delete_button.position=Vector2(-16,-16)
	_rotate_button.position=Vector2(extent.x-16,-16)

func _rebuild() -> void:
	if layout == null or _floor == null:
		return
	_wall_posts.clear()
	for waiter: Waiter in _waiters.values():
		waiter.goal = Vector2i(-1,-1)
		var cell := _cell_at(waiter.feet)
		if not layout.feet_inside(waiter.feet) and not (cell.x == 0 and layout.is_walkable(1,cell.y)):
			waiter.feet = layout.cell_center(_nearest_walkable(cell,service_window_cell()))
	_floor.texture = TDRestaurantArt.floor_texture(layout)
	_floor.visible = false
	if _iso != null:
		_iso.set_room(layout)
		if player_mode: _iso.interaction_markers=interaction_points()
	if session != null and session.ready:
		session.set_player_pieces(layout.pieces())
	_free_children(_blockers)
	_free_children(_fixtures)
	for y in layout.rows:
		for x in layout.columns:
			# Facade cells are drawn as floor. A full-cell body there is an invisible wall
			# in front of the old door and along the north wall. Furniture still fills its cells.
			if not _standing_inside_solid(Vector2i(x,y)):
				continue
			var shape := RectangleShape2D.new()
			shape.size = Vector2(layout.cell_px, layout.cell_px)
			var collider := CollisionShape2D.new()
			collider.shape = shape
			collider.position = layout.cell_center(Vector2i(x, y))
			_blockers.add_child(collider)
	# The drawn north and west walls sit on the room edge. This boundary matches that edge,
	# including the shop door, so the player can reach the door and cannot leave. E changes scenes.
	var width:float=layout.columns*layout.cell_px
	var height:float=layout.rows*layout.cell_px
	for edge:Rect2 in [Rect2(-32,-32,width+64,32),Rect2(-32,height,width+64,32),Rect2(-32,0,32,height),Rect2(width,0,32,height)]:
		var wall:=CollisionShape2D.new();var rectangle:=RectangleShape2D.new()
		rectangle.size=edge.size;wall.shape=rectangle;wall.position=edge.get_center();_blockers.add_child(wall)
	for item: Variant in layout.pieces():
		_add_fixture(item)
	if _player != null and _standing_inside_solid(cell_of_player()):
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
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sprite.texture = TDRestaurantArt.piece_texture(String(item["kind"]), String(item["surface"]), culture, tier, int(item["w"]) * layout.cell_px, int(item["h"]) * layout.cell_px)
	sprite.visible = false
	node.add_child(sprite)
	var label := Label.new()
	label.text = String(item["name"])
	label.position = Vector2(4, 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.theme = _theme
	label.add_theme_font_size_override("font_size", TDUI.FONT_CAPTION)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.visible = false
	node.add_child(label)
	_fixtures.add_child(node)

func _click_cell(cell: Vector2i, button: int = MOUSE_BUTTON_LEFT) -> void:
	if button == MOUSE_BUTTON_RIGHT:
		_cancel_decoration()
		return
	if cell.x < 0 or cell.y < 0 or cell.x >= layout.columns or cell.y >= layout.rows:
		_set_status("点在房间外面了。")
		return
	var hit := _piece_at(cell)
	if _tool == "paint":
		if _brush in ["#", ".", "+"]:
			paint_cell(cell.x, cell.y, _brush)
		else:
			_apply(layout.set_finish(cell.x, cell.y, _brush))
		_refresh_hover()
		return
	if _tool == "place":
		var placed:=place_kind(_armed_kind, cell.x, cell.y)
		if placed.ok:
			_tool="select";_decor_panel.clear_selection();_clear_hover()
			_set_status("已放好。点击家具可转向、移动或删除；选择卡片可继续添置。")
		else: _refresh_hover()
		return
	_select_furniture(hit)

func _apply(result: TDOutcome) -> TDOutcome:
	if result.ok:
		_dirty = true
		if result.data.has("id"):
			_selected = String(result.data["id"])
		_clear_guests()
		_rebuild()
		layout_changed.emit()
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
		"waiting_seat":
			return "等候座。客人入座时优先去用餐区。"
		"screen":
			return "屏风，用来隔开等候区。"
		_:
			if String(piece["seat_use"]) == "dining":
				return "%s可以入座。" % String(piece["name"])
			return String(piece["name"])

func _toggle_edit() -> void:
	_reset_drag()
	_culture=layout.culture;_tier=layout.tier
	_editing = not _editing
	_iso.editing=_editing
	_decoration_backdrop.visible = _editing
	_order_plate.visible = not _editing and player_mode and not _covered and business != null and str(business.snapshot().phase) in ["OPEN", "DRAINING"]
	_edit_box.hide()
	_bar.visible=not player_mode and not _editing
	_decor_panel.visible=_editing
	if _editing: _decor_panel.refresh_cards()
	_selected="";_context_menu.hide()
	for button: Button in _service_buttons:
		button.visible = not _editing and not player_mode
	_edit_button.text = "完成布置" if _editing else "布置"
	_tool = "select"
	_fit_bar()
	if not _editing:
		_clear_hover()
		if not _iso.follow_player:
			_iso._camera.zoom=Vector2.ONE
			_iso.set_room(layout)
	queue_redraw()
	_lock_player()
	_set_status("拖动家具调整位置" if _editing else "")

func _cycle_kind() -> void:
	var kinds := catalog.kinds()
	var index := kinds.find(_armed_kind)
	_armed_kind = kinds[(index + 1) % kinds.size()]
	_tool = "place"
	_refresh_buttons()
	_set_status("滚轮转向，左键在任意地板放下%s。右键取消。它会把自己的格子划成%s。" % [String(catalog.furniture(_armed_kind)["name"]), _zone_title(String(catalog.furniture(_armed_kind).get("zone", "")))])
	_refresh_hover()

func _cycle_brush() -> void:
	var index := BRUSHES.find(_brush)
	_brush = BRUSHES[(index + 1) % BRUSHES.size()]
	_tool = "paint"
	_refresh_buttons()
	_set_status("左键刷上%s。墙纸只上墙，地板只上地面。这不划功能区。" % _brush_name(_brush))
	_refresh_hover()

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
	if _tool == "place":
		_spin(1)
		return
	if _selected == "":
		_set_status("先点选一件家具，或先进入放置再用滚轮转向。")
		return
	_apply(layout.rotate_piece_by(_selected,-90))
	_refresh_hover()

func _spin(steps: int) -> void:
	if _tool == "place":
		_place_rotation = posmod(_place_rotation + steps * 90, 360)
		_refresh_buttons()
		_refresh_hover()
		_set_status("朝向 %d°。右键取消放置。" % _place_rotation)
		return
	if _tool == "paint":
		return
	if _selected == "":
		_set_status("先选中一件家具，滚轮才能转它。")
		return
	_apply(layout.rotate_piece_by(_selected, steps * 90))
	_refresh_hover()

func _set_tool(next: String) -> void:
	_tool = next
	_refresh_buttons()
	_refresh_hover()
	_set_status("点击家具打开转向/删除菜单，右键关闭。" if next == "select" else "滚轮转向，右键取消。")

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
		_kind_button.text = "放置：%s · %d°" % [String(catalog.furniture(_armed_kind).get("name", _armed_kind)), _place_rotation]
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
		"#":
			return "砌墙"
		_:
			return TDRestaurantLayout.finish_name(symbol)

func _zone_title(zone: String) -> String:
	match zone:
		"reception":
			return "接待"
		"ordering":
			return "点餐"
		"dining":
			return "用餐"
		"facade":
			return "门面"
		_:
			return "过道"

func _hover_at(cell: Vector2i) -> void:
	_hover_cell = cell
	if layout == null or cell.x < 0 or cell.y < 0 or cell.x >= layout.columns or cell.y >= layout.rows:
		_clear_hover()
		return
	if _hover_label != null:
		_hover_label.visible = false
	if _tool == "place":
		var preview := layout.preview_piece(_armed_kind, cell.x, cell.y, _place_rotation,_culture+"_"+_tier)
		_show_ghost(cell, int(preview["w"]), int(preview["h"]), bool(preview["ok"]))
		_iso.ghost_piece=preview.piece.duplicate(true)
		if _decor_panel!=null: _decor_panel.show_info(_place_hover_text(preview))
		if _hover_label != null:
			_hover_label.text = _place_hover_text(preview)
		return
	if _tool == "paint":
		_show_ghost(cell, 1, 1, _finish_fits(cell))
		if _decor_panel!=null: _decor_panel.show_info(_paint_hover_text(cell))
		if _hover_label != null:
			_hover_label.text = _paint_hover_text(cell)
		return
	_show_ghost(Vector2i(-1, -1), 0, 0, false)
	if _decor_panel!=null: _decor_panel.show_info(_cell_hover_text(cell))
	if _hover_label != null:
		_hover_label.text = _cell_hover_text(cell)

func _refresh_hover() -> void:
	if not _editing:
		_clear_hover()
		return
	if _hover_cell.x < 0:
		return
	_hover_at(_hover_cell)

func _clear_hover() -> void:
	_hover_cell = Vector2i(-1, -1)
	if _hover_label != null:
		_hover_label.visible = false
		_hover_label.text = ""
	_show_ghost(Vector2i(-1, -1), 0, 0, false)

func _show_ghost(cell: Vector2i, width: int, height: int, ok: bool) -> void:
	if _iso == null:
		return
	_iso.ghost_cell = cell
	_iso.ghost_size = Vector2i(width, height)
	_iso.ghost_ok = ok
	_iso.ghost_piece={}
	_iso.queue_redraw()

func _finish_fits(cell: Vector2i) -> bool:
	var wall := layout.cell_zone(cell.x, cell.y) == "facade"
	if _brush in ["#", ".", "+"]:
		return true
	if wall:
		return TDRestaurantLayout.WALL_FINISHES.has(_brush)
	return TDRestaurantLayout.FLOOR_FINISHES.has(_brush)

func _place_hover_text(preview: Dictionary) -> String:
	var title := "%s  %d×%d  ·  %d°" % [String(preview["name"]), int(preview["w"]), int(preview["h"]), _place_rotation]
	var zone := _zone_title(String(preview["zone"]))
	if not bool(preview["ok"]):
		return "%s\n%s" % [title, String(preview["message"])]
	var before := float(_decor_now()["effect"])
	var pieces := layout.pieces()
	pieces.append(preview["piece"])
	var wild: Array = []
	if session != null and session.catalog != null:
		wild = session.catalog.wildcards
	var after := float(TDEconomyMath.decor_of(pieces, wild)["effect"])
	return "%s\n可以放下。所占地板划成%s。\n装修效果 %.0f → %.0f（墙纸和地板不计入）" % [title, zone, before, after]

func _paint_hover_text(cell: Vector2i) -> String:
	var facility := layout.facility_zone(cell.x, cell.y)
	var role := "这格还没有功能区" if facility == "" else "这格功能仍是%s" % _zone_title(facility)
	if _brush in ["#", ".", "+"]:
		return "%s\n%s。砌墙会挡住走路，不靠颜色划接待或用餐。" % [_brush_name(_brush), role]
	return "%s\n%s。只改外观。" % [_brush_name(_brush), role]

func _cell_hover_text(cell: Vector2i) -> String:
	var facility := layout.facility_zone(cell.x, cell.y)
	var finish := layout.finish_at(cell.x, cell.y)
	var surface := "墙" if layout.cell_zone(cell.x, cell.y) == "facade" else "地板"
	var role := "还没有功能区，放下迎宾台、收银台或餐桌后才划出来" if facility == "" else "由家具划成%s" % _zone_title(facility)
	var coat := "" if finish == "" else "，%s" % TDRestaurantLayout.finish_name(finish)
	return "%s%s。%s。" % [surface, coat, role]

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
	if _closed or not is_inside_tree() or _bar==null: return
	if _drag_candidate: _reset_drag()
	var view_size := get_viewport().get_visible_rect().size
	var decor_height := TDDecorationPanel.PANEL_HEIGHT
	if _decor_panel!=null:
		_decor_panel.size=Vector2(view_size.x,decor_height)
		decor_height=_decor_panel.size.y
		_decor_panel.position=Vector2(0,view_size.y-decor_height)
	if _iso!=null: _iso.decoration_panel_height=decor_height
	var height := decor_height if _editing else (68.0 if player_mode else 168.0)
	_bar.size = Vector2(view_size.x, height)
	_bar.position = Vector2(0, view_size.y - height)
	_position_context()
	if _bar_box != null:
		_bar_box.size = Vector2(view_size.x - 20, height - 16)
	if _status != null:
		_status.custom_minimum_size.x = view_size.x - 40
	_fit_order_board()

func set_info_top(value: float) -> void:
	if is_equal_approx(_info_top,value): return
	_info_top=value
	_fit_order_board()

func _fit_order_board() -> void:
	# Label minimum-size callbacks may still be queued while the scene is being removed.
	if _closed or not is_inside_tree(): return
	if _order_plate==null or _order_scroll==null or _order_board==null: return
	var view_size := get_viewport().get_visible_rect().size
	var width := minf(420,view_size.x-28)
	var available := maxf(96,view_size.y-_info_top-84)
	var height := clampf(_order_board.get_minimum_size().y+24,96,available)
	_order_plate.position=Vector2(14,_info_top)
	_order_plate.size=Vector2(width,height)
	_order_scroll.size=Vector2(width-24,height-24)

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
	button.add_theme_font_size_override("font_size", TDUI.FONT_CAPTION)
	for state: String in ["normal","hover","pressed"]:
		button.add_theme_stylebox_override(state,TDUI.wood(TDUI.Surface.SELECTED if state!="normal" else TDUI.Surface.CARD,8))
	button.pressed.connect(callback)
	return button

func _note(result: TDOutcome) -> TDOutcome:
	_set_status(result.message)
	return result

func _set_status(text: String) -> void:
	if _decor_panel!=null and _editing: _decor_panel.show_info(text)
	elif player_mode and is_visible_in_tree() and not text.is_empty(): status_reported.emit(text)
	if _status != null:
		_status.text = text
		_status_left=4.0 if not text.is_empty() else 0.0

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
	plated.message = "这盘菜放在出餐口，要端给坐着的%s。走到南墙出餐口按 E 端起。" % who
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
		plated.message = "这盘没做成，放在出餐口，要端给坐着等的%s。" % who
	else:
		plated.message = "%s的菜放在南墙出餐口。走到那里按 E 端起，再到这桌座位旁按 E。雇了服务员会自己去取。" % who
	return plated

func service_window_cell() -> Vector2i:
	if layout == null:
		return Vector2i(-1, -1)
	var origin := Vector2i(maxi(1, layout.columns - 3), maxi(1, layout.rows - 2))
	if layout.is_walkable(origin.x, origin.y):
		return origin
	var steps: Array[Vector2i] = [Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i(-1, -1), Vector2i(1, -1)]
	for step: Vector2i in steps:
		var cell := origin + step
		if layout.is_walkable(cell.x, cell.y):
			return cell
	return _spawn_cell()

func pass_cell() -> Vector2i:
	return service_window_cell()

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
		return TDOutcome.new(false, "TOO_FAR", "先走到南墙的出餐口。")
	var plate := active.floor.pass_plate()
	if plate.is_empty():
		return TDOutcome.new(false, "NO_PLATE", "出餐口还没有菜。")
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
	if covered:
		_reset_drag()
		_dismiss_talk()
		_clear_hover()
		if _context_menu!=null: _context_menu.hide()
	_covered = covered
	visible = not covered
	set_process_unhandled_input(not covered)
	if _iso != null:
		_iso.set_presented(not covered)
	_lock_player()
	if player_mode:
		for child: Node in get_children():
			if child is CanvasLayer: child.visible=not covered
	if _order_plate != null:
		_order_plate.visible = player_mode and not covered and not _editing and business != null and str(business.snapshot().phase) in ["OPEN", "DRAINING"]

func set_observe(observing: bool) -> void:
	_observing = observing
	if _observe_banner != null:
		_observe_banner.visible = observing
	_lock_player()

func _lock_player() -> void:
	if _player == null:
		return
	_player.set_controls_enabled(not _closed and not _covered and not _observing and not _editing and not _talk_open())

func _talk_open() -> bool:
	return _talk_view != null and is_instance_valid(_talk_view) and _talk_view.visible

func _ensure_talk() -> void:
	if _talk_view != null and is_instance_valid(_talk_view):
		return
	_talk_layer = CanvasLayer.new()
	_talk_layer.layer = 40
	_talk_layer.name = "DialogueLayer"
	add_child(_talk_layer)
	_talk_view = TDDialogueView.new()
	_talk_layer.add_child(_talk_view)
	_talk_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_talk_view.closed.connect(_on_talk_closed)

func _open_talk(next: TDDialogue) -> void:
	if characters!=null and next.context.get("kind")=="resident": characters.hold(str(next.context.character_id),true)
	_ensure_talk()
	_talk_view.present(next)
	_lock_player()

func _on_talk_closed(last_text: String, _picks: Array) -> void:
	var context: Dictionary=_talk_view.last_context
	if characters!=null and context.get("kind")=="resident":
		characters.hold(str(context.character_id),false)
		characters.complete_chat(context,_talk_view.last_completed,_picks)
	if not player_mode and not last_text.is_empty():
		_set_status(last_text)
	_lock_player()

func _dismiss_talk() -> void:
	if _talk_view != null and is_instance_valid(_talk_view):
		if characters!=null and _talk_view.talk!=null and _talk_view.talk.context.get("kind")=="resident": characters.hold(str(_talk_view.talk.context.character_id),false)
		_talk_view.dismiss()

func _place_seated(guest: TDRestaurantGuest) -> void:
	if layout == null or guest.seat_id == "":
		guest.seated = false
		return
	# Shop orders display payment at the table. Legacy service visits instead
	# walk to a cashier during pay; snapping them back would block that route.
	var at_table := guest.phase in ["wait_serve", "eat"] or (guest.phase == "pay" and not guest.service_active)
	if not at_table:
		guest.seated = false
		return
	var seat := layout.piece(guest.seat_id)
	if seat.is_empty():
		guest.seated = false
		return
	guest.seated = true
	guest.position = _dining_point(seat)

func _dining_point(seat: Dictionary) -> Vector2:
	if not unified_dining_clock: return layout.cell_center(layout.sit_cell(seat))
	var screen:=TDFurnitureModel.dining_feet(seat)-TDRestaurantIsoView.ORIGIN
	return Vector2((screen.x/TDRestaurantIsoView.HALF_W+screen.y/TDRestaurantIsoView.HALF_H)*.5,(screen.y/TDRestaurantIsoView.HALF_H-screen.x/TDRestaurantIsoView.HALF_W)*.5)*layout.cell_px

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
	return 180.0

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
	if _physical_service() and _plate_order!="":
		var plate:=business.table_service.get_plate(_plate_order)
		if plate.is_empty(): return ""
		if plate.order_id==TDTableService.TRIAL_ORDER: return "番茄炒蛋 → 阿铃 · 桌边 E 上菜"
		return business.recipe_name(str(plate.dish.recipe_id))+" · "+(business.order_label(plate.order_id) if plate.order_id!="" else "暂无客人 · 出餐口 E 放回 / Q 丢弃")
	if _plate_order != "":
		return "待上桌"
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
			return "%s已经坐在座位上，等%s。菜要从出餐口端到这桌旁边。" % [String(guest.profile.get("id", "客人")), guest.dish_name]
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
	var servers := layout.crew.waiters()
	var ids := servers.map(func(person: Dictionary) -> String: return str(person.id))
	for id: String in _waiters.keys():
		if id not in ids: _waiters.erase(id)
	var physical := _physical_service()
	if physical and delta > 0:
		business.table_service.release_missing_waiters(ids)
	if _wall_posts.size() != servers.size():
		_wall_posts = _waiter_posts(servers.size())
	var ready: Dictionary = {}
	for guest: TDRestaurantGuest in _service_jobs():
		ready[guest.ticket_id] = guest
	var held: Dictionary = {}
	if physical:
		for plate: Dictionary in business.table_service.rows():
			if plate.carrier != "":
				held[plate.carrier] = str(plate.id)
				ready.erase(plate.order_id)
	for index: int in servers.size():
		var id: String = servers[index].id
		if not _waiters.has(id):
			var newcomer := Waiter.new()
			newcomer.feet = _waiting_feet(_wall_posts[index])
			_waiters[id] = newcomer
		var waiter: Waiter = _waiters[id]
		if physical: waiter.plate = held.get(id, "")
		if waiter.plate != "": ready.erase(_plate_ticket(waiter.plate))
	# Keep an approaching employee's assignment even if a colleague finishes first.
	for id: String in ids:
		var waiter: Waiter = _waiters[id]
		if waiter.plate == "" and ready.has(waiter.pickup_ticket):
			ready.erase(waiter.pickup_ticket)
		else:
			waiter.pickup_ticket = ""
	var tickets := ready.keys()
	for index: int in servers.size():
		var server: Dictionary = servers[index]
		var waiter: Waiter = _waiters[server.id]
		if delta > 0 and waiter.plate == "" and waiter.pickup_ticket == "" and not tickets.is_empty():
			waiter.pickup_ticket = tickets.pop_front()
		var seated: TDRestaurantGuest
		if waiter.plate != "":
			seated = _guest_by_ticket(_plate_ticket(waiter.plate))
			if seated != null and (seated.phase != "wait_serve" or seated.get_meta("plated", false)):
				seated = null
			if not physical and seated == null: waiter.plate = ""
		var goal := _wall_posts[index]
		var verb := "待命"
		if seated != null:
			goal = _beside_seat(seated.seat_id)
			verb = "上菜"
		elif waiter.plate != "" or waiter.pickup_ticket != "":
			goal = service_window_cell()
			verb = "退菜" if waiter.plate != "" else "取菜"
		var previous := waiter.feet
		var waiting := waiter.plate == "" and waiter.pickup_ticket == ""
		var destination := _waiting_feet(goal) if waiting else layout.cell_center(goal)
		if delta > 0:
			_walk_waiter(waiter, goal, destination, delta)
			if waiter.feet.is_equal_approx(destination):
				if seated != null:
					if hand_plate(seated, server.id).ok: waiter.plate = ""
				elif waiter.plate != "":
					if business.table_service.put_back(waiter.plate, server.id).ok: waiter.plate = ""
				elif waiter.pickup_ticket != "":
					if physical:
						var plate := business.table_service.for_order(waiter.pickup_ticket)
						if not plate.is_empty() and business.table_service.take(plate.id, server.id).ok:
							waiter.plate = plate.id
					else: waiter.plate = waiter.pickup_ticket
					waiter.pickup_ticket = ""
		var at_wall := waiting and waiter.feet.is_equal_approx(destination)
		people.append({"point":waiter.feet, "actor_id":server.id, "role":"waiter",
			"cuisine_id":server.get("cuisine_id","cn"), "appearance_variant":server.get("appearance_variant",0),
			"held":business.table_service.held_item(waiter.plate) if physical else {}, "carrying":waiter.plate != "", "moving":not previous.is_equal_approx(waiter.feet),
			"at_wall":at_wall, "idle_lift":TDEmployeeArt.breath_lift(_visit_seconds,index) if at_wall else 0.0,
			"label":"%s %s%d" % [verb, server.name, server.get("level",1)], "color":Color("#2f7a68")})
	var active := _session() if not player_mode else null
	if active != null and active.ready:
		if active.staff_on("greeter"):
			people.append({"actor_id":"floor-greeter","point": layout.cell_center(layout.entrance()), "label": "迎宾", "color": Color("#d7a15a"), "moving": false})
		if active.staff_on("cashier"):
			var desk := layout.piece_by_kind("cashier")
			var at := layout.entrance()
			if not desk.is_empty():
				at = Vector2i(int(desk.approach_x), int(desk.approach_y))
			people.append({"actor_id":"floor-cashier","point": layout.cell_center(at), "label": "收银", "color": Color("#c4b15a"), "moving": false})
	return people

func _walk_waiter(waiter: Waiter, goal: Vector2i, destination: Vector2, delta: float) -> void:
	if waiter.feet.is_equal_approx(destination): return
	if waiter.goal != goal or waiter.destination != destination:
		var from := _cell_at(waiter.feet)
		# The visible west wall is on x=0. Enter and leave its narrow
		# standing strip through the adjacent aisle, then use normal floor paths.
		from.x = maxi(1, from.x)
		var cells := layout.path(from, goal)
		waiter.route.clear()
		for cell: Vector2i in cells:
			waiter.route.append(layout.cell_center(cell))
		if not cells.is_empty() and not destination.is_equal_approx(waiter.route[-1]):
			waiter.route.append(destination)
		waiter.waypoint = 0
		if waiter.route.size() > 1:
			# Continue straight through this cell, or return to its center before turning.
			var first := waiter.route[0]
			var second := waiter.route[1]
			if Geometry2D.get_closest_point_to_segment(waiter.feet, first, second).is_equal_approx(waiter.feet):
				waiter.waypoint = 1
		waiter.goal = goal
		waiter.destination = destination
	var budget := guest_speed * delta
	while budget > 0 and waiter.waypoint < waiter.route.size():
		var target := waiter.route[waiter.waypoint]
		var distance := waiter.feet.distance_to(target)
		if distance > budget:
			waiter.feet = waiter.feet.move_toward(target, budget)
			break
		waiter.feet = target
		budget -= distance
		waiter.waypoint += 1

func _beside_seat(seat_id: String) -> Vector2i:
	var seat := layout.piece(seat_id)
	if seat.is_empty():
		return service_window_cell()
	var approach := Vector2i(int(seat.approach_x), int(seat.approach_y))
	# The diner uses the approach to sit. Serve from the neighbouring
	# space on the same side of a two-cell table, clear of the occupied stool.
	if seat.kind == "dining_table":
		var along := Vector2i.RIGHT if approach.x == int(seat.x) else Vector2i.LEFT
		if approach.x < int(seat.x) or approach.x >= int(seat.x + seat.w):
			along = Vector2i.DOWN if approach.y == int(seat.y) else Vector2i.UP
		var side := approach + along
		if layout.is_walkable(side.x,side.y) and layout.is_walkable(approach.x,approach.y): return side
	if layout.is_walkable(approach.x, approach.y) and not _piece_covers(seat, approach):
		return approach
	return _nearest_walkable(approach, approach)

func _piece_covers(seat: Dictionary, cell: Vector2i) -> bool:
	return cell.x >= int(seat.x) and cell.y >= int(seat.y) and cell.x < int(seat.x) + int(seat.w) and cell.y < int(seat.y) + int(seat.h)

func _nearest_walkable(origin: Vector2i, prefer: Vector2i) -> Vector2i:
	if layout.is_walkable(origin.x, origin.y):
		return origin
	var best := origin
	var best_distance := 1 << 30
	var found := false
	for radius: int in range(1, 6):
		for y: int in range(origin.y - radius, origin.y + radius + 1):
			for x: int in range(origin.x - radius, origin.x + radius + 1):
				if not layout.is_walkable(x, y):
					continue
				var distance := absi(x - prefer.x) + absi(y - prefer.y)
				if distance < best_distance:
					best = Vector2i(x, y)
					best_distance = distance
					found = true
		if found:
			return best
	return service_window_cell()

func _service_jobs() -> Array[TDRestaurantGuest]:
	var seats: Array[TDRestaurantGuest] = []
	for guest: TDRestaurantGuest in guest_nodes():
		if guest.phase != "wait_serve" or guest.seat_id == "" or bool(guest.get_meta("plated", false)):
			continue
		if business == null:
			continue
		if _physical_service():
			if business.table_service.for_order(guest.ticket_id).is_empty(): continue
		elif str(business.order(guest.ticket_id).get("status", "")) != "SERVED": continue
		var cell := _beside_seat(guest.seat_id)
		if layout.is_walkable(cell.x, cell.y):
			seats.append(guest)
	return seats

func _hatch_plate_count() -> int:
	if _physical_service(): return business.table_service.rows().filter(func(p:Dictionary)->bool:return p.carrier=="").size()
	var count := 0
	if _pass_has_plate() and _held_ticket == "":
		count += 1
	var carried := {}
	for waiter: Waiter in _waiters.values():
		if waiter.plate != "": carried[waiter.plate] = true
	if _plate_order != "":
		carried[_plate_order] = true
	for guest: TDRestaurantGuest in _service_jobs():
		if not carried.has(guest.ticket_id):
			count += 1
	return count

func _waiter_posts(count: int) -> Array[Vector2i]:
	var posts: Array[Vector2i] = []
	if count == 0: return posts
	var hatch := service_window_cell()
	# x=0 is the full wall on the left of the isometric room. Start
	# toward its kitchen end, leaving room for the decoration and menu boards.
	for x: int in range(1, layout.columns - 1):
		for y: int in range(layout.rows - 4, 1, -1):
			var cell := Vector2i(x, y)
			if (x == 1 and (y == 3 or layout.furniture_blocks(0,y))) or cell == layout.entrance() or cell == hatch: continue
			if layout.path(hatch, cell).is_empty(): continue
			posts.append(cell)
			if posts.size() == count: return posts
	# A sealed-off hatch has no reachable row. Do not spawn staff inside furniture.
	while posts.size() < count: posts.append(hatch)
	return posts

func _waiting_feet(post: Vector2i) -> Vector2:
	var point := layout.cell_center(post)
	if post.x == 1: point.x = layout.cell_px * .28
	return point

func nearby_object() -> Dictionary:
	var nearest: Dictionary={};var distance: float=1.0
	for entry: Dictionary in interaction_points():
		var gap:=TDInteractionRange.distance(_player.position/float(layout.cell_px),entry.get("bounds",Rect2(entry.cell,Vector2.ONE)))
		if gap<distance or (is_equal_approx(gap,distance) and str(entry.action)<str(nearest.get("action","~"))): nearest=entry;distance=gap
	return nearest

func kitchen_door_cell() -> Vector2i:
	return Vector2i(layout.columns-2,layout.rows-2)

func interaction_points() -> Array[Dictionary]:
	if layout==null: return []
	var cashier:=layout.counter()
	var ledger_cell:=Vector2(maxi(2,layout.columns/3),0)
	var ledger_bounds:=Rect2(ledger_cell,Vector2.ONE)
	if not cashier.is_empty():
		ledger_bounds=Rect2(cashier.x,cashier.y,cashier.w,cashier.h)
		ledger_cell=ledger_bounds.get_center()-Vector2.ONE*.5
	return [
		{"action":"town","name":"店门 · 小镇","cell":Vector2(layout.entrance())},
		{"action":"menu","name":"营业牌","cell":Vector2(0,3)},
		{"action":"ledger","name":"账本","cell":ledger_cell,"bounds":ledger_bounds,"on_counter":not cashier.is_empty()},
		{"action":"decorate","name":"装修图板","cell":Vector2(0,layout.rows-3)},
		{"action":"kitchen","name":"后厨","cell":Vector2(kitchen_door_cell())}]

func bind_dining_clock() -> void:
	if business==null: return
	unified_dining_clock=true;business.require_seating=true
	business.dining_tick=advance_dining;business.dining_boundary=next_dining_boundary

func advance_dining(seconds: float) -> void:
	if _closed or get_tree().paused or story_frozen: return
	_visit_seconds+=seconds
	for guest: TDRestaurantGuest in guest_nodes():
		if guest.frozen: continue
		if guest.phase=="sitting": guest.advance_sitting(seconds)
		elif guest.phase in ["approach","leave"]: guest.advance(guest.speed*seconds)
	_sync_business_guests()
	_crew_points(seconds)
	for guest: TDRestaurantGuest in guest_nodes(): _place_seated(guest)

func next_dining_boundary(maximum: float) -> float:
	var next := _waiter_boundary(maximum)
	for guest: TDRestaurantGuest in guest_nodes():
		if guest.frozen: continue
		if guest.phase=="sitting": next=minf(next,maxf(.0000001,guest.sit_duration-guest.sit_elapsed))
		elif guest.phase in ["approach","leave"] and not guest.finished: next=minf(next,maxf(.0000001,guest.walking_seconds()))
		elif guest.has_meta("settled_at") and guest.phase in ["eat","pay"]:
			var age: float=_visit_seconds-float(guest.get_meta("settled_at"))
			var target: float=TDGuestVisit.EAT_SEC if guest.phase=="eat" else TDGuestVisit.EAT_SEC+TDGuestVisit.PAY_SEC
			if age<target: next=minf(next,maxf(.0000001,target-age))
	return next

# Stop the shared clock at real pickup/handoff, even when advancing a large span off screen.
func _waiter_boundary(maximum: float) -> float:
	if not _physical_service() or _waiters.is_empty() or business.table_service.empty(): return maximum
	var available := {}
	for plate: Dictionary in business.table_service.rows():
		if plate.carrier == "" and not str(plate.order_id).is_empty():
			var guest := _guest_by_ticket(plate.order_id)
			if guest != null and guest.phase=="wait_serve": available[plate.order_id] = true
	for waiter: Waiter in _waiters.values(): available.erase(waiter.pickup_ticket)
	var next := maximum
	for waiter: Waiter in _waiters.values():
		if waiter.plate == "" and waiter.pickup_ticket == "" and available.is_empty(): continue
		var guest := _guest_by_ticket(_plate_ticket(waiter.plate)) if waiter.plate != "" else null
		var target := _beside_seat(guest.seat_id) if guest != null and guest.phase=="wait_serve" else service_window_cell()
		if waiter.goal != target or waiter.waypoint >= waiter.route.size():
			next = minf(next, 0.05)
			continue
		var distance := waiter.feet.distance_to(waiter.route[waiter.waypoint])
		for i: int in range(waiter.waypoint + 1, waiter.route.size()):
			distance += waiter.route[i - 1].distance_to(waiter.route[i])
		next = minf(next, maxf(.000001, distance / guest_speed))
	return next

func restore_visit_boundary() -> void:
	# Boundary saves contain historical orders, not resumable dining actors.
	_finished_visits.clear()
	if business==null: return
	var state:=business.snapshot()
	_visit_day=int(state.day)
	for order: Dictionary in state.orders:
		if order.status not in ["ARRIVING","WAITING","COOKING"]: _finished_visits[str(order.id)]=true

func _sync_business_guests() -> void:
	if business == null or layout == null or _guests == null:
		return
	_sync_trial_guest()
	var snap := business.snapshot()
	var orders: Array = snap.orders
	var now := float(snap.elapsed_sec)
	if _visit_day!=int(snap.day): _finished_visits.clear();_visit_day=int(snap.day)
	var by_id := {}
	for order: Dictionary in orders:
		by_id[str(order.id)] = order
	for order: Dictionary in orders:
		if str(order.status) not in ["ARRIVING", "WAITING", "COOKING", "SERVED"] or _business_guests.has(str(order.id)) or _finished_visits.has(str(order.id)):
			continue
		var character_id:=characters.character_for(order.get("economic_profile",{})) if characters!=null else ""
		if character_id!="" and not characters.can_enter(character_id,str(order.id)): continue
		var occupied: Array = []
		for current: TDRestaurantGuest in guest_nodes():
			if current.seat_id != "":
				occupied.append(current.seat_id)
		var seat := {}
		var route: Array = []
		for piece: Dictionary in layout.pieces():
			if str(piece.seat_use) != "dining" or str(piece.id) in occupied:
				continue
			var path: Array = layout.path(layout.entrance(), Vector2i(int(piece.approach_x), int(piece.approach_y)))
			if path.is_empty():
				continue
			seat = piece
			route = path
			break
		if route.is_empty() and str(order.status)!="ARRIVING":
			continue
		var guest := TDRestaurantGuest.new()
		guest.ticket_id = str(order.id)
		guest.character_id=character_id
		if characters!=null and not character_id.is_empty(): characters.begin_visit(character_id,str(order.id))
		guest.appearance_id=TDDinerArt.appearance(str(order.get("economic_profile",{}).get("id",order.id)))
		guest.externally_driven=unified_dining_clock
		guest.speed=guest_speed
		if order.has("economic_profile"): guest.dining_profile=TDEconomicCustomer.new(order.economic_profile)
		if order.has("economic_intent"): guest.meal_intent=TDMealIntent.new(order.economic_intent)
		guest.seat_id = str(seat.get("id", ""))
		guest.phase = "approach"
		guest.set_meta("recipe_label", business.recipe_name(str(order.recipe_id)))
		var welcomed := unified_dining_clock or duty_on("greeter")
		guest.set_meta("welcomed", welcomed)
		guest.set_meta("sent_in", welcomed)
		guest.dish_name = _order_caption(order, "approach", now)
		guest.process_mode = Node.PROCESS_MODE_PAUSABLE
		_guests.add_child(guest)
		if welcomed and not route.is_empty():
			guest.set_path(route, layout.cell_px)
		else:
			guest.position = layout.cell_center(_queue_cell() if route.is_empty() else layout.entrance())
			guest.finished = true
			if route.is_empty(): guest.phase="waiting_seat"
		_business_guests[str(order.id)] = guest
	var ids: Array = _business_guests.keys()
	for id: String in ids:
		var guest: TDRestaurantGuest = _business_guests[id]
		if not is_instance_valid(guest):
			_business_guests.erase(id)
			continue
		var order: Dictionary = by_id.get(id, {})
		var status := str(order.get("status", "CANCELLED"))
		if _talk_open() and str(_talk_view.talk.context.get("ticket_id",""))==id: continue
		if status=="ARRIVING" and guest.seat_id=="":
			var next_seat:=_free_seat(_cell_at(guest.position))
			if next_seat.is_empty():
				guest.phase="waiting_seat";guest.dish_name=business.order_label(id)+" · 等空位"
				continue
			guest.seat_id=str(next_seat.seat.id);guest.phase="approach"
			guest.set_path(next_seat.path,layout.cell_px)
		var arrived := guest.phase != "approach" or guest.finished
		var welcomed := unified_dining_clock or duty_on("greeter") or bool(guest.get_meta("welcomed", false))
		if not welcomed and status in ["ARRIVING","WAITING","COOKING","SERVED"]:
			guest.phase = "approach"
			guest.dish_name = _order_caption(order, "approach", now)
			continue
		if not bool(guest.get_meta("sent_in", false)) and status in ["ARRIVING","WAITING","COOKING","SERVED"]:
			guest.set_meta("sent_in", true)
			guest.set_meta("welcomed", true)
			var seat := layout.piece(guest.seat_id)
			var dest := layout.entrance()
			if not seat.is_empty():
				dest = Vector2i(int(seat.approach_x), int(seat.approach_y))
			var walk: Array = layout.path(layout.entrance(), dest)
			if walk.is_empty():
				guest.finished = true
			else:
				guest.set_path(walk, layout.cell_px)
			arrived = guest.finished or guest.phase != "approach"
		if status=="ARRIVING":
			if guest.phase=="sitting" and guest.sit_elapsed>=guest.sit_duration:
				business.confirm_seated(id,guest.seat_id)
				order=business.order(id);status=str(order.status)
			elif arrived and guest.phase!="sitting":
				var seat:=layout.piece(guest.seat_id)
				if not seat.is_empty():
					var target:=_dining_point(seat)
					var direction:=TDFurnitureModel.center(seat)-TDFurnitureModel.dining_feet(seat)
					var facing:=Vector2i.RIGHT if direction.x>0 else Vector2i.LEFT
					if absf(direction.y)>absf(direction.x): facing=Vector2i.DOWN if direction.y>0 else Vector2i.UP
					guest.begin_sitting(target,float(business.catalog.config.settings.get("sit_down_sec",.7)),facing)
			if status=="ARRIVING":
				guest.dish_name="正在入座…" if guest.phase=="sitting" else "走向座位 · 尚未点单"
				continue
		if status in ["WAITING", "COOKING"]:
			guest.phase = TDGuestVisit.phase_of(status, arrived, 0.0)
			if guest.has_meta("settled_at"):
				guest.remove_meta("settled_at")
		else:
			var plated := not floor_service or (duty_on("runner") and layout.crew.waiters().is_empty()) or bool(guest.get_meta("plated", false))
			if status == "SERVED" and not plated:
				if guest.has_meta("settled_at"):
					guest.remove_meta("settled_at")
				guest.phase = "wait_serve" if arrived else "approach"
				guest.dish_name = _order_caption(order, guest.phase, now)
				continue
			if not guest.has_meta("settled_at"):
				guest.set_meta("settled_at", _visit_seconds)
			var since := _visit_seconds - float(guest.get_meta("settled_at"))
			var next := TDGuestVisit.phase_of(status, true, since)
			if next == "leave" and status=="SERVED" and not duty_on("cashier") and not bool(guest.get_meta("cashed", false)):
				guest.phase = "pay"
			elif next == "leave":
				if guest.phase != "leave":
					_send_guest_out(guest)
				elif guest.finished:
					_finished_visits[id]=true
					if characters!=null: characters.finish_visit(guest.character_id,id)
					_guests.remove_child(guest)
					guest.free()
					_business_guests.erase(id)
					continue
			else:
				guest.phase = next
		if is_instance_valid(guest):
			guest.dish_name = _order_caption(order, guest.phase, now)
	_refresh_order_board(orders, now)

func _sync_trial_guest() -> void:
	# Tutorial recipient shares the physical pass without inventing a paid order.
	var waiting:=not business.table_service.for_order(TDTableService.TRIAL_ORDER).is_empty()
	for guest: TDRestaurantGuest in guest_nodes():
		if guest.ticket_id!=TDTableService.TRIAL_ORDER: continue
		if not waiting: _guests.remove_child(guest);guest.free()
		return
	if not waiting: return
	var seat:=_free_seat(service_window_cell())
	if seat.is_empty(): return
	var guest:=TDRestaurantGuest.new()
	guest.ticket_id=TDTableService.TRIAL_ORDER;guest.character_id="aling"
	guest.seat_id=str(seat.seat.id);guest.phase="wait_serve";guest.finished=true
	guest.externally_driven=true;guest.dish_name="阿铃 · 等你端来番茄炒蛋"
	_guests.add_child(guest);_place_seated(guest)

func _free_seat(start: Vector2i) -> Dictionary:
	var occupied: Array=guest_nodes().map(func(g:TDRestaurantGuest)->String:return g.seat_id)
	for piece: Dictionary in layout.pieces():
		if piece.seat_use!="dining" or piece.id in occupied: continue
		var route:=layout.path(start,Vector2i(piece.approach_x,piece.approach_y))
		if not route.is_empty(): return {"seat":piece,"path":route}
	return {}

func _queue_cell() -> Vector2i:
	# Visual actors have no collision, but also keep door/fixture interaction areas clear.
	for y: int in range(1,mini(layout.rows-1,7)):
		for x: int in range(1,layout.columns-1):
			var cell:=Vector2i(x,y)
			if not layout.is_walkable(x,y) or Vector2(cell).distance_to(Vector2(layout.entrance()))<2.0: continue
			var safe: bool=true
			for marker: Dictionary in interaction_points():
				if TDInteractionRange.distance(Vector2(cell)+Vector2.ONE*.5,marker.get("bounds",Rect2(marker.cell,Vector2.ONE)))<1.3: safe=false;break
			for other: TDRestaurantGuest in guest_nodes():
				if other.position.distance_to(layout.cell_center(cell))<float(layout.cell_px): safe=false;break
			if safe: return cell
	return layout.entrance()

func duty_on(role: String) -> bool:
	if not floor_service: return true
	if role in ["runner","cashier","greeter"] and layout!=null and not layout.crew.waiters().is_empty(): return true
	if layout!=null and layout.crew.external: return false
	var active := _session()
	if active == null or not active.ready:
		return false
	return active.staff_on(role)

func greet_guest(guest: TDRestaurantGuest) -> void:
	if guest == null:
		return
	guest.set_meta("welcomed", true)

func hand_plate(guest: TDRestaurantGuest, carrier: String="player") -> TDOutcome:
	if guest == null:
		return TDOutcome.new(false,"UNKNOWN_GUEST")
	if _physical_service():
		if get_tree().paused or story_frozen: return TDOutcome.new(false,"PAUSED")
		var id:=_plate_order;var carrier_position:=_player.position
		if carrier!="player":
			var waiter: Waiter = _waiters.get(carrier)
			if waiter == null: return TDOutcome.new(false,"INVALID_CARRIER")
			id = waiter.plate
			carrier_position = waiter.feet
		if carrier_position.distance_to(layout.cell_center(_beside_seat(guest.seat_id)))>INTERACTION_RADIUS: return TDOutcome.new(false,"TOO_FAR","请走到这位客人桌边再上菜。")
		var result:=business.table_service.serve(id,carrier,guest.ticket_id)
		if not result.ok: return result
		if carrier=="player": _plate_order=""
		if guest.ticket_id != TDTableService.TRIAL_ORDER:
			guest.phase = "eat"
			guest.set_meta("settled_at", _visit_seconds)
	guest.set_meta("plated", true)
	if _plate_order == guest.ticket_id:
		_plate_order = ""
	return TDOutcome.new(true,"SERVED","已将试做交给阿铃。" if guest.ticket_id==TDTableService.TRIAL_ORDER else "菜已送到客人桌上，评价和菜款已记入账本。")

func _physical_service() -> bool:
	return player_mode and floor_service and business!=null and business.table_service_enabled

func _plate_ticket(id: String) -> String:
	return str(business.table_service.get_plate(id).get("order_id","")) if _physical_service() else id

func _at_service_window() -> bool:
	return _player.position.distance_to(layout.cell_center(service_window_cell()))<=INTERACTION_RADIUS

func cash_guest(guest: TDRestaurantGuest) -> void:
	if guest == null:
		return
	guest.set_meta("cashed", true)

func _floor_act() -> bool:
	if _physical_service():
		if _plate_order!="" and business.table_service.get_plate(_plate_order).is_empty(): _plate_order=""
		if _at_service_window():
			if _plate_order!="":
				var returned:=business.table_service.put_back(_plate_order,"player")
				if returned.ok: _plate_order=""
				_set_status(returned.message);return true
			var id:=_unplated_order()
			if id!="":
				var taken:=business.table_service.take(id,"player")
				if taken.ok: _plate_order=id
				_set_status(taken.message);return true
		if _plate_order!="":
			var closest: TDRestaurantGuest=null;var gap:=INTERACTION_RADIUS
			for guest: TDRestaurantGuest in guest_nodes():
				if guest.seat_id=="" or guest.phase!="wait_serve": continue
				var distance:=_player.position.distance_to(layout.cell_center(_beside_seat(guest.seat_id)))
				if distance<=INTERACTION_RADIUS and guest.ticket_id==_plate_ticket(_plate_order): closest=guest;break
				if distance<gap: gap=distance;closest=guest
			if closest!=null: _set_status(hand_plate(closest).message);return true
		var paying:=_faced_guest()
		if paying!=null and paying.phase=="pay" and not duty_on("cashier") and not bool(paying.get_meta("cashed",false)):
			cash_guest(paying);_set_status("这一桌已结账离开，账本不会重复收款。");return true
		return false
	var faced := _faced_guest()
	if _plate_order != "" and faced != null:
		if faced.ticket_id != _plate_order:
			_set_status("这盘要端给点这道菜的那一桌。")
			return true
		_set_status(hand_plate(faced).message)
		return true
	if faced != null and not duty_on("greeter") and not bool(faced.get_meta("welcomed", false)):
		greet_guest(faced)
		_set_status("%s请进，我带你去座位。" % _guest_name(faced))
		return true
	if faced != null and faced.phase == "pay" and not duty_on("cashier") and not bool(faced.get_meta("cashed", false)):
		cash_guest(faced)
		_set_status("这一桌送走了。款项在出餐时已经入账。")
		return true
	if _plate_order == "" and _needs_player_plate() and cell_of_player() == pass_cell():
		_plate_order = _unplated_order()
		_set_status("从出餐口端起菜。走到客人面前按 E。")
		return true
	return false

func _waiter_serving() -> bool:
	return layout != null and layout.crew != null and not layout.crew.waiters().is_empty()

func _needs_player_plate() -> bool:
	if _physical_service(): return _unplated_order()!=""
	return floor_service and not duty_on("runner") and not _waiter_serving() and _unplated_order() != ""

func _unplated_order() -> String:
	if _physical_service():
		for plate: Dictionary in business.table_service.rows():
			if plate.carrier=="": return str(plate.id)
		return ""
	for id: String in _business_guests.keys():
		var guest: TDRestaurantGuest = _business_guests[id]
		if not is_instance_valid(guest) or bool(guest.get_meta("plated", false)):
			continue
		if business == null:
			continue
		var order := business.order(id)
		if str(order.get("status", "")) == "SERVED":
			return id
	return ""

func _guest_name(guest: TDRestaurantGuest) -> String:
	if guest!=null and characters!=null and guest.character_id!="": return str(characters.definition(guest.character_id).get("name","客人"))
	if guest!=null and business!=null: return business.order_label(guest.ticket_id)
	return "客人"

func _tick_floor_runner(_delta: float) -> void:
	# Hired waiters carry the plates. The formal dining room does not add a runner.
	_runner_on = false

func _send_guest_out(guest: TDRestaurantGuest) -> void:
	guest.phase = "leave"
	guest.seated = false
	var cell := _cell_at(guest.position)
	var seat := layout.piece(guest.seat_id)
	if not layout.is_walkable(cell.x, cell.y) and not seat.is_empty():
		cell = Vector2i(int(seat.approach_x), int(seat.approach_y))
	var route := layout.path(cell, layout.entrance())
	if route.is_empty():
		guest.finished = true
		return
	guest.set_path(route, layout.cell_px)

func _order_caption(order: Dictionary, phase: String, now: float) -> String:
	if _physical_service():
		var plate:=business.table_service.for_order(str(order.get("id","")))
		if not plate.is_empty():
			return business.order_label(str(order.id))+" · "+business.recipe_name(str(order.recipe_id))+" · "+("出餐口待取" if plate.carrier=="" else "端菜途中")+" · %d秒"%maxi(0,ceili(float(order.deadline_sec)-now))
	var dish := ""
	if not order.is_empty():
		dish = business.recipe_name(str(order.get("recipe_id", "")))
	var left := 0
	if order.has("deadline_sec"):
		left = ceili(maxf(0.0, float(order.deadline_sec) - now))
	var satisfaction := -1.0
	if order.get("score") is Dictionary and not (order.score as Dictionary).is_empty():
		satisfaction = float((order.score as Dictionary).get("satisfaction", -1.0))
	var net := int(order.get("prepaid_cents", 0)) + int(order.get("tip_cents", 0)) - int(order.get("refunded_cents", 0))
	return business.order_label(str(order.get("id","")))+" · "+TDGuestVisit.caption(dish, str(order.get("status", "")), phase, left, satisfaction, net, int(order.get("refunded_cents", 0)))

func _decor_now() -> Dictionary:
	var wild: Array = []
	if session != null and session.catalog != null:
		wild = session.catalog.wildcards
	return TDEconomyMath.decor_of(layout.pieces() if layout != null else [], wild)

func _faced_guest() -> TDRestaurantGuest:
	if _player == null:
		return null
	var best: TDRestaurantGuest = null
	var best_gap := 1.45
	var here := Vector2(cell_of_player())
	for guest: TDRestaurantGuest in guest_nodes():
		if guest.phase == "gone":
			continue
		var gap := here.distance_to(Vector2(_cell_at(guest.position)))
		if gap >= best_gap:
			continue
		best = guest
		best_gap = gap
	return best

func _guest_brief(guest: TDRestaurantGuest) -> String:
	if business == null:
		return guest.dish_name
	var order := business.order(guest.ticket_id)
	var now := float(business.snapshot().elapsed_sec)
	var dish := str(guest.get_meta("recipe_label", guest.dish_name))
	var customer := "客人"
	var status := guest.phase
	var price := 0
	var satisfaction := -1.0
	var net := 0
	var refunded := 0
	var reasons := PackedStringArray()
	if not order.is_empty():
		dish = business.recipe_name(str(order.recipe_id))
		status = str(order.status)
		price = int(order.get("price_cents", 0))
		net = int(order.get("prepaid_cents", 0)) + int(order.get("tip_cents", 0)) - int(order.get("refunded_cents", 0))
		refunded = int(order.get("refunded_cents", 0))
		if order.get("customer") is Dictionary:
			customer = str((order.customer as Dictionary).get("name", "客人"))
		if guest.character_id!="": customer=_guest_name(guest)
		if order.get("score") is Dictionary and not (order.score as Dictionary).is_empty():
			satisfaction = float((order.score as Dictionary).get("satisfaction", -1.0))
		if order.get("economic_intent") is Dictionary:
			for reason: Variant in (order.economic_intent as Dictionary).get("reasons", []):
				reasons.append(str(reason))
	var left := 0
	if order.has("deadline_sec"):
		left = ceili(maxf(0.0, float(order.deadline_sec) - now))
	var crew := ""
	if layout != null and layout.crew != null:
		crew = layout.crew.duty_line()
	var text := TDGuestVisit.inspect_text(dish, customer, status, guest.phase, left, price, satisfaction, net, refunded, reasons, float(_decor_now().get("effect", 0.0)), crew)
	if floor_service:
		text += "\n客人自己入座，收银%s。%s。" % ["在岗" if duty_on("cashier") else "你来", "菜放在出餐口，服务员去取再端上桌" if _waiter_serving() else "菜放在出餐口，由你端上桌"]
	return text

func _refresh_order_board(orders: Array, now: float) -> void:
	if _order_board == null:
		return
	if _order_plate != null:
		_order_plate.visible = player_mode and not _covered and not _editing and business!=null and str(business.snapshot().phase) in ["OPEN","DRAINING"]
	_order_board.visible = true
	if not player_mode or _covered:
		return
	var lines := PackedStringArray()
	if not unified_dining_clock:
		var decor := _decor_now()
		lines.append("装修效果 %.0f · 统一 %.0f · 高端 %.0f" % [float(decor.effect), float(decor.unity), float(decor.luxury)])
		if floor_service:
			lines.append("自动入座 · 送餐：%s · 收银：%s" % ["服务员" if _waiter_serving() else "你","在岗" if duty_on("cashier") else "你"])
	var active: Array = []
	var arriving: int=0
	var recent: Dictionary = {}
	for order: Dictionary in orders:
		var status := str(order.status)
		if status=="ARRIVING": arriving+=1
		if status in ["WAITING", "COOKING"]:
			active.append(order)
		elif status in ["SERVED", "TIMED_OUT", "CANCELLED", "REJECTED_STOCK"]:
			recent = order
	var shown := 0
	for order: Dictionary in active:
		var guest: TDRestaurantGuest = _business_guests.get(str(order.id), null) as TDRestaurantGuest
		if guest != null and is_instance_valid(guest):
			lines.append(_order_caption(order, guest.phase, now))
		else:
			lines.append(_order_caption(order, "approach", now) + " · 门口等位")
		shown += 1
		if shown >= 5:
			break
	if not unified_dining_clock and not recent.is_empty() and shown < 6:
		var latest: TDRestaurantGuest = _business_guests.get(str(recent.id), null) as TDRestaurantGuest
		var phase := "leave"
		if latest != null and is_instance_valid(latest):
			phase = latest.phase
		lines.append(_order_caption(recent, phase, now))
		shown += 1
	if arriving>0: lines.append("%d位客人入座中"%arriving)
	if shown == 0 and arriving==0:
		var phase:=str(business.snapshot().phase) if business!=null else ""
		if phase in ["OPEN","DRAINING"] and business.economic_menu().is_empty():
			lines.append("食材不足，请补货或调整菜单")
	if unified_dining_clock:
		if _physical_service():
			if _plate_order!="": lines.append("端着："+_held_caption())
	elif floor_service:
		lines.append("靠近客人按 E。菜放在出餐口后，雇了服务员就由服务员去取，没雇就由你端。")
	else:
		lines.append("靠近客人按 E，查看点单、比较和结算。")
	var text := "\n".join(lines)
	if text.is_empty(): _order_plate.hide()
	if _order_board.text!=text:
		_order_board.text=text
		_fit_order_board.call_deferred()

var last_visit: Dictionary = {}

func finish_night() -> void:
	_dismiss_talk()
	for guest: TDRestaurantGuest in guest_nodes():
		_finished_visits[guest.ticket_id]=true
		if characters!=null: characters.finish_visit(guest.character_id,guest.ticket_id)
	_clear_guests()
	_business_guests.clear();_plate_order=""
