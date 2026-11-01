extends GutTest

func test_source_lines_emotions_cg_and_branch_coverage() -> void:
	var data:=TDOpeningScript.data();var scenes: Dictionary=data.scenes
	assert_eq(scenes.size(),8)
	var spoken: Dictionary={};var shots: Dictionary={}
	for id: String in scenes:
		for row: Dictionary in scenes[id]:
			assert_false(row.paragraphs.is_empty())
			if row.kind=="line":
				spoken[int(row.paragraphs[0])]=true;assert_has(TDStoryArt.EMOTIONS,str(row.emotion))
			elif row.kind=="cg": shots[str(row.cg)]=true;assert_gt(float(row.duration),0.0)
	for paragraph: int in [14,16,17,19,20,21,30,32,33,34,35,42,45,46,47,49,50,51,52,53,55,61,62,63,65,67,87,88,89,91,92,95,97,99,100,101,103,104,105,106,109,110]: assert_has(spoken,paragraph)
	assert_eq(shots.size(),17)
	data.scenes.clear();assert_false(TDOpeningScript.data().scenes.is_empty(),"Config is immutable to callers")
	var talk:=TDOpeningScript.conversation("intro","小焰",100);talk.begin()
	assert_eq(talk.display_kind,"cg");assert_eq(talk.cg_id,"arrival")
	talk.click();talk.click();assert_eq(talk.cg_id,"arrival","CG has a real timed animation")
	talk.tick(talk.cg_duration);assert_eq(talk.emotion,"happy");assert_eq(talk.active_side,"left")
	assert_eq(talk.shown,0,"Movie finishes automatically but does not consume the next spoken line")

func test_movies_chain_automatically_and_input_does_not_cut_animation() -> void:
	var talk:=TDDialogue.new();talk.add_cg("sign","direction only",2);talk.add_cg("fire","",3);talk.add_line("我","hero","继续做菜")
	talk.begin();talk.pointer_down();talk.hold(100,true);talk.release()
	assert_eq(talk.cg_elapsed,0.0);assert_eq(talk.cg_id,"sign")
	talk.tick(2.5);assert_eq(talk.cg_id,"fire");assert_almost_eq(talk.cg_elapsed,.5,.0001)
	talk.pause_cg(true);talk.tick(99);assert_almost_eq(talk.cg_elapsed,.5,.0001)
	talk.pause_cg(false);talk.tick(99);assert_eq(talk.display_kind,"line");assert_eq(talk.shown,0);assert_false(talk.finished)

func test_movie_only_completion_skip_and_bad_time_are_safe() -> void:
	var talk:=TDDialogue.new();talk.add_cg("fire","",2);talk.begin()
	for bad: float in [-1.0,NAN,INF]: talk.tick(bad)
	assert_eq(talk.cg_elapsed,0.0)
	talk.tick(2);assert_true(talk.finished);assert_false(talk.cancelled)
	talk.begin();talk.pause_cg(true);talk.skip_cg();assert_true(talk.finished);assert_false(talk.cg_paused)
	talk.begin();talk.force_close();talk.tick(3);assert_true(talk.cancelled)

func test_every_script_clip_finishes_without_a_click_and_stops_at_ui() -> void:
	for rows: Array in TDOpeningScript.data().scenes.values():
		for row: Dictionary in rows:
			if row.kind!="cg": continue
			var talk:=TDDialogue.new();talk.add_cg(row.cg,row.text,row.duration);talk.add_line("提示","","界面","calm","","ui");talk.begin()
			talk.tick(row.duration-.01);assert_eq(talk.display_kind,"cg",row.cg)
			talk.tick(.02);assert_eq(talk.display_kind,"ui",row.cg);assert_eq(talk.shown,0)

func test_scenes_are_cancel_safe_idempotent_and_save_local() -> void:
	var story:=TDOpening.new();story.begin()
	assert_true(story.complete_scene("intro",false).is_empty());assert_eq(story.beat,"arrive")
	story.complete_scene("intro");assert_eq(story.beat,"follow")
	story.arrive_escort();assert_eq(story.beat,"soup")
	story.complete_scene("soup");assert_eq(story.beat,"bowl")
	assert_eq(story.complete_scene("after_taste"),{"san":-5});assert_true(story.complete_scene("after_taste").is_empty())
	assert_eq(story.beat,"return");story.arrive_escort();assert_eq(story.beat,"awaken")
	assert_eq(story.complete_scene("awaken"),{"grant":true});story.mark_supplied();assert_eq(story.beat,"cook")
	story.tracked=false;story.recipe_viewed=true;story.tutorials.append("M1")
	var other:=TDOpening.new();other.restore(story.export_state())
	assert_eq(other.export_state(),story.export_state());other.tutorials.append("M2");assert_eq(story.tutorials,["M1"])
	assert_false(story.accept_trial({"state":"plated","recipe_id":"beef","session_id":"wrong"},{"satisfaction":90}).ok)
	var dish:={"state":"plated","recipe_id":"service.tomato_egg","session_id":"trial-1"}
	assert_true(story.accept_trial(dish,{"satisfaction":45,"reasons":[{"message":"失误"}]}).ok)
	assert_false(story.good);assert_eq(story.beat,"verdict");assert_eq(story.accept_trial(dish,{"satisfaction":100}).code,"ALREADY_SERVED")
	assert_eq(story.complete_scene("verdict_bad"),{"pay":true});story.mark_paid();assert_true(story.complete_scene("verdict_bad").is_empty())
	var legacy:=TDOpening.new();legacy.restore({"beat":"cook","score":95,"good":true,"supplied":true})
	assert_eq(legacy.score,-1);assert_true(legacy.supplied)

func test_navigation_detours_solid_target_and_unreachable_regions() -> void:
	var obstacles: Dictionary={Vector2i(2,0):true,Vector2i(2,1):true,Vector2i(2,2):true,Vector2i(4,1):true}
	var walk:=func(p:Vector2i)->bool:return not obstacles.has(p)
	var route:=TDQuestPath.find(Vector2i(0,1),Vector2i(4,1),Rect2i(0,0,5,5),walk)
	assert_gt(route.size(),5)
	for i: int in route.size():
		assert_false(obstacles.has(route[i]))
		if i>0: assert_eq(absi(route[i].x-route[i-1].x)+absi(route[i].y-route[i-1].y),1)
	assert_lte(route[-1].distance_to(Vector2i(4,1)),1.0)
	assert_true(TDQuestPath.find(Vector2i(2,0),Vector2i(4,1),Rect2i(0,0,5,5),walk).is_empty())

func test_emotions_keep_original_happy_art_and_unique_other_poses() -> void:
	for who: String in ["hero","aling","chen"]:
		for emotion: String in TDStoryArt.EMOTIONS:
			var art:=TDStoryArt.portrait(who,emotion);assert_not_null(art);assert_gt(art.get_width(),0)
	assert_same(TDStoryArt.portrait("aling","happy"),TDStoryArt.portrait("aling"))
	assert_same(TDStoryArt.portrait("chen","happy"),TDStoryArt.portrait("chen"))
	assert_ne(TDStoryArt.portrait("hero","sad"),TDStoryArt.portrait("hero","angry"))
	assert_same(TDStoryArt.portrait("hero","happy","握住锅柄"),TDStoryArt.action_pose(3))

func test_bad_story_state_is_rejected_before_restore() -> void:
	for raw: Variant in [null,[],{"script_version":3},{"tutorials":["M1","M1"]},{"tutorials":[1]},{"tracked":"false"},{"assessment":{"satisfaction":-1}},{"assessment":{"satisfaction":101}},{"assessment":{"satisfaction":"90"}},{"assessment":{"satisfaction":NAN}},{"assessment":{"satisfaction":90,"reasons":[1]}}]:
		assert_false(TDOpening.validate_state(raw).ok,str(raw))
	assert_true(TDOpening.validate_state({"beat":"founded","paid":true}).ok,"Legacy progress remains readable")
	var story:=TDOpening.new();assert_true(story.complete_scene("missing").is_empty())
	story.begin();story.hero_name="赤焰";story.clear();assert_eq(story.hero_name,"")

func test_port_contract_requires_passenger_unlock_and_destination_anchor() -> void:
	assert_eq(TDHarbor.departure_request("unknown","chengdu",[],{}).code,"INVALID_DESTINATION")
	assert_eq(TDHarbor.departure_request("chengdu","chengdu",[],{}).code,"INVALID_DESTINATION")
	assert_eq(TDHarbor.departure_request("paris","chengdu",[],{}).code,"PASSENGER_ROUTE_LOCKED")
	assert_eq(TDHarbor.departure_request("paris","chengdu",["paris"],{}).code,"DESTINATION_NOT_READY")
	assert_eq(TDHarbor.departure_request("paris","chengdu",["paris"],{"paris":"port.arrival"},true).code,"SHOP_OPEN")
	var anchors:={"paris":"port.arrival"};var open:=["paris"]
	var ready:=TDHarbor.departure_request("paris","chengdu",open,anchors)
	assert_true(ready.ok);assert_eq(ready.data.schema_version,1);assert_eq(ready.data.origin_port_id,"harbor.hekou")
	assert_eq(ready.data.arrival_anchor_id,"port.arrival");assert_eq(anchors,{"paris":"port.arrival"});assert_eq(open,["paris"])
