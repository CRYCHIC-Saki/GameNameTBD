class_name TDEconomyBoard
extends CanvasLayer

signal closed
signal day_closed

var session: TDPhase3Session
var _label: Label
var _dish_id: String = "mapodoufu"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var panel := Panel.new()
	panel.position = Vector2(24, 16)
	panel.size = Vector2(820, 560)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)
	var box := VBoxContainer.new()
	box.position = Vector2(12, 8)
	box.size = Vector2(796, 544)
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(780, 390)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size = Vector2(760, 0)
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.add_theme_font_size_override("font_size", 15)
	scroll.add_child(_label)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 4)
	box.add_child(row)
	row.add_child(_button("下一天", _next_day))
	row.add_child(_button("房价客流开关", _toggle_housing))
	row.add_child(_button("流水线", func() -> void: _buff("pipeline")))
	row.add_child(_button("近市", func() -> void: _buff("nearby_market")))
	row.add_child(_button("换小镇", _cycle_town))
	row.add_child(_button("菜价-", func() -> void: _price(-1)))
	row.add_child(_button("菜价+", func() -> void: _price(1)))
	row.add_child(_button("换一道菜", _cycle_dish))
	row.add_child(_button("关闭", func() -> void: closed.emit()))
	refresh()

func refresh() -> void:
	if _label == null or session == null or not session.ready:
		return
	var dish := session.catalog.dish(_dish_id)
	var price_line := ""
	if not dish.is_empty():
		price_line = "\n正在改价：%s %d元，参考价%.1f" % [String(dish["name"]), session.price_of(_dish_id), session.catalog.reference_of(_dish_id)]
	_label.text = session.report() + price_line

func _next_day() -> void:
	session.close_day()
	day_closed.emit()
	refresh()

func _toggle_housing() -> void:
	session.set_housing_enabled(session.town_map.housing_enabled() == 0)
	refresh()

func _buff(buff_id: String) -> void:
	session.enable_buff(buff_id)
	refresh()

func _cycle_town() -> void:
	var towns := session.catalog.playable_towns()
	var index := 0
	for item: Variant in towns:
		if String((item as Dictionary)["id"]) == session.town_id:
			break
		index += 1
	var next: Dictionary = towns[(index + 1) % towns.size()]
	session.set_town(String(next["id"]))
	refresh()

func _cycle_dish() -> void:
	var ids := session.recipes.ids()
	if ids.is_empty():
		return
	var index := ids.find(_dish_id)
	_dish_id = ids[(index + 1) % ids.size()] if index >= 0 else ids[0]
	refresh()

func _price(delta: int) -> void:
	if session.catalog.dish(_dish_id).is_empty():
		var ids := session.recipes.ids()
		if ids.is_empty():
			return
		_dish_id = ids[0]
	session.adjust_price(_dish_id, delta)
	session.set_player_pieces(session.player_pieces)
	refresh()

func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(108, 32)
	button.pressed.connect(callback)
	return button
