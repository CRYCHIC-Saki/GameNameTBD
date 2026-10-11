class_name TDPantryBoard
extends CanvasLayer

signal closed

var session: TDPhase3Session
var _label: Label

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
	row.add_child(_button("按这道菜备齐", _prep_dish))
	row.add_child(_button("换一道菜", _cycle_dish))
	row.add_child(_button("备这一份", _prep_one))
	row.add_child(_button("下一种食材", _cycle_item))
	row.add_child(_button("换一类", _cycle_category))
	row.add_child(_button("换设备", _cycle_device))
	row.add_child(_button("关闭", func() -> void: closed.emit()))
	refresh()

func refresh() -> void:
	if _label == null or session == null or not session.ready:
		return
	_label.text = session.pantry_text()

func _prep_dish() -> void:
	session.prep_dish()
	refresh()

func _prep_one() -> void:
	session.prep_selected_ingredient()
	refresh()

func _cycle_dish() -> void:
	session.cycle_pantry_dish()
	refresh()

func _cycle_item() -> void:
	session.cycle_pantry_ingredient()
	refresh()

func _cycle_category() -> void:
	session.cycle_pantry_category()
	refresh()

func _cycle_device() -> void:
	session.cycle_pantry_device()
	refresh()

func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(120, 32)
	button.pressed.connect(callback)
	return button
