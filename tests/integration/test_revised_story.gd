extends GutTest
const Driver := preload("res://tools/test_support/native_dialogue.gd")
const CuisineInput := preload("res://tools/test_support/cuisine_input.gd")
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

func test_eight_source_scenes_original_expression_files_and_playable_battles() -> void:
	var source := TDRevisedMainline.data()
	assert_eq(source.chapters.size(),8)
	assert_eq(source.nodes.size(),26)
	assert_eq(source.portraits.size(),56)
	assert_true(source.combat_implemented)
	assert_eq(source.source_sha256,"5ef0817bac21a24dd5e3b1d5037b183cef322545619f3fb57ee0115565264e00")
	assert_eq(source.cast.get("日奈"),"hina")
	var luo_cry_lines := 0
	for row: Dictionary in source.chapters[7].rows:
		if row.get("actor") == "luo" and row.get("expression") == "cry": luo_cry_lines+=1
	assert_eq(luo_cry_lines,2,"Luo uses the crying portrait at both the tasting and the confession")
	var document := preload("res://addons/td_vn_editor/document.gd").new()
	for chapter: Dictionary in source.chapters:
		var expected := _script_lines(chapter)
		assert_eq(document.open_file(chapter.preview),"")
		assert_eq(document.validate(),PackedStringArray(),chapter.title)
		assert_eq(_spoken_lines(chapter.preview,source.cast.values()),expected,chapter.title + " preview")
		var actual: Array = []
		for node: Dictionary in source.nodes:
			if node.chapter!=chapter.number or node.kind!="dialogue": continue
			for key: String in ["path","continuation"]:
				if not node.has(key): continue
				assert_eq(document.open_file(node[key]),"")
				assert_eq(document.validate(),PackedStringArray(),node.id)
				actual.append_array(_spoken_lines(node[key],source.cast.values()))
		assert_eq(actual,expected,chapter.title + " runtime")
	for node: Dictionary in source.nodes:
		if node.kind == "battle":
			assert_true(node.implemented)
			assert_eq(node.music,"boss" if node.chapter == 8 else "cooking")
	for row: Dictionary in source.portraits:
		var digest := HashingContext.new(); digest.start(HashingContext.HASH_SHA256)
		digest.update(FileAccess.get_file_as_bytes("res://" + row.path))
		assert_eq(digest.finish().hex_encode(),row.sha256,row.path)
		var art: Texture2D = TDRedrawArt.portrait(row.actor,row.expression)
		assert_not_null(art,row.path)
		assert_eq(art.get_size(),Vector2(row.size[0],row.size[1]))

func _script_lines(chapter: Dictionary) -> Array:
	var lines: Array = []
	for row: Dictionary in chapter.rows:
		if row.kind in ["dialogue","narration"]:
			lines.append([row.get("actor","narrator"),row.get("expression",""),row.text])
	return lines

func _spoken_lines(path: String, actors: Array) -> Array:
	var lines: Array = []
	var expressions := {}
	for line: String in FileAccess.get_file_as_string(path).split("\n"):
		if line.begins_with("@show "):
			var fields := line.split(" ",false)
			expressions[fields[1]]=fields[2]
		var separator := line.find(": ")
		if separator<0: continue
		var actor := line.left(separator)
		var content := line.substr(separator+2).trim_suffix("\r")
		if actor in actors or (actor=="narrator" and not content.begins_with("【")):
			lines.append([actor,expressions.get(actor,""),content])
	return lines

func test_new_game_native_story_cancel_resume_and_battle_is_not_auto_won() -> void:
	var view := shell.guide.dialogue
	assert_true(view._native)
	assert_eq(view.talk.context.kind,"revised_mainline")
	assert_eq(shell.profile.story.revised.cursor,0)
	view.dismiss(); await get_tree().process_frame
	assert_eq(shell.profile.story.revised.cursor,0,"Cancel never completes a chapter")
	shell.guide.continue_revised()
	await Driver.finish(view,get_tree())
	var journey := shell.guide.journey
	assert_eq(shell.profile.story.revised.cursor,0,"The opening hands control back for the food search")
	assert_eq(journey.arrival_checked_count(),0)
	assert_string_contains(shell._toast,"新任务：探索臻味港，找找吃饭的地方【0/3】")
	shell.guide._process_revised(0)
	assert_true(shell.guide._trail.visible)
	assert_gt(shell.guide._trail.points.size(),1)
	var look := InputEventAction.new()
	look.action="world_interact"
	look.pressed=true
	for index: int in journey.ARRIVAL_SHOPS.size():
		var id: String = journey.ARRIVAL_SHOPS[index]
		shell.town.spawn_at_plot(id)
		assert_eq(shell.town.facing_plot().get("id"),id)
		shell.town._unhandled_input(look)
		assert_eq(journey.arrival_checked_count(),index+1)
		assert_eq(shell._toast,"真不巧！这家没开门，换一家吧！")
		shell.town._unhandled_input(look)
		assert_eq(journey.arrival_checked_count(),index+1,"Rechecking an entrance never adds progress")
	assert_true(TDRevisedMainline.validate(shell.profile.story.revised))
	assert_eq(journey.objective().title,"返回港口【3/3】")
	shell.guide._process_revised(0)
	assert_false(view.visible,"Checking the third shop does not play the return dialogue in town")
	assert_gt(shell.guide._trail.points.size(),1)
	shell.town.spawn_at_harbor()
	shell.guide.continue_revised()
	assert_eq(view.talk.context.scene,TDRevisedMainline.ARRIVAL_RETURN_ID)
	view.dismiss()
	await get_tree().process_frame
	assert_eq(shell.profile.story.revised.cursor,0,"Closing the return dialogue preserves the quest for a retry")
	shell.guide.continue_revised()
	await Driver.finish(view,get_tree())
	assert_eq(shell.profile.story.revised.cursor,1)
	assert_false(view.visible)
	assert_false(shell.voyage("paris").ok)
	shell.guide.set_process(false)
	journey.tick(.05)
	assert_not_null(journey._escort, "Aling leads the player from the town")
	assert_true(shell.travel("restaurant").ok)
	journey.tick(0)
	var room := shell.restaurant
	assert_false(room._iso.story_escort.is_empty())
	var doorway := room.kitchen_door_cell()
	var entrance := room.cell_of_player()
	var interact := InputEventAction.new()
	interact.action = "world_interact"
	interact.pressed = true
	room.teleport_player(doorway)
	room._unhandled_input(interact)
	assert_eq(shell.location,"restaurant","The first kitchen visit waits for Aling")
	room.teleport_player(entrance)
	for i: int in 240:
		journey.tick(.05)
		assert_true(room.layout.feet_inside(journey._dining_escort_feet))
		room._player.position = journey._dining_escort_feet
		if journey._step >= journey._route.size(): break
	assert_eq(room.cell_of_player(), doorway)
	room._unhandled_input(interact)
	assert_eq(shell.location,"kitchen")
	journey.tick(0)
	assert_false(view.visible,"Scene two waits for the kitchen escort")
	for i: int in 90:
		journey.tick(.05)
		if view.visible: break
	assert_true(view.visible)
	assert_eq(view.talk.context.scene,"revised_01")
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

func test_hina_uses_archived_portraits_and_preview_never_grants_progress() -> void:
	_position_story(1)
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
		var sprite: VNEngineCharacterSprite = layer.active_sprites.hina
		assert_eq(sprite.sprite.texture, TDRedrawArt.portrait("日奈", "calm"))
		assert_false(sprite.has_node("TextPlaceholder"))
	await Driver.finish(shell.guide.dialogue,get_tree())
	var after := shell.profile.snapshot()
	assert_true(TDLevelProgression.same_value(before.story,after.story))
	assert_true(TDLevelProgression.same_value(before.shop,after.shop))
	assert_true(TDLevelProgression.same_value(before.research,after.research))

func test_archived_pixel_characters_are_visible_in_their_towns() -> void:
	_position_story(26)
	shell.travel("town")
	shell.town.spawn_at_harbor()
	var hertz := shell.town.get_node_or_null("Hertz") as TDStoryArt.TownActor
	_check_town_actor(hertz, "hertz", shell.town._can_stand)
	_check_doorway_crowd(shell.town.get_node_or_null("CrowdStands"), shell.town._can_stand)
	shell.town._build_blockers()
	_check_doorway_crowd(shell.town.get_node_or_null("CrowdStands"), shell.town._can_stand)
	for destination: String in ["paris","tokyo"]:
		var arrived := shell._arrive(destination)
		assert_true(arrived.ok, destination + " " + arrived.code)
		if not arrived.ok: return
		var id := "vito" if destination == "paris" else "hina"
		var actor := shell.visiting.get_node_or_null(id.capitalize()) as TDStoryArt.TownActor
		_check_town_actor(actor, id, shell.visiting._can_stand)
		_check_doorway_crowd(shell.visiting.get_node_or_null("CrowdStands"), shell.visiting._can_stand)

func test_preset_overseas_storefronts_match_the_jiangnan_main_store() -> void:
	_position_story(26)
	var main_store := shell.town._facades.filter(func(entry: Dictionary) -> bool: return entry.get("reference_id") == "diner")
	assert_eq(main_store.size(), 1)
	if main_store.size() != 1: return
	var main_bounds: Rect2 = main_store[0].rect
	for destination: String in ["paris", "tokyo"]:
		var arrived := shell._arrive(destination)
		assert_true(arrived.ok, destination + " " + arrived.code)
		if not arrived.ok: return
		var world := shell.visiting
		var branch_id := shell.profile.branches.preset_in(destination)
		var entries := world._buildings.filter(func(entry: Dictionary) -> bool: return entry.plot.get("branch_id", "") == branch_id)
		assert_eq(entries.size(), 1, destination)
		if entries.size() != 1: return
		var entry: Dictionary = entries[0]
		var lot := TDInteractionRange.plot_bounds(entry.plot)
		var anchor := Vector2(lot.get_center().x, lot.end.y - .12) * world.cell_size
		var visible_rect: Rect2 = entry.rect
		assert_eq(entry.art, main_store[0].art, destination + " uses the actual Jiangnan facade")
		assert_true(visible_rect.size.is_equal_approx(main_bounds.size), destination + " matches the main store proportions")
		assert_true(Vector2(visible_rect.get_center().x, visible_rect.end.y).is_equal_approx(anchor), destination + " facade anchor")
		assert_false(world._can_stand(entry.base.get_center()), destination + " the shared storefront has a solid wall")
		var entrance := world.landmark_access("player_diner", branch_id)
		assert_true(entrance.is_finite(), destination + " walkable entrance")
		assert_true(is_equal_approx(entrance.x, anchor.x) and entrance.y > anchor.y, destination + " approaches the front steps")
		assert_eq(world._target_at(entrance).get("branch_id"), branch_id, destination + " entrance interaction")
		if destination == "paris":
			var bank_id := "commercial_street:bank"
			var bank := world._buildings.filter(func(item: Dictionary) -> bool: return item.plot.get("id") == bank_id)
			assert_eq(bank.size(), 1)
			if bank.size() != 1: return
			var bank_bounds: Rect2 = bank[0].rect
			assert_gt(visible_rect.position.x - bank_bounds.end.x, 90.0, "walking room between the bank and diner")
			var bank_door := world.landmark_access("bank", bank_id)
			assert_true(bank_door.is_finite(), "walkable relocated bank entrance")
			assert_eq(world._target_at(bank_door).get("id"), bank_id, "bank interaction follows the facade")

func _check_doorway_crowd(group: Node2D, can_stand: Callable) -> void:
	assert_not_null(group)
	if group == null: return
	assert_eq(group.get_child_count(), 3)
	var doors := {}
	for actor: TDStoryArt.TownActor in group.get_children():
		var site: String = actor.get_meta("site_id")
		var door: Vector2 = actor.get_meta("doorway")
		assert_false(doors.has(site), site)
		doors[site] = true
		assert_true(actor.is_visible_in_tree(), site)
		assert_true(can_stand.call(actor.position), site)
		assert_true(absf(door.x - actor.position.x) >= 42.0, site)
		assert_true(actor.position.distance_to(door) <= 124.1, site)
		actor.face_nearby(actor.position + Vector2.DOWN * 70.0)
		assert_eq(actor.texture, TDStoryArt.sprite("crowd", Vector2i.DOWN), site)

func _check_town_actor(actor: TDStoryArt.TownActor, id: String, can_stand: Callable) -> void:
	assert_not_null(actor, id)
	if actor == null: return
	assert_true(actor.is_visible_in_tree(), id)
	assert_true(can_stand.call(actor.position), id)
	for direction: Vector2i in [Vector2i.DOWN, Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT]:
		actor.face_nearby(actor.position + Vector2(direction) * 70.0)
		assert_eq(actor.texture, TDStoryArt.sprite(id, direction), id + str(direction))
		assert_almost_eq(-actor.offset.y * actor.scale.y, TDTownWorld.OUTDOOR_PERSON_HEIGHT, .01)

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

func _position_story(step: int) -> void:
	shell._close_dialog()
	if shell.guide.presenting(): shell.guide.dialogue.finish_now()
	var state := TDRevisedMainline.initial()
	for i: int in step:
		var node := TDRevisedMainline.current(state)
		if node.kind=="dialogue": TDRevisedMainline.complete_dialogue(state,node.id,true)
		else: TDRevisedMainline.complete_action(state,node.id)
	shell.profile.story.revised=state

func test_active_task_notice_and_journal_history_are_bounded_by_story_progress() -> void:
	shell.guide.set_process(false)
	_position_story(0)
	var guide := shell.guide
	guide.show_journal()
	assert_false(shell._modal_box.find_children("*","Button",true,false).any(func(button: Button) -> bool: return button.text.begins_with("第一场")))
	shell._close_dialog()
	_position_story(2)
	var task := guide.journey.objective()
	guide._update_task_notice("revised_02", task, false, 0)
	assert_true(guide._card.visible)
	guide._update_task_notice("revised_02", task, false, guide.TASK_NOTICE_SECONDS)
	guide._update_task_notice("revised_02", task, false, 0)
	assert_false(guide._card.visible)
	guide.show_journal()
	var buttons := shell._modal_box.find_children("*","Button",true,false)
	assert_false(buttons.any(func(button: Button) -> bool: return "预览" in button.text or button.text.begins_with("第三场")))
	var history := buttons.filter(func(button: Button) -> bool: return button.text.begins_with("第一场"))
	assert_eq(history.size(), 2)
	if history.is_empty(): return
	history[0].pressed.emit()
	await Driver.finish(guide.dialogue,get_tree())
	assert_eq(shell.profile.story.revised.cursor, 2)

func test_main_town_business_and_three_intermission_checkpoints() -> void:
	shell.guide.set_process(false)
	_position_story(2)
	assert_eq(shell.start_day().code, "PORT_CLOSED_BY_STORY")
	assert_eq(shell.profile.shop.current_phase(), "PREPARE")
	assert_true(shell.travel("kitchen").ok)
	for step: int in [8,13,15]:
		_position_story(step)
		var state := shell.profile.story.revised
		var town_id := TDRevisedMainline.training_town(state)
		state.lodging = town_id
		assert_true(shell.profile.story_can_trade(town_id))
		shell._update_story_checkpoint(true)
		var saved := shell.slots.load_slot("slot-01", TDProfileStore.STORY)
		assert_true(saved.ok, saved.code)
		if not saved.ok: return
		assert_eq(int(saved.data.story.revised.cursor), step)
	var resumed := shell.load_game("slot-01", TDProfileStore.STORY)
	assert_true(resumed.ok, resumed.code)
	if not resumed.ok: return
	assert_eq(int(shell.profile.story.revised.cursor), 15)
	assert_eq(shell.visiting_town, "tokyo")
	assert_not_null(shell.branch_visit)
	_position_story(25)
	assert_true(shell.profile.story_can_trade("chengdu"))

func test_daily_popularity_decline_is_limited_to_intermissions_and_postgame() -> void:
	shell.guide.set_process(false)
	var profile := shell.profile
	var branch_id := profile.branches.preset_in("paris")
	assert_false(branch_id.is_empty())
	if branch_id.is_empty(): return
	var cases := [[2, false, false], [8, false, false], [8, true, true], [10, false, false],
		[13, false, true], [14, false, false], [15, false, true], [22, false, false],
		[24, false, false], [25, false, true], [26, false, true]]
	for example: Array in cases:
		var step := int(example[0])
		_position_story(step)
		if step == 8:
			TDRevisedMainline.mark(profile.story.revised, "paris_training_started")
			if example[1]: TDRevisedMainline.mark(profile.story.revised, "paris_training_complete")
		profile.branches.prepare()
		var branch: Dictionary = profile.branches.state.stores[branch_id]
		# Exercise the branch's operating-day path with the same empty day as the main store.
		branch.daily.story_service = true
		var main_before := float(profile.commerce.state.popularity)
		var branch_before := float(branch.popularity)
		var scale := 0.8 if example[2] else 1.0
		var label := "story cursor %d, training complete %s" % [step, str(example[1])]
		assert_true(profile.shop.close_for_night().ok, label)
		assert_almost_eq(float(profile.commerce.state.popularity), main_before * scale, 0.000001, label)
		assert_almost_eq(float(branch.popularity), branch_before * scale, 0.000001, label)
		var sleep := profile.next_day()
		assert_true(sleep.ok, sleep.code)
		if not sleep.ok: return
		assert_eq(float(sleep.data.awareness_delta), 0.0, label)
		if example[2]: assert_lt(float(sleep.data.popularity_delta), 0.0, label)
		else: assert_eq(float(sleep.data.popularity_delta), 0.0, label)

func test_harbor_uses_a_toast_until_the_story_route_opens() -> void:
	shell.guide.set_process(false)
	_position_story(5)
	shell.town.spawn_at_harbor()
	# The same harbor interaction that opened the empty dialog in play.
	shell.town._interact()
	assert_null(shell._modal)
	assert_true(shell._toast.contains("暂无航线开放"))
	assert_true(shell.town._player.controls_enabled)
	assert_false(get_tree().paused)
	for leg: Array in [[7,"chengdu","paris"],[12,"paris","tokyo"],[17,"tokyo","chengdu"]]:
		_position_story(int(leg[0]))
		assert_true(shell._arrive(leg[1]).ok)
		if leg[1]=="chengdu":
			shell.town._interact()
		else:
			var interact := InputEventAction.new()
			interact.action="world_interact"
			interact.pressed=true
			shell.visiting._unhandled_input(interact)
		assert_not_null(shell._modal_box)
		if shell._modal_box==null: return
		var destinations := shell._modal_box.find_children("*","Button",true,false).filter(func(button: Button) -> bool: return button.text.begins_with("前往 "))
		assert_eq(destinations.size(),1)
		if destinations.size()==1:
			assert_eq(destinations[0].text,"前往 "+str(TDTravelCatalog.info(leg[2]).name))
			destinations[0].pressed.emit()
			assert_eq(shell.visiting_town,leg[2],"The destination button actually takes the player there")
		shell._close_dialog()

func test_escort_grid_route_checks_every_segment_between_clear_cell_centres() -> void:
	var wall := Rect2(38,0,4,102)
	var walkable := func(at: Vector2) -> bool: return not wall.has_point(at)
	var start := Vector2(20,20)
	var end := Vector2(60,20)
	var route := shell.guide.journey._terrain_route(start,end,Vector2.ZERO,40,4,walkable)
	assert_gt(route.size(),2)
	assert_eq(route[-1],end)
	var previous := start
	for point: Vector2 in route:
		assert_true(TDInteractionRange.ground_segment_clear(previous,point,walkable,2.0))
		previous=point
	assert_false(TDInteractionRange.npc_clear(Vector2(4,0),Vector2(-32,0),Vector2.ZERO,28.0),"An overlapping actor can move away without crossing the other actor")

func test_old_opening_save_loads_the_revised_story_with_business_intact() -> void:
	shell.guide.set_process(false)
	shell.guide.dialogue.finish_now()
	var old := shell.profile
	old.story.clear()
	old.story.begin()
	old.story.beat="founded"
	old.story.hero_name="旧主角"
	old.characters.mark_met("chen")
	assert_true(old.shop.world_adjustment(2500,"test-legacy","经营收入").ok)
	var balance := int(old.shop._s.money_cents)
	var recipes: Array = old.research.snapshot().unlocked
	assert_true(old.save().ok)
	assert_true(shell.load_game("slot-01").ok)
	assert_eq(shell.profile.story.revised.cursor,0)
	assert_eq(shell.profile.story.hero_name,"焰子")
	assert_eq(shell.profile.research.snapshot().unlocked,recipes)
	assert_eq(int(shell.profile.shop._s.money_cents),balance)
	assert_false(shell.profile.characters.has_met("chen"))
	assert_true(shell.guide.presenting())
	assert_eq(shell.guide.dialogue.talk.context.scene,"revised_00")

func test_world_map_reveals_each_town_at_its_scripted_interruption() -> void:
	_position_story(6)
	var early_map := shell.show_world_map()
	assert_eq(early_map.maps.keys(),["chengdu"])
	assert_eq(early_map._locked_towns,["tokyo","paris"])
	early_map.focus_town("tokyo")
	assert_eq(early_map.zoom,1.0,"Locked town cannot be focused")
	assert_true(early_map.challenge_towns.is_empty(), "Story discoveries still use the authored reveal")
	assert_eq(early_map.challenge_locations("chengdu").size(),3,"Nearby opponents are visible on the local chart")
	assert_true(early_map.challenge_locations("paris").is_empty())
	assert_eq(shell._arrive("paris").code,"PASSENGER_ROUTE_LOCKED")
	shell._close_dialog()
	shell.guide.journey.tick(0)
	await Driver.finish(shell.guide.dialogue,get_tree())
	await get_tree().process_frame
	assert_not_null(shell._challenge_notice, "The advice reward appears before the map")
	if shell._challenge_notice!=null: shell._challenge_notice.confirm_button.pressed.emit()
	var view := _open_chart()
	assert_not_null(view)
	if view==null: return
	assert_eq(view._locked_towns,["tokyo"])
	assert_eq(view.challenge_towns,["chengdu","paris"])
	assert_eq(view.challenge_locations("chengdu"),shell.town._crowd_stands.map_locations(shell.town._origin(),shell.town.cell_size()))
	assert_eq(view.challenge_locations("chengdu").size(),3)
	assert_eq(view.challenge_locations("paris").size(),3)
	assert_true(view.challenge_locations("tokyo").is_empty())
	assert_eq(shell.profile.story.revised.cursor,6,"Marking the map does not advance the dialogue")
	await get_tree().create_timer(1.7).timeout
	assert_eq(view.focused_town(),"paris")
	shell._close_dialog()
	shell.guide.journey.tick(0)
	assert_eq(shell.guide.dialogue.talk.context.scene,"revised_06_route")
	await Driver.finish(shell.guide.dialogue,get_tree())
	assert_eq(shell.profile.story.revised.cursor,7)
	assert_true(shell._story_passenger_route("paris"))

	_position_story(11)
	var before_japan := shell.show_world_map()
	assert_eq(before_japan._locked_towns,["tokyo"])
	assert_false(shell._story_passenger_route("tokyo"))
	shell._close_dialog()
	shell.guide.journey.tick(0)
	await Driver.finish(shell.guide.dialogue,get_tree())
	await get_tree().process_frame
	var updated := _open_chart()
	assert_not_null(updated)
	if updated==null: return
	assert_eq(updated.challenge_towns,["chengdu","tokyo","paris"])
	assert_eq(updated.challenge_locations("tokyo").size(),3)
	assert_true(TDRevisedMainline.flag(shell.profile.story.revised,"tokyo_briefed"))
	assert_eq(shell.profile.story.revised.cursor,11)
	await get_tree().create_timer(1.7).timeout
	assert_eq(updated.focused_town(),"tokyo")
	shell._close_dialog()
	shell.guide.journey.tick(0)
	assert_eq(shell.guide.dialogue.talk.context.scene,"revised_11_route")
	await Driver.finish(shell.guide.dialogue,get_tree())
	assert_eq(shell.profile.story.revised.cursor,12)
	assert_true(shell._story_passenger_route("tokyo"))
	assert_true(shell._arrive("tokyo").ok)
	assert_false(shell._crowd_label("tokyo").is_empty())
	var restored := TDOpening.new()
	restored.restore(shell.profile.story.export_state())
	assert_true(TDRevisedMainline.map_unlocked(restored.revised,"tokyo"))

	assert_true(shell._arrive("chengdu").ok)
	shell.profile.story.revised.clear()
	shell.profile.require_revised_unlocks=true
	var legacy_map := shell.show_world_map()
	assert_eq(legacy_map.maps.keys(),["chengdu"])
	assert_true(legacy_map.challenge_locations("paris").is_empty())
	shell._close_dialog()

func _open_chart() -> TDTravelMapView:
	if shell._modal_box==null: return null
	for child: Node in shell._modal_box.get_children():
		if child is TDTravelMapView: return child
	return null

func test_map_crowd_starts_repeatable_duels_with_local_cooking_outside_the_story() -> void:
	for town_id: String in ["chengdu", "paris", "tokyo"]:
		_position_story(1 if town_id == "chengdu" else 26)
		shell.profile.progression._state.level = 1
		assert_true(shell._arrive(town_id).ok)
		var world: Node2D = shell.town if town_id == "chengdu" else shell.visiting
		var player: TDKitchenPlayer = shell.town._player if town_id == "chengdu" else shell.visiting.player
		var group := world.get_node("CrowdStands")
		var title: String = TDChallengeBattle.CROWD_RIVALS[town_id].name
		if town_id == "tokyo": shell.profile.characters.clock.closed_day = shell.profile.characters.clock.day
		var story := shell.profile.story.revised.duplicate(true)
		var shop := shell.profile.shop.snapshot()
		assert_eq(group.get_child_count(), 3)
		for actor: TDStoryArt.TownActor in group.get_children():
			player.position = actor.position + Vector2.DOWN * 48.0
			player.face(Vector2.UP)
			var feet := player.position
			var input := InputEventAction.new()
			input.action = "world_interact"
			input.pressed = true
			var previous: TDChallengeBattle
			for result: int in [TDChallengeBattle.Phase.WON, TDChallengeBattle.Phase.LOST]:
				assert_eq(world.call("_nearby_crowd"), title)
				world.call("_unhandled_input", input)
				var panel := shell._challenge
				assert_not_null(panel, "E starts a duel at " + String(actor.name))
				if panel == null: return
				assert_null(panel.battle, "Every rematch requires its own cooking round")
				var chart := TDChallengeBattle.Rules.recipe(0, town_id, actor.get_meta("site_id"))
				assert_eq(panel.lesson.definition.recipe_id, shell.profile.research.catalog.chart(chart).recipe_id)
				assert_null(panel.selection)
				stage_test_battle(panel)
				var battle := panel.battle
				assert_ne(battle, previous, "Each rematch gets a fresh battle")
				previous = battle
				assert_eq(battle.opponent.id, TDChallengeBattle.CROWD_RIVALS[town_id].id)
				assert_eq(battle.round_number, 1)
				if result == TDChallengeBattle.Phase.WON:
					battle.foe = battle.hero + Vector2i.RIGHT
					battle.foe_hp = 2
				else:
					battle.hp = battle._enemy_damage(1)
					battle._schedule_strike([battle.hero], 1)
				var attack := InputEventKey.new()
				attack.physical_keycode = KEY_F
				attack.pressed = true
				assert_true(panel.handle_key(attack))
				assert_true(panel.handle_key(attack))
				assert_eq(battle.phase, result)
				confirm_notices(panel)
				var buttons := panel.decision.find_children("*", "Button", true, false)
				assert_eq(buttons.size(), 1)
				if buttons.size() != 1: return
				var back := buttons[0] as Button
				assert_eq(back.text, "返回小镇")
				back.pressed.emit()
				assert_null(shell._challenge)
				assert_true(player.controls_enabled)
				assert_eq(player.position, feet)
			assert_eq(world.call("_nearby_crowd"), title)
			world.call("_unhandled_input", input)
			assert_not_null(shell._challenge, "The same opponent can be challenged again after losing")
			if shell._challenge == null: return
			assert_not_null(shell._challenge.lesson)
			stage_test_battle(shell._challenge)
			assert_ne(shell._challenge.battle, previous)
			shell._challenge.back()
			var quit_buttons := shell._challenge.decision.find_children("*", "Button", true, false)
			var quit_button: Button
			for button: Button in quit_buttons:
				if button.text == "退出本局": quit_button = button
			assert_not_null(quit_button)
			if quit_button == null: return
			quit_button.pressed.emit()
			assert_null(shell._challenge)
			await get_tree().process_frame
		assert_eq(shell.profile.story.revised, story)
		assert_eq(shell.profile.shop.snapshot(), shop)

func test_overseas_main_gates_advance_without_resident_wins() -> void:
	shell.guide.set_process(false)
	_position_story(8)
	TDRevisedMainline.mark(shell.profile.story.revised,"paris_training_complete")
	assert_true(shell._arrive("paris").ok)
	shell.profile.progression._state.level=4
	assert_string_contains(shell.guide.objective().title,"Lv.2")
	assert_string_contains(shell.guide.objective().text,"德式椒盐卷饼")
	shell.guide.journey.tick(0)
	assert_eq(shell.profile.story.revised.cursor,8)
	shell.profile.progression._state.level=5
	shell.guide.journey.tick(0)
	assert_eq(shell.profile.story.revised.cursor,9)

	_position_story(13)
	assert_true(shell._arrive("tokyo").ok)
	shell._enter_story_branch("tokyo")
	shell.profile.progression._state.level=9
	assert_string_contains(shell.guide.objective().text,"Lv.9 / 10")
	assert_string_contains(shell.guide.objective().text,"再挑战日奈")
	shell.guide.journey.tick(0)
	assert_null(shell._challenge)
	shell.profile.progression._state.level=10
	shell.guide.journey.tick(0)
	if shell._challenge!=null: start_from_loadout(shell._challenge)
	var lesson: TDResearchLesson=shell._challenge.lesson if shell._challenge!=null else null
	assert_not_null(lesson)
	if lesson!=null:
		assert_eq(lesson.definition.recipe_id,shell.profile.research.catalog.chart("J03").recipe_id)
		shell._challenge.back()

func test_paris_tracks_each_level_challenge_and_preset_doors_ignore_feature_locks() -> void:
	shell.guide.set_process(false)
	_position_story(12)
	var p := shell.profile
	for flag: String in ["branches","employees","suppliers"]:
		assert_false(p.story_feature_available(flag))
	assert_true(shell.travel("restaurant").ok)
	assert_true(shell.travel("kitchen").ok)
	for town_id: String in ["paris","tokyo"]:
		assert_true(shell._arrive(town_id).ok)
		var store_id := p.branches.preset_in(town_id)
		shell._enter_story_branch(town_id)
		assert_eq(shell.location,"branch")
		assert_not_null(shell.branch_visit)
		if shell.branch_visit==null: return
		assert_eq(shell.branch_visit.store_id,store_id)
		assert_false(p.branches.can_manage_store(store_id))
		assert_true(p.branches.can_support_store(store_id))
		shell._show_training_desk(store_id)
		assert_true(_press_shift_button("账本与库存"))
		shell._close_dialog()
		shell.exit_branch()
	_position_story(8)
	assert_true(shell._arrive("paris").ok)
	TDRevisedMainline.mark(p.story.revised,"paris_training_complete")
	var sites := ["competitor:shop:1","competitor:shop:2","residences-a"]
	var recipes := ["E01","E03","E07"]
	for index: int in sites.size():
		p.progression._state.level=index+2
		var site: String = sites[index]
		assert_eq(shell.guide.journey.next_paris_resident(),site)
		shell.guide._process_revised(30)
		assert_true(shell.guide._card.visible,"The tracked task persists beyond the first notification.")
		var key := InputEventAction.new()
		key.action="quest_track"
		key.pressed=true
		shell._input(key)
		shell.guide._process_revised(0)
		assert_false(shell.guide._card.visible)
		shell._input(key)
		assert_eq(shell.show_world_map().tracked_paris_site,site)
		shell._close_dialog()
		shell._talk_to_crowd(site,"paris")
		var panel := shell._challenge
		assert_not_null(panel)
		if panel==null: return
		assert_eq(panel.lesson.definition.recipe_id,p.research.catalog.chart(recipes[index]).recipe_id)
		panel.back()
		assert_eq(shell.guide.journey.next_paris_resident(),site,"Leaving the lesson does not finish the challenge.")
		p.record_challenge_result(TDChallengeBattle.Phase.WON,"crowd_eu","paris",site)
		assert_eq(shell.guide.journey.next_paris_resident(),"")

func test_western_restaurant_teaching_and_sleep_open_vito_story() -> void:
	if not _play_overseas_shift("paris",8,"E21",5): return
	shell.guide.journey.tick(0)
	assert_eq(shell.profile.story.revised.cursor,9)
	shell.guide.journey.tick(0)
	assert_true(shell.guide.presenting())
	assert_eq(shell.guide.dialogue.talk.context.get("scene"),"revised_09")
	await Driver.finish(shell.guide.dialogue,get_tree())
	assert_eq(shell.profile.story.revised.cursor,10)
	var store_id := shell.branch_visit.store_id
	shell.exit_branch()
	assert_true(shell.enter_branch(store_id).ok,"The restaurant remains accessible for the challenge.")
	assert_false(shell.profile.story_feature_available("branches"))
	assert_false(shell.profile.branches.can_manage_store(store_id))
	shell.guide.journey.tick(0)
	_assert_overseas_challenge("E02","维托")

func test_japanese_restaurant_sleep_awards_xp_and_opens_hina_challenge() -> void:
	if not _play_overseas_shift("tokyo",13,"J03",10): return
	shell._enter_story_branch("tokyo")
	shell.guide.journey.tick(0)
	_assert_overseas_challenge("J03","日奈")
	var p := shell.profile
	var settled := p.progression.snapshot()
	assert_false(p.next_day().ok)
	assert_eq(p.progression.snapshot(),settled,"A retry does not award the same shift twice.")

func _assert_overseas_challenge(atlas_id: String, opponent: String) -> void:
	var panel := shell._challenge
	assert_not_null(panel,"The story opens the corresponding challenge after sleeping.")
	if panel==null: return
	assert_eq(panel.story_encounter.opponent_name,opponent)
	start_from_loadout(panel)
	assert_not_null(panel.lesson)
	if panel.lesson!=null:
		assert_eq(panel.lesson.definition.recipe_id,shell.profile.research.catalog.chart(atlas_id).recipe_id)
	panel.back()

func _play_overseas_shift(town_id: String, step: int, atlas_id: String, target: int) -> bool:
	shell.guide.set_process(false)
	_position_story(step)
	var p := shell.profile
	assert_true(shell._arrive(town_id).ok)
	shell._enter_story_branch(town_id)
	var visit := shell.branch_visit
	assert_not_null(visit)
	if visit==null: return false
	var store_id := visit.store_id
	var mentor_flag := "mentors_" + town_id
	assert_true(shell.guide.journey.remote_landmark({"kind":"market"}))
	if not _press_shift_button("学习当地料理"): return false
	assert_true(TDRevisedMainline.flag(p.story.revised,mentor_flag))
	if town_id=="paris":
		TDRevisedMainline.mark(p.story.revised,"paris_training_started")
		assert_has(p.research.snapshot().unlocked,"E21")
		assert_has(p.research.snapshot().unlocked,"E07")
		shell._manage_training_store(store_id,"menu")
		shell._manage_training_store(store_id,"books")
		shell._close_dialog()
	var recipe_id: String=p.research.catalog.chart(atlas_id).recipe_id
	var offer := p.service.offer(recipe_id)
	var price := int(offer.reference_cents)
	assert_true(p.branches.configure_store(store_id,[{"id":recipe_id,"price_cents":price}],0).ok)
	var bought := p.buy(offer.stock,town_id)
	assert_true(bought.ok,bought.code)
	var before_xp := p.progression.threshold(target)-1
	assert_true(p.add_debug_xp(before_xp).ok)
	assert_eq(int(p.progression.progress().level),target-1)
	shell.guide.journey.tick(0)
	assert_eq(p.story.revised.cursor,step)
	assert_null(shell._challenge)

	var interact := InputEventAction.new()
	interact.action="world_interact"
	interact.pressed=true
	var dining := visit.dining
	dining.teleport_player(Vector2i(1,3))
	dining._unhandled_input(interact)
	if not _press_shift_button("开门营业"): return false
	assert_true(p.branches.training_open(store_id))
	assert_eq(p.shop.current_phase(),"PREPARE","The home store stays shut.")
	var family := p.commerce.society.identity(town_id,p.commerce.config.groups[0].id,0)
	var ordered := p.branches.sell(store_id,recipe_id,family)
	assert_true(ordered,"A local household orders from the branch menu.")
	if not ordered: return false
	var live := visit.kitchen_session
	live.advance(0)
	assert_eq(dining.guest_nodes().size(),1)
	if dining.guest_nodes().is_empty(): return false
	var guest: TDRestaurantGuest=dining.guest_nodes()[0]
	live.advance(guest.walking_seconds()+guest.sit_duration)
	assert_eq(guest.phase,"wait_serve")
	var ticket := guest.ticket_id
	assert_eq(live.order(ticket).recipe_id,recipe_id)
	visit.show_room("kitchen")
	if not _cook_shift_order(visit,offer): return false
	assert_false(live.table_service.for_order(ticket).is_empty())
	assert_eq(int(live.order(ticket).prepaid_cents),0)

	visit.show_room("restaurant")
	dining.teleport_player(dining.service_window_cell())
	dining._unhandled_input(interact)
	dining.teleport_player(dining._beside_seat(guest.seat_id))
	dining._unhandled_input(interact)
	assert_eq(live.order(ticket).status,"SERVED")
	assert_eq(p.commerce.society.state.holds[ticket].status,"paid")
	assert_gt(int(p.branches.state.stores[store_id].daily.sales_cents),0)
	assert_eq(int(p.progression.progress().total_xp),before_xp)
	if town_id=="paris":
		live.advance(TDGuestVisit.EAT_SEC+TDGuestVisit.PAY_SEC+0.1)
		assert_eq(guest.phase,"pay")
		dining._unhandled_input(interact)
		live.advance(0.1)
		if is_instance_valid(guest): live.advance(guest.walking_seconds()+0.1)
		assert_true(dining.guest_nodes().is_empty())

	dining.teleport_player(Vector2i(1,3))
	dining._unhandled_input(interact)
	if not _press_shift_button("打烊并结算"): return false
	assert_eq(p.shop.current_phase(),"SETTLED")
	assert_false(p.branches.training_open(store_id))
	var day := int(p.shop.frame_status().day)
	var training_rows := p.branches.level_rows(day)
	assert_eq(training_rows.size(),1)
	if training_rows.is_empty(): return false
	assert_eq(training_rows[0].store_id,store_id)
	var report := p.level_daily_report()
	assert_true(report.ok,report.code)
	var home_rows: Array = report.data.stores.filter(func(row: Dictionary) -> bool: return row.store_id=="player_diner")
	var with_branch := p.progression.evaluate(report.data)
	var without_branch := p.progression.evaluate({"day":day,"stores":home_rows})
	assert_gt(int(with_branch.data.mapped_xp),int(without_branch.data.mapped_xp),"Today's branch must contribute experience.")
	var levels := p.progression.snapshot()
	assert_eq(int(levels.last_day),day-1,"Closing records the business without awarding experience.")
	assert_eq(int(levels.total_xp),before_xp)
	if town_id=="paris":
		shell._manage_training_store(store_id,"books")
		shell._close_dialog()
		shell.guide.journey.tick(0)
		assert_true(TDRevisedMainline.flag(p.story.revised,"paris_training_complete"))
		assert_eq(p.story.revised.cursor,8)
	shell._sleep(town_id,0)
	levels = p.progression.snapshot()
	assert_eq(int(levels.last_day),day,"Rest applies experience from the closed business day.")
	assert_eq(int(levels.total_xp),before_xp+int(with_branch.data.mapped_xp))
	assert_gte(int(levels.level),target)
	if int(levels.last_day)!=day: return false
	assert_eq(levels.recent.back().input.stores.map(func(row: Dictionary) -> String: return row.store_id),[store_id,"player_diner"])
	assert_eq(p.settle_progression().code,"NOT_DUE")
	assert_true(TDGameProfile.validate_save(p.snapshot()).ok)
	return true

func _press_shift_button(label: String) -> bool:
	var buttons := shell._modal_box.find_children("*","Button",true,false) if shell._modal_box!=null else []
	for button: Button in buttons:
		if button.text==label:
			button.pressed.emit()
			return true
	fail_test("Missing button: " + label)
	return false

func _cook_shift_order(visit: TDBranchInterior, offer: Dictionary) -> bool:
	var view := visit.shop_view
	var recipe := visit.profile.service.cooking.recipe_data(offer.id)
	var pot := TDCuisineKitchen.station_for(visit.kitchen_session.cuisine_id,recipe)
	for food: String in offer.primary:
		var picked := view.pick_ingredient(food)
		assert_true(picked.ok,picked.code)
		if not picked.ok: return false
		if recipe.preparation_sheets.has(food):
			view._station_action("kitchen.board","interact")
			assert_true(view.choose_cut("slice").ok)
			if not _play_shift_lane(visit,view.kitchen.prep): return false
			view.kitchen.close_bench()
			view._station_action("kitchen.board","interact")
		view._station_action(pot,"interact")
	view._station_action(pot,"open")
	var lane: TDCookingLane = view.kitchen.lanes[view.kitchen.pot_index(pot)]
	assert_eq(lane.base_recipe_id,offer.id)
	if not _play_shift_lane(visit,lane): return false
	assert_eq(lane.snapshot().state,"plated")
	assert_false(lane.snapshot().failed_dish)
	view.kitchen.close_bench()
	view._station_action(pot,"interact")
	view._station_action("kitchen.serve","interact")
	return true

func _play_shift_lane(visit: TDBranchInterior, lane: TDCookingLane) -> bool:
	var sent: Dictionary={}
	for tick: int in 10000:
		visit.advance(.05)
		CuisineInput.drive(lane,sent)
		if lane.sheet!=null and not lane.sheet.running and lane.qte==null and lane.thermal_qte==null: return true
	fail_test("The cooking stage did not finish.")
	return false

func test_overseas_boards_open_local_business_and_save_independent_decoration() -> void:
	shell.guide.set_process(false)
	var p := shell.profile
	var original_layout := p.layout.to_dict()
	var interact := InputEventAction.new()
	interact.action="world_interact"
	interact.pressed=true
	var finished: Dictionary={}
	for fixture: Array in [["paris",8,"wood","french",Vector2i(2,2)],["tokyo",13,"paper","japanese",Vector2i(0,2)]]:
		_position_story(fixture[1])
		assert_true(shell._arrive(fixture[0]).ok)
		shell._enter_story_branch(fixture[0])
		var visit := shell.branch_visit
		assert_not_null(visit)
		if visit==null: return
		var room := visit.dining
		assert_eq(room.layout.culture,fixture[3])
		assert_true(room.layout.can_reach_protected_access())
		assert_eq(visit.iso.interaction_markers.map(func(marker: Dictionary) -> String: return marker.action),
			["town","menu","ledger","decorate","kitchen"])
		room.teleport_player(Vector2i(1,3))
		room._unhandled_input(interact)
		assert_not_null(shell._modal)
		assert_true(shell._modal_box.find_children("*","Button",true,false).any(func(button: Button) -> bool: return button.text=="菜单与价格"))
		shell._close_dialog()
		room.teleport_player(Vector2i(1,room.layout.rows-3))
		room._unhandled_input(interact)
		assert_true(room._editing and room._decor_panel.is_visible_in_tree())
		room._choose_decoration(fixture[2],true)
		var id := visit.store_id
		finished[id]=fixture
		var sample: Vector2i=fixture[4]
		assert_eq(room.layout.finish_at(sample.x,sample.y),fixture[2])
		room._decor_panel.done.emit()
		assert_true(visit.player.controls_enabled)
		assert_eq(room.place_kind("screen",1,3).code,"BLOCKED_ACCESS")
		assert_true(room.place_kind("screen",1,2).ok)
		visit.player.position=Vector2.ZERO
		visit.show_room("restaurant")
		assert_true(room.layout.feet_inside(visit.player.position))
		assert_eq(p.layout.to_dict(),original_layout)
		assert_true(TDGameProfile.validate_save(p.snapshot()).ok)
		shell.exit_branch()
	for id: String in finished:
		var restored := p.branches.dining_layout(id,p.layout._catalog)
		var sample: Vector2i=finished[id][4]
		assert_eq(restored.finish_at(sample.x,sample.y),finished[id][2])

func test_journal_has_no_skip_and_real_duels_report_their_terminal_result() -> void:
	_position_story(2)
	shell.travel("kitchen")
	shell.profile.record_challenge_result(TDChallengeBattle.Phase.LOST,"chen","","")
	shell.profile.complete_rojin_advice()
	shell.guide.show_revised_journal()
	for child: Node in shell._modal_box.get_children():
		if child is Button: assert_false(child.text.contains("跳过"))
	shell._close_dialog()
	shell.guide.journey.start_cooking()
	var encounter := shell._challenge
	assert_not_null(encounter.skill_setup,"The storyline presents loadout first")
	assert_null(encounter.lesson)
	encounter.warehouse_slots[0].pressed.emit()
	assert_eq(encounter.loadout,["",""],"Inspecting a skill leaves the loadout untouched")
	assert_string_contains(encounter._skill_details.text,"场上所有倒计时加 1")
	assert_string_contains(encounter._skill_details.text,"消耗 4 能量")
	encounter._quick_equip.pressed.emit()
	assert_eq(encounter.loadout,[TDChallengeBattle.Skills.DELAY,""])
	assert_string_contains(encounter._skill_details.text,"已装配至 E")
	start_from_loadout(encounter)
	assert_not_null(encounter.notice)
	assert_null(encounter.lesson)
	assert_true(get_tree().paused)
	assert_string_contains(encounter.notice.body.text,"番茄炒蛋")
	confirm_notices(encounter)
	var lesson: TDResearchLesson=encounter.lesson
	assert_not_null(lesson)
	if lesson==null: return
	assert_eq(lesson.definition.recipe_id,"service.tomato_egg")
	var driver:=TDResearchSession.new(shell.profile.research.catalog)
	driver.controller=lesson
	driver._active={"token":"fixture"}
	var sent: Dictionary={}
	var input := preload("res://tools/test_support/research_input.gd")
	var stages: Array[String] = []
	var plating_source := ""
	for i: int in 4500:
		if lesson.update().data.get("ready_to_finish",false): break
		input.tick(driver,"fixture",sent,get_tree().root)
		var lane := lesson.active_lane()
		if not lane.food_stage.is_empty() and lane.food_stage not in stages:
			stages.append(lane.food_stage)
		if lane.food_stage == "plate:dish": plating_source = lane.plating_source
	assert_eq(stages,["wok:empty","wok:oil","wok:egg>curds","wok:curds+tomato_dice>dish","plate:dish"])
	assert_eq(plating_source,"wok:curds+tomato_dice>dish")
	assert_true(lesson.update().ok,lesson.update().code)
	assert_eq(lesson.update().data.get("dish_state"),"plated",str(lesson.update().data))
	var expected_score := roundi(float(lesson.update().data.quality) * 100.0)
	shell._challenge.advance_cooking(0)
	assert_true(TDRevisedMainline.flag(shell.profile.story.revised,"aling_cooking_taught"))
	assert_not_null(shell._challenge,"Plating opens the real challenge panel")
	if shell._challenge==null: return
	assert_null(encounter.battle)
	assert_eq(encounter.preparation.player_score,expected_score)
	assert_between(int(encounter.preparation.opponent_score),40,50)
	assert_null(encounter.skill_setup)
	assert_eq(encounter.notice.body.text,"料理得分 · 你 %d 分 · 阿铃 %d 分" % [expected_score, int(encounter.preparation.opponent_score)])
	await get_tree().process_frame
	assert_eq(encounter.notice.body.get_line_count(),1)
	encounter.notice.confirm_button.pressed.emit()
	assert_true(encounter.notice.body.text.begins_with("比拼结果 · "))
	assert_eq(encounter.notice.body.get_line_count(),1)
	encounter.notice.confirm_button.pressed.emit()
	assert_eq(encounter.notice.body.text,encounter.preparation.description)
	assert_eq(encounter.notice.body.get_line_count(),1)
	assert_null(encounter.battle,"The last page is acknowledged before combat")
	encounter.notice.confirm_button.pressed.emit()
	assert_eq(encounter.battle.opponent.id,"aling")
	assert_eq(encounter.battle.skill_slots,[TDChallengeBattle.Skills.DELAY,""])
	encounter._finish_story(TDChallengeBattle.Phase.LOST)
	assert_eq(shell.profile.story.revised.cursor,2)
	shell.guide.journey._battle_finished(TDChallengeBattle.Phase.WON,2)
	assert_eq(shell.profile.story.revised.cursor,3)
	_position_story(5)
	shell.guide.journey._battle_finished(-1,5)
	assert_eq(shell.profile.story.revised.cursor,5,"Exiting is not an evaluation")
	shell.guide.journey._battle_finished(TDChallengeBattle.Phase.DRAW,5)
	assert_eq(shell.profile.story.revised.cursor,6,"Completing the evaluation leads into the authored defeat")

func test_all_mainline_duels_resume_native_dialogue_on_terminal_result() -> void:
	shell.guide.set_process(false)
	var attack := InputEventKey.new()
	attack.physical_keycode = KEY_F
	attack.pressed = true
	for encounter: Array in [[2,0,3],[5,1,6],[10,2,11],[13,3,14],[18,1,19],[23,4,24]]:
		var step := int(encounter[0])
		var assessment := step == 5
		var next := int(encounter[2])
		_position_story(step)
		shell._show_challenge({"opponent": encounter[1], "assessment": assessment},
			shell.guide.journey._battle_finished.bind(step))
		var panel := shell._challenge
		assert_not_null(panel)
		if panel == null: return
		stage_test_battle(panel)
		var battle := panel.battle
		if assessment:
			battle.hp = battle._enemy_damage(1)
			battle._schedule_strike([battle.hero], 1)
		else:
			battle.foe = battle.hero + Vector2i.RIGHT
			battle.foe_hp = 2
		assert_true(panel.handle_key(attack))
		assert_true(panel.handle_key(attack))
		assert_eq(battle.phase, TDChallengeBattle.Phase.LOST if assessment else TDChallengeBattle.Phase.WON)
		assert_true(panel.decision.find_children("*","Button",true,false).is_empty())
		confirm_notices(panel)
		await get_tree().process_frame
		await get_tree().process_frame
		assert_null(shell._challenge)
		assert_null(shell._modal)
		assert_false(get_tree().paused)
		assert_eq(shell.profile.story.revised.cursor,next)
		assert_true(shell.guide.presenting())
		assert_true(shell.guide.dialogue._native)
		if shell.guide.dialogue.talk == null: return
		assert_eq(shell.guide.dialogue.talk.context.scene,"revised_%02d" % next)

func stage_test_battle(panel: TDChallengePanel) -> void:
	panel.should_teach = Callable()
	panel._close_cooking()
	panel.preparation = TDChallengeBattle.Rules.compare(50, 50)
	panel._enter_battle()

func start_from_loadout(panel: TDChallengePanel) -> void:
	if panel.skill_setup==null: return
	for button: Button in panel.skill_setup.find_children("*","Button",true,false):
		if button.text=="开始做菜":
			button.pressed.emit()
			return

func confirm_notices(panel: TDChallengePanel) -> void:
	for index: int in 3:
		if not is_instance_valid(panel.notice): return
		panel.notice.confirm_button.pressed.emit()

func battle_key(panel: TDChallengePanel, key: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = true
	assert_true(panel.handle_key(event))

func test_first_combat_tutorials_gate_real_actions_and_resume_normal_battles() -> void:
	const Tutorial := TDChallengeBattle.Tutorial
	shell.guide.dialogue.finish_now()
	shell.guide.set_process(false)
	shell._show_challenge({"opponent":0})
	var panel := shell._challenge
	panel._close_cooking()
	panel.preparation = TDChallengeBattle.Rules.compare(50, 50)
	panel._enter_battle()
	var battle := panel.battle
	var original_foe := battle.foe
	assert_eq(battle.tutorial, Tutorial.ALING_MOVE)
	battle_key(panel, KEY_F)
	assert_eq(battle.ap, 4)
	for key: Key in [KEY_W, KEY_A, KEY_S, KEY_D]: battle_key(panel, key)
	assert_eq(battle.tutorial, Tutorial.ALING_LINE)
	for hit: int in 4:
		battle_key(panel, KEY_SPACE)
		assert_eq(panel.tutorial_hint.text, "使用鼠标左键确定攻击方向")
		panel._click_cell(battle.foe)
	assert_eq(battle.tutorial, Tutorial.ALING_SQUARE)
	for hit: int in 4:
		battle_key(panel, KEY_F)
		assert_eq(panel.tutorial_hint.text, "再次按下F键确认后释放攻击")
		assert_eq(battle.tutorial, Tutorial.ALING_SQUARE)
		battle_key(panel, KEY_F)
	assert_eq(battle.tutorial, Tutorial.ALING_BUDGET)
	for key: Key in [KEY_W, KEY_A, KEY_S, KEY_D]: battle_key(panel, key)
	assert_eq(battle.foe, original_foe)
	assert_eq(battle.foe_hp, battle.foe_max_hp)
	assert_eq(battle.tutorial, Tutorial.ALING_DODGE)
	assert_eq(battle.warnings[battle.hero], [2])
	for input: int in 4: battle_key(panel, KEY_F)
	assert_eq(battle.tutorial, Tutorial.ALING_DODGE,"Taking the hit repeats the dodge exercise")
	assert_eq(battle.hp, battle.max_hp - 2)
	battle_key(panel, KEY_W)
	battle_key(panel, KEY_W)
	assert_eq(battle.tutorial, Tutorial.NONE)
	assert_eq(battle.ap, 4)
	assert_eq(battle.hp, battle.max_hp)
	assert_eq(battle.round_number, 1)
	assert_has(shell.profile.challenge_progress.tutorials, "aling")
	assert_eq(panel.tutorial_text.text,"现在阿玲要动真格了！集中注意与她比拼吧！")
	battle.foe = battle.hero + Vector2i.RIGHT
	battle.foe_hp = 2
	battle_key(panel, KEY_F)
	assert_eq(battle.foe_hp, 2)
	battle_key(panel, KEY_F)
	assert_eq(battle.phase, battle.Phase.WON)
	assert_eq(panel.notice.body.text,"获得技能 · 驱遣夜鸦程度的能力")
	await get_tree().process_frame
	assert_eq(panel.notice.body.get_line_count(),1)
	panel.notice.confirm_button.pressed.emit()
	assert_eq(panel.notice.body.text,"下次备战可装配技能。")
	assert_eq(panel.notice.body.get_line_count(),1)
	panel.notice.confirm_button.pressed.emit()
	shell._close_dialog()

	shell._show_challenge({"opponent":1})
	panel = shell._challenge
	assert_not_null(panel.skill_setup)
	stage_test_battle_with_tutorial(panel)
	battle = panel.battle
	assert_eq(battle.tutorial, Tutorial.CHEN_CAST)
	assert_eq(battle.energy, 5)
	battle_key(panel, KEY_E)
	assert_eq(panel.tutorial_hint.text,"使用鼠标左键确定攻击方向，使用技能也会消耗行动点")
	panel._click_cell(battle.foe)
	assert_eq(battle.energy, 0)
	assert_eq(battle.ap, 3)
	assert_eq(battle.tutorial, Tutorial.CHEN_CHARGE)
	for hit: int in 5:
		battle_key(panel, KEY_F)
		battle_key(panel, KEY_F)
		assert_eq(battle.ap, 3,"Practice hits don't spend AP")
	assert_eq(battle.tutorial, Tutorial.CHEN_PICKUP)
	assert_eq(battle.foe_hp, battle.foe_max_hp)
	assert_eq(battle.energy, 5)
	assert_eq(battle.pickups.size(), 1)
	var pickup := battle.pickups[0]
	for step: int in 3:
		if battle.tutorial != Tutorial.CHEN_PICKUP: break
		if battle.hero.x != pickup.x: battle_key(panel, KEY_D if pickup.x > battle.hero.x else KEY_A)
		else: battle_key(panel, KEY_S if pickup.y > battle.hero.y else KEY_W)
	assert_eq(battle.tutorial, Tutorial.NONE)
	assert_eq(battle.energy, 7)
	assert_eq(battle.ap, 4)
	assert_eq(battle.skill_slots, ["",""],"The practice skill doesn't change the player's loadout")
	assert_has(shell.profile.challenge_progress.tutorials, "chen")

func stage_test_battle_with_tutorial(panel: TDChallengePanel) -> void:
	panel._close_cooking()
	panel.preparation = TDChallengeBattle.Rules.compare(50, 50)
	panel._enter_battle()

func test_rojin_reward_waits_for_the_first_post_fight_conversation() -> void:
	_position_story(5)
	shell.guide.set_process(false)
	const Skills := TDChallengeBattle.Skills
	var profile := shell.profile
	assert_eq(profile.record_challenge_result(TDChallengeBattle.Phase.LOST,"chen","",""), [])
	shell.guide.journey._battle_finished(TDChallengeBattle.Phase.LOST, 5)
	assert_false(Skills.DELAY in Skills.unlocked(profile.story, profile.challenge_progress))
	await Driver.finish(shell.guide.dialogue, get_tree())
	await get_tree().process_frame
	assert_not_null(shell._challenge_notice)
	if shell._challenge_notice==null: return
	assert_null(_open_chart())
	assert_eq(shell._challenge_notice.body.text,"获得技能 · 师承金娜的保命程度的能力")
	assert_eq(shell._challenge_notice.body.get_line_count(),1)
	assert_has(Skills.unlocked(profile.story, profile.challenge_progress), Skills.DELAY)
	shell._challenge_notice.confirm_button.pressed.emit()
	assert_not_null(_open_chart())

func test_challenge_menu_is_locked_until_the_final_dialogue_finishes() -> void:
	shell.guide.set_process(false)
	_position_story(24)
	var button := shell._hud.button_for("challenge") as TDGameHUD.IconButton
	shell._hud.update_profile(shell.profile)
	assert_true(button.locked and button.disabled)
	assert_string_contains(button.tooltip_text,TDRevisedMainline.CHALLENGE_LOCK_HINT)
	var shortcut := InputEventAction.new()
	shortcut.action="challenge_menu"
	shortcut.pressed=true
	shell.show_pause()
	var pause_menu := shell._modal
	button.pressed.emit()
	shell._input(shortcut)
	shell._show_challenge()
	assert_null(shell._challenge)
	assert_same(shell._modal,pause_menu)
	shell._close_dialog()

	shell.guide.journey.tick(0)
	assert_true(shell.guide.presenting())
	await Driver.finish(shell.guide.dialogue,get_tree())
	assert_eq(shell.profile.story.revised.cursor,25)
	shell._hud.update_profile(shell.profile)
	assert_false(button.locked or button.disabled)
	assert_string_contains(button.tooltip_text,"[C]")
	button.pressed.emit()
	assert_not_null(shell._challenge)
	shell._close_dialog()
	shell._input(shortcut)
	assert_not_null(shell._challenge)

func test_challenge_menu_cooking_provides_the_actual_score_and_replay_starts_a_new_lesson() -> void:
	shell.guide.set_process(false)
	_position_story(25)
	shell._open_management("challenge")
	var panel := shell._challenge
	assert_not_null(panel)
	if panel==null: return
	assert_not_null(panel.find_child("SkillAdjustment",true,false))
	var card := panel.selection.get_child(0) as Button
	card.pressed.emit()
	assert_null(panel.battle)
	assert_false(get_tree().paused,"Cooking accepts real kitchen input")
	var lesson := panel.lesson
	assert_not_null(lesson)
	if lesson==null: return
	var driver := TDResearchSession.new(shell.profile.research.catalog)
	driver.controller=lesson
	driver._active={"token":"fixture"}
	var sent := {}
	var player := preload("res://tools/test_support/research_input.gd")
	for tick: int in 4500:
		if lesson.update().data.get("ready_to_finish",false): break
		player.tick(driver,"fixture",sent,get_tree().root)
	assert_true(lesson.update().data.get("ready_to_finish",false))
	var expected := roundi(clampf(float(lesson.update().data.quality),0,1)*100)
	panel.advance_cooking(0)
	assert_null(panel.battle)
	assert_eq(panel.preparation.player_score,expected)
	assert_not_null(panel.notice)
	assert_true(get_tree().paused)
	confirm_notices(panel)
	assert_eq(panel.battle.preparation.player_score,expected)
	panel._start(0)
	assert_null(panel.battle)
	assert_not_null(panel.lesson)
	assert_true(panel.preparation.is_empty())

func test_missing_post_battle_scenario_restores_movement_and_can_retry() -> void:
	_position_story(3)
	assert_true(shell.travel("kitchen").ok)
	var guide := shell.guide
	var talk := TDRevisedMainline.talk(TDRevisedMainline.current(shell.profile.story.revised))
	talk.context.event_chapter = {
		"id":"revised_03", "title":"第二场", "script_path":"res://missing-post-battle-scene.txt"
	}
	guide.show_talk(talk)
	await get_tree().process_frame
	assert_false(guide.presenting())
	assert_false(get_tree().paused)
	assert_false(shell.kitchen_view.kitchen.shared_clock.paused)
	assert_true(shell.kitchen_view.kitchen.world._player.controls_enabled)
	assert_eq(shell.profile.story.revised.cursor,3)
	assert_same(guide._failed_revised_scene,talk)

	# Once the resource is available, the journal resumes that segment without replaying the duel.
	talk.context.erase("event_chapter")
	guide.show_revised_journal()
	var retry := shell._modal_box.find_children("*","Button",true,false).filter(
		func(button: Button) -> bool: return button.text == "重试当前剧情")
	assert_eq(retry.size(),1)
	if retry.is_empty(): return
	retry[0].pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(guide.presenting())
	assert_false(guide.dialogue.talk.body.is_empty())
	await Driver.finish(guide.dialogue,get_tree())
	await get_tree().process_frame
	assert_eq(shell.profile.story.revised.cursor,4)
	assert_eq(shell.location,"town")
	assert_true(shell.town._player.controls_enabled)
	assert_false(shell.kitchen_view.kitchen.shared_clock.paused)

func test_training_visit_purchase_real_order_and_safe_hotel_checkpoint() -> void:
	_position_story(7)
	shell.town.spawn_at_harbor()
	var voyage := shell.voyage("paris")
	assert_true(voyage.ok,voyage.code)
	if not voyage.ok: return
	shell.guide.journey.tick(0)
	await Driver.finish(shell.guide.dialogue,get_tree())
	await get_tree().process_frame
	assert_eq(shell.profile.story.revised.cursor,8)
	assert_eq(shell.location,"branch")
	if shell.branch_visit==null: return
	var site := shell.branch_visit.store_id
	var p := shell.profile
	assert_true(p.research.learn_story("story:mentors_paris","eu",["E02","E03","E06"]).ok)
	TDRevisedMainline.mark(p.story.revised,"mentors_paris")
	var rows := p.branches.recipes("eu")
	assert_false(rows.is_empty())
	var recipe: String=p.research.catalog.chart("E02").recipe_id
	var matching := rows.filter(func(it:Dictionary)->bool:return it.id==recipe)
	assert_false(matching.is_empty(),str(rows))
	if matching.is_empty(): return
	var row: Dictionary=matching[0]
	assert_true(p.branches.configure_store(site,[{"id":row.id,"price_cents":row.reference_cents}],0).ok)
	assert_true(p.buy(row.ingredients,"paris").ok)
	for key: String in row.ingredients:
		assert_eq(p.branches.state.stores[site].inventory[key],row.ingredients[key])
	var room := shell.branch_visit.dining
	room.teleport_player(Vector2i(1,3))
	var interact := InputEventAction.new()
	interact.action="world_interact"
	interact.pressed=true
	room._unhandled_input(interact)
	var open := shell._modal_box.find_children("*","Button",true,false).filter(func(button: Button) -> bool: return button.text=="开门营业")
	assert_eq(open.size(),1)
	if open.is_empty(): return
	open[0].pressed.emit()
	assert_true(p.branches.training_open(site))
	assert_eq(p.shop.current_phase(),"PREPARE")
	room.teleport_player(Vector2i(1,room.layout.rows-3))
	room._unhandled_input(interact)
	assert_false(room._editing)
	assert_eq(shell._write_checkpoint(TDProfileStore.STORY).code,"SHOP_OPEN")
	var live := shell.branch_visit.kitchen_session
	var family := p.commerce.society.identity("paris",p.commerce.config.groups[0].id,0)
	assert_true(p.branches.sell(site,row.id,family))
	assert_eq(live.pending_orders().size(),1)
	assert_true(p.shop.close_for_night().ok)
	assert_eq(p.branches.level_rows(1).size(),1)
	shell._sleep("paris",0)
	assert_true(shell.slots.load_slot("slot-01",TDProfileStore.DAILY).ok)
	assert_true(shell.load_game("slot-01").ok)
	assert_eq(shell.location,"voyage")
	assert_eq(shell.visiting_town,"paris")
	assert_eq(shell.visiting.nearby().get("kind"),"hotel")

func test_revised_mode_retains_independent_first_business_homecoming_flags() -> void:
	var story := TDOpening.new(); story.begin(); story.beat = "done"
	story.revised = TDRevisedMainline.initial()
	story.note_opened(); assert_true(story.opened)
	story.note_served(); assert_true(story.served); assert_false(story.opened)
	assert_eq(story.revised.cursor,0,"Housing milestones do not advance revised mainline")

func test_expansion_milestones_unlock_in_order_and_final_appointment_waits_until_tomorrow() -> void:
	# These fixtures tick the journey manually between consecutive dialogues.
	shell.guide.set_process(false)
	_position_story(15)
	var p := shell.profile
	var actual_level := p.progression.snapshot()
	assert_true(shell._arrive("tokyo").ok)
	shell._enter_story_branch("tokyo")
	assert_eq(shell.location,"branch")
	var site := p.branches.training_store()
	shell._manage_training_store(site,"menu")
	var panel := shell._modal_box.find_children("*","TDBranchPanel",true,false)[0] as TDBranchPanel
	assert_eq(panel.tab_buttons.keys(),["menu","books"])
	shell._close_dialog()
	p.progression._state.level=11
	assert_string_contains(shell.guide.objective().text,"Lv.11 / 20")
	assert_string_contains(shell.guide.objective().text,"雇员招聘（12 级）")
	shell.guide.journey.tick(0)
	assert_false(shell.guide.presenting())
	for feature: String in ["employees","suppliers","branches"]: assert_false(p.story_feature_available(feature))
	assert_eq(p.employees.sign_employee("unavailable","check","check").code,"STORY_LOCKED")
	assert_eq(p.menu_supply.set_enabled(true).code,"STORY_LOCKED")
	assert_eq(p.branches.quote("chengdu",[1,1,3,3],"cn").code,"STORY_LOCKED")
	shell.show_branch()
	assert_null(shell._modal)
	var unlocked: Array[String]=[]
	for entry: Array in [[12,"employees"],[15,"suppliers"],[18,"branches"]]:
		var feature: String=entry[1]
		p.progression._state.level=entry[0]-1
		shell.guide.journey.tick(0)
		assert_false(shell.guide.presenting())
		p.progression._state.level=entry[0]
		if feature=="suppliers": shell.guide.request_person("aling")
		else: shell.guide.journey.tick(0)
		assert_true(shell.guide.presenting())
		if not shell.guide.presenting(): return
		assert_eq(shell.guide.dialogue.talk.context.scene,feature)
		assert_false(p.story_feature_available(feature),"Viewing the dialogue is not yet an unlock")
		await Driver.finish(shell.guide.dialogue,get_tree())
		unlocked.append(feature)
		for id: String in ["employees","suppliers","branches"]:
			assert_eq(p.story_feature_available(id),id in unlocked,id)
		shell.guide.journey.tick(0)
		assert_false(shell.guide.presenting(),"Each unlock dialogue runs once")
		assert_eq(p.story.revised.cursor,15)
		match feature:
			"employees":
				var cook: Dictionary=p.employees.market_rows("tokyo","cook")[0]
				assert_true(p.employees.sign_employee(cook.id,"training-hire",cook.offer_key).ok)
				assert_true(p.employees.assign(cook.id,site).ok)
				var europe_site := p.branches.preset_in("paris")
				assert_true(p.branches.can_support_store(europe_site))
				assert_eq(p.employees.assign(cook.id,europe_site).code,"CUISINE_MISMATCH")
			"suppliers":
				assert_true(p.menu_supply.set_enabled(true).ok)
				assert_eq(p.menu_supply.store_ids(),["player_diner",site,p.branches.preset_in("paris")])
			"branches":
				assert_ne(p.branches.quote("chengdu",[1,1,3,3],"cn").code,"STORY_LOCKED")
	p.progression._state.level=20
	shell.guide.journey.tick(0)
	assert_eq(shell.guide.dialogue.talk.context.scene,"return_home")
	assert_false(shell._story_passenger_route("chengdu"))
	await Driver.finish(shell.guide.dialogue,get_tree())
	shell.guide.journey.tick(0)
	assert_eq(p.story.revised.cursor,16)

	_position_story(21)
	assert_true(p.progression.restore(actual_level).ok)
	var story := p.story.revised
	shell.travel("town")
	shell.town.spawn_at_harbor()
	shell.guide.journey.record_practice({"recipe_id":"study.c20","state":"plated","failed_dish":false})
	assert_eq(story.cursor,22)
	assert_eq(story.prepared_day,p.characters.clock.day)
	shell.guide.journey.tick(0)
	assert_false(shell.guide.presenting())
	assert_true(p.shop.close_for_night().ok)
	assert_true(p.next_day().ok)
	shell.guide.journey.tick(0)
	assert_eq(shell.guide.dialogue.talk.context.scene,"revised_22")

func test_expansion_catches_up_in_order_and_keeps_previously_introduced_features() -> void:
	# These fixtures tick the journey manually between consecutive dialogues.
	shell.guide.set_process(false)
	_position_story(15)
	var p := shell.profile
	assert_true(shell._arrive("tokyo").ok)
	shell._enter_story_branch("tokyo")
	p.progression._state.level=20
	for feature: String in ["employees","suppliers","branches","return_home"]:
		shell.guide.journey.tick(0)
		assert_true(shell.guide.presenting())
		if not shell.guide.presenting(): return
		assert_eq(shell.guide.dialogue.talk.context.scene,feature)
		await Driver.finish(shell.guide.dialogue,get_tree())
	shell.guide.journey.tick(0)
	assert_eq(p.story.revised.cursor,16)

	_position_story(15)
	TDRevisedMainline.mark(p.story.revised,"business_expansion")
	p.progression._state.level=17
	assert_true(p.story_feature_available("employees"))
	assert_true(p.story_feature_available("suppliers"))
	assert_false(p.story_feature_available("branches"))
	p.progression._state.level=18
	shell.guide.journey.tick(0)
	assert_true(shell.guide.presenting())
	if shell.guide.presenting(): assert_eq(shell.guide.dialogue.talk.context.scene,"branches")
