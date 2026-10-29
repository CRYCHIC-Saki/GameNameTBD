class_name TDDialogueView
extends Control
const CHEF_STAND_IN := preload("res://assets/kitchen/chef-v1.png")
## Portrait, dimmed room, and a bottom dialogue box.
## Left click advances. Holding the left button fast-forwards. Skip jumps ahead.

signal closed(last_text: String, picks: Array)

class Portrait extends Control:
	var who: String = "guest"

	func _draw() -> void:
		TDDialogueView.paint_bust(self, who, Rect2(Vector2.ZERO, size))

var talk: TDDialogue
var _pressing: bool = false
var _portrait: Portrait
var _name: Label
var _body: Label
var _hint: Label
var _skip: Button
var _choices: VBoxContainer
var _choice_sig: String = ""
var _dim: ColorRect

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	theme = TDUI.theme()
	visible = false
	set_process(false)
	_dim = ColorRect.new()
	_dim.name = "Dim"
	_dim.color = Color(0, 0, 0, 0.58)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)
	_portrait = Portrait.new()
	_portrait.name = "Portrait"
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_portrait.offset_left = 48.0
	_portrait.offset_right = 348.0
	_portrait.offset_top = -620.0
	_portrait.offset_bottom = -36.0
	add_child(_portrait)
	var panel := Panel.new()
	panel.name = "Box"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = 28.0
	panel.offset_right = -28.0
	panel.offset_top = -248.0
	panel.offset_bottom = -18.0
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color(0.08, 0.07, 0.06, 0.94)
	plate.border_color = Color("#ecb36e")
	plate.set_border_width_all(2)
	plate.set_corner_radius_all(12)
	panel.add_theme_stylebox_override("panel", plate)
	add_child(panel)
	_name = Label.new()
	_name.name = "Speaker"
	_name.position = Vector2(300, 16)
	_name.add_theme_font_size_override("font_size", 26)
	_name.add_theme_color_override("font_color", TDUI.ORANGE)
	panel.add_child(_name)
	_skip = Button.new()
	_skip.name = "Skip"
	_skip.text = "跳过"
	_skip.focus_mode = Control.FOCUS_NONE
	_skip.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_skip.offset_left = -124.0
	_skip.offset_right = -16.0
	_skip.offset_top = 12.0
	_skip.offset_bottom = 54.0
	_skip.pressed.connect(_on_skip)
	panel.add_child(_skip)
	_body = Label.new()
	_body.name = "Body"
	_body.position = Vector2(300, 58)
	_body.size = Vector2(760, 78)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_theme_font_size_override("font_size", 22)
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_body)
	_choices = VBoxContainer.new()
	_choices.name = "Choices"
	_choices.position = Vector2(300, 112)
	_choices.size = Vector2(760, 120)
	_choices.add_theme_constant_override("separation", 8)
	_choices.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_choices)
	_hint = Label.new()
	_hint.name = "Hint"
	_hint.position = Vector2(300, 206)
	_hint.add_theme_font_size_override("font_size", 14)
	_hint.add_theme_color_override("font_color", TDUI.MUTED)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_hint)

func present(next: TDDialogue) -> void:
	talk = next
	talk.begin()
	_pressing = false
	_choice_sig = ""
	if _portrait != null:
		_portrait.who = talk.portrait_id
		_portrait.queue_redraw()
	visible = true
	set_process(true)
	_refresh()

func finish_now() -> void:
	if talk == null:
		return
	talk.force_close()
	_emit_if_finished()

func dismiss() -> void:
	_pressing = false
	talk = null
	visible = false
	set_process(false)

func dim_alpha() -> float:
	return _dim.color.a if _dim != null else 0.0

func _gui_input(event: InputEvent) -> void:
	if talk == null or not event is InputEventMouseButton:
		return
	var mouse := event as InputEventMouseButton
	if mouse.button_index != MOUSE_BUTTON_LEFT:
		return
	if mouse.pressed:
		_pressing = true
		talk.pointer_down()
	else:
		_pressing = false
		talk.release()
		_refresh()
		_emit_if_finished()
	accept_event()

func _process(delta: float) -> void:
	if talk == null:
		return
	talk.tick(delta)
	if _pressing:
		talk.hold(delta, true)
	_refresh()
	_emit_if_finished()

func _on_skip() -> void:
	if talk == null:
		return
	if talk.exhausted:
		talk.click()
	else:
		talk.skip()
	_refresh()
	_emit_if_finished()

func _emit_if_finished() -> void:
	if talk == null or not talk.finished:
		return
	var text := talk.full_text()
	var picked: Array = talk.picks.duplicate()
	talk = null
	_pressing = false
	visible = false
	set_process(false)
	closed.emit(text, picked)

func _refresh() -> void:
	if talk == null or _name == null:
		return
	_name.text = talk.speaker_name
	_body.text = talk.visible_text()
	if _portrait != null and _portrait.who != talk.portrait_id:
		_portrait.who = talk.portrait_id
		_portrait.queue_redraw()
	elif _portrait != null and talk.portrait_id == "":
		_portrait.who = "guest"
		_portrait.queue_redraw()
	var signature := ""
	for option: Variant in talk.options():
		signature += String((option as Dictionary).get("id", "")) + "|"
	if signature != _choice_sig:
		_choice_sig = signature
		_rebuild_choices()
	_choices.visible = talk.choices_open
	_body.visible = true
	_body.position = Vector2(300, 54)
	var plate := _body.get_parent() as Control
	var plate_width := plate.size.x if plate != null else 1100.0
	_body.size = Vector2(maxf(280.0, plate_width - 340.0), 46.0 if talk.choices_open else 120.0)
	_choices.position = Vector2(300, 104)
	if talk.choices_open:
		_hint.text = "请点选一句回复。跳过要等选完。"
		_skip.text = "跳过"
		_skip.disabled = true
	elif talk.exhausted:
		_hint.text = "点击鼠标左键，或按「关闭」。"
		_skip.text = "关闭"
		_skip.disabled = false
	elif talk.shown < talk.body.length():
		_hint.text = "点击显示完这句。长按鼠标左键快进。"
		_skip.text = "跳过"
		_skip.disabled = false
	else:
		_hint.text = "点击继续。长按鼠标左键快进。"
		_skip.text = "跳过"
		_skip.disabled = false

func _rebuild_choices() -> void:
	if _choices == null:
		return
	while _choices.get_child_count() > 0:
		var child := _choices.get_child(0)
		_choices.remove_child(child)
		child.free()
	if talk == null:
		return
	for option: Variant in talk.options():
		var item: Dictionary = option
		var id := String(item.get("id", ""))
		var button := Button.new()
		button.text = String(item.get("label", id))
		button.focus_mode = Control.FOCUS_NONE
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(640, 42)
		button.pressed.connect(_choose.bind(id))
		_choices.add_child(button)

func _choose(id: String) -> void:
	if talk == null:
		return
	talk.pick(id)
	_choice_sig = ""
	_refresh()

static func paint_bust(canvas: CanvasItem, who: String, box: Rect2) -> void:
	if box.size.x < 8.0 or box.size.y < 8.0:
		return
	var cloth := Color("#3f6f8f")
	var hair := Color("#243038")
	var accent := Color("#d7e4ea")
	if who == "linxia":
		cloth = Color("#e07a3a")
		hair = Color("#3a2418")
		accent = Color("#f2c14e")
	elif who == "aling":
		cloth = Color("#24344a")
		hair = Color("#1b1a24")
		accent = Color("#8ea0c0")
	elif who == "chen":
		cloth = Color("#8a6238")
		hair = Color("#4a4038")
		accent = Color("#d7c4a2")
	elif who == "luo":
		cloth = Color("#3a2428")
		hair = Color("#17141c")
		accent = Color("#c6a15a")
	if who in ["aling", "chen", "luo", "page"]:
		_paint_stand_in(canvas, who, box)
		return
	canvas.draw_rect(box, Color(0.12, 0.1, 0.09, 0.55))
	var ground := box.position + Vector2(box.size.x * 0.5, box.size.y * 0.92)
	canvas.draw_rect(Rect2(ground + Vector2(-70, -210), Vector2(140, 210)), cloth)
	canvas.draw_rect(Rect2(ground + Vector2(-78, -188), Vector2(156, 22)), accent)
	var head := ground + Vector2(0, -250)
	canvas.draw_circle(head, 58, Color("#f2d3b5"))
	canvas.draw_rect(Rect2(head + Vector2(-62, -78), Vector2(124, 70)), hair)
	canvas.draw_rect(Rect2(head + Vector2(-64, -20), Vector2(22, 64)), hair)
	canvas.draw_circle(head + Vector2(-18, -2), 4, Color("#2a211c"))
	canvas.draw_circle(head + Vector2(18, -2), 4, Color("#2a211c"))
	canvas.draw_rect(Rect2(head + Vector2(-16, 22), Vector2(32, 4)), Color("#c48b78"))

static func _paint_stand_in(canvas: CanvasItem, who: String, box: Rect2) -> void:
	var paper := who == "page"
	canvas.draw_rect(box, Color("#f4ecd8") if paper else Color(0.1, 0.08, 0.07, 0.35))
	var fit := box.size.y * 0.72
	var portrait := Rect2(box.position + Vector2((box.size.x - fit) * 0.5, box.size.y * 0.08), Vector2(fit, fit))
	canvas.draw_texture_rect(CHEF_STAND_IN, portrait, false)
	if paper:
		canvas.draw_rect(box.grow(-4), Color("#8a6238"), false, 3.0)

