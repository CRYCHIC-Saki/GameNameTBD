extends GutTest
const Document := preload("res://addons/td_vn_editor/document.gd")
const Handoff := preload("res://addons/td_vn_editor/handoff.gd")

func after_each() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

func advance(view: TDDialogueView) -> void:
	view._vn_stage.dialog._reveal_to_end()
	view._vn_stage.dialog._advance_dialog()
	await get_tree().process_frame
	await get_tree().process_frame

func make_view(talk: TDDialogue) -> TDDialogueView:
	var view := TDDialogueView.new()
	add_child_autofree(view)
	view.present(talk)
	await get_tree().process_frame
	await get_tree().process_frame
	return view

func test_all_formal_chapters_preserve_exact_script_beats_and_are_editable() -> void:
	var presentation: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/story/vn/presentation.json"))
	assert_gte(presentation.chapters.size(), 10)
	assert_false(Document.backgrounds(false).has("arrival-coast-v1"), "legacy aliases stay out of the palette")
	assert_true(Document.backgrounds(false).has("town-japan"))
	for id: String in ["intro","soup","after_taste","awaken","verdict_good","verdict_bad","setup","home_invite","home_late","home_door"]:
		var path := str(presentation.chapters[id].path)
		var doc := Document.new()
		assert_eq(doc.open_file(path), "")
		assert_eq(doc.validate(), PackedStringArray(), id)
		assert_true(Handoff.protected_target(path).protected)
		var talk := TDOpeningScript.home_conversation(id, "原名") if id.begins_with("home_") else TDOpeningScript.conversation(id, "原名", 80)
		var script := VNEngineScenarioLoader.load_script(path, null)
		assert_false(script.has_errors(), id)
		var text: Array[String] = []
		for node: VNEngineStoryNode in script.nodes:
			if not node.text.is_empty(): text.append(node.text.replace("{$hero}", "原名").replace("{$san_before}", "80").replace("{$san_after}", "75"))
		var expected: Array[String] = []
		for beat: Dictionary in talk._beats: expected.append(beat.text)
		assert_eq(text, expected, id)
		assert_false(doc.text().contains("@td_cg"), id)
		assert_false(doc.text().contains("@wait"), id)

func test_each_formal_chapter_plays_in_real_native_engine_and_completes_once() -> void:
	for id: String in ["soup", "after_taste", "awaken", "verdict_good", "verdict_bad", "setup", "home_invite", "home_late", "home_door"]:
		var talk := TDOpeningScript.home_conversation(id, "小满") if id.begins_with("home_") else TDOpeningScript.conversation(id, "小满", 80)
		var view := await make_view(talk)
		assert_true(view._native, id)
		assert_true(view._vn_stage.runner is VNEngineStoryRunner)
		var ended: Array = []
		view.closed.connect(func(_text: String, _picks: Array) -> void: ended.append(view.last_completed))
		for _i: int in 45:
			if view.talk == null: break
			await advance(view)
		assert_eq(ended, [true], id)
		assert_eq(view.last_context.get("scene"), id)
		assert_null(VNEngineMain.instance())

func test_dynamic_native_choice_retains_selected_id_and_continues_without_disk_script() -> void:
	var talk := TDDialogue.new()
	talk.story_layout("小满", "chen")
	talk.add_line("老陈", "chen", "要试试吗？")
	talk.add_choice([{"id":"yes", "label":"尝一口", "speaker":"老陈", "portrait":"chen", "text":"请慢用。"}, {"id":"no", "label":"下次吧", "speaker":"老陈", "portrait":"chen", "text":"下次见。"}])
	talk.add_line("阿铃", "aling", "我记下了。")
	var view := await make_view(talk)
	var runner := view._vn_stage.runner
	assert_false(runner.script_res.has_errors())
	await advance(view)
	assert_eq(runner.current_choices.size(), 2)
	runner.make_choice(runner.script_res.index_of("answer_1_0"))
	await get_tree().process_frame
	assert_eq(talk.picks, ["yes"])
	assert_eq(runner.current_text, "尝一口")
	await advance(view)
	assert_eq(runner.current_text, "请慢用。")
	await advance(view)
	assert_eq(runner.current_text, "我记下了。")
	var picked: Array = []
	view.closed.connect(func(_text: String, choices: Array) -> void: picked.append_array(choices))
	await advance(view)
	assert_eq(picked, ["yes"])
	assert_true(view.last_completed)

func test_cancel_dynamic_story_does_not_complete_and_another_talk_can_start() -> void:
	var talk := TDDialogue.new(); talk.story_layout("甲", "aling"); talk.add_line("阿铃", "aling", "还没讲完。")
	var view := await make_view(talk)
	view.finish_now()
	assert_false(view.last_completed)
	assert_null(VNEngineMain.instance())
	view.present(TDOpeningScript.conversation("after_taste", "乙", 62))
	await get_tree().process_frame; await get_tree().process_frame
	assert_eq(view._vn_stage.hero_name, "乙")
	assert_eq(view._vn_stage.runner.state.flags.san_before, "62")
	assert_eq(view._vn_stage.runner.state.flags.san_after, "57")
	view.finish_now()

func test_principal_backgrounds_and_all_existing_portrait_expressions_resolve() -> void:
	for place: String in ["town:chengdu", "town:tokyo", "town:paris", "town:bangkok", "town:mexico_city", "harbor", "restaurant", "cottage"]:
		var id := TDVNPresentation.background_for(place)
		var texture: Texture2D = load("res://content/story/vn/backgrounds/%s.tres" % id)
		assert_not_null(texture, place)
		assert_gt(texture.get_width(), 1200)
	for who: String in TDVNPresentation.ACTORS:
		for mood: String in TDVNPresentation.MOODS:
			assert_true(ResourceLoader.exists(Document.portrait_path(who, mood)))
	var view := await make_view(TDOpeningScript.conversation("intro", "甲", 80))
	assert_eq(view._cg.get_child_count(), 0, "legacy animation scene is never instantiated")
	assert_false(view._cg.visible)
	view.finish_now()
