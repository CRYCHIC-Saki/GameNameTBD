extends GutTest
const Driver := preload("res://tools/test_support/native_dialogue.gd")
var app: TDApplication
var shell: TDGameShell

func before_each() -> void:
	app = load("res://src/app/main.tscn").instantiate()
	app.settings_path = "res://artifacts/story-revision-20261126/tests/%d/settings.json" % Time.get_ticks_usec()
	add_child_autofree(app); shell = app.game_shell; shell.automatic_time = false
	assert_true(shell.create_game("slot-01","修订稿",true).ok)
	await get_tree().process_frame; await get_tree().process_frame

func after_each() -> void:
	shell.go_title()
	await get_tree().process_frame; await get_tree().process_frame

func test_eight_source_scenes_original_expression_files_and_reserved_battles() -> void:
	var source := TDRevisedMainline.data()
	assert_eq(source.chapters.size(),8)
	assert_eq(source.nodes.size(),26)
	assert_false(source.combat_implemented)
	assert_eq(source.source_sha256,"4a65f8bad716ac8cd7074320fe1c1190eeea6996020ea661e733208495029767")
	var luo_cry_lines := 0
	for row: Dictionary in source.chapters[7].rows:
		if row.get("actor") == "luo" and row.get("expression") == "cry": luo_cry_lines+=1
	assert_eq(luo_cry_lines,2,"Updated script uses Luo crying in both ending lines")
	var document := preload("res://addons/td_vn_editor/document.gd").new()
	for chapter: Dictionary in source.chapters:
		assert_eq(document.open_file(chapter.preview),"")
		assert_eq(document.validate(),PackedStringArray(),chapter.title)
	for node: Dictionary in source.nodes:
		if node.kind == "dialogue":
			assert_eq(document.open_file(node.path),"")
			assert_eq(document.validate(),PackedStringArray(),node.id)
		elif node.kind == "battle":
			assert_false(node.implemented)
			assert_eq(node.music,"boss" if node.chapter == 8 else "cooking")
	for row: Dictionary in source.portraits:
		var digest := HashingContext.new(); digest.start(HashingContext.HASH_SHA256)
		digest.update(FileAccess.get_file_as_bytes("res://" + row.path))
		assert_eq(digest.finish().hex_encode(),row.sha256,row.path)
		var art: Texture2D = TDRedrawArt.portrait(row.actor,row.expression)
		assert_not_null(art,row.path)
		assert_eq(art.get_size(),Vector2(row.size[0],row.size[1]))

func test_new_game_native_story_cancel_resume_and_battle_is_not_auto_won() -> void:
	var view := shell.guide.dialogue
	assert_true(view._native)
	assert_eq(view.talk.context.kind,"revised_mainline")
	assert_eq(shell.profile.story.revised.cursor,0)
	view.dismiss(); await get_tree().process_frame
	assert_eq(shell.profile.story.revised.cursor,0,"Cancel never completes a chapter")
	shell.guide.continue_revised()
	await Driver.finish(view,get_tree())
	assert_eq(shell.profile.story.revised.cursor,1)
	shell.guide.continue_revised()
	await Driver.finish(view,get_tree())
	assert_eq(shell.profile.story.revised.cursor,2)
	var pending := TDRevisedMainline.current(shell.profile.story.revised)
	assert_eq(pending.kind,"battle")
	assert_false(TDRevisedMainline.complete_dialogue(shell.profile.story.revised,pending.id,true))
	assert_eq(shell.profile.story.revised.cursor,2)
	assert_true(TDOpening.validate_state(shell.profile.story.export_state()).ok)
	var fabricated := shell.profile.story.revised.duplicate(true)
	fabricated.cursor = 3; fabricated.completed.append(pending.id)
	assert_false(TDRevisedMainline.validate(fabricated))

func test_hina_is_an_expression_label_and_preview_never_grants_progress() -> void:
	shell.guide.dialogue.dismiss()
	var before := shell.profile.snapshot()
	var chapter: Dictionary = TDRevisedMainline.data().chapters[4]
	var entry := {"id":"revised_preview_05","title":chapter.title,"path":chapter.preview}
	shell.guide.show_talk(TDRevisedMainline.talk(entry,true))
	await get_tree().process_frame; await get_tree().process_frame
	var layer := shell.guide.dialogue._vn_stage.runner.ctx.characters
	# Preview starts with the narrator warning; explicitly advance to Hina's first line.
	for i: int in 4:
		if layer.active_sprites.has("hina"): break
		shell.guide.dialogue._vn_stage.dialog._reveal_to_end()
		shell.guide.dialogue._vn_stage.dialog._advance_dialog()
		await get_tree().process_frame; await get_tree().process_frame
	assert_true(layer.active_sprites.has("hina"))
	if layer.active_sprites.has("hina"):
		assert_eq(layer.active_sprites.hina.get_node("TextPlaceholder").text,"希娜-通常")
	await Driver.finish(shell.guide.dialogue,get_tree())
	assert_true(TDLevelProgression.same_value(before,shell.profile.snapshot()))

func test_port_ban_is_domain_checked_and_old_save_keeps_legacy_mode() -> void:
	var before := shell.profile.shop.snapshot()
	assert_eq(shell.profile.shop.open_day().code,"PORT_CLOSED_BY_STORY")
	assert_eq(shell.profile.shop.snapshot(),before)
	var old := TDOpening.new(); old.begin()
	assert_true(old.revised.is_empty())
	var restored := TDOpening.new(); restored.restore(shell.profile.story.export_state())
	assert_eq(restored.revised,shell.profile.story.revised)
	var corrupt := restored.export_state(); corrupt.revised.port_reopened = true
	assert_false(TDOpening.validate_state(corrupt).ok)

func test_shared_140_bpm_native_music_and_three_registered_roles() -> void:
	var catalog := TDCookingCatalog.new()
	assert_true(catalog.load_file("res://content/cooking_system.json").ok)
	assert_eq(catalog.data().pc_operations.bpm,140)
	var audio := TDBeatAudio.new(); add_child_autofree(audio)
	audio.prepare_cooking_music(140)
	assert_eq(audio.pitch_scale,1.0)
	assert_eq((audio.stream as AudioStreamWAV).data,TDGameMusic.TRACKS.casual.data)
	assert_true(TDGameMusic.TRACKS.has("cooking"))
	assert_true(TDGameMusic.TRACKS.has("boss"))

func test_explicit_placeholder_acknowledgements_preserve_economy_and_reopen_only_after_ending() -> void:
	var state := TDRevisedMainline.initial()
	assert_false(TDRevisedMainline.defer_placeholder(state,"revised_02"),"Cannot skip a future interface")
	for node: Dictionary in TDRevisedMainline.data().nodes:
		assert_eq(TDRevisedMainline.current(state).id,node.id)
		if node.kind == "dialogue":
			assert_true(TDRevisedMainline.complete_dialogue(state,node.id,true))
		elif node.kind == "evaluation":
			assert_false(TDRevisedMainline.evaluate_plate(state,{}))
			assert_false(TDRevisedMainline.evaluate_plate(state,{"state":"plated","session_id":"invalid","ingredients":{}}))
			# Domain fixture only: production caller obtains this from a live kitchen session.
			assert_true(TDRevisedMainline.evaluate_plate(state,{"state":"plated","session_id":"domain-fixture-chicken","ingredients":{"sample":{"ingredient_id":"chicken"}}}))
		else:
			assert_true(TDRevisedMainline.defer_placeholder(state,node.id))
		assert_eq(state.port_reopened,int(state.cursor)>=25)
		assert_true(TDRevisedMainline.validate(state))
	assert_eq(state.cursor,26)
	assert_eq(state.deferred.size(),9)

func test_journal_placeholder_button_continues_story_without_battle_settlement() -> void:
	await Driver.finish(shell.guide.dialogue,get_tree())
	shell.guide.continue_revised()
	await Driver.finish(shell.guide.dialogue,get_tree())
	assert_eq(shell.profile.story.revised.cursor,2)
	var before := shell.profile.shop.snapshot()
	shell.guide.show_revised_journal()
	await get_tree().process_frame; await get_tree().process_frame
	assert_eq(shell.music.context,"cooking","Unfinished battle card uses the reserved battle track")
	var clicked := false
	for child: Node in shell._modal_box.get_children():
		if child is Button and child.text.begins_with("跳过待制作接口"):
			clicked = true; child.pressed.emit(); break
	assert_true(clicked)
	await get_tree().process_frame; await get_tree().process_frame
	assert_eq(shell.profile.story.revised.cursor,3)
	assert_true(shell.guide.dialogue._native)
	assert_eq(shell.profile.shop.snapshot(),before,"Story continuation never settles battle money, stock or scores")
	await Driver.finish(shell.guide.dialogue,get_tree())
	shell.guide.continue_revised()
	await Driver.finish(shell.guide.dialogue,get_tree())
	assert_eq(shell.profile.story.revised.cursor,5)
	shell.guide.show_revised_journal()
	shell.guide.submit_revised_evaluation()
	assert_eq(shell.profile.story.revised.cursor,5,"No chicken plate means no evaluation progress")
	shell._close_dialog()

func test_revised_mode_retains_independent_first_business_homecoming_flags() -> void:
	var story := TDOpening.new(); story.begin(); story.beat = "done"
	story.revised = TDRevisedMainline.initial()
	story.note_opened(); assert_true(story.opened)
	story.note_served(); assert_true(story.served); assert_false(story.opened)
	assert_eq(story.revised.cursor,0,"Housing milestones do not advance revised mainline")
