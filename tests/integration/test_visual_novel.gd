extends GutTest

func after_each() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

func make_view(request_name: bool = true) -> TDDialogueView:
	var view := TDDialogueView.new()
	add_child_autofree(view)
	var conversation := TDOpeningScript.conversation("intro", "？？？", 80)
	conversation.context.request_name = request_name
	view.present(conversation)
	view.set_process(false)
	await get_tree().process_frame
	await get_tree().process_frame
	return view

func advance(view: TDDialogueView) -> void:
	view._vn_stage.dialog._advance_dialog()
	view._vn_stage.dialog._advance_dialog()
	await get_tree().process_frame

func to_name(view: TDDialogueView) -> void:
	view._process(14.0)
	await get_tree().process_frame
	await advance(view)
	view._process(6.0)
	await get_tree().process_frame
	await advance(view)
	await advance(view)
	view._process(10.0)
	await get_tree().process_frame
	await advance(view)

func test_real_plugin_runtime_and_native_scenario_drive_opening() -> void:
	var view := await make_view()
	var stage := view._vn_stage
	assert_true(stage.main is VNEngineMain)
	assert_true(stage.runner is VNEngineStoryRunner)
	assert_true(stage.dialog is VNEngineDialogUI)
	assert_true(stage.runner.ctx.background is VNEngineBackgroundSystem)
	assert_true(stage.runner.script_res.source_path.ends_with("scenario/intro/script.txt"))
	assert_false(stage.runner.script_res.has_errors())
	assert_eq(stage.blocked, "td_cg")
	assert_true(view._cg.visible)
	view._process(14.0)
	await get_tree().process_frame
	assert_false(view._cg.visible)
	assert_eq(stage.runner.current_text, "终于到了。吾之舌啊，准备迎接万国料理的洗礼！")
	assert_eq(stage.dialog.speaker_label.text, "？？？")
	assert_eq(stage.runner.ctx.background.current_layer.texture.resource_path, "res://content/story/vn/backgrounds/arrival-coast-v1.tres")
	var background := stage.runner.ctx.background.current_layer.texture as AtlasTexture
	assert_not_null(background)
	assert_eq(background.atlas.resource_path, "res://assets/redraw-v1/backgrounds.png")
	var hero := stage.runner.ctx.characters.active_sprites["hero"] as VNEngineCharacterSprite
	var portrait := hero.sprite.texture as AtlasTexture
	assert_eq(portrait.atlas.resource_path, "res://assets/ui-wood-v1/portrait-hero-v2.png")
	assert_true(stage.dialog.background_box.get_theme_stylebox("panel") is StyleBoxTexture)
	assert_true(stage.runner.ctx.characters.active_sprites.has("hero"))
	assert_false(stage.runner.ctx.characters.active_sprites.has("aling"))
	view.finish_now()

func test_cg_name_blocks_survive_auto_skip_and_duplicate_completion() -> void:
	var view := await make_view()
	var stage := view._vn_stage
	var names: Array = []; var ended: Array = []
	view.hero_named.connect(func(value: String) -> void: names.append(value))
	view.closed.connect(func(_text: String, _picks: Array) -> void: ended.append(view.last_completed))
	var index := stage.runner.current_index
	stage.runner.next_node(); stage.dialog._on_auto_timer_timeout()
	assert_eq(stage.runner.current_index, index, "real runner cannot bypass CG")
	await to_name(view)
	assert_true(view.awaiting_name())
	assert_true(stage.runner.ctx.characters.active_sprites.has("aling"))
	index = stage.runner.current_index
	stage.runner.next_node(); stage.dialog._on_auto_timer_timeout(); view._process(100)
	assert_eq(stage.runner.current_index, index)
	view._hero_input.text = " "; view._confirm_hero_name()
	assert_true(view.awaiting_name())
	view._hero_input.text = "海风"; view._confirm_hero_name(); view._confirm_hero_name()
	await get_tree().process_frame
	assert_eq(names, ["海风"])
	assert_eq(stage.dialog.speaker_label.text, "海风")
	assert_true(stage.runner.current_text.contains("海风"))
	await advance(view); await advance(view)
	await get_tree().process_frame
	assert_eq(ended, [true])
	view._close_native(true)
	assert_eq(ended, [true])
	assert_null(VNEngineMain.instance())

func test_host_has_no_secondary_save_or_rollback_authority() -> void:
	var view := await make_view(false)
	var stage := view._vn_stage
	var data := VNEngineMain.save_data()
	assert_true(data.memory_only)
	assert_eq(data.get_save_dir(), "")
	assert_false(VNEngineMain.saves().save_game(stage.runner.state, 0))
	assert_null(VNEngineMain.saves().load_game(0))
	assert_eq(VNEngineMain.saves().get_slot_status(0), VNEngineSaveData.SlotStatus.EMPTY)
	data.write_flow_snapshot("test", {"value": 1})
	assert_eq(data.read_flow_snapshot("test"), {"value": 1})
	var index := stage.runner.current_index
	stage.runner.rollback(); stage.runner.forward(); stage.runner.execute_load_game(0)
	assert_eq(stage.runner.current_index, index)
	assert_true(stage.main.host_managed)
	view.finish_now()

func test_pause_cancel_restart_discards_old_resume_and_template_name() -> void:
	var view := await make_view()
	view._process(2.0); view.toggle_presentation_pause(); view._process(99.0)
	assert_eq(view.talk.cg_elapsed, 2.0)
	assert_eq(view._vn_stage.main.process_mode, Node.PROCESS_MODE_DISABLED)
	var generation := view._vn_stage._generation
	view.finish_now()
	assert_false(view.last_completed)
	assert_null(VNEngineMain.instance())
	var conversation := TDOpeningScript.conversation("intro", "另一个人", 80)
	view.present(conversation); view.set_process(false)
	await get_tree().process_frame
	view._vn_stage._resume(generation)
	assert_eq(view._vn_stage.blocked, "td_cg")
	assert_eq(view.talk.cg_elapsed, 0.0)
	assert_eq((load("res://content/story/vn/config/characters/_characters.tres") as VNEngineCast).display_name_of("hero"), "？？？")
	view.dismiss()
	assert_null(VNEngineMain.instance())
	var daily := TDDialogue.new(); daily.add_line("老陈", "chen", "来，坐下聊聊。")
	view.present(daily); view.set_process(false)
	assert_false(view._native)
	assert_true(view.get_node("Portrait").visible)
	assert_true(view._skip.visible, "ordinary conversation controls restored")
	view.finish_now()

func test_native_source_preserves_all_opening_dialogue_and_three_films() -> void:
	var script := VNEngineScenarioLoader.load_script("res://content/story/vn/scenario/intro/script.txt", null)
	assert_false(script.has_errors())
	var texts: Array = []; var films: Array = []; var names: int = 0
	for node: VNEngineStoryNode in script.nodes:
		if not node.text.is_empty(): texts.append(node.text.replace("{$hero}", "{hero}"))
		for command: Dictionary in node.commands:
			if command.name == "td_cg": films.append(command.args)
			if command.name == "td_name": names += 1
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/story/opening.json"))
	var expected: Array = []
	for beat: Dictionary in source.scenes.intro:
		if beat.kind == "line": expected.append(beat.text)
	assert_eq(texts, expected)
	assert_eq(films, ["arrival", "hungry", "messenger"])
	assert_eq(names, 1)

func test_cancel_before_deferred_plugin_start_does_not_hijack_replay() -> void:
	var view := TDDialogueView.new(); add_child_autofree(view)
	view.present(TDOpeningScript.conversation("intro", "甲", 80))
	view.finish_now()
	view.present(TDOpeningScript.conversation("intro", "乙", 80)); view.set_process(false)
	await get_tree().process_frame; await get_tree().process_frame
	assert_eq(VNEngineMain.instance(), view._vn_stage.main)
	assert_eq(view._vn_stage.blocked, "td_cg")
	assert_eq(view._vn_stage.hero_name, "乙")
	view.finish_now()

func test_reading_log_is_read_only_and_paused_typewriter_freezes() -> void:
	var view := await make_view()
	view._process(14.0); await get_tree().process_frame
	var stage := view._vn_stage
	view.toggle_presentation_pause()
	var shown := stage.dialog.dialog_label.visible_characters
	await get_tree().create_timer(.12).timeout
	assert_eq(stage.dialog.dialog_label.visible_characters, shown)
	view.toggle_presentation_pause()
	stage.dialog._reveal_to_end()
	var index := stage.runner.current_index
	stage.main.screen_stack.current_screen()._on_log_requested()
	await get_tree().process_frame
	var log := stage.main.overlay_stack.top_overlay() as VNEngineLogUI
	assert_not_null(log)
	assert_eq(log.runner, stage.runner)
	assert_gt(log.log_container.get_child_count(), 0)
	assert_eq(log.close_btn.text, "返回剧情")
	log.close_btn.pressed.emit()
	await get_tree().create_timer(.25).timeout
	assert_true(stage.main.overlay_stack.is_empty())
	assert_eq(stage.runner.current_index, index)
	view.finish_now()

func test_memory_only_data_never_creates_disk_directory() -> void:
	var path := "res://artifacts/vn-runtime-20261113/must-not-exist-%d" % Time.get_ticks_usec()
	var data := VNEngineSaveData.new(path, true)
	data.mark_line_seen("intro", "first")
	data.write_flow_snapshot("intro", {"hero":"甲"})
	data.flush()
	assert_true(data.is_line_seen("intro", "first"))
	assert_eq(data.read_flow_snapshot("intro"), {"hero":"甲"})
	assert_false(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path)))
