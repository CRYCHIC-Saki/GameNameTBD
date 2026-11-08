extends GutTest
const DRIVER = preload("res://tools/test_support/kitchen_input.gd")
var app: TDApplication
var shell: TDGameShell
var driver: RefCounted

func before_each() -> void:
	app=load("res://src/app/main.tscn").instantiate()
	app.settings_path="res://artifacts/story-tests/%d/settings.json"%Time.get_ticks_usec()
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

func test_story_pack_contains_usable_portions_and_is_idempotent() -> void:
	var before:=shell.profile.shop.snapshot()
	grant()
	var after:=shell.profile.shop.snapshot()
	assert_eq(int(after.inventory.tomato)-int(before.inventory.tomato),1000)
	assert_eq(int(after.inventory.egg)-int(before.inventory.egg),1000)
	assert_gt(int(after.inventory.oil),int(before.inventory.oil))
	assert_gt(int(after.inventory.starch),int(before.inventory.starch))
	assert_eq(after.money_cents,before.money_cents)
	shell._story_supplies();assert_eq(shell.profile.shop.snapshot(),after)

func test_prepare_ingredients_are_usable_without_opening_shop() -> void:
	grant();shell.travel("kitchen")
	var picked:=shell.kitchen_view.pick_ingredient("tomato")
	assert_true(picked.ok,picked.code)
	assert_eq(shell.profile.shop.snapshot().phase,"PREPARE")
	assert_true(shell.profile.shop.active_orders().is_empty())
	assert_eq(shell.save_game().code,"KITCHEN_BUSY")
	assert_eq(shell.profile._research_candidate(shell.profile.research.snapshot()).code,"BUFFERED_UNTIL_KITCHEN_CLEAR")
	assert_true(shell.kitchen_view.return_ingredient().ok)
	assert_true(shell.save_game().ok)
	var cold: Array=shell.profile.shop.snapshot().cold_foods
	assert_eq(cold.size(),1)
	shell.go_title();assert_true(shell.load_game("slot-01").ok)
	assert_true(TDLevelProgression.same_value(shell.profile.shop.snapshot().cold_foods,cold))
	assert_true(shell.kitchen_view.pick_stored(cold[0].id).ok)

func test_old_micro_grant_is_topped_up_once_across_save_reload() -> void:
	var shop:=shell.profile.shop
	var original:={"tomato":1,"egg":1,"salt":1,"sugar":1}
	assert_true(shop.receive_supply(original,"story-chen-pack:%s"%shop.snapshot().run_id,0).ok)
	shell.profile.story.beat="cook";shell.profile.story.supplied=true
	shell._story_supplies()
	assert_eq(int(shop.snapshot().inventory.tomato),1000)
	assert_eq(int(shop.snapshot().inventory.egg),1000)
	var inventory: Dictionary=shop.snapshot().inventory
	assert_true(shell.save_game().ok)
	shell.go_title();assert_true(shell.load_game("slot-01").ok)
	shell._story_supplies();shell._story_supplies()
	assert_true(TDLevelProgression.same_value(shell.profile.shop.snapshot().inventory,inventory))
	assert_eq(shell.profile.shop.snapshot().ledger.filter(func(e:Dictionary)->bool:return str(e.reference).begins_with("story-chen-pack-v2:")).size(),1)

func test_real_closed_kitchen_inputs_complete_and_feed_opening_story() -> void:
	grant();shell.travel("kitchen")
	var view:=shell.kitchen_view;var kitchen:=view.kitchen
	var money:=int(view.shop.snapshot().money_cents)
	var sugar_before:=view.shop.available("sugar")
	for lane: TDCookingLane in kitchen.lanes+[kitchen.prep]: lane.beat_offset_sec=0
	# First attempt is wasted; the actual second attempt must still be playable.
	for id: String in ["tomato","egg"]:
		assert_true(view.pick_ingredient(id).ok);view._trash()
	assert_true(view.pick_ingredient("tomato").ok)
	driver.station("kitchen.board");assert_true(view.choose_cut("chunk").ok)
	driver.play(12);driver.station("kitchen.board");driver.station("kitchen.stove.left")
	assert_true(view.pick_ingredient("egg").ok)
	driver.station("kitchen.stove.left");driver.station("kitchen.stove.left",KEY_F)
	assert_true(kitchen.stage.visible)
	driver.tap(KEY_ESCAPE);assert_true(get_tree().paused)
	var before:=kitchen.lanes[0].snapshot()
	kitchen.advance(5);assert_eq(kitchen.lanes[0].snapshot(),before)
	driver.tap(KEY_ESCAPE);assert_false(get_tree().paused);driver.play(70)
	var dish:=kitchen.lanes[0].snapshot()
	assert_eq(dish.state,"plated")
	assert_true(dish.missing_required.is_empty())
	assert_eq(int(view.shop.snapshot().money_cents),money)
	assert_eq(float(view.shop.snapshot().elapsed_sec),0.0)
	assert_true(view.shop.active_orders().is_empty())
	assert_gt(float(shell.profile.commerce.state.day_stats.cooking_seconds),0.0)
	assert_lt(view.shop.available("sugar"),sugar_before,"M6 really consumed held seasoning")
	shell.travel("restaurant");assert_eq(shell.profile.story.score,-1,"Leaving is not delivery")
	shell.travel("kitchen");driver.station("kitchen.stove.left");driver.station("kitchen.serve")
	assert_gte(shell.profile.story.score,0);assert_eq(shell.profile.story.beat,"verdict")
	assert_true(shell.guide.practice_supplies().is_empty())
	assert_eq(view.kitchen.handling.hand_kind,"")
	assert_eq(view.shop.replenish_practice_materials().code,"NO_PRACTICE_SUPPLY")
	shell._apply_story(shell.profile.story.complete_scene("verdict_good" if shell.profile.story.good else "verdict_bad"))
	assert_eq(shell.profile.story.beat,"founded")
	assert_true(kitchen.lanes[0].snapshot().ingredients.is_empty(),"阿铃吃掉这盘试做菜")
	assert_true(shell.save_game().ok)
	var paid:=view.shop.snapshot()
	shell._apply_story({"pay":true});assert_eq(view.shop.snapshot(),paid)

func test_opening_and_closing_keep_prepared_food_and_settled_kitchen_operates() -> void:
	grant();shell.travel("kitchen")
	var view:=shell.kitchen_view;var kitchen:=view.kitchen
	assert_true(view.pick_ingredient("tomato").ok)
	driver.station("kitchen.stove.left")
	var pot:=kitchen.lanes[0].session
	assert_true(shell.start_day().ok)
	assert_same(view.kitchen,kitchen);assert_same(kitchen.lanes[0].session,pot)
	assert_eq(pot.snapshot().to_dict().ingredients.size(),1)
	assert_false(view.shop._kitchen.is_empty(),"开门仍统计预先放入锅里的材料")
	assert_eq(kitchen.time_advanced.get_connections().size(),1)
	view.shop.close_early();kitchen.advance(.1)
	assert_eq(view.shop.snapshot().phase,"SETTLED")
	assert_eq(pot.snapshot().to_dict().ingredients.size(),1)
	shell.travel("kitchen")
	assert_true(view.pick_ingredient("egg").ok)
	driver.station("kitchen.stove.left");driver.station("kitchen.stove.left",KEY_F)
	assert_true(kitchen.stage.visible)
	driver.play(70)
	assert_eq(kitchen.lanes[0].snapshot().state,"plated")
	assert_gt(float(shell.profile.commerce.state.get("after_hours_seconds",0)),0.0)
	assert_eq(shell.profile.next_day().code,"KITCHEN_BUSY")

func test_after_hours_costs_carry_once_and_old_books_stay_frozen() -> void:
	var profile:=shell.profile;var shop:=profile.shop;var economy:=profile.commerce
	assert_true(profile.buy({"tomato":2000}).ok)
	var cost:=int(economy.state.cost_stock.tomato.value_cents)
	assert_true(shop.open_day().ok);shop.close_early()
	var book:Dictionary=economy.state.books.back().duplicate(true)
	var token:=shop.day_namespace()+"after-hours-test"
	assert_true(shop.consume_materials(token,{"tomato":1000}).ok)
	assert_eq(shop.consume_materials(token,{"tomato":1000}).code,"DUPLICATE")
	economy.cooking_time(20)
	assert_eq(int(economy.state.after_hours_cost_cents),roundi(cost*.5))
	assert_eq(economy.state.books.back(),book)
	assert_true(shell.save_game().ok)
	shell.go_title();assert_true(shell.load_game("slot-01").ok)
	profile=shell.profile;shop=profile.shop;economy=profile.commerce
	assert_true(profile.next_day().ok)
	assert_eq(int(economy.state.cost_consumed),roundi(cost*.5))
	assert_eq(float(economy.state.day_stats.cooking_seconds),20.0)
	assert_eq(int(economy.state.after_hours_cost_cents),0)
	assert_true(shop.open_day().ok);shop.close_early()
	assert_eq(int(economy.state.books.back().consumed_cost_cents),roundi(cost*.5))
	assert_true(profile.next_day().ok)
	assert_eq(int(economy.state.cost_consumed),0)
	var old:=economy.snapshot();old.erase("after_hours_cost_cents");old.erase("after_hours_seconds")
	assert_true(economy.validate_save(old).ok)
	old.after_hours_seconds=-1;assert_false(economy.validate_save(old).ok)

func test_selected_art_uses_distinct_read_only_directional_resources() -> void:
	for who: String in ["aling","chen"]:
		var textures: Array=[]
		for facing: Vector2i in [Vector2i.DOWN,Vector2i.UP,Vector2i.LEFT,Vector2i.RIGHT]:
			var sprite:=TDStoryArt.sprite(who,facing) as AtlasTexture
			assert_not_null(sprite);assert_false(sprite in textures);textures.append(sprite)
			assert_same(sprite,TDStoryArt.sprite(who,facing))
			assert_true(sprite.atlas.resource_path.contains("archive/2026-10-29"))
			assert_gte(sprite.region.size.y,578.0)
		assert_not_null(TDStoryArt.portrait(who))
	assert_null(TDStoryArt.portrait("luo"),"No invented portrait assignment for a missing asset")
