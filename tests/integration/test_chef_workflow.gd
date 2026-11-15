extends GutTest
var view: TDShopView
var shop: TDShopSession
var events: Array=[]

func before_each() -> void:
	events=[]
	var catalog:=TDServiceCatalog.new();assert_true(catalog.load_file().ok)
	shop=TDShopSession.new(catalog,"chef-flow",59,["service.tomato_egg","service.pepper_pork","service.qiguoji"])
	shop.table_service_enabled=true;shop.crew=TDRestaurantCrew.new()
	assert_true(shop.crew.hire("cook-he").ok)
	view=TDShopView.new();view.shop=shop;view.service=catalog;view.embedded=true
	view.save_path="res://artifacts/chef-workflow-20261114/test-%d.json"%Time.get_ticks_usec()
	assert_eq(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(view.save_path.get_base_dir())),OK,"Fresh checkout creates isolated evidence directory")
	add_child(view);view.kitchen.auto_advance=false
	for lane: TDCookingLane in view.kitchen.lanes+[view.kitchen.prep]: lane.beat_offset_sec=0.0
	view.staff.action_completed.connect(func(event:Dictionary)->void:events.append(event.duplicate(true)))
	# Rendering is sampled explicitly; advancing the real kitchen is the only simulation clock.
	view.kitchen.world.set_process(false)
	await wait_process_frames(1)

func after_each() -> void:
	get_tree().paused=false
	view.close();view.queue_free();await wait_process_frames(2)

func open_recipe(id: String="service.tomato_egg", portions: int=1) -> void:
	var cart: Dictionary=shop.offer(id).stock
	for key: String in cart: cart[key]=int(cart[key])*portions
	assert_true(shop.buy(cart,"stock-"+id).ok)
	for key: String in shop.snapshot().menu: assert_true(shop.set_menu(key,key==id,1200).ok)
	assert_true(shop.open_day().ok);assert_true(shop.advance(1).ok)
	shop._next_arrival=350.0;view.tick_staff()

func until_action(action: String, max_seconds: float=140) -> bool:
	for i: int in ceili(max_seconds/.5):
		if events.any(func(e:Dictionary)->bool:return e.action==action): return true
		view.kitchen.advance(.5)
	return false

func job() -> Dictionary:
	return view.staff.job_for("cook-he")

func test_tomato_egg_physical_sequence_real_cut_and_once_only_food() -> void:
	open_recipe()
	var initial:=shop.snapshot()
	view.kitchen.advance(1)
	assert_eq(shop.snapshot().inventory,initial.inventory,"Walking to fridge must not consume food")
	assert_true(until_action("cut_started"))
	assert_eq(shop.available("egg"),int(initial.inventory.egg),"Egg is still in fridge during tomato preparation")
	assert_true(view.kitchen.lanes[0].snapshot().ingredients.is_empty(),"Tomato is on the board, not already in the pot")
	var tomato: Dictionary=(job().handling as TDKitchenHandling).board.snapshot().to_dict().ingredients.values()[0]
	assert_true(until_action("ingredient_deposited"))
	var deposited: Dictionary=view.kitchen.lanes[0].snapshot().ingredients[tomato.id]
	assert_eq(deposited.expires_on,tomato.expires_on)
	assert_true(deposited.history.any(func(h:Dictionary)->bool:return h.operation=="cut"))
	assert_eq(shop.available("egg"),int(initial.inventory.egg))
	assert_true(until_action("dish_picked"));assert_true(shop.table_service.empty(),"Holding finished food is not pass delivery")
	assert_true(until_action("dish_deposited"))
	assert_eq(events.map(func(e:Dictionary)->String:return e.action+":"+e.ingredient),[
		"picked:tomato","cut_started:tomato","cut_finished:tomato","ingredient_deposited:tomato",
		"picked:egg","ingredient_deposited:egg","cook_started:","dish_picked:","dish_deposited:"])
	assert_eq(shop.available("tomato"),int(initial.inventory.tomato)-1000)
	assert_eq(shop.available("egg"),int(initial.inventory.egg)-1000)
	assert_eq(shop.snapshot().money_cents,initial.money_cents)
	assert_eq(shop.table_service.rows().size(),1)
	var dish: Dictionary=shop.table_service.rows()[0].dish
	assert_eq(dish.production_mode,"automatic");assert_eq(shop.mastery("service.tomato_egg").points,0.0)
	assert_gt(dish.steps.size(),3)
	var before:=shop.snapshot();for i: int in 8: view.tick_staff()
	assert_eq(shop.snapshot(),before);assert_eq(shop.table_service.rows().size(),1)
	for event: Dictionary in events:
		var station: String="kitchen.fridge" if event.action=="picked" else ("kitchen.board" if event.action.begins_with("cut_") else ("kitchen.serve" if event.action=="dish_deposited" else "kitchen.stove.left"))
		assert_lt(event.position.distance_to(view.kitchen.world.staff_approach(station)),1.0)

func test_world_stations_routes_gait_and_both_pause_paths() -> void:
	open_recipe();view.kitchen.advance(.2)
	view.kitchen.world._sync_staff()
	var actor:=view.kitchen.world.get_node("Cook0") as TDKitchenStaffActor
	assert_not_null(actor)
	assert_true(actor.body.texture!=TDKitchenWorld.CHEF_SPRITE)
	assert_gte(int(view.staff.rows()[0].frame),0)
	var rows:=view.staff.rows();var clock:=view.kitchen.shared_clock.game_sec;var food:=shop.snapshot()
	view.set_paused(true);view.kitchen.advance(20);view.kitchen.world._process(20)
	assert_eq(view.staff.rows(),rows);assert_eq(view.kitchen.shared_clock.game_sec,clock);assert_eq(shop.snapshot(),food)
	view.set_paused(false);get_tree().paused=true;view.kitchen.advance(1);view.tick_staff()
	assert_eq(view.staff.rows(),rows);get_tree().paused=false
	view.hide();view.kitchen.advance(.2);assert_ne(view.staff.rows()[0].point,rows[0].point)
	var world:=view.kitchen.world
	var ids: Array=["kitchen.fridge","kitchen.board","kitchen.stove.left","kitchen.stove.right","kitchen.steamer","kitchen.serve"]
	for from_id: String in ids:
		for to_id: String in ids:
			var last:=world.staff_approach(from_id)
			for point: Vector2 in world.staff_route(last,world.staff_approach(to_id)):
				for i: int in 21: assert_true(world.staff_walkable(last.lerp(point,float(i)/20.0)))
				last=point
			assert_eq(last,world.staff_approach(to_id))

func test_player_hand_board_and_assigned_empty_pot_are_protected() -> void:
	assert_true(shop.buy(shop.offer("service.tomato_egg").stock,"player-stock").ok)
	assert_true(view.pick_ingredient("tomato").ok)
	assert_true(view.kitchen.handling.put_board().ok)
	var player_board:=view.kitchen.handling.board
	open_recipe();assert_false(job().is_empty())
	view._station_action("kitchen.stove.left","interact");assert_eq(view.last_result.code,"STAFF_BUSY")
	view.kitchen.advance(9)
	assert_eq(job().phase,"wait_board");assert_eq(view.kitchen.handling.board,player_board)
	assert_true(view.kitchen.handling.take_board().ok)
	var player_hand:=view.kitchen.handling.hand
	assert_true(until_action("cut_started"))
	view._station_action("kitchen.board","interact");assert_eq(view.last_result.code,"STAFF_BUSY")
	assert_eq(view.kitchen.handling.hand,player_hand)
	assert_eq(view.take_pot_ingredient(0,"no-such-id").code,"STAFF_BUSY")
	assert_eq(view.checkpoint_ready().code,"KITCHEN_BUSY")

func test_shortage_waits_and_restock_resumes_without_duplicate_tomato() -> void:
	open_recipe();assert_true(until_action("ingredient_deposited"))
	assert_true(shop.consume_materials(shop.day_namespace()+"player-use-egg",{"egg":shop.available("egg")}).ok)
	view.kitchen.advance(8);assert_eq(job().phase,"wait_stock")
	var count:=events.filter(func(e:Dictionary)->bool:return e.action=="picked").size()
	for i: int in 5: view.tick_staff()
	assert_eq(events.filter(func(e:Dictionary)->bool:return e.action=="picked").size(),count)
	assert_true(shop.receive_supply({"egg":1000},"restock-egg",0,true).ok)
	# Sold-out requests are rejected by the established policy; the prepared tomato remains real food.
	shop._next_arrival=float(shop.snapshot().elapsed_sec)+.1
	view.kitchen.advance(.1);shop._next_arrival=350
	assert_true(until_action("dish_deposited"))
	assert_eq(events.filter(func(e:Dictionary)->bool:return e.action=="picked" and e.ingredient=="tomato").size(),1)

func test_dismissal_and_night_release_keep_real_cold_food_and_clear_callbacks() -> void:
	open_recipe();assert_true(until_action("cut_finished"))
	var held: Dictionary=(job().handling as TDKitchenHandling).board.snapshot().to_dict().ingredients.values()[0]
	assert_true(shop.crew.dismiss("cook-he").ok);view.tick_staff()
	assert_true(view.staff.jobs.is_empty());assert_eq(view.staff.board_owner,"")
	var stored: Dictionary=shop.snapshot().cold_foods[0]
	assert_eq(stored.id,held.id);assert_eq(stored.expires_on,held.expires_on);assert_gt(stored.cuts.size(),0)
	assert_true(view.finish_night().ok)
	view.close();assert_false(shop.cook_step_source.is_valid());assert_false(view.kitchen.world.staff_source.is_valid())

func test_real_steam_recipe_uses_steamer_and_real_recipe_steps() -> void:
	open_recipe("service.qiguoji")
	assert_eq(job().pot_station,"kitchen.steamer");assert_eq(job().lane,1)
	assert_true(until_action("dish_deposited",180))
	var cooked: Array=events.filter(func(e:Dictionary)->bool:return e.action=="cook_started")
	assert_eq(cooked.size(),1)
	assert_eq(cooked[0].position,view.kitchen.world.staff_approach("kitchen.steamer"))
	assert_eq(shop.table_service.rows()[0].dish.recipe_id,"service.qiguoji")

func test_tuning_validation_and_zero_time_no_actions() -> void:
	var raw: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/service_content.json"))
	raw.staff_workflow.walk_speed_px_sec=-1
	assert_eq(TDServiceCatalog.new().load_data(raw).code,"INVALID_STAFF_WORKFLOW")
	open_recipe();var inventory: Dictionary=shop.snapshot().inventory;var rows:=view.staff.rows()
	for i: int in 20: view.tick_staff()
	assert_eq(shop.snapshot().inventory,inventory);assert_eq(view.staff.rows(),rows);assert_true(events.is_empty())

func test_two_cooks_share_one_board_without_shared_hands_or_pots() -> void:
	assert_true(shop.crew.hire("cook-zhou").ok)
	var cart: Dictionary={}
	for id: String in ["service.tomato_egg","service.pepper_pork"]:
		for ingredient: String in shop.offer(id).stock: cart[ingredient]=int(cart.get(ingredient,0))+int(shop.offer(id).stock[ingredient])*2
	assert_true(shop.buy(cart,"dual-stock").ok)
	for id: String in shop.snapshot().menu: shop.set_menu(id,id in ["service.tomato_egg","service.pepper_pork"],1200)
	assert_true(shop.open_day().ok)
	for i: int in 5: shop._arrive()
	shop._next_arrival=350;view.tick_staff()
	assert_eq(view.staff.jobs.size(),2)
	assert_ne(view.staff.jobs[0].handling,view.staff.jobs[1].handling)
	var max_cuts: int=0
	for i: int in 360:
		view.kitchen.advance(.5)
		var cutting: int=view.staff.jobs.values().filter(func(j:Dictionary)->bool:return j.phase=="cut").size()
		max_cuts=maxi(max_cuts,cutting)
		assert_lte(cutting,1)
		if shop.table_service.rows().size()>=2: break
	assert_eq(max_cuts,1);assert_gte(shop.table_service.rows().size(),2)
	assert_true(view.kitchen.handling.hand==null);assert_true(view.kitchen.handling.board==null)

func test_coarse_and_fine_clock_steps_produce_same_actions_food_and_stock() -> void:
	open_recipe()
	for i: int in 1600:
		view.kitchen.advance(.1)
		if not shop.table_service.empty(): break
	assert_false(shop.table_service.empty())
	var first_events: Array=events.duplicate(true)
	var first_stock: Dictionary=shop.snapshot().inventory
	var first_dish: Dictionary=shop.table_service.rows()[0].dish
	view.close();view.queue_free();await wait_process_frames(2)
	await before_each();open_recipe()
	for i: int in 60:
		view.kitchen.advance(3.0)
		if not shop.table_service.empty(): break
	assert_false(shop.table_service.empty())
	assert_eq(events.size(),first_events.size())
	for i: int in mini(events.size(),first_events.size()):
		assert_eq(events[i].action,first_events[i].action);assert_eq(events[i].ingredient,first_events[i].ingredient)
		assert_almost_eq(float(events[i].time),float(first_events[i].time),.00001)
	assert_eq(shop.snapshot().inventory,first_stock)
	var second: Dictionary=shop.table_service.rows()[0].dish
	assert_almost_eq(second.performance_score,first_dish.performance_score,.00001)
	var diagnostic:=FileAccess.open("res://artifacts/chef-workflow-20261114/clock-comparison.json",FileAccess.WRITE)
	assert_not_null(diagnostic,"Clock comparison evidence opens successfully")
	if diagnostic!=null:
		diagnostic.store_string(JSON.stringify({"fine":first_dish,"coarse":second},"\t"));diagnostic.close()
	# Integrating continuous temperature in different slices may differ by < 0.00001 C.
	assert_attributes_close(second.dish_attributes,first_dish.dish_attributes)

func assert_attributes_close(actual: Variant, expected: Variant) -> void:
	if actual is Dictionary:
		assert_eq(actual.keys(),expected.keys())
		for key: Variant in actual: assert_attributes_close(actual[key],expected[key])
	elif actual is Array:
		assert_eq(actual.size(),expected.size())
		for i: int in actual.size(): assert_attributes_close(actual[i],expected[i])
	elif actual is float: assert_almost_eq(actual,float(expected),.00001)
	else: assert_eq(actual,expected)

func test_night_during_cut_cancels_worker_and_reentry_starts_clean() -> void:
	open_recipe();assert_true(until_action("cut_started"))
	var old_session:=str(job().session_id)
	assert_eq(view.kitchen.staff_prep.input_action("cut",true).code,"AUTOMATIC")
	assert_true(view.finish_night().ok)
	assert_true(view.staff.jobs.is_empty());assert_false(view.kitchen.staff_prep_active)
	assert_null(view.kitchen.staff_prep.qte);assert_eq(view.staff.board_owner,"")
	assert_eq(shop.snapshot().cold_foods.size(),1)
	assert_eq(shop.available("egg"),1000)
	view._make_kitchen();view.kitchen.auto_advance=false
	assert_true(view.staff.jobs.is_empty());assert_eq(view.staff.board_owner,"")
	assert_ne(view.kitchen.lanes[0].snapshot().session_id,old_session)
	view.tick_staff();assert_eq(shop.snapshot().cold_foods.size(),1)
