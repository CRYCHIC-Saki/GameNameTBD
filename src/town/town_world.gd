class_name TDTownWorld
extends Node2D

signal back_requested
signal pause_requested
signal restaurant_requested
signal place_requested(kind: String, id: String)
var player_mode: bool = false
var transaction_sink: Callable
var external_factory_clock: bool = false
var balance_reader: Callable
var commercial_refresh: Callable

const CELL := 48
const BAR_HEIGHT := 92.0
const GLASS := Color(0.07, 0.15, 0.30, 0.78)
const GLASS_CARD := Color(0.20, 0.36, 0.62, 0.38)
const GLASS_EDGE := Color(0.74, 0.88, 1.0, 0.48)
const GLASS_INK := Color(0.95, 0.97, 1.0)
const GLASS_MUTED := Color(0.76, 0.86, 0.98, 0.86)
const GLASS_BLUE := Color(0.45, 0.74, 1.0, 0.95)
const GLASS_DIM := Color(0.03, 0.08, 0.18, 0.42)

var session: TDPhase3Session
var _player: TDKitchenPlayer
var _camera: Camera2D
var _status: Label
var _status_panel: Panel
var _selected: Dictionary = {}
var _closed: bool = false
var _blockers: StaticBody2D
var _seen_revision: int = -1
var _venue_layer: CanvasLayer
var _factory_layer: CanvasLayer
var _factory_dim: ColorRect
var _factory_shell: PanelContainer
var _pack_layer: CanvasLayer
var _factory_plot: String = ""
var _factory_rows: Dictionary = {}
var _factory_hover: Label
var _factory_hover_id: String = ""
var _factory_cash: Label
var _factory_time: Label
var _factory_pack: Label
var _pack_button: Button
var _factory_level_label: Label
var _factory_upgrade: Button
var _factory_mill: FactoryMill
var _qty_layer: CanvasLayer
var _qty_item: String = ""
var _qty_line: int = 0
var _qty_count: int = 1
var _qty_summary: Label
var _factory_accent: Color = Color("#ecb36e")
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
	_player.collision_layer = 32
	_player.collision_mask = 16
	_player.directional_art=player_mode
	_player.sprite_height=48.0
	var sprite := Sprite2D.new()
	sprite.name = "Sprite2D"
	sprite.texture = preload("res://assets/kitchen/chef-v1.png") if player_mode else TDRestaurantArt.guest_texture()
	if player_mode: sprite.scale=Vector2(.055,.055)
	_player.add_child(sprite)
	_player.body_lift = 24.0 if player_mode else 0.0
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
	if player_mode: spawn_at_home()
	_set_status(_enter_hint())
	if player_mode: _set_status("WASD 走动 · 面向建筑按 E · 小屋的床可保存/休息 · B 菜谱 · Esc 暂停")
	queue_redraw()

func _process(delta: float) -> void:
	_follow_camera()
	if not player_mode: _try_enter_diner()
	if _closed:
		return
	if session != null and not get_tree().paused:
		var finished: Array = [] if external_factory_clock else session.tick_factories(clampf(delta, 0.0, 0.25))
		for item: Variant in finished:
			var job: Dictionary = item
			_set_status("%s做好了一份，已放入背包，现在有%d。" % [String(job.get("name", "")), int(job.get("stock", 0))])
		if not finished.is_empty() and _factory_cash != null and is_instance_valid(_factory_cash):
			_refresh_factory_panel()
		elif _factory_mill != null and is_instance_valid(_factory_mill):
			_paint_factory_job()
		if not finished.is_empty() and _pack_layer != null and is_instance_valid(_pack_layer):
			_open_backpack()
		_paint_backpack_count()
	if session != null and session.map_revision != _seen_revision:
		_seen_revision = session.map_revision
		if commercial_refresh.is_valid(): commercial_refresh.call()
		_build_blockers()
		_keep_player_on_map()
	queue_redraw()

func _overview_zoom() -> float:
	if player_mode: return 1.0
	var view := get_viewport().get_visible_rect().size
	if view.x < 8.0 or view.y < 8.0:
		return 1.0
	var map_px := float(TDTownMap.SIZE * CELL)
	var usable_height := maxf(1.0, view.y - (80.0 if player_mode else BAR_HEIGHT))
	return maxf(0.05, minf(view.x / map_px, usable_height / map_px) * 0.96 * 2.0)

func _follow_camera() -> void:
	if _player == null or _camera == null:
		return
	var zoom := _overview_zoom()
	_camera.zoom = Vector2(zoom, zoom)
	var view := get_viewport().get_visible_rect().size / zoom
	var map_size := Vector2(TDTownMap.SIZE * CELL, TDTownMap.SIZE * CELL)
	var origin := _origin()
	var half := view * 0.5
	var target := _player.position + Vector2(0, -70 if player_mode else BAR_HEIGHT * 0.5 / zoom)
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
	if player_mode:
		TDTownArt.draw_world(self,session,_selected)
		_draw_economic_places()
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
		elif String(plot.get("supply", "")) != "":
			fill = _supply_color(String(plot.get("supply", "")), String(plot["kind"]) == "supply_factory")
		draw_rect(rect, fill)
		if String(plot["id"]) == String(_selected.get("id", "")) and String(plot["kind"]) != "housing":
			draw_rect(rect, Color("#f0cc70"), false, 3.0)
		if String(plot["kind"]) == "housing":
			continue
		if String(plot["kind"]) == "diner_lot":
			draw_rect(rect, Color("#f4e27a"), false, 3.0)
		var font := ThemeDB.fallback_font
		if font != null:
			var at := rect.position + Vector2(6, maxf(18.0, rect.size.y * 0.55))
			draw_string(font, at, "%s  %d×%d" % [String(plot["name"]), width, height], HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 8, 14, Color.WHITE)
	if session != null:
		var shade := TDSanRules.vignette_alpha(float(session.san))
		if shade > 0.01:
			draw_rect(Rect2(_origin(), Vector2(TDTownMap.SIZE * CELL, TDTownMap.SIZE * CELL)), Color(0, 0, 0, shade))

func _draw_economic_places() -> void:
	for plot: Dictionary in session.town_map.plots:
		if not plot.get("economic_courtyard",false): continue
		var floor_at:=_origin()+Vector2(plot.x,plot.y)*CELL
		for y: int in int(plot.h):
			for x: int in int(plot.w):
				var tile:=Rect2(floor_at+Vector2(x,y)*CELL,Vector2.ONE*CELL)
				draw_rect(tile,Color("a99d7c"));draw_rect(tile.grow(-2),Color("b4a789"))
	for plot: Dictionary in session.town_map.plots:
		if str(plot.kind)=="bank":
			var bank_at:=_origin()+Vector2(plot.x,plot.y)*CELL
			var bank_size:=Vector2(plot.w,plot.h)*CELL
			draw_rect(Rect2(bank_at,bank_size),Color("a98f5e"))
			draw_rect(Rect2(bank_at,Vector2(bank_size.x,14)),Color("514837"))
			draw_rect(Rect2(bank_at+Vector2(bank_size.x*.5-9,bank_size.y-18),Vector2(18,16)),Color("483b2a"))
			draw_rect(Rect2(bank_at+Vector2(0,16),Vector2(bank_size.x,20)),Color("483b2a"))
			draw_string(ThemeDB.fallback_font,bank_at+Vector2(2,31),"钱庄",HORIZONTAL_ALIGNMENT_CENTER,bank_size.x-4,14,Color("f6d88a"))
		if not plot.has("economic_parcel_id"): continue
		var rect:=Rect2(_origin()+Vector2(plot.x,plot.y)*CELL,Vector2(plot.w,plot.h)*CELL).grow(-3)
		var constructing: bool=plot.get("construction",false)
		draw_rect(rect,Color("94744c") if constructing else Color("c5a57d"))
		if constructing:
			for x: int in range(4,int(rect.size.x),12): draw_rect(Rect2(rect.position+Vector2(x,4),Vector2(4,rect.size.y-8)),Color("564b39"))
		else:
			draw_rect(Rect2(rect.position,Vector2(rect.size.x,18)),Color("754937"))
			var door_height:=minf(34,rect.size.y*.42)
			draw_rect(Rect2(rect.position+Vector2(rect.size.x*.5-9,rect.size.y-door_height-2),Vector2(18,door_height)),Color("46392f"))
		var plate:=Rect2(rect.position+Vector2(0,20),Vector2(rect.size.x,22))
		draw_rect(plate,Color("443a2b"))
		draw_string(ThemeDB.fallback_font,plate.position+Vector2(2,16),"施工中" if constructing else ("食堂" if plate.size.x<60 else "街坊食堂"),HORIZONTAL_ALIGNMENT_CENTER,plate.size.x-4,12,Color("f0d392"))

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
			_click_build(mouse)
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
	_close_venue_choice()
	_close_factory_panel()
	_close_backpack()

func _interact() -> void:
	var cell := _player_cell()
	var plot := session.town_map.plot_at(cell.x, cell.y)
	if player_mode:
		plot=facing_plot()
	elif plot.is_empty() or plot.get("economic_courtyard",false):
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var neighbor := session.town_map.plot_at(cell.x + step.x, cell.y + step.y)
			if not neighbor.is_empty() and String(neighbor["kind"]) != "housing" and not neighbor.get("economic_courtyard",false):
				plot = neighbor
				break
	if plot.is_empty():
		_set_status("前方没有可交互建筑。请走近并转向门口或摊贩。")
		return
	_selected = plot
	var kind := String(plot["kind"])
	if player_mode:
		if kind=="player_cottage": place_requested.emit("cottage",str(plot.id));return
		if kind=="player_diner" and String(plot.get("id",""))=="player_diner":
			restaurant_requested.emit()
			return
		if kind=="supply_factory":
			_open_factory_panel(plot)
			return
		if kind=="factory_lot":
			var built := session.click_build_at(Vector2i(int(plot["x"]), int(plot["y"])))
			_set_status(built.message if built.message != "" else built.code)
			queue_redraw()
			return
		if kind=="diner_lot":
			_open_venue_choice()
			return
		place_requested.emit(kind, String(plot.get("id", "")))
		return
	if kind == "diner_lot":
		_set_status("餐厅建设区还是空地。点击这块地，选择中餐厅或西餐厅。")
		return
	if kind == "factory_lot":
		_set_status("%s还是空地。点击后建成，提供%s。" % [String(plot.get("name", "原料厂空地")), TDTownMap.supply_goods(String(plot.get("supply", "")))])
		return
	if kind == "supply_factory":
		_set_status("%s已建成，提供%s。" % [String(plot.get("name", "原料厂")), TDTownMap.supply_goods(String(plot.get("supply", "")))])
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
	body.collision_layer = 16
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
	var view := get_viewport().get_visible_rect().size
	if view.x < 8.0 or view.y < 8.0:
		return
	_status_panel = Panel.new()
	_status_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar := _glass(18)
	bar.set_corner_radius_all(0)
	bar.border_color = Color(0.74, 0.88, 1.0, 0.28)
	_status_panel.add_theme_stylebox_override("panel", bar)
	_status_panel.theme = _glass_theme()
	layer.add_child(_status_panel)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.position = Vector2(16, 8)
	box.size = Vector2(maxf(1.0, view.x - 32.0), BAR_HEIGHT - 16.0)
	_status_panel.add_child(box)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(view.x - 32.0, 28)
	_status.add_theme_font_size_override("font_size", 16)
	_status.add_theme_color_override("font_color", GLASS_INK)
	box.add_child(_status)
	if player_mode:
		_status.text = "WASD 走动 · 面向建筑按 E · 小屋的床可保存/休息 · B 菜谱 · Esc 暂停"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	if not player_mode:
		row.add_child(_button("返回", func() -> void: back_requested.emit()))
	_pack_button = _button("背包 0", _open_backpack)
	row.add_child(_pack_button)
	_paint_backpack_count()
	_place_status_bar()
	if not get_viewport().size_changed.is_connected(_place_status_bar):
		get_viewport().size_changed.connect(_place_status_bar)

func _place_status_bar() -> void:
	if _status_panel == null or not is_instance_valid(_status_panel):
		return
	var view := get_viewport().get_visible_rect().size
	if view.x < 8.0 or view.y < 8.0:
		return
	var bar_h := 70.0 if player_mode else BAR_HEIGHT
	_status_panel.position = Vector2(0, maxf(0.0, view.y - bar_h))
	_status_panel.size = Vector2(view.x, minf(bar_h, view.y))
	var box := _status_panel.get_child(0) as Control
	if box != null:
		box.size = Vector2(maxf(1.0, view.x - 32.0), minf(bar_h, view.y) - 16.0)
	_layout_factory_panel()
	_follow_camera()

func _keep_player_on_map() -> void:
	if _player == null or session == null:
		return
	var cell := _player_cell()
	if session.town_map.is_walkable(cell.x, cell.y):
		return
	var best := Vector2i(TDTownMap.CENTER, TDTownMap.CENTER)
	var distance := INF
	for y: int in TDTownMap.SIZE:
		for x: int in TDTownMap.SIZE:
			if not session.town_map.is_walkable(x, y):
				continue
			var score := Vector2(x, y).distance_squared_to(Vector2(cell))
			if score < distance:
				distance = score
				best = Vector2i(x, y)
	_player.position = _origin() + (Vector2(best) + Vector2(0.5, 0.5)) * CELL
	_player.velocity = Vector2.ZERO

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

func _click_build(mouse: InputEventMouse) -> void:
	if session == null or _player == null:
		return
	var world := _world_from_pointer(mouse)
	var plot := _plot_under(world)
	var kind := String(plot.get("kind", ""))
	if player_mode and str(facing_plot().get("id",""))!=str(plot.get("id","")):
		_selected=plot;_set_status("请走近并面向这栋建筑，再按 E 交互。");queue_redraw();return
	if kind == "diner_lot":
		_selected = plot
		_open_venue_choice()
		return
	if kind == "supply_factory":
		_selected = plot
		_open_factory_panel(plot)
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
	var result := session.click_build_at(Vector2i(int(plot["x"]), int(plot["y"])))
	_set_status(result.message if result.message != "" else result.code)
	queue_redraw()

func _world_from_pointer(_mouse: InputEventMouse) -> Vector2:
	if _camera != null and _camera.has_method("force_update_scroll"):
		_camera.force_update_scroll()
	return get_global_mouse_position()

func _buildable(plot: Dictionary) -> bool:
	var kind := String(plot.get("kind", ""))
	return kind == "factory_lot" or kind == "supply_factory" or kind == "diner_lot" or kind == "player_diner"

func _plot_under(world: Vector2) -> Dictionary:
	if session == null:
		return {}
	var direct := session.town_map.plot_at(_cell_at(world).x, _cell_at(world).y)
	if _buildable(direct):
		return direct
	for item: Variant in session.town_map.plots:
		var plot: Dictionary = item
		var rect := Rect2(_origin() + Vector2(float(int(plot["x"])) * CELL, float(int(plot["y"])) * CELL), Vector2(float(int(plot["w"])) * CELL, float(int(plot["h"])) * CELL))
		if not rect.grow(12.0).has_point(world):
			continue
		if _buildable(plot):
			return plot.duplicate(true)
	return direct

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

func _supply_color(supply: String, built: bool) -> Color:
	return TDTownMap.supply_color(supply, built)

func _enter_hint() -> String:
	if session == null or session.town_map.diner_lot().is_empty():
		return "小镇已进入，但餐厅建设区没生成。看底部栏能否返回。"
	return "已进入小镇。点击橙色餐厅建设区，选择中餐厅或西餐厅。原料厂分四类：金色调料、绿色蔬菜、红色肉类、橙色水果，各两块，点击空地建设。"

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
	panel.theme = _glass_theme()
	var shell := _glass(16)
	panel.add_theme_stylebox_override("panel", shell)
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

func _open_factory_panel(plot: Dictionary) -> void:
	_close_factory_panel()
	_close_backpack()
	_close_venue_choice()
	if session == null:
		return
	var supply := String(plot.get("supply", ""))
	var products := session.factory_products(supply)
	_factory_plot = String(plot.get("id", ""))
	_factory_rows = {}
	_factory_hover_id = ""
	_factory_accent = _supply_color(supply, true)
	var view := get_viewport().get_visible_rect().size
	var panel_size := Vector2(minf(1100.0, view.x - 36.0), minf(620.0, view.y - BAR_HEIGHT - 28.0))
	_factory_layer = CanvasLayer.new()
	_factory_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_factory_layer)
	var dim := ColorRect.new()
	_factory_dim = dim
	dim.color = GLASS_DIM
	dim.size = view
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_factory_dim_input)
	_factory_layer.add_child(dim)
	var panel := PanelContainer.new()
	_factory_shell = panel
	panel.position = Vector2((view.x - panel_size.x) * 0.5, maxf(16.0, (view.y - BAR_HEIGHT - panel_size.y) * 0.45))
	panel.size = panel_size
	panel.custom_minimum_size = panel_size
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.theme = _glass_theme()
	var shell := _glass(18)
	shell.content_margin_left = 22
	shell.content_margin_right = 22
	shell.content_margin_top = 18
	shell.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", shell)
	_factory_layer.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var stripe := ColorRect.new()
	stripe.custom_minimum_size = Vector2(0, 4)
	stripe.color = GLASS_BLUE
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(stripe)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	box.add_child(header)
	var title := Label.new()
	title.text = String(plot.get("name", "原料厂"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_override("font", _glass_font(600))
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", GLASS_INK)
	header.add_child(title)
	_factory_level_label = Label.new()
	_factory_level_label.add_theme_font_size_override("font_size", 16)
	_factory_level_label.add_theme_color_override("font_color", GLASS_BLUE)
	header.add_child(_factory_level_label)
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 8)
	box.add_child(stats)
	_factory_cash = _stat_chip(stats, "现金")
	_factory_time = _stat_chip(stats, "产线")
	_factory_pack = _stat_chip(stats, "背包")
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(body)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_stretch_ratio = 1.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	body.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)
	for item: Variant in products:
		var row_item: Dictionary = item
		grid.add_child(_factory_card(String(row_item.get("id", ""))))
	if products.is_empty(): grid.add_child(TDUI.label("暂无可供货原料\n解锁相关菜谱后会增加品种。",17))
	_factory_hover = Label.new()
	_factory_hover.text = "拖到右侧产线"
	_factory_hover.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_factory_hover.add_theme_font_size_override("font_size", 15)
	_factory_hover.add_theme_color_override("font_color", GLASS_MUTED)
	box.add_child(_factory_hover)
	body.add_child(_factory_status_panel())
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	box.add_child(actions)
	_factory_upgrade = _factory_button("升级厂房", _upgrade_open_factory, _factory_accent, 220)
	actions.add_child(_factory_upgrade)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)
	actions.add_child(_factory_button("关闭", _close_factory_panel, GLASS_BLUE, 120))
	_refresh_factory_panel()

func _stat_chip(parent: Node, caption: String) -> Label:
	var chip := PanelContainer.new()
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := _glass_card(10)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	chip.add_theme_stylebox_override("panel", style)
	parent.add_child(chip)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	chip.add_child(column)
	var cap := Label.new()
	cap.text = caption
	cap.add_theme_font_size_override("font_size", 15)
	cap.add_theme_color_override("font_color", GLASS_MUTED)
	column.add_child(cap)
	var value := Label.new()
	value.add_theme_font_size_override("font_size", 18)
	value.add_theme_color_override("font_color", GLASS_INK)
	column.add_child(value)
	return value

func _factory_card(item_id: String) -> FactoryDrag:
	var card := FactoryDrag.new()
	card.item_id = item_id
	card.item_name = String(session._supply_item(item_id).get("name", item_id))
	card.host = self
	card.custom_minimum_size = Vector2(76, 76)
	card.mouse_entered.connect(_hover_factory_goods.bind(item_id))
	card.mouse_exited.connect(_leave_factory_goods.bind(item_id))
	var style := _glass_card(12)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	card.add_theme_stylebox_override("panel", style)
	var icon := _product_icon(item_id, 64)
	icon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	icon.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_child(icon)
	_factory_rows[item_id] = {"card": card}
	return card

func _hover_factory_goods(item_id: String) -> void:
	_factory_hover_id = item_id
	_paint_factory_row(item_id)

func _leave_factory_goods(item_id: String) -> void:
	if _factory_hover_id != item_id:
		return
	_factory_hover_id = ""
	if _factory_hover != null and is_instance_valid(_factory_hover):
		_factory_hover.text = "拖到右侧产线"
		_factory_hover.add_theme_color_override("font_color", GLASS_MUTED)

func _factory_button(text: String, callback: Callable, _accent: Color, width: int) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(width, 40)
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_color_override("font_color", GLASS_INK)
	button.add_theme_color_override("font_disabled_color", Color(0.78, 0.86, 0.96, 0.55))
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		var bg := Color(0.22, 0.42, 0.74, 0.5)
		var edge := GLASS_EDGE
		if state == "hover":
			bg = Color(0.34, 0.58, 0.92, 0.72)
		elif state == "pressed":
			bg = Color(0.16, 0.34, 0.64, 0.82)
		elif state == "disabled":
			bg = Color(0.14, 0.2, 0.32, 0.35)
			edge = Color(1, 1, 1, 0.12)
		var style := _flat(bg, edge, 10, 1)
		style.content_margin_left = 8
		style.content_margin_right = 8
		style.content_margin_top = 4
		style.content_margin_bottom = 4
		button.add_theme_stylebox_override(state, style)
	button.pressed.connect(callback)
	return button

func _flat(bg: Color, border: Color, radius: int, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	return style

func _glass(radius: int) -> StyleBoxFlat:
	var style := _flat(GLASS, GLASS_EDGE, radius, 1)
	style.shadow_color = Color(0.04, 0.1, 0.24, 0.32)
	style.shadow_size = 18
	style.shadow_offset = Vector2(0, 8)
	return style

func _glass_card(radius: int) -> StyleBoxFlat:
	return _flat(GLASS_CARD, Color(1, 1, 1, 0.18), radius, 1)

func _glass_font(weight: int = 400) -> Font:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "PingFang SC", "Noto Sans CJK SC"])
	font.font_weight = weight
	font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	font.hinting = TextServer.HINTING_LIGHT
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	return font

func _glass_theme() -> Theme:
	var theme := TDUI.theme()
	var body := _glass_font(400)
	theme.default_font = body
	theme.default_font_size = 17
	theme.set_font("font", "Label", body)
	theme.set_font("font", "Button", body)
	theme.set_font_size("font_size", "Label", 17)
	theme.set_font_size("font_size", "Button", 16)
	theme.set_color("font_color", "Label", GLASS_INK)
	theme.set_color("font_color", "Button", GLASS_INK)
	theme.set_constant("line_spacing", "Label", 3)
	return theme

func _on_factory_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			_close_factory_panel()

func _refresh_factory_panel() -> void:
	if session == null or _factory_cash == null or not is_instance_valid(_factory_cash):
		return
	var level := session.factory_level_of(_factory_plot)
	_factory_level_label.text = "%d级 · %d条产线" % [level, session.factory_lines(_factory_plot)]
	_factory_cash.text = "¥%.2f" % (float(balance_reader.call())/100.0) if balance_reader.is_valid() else "%d元" % session.money
	_paint_factory_pack()
	_paint_factory_job()
	if _factory_upgrade != null and is_instance_valid(_factory_upgrade):
		if level >= TDTownMap.FACTORY_LEVEL_MAX:
			_factory_upgrade.text = "厂房已满级"
			_factory_upgrade.disabled = true
		else:
			_factory_upgrade.text = "升级 +1条产线   %d元" % [30 * level]
			_factory_upgrade.disabled = false
	for item_id: Variant in _factory_rows.keys():
		_paint_factory_row(String(item_id))

func _paint_factory_row(item_id: String) -> void:
	var row: Dictionary = _factory_rows.get(item_id, {})
	if row.is_empty():
		return
	var unit := session.factory_quote(item_id)
	var each := session.factory_hours(_factory_plot, item_id, 1)
	var card := row["card"] as Control
	var name := String(session._supply_item(item_id).get("name", item_id))
	var package: String=str(session._supply_item(item_id).get("unit","份"))
	var cost := "%s\n%d元/%s\n%.1f小时/%s" % [name, unit,package, each,package]
	if card != null:
		card.tooltip_text = cost
	if _factory_hover_id == item_id and _factory_hover != null and is_instance_valid(_factory_hover):
		_factory_hover.text = "%s    %d元/%s    %.1f小时/%s" % [name, unit,package, each,package]
		_factory_hover.add_theme_color_override("font_color", GLASS_INK)

func _factory_status_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 2.0
	var style := _glass_card(12)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	var title := Label.new()
	title.text = "正在生产"
	title.add_theme_font_override("font", _glass_font(600))
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", GLASS_INK)
	column.add_child(title)
	_factory_mill = FactoryMill.new()
	_factory_mill.host = self
	_factory_mill.custom_minimum_size = Vector2(0, 220)
	_factory_mill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_factory_mill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_factory_mill)
	return panel

func _paint_factory_job() -> void:
	if session == null or _factory_mill == null or not is_instance_valid(_factory_mill):
		return
	var lines := session.factory_lines(_factory_plot)
	var running := session.factory_running(_factory_plot)
	if _factory_time != null and is_instance_valid(_factory_time):
		_factory_time.text = "%d / %d" % [running.size(), lines]
	var by_line := {}
	for item: Variant in running:
		var loaded: Dictionary = item
		by_line[int(loaded.get("line", 0))] = loaded
	var lanes: Array = []
	for line in lines:
		var number := line + 1
		var job: Dictionary = by_line.get(number, {})
		var unit_hours := float(job.get("unit_hours", 0.0))
		var unit_elapsed := float(job.get("unit_elapsed", 0.0))
		if unit_hours <= 0.001 and not job.is_empty():
			var pieces := maxi(int(job.get("qty", 1)), 1)
			unit_hours = float(job.get("total_hours", 0.0)) / float(pieces)
			unit_elapsed = float(job.get("elapsed_hours", 0.0))
		var ratio := 0.0 if unit_hours <= 0.001 else clampf(unit_elapsed / unit_hours, 0.0, 1.0)
		lanes.append({
			"running": not job.is_empty(),
			"ratio": ratio,
			"left": int(job.get("qty", 0)),
			"item_id": String(job.get("item_id", "")),
		})
	_factory_mill.lanes = lanes
	_paint_factory_pack()

func _paint_factory_pack() -> void:
	_paint_backpack_count()
	if _factory_pack == null or not is_instance_valid(_factory_pack) or session == null:
		return
	var parts: PackedStringArray = []
	for item: Variant in session.factory_goods():
		var row: Dictionary = item
		parts.append("%s×%d" % [String(row.get("name", "")), int(row.get("qty", 0))])
	_factory_pack.text = "空" if parts.is_empty() else "  ".join(parts)
	_factory_pack.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _paint_backpack_count() -> void:
	if _pack_button == null or not is_instance_valid(_pack_button) or session == null:
		return
	var total := 0
	for item: Variant in session.factory_goods():
		total += int((item as Dictionary).get("qty", 0))
	_pack_button.text = "背包 %d" % total

func _ask_factory_qty(line_no: int, item_id: String) -> void:
	if session == null or item_id == "":
		return
	for item: Variant in session.factory_running(_factory_plot):
		var job: Dictionary = item
		if int(job.get("line", 0)) == line_no:
			_set_status("产线%d正在生产%s。" % [line_no, String(job.get("name", ""))])
			return
	_close_qty_dialog()
	_qty_item = item_id
	_qty_line = line_no
	_qty_count = TDTownMap.FACTORY_QTY_MIN
	var view := get_viewport().get_visible_rect().size
	_qty_layer = CanvasLayer.new()
	_qty_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	_qty_layer.layer = 20
	add_child(_qty_layer)
	var dim := ColorRect.new()
	dim.color = GLASS_DIM
	dim.size = view
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_qty_layer.add_child(dim)
	var panel := PanelContainer.new()
	var panel_size := Vector2(420, 220)
	panel.position = Vector2((view.x - panel_size.x) * 0.5, (view.y - BAR_HEIGHT - panel_size.y) * 0.45)
	panel.size = panel_size
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.theme = _glass_theme()
	var shell := _glass(16)
	shell.content_margin_left = 20
	shell.content_margin_right = 20
	shell.content_margin_top = 16
	shell.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", shell)
	_qty_layer.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var name := String(session._supply_item(item_id).get("name", item_id))
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 10)
	heading.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(heading)
	heading.add_child(_product_icon(item_id, 40))
	var title := Label.new()
	title.text = "产线%d 生产%s" % [line_no, name]
	title.add_theme_font_override("font", _glass_font(600))
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", GLASS_INK)
	heading.add_child(title)
	var stepper := HBoxContainer.new()
	stepper.add_theme_constant_override("separation", 8)
	stepper.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(stepper)
	stepper.add_child(_factory_button("−", _lower_factory_qty, GLASS_BLUE, 48))
	var count := Label.new()
	count.name = "QtyCount"
	count.custom_minimum_size = Vector2(48, 0)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count.add_theme_font_size_override("font_size", 22)
	count.add_theme_color_override("font_color", GLASS_INK)
	stepper.add_child(count)
	stepper.add_child(_factory_button("+", _raise_factory_qty, GLASS_BLUE, 48))
	_qty_summary = Label.new()
	_qty_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_qty_summary.add_theme_font_size_override("font_size", 16)
	_qty_summary.add_theme_color_override("font_color", GLASS_MUTED)
	box.add_child(_qty_summary)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	box.add_child(actions)
	actions.add_child(_factory_button("确定", _confirm_factory_qty, GLASS_BLUE, 120))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)
	actions.add_child(_factory_button("取消", _close_qty_dialog, GLASS_BLUE, 120))
	_paint_qty_dialog()

func _raise_factory_qty() -> void:
	_qty_count = mini(_qty_count + 1, TDTownMap.FACTORY_QTY_MAX)
	_paint_qty_dialog()

func _lower_factory_qty() -> void:
	_qty_count = maxi(_qty_count - 1, TDTownMap.FACTORY_QTY_MIN)
	_paint_qty_dialog()

func _paint_qty_dialog() -> void:
	if _qty_layer == null or not is_instance_valid(_qty_layer) or session == null:
		return
	var count := _qty_layer.find_child("QtyCount", true, false) as Label
	if count != null:
		count.text = str(_qty_count)
	if _qty_summary != null and is_instance_valid(_qty_summary):
		var unit := session.factory_quote(_qty_item)
		var each := session.factory_hours(_factory_plot, _qty_item, 1)
		var package: String=str(session._supply_item(_qty_item).get("unit","份"))
		_qty_summary.text = "共%d%s，%d元。每%s%.1f小时，完成后送入库存。" % [_qty_count,package,unit * _qty_count,package,each]

func _confirm_factory_qty() -> void:
	if session == null:
		return
	var result: TDOutcome = transaction_sink.call(session.produce_factory.bind(_factory_plot, _qty_item, _qty_count, _qty_line),"工厂生产") if transaction_sink.is_valid() else session.produce_factory(_factory_plot, _qty_item, _qty_count, _qty_line)
	_set_status(result.message if result.message != "" else result.code)
	_close_qty_dialog()
	_refresh_factory_panel()

func _close_qty_dialog() -> void:
	if _qty_layer != null and is_instance_valid(_qty_layer):
		_qty_layer.queue_free()
	_qty_layer = null
	_qty_summary = null

func _upgrade_open_factory() -> void:
	var result: TDOutcome = transaction_sink.call(session.upgrade_factory.bind(_factory_plot),"工厂升级") if transaction_sink.is_valid() else session.upgrade_factory(_factory_plot)
	_set_status(result.message if result.message != "" else result.code)
	_refresh_factory_panel()

func _layout_factory_panel() -> void:
	if _factory_layer == null or not is_instance_valid(_factory_layer):
		return
	var view := get_viewport().get_visible_rect().size
	if view.x < 8.0 or view.y < 8.0:
		return
	if _factory_dim != null and is_instance_valid(_factory_dim):
		_factory_dim.size = view
	if _factory_shell != null and is_instance_valid(_factory_shell):
		var panel_size := Vector2(minf(1100.0, maxf(320.0, view.x - 36.0)), minf(620.0, maxf(240.0, view.y - BAR_HEIGHT - 28.0)))
		_factory_shell.custom_minimum_size = panel_size
		_factory_shell.size = panel_size
		_factory_shell.position = Vector2((view.x - panel_size.x) * 0.5, maxf(16.0, (view.y - BAR_HEIGHT - panel_size.y) * 0.45))

func _close_factory_panel() -> void:
	if _factory_layer != null and is_instance_valid(_factory_layer):
		_factory_layer.queue_free()
	_factory_layer = null
	_factory_dim = null
	_factory_shell = null
	_factory_rows = {}
	_factory_hover = null
	_factory_hover_id = ""
	_factory_cash = null
	_factory_time = null
	_factory_pack = null
	_factory_level_label = null
	_factory_upgrade = null
	_factory_mill = null
	_close_qty_dialog()

func _open_backpack() -> void:
	_close_backpack()
	_close_factory_panel()
	_close_venue_choice()
	if session == null:
		return
	var view := get_viewport().get_visible_rect().size
	_pack_layer = CanvasLayer.new()
	_pack_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_pack_layer)
	var dim := ColorRect.new()
	dim.color = GLASS_DIM
	dim.size = view
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_pack_dim_input)
	_pack_layer.add_child(dim)
	var panel := PanelContainer.new()
	var panel_size := Vector2(640, 520)
	panel.position = Vector2((view.x - panel_size.x) * 0.5, 48)
	panel.size = panel_size
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.theme = _glass_theme()
	var shell := _glass(18)
	shell.content_margin_left = 22
	shell.content_margin_right = 22
	shell.content_margin_top = 18
	shell.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", shell)
	_pack_layer.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title := Label.new()
	title.text = "背包"
	title.add_theme_font_override("font", _glass_font(600))
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", GLASS_INK)
	box.add_child(title)
	var note := Label.new()
	note.text = "这里是已经生产完成的一级原料。"
	note.add_theme_font_size_override("font_size", 15)
	note.add_theme_color_override("font_color", GLASS_MUTED)
	box.add_child(note)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 360)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)
	var goods := session.factory_goods()
	if goods.is_empty():
		var empty := Label.new()
		empty.text = "背包是空的。原料厂做完的货会放进这里。"
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_color_override("font_color", GLASS_MUTED)
		list.add_child(empty)
	else:
		var grouped := {"seasoning": [], "vegetable": [], "meat": [], "fruit": []}
		for item: Variant in goods:
			var row: Dictionary = item
			var supply := String(row.get("supply", ""))
			if grouped.has(supply):
				(grouped[supply] as Array).append(row)
		for supply_id: String in ["seasoning", "vegetable", "meat", "fruit"]:
			var rows: Array = grouped[supply_id]
			if rows.is_empty():
				continue
			var head := Label.new()
			var label := TDTownMap.supply_name(supply_id, true)
			if label.ends_with("厂"):
				label = label.substr(0, label.length() - 1)
			head.text = label
			head.add_theme_font_size_override("font_size", 18)
			head.add_theme_color_override("font_color", _supply_color(supply_id, true))
			list.add_child(head)
			for item: Variant in rows:
				var row: Dictionary = item
				var line := HBoxContainer.new()
				line.add_theme_constant_override("separation", 8)
				line.alignment = BoxContainer.ALIGNMENT_CENTER
				list.add_child(line)
				line.add_child(_product_icon(String(row.get("id", "")), 32))
				var caption := Label.new()
				caption.text = "%s    ×%d" % [String(row.get("name", "")), int(row.get("qty", 0))]
				caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				caption.add_theme_font_size_override("font_size", 16)
				caption.add_theme_color_override("font_color", GLASS_INK)
				line.add_child(caption)
	var actions := HBoxContainer.new()
	box.add_child(actions)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)
	actions.add_child(_factory_button("关闭", _close_backpack, GLASS_BLUE, 120))

func _on_pack_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			_close_backpack()

func _close_backpack() -> void:
	if _pack_layer != null and is_instance_valid(_pack_layer):
		_pack_layer.queue_free()
	_pack_layer = null

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

func _product_icon(item_id: String, side: int) -> FactoryIcon:
	var icon := FactoryIcon.new()
	icon.item_id = item_id
	icon.custom_minimum_size = Vector2(side, side)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon

func _button(text: String, callback: Callable) -> Button:
	var button := _factory_button(text, callback, GLASS_BLUE, 110)
	button.custom_minimum_size = Vector2(110, 36)
	return button

func set_presented(value: bool) -> void:
	visible = value
	if _camera != null:
		_camera.enabled = value
		if value:
			_camera.make_current()
	if _player != null:
		_player.set_controls_enabled(value)
	for child: Node in get_children():
		if child is CanvasLayer:
			child.visible = value
	set_process_unhandled_input(value)

func spawn_at_home() -> void:
	spawn_at_plot("player_diner")

func facing_plot() -> Dictionary:
	var cell:=_player_cell()+_player.facing
	var target:=session.town_map.plot_at(cell.x,cell.y)
	if target.get("economic_courtyard",false) or target.get("kind","")=="housing": return {}
	return target

func spawn_at_plot(identity:String) -> void:
	if session == null or _player == null:
		return
	var home: Dictionary = session._plot_by_id(identity)
	if home.is_empty():
		return
	var goal := Vector2i(int(home.x) + int(home.w) / 2, int(home.y) + int(home.h))
	var best := Vector2i(TDTownMap.CENTER, TDTownMap.CENTER)
	var distance: float = INF
	for y: int in TDTownMap.SIZE:
		for x: int in TDTownMap.SIZE:
			if not session.town_map.is_road(x, y):
				continue
			var at := Vector2i(x, y)
			var score := Vector2(at).distance_squared_to(Vector2(goal))
			if score < distance:
				best = at
				distance = score
	_player.position = _origin() + (Vector2(best) + Vector2(0.5, 0.5)) * CELL
	if identity=="player_cottage":
		_player.position=_origin()+(Vector2(home.approach_x,home.approach_y)+Vector2(.5,.5))*CELL
	_player.face(_origin()+Vector2(home.x+home.w*.5,home.y+home.h*.5)*CELL-_player.position)
	_player.velocity = Vector2.ZERO
	_follow_camera()

class FactoryMill extends Control:
	var phase: float = 0.0
	var lanes: Array = []
	var host: TDTownWorld

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		mouse_filter = Control.MOUSE_FILTER_STOP
		clip_contents = true

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return data is Dictionary and String((data as Dictionary).get("item_id", "")) != ""

	func _drop_data(at: Vector2, data: Variant) -> void:
		if host == null:
			return
		host._ask_factory_qty(_lane_at(at.y), String((data as Dictionary).get("item_id", "")))

	func _lane_at(y: float) -> int:
		var count := maxi(lanes.size(), 1)
		var lane_h := maxf(1.0, (size.y - 36.0) / float(count))
		return clampi(int((y - 22.0) / lane_h), 0, count - 1) + 1

	func _process(delta: float) -> void:
		if _moving() and get_tree() != null and not get_tree().paused:
			phase += delta
		queue_redraw()

	func _moving() -> bool:
		for item: Variant in lanes:
			if bool((item as Dictionary).get("running", false)):
				return true
		return false

	func _draw() -> void:
		var bounds := size
		if bounds.x < 16.0 or bounds.y < 16.0:
			return
		draw_rect(Rect2(Vector2.ZERO, bounds), Color(0.05, 0.1, 0.18, 0.72))
		_draw_machine(bounds)
		_draw_belts(bounds)

	func _draw_machine(bounds: Vector2) -> void:
		var moving := _moving()
		var body := Rect2(18, 36, 78, bounds.y - 58)
		draw_rect(body, Color(0.13, 0.24, 0.4, 0.95))
		draw_rect(Rect2(18, 36, 78, 8), Color(0.45, 0.68, 0.92, 0.85))
		var lift := 0.0
		if moving:
			lift = sin(phase * 2.4) * 10.0
		draw_rect(Rect2(48, 16 + lift, 18, 22), Color(0.72, 0.86, 1.0, 0.9))
		draw_line(Vector2(57, 38 + lift), Vector2(57, body.position.y + 18), Color(0.75, 0.88, 1.0, 0.7), 3.0)
		var center := Vector2(57, body.position.y + body.size.y * 0.55)
		var spin := 0.0
		if moving:
			spin = phase * 1.8
		draw_circle(center, 16, Color(0.28, 0.48, 0.72, 1.0))
		for tooth in 8:
			var angle := spin + float(tooth) * TAU / 8.0
			var dir := Vector2(cos(angle), sin(angle))
			draw_line(center + dir * 12.0, center + dir * 24.0, Color(0.78, 0.9, 1.0, 0.95), 4.0)
		draw_circle(center, 5, Color(0.08, 0.14, 0.22, 1.0))
		if moving:
			for puff in 3:
				var rise := fmod(phase * 28.0 + float(puff) * 16.0, 42.0)
				var alpha := 1.0 - rise / 42.0
				draw_circle(Vector2(86, 28 - rise), 3.0 + float(puff), Color(0.8, 0.9, 1.0, alpha * 0.45))

	func _draw_belts(bounds: Vector2) -> void:
		var count := maxi(lanes.size(), 1)
		var left := 112.0
		var right := bounds.x - 16.0
		var top := 22.0
		var lane_h := (bounds.y - 36.0) / float(count)
		var font := ThemeDB.fallback_font
		for index in count:
			var lane: Dictionary = lanes[index] if index < lanes.size() else {}
			var running := bool(lane.get("running", false))
			var y := top + lane_h * float(index) + lane_h * 0.62
			var belt_w := maxf(40.0, right - left)
			var queued := 0
			if running:
				queued = maxi(int(lane.get("left", 0)) - 1, 0)
			var gap := 4.0
			var box_w := 22.0
			if queued > 0:
				box_w = minf(22.0, (belt_w * 0.42 - gap * float(queued)) / float(queued))
				box_w = maxf(14.0, box_w)
			var track_h := 26.0
			var line_no := index + 1
			var remain := int(lane.get("left", 0))
			var left_w := 108.0
			var belt_rect: Rect2 = Rect2(left, y - track_h * 0.5, belt_w, track_h)
			draw_rect(belt_rect, Color(0.04, 0.08, 0.14, 0.98))
			draw_rect(Rect2(belt_rect.position, Vector2(belt_w, 2.0)), Color(0.82, 0.92, 1.0, 0.7))
			draw_rect(Rect2(Vector2(left, y + track_h * 0.5 - 2.0), Vector2(belt_w, 2.0)), Color(0.82, 0.92, 1.0, 0.7))
			draw_string(font, Vector2(left, y - track_h * 0.5 - 4.0), "产线 %d" % line_no, HORIZONTAL_ALIGNMENT_LEFT, left_w, 16, Color(0.82, 0.9, 1.0, 0.9))
			var goods := String(lane.get("item_id", ""))
			if not running:
				draw_string(font, Vector2(left + left_w + 12.0, y + 7.0), "拖到这里", HORIZONTAL_ALIGNMENT_LEFT, belt_w - left_w - 24.0, 16, Color(0.76, 0.86, 0.98, 0.55))
				continue
			var ratio := clampf(float(lane.get("ratio", 0.0)), 0.0, 1.0)
			var badge_w := 72.0
			var fill_left := left + left_w
			var fill_room := maxf(24.0, belt_w - left_w - badge_w)
			var fill_w := fill_room * ratio
			if fill_w > 1.0:
				draw_rect(Rect2(fill_left, y - track_h * 0.5, fill_w, track_h), Color(0.22, 0.62, 1.0, 0.96))
				draw_rect(Rect2(fill_left, y - track_h * 0.5, fill_w, 5.0), Color(0.9, 0.97, 1.0, 0.95))
				draw_line(Vector2(fill_left + fill_w, y - track_h * 0.5), Vector2(fill_left + fill_w, y + track_h * 0.5), Color(1, 1, 1, 1), 4.0)
			var qx := fill_left + 8.0
			var queue_limit := fill_left + fill_room - 8.0
			for _box in queued:
				if qx + box_w > queue_limit:
					break
				FactoryIcon.draw_on(self, goods, Rect2(qx, y - box_w - 18.0, box_w, box_w))
				qx += box_w + gap
			var travel_left := fill_left + 8.0
			var span := maxf(20.0, fill_room - 44.0)
			var box_x := travel_left + span * ratio
			FactoryIcon.draw_on(self, goods, Rect2(box_x, y - 44.0, 34.0, 34.0))
			var waiting := Rect2(left, y - track_h * 0.5, left_w, track_h)
			draw_rect(waiting, Color(0.1, 0.24, 0.46, 1.0))
			draw_string(font, Vector2(waiting.position.x, y + 8.0), "还剩 %d" % remain, HORIZONTAL_ALIGNMENT_CENTER, left_w, 20, Color(0.97, 0.99, 1.0, 1.0))
			var badge := Rect2(fill_left + fill_room, y - track_h * 0.5, badge_w, track_h)
			draw_rect(badge, Color(0.08, 0.16, 0.3, 1.0))
			draw_string(font, Vector2(badge.position.x, y + 8.0), "%d%%" % int(round(ratio * 100.0)), HORIZONTAL_ALIGNMENT_CENTER, badge_w, 20, Color(0.95, 0.98, 1.0, 1.0))

class FactoryDrag extends PanelContainer:
	var item_id: String = ""
	var item_name: String = ""
	var host: TDTownWorld

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _get_drag_data(_at: Vector2) -> Variant:
		var preview := FactoryIcon.new()
		preview.item_id = item_id
		preview.custom_minimum_size = Vector2(48, 48)
		preview.size = Vector2(48, 48)
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_drag_preview(preview)
		return {"item_id": item_id}

class FactoryIcon extends TDIngredientIcon:
	pass
