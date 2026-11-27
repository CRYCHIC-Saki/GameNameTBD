extends Control

const GAME := "res://src/app/main.tscn"
const LOADING_ART := preload("res://assets/title/加载界面.png")
const PANEL_BACKGROUND := Color("#501d1d")
var _game: PackedScene
var _prompt: Label
var _starting := false

func _ready() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = PANEL_BACKGROUND
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var art := TextureRect.new()
	art.texture = LOADING_ART
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(art)
	_make_prompt()
	_load_game.call_deferred()

func _make_prompt() -> void:
	_prompt = TDUI.label("", 23, Color("#fff4d9"))
	_prompt.name = "StartPrompt"
	_prompt.add_theme_color_override("font_outline_color", Color("#501d1d"))
	_prompt.add_theme_constant_override("outline_size", 4)
	_prompt.add_theme_color_override("font_shadow_color", Color("#43140e"))
	_prompt.add_theme_constant_override("shadow_offset_x", 2)
	_prompt.add_theme_constant_override("shadow_offset_y", 2)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.offset_left = -260
	_prompt.offset_right = 260
	_prompt.offset_top = -63
	_prompt.offset_bottom = -20
	_prompt.hide()
	add_child(_prompt)

func _load_game() -> void:
	# Render the cover before loading the scene graph and its map textures.
	await get_tree().process_frame
	await get_tree().process_frame
	var scene := load(GAME) as PackedScene
	await get_tree().process_frame
	_game = scene
	_prompt.text = "Press to Start..." if _game != null else "游戏加载失败"
	_prompt.show()

func _input(event: InputEvent) -> void:
	if _game == null or _starting or not event.is_pressed() or event.is_echo():
		return
	if event is InputEventMouseButton and event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton or event is InputEventScreenTouch:
		_starting = true
		get_viewport().set_input_as_handled()
		get_tree().change_scene_to_packed(_game)
