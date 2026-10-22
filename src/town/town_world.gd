class_name TDTownWorld
extends Node2D

signal back_requested
signal pause_requested
signal restaurant_requested

const CELL := 48
const BAR_HEIGHT := 210.0

var session: TDPhase3Session
var _player: TDKitchenPlayer
var _camera: Camera2D
var _status: Label
var _selected: Dictionary = {}
var _board: TDEconomyBoard
var _pantry: TDPantryBoard
var _closed: bool = false
var _blockers: StaticBody2D
var _seen_revision: int = -1
var _staff_role: String = "greeter"
var _venue_layer: CanvasLayer
var _entering_diner: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if session == null:
		session = TDPhase3Session.new()
		var loaded := session.load_default()
		if not loaded.ok:
			_status_bar()
			_set_status(loaded.message)
			return
	elif not session.ready:
		session.load_default()
	_player = TDKitchenPlayer.new()
	_player.name = "Player"
	_player.process_mode = Node.PROCESS_MODE_PAUSABLE
	_player.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	_player.collision_layer = 2
	_player.collision_mask = 1
	var sprite := Sprite2D.new()
	sprite.name = "Sprite2D"
	sprite.texture = TDRestaurantArt.guest_texture()
	_player.add_child(sprite)
	_player.body_lift = 0.0
	_player.confine_to = _feet_on_road
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 10.0
	shape.shape = circle
	_player.add_child(shape)
	_player.position = _origin() + Vector2((TDTownMap.CENTER + 0.5) * CELL, (TDTownMap.CENTER + 0.5) * CELL)
	add_child(_player)
	_camera = Camera2D.new()
	_camera.name = "TownCamera"
	_camera.zoom = Vector2.ONE * _overview_zoom()
	_camera.position_smoothing_enabled = false
	_camera.enabled = true
	add_child(_camera)
	_camera.make_current()
	_follow_camera()
	_build_blockers()
	_seen_revision = session.map_revision
	_status_bar()
	_set_status(_enter_hint())
	queue_redraw()

func _process(_delta: float) -> void:
	_follow_camera()
	_try_enter_diner()
	if _closed:
		return
	if session != null and session.map_revision != _seen_revision:
		_seen_revision = session.map_revision
		_build_blockers()
		if _player != null:
			_player.position = _origin() + Vector2((TDTownMap.CENTER + 0.5) * CELL, (TDTownMap.CENTER + 0.5) * CELL)
	queue_redraw()

func _overview_zoom() -> float:
	var view := get_viewport().get_visible_rect().size
	var map_px := float(TDTownMap.SIZE * CELL)
	var usable_height := maxf(1.0, view.y - BAR_HEIGHT)
	return minf(view.x / map_px, usable_height / map_px) * 0.96 * 2.0

func _follow_camera() -> void:
	if _player == null or _camera == null:
		return
	var zoom := _overview_zoom()
	_camera.zoom = Vector2(zoom, zoom)
	var view := get_viewport().get_visible_rect().size / zoom
	var map_size := Vector2(TDTownMap.SIZE * CELL, TDTownMap.SIZE * CELL)
	var origin := _origin()
	var half := view * 0.5
	var target := _player.position + Vector2(0, BAR_HEIGHT * 0.5 / zoom)
	if map_size.x > view.x:
		target.x = clampf(target.x, origin.x + half.x, origin.x + map_size.x - half.x)
	else:
		target.x = origin.x + map_size.x * 0.5
	if map_size.y > view.y:
		target.y = clampf(target.y, origin.y + half.y, origin.y + map_size.y - half.y)
	else:
		target.y = origin.y + map_size.y * 0.5
	_camera.position = target

func _draw() -> void:
	if session == null or session.town_map.plots.is_empty():
		return
	var origin := _origin()
	for y in TDTownMap.SIZE:
		for x in TDTownMap.SIZE:
			var ground := Rect2(origin + Vector2(x * CELL, y * CELL), Vector2(CELL - 1, CELL - 1))
			var color := Color("#2c3338")
			if session.town_map.is_road(x, y):
				color = Color("#c8b48a")
			draw_rect(ground, color)
	for item: Variant in session.town_map.plots:
		var plot: Dictionary = item
		var width := int(plot.get("w", 1))
		var height := int(plot.get("h", 1))
		var rect := Rect2(origin + Vector2(int(plot["x"]) * CELL + 2, int(plot["y"]) * CELL + 2), Vector2(width * CELL - 4, height * CELL - 4))
		var fill := _kind_color(String(plot["kind"]), bool(plot["enabled"]))
		if String(plot.get("venue", "")) == "western":
			fill = Color("#3f6f99")
		elif String(plot.get("venue", "")) == "chinese":
			fill = Color("#b84a3c")
		draw_rect(rect, fill)
		if String(plot["id"]) == String(_selected.get("id", "")) and String(plot["kind"]) != "housing":
			draw_rect(rect, Color("#f0cc70"), false, 3.0)
		if String(plot["kind"]) == "housing":
			continue
		if String(plot["kind"]) == "diner_lot" or String(plot["kind"]) == "factory_lot":
			draw_rect(rect, Color("#f4e27a"), false, 3.0)
		var font := ThemeDB.fallback_font
		if font != null:
			var at := rect.position + Vector2(6, maxf(18.0, rect.size.y * 0.55))
			draw_string(font, at, "%s  %d×%d" % [String(plot["name"]), width, height], HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 8, 14, Color.WHITE)
	if session != null:
		var shade := TDSanRules.vignette_alpha(float(session.san))
		if shade > 0.01:
			draw_rect(Rect2(_origin(), Vector2(TDTownMap.SIZE * CELL, TDTownMap.SIZE * CELL)), Color(0, 0, 0, shade))

func _unhandled_input(event: InputEvent) -> void:
	if _closed or session == null:
		return
	if event.is_action_pressed("pause") and not event.is_echo():
		pause_requested.emit()
		get_viewport().set_input_as_handled()
		return
	if get_tree().paused:
		return
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT and not mouse.is_echo():
			_click_build(mouse.position)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("world_interact") and not event.is_echo():
		_interact()
		get_viewport().set_input_as_handled()

func close() -> void:
	_closed = true
	if _camera != null:
		_camera.enabled = false
	set_process_unhandled_input(false)
	if _player != null:
		_player.set_controls_enabled(false)
	if _board != null:
		_board.queue_free()
	if _pantry != null:
		_pantry.queue_free()
	_close_venue_choice()

func _interact() -> void:
	var cell := _player_cell()
	var plot := session.town_map.plot_at(cell.x, cell.y)
	if plot.is_empty():
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var neighbor := session.town_map.plot_at(cell.x + step.x, cell.y + step.y)
			if not neighbor.is_empty() and String(neighbor["kind"]) != "housing":
				plot = neighbor
				break
	if plot.is_empty():
		_set_status("旁边没有功能区。点建设区空地建店或建厂；沿路按E选功能区。")
		return
	_selected = plot
	var kind := String(plot["kind"])
	if kind == "diner_lot":
		_set_status("餐厅建设区还是空地。点击这块地，选择中餐厅或西餐厅。")
		return
	if kind == "factory_lot":
		_set_status("%s还是空地。点击建设原料提供厂，不用按E。" % String(plot.get("name", "原料厂空地")))
		return
	if kind == "supply_factory":
		_set_status("%s已建成。供货仍走市场报价，这里不做单独工厂场景。" % String(plot.get("name", "原料提供厂")))
		return
	if kind == "player_diner":
		var size_id := String(plot.get("size", session.home_size))
		if size_id == "":
			size_id = "small"
		var room := TDRestaurantSizes.interior(size_id)
		if String(plot.get("id", "")) == "branch_diner":
			_set_status("这是分店，地图%d×%d，店内%d×%d。菜单、员工和库存跟主店分开。" % [int(plot["w"]), int(plot["h"]), room.x, room.y])
		else:
			_set_status("这是%s，地图%d×%d。走到店里就能进去。" % [String(plot.get("name", "餐厅")), int(plot["w"]), int(plot["h"])])
		return
	if kind == "market":
		var picked := session.select_market(String(plot["id"]))
		_set_status(picked.message if picked.message != "" else picked.code)
		return
	if kind == "competitor":
		var names := ""
		if not session.competitors.is_empty():
			var rival: Dictionary = session.competitors[0]
			names = String(rival["name"])
		_set_status("竞品%s。客人会比较你和两家竞品菜单上的每一道菜。" % names)
		return
	var enabled := "计入客流" if bool(plot["enabled"]) else "不计入客流"
	var offer := TDSanRules.recovery(kind)
	var visit := ""
	if not offer.is_empty():
		visit = " 花%d元、%.0f小时可回复%d点SAN。" % [int(offer["cost"]), float(offer["hours"]), int(offer["san"])]
	var near := ""
	if kind == "amusement" or kind == "landmark":
		near = " 离餐厅%d格，预计人气加成%d。" % [session.town_map.distance_to(String(plot["id"])), TDSanRules.near_bonus(session.town_map.distance_to(String(plot["id"])))]
	_set_status("%s，%s。人数贡献%d，预算平移%d。%s%s" % [String(plot["name"]), enabled, int(plot["pool"]), int(plot["budget_shift"]), visit, near])

func _build_blockers() -> void:
	if _blockers != null and is_instance_valid(_blockers):
		_blockers.queue_free()
	var body := StaticBody2D.new()
	_blockers = body
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	for y in TDTownMap.SIZE:
		for x in TDTownMap.SIZE:
			if session.town_map.is_walkable(x, y):
				continue
			var shape := RectangleShape2D.new()
			shape.size = Vector2(CELL, CELL)
			var collider := CollisionShape2D.new()
			collider.shape = shape
			collider.position = _origin() + Vector2((x + 0.5) * CELL, (y + 0.5) * CELL)
			body.add_child(collider)

func _status_bar() -> void:
	var layer := CanvasLayer.new()
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	var panel := Panel.new()
	panel.position = Vector2(0, 590)
	panel.size = Vector2(1280, 210)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(panel)
	var box := VBoxContainer.new()
	box.position = Vector2(12, 8)
	box.size = Vector2(1250, 194)
	panel.add_child(box)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(1240, 48)
	_status.add_theme_font_size_override("font_size", 15)
	box.add_child(_status)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	box.add_child(row)
	row.add_child(_button("返回", func() -> void: back_requested.emit()))
	row.add_child(_button("暂停", func() -> void: pause_requested.emit()))
	row.add_child(_button("进入餐厅", _enter_restaurant))
	row.add_child(_button("客流面板", _open_board))
	row.add_child(_button("备料", _open_pantry))
	row.add_child(_button("订当前货", _order))
	row.add_child(_button("换一种货", _cycle_goods))
	row.add_child(_button("开关这个区", _toggle_selected))
	row.add_child(_button("SAN-10", func() -> void: _set_status(session.set_san(session.san - 10).message)))
	row.add_child(_button("SAN+10", func() -> void: _set_status(session.set_san(session.san + 10).message)))
	row.add_child(_button("开门-1小时", func() -> void: _set_status(session.shift_open(-1).message)))
	row.add_child(_button("开门+1小时", func() -> void: _set_status(session.shift_open(1).message)))
	row.add_child(_button("收摊-1小时", func() -> void: _set_status(session.shift_close(-1).message)))
	row.add_child(_button("收摊+1小时", func() -> void: _set_status(session.shift_close(1).message)))
	row.add_child(_button("开始营业", func() -> void: _set_status(session.start_service().message)))
	row.add_child(_button("收摊", func() -> void: _set_status(session.end_service().message)))
	row.add_child(_button("去休息", func() -> void: _set_status(session.rest().message)))
	row.add_child(_button("雇/辞保洁", _toggle_cleaner))
	row.add_child(_button("花时间恢复", _visit_selected))
	row.add_child(_button("下一天", func() -> void: _set_status(_day_text(session.advance_day()))))
	row.add_child(_button("选面积", _cycle_size))
	row.add_child(_button("改主店面积", _resize_home))
	row.add_child(_button("在这里划地", _claim_here))
	row.add_child(_button("关掉分店", func() -> void: _set_status(session.close_branch().message)))
	row.add_child(_button("雇备菜", func() -> void: _hire("prep")))
	row.add_child(_button("雇主厨", func() -> void: _hire("chef")))
	row.add_child(_button("雇店长", func() -> void: _hire("manager")))
	row.add_child(_button("教会这道菜", _teach))
	row.add_child(_button("备菜岗动手", func() -> void: _set_status(session.hand_prep().message)))
	row.add_child(_button("主厨出菜", func() -> void: _set_status(session.hand_cook().message)))
	row.add_child(_button("接手", func() -> void: _set_status(session.take_over().message)))
	row.add_child(_button("给分店备货", func() -> void: _set_status(session.stock_branch().message)))
	row.add_child(_button("结算分店", _settle_branch))
	row.add_child(_button("看员工", _inspect_staff))
	row.add_child(_button("工资+1", func() -> void: _change_wage(1)))
	row.add_child(_button("工资-1", func() -> void: _change_wage(-1)))

func _open_board() -> void:
	_close_pantry()
	if _board != null and is_instance_valid(_board):
		_board.queue_free()
	_board = TDEconomyBoard.new()
	_board.session = session
	_board.closed.connect(func() -> void: _board.queue_free())
	add_child(_board)

func _open_pantry() -> void:
	if _board != null and is_instance_valid(_board):
		_board.queue_free()
	_close_pantry()
	_pantry = TDPantryBoard.new()
	_pantry.session = session
	_pantry.closed.connect(_close_pantry)
	add_child(_pantry)

func _close_pantry() -> void:
	if _pantry != null and is_instance_valid(_pantry):
		_pantry.queue_free()
	_pantry = null

func _order() -> void:
	var item := session.current_supply_item()
	var result := session.order_supply(String(item.get("id", "")))
	_set_status(result.message if result.message != "" else result.code)

func _cycle_goods() -> void:
	var item := session.next_supply_item()
	_set_status("改为订%s。" % String(item.get("name", "")))

func _toggle_selected() -> void:
	if _selected.is_empty():
		_set_status("先按E选中一个功能区。")
		return
	var id := String(_selected["id"])
	if id == "player_diner" or id == "plaza" or id == "diner_lot" or String(_selected.get("kind", "")).begins_with("factory") or String(_selected.get("kind", "")) == "supply_factory":
		_set_status("建设区和广场不能这样关掉。")
		return
	var enabled := not bool(session.town_map.plot_at(int(_selected["x"]), int(_selected["y"])).get("enabled", true))
	session.set_zone_enabled(id, enabled)
	_selected = session.town_map.plot_at(int(_selected["x"]), int(_selected["y"]))
	_set_status("%s现在%s客流。" % [String(_selected.get("name", id)), "计入" if enabled else "不计入"])
	queue_redraw()

func _cycle_size() -> void:
	session.claim_size = TDRestaurantSizes.next(session.claim_size)
	var foot := TDRestaurantSizes.footprint(session.claim_size)
	var room := TDRestaurantSizes.interior(session.claim_size)
	_set_status("当前选%s店，地图%d×%d，店内%d×%d。" % [TDRestaurantSizes.name_of(session.claim_size), foot.x, foot.y, room.x, room.y])

func _resize_home() -> void:
	var result := session.resize_home(session.claim_size)
	_set_status(result.message if result.message != "" else result.code)
	queue_redraw()

func _claim_here() -> void:
	var result := session.claim_branch(session.claim_size, _player_cell())
	_set_status(result.message if result.message != "" else result.code)
	queue_redraw()

func _hire(role: String) -> void:
	var store_id := "home"
	if session.branch_open and session.town_id == session.branch_town:
		store_id = "branch"
	var hired := session.employ(role, store_id)
	if hired.code == "ALREADY":
		hired = session.dismiss(role, store_id)
	_set_status(hired.message if hired.message != "" else hired.code)

func _teach() -> void:
	var store_id := "home"
	if session.branch_open and session.town_id == session.branch_town:
		store_id = "branch"
	var taught := session.teach_chef(store_id, session.pantry_dish)
	_set_status(taught.message if taught.message != "" else taught.code)

func _active_store() -> String:
	if session.branch_open and session.town_id == session.branch_town:
		return "branch"
	return "home"

func _inspect_staff() -> void:
	var index := TDPhase3Session.ROLES.find(_staff_role)
	if index < 0:
		index = 0
	_staff_role = TDPhase3Session.ROLES[(index + 1) % TDPhase3Session.ROLES.size()]
	var store_id := _active_store()
	var hired := session.staff_on(_staff_role)
	if store_id == "branch":
		hired = bool(session.branch_staff.get(_staff_role, false))
	if not hired:
		_set_status("%s还没到岗。推荐日薪%d元。" % [session._role_title(_staff_role), session.catalog.wage_of(_staff_role)])
		return
	var card := session.staff_card(store_id, _staff_role)
	_set_status("%s：日薪%d，推荐%d，情绪%d，%s、%s，服务质量%+d。" % [session._role_title(_staff_role), int(card["wage"]), int(card["recommended"]), int(card["mood"]), TDBranchSim.drive_name(String(card["drive"])), TDBranchSim.care_name(String(card["care"])), int(card["shift"])])

func _change_wage(delta: int) -> void:
	var result := session.set_wage(_staff_role, _active_store(), delta)
	_set_status(result.message if result.message != "" else result.code)

func _settle_branch() -> void:
	var result := session.settle_branch()
	if String(result.get("code", "")) == "CLOSED":
		_set_status(String(result.get("events", "分店还没开。")))
		return
	_set_status("第%d天分店：客流%d，卖出%d，收入%d元，工资%d元，损耗%d。%s" % [int(result.get("day", 0)), int(result.get("guests", 0)), int(result.get("served", 0)), int(result.get("revenue", 0)), int(result.get("wages", 0)), int(result.get("waste", 0)), String(result.get("events", ""))])

func _toggle_cleaner() -> void:
	if session.staff_on("cleaner"):
		_set_status(session.dismiss("cleaner").message)
	else:
		var hired := session.employ("cleaner")
		_set_status(hired.message if hired.message != "" else hired.code)

func _visit_selected() -> void:
	if _selected.is_empty():
		_set_status("先按E站到功能区旁边。")
		return
	var result := session.visit_zone(String(_selected["kind"]))
	_set_status(result.message if result.message != "" else result.code)

func _day_text(result: Dictionary) -> String:
	return "进入第%d天。到货%d批，NPC池%d人。" % [int(result["day"]), (result["arrived"] as Array).size(), session.npcs.size()]

func _feet_on_road(at: Vector2) -> bool:
	var cell := _cell_at(at)
	return session != null and session.town_map.is_walkable(cell.x, cell.y)

func _player_cell() -> Vector2i:
	return _cell_at(_player.position)

func _cell_at(at: Vector2) -> Vector2i:
	var local := at - _origin()
	return Vector2i(floori(local.x / CELL), floori(local.y / CELL))

func _origin() -> Vector2:
	return Vector2(300, 24)

func _enter_restaurant() -> void:
	if session == null:
		return
	if session.town_id == session.home_town_id and not session.home_built:
		_set_status("还没有主店。先点击餐厅建设区空地建店。")
		return
	restaurant_requested.emit()

func _click_build(screen_pos: Vector2) -> void:
	if session == null or _player == null:
		return
	var world := get_viewport().get_canvas_transform().affine_inverse() * screen_pos
	var cell := _cell_at(world)
	var plot := session.town_map.plot_at(cell.x, cell.y)
	var kind := String(plot.get("kind", ""))
	if kind == "diner_lot":
		_selected = plot
		_open_venue_choice()
		return
	if kind == "player_diner" and String(plot.get("id", "")) == "player_diner":
		_selected = plot
		_set_status("走到%s上就能进去。" % String(plot.get("name", "餐厅")))
		return
	if kind != "factory_lot":
		if not plot.is_empty() and kind != "housing":
			_selected = plot
			_set_status("选中了%s。建设请点空地；功能区仍可用E。" % String(plot.get("name", kind)))
		return
	_selected = plot
	var result := session.click_build_at(cell)
	_set_status(result.message if result.message != "" else result.code)
	queue_redraw()

func _kind_color(kind: String, enabled: bool) -> Color:
	var color := Color("#888888")
	match kind:
		"diner_lot":
			color = Color("#e08a5a")
		"factory_lot":
			color = Color("#8fbf5a")
		"supply_factory":
			color = Color("#3d7a45")
		"player_diner":
			color = Color("#c45b4a")
		"competitor":
			color = Color("#8d5a3c")
		"market":
			color = Color("#d4a017")
		"urban_village":
			color = Color("#6f8f71")
		"rich_district":
			color = Color("#e6c98a")
		"commercial_street":
			color = Color("#7a1e2b")
		"snack_street":
			color = Color("#e07a3d")
		"amusement":
			color = Color("#3f6f8f")
		"zoo":
			color = Color("#3e5160")
		"landmark":
			color = Color("#6a1b2a")
		"housing":
			color = Color("#9a7b5a")
		_:
			color = Color("#888888")
	if not enabled:
		color = color.darkened(0.45)
	return color

func _enter_hint() -> String:
	if session == null or session.town_map.diner_lot().is_empty():
		return "小镇已进入，但餐厅建设区没生成。看底部栏能否返回。"
	var factories := session.town_map.factory_lots().size()
	return "已进入小镇。点击橙色餐厅建设区，选择中餐厅或西餐厅。建成后只占四分之一，走到店里就能进去。绿色空地%d块可建原料厂。" % factories

func _open_venue_choice() -> void:
	if session == null:
		return
	if session.home_built:
		_set_status("餐厅已经建好。走到店里就能进去。")
		return
	if session.town_id != session.home_town_id:
		_set_status("只能在主小镇的餐厅建设区建店。")
		return
	_close_venue_choice()
	_venue_layer = CanvasLayer.new()
	_venue_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_venue_layer)
	var panel := Panel.new()
	panel.position = Vector2(390, 180)
	panel.size = Vector2(500, 150)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_venue_layer.add_child(panel)
	var box := VBoxContainer.new()
	box.position = Vector2(16, 12)
	box.size = Vector2(468, 126)
	panel.add_child(box)
	var title := Label.new()
	title.text = "在建设区建立哪一类餐厅？初始只占这块地的四分之一。"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	row.add_child(_button("中餐厅", func() -> void: _pick_venue("chinese")))
	row.add_child(_button("西餐厅", func() -> void: _pick_venue("western")))
	row.add_child(_button("取消", _close_venue_choice))

func _pick_venue(venue: String) -> void:
	_close_venue_choice()
	if session == null:
		return
	var result := session.build_venue(venue)
	_set_status(result.message if result.message != "" else result.code)
	queue_redraw()

func _close_venue_choice() -> void:
	if _venue_layer != null and is_instance_valid(_venue_layer):
		_venue_layer.queue_free()
	_venue_layer = null

func _try_enter_diner() -> void:
	if _closed or _entering_diner or session == null or _player == null or get_tree().paused:
		return
	var plot := session.town_map.plot_at(_player_cell().x, _player_cell().y)
	if String(plot.get("id", "")) != "player_diner":
		return
	_entering_diner = true
	_close_venue_choice()
	restaurant_requested.emit()

func _set_status(text: String) -> void:
	if _status != null:
		_status.text = text

func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(110, 32)
	button.pressed.connect(callback)
	return button
