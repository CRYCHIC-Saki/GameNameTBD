extends GutTest

func test_editable_timeline_exact_shots_and_independent_initialization() -> void:
	var scene:=load("res://src/story/arrival_cutscene.tscn").instantiate() as TDArrivalCutscene
	add_child_autofree(scene)
	var player:=scene.get_node("AnimationPlayer") as AnimationPlayer
	assert_eq(player.get_animation("A_arrival").length,14.0)
	assert_eq(player.get_animation("B_hungry").length,6.0)
	assert_eq(player.get_animation("C_aling").length,10.0)
	for row: Array in [["arrival",0,1],["arrival",4,2],["arrival",8,3],["arrival",11,4],["hungry",0,5],["hungry",3,6],["messenger",0,7],["messenger",4,8],["messenger",7,9]]:
		scene.sample_segment(row[0],row[1]);assert_eq(scene.shot_index,row[2])
	scene.sample_segment("arrival",8.5)
	assert_eq(scene.get_node("MapRoot/TownName").text,"河口镇")
	assert_eq(scene.get_node("MapRoot/Caption").text,"百国商船汇聚，天下千味之港。")
	assert_eq(scene.get_node("MapRoot").find_children("RedCircle*","Line2D",true,false).size(),3)
	scene.sample_segment("arrival",12);assert_lt(scene.hero_position.x,540.0)
	scene.sample_segment("arrival",13);assert_gt(scene.hero_position.x,560.0);assert_eq(scene.hero_pose,3)
	scene.sample_segment("hungry",6);assert_eq(scene.hero_pose,7);assert_false(scene.bus_visible)
	scene.sample_segment("messenger",10);assert_true(scene.aling_visible);assert_eq(scene.aling_pose,4);assert_eq(scene.hero_pose,7)
	scene.sample_segment("arrival",0);assert_false(scene.aling_visible);assert_true(scene.bus_visible);assert_eq(scene.hero_pose,0);assert_eq(scene.detail_mode,0)

func test_new_slot_shows_film_first_then_harbor_once_and_load_remains_cottage() -> void:
	var app:=load("res://src/app/main.tscn").instantiate() as TDApplication
	app.settings_path="res://artifacts/arrival-coast/tests/%d/settings.json"%Time.get_ticks_usec()
	add_child_autofree(app)
	var shell:=app.game_shell;shell.automatic_time=false
	assert_true(shell.create_game("slot-01").ok)
	var view:=shell.guide.dialogue;view.set_process(false)
	assert_eq(view.talk.cg_id,"arrival");assert_false(shell.town.visible);assert_false(shell._hud_layer.visible)
	assert_false(shell.town._player.controls_enabled);assert_eq(shell.town._player_cell(),TDHarbor.ARRIVAL)
	var minute:=shell.profile.characters.clock.minute
	var ended: Array=[];view.closed.connect(func(_a:String,_b:Array)->void:ended.append(1))
	for i: int in 40:
		if view.talk==null: break
		if view.awaiting_name(): view._hero_input.text="海风";view._confirm_hero_name()
		elif view.talk.display_kind=="cg": view._process(view.talk.cg_duration)
		else: view.talk.click();view._refresh();view._emit_if_finished()
	assert_eq(ended.size(),1);assert_false(shell.guide.presenting());assert_true(shell.town.visible)
	assert_true(shell.town._player.controls_enabled);assert_eq(shell.profile.story.beat,"follow")
	assert_eq(shell.profile.story.hero_name,"海风");assert_eq(shell.profile.characters.clock.minute,minute)
	assert_eq(shell.town._player_cell(),TDHarbor.ARRIVAL)
	view._process(100);assert_eq(ended.size(),1)
	assert_true(shell.save_game().ok);shell.go_title();assert_true(shell.load_game("slot-01").ok)
	assert_eq(shell.location,"cottage");assert_false(shell.guide.presenting());assert_eq(shell.profile.story.hero_name,"海风")
	shell.go_title()
	await get_tree().process_frame;await get_tree().process_frame

func test_intro_pause_focus_skip_and_offscreen_call_do_not_leak_world_or_sound() -> void:
	var view:=TDDialogueView.new();add_child_autofree(view)
	view.present(TDOpeningScript.conversation("intro","玩家",80));view.set_process(false)
	view._process(2);view.toggle_presentation_pause();view._process(20)
	assert_eq(view.talk.cg_elapsed,2.0);assert_true(view._cg._paused)
	view.toggle_presentation_pause();view._process(12)
	assert_eq(view.talk.display_kind,"line");assert_true(view._cg.visible);assert_eq(view._cg.arrival_stage.hero_pose,3)
	assert_false(view.get_node("Portrait").visible);assert_false(view.get_node("RightPortrait").visible)
	view._notification(NOTIFICATION_APPLICATION_FOCUS_OUT);var shown:=view.talk.shown;view._process(9);assert_eq(view.talk.shown,shown)
	view.toggle_presentation_pause();view.talk.click();view.talk.click();view._refresh()
	assert_eq(view.talk.cg_id,"hungry")
	view._skip_clip.pressed.emit();assert_eq(view.talk.display_kind,"line");assert_false(view._cg._sound.playing)
	view.talk.click();view.talk.click();view._refresh();assert_eq(view.talk.display_kind,"offscreen")
	assert_false(view._cg.arrival_stage.aling_visible);assert_false(view.get_node("RightPortrait").visible)
	view.finish_now();assert_false(view.visible);assert_false(view._cg._sound.playing)

func test_seacoast_keeps_property_and_routes_but_pier_is_public() -> void:
	var profile:=TDGameProfile.new();var map:=profile.world.town_map
	for raw: Dictionary in TDPlannedTown.definition().plots:
		var matches:=map.plots.filter(func(p:Dictionary)->bool:return p.id==raw.id)
		assert_eq(matches.size(),1)
		assert_eq([matches[0].x,matches[0].y,matches[0].w,matches[0].h],raw.rect.map(func(v:Variant)->int:return int(v)))
	assert_eq(map.terrain_at(Vector2i(71,30)).terrain_type,"water")
	assert_false(map.is_walkable(71,30));assert_false(map.can_place(71,30,1,1))
	assert_true(map.is_walkable(72,34));assert_false(map.can_place(72,34,1,1))
	var route:=TDQuestPath.find(Vector2i(20,34),TDHarbor.ARRIVAL,Rect2i(0,0,73,73),func(p:Vector2i)->bool:return map.is_road(p.x,p.y))
	assert_gt(route.size(),30);assert_eq(route[-1],TDHarbor.ARRIVAL)
	profile.close()

func test_story_stops_and_escort_do_not_stack_and_reach_is_nearby() -> void:
	var profile:=TDGameProfile.new()
	var town:=TDTownWorld.new();town.player_mode=true;town.session=profile.world;town.characters=profile.characters;town.story=profile.story
	add_child_autofree(town);town.set_process(false)
	for beat: String in ["arrive","soup","bowl","awaken","cook","verdict","founded"]:
		profile.story.beat=beat;town.sync_characters(0)
		var positions:=town._story_positions()
		assert_gte(Vector2(positions[0].cell).distance_to(Vector2(positions[1].cell)),2.0,beat)
	for leg: String in ["follow","return"]:
		profile.story.beat=leg;town._tick_escort(0)
		assert_gte(town._escort.distance_to(town._chen_cell()),2.0)
	profile.story.beat="soup";town.sync_characters(0)
	var chen:=town._origin()+(Vector2(town._chen_cell())+Vector2(.5,.5))*town.CELL
	for facing: Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
		town._player.position=chen+Vector2(0,40);town._player.face(facing);assert_eq(town._story_faced(),"chen")
	town._player.position=chen+Vector2(0,42);assert_ne(town._story_faced(),"chen")
	var harbor:=TDHarbor.facility(profile.world.town_map);var rect:=TDInteractionRange.plot_bounds(harbor,town.CELL,town._origin())
	town._player.position=Vector2(rect.get_center().x,rect.end.y+30);assert_eq(town.facing_plot().get("id"),TDHarbor.ID)
	town._player.position=Vector2(rect.get_center().x,rect.end.y+33);assert_ne(town.facing_plot().get("id"),TDHarbor.ID)
	profile.close()
