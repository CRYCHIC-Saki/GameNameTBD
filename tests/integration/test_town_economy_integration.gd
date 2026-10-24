extends GutTest

var profiles: Array[TDGameProfile]=[]

func test_all_commercial_doors_connect_to_roads_without_opening_housing() -> void:
	var profile:=make_profile()
	for town: String in profile.commerce.config.active_towns:
		var map:=profile.world.town_map if town==profile.commerce.state.home else TDTownMap.new()
		if town!=profile.commerce.state.home: assert_true(map.build_economic_layout(profile.world.catalog,TDTownMap.seed_of(town)).ok)
		var occupied: Dictionary={}
		for parcel: Dictionary in map.commercial_parcels(): occupied[parcel.id]={"owner_id":"boundary-fixture","store_id":parcel.id}
		assert_true(map.apply_commercial_occupancy(occupied).ok)
		var pending: Array[Vector2i]=[Vector2i(TDTownMap.CENTER,TDTownMap.CENTER)]
		var reached: Dictionary={}
		for entrance: Vector2i in pending: reached[entrance]=true
		var index: int=0
		while index<pending.size():
			var at:=pending[index];index+=1
			for direction: Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
				var next:=at+direction
				if not reached.has(next) and map.is_walkable(next.x,next.y): reached[next]=true;pending.append(next)
		for plot: Dictionary in map.plots:
			if plot.has("economic_parcel_id") or plot.kind=="bank":
				assert_has(reached,Vector2i(plot.approach_x,plot.approach_y),town+":"+str(plot.id))
				assert_false(map.is_walkable(plot.x,plot.y),"Store footprint remains solid")
			if plot.kind in ["housing","factory_lot"]: assert_false(map.is_walkable(plot.x,plot.y),"Protected land unchanged")

func test_paid_thirteen_town_legacy_save_migrates_without_losing_shipments() -> void:
	var old: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/town_economy/profile_v2.json"))
	assert_eq(old.economy.markets.size(),13)
	old.economy.familiarity["local:eu"]=0.72
	var profile:=make_profile()
	var result:=profile.restore(old)
	assert_true(result.ok,result.code)
	if not result.ok: return
	assert_eq(int(profile.commerce.state.schema_version),2)
	assert_eq(profile.commerce.state.markets.size(),5)
	assert_eq(profile.commerce.state.familiarity["local:continental"],0.72)
	assert_eq(profile.commerce.state.familiarity["local:eu"],0.72)
	assert_eq(profile.shop.snapshot(),TDShopSession.normalize_save(old.shop))
	assert_eq(profile.research.snapshot().unlocked,old.research.unlocked)
	assert_eq(profile.commerce.state.shipments,old.economy.shipments)
	assert_true(profile.commerce.state.legacy_archive.markets.has("guangzhou"))
	assert_eq(int(profile.commerce.state.tax_due_cents),0)
	var original_egg: int=profile.shop.available("egg")
	for day: int in range(1,5):
		profile.shop.buy({"egg":1000,"tomato":1000},"fixture:day:%d"%day)
		assert_true(profile.shop.open_day().ok);assert_true(profile.shop.close_early().ok)
		assert_true(profile.next_day().ok)
	assert_eq(profile.shop.available("egg"),original_egg+5000)
	var before:=profile.shop.available("egg");profile.receive_supplies();assert_eq(profile.shop.available("egg"),before)
	assert_true(TDGameProfile.validate_save(profile.snapshot()).ok)

func test_player_bank_tax_save_and_total_cash_conservation() -> void:
	var profile:=make_profile()
	assert_eq(int(profile.commerce.cash_audit(int(profile.shop.snapshot().money_cents)).difference_cents),0)
	assert_true(profile.bank_action("deposit",5000,"bank:test:1").ok)
	assert_true(profile.bank_action("borrow",10000,"bank:test:2").ok)
	var before:=profile.snapshot()
	assert_false(profile.bank_action("borrow",10000,"bank:test:2").ok)
	assert_false(profile.bank_action("withdraw",100000,"bank:test:3").ok)
	assert_eq(profile.snapshot(),before)
	assert_true(profile.buy({"tomato":2000,"egg":2000}).ok)
	assert_eq(int(profile.commerce.cash_audit(int(profile.shop.snapshot().money_cents)).difference_cents),0)
	assert_true(profile.shop.open_day().ok);profile.shop.advance(60)
	profile.shop.close_early()
	for order: Dictionary in profile.shop.active_orders(): profile.shop.cancel_order(order.id)
	profile.shop.advance(.01)
	assert_eq(profile.shop.snapshot().phase,"SETTLED")
	assert_eq(int(profile.commerce.state.books.back().tax_cents),0,"No profit, no profit tax")
	assert_eq(int(profile.commerce.state.books.back().interest_cents),5,"10000 cents * .0005")
	assert_eq(int(profile.commerce.cash_audit(int(profile.shop.snapshot().money_cents)).difference_cents),0)
	var restored:=make_profile();var result:=restored.restore(JSON.parse_string(JSON.stringify(profile.snapshot())))
	assert_true(result.ok,result.code)
	assert_eq(int(restored.commerce.cash_audit(int(restored.shop.snapshot().money_cents)).difference_cents),0)
	assert_true(restored.next_day().ok)
	assert_eq(int(restored.commerce.cash_audit(int(restored.shop.snapshot().money_cents)).difference_cents),0)

func test_commercial_property_protects_housing_and_construction_is_delayed() -> void:
	var profile:=make_profile();var world:=profile.commerce
	var map:=profile.world.town_map
	var old_houses:=map.plots.filter(func(p:Dictionary)->bool:return p.kind=="housing").duplicate(true)
	var old_factory:=map.plots.filter(func(p:Dictionary)->bool:return p.kind in ["factory_lot","supply_factory","diner_lot","player_diner"]).duplicate(true)
	var plots:=world.expansion.candidates("chengdu")
	assert_eq(plots.size(),3)
	var firm: Dictionary=world.state.competitors.chengdu[0]
	# Isolated initial capital scenario, not fake gameplay income.
	firm.cash_cents=1000000
	for day: int in range(1,8): firm.history.append({"day":day,"profit_cents":8000,"cash_flow_cents":8000})
	firm.profitable_reviews=2
	var before:=world.snapshot()
	assert_eq(world.expansion.buy("chengdu","player_diner",1,firm,world.state.competitors.chengdu,world.society,1).code,"PROTECTED_OR_OWNED_PARCEL")
	assert_eq(world.snapshot(),before)
	var bought:=world.expansion.buy("chengdu",plots[0].id,plots[0].version,firm,world.state.competitors.chengdu,world.society,1)
	assert_true(bought.ok)
	assert_eq(world.state.competitors.chengdu.size(),4)
	var branch: Dictionary=world.state.competitors.chengdu.back()
	assert_eq(int(branch.open_day),4)
	assert_eq(branch.status,"construction")
	assert_eq(world.society.staff(branch.id).size(),1)
	assert_false(world._firms("chengdu",world.config.groups[0]).back().open)
	before=world.snapshot()
	assert_false(world.expansion.buy("chengdu",plots[0].id,plots[0].version,firm,world.state.competitors.chengdu,world.society,1).ok)
	assert_eq(world.snapshot(),before)
	assert_true(profile.sync_commercial_map().ok)
	assert_eq(map.plots.filter(func(p:Dictionary)->bool:return p.kind=="housing"),old_houses)
	assert_eq(map.plots.filter(func(p:Dictionary)->bool:return p.kind in ["factory_lot","supply_factory","diner_lot","player_diner"]),old_factory)
	assert_true(map.plots.any(func(p:Dictionary)->bool:return p.get("economic_store","")==branch.id))
	assert_true(TDGameProfile.validate_save(profile.snapshot()).ok)
	var invalid:=profile.snapshot()
	invalid.economy.expansion.parcels.chengdu[plots[0].id].x+=1
	assert_eq(TDGameProfile.validate_save(invalid).code,"INVALID_PROPERTY_GEOMETRY")

func make_profile() -> TDGameProfile:
	var value:=TDGameProfile.new();value.slot_id="slot-01"
	profiles.append(value);assert_true(value.error.ok,value.error.code)
	return value

func after_each() -> void:
	for profile: TDGameProfile in profiles: profile.close()
	profiles.clear()
	await get_tree().process_frame

func test_cash_stock_market_and_route_failure_are_one_transaction() -> void:
	var profile:=make_profile()
	var before:=profile.snapshot()
	assert_false(profile.buy({"tomato":1000,"egg":100000}).ok)
	assert_eq(profile.snapshot(),before)
	var quote:=profile.commerce.quote("chengdu",{"egg":2000})
	assert_true(profile.buy({"egg":2000}).ok)
	assert_eq(int(profile.shop.snapshot().money_cents),int(before.shop.money_cents)-int(quote.data.total_cents))
	assert_eq(int(profile.commerce.state.markets.chengdu.stock.egg),int(before.economy.markets.chengdu.stock.egg)-2000)
	assert_eq(int(profile.commerce.state.cost_stock.egg.value_cents),int(quote.data.total_cents))
	before=profile.snapshot()
	assert_eq(profile.order_remote("egg","tokyo").code,"ROUTE_LOCKED")
	assert_eq(profile.snapshot(),before)
	assert_true(profile.recommend_route("tokyo","story:test:tokyo").ok)
	assert_false(profile.recommend_route("tokyo","story:test:tokyo").ok)
	assert_true(profile.order_remote("egg","tokyo",1000,"test:shipment").ok)
	before=profile.snapshot()
	assert_false(profile.order_remote("egg","tokyo",1000,"test:shipment").ok)
	assert_eq(profile.snapshot(),before)
	assert_true(TDGameProfile.validate_save(before).ok)

func test_zero_customers_utilities_debt_and_income_repayment_are_exact() -> void:
	var profile:=make_profile();var shop:=profile.shop
	assert_true(profile.buy({"egg":1000,"tomato":1000}).ok)
	for id: String in shop.snapshot().menu: assert_true(shop.set_menu(id,shop.is_unlocked(id),1000000).ok)
	assert_eq(shop.visitor_forecast().max_visitors,0)
	assert_true(shop.world_adjustment(-int(shop.snapshot().money_cents),"fixture:no-cash","测试隔离现金条件").ok)
	assert_true(shop.open_day().ok)
	shop.advance(float(shop.catalog.config.settings.day_sec)+1)
	assert_eq(shop.snapshot().phase,"SETTLED")
	assert_true(shop.active_orders().is_empty())
	assert_eq(int(profile.commerce.state.day_stats.admitted),0)
	assert_eq(int(profile.commerce.state.debt_cents),120)
	assert_eq(int(profile.commerce.state.books.back().rent_cents),0)
	var before:=profile.snapshot();assert_false(shop.settle_day().ok);assert_eq(profile.snapshot(),before)
	assert_true(profile.next_day().ok)
	assert_true(shop.world_adjustment(200,"test:income","测试收入").ok)
	assert_eq(int(shop.snapshot().money_cents),80)
	assert_eq(int(profile.commerce.state.debt_cents),0)
	assert_true(TDGameProfile.validate_save(profile.snapshot()).ok)

func test_three_days_arrivals_reviews_and_economy_roundtrip_are_reproducible() -> void:
	var profile:=make_profile();var other:=make_profile()
	assert_true(profile.buy({"egg":20000,"tomato":20000,"oil":4000,"salt":2000,"sugar":2000,"starch":2000}).ok)
	for id: String in profile.shop.snapshot().menu: profile.shop.set_menu(id,id=="service.tomato_egg",1300)
	assert_true(other.restore(profile.snapshot()).ok)
	var admitted: int=0
	for day: int in range(1,4):
		for value: TDGameProfile in [profile,other]:
			assert_true(value.shop.open_day().ok)
		profile.shop.advance(300)
		for i: int in 300: other.shop.advance(1)
		assert_eq(profile.commerce.snapshot(),other.commerce.snapshot(),"No dependence on frame batching")
		admitted+=int(profile.commerce.state.day_stats.admitted)
		for value: TDGameProfile in [profile,other]:
			value.shop.close_early()
			for order: Dictionary in value.shop.active_orders():
				assert_true(value.shop.cancel_order(order.id).ok)
				var snapshot:=value.commerce.snapshot()
				assert_false(value.shop.cancel_order(order.id).ok)
				assert_eq(value.commerce.snapshot(),snapshot)
			value.shop.advance(.01)
			var restored:=make_profile()
			assert_true(restored.restore(JSON.parse_string(JSON.stringify(value.snapshot()))).ok)
			assert_eq(JSON.parse_string(JSON.stringify(restored.commerce.snapshot())),JSON.parse_string(JSON.stringify(value.commerce.snapshot())))
			assert_true(value.next_day().ok)
	assert_eq(int(profile.shop.snapshot().day),4)
	assert_gt(admitted,0,"This seeded three-day scenario exercises real customers; any one day may have zero.")

func test_v1_migration_keeps_cash_and_research_without_retrospective_fees() -> void:
	var profile:=make_profile();assert_true(profile.buy({"tomato":2000}).ok)
	var old:=profile.snapshot();old.schema_version=1;old.erase("economy")
	var restored:=make_profile();assert_true(restored.restore(old).ok)
	assert_eq(restored.shop.snapshot(),profile.shop.snapshot())
	assert_eq(restored.research.snapshot(),profile.research.snapshot())
	assert_eq(int(restored.commerce.state.debt_cents),0)
	assert_true(restored.commerce.state.books.is_empty())
	assert_eq(int(restored.snapshot().schema_version),2)
	var corrupt:=restored.snapshot();corrupt.economy.competitors.chengdu[0].erase("ingredients")
	var before:=restored.snapshot();assert_false(restored.restore(corrupt).ok);assert_eq(restored.snapshot(),before)

func test_real_town_factory_panel_pays_formal_wallet_and_keeps_cost_basis() -> void:
	var profile:=make_profile()
	var plots: Array=profile.world.town_map.plots.filter(func(p:Dictionary)->bool:return p.kind=="factory_lot" and p.supply=="vegetable")
	if plots.is_empty():
		plots=profile.world.town_map.plots.filter(func(p:Dictionary)->bool:return p.kind=="factory_lot")
	assert_gt(plots.size(),0)
	if plots.is_empty(): return
	var plot: Dictionary=plots[0]
	assert_true(profile.world.build_factory(plot.id).ok)
	var products: Array=TDTownMap.products_of(plot.supply)
	var id: String=products[0].id
	var town:=TDTownWorld.new();town.session=profile.world;town.transaction_sink=profile.world_transaction;town.external_factory_clock=true
	town.balance_reader=func()->int:return int(profile.shop.snapshot().money_cents)
	add_child_autofree(town)
	await get_tree().process_frame
	town._open_factory_panel(profile.world._plot_by_id(plot.id))
	town._factory_plot=plot.id;town._qty_item=id;town._qty_count=1;town._qty_line=1
	var money:int=profile.shop.snapshot().money_cents
	town._confirm_factory_qty()
	assert_eq(int(profile.shop.snapshot().money_cents),money-profile.world.factory_quote(id)*100)
	assert_eq(town._factory_cash.text,"¥%.2f"%(float(profile.shop.snapshot().money_cents)/100))
	if profile.service.config.costs.has(id):
		assert_eq(int(profile.commerce.state.factory_costs[id].value_cents),profile.world.factory_quote(id)*100)
	# The previous factory release also accepted a single-job dictionary in old saves.
	var key: String=profile.world.factory_jobs.keys()[0]
	profile.world.factory_jobs[key]=profile.world.factory_jobs[key][0].duplicate(true)
	assert_true(profile.world_transaction(profile.world.upgrade_factory.bind(plot.id),"工厂升级").ok)
	assert_true(profile.world_transaction(profile.world.produce_factory.bind(plot.id,id,1,2),"工厂生产").ok)
	profile.world.tick_factories(100000)
	assert_true(profile.receive_supplies().ok)
	if profile.service.config.costs.has(id):
		assert_eq(int(profile.commerce.state.cost_stock[id].value_cents),profile.world.factory_quote(id)*200)
		assert_eq(int(profile.commerce.state.factory_costs[id].value_cents),0)
	assert_true(TDGameProfile.validate_save(profile.snapshot()).ok)
	town.close()

func test_factory_clock_freezes_in_pause_and_research_overlay() -> void:
	var shell:=TDGameShell.new()
	shell.profile_root="res://artifacts/economy-clock/%d"%Time.get_ticks_usec()
	shell.preferences_path=shell.profile_root+"/settings.json"
	add_child_autofree(shell)
	assert_true(shell.create_game("slot-01","时钟测试").ok)
	var world:=shell.profile.world
	var plot: Dictionary=world.town_map.plots.filter(func(p:Dictionary)->bool:return p.kind=="factory_lot")[0]
	assert_true(world.build_factory(plot.id).ok)
	var id: String=TDTownMap.products_of(plot.supply)[0].id
	assert_true(shell.profile.world_transaction(world.produce_factory.bind(plot.id,id,1,1),"工厂生产").ok)
	shell._process(.01)
	var active:=world.factory_jobs.duplicate(true)
	shell.show_pause();shell._process(10)
	assert_eq(world.factory_jobs,active)
	shell._close_dialog();shell.open_atlas();shell._process(10)
	assert_eq(world.factory_jobs,active,"Research temporarily unpauses its own scene, not the background factory")
	shell.close_atlas();shell._process(.01)
	assert_ne(world.factory_jobs,active)
	shell.go_title();get_tree().paused=false
