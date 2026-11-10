extends GutTest
## 3719c13 crew/market rules composed with the local fixed roster and store lifecycle.
var profile: TDGameProfile
var room: TDRestaurantWorld
var view: TDShopView

func after_each() -> void:
	if is_instance_valid(view): view.close();view.queue_free()
	if is_instance_valid(room): room.close();room.queue_free()
	if profile!=null: profile.close()
	get_tree().paused=false
	await wait_process_frames(2)

func test_fixed_employee_two_real_jobs_reset_station_and_release_callbacks() -> void:
	profile=TDGameProfile.new();profile.slot_id="slot-01";assert_true(profile.error.ok)
	assert_true(profile.shop.world_adjustment(500000,"fixture-funds","test funding").ok)
	var offer: Dictionary=profile.employees.market_rows("chengdu","cook")[0]
	assert_true(profile.employees.sign_employee(offer.id,"hire",offer.offer_key).ok)
	assert_true(profile.employees.assign(offer.id,"player_diner").ok)
	# Isolate arrivals with the existing deterministic standalone clock, while using
	# the actual fixed employee, Shop, kitchen, stock consumption and delivery path.
	profile.shop.commerce=null
	var shop:=profile.shop
	room=TDRestaurantWorld.new();room.layout=profile.layout;room.player_mode=true;room.floor_service=true;room.business=shop
	add_child(room);room.bind_dining_clock()
	view=TDShopView.new();view.service=profile.service;view.shop=shop;view.embedded=true
	view.save_path="res://artifacts/pull-current/staff-%d.json"%Time.get_ticks_usec()
	add_child(view);view.kitchen.auto_advance=false;view.staff_away=true
	var cart: Dictionary=shop.offer("service.tomato_egg").stock.duplicate(true)
	for id: String in cart: cart[id]=int(cart[id])*5
	assert_true(shop.buy(cart,"stock").ok)
	for id: String in shop.snapshot().menu: assert_true(shop.set_menu(id,id=="service.tomato_egg",1200).ok)
	assert_true(shop.open_day().ok)
	var world:=view.kitchen.world
	var jobs: Dictionary={};var steps: Dictionary={};var dishes: Array=[]
	for lane: TDCookingLane in view.kitchen.lanes: lane.dish_delivered.connect(func(dish:Dictionary)->void:dishes.append(dish.duplicate(true)))
	for n: int in 2400:
		view.kitchen.advance(.1)
		var job:=shop.cook_job_id(offer.id);var step:=shop.cook_step(offer.id)
		if not step.is_empty(): steps[step]=true
		if not job.is_empty() and not jobs.has(job):
			if not jobs.is_empty():
				# Rendering need not observe an idle frame between adjacent jobs.
				world._staff_nodes[0].set_meta("cook_place","出餐")
			world._staff_delta=.1;world._sync_staff()
			assert_eq(str(world._staff_nodes[0].get_meta("cook_job_id")),str(offer.id)+":"+job)
			assert_ne(str(world._staff_nodes[0].get_meta("cook_place","")),"出餐","new actual session resets the previous serving station")
			jobs[job]=true
		else:
			world._staff_delta=.1;world._sync_staff()
		if dishes.size()>=2: break
	assert_gte(jobs.size(),2);assert_gte(dishes.size(),2)
	assert_true(steps.has("切菜"));assert_true(steps.has("翻炒"));assert_true(steps.has("调味"))
	for dish: Dictionary in dishes:
		assert_gt(dish.steps.size(),0);assert_gt(dish.consumed_ingredients.size(),0)
	assert_eq(shop.mastery("service.tomato_egg").points,0.0);assert_true(shop._crew_jobs.is_empty())
	view.close()
	assert_false(shop.crew_status_source.is_valid());assert_false(shop.cook_step_source.is_valid());assert_false(shop.cook_job_source.is_valid())
	assert_eq(shop.cook_job_id(offer.id),"");assert_eq(shop.cook_step(offer.id),"")

func test_market_open_stock_does_not_unlock_supplier_or_recipe() -> void:
	profile=TDGameProfile.new();profile.slot_id="slot-01";assert_true(profile.error.ok)
	assert_false(profile.shop.purchasable("chicken"));assert_true(profile.shop.market_sells("chicken"))
	var research:=profile.research.snapshot()
	assert_true(profile.shop.buy({"chicken":1000},"market-chicken").ok)
	assert_eq(profile.research.snapshot(),research)
	assert_false(profile.shop.purchasable("chicken"))
	var catalogue: Array=profile.suppliers.catalogue("chengdu")
	assert_true(catalogue.filter(func(row:Dictionary)->bool:return row.id=="chicken").is_empty())

func test_station_monotonic_within_job_and_resets_without_teleport_between_jobs() -> void:
	var world:=TDKitchenWorld.new();var actor:=Node2D.new();actor.position=Vector2(700,430)
	assert_eq(world._held_place(actor,"热锅",true,"first"),"做菜")
	assert_eq(world._held_place(actor,"调味",true,"first"),"做菜")
	assert_eq(world._held_place(actor,"出餐",true,"first"),"出餐")
	assert_eq(world._held_place(actor,"切菜",true,"second"),"切菜")
	assert_eq(actor.position,Vector2(700,430))
	assert_eq(world._held_place(actor,"",false,"second"),"")
	actor.free();world.free()
