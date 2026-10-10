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

func test_forecast_hand_calculated_range_popularity_and_limits() -> void:
	# 360s, first arrival at 1s, 47.25s intervals => 8 expected arrivals.
	assert_eq(shop.visitor_forecast(),{"day":1,"min_visitors":6,"max_visitors":10,"expected_visitors":8})
	var state: Dictionary=shop.snapshot(); state.popularity=0
	assert_true(shop.restore(state).ok)
	assert_eq(shop.visitor_forecast().expected_visitors,7)
	state.popularity=100; assert_true(shop.restore(state).ok)
	assert_eq(shop.visitor_forecast().expected_visitors,10)
	catalog.config.settings.day_sec=1
	assert_eq(shop.visitor_forecast().max_visitors,0)
	var invalid: Dictionary=catalog.config.duplicate(true)
	for percentage: Variant in [-1,51,.5,NAN,"20"]:
		invalid.settings.forecast_uncertainty_percent=percentage
		assert_eq(TDServiceCatalog.new().load_data(invalid).code,"INVALID_SETTINGS")
	invalid.settings.erase("forecast_uncertainty_percent")
	assert_true(TDServiceCatalog.new().load_data(invalid).ok)

func test_forecast_is_read_only_survives_boundary_reload_and_never_draws_rng() -> void:
	var state: Dictionary=shop.snapshot()
	var restored:=TDShopSession.new(catalog)
	assert_true(restored.restore(JSON.parse_string(JSON.stringify(state))).ok)
	var expected: Dictionary=shop.visitor_forecast()
	for iteration: int in 10:
		var changed: Dictionary=shop.visitor_forecast(); changed.min_visitors=-999
		assert_eq(shop.visitor_forecast(),expected)
	assert_eq(shop.snapshot(),state)
	assert_eq(restored.visitor_forecast(),expected)
	shop.open_day(); restored.open_day()
	for iteration: int in 3:
		shop.visitor_forecast(); shop.advance(80); restored.advance(80)
	assert_eq(shop.snapshot(),restored.snapshot())

func test_five_reviewed_recipes_and_bad_references() -> void:
	assert_eq(catalog.config.offers.size(),6)
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

func test_stock_filters_new_customers_and_no_manual_acceptance_needed() -> void:
	shop.open_day(); shop.advance(1)
	assert_eq(shop.active_orders().size(),0)
	shop=TDShopSession.new(catalog,"stock",22)
	var id: String=stock_and_open()
	assert_eq(shop.order(id).status,"WAITING")
	assert_eq(shop.available("tomato"),1000)
	shop.advance(90)
	assert_eq(shop.active_orders().size(),1)
	assert_eq(shop.order(id).status,"WAITING")

func test_cancel_once_keeps_unspent_stock_and_actual_material_loss() -> void:
	var id: String=stock_and_open(); var cash: int=shop.snapshot().money_cents
	assert_eq(shop.snapshot().money_cents,cash)
	assert_true(shop.consume_materials(shop.day_namespace()+"take",{"tomato":1000}).ok)
	var count: int=shop.snapshot().ledger.size()
	assert_false(shop.consume_materials(shop.day_namespace()+"take",{"tomato":1000}).ok); assert_eq(shop.snapshot().ledger.size(),count)
	assert_true(shop.cancel_order(id).ok)
	assert_eq(shop.available("tomato"),0); assert_eq(shop.available("egg"),1000)
	assert_eq(shop.snapshot().money_cents,cash)
	var before: Dictionary=shop.snapshot(); assert_false(shop.cancel_order(id).ok); assert_eq(shop.snapshot(),before)

func test_clock_partition_timeout_pause_and_settlement_once() -> void:
	var other:=TDShopSession.new(catalog,"unit",22)
	shop.buy(shop.offer("service.tomato_egg").stock,"a"); other.buy(other.offer("service.tomato_egg").stock,"a")
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
	var id: String=stock_and_open()
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
	var id: String=stock_and_open(); shop.deliver(id,rated_dish(id))
	assert_eq(shop.snapshot().popularity,22)
	shop=TDShopSession.new(catalog,"failure",22)
	id=stock_and_open(); var cash: int=shop.snapshot().money_cents
	var dish: Dictionary=rated_dish(id,0); dish.dish_attributes.flavor[1][1]=0.0; dish.dish_attributes.temperature_c=400; dish.ingredients={}
	assert_true(shop.deliver(id,dish).ok)
	assert_gt(shop.order(id).refunded_cents,0); assert_eq(shop.snapshot().money_cents,cash)

func test_consumption_limits_and_next_day_stale_dish_are_rejected() -> void:
	var id: String=stock_and_open()
	var before: Dictionary=shop.snapshot()
	assert_false(shop.consume_materials(shop.day_namespace()+"invalid",{"tomato":1001}).ok); assert_eq(shop.snapshot(),before)
	var dish: Dictionary=rated_dish(id); shop.deliver(id,dish); shop.close_early(); shop.next_day(1)
	shop.open_day(); shop.advance(1); var new_id: String=shop.active_orders()[0].id
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

func test_customer_requirements_compile_different_charts_without_changing_dish_identity() -> void:
	var source: Dictionary=catalog.cooking.data()
	var sweet: TDCookingCatalog=catalog.request_profile("service.tomato_egg",source.customers[0])
	var small: TDCookingCatalog=catalog.request_profile("service.tomato_egg",source.customers[1])
	assert_not_null(sweet); assert_not_null(small)
	if sweet==null or small==null: return
	assert_eq(sweet.for_recipe("service.tomato_egg").recipe.id,small.for_recipe("service.tomato_egg").recipe.id)
	var chart:=TDBeatSheet.new()
	var recipe: Dictionary=small.for_recipe("service.tomato_egg").recipe
	assert_true(chart.configure(small.data().pc_operations.document_sheets[recipe.preparation_sheets.tomato],source.operations).ok)
	var cut: Dictionary=chart.snapshot().events[0].settings
	assert_eq(cut.cut_actions.count("primary"),6)
	assert_eq(cut.beat_times_sec.size(),8)
	assert_almost_eq(float(cut.beat_times_sec[1])-float(cut.beat_times_sec[0]),.25,.000001)
	assert_eq(catalog.material_needs(sweet,"service.tomato_egg").sugar,200)
	assert_eq(catalog.material_needs(small,"service.tomato_egg").soy_sauce,150)
	assert_eq(catalog.cooking.data(),source)
	var invalid: Dictionary=catalog.config.duplicate(true); invalid.request_rules.flavor_targets[0].amount=-.1
	assert_eq(TDServiceCatalog.new().load_data(invalid).code,"INVALID_REQUEST_RULES")

func test_atomic_material_sink_rejects_shortage_duplicates_and_old_day_before_mutation() -> void:
	var id: String=stock_and_open()
	var session:=TDCookingSession.new(shop.day_namespace()+"test",1,catalog.cooking.for_recipe("service.tomato_egg"),{"pc_controls":true,"document_rules":true})
	session.set_material_sink(shop.consume_materials)
	var request:=TDRequest.new(shop.day_namespace()+"test",1,"take","add",0,{"ingredient_id":"tomato","amount":2.0}); request.schema_version=3
	var before: Dictionary=session.snapshot().to_dict(); var state: Dictionary=shop.snapshot()
	assert_eq(session.begin(request).code,"INSUFFICIENT_STOCK")
	assert_eq(session.snapshot().to_dict(),before); assert_eq(shop.snapshot(),state)
	request.parameters.amount=1.0; assert_true(session.begin(request).ok)
	assert_eq(shop.available("tomato"),0)
	state=shop.snapshot(); assert_false(session.begin(request).ok); assert_eq(shop.snapshot(),state)
	assert_false(shop.consume_materials(shop.day_namespace()+"bad",{"egg":1000,"sugar":999}).ok)
	assert_eq(shop.available("egg"),1000)
	assert_false(shop.consume_materials("old:d9:bad",{"egg":1}).ok)
	shop.sync_kitchen([{"location":"loose","dish":session.snapshot().to_dict()}])
	assert_eq(shop.order(id).status,"WAITING","最后一份已取料仍能供应")

func test_stock_rejection_is_once_and_survives_boundary_reload() -> void:
	var id: String=stock_and_open()
	assert_true(shop.consume_materials(shop.day_namespace()+"wasted",{"egg":1000}).ok)
	shop.sync_kitchen([])
	assert_eq(shop.order(id).status,"REJECTED_STOCK"); assert_eq(shop.snapshot().popularity,49)
	assert_true(shop.order(id).score.is_empty()); assert_false(shop.order(id).feedback.is_empty())
	var state: Dictionary=shop.snapshot(); shop.sync_kitchen([]); assert_eq(shop.snapshot(),state)
	shop.advance(100); assert_eq(shop.active_orders().size(),0)
	shop.close_early(); assert_true(shop.validate_save(shop.snapshot()).ok)
	var restored:=TDShopSession.new(catalog)
	assert_true(restored.restore(JSON.parse_string(JSON.stringify(shop.snapshot()))).ok)
	assert_eq(restored.snapshot().popularity,49)
	assert_eq(restored.order(id).status,"REJECTED_STOCK")

func test_same_dish_targets_oldest_customer_and_delivery_cannot_skip_them() -> void:
	shop.buy(shop.offer("service.tomato_egg").stock,"a"); shop.buy(shop.offer("service.tomato_egg").stock,"b")
	shop.open_day(); shop.advance(81)
	var first: Dictionary=shop.active_orders()[0]; var second: Dictionary=shop.active_orders()[1]
	assert_eq(shop.context_for_ingredients(["tomato","egg"],true).id,first.id)
	assert_eq(first.customer.id,"sweet"); assert_eq(second.customer.id,"savory")
	var dish: Dictionary=rated_dish(first.id)
	assert_eq(shop.deliver(second.id,dish).code,"EARLIER_MATCHING_ORDER")
	assert_true(shop.deliver(first.id,dish).ok)
	assert_eq(shop.context_for_ingredients(["tomato","egg"],true).id,second.id)

func test_overpour_shortage_rejects_entire_seasoning_without_free_ingredients() -> void:
	stock_and_open()
	var session:=TDCookingSession.new(shop.day_namespace()+"pour",1,catalog.cooking.for_recipe("service.tomato_egg"),{"pc_controls":true,"document_rules":true})
	session.set_material_sink(shop.consume_materials)
	var add:=TDRequest.new(shop.day_namespace()+"pour",1,"add","add",0,{"ingredient_id":"tomato","amount":1.0}); add.schema_version=3
	assert_true(session.begin(add).ok)
	var pour:=TDRequest.new(shop.day_namespace()+"pour",1,"pour","season",1,{"ingredient_id":"salt","amount":.1,"mode":"precise"}); pour.schema_version=3
	assert_true(session.begin(pour).ok)
	# Contract-boundary result fixture; actual mouse holds are covered by scene tests.
	var result:=TDOutcome.new(true,"COMPLETED","",{"schema_version":3,"session_id":shop.day_namespace()+"pour","generation":1,"operation_id":"pour","kind":"season","status":"completed","quality":1.0,"elapsed_sec":5.0,"pour_rate_per_sec":.2,"actual_actions":[{"action":"spice:salt","beat_index":0,"held_sec":3.0,"amount":.6}]})
	var state: Dictionary=shop.snapshot(); var dish: Dictionary=session.snapshot().to_dict()
	assert_eq(session.complete_operation(result).code,"INSUFFICIENT_STOCK")
	assert_eq(shop.snapshot(),state); assert_eq(session.snapshot().to_dict(),dish)
	assert_true(session.cancel_operation("pour").ok)
	assert_false(session.complete_operation(result).ok)

func test_shortage_keeps_earlier_feasible_order_and_does_not_reject_twice() -> void:
	shop.buy(shop.offer("service.tomato_egg").stock,"first"); shop.buy(shop.offer("service.tomato_egg").stock,"second")
	shop.open_day(); shop.advance(81)
	var earlier: String=shop.active_orders()[0].id; var later: String=shop.active_orders()[1].id
	assert_true(shop.consume_materials(shop.day_namespace()+"waste-egg",{"egg":1000}).ok)
	shop.sync_kitchen([])
	assert_eq(shop.order(earlier).status,"WAITING")
	assert_eq(shop.order(later).status,"REJECTED_STOCK")
	assert_eq(shop.snapshot().popularity,49)
	shop.sync_kitchen([]); shop.advance(1)
	assert_eq(shop.snapshot().popularity,49)
