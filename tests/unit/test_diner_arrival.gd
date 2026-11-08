extends GutTest

var shop: TDShopSession

func before_each() -> void:
	var catalog:=TDServiceCatalog.new();assert_true(catalog.load_file().ok)
	shop=TDShopSession.new(catalog,"arrival-check",31)
	shop.require_seating=true
	assert_true(shop.buy(shop.offer("service.tomato_egg").stock,"stock").ok)
	assert_true(shop.open_day().ok)
	assert_true(shop.advance(1.0).ok)

func test_arrival_does_not_publish_kitchen_order_until_seated_once() -> void:
	assert_eq(shop.pending_orders().size(),1);assert_eq(shop.active_orders().size(),0)
	var arriving: Dictionary=shop.pending_orders()[0]
	assert_eq(arriving.status,"ARRIVING")
	assert_true(shop.first_order_for({"recipe_id":arriving.recipe_id}).is_empty())
	assert_eq(shop.can_deliver(arriving.id,{}).code,"INVALID_ORDER")
	assert_true(shop.advance(2.0).ok)
	assert_eq(shop.confirm_seated(arriving.id,"table-a").code,"ORDERED")
	var ordered:=shop.order(arriving.id)
	assert_eq(ordered.arrival_sec,1.0);assert_eq(ordered.ordered_sec,3.0)
	assert_eq(ordered.customer,arriving.customer);assert_eq(ordered.price_cents,arriving.price_cents)
	assert_eq(ordered.deadline_sec,3.0+float(arriving.patience_seconds))
	assert_eq(shop.active_orders().size(),1)
	assert_true(shop.advance(1.0).ok)
	assert_eq(shop.confirm_seated(arriving.id,"table-a").code,"ALREADY_ORDERED")
	assert_eq(shop.order(arriving.id),ordered)
	assert_eq(shop.confirm_seated(arriving.id,"table-b").code,"SEAT_MISMATCH")

func test_draining_waits_for_arrivals_and_night_closes_them_once() -> void:
	var id: String=shop.pending_orders()[0].id
	assert_eq(shop.close_early().code,"DRAINING")
	assert_eq(shop.settle_day().code,"INVALID_SETTLEMENT")
	assert_true(shop.close_for_night().ok)
	assert_eq(shop.order(id).status,"TIMED_OUT");assert_eq(shop.snapshot().phase,"SETTLED")
	var after:=shop.snapshot()
	assert_eq(shop.confirm_seated(id,"table-a").code,"STALE_VISIT")
	assert_true(shop.close_for_night().ok);assert_eq(shop.snapshot(),after)
	assert_true(shop.validate_save(shop.snapshot()).ok)

func test_waiting_for_seat_times_out_without_publishing_or_charging() -> void:
	var arriving: Dictionary=shop.pending_orders()[0]
	var money: int=shop.snapshot().money_cents
	assert_true(shop.close_early().ok)
	assert_true(shop.advance(150.0).ok)
	assert_eq(shop.order(arriving.id).status,"TIMED_OUT")
	assert_false(shop.order(arriving.id).has("ordered_sec"))
	assert_eq(shop.snapshot().money_cents,money)
	assert_eq(shop.active_orders().size(),0)

func test_walk_consumes_all_distance_across_corners() -> void:
	var guest:=TDRestaurantGuest.new();autofree(guest)
	guest.set_path([Vector2i(0,0),Vector2i(1,0),Vector2i(1,1)],64)
	guest.advance(96.0);assert_eq(guest.position,Vector2(96,64));assert_false(guest.finished)
	guest.advance(32.0);assert_eq(guest.position,Vector2(96,96));assert_true(guest.finished)
	guest.begin_sitting(Vector2(128,96),.8,Vector2i.LEFT)
	guest.advance_sitting(.4);assert_eq(guest.position,Vector2(112,96));assert_false(guest.seated)
	guest.advance_sitting(.4);assert_eq(guest.position,Vector2(128,96));assert_true(guest.seated)

func test_saved_visit_metadata_validates_and_legacy_boundary_remains_compatible() -> void:
	var id: String=shop.pending_orders()[0].id
	assert_true(shop.confirm_seated(id,"table-a").ok)
	assert_true(shop.cancel_order(id).ok);assert_true(shop.close_early().ok)
	var data:=shop.snapshot()
	assert_true(shop.validate_save(data).ok)
	for field: String in ["ordered_sec","patience_seconds","seat_id"]:
		var bad:=data.duplicate(true);bad.orders[0][field]=-1
		assert_eq(shop.validate_save(bad).code,"INVALID_VISIT")
	for field: String in ["ordered_sec","patience_seconds","seat_id","arrival_sec"]: data.orders[0].erase(field)
	assert_true(shop.validate_save(data).ok,"Old boundary orders do not need new presentation metadata")

func test_diner_clothes_change_without_changing_face_or_rng() -> void:
	var skin:=Color("edc39d")
	assert_eq(TDDinerArt.cloth_color(skin,1),skin)
	assert_ne(TDDinerArt.cloth_color(Color("256e67"),1),Color("256e67"))
	assert_eq(TDDinerArt.cloth_color(Color(1,1,1,.01),2),Color.TRANSPARENT)
	assert_eq(TDDinerArt.appearance("same-person"),TDDinerArt.appearance("same-person"))
	for variant: int in TDDinerArt.VARIANTS:
		var idle:=TDDinerArt.sprite(variant)
		assert_gt(idle.get_width(),10);assert_gt(idle.get_height(),10)
		assert_same(TDDinerArt.sprite(variant),idle,"Cached sprites are reused")
		assert_ne(TDDinerArt.sprite(variant,Vector2i.DOWN,0).get_image().get_data(),TDDinerArt.sprite(variant,Vector2i.DOWN,2).get_image().get_data())
		assert_gt(TDDinerArt.sprite(variant,Vector2i.DOWN,-1,true).get_height(),10)
