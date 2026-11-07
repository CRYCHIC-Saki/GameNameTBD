class_name TDKitchenWorld
extends Node2D

## Composition owns cooking UI: this world only publishes a station identity.
signal cooking_requested(station_id: String)
signal station_action(station_id: String, action: String)
signal back_requested
signal dining_requested

const STATIONS: Array[Dictionary] = [
	{"id":"kitchen.supply.tomato", "position":Vector2(170,290), "visual":Vector2(170,173), "name":"番茄", "kind":"supply"},
	{"id":"kitchen.supply.egg", "position":Vector2(345,290), "visual":Vector2(345,173), "name":"鸡蛋", "kind":"supply"},
	{"id":"kitchen.board", "position":Vector2(930,290), "visual":Vector2(930,173), "name":"砧板", "kind":"board"},
	{"id": "kitchen.stove.left", "position": Vector2(588.0, 275.0), "name": "左灶台"},
	{"id": "kitchen.stove.right", "position": Vector2(693.0, 275.0), "name": "右灶台"},
	{"id":"kitchen.steamer", "position":Vector2(805,290), "visual":Vector2(805,173), "name":"蒸笼", "kind":"steamer"},
	{"id":"kitchen.supply.beef", "position":Vector2(1070,290), "visual":Vector2(1070,173), "name":"炖煮食材", "kind":"supply"},
	{"id":"kitchen.serve", "position":Vector2(1040,635), "visual":Vector2(1040,560), "name":"出餐台", "kind":"serve"},
]
const INTERACTION_RADIUS: float = 88.0
const DOOR_POS := Vector2(640, 700)
# Wooden leaves fill the doorway already painted on the kitchen background. The old mark was a flat outline on the floor.
const SERVICE_DOOR_RECT := Rect2(556, 724, 176, 64)
var service_door: bool = false
var day_minute: float=720.0

func set_day_minute(value: float) -> void:
	day_minute=value
	self_modulate=TDDaylight.sample(value,true).tint
	if _player!=null: _player.modulate=self_modulate
	if has_node("Background"): $Background.modulate=self_modulate
var _controls_enabled: bool = true
var _player: TDKitchenPlayer
var _prompt: Label
var _back_button: Button
var _hud: Control
var _context: Dictionary = {}
var _message: String = ""
var _held_label: Label
var _simmer_label: Label
var _near_prompt: Label
var simmer_meters: Array=[]
var station_names: Dictionary={}
var single_fridge: bool = false
var pot_contents: Array=[]
var crew: TDRestaurantCrew
const CHEF_SPRITE := preload("res://assets/kitchen/chef-v1.png")
const COOK_POSTS: Array[Vector2] = [Vector2(640, 400), Vector2(850, 400)]
var _staff_nodes: Array[Node2D] = []
var _crew_time: float = 0.0
var order_shop: TDShopSession

func stations() -> Array[Dictionary]:
	if not single_fridge: return STATIONS.duplicate(true)
	var result: Array[Dictionary]=[]
	result.append({"id":"kitchen.fridge","position":Vector2(200,330),"visual":Vector2(200,270),"name":"大冰箱","kind":"fridge"})
	result.append({"id":"kitchen.trash","position":Vector2(310,590),"visual":Vector2(245,585),"name":"垃圾桶","kind":"trash"})
	for station: Dictionary in STATIONS:
		if station.get("kind")!="supply":
			var item:=station.duplicate(true)
			var columns: Dictionary={"kitchen.board":420.0,"kitchen.stove.left":640.0,"kitchen.stove.right":850.0,"kitchen.steamer":1060.0}
			if columns.has(item.id): item.position=Vector2(columns[item.id],330);item.visual=Vector2(columns[item.id],270)
			result.append(item)
	return result


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_player = $Player as TDKitchenPlayer
	$Background.z_index = -10
	$Background.scale=Vector2(1280.0/$Background.texture.get_width(),800.0/$Background.texture.get_height())
	_player.z_index = 1
	_make_hud()
	_hud.z_index=2
	_near_prompt=TDUI.label("[ E ]",20,TDUI.ORANGE); _near_prompt.size=Vector2(72,30); _near_prompt.autowrap_mode=TextServer.AUTOWRAP_OFF; _near_prompt.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; _hud.add_child(_near_prompt)
	for station: Dictionary in stations():
		var label := TDUI.label(str(station_names.get(station.id,station.name)), 16, TDUI.ORANGE)
		label.position = (station.get("visual",station.position+Vector2(0,-120)) as Vector2) + Vector2(-60,8)
		label.size = Vector2(120,28); label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_hud.add_child(label)
		if station.get("kind") == "serve":
			var body := StaticBody2D.new(); body.name="ServingCounter"; body.position = Vector2(1040,565)
			var collider := CollisionShape2D.new(); var shape := RectangleShape2D.new(); shape.size = Vector2(232,102); collider.shape = shape
			body.add_child(collider); add_child(body)
	_update_prompt()

func _process(delta: float) -> void:
	if is_inside_tree() and not get_tree().paused:
		_crew_time += delta
	_update_prompt()
	_sync_staff()
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if not _controls_enabled or not is_visible_in_tree() or get_tree().paused:
		return
	if single_fridge and not event.is_echo():
		for action: String in ["open","retrieve"]:
			if event.is_action_pressed("world_"+action) and interaction_available():
				var id: String=str(_station_at_player().id)
				set_controls_enabled(false); station_action.emit(id,action)
				get_viewport().set_input_as_handled(); return
	if event.is_action_pressed("world_interact") and not event.is_echo():
		if request_interaction():
			get_viewport().set_input_as_handled()

func set_controls_enabled(enabled: bool) -> void:
	_controls_enabled = enabled
	if is_instance_valid(_player):
		_player.set_controls_enabled(enabled)
	if is_instance_valid(_back_button):
		_back_button.disabled = not enabled
	_update_prompt()

func interaction_available() -> bool:
	return _controls_enabled and is_visible_in_tree() and is_inside_tree() and not get_tree().paused and not _station_at_player().is_empty()

func player_position() -> Vector2:
	return _player.position if is_instance_valid(_player) else Vector2.ZERO

func set_return_visible(value: bool) -> void:
	if is_instance_valid(_back_button): _back_button.visible=value

func set_return_label(text: String) -> void:
	if is_instance_valid(_back_button):
		_back_button.text = text

func request_interaction() -> bool:
	if not interaction_available():
		return false
	var station := _station_at_player()
	if String(station.get("id", "")) == "kitchen.dining":
		dining_requested.emit()
		return true
	set_controls_enabled(false)
	cooking_requested.emit(String(station["id"]))
	return true

func close() -> void:
	set_controls_enabled(false)
	set_process(false)
	set_process_unhandled_input(false)

func _exit_tree() -> void:
	if is_instance_valid(_player):
		_player.set_controls_enabled(false)

func station_bounds(station: Dictionary) -> Rect2:
	if not single_fridge: return Rect2(station.position,Vector2.ZERO)
	if station.id=="kitchen.dining": return Rect2(DOOR_POS-Vector2(44,12),Vector2(88,24))
	if station.id=="kitchen.serve": return Rect2(924,514,232,102)
	if station.id=="kitchen.trash": return Rect2(205,515,80,70)
	var x: float=float(station.position.x)
	var half_width: float=110 if station.id=="kitchen.fridge" else 90
	return Rect2(x-half_width,200,half_width*2,80)

func _station_at_player() -> Dictionary:
	if not is_instance_valid(_player):
		return {}
	var best: Dictionary = {}
	var shortest: float = 96.0 if single_fridge else INTERACTION_RADIUS
	if service_door and is_instance_valid(_player):
		var door_distance := TDInteractionRange.distance(_player.position,Rect2(DOOR_POS-Vector2(44,12),Vector2(88,24)))
		if door_distance <= shortest:
			shortest = door_distance
			best = {"id": "kitchen.dining", "position": DOOR_POS, "name": "餐厅门口", "visual": DOOR_POS + Vector2(0, -80)}
	for station: Dictionary in stations():
		var distance: float = TDInteractionRange.distance(_player.position,station_bounds(station))
		if distance <= shortest:
			shortest = distance
			best = station
	return best

func _update_prompt() -> void:
	if not is_instance_valid(_prompt):
		return
	var station := _station_at_player()
	var station_id := String(station.get("id", ""))
	if _near_prompt != null:
		_near_prompt.visible = _controls_enabled and not station_id.is_empty()
		if not station_id.is_empty(): _near_prompt.position=(station.get("visual",station.position-Vector2(0,120)) as Vector2)+Vector2(-36,-70)
	if not _controls_enabled:
		_prompt.text = "正在灶台做菜 · 关闭做菜界面后继续走动"
	elif not station_id.is_empty():
		_prompt.text = "[ E ]  %s · %s" % [String(station["name"]), _station_hint(station_id)]
	else:
		_prompt.text = "WASD 移动 · Shift 疾跑 · E 取放 · F 开灶台 · Q 取锅内材料" if single_fridge else "WASD / 方向键走动 · Shift 疾跑 · E 拿取 / 放下 / 操作 · 先去左上方拿食材"

func _make_hud() -> void:
	_hud = Control.new()
	_hud.name = "KitchenHUD"
	_hud.theme = TDUI.theme()
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_hud)
	var heading := TDUI.label("小镇食堂  /  厨房", 24)
	heading.position = Vector2(28.0, 16.0)
	heading.size = Vector2(350.0, 36.0)
	heading.add_theme_color_override("font_shadow_color", Color("#172724"))
	heading.add_theme_constant_override("shadow_offset_x", 2)
	heading.add_theme_constant_override("shadow_offset_y", 2)
	_hud.add_child(heading)
	_held_label = TDUI.label("手上：空", 18, TDUI.ORANGE); _held_label.position = Vector2(28,60); _held_label.size = Vector2(900,30); _hud.add_child(_held_label)
	_simmer_label = TDUI.label("",16); _simmer_label.position = Vector2(28,588); _simmer_label.size = Vector2(540,44); _hud.add_child(_simmer_label)
	_back_button = TDUI.button("返回主界面", _back)
	_back_button.position = Vector2(1070.0, 14.0)
	_back_button.size = Vector2(182.0, 50.0)
	_hud.add_child(_back_button)
	var bar := Panel.new()
	bar.position = Vector2(215.0, 731.0)
	bar.size = Vector2(850.0, 52.0)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.15, 0.14, 0.94)
	style.border_color = TDUI.ORANGE
	style.set_border_width_all(2)
	bar.add_theme_stylebox_override("panel", style)
	_hud.add_child(bar)
	_prompt = TDUI.label("", 20)
	_prompt.position = Vector2(18.0, 11.0)
	_prompt.size = Vector2(816.0, 30.0)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar.add_child(_prompt)
	var note := TDUI.label("像素场景原型 · 美术与动作可继续迭代", 14)
	note.position = Vector2(28.0, 776.0)
	note.size = Vector2(420.0, 23.0)
	_hud.add_child(note)

func _back() -> void:
	if _controls_enabled:
		close()
		back_requested.emit()

func set_context(value: Dictionary, message: String = "", simmer: String = "") -> void:
	_context = value.duplicate(true)
	if not message.is_empty(): _message = message
	if _held_label != null:
		var hand: Dictionary = _context.get("hand",{})
		_held_label.text = "手上：" + ("空" if hand.is_empty() else str(hand.name) + " · " + {"whole":"完整","slice":"片","strip":"条","chunk":"块","dice":"丁"}.get(hand.shape,hand.shape)) + "     " + _message
	if _simmer_label != null: _simmer_label.text = simmer
	queue_redraw()

static func cook_point(index: int, _time_sec: float) -> Vector2:
	return COOK_POSTS[index % COOK_POSTS.size()]

func _sync_staff() -> void:
	var wanted: Array[Dictionary] = []
	if crew != null:
		var cooks := crew.cooks()
		for index: int in cooks.size():
			var cook: Dictionary = cooks[index]
			var work := ""
			if order_shop != null:
				work = order_shop.crew_work(str(cook.id))
			var caption := "厨师 %s %d级" % [String(cook["name"]), int(cook.get("level", 1))]
			if work != "":
				caption = "厨师 %s %s" % [String(cook["name"]), work]
			wanted.append({"caption": caption, "at": cook_point(index, _crew_time), "color": Color("#c46a3a"), "work": work})
	while _staff_nodes.size() < wanted.size():
		var root := Node2D.new()
		var sprite := Sprite2D.new()
		sprite.name = "Body"
		sprite.texture = CHEF_SPRITE
		sprite.centered = true
		sprite.position = Vector2(0, -47)
		sprite.scale = Vector2(0.07, 0.07)
		root.add_child(sprite)
		var caption := Label.new()
		caption.name = "Name"
		caption.theme = TDUI.theme()
		caption.position = Vector2(-60, -102)
		caption.size = Vector2(120, 24)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.add_theme_font_size_override("font_size", 14)
		root.add_child(caption)
		root.name = "Cook%d" % _staff_nodes.size()
		add_child(root)
		_staff_nodes.append(root)
	while _staff_nodes.size() > wanted.size():
		var extra: Node2D = _staff_nodes.pop_back()
		extra.queue_free()
	for index: int in wanted.size():
		var info: Dictionary = wanted[index]
		var root: Node2D = _staff_nodes[index]
		var body := root.get_node("Body") as Sprite2D
		if not root.has_meta("placed"):
			root.position = info.at
			root.set_meta("placed", true)
		var step_x := float(info.at.x) - root.position.x
		root.position = info.at
		root.z_index = 1
		if step_x < -0.4:
			body.flip_h = true
		elif step_x > 0.4:
			body.flip_h = false
		var task := str(info.get("work", ""))
		var cooking := task == "做菜" or (order_shop != null and not order_shop.active_orders().is_empty())
		var bob := 6.0 if task == "做菜" else 2.0
		body.position.y = -47.0 - (absf(sin(_crew_time * 8.0 + float(index))) * bob if cooking else 0.0)
		var caption := root.get_node("Name") as Label
		caption.text = String(info.caption)
		caption.add_theme_color_override("font_color", info.color)

func _station_hint(id: String) -> String:
	var hand: Dictionary = _context.get("hand",{})
	if id=="kitchen.fridge" or id.begins_with("kitchen.supply."): return "选一份食材" if hand.is_empty() else "放回食材（保留切型）"
	if id=="kitchen.trash": return "丢弃手上物品" if not hand.is_empty() else "清理锅 / 砧板"
	if id == "kitchen.board": return "取走备好的食材" if _context.get("board_occupied",false) else "放下食材并备菜"
	if id == "kitchen.dining": return "走进餐厅"
	if id == "kitchen.serve": return "交付客人" if hand.get("kind") == "dish" else "把出锅的菜端到这里"
	if single_fridge: return "取放食材 / 端盘 · F 开灶台 · Q 取回"
	return "放入食材" if hand.get("kind") == "ingredient" else "操作 / 端起成品"

func _draw_service_door() -> void:
	var frame := SERVICE_DOOR_RECT
	var leaf_w := frame.size.x * 0.5 - 2.0
	draw_rect(Rect2(frame.position, Vector2(leaf_w, frame.size.y)), Color("8b5a34"))
	draw_rect(Rect2(frame.position + Vector2(frame.size.x - leaf_w, 0), Vector2(leaf_w, frame.size.y)), Color("6d4528"))
	var panel := Vector2(leaf_w - 16.0, frame.size.y * 0.62)
	var panel_at := frame.position + Vector2(8.0, frame.size.y * 0.16)
	draw_rect(Rect2(panel_at, panel), Color("5c3a22"))
	draw_rect(Rect2(frame.position + Vector2(frame.size.x - leaf_w + 8.0, frame.size.y * 0.16), panel), Color("4a2e1b"))
	var seam := frame.position.x + frame.size.x * 0.5
	draw_line(Vector2(seam, frame.position.y), Vector2(seam, frame.end.y), Color("3a2416"), 2.0)
	draw_circle(Vector2(seam - 14.0, frame.position.y + frame.size.y * 0.55), 3.0, Color("e2ba69"))
	draw_circle(Vector2(seam + 14.0, frame.position.y + frame.size.y * 0.55), 3.0, Color("e2ba69"))
	if _hud != null:
		draw_string(_hud.get_theme_default_font(), frame.position + Vector2(frame.size.x * 0.5 - 20.0, -8.0), "餐厅", HORIZONTAL_ALIGNMENT_LEFT, 80, 16, TDUI.ORANGE)

func _draw() -> void:
	if service_door:
		_draw_service_door()
	if single_fridge and _hud!=null:
		for i: int in pot_contents.size():
			var box:=Rect2(530+i*220,350,210,62)
			draw_rect(box,Color("172b24")); draw_rect(box,Color("c5a46c"),false,2)
			draw_colored_polygon(PackedVector2Array([box.position+Vector2(124,0),box.position+Vector2(144,-18),box.position+Vector2(153,0)]),Color("172b24"))
			draw_string(_hud.get_theme_default_font(),box.position+Vector2(10,23),str(pot_contents[i].title),HORIZONTAL_ALIGNMENT_LEFT,232,17,TDUI.ORANGE)
			draw_string(_hud.get_theme_default_font(),box.position+Vector2(10,46),str(pot_contents[i].materials),HORIZONTAL_ALIGNMENT_LEFT,232,16,TDUI.INK)
	if _simmer_label!=null: _simmer_label.visible=simmer_meters.is_empty()
	for i: int in simmer_meters.size():
		var r:=Rect2(24,654-i*78,342,22)
		draw_rect(Rect2(r.position-Vector2(4,33),Vector2(350,59)),Color("1d3028"))
		draw_rect(r,Color("263c32")); draw_rect(Rect2(r.position+Vector2(3,3),Vector2(269*float(simmer_meters[i].ratio),16)),Color("92ae76"))
		if _hud!=null: draw_string(_hud.get_theme_default_font(),r.position+Vector2(5,-10),"%s  ·  稳定 %d%%  ·  %.1fs"%[simmer_meters[i].name,roundi(float(simmer_meters[i].ratio)*100),float(simmer_meters[i].remaining_sec)],HORIZONTAL_ALIGNMENT_LEFT,-1,16,TDUI.INK)
	for station: Dictionary in stations():
		var feet: Vector2=station.get("visual",station.position-Vector2(0,70))
		var index: int={"fridge":4,"board":5,"steamer":7,"serve":8,"trash":9,"supply":14}.get(str(station.get("kind","")),6)
		if station.id=="kitchen.serve": feet=Vector2(1040,615)
		TDEnvironmentArt.draw_prop(self,index,feet,220 if index in [4,8] else (120 if index==9 else 180))
	for at: Vector2 in [Vector2(135,95),Vector2(1145,95)]: TDDaylight.glow(self,at,float(TDDaylight.sample(day_minute,true).lamps),55)
	if is_instance_valid(_player) and not _context.get("hand",{}).is_empty():
		var hand: Dictionary = _context.hand
		var point: Vector2 = _player.position + Vector2(0,-116)
		draw_rect(Rect2(point - Vector2(20,14),Vector2(40,24)),Color("d5d6bb"))
		if hand.kind == "dish" or hand.shape != "whole":
			for index: int in 3: draw_rect(Rect2(point + Vector2(-13+index*10,-9),Vector2(8,9)),Color("d56a48"))
		else: draw_circle(point + Vector2(0,-2),9,Color("f1d17d") if hand.name == "鸡蛋" else Color("d95e45"))
