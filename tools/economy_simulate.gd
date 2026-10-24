extends SceneTree
## Offline demand/finance test: never fabricates a successful dish or human playtest.
var failures: Array[String]=[]
func _initialize() -> void:
	var content:=TDServiceCatalog.new();check(content.load_file().ok,"content")
	check(TDResearchRuntime.install(content).ok,"research definitions")
	var catalog:=TDTownCatalog.new();check(catalog.load_file().ok,"town catalog")
	var reports: Array=[]
	for scenario: String in ["baseline","supply_shock","expensive_menu","price_war","expansion"]:
		var economy:=TDWorldEconomy.new(content.config.costs,"chengdu",101 if scenario=="baseline" else 2101)
		for town: String in economy.config.active_towns:
			var map:=TDTownMap.new();check(map.build_economic_layout(catalog,TDTownMap.seed_of(town)).ok,"connected commercial region")
			economy.configure_parcels(town,map.plots,map.commercial_parcels())
			if scenario=="expansion":
				for firm: Dictionary in economy.state.competitors[town]: firm.cash_cents=1000000 # Explicit stress fixture.
		var cash: int=30000;economy.attach_cash_baseline(cash)
		var times: Array[float]=[]
		var visitors: int=0;var zeros: int=0;var unmet: int=0;var stores_max: int=15
		var ratio_min: float=100;var ratio_max: float=0;var boundary_hits: int=0;var prior: Dictionary={}
		for day: int in range(1,361):
			if scenario=="supply_shock" and day==60:
				var m: Dictionary=economy.state.markets.bangkok
				m.stock.egg=0;m.opening.egg=int(m.sold.get("egg",0))+int(m.exports.get("egg",0))-int(m.imports.get("egg",0))
			if scenario=="price_war" and day==60:
				for firms: Array in economy.state.competitors.values():
					for firm: Dictionary in firms: firm.price_cents=maxi(500,roundi(float(firm.price_cents)*.65))
			economy.config.opportunities_per_day=66 if scenario=="expansion" and day>=60 and day<=90 else 44
			var tick:=Time.get_ticks_usec()
			economy.begin_day()
			var menu: Array=[{"id":"service.tomato_egg","family_id":"service.tomato_egg","price_cents":1000000 if scenario=="expensive_menu" else 1300,"reference_cents":1300,"culture":"chinese","taste":{"sweet":.4}}]
			for slot: int in int(economy.config.slots_per_day):
				var arrivals:=economy.arrivals(slot,menu,0,3,[{"requirements":[]},{"requirements":[]}],240)
				for arrival: Dictionary in arrivals: economy.society.release(arrival.intent.opportunity_id)
			visitors+=int(economy.state.day_stats.admitted)
			if int(economy.state.day_stats.admitted)==0: zeros+=1
			economy.settle([],0);cash-=economy.pay_debt(cash)
			check(int(economy.cash_audit(cash).difference_cents)==0,"cash:"+scenario+":"+str(day))
			check(int(economy.society.bank.audit().difference_cents)==0,"bank")
			unmet+=int(economy.society.state.daily.unmet_needs_cents)
			var stores: int=0
			for town: String in economy.state.markets:
				var market: Dictionary=economy.state.markets[town]
				for id: String in content.config.costs:
					check(int(market.stock[id])>=0 and int(market.stock[id])<=int(economy.config.market.capacity_units),"stock bounds")
					check(int(market.stock[id])==int(market.opening[id])+int(market.imports.get(id,0))-int(market.exports.get(id,0))-int(market.sold.get(id,0)),"inventory conservation:"+town+":"+id)
					var ratio:=float(market.price[id])/int(content.config.costs[id])
					ratio_min=minf(ratio_min,ratio);ratio_max=maxf(ratio_max,ratio)
					var key:=town+":"+id
					if prior.has(key) and absf(float(market.price[id])/int(prior[key])-1)>=.079: boundary_hits+=1
					prior[key]=int(market.price[id])
				stores+=economy.state.competitors[town].size()
				for firm: Dictionary in economy.state.competitors[town]:
					check(int(firm.cash_cents)>=0 and int(firm.served)<=int(firm.capacity),"finite firm")
			stores_max=maxi(stores_max,stores)
			check(economy.advance_day(day).ok,"advance")
			check(int(economy.cash_audit(cash).difference_cents)==0,"advance cash:"+scenario+":"+str(day))
			times.append(float(Time.get_ticks_usec()-tick)/1000)
			if day%60==0:
				var valid:=economy.validate_save(economy.snapshot())
				check(valid.ok,"validator:"+scenario+":"+str(day)+":"+valid.code)
		times.sort()
		var encoded:=JSON.stringify(economy.snapshot())
		check(encoded.to_utf8_buffer().size()<1000000,"bounded snapshot")
		if scenario=="expensive_menu": check(visitors==0,"zero demand")
		if scenario=="expansion": check(stores_max>15,"expansion occurs")
		var low: int=9223372036854775807;var high: int=0
		for family: Dictionary in economy.society.state.households.values():
			var wealth:=int(family.cash_cents)+int(economy.society.bank.account(family.id).deposit_cents)
			low=mini(low,wealth);high=maxi(high,wealth)
		reports.append({"scenario":scenario,"days":360,"towns":5,"households":economy.society.state.households.size(),"visitors":visitors,"zero_days":zeros,"max_stores":stores_max,"expansions":economy.expansion.state.serial,"unmet_needs_cents":unmet,"wealth_min_cents":low,"wealth_max_cents":high,"daily_price_boundary_hits":boundary_hits,"price_ratio_min":ratio_min,"price_ratio_max":ratio_max,"day_ms_p50":times[179],"day_ms_p95":times[341],"day_ms_max":times.back(),"snapshot_bytes":encoded.to_utf8_buffer().size()})
		print(JSON.stringify(reports.back()))
	var report: Dictionary={"status":"PASS" if failures.is_empty() else "FAIL","engine":Engine.get_version_info().string,"scenarios":reports,"failures":failures,"human_playtest":"PENDING"}
	DirAccess.make_dir_recursive_absolute("res://artifacts/society-simulation")
	var file:=FileAccess.open("res://artifacts/society-simulation/summary.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "));file.close();print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
func check(value: bool, message: String) -> void:
	if not value and failures.size()<40 and message not in failures: failures.append(message)
