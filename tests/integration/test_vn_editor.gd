extends GutTest
const PreviewStage := preload("res://addons/td_vn_editor/preview_stage.gd")
const Document := preload("res://addons/td_vn_editor/document.gd")
var stage: TDVisualNovelStage
var draft_path: String

func before_each() -> void:
	draft_path = "res://.godot/td_vn_editor/tests/" + str(Time.get_ticks_usec()) + "/intro/script.txt"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(draft_path.get_base_dir()))

func after_each() -> void:
	if is_instance_valid(stage): stage.reset()
	await get_tree().process_frame
	await get_tree().process_frame
	if FileAccess.file_exists(draft_path): DirAccess.remove_absolute(ProjectSettings.globalize_path(draft_path))

func start(source: String) -> void:
	var file := FileAccess.open(draft_path,FileAccess.WRITE); file.store_string(source); file.close()
	stage = PreviewStage.new(); add_child_autofree(stage)
	# GUT's root viewport is square; use the game's authored 1280 x 800 stage.
	stage.set_anchors_preset(Control.PRESET_TOP_LEFT); stage.size = Vector2(1280,800)
	stage.draft_path = draft_path; stage.start("？？？",true)
	await get_tree().process_frame
	await get_tree().process_frame

func test_real_runtime_plays_unsaved_draft_and_does_not_modify_manifest() -> void:
	var manifest: VNEngineGameManifest = load("res://content/story/vn/config/game.tres")
	await start("# start\n@bg arrival-coast-v1 with instant 0\n@show hero happy at left with instant\nhero: 草稿对白\n# end\n@end\n")
	assert_true(stage.runner is VNEngineStoryRunner)
	assert_eq(stage.runner.current_text,"草稿对白")
	assert_eq(stage.dialog.speaker_label.text,"？？？")
	assert_eq(stage.runner.ctx.characters.active_sprites.size(),1)
	assert_eq(stage.runner.script_res.source_path,draft_path)
	assert_eq(manifest.find_chapter("intro").script_path,Document.INTRO)
	assert_true(VNEngineMain.save_data().memory_only)
	assert_eq(VNEngineMain.save_data().get_save_dir(),"")
	assert_false(VNEngineMain.saves().save_game(stage.runner.state,0))

func test_custom_cg_name_and_restart_release_real_singleton() -> void:
	await start("# start\n@td_cg arrival\n# name\n@td_name hero\n# hi\nhero: 你好，{$hero}\n# done\n@end\n")
	assert_eq(stage.blocked,"td_cg")
	stage.resume_cg(); await get_tree().process_frame
	assert_eq(stage.blocked,"td_name")
	assert_false(stage.submit_name(""))
	assert_true(stage.submit_name("小海")); await get_tree().process_frame
	assert_eq(stage.runner.current_text,"你好，小海")
	assert_eq(stage.dialog.speaker_label.text,"小海")
	stage.reset(); await get_tree().process_frame
	assert_null(VNEngineMain.instance())
	stage.start("？？？",true)
	await get_tree().process_frame; await get_tree().process_frame
	assert_eq(stage.blocked,"td_cg")
	assert_eq(stage.hero_name,"？？？")

func test_choices_use_native_runner() -> void:
	await start("# start\nhero: 去哪里？\n- 港口 -> harbor\n- 留下 -> done\n# harbor\nhero: 看海。\n@jump done\n# done\n@end\n")
	assert_eq(stage.runner.script_res.nodes[0].choices.size(),2)
	assert_eq(stage.runner.current_text,"去哪里？")
	stage.runner.make_choice(int(stage.runner.script_res.labels.harbor))
	await get_tree().process_frame
	assert_eq(stage.runner.current_text,"看海。")

func test_authored_xy_scale_persist_on_lines_skip_and_state_restore() -> void:
	await start("# first\n@bg restaurant-v1 with instant 0\n@show hero happy at td:0.6:0.8:0.8 with instant\nhero: 拖动后\n# second\nhero: 下一句\n# end\n@end\n")
	var actor: Control = stage.runner.ctx.characters.active_sprites.hero
	assert_almost_eq(actor.position.x,573.44,.02)
	assert_almost_eq(actor.position.y,156.0,.02)
	assert_almost_eq(actor.size.x,389.12,.02)
	assert_almost_eq(actor.size.y,484.0,.02)
	stage.runner.is_skip = true; stage.runner.next_node(); stage.runner.is_skip = false
	assert_eq(stage.runner.current_text,"下一句")
	assert_almost_eq(actor.position.y,156.0,.02,"host does not reset authored Y")
	stage.runner.ctx.characters._on_state_restored(stage.runner.state)
	await get_tree().process_frame
	actor = stage.runner.ctx.characters.active_sprites.hero
	assert_almost_eq(actor.position.x,573.44,.02)
	assert_almost_eq(actor.position.y,156.0,.02)
	assert_eq(stage.runner.state.characters.hero.position,"td:0.6:0.8:0.8")
	stage.size = Vector2(640,400)
	await get_tree().process_frame; await get_tree().process_frame
	assert_almost_eq(actor.position.x,286.72,.02)
	assert_almost_eq(actor.position.y,78.0,.02)
	assert_almost_eq(actor.size.x,194.56,.02)
	assert_almost_eq(actor.size.y,242.0,.02)

func test_editor_slide_isolation_matches_native_playback() -> void:
	var doc := Document.new()
	doc.load_text("# first\n@bg arrival-coast-v1 with instant 0\n@show hero calm at left with instant\nhero: 第一页\n# second\nhero: 第二页\n# end\n@end\n")
	doc.set_page_visual(3,"position","hero","td:.6:.8:.8")
	await start(doc.text())
	assert_almost_eq(stage.runner.ctx.characters.active_sprites.hero.position.y,156.0,.02)
	stage.runner.next_node(); await get_tree().process_frame
	assert_eq(stage.runner.current_text,"第二页")
	var actor: Control = stage.runner.ctx.characters.active_sprites.hero
	assert_almost_eq(actor.position.x,76.8,.02)
	assert_almost_eq(actor.position.y,80.0,.02)
