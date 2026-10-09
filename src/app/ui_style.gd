class_name TDUI
extends RefCounted

const INK := Color("#eff0dc")
const MUTED := Color("#b0c5bc")
const TEAL := Color("#213f3d")
const ORANGE := Color("#ecb36e")

static func theme() -> Theme:
	var result := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC"])
	result.default_font = font
	result.default_font_size = 18
	result.set_color("font_color", "Label", INK)
	result.set_color("font_color", "Button", INK)
	for state: String in ["normal", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#355d56") if state == "hover" else TEAL
		style.border_color = ORANGE if state == "focus" else Color("#507064")
		style.set_border_width_all(1)
		style.set_corner_radius_all(10)
		style.content_margin_left = 20
		style.content_margin_right = 20
		style.content_margin_top = 12
		style.content_margin_bottom = 12
		result.set_stylebox(state, "Button", style)
	return result

static func label(text: String, size: int = 18, color: Color = INK) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return node

static func button(text: String, callback: Callable) -> Button:
	var node := Button.new()
	node.text = text
	node.custom_minimum_size.y = 48
	node.focus_mode = Control.FOCUS_NONE
	node.pressed.connect(callback)
	return node

static func column(parent: Node, spacing: int = 16) -> VBoxContainer:
	var node := VBoxContainer.new()
	node.add_theme_constant_override("separation", spacing)
	parent.add_child(node)
	return node
