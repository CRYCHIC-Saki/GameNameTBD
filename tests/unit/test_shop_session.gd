extends GutTest
var catalog: TDServiceCatalog
var shop: TDShopSession

func before_each() -> void:
	catalog=TDServiceCatalog.new(); assert_true(catalog.load_file().ok)
	shop=TDShopSession.new(catalog,"unit",22)

func stock_and_open() -> String:
	assert_true(shop.buy(shop.offer("service.tomato_egg").stock,"buy").ok)
	assert_true(shop.open_day().ok); shop.advance(1)
	return str(shop.active_orders()[0].id)

func test_five_reviewed_recipes_and_bad_references() -> void:
	assert_eq(catalog.config.offers.size(),5)
	for offer: Dictionary in catalog.config.offers:
		assert_ne(catalog.cooking.for_recipe(offer.id).recipe.scope,"TEST_ONLY")
		assert_false(offer.source.is_empty())
	var invalid: Dictionary=catalog.config.duplicate(true); invalid.offers[0].stock.ghost=100
	assert_false(TDServiceCatalog.new().load_data(invalid).ok)

func test_purchase_is_atomic_integer_and_duplicate_safe() -> void:
	assert_true(shop.buy({"tomato":1500,"egg":1000},"p1").ok)
	assert_eq(shop.snapshot().money_cents,29550)
	assert_eq(shop.available("tomato"),1500)
	var before: Dictionary=shop.snapshot()
	assert_false(shop.buy({"tomato":1000},"p1").ok)
	assert_false(shop.buy({"tomato":1000,"egg":.1},"p2").ok)
	assert_false(shop.buy({"beef":100000},"p3").ok)
	assert_eq(shop.snapshot(),before)

func test_missing_stock_and_reserved_double_pot_no_partial_commit() -> void:
	shop.open_day(); shop.advance(1)
	var before: Dictionary=shop.snapshot()
	assert_eq(shop.begin_order(shop.active_orders()[0].id,0).code,"INSUFFICIENT_STOCK")
	assert_eq(shop.snapshot(),before)
	shop=TDShopSession.new(catalog,"stock",22)
	var id: String=stock_and_open(); assert_true(shop.begin_order(id,0).ok)
	assert_eq(shop.available("tomato"),0)
	shop.advance(90)
	assert_false(shop.begin_order(shop.active_orders()[1].id,1).ok)
	assert_eq(shop.order(id).status,"COOKING")

func test_cancel_refunds_once_and_only_unused_stock_is_released() -> void:
	var id: String=stock_and_open(); var cash: int=shop.snapshot().money_cents
	shop.begin_order(id,0); assert_eq(shop.snapshot().money_cents,cash+1800)
	assert_true(shop.consume_total(id,{"tomato":1000}).ok)
	var count: int=shop.snapshot().ledger.size()
	assert_true(shop.consume_total(id,{"tomato":1000}).ok); assert_eq(shop.snapshot().ledger.size(),count)
	assert_true(shop.cancel_order(id).ok)
	assert_eq(shop.available("tomato"),0); assert_eq(shop.available("egg"),1000)
	assert_eq(shop.snapshot().money_cents,cash)
	var before: Dictionary=shop.snapshot(); assert_false(shop.cancel_order(id).ok); assert_eq(shop.snapshot(),before)

func test_clock_partition_timeout_pause_and_settlement_once() -> void:
	var other:=TDShopSession.new(catalog,"unit",22)
	shop.open_day(); other.open_day()
	shop.advance(120); other.advance(30); other.advance(90)
	assert_eq(shop.snapshot(),other.snapshot())
	var before: Dictionary=shop.snapshot(); shop.advance(900,true); assert_eq(shop.snapshot(),before)
	shop.advance(900); assert_eq(shop.snapshot().phase,"SETTLED")
	before=shop.snapshot(); assert_false(shop.settle_day().ok); assert_eq(shop.snapshot(),before)
	assert_true(shop.next_day(1).ok); assert_false(shop.next_day(1).ok); assert_eq(shop.snapshot().day,2)

func test_save_integrity_and_unknown_version_and_live_boundary() -> void:
	assert_true(shop.validate_save(shop.snapshot()).ok)
	var bad: Dictionary=shop.snapshot(); bad.money_cents+=1
	assert_eq(shop.validate_save(bad).code,"LEDGER_MISMATCH")
	bad=shop.snapshot(); bad.schema_version=99; assert_eq(shop.validate_save(bad).code,"UNSUPPORTED_VERSION")
	shop.open_day(); assert_eq(shop.validate_save(shop.snapshot()).code,"NOT_AT_BOUNDARY")

func test_pricing_menu_and_grant_constraints() -> void:
	assert_false(shop.set_menu("missing",true,1500).ok)
	assert_false(shop.set_menu("service.tomato_egg",true,0).ok)
	assert_false(shop.claim_grant().ok)
	shop.open_day(); shop.close_early(); shop.next_day(1)
	assert_eq(shop.claim_grant().code,"GRANT_NOT_NEEDED")

func test_three_days_boundary_round_trip() -> void:
	for day: int in range(1,4):
		shop.open_day(); shop.advance(900)
		assert_eq(shop.snapshot().day,day); assert_eq(shop.snapshot().phase,"SETTLED")
		var restored:=TDShopSession.new(catalog,"restored",0)
		assert_true(restored.restore(JSON.parse_string(JSON.stringify(shop.snapshot()))).ok)
		assert_eq(JSON.stringify(restored.snapshot()),JSON.stringify(shop.snapshot()))
		assert_typeof(restored.snapshot().money_cents,TYPE_INT)
		shop=restored; assert_true(shop.next_day(day).ok)

func rated_dish(id: String, quality: float = 100.0) -> Dictionary:
	# Explicit rule-boundary fixture: real kitchen production is covered in test_shop_application.
	var source:=TDCookingSession.new(id+":fixture",1,catalog.cooking.for_recipe("service.tomato_egg"),{"pc_controls":true})
	var value: Dictionary=source.snapshot().to_dict()
	value.state="delivered"; value.dish_id=id+":fixture:dish"
	value.dish_attributes.completion=quality; value.dish_attributes.harmony=quality
	value.dish_attributes.temperature_c=60.0; value.dish_attributes.flavor[1][1]=40.0
	value.ingredients={"tomato-instance":{"ingredient_id":"tomato","fine":.25,"texture":{"A":.2,"B":.1,"C":0.0}}}
	value.base_reasons=[]
	return value

func test_wrong_order_readonly_scoring_tip_refund_and_duplicate_delivery() -> void:
	var id: String=stock_and_open(); shop.begin_order(id,0)
	var dish: Dictionary=rated_dish(id); var unchanged: Dictionary=dish.duplicate(true)
	var wrong: Dictionary=dish.duplicate(true); wrong.recipe_id="service.kungpao"
	var before: Dictionary=shop.snapshot(); assert_eq(shop.deliver(id,wrong).code,"WRONG_ORDER"); assert_eq(shop.snapshot(),before)
	var result:=shop.deliver(id,dish)
	assert_true(result.ok); assert_eq(float(result.data.score.satisfaction),100.0)
	assert_eq(result.data.tip_cents,180); assert_eq(shop.snapshot().popularity,52)
	assert_eq(shop.snapshot().fame["service.tomato_egg"],5)
	assert_eq(dish,unchanged)
	before=shop.snapshot(); assert_false(shop.deliver(id,dish).ok); assert_eq(shop.snapshot(),before)
	var cash: int=shop.snapshot().money_cents
	assert_true(shop.refund(id).ok); assert_eq(shop.snapshot().money_cents,cash-1980)
	before=shop.snapshot(); assert_false(shop.refund(id).ok); assert_eq(shop.snapshot(),before)

func test_price_consequences_and_low_score_actual_refund() -> void:
	shop.set_menu("service.tomato_egg",true,3600)
	var id: String=stock_and_open(); shop.begin_order(id,0); shop.deliver(id,rated_dish(id))
	assert_eq(shop.snapshot().popularity,22)
	shop=TDShopSession.new(catalog,"failure",22)
	id=stock_and_open(); var cash: int=shop.snapshot().money_cents; shop.begin_order(id,0)
	var dish: Dictionary=rated_dish(id,0); dish.dish_attributes.flavor[1][1]=0.0; dish.dish_attributes.temperature_c=400; dish.ingredients={}
	assert_true(shop.deliver(id,dish).ok)
	assert_gt(shop.order(id).refunded_cents,0); assert_eq(shop.snapshot().money_cents,cash)

func test_consumption_limits_and_next_day_stale_dish_are_rejected() -> void:
	var id: String=stock_and_open(); shop.begin_order(id,0)
	var before: Dictionary=shop.snapshot()
	assert_false(shop.consume_total(id,{"tomato":1001}).ok); assert_eq(shop.snapshot(),before)
	var dish: Dictionary=rated_dish(id); shop.deliver(id,dish); shop.close_early(); shop.next_day(1)
	shop.open_day(); shop.advance(1); var new_id: String=shop.active_orders()[0].id; shop.begin_order(new_id,0)
	assert_eq(shop.deliver(new_id,dish).code,"WRONG_ORDER_SESSION")

func test_emergency_grant_is_conditional_recorded_and_once_per_day() -> void:
	catalog.config.settings.initial_cents=100
	shop=TDShopSession.new(catalog,"poor",2); shop.buy({"tomato":500},"p")
	assert_eq(shop.snapshot().money_cents,0)
	shop.open_day(); shop.close_early(); shop.next_day(1)
	assert_true(shop.claim_grant().ok); assert_eq(shop.snapshot().money_cents,10000)
	var before: Dictionary=shop.snapshot(); assert_false(shop.claim_grant().ok); assert_eq(shop.snapshot(),before)
	assert_eq(shop.snapshot().ledger.back().kind,"emergency_grant")
	assert_true(shop.validate_save(shop.snapshot()).ok)

func test_corrupt_boundary_shapes_refs_and_day_history_are_rejected() -> void:
	var bad: Dictionary=shop.snapshot(); bad.menu.erase("service.tomato_egg"); assert_false(shop.validate_save(bad).ok)
	bad=shop.snapshot(); bad.day=3; bad.settled_days=[1,3]; assert_false(shop.validate_save(bad).ok)
	bad=shop.snapshot(); bad.inventory.tomato=-1; assert_false(shop.validate_save(bad).ok)
	bad=shop.snapshot(); bad.custom=[{"id":"custom.a","name":"x","version":1,"plan":{"schema_version":2,"recipe_id":"missing","ingredients":[],"operations":[]}}]; assert_false(shop.validate_save(bad).ok)
	shop.buy({"tomato":1000},"one")
	bad=shop.snapshot(); bad.ledger[0].erase("extra"); assert_false(shop.validate_save(bad).ok)
	bad=shop.snapshot(); bad.ledger[0].extra={"waste":{"missing":10}}; assert_false(shop.validate_save(bad).ok)
