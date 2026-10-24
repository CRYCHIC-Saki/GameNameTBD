class_name TDFullKitchen
extends Control
signal back_requested
signal pause_requested
signal dish_delivered(dish: Dictionary)
signal time_advanced(seconds: float)
signal work_advanced(station_seconds: float)
# Optional business composition. Legacy kitchens retain their established routes.
var station_handler: Callable
var action_handler: Callable
var time_boundary: Callable
var station_names: Dictionary={}
var single_fridge: bool = false
const WORLD := preload("res://src/world/kitchen_world.tscn")
var catalog: TDCookingCatalog
var _content: Dictionary = {}
var scorer: TDCustomerScorer
var library_path: String = "user://recipe-library.json"
var auto_advance: bool = true
# A research host drives the same kitchen, while owning return/completion navigation.
var lesson_mode: bool = false
var before_input: Callable
var world: TDKitchenWorld
var lanes: Array[TDCookingLane] = []
var day_san: float = -1.0
var panel: Control
var dual: bool = false
var _dual_toggle: CheckButton
var _pause_button: Button
var _last_ticks: int
var _closed: bool = false
var _paused_label: Label
var handling: TDKitchenHandling
var prep: TDCookingLane
var shared_clock := TDClock.new()
var beat_audio: TDBeatAudio
var beat_bar: TDTemperatureView
var active_lane: int = 0
var _row_container: HBoxContainer
var _title: Label
var _message: String = ""
var _supply_panel: PanelContainer
var guided_controls: bool = true
var stage: TDGuidedCookingView
var _on_board: bool = false
var _finished_at: float = -1

func _ready() -> void:
	_content = catalog.data()
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = TDUI.theme()
	theme.default_font_size = 16
	for state: String in ["normal", "hover", "pressed", "focus"]:
		var style := theme.get_stylebox(state, "Button").duplicate() as StyleBoxFlat
		style.content_margin_left = 9; style.content_margin_right = 9
		style.content_margin_top = 5; style.content_margin_bottom = 5
		theme.set_stylebox(state, "Button", style)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	world = WORLD.instantiate() as TDKitchenWorld
	world.station_names=station_names
	world.single_fridge=single_fridge
	add_child(world)
	handling = TDKitchenHandling.new(catalog)
	world.cooking_requested.connect(_station_interaction)
	world.station_action.connect(func(id:String,action:String)->void:
		if action_handler.is_valid(): action_handler.call(id,action)
		else: _station_interaction(id))
	world.back_requested.connect(func() -> void: back_requested.emit())
	beat_audio = TDBeatAudio.new(); add_child(beat_audio)
	beat_audio.prepare_loop(float(_content.pc_operations.bpm))
	var audio_delay: float = 0.0
	panel = PanelContainer.new()
	var backdrop := StyleBoxFlat.new(); backdrop.bg_color = Color("142c29")
	panel.add_theme_stylebox_override("panel", backdrop)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 12)
	panel.add_child(margin)
	var column := VBoxContainer.new(); margin.add_child(column)
	var header := HBoxContainer.new(); column.add_child(header)
	_title = TDUI.label("功能位 · 卡拍做菜", 23, TDUI.ORANGE); _title.size_flags_horizontal = Control.SIZE_EXPAND_FILL; header.add_child(_title)
	_dual_toggle = CheckButton.new(); _dual_toggle.text = "双菜同时操作"; _dual_toggle.toggled.connect(set_dual); header.add_child(_dual_toggle)
	var offset := SpinBox.new(); offset.min_value = -250; offset.max_value = 250; offset.step = 5; offset.suffix = "ms补偿"; offset.custom_minimum_size.x = 155
	offset.value_changed.connect(func(value: float) -> void:
		for lane: TDCookingLane in lanes + [prep]: lane.input_offset_sec = value / 1000.0)
	header.add_child(offset)
	_pause_button = TDUI.button("暂停 Esc", func() -> void: pause_requested.emit()); header.add_child(_pause_button)
	header.add_child(TDUI.button("回到厨房", close_bench))
	var assistance := HBoxContainer.new(); column.add_child(assistance)
	var window_assist := CheckButton.new(); window_assist.text = "节拍辅助 ×1.5"; assistance.add_child(window_assist)
	window_assist.toggled.connect(func(value: bool) -> void:
		for lane: TDCookingLane in lanes + [prep]: lane.assist_windows = value)
	var heat_assist := CheckButton.new(); heat_assist.text = "辅助控温（练习）"; assistance.add_child(heat_assist)
	heat_assist.toggled.connect(func(value: bool) -> void:
		for lane: TDCookingLane in lanes: lane.assist_temperature = value)
	assistance.add_child(TDUI.button("取走 / 端起", _take_and_leave))
	assistance.add_child(TDUI.button("重新做一份", _restart_active))
	var scroll := ScrollContainer.new(); scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL; scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; column.add_child(scroll)
	var row := HBoxContainer.new(); row.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.size_flags_vertical = Control.SIZE_EXPAND_FILL; row.add_theme_constant_override("separation", 20); scroll.add_child(row)
	_row_container = row
	for index: int in 2:
		var lane := TDCookingLane.new()
		lane.catalog = catalog; lane.scorer = scorer; lane.lane_index = index
		lane.day_san = day_san
		lane.pc_controls = true; lane.shared_clock = shared_clock; lane.beat_offset_sec = audio_delay
		lane.document_rules = guided_controls
		lane.restart_allowed = func() -> bool: return handling.hand == null or handling.hand != lane.session
		lane.library = TDRecipeLibrary.new(library_path, _content)
		lane.dish_delivered.connect(_forward_dish)
		row.add_child(lane)
		lanes.append(lane)
	prep = TDCookingLane.new(); prep.catalog = catalog; prep.scorer = scorer; prep.lane_index = 2; prep.day_san = day_san
	prep.pc_controls = true; prep.station_role = "board"; prep.shared_clock = shared_clock; prep.beat_offset_sec = audio_delay
	prep.document_rules = guided_controls
	prep.library = TDRecipeLibrary.new(library_path, _content); row.add_child(prep); prep.hide()
	beat_bar = TDTemperatureView.new(); beat_bar.beat_only = true; beat_bar.bpm = float(_content.pc_operations.bpm); column.add_child(beat_bar)
	column.add_child(TDUI.label("占位美术 / 节奏音轨 · 左锅WASD、右锅方向键 · 空格收势 / 出锅 · Esc暂停", 13, TDUI.MUTED))
	_paused_label = TDUI.label("已暂停 · Esc 恢复", 28, TDUI.ORANGE)
	_paused_label.position = Vector2(470, 370)
	_paused_label.size=Vector2(450,50); _paused_label.autowrap_mode=TextServer.AUTOWRAP_OFF
	_paused_label.z_index=20; _paused_label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(_paused_label)
	_paused_label.hide()
	set_dual(false)
	_compact_controls(panel)
	panel.hide()
	stage = TDGuidedCookingView.new(); add_child(stage); stage.hide()
	stage.spice_clicked.connect(func(index: int, id: String) -> void:
		if get_tree().paused or not stage.visible: return
		var lane: TDCookingLane=prep if index==2 else lanes[index]
		lane.input_action("spice:"+id,true); lane.input_action("spice:"+id,false))
	stage.spice_input.connect(func(index: int,id: String,pressed: bool) -> void:
		if get_tree().paused or not stage.visible: return
		var lane: TDCookingLane=prep if index==2 else lanes[index]
		lane.input_action("spice:"+id,pressed))
	audio_delay = beat_audio.begin()
	for lane: TDCookingLane in lanes + [prep]: lane.beat_offset_sec = audio_delay
	_last_ticks = Time.get_ticks_usec()

func _compact_controls(node: Node) -> void:
	if node is Button: node.custom_minimum_size.y = 32
	for child: Node in node.get_children(): _compact_controls(child)

func _forward_dish(dish: Dictionary) -> void:
	dish_delivered.emit(dish.duplicate(true))

func open_bench(station_id: String = "kitchen.stove.left") -> void:
	if _closed: return
	if guided_controls: _open_guided(station_id); return
	world.set_controls_enabled(false)
	world.hide()
	active_lane = 1 if station_id in ["kitchen.stove.right", "kitchen.steamer"] else 0
	if station_id == "kitchen.board":
		for lane: TDCookingLane in lanes: lane.hide()
		prep.show(); _dual_toggle.hide(); _title.text = "砧板 · 备好后取走"
	else:
		prep.hide(); _dual_toggle.show()
		lanes[active_lane].station_role = "steamer" if station_id == "kitchen.steamer" else "stove"
		_title.text = "灶台 · 投料后开始操作" if station_id != "kitchen.steamer" else "蒸笼 · 右锅"
		set_dual(dual)
	panel.show()

func close_bench() -> void:
	if stage != null: stage.hide(); stage.feedback=""
	for lane: TDCookingLane in lanes + [prep]:
		if lane.qte != null: lane.qte.release_input()
		if lane.thermal_qte != null: lane.thermal_qte.release_input()
	panel.hide()
	world.show()
	world.set_controls_enabled(true)
	_update_world()

func open_station_view(station_id: String) -> void:
	if not _closed: _open_guided(station_id)

func refresh_world() -> void:
	_update_world()

func set_dual(value: bool) -> void:
	if lanes.size() < 2: return
	if not value and lanes[1].qte != null:
		_dual_toggle.set_pressed_no_signal(true)
		return
	dual = value
	_dual_toggle.set_pressed_no_signal(value)
	for index: int in lanes.size(): lanes[index].visible = value or index == active_lane
	for lane: TDCookingLane in lanes:
		if lane.qte != null: lane.qte.release_input()
		lane.dual = value
		lane.refresh()

func _process(_delta: float) -> void:
	if auto_advance: _sync_time()

func _sync_time() -> void:
	var now: int = Time.get_ticks_usec()
	var elapsed: float = float(now - _last_ticks) / 1000000.0
	_last_ticks = now
	advance(elapsed)

func advance(seconds: float) -> void:
	if _closed: return
	if time_boundary.is_valid() and is_finite(seconds) and seconds > 0 and not shared_clock.paused:
		var remaining: float=seconds
		while remaining > .0000001:
			var span: float=clampf(float(time_boundary.call(remaining)),.0000001,remaining)
			_advance_span(span)
			remaining-=span
	else: _advance_span(seconds)

func _advance_span(seconds: float) -> void:
	var business_delta: float = seconds if is_finite(seconds) and seconds >= 0 and not shared_clock.paused else 0.0
	if guided_controls: _advance_guided(seconds)
	else:
		for lane: TDCookingLane in lanes: lane.advance(seconds)
		if handling.board != null: prep.advance(seconds)
		if handling.hand != null and handling.hand_kind == "ingredient" and not shared_clock.paused: handling.hand.advance_time(seconds)
		shared_clock.advance(seconds)
	beat_bar.beat_sec = shared_clock.qte_sec - lanes[0].beat_offset_sec; beat_bar.queue_redraw()
	_update_world()
	if guided_controls and stage != null:
		_refresh_guided()
	if business_delta > 0.0: time_advanced.emit(business_delta)

func _sync_mouse_ownership() -> bool:
	var reserved: bool = lanes.any(func(lane:TDCookingLane)->bool:return lane.qte != null and lane.progress.get("pc_module") == "M6")
	for lane: TDCookingLane in lanes:
		if lane.thermal_qte != null:
			lane.thermal_qte.set_control_suspended(reserved)
			lane.thermal_progress = lane.thermal_qte.update().data
	return reserved

func _advance_guided(seconds: float) -> void:
	if not is_finite(seconds) or seconds < 0 or shared_clock.paused: return
	var remaining: float = seconds
	var active: Array = lanes.duplicate()
	if handling.board != null: active.append(prep)
	for iteration: int in 1024:
		for lane: TDCookingLane in active: lane.advance(0)
		_sync_mouse_ownership()
		if remaining <= .000000001: return
		var span: float = remaining
		for lane: TDCookingLane in active: span = minf(span,lane.next_boundary_sec())
		if span <= .000000001:
			push_error("Guided scheduler failed to advance"); return
		var working: int=0
		for lane: TDCookingLane in active:
			if lane.qte!=null or lane.thermal_qte!=null: working+=1
		if working>0: work_advanced.emit(span*working)
		for lane: TDCookingLane in active: lane.advance(span)
		if handling.hand != null and handling.hand_kind == "ingredient": handling.hand.advance_time(span)
		shared_clock.advance(span); remaining -= span
		if remaining <= .000000001: return
	push_error("Guided scheduler exceeded bounded event count")

func _input(event: InputEvent) -> void:
	if _closed: return
	if before_input.is_valid(): before_input.call()
	if event.is_action("recipe_book"): return
	if auto_advance: _sync_time()
	if event.is_action_pressed("pause") and not event.is_echo():
		pause_requested.emit(); get_viewport().set_input_as_handled(); return
	if guided_controls:
		if stage != null and stage.visible and not get_tree().paused: _input_guided(event)
		return
	if panel.visible and not get_tree().paused and _uses_pc():
		_input_pc(event)
		return
	if not panel.visible or get_tree().paused or not event is InputEventKey or event.echo: return
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit: return
	if not dual and event.is_action("cook_action"):
		lanes[0].input_action("primary", event.pressed)
		get_viewport().set_input_as_handled(); return
	for index: int in (2 if dual else 1):
		var prefix: String = "lane_left_" if index == 0 else "lane_right_"
		for direction: String in ["up", "left", "down", "right"]:
			if not event.is_action(prefix + direction): continue
			var lane: TDCookingLane = lanes[index]
			var kind: String = lane.progress.get("qte_kind", "")
			if kind == "sequence": lane.input_action(direction, event.pressed)
			elif kind == "maintain" and direction in ["left", "right"] and event.pressed:
				var control: float = clampf(float(lane.progress.get("control", .5)) + (-.05 if direction == "left" else .05), 0, 1)
				lane.input_action("adjust", true, control)
				lane._heat.set_value_no_signal(control * 100)
			elif dual and direction == "up": lane.input_action("primary", event.pressed)
			get_viewport().set_input_as_handled()
			return

func set_paused(value: bool) -> void:
	_last_ticks = Time.get_ticks_usec()
	for lane: TDCookingLane in lanes: lane.set_paused(value)
	prep.set_paused(value)
	shared_clock.paused = value
	beat_audio.stream_paused = value
	_paused_label.visible = value
	_pause_button.text = "恢复 Esc" if value else "暂停 Esc"

func close() -> void:
	_closed = true
	world.close()
	for lane: TDCookingLane in lanes: lane.close()
	prep.close(); handling.close(); beat_audio.stop(); beat_audio.stream = null
	set_process(false)
	set_process_input(false)

func _uses_pc() -> bool:
	return prep.pc_controls if prep.visible else lanes[active_lane].pc_controls

func _station_interaction(id: String) -> void:
	if guided_controls: _guided_station(id); return
	var result := TDOutcome.new(false, "NO_ACTION")
	if id == "kitchen.supply.pantry":
		_show_pantry(); return
	if id.begins_with("kitchen.supply."):
		result = handling.pick(id.trim_prefix("kitchen.supply."))
	elif id == "kitchen.board":
		if handling.board != null:
			if handling.board.snapshot().to_dict().state == "operating": open_bench(id); return
			result = handling.take_board()
		else:
			result = handling.put_board()
			if result.ok:
				prep.bind_preparation(handling.board); open_bench(id); return
	elif id == "kitchen.serve":
		if handling.hand_kind == "dish":
			for index: int in lanes.size():
				if lanes[index].session == handling.hand:
					result = lanes[index].perform("deliver")
					if result.ok:
						handling.clear_dish(); active_lane = index; open_bench("kitchen.stove.left" if index == 0 else "kitchen.stove.right")
						_title.text = "试吃反馈 · 根据要求再做一份"
						return
		else: result = TDOutcome.new(false,"NO_DISH","先在灶台出锅，再端着盘子来。")
	else:
		var index: int = 1 if id in ["kitchen.stove.right","kitchen.steamer"] else 0
		if handling.hand_kind == "ingredient":
			result = handling.put_pot(lanes[index].session)
			if result.ok: result.message = "食材已入锅；继续拿料，或空手按 E 开始操作。"
		elif handling.hand != null: result = TDOutcome.new(false,"HANDS_FULL","把成品送到右下方出餐台。")
		elif lanes[index].snapshot().state == "plated": result = handling.take_dish(lanes[index].session)
		else: open_bench(id); return
	_message = result.message if not result.message.is_empty() else ("已完成" if result.ok else lanes[0]._explain_error(result))
	world.set_controls_enabled(true); _update_world()

func _take_and_leave() -> void:
	var result: TDOutcome = handling.take_board() if prep.visible else handling.take_dish(lanes[active_lane].session)
	if result.ok: _message = result.message; close_bench()
	else:
		_title.text = result.message if not result.message.is_empty() else "先完成工序并出锅，再取走"

func _restart_active() -> void:
	if prep.visible:
		_title.text = "备菜可以取消重切；取走后再从料箱拿新食材"
		return
	if handling.hand == lanes[active_lane].session:
		_title.text = "请先交付手上的成品"
		return
	lanes[active_lane].new_session(lanes[active_lane].base_recipe_id)
	_title.text = "新的一份菜 · 返回厨房取料"

func _update_world() -> void:
	var status: Array[String] = []
	var meters: Array=[]
	for index: int in lanes.size():
		var lane: TDCookingLane = lanes[index]
		if lane.thermal_qte != null:
			var p: Dictionary = lane.thermal_progress
			if p.kind=="boil": meters.append({"ratio":float(p.inside_sec)/maxf(.001,float(p.elapsed_sec)),"name":lane.snapshot().recipe_name,"remaining_sec":float(p.remaining_sec)})
			status.append("%s%s · 稳定 %.0f%% · 剩余 %.1fs" % ["左锅" if index == 0 else "右锅", "炖煮" if p.kind == "boil" else "控温", float(p.inside_sec) / maxf(.0001,float(p.elapsed_sec))*100,float(p.remaining_sec)])
	world.set_context(handling.display(), _message, "\n".join(status))
	world.simmer_meters=meters

func _input_pc(event: InputEvent) -> void:
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		var pointer: Vector2 = event.position
		var views: Array[TDCookingLane] = []
		for lane: TDCookingLane in lanes:
			if lane.visible and lane.thermal_qte != null: views.append(lane)
		var in_area: bool = false
		for lane: TDCookingLane in views:
			if lane.temperature_view.get_global_rect().has_point(pointer): in_area = true
		var dragged: bool = (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT: dragged = event.pressed
		for lane: TDCookingLane in views:
			var area: Rect2 = lane.temperature_view.bar_rect()
			if dual: area = Rect2(_row_container.global_position, _row_container.size)
			lane.input_action("drag" if dragged else "hover", in_area, clampf((pointer.x-area.position.x)/maxf(1,area.size.x),0,1))
		return
	if not event is InputEventKey or event.echo: return
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit: return
	var active: Array = [prep] if prep.visible else ([lanes[0],lanes[1]] if dual else [lanes[active_lane]])
	if event.is_action("cook_action"):
		for lane: TDCookingLane in active:
			if lane.qte != null and (active.size() == 1 or lane.qte.accepts_primary() or not event.pressed): lane.input_action("primary",event.pressed)
		get_viewport().set_input_as_handled(); return
	for lane: TDCookingLane in active:
		var prefix: String = "lane_right_" if lane.lane_index == 1 else "lane_left_"
		for direction: String in ["up","left","down","right"]:
			if event.is_action(prefix+direction):
				var action: String = direction
				if lane.progress.get("pc_module") == "M1" and direction in ["left","right"]: action = "rotate_"+direction
				lane.input_action(action,event.pressed)
				get_viewport().set_input_as_handled(); return
	if active.size() == 1 and event.pressed and active[0].qte != null:
		for prefix: String in ["lane_left_","lane_right_"]:
			for direction: String in ["up","left","down","right"]:
				if event.is_action(prefix+direction): active[0].input_action("wrong",true)

func _show_pantry() -> void:
	if is_instance_valid(_supply_panel): _supply_panel.queue_free()
	_supply_panel=PanelContainer.new(); _supply_panel.position=Vector2(430,210); _supply_panel.size=Vector2(420,380); add_child(_supply_panel)
	var column := VBoxContainer.new(); _supply_panel.add_child(column)
	column.add_child(TDUI.label("取一份食材 · 原型供料不限量",20,TDUI.ORANGE))
	for item: Dictionary in _content.ingredients:
		if item.category == "seasoning": continue
		var identity: String=item.id
		var label: String=item.name+(" [TEST_ONLY]" if item.scope == "TEST_ONLY" else "")
		column.add_child(TDUI.button(label,func() -> void:
			if get_tree().paused: return
			var result := handling.pick(identity)
			_message=result.message if not result.message.is_empty() else result.code
			_close_pantry()))
	column.add_child(TDUI.button("返回厨房",_close_pantry))

func _close_pantry() -> void:
	if get_tree().paused: return
	if is_instance_valid(_supply_panel): _supply_panel.queue_free()
	world.set_controls_enabled(true); _update_world()

func _guided_station(id: String) -> void:
	if station_handler.is_valid():
		station_handler.call(id)
		return
	var result := TDOutcome.new(false,"NO_ACTION")
	if id.begins_with("kitchen.supply."):
		var ingredient: String = id.trim_prefix("kitchen.supply.")
		var recipe: String = str(_content.pc_operations.document_rules.preparation_recipes.get(ingredient,lanes[active_lane].base_recipe_id))
		result=handling.pick(ingredient,recipe)
	elif id=="kitchen.board":
		if handling.hand==null and handling.board!=null:
			if prep.qte!=null or (prep.sheet!=null and prep.sheet.running): _open_guided(id); return
			result=handling.take_board()
		else:
			result=handling.put_board()
			if result.ok:
				prep.bind_preparation(handling.board); prep.document_rules=true
				result=prep.start_preparation()
				if result.ok: _open_guided(id); return
	elif id=="kitchen.serve":
		if handling.hand_kind=="dish":
			for i: int in lanes.size():
				if lanes[i].session==handling.hand:
					result=lanes[i].perform("deliver")
					if result.ok:
						handling.clear_dish(); active_lane=i
						_open_guided("kitchen.stove.left" if i==0 else "kitchen.stove.right")
						stage.feedback=lanes[i]._feedback.text; stage.customer_feedback=lanes[i].customer_feedback(); stage.queue_redraw(); return
		else: result=TDOutcome.new(false,"NO_DISH","请把出锅的菜端到出餐台。")
	else:
		var index: int=1 if id in ["kitchen.stove.right","kitchen.steamer"] else 0
		var lane: TDCookingLane=lanes[index]
		if handling.hand_kind=="ingredient":
			if lane.snapshot().state=="delivered": lane.new_session("tomato_egg")
			var item: Dictionary=handling.hand.snapshot().to_dict().ingredients.values()[0]
			if lane.snapshot().ingredients.is_empty():
				var recipe: String="steamed_egg" if id=="kitchen.steamer" else ("beef_stew" if item.ingredient_id=="beef" else "tomato_egg")
				if recipe!=lane.base_recipe_id: lane.new_session(recipe)
			if item.ingredient_id=="tomato" and item.history.is_empty():
				result=TDOutcome.new(false,"PREPARE_FIRST","番茄先到砧板备菜，再搬到锅中。")
			else: result=handling.put_pot(lane.session)
			if result.ok: result.message="已放入锅中 · 备齐食材后空手按 E 开始"
		elif handling.hand!=null: result=TDOutcome.new(false,"HANDS_FULL","先将手上的成品送到出餐台。")
		elif lane.snapshot().state=="plated": result=handling.take_dish(lane.session)
		else:
			if lane.sheet==null or (not lane.sheet.running and lane.qte==null and lane.thermal_qte==null):
				var food: Array=[]
				for item: Dictionary in lane.snapshot().ingredients.values(): food.append(item.ingredient_id)
				var profile: String="steam" if id=="kitchen.steamer" else ("simmer" if "beef" in food else "tomato_egg")
				if food.is_empty() or (profile in ["tomato_egg","steam"] and ("tomato" not in food or "egg" not in food)):
					result=TDOutcome.new(false,"MISSING_PREPARATION","先放入切好的番茄和鸡蛋。" if profile in ["tomato_egg","steam"] else "先将食材放入锅中。")
				else:
					lane.document_rules=true
					# Both pots use separated target bands from the start, so opening
					# the second pot never changes an in-flight controller's target.
					lane.dual=true
					result=lane.start_sheet(profile)
					if result.ok: _open_guided(id); return
			else: _open_guided(id); return
	_message=result.message if not result.message.is_empty() else ("已完成" if result.ok else lanes[0]._explain_error(result))
	world.set_controls_enabled(true); _update_world()

func _open_guided(id: String) -> void:
	_on_board=id=="kitchen.board"
	active_lane=1 if id in ["kitchen.stove.right","kitchen.steamer"] else 0
	if not _on_board: lanes[active_lane].station_role="steamer" if id=="kitchen.steamer" else "stove"
	panel.hide(); world.hide(); world.set_controls_enabled(false)
	stage.feedback=""; stage.customer_feedback=[]; stage.show(); _finished_at=-1
	_refresh_guided()

func _guided_lanes() -> Array:
	if _on_board: return [prep]
	var active: Array=[]
	for lane: TDCookingLane in lanes:
		if lane.qte!=null or lane.thermal_qte!=null or (lane.sheet!=null and lane.sheet.running): active.append(lane)
	if lanes[active_lane] not in active: active.append(lanes[active_lane])
	active.sort_custom(func(a:TDCookingLane,b:TDCookingLane)->bool: return a.lane_index<b.lane_index)
	return active

func _refresh_guided() -> void:
	stage.lanes=_guided_lanes(); stage.beat_sec=shared_clock.qte_sec-lanes[0].beat_offset_sec
	stage.bpm=float(_content.pc_operations.bpm); stage.queue_redraw()
	stage.simmer_meters=world.simmer_meters.duplicate(true)
	if not stage.visible or not stage.feedback.is_empty(): return
	var current: TDCookingLane=prep if _on_board else lanes[active_lane]
	var done: bool=current.sheet!=null and not current.sheet.running and current.qte==null and current.thermal_qte==null
	if done:
		if lesson_mode: return
		if not _on_board:
			for lane: TDCookingLane in lanes:
				if lane.qte!=null or lane.thermal_qte!=null or (lane.sheet!=null and lane.sheet.running): _finished_at=-1; return
		if _finished_at<0: _finished_at=shared_clock.game_sec
		if shared_clock.game_sec-_finished_at>=1.1:
			_message="备菜完成 · 在砧板按 E 取走" if _on_board else "烹饪完成 · 在灶台按 E 端起"
			close_bench()

func _input_guided(event: InputEvent) -> void:
	if event.is_action_pressed("world_interact") and not event.is_echo():
		if lesson_mode: back_requested.emit()
		else: close_bench()
		get_viewport().set_input_as_handled(); return
	if not stage.feedback.is_empty(): return
	var active: Array=_guided_lanes()
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		if _sync_mouse_ownership(): return
		var pointer: Vector2=event.position
		var hovered: bool=false
		for lane: TDCookingLane in active:
			if lane.thermal_qte!=null and stage.thermal_rect(lane.lane_index).grow(22).has_point(pointer): hovered=true
		var dragged: bool=(event.button_mask&MOUSE_BUTTON_MASK_LEFT)!=0
		if event is InputEventMouseButton:
			dragged=event.pressed and event.button_index==MOUSE_BUTTON_LEFT
			if not event.pressed: hovered=false
		for lane: TDCookingLane in active:
			if lane.thermal_qte==null: continue
			var rect: Rect2=stage.thermal_rect(lane.lane_index)
			# Dual bars share a physical x axis; visible target and mouse
			# attraction coordinates must agree in both single and dual views.
			var value: float=(pointer.x-rect.position.x)/rect.size.x
			lane.input_action("drag" if dragged else "hover",hovered,clampf(value,0,1))
		return
	if not event is InputEventKey or event.echo: return
	if event.is_action("cook_action"):
		var accepted: bool=false
		for lane: TDCookingLane in active:
			if lane.qte!=null and (lane.qte.accepts_primary() or not event.pressed): lane.input_action("primary",event.pressed); accepted=true
		if not accepted and event.pressed:
			for lane: TDCookingLane in active:
				if lane.qte!=null and lane.progress.get("pc_module")=="M3": lane.input_action("primary",true)
		get_viewport().set_input_as_handled(); return
	var routed: bool=false
	for lane: TDCookingLane in active:
		var prefix: String="lane_right_" if lane.lane_index==1 else "lane_left_"
		for direction: String in ["up","left","down","right"]:
			if event.is_action(prefix+direction) and lane.qte!=null and lane.progress.get("qte_kind") in ["sequence","rhythm"]:
				var action: String="rotate_"+direction if lane.progress.get("pc_module")=="M1" and direction in ["left","right"] else direction
				lane.input_action(action,event.pressed); routed=true
	if not routed and event.pressed:
		for prefix: String in ["lane_left_","lane_right_"]:
			for direction: String in ["up","left","down","right"]:
				if event.is_action(prefix+direction):
					for lane: TDCookingLane in active:
						if lane.qte!=null: lane.input_action("wrong",true)
	get_viewport().set_input_as_handled()
