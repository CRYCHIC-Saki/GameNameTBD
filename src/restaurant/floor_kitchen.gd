class_name TDFloorKitchen
extends Control

signal restaurant_requested
signal pause_requested
signal look_requested

const KITCHEN := preload("res://src/kitchen/full_kitchen.tscn")

var session: TDPhase3Session
var kitchen: TDFullKitchen
var _restaurant: TDRestaurantWorld
var _orders: Label
var _note: Label
var _service := TDServiceCatalog.new()
var _scorer := TDCustomerScorer.new()
var _built: bool = false

func open_for(restaurant: TDRestaurantWorld) -> void:
	_restaurant = restaurant
	if restaurant != null and restaurant.session != null:
		session = restaurant.session
	if not _built:
		_build()
	_refresh_orders()
	set_active(true)

func set_active(active: bool) -> void:
	visible = active
	_set_input_tree(self, active)
	if kitchen != null and kitchen.world != null:
		kitchen.world.set_controls_enabled(active)

func set_paused(value: bool) -> void:
	if kitchen != null:
		kitchen.set_paused(value)

func close() -> void:
	set_active(false)
	if kitchen != null:
		kitchen.close()

func _build() -> void:
	_built = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var loaded := _service.load_file()
	if not loaded.ok:
		_note = TDUI.label(loaded.message, 18)
		_note.position = Vector2(24, 24)
		add_child(_note)
		return
	var learned: Array = []
	if session != null:
		learned = session.learned_kitchen_dishes()
	TDKitchenLink.install(_service, learned)
	var config := _service.with_plans([])
	var catalog := TDCookingCatalog.new()
	if not config.ok or not catalog.load_data(config.data, "floor kitchen").ok:
		_note = TDUI.label("后厨菜谱没装上。", 18)
		_note.position = Vector2(24, 24)
		add_child(_note)
		return
	kitchen = KITCHEN.instantiate() as TDFullKitchen
	kitchen.catalog = catalog
	kitchen.scorer = _scorer
	kitchen.single_fridge = true
	kitchen.library_path = "user://floor-kitchen.unused-library"
	kitchen.day_san = float(session.san) if session != null else -1.0
	add_child(kitchen)
	if session != null:
		kitchen.handling.session_namespace = "floor-d%d:" % session.day
	kitchen.back_requested.connect(func() -> void: restaurant_requested.emit())
	kitchen.pause_requested.connect(func() -> void: pause_requested.emit())
	kitchen.dish_delivered.connect(_on_dish)
	kitchen.world.service_door = true
	kitchen.world.set_return_visible(true)
	kitchen.world.set_return_label("回餐厅")
	kitchen.world.dining_requested.connect(func() -> void: restaurant_requested.emit())
	var panel := Panel.new()
	panel.position = Vector2(968, 78)
	panel.size = Vector2(292, 700)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.z_index = 30
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.14, 0.13, 0.94)
	style.border_color = Color("c5a46c")
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var box := VBoxContainer.new()
	box.position = Vector2(12, 10)
	box.size = Vector2(268, 680)
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	box.add_child(TDUI.label("餐厅里的客人", 20, TDUI.ORANGE))
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	box.add_child(actions)
	actions.add_child(TDUI.button("回餐厅", func() -> void: restaurant_requested.emit()))
	actions.add_child(TDUI.button("看一眼", func() -> void: look_requested.emit()))
	_orders = TDUI.label("", 15)
	_orders.custom_minimum_size = Vector2(268, 420)
	_orders.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_orders)
	_note = TDUI.label("走到下方门口按 E，或点回餐厅。V 只看店里，时间继续走。出餐后菜放在餐厅传菜口，要端到客人坐下的那一桌。", 14, TDUI.MUTED)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size = Vector2(268, 96)
	box.add_child(_note)

func _process(_delta: float) -> void:
	if visible:
		_refresh_orders()

func _refresh_orders() -> void:
	if _orders == null:
		return
	if session == null or session.floor == null:
		_orders.text = "还没有餐厅订单。"
		return
	_orders.text = "\n".join(session.floor.live_lines())

func _on_dish(dish: Dictionary) -> void:
	if _restaurant == null:
		return
	var recipe_id := String(dish.get("recipe_id", ""))
	var dish_id := ""
	if session != null:
		dish_id = session.catalog.dish_id_for_kitchen(recipe_id)
	var quality := _quality_of(dish)
	var failed := bool(dish.get("failed_dish", false))
	var result := _restaurant.deliver_to_guest(dish_id, quality, failed)
	if _note != null:
		_note.text = result.message

func _quality_of(dish: Dictionary) -> float:
	var rated := _scorer.evaluate(dish, {"requirements": []})
	if rated.ok:
		return float((rated.data as Dictionary)["satisfaction"])
	if bool(dish.get("failed_dish", false)):
		return 35.0
	return 70.0

func _set_input_tree(node: Node, enabled: bool) -> void:
	node.set_process_unhandled_input(enabled)
	node.set_process_input(enabled)
	for child: Node in node.get_children():
		_set_input_tree(child, enabled)
