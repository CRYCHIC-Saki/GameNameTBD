class_name TDWorldEconomy
extends RefCounted
## One save slot's economy. Shop owns player cash/food; this owns markets and NPC firms.
## No Node, wall clock, process loop, or hidden runtime singleton.
const SOURCE := "res://content/town_economy/economy.json"
var config: Dictionary = {}
var costs: Dictionary = {}
var state: Dictionary = {}
var geography := TDEconomicGeography.new()
var error := TDOutcome.new(true)
var society: TDCommunitySociety
var expansion: TDBusinessExpansion
var _daily_interest: Dictionary = {}
## Negative means "not set": player_store keeps map attractiveness. The live shell writes layout effect.
var interior_effect: float = -1.0
const SOCIETY_FIELDS: Array[String] = ["society","expansion","legacy_archive","tax_due_cents","today_interest_cents"]
const FIRM_FIELDS: Array[String] = ["owner_id","name","parcel_id","capacity","open_day","status","cost_basis","consumed_cents","wage_expense_cents","tax_cents","tax_due_cents","profitable_reviews","last_profit_cents","travel_minutes","basket_index"]

func _init(base_costs: Dictionary = {}, home: String = "chengdu", seed_value: int = 101, day: int = 1) -> void:
	var parser := JSON.new()
	var file := FileAccess.open(SOURCE, FileAccess.READ)
	if file == null or parser.parse(file.get_as_text()) != OK:
		error=TDOutcome.new(false,"ECONOMY_CONFIG_FAILED");return
	config=parser.data
	error=validate_config(config)
	if not error.ok: return
	costs=base_costs.duplicate(true)
	if home not in config.active_towns: home="chengdu"
	society=TDCommunitySociety.new(config,config.active_towns,config.groups,day)
	expansion=TDBusinessExpansion.new(config.expansion)
	state={"schema_version":1,"day":day,"seed":seed_value,"home":home,"routes":[home],"route_events":{},"markets":{},"competitors":{},"shipments":[],"shipping_serial":0,"debt_cents":0,"lease":{"parcel_id":"player_diner","owned":true,"daily_cents":0,"through_day":2147483647},"reputation":{},"awareness":0.35,"brand":0.3,"popularity":50.0,"familiarity":{},"food_memory":{},"residents":{},"books":[],"day_stats":{},"cost_stock":{},"cost_consumed":0,"cost_cursor":0,"last_settled_day":day-1,"last_operated_day":0,"economy_open":false,"cells":{}}
	for id: String in config.initial_routes:
		if id not in state.routes and state.routes.size()<3: state.routes.append(id)
	for group: Dictionary in config.groups: state.reputation[group.id]={"food":[0.0,0.0],"service":[0.0,0.0],"value":[0.0,0.0]}
	for town: String in config.active_towns:
		var market: Dictionary={"stock":{},"price":{},"premium":{},"requested":{},"sold":{},"produced":{},"imports":{},"exports":{},"spoilage":{},"opening":{}}
		for item: String in costs:
			market.stock[item]=int(config.market.initial_units)
			market.price[item]=maxi(1,roundi(float(costs[item])*source_factor(town,item)))
			market.premium[item]=0.0;market.requested[item]=0;market.sold[item]=0
		market.opening=market.stock.duplicate(true)
		state.markets[town]=market
		var firms: Array=[]
		for i: int in int(config.npc.stores_per_town):
			firms.append({"id":"npc-store:%s:%d"%[town,i],"cash_cents":int(config.npc.initial_cash_cents),"debt_cents":0,"inventory":{},"price_cents":1100+i*400,"reference_cents":1100+i*400,"served":0,"last_served":0,"receipts_cents":0,"purchase_cents":0,"paid_fixed_cents":0,"quality":0.60+i*0.06,"awareness":0.45,"brand":0.3,"history":[],"recipe_id":"npc.meal.%d"%i,"ingredients":_npc_basket(i),"family_id":"npc.meal.%d"%i})
		state.competitors[town]=firms
		for index: int in firms.size():
			decorate_firm(firms[index],index,day)
			society.hire(firms[index].id,town,1,int(config.society.npc_wage_cents))
	state.schema_version=2;state.society=society.state;state.expansion=expansion.state
	state.legacy_archive={};state.tax_due_cents=0;state.today_interest_cents=0
	_reset_day()
	_stock_competitors()
	state.factory_costs={}

func decorate_firm(firm: Dictionary, index: int, day: int) -> void:
	firm.merge({"owner_id":str(firm.id),"name":"街坊食堂%d"%(index+1),"parcel_id":"","capacity":int(config.npc.capacity_per_day),"open_day":day,"status":"open","cost_basis":{},"consumed_cents":0,"wage_expense_cents":0,"tax_cents":0,"tax_due_cents":0,"profitable_reviews":0,"last_profit_cents":0,"travel_minutes":4.0+2*index,"basket_index":index},false)

func attach_cash_baseline(player_cash: int) -> void:
	if society.state.baseline_attached: return
	society.state.initial_cash_cents=society.cash_total()+firm_cash()+player_cash
	society.state.external_net_cents=0;society.state.baseline_attached=true

func firm_cash() -> int:
	var total: int=0
	for firms: Array in state.competitors.values():
		for firm: Dictionary in firms: total+=int(firm.cash_cents)
	return total

func cash_audit(player_cash: int) -> Dictionary:
	var actual:=society.cash_total()+firm_cash()+player_cash
	var expected:=int(society.state.initial_cash_cents)+int(society.state.external_net_cents)
	return {"actual_cents":actual,"expected_cents":expected,"difference_cents":actual-expected,"bank_difference_cents":int(society.bank.audit().difference_cents)}

func configure_parcels(town: String, plots: Array, parcels: Array) -> TDOutcome:
	if town not in config.active_towns: return TDOutcome.new(false,"UNKNOWN_TOWN")
	var view:=TDEconomicGeography.new();view.configure(town,plots,state.cells)
	return expansion.register(town,parcels,view,state.competitors[town])

static func validate_config(raw: Variant) -> TDOutcome:
	if not raw is Dictionary or raw.get("schema_version")!=1: return TDOutcome.new(false,"INVALID_ECONOMY_CONFIG")
	for field: String in ["market","fees","npc"]:
		if not raw.get(field) is Dictionary: return TDOutcome.new(false,"INVALID_ECONOMY_CONFIG",field)
	var required: Dictionary={"market":["initial_units","production_units","capacity_units","background_need_units","reversion","gap_response","max_daily_change","max_premium","freight_cents_per_portion","route_capacity_units","max_lead_days"],"fees":["opening_cents","guest_cents","cooking_second_cents"],"npc":["stores_per_town","initial_cash_cents","target_portions","capacity_per_day","daily_fixed_cents","weekly_price_limit"]}
	for section: String in required:
		for key: String in required[section]:
			if not raw[section].has(key): return TDOutcome.new(false,"MISSING_ECONOMY_PARAMETER",section+"."+key)
	if not raw.get("active_towns") is Array or raw.active_towns.is_empty() or raw.active_towns.size()>64 or not raw.get("initial_routes") is Array: return TDOutcome.new(false,"INVALID_ECONOMY_TOWNS")
	var seen: Dictionary={}
	for id: Variant in raw.active_towns:
		if not id is String or not raw.get("towns",{}).has(id) or seen.has(id): return TDOutcome.new(false,"INVALID_ECONOMY_TOWNS")
		seen[id]=true
	if seen.size()!=5: return TDOutcome.new(false,"FIVE_TOWNS_REQUIRED")
	var cuisines: Dictionary={}
	for town: String in raw.towns:
		var row: Variant=raw.towns[town]
		if not row is Dictionary or row.get("cuisine_id") not in ["cn","eu","jp","sea","lat"] or cuisines.has(row.cuisine_id): return TDOutcome.new(false,"INVALID_CUISINE_TOWN")
		for field: String in ["name","culture","source_id"]:
			if not row.get(field) is String or row[field].is_empty(): return TDOutcome.new(false,"INVALID_CUISINE_TOWN")
		cuisines[row.cuisine_id]=town
	for section: String in ["bank","society","expansion"]:
		if not raw.get(section) is Dictionary: return TDOutcome.new(false,"MISSING_SOCIAL_CONFIG")
		for key: String in raw[section]:
			if not TDServiceCatalog.integer(raw[section][key],0,100000000): return TDOutcome.new(false,"INVALID_SOCIAL_CONFIG",key)
	var required_social: Dictionary={"bank":["reserve_cents","reserve_floor_cents","loan_limit_cents","term_days","loan_daily_bps","deposit_daily_bps"],"society":["families_per_group","starting_cash_days","wage_budget_bps","necessities_wage_bps","income_tax_bps","daily_wage_allowance_cents","profit_tax_bps","savings_cash_days","npc_wage_cents"],"expansion":["parcels_per_town","max_stores_per_owner","review_days","profitable_reviews","horizon_days","construction_days","construction_cents","working_cash_days","store_capacity","staff_per_store"]}
	for section: String in required_social:
		for key: String in required_social[section]:
			if not raw[section].has(key): return TDOutcome.new(false,"MISSING_SOCIAL_CONFIG",key)
	if int(raw.society.families_per_group)<1 or int(raw.society.families_per_group)>64 or int(raw.expansion.review_days)<1 or int(raw.bank.term_days)<1 or int(raw.expansion.max_stores_per_owner)<1 or int(raw.expansion.max_stores_per_owner)>4 or int(raw.expansion.staff_per_store)<1: return TDOutcome.new(false,"INVALID_SOCIAL_CONFIG")
	if int(raw.society.profit_tax_bps)>10000 or int(raw.society.income_tax_bps)>10000 or int(raw.bank.deposit_daily_bps)>int(raw.bank.loan_daily_bps) or int(raw.bank.reserve_floor_cents)>int(raw.bank.reserve_cents): return TDOutcome.new(false,"INVALID_SOCIAL_CONFIG")
	for id: Variant in raw.initial_routes:
		if not seen.has(id): return TDOutcome.new(false,"INVALID_ECONOMY_ROUTES")
	for field: String in ["opportunities_per_day","slots_per_day","game_minutes_per_day"]:
		if not TDServiceCatalog.integer(raw.get(field),1,2000): return TDOutcome.new(false,"INVALID_ECONOMY_SCALE")
	if not TDEconomicCustomer.finite_range(raw.get("menu_tau"),0.1,1) or not TDEconomicCustomer.finite_range(raw.get("outside_utility"),-20,20): return TDOutcome.new(false,"INVALID_ECONOMY_SCALE")
	if not TDEconomicCustomer.finite_range(raw.get("prior_strength"),1,100) or not TDEconomicCustomer.finite_range(raw.get("prior_score"),0,1): return TDOutcome.new(false,"INVALID_ECONOMY_SCALE")
	if not raw.get("groups") is Array or raw.groups.is_empty() or raw.groups.size()>16: return TDOutcome.new(false,"INVALID_ECONOMY_GROUP")
	var shares: float=0.0;seen={}
	for group: Variant in raw.groups:
		if not group is Dictionary or not group.get("id") is String or seen.has(group.id): return TDOutcome.new(false,"INVALID_ECONOMY_GROUP")
		if not group.get("name") is String or group.name.is_empty(): return TDOutcome.new(false,"INVALID_ECONOMY_GROUP")
		seen[group.id]=true
		for key: String in ["share","price_weight","food_weight","travel_weight","wait_weight","patience_scale"]:
			if not TDEconomicCustomer.finite_range(group.get(key),0,10): return TDOutcome.new(false,"INVALID_ECONOMY_GROUP",key)
		if not TDEconomicCustomer.finite_range(group.get("culture_weight"),-10,10) or not TDServiceCatalog.integer(group.get("budget_cents"),1,1000000) or not TDServiceCatalog.integer(group.get("hard_budget_cents"),int(group.budget_cents),1000000): return TDOutcome.new(false,"INVALID_ECONOMY_GROUP")
		if group.get("preferred_taste") not in TDEconomicCustomer.TASTES or not TDServiceCatalog.integer(group.get("customer_template"),0,1): return TDOutcome.new(false,"INVALID_ECONOMY_GROUP")
		shares+=float(group.share)
	if absf(shares-1)>0.00001: return TDOutcome.new(false,"INVALID_GROUP_SHARES")
	for field: String in ["market","fees","npc"]:
		for key: Variant in raw[field]:
			if not TDEconomicCustomer.finite_range(raw[field][key],0,100000000): return TDOutcome.new(false,"INVALID_ECONOMY_PARAMETER",str(key))
	if int(raw.market.production_units)<=0 or int(raw.market.initial_units)<=0 or int(raw.market.capacity_units)<int(raw.market.initial_units) or not TDServiceCatalog.integer(raw.market.max_lead_days,1,30) or not TDServiceCatalog.integer(raw.npc.stores_per_town,1,16): return TDOutcome.new(false,"INVALID_ECONOMY_PARAMETER")
	for key: String in ["reversion","gap_response","max_daily_change","max_premium"]:
		if float(raw.market[key])>1: return TDOutcome.new(false,"INVALID_ECONOMY_PARAMETER",key)
	if float(raw.npc.weekly_price_limit)>0.2: return TDOutcome.new(false,"INVALID_ECONOMY_PARAMETER")
	return TDOutcome.new(true,"VALID_CONFIG")

func unit(key: String) -> float:
	# Adjacent text hashes are correlated; use a locally seeded generator to mix them.
	# Each purpose has its own key, so previews/rendering never consume gameplay RNG.
	var random:=RandomNumberGenerator.new()
	random.seed=(str(state.seed)+":"+key).hash()
	return random.randf()

func source_factor(town: String, item: String) -> float:
	# Fictional explicit seed-based production variation, never inferred from a real city's income.
	return 0.78+float((town+":"+item).hash()%45)/100.0

func snapshot() -> Dictionary:
	return state.duplicate(true)

func attach_map(plots: Array) -> void:
	geography.configure(state.home,plots,state.cells)

func configure_cell(raw: Dictionary) -> TDOutcome:
	var checked:=TDEconomicCell.validate(raw)
	if not checked.ok: return checked
	if raw.town_id not in config.active_towns: return TDOutcome.new(false,"UNKNOWN_TOWN")
	if state.economy_open: return TDOutcome.new(false,"NOT_AT_BOUNDARY")
	state.cells[raw.id]=raw.duplicate(true)
	geography.configure(state.home,geography._plots,state.cells)
	return TDOutcome.new(true,"CELL_UPDATED")

func reputation(group: String, channel: String) -> float:
	var evidence: Array=state.reputation[group][channel]
	return (float(config.prior_strength)*float(config.prior_score)+float(evidence[0]))/(float(config.prior_strength)+float(evidence[0])+float(evidence[1]))

func routes() -> Array:
	var result: Array=[]
	for town: String in config.active_towns:
		result.append({"town_id":town,"open":town in state.routes,"lead_days":lead_days(town),"capacity_units":int(config.market.route_capacity_units),"freight_cents_per_portion":freight(town)})
	return result

func open_route(town: String, event_id: String) -> TDOutcome:
	if town not in config.active_towns or event_id.is_empty(): return TDOutcome.new(false,"INVALID_ROUTE_EVENT")
	if state.route_events.has(event_id): return TDOutcome.new(false,"DUPLICATE")
	state.route_events[event_id]=town
	if town not in state.routes: state.routes.append(town)
	return TDOutcome.new(true,"ROUTE_OPENED")

func lead_days(town: String) -> int:
	return 0 if town==state.home else 1+int((town+state.home).hash()%int(config.market.max_lead_days))

func freight(town: String) -> int:
	return int(config.market.freight_cents_per_portion)*lead_days(town)

func quote(town: String, cart: Dictionary) -> TDOutcome:
	if town not in state.routes: return TDOutcome.new(false,"ROUTE_LOCKED","这条商路尚未收到推荐。")
	if cart.is_empty(): return TDOutcome.new(false,"EMPTY_CART")
	var rows: Dictionary={};var total: int=0;var units: int=0;var freight_total: int=0
	for item: Variant in cart:
		if not costs.has(item) or not TDServiceCatalog.integer(cart[item],1,100000): return TDOutcome.new(false,"INVALID_QUANTITY")
		if int(cart[item])>int(state.markets[town].stock[item]): return TDOutcome.new(false,"MARKET_SOLD_OUT","供应地现货不足，本次未扣款。")
		var product_cost := roundi(float(cart[item])*int(state.markets[town].price[item])/1000.0)
		var shipping_cost := roundi(float(cart[item])*freight(town)/1000.0)
		rows[item]={"units":int(cart[item]),"goods_cents":product_cost,"freight_cents":shipping_cost,"price_cents":int(state.markets[town].price[item])}
		total+=product_cost+shipping_cost;freight_total+=shipping_cost;units+=int(cart[item])
	var booked: int=0
	for shipment: Dictionary in state.shipments:
		if shipment.source==town and int(shipment.ordered_day)==int(state.day): booked+=int(shipment.units)
	if town!=state.home and booked+units>int(config.market.route_capacity_units): return TDOutcome.new(false,"ROUTE_CAPACITY","今天这条商路的运力不足。")
	return TDOutcome.new(true,"QUOTED","",{"quote_id":"%d:%s:%d"%[state.day,town,state.shipping_serial+1],"day":int(state.day),"source":town,"destination":state.home,"arrival_day":int(state.day)+lead_days(town),"rows":rows,"units":units,"total_cents":total,"freight_cents":freight_total})

func commit_quote(value: Dictionary, token: String) -> TDOutcome:
	if token.is_empty() or state.shipments.any(func(s:Dictionary)->bool:return s.id==token): return TDOutcome.new(false,"DUPLICATE")
	var cart: Dictionary={}
	for item: String in value.get("rows",{}): cart[item]=value.rows[item].units
	var current:=quote(str(value.get("source","")),cart)
	if not current.ok or current.data!=value: return TDOutcome.new(false,"STALE_QUOTE")
	for item: String in cart:
		state.markets[value.source].stock[item]-=int(cart[item])
		state.markets[value.source].sold[item]=int(state.markets[value.source].sold.get(item,0))+int(cart[item])
		state.markets[value.source].requested[item]=int(state.markets[value.source].requested.get(item,0))+int(cart[item])
	state.shipping_serial+=1
	var shipment:=value.duplicate(true)
	shipment.id=token;shipment.delivered=false;shipment.ordered_day=int(state.day)
	state.shipments.append(shipment)
	return TDOutcome.new(true,"ORDERED","",shipment.duplicate(true))

func due_shipments() -> Array:
	return state.shipments.filter(func(s:Dictionary)->bool:return not s.delivered and int(s.arrival_day)<=int(state.day)).duplicate(true)

func mark_delivered(id: String) -> void:
	for shipment: Dictionary in state.shipments:
		if shipment.id==id: shipment.delivered=true

func _npc_basket(index: int) -> Dictionary:
	var baskets: Array=[{"tomato":1000,"egg":1000},{"noodles":1000,"beef":500},{"tofu":1000,"bean_paste":200}]
	var result: Dictionary={}
	for id: String in baskets[index%baskets.size()]:
		if costs.has(id): result[id]=baskets[index%baskets.size()][id]
	return result

func _stock_competitors() -> void:
	for town: String in state.markets:
		var market: Dictionary=state.markets[town]
		for firm: Dictionary in state.competitors[town]:
			firm.served=0;firm.receipts_cents=0;firm.purchase_cents=0;firm.paid_fixed_cents=0
			firm.consumed_cents=0;firm.wage_expense_cents=0;firm.tax_cents=0
			if int(firm.open_day)>int(state.day): continue
			firm.status="open"
			_finance_firm(firm)
			for item: String in firm.ingredients:
				var desired:=maxi(0,int(config.npc.target_portions)*int(firm.ingredients[item])-int(firm.inventory.get(item,0)))
				var affordable:=floori(float(firm.cash_cents)*1000/maxi(1,int(market.price[item])))
				var request:=mini(desired,affordable)
				market.requested[item]=int(market.requested.get(item,0))+request
				var quantity:=mini(request,int(market.stock[item]))
				var cost:=roundi(float(quantity)*int(market.price[item])/1000.0)
				firm.cash_cents-=cost;firm.purchase_cents+=cost;market.stock[item]-=quantity
				society.state.sectors.market+=cost
				var basis: Dictionary=firm.cost_basis.get(item,{"units":0,"value_cents":0})
				basis.units+=quantity;basis.value_cents+=cost;firm.cost_basis[item]=basis
				market.sold[item]=int(market.sold.get(item,0))+quantity
				firm.inventory[item]=int(firm.inventory.get(item,0))+quantity

func _finance_firm(firm: Dictionary) -> void:
	var bank:=society.bank
	var saving: int=int(bank.account(firm.id).deposit_cents)
	var need:=maxi(0,25000-int(firm.cash_cents))
	var amount:=mini(need,mini(saving,int(bank.state.reserve_cents)))
	if amount>0:
		var withdrawn:=bank.transact(firm.id,"withdraw",amount,int(firm.cash_cents),int(state.day),"npc:withdraw:%s:%d"%[firm.id,state.day],true)
		if withdrawn.ok: firm.cash_cents+=int(withdrawn.data.cash_delta_cents)
	if int(firm.cash_cents)<15000 and int(firm.last_profit_cents)>0 and firm.history.size()>=7:
		var loan:=bank.transact(firm.id,"borrow",15000-int(firm.cash_cents),int(firm.cash_cents),int(state.day),"npc:borrow:%s:%d"%[firm.id,state.day],true)
		if loan.ok: firm.cash_cents+=int(loan.data.cash_delta_cents)

func _reset_day() -> void:
	state.day_stats={"opportunities":0,"outside":0,"competitor":0,"considered":0,"admitted":0,"capacity_rejected":0,"completed":0,"abandoned":0,"slot":-1,"cooking_seconds":0.0,"reviews":{},"arrivals":[],"npc_finished":false}
	state.cost_consumed=0;state.economy_open=false

func customer(group: Dictionary, index: int, templates: Array) -> TDEconomicCustomer:
	var tastes: Dictionary={}
	for taste: String in TDEconomicCustomer.TASTES: tastes[taste]=[35.0,55.0,35.0,20.0] if taste==group.preferred_taste else [15.0,20.0,15.0,10.0]
	var template: Dictionary=templates[int(group.customer_template)%templates.size()]
	var family:=society.identity(state.home,group.id,index)
	var budget:=spending_group(group,state.home,index)
	return TDEconomicCustomer.new({"schema_version":1,"id":"resident:%s:%s:%d"%[state.home,group.id,index%int(config.society.families_per_group)],"household_id":family,"group_id":group.id,"home_town_id":state.home,"origin_id":["residential","station","market"][index%3],"budget_cents":int(budget.budget_cents),"hard_budget_cents":int(budget.hard_budget_cents),"taste":tastes,"familiarity":{"chinese":float(state.familiarity.get(group.id,0.7))},"declared_requirements":template.requirements})

func spending_group(group: Dictionary, town: String, index: int) -> Dictionary:
	var result:=group.duplicate(true)
	var cash:=society.available(society.identity(town,group.id,index))
	result.hard_budget_cents=maxi(1,mini(cash,int(group.hard_budget_cents)))
	result.budget_cents=maxi(1,mini(int(result.hard_budget_cents),int(group.budget_cents)))
	return result

func _group(index: int) -> Dictionary:
	var value:=float(index%100)/100.0
	for group: Dictionary in config.groups:
		value-=float(group.share)
		if value<0: return group
	return config.groups.back()

func _firms(town: String, group: Dictionary) -> Array:
	var result: Array=[]
	for firm: Dictionary in state.competitors[town]:
		var enough: bool=not firm.ingredients.is_empty()
		for item: String in firm.ingredients:
			if int(firm.inventory.get(item,0))<int(firm.ingredients[item]): enough=false
		result.append({"id":firm.id,"open":enough and firm.status=="open" and society.staff(firm.id).size()>=int(config.expansion.staff_per_store) and int(firm.served)<int(firm.capacity),"visibility":0.45,"awareness":firm.awareness,"brand":firm.brand,"service":0.65,"travel_minutes":float(firm.travel_minutes),"wait_minutes":float(firm.served)*0.3,"decor_match":0.25,"menu":[{"id":firm.recipe_id,"family_id":firm.family_id,"price_cents":int(firm.price_cents),"reference_cents":int(firm.reference_cents),"food":firm.quality,"familiarity":0.7,"taste":{group.preferred_taste:0.2}}]})
	return result

func player_store(menu: Array, waiting: int, group: Dictionary, origin: String = "residential", resident_id: String = "") -> Dictionary:
	var place:=geography.cell(Vector2i(20,20))
	for plot: Dictionary in geography._plots:
		if plot.kind=="player_diner": place=geography.cell(Vector2i(int(plot.x+plot.w/2),int(plot.y+plot.h/2)));break
	var actual_menu: Array=menu.duplicate(true)
	for dish: Dictionary in actual_menu:
		dish.food=float(state.food_memory.get(dish.family_id,reputation(group.id,"food")))
		dish.familiarity=float(state.familiarity.get(group.id+":"+str(dish.get("culture","chinese")),0.7 if dish.get("culture","chinese")=="chinese" else 0.25))
	var service:=reputation(group.id,"service")
	if state.residents.has(resident_id): service=lerpf(service,float(state.residents[resident_id].last_experience),0.25)
	return {"id":"player","open":true,"reachable":place.reachable,"visibility":place.visibility,"awareness":state.awareness,"brand":state.brand,"service":service,"travel_minutes":place.travel_minutes.get(origin,5.0),"wait_minutes":waiting*35.0,"decor_match":decor_match_for(float(place.attractiveness)),"menu":actual_menu}

func decor_match_for(attractiveness: float) -> float:
	var base := clampf(attractiveness, 0.0, 1.0)
	if interior_effect < 0.0 or not is_finite(interior_effect):
		return base
	# AI-048: a uniform low-tier room scores about 30 and does not move the old location weight.
	var delta := clampf((interior_effect - 30.0) / 80.0, -0.25, 0.25)
	return clampf(base + delta, 0.0, 1.0)

func forecast(menu: Array) -> Dictionary:
	var expected: float=0
	var excluded_share: float=0
	var by_recipe: Dictionary={}
	for group: Dictionary in config.groups:
		var share: float=float(group.share)/int(config.society.families_per_group)
		for index: int in int(config.society.families_per_group):
			var actual:=spending_group(group,state.home,index)
			if society.available(society.identity(state.home,group.id,index))==0 or menu.is_empty() or menu.all(func(d:Dictionary)->bool:return int(d.price_cents)>int(actual.hard_budget_cents)):
				excluded_share+=share;continue
			var candidates:=_firms(state.home,actual)
			candidates.append(player_store(menu,0,actual))
			for row: Dictionary in TDEconomicDemand.choices(actual,candidates,config.outside_utility,config.menu_tau):
				if row.store_id!="player": continue
				var visits:=float(config.opportunities_per_day)*share*float(row.probability)
				expected+=visits;by_recipe[row.recipe_id]=float(by_recipe.get(row.recipe_id,0))+visits
	return {"day":int(state.day),"expected_visitors":expected,"min_visitors":maxi(0,floori(expected-1.8*sqrt(expected))),"max_visitors":mini(int(config.opportunities_per_day),ceili(expected+1.8*sqrt(expected))),"by_recipe":by_recipe,"excluded_budget_share":excluded_share,"reasons":["当前菜单超出约%.0f%%客群的预算上限。"%(100*excluded_share),"预算、价格、距离和竞争共同决定到店意向。","区间是估计，存在零客；缺料和排队会继续降低实际下单。"]}

func begin_day() -> void:
	state.economy_open=true;state.last_operated_day=int(state.day)

func arrivals(slot: int, menu: Array, waiting: int, capacity: int, templates: Array, patience: float) -> Array:
	if slot<=int(state.day_stats.slot) or slot>=int(config.slots_per_day): return []
	var result: Array=[]
	var start: int=floori(float(slot)*int(config.opportunities_per_day)/int(config.slots_per_day))
	var finish: int=floori(float(slot+1)*int(config.opportunities_per_day)/int(config.slots_per_day))
	state.day_stats.slot=slot
	for index: int in range(start,finish):
		var group:=_group((index*37+int(state.day)*7)%100)
		var person:=customer(group,index%64,templates)
		var family: String=person.snapshot().household_id
		group=spending_group(group,state.home,index)
		var candidates:=_firms(state.home,group)
		candidates.append(player_store(menu,waiting+result.size(),group,person.snapshot().origin_id,person.id))
		var compared:=TDEconomicDemand.choices(group,candidates,config.outside_utility,config.menu_tau)
		var chosen:=TDEconomicDemand.pick(compared,unit("choice:%s:%d:%d"%[state.home,state.day,index]))
		var comparison:=TDEconomicDemand.comparison_note(compared,chosen)
		state.day_stats.opportunities+=1
		if chosen.store_id=="outside" or society.available(family)==0: state.day_stats.outside+=1;continue
		if chosen.store_id!="player":
			if _sell_npc(state.home,chosen.store_id,family): state.day_stats.competitor+=1
			else: state.day_stats.outside+=1
			continue
		state.day_stats.considered+=1
		if waiting+result.size()>=capacity: state.day_stats.capacity_rejected+=1;continue
		var dish: Dictionary=menu.filter(func(d:Dictionary)->bool:return d.id==chosen.recipe_id)[0]
		var patience_seconds:=clampf(patience*float(group.patience_scale)*pow(-log(maxf(0.000001,1.0-unit("patience:%d:%d"%[state.day,index]))),0.5),90,600)
		var reasons: Array=["预算范围内","比较菜单、路程和预计等待后到店"]
		if comparison!="": reasons.append(comparison)
		var intent:=TDMealIntent.new({"schema_version":1,"opportunity_id":"%s:d%d:s%d:n%d"%[state.home,state.day,slot,index],"customer_id":person.id,"town_id":state.home,"origin_id":person.snapshot().origin_id,"group_id":group.id,"store_id":"player","recipe_id":chosen.recipe_id,"day":int(state.day),"slot":slot,"quoted_cents":int(dish.price_cents),"travel_minutes":float(candidates.back().travel_minutes),"expected_wait_minutes":float(candidates.back().wait_minutes),"patience_seconds":patience_seconds,"reasons":reasons})
		if not society.reserve(family,int(dish.price_cents),intent.snapshot().opportunity_id).ok:
			state.day_stats.capacity_rejected+=1;continue
		state.day_stats.admitted+=1
		result.append({"person":person.snapshot(),"intent":intent.snapshot(),"template":templates[int(group.customer_template)%templates.size()].duplicate(true),"reference_cents":int(dish.reference_cents)})
	return result

func _sell_npc(town: String, id: String, family_id: String) -> bool:
	for firm: Dictionary in state.competitors[town]:
		if firm.id!=id: continue
		if not society.spend(family_id,int(firm.price_cents)): return false
		for item: String in firm.ingredients:
			var quantity: int=int(firm.ingredients[item])
			firm.inventory[item]-=quantity
			var basis: Dictionary=firm.cost_basis.get(item,{"units":0,"value_cents":0})
			var used:=mini(quantity,int(basis.units))
			var cost: int=int(basis.value_cents) if used==int(basis.units) else roundi(float(basis.value_cents)*used/maxi(1,int(basis.units)))
			basis.units-=used;basis.value_cents-=cost;firm.cost_basis[item]=basis;firm.consumed_cents+=cost
		firm.served+=1;firm.cash_cents+=int(firm.price_cents);firm.receipts_cents+=int(firm.price_cents)
		return true
	return false

func record_visit(order: Dictionary) -> Dictionary:
	var id: String=order.id
	if state.day_stats.reviews.has(id): return state.day_stats.reviews[id].duplicate(true)
	var intent: Dictionary=order.get("economic_intent",{})
	if intent.is_empty(): return {}
	var group: String=intent.group_id
	var served: bool=order.status=="SERVED"
	var food: float=clampf(float(order.score.get("satisfaction",0))/100.0,0,1)
	var wait: float=maxf(0,float(order.get("finished_sec",0))-float(order.get("arrival_sec",0)))
	var service: float=exp(-maxf(0,wait/maxf(1,float(intent.patience_seconds))-0.6)) if served else 0.0
	var value: float=clampf(0.5+0.7*(1.0-float(order.price_cents)/maxf(1,float(order.get("reference_cents",order.price_cents)))),0,1) if served else 0.0
	var visit: float=0.7*food+0.2*service+0.1*value
	var review: Dictionary={"food":food,"service":service,"value":value,"visit":visit,"waiting_seconds":wait,"group_id":group,"customer_id":intent.customer_id,"served":served}
	for channel: String in ["food","service","value"]:
		if channel=="food" and not served: continue
		state.reputation[group][channel][0]+=float(review[channel]);state.reputation[group][channel][1]+=1.0-float(review[channel])
	if served:
		state.day_stats.completed+=1
		var family: String=order.get("family_id",order.recipe_id)
		state.food_memory[family]=lerpf(float(state.food_memory.get(family,config.prior_score)),food,0.15)
		if food>=0.65:
			var culture_key:=group+":"+str(order.get("culture","chinese"))
			state.familiarity[culture_key]=minf(1,float(state.familiarity.get(culture_key,0.25))+0.02)
	else: state.day_stats.abandoned+=1
	state.residents[intent.customer_id]={"last_day":int(state.day),"visits":int(state.residents.get(intent.customer_id,{}).get("visits",0))+1,"last_experience":visit}
	state.day_stats.reviews[id]=review
	return review.duplicate(true)

func cooking_time(seconds: float) -> void:
	if state.economy_open and is_finite(seconds) and seconds>0: state.day_stats.cooking_seconds+=seconds

func sync_costs(ledger: Array) -> void:
	for index: int in range(int(state.cost_cursor),ledger.size()):
		var event: Dictionary=ledger[index]
		if society.state.baseline_attached:
			match str(event.kind):
				"purchase": society.state.sectors.market-=int(event.cents)
				"wage": society.state.sectors.services-=int(event.cents)
				"world_adjustment":
					if int(event.cents)>0: society.state.external_net_cents+=int(event.cents)
					elif str(event.extra.get("label","")).begins_with("跨镇采购"): society.state.sectors.market-=int(event.cents)
					else: society.state.sectors.services-=int(event.cents)
				"emergency_grant": society.state.external_net_cents+=int(event.cents)
		var additions: Dictionary={}
		var weights: int=0
		for item: String in event.inventory_delta:
			if int(event.inventory_delta[item])>0:
				additions[item]=int(event.inventory_delta[item])*int(costs.get(item,1));weights+=int(additions[item])
		var left_cost: int=maxi(0,-int(event.cents)) if event.kind=="purchase" else int(event.extra.get("inventory_cost_cents",0))
		var remaining_weight: int=weights
		for item: String in event.inventory_delta:
			if not state.cost_stock.has(item): state.cost_stock[item]={"units":0,"value_cents":0}
			var stock: Dictionary=state.cost_stock[item]
			var quantity: int=int(event.inventory_delta[item])
			if quantity>0:
				var value: int=left_cost if int(additions[item])==remaining_weight else roundi(float(left_cost)*float(additions[item])/maxi(1,remaining_weight))
				stock.units+=quantity;stock.value_cents+=value;left_cost-=value;remaining_weight-=int(additions[item])
			elif quantity<0:
				var used:=mini(-quantity,int(stock.units))
				var spent:=int(stock.value_cents) if used==int(stock.units) else roundi(float(stock.value_cents)*used/maxi(1,int(stock.units)))
				stock.units-=used;stock.value_cents-=spent
				if int(event.day)==int(state.day): state.cost_consumed+=spent
	state.cost_cursor=ledger.size()

func settle(ledger: Array, receipts: int) -> Dictionary:
	if int(state.last_settled_day)==int(state.day): return state.books.back().duplicate(true) if not state.books.is_empty() else {}
	sync_costs(ledger)
	var bank_day:=society.bank.accrue(int(state.day))
	_daily_interest=bank_day.data.get("loan_interest",{}) if bank_day.ok else {}
	state.today_interest_cents=int(bank_day.data.get("loan_interest",{}).get("player",0)) if bank_day.ok else 0
	_simulate_remaining()
	society.finish_day(int(state.day))
	for town: String in config.active_towns: expansion.review(town,state.competitors[town],society,int(state.day))
	var utility: int=roundi(float(config.fees.opening_cents)+int(state.day_stats.admitted)*float(config.fees.guest_cents)+float(state.day_stats.cooking_seconds)*float(config.fees.cooking_second_cents))
	var rent: int=0 if state.lease.owned else int(state.lease.daily_cents)
	# A wage paid after yesterday's settlement belongs to the next business day.
	# The ledger settlement marker makes this boundary survive save/reload without
	# charging the same wage twice or changing a previously settled book.
	var wage: int=0
	for event: Dictionary in ledger:
		if event.kind=="settlement": wage=0
		elif event.kind=="wage": wage-=int(event.cents)
	var before_tax:=receipts-int(state.cost_consumed)-utility-rent-wage-int(state.today_interest_cents)
	var tax:=roundi(float(maxi(0,before_tax))*int(config.society.profit_tax_bps)/10000)
	state.tax_due_cents+=tax
	var expense:=utility+rent+tax
	state.debt_cents+=expense
	var completed: int=int(state.day_stats.completed)
	state.popularity=lerpf(float(state.popularity),100.0*completed/(completed+8.0),0.2)
	state.awareness=clampf(float(state.awareness)*0.995+(1.0-float(state.awareness))*(1.0-exp(-float(state.day_stats.opportunities)*0.004)),0,1)
	var visits: Array=state.day_stats.reviews.values()
	if not visits.is_empty():
		var average: float=0
		for review: Dictionary in visits: average+=float(review.visit)/visits.size()
		state.brand=lerpf(float(state.brand),average,0.025*visits.size()/(visits.size()+8.0))
	var book: Dictionary={"day":int(state.day),"sales_net_cents":receipts,"consumed_cost_cents":int(state.cost_consumed),"utilities_cents":utility,"rent_cents":rent,"expense_cents":expense,"profit_cents":receipts-int(state.cost_consumed)-expense,"debt_cents":int(state.debt_cents),"funnel":state.day_stats.duplicate(true),"paid_cents":0}
	book.profit_before_tax_cents=before_tax;book.tax_cents=tax;book.interest_cents=int(state.today_interest_cents);book.wages_cents=wage;book.profit_cents=before_tax-tax
	book.funnel.erase("reviews");book.funnel.erase("arrivals")
	state.books.append(book)
	while state.books.size()>28: state.books.pop_front()
	state.last_settled_day=int(state.day);state.economy_open=false
	return book.duplicate(true)

func pay_debt(available_cents: int) -> int:
	var amount:=mini(maxi(0,available_cents),int(state.debt_cents))
	var tax_paid:=mini(amount,int(state.tax_due_cents))
	state.tax_due_cents-=tax_paid;society.state.public[state.home]+=tax_paid
	society.state.sectors.services+=amount-tax_paid
	state.debt_cents-=amount
	if not state.books.is_empty() and int(state.books.back().day)==int(state.day):
		state.books.back().paid_cents+=amount;state.books.back().debt_cents=int(state.debt_cents)
	return amount

func _simulate_remaining() -> void:
	if state.day_stats.npc_finished: return
	for town: String in config.active_towns:
		var start: int=int(state.day_stats.opportunities) if town==state.home else 0
		for index: int in range(start,int(config.opportunities_per_day)):
			var group:=_group((index*37+int(state.day)*7)%100)
			var family:=society.identity(town,group.id,index)
			group=spending_group(group,town,index)
			var chosen:=TDEconomicDemand.pick(TDEconomicDemand.choices(group,_firms(town,group),config.outside_utility,config.menu_tau),unit("choice:%s:%d:%d"%[town,state.day,index]))
			if chosen.store_id!="outside" and not _sell_npc(town,chosen.store_id,family): chosen.store_id="outside"
			if town==state.home:
				state.day_stats.opportunities+=1
				if chosen.store_id=="outside": state.day_stats.outside+=1
				else: state.day_stats.competitor+=1
		for firm: Dictionary in state.competitors[town]:
			var payroll:=society.payroll(firm.id,int(firm.cash_cents),int(state.day))
			firm.cash_cents-=int(payroll.paid_cents);firm.wage_expense_cents=int(payroll.expense_cents)
			var interest:=int(society.bank.account(firm.id).interest_cents)
			var before_tax:=int(firm.receipts_cents)-int(firm.consumed_cents)-int(payroll.expense_cents)-int(config.npc.daily_fixed_cents)-int(_daily_interest.get(firm.id,0))
			var tax:=roundi(float(maxi(0,before_tax))*int(config.society.profit_tax_bps)/10000)
			firm.tax_cents=tax;firm.tax_due_cents+=tax;firm.debt_cents+=int(config.npc.daily_fixed_cents)+tax
			var paid:=mini(int(firm.cash_cents),int(firm.debt_cents))
			firm.cash_cents-=paid;firm.debt_cents-=paid;firm.paid_fixed_cents=paid
			var tax_paid:=mini(paid,int(firm.tax_due_cents))
			firm.tax_due_cents-=tax_paid;society.state.public[town]+=tax_paid;society.state.sectors.services+=paid-tax_paid
			var account:=society.bank.account(firm.id)
			var due:=interest+(int(account.principal_cents) if int(state.day)>=int(account.due_day) else 0)
			var interest_paid: int=0
			if due>0 and int(firm.cash_cents)>0:
				var result:=society.bank.transact(firm.id,"repay",mini(due,int(firm.cash_cents)),int(firm.cash_cents),int(state.day),"npc:repay:%s:%d"%[firm.id,state.day],true)
				if result.ok:
					firm.cash_cents+=int(result.data.cash_delta_cents);interest_paid=int(result.data.interest_paid_cents)
			firm.last_profit_cents=before_tax-tax
			firm.history.append({"day":int(state.day),"served":int(firm.served),"receipts_cents":int(firm.receipts_cents),"purchase_cents":int(firm.purchase_cents),"paid_fixed_cents":paid,"cash_cents":int(firm.cash_cents),"profit_cents":int(firm.last_profit_cents),"wages_cents":int(payroll.expense_cents),"tax_cents":tax})
			firm.history.back().cash_flow_cents=int(firm.receipts_cents)-int(firm.purchase_cents)-int(payroll.paid_cents)-paid-interest_paid
			while firm.history.size()>7: firm.history.pop_front()
			firm.last_served=firm.served
			if int(state.day)%7==0:
				var direction: float=1.0 if int(firm.served)>int(config.npc.target_portions) else (-1.0 if int(firm.served)<int(config.npc.target_portions)/2 else 0.0)
				firm.price_cents=clampi(roundi(float(firm.price_cents)*(1.0+direction*float(config.npc.weekly_price_limit))),500,6000)
	state.day_stats.npc_finished=true

func advance_day(expected: int) -> TDOutcome:
	if expected!=int(state.day) or int(state.last_settled_day)!=expected: return TDOutcome.new(false,"DUPLICATE_DAY")
	# All markets update once; shipping consumes origin inventory at departure, adds at arrival.
	for town: String in config.active_towns:
		var market: Dictionary=state.markets[town]
		for item: String in costs:
			var request:=mini(int(config.market.background_need_units),int(market.stock[item]))
			market.requested[item]=int(market.requested.get(item,0))+int(config.market.background_need_units)
			market.stock[item]-=request;market.sold[item]=int(market.sold.get(item,0))+request
			# Opening is measured after daily production: adding produced again double counts it.
			var available:=maxi(1,int(market.opening.get(item,config.market.initial_units))+int(market.imports.get(item,0))-int(market.exports.get(item,0)))
			var gap:=float(int(market.requested.get(item,0))-available)/float(config.market.initial_units)
			var premium:=clampf((1.0-float(config.market.reversion))*float(market.premium[item])+float(config.market.gap_response)*tanh(gap),-float(config.market.max_premium),float(config.market.max_premium))
			var target:=float(costs[item])*source_factor(town,item)*exp(premium)
			var old:=int(market.price[item]);var limit:=float(config.market.max_daily_change)
			market.price[item]=maxi(1,clampi(roundi(target),ceili(old*(1-limit)),floori(old*(1+limit))))
			market.premium[item]=premium
			var quantity:=roundi(float(config.market.production_units)/source_factor(town,item))
			var spoil:=floori(float(market.stock[item])*0.02)
			market.stock[item]-=spoil
			quantity=mini(quantity,int(config.market.capacity_units)-int(market.stock[item]))
			market.stock[item]+=quantity
			market.produced[item]=quantity;market.spoilage[item]=spoil
		market.requested={};market.sold={};market.imports={};market.exports={};market.opening=market.stock.duplicate(true)
	# Bounded wholesale redistribution makes one town's shortage affect another's stock.
	for item: String in costs:
		var richest: String=config.active_towns[0];var poorest: String=richest
		for town: String in config.active_towns:
			if int(state.markets[town].stock[item])>int(state.markets[richest].stock[item]): richest=town
			if int(state.markets[town].stock[item])<int(state.markets[poorest].stock[item]): poorest=town
		var movement:=mini(4000,maxi(0,(int(state.markets[richest].stock[item])-int(state.markets[poorest].stock[item]))/4))
		if movement>0:
			state.markets[richest].stock[item]-=movement;state.markets[poorest].stock[item]+=movement
			state.markets[richest].exports[item]=movement;state.markets[poorest].imports[item]=movement
	state.day+=1
	society.start_day();state.today_interest_cents=0
	state.shipments=state.shipments.filter(func(s:Dictionary)->bool:return not s.delivered or int(s.ordered_day)>=int(state.day)-7)
	for group: Dictionary in config.groups:
		for channel: String in ["food","service","value"]:
			state.reputation[group.id][channel][0]*=0.98;state.reputation[group.id][channel][1]*=0.98
	_reset_day();_stock_competitors()
	return TDOutcome.new(true,"NEXT_ECONOMY_DAY")

func restore(raw: Dictionary) -> TDOutcome:
	var checked:=validate_save(raw)
	if not checked.ok: return checked
	if int(raw.schema_version)==1: return _migrate_v1(raw)
	state=raw.duplicate(true)
	society.restore(state.society);state.society=society.state
	expansion.state=state.expansion
	return TDOutcome.new(true,"RESTORED")

func _migrate_v1(raw: Dictionary) -> TDOutcome:
	# Original location and paid shipments stay intact. Only five representatives tick onward.
	var home: String=str(raw.home) if raw.home in config.active_towns else ("paris" if raw.home in ["london","stockholm","moscow"] else "chengdu")
	var fresh:=TDWorldEconomy.new(costs,home,int(raw.seed),int(raw.day))
	var archived: Dictionary={"original_home":raw.home,"markets":{},"competitors":{},"routes":raw.routes.duplicate(true),"route_events":raw.route_events.duplicate(true)}
	for key: String in raw:
		if key not in ["schema_version","home","markets","competitors","routes","route_events"]: fresh.state[key]=_copy(raw[key])
	for town: String in raw.markets:
		if town in config.active_towns:
			fresh.state.markets[town]=raw.markets[town].duplicate(true)
			fresh.state.competitors[town]=raw.competitors[town].duplicate(true)
			for index: int in fresh.state.competitors[town].size():
				var firm: Dictionary=fresh.state.competitors[town][index]
				fresh.decorate_firm(firm,index,int(raw.day))
				for item: String in firm.inventory: firm.cost_basis[item]={"units":int(firm.inventory[item]),"value_cents":roundi(float(firm.inventory[item])*int(fresh.state.markets[town].price[item])/1000)}
		else:
			archived.markets[town]=raw.markets[town].duplicate(true);archived.competitors[town]=raw.competitors[town].duplicate(true)
	fresh.state.routes=raw.routes.filter(func(t:Variant)->bool:return t in config.active_towns)
	if home not in fresh.state.routes: fresh.state.routes.append(home)
	fresh.state.route_events={}
	for event: String in raw.route_events:
		if raw.route_events[event] in fresh.state.routes: fresh.state.route_events[event]=raw.route_events[event]
	fresh.state.legacy_archive=archived
	var cultures: Dictionary={"cn":"chinese","eu":"continental","fr":"continental","french":"continental","en":"continental","british":"continental","jp":"japanese","sea":"southeast_asian","lat":"latin_american"}
	for key: String in raw.familiarity:
		var parts:=key.split(":")
		if parts.size()!=2 or not cultures.has(parts[1]): continue
		var canonical: String=parts[0]+":"+str(cultures[parts[1]])
		if not fresh.state.familiarity.has(canonical): fresh.state.familiarity[canonical]=raw.familiarity[key]
	fresh.society.state.last_day=int(raw.last_settled_day);fresh.society.bank.state.last_day=int(raw.last_settled_day)
	# No historical wages, interest or tax. Existing balances become the new opening balance.
	config=fresh.config;state=fresh.state;society=fresh.society;expansion=fresh.expansion
	return TDOutcome.new(true,"MIGRATED_FIVE_TOWNS","历史在途货物和原店位置保留；旧区域停止新增模拟。")

func _copy(value: Variant) -> Variant:
	return value.duplicate(true) if value is Dictionary or value is Array else value

func validate_save(raw: Variant) -> TDOutcome:
	if not raw is Dictionary or not TDServiceCatalog.integer(raw.get("schema_version"),1,2): return TDOutcome.new(false,"INVALID_ECONOMY_VERSION")
	var legacy: bool=int(raw.schema_version)==1
	var towns: Array=TDTownCatalog.PLAYABLE_IDS if legacy else config.active_towns
	for field: String in state:
		if legacy and field in SOCIETY_FIELDS: continue
		if not raw.has(field): return TDOutcome.new(false,"MISSING_ECONOMY_FIELD",field)
	if not legacy and not raw.legacy_archive is Dictionary: return TDOutcome.new(false,"INVALID_LEGACY_ARCHIVE")
	if not _safe_tree(raw): return TDOutcome.new(false,"INVALID_ECONOMY_DATA")
	for field: String in ["day","seed","shipping_serial","debt_cents","last_settled_day","last_operated_day","cost_cursor","cost_consumed"]:
		if not TDServiceCatalog.integer(raw[field],0,1000000000): return TDOutcome.new(false,"INVALID_ECONOMY_NUMBER",field)
	if int(raw.day)<1 or int(raw.last_settled_day) not in [int(raw.day)-1,int(raw.day)] or raw.home not in towns or not raw.routes is Array or not raw.books is Array or raw.books.size()>28: return TDOutcome.new(false,"INVALID_ECONOMY_DAY")
	for field: String in ["markets","competitors","reputation","cost_stock","factory_costs","cells","lease","day_stats","route_events","residents","familiarity","food_memory"]:
		if not raw[field] is Dictionary: return TDOutcome.new(false,"INVALID_ECONOMY_DATA",field)
	if not raw.economy_open is bool or not _shape(raw.day_stats,state.day_stats) or not _shape(raw.lease,state.lease): return TDOutcome.new(false,"INVALID_ECONOMY_STATE")
	for field: String in ["awareness","brand"]:
		if not TDEconomicCustomer.finite_range(raw[field],0,1): return TDOutcome.new(false,"INVALID_REPUTATION")
	if not TDEconomicCustomer.finite_range(raw.popularity,0,100): return TDOutcome.new(false,"INVALID_REPUTATION")
	for field: String in ["opportunities","outside","competitor","considered","admitted","capacity_rejected","completed","abandoned"]:
		if not TDServiceCatalog.integer(raw.day_stats[field],0,2000): return TDOutcome.new(false,"INVALID_FUNNEL")
	if not TDServiceCatalog.integer(raw.day_stats.slot,-1,int(config.slots_per_day)-1) or not TDEconomicCustomer.finite_range(raw.day_stats.cooking_seconds,0,10000000): return TDOutcome.new(false,"INVALID_FUNNEL")
	if not TDServiceCatalog.integer(raw.lease.daily_cents,0,100000000) or not TDServiceCatalog.integer(raw.lease.through_day,1,2147483647): return TDOutcome.new(false,"INVALID_LEASE")
	for pool: Dictionary in [raw.cost_stock,raw.factory_costs]:
		for item: Variant in pool:
			var stock: Variant=pool[item]
			if not costs.has(item) or not stock is Dictionary or not TDServiceCatalog.integer(stock.get("units"),0,10000000) or not TDServiceCatalog.integer(stock.get("value_cents"),0,1000000000): return TDOutcome.new(false,"INVALID_COST_STOCK")
	for key: Variant in raw.cells:
		var cell: Variant=raw.cells[key]
		if not cell is Dictionary or not TDEconomicCell.new(cell).error.ok or cell.id!=key: return TDOutcome.new(false,"INVALID_CELL")
	for map: Dictionary in [raw.familiarity,raw.food_memory]:
		for value: Variant in map.values():
			if not TDEconomicCustomer.finite_range(value,0,1): return TDOutcome.new(false,"INVALID_MEMORY")
	for resident: Variant in raw.residents.values():
		if not resident is Dictionary or not TDServiceCatalog.integer(resident.get("last_day"),1,int(raw.day)) or not TDServiceCatalog.integer(resident.get("visits"),1,1000000) or not TDEconomicCustomer.finite_range(resident.get("last_experience"),0,1): return TDOutcome.new(false,"INVALID_RESIDENT")
	for destination: Variant in raw.route_events.values():
		if destination not in raw.routes: return TDOutcome.new(false,"INVALID_ROUTE_EVENT")
	for review: Variant in raw.day_stats.reviews.values():
		if not review is Dictionary: return TDOutcome.new(false,"INVALID_REVIEW")
		for field: String in ["food","service","value","visit"]:
			if not TDEconomicCustomer.finite_range(review.get(field),0,1): return TDOutcome.new(false,"INVALID_REVIEW")
	for book: Variant in raw.books:
		if not book is Dictionary or not TDServiceCatalog.integer(book.get("day"),1,int(raw.day)) or not book.get("funnel") is Dictionary: return TDOutcome.new(false,"INVALID_BOOK")
		for field: String in ["sales_net_cents","consumed_cost_cents","utilities_cents","rent_cents","expense_cents","debt_cents","paid_cents"]:
			if not TDServiceCatalog.integer(book.get(field),0,1000000000): return TDOutcome.new(false,"INVALID_BOOK")
		if not TDServiceCatalog.integer(book.get("profit_cents"),-1000000000,1000000000): return TDOutcome.new(false,"INVALID_BOOK")
		for field: String in ["opportunities","considered","admitted","completed","abandoned"]:
			if not TDServiceCatalog.integer(book.funnel.get(field),0,2000): return TDOutcome.new(false,"INVALID_BOOK")
	if raw.markets.size()!=towns.size() or raw.competitors.size()!=towns.size(): return TDOutcome.new(false,"INVALID_MARKET_COUNT")
	var identities: Dictionary={}
	for town: String in towns:
		if not raw.markets.get(town) is Dictionary or not raw.competitors.get(town) is Array or raw.competitors[town].size()<int(config.npc.stores_per_town) or raw.competitors[town].size()>int(config.npc.stores_per_town)*(1 if legacy else int(config.expansion.max_stores_per_owner)): return TDOutcome.new(false,"MISSING_MARKET")
		for field: String in ["stock","price","premium","requested","sold","produced","imports","exports","spoilage","opening"]:
			if not raw.markets[town].get(field) is Dictionary: return TDOutcome.new(false,"INVALID_MARKET")
		for item: String in costs:
			if not TDServiceCatalog.integer(raw.markets[town].stock.get(item),0,10000000) or not TDServiceCatalog.integer(raw.markets[town].price.get(item),1,10000000) or not TDEconomicCustomer.finite_range(raw.markets[town].premium.get(item),-2,2): return TDOutcome.new(false,"INVALID_MARKET")
		for firm: Variant in raw.competitors[town]:
			var model: Dictionary=state.competitors[config.active_towns[0]][0].duplicate(true)
			if legacy:
				for key: String in FIRM_FIELDS: model.erase(key)
			if not firm is Dictionary or not _shape(firm,model) or not TDServiceCatalog.integer(firm.get("cash_cents"),0,1000000000) or not TDServiceCatalog.integer(firm.get("debt_cents"),0,1000000000): return TDOutcome.new(false,"INVALID_COMPETITOR")
			if identities.has(firm.id): return TDOutcome.new(false,"DUPLICATE_FIRM")
			identities[firm.id]=true
			if not legacy:
				if firm.status not in ["construction","open"] or not firm.owner_id.begins_with("npc-store:"+town+":") or not firm.id.begins_with("npc-store:"+town+":"): return TDOutcome.new(false,"INVALID_FIRM_ID")
				for field: String in ["capacity","open_day","consumed_cents","wage_expense_cents","tax_cents","tax_due_cents","profitable_reviews"]:
					if not TDServiceCatalog.integer(firm[field],0,1000000000): return TDOutcome.new(false,"INVALID_FIRM_NUMBER",field)
				if int(firm.tax_due_cents)>int(firm.debt_cents): return TDOutcome.new(false,"INVALID_TAX_DEBT")
				for pool: Variant in firm.cost_basis.values():
					if not pool is Dictionary or not TDServiceCatalog.integer(pool.get("units"),0,10000000) or not TDServiceCatalog.integer(pool.get("value_cents"),0,1000000000): return TDOutcome.new(false,"INVALID_FIRM_COST")
			for field: String in ["price_cents","reference_cents","served","last_served","receipts_cents","purchase_cents","paid_fixed_cents"]:
				if not TDServiceCatalog.integer(firm[field],0,1000000000): return TDOutcome.new(false,"INVALID_COMPETITOR")
			if firm.history.size()>7: return TDOutcome.new(false,"INVALID_COMPETITOR")
			for value: Variant in firm.ingredients.values():
				if not TDServiceCatalog.integer(value,1,100000): return TDOutcome.new(false,"INVALID_COMPETITOR")
			for field: String in ["quality","awareness","brand"]:
				if not TDEconomicCustomer.finite_range(firm[field],0,1): return TDOutcome.new(false,"INVALID_COMPETITOR")
			for amount: Variant in firm.inventory.values():
				if not TDServiceCatalog.integer(amount,0,10000000): return TDOutcome.new(false,"INVALID_COMPETITOR_STOCK")
		for index: int in raw.competitors[town].size():
			var firm: Dictionary=raw.competitors[town][index]
			var basket_index: int=index if legacy else int(firm.basket_index)
			if basket_index<0 or basket_index>=int(config.npc.stores_per_town): return TDOutcome.new(false,"INVALID_COMPETITOR_IDENTITY")
			var basket:=_npc_basket(basket_index)
			if (legacy and firm.id!="npc-store:%s:%d"%[town,index]) or firm.ingredients.size()!=basket.size(): return TDOutcome.new(false,"INVALID_COMPETITOR_IDENTITY")
			for item: String in basket:
				if not TDServiceCatalog.integer(firm.ingredients.get(item),int(basket[item]),int(basket[item])): return TDOutcome.new(false,"INVALID_COMPETITOR_IDENTITY")
	for group: Dictionary in config.groups:
		if not raw.reputation.get(group.id) is Dictionary: return TDOutcome.new(false,"INVALID_REPUTATION")
		for channel: String in ["food","service","value"]:
			var pair: Variant=raw.reputation[group.id].get(channel)
			if not pair is Array or pair.size()!=2 or not TDEconomicCustomer.finite_range(pair[0],0,1000000) or not TDEconomicCustomer.finite_range(pair[1],0,1000000): return TDOutcome.new(false,"INVALID_REPUTATION")
	var shipment_ids: Dictionary={}
	var historical: Dictionary={} if legacy else raw.legacy_archive
	if not raw.shipments is Array or raw.shipments.size()>1000: return TDOutcome.new(false,"INVALID_SHIPMENTS")
	for shipment: Variant in raw.shipments:
		if not shipment is Dictionary or not shipment.get("id") is String or shipment_ids.has(shipment.id) or (shipment.get("source") not in towns and not historical.get("markets",{}).has(shipment.get("source"))) or not shipment.get("delivered") is bool or not shipment.get("rows") is Dictionary: return TDOutcome.new(false,"INVALID_SHIPMENTS")
		shipment_ids[shipment.id]=true
		for field: String in ["day","ordered_day","arrival_day","total_cents","freight_cents","units"]:
			if not TDServiceCatalog.integer(shipment.get(field),0,1000000000): return TDOutcome.new(false,"INVALID_SHIPMENTS")
		if shipment.get("destination") not in [raw.home,historical.get("original_home",raw.home)] or not shipment.get("quote_id") is String or int(shipment.arrival_day)<int(shipment.ordered_day): return TDOutcome.new(false,"INVALID_SHIPMENTS")
		for item: String in shipment.rows:
			if not costs.has(item) or not shipment.rows[item] is Dictionary or not TDServiceCatalog.integer(shipment.rows[item].get("units"),1,100000): return TDOutcome.new(false,"INVALID_SHIPMENTS")
			for field: String in ["goods_cents","freight_cents","price_cents"]:
				if not TDServiceCatalog.integer(shipment.rows[item].get(field),0,1000000000): return TDOutcome.new(false,"INVALID_SHIPMENTS")
	var route_seen: Dictionary={}
	for town: Variant in raw.routes:
		if town not in towns or route_seen.has(town): return TDOutcome.new(false,"INVALID_ROUTES")
		route_seen[town]=true
	if not route_seen.has(raw.home): return TDOutcome.new(false,"INVALID_ROUTES")
	if not legacy:
		if not raw.legacy_archive is Dictionary: return TDOutcome.new(false,"INVALID_LEGACY_ARCHIVE")
		if not TDServiceCatalog.integer(raw.tax_due_cents,0,int(raw.debt_cents)) or not TDServiceCatalog.integer(raw.today_interest_cents,0,1000000000): return TDOutcome.new(false,"INVALID_TAX_DEBT")
		var social_check:=society.validate(raw.society)
		if not social_check.ok: return social_check
		if int(raw.society.last_day)!=int(raw.last_settled_day) or int(raw.society.bank.last_day)!=int(raw.last_settled_day): return TDOutcome.new(false,"INCONSISTENT_SOCIAL_DAY")
		var building_check:=expansion.validate(raw.expansion,towns,raw.competitors)
		if not building_check.ok: return building_check
		for family: Dictionary in raw.society.households.values():
			if not family.employer_id.is_empty() and not identities.has(family.employer_id): return TDOutcome.new(false,"UNKNOWN_EMPLOYER")
	return TDOutcome.new(true,"VALID_ECONOMY")

func _shape(value: Variant, model: Variant) -> bool:
	if model is Dictionary:
		if not value is Dictionary: return false
		for key: Variant in model:
			if not value.has(key): return false
			if model[key] is Dictionary:
				if not value[key] is Dictionary: return false
			elif not _shape(value[key],model[key]): return false
	elif model is Array: return value is Array
	elif model is float or model is int: return (value is float or value is int) and is_finite(value)
	else: return typeof(value)==typeof(model)
	return true

func _safe_tree(value: Variant, depth: int=0) -> bool:
	if depth>20: return false
	if value is Dictionary:
		if value.size()>20000: return false
		for key: Variant in value:
			if not (key is String or key is StringName) or not _safe_tree(value[key],depth+1): return false
	elif value is Array:
		if value.size()>20000: return false
		for item: Variant in value:
			if not _safe_tree(item,depth+1): return false
	elif value is float:
		return is_finite(value)
	elif not (value is String or value is int or value is bool): return false
	return true
