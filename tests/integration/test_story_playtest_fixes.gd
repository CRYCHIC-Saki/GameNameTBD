extends GutTest
const DRIVER = preload("res://tools/test_support/kitchen_input.gd")
var app: TDApplication
var shell: TDGameShell
var driver: RefCounted

func before_each() -> void:
	app=load("res://src/app/main.tscn").instantiate()
	app.settings_path="res://artifacts/story-fixes/tests/%d/settings.json"%Time.get_ticks_usec()
	autofree(app);get_tree().root.add_child(app)
	shell=app.game_shell;shell.automatic_time=false
	assert_true(shell.create_game("slot-01","试做食堂").ok);shell.guide.dialogue.finish_now()
	driver=DRIVER.new();driver.viewport=get_tree().root;driver.kitchen=shell.kitchen_view.kitchen
	await get_tree().process_frame

func after_each() -> void:
	get_tree().paused=false;shell.go_title()
	await get_tree().process_frame;await get_tree().process_frame

func grant() -> void:
	shell.profile.story.beat="awaken"
	shell._apply_story(shell.profile.story.complete_scene("awaken"))
	# This legacy cooking suite isolates actual device timelines; first-time tutorials
	# are independently covered in test_story_expansion.
	shell.profile.story.tutorials.assign(["M1","M2","M3","M4","M5","M6","M7"])

func test_unnamed_hero_and_first_person_name_prompt() -> void:
	shell.guide.present("intro")
	var view:=shell.guide.dialogue
	var talk:=view.talk
	for n: int in 30:
		if talk.action=="enter_name": break
		if talk.display_kind=="cg": talk.skip_cg()
		else:
			if talk.portrait_id=="hero": assert_eq(talk.speaker_name,"？？？")
			talk.shown=talk.body.length();talk.click()
	view._refresh()
	assert_true(view.awaiting_name())
	assert_eq(view._body.text,"我的名字是……")
	view._hero_input.text="小满";view._confirm_hero_name()
	assert_eq(talk.speaker_name,"小满")
	assert_eq(shell.profile.story.hero_name,"小满")

func test_chen_is_at_shop_front_and_door_opens_story() -> void:
	var town:=shell.town;shell.profile.story.beat="soup"
	var shop:=town._plot_of_kind("market")
	assert_eq(town._chen_cell().y,int(shop.y+shop.h))
	town._player.position=town._origin()+Vector2(shop.x+shop.w*.5,shop.y+shop.h)*town.CELL+Vector2(0,20)
	town._interact()
	assert_true(shell.guide.presenting(),"E at Chen's actual front door starts soup story")
	if shell.guide.presenting(): assert_eq(shell.guide.dialogue.talk.context.get("scene"),"soup")

func test_restaurant_actor_scale_keeps_feet_anchored() -> void:
	shell.travel("restaurant")
	var room:=shell.restaurant;var rect:=room._iso.chef_rect(room.player_position())
	assert_eq(rect.size.y,96.0)
	var grid:=room.player_position()/float(room.layout.cell_px)
	assert_almost_eq(rect.end.y,TDRestaurantIsoView.project(grid.x,grid.y).y,.001)

func test_first_escort_passes_gate_centre_before_heading_to_chen() -> void:
	var town:=shell.town;shell.profile.story.beat="follow"
	town._tick_escort(0)
	var centre_crossings: Dictionary={}
	for tick: int in 1600:
		town._player.position=town.escort_position()+Vector2(48,0)
		town._tick_escort(.1)
		var cell: Vector2i=town._escort
		if cell.y in [32,31,30,29] and cell.x>=62 and not centre_crossings.has(cell.y):
			centre_crossings[cell.y]=cell.x
		if shell.profile.story.beat!="follow": break
	assert_eq(shell.profile.story.beat,"soup")
	for y: int in [32,31,30,29]: assert_eq(centre_crossings.get(y,-1),64,"Guide walks through the arch, not a pillar")
	assert_gte(town._chen_cell().distance_to(town._aling_market_cell()),2.0)

func test_practice_retries_keep_real_stock_ledger_and_stop_after_tutorial() -> void:
	grant();shell.travel("kitchen")
	var view:=shell.kitchen_view;var shop:=view.shop
	var cash: int=shop.snapshot().money_cents
	for attempt: int in 4:
		for id: String in ["tomato","egg"]:
			assert_true(view.pick_ingredient(id).ok,"Can retry after throwing away tutorial ingredients")
			view._trash()
	var records: Array=shop.snapshot().ledger.filter(func(e:Dictionary)->bool:return e.extra.get("source")=="opening_practice")
	assert_gt(records.size(),0)
	assert_eq(shop.snapshot().money_cents,cash)
	for record: Dictionary in records:
		assert_eq(int(record.cents),0)
		assert_eq(int(record.extra.inventory_cost_cents),0)
	assert_true(shell.save_game().ok)
	shell.go_title();assert_true(shell.load_game("slot-01").ok)
	view=shell.kitchen_view;shop=view.shop;shell.travel("kitchen")
	var retried:=view.pick_ingredient("tomato")
	assert_true(retried.ok,"Saved cooking tutorial can retry: "+retried.code)
	view._trash();shell.profile.story.beat="founded"
	var before:=shop.snapshot()
	assert_false(view.pick_ingredient("tomato").ok)
	assert_eq(shop.snapshot(),before,"Ending tutorial stops grants immediately")

func test_recoverable_food_is_counted_and_returning_does_not_duplicate_grants() -> void:
	grant();shell.travel("kitchen")
	var view:=shell.kitchen_view;var shop:=view.shop
	assert_true(view.pick_ingredient("tomato").ok)
	assert_true(view.return_ingredient().ok)
	var ledger: Array=shop.snapshot().ledger
	view._show_pantry();await get_tree().process_frame
	assert_false(shell.guide._trail.visible,"Tracking must not draw over the fridge controls")
	view._close_popup()
	assert_eq(shop.snapshot().ledger,ledger)
	assert_eq(shop.available("tomato"),0)
	assert_true(view.pick_stored(shop.snapshot().cold_foods[0].id).ok)
	driver.station("kitchen.board");assert_true(view.choose_cut("chunk").ok)
	driver.play(12);driver.station("kitchen.board")
	assert_true(view.return_ingredient().ok)
	var stored: Dictionary=shop.snapshot().cold_foods[0]
	assert_gt(stored.cuts.size(),0)
	view._show_pantry();view._close_popup()
	assert_eq(shop.available("tomato"),0,"Cut tomato is usable; do not duplicate it as raw stock")
	assert_true(view.pick_stored(stored.id).ok)
	assert_eq(view.kitchen.handling.hand.snapshot().to_dict().ingredients.values()[0].shape,"chunk")
	driver.station("kitchen.stove.left")
	var before:=shop.snapshot()
	view._show_pantry();view._close_popup()
	assert_eq(shop.snapshot(),before,"Cold pot ingredients count too")
	assert_eq(shop.replenish_practice_materials().code,"PRACTICE_STOCK_READY")

func test_tutorial_rejects_missing_ingredient_and_steamer_before_heating() -> void:
	grant();shell.travel("kitchen")
	var view:=shell.kitchen_view;var pot:=view.kitchen.lanes[0]
	assert_true(view.pick_ingredient("tomato").ok);driver.station("kitchen.stove.left")
	var before:=pot.snapshot()
	driver.station("kitchen.stove.left",KEY_F)
	assert_eq(view.last_result.code,"TRIAL_MISSING_MATERIAL")
	assert_string_contains(view.last_result.message,"鸡蛋")
	assert_eq(pot.snapshot(),before)
	assert_true(view.pick_ingredient("egg").ok);driver.station("kitchen.stove.left")
	assert_eq(shell.guide.check_trial_cooking(pot.snapshot(),"steam").code,"TRIAL_WRONG_METHOD")
	assert_true(shell.guide.check_trial_cooking(pot.snapshot(),"stir").ok)
	assert_true(pot.session.is_cold())

func test_old_failed_plate_gets_retry_explanation_without_progress_or_payment() -> void:
	grant();shell.travel("kitchen")
	var view:=shell.kitchen_view;var kitchen:=view.kitchen
	assert_true(view.pick_ingredient("tomato").ok);driver.station("kitchen.stove.left")
	# Recreate an old save/session mistake through the same real unknown-recipe lane.
	var lane:=kitchen.lanes[0]
	assert_true(view._recognize(lane,"stir",true).ok)
	assert_eq(lane.base_recipe_id,"kitchen.unknown_stir")
	for active: TDCookingLane in kitchen.lanes+[kitchen.prep]: active.beat_offset_sec=0
	view._begin_manual(lane,"kitchen.stove.left");driver.play(70)
	assert_eq(lane.snapshot().state,"plated")
	assert_true(lane.snapshot().failed_dish)
	driver.station("kitchen.stove.left")
	assert_eq(shell.guide.objective().target,"kitchen.trash")
	var issue:=shell.guide.trial_plate_problem(lane.snapshot())
	assert_string_contains(issue.message,"缺少番茄或鸡蛋")
	assert_string_contains(issue.message,"垃圾桶")
	var before:=shell.profile.shop.snapshot()
	driver.station("kitchen.serve")
	assert_eq(view.last_result.code,"WRONG_TRIAL_DISH")
	assert_eq(kitchen.handling.hand_kind,"dish")
	assert_eq(shell.profile.story.beat,"cook");assert_eq(shell.profile.shop.snapshot(),before)
	driver.station("kitchen.trash")
	assert_eq(kitchen.handling.hand_kind,"")
	assert_true(view.pick_ingredient("tomato").ok,"Failed tutorial dish can be cleared and retried")
