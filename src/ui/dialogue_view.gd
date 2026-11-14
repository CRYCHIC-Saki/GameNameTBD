class_name TDDialogueView
extends Control
const CHEF_STAND_IN := preload("res://assets/redraw-v1/chef.png")
## Portrait, dimmed room, and a bottom dialogue box.
## Left click advances. Holding the left button fast-forwards. Skip jumps ahead.

signal closed(last_text: String, picks: Array)

class Portrait extends Control:
	var who: String = "guest"
	var emotion: String = ""
	var action: String = ""

	func _draw() -> void:
		texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
		TDDialogueView.paint_bust(self, who, Rect2(Vector2.ZERO, size),emotion,action)

var talk: TDDialogue
var _pressing: bool = false
var _ignore_release: bool = false
var _portrait: Portrait
var _right_portrait: Portrait
var last_context: Dictionary = {}
var last_completed: bool = false
var _panel: Panel
var _name: Label
var _body: Label
var _hint: Label
var _skip: Button
var _choices: VBoxContainer
var _choice_sig: String = ""
var _dim: ColorRect
var _vn_background: TextureRect
var _cg: TDCutsceneView
var _film_controls: HBoxContainer
var _film_pause: Button
var _skip_clip: Button
var presentation_paused: bool=false
var _arrival_hold: String=""
signal hero_named(value: String)
var _name_entry: HBoxContainer
var _hero_input: LineEdit
var _name_confirmed: bool=false

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
	_vn_background=TextureRect.new();_vn_background.name="VNBackground"
	_vn_background.texture=TDStoryArt.background(0)
	_vn_background.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	_vn_background.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_vn_background.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_vn_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_vn_background);_vn_background.hide()
	_dim = ColorRect.new()
	_dim.name = "Dim"
	_dim.color = Color(0, 0, 0, 0.58)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)
	_cg=TDCutsceneView.new();_cg.position=Vector2.ZERO;_cg.size=Vector2(1280,550);add_child(_cg);_cg.hide()
	_portrait = Portrait.new()
	_portrait.name = "Portrait"
	_portrait.z_index = 0
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_portrait.offset_left = 32.0
	_portrait.offset_right = 308.0
	_portrait.offset_top = -620.0
	_portrait.offset_bottom = -36.0
	add_child(_portrait)
	_right_portrait=Portrait.new()
	_right_portrait.name="RightPortrait"
	_right_portrait.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(_right_portrait)
	var panel := Panel.new()
	_panel=panel
	panel.name = "Box"
	panel.z_index=2
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = 28.0
	panel.offset_right = -28.0
	panel.offset_top = -248.0
	panel.offset_bottom = -18.0
	var plate:=TDUI.parchment(0)
	panel.add_theme_stylebox_override("panel", plate)
	add_child(panel)
	_name = Label.new()
	_name.name = "Speaker"
	_name.position = Vector2(300, 16)
	_name.add_theme_font_size_override("font_size", TDUI.FONT_TITLE)
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
	_body.add_theme_font_size_override("font_size", TDUI.FONT_SECTION)
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
	_hint.add_theme_font_size_override("font_size", TDUI.FONT_CAPTION)
	_hint.add_theme_color_override("font_color", TDUI.MUTED)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_hint)
	_film_controls=HBoxContainer.new();_film_controls.name="FilmControls"
	_film_controls.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_film_controls.offset_left=-310;_film_controls.offset_right=-20
	_film_controls.offset_top=10;_film_controls.offset_bottom=48
	add_child(_film_controls)
	_film_pause=Button.new();_film_pause.text="暂停";_film_pause.focus_mode=Control.FOCUS_NONE
	_film_pause.pressed.connect(toggle_presentation_pause)
	_film_controls.add_child(_film_pause)
	var skip_clip:=Button.new();skip_clip.name="SkipClip";skip_clip.text="跳过本段";skip_clip.focus_mode=Control.FOCUS_NONE
	_skip_clip=skip_clip
	skip_clip.pressed.connect(func()->void:
		if talk!=null and not presentation_paused: talk.skip_cg();_pressing=false;_refresh();_emit_if_finished())
	_film_controls.add_child(skip_clip)
	_name_entry=HBoxContainer.new();_name_entry.name="HeroNameEntry"
	_name_entry.position=Vector2(36,116);panel.add_child(_name_entry)
	_hero_input=LineEdit.new();_hero_input.placeholder_text="你的昵称";_hero_input.max_length=20
	_hero_input.custom_minimum_size=Vector2(450,46);_name_entry.add_child(_hero_input)
	var confirm:=Button.new();confirm.text="报上真名";confirm.focus_mode=Control.FOCUS_NONE
	confirm.pressed.connect(_confirm_hero_name);_name_entry.add_child(confirm)
	_hero_input.text_submitted.connect(func(_value:String)->void:_confirm_hero_name())


func present(next: TDDialogue) -> void:
	talk = next
	presentation_paused=false;_arrival_hold=""
	_name_confirmed=not next.context.get("request_name",false)
	_hero_input.text=""
	talk.begin()
	_pressing = false
	_ignore_release = false
	_choice_sig = ""
	last_context={};last_completed=false
	_apply_layout()
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
	if _cg!=null: _cg.stop_audio()
	visible = false
	set_process(false)
	last_context={};last_completed=false

func dim_alpha() -> float:
	return _dim.color.a if _dim != null else 0.0

func _gui_input(event: InputEvent) -> void:
	if talk == null or presentation_paused or awaiting_name() or not event is InputEventMouseButton:
		return
	var mouse := event as InputEventMouseButton
	if mouse.button_index != MOUSE_BUTTON_LEFT:
		return
	if mouse.pressed and talk.display_kind=="cg":
		_ignore_release=true;accept_event();return
	if not mouse.pressed and _ignore_release:
		_ignore_release=false;_pressing=false;accept_event();return
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
	if talk == null or presentation_paused or awaiting_name():
		return
	var was_film:=talk.display_kind=="cg"
	talk.tick(delta)
	if was_film: _pressing=false
	if _pressing:
		talk.hold(delta, true)
	_refresh()
	_emit_if_finished()

func _on_skip() -> void:
	if talk == null or presentation_paused or awaiting_name():
		return
	if talk.context.get("scene")=="intro":
		if talk.display_kind=="cg": talk.skip_cg()
		else: talk.click()
		_refresh();_emit_if_finished();return
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
	last_context=talk.context.duplicate(true)
	last_completed=not talk.cancelled
	talk = null
	_cg.stop_audio()
	_pressing = false
	visible = false
	set_process(false)
	closed.emit(text, picked)

func _refresh() -> void:
	if talk == null or _name == null:
		return
	_cg.size=size
	var film:=talk.display_kind=="cg"
	var intro: bool=str(talk.context.get("scene",""))=="intro"
	if film and TDArrivalCutscene.SEGMENTS.has(talk.cg_id): _arrival_hold=talk.cg_id
	if intro and not film and not _arrival_hold.is_empty():
		_cg.show_shot(_arrival_hold,TDArrivalCutscene.SPANS[_arrival_hold],TDArrivalCutscene.SPANS[_arrival_hold],true)
		_cg.stop_audio()
	else: _cg.show_shot(talk.cg_id if film else "",talk.cg_elapsed,talk.cg_duration)
	_vn_background.visible=intro and not film
	if intro and not film: _cg.hide()
	_panel.visible=not film;_dim.visible=not film and not intro;_film_controls.visible=film or intro
	_film_pause.text="继续播放" if presentation_paused or talk.cg_paused else "暂停"
	_skip_clip.disabled=not film or presentation_paused
	_cg.set_audio_paused(presentation_paused or talk.cg_paused)

	_portrait.visible=talk.display_kind=="line"
	_right_portrait.visible=talk.presentation=="story" and talk.display_kind=="line"
	# Keep the offscreen call offscreen; reveal Aling only after her entrance clip.
	if intro:
		_portrait.visible=not film
		_right_portrait.visible=not film and talk.display_kind=="line" and _arrival_hold=="messenger"
	_portrait.emotion=talk.left_emotion if talk.presentation=="story" else talk.emotion
	_right_portrait.emotion=talk.right_emotion
	_portrait.action=talk.action if talk.active_side=="left" else ""
	_right_portrait.action=talk.action if talk.active_side=="right" else ""
	_name.text = "演出" if talk.display_kind=="cg" else talk.speaker_name
	_body.text = talk.visible_text()
	if talk.presentation=="story":
		_portrait.who=talk.left_portrait;_right_portrait.who=talk.right_portrait
		_portrait.modulate=Color.WHITE if talk.active_side=="left" else Color(0.42,0.42,0.48)
		_right_portrait.modulate=Color.WHITE if talk.active_side=="right" else Color(0.42,0.42,0.48)
		_portrait.queue_redraw();_right_portrait.queue_redraw()
	elif _portrait != null and _portrait.who != talk.portrait_id:
		_portrait.who = talk.portrait_id
		_portrait.queue_redraw()
	elif _portrait != null and talk.portrait_id == "":
		_portrait.who = "guest"
		_portrait.queue_redraw()
	_portrait.queue_redraw()
	var signature := ""
	for option: Variant in talk.options():
		signature += String((option as Dictionary).get("id", "")) + "|"
	if signature != _choice_sig:
		_choice_sig = signature
		_rebuild_choices()
	_choices.visible = talk.choices_open
	_body.visible = true
	var left:=36.0
	_body.position = Vector2(left, 54)
	var plate := _body.get_parent() as Control
	var plate_width := plate.size.x if plate != null else 1100.0
	_body.size = Vector2(maxf(280.0, plate_width-left-40.0), 46.0 if talk.choices_open else 120.0)
	_choices.position = Vector2(left, 104)
	_panel.offset_top = -248.0
	_hint.position.y = 206.0
	if talk.choices_open:
		var width := maxf(280.0, plate_width-left-40.0)
		var text_height := TDUI.font().get_multiline_string_size(_body.text,HORIZONTAL_ALIGNMENT_LEFT,width,TDUI.FONT_SECTION).y
		_body.size = Vector2(width,maxf(46.0,text_height))
		_choices.position.y = _body.position.y+_body.size.y+12.0
		var replies_height := talk.options().size()*48.0+maxi(0,talk.options().size()-1)*8.0
		_choices.size = Vector2(width,replies_height)
		var plate_height := _choices.position.y+replies_height+54.0
		_panel.offset_top = -plate_height-18.0
		_hint.position.y = plate_height-30.0
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
		_hint.text = "演出中… 可点跳过" if talk.display_kind=="cg" and talk.cg_elapsed<talk.cg_duration else "点击继续。长按鼠标左键快进。"
		_skip.text = "跳过"
		_skip.disabled = false

	_name_entry.visible=awaiting_name()
	if intro and not film: _skip.text="继续"
	if awaiting_name():
		_skip.disabled=true;_body.text="我的名字是……";_hint.text="输入昵称后报上真名。"

func awaiting_name() -> bool:
	return talk!=null and talk.action=="enter_name" and not _name_confirmed

func _confirm_hero_name() -> void:
	if not awaiting_name() or presentation_paused: return
	if talk.name_hero(_hero_input.text):
		_name_confirmed=true;hero_named.emit(talk.hero_name);_hero_input.release_focus();_refresh()

func toggle_presentation_pause() -> void:
	if talk==null: return
	presentation_paused=not presentation_paused
	_pressing=false;talk.pointer_down()
	talk.pause_cg(presentation_paused)
	_refresh()

func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT and visible and talk!=null and not presentation_paused:
		toggle_presentation_pause()

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
		button.custom_minimum_size = Vector2(640, 48)
		button.pressed.connect(_choose.bind(id))
		_choices.add_child(button)

func _choose(id: String) -> void:
	if talk == null or presentation_paused:
		return
	talk.pick(id)
	_choice_sig = ""
	_refresh()

func _apply_layout() -> void:
	var story_mode:=talk.presentation=="story"
	_right_portrait.visible=story_mode
	_portrait.modulate=Color.WHITE
	_portrait.z_index=0;_right_portrait.z_index=0
	_portrait.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_portrait.offset_left=-32.0;_portrait.offset_right=728.0
	_portrait.offset_top=-760.0;_portrait.offset_bottom=0.0
	_right_portrait.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_right_portrait.offset_left=-728.0;_right_portrait.offset_right=32.0
	_right_portrait.offset_top=-760.0;_right_portrait.offset_bottom=0.0
	_name.position.x=36.0
	_hint.position.x=_name.position.x
	_choices.size.x=1080.0

static func paint_bust(canvas: CanvasItem, who: String, box: Rect2, emotion: String="", action: String="") -> void:
	if box.size.x < 8.0 or box.size.y < 8.0:
		return
	var art:=TDStoryArt.portrait(who,emotion,action)
	if art!=null:
		canvas.draw_texture_rect(art,TDStoryArt.fit(art,box),false)
		if who=="aling": TDStoryArt.paint_ledger_title(canvas,art,box)
		return
	var cloth := Color("#3f6f8f")
	var hair := Color("#243038")
	var accent := Color("#d7e4ea")
	if who.begins_with("guest"):
		var guest_art:=TDDinerArt.portrait(int(who.trim_prefix("guest")))
		canvas.draw_texture_rect(guest_art,TDStoryArt.fit(guest_art,box),false)
		return
	if who == "aling":
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
	if who=="crowd":
		canvas.draw_circle(box.get_center()-Vector2(0,70),65,Color("232c32"));canvas.draw_rect(Rect2(box.get_center()-Vector2(90,10),Vector2(180,220)),Color("232c32"));return
	if who in ["luo", "page"]:
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

