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
var _message_left: float = 0.0
var _last_context_message: String = ""
var _held_label: Label
var _simmer_label: Label
var _near_prompt: Label
var simmer_meters: Array=[]
var station_names: Dictionary={}
var single_fridge: bool = false
var cuisine_id: String = "cn":
	set(value):
		cuisine_id=value
		if has_node("Background"): $Background.visible=not TDRegionalInterior.regional(value)
		queue_redraw()
var pot_contents: Array=[]
var crew: TDRestaurantCrew
const CHEF_SPRITE := preload("res://assets/redraw-v1/chef.png")
const COOK_POSTS: Array[Vector2] = [Vector2(640, 400), Vector2(850, 400)]
const COOK_WALK_SPEED := 140.0
const COOK_LEG_SEC := 1.2
var _staff_nodes: Array[Node2D] = []
var _crew_time: float = 0.0
var _staff_delta: float = 0.0
var order_shop: TDShopSession
var staff_source: Callable
var _pot_panels: Array[PanelContainer] = []
var _pot_titles: Array[Label] = []
var _pot_materials: Array[Label] = []
var _simmer_panels: Array[PanelContainer] = []
var _simmer_titles: Array[Label] = []
var _simmer_bars: Array[ProgressBar] = []

func staff_approach(id: String, slot: int = 0) -> Vector2:
	for station: Dictionary in stations():
		if station.id!=id: continue
		var bounds:=station_bounds(station)
		if id=="kitchen.serve": return Vector2(bounds.position.x-28,bounds.get_center().y)
		return Vector2(bounds.get_center().x+float(slot)*34,bounds.end.y+32)
	return Vector2(640,430)

func staff_home(index: int) -> Vector2:
	return staff_approach("kitchen.stove.left" if index%2==0 else "kitchen.stove.right")+Vector2(0,80)

func staff_waiting_point(index: int) -> Vector2:
	return Vector2(staff_approach("kitchen.board").x+float(index)*40,440)

func staff_walkable(point: Vector2) -> bool:
	if not Rect2(108,296,1064,426).has_point(point): return false
	for station: Dictionary in stations():
		if station.id in ["kitchen.serve","kitchen.trash"] and station_bounds(station).grow(14).has_point(point): return false
	return true

func _staff_segment_clear(from: Vector2, to: Vector2) -> bool:
	var count:=maxi(1,ceili(from.distance_to(to)/8.0))
	for i: int in count+1:
		if not staff_walkable(from.lerp(to,float(i)/count)): return false
	return true

func staff_route(from: Vector2, to: Vector2) -> PackedVector2Array:
	if _staff_segment_clear(from,to): return PackedVector2Array([to])
	# All fixtures are on the north counter or the southeast pass. Use the clear central aisle.
	var points:=PackedVector2Array([Vector2(from.x,440),Vector2(to.x,440),to])
	var previous:=from
	for point: Vector2 in points:
		if not _staff_segment_clear(previous,point): push_error("Unreachable staff work station: "+str(to));return PackedVector2Array([from])
		previous=point
	return points

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
	$Background.visible=not TDRegionalInterior.regional(cuisine_id)
	$Background.scale=Vector2(1280.0/$Background.texture.get_width(),800.0/$Background.texture.get_height())
	_player.z_index = 1
	_make_hud()
	_hud.z_index=2
	_near_prompt=_sign("[ E ]", Vector2.ZERO, 76, TDUI.FONT_SECTION, "InteractionSign")
	_near_prompt.autowrap_mode=TextServer.AUTOWRAP_OFF
	_near_prompt.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	for station: Dictionary in stations():
		var at: Vector2 = (station.get("visual",station.position+Vector2(0,-120)) as Vector2) + Vector2(-70,12)
		if station.id=="kitchen.trash": at.y-=24
		var label := _sign(str(station_names.get(station.id,station.name)), at, 140, TDUI.FONT_BODY, "StationSign_"+str(station.id))
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.get_parent().hide()
		if station.get("kind") == "serve":
			var body := StaticBody2D.new(); body.name="ServingCounter"; body.position = Vector2(1040,565)
			var collider := CollisionShape2D.new(); var shape := RectangleShape2D.new(); shape.size = Vector2(232,102); collider.shape = shape
			body.add_child(collider); add_child(body)
	_update_prompt()

func _process(delta: float) -> void:
	_staff_delta = 0.0
	if is_inside_tree() and not get_tree().paused:
		_crew_time += delta
		_staff_delta = delta
		if is_visible_in_tree(): _message_left=maxf(0.0,_message_left-delta)
	_refresh_held()
	_update_prompt()
	_update_pot_signs()
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

func set_embedded_hud() -> void:
	# The host already presents the room and quest; keep held items above the bottom controls.
	_hud.get_node("HeadingSign").hide()
	for index: int in _pot_panels.size():
		_pot_panels[index].position=Vector2(550+index*290,12)
		_pot_panels[index].size.x=280

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
		var sign := _near_prompt.get_parent() as Control
		sign.visible = _controls_enabled and not station_id.is_empty()
		if not station_id.is_empty():
			_near_prompt.text=_station_hint(station_id)
			sign.size.x=300 if station_id in ["kitchen.stove.left","kitchen.stove.right","kitchen.steamer"] else 170
			sign.position=(station.get("visual",station.position-Vector2(0,120)) as Vector2)+Vector2(-sign.size.x*.5,-70)
	_prompt.text=""
	_prompt.get_parent().hide()

func _sign(text: String, at: Vector2, width: float, font_size: int, id: String) -> Label:
	var panel := PanelContainer.new()
	panel.name=id;panel.position=at;panel.size=Vector2(width,0)
	panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel",TDUI.wood(TDUI.Surface.INSET,10))
	_hud.add_child(panel)
	var label := TDUI.label(text,font_size,TDUI.INK)
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	panel.add_child(label)
	return label

func _make_hud() -> void:
	_hud = Control.new()
	_hud.name = "KitchenHUD"
	_hud.theme = TDUI.theme()
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_hud)
	_sign("小镇食堂 / 厨房",Vector2(24,12),360,TDUI.FONT_SECTION,"HeadingSign")
	_held_label = _sign("手上：空",Vector2(24,628),1232,TDUI.FONT_SECTION,"HeldSign")
	_held_label.max_lines_visible=2
	_held_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	_simmer_label = _sign("",Vector2(24,380),460,TDUI.FONT_SECTION,"SimmerSign")
	_simmer_label.get_parent().hide()
	_back_button = TDUI.button("返回主界面", _back)
	_back_button.position = Vector2(1070.0, 14.0)
	_back_button.size = Vector2(182.0, 50.0)
	_hud.add_child(_back_button)
	var bar := Panel.new()
	bar.name="OperationSign"
	bar.position = Vector2(108.0, 716.0)
	bar.size = Vector2(1064.0, 72.0)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("panel", TDUI.wood(TDUI.Surface.INSET,12))
	_hud.add_child(bar)
	_prompt = TDUI.label("", TDUI.FONT_SECTION,TDUI.INK)
	_prompt.position = Vector2(18.0, 8.0)
	_prompt.size = Vector2(1028.0, 56.0)
	_prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.mouse_filter=Control.MOUSE_FILTER_IGNORE
	bar.add_child(_prompt)
	for index: int in 2:
		var panel := PanelContainer.new()
		panel.name="PotSign%d"%index;panel.position=Vector2(530+index*220,352);panel.size=Vector2(214,0)
		panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
		panel.add_theme_stylebox_override("panel",TDUI.wood(TDUI.Surface.INSET,10))
		_hud.add_child(panel);_pot_panels.append(panel)
		var column := VBoxContainer.new();column.mouse_filter=Control.MOUSE_FILTER_IGNORE
		column.add_theme_constant_override("separation",4);panel.add_child(column)
		var title := TDUI.label("",TDUI.FONT_SECTION,TDUI.ORANGE)
		var materials := TDUI.label("",TDUI.FONT_BODY,TDUI.INK)
		for label: Label in [title,materials]:
			label.mouse_filter=Control.MOUSE_FILTER_IGNORE;label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
			column.add_child(label)
		_pot_titles.append(title);_pot_materials.append(materials);panel.hide()
		var simmer_panel := PanelContainer.new()
		simmer_panel.name="SimmerMeter%d"%index; simmer_panel.position=Vector2(24,380+index*96);simmer_panel.size=Vector2(460,0)
		simmer_panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
		simmer_panel.add_theme_stylebox_override("panel",TDUI.wood(TDUI.Surface.INSET,10))
		_hud.add_child(simmer_panel)
		var simmer_column := VBoxContainer.new();simmer_column.mouse_filter=Control.MOUSE_FILTER_IGNORE;simmer_panel.add_child(simmer_column)
		var simmer_title := TDUI.label("",TDUI.FONT_BODY,TDUI.INK)
		simmer_title.mouse_filter=Control.MOUSE_FILTER_IGNORE;simmer_title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;simmer_column.add_child(simmer_title)
		var meter := ProgressBar.new();meter.custom_minimum_size.y=18;meter.show_percentage=false;meter.mouse_filter=Control.MOUSE_FILTER_IGNORE
		simmer_column.add_child(meter)
		_simmer_panels.append(simmer_panel);_simmer_titles.append(simmer_title);_simmer_bars.append(meter);simmer_panel.hide()

func _update_pot_signs() -> void:
	for index: int in _pot_panels.size():
		_pot_panels[index].visible=single_fridge and index<pot_contents.size() and bool(pot_contents[index].get("occupied",true))
		if index<pot_contents.size():
			_pot_titles[index].text=str(pot_contents[index].title)
			_pot_materials[index].text=str(pot_contents[index].materials)
	if _simmer_label!=null:
		_simmer_label.get_parent().visible=simmer_meters.is_empty() and not _simmer_label.text.is_empty()
	for index: int in _simmer_panels.size():
		_simmer_panels[index].visible=index<simmer_meters.size()
		if index<simmer_meters.size():
			var meter: Dictionary=simmer_meters[index]
			_simmer_titles[index].text="%s · 稳定 %d%% · %.1fs"%[meter.name,roundi(float(meter.ratio)*100),float(meter.remaining_sec)]
			_simmer_bars[index].value=float(meter.ratio)*100

func _back() -> void:
	if _controls_enabled:
		close()
		back_requested.emit()

func set_context(value: Dictionary, message: String = "", simmer: String = "") -> void:
	_context = value.duplicate(true)
	if message!=_last_context_message:
		_last_context_message=message
		if not message.is_empty(): show_feedback(message)
	_refresh_held()
	if _simmer_label != null: _simmer_label.text = simmer
	queue_redraw()

func show_feedback(text: String) -> void:
	_message=text;_message_left=4.0 if not text.is_empty() else 0.0
	_refresh_held()

func _refresh_held() -> void:
	if _held_label==null: return
	var hand: Dictionary=_context.get("hand",{})
	var parts: Array[String]=[]
	if not hand.is_empty():
		parts.append(str(hand.name)+(" · "+str({"slice":"片","strip":"条","chunk":"块","dice":"丁"}.get(hand.get("shape",""),"")) if hand.get("shape","") in ["slice","strip","chunk","dice"] else ""))
	if _message_left>0: parts.append(_message)
	_held_label.text="\n".join(parts)
	_held_label.tooltip_text=_held_label.text
	_held_label.get_parent().visible=not parts.is_empty()

static func cook_point(index: int, _time_sec: float) -> Vector2:
	return COOK_POSTS[index % COOK_POSTS.size()]

static func cook_flow_step(time_sec: float) -> String:
	var steps: Array[String] = ["取料", "切菜", "热锅", "翻炒", "调味", "出餐"]
	var leg := int(time_sec / COOK_LEG_SEC) % steps.size()
	if leg < 0:
		leg = 0
	return steps[leg]

static func cook_place(step: String) -> String:
	match step:
		"取料":
			return "取料"
		"切菜":
			return "切菜"
		"热锅", "翻炒", "调味", "勾芡", "做菜":
			return "做菜"
		"蒸制":
			return "蒸制"
		"出餐", "出锅":
			return "出餐"
		_:
			return ""

static func cook_place_rank(place: String) -> int:
	match place:
		"取料":
			return 1
		"切菜":
			return 2
		"做菜", "蒸制":
			return 3
		"出餐":
			return 4
		_:
			return 0

static func cook_station(index: int, step: String) -> Vector2:
	var stove := cook_point(index, 0.0)
	var slot := float(index % 2)
	match cook_place(step):
		"取料":
			return Vector2(210.0 + slot * 90.0, 450.0)
		"切菜":
			return Vector2(790.0 + slot * 80.0, 348.0)
		"蒸制":
			return Vector2(740.0 + slot * 50.0, 390.0)
		"出餐":
			return Vector2(820.0 + slot * 70.0, 478.0)
		_:
			return stove

static func cook_task_point(index: int, time_sec: float) -> Vector2:
	return cook_station(index, cook_flow_step(time_sec))

func _sync_staff() -> void:
	if staff_source.is_valid():
		var rows: Array=staff_source.call()
		while _staff_nodes.size()<rows.size():
			var actor:=TDKitchenStaffActor.new();actor.name="Cook%d"%_staff_nodes.size();add_child(actor);_staff_nodes.append(actor)
		while _staff_nodes.size()>rows.size(): (_staff_nodes.pop_back() as Node2D).queue_free()
		for i: int in rows.size(): (_staff_nodes[i] as TDKitchenStaffActor).present(rows[i])
		return
	var wanted: Array[Dictionary] = []
	if crew != null:
		var cooks := crew.cooks()
		for index: int in cooks.size():
			var cook: Dictionary = cooks[index]
			var work := ""
			var step := ""
			var job_id := ""
			if order_shop != null:
				work = order_shop.crew_work(str(cook.id))
				step = str(order_shop.cook_step(str(cook.id)))
				job_id = order_shop.cook_job_id(str(cook.id))
			var caption := "厨师 %s %d级" % [String(cook["name"]), int(cook.get("level", 1))]
			if work == "做菜":
				if step == "":
					step = cook_flow_step(_crew_time)
				caption = "厨师 %s 做菜 · %s" % [String(cook["name"]), step]
			elif work != "":
				caption = "厨师 %s %s" % [String(cook["name"]), work]
			wanted.append({"caption": caption, "cuisine_id": cook.get("cuisine_id","cn"), "appearance_variant": cook.get("appearance_variant",0), "name": String(cook["name"]), "color": Color("#c46a3a"), "work": work, "step": step, "job_id": str(cook.id)+":"+job_id, "index": index})
	while _staff_nodes.size() < wanted.size():
		var root := Node2D.new()
		var sprite := Sprite2D.new()
		sprite.name = "Body"
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		root.add_child(sprite)
		var caption := Label.new()
		caption.name = "Name"
		caption.theme = TDUI.theme()
		caption.position = Vector2(-60, -137)
		caption.size = Vector2(120, 24)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.add_theme_font_size_override("font_size", TDUI.FONT_CAPTION)
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
		var home := cook_point(int(info.index), 0.0)
		var task := str(info.get("work", ""))
		var cooking := task == "做菜"
		var step := str(info.get("step", ""))
		var place := _held_place(root, step, cooking, str(info.job_id))
		var goal := cook_station(int(info.index), place) if cooking else home
		if not root.has_meta("placed"):
			root.position = home
			root.set_meta("placed", true)
		var previous := root.position
		if _staff_delta > 0.0:
			root.position = root.position.move_toward(goal, COOK_WALK_SPEED * _staff_delta)
		root.z_index = 1
		if not root.has_meta("gait"):
			var new_gait := TDNpcGait.new()
			new_gait.reset(previous)
			root.set_meta("gait",new_gait)
		var gait: TDNpcGait = root.get_meta("gait")
		gait.sample(root.position,_staff_delta<=0,root.position.is_equal_approx(goal))
		body.texture=TDEmployeeArt.sprite(info.cuisine_id,"cook",gait.facing,gait.frame,info.appearance_variant)
		var lift := TDEmployeeArt.breath_lift(_crew_time,index) if gait.frame < 0 and not cooking else 0.0
		TDEmployeeArt.pose_body(body,TDKitchenStaffActor.FRAME_HEIGHT,lift)
		var name_label := root.get_node("Name") as Label
		name_label.text = String(info.caption)
		if cooking:
			var shown := step if cook_place(step) == place else place
			if shown == "":
				shown = "做菜"
			name_label.text = "厨师 %s 做菜 · %s" % [String(info.get("name", "")), shown]
		name_label.add_theme_color_override("font_color", info.color)

func _held_place(root: Node2D, reported: String, cooking: bool, job_id: String="") -> String:
	# A scheduler may finish one dish and begin another without an idle frame.
	# Only presentation state is reset; position and the real cooking session stay intact.
	if str(root.get_meta("cook_job_id",""))!=job_id:
		root.set_meta("cook_job_id",job_id)
		if root.has_meta("cook_place"): root.remove_meta("cook_place")
	if not cooking:
		if root.has_meta("cook_place"):
			root.remove_meta("cook_place")
		return ""
	var place := cook_place(reported)
	var held := str(root.get_meta("cook_place", ""))
	if place != "" and (held == "" or cook_place_rank(place) > cook_place_rank(held)):
		root.set_meta("cook_place", place)
		return place
	return held

func _station_hint(id: String) -> String:
	var hand: Dictionary = _context.get("hand",{})
	if id=="kitchen.fridge" or id.begins_with("kitchen.supply."): return "E 冰箱" if hand.is_empty() else "E 放回"
	if id=="kitchen.trash": return "E 丢弃" if not hand.is_empty() else "E 清理"
	if id == "kitchen.board": return "E 取回" if _context.get("board_occupied",false) else "E 备菜"
	if id == "kitchen.dining": return "E 餐厅"
	if id == "kitchen.serve": return "E 出餐"
	var index: int=0 if id=="kitchen.stove.left" else 1
	var pot: Dictionary=pot_contents[index] if index<pot_contents.size() else {}
	if pot.get("state","")=="plated": return "E 端盘"
	if not pot.get("occupied",false): return "E 放入"
	return "E 放入 · F 开火 · Q 取回"

func _draw_service_door() -> void:
	var frame := SERVICE_DOOR_RECT
	var wood := Color(TDRegionalInterior.WOODS.get(TDRegionalInterior.style(cuisine_id),"8b5a34"))
	var leaf_w := frame.size.x * 0.5 - 2.0
	draw_rect(Rect2(frame.position, Vector2(leaf_w, frame.size.y)), wood)
	draw_rect(Rect2(frame.position + Vector2(frame.size.x - leaf_w, 0), Vector2(leaf_w, frame.size.y)), wood.darkened(.12))
	var panel := Vector2(leaf_w - 16.0, frame.size.y * 0.62)
	var panel_at := frame.position + Vector2(8.0, frame.size.y * 0.16)
	draw_rect(Rect2(panel_at, panel), wood.darkened(.24))
	draw_rect(Rect2(frame.position + Vector2(frame.size.x - leaf_w + 8.0, frame.size.y * 0.16), panel), wood.darkened(.3))
	var seam := frame.position.x + frame.size.x * 0.5
	draw_line(Vector2(seam, frame.position.y), Vector2(seam, frame.end.y), Color("3a2416"), 2.0)
	draw_circle(Vector2(seam - 14.0, frame.position.y + frame.size.y * 0.55), 3.0, Color("e2ba69"))
	draw_circle(Vector2(seam + 14.0, frame.position.y + frame.size.y * 0.55), 3.0, Color("e2ba69"))
	if _hud != null:
		draw_string(_hud.get_theme_default_font(), frame.position + Vector2(frame.size.x * 0.5 - 20.0, -8.0), "餐厅", HORIZONTAL_ALIGNMENT_LEFT, 80, TDUI.FONT_CAPTION, TDUI.ORANGE)

func _draw() -> void:
	TDRegionalInterior.draw_kitchen(self,cuisine_id)
	if service_door:
		_draw_service_door()
	for station: Dictionary in stations():
		var feet: Vector2=station.get("visual",station.position-Vector2(0,70))
		var index: int={"fridge":4,"board":5,"steamer":7,"serve":8,"trash":9,"supply":14}.get(str(station.get("kind","")),6)
		if station.id=="kitchen.serve": feet=Vector2(1040,615)
		var bay:=TDCuisineKitchen.IDS.find(station.id)
		if TDRegionalInterior.draw_prop(self,cuisine_id,str(station.get("kind","")),feet): pass
		elif cuisine_id!="cn" and bay>=0: TDCuisineKitchen.fixture(self,feet,cuisine_id,bay)
		else: TDEnvironmentArt.draw_prop(self,index,feet,220 if index in [4,8] else (120 if index==9 else 180))
	for at: Vector2 in [Vector2(135,95),Vector2(1145,95)]: TDDaylight.glow(self,at,float(TDDaylight.sample(day_minute,true).lamps),55)
	if is_instance_valid(_player) and not _context.get("hand",{}).is_empty():
		var hand: Dictionary = _context.hand
		var point: Vector2 = _player.position + Vector2(0,-116)
		draw_rect(Rect2(point - Vector2(20,14),Vector2(40,24)),Color("d5d6bb"))
		if hand.kind == "dish" or hand.shape != "whole":
			for index: int in 3: draw_rect(Rect2(point + Vector2(-13+index*10,-9),Vector2(8,9)),Color("d56a48"))
		else: draw_circle(point + Vector2(0,-2),9,Color("f1d17d") if hand.name == "鸡蛋" else Color("d95e45"))
