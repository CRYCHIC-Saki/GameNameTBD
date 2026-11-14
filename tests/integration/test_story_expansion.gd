extends GutTest
const DRIVER=preload("res://tools/test_support/kitchen_input.gd")
var app: TDApplication
var shell: TDGameShell
var driver: RefCounted

func before_each() -> void:
	app=load("res://src/app/main.tscn").instantiate()
	app.settings_path="res://artifacts/story-expansion/tests/%d/settings.json"%Time.get_ticks_usec()
	add_child_autofree(app);shell=app.game_shell;shell.automatic_time=false
	assert_true(shell.create_game("slot-01","赤焰").ok);shell.guide.dialogue.finish_now()
	driver=DRIVER.new();driver.viewport=get_tree().root;driver.kitchen=shell.kitchen_view.kitchen
	await get_tree().process_frame

func after_each() -> void:
	get_tree().paused=false;shell.go_title()
	await get_tree().process_frame;await get_tree().process_frame

func test_journal_key_tracking_and_recipe_reading() -> void:
	driver.tap(KEY_J);assert_not_null(shell._modal);assert_true(get_tree().paused)
	driver.tap(KEY_ESCAPE);assert_null(shell._modal);assert_false(get_tree().paused)
	var was:=shell.profile.story.tracked;driver.tap(KEY_T);assert_eq(shell.profile.story.tracked,not was)
	shell.profile.story.beat="cook";driver.tap(KEY_B);assert_not_null(shell.atlas)
	await get_tree().process_frame
	assert_true(shell.profile.story.recipe_viewed);driver.tap(KEY_B)
	assert_null(shell.atlas)

func test_real_escort_waits_faces_player_and_resumes_without_teleport() -> void:
	var town:=shell.town;shell.profile.story.beat="follow";town._tick_escort(.01)
	var first:=town.escort_position();town._player.position=first+Vector2(500,0)
	town._tick_escort(10);assert_eq(town.escort_position(),first);assert_true(town._escort_waiting);assert_eq(town._escort_facing,Vector2i.RIGHT)
	town._player.position=first+Vector2(80,0);town._tick_escort(.1)
	assert_false(town._escort_waiting);assert_gt(town.escort_position().distance_to(first),0.0)
	var next:=town.escort_position();get_tree().paused=true;town._tick_escort(10);assert_eq(town.escort_position(),next)
	get_tree().paused=false;town._player.position=next;town._tick_escort(100)
	assert_lte(town.escort_position().distance_to(next),float(town.CELL*6+8),"A long frame cannot carry the guide out of range")

func test_cg_playback_is_frozen_by_pause_and_cancel_does_not_progress() -> void:
	shell.guide.present("intro");assert_true(shell.guide.presenting());assert_false(shell.town._player.controls_enabled)
	var talk:=shell.guide.dialogue.talk;talk.tick(.5);var elapsed:=talk.cg_elapsed
	get_tree().paused=true;await get_tree().process_frame;assert_eq(talk.cg_elapsed,elapsed)
	get_tree().paused=false;shell.guide.dialogue.finish_now();assert_eq(shell.profile.story.beat,"arrive")
	assert_false(shell.town.external_story_frozen);assert_true(shell.town._player.controls_enabled)
	shell.guide.present("intro");shell.guide.dialogue.talk.skip();shell.guide.dialogue._emit_if_finished();assert_eq(shell.profile.story.beat,"follow")

func test_movie_uses_full_screen_without_gal_box_and_restores_dialogue() -> void:
	shell.guide.present("intro")
	var view:=shell.guide.dialogue;var talk:=view.talk
	view.set_process(false);view._refresh()
	assert_false(view.get_node("Box").visible);assert_false(view.get_node("Portrait").visible)
	assert_true(view.get_node("FilmControls").visible);assert_eq(view._cg.size,view.size)
	var minute:=shell.profile.characters.clock.minute
	talk.tick(talk.cg_duration);view._refresh()
	assert_true(view.get_node("Box").visible);assert_true(view.get_node("Portrait").visible)
	assert_gt(view._panel.z_index,view._portrait.z_index)
	assert_true(view.get_node("FilmControls").visible);assert_eq(talk.full_text(),"终于到了。吾之舌啊，准备迎接万国料理的洗礼！")
	assert_eq(shell.profile.characters.clock.minute,minute);assert_false(shell.town._player.controls_enabled)
	view.finish_now();assert_true(shell.town._player.controls_enabled)

func test_end_movie_returns_control_once_without_click_or_reward_replay() -> void:
	var talk:=TDDialogue.new();talk.context={"kind":"story_replay"};talk.add_cg("sign","",.1);talk.add_cg("fire","",.1)
	shell.guide.show_talk(talk);shell.guide.dialogue.set_process(false)
	var old:=shell.profile.story.export_state();var ends: Array=[]
	shell.guide.dialogue.closed.connect(func(_s:String,_p:Array)->void:ends.append(1))
	shell.guide.dialogue._process(.3)
	assert_eq(ends.size(),1);assert_false(shell.guide.presenting());assert_true(shell.town._player.controls_enabled)
	shell.guide.dialogue._process(1);assert_eq(ends.size(),1);assert_eq(shell.profile.story.export_state(),old)

func test_tutorial_gate_freezes_exact_qte_and_world_then_resumes() -> void:
	shell.profile.story.beat="awaken";shell._apply_story(shell.profile.story.complete_scene("awaken"));shell.travel("kitchen")
	var view:=shell.kitchen_view;var kitchen:=view.kitchen
	assert_true(view.pick_ingredient("tomato").ok);driver.station("kitchen.board");assert_true(view.choose_cut("chunk").ok)
	kitchen.advance(10)
	await get_tree().process_frame
	assert_eq(shell.guide._pending_tutorial,"M1");assert_true(get_tree().paused)
	driver.tap(KEY_ESCAPE);assert_false(get_tree().paused)
	assert_does_not_have(shell.profile.story.tutorials,"M1","Closing is not acknowledgement")
	kitchen.advance(.1);await get_tree().process_frame
	assert_true(get_tree().paused);assert_eq(shell.guide._pending_tutorial,"M1","Cancelled lesson can reopen without a stuck clock")
	var qte_time:=kitchen.prep.clock.qte_sec;var minute:=shell.profile.characters.clock.minute
	kitchen.advance(30);assert_eq(kitchen.prep.clock.qte_sec,qte_time);assert_eq(shell.profile.characters.clock.minute,minute)
	var button: Button
	for node: Node in shell._modal_box.get_children():
		if node is Button and node.text=="明白了，开始操作": button=node
	assert_not_null(button);button.pressed.emit();assert_false(get_tree().paused);assert_has(shell.profile.story.tutorials,"M1")
	kitchen.advance(.1);assert_gt(kitchen.prep.clock.qte_sec,qte_time)

func test_both_escort_legs_bowl_interaction_and_story_save_round_trip() -> void:
	var story:=shell.profile.story;story.hero_name="测试厨神"
	var san_before:=shell.profile.world.san
	shell.guide.present("intro");shell.guide.dialogue.talk.skip();shell.guide.dialogue._emit_if_finished()
	var town:=shell.town
	for leg: String in ["follow","return"]:
		assert_eq(story.beat,leg)
		for step: int in 1600:
			town._player.position=town.escort_position();town._tick_escort(.1)
			if story.beat!=leg: break
		assert_ne(story.beat,leg,"Guide actually reaches this leg's destination")
		if leg=="follow":
			shell.guide.request_person("chen");shell.guide.dialogue._on_skip();assert_eq(story.beat,"bowl")
			var bowl_cell:=Vector2i((town.bowl_point()-town._origin())/town.CELL)
			assert_true(town.session.town_map.is_road(bowl_cell.x,bowl_cell.y),"The interactive bowl must be on reachable ground")
			town._player.position=town.bowl_point();town._interact();assert_not_null(shell._modal)
			for node: Node in shell._modal_box.get_children():
				if node is Button and node.text=="尝一口": node.pressed.emit();break
			shell.guide.dialogue._on_skip();assert_eq(shell.profile.world.san,san_before-5)
	shell.guide.present("awaken");shell.guide.dialogue._on_skip();assert_eq(story.beat,"cook")
	story.recipe_viewed=true;story.tutorials.append("M1");story.tracked=false
	var inventory: Dictionary=shell.profile.shop.snapshot().inventory
	var snapshot:=story.export_state();assert_true(shell.save_game().ok)
	shell.go_title();assert_true(shell.load_game("slot-01").ok)
	assert_true(TDLevelProgression.same_value(shell.profile.story.export_state(),snapshot))
	assert_eq(shell.profile.world.san,san_before-5)
	assert_true(TDLevelProgression.same_value(shell.profile.shop.snapshot().inventory,inventory))
	var exported:=shell.profile.snapshot()
	# Profile-level load validation rejects corrupt optional chapter state.
	exported.story={"script_version":99}
	assert_eq(TDGameProfile.validate_save(exported).code,"UNSUPPORTED_STORY_VERSION")

func test_old_completed_chapter_replay_cannot_repeat_rewards() -> void:
	shell.profile.story.beat="done";shell.profile.story.paid=true
	var before:=shell.profile.snapshot()
	var talk:=TDOpeningScript.conversation("after_taste","赤焰",100);talk.context={"kind":"story_replay"}
	shell.guide.show_talk(talk);shell.guide.dialogue._on_skip()
	assert_true(TDLevelProgression.same_value(shell.profile.snapshot(),before))

func test_first_cooking_pipeline_teaches_every_used_module_without_skipping_time() -> void:
	shell.profile.story.beat="awaken";shell._apply_story(shell.profile.story.complete_scene("awaken"));shell.travel("kitchen")
	var view:=shell.kitchen_view;var kitchen:=view.kitchen
	for lane: TDCookingLane in kitchen.lanes+[kitchen.prep]: lane.beat_offset_sec=0
	assert_true(view.pick_ingredient("tomato").ok);driver.station("kitchen.board");assert_true(view.choose_cut("chunk").ok)
	await play_with_lessons(14)
	driver.station("kitchen.board");driver.station("kitchen.stove.left")
	assert_true(view.pick_ingredient("egg").ok);driver.station("kitchen.stove.left");driver.station("kitchen.stove.left",KEY_F)
	await play_with_lessons(74)
	assert_eq(kitchen.lanes[0].snapshot().state,"plated")
	for module: String in ["M1","M2","M3","M4","M6","M7"]: assert_has(shell.profile.story.tutorials,module)
	assert_does_not_have(shell.profile.story.tutorials,"M5","Stir-fry must not pretend to teach steaming")
	assert_false(get_tree().paused);assert_eq(shell.guide._pending_tutorial,"")

func play_with_lessons(seconds: int) -> void:
	for step: int in seconds*2:
		driver.play(.5)
		await get_tree().process_frame
		if shell.guide._pending_tutorial!="" and shell._modal!=null:
			for node: Node in shell._modal_box.get_children():
				if node is Button and node.text=="明白了，开始操作": node.pressed.emit();break

func test_harbor_is_reachable_and_interactive_without_changing_property_or_save() -> void:
	var map:=shell.profile.world.town_map;var before:=shell.profile.snapshot()
	var port:=TDHarbor.facility(map);assert_eq(port.id,"harbor.hekou")
	for y: int in range(29,31):
		for x: int in range(71,73):
			assert_false(map.is_walkable(x,y));assert_false(map.can_place(x,y,1,1))
	var route:=TDQuestPath.find(Vector2i(20,34),TDHarbor.ARRIVAL,Rect2i(0,0,map.extent,map.extent),func(p:Vector2i)->bool:return map.is_road(p.x,p.y))
	assert_gt(route.size(),10);assert_eq(route[-1],TDHarbor.ARRIVAL)
	for direction: Vector2i in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:
		shell.town._player.position=shell.town._origin()+Vector2(70.5,33.5)*shell.town.CELL;shell.town._player.face(Vector2(direction))
		assert_eq(shell.town.facing_plot().id,"harbor.hekou")
	driver.tap(KEY_E);assert_not_null(shell._modal);assert_true(get_tree().paused)
	driver.tap(KEY_ESCAPE);assert_false(get_tree().paused)
	assert_true(TDLevelProgression.same_value(before,shell.profile.snapshot()),"Port preview does not unlock cargo routes, spend money or alter property")
