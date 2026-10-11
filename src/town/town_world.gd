class_name TDTownWorld
extends Node2D

signal back_requested
signal pause_requested
signal restaurant_requested

const CELL := 48
const VIEW_ZOOM := 2.4
const BAR_HEIGHT := 160.0

var session: TDPhase3Session
var _player: TDKitchenPlayer
var _camera: Camera2D
var _status: Label
var _selected: Dictionary = {}
var _board: TDEconomyBoard
var _pantry: TDPantryBoard
var _closed: bool = false

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
	sprite.position = Vector2(0, -28)
	_player.add_child(sprite)
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 10.0
	shape.shape = circle
	_player.add_child(shape)
	_player.position = _origin() + Vector2((TDTownMap.CENTER + 0.5) * CELL, (TDTownMap.CENTER + 0.5) * CELL)
	add_child(_player)
	_camera = Camera2D.new()
	_camera.name = "TownCamera"
	_camera.zoom = Vector2(VIEW_ZOOM, VIEW_ZOOM)
	_camera.position_smoothing_enabled = true
	_camera.position_smoothing_speed = 8.0
	_camera.enabled = true
	add_child(_camera)
	_camera.make_current()
	_follow_camera()
	_build_blockers()
	_status_bar()
	_set_status("镜头跟着你走。WASD 沿十字路移动，E 查看路边的整片功能区。")
	queue_redraw()

func _process(_delta: float) -> void:
	_follow_camera()
	queue_redraw()

func _follow_camera() -> void:
	if _player == null or _camera == null:
		return
	var zoom := _camera.zoom
	var view := get_viewport().get_visible_rect().size / zoom
	var map_size := Vector2(TDTownMap.SIZE * CELL, TDTownMap.SIZE * CELL)
	var origin := _origin()
	var half := view * 0.5
	var target := _player.position + Vector2(0, BAR_HEIGHT * 0.5 / zoom.y)
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
		if String(plot["kind"]) == "plaza":
			continue
		var width := int(plot.get("w", 1))
		var height := int(plot.get("h", 1))
		var rect := Rect2(origin + Vector2(int(plot["x"]) * CELL + 2, int(plot["y"]) * CELL + 2), Vector2(width * CELL - 4, height * CELL - 4))
		draw_rect(rect, _kind_color(String(plot["kind"]), bool(plot["enabled"])))
		if String(plot["id"]) == String(_selected.get("id", "")) and String(plot["kind"]) != "housing":
			draw_rect(rect, Color("#f0cc70"), false, 3.0)
		if String(plot["kind"]) == "housing":
			continue
		var font := ThemeDB.fallback_font
		if font != null:
			var at := rect.position + Vector2(6, maxf(18.0, rect.size.y * 0.55))
			draw_string(font, at, "%s  %d×%d" % [String(plot["name"]), width, height], HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 8, 14, Color.WHITE)

func _unhandled_input(event: InputEvent) -> void:
	if _closed or session == null:
		return
	if event.is_action_pressed("pause") and not event.is_echo():
		pause_requested.emit()
		get_viewport().set_input_as_handled()
		return
	if get_tree().paused:
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
		_set_status("旁边没有功能区。广场在十字路口中间。")
		return
	_selected = plot
	var kind := String(plot["kind"])
	if kind == "player_diner":
		_set_status("这是你的餐厅。可以进去布置、迎客和上菜。小镇贴图仍是色块。")
		return
	if kind == "market":
		var item := session.current_supply_item()
		_set_status("市场。下一份可订：%s，%d元。没有加成时明天到。" % [String(item.get("name", "")), int(item.get("cost", 0))])
		return
	if kind == "competitor":
		var names := ""
		if not session.competitors.is_empty():
			var rival: Dictionary = session.competitors[0]
			names = String(rival["name"])
		_set_status("竞品%s。客人会比较你和两家竞品菜单上的每一道菜。" % names)
		return
	var enabled := "计入客流" if bool(plot["enabled"]) else "不计入客流"
	_set_status("%s，%s。人数贡献%d，预算平移%d。" % [String(plot["name"]), enabled, int(plot["pool"]), int(plot["budget_shift"])])

func _build_blockers() -> void:
	var body := StaticBody2D.new()
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
	panel.position = Vector2(0, 640)
	panel.size = Vector2(1280, 160)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(panel)
	var box := VBoxContainer.new()
	box.position = Vector2(12, 8)
	box.size = Vector2(1250, 144)
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
	row.add_child(_button("进入餐厅", func() -> void: restaurant_requested.emit()))
	row.add_child(_button("客流面板", _open_board))
	row.add_child(_button("备料", _open_pantry))
	row.add_child(_button("订当前货", _order))
	row.add_child(_button("换一种货", _cycle_goods))
	row.add_child(_button("开关这个区", _toggle_selected))
	row.add_child(_button("下一天", func() -> void: _set_status(_day_text(session.close_day()))))

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
	if id == "player_diner" or id == "plaza":
		_set_status("餐厅和广场一直都在。")
		return
	var enabled := not bool(session.town_map.plot_at(int(_selected["x"]), int(_selected["y"])).get("enabled", true))
	session.set_zone_enabled(id, enabled)
	_selected = session.town_map.plot_at(int(_selected["x"]), int(_selected["y"]))
	_set_status("%s现在%s客流。" % [String(_selected.get("name", id)), "计入" if enabled else "不计入"])
	queue_redraw()

func _day_text(result: Dictionary) -> String:
	return "进入第%d天。到货%d批，NPC池%d人。" % [int(result["day"]), (result["arrived"] as Array).size(), session.npcs.size()]

func _player_cell() -> Vector2i:
	var local := _player.position - _origin()
	return Vector2i(floori(local.x / CELL), floori(local.y / CELL))

func _origin() -> Vector2:
	return Vector2(300, 24)

func _kind_color(kind: String, enabled: bool) -> Color:
	var color := Color("#888888")
	match kind:
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
