extends GutTest
var profile: TDGameProfile
var id: String
var visit: TDBranchInterior

func before_each() -> void:
	profile=TDGameProfile.new();profile.slot_id="slot-01"
	assert_true(profile.error.ok,profile.error.code)
	assert_true(profile.shop.world_adjustment(500000,"fixture","branch cooking test").ok)
	for row: Dictionary in profile.employees.config.templates:
		profile.employees.state.owned[row.id]={"id":row.id,"copies":1,"xp":0,"assigned":""}
	var result:=profile.branches.open_store("chengdu",TDRegionMigration.find_site(profile.world.town_map,[6,48,3,4]),"cn","manager.steady","build")
	assert_true(result.ok,result.code);id=result.data.store_id
	for role: String in ["cook","waiter"]:
		for row: Dictionary in profile.employees.config.templates:
			if row.role==role: assert_true(profile.employees.assign(row.id,id).ok);break
	assert_true(profile.shop.close_for_night().ok);assert_true(profile.next_day().ok)
	var cart: Dictionary={"rice":6000,"egg":6000,"oil":6000,"salt":6000,"scallion":6000,"tomato":6000,"sugar":6000,"starch":6000}
	var costs: Dictionary={}
	for key: String in cart: costs[key]=600
	assert_true(profile.branches.receive_supply(id,cart,costs,"fixture-delivery").ok)
	visit=TDBranchInterior.new();visit.profile=profile;visit.store_id=id;add_child(visit)
	await wait_process_frames(2)

func after_each() -> void:
	get_tree().paused=false
	if is_instance_valid(visit): visit.close();visit.queue_free()
	profile.close();await wait_process_frames(2)

func seat_customer() -> void:
	var shop:=visit.kitchen_session
	assert_eq(shop.pending_orders()[0].status,"ARRIVING")
	shop.advance(0)
	var guest:=visit.dining.guest_nodes()[0]
	shop.advance(guest.walking_seconds()+guest.sit_duration)
	assert_eq(guest.phase,"wait_serve")
	assert_eq(shop.active_orders().size(),1)

func follow_plate(order: Dictionary) -> void:
	var shop:=visit.kitchen_session
	var plate:=shop.table_service.for_order(order.id)
	assert_false(plate.is_empty())
	if plate.is_empty(): return
	assert_eq(plate.carrier,"")
	assert_eq(shop.order(order.id).prepaid_cents,0)
	var saw_pickup:=false
	var waiter_id: String=visit.layout.crew.waiters()[0].id
	var guest:=visit.dining._guest_by_ticket(order.id)
	for tick: int in 320:
		shop.advance(shop.next_boundary(.05))
		var waiter: TDRestaurantWorld.Waiter=visit.dining._waiters[waiter_id]
		if not saw_pickup and waiter.plate==plate.id:
			assert_eq(waiter.feet,visit.layout.cell_center(visit.dining.service_window_cell()))
			assert_eq(shop.order(order.id).prepaid_cents,0)
			saw_pickup=true
		if shop.order(order.id).status=="SERVED":
			assert_eq(waiter.feet,visit.layout.cell_center(visit.dining._beside_seat(guest.seat_id)))
			break
	assert_true(saw_pickup)
	assert_true(shop.table_service.empty())

func test_real_branch_fridge_preparation_pause_and_main_stock_isolation() -> void:
	var main:=profile.shop.snapshot()
	visit.show_room("kitchen")
	assert_same(visit.shop_view.shop,visit.kitchen_session)
	assert_ne(visit.shop_view.kitchen.lanes[0].session,visit.shop_view.kitchen.lanes[1].session)
	var stock: int=visit.kitchen_session.available("tomato")
	visit.shop_view._station_action("kitchen.fridge","interact")
	assert_not_null(visit.shop_view._popup)
	visit.shop_view._close_popup()
	var picked:=visit.shop_view.kitchen.handling.pick("tomato","service.tomato_egg")
	assert_true(picked.ok,picked.code)
	assert_eq(visit.kitchen_session.available("tomato"),stock-1000)
	assert_eq(profile.shop.snapshot().inventory,main.inventory)
	visit.shop_view._station_action("kitchen.board","interact")
	assert_not_null(visit.shop_view.kitchen.handling.board)
	assert_true(visit.shop_view.choose_cut("dice").ok)
	var before:=visit.shop_view.kitchen.shared_clock.qte_sec
	get_tree().paused=true;visit.advance(10)
	assert_eq(visit.shop_view.kitchen.shared_clock.qte_sec,before)
	get_tree().paused=false
	assert_true(visit.shop_view.finish_night().ok)
	assert_true(visit.shop_view.checkpoint_ready().ok)
	assert_eq(visit.kitchen_session._s.cold_foods.size(),1)
	var validation:=TDGameProfile.validate_save(profile.snapshot());assert_true(validation.ok,validation.code+" "+validation.message)

func test_branch_economic_customer_queues_without_early_revenue_or_duplicate_stock() -> void:
	assert_true(profile.shop.open_day().ok)
	visit.kitchen_session.sync_store()
	var store: Dictionary=profile.branches.state.stores[id]
	var dish: String=store.menu[0].id
	var family: String=profile.commerce.society.state.households.keys()[0]
	profile.commerce.society.state.households[family].cash_cents=100000
	var money: int=int(profile.shop._s.money_cents);var stock: Dictionary=store.inventory.duplicate(true)
	assert_true(profile.branches.sell(id,dish,family))
	seat_customer()
	assert_eq(visit.kitchen_session.active_orders().size(),1)
	assert_eq(int(store.daily.sales_cents),0)
	assert_eq(int(profile.shop._s.money_cents),money)
	assert_eq(store.inventory,stock)
	var order: Dictionary=visit.kitchen_session.active_orders()[0]
	assert_eq(profile.commerce.society.state.holds[order.id].status,"reserved")
	assert_true(visit.kitchen_session.cancel_order(order.id).ok)
	assert_false(visit.kitchen_session.cancel_order(order.id).ok)
	assert_eq(profile.commerce.society.state.holds[order.id].status,"released")
	assert_eq(int(profile.shop._s.money_cents),money)

func test_branch_timeout_while_carrying_returns_plate_without_charging() -> void:
	var recipe := "service.tomato_egg"
	assert_true(profile.branches.configure_store(id,[{"id":recipe,"price_cents":1850}],10000).ok)
	assert_true(profile.shop.open_day().ok)
	var family: String = profile.commerce.society.state.households.keys()[0]
	profile.commerce.society.state.households[family].cash_cents = 100000
	assert_true(profile.branches.sell(id,recipe,family))
	seat_customer()
	var shop := visit.kitchen_session
	var ticket: String = shop.active_orders()[0].id
	var plate := {}
	for tick: int in 800:
		visit.shop_view.kitchen.advance(.2)
		plate = shop.table_service.for_order(ticket)
		if plate.get("carrier","") != "": break
	assert_ne(plate.get("carrier",""),"")
	if plate.get("carrier","") == "": return
	shop._s.orders[shop._order_index(ticket)].deadline_sec = float(shop._s.elapsed_sec) + .2
	var cash: int = profile.shop._s.money_cents
	shop.advance(.3)
	assert_eq(shop.order(ticket).status,"TIMED_OUT")
	assert_eq(profile.commerce.society.state.holds[ticket].status,"released")
	shop.advance(15)
	assert_eq(shop.table_service.get_plate(plate.id).carrier,"")
	assert_eq(shop.table_service.get_plate(plate.id).order_id,"")
	assert_eq(profile.shop._s.money_cents,cash)
	assert_eq(profile.branches.state.stores[id].daily.sales_cents,0)

func test_branch_hidden_kitchen_and_invalid_saved_state() -> void:
	visit.show_room("kitchen");visit.set_presented(false)
	assert_false(visit.kitchen._player.controls_enabled)
	assert_false(visit.shop_view.visible)
	assert_false(visit._layer.visible)
	visit.set_presented(true)
	assert_true(visit.kitchen._player.controls_enabled)
	var raw:=profile.snapshot();raw.branches.stores[id].kitchen_state.version=999
	assert_false(TDGameProfile.validate_save(raw).ok)
	raw=profile.snapshot();raw.branches.erase("cuisine_revision")
	var dish: Dictionary=raw.branches.stores[id].menu[0]
	dish.ingredients=profile.service.legacy_material_needs(dish.id)
	assert_true(TDGameProfile.validate_save(raw).ok,"genuine legacy quantities accepted")
	dish.ingredients["egg"]=99999
	assert_false(TDGameProfile.validate_save(raw).ok,"malformed old quantities are not silently migrated")
	var money: int=int(profile.shop._s.money_cents)
	var bad:=visit.kitchen_session.consume_materials(visit.kitchen_session.day_namespace()+"bad",{"tomato":999999})
	assert_false(bad.ok);assert_eq(int(profile.shop._s.money_cents),money)

func _play_lane(lane: TDCookingLane) -> bool:
	var sent: Dictionary={}
	for i: int in 10000:
		visit.advance(.05)
		load("res://tools/test_support/cuisine_input.gd").drive(lane,sent)
		if lane.sheet!=null and not lane.sheet.running and lane.qte==null and lane.thermal_qte==null: return true
	return false

func test_manual_branch_cooking_delivers_once_and_saves_at_boundary() -> void:
	assert_true(profile.branches.configure_store(id,[{"id":"service.tomato_egg","price_cents":1850}],10000).ok)
	assert_true(profile.shop.open_day().ok)
	visit.kitchen_session.sync_store()
	# This test is a manual shift: the real staff planner yields its workplaces.
	visit.shop_view.staff.close()
	var family: String=profile.commerce.society.state.households.keys()[0]
	profile.commerce.society.state.households[family].cash_cents=100000
	assert_true(profile.branches.sell(id,"service.tomato_egg",family))
	seat_customer()
	var order: Dictionary=visit.kitchen_session.active_orders()[0]
	var main_stock: Dictionary=profile.shop._s.inventory.duplicate(true)
	var money: int=int(profile.shop._s.money_cents)
	var view:=visit.shop_view;visit.show_room("kitchen")
	assert_true(view.pick_ingredient("tomato").ok)
	view._station_action("kitchen.board","interact")
	assert_true(view.choose_cut("chunk").ok)
	assert_true(_play_lane(view.kitchen.prep))
	assert_eq(view.kitchen.handling.board.snapshot().to_dict().ingredients.values()[0].shape,"chunk")
	view.kitchen.close_bench();view._station_action("kitchen.board","interact")
	view._station_action("kitchen.stove.left","interact")
	assert_true(view.pick_ingredient("egg").ok)
	view._station_action("kitchen.stove.left","interact")
	view._station_action("kitchen.stove.left","open")
	var lane:=view.kitchen.lanes[0]
	assert_true(_play_lane(lane));assert_eq(lane.snapshot().state,"plated")
	assert_gte(float(lane.snapshot().dish_attributes.completion),70.0)
	view.kitchen.close_bench();view._station_action("kitchen.stove.left","interact")
	view._station_action("kitchen.serve","interact")
	follow_plate(order)
	assert_eq(visit.kitchen_session.order(order.id).status,"SERVED")
	assert_gt(int(profile.shop._s.money_cents),money)
	var paid: int=int(profile.shop._s.money_cents)
	view._station_action("kitchen.serve","interact")
	assert_eq(int(profile.shop._s.money_cents),paid)
	assert_eq(profile.shop._s.inventory,main_stock)
	assert_eq(profile.commerce.society.state.holds[order.id].status,"paid")
	assert_true(profile.shop.close_for_night().ok)
	var raw:=profile.snapshot();var checked:=TDGameProfile.validate_save(raw)
	assert_true(checked.ok,checked.code+" "+checked.message)
	assert_true(profile.next_day().ok)
	visit.advance(0)
	assert_true(visit.kitchen_session.active_orders().is_empty())
	var picked:=visit.shop_view.pick_ingredient("egg")
	assert_true(picked.ok,"next-day live kitchen namespace "+picked.code)
	assert_true(visit.shop_view.return_ingredient().ok)

func test_japanese_branch_real_sushi_station_owns_its_stock_and_order() -> void:
	assert_true(profile.research.recommend_cuisine("fixture:jp","jp").ok)
	assert_true(profile.research.debug_unlock("J08").ok)
	var built:=profile.branches.open_store("tokyo",TDRegionMigration.find_site(profile.branches.town_map("tokyo"),[11,46,3,4]),"jp","manager.host","japanese-build")
	assert_true(built.ok,built.code)
	if not built.ok: return
	var second: String=built.data.store_id
	for role: String in ["cook","waiter"]:
		var person: Dictionary=profile.employees.market_rows("tokyo",role)[0]
		assert_true(profile.employees.sign_employee(person.id,"tokyo-"+role,person.offer_key).ok)
		assert_true(profile.employees.assign(person.id,second).ok)
	assert_true(profile.shop.close_for_night().ok);assert_true(profile.next_day().ok)
	assert_true(profile.branches.configure_store(second,[{"id":"study.j08","price_cents":4000}],10000).ok)
	var cart: Dictionary={};var costs: Dictionary={}
	for food: String in profile.service.offer("study.j08").stock: cart[food]=6000;costs[food]=600
	assert_true(profile.branches.receive_supply(second,cart,costs,"jp-stock").ok)
	visit.close();visit.queue_free();await wait_process_frames(2)
	visit=TDBranchInterior.new();visit.profile=profile;visit.store_id=second;add_child(visit)
	await wait_process_frames(2)
	visit.show_room("kitchen");visit.shop_view.staff.close()
	assert_eq(visit.kitchen_session.cuisine_id,"jp")
	if DisplayServer.get_name()!="headless":
		for node: Node in get_tree().root.find_children("GutLayer","CanvasLayer",true,false): node.hide()
		await wait_process_frames(2);RenderingServer.force_draw()
		assert_eq(get_viewport().get_texture().get_image().save_png("res://artifacts/cuisine-expansion-20261117/gpu/branch-jp-room.png"),OK)
	var home: Dictionary=profile.shop.snapshot().inventory
	var other: Dictionary=profile.branches.state.stores[id].inventory.duplicate(true)
	assert_true(profile.shop.open_day().ok)
	var family: String=profile.commerce.society.state.households.keys()[0]
	profile.commerce.society.state.households[family].cash_cents=100000
	assert_true(profile.branches.sell(second,"study.j08",family))
	seat_customer()
	var order: Dictionary=visit.kitchen_session.active_orders()[0]
	var view:=visit.shop_view
	for food: String in profile.service.offer("study.j08").primary:
		assert_true(view.pick_ingredient(food).ok)
		if profile.service.cooking.recipe_data("study.j08").preparation_sheets.has(food):
			view._station_action("kitchen.board","interact");assert_true(view.choose_cut("slice").ok)
			assert_true(_play_lane(view.kitchen.prep));view.kitchen.close_bench();view._station_action("kitchen.board","interact")
		view._station_action("kitchen.steamer","interact")
	view._station_action("kitchen.steamer","open")
	assert_eq(view.kitchen.lanes[1].base_recipe_id,"study.j08")
	assert_true(_play_lane(view.kitchen.lanes[1]))
	assert_false(view.kitchen.lanes[1].snapshot().failed_dish)
	view.kitchen.close_bench();view._station_action("kitchen.steamer","interact");view._station_action("kitchen.serve","interact")
	follow_plate(order)
	assert_eq(visit.kitchen_session.order(order.id).status,"SERVED")
	assert_eq(profile.shop.snapshot().inventory,home)
	assert_eq(profile.branches.state.stores[id].inventory,other)
	# Stream real Tokyo market choices, with no synthetic guaranteed guest.
	profile.branches.advance_live_markets(900)
	var processed: int=int(profile.commerce.state.day_stats.remote_opportunities.tokyo)
	assert_gt(processed,0)
	assert_gt(int(profile.branches.state.stores[second].kitchen_state.order_serial),1,"real Tokyo market opportunities enqueue future guests")
	var snapshot:=profile.snapshot()
	profile.branches.advance_live_markets(900)
	assert_eq(profile.snapshot(),snapshot,"same clock boundary does not spend or enqueue twice")
	assert_true(profile.shop.close_for_night().ok)
	snapshot=profile.snapshot()
	var verified:=TDGameProfile.validate_save(snapshot)
	assert_true(verified.ok,verified.code+" "+verified.message)
	var restored:=TDGameProfile.new()
	var expected: Dictionary=JSON.parse_string(JSON.stringify(snapshot))
	var loaded:=restored.restore(expected)
	assert_true(loaded.ok,loaded.code+" "+loaded.message)
	assert_eq(restored.branches.state.stores[second].inventory,expected.branches.stores[second].inventory)
	assert_eq(restored.branches.state.stores[second].kitchen_state,expected.branches.stores[second].kitchen_state)
	assert_eq(restored.commerce.state.day_stats.remote_opportunities,expected.economy.day_stats.remote_opportunities)
	var cash: int=restored.shop._s.money_cents
	restored.commerce.advance_town_market("tokyo",900)
	assert_eq(int(restored.shop._s.money_cents),cash,"reloading does not settle the same market interval twice")
	restored.close()
	snapshot.economy.day_stats.remote_opportunities.tokyo=-1
	assert_false(TDGameProfile.validate_save(snapshot).ok)
