extends GutTest

var world: TDRestaurantWorld
var shop: TDShopSession
var kitchen: TDShopView
var viewport: SubViewport

func before_each() -> void:
	var catalog:=TDServiceCatalog.new();assert_true(catalog.load_file().ok)
	shop=TDShopSession.new(catalog,"dining-integration",59)
	var cart: Dictionary=shop.offer("service.tomato_egg").stock.duplicate(true)
	for id: String in cart: cart[id]=int(cart[id])*3
	assert_true(shop.buy(cart,"stock").ok)
	for id: String in shop.snapshot().menu: assert_true(shop.set_menu(id,id=="service.tomato_egg",1200).ok)
	viewport=SubViewport.new();viewport.size=Vector2i(1280,800);add_child_autofree(viewport)
	world=TDRestaurantWorld.new();world.player_mode=true;world.floor_service=true;world.business=shop
	viewport.add_child(world);world.bind_dining_clock()
	kitchen=TDShopView.new();kitchen.service=catalog;kitchen.shop=shop;kitchen.embedded=true
	kitchen.save_path="res://artifacts/diner-flow/test-storage/%d.json"%Time.get_ticks_usec()
	viewport.add_child(kitchen);kitchen.kitchen.auto_advance=false
	await wait_process_frames(2)

func after_each() -> void:
	get_tree().paused=false;kitchen.close();world.close()
	# Sidebar refresh queues detached labels for deletion; flush before GUT checks orphans.
	await wait_process_frames(2)

func test_hidden_front_room_walks_sits_then_publishes_same_kitchen_order() -> void:
	assert_true(shop.open_day().ok)
	assert_true(shop.advance(1).ok);kitchen.refresh()
	var incoming: Dictionary=shop.pending_orders()[0]
	var guest:=world._business_guests[incoming.id] as TDRestaurantGuest
	assert_eq(guest.phase,"approach");assert_false(guest.finished)
	assert_false(world.duty_on("greeter"),"Auto seating works with no hired greeter")
	assert_false(sidebar_text().contains(shop.order_label(incoming.id)))
	var start:=guest.position
	world.set_floor_cover(true)
	assert_true(shop.advance(.2).ok);assert_gt(guest.position.distance_to(start),0.0)
	var remaining:=guest.walking_seconds()
	assert_true(shop.advance(remaining).ok)
	assert_eq(guest.phase,"sitting");assert_eq(shop.active_orders().size(),0)
	assert_true(shop.advance(guest.sit_duration*.5).ok)
	assert_gt(guest.position.distance_to(guest.sit_from),0.0)
	assert_eq(shop.active_orders().size(),0)
	assert_true(shop.advance(guest.sit_duration*.5).ok);kitchen.refresh()
	assert_eq(shop.active_orders().size(),1);assert_true(guest.seated)
	var order: Dictionary=shop.active_orders()[0]
	assert_eq(order.id,incoming.id);assert_eq(order.customer,incoming.customer)
	assert_eq(order.recipe_id,incoming.recipe_id);assert_eq(order.seat_id,guest.seat_id)
	assert_true(sidebar_text().contains(shop.order_label(order.id)))
	assert_true(sidebar_text().contains(shop.recipe_name(order.recipe_id)))
	var deadline: float=order.deadline_sec
	world.advance_dining(0);world.advance_dining(0)
	assert_eq(shop.order(order.id).deadline_sec,deadline);assert_eq(shop.active_orders().size(),1)

func test_full_room_waits_and_reuses_a_released_seat_without_duplicate_orders() -> void:
	var keep: String=world.layout.piece_by_kind("dining_table").id
	for seat: Dictionary in world.layout.pieces():
		if seat.seat_use=="dining" and seat.id!=keep: assert_true(world.layout.remove_piece(seat.id).ok)
	assert_true(shop.open_day().ok);assert_true(shop.advance(1).ok)
	shop._arrive();world.advance_dining(0)
	assert_eq(shop.pending_orders().size(),2);assert_eq(world.guest_nodes().size(),2)
	var first:=world.guest_nodes()[0];var second:=world.guest_nodes()[1]
	assert_eq(second.phase,"waiting_seat");assert_eq(second.seat_id,"")
	assert_ne(first.position,second.position)
	assert_true(shop.advance(first.walking_seconds()+first.sit_duration).ok)
	assert_eq(shop.active_orders().size(),1)
	assert_true(shop.cancel_order(first.ticket_id).ok)
	assert_true(shop.advance(30).ok)
	assert_eq(shop.active_orders().size(),1)
	assert_eq(shop.active_orders()[0].id,second.ticket_id)
	assert_eq(second.seat_id,keep)

func test_clock_partition_pause_and_invalid_seat_never_publish_early() -> void:
	assert_true(shop.open_day().ok);assert_true(shop.advance(1).ok)
	var guest:=world.guest_nodes()[0]
	var expected: float=1.0+guest.walking_seconds()+guest.sit_duration
	var before:=guest.position
	assert_true(shop.advance(10,true).ok);assert_eq(guest.position,before)
	for step: int in 500:
		if not shop.active_orders().is_empty(): break
		assert_true(shop.advance(.05).ok)
	assert_eq(shop.active_orders().size(),1)
	assert_almost_eq(float(shop.active_orders()[0].ordered_sec),expected,.0001)
	var order: Dictionary=shop.active_orders()[0]
	assert_true(shop.close_for_night().ok)
	world.finish_night();assert_eq(world.guest_nodes().size(),0)
	world.advance_dining(1);assert_eq(world.guest_nodes().size(),0)
	assert_eq(shop.confirm_seated(order.id,"invalid").code,"SEAT_MISMATCH")

func sidebar_text() -> String:
	var lines: PackedStringArray=[]
	for label: Label in kitchen._sidebar.find_children("*","Label",true,false): lines.append(label.text)
	return "\n".join(lines)
