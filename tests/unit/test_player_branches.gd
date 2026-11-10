extends GutTest
var profiles: Array[TDGameProfile]=[]
var stores: Array[TDProfileStore]=[]

func make_profile() -> TDGameProfile:
	var p:=TDGameProfile.new(); profiles.append(p)
	assert_true(p.error.ok,p.error.code)
	p.slot_id="slot-01"
	var storage:=TDProfileStore.new("res://artifacts/branch-tests/%d"%Time.get_ticks_usec(),TDGameProfile.validate_save)
	stores.append(storage); p.persistence=storage.save_slot
	assert_true(p.shop.world_adjustment(300000,"fixture","test funding").ok)
	# D063 fixture owns the workers previously implicit in the anonymous crew.
	for person: Dictionary in p.employees.config.templates:
		var copies: int=9 if person.id=="manager.master" else (3 if person.id=="manager.host" else 1)
		p.employees.state.owned[person.id]={"id":person.id,"copies":copies,"xp":0,"assigned":""}
	return p

func after_each() -> void:
	for p: TDGameProfile in profiles: p.close()
	profiles.clear()
	stores.clear()

func open_at(p: TDGameProfile, y: int=48, manager: String="manager.steady") -> String:
	if not p.employees.manager_info(manager).assigned.is_empty(): manager="manager.lan"
	var result:=p.branches.open_store("chengdu",[6,y,3,4],"cn",manager,"open:%d"%y)
	assert_true(result.ok,result.code+": "+result.message)
	var id: String=str(result.data.get("store_id",""))
	if result.ok:
		for role: String in ["cook","waiter"]:
			for person: Dictionary in p.employees.config.templates:
				if person.role==role and p.employees.employee_info(person.id).assigned=="":
					assert_true(p.employees.assign(person.id,id).ok);break
	return id

func new_day(p: TDGameProfile) -> void:
	if p.shop.snapshot().phase=="PREPARE": assert_true(p.shop.close_for_night().ok)
	assert_eq(p.shop.snapshot().phase,"SETTLED")
	assert_true(p.next_day().ok)

func stock(p: TDGameProfile) -> void:
	for store: Dictionary in p.branches.state.stores.values():
		var result:=p.suppliers.order(str(store.town_id),str(store.id),store.menu[0].ingredients,"stock:%s:%d"%[store.id,p.shop.snapshot().day])
		assert_true(result.ok,result.code)
	p.suppliers.advance(100000)

func test_configuration_star_stats_and_costs_increase() -> void:
	var rules:=TDPlayerBranches.new()
	assert_true(rules.error.ok)
	for i: int in 2:
		var a: Dictionary=rules.config.managers[i]; var b: Dictionary=rules.config.managers[i+1]
		for key: String in ["wage_cents","attraction","operations","quality","economy"]: assert_gt(b[key],a[key])
	assert_eq(rules.config.managers[0].service_bonus,0.0)
	assert_gt(rules.config.managers[1].service_bonus,0.0)
	assert_gt(rules.config.managers[2].utility_discount,0.0)
	var bad:=rules.config.duplicate(true); bad.managers[1].id=bad.managers[0].id
	assert_false(TDPlayerBranches.validate_config(bad).ok)

func test_quotes_are_read_only_and_multiple_local_stores_charge_once() -> void:
	var p:=make_profile(); var before:=p.snapshot()
	var quote:=p.branches.quote("chengdu",[6,48,3,4],"cn","manager.steady")
	assert_true(quote.ok,quote.code)
	assert_eq(int(quote.data.opening_cents),30800)
	assert_eq(p.snapshot(),before)
	var first:=open_at(p); var second:=open_at(p,53,"manager.master")
	assert_ne(first,second); assert_eq(p.branches.state.stores.size(),2)
	assert_eq(int(p.shop.snapshot().money_cents),int(before.shop.money_cents)-61600)
	var after:=p.snapshot()
	assert_eq(p.branches.open_store("chengdu",[6,60,3,4],"cn","manager.master","open:48").code,"DUPLICATE")
	assert_eq(p.snapshot(),after)
	assert_eq(p.world.town_map.plots.filter(func(row:Dictionary)->bool:return row.has("branch_id")).size(),2)

func test_illegal_land_missing_manager_or_money_never_partially_changes_state() -> void:
	var p:=make_profile(); var before:=p.snapshot()
	for r: Array in [[19,48,3,4],[53,30,3,4],[70,70,3,4],[6,48,1,4],[8,50,3,4]]:
		assert_false(p.branches.open_store("chengdu",r,"cn","manager.steady","bad"+str(r)).ok,str(r))
	var home: Dictionary=p.world._plot_by_id("player_diner")
	assert_false(p.branches.quote("chengdu",[int(home.x),int(home.y),3,4],"cn").ok)
	var house: Dictionary=p.world.town_map.plots.filter(func(x:Dictionary)->bool:return x.kind=="housing")[0]
	assert_false(p.branches.quote("chengdu",[int(house.x),int(house.y),3,4],"cn").ok)
	assert_eq(p.branches.open_store("chengdu",[6,48,3,4],"cn","missing-manager","no-manager").code,"MANAGER_REQUIRED")
	assert_eq(p.snapshot(),before)
	p.shop.world_adjustment(-int(p.shop.snapshot().money_cents),"fixture-empty","test")
	before=p.snapshot()
	assert_false(p.branches.open_store("chengdu",[6,48,3,4],"cn","manager.steady","no-cash").ok)
	assert_eq(p.snapshot(),before)

func test_town_cuisine_menu_and_overlap_gates() -> void:
	var p:=make_profile()
	assert_ne(p.branches.quote("paris",[6,48,3,4],"cn").code,"TOWN_LOCKED")
	assert_eq(p.branches.quote("london",[6,48,3,4],"cn").code,"TOWN_LOCKED")
	assert_eq(p.branches.quote("chengdu",[6,48,3,4],"jp").code,"CUISINE_LOCKED")
	var id:=open_at(p)
	assert_eq(p.branches.quote("chengdu",[6,50,3,4],"cn").code,"OCCUPIED")
	var before:=p.branches.snapshot()
	assert_false(p.branches.configure_store(id,[{"id":"nonexistent","price_cents":100}],1000).ok)
	assert_false(p.branches.configure_store(id,[],1000).ok)
	assert_false(p.branches.configure_store(id,[{"id":before.stores[id].menu[0].id,"price_cents":0}],1000).ok)
	assert_eq(p.branches.snapshot(),before)

func test_supplier_automation_is_bounded_and_never_takes_home_ingredients() -> void:
	var p:=make_profile(); var id:=open_at(p)
	new_day(p)
	var store: Dictionary=p.branches.state.stores[id]
	var before_home: Dictionary=p.shop.snapshot().inventory
	var price: int=0
	for item: String in store.menu[0].ingredients: price+=TDShopSession.amount_cost(int(store.menu[0].ingredients[item]),int(p.commerce.state.markets.chengdu.price[item]))
	p.branches.configure_store(id,store.menu,price-1)
	var before_money: int=int(p.shop.snapshot().money_cents)
	p.suppliers.set_automation(id,true,price-1);p.suppliers.automate()
	p.branches.prepare()
	assert_true(store.inventory.is_empty())
	assert_lte(before_money-int(p.shop.snapshot().money_cents),price-1,"Per-item production orders stay inside the supply budget")
	assert_gte(int(p.shop.snapshot().money_cents),0)
	assert_eq(p.shop.snapshot().inventory,before_home)
	var snap:=p.snapshot(); p.branches.prepare(); assert_eq(p.snapshot(),snap)

func test_market_shortage_does_not_buy_half_recipe() -> void:
	var p:=make_profile(); var id:=open_at(p); new_day(p)
	var s: Dictionary=p.branches.state.stores[id]
	var material: String=s.menu[0].ingredients.keys()[0]
	p.commerce.state.markets.chengdu.stock[material]=0
	var money: int=int(p.shop.snapshot().money_cents)
	var result:=p.suppliers.order("chengdu",id,s.menu[0].ingredients,"shortage")
	assert_eq(result.code,"MARKET_SHORTAGE")
	assert_true(s.inventory.is_empty()); assert_eq(int(p.shop.snapshot().money_cents),money)

func test_real_market_customer_money_stock_and_book_conserve() -> void:
	var p:=make_profile(); var id:=open_at(p); new_day(p)
	var audit:=p.commerce.cash_audit(int(p.shop.snapshot().money_cents))
	assert_eq(int(audit.difference_cents),0)
	stock(p);p.branches.prepare()
	var s: Dictionary=p.branches.state.stores[id]; var dish: Dictionary=s.menu[0]
	assert_gt(s.inventory.size(),0)
	var family: String=p.commerce.society.identity("chengdu",str(p.commerce.config.groups[0].id),0)
	var before_family: int=int(p.commerce.society.state.households[family].cash_cents)
	var before_cash: int=int(p.shop.snapshot().money_cents)
	assert_true(p.branches.sell(id,dish.id,family))
	assert_eq(int(p.shop.snapshot().money_cents)-before_cash,int(dish.price_cents))
	assert_eq(before_family-int(p.commerce.society.state.households[family].cash_cents),int(dish.price_cents))
	assert_gt(int(s.daily.consumed_cents),0)
	assert_eq(int(p.commerce.cash_audit(int(p.shop.snapshot().money_cents)).difference_cents),0)
	p.branches.settle()
	var d: Dictionary=s.books.back()
	assert_eq(int(d.manager_cents),1800); assert_eq(int(d.crew_cents),5200)
	assert_eq(int(d.profit_cents),int(d.sales_cents)-int(d.consumed_cents)-int(d.spoilage_cents)-int(d.rent_cents)-int(d.utilities_cents)-7000-int(d.tax_cents))
	var before:=p.snapshot(); p.branches.settle(); assert_eq(p.snapshot(),before)
	assert_eq(int(p.commerce.cash_audit(int(p.shop.snapshot().money_cents)).difference_cents),0)

func test_two_stores_share_existing_finite_customer_pool() -> void:
	var p:=make_profile(); var one:=open_at(p); var two:=open_at(p,53)
	new_day(p);stock(p);p.branches.prepare()
	var group: Dictionary=p.commerce.config.groups[0]
	var firms:=p.commerce._firms("chengdu",group)
	assert_true(firms.any(func(f:Dictionary)->bool:return f.id==one))
	assert_true(firms.any(func(f:Dictionary)->bool:return f.id==two))
	var dish:=p.shop.economic_menu(true)
	var with_branches:=TDEconomicDemand.choices(group,firms+[p.commerce.player_store(dish,0,group)],p.commerce.config.outside_utility,p.commerce.config.menu_tau)
	var without_branches:=TDEconomicDemand.choices(group,firms.filter(func(f:Dictionary)->bool:return not str(f.id).begins_with("player-branch:"))+[p.commerce.player_store(dish,0,group)],p.commerce.config.outside_utility,p.commerce.config.menu_tau)
	var chance: float=0; var old_chance: float=0
	for row: Dictionary in with_branches:
		if row.store_id=="player": chance+=float(row.probability)
	for row: Dictionary in without_branches:
		if row.store_id=="player": old_chance+=float(row.probability)
	assert_lt(chance,old_chance)
	assert_true(p.shop.close_for_night().ok)
	var total: int=0
	for s: Dictionary in p.branches.state.stores.values(): total+=int(s.daily.served)
	assert_lte(total,int(p.commerce.config.opportunities_per_day))
	assert_eq(int(p.commerce.state.day_stats.opportunities),int(p.commerce.config.opportunities_per_day))
	assert_eq(p.level_daily_report().data.stores.size(),3)

func test_debt_preserved_and_pause_still_pays_rent_and_manager() -> void:
	var p:=make_profile(); var id:=open_at(p); new_day(p)
	var s: Dictionary=p.branches.state.stores[id]
	p.branches.configure_store(id,s.menu,0,true)
	p.shop.world_adjustment(-int(p.shop.snapshot().money_cents),"empty","test")
	p.branches.settle()
	assert_eq(TDPlayerBranches.debt_total(s),int(s.rent_cents)+7000)
	assert_eq(int(s.daily.utilities_cents),0); assert_eq(int(s.daily.crew_cents),5200)
	var before:=p.branches.snapshot(); p.branches.settle(); assert_eq(p.branches.snapshot(),before)

func test_manager_dimensions_and_specials_change_real_capacity_service_and_utilities() -> void:
	var p:=make_profile(); var a:=open_at(p); var b:=open_at(p,53,"manager.host"); var c:=open_at(p,58,"manager.master")
	new_day(p);stock(p);p.branches.prepare()
	var rows:=p.branches.candidates("chengdu",p.commerce.config.groups[0])
	var values: Dictionary={}
	for row: Dictionary in rows: values[row.id]=row
	assert_gt(int(p.branches.state.stores[c].capacity),int(p.branches.state.stores[a].capacity))
	assert_gt(float(values[b].service),float(values[a].service))
	assert_gt(float(values[c].menu[0].food),float(values[b].menu[0].food))
	p.branches.settle()
	var first: Dictionary=p.branches.state.stores[a].daily; var third: Dictionary=p.branches.state.stores[c].daily
	assert_eq(int(first.manager_cents),1800); assert_eq(int(third.manager_cents),4000)
	assert_eq(int(third.utilities_cents),roundi(float(p.commerce.config.fees.opening_cents)*.85))
	assert_lt(int(third.utilities_cents),int(first.utilities_cents))

func test_old_callbacks_cannot_operate_after_profile_closed() -> void:
	var p:=make_profile(); var id:=open_at(p); var before:=p.snapshot(); p.close()
	assert_false(p.branches.sell(id,"service.tomato_egg","none"))
	p.branches.prepare(); p.branches.settle()
	assert_eq(p.branches.configure_store(id,[],0).code,"NOT_AT_BOUNDARY")
	assert_eq(p.branches.snapshot(),before.branches)

func test_save_reload_three_days_and_corruption_rejected() -> void:
	var p:=make_profile(); var first:=open_at(p); open_at(p,53,"manager.master")
	assert_true(p.save().ok)
	var saved:=p.snapshot()
	var q:=make_profile(); assert_true(q.restore(saved).ok)
	assert_eq(q.branches.snapshot(),p.branches.snapshot())
	for day: int in 3:
		new_day(q)
		assert_true(q.shop.close_for_night().ok)
		var result:=q.save(); assert_true(result.ok,result.code+result.message)
	var money: int=int(q.shop.snapshot().money_cents)
	var before:=q.snapshot(); var another:=make_profile()
	assert_true(another.restore(before).ok)
	another.branches.settle()
	assert_eq(int(another.shop.snapshot().money_cents),money)
	assert_eq(another.branches.snapshot(),q.branches.snapshot())
	var bad:=before.duplicate(true); bad.branches.stores[first].rect=[19,48,3,4]
	assert_false(TDGameProfile.validate_save(bad).ok)
	bad=before.duplicate(true); bad.branches.stores[first].menu[0].ingredients={"tomato":1}
	assert_eq(TDGameProfile.validate_save(bad).code,"INVALID_BRANCH_INGREDIENTS")

func test_legacy_branch_migrates_without_opening_charge_and_keeps_archive() -> void:
	var p:=make_profile()
	assert_true(p.world_transaction(p.world.open_branch_in_town.bind("paris"),"旧分店").ok)
	var raw:=p.snapshot(); raw.schema_version=7; raw.erase("branches")
	var q:=make_profile(); var result:=q.restore(raw)
	assert_true(result.ok,result.code)
	assert_false(q.world.branch_open); assert_eq(q.branches.state.stores.size(),1)
	assert_eq(int(q.shop.snapshot().money_cents),int(raw.shop.money_cents))
	assert_true(q.branches.state.legacy.branch_open)
	assert_true(TDGameProfile.validate_save(q.snapshot()).ok)

func test_corrupt_serial_and_cottage_overlap_reject_whole_restore() -> void:
	var p:=make_profile(); var id:=open_at(p)
	var raw:=p.snapshot(); var previous:=p.snapshot()
	raw.branches.serial=0
	assert_eq(p.restore(raw).code,"INVALID_BRANCH_SERIAL")
	assert_eq(p.snapshot(),previous)
	raw=previous.duplicate(true)
	var cottage: Dictionary=raw.residence.plot
	raw.branches.stores[id].rect=[int(cottage.x),int(cottage.y),3,4]
	assert_eq(p.restore(raw).code,"PROTECTED_BRANCH_GEOMETRY")
	assert_eq(p.snapshot(),previous)
	raw=previous.duplicate(true); raw.branches.stores[id].rect=[6,48,1,1]
	assert_eq(p.restore(raw).code,"INVALID_BRANCH_AREA")
	assert_eq(p.snapshot(),previous)

func test_five_towns_open_trade_locked_and_run_local_business_then_reload() -> void:
	var p:=make_profile()
	assert_eq(p.commerce.state.routes,["chengdu"])
	var research:=p.research.snapshot(); var home_stock: Dictionary=p.shop.snapshot().inventory
	var managers: Array=["manager.steady","manager.host","manager.master","manager.lan","manager.fang"]
	for town: String in TDTravelCatalog.IDS:
		var manager: String=managers[TDTravelCatalog.IDS.find(town)]
		# Find a fixture site; this test targets route independence, not the land formula.
		var rect:=TDRegionMigration.find_site(p.branches.town_map(town),[6,48,3,4])
		print("WORLD_BRANCH_SITE ",town," ",rect)
		assert_false(rect.is_empty(),town)
		var quote:=p.branches.quote(town,rect,"cn",manager)
		assert_true(quote.ok,town+quote.code)
		var result:=p.branches.open_store(town,rect,"cn",manager,"five:"+town)
		assert_true(result.ok,town+result.code)
		if result.ok: assert_true(p.employees.auto_assign(result.data.store_id).ok)
		var map:=TDTravelCatalog.map_for(p,town)
		assert_eq(map.plots.filter(func(row:Dictionary)->bool:return row.get("branch_id")==result.data.get("store_id")).size(),1)
	assert_eq(p.branches.state.stores.size(),5)
	assert_eq(p.commerce.state.routes,["chengdu"]);assert_true(p.commerce.state.route_events.is_empty())
	assert_eq(p.research.snapshot(),research);assert_eq(p.shop.snapshot().inventory,home_stock)
	new_day(p);stock(p);p.branches.prepare()
	for store: Dictionary in p.branches.state.stores.values():
		assert_gt(store.inventory.size(),0,store.town_id+" local procurement")
		assert_gt(int(store.daily.purchase_cents),0)
		var family: String=p.commerce.society.identity(store.town_id,str(p.commerce.config.groups[0].id),0)
		assert_true(p.branches.sell(store.id,store.menu[0].id,family),store.town_id+" real resident payment")
	assert_true(p.shop.close_for_night().ok)
	for store: Dictionary in p.branches.state.stores.values():
		assert_eq(store.books.size(),1)
		assert_gt(int(store.books[0].sales_cents),0)
		assert_gt(int(store.books[0].rent_cents),0)
	assert_eq(int(p.commerce.cash_audit(int(p.shop.snapshot().money_cents)).difference_cents),0)
	assert_true(p.save().ok)
	var disk:=stores[0].load_slot("slot-01");assert_true(disk.ok,disk.code)
	var q:=make_profile();var restored:=q.restore(disk.data);assert_true(restored.ok,restored.code)
	assert_true(TDLevelProgression.same_value(q.branches.snapshot(),p.branches.snapshot()))
	assert_eq(q.commerce.state.routes,["chengdu"])
	var before:=q.snapshot();q.branches.settle()
	for field: String in before:
		assert_true(TDLevelProgression.same_value(q.snapshot()[field],before[field]),"repeated settlement keeps "+field)
