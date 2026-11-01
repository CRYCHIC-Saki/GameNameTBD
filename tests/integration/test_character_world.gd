extends GutTest
const DRIVER=preload("res://tools/test_support/kitchen_input.gd")
var app: TDApplication
var shell: TDGameShell
var driver: RefCounted

func before_each() -> void:
	app=load("res://src/app/main.tscn").instantiate()
	app.settings_path="res://artifacts/character-tests/%d/settings.json"%Time.get_ticks_usec()
	add_child_autofree(app);shell=app.game_shell;shell.automatic_time=false
	assert_true(shell.create_game("slot-01","日程测试").ok);shell.guide.dialogue.finish_now()
	driver=DRIVER.new();driver.viewport=get_tree().root;driver.kitchen=shell.kitchen_view.kitchen
	await get_tree().process_frame

func after_each() -> void:
	get_tree().paused=false;shell.go_title()
	await get_tree().process_frame;await get_tree().process_frame

func test_clock_story_pause_daily_chat_and_hidden_town_schedule() -> void:
	var people:=shell.profile.characters
	var talk:=shell.profile.story.talk("aling","店主",false,100)
	shell.town._open_talk(talk)
	shell.advance_world_time(30);assert_eq(people.clock.minute,480.0)
	shell.town._dismiss_talk();get_tree().paused=true
	shell.advance_world_time(30);assert_eq(people.clock.minute,480.0)
	get_tree().paused=false;shell.advance_world_time(10);assert_eq(people.clock.minute,490.0)
	var story_before:=shell.profile.story.export_state()
	var daily:=people.conversation("aling")
	shell.town._open_talk(daily);daily.skip();shell.town._talk_view._choose("chat")
	shell.town._talk_view._on_skip()
	assert_eq(people.relationship("aling").affection,2)
	assert_eq(shell.profile.story.export_state(),story_before,"Everyday chat cannot progress the story")
	shell.profile.story.beat="done";shell.town.sync_characters(0)
	var old: Vector2i=people.runtime.chen.cell
	shell.travel("restaurant");people.clock.minute=1210
	shell.advance_world_time(25)
	assert_ne(people.runtime.chen.cell,old,"Town routes continue while its scene is hidden")
	for person: Dictionary in people.visible_people():
		assert_true(shell.profile.world.town_map.is_road(person.cell.x,person.cell.y))
	assert_false(people.definitions.has("linxia"))

func test_profile_clock_relationship_roundtrip_legacy_and_slot_isolation() -> void:
	var profile:=shell.profile
	profile.characters.complete_chat(profile.characters.conversation("chen").context,true,["about"])
	shell.advance_world_time(123.5)
	assert_true(shell.save_game().ok)
	var expected:=profile.characters.snapshot()
	shell.go_title();assert_true(shell.load_game("slot-01").ok)
	assert_true(TDLevelProgression.same_value(shell.profile.characters.snapshot(),expected))
	var saved:=shell.profile.snapshot();var legacy:=saved.duplicate(true)
	legacy.schema_version=4;legacy.erase("characters")
	var migrated:=TDGameProfile.new();assert_true(migrated.restore(legacy).ok)
	assert_eq(migrated.characters.clock.minute,480.0);assert_eq(migrated.characters.relationship("chen").affection,0)
	migrated.close()
	var bad:=saved.duplicate(true);bad.characters.clock.day=2
	assert_false(shell.profile.restore(bad).ok)
	assert_true(TDLevelProgression.same_value(shell.profile.characters.snapshot(),expected))
	shell.go_title();assert_true(shell.create_game("slot-02").ok);shell.guide.dialogue.finish_now()
	assert_eq(shell.profile.characters.relationship("chen").affection,0)
	assert_eq(shell.profile.characters.clock.minute,480.0)

func test_night_returns_raw_and_cut_stock_discards_heated_food_then_saves_once() -> void:
	var shop:=shell.profile.shop
	assert_true(shell.profile.buy({"tomato":2000,"egg":1000}).ok)
	shell.travel("kitchen")
	var view:=shell.kitchen_view;var kitchen:=view.kitchen
	assert_true(view.pick_ingredient("tomato").ok)
	driver.station("kitchen.board");assert_true(view.choose_cut("chunk").ok)
	driver.play(12)
	assert_true(view.pick_ingredient("egg").ok);driver.station("kitchen.stove.left")
	driver.station("kitchen.stove.left",KEY_F);driver.play(6)
	assert_false(kitchen.lanes[0].session.is_cold())
	assert_true(view.pick_ingredient("tomato").ok)
	shell.profile.characters.clock.minute=1559.5
	shell.advance_world_time(1)
	assert_eq(shell.location,"cottage");assert_eq(shop.snapshot().phase,"SETTLED")
	assert_eq(shell.profile.characters.clock.label(),"02:00")
	assert_true(view.checkpoint_ready().ok)
	var returned:=0
	for food: Dictionary in shop.snapshot().cold_foods:
		if food.ingredient_id=="tomato": returned+=roundi(float(food.amount)*1000)
	assert_eq(returned,2000,"Returned raw and prepared portions stay usable")
	assert_eq(shop.available("egg"),0,"Heating is not undone into raw eggs")
	assert_true(shop.snapshot().cold_foods.any(func(f:Dictionary)->bool:return not f.get("cuts",[]).is_empty()))
	var before:=shop.snapshot();assert_eq(shell.finish_night().code,"NIGHT_ALREADY_CLOSED")
	assert_eq(shop.snapshot(),before)
	assert_eq(shell.travel("town").code,"NIGHT_CLOSED")
	shell.go_title();assert_true(shell.load_game("slot-01").ok)
	assert_eq(shell.profile.characters.clock.closed_day,1)
	assert_eq(shell.profile.shop.snapshot().day,1)
	assert_true(shell.profile.next_day().ok)
	assert_eq(shell.profile.characters.clock.minute,480.0)
	assert_eq(shell.profile.shop.snapshot().day,2)

func test_night_write_failure_preserves_last_good_save_and_can_retry() -> void:
	assert_true(shell.save_game().ok)
	var path:=shell.slots.path_for("slot-01");var bytes:=FileAccess.get_file_as_bytes(path)
	var before_cash:=int(shell.profile.shop.snapshot().money_cents)
	shell.profile.persistence=func(_id:String,_data:Dictionary)->TDOutcome:return TDOutcome.new(false,"INJECTED_WRITE_FAILURE")
	shell.profile.characters.clock.minute=1560
	assert_eq(shell.finish_night().code,"INJECTED_WRITE_FAILURE")
	assert_eq(shell.location,"cottage");assert_eq(shell.profile.shop.snapshot().day,1)
	assert_eq(int(shell.profile.shop.snapshot().money_cents),before_cash,"No opening fee on an idle unopened day")
	assert_eq(FileAccess.get_file_as_bytes(path),bytes)
	shell.profile.persistence=shell.slots.save_slot
	assert_true(shell.save_game().ok)
	shell.go_title();assert_true(shell.load_game("slot-01").ok)
	assert_eq(shell.profile.characters.clock.minute,1560.0)

func test_night_ends_open_orders_without_duplicate_reviews_or_dates() -> void:
	var shop:=shell.profile.shop
	shell.profile.story.beat="done";shell.profile.characters.clock.minute=730;shell.town.sync_characters(0)
	shell.profile.commerce.config.outside_utility=-100
	for firm: Dictionary in shell.profile.commerce.state.competitors.chengdu: firm.served=int(firm.capacity)
	assert_true(shell.profile.buy(shop.offer("service.tomato_egg").stock).ok)
	assert_true(shop.open_day().ok);shop.advance(shop.next_boundary(1080)+.001)
	assert_false(shop.active_orders().is_empty())
	shell.profile.characters.clock.minute=1560
	var closed:=shell.finish_night();assert_true(closed.ok,closed.code)
	assert_true(shop.active_orders().is_empty());assert_eq(shop.snapshot().orders[0].status,"TIMED_OUT")
	var state:=shop.snapshot();shell.finish_night();assert_eq(shop.snapshot(),state)
	assert_eq(state.settled_days,[1])

func test_cancelled_unwelcomed_guest_departs_and_served_guest_finishes_after_settlement() -> void:
	var shop:=shell.profile.shop;shop.commerce=null
	assert_true(shop.buy(shop.offer("service.tomato_egg").stock,"visit-stock").ok)
	assert_true(shop.open_day().ok);shop.advance(shop.next_boundary(1080)+.001)
	var room:=shell.restaurant;room._sync_business_guests()
	assert_eq(room.guest_nodes().size(),1)
	var guest:=room.guest_nodes()[0];var ticket:=guest.ticket_id
	assert_false(bool(guest.get_meta("welcomed",false)))
	assert_true(shop.cancel_order(ticket,"TIMED_OUT").ok)
	room._sync_business_guests();assert_eq(guest.phase,"leave")
	for i: int in 80:
		if is_instance_valid(guest): guest.advance(240);room._sync_business_guests()
	assert_false(is_instance_valid(guest));assert_false(room._business_guests.has(ticket))
	room._sync_business_guests();assert_true(room.guest_nodes().is_empty())
	# Presentation of an already settled real order does not change its ledger.
	var order: Dictionary=shop._s.orders[0];order.status="SERVED";order.score={"satisfaction":85.0}
	room._finished_visits.clear();room.floor_service=false;room._sync_business_guests()
	guest=room.guest_nodes()[0];guest.finished=true;room._sync_business_guests()
	shop.close_early();var before:=shop.snapshot()
	room._visit_seconds+=9;room._sync_business_guests();assert_eq(guest.phase,"leave")
	for i: int in 80:
		if is_instance_valid(guest): guest.advance(240);room._sync_business_guests()
	assert_false(is_instance_valid(guest));assert_eq(shop.snapshot(),before)
	room._sync_business_guests();assert_true(room.guest_nodes().is_empty())

func test_named_diner_uses_actual_economic_arrival_and_only_one_world_instance() -> void:
	var profile:=shell.profile;var shop:=profile.shop;var people:=profile.characters
	# Inject the named household's earliest opportunity inside its own lunch window.
	# Still uses real identity, budget, demand comparison, reservation and order creation.
	for peak: Dictionary in profile.commerce.meal_schedule.config.peaks: peak.mean=760;peak.sigma=1
	profile.commerce.meal_schedule.config.start_minute=750
	profile.commerce.meal_schedule.config.off_peak_end=761
	profile.commerce.meal_schedule._cache.clear()
	profile.story.beat="done";people.clock.minute=730; shell.town.sync_characters(0)
	assert_true(profile.buy({"tomato":5000,"egg":5000,"oil":5000,"salt":5000,"sugar":5000,"starch":5000}).ok)
	# Controlled market conditions, still real choice/reservation/order creation (no fake arrival).
	profile.commerce.config.outside_utility=-100
	for firm: Dictionary in profile.commerce.state.competitors.chengdu: firm.served=int(firm.capacity)
	assert_true(shop.open_day().ok);shop.advance(shop.next_boundary(1080)+.001)
	var named: Array=shop.snapshot().orders.filter(func(o:Dictionary)->bool:return o.get("economic_profile",{}).has("character_id"))
	assert_false(named.is_empty())
	if named.is_empty(): return
	var order: Dictionary=named[0];var id:=people.character_for(order.economic_profile)
	assert_eq(order.economic_intent.customer_id,"character:"+id)
	assert_true(TDEconomicCustomer.validate(order.economic_profile).ok)
	assert_true(TDMealIntent.validate(order.economic_intent).ok)
	people.advance(100,shop.snapshot().orders)
	assert_true(people.can_enter(id,order.id),str(people.runtime[id])+" pinned="+str(people.pinned));assert_false(people.visible_people().any(func(p:Dictionary)->bool:return p.id==id))
	shell.restaurant._sync_business_guests()
	var visitors: Array=shell.restaurant.guest_nodes().filter(func(g:TDRestaurantGuest)->bool:return g.character_id==id)
	assert_eq(visitors.size(),1)
	if visitors.is_empty(): return
	assert_eq(visitors[0].dining_profile.id,order.economic_intent.customer_id)
	assert_eq(visitors[0].meal_intent.snapshot().opportunity_id,order.economic_intent.opportunity_id)
	assert_true(shop.cancel_order(order.id).ok);people.observe_orders(shop.snapshot().orders)
	assert_false(people.visible_people().any(func(p:Dictionary)->bool:return p.id==id),"Do not also reappear in town while leaving the restaurant")
	shell.restaurant._sync_business_guests()
	var visitor: TDRestaurantGuest=visitors[0]
	for i: int in 80:
		if is_instance_valid(visitor): visitor.advance(240);shell.restaurant._sync_business_guests()
	assert_false(people.can_enter(id,order.id));assert_eq(people.relationship(id).affection,0)

func test_real_named_meal_changes_affection_once_and_loaded_history_does_not_respawn() -> void:
	var profile:=shell.profile;var shop:=profile.shop;var people:=profile.characters
	# Inject the named household's earliest opportunity inside its own lunch window.
	# Still uses real identity, budget, demand comparison, reservation and order creation.
	for peak: Dictionary in profile.commerce.meal_schedule.config.peaks: peak.mean=760;peak.sigma=1
	profile.commerce.meal_schedule.config.start_minute=750
	profile.commerce.meal_schedule.config.off_peak_end=761
	profile.commerce.meal_schedule._cache.clear()
	profile.story.beat="done";people.clock.minute=730;shell.town.sync_characters(0)
	assert_true(profile.buy({"tomato":5000,"egg":5000,"oil":5000,"salt":5000,"sugar":5000,"starch":5000}).ok)
	profile.commerce.config.outside_utility=-100
	for firm: Dictionary in profile.commerce.state.competitors.chengdu: firm.served=int(firm.capacity)
	assert_true(shop.open_day().ok);shop.advance(shop.next_boundary(1080)+.001)
	var orders: Array=shop.active_orders()
	var named: Array=orders.filter(func(o:Dictionary)->bool:return o.get("economic_profile",{}).has("character_id"))
	assert_false(named.is_empty())
	if named.is_empty(): return
	var target: Dictionary=named[0];var id:=people.character_for(target.economic_profile)
	people.records[id].affection=10
	for order: Dictionary in orders:
		if order.id!=target.id: assert_true(shop.cancel_order(order.id).ok)
	shop.close_early() # Drain only this real order; no later arrivals in the fixture.
	people.advance(100,shop.snapshot().orders)
	shell.restaurant._sync_business_guests();shell.travel("kitchen")
	var view:=shell.kitchen_view;var kitchen:=view.kitchen
	for lane: TDCookingLane in kitchen.lanes+[kitchen.prep]: lane.beat_offset_sec=0
	assert_true(view.pick_ingredient("tomato").ok)
	driver.station("kitchen.board");assert_true(view.choose_cut("chunk").ok);driver.play(12)
	driver.station("kitchen.board");driver.station("kitchen.stove.left")
	assert_true(view.pick_ingredient("egg").ok);driver.station("kitchen.stove.left")
	driver.station("kitchen.stove.left",KEY_F);driver.play(70)
	assert_eq(kitchen.lanes[0].snapshot().state,"plated")
	driver.station("kitchen.stove.left");driver.station("kitchen.serve");kitchen.advance(.1)
	var served:=shop.order(target.id)
	assert_eq(served.status,"SERVED")
	if served.score.is_empty(): return
	var satisfaction:=float(served.score.satisfaction)
	var expected:=13 if satisfaction>=80 else (8 if satisfaction<40 else 10)
	people.observe_orders(shop.snapshot().orders);people.observe_orders(shop.snapshot().orders)
	assert_eq(people.relationship(id).affection,expected)
	assert_eq(shop.snapshot().phase,"SETTLED")
	assert_true(shell.save_game().ok)
	shell.go_title();assert_true(shell.load_game("slot-01").ok)
	shell.restaurant._sync_business_guests()
	assert_true(shell.restaurant.guest_nodes().is_empty(),"Boundary reload must not replay old meals")
	assert_eq(int(shell.profile.characters.relationship(id).affection),expected)
