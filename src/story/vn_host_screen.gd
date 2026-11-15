extends VNEngineStageScreen
## Local layout/host hooks; parsing, progression and dialogue remain VN Engine.

func _ready() -> void:
	super._ready()
	theme = TDUI.theme().duplicate()
	theme.default_font_size = TDUI.FONT_SECTION
	for child: Node in $CanvasLayer.get_children():
		if child is Control: child.theme = theme
	story_runner.ctx.dialog_ui._apply_text_scale()
	var dialog := story_runner.ctx.dialog_ui
	dialog.background_box.add_theme_stylebox_override("panel", TDUI.parchment(0))
	dialog.name_plate.add_theme_stylebox_override("panel", TDUI.wood(TDUI.Surface.CARD, 8))
	dialog.speaker_label.add_theme_color_override("font_color", TDUI.ORANGE)
	dialog.dialog_label.add_theme_color_override("default_color", TDUI.INK)
	dialog.get_node("ContinueIndicator").add_theme_color_override("font_color", TDUI.MUTED)
	for key: String in ["SettingsMargin", "QSaveMargin", "QLoadMargin", "SaveMargin", "LoadMargin", "MenuMargin", "ChoiceSkipMargin"]:
		in_game_buttons.get_node(key).hide()
	in_game_buttons.auto_btn.text = "自动"
	in_game_buttons.skip_btn.text = "快进"
	in_game_buttons.log_btn.text = "回看"
	story_runner.ctx.characters.cast = story_runner.ctx.characters.cast.duplicate(true)
	for member: VNEngineCastMember in story_runner.ctx.characters.cast.characters:
		member.name_color = TDUI.ORANGE
	story_runner.mode_changed.connect(_sync_bar_colors)
	_sync_bar_colors()
	VNEngineMain.instance().get_meta("host").attach_stage(self)

func _sync_bar_colors() -> void:
	# Native controls keep their behavior; host ink stays legible on parchment.
	for button: Button in [in_game_buttons.auto_btn, in_game_buttons.skip_btn, in_game_buttons.log_btn]:
		var active: bool = (button == in_game_buttons.auto_btn and story_runner.is_auto) or (button == in_game_buttons.skip_btn and story_runner.is_skip)
		for key: String in ["font_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color", "font_hover_color"]:
			button.add_theme_color_override(key, TDUI.ORANGE if active else TDUI.INK)

func handle_back() -> bool:
	return false

func open_game_menu() -> void:
	pass # Host pause/menu owns scene lifetime and saving.

func _on_log_requested() -> void:
	var log := VNEngineMain.game().open_overlay(&"log", {"runner": story_runner}) as VNEngineLogUI
	if log != null: log.close_btn.text = "返回剧情"
