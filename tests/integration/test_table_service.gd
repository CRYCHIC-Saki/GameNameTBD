extends GutTest
## Real kitchen + real dining room. All state and files are isolated test instances.
var shop: TDShopSession
var room: TDRestaurantWorld
var view: TDShopView
var ticket: String
var plate_id: String

func before_each() -> void:
	plate_id=""
	var catalog:=TDServiceCatalog.new();assert_true(catalog.load_file().ok)
	shop=TDShopSession.new(catalog,"table-test-%d"%Time.get_ticks_usec(),59)
	shop.table_service_enabled=true
	room=TDRestaurantWorld.new();room.player_mode=true;room.floor_service=true;room.business=shop
	add_child(room);room.bind_dining_clock()
	view=TDShopView.new();view.service=catalog;view.shop=shop;view.embedded=true
	add_child(view);view.kitchen.auto_advance=false
	shop.crew=room.layout.crew
	assert_true(shop.buy(shop.offer("service.tomato_egg").stock,"stock").ok)
	for id: String in shop.snapshot().menu: shop.set_menu(id,id=="service.tomato_egg",1200)
	assert_true(shop.open_day().ok);assert_true(shop.advance(1).ok)
	shop._next_arrival=350.0
	var guest:=room.guest_nodes()[0]
	assert_true(shop.advance(guest.walking_seconds()+guest.sit_duration).ok)
	ticket=str(shop.active_orders()[0].id)
	assert_eq(guest.phase,"wait_serve")
	await wait_process_frames(1)

func after_each() -> void:
	get_tree().paused=false
	view.close();room.close();view.queue_free();room.queue_free()
	await wait_process_frames(2)

func cook() -> void:
	# Hired chef operates the actual timed lane, not the old synthetic countdown.
	assert_true(shop.crew.hire("cook-he").ok)
	var before:=int(shop.snapshot().money_cents)
	for i: int in 1200:
		view.kitchen.advance(.1)
		if not shop.table_service.empty(): break
	assert_eq(shop.table_service.rows().size(),1,"Finished food goes to real pass")
	if shop.table_service.empty(): return
	var plate: Dictionary=shop.table_service.rows()[0];plate_id=str(plate.id)
	assert_gt(plate.dish.steps.size(),0);assert_gt(plate.dish.consumed_ingredients.size(),0)
	assert_eq(shop.order(ticket).status,"WAITING")
	assert_eq(shop.order(ticket).prepaid_cents,0)
	assert_eq(shop.snapshot().money_cents,before,"Cooking does not collect the customer's money")
	assert_false(bool(room._guest_by_ticket(ticket).get_meta("plated",false)))
	view.hide();view.kitchen.world.set_controls_enabled(false);room.set_floor_cover(false)

func press(action: String) -> void:
	for down: bool in [true,false]:
		var event:=InputEventAction.new();event.action=action;event.pressed=down
		get_tree().root.push_input(event,true)

func pickup() -> void:
	room.teleport_player(room.service_window_cell());press("world_interact")
	assert_eq(room._plate_order,plate_id)
	assert_eq(shop.table_service.get_plate(plate_id).carrier,"player")

func test_real_chef_hatch_player_table_and_once_only_payment() -> void:
	cook();if plate_id.is_empty(): return
	var before:=shop.snapshot();pickup()
	assert_eq(shop.snapshot(),before,"Taking food does not score or charge")
	var guest:=room._guest_by_ticket(ticket)
	assert_eq(room.hand_plate(guest).code,"TOO_FAR")
	room.teleport_player(room._beside_seat(guest.seat_id));press("world_interact")
	assert_eq(shop.order(ticket).status,"SERVED");assert_true(shop.table_service.empty())
	assert_eq(room._plate_order,"");assert_true(bool(guest.get_meta("plated",false)))
	assert_eq(shop.order(ticket).prepaid_cents,1200)
	assert_eq(shop.snapshot().ledger.filter(func(e:Dictionary)->bool:return e.kind=="prepayment").size(),1)
	var paid:=shop.snapshot();press("world_interact")
	assert_false(room.hand_plate(guest).ok);assert_eq(shop.snapshot(),paid)
	assert_true(shop.advance(.1).ok);assert_eq(guest.phase,"eat")

func test_hidden_waiter_really_carries_pause_freezes_and_render_is_read_only() -> void:
	cook();if plate_id.is_empty(): return
	assert_true(room.layout.crew.hire("waiter-ning").ok)
	room.set_floor_cover(true)
	var before:=shop.snapshot();var rows:=shop.table_service.rows()
	for i: int in 20: room._crew_points(0)
	assert_eq(shop.snapshot(),before);assert_eq(shop.table_service.rows(),rows)
	get_tree().paused=true;shop.advance(80,true);room.advance_dining(80)
	assert_eq(shop.snapshot(),before);assert_eq(shop.table_service.rows(),rows)
	get_tree().paused=false
	var saw_carry:=false
	for i: int in 250:
		shop.advance(.1)
		saw_carry=saw_carry or shop.table_service.get_plate(plate_id).get("carrier","")=="waiter-ning"
		if shop.order(ticket).status=="SERVED": break
	assert_true(saw_carry,"Actual pickup precedes reaching the table")
	assert_eq(shop.order(ticket).status,"SERVED");assert_true(shop.table_service.empty())
	assert_true(bool(room._guest_by_ticket(ticket).get_meta("plated",false)))

func test_claim_put_back_wrong_table_and_discard_are_atomic() -> void:
	cook();if plate_id.is_empty(): return
	pickup();var before:=shop.snapshot();var rows:=shop.table_service.rows()
	assert_eq(shop.table_service.take(plate_id,"other-waiter").code,"ALREADY_CLAIMED")
	assert_eq(shop.table_service.take(plate_id,"player").code,"HANDS_FULL")
	assert_eq(shop.table_service.serve(plate_id,"player","other-order").code,"WRONG_TABLE")
	assert_eq(shop.table_service.discard(plate_id,"other-waiter").code,"NOT_CARRIER")
	assert_eq(shop.snapshot(),before);assert_eq(shop.table_service.rows(),rows)
	press("world_interact");assert_eq(room._plate_order,"")
	assert_eq(shop.table_service.get_plate(plate_id).carrier,"")
	press("world_interact");assert_eq(room._plate_order,plate_id)
	press("world_retrieve");assert_true(shop.table_service.empty());assert_eq(room._plate_order,"")
	assert_eq(shop.snapshot().inventory,before.inventory,"Discard cannot consume the food twice")
	assert_eq(shop.snapshot().ledger.filter(func(e:Dictionary)->bool:return e.kind=="pass_waste").size(),1)
	assert_false(shop.table_service.discard(plate_id,"").ok)
	assert_eq(shop.deliver(ticket,rows[0].dish).code,"DUPLICATE_DISH","Discarded plate cannot be replayed by an old signal")
	assert_true(shop.close_for_night().ok);assert_true(shop.validate_save(shop.snapshot()).ok)

func test_patience_at_pass_then_same_food_reassigned_after_timeout() -> void:
	cook();if plate_id.is_empty(): return
	var stock: Dictionary=shop.snapshot().inventory;var dish: Dictionary=shop.table_service.get_plate(plate_id).dish
	var remaining:=float(shop.order(ticket).deadline_sec)-float(shop.snapshot().elapsed_sec)
	assert_true(shop.advance(1).ok)
	assert_almost_eq(float(shop.order(ticket).deadline_sec)-float(shop.snapshot().elapsed_sec),remaining-1,.001)
	pickup();assert_true(shop.advance(remaining).ok)
	assert_eq(shop.order(ticket).status,"TIMED_OUT")
	assert_eq(shop.table_service.get_plate(plate_id).order_id,"")
	assert_eq(shop.table_service.get_plate(plate_id).carrier,"player")
	assert_eq(shop.table_service.get_plate(plate_id).dish,dish)
	shop._next_arrival=float(shop.snapshot().elapsed_sec)+.1
	assert_true(shop.advance(.1).ok);shop._next_arrival=350
	for i: int in 200:
		shop.advance(.1)
		if not str(shop.table_service.get_plate(plate_id).get("order_id","")).is_empty(): break
	var new_id:=str(shop.table_service.get_plate(plate_id).order_id)
	assert_ne(new_id,"");assert_ne(new_id,ticket)
	var guest:=room._guest_by_ticket(new_id)
	assert_not_null(guest);if guest==null: return
	room.teleport_player(room._beside_seat(guest.seat_id));press("world_interact")
	assert_eq(shop.order(new_id).status,"SERVED");assert_eq(shop.order(ticket).prepaid_cents,0)
	assert_eq(shop.snapshot().inventory,stock,"Reassigned food has no second ingredient charge")

func test_night_cleanup_is_once_and_save_day_boundary_blocks_unserved_food() -> void:
	cook();if plate_id.is_empty(): return
	assert_true(shop.cancel_order(ticket).ok);assert_true(shop.close_early().ok)
	assert_eq(shop.snapshot().phase,"SETTLED")
	assert_eq(shop.next_day(1).code,"PASS_NOT_CLEAR")
	var path: String="res://artifacts/test-storage/pass-%d.json"%Time.get_ticks_usec()
	var store:=TDShopStore.new(path,shop)
	assert_eq(store.save_game(shop.snapshot()).code,"PASS_NOT_CLEAR");assert_false(FileAccess.file_exists(path))
	var inventory: Dictionary=shop.snapshot().inventory
	assert_true(shop.close_for_night().ok);assert_true(shop.table_service.empty())
	var closed:=shop.snapshot();assert_true(shop.close_for_night().ok);assert_eq(shop.snapshot(),closed)
	assert_eq(closed.inventory,inventory);assert_true(shop.validate_save(closed).ok)
	assert_true(store.save_game(closed).ok);assert_true(shop.next_day(1).ok)

func test_pass_snapshot_isolation_and_replacement_waiter_cannot_lose_plate() -> void:
	cook();if plate_id.is_empty(): return
	var original:=shop.table_service.rows();var copy:=shop.table_service.rows()
	copy[0].dish.dish_attributes.completion=0;copy[0].carrier="fake"
	assert_eq(shop.table_service.rows(),original)
	assert_true(shop.table_service.take(plate_id,"former-waiter").ok)
	shop.table_service.release_missing_waiters(["replacement"])
	assert_eq(shop.table_service.get_plate(plate_id).carrier,"")
	assert_true(shop.table_service.take(plate_id,"replacement").ok)
	assert_true(shop.table_service.serve(plate_id,"replacement",ticket).ok)
	var before:=shop.snapshot()
	assert_false(shop.deliver(ticket,original[0].dish).ok);assert_eq(shop.snapshot(),before)
