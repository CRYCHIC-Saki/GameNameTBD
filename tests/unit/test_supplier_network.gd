extends GutTest
var profiles: Array[TDGameProfile]=[]

func make_profile() -> TDGameProfile:
	var p:=TDGameProfile.new(); profiles.append(p)
	assert_true(p.error.ok,p.error.code)
	p.slot_id="slot-01"
	assert_true(p.shop.world_adjustment(300000,"supplier-fixture","test funding").ok)
	return p

func network(p: TDGameProfile) -> TDSupplierNetwork:
	var result:=TDSupplierNetwork.new(); result.attach(p)
	assert_true(result.error.ok,result.error.code)
	return result

func after_each() -> void:
	for p: TDGameProfile in profiles: p.close()
	profiles.clear()

func branch(p: TDGameProfile) -> String:
	# The fixture retains the supported pre-roster opening path; delivery itself
	# exercises the real shared branch inventory, batch and cost implementations.
	p.branches.managed=false
	var opened:=p.branches.open_store("chengdu",[6,48,3,4],"cn","manager.steady","supplier-branch")
	assert_true(opened.ok,opened.code)
	return str(opened.data.get("store_id",""))

func test_five_suppliers_cuisine_filter_and_quote_are_read_only() -> void:
	var p:=make_profile(); var n:=network(p); var before:=p.snapshot()
	assert_eq(n.config.towns.size(),5)
	assert_eq(n.item_name("tomato"),"番茄")
	assert_eq(n.item_name("egg"),"鸡蛋")
	assert_eq(n.item_name("oil"),"食用油")
	for town: String in TDSupplierNetwork.TOWNS:
		var ids: Array=n.catalogue(town).map(func(row: Dictionary)->String:return row.id)
		assert_has(ids,"salt")
		assert_has(ids,"tomato")
		assert_does_not_have(ids,"beef","Locked recipe material stays unavailable.")
		assert_true(n.quote(town,"player_diner",{"salt":1000}).ok)
	assert_eq(p.snapshot(),before)
	assert_eq(n.quote("unknown","player_diner",{"salt":1000}).code,"UNKNOWN_SUPPLY_TARGET")
	assert_eq(n.quote("chengdu","missing",{"salt":1000}).code,"UNKNOWN_SUPPLY_TARGET")
	assert_eq(n.quote("chengdu","player_diner",{}).code,"EMPTY_CART")

func test_shared_distance_increases_price_and_time_for_equal_market_prices() -> void:
	var p:=make_profile(); var n:=network(p)
	for town: String in TDSupplierNetwork.TOWNS: p.commerce.state.markets[town].price.salt=100
	var local:=n.quote("chengdu","player_diner",{"salt":1000})
	var near:=n.quote("bangkok","player_diner",{"salt":1000})
	var far:=n.quote("mexico_city","player_diner",{"salt":1000})
	assert_eq(float(local.data.distance),0.0)
	assert_eq(int(local.data.total_cents),100)
	assert_eq(float(local.data.production_seconds),1800.0)
	assert_gt(float(near.data.distance),0.0)
	assert_gt(int(near.data.total_cents),100)
	assert_gt(float(near.data.production_seconds),1800.0)
	assert_gt(int(far.data.total_cents),int(near.data.total_cents))
	assert_gt(float(far.data.production_seconds),float(near.data.production_seconds))
	assert_eq(n.distance("paris","tokyo"),n.distance("tokyo","paris"))

func test_paid_production_reserves_stock_delivers_exact_cost_and_is_idempotent() -> void:
	var p:=make_profile(); var n:=network(p)
	var inventory: int=p.shop.available("tomato"); var money: int=int(p.shop.snapshot().money_cents)
	var stock: int=int(p.commerce.state.markets.chengdu.stock.tomato)
	var basis: int=int(p.commerce.state.cost_stock.get("tomato",{}).get("value_cents",0))
	var quoted:=n.quote("chengdu","player_diner",{"tomato":1500})
	var expense: int=int(quoted.data.total_cents)
	assert_true(n.order("chengdu","player_diner",{"tomato":1500},"paid").ok)
	assert_eq(p.shop.available("tomato"),inventory)
	assert_eq(int(p.shop.snapshot().money_cents),money-expense)
	assert_eq(int(p.commerce.state.markets.chengdu.stock.tomato),stock-1500)
	assert_eq(int(p.commerce.cash_audit(int(p.shop.snapshot().money_cents)).difference_cents),0)
	var after:=p.snapshot(); var saved:=n.snapshot()
	assert_eq(n.order("chengdu","player_diner",{"tomato":1500},"paid").code,"DUPLICATE")
	assert_eq(p.snapshot(),after); assert_eq(n.snapshot(),saved)
	n.advance(1799)
	assert_eq(p.shop.available("tomato"),inventory)
	n.advance(1)
	assert_eq(p.shop.available("tomato"),inventory+1000)
	n.advance(900)
	assert_eq(p.shop.available("tomato"),inventory+1500)
	assert_eq(int(p.commerce.state.cost_stock.tomato.value_cents),basis+expense)
	after=p.snapshot(); n.advance(100000)
	assert_eq(p.snapshot(),after)
	assert_true(n.validate_save(n.snapshot()).ok)

func test_atomic_rejection_for_scarce_market_insufficient_cash_and_invalid_cart() -> void:
	var p:=make_profile(); var n:=network(p)
	p.commerce.state.markets.chengdu.stock.egg=0
	var before:=p.snapshot(); var saved:=n.snapshot()
	assert_eq(n.order("chengdu","player_diner",{"tomato":1000,"egg":1000},"scarce").code,"MARKET_SHORTAGE")
	assert_eq(p.snapshot(),before); assert_eq(n.snapshot(),saved)
	for cart: Dictionary in [{"tomato":0},{"tomato":-1},{"tomato":8001},{"not_food":1000},{"tomato":0.5}]:
		assert_false(n.order("chengdu","player_diner",cart,"invalid").ok)
	assert_eq(p.snapshot(),before)
	assert_true(p.shop.world_adjustment(-int(p.shop.snapshot().money_cents),"empty","fixture").ok)
	before=p.snapshot()
	assert_false(n.order("chengdu","player_diner",{"tomato":1000},"poor").ok)
	assert_eq(p.snapshot(),before); assert_eq(n.snapshot(),saved)

func test_main_delivery_waits_for_boundary_and_open_orders_are_rejected() -> void:
	var p:=make_profile(); var n:=network(p); var units: int=p.shop.available("tomato")
	assert_true(n.order("chengdu","player_diner",{"tomato":1000},"boundary").ok)
	assert_true(p.shop.open_day().ok)
	var before:=p.snapshot()
	assert_eq(n.order("chengdu","player_diner",{"salt":1000},"open-buy").code,"NOT_AT_BOUNDARY")
	assert_eq(p.snapshot(),before)
	n.advance(1800)
	assert_eq(p.shop.available("tomato"),units)
	assert_false(n.state.orders[0].jobs[0].delivered)
	assert_true(p.shop.close_for_night().ok)
	n.advance(0)
	assert_eq(p.shop.available("tomato"),units+1000)
	assert_true(n.state.orders[0].jobs[0].delivered)

func test_branch_destination_inventory_basis_and_paid_ledger_stay_separate() -> void:
	var p:=make_profile(); var id:=branch(p); var n:=network(p)
	var main: int=p.shop.available("tomato")
	var quoted:=n.quote("tokyo",id,{"tomato":1000})
	assert_true(quoted.ok)
	assert_true(n.order("tokyo",id,{"tomato":1000},"branch-order").ok)
	var store: Dictionary=p.branches.state.stores[id]
	assert_eq(int(store.daily.purchase_cents),int(quoted.data.total_cents))
	n.advance(float(quoted.data.production_seconds))
	assert_eq(p.shop.available("tomato"),main)
	assert_eq(int(store.inventory.tomato),1000)
	assert_eq(int(store.basis.tomato.value_cents),int(quoted.data.total_cents))
	assert_eq(int(p.commerce.cash_audit(int(p.shop.snapshot().money_cents)).difference_cents),0)
	var before: Dictionary=store.duplicate(true)
	n.advance(50000)
	assert_eq(store,before)
	var check:=TDSupplierNetwork.new().validate_save(n.snapshot(),p.branches.state.stores,int(p.shop.snapshot().day),p.commerce.costs.keys())
	assert_true(check.ok,check.code)

func test_upgrade_adds_parallel_lines_future_speed_only_and_exact_once_cost() -> void:
	var p:=make_profile(); var n:=network(p)
	assert_true(n.order("chengdu","player_diner",{"tomato":2000},"old-speed").ok)
	var old_seconds: float=n.state.orders[0].jobs[0].seconds
	var before: int=int(p.shop.snapshot().money_cents)
	assert_true(n.upgrade("chengdu","upgrade").ok)
	assert_eq(int(p.shop.snapshot().money_cents),before-3000)
	assert_eq(n.upgrade("chengdu","upgrade").code,"DUPLICATE")
	assert_eq(n.state.orders[0].jobs[0].seconds,old_seconds)
	assert_eq(float(n.catalogue("chengdu").filter(func(x: Dictionary)->bool:return x.id=="tomato")[0].production_seconds),1350.0)
	var units: int=p.shop.available("tomato"); n.advance(1800)
	assert_eq(p.shop.available("tomato"),units+2000)
	assert_eq(int(p.commerce.cash_audit(int(p.shop.snapshot().money_cents)).difference_cents),0)

func test_automation_off_no_repeated_restock_and_no_budget_reset_exploit() -> void:
	var p:=make_profile(); var n:=network(p)
	var before:=p.snapshot(); n.automate()
	assert_eq(p.snapshot(),before)
	assert_true(n.set_automation("player_diner",true,5000).ok)
	n.automate()
	assert_gt(n.state.orders.size(),0)
	assert_lte(int(n.state.automation.player_diner.spent_cents),5000)
	var saved:=n.snapshot(); before=p.snapshot()
	n.automate()
	assert_eq(p.snapshot(),before); assert_eq(n.snapshot(),saved)
	var spent: int=int(n.state.automation.player_diner.spent_cents)
	n.set_automation("player_diner",false,5000); n.set_automation("player_diner",true,5000)
	assert_eq(int(n.state.automation.player_diner.spent_cents),spent)
	n.set_automation("player_diner",true,0); n.automate()
	assert_eq(int(p.shop.snapshot().money_cents),int(before.shop.money_cents))

func test_restore_continues_production_without_repay_and_rejects_unknowns() -> void:
	var p:=make_profile(); var n:=network(p)
	assert_true(n.order("chengdu","player_diner",{"tomato":1000},"resume").ok)
	n.advance(750)
	var saved:=n.snapshot(); var restored:=network(p)
	assert_true(restored.restore(saved).ok)
	var money: int=int(p.shop.snapshot().money_cents); var amount: int=p.shop.available("tomato")
	restored.advance(1050)
	assert_eq(p.shop.available("tomato"),amount+1000)
	assert_eq(int(p.shop.snapshot().money_cents),money)
	# Old producer callback cannot duplicate the target store's persisted receipt.
	n.advance(1050)
	assert_eq(p.shop.available("tomato"),amount+1000)
	for key: String in ["unknown","bad_version","target","item","cost","progress"]:
		var bad:=saved.duplicate(true)
		match key:
			"unknown": bad.extra=true
			"bad_version": bad.schema_version=3
			"target": bad.orders[0].store_id="player-branch:999"
			"item": bad.orders[0].jobs[0].item_id="fake"
			"cost": bad.orders[0].total_cents+=1
			"progress": bad.orders[0].jobs[0].elapsed=1000000
		var previous:=restored.snapshot()
		assert_false(restored.restore(bad).ok,key)
		assert_eq(restored.snapshot(),previous)

func test_legacy_upgrade_migrates_once_without_copying_paid_jobs_or_stock() -> void:
	var p:=make_profile(); var n:=network(p)
	p.world.factory_built["chengdu:fixture"]=true
	p.world.factory_level["chengdu:fixture"]=3
	p.world.factory_built["chengdu:second"]=true
	p.world.factory_level["chengdu:second"]=2
	p.world.factory_jobs["chengdu:fixture"]=[{"qty":2,"unit_elapsed":.25}]
	var world: Dictionary=p.snapshot().world; var shop:=p.shop.snapshot()
	n.migrate_legacy(p.world)
	assert_eq(int(n.state.levels.chengdu),3)
	assert_eq(n.capacity("chengdu"),5)
	assert_true(n.validate_save(n.snapshot()).ok)
	assert_true(n.state.orders.is_empty())
	assert_eq(p.snapshot().world,world); assert_eq(p.shop.snapshot(),shop)
	var saved:=n.snapshot(); n.migrate_legacy(p.world)
	assert_eq(n.snapshot(),saved)

func test_time_partition_and_invalid_elapsed_do_not_change_outcome() -> void:
	var p:=make_profile(); var n:=network(p)
	assert_true(n.order("chengdu","player_diner",{"tomato":1500},"partition").ok)
	var other:=network(p); assert_true(other.restore(n.snapshot()).ok)
	var before:=n.snapshot()
	n.advance(-1); n.advance(NAN); n.advance(INF)
	assert_eq(n.snapshot(),before)
	n.advance(2700)
	for index: int in 27: other.advance(100)
	assert_eq(other.snapshot(),n.snapshot())

func test_branch_automation_uses_its_menu_and_in_transit_without_borrowing() -> void:
	var p:=make_profile(); var id:=branch(p); var n:=network(p)
	var main: Dictionary=p.shop.snapshot().inventory
	assert_true(n.set_automation(id,true,5000).ok)
	n.automate()
	assert_gt(n.state.orders.size(),0)
	for row: Dictionary in n.state.orders: assert_eq(row.store_id,id)
	assert_lte(int(n.state.automation[id].spent_cents),5000)
	var state_before:=n.snapshot(); var shop_before:=p.shop.snapshot()
	n.automate()
	assert_eq(n.snapshot(),state_before); assert_eq(p.shop.snapshot(),shop_before)
	n.advance_game_minutes(20000)
	assert_eq(p.shop.snapshot().inventory,main)
	var primary: String=str(p.branches.state.stores[id].menu[0].ingredients.keys()[0])
	assert_gt(int(p.branches.state.stores[id].inventory.get(primary,0)),0)
	assert_eq(int(p.commerce.cash_audit(int(p.shop.snapshot().money_cents)).difference_cents),0)

func test_config_and_save_reject_unknown_fields_and_unearned_capacity() -> void:
	var n:=TDSupplierNetwork.new()
	var bad:=n.config.duplicate(true); bad.unknown=true
	assert_false(TDSupplierNetwork.validate_config(bad).ok)
	bad=n.config.duplicate(true); bad.towns.paris.local_items.append("salt")
	assert_false(TDSupplierNetwork.validate_config(bad).ok)
	bad=n.snapshot(); bad.legacy_lines.chengdu=3
	assert_false(n.validate_save(bad,{},1,["salt"]).ok)
	bad=n.snapshot(); bad.levels.tokyo=4
	assert_false(n.validate_save(bad).ok)
	bad=n.snapshot(); bad.automation["player-branch:999"]={"enabled":true,"budget_cents":100,"spent_day":0,"spent_cents":0}
	assert_false(n.validate_save(bad).ok)

func test_order_rechecks_current_price_and_stock_instead_of_trusting_prior_quote() -> void:
	var p:=make_profile(); var n:=network(p)
	var first:=n.quote("chengdu","player_diner",{"salt":1000})
	p.commerce.state.markets.chengdu.price.salt=1000
	var cash: int=int(p.shop.snapshot().money_cents)
	assert_true(n.order("chengdu","player_diner",{"salt":1000},"repriced").ok)
	assert_eq(int(p.shop.snapshot().money_cents),cash-1000)
	assert_lt(int(first.data.total_cents),1000)
	assert_true(n.quote("chengdu","player_diner",{"salt":1000}).ok)
	p.commerce.state.markets.chengdu.stock.salt=0
	var before:=p.snapshot(); var orders:=n.snapshot()
	assert_eq(n.order("chengdu","player_diner",{"salt":1000},"sold-out").code,"MARKET_SHORTAGE")
	assert_eq(p.snapshot(),before); assert_eq(n.snapshot(),orders)

func test_both_store_automations_restock_real_chart_condiments() -> void:
	var p:=make_profile(); var id:=branch(p); var n:=network(p)
	var used: Dictionary={}
	for item: String in p.shop.purchase_ids():
		if p.shop.stock_info(item).condiment and p.shop.available(item)>0: used[item]=p.shop.available(item)
	if not used.is_empty(): assert_true(p.shop.consume_materials(p.shop.day_namespace()+"seasoning-fixture",used).ok)
	for store_id: String in ["player_diner",id]:
		var needed:=n._desired(store_id)
		assert_gt(int(needed.get("oil",0)),0,"The real recipe includes cooking oil.")
		assert_gt(int(needed.get("salt",0)),0,"M6 seasoning is part of the actual menu requirement.")
		assert_true(n.set_automation(store_id,true,20000).ok)
	n.automate();n.advance_game_minutes(3000)
	for store_id: String in ["player_diner",id]:
		assert_gt(n._on_hand(store_id,"oil")+n.in_transit(store_id,"oil"),0)
		assert_gt(n._on_hand(store_id,"salt")+n.in_transit(store_id,"salt"),0)
	var orders:=n.snapshot(); n.automate()
	assert_eq(n.snapshot(),orders,"In-flight condiment orders count toward the restock target.")

func test_next_day_sparse_market_statistics_accept_branch_rice_order() -> void:
	var p:=make_profile(); var id:=branch(p); var n:=network(p)
	p.branches.managed=true
	assert_true(p.shop.close_for_night().ok)
	assert_true(p.next_day().ok)
	var market: Dictionary=p.commerce.state.markets.chengdu
	var sold: int=int(market.sold.get("rice",0)); var requested: int=int(market.requested.get("rice",0))
	assert_true(n.order("chengdu",id,{"rice":1000},"day-two-rice").ok)
	assert_eq(int(market.sold.rice),sold+1000)
	assert_eq(int(market.requested.rice),requested+1000)
	n.advance(1800)
	assert_eq(int(p.branches.state.stores[id].inventory.rice),1000)
	assert_true(n.validate_save(n.snapshot()).ok)

func test_closed_profile_rejects_all_stale_supply_mutations_and_delivery() -> void:
	var p:=make_profile(); var n:=network(p)
	assert_true(n.order("chengdu","player_diner",{"tomato":1000},"close-pending").ok)
	assert_true(n.set_automation("player_diner",true,5000).ok)
	p.close()
	var before:=p.snapshot(); var saved:=n.snapshot()
	n.advance(100000); n.automate(); n.migrate_legacy(p.world); n._deliver_ready()
	assert_eq(n.order("chengdu","player_diner",{"salt":1000},"stale-order").code,"STALE_PROFILE")
	assert_eq(n.upgrade("chengdu","stale-upgrade").code,"STALE_PROFILE")
	assert_eq(n.set_automation("player_diner",false,5000).code,"STALE_PROFILE")
	assert_eq(n.restore(saved).code,"STALE_PROFILE")
	assert_eq(n.snapshot(),saved)
	assert_eq(p.snapshot(),before)

func test_branch_supply_automation_respects_smaller_store_budget_and_manual_spend() -> void:
	var p:=make_profile(); var id:=branch(p); var n:=network(p)
	p.branches.state.stores[id].budget_cents=1000
	var quote:=n.quote("chengdu",id,{"salt":1000})
	assert_true(n.order("chengdu",id,{"salt":1000},"manual-before-auto").ok)
	var manual: int=int(quote.data.total_cents)
	assert_true(n.set_automation(id,true,20000).ok)
	n.automate()
	n.advance(1800) # The paid legacy batch releases its capacity first.
	n.advance_game_minutes(300)
	assert_gt(n.state.orders.size(),1,"The budget still allows a real automatic purchase.")
	assert_lte(int(n.state.automation[id].spent_cents),1000-manual)
	assert_lte(int(p.branches.state.stores[id].daily.purchase_cents),1000)
	var saved:=n.snapshot(); var cash: int=int(p.shop.snapshot().money_cents)
	n.automate()
	assert_eq(n.snapshot(),saved); assert_eq(int(p.shop.snapshot().money_cents),cash)

func test_home_pending_includes_legacy_queues_stock_and_paid_trade_without_mutating_them() -> void:
	var p:=make_profile(); var n:=network(p)
	assert_true(p.recommend_route("tokyo","legacy-route-fixture").ok)
	assert_true(p.order_remote("tomato","tokyo",1000,"legacy-paid-shipment").ok)
	assert_true(n.order("chengdu","player_diner",{"tomato":1000},"new-paid-shipment").ok)
	p.world.supply.stock.tomato=2
	p.world.supply.incoming.append({"item_id":"tomato","amount":3,"arrive":2,"ordered_on":1})
	p.world.factory_jobs["chengdu:legacy-array"]=[{"item_id":"tomato","qty":4,"line":1,"unit_hours":.5,"unit_elapsed":0.0,"elapsed_hours":0.0}]
	p.world.factory_jobs["chengdu:legacy-single"]={"item_id":"tomato","qty":1,"line":1,"total_hours":.5,"elapsed_hours":0.0}
	var queues:=p.world.factory_jobs.duplicate(true); var supply:=p.world.supply.duplicate_state(); var shipments: Array=p.commerce.state.shipments.duplicate(true)
	var home_units: int=p.shop.available("tomato")
	assert_eq(n.in_transit("player_diner","tomato"),12000)
	assert_eq(n.in_transit("player-branch:999","tomato"),0,"Main-store legacy entitlements cannot restock branches.")
	assert_eq(n.in_transit("player_diner","unknown"),0)
	assert_eq(p.world.factory_jobs,queues); assert_eq(p.world.supply.duplicate_state(),supply); assert_eq(p.commerce.state.shipments,shipments)
	p.world.tick_factories(1800)
	assert_eq(n.in_transit("player_diner","tomato"),12000,"Finishing old production moves units to stock; it does not duplicate them.")
	p.world.supply.collect(2)
	assert_eq(n.in_transit("player_diner","tomato"),12000)
	assert_true(p.receive_supplies().ok)
	assert_eq(p.shop.available("tomato")+n.in_transit("player_diner","tomato"),home_units+12000)
	assert_eq(n.state.orders.size(),1,"No legacy shipment was copied into the new producer.")

func test_supply_automation_deducts_pending_legacy_food_before_buying_again() -> void:
	var p:=make_profile(); var n:=network(p)
	for item: String in n._desired("player_diner"):
		var missing: int=maxi(0,int(n._desired("player_diner")[item])-p.shop.available(item))
		if missing>0: p.world.supply.incoming.append({"item_id":item,"amount":ceili(float(missing)/1000.0),"arrive":2,"ordered_on":1})
	var before:=p.snapshot(); var old_supply:=p.world.supply.duplicate_state()
	assert_true(n.set_automation("player_diner",true,20000).ok)
	n.automate(); n.automate()
	assert_true(n.state.orders.is_empty(),"Paid legacy food already covers the configured menu target.")
	assert_eq(int(n.state.automation.player_diner.spent_cents),0)
	assert_eq(p.snapshot(),before)
	assert_eq(p.world.supply.duplicate_state(),old_supply)
