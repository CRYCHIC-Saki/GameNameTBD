extends GutTest
## Regression for 217cd34 + local D057-D062, using isolated state only.

func test_parcel_cache_separates_region_versions_and_cannot_be_mutated_by_readers() -> void:
	var catalog:=TDTownCatalog.new();assert_true(catalog.load_file().ok)
	var seed_value:=TDTownMap.seed_of("tokyo")
	var old: Dictionary=TDTownMap.economic_parcels(catalog,seed_value,2,1)
	var modern: Dictionary=TDTownMap.economic_parcels(catalog,seed_value,2,2)
	assert_eq(old.keys(),modern.keys(),"persistent property IDs survive terrain version")
	assert_ne(old,modern,"old and island geography cannot share a cache entry")
	var original:=modern.duplicate(true)
	var key: String=modern.keys()[0];modern[key].x=999
	var again: Dictionary=TDTownMap.economic_parcels(catalog,seed_value,2,2)
	assert_eq(again,original,"consumer mutation cannot corrupt future save validation")
	assert_eq(TDTownMap.economic_parcels(catalog,seed_value,2,1),old)

func test_existing_semantically_invalid_payload_cannot_be_replaced() -> void:
	var folder: String="res://artifacts/pull-tests/%d"%Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(folder)
	var validator:=func(raw:Dictionary)->TDOutcome:return TDOutcome.new(raw.get("schema_version")==1,"VALID" if raw.get("schema_version")==1 else "UNSUPPORTED_VERSION")
	var store:=TDResearchStore.new(folder+"/save.json",validator)
	assert_true(store.save_game({"schema_version":1,"points":3}).ok)
	var future: String=JSON.stringify({"schema_version":99,"points":5})
	var file:=FileAccess.open(store.path,FileAccess.WRITE)
	file.store_string(JSON.stringify({"schema_version":1,"payload":future,"sha256":future.sha256_text()}));file.close()
	var before:=FileAccess.get_file_as_bytes(store.path)
	assert_eq(store.save_game({"schema_version":1,"points":7}).code,"UNSUPPORTED_VERSION")
	assert_eq(FileAccess.get_file_as_bytes(store.path),before)

func test_real_staff_scheduler_at_home_and_away_has_no_parallel_timer_production() -> void:
	for away: bool in [false,true]:
		var catalog:=TDServiceCatalog.new();assert_true(catalog.load_file().ok)
		var shop:=TDShopSession.new(catalog,"merged-staff-"+str(away),59)
		var room:=TDRestaurantWorld.new();room.player_mode=true;room.floor_service=true;room.business=shop
		add_child(room);room.bind_dining_clock()
		var view:=TDShopView.new();view.service=catalog;view.shop=shop;view.embedded=true
		view.save_path="res://artifacts/pull-tests/staff-%d.json"%Time.get_ticks_usec()
		add_child(view);view.kitchen.auto_advance=false;view.staff_away=away
		shop.crew=room.layout.crew;assert_true(shop.crew.hire("cook-he").ok)
		assert_true(shop.buy(shop.offer("service.tomato_egg").stock,"stock").ok)
		for id: String in shop.snapshot().menu: shop.set_menu(id,id=="service.tomato_egg",1200)
		assert_true(shop.open_day().ok)
		var saw_work: bool=false
		var dishes: Array=[]
		for lane: TDCookingLane in view.kitchen.lanes: lane.dish_delivered.connect(func(dish:Dictionary)->void:dishes.append(dish.duplicate(true)))
		for n: int in 1500:
			view.kitchen.advance(.1)
			saw_work=saw_work or shop.crew_work("cook-he")=="做菜"
		assert_true(saw_work,"real job drives employee animation")
		assert_gt(dishes.size(),0,"same actual kitchen at home and overseas")
		for dish: Dictionary in dishes:
			assert_gt(dish.steps.size(),0,"real operations must run")
			assert_gt(dish.consumed_ingredients.size(),0,"real stock consumption recorded")
		assert_true(shop._crew_jobs.is_empty(),"legacy countdown never runs beside real QTE")
		assert_eq(shop.mastery("service.tomato_egg").points,0.0)
		var money: int=int(shop.snapshot().money_cents)
		for n: int in 10: view.tick_staff()
		assert_eq(int(shop.snapshot().money_cents),money)
		view.close();assert_eq(shop.crew_work("cook-he"),"")
		var snapshot:=shop.snapshot();shop.tick_crew(100);assert_eq(shop.snapshot(),snapshot)
		room.close();view.queue_free();room.queue_free();await wait_process_frames(2)

func test_waiter_uses_dining_clock_when_hidden_and_rendering_cannot_serve() -> void:
	var catalog:=TDServiceCatalog.new();assert_true(catalog.load_file().ok)
	var shop:=TDShopSession.new(catalog,"merged-waiter",59)
	assert_true(shop.buy(shop.offer("service.tomato_egg").stock,"stock").ok)
	var room:=TDRestaurantWorld.new();room.player_mode=true;room.floor_service=true;room.business=shop
	add_child(room);room.bind_dining_clock()
	assert_true(room.layout.crew.hire("waiter-ning").ok)
	assert_true(shop.open_day().ok);assert_true(shop.advance(1).ok)
	var guest:=room.guest_nodes()[0]
	assert_true(shop.advance(guest.walking_seconds()+guest.sit_duration).ok)
	assert_eq(guest.phase,"wait_serve")
	# Fixture isolates the handoff boundary; the preceding test runs real cooking.
	shop._s.orders[0].status="SERVED"
	room._sync_business_guests()
	assert_eq(guest.phase,"wait_serve","a hired waiter must actually reach the table")
	var before: Vector2=room._crew_points(0)[0].point
	room._process(2.0)
	assert_eq(room._crew_points(0)[0].point,before,"render frames do not advance a unified clock")
	room.story_frozen=true;room.advance_dining(5)
	assert_eq(room._crew_points(0)[0].point,before)
	assert_false(bool(guest.get_meta("plated",false)))
	room.story_frozen=false;room.set_floor_cover(true)
	room.advance_dining(.1)
	assert_gt(room._crew_points(0)[0].point.distance_to(before),0.0,"hidden dining room still works")
	for step: int in 200:
		if bool(guest.get_meta("plated",false)): break
		room.advance_dining(.1)
	assert_true(bool(guest.get_meta("plated",false)))
	room.advance_dining(0)
	assert_eq(guest.phase,"eat")
	room.close();room.queue_free();await wait_process_frames(2)
