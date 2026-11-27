extends GutTest

func make_economy() -> TDWorldEconomy:
	return TDWorldEconomy.new({"tomato":200,"egg":150,"noodles":200,"beef":700,"tofu":200,"bean_paste":200},"chengdu",101)

func menu(price: int=1300) -> Array:
	return [{"id":"service.tomato_egg","family_id":"service.tomato_egg","price_cents":price,"reference_cents":1300,"food":0.7,"familiarity":0.7,"available":true,"taste":{"sweet":0.5},"culture":"chinese"}]

func probability(rows: Array, store: String) -> float:
	var total: float=0
	for row: Dictionary in rows:
		if row.store_id==store: total+=float(row.probability)
	return total

func test_price_distance_clones_outside_budget_and_forecast_are_readonly() -> void:
	var economy:=make_economy();assert_true(economy.error.ok)
	var group: Dictionary=economy.config.groups[0]
	var store:=economy.player_store(menu(),0,group)
	var basic:=probability(TDEconomicDemand.choices(group,[store]),"player")
	store.menu[0].price_cents=2000
	assert_lt(probability(TDEconomicDemand.choices(group,[store]),"player"),basic)
	store.menu=menu();store.travel_minutes=100.0
	assert_lt(probability(TDEconomicDemand.choices(group,[store]),"player"),basic)
	store=economy.player_store(menu(),0,group)
	store.menu.append(store.menu[0].duplicate(true));store.menu[1].id="custom.clone"
	assert_almost_eq(probability(TDEconomicDemand.choices(group,[store]),"player"),basic,0.000001)
	store.menu=menu(500000)
	assert_eq(probability(TDEconomicDemand.choices(group,[store]),"outside"),1.0)
	var before:=economy.snapshot()
	assert_eq(economy.forecast(menu()),economy.forecast(menu()))
	assert_eq(economy.snapshot(),before)

func test_quotes_supply_shipping_are_finite_idempotent_and_locked() -> void:
	var economy:=make_economy()
	assert_eq(economy.quote("tokyo",{"egg":1000}).code,"ROUTE_LOCKED")
	assert_true(economy.open_route("paris","story.paris").ok)
	var quote:=economy.quote("paris",{"egg":1000})
	assert_true(quote.ok)
	var before: int=economy.state.markets.paris.stock.egg
	assert_true(economy.commit_quote(quote.data,"ship.1").ok)
	assert_true(economy.validate_save(economy.snapshot()).ok,"A live shipment must validate before JSON encoding.")
	assert_eq(int(economy.state.markets.paris.stock.egg),before-1000)
	assert_false(economy.commit_quote(quote.data,"ship.1").ok)
	assert_eq(int(economy.state.markets.paris.stock.egg),before-1000)
	assert_true(economy.due_shipments().is_empty())
	assert_eq(economy.quote("paris",{"egg":100000}).code,"MARKET_SOLD_OUT")
	assert_true(economy.open_route("tokyo","story.tokyo").ok)
	assert_false(economy.open_route("tokyo","story.tokyo").ok)

func test_inventory_cost_and_debt_do_not_double_charge_purchases() -> void:
	var economy:=make_economy()
	var ledger: Array=[{"day":1,"kind":"purchase","cents":-700,"inventory_delta":{"tomato":2000,"egg":2000},"extra":{}},{"day":1,"kind":"consumption","cents":0,"inventory_delta":{"tomato":-1000,"egg":-1000},"extra":{}}]
	economy.begin_day();economy.state.day_stats.admitted=2;economy.cooking_time(10)
	var report:=economy.settle(ledger,1300)
	assert_eq(int(report.consumed_cost_cents),350)
	var fees: Dictionary = economy.config.fees
	var utility := roundi(float(fees.opening_cents)+2*float(fees.guest_cents)+10*float(fees.cooking_second_cents))
	var profit := 1300 - 350 - utility
	var tax := roundi(float(profit) * int(economy.config.society.profit_tax_bps) / 10000)
	assert_eq(int(report.utilities_cents),utility)
	assert_eq(int(report.profit_before_tax_cents),profit)
	assert_eq(int(report.tax_cents),tax)
	assert_eq(int(report.profit_cents),profit-tax)
	var snap:=economy.snapshot()
	assert_eq(economy.settle(ledger,1300),report)
	assert_eq(economy.snapshot(),snap)
	assert_eq(economy.pay_debt(100),100)
	assert_eq(int(economy.state.debt_cents),utility+tax-100)
	assert_eq(economy.pay_debt(1000),utility+tax-100)
	assert_eq(int(economy.state.debt_cents),0)

func test_store_reputation_uses_volume_and_satisfaction_but_awareness_uses_retained_sales() -> void:
	var examples := [
		[0, 0.0, 0, 40.0, 0.35],
		[8, 60.0, 8, 50.0, 0.37047072],
		[8, 90.0, 8, 53.0, 0.37047072],
		[8, 90.0, 0, 53.0, 0.35],
		[8, 30.0, 0, 47.0, 0.35],
		[12, 90.0, 12, 55.6, 0.38046304],
	]
	for example: Array in examples:
		var economy := make_economy()
		economy.begin_day()
		var orders: Array = [{"status": "TIMED_OUT", "prepaid_cents": 0, "refunded_cents": 0}]
		for i: int in int(example[0]):
			orders.append({"status": "SERVED", "score": {"satisfaction": example[1]},
				"prepaid_cents": 1000, "refunded_cents": 0 if i < int(example[2]) else 1000})
		economy.settle([], 1000 * int(example[2]), true, orders)
		assert_almost_eq(float(economy.state.popularity), float(example[3]), 0.000001)
		assert_almost_eq(float(economy.state.awareness), float(example[4]), 0.00001)
		assert_eq(economy.state.day_stats.opportunities, 44)
	assert_almost_eq(TDWorldEconomy.popularity_after_service(50.0, 8, 2.4, false), 50.0, 0.000001)
	assert_almost_eq(TDWorldEconomy.popularity_after_service(50.0, 8, 7.2, false), 53.0, 0.000001)

func test_shared_opportunity_pool_capacity_npc_cash_and_two_worlds() -> void:
	var economy:=make_economy();var other:=make_economy()
	var template: Array=[{"requirements":[]},{"requirements":[]}]
	var first:=economy.arrivals(0,menu(),0,3,template,240)
	assert_eq(first,other.arrivals(0,menu(),0,3,template,240))
	assert_true(economy.arrivals(0,menu(),0,3,template,240).is_empty())
	for slot: int in range(1,int(economy.config.slots_per_day)): economy.arrivals(slot,menu(),3,3,template,240)
	var stats: Dictionary=economy.state.day_stats
	assert_eq(int(stats.opportunities),44)
	assert_eq(int(stats.outside+stats.competitor+stats.considered),44)
	assert_eq(int(stats.admitted+stats.capacity_rejected),int(stats.considered))
	assert_ne(economy.snapshot(),other.snapshot())
	for firms: Array in economy.state.competitors.values():
		for firm: Dictionary in firms:
			assert_eq(int(firm.cash_cents),80000-int(firm.purchase_cents)+int(firm.receipts_cents))
			for quantity: Variant in firm.inventory.values(): assert_gte(int(quantity),0)

func test_world_save_roundtrip_rejects_corruption_and_day_repeat() -> void:
	var economy:=make_economy();economy.begin_day();economy.settle([],0)
	var raw: Dictionary=JSON.parse_string(JSON.stringify(economy.snapshot()))
	var restored:=make_economy();assert_true(restored.restore(raw).ok)
	assert_true(restored.advance_day(1).ok)
	assert_false(restored.advance_day(1).ok)
	raw.markets.chengdu.stock.egg=-1
	var before:=restored.snapshot()
	assert_false(restored.restore(raw).ok)
	assert_eq(restored.snapshot(),before)

func test_missing_config_nested_save_fields_and_cell_changes_are_checked() -> void:
	var economy:=make_economy()
	var broken:=economy.config.duplicate(true);broken.market.erase("production_units")
	assert_false(economy.validate_config(broken).ok)
	broken=economy.snapshot();broken.competitors.chengdu[0].erase("price_cents")
	assert_false(economy.restore(broken).ok)
	economy.settle([],0);broken=economy.snapshot();broken.books[0].erase("profit_cents")
	assert_false(economy.restore(broken).ok)
	economy.geography.configure("chengdu",[])
	var original:=economy.geography.cell(Vector2i(20,20))
	var changed:=original.duplicate(true);changed.visibility=0.05;changed.travel_minutes.residential=100.0
	assert_true(economy.configure_cell(changed).ok)
	assert_eq(economy.geography.cell(Vector2i(20,20)).visibility,0.05)
	assert_ne(economy.geography.cell(Vector2i(21,20)).visibility,0.05)
	assert_true(economy.validate_save(economy.snapshot()).ok)
