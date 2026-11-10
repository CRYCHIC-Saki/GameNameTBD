class_name TDShopSession
extends RefCounted
var before_open: Callable
var before_settlement: Callable
signal day_settled(day: int)
signal day_opened()
## Money, orders and stock have one owner. The kitchen provides real dish snapshots.
var catalog: TDServiceCatalog
var scorer := TDCustomerScorer.new()
var _s: Dictionary = {}
var _rng: RefCounted
var _next_arrival: float = 1.0
var _kitchen: Array = []
var _kitchen_key: String = ""
var _day_end_reason: String = "time"
var research_controlled: bool = false
var commerce: TDWorldEconomy
var recipe_cultures: Dictionary = {}
var cooking_reward: Callable
var kitchen_gate: Callable
var practice_supply_policy: Callable
var require_seating: bool=false
var dining_tick: Callable
var dining_boundary: Callable
var day_minute_reader: Callable
var _opening_minute: float = 480.0

func business_close_sec() -> float:
	return maxf(0,TDWorldDayClock.END_MINUTE-_opening_minute) if day_minute_reader.is_valid() else float(catalog.config.settings.day_sec)

func _scheduled_arrival() -> float:
	return minf(business_close_sec()+1,maxf(0,commerce.next_meal_minute()-_opening_minute))
var crew: TDRestaurantCrew
var _starter_override: Array = []
var material_recipe_unlocks: Array=[]
var material_cuisine_unlocks: Array=["cn"]
var stock_rules: Dictionary = TDFoodStock.load_rules()

func purchasable(id: String) -> bool:
	if not catalog.config.costs.has(id): return false
	if stock_rules.get(id,{}).get("condiment",false): return TDMaterialCatalog.condiment_unlocked(id,material_cuisine_unlocks)
	if TDMaterialCatalog.needed_by_unlocked(id,material_recipe_unlocks): return true
	for item: Dictionary in catalog.config.offers:
		if is_unlocked(item.id) and id in item.primary: return true
	return false

func market_sells(id: String) -> bool:
	# D070 gates condiments; the neighbourhood market still sells all stocked foods.
	if catalog==null or not catalog.config.costs.has(id): return false
	return not stock_rules.get(id,{}).get("condiment",false) or TDMaterialCatalog.condiment_unlocked(id,material_cuisine_unlocks)

func market_ids() -> Array[String]:
	var result: Array[String]=[]
	for id: String in catalog.config.costs:
		if market_sells(id): result.append(id)
	return result

func purchase_ids() -> Array[String]:
	var result: Array[String]=[]
	for id: String in catalog.config.costs:
		if purchasable(id): result.append(id)
	return result

func stock_info(id: String) -> Dictionary:
	var result: Dictionary=stock_rules.get(id,{"group":"vegetable","unit":"份","pack_units":1000,"shelf_days":3,"condiment":false}).duplicate(true)
	var metadata:=TDMaterialCatalog.item(id)
	result.supply_regions=metadata.get("supply_regions",[]);result.category=metadata.get("category",result.group)
	result.region_label=TDMaterialCatalog.regions_text(id)
	result.units=available(id); result.expires_on=TDFoodStock.first_expiry(_s.get("inventory_lots",{}),id)
	result.remaining_days=maxi(0,int(result.expires_on)-int(_s.day))
	return result

func replenish_practice_materials() -> TDOutcome:
	if not kitchen_available() or not practice_supply_policy.is_valid(): return TDOutcome.new(true,"NO_PRACTICE_SUPPLY")
	var policy: Variant=practice_supply_policy.call()
	if not policy is Dictionary: return TDOutcome.new(false,"INVALID_PRACTICE_SUPPLY")
	if policy.is_empty(): return TDOutcome.new(true,"NO_PRACTICE_SUPPLY")
	var units: Dictionary={}
	for id: Variant in policy:
		if not catalog.config.costs.has(id) or not TDServiceCatalog.integer(policy[id],1,1000): return TDOutcome.new(false,"INVALID_PRACTICE_SUPPLY")
		var held: int=available(id)
		for food: Dictionary in _s.cold_foods:
			if food.ingredient_id==id: held+=roundi(float(food.amount)*1000)
		for entry: Dictionary in _kitchen:
			var dish: Dictionary=entry.dish
			# Board/hand food stays recoverable during cutting. Cooking food does not.
			var cold: bool=dish.state=="preparing" and dish.steps.all(func(step:Dictionary)->bool:return step.operation=="cut")
			if not cold and not (entry.location=="loose" and dish.state=="operating" and dish.steps.all(func(step:Dictionary)->bool:return step.operation=="cut")): continue
			for food: Dictionary in dish.ingredients.values():
				if food.ingredient_id==id: held+=roundi(float(food.amount)*1000)
		var missing:=maxi(0,int(policy[id])-held)
		if missing>0: units[id]=missing
	if units.is_empty(): return TDOutcome.new(true,"PRACTICE_STOCK_READY")
	var token: String="story-practice-v1:%s:%d"%[_s.run_id,int(_s.serial)+1]
	_s.seen[token]=true
	_record("supply_delivery",0,units,token,{"inventory_cost_cents":0,"source":"opening_practice"})
	return TDOutcome.new(true,"PRACTICE_REFILLED","教程补给已补齐：番茄和鸡蛋可反复试做。",units.duplicate(true))

func day_namespace() -> String:
	return "%s:d%d:" % [_s.run_id,_s.day]

func family_id(id: String) -> String:
	var item: Dictionary=offer(id)
	return str(item.custom_entry.plan.recipe_id) if item.has("custom_entry") else id

func context_for_ingredients(ids: Array, complete: bool = false, method: String = "") -> Dictionary:
	for item: Dictionary in active_orders():
		if _method_matches(family_id(item.recipe_id),method) and _matches_materials(ids,offer(item.recipe_id).primary,complete): return item
	for item: Dictionary in catalog.config.offers:
		if _method_matches(item.id,method) and _matches_materials(ids,item.primary,complete): return {"recipe_id":item.id,"customer":{}}
	return {}

func _method_matches(id: String, method: String) -> bool:
	return method.is_empty() or catalog.cooking.for_recipe(id).get("recipe",{}).get("cooking_method","stir")==method

func _matches_materials(ids: Array, primary: Array, complete: bool) -> bool:
	if ids.is_empty(): return false
	var main: Array=[]
	for id: String in ids:
		if catalog.is_primary(id): main.append(id)
	if main.is_empty(): return false
	for id: String in main:
		if id not in primary: return false
	return not complete or primary.all(func(id:String)->bool:return id in main)

func profile_for(context: Dictionary) -> TDCookingCatalog:
	var item: Dictionary=offer(str(context.recipe_id))
	return catalog.request_profile(family_id(str(context.recipe_id)),context.get("customer",{}),item.get("custom_entry",{}))

func first_order_for(dish: Dictionary) -> Dictionary:
	for item: Dictionary in active_orders():
		if dish.get("failed_dish",false): return item
		if family_id(item.recipe_id)==dish.get("recipe_id"): return item
	return {}

func consume_materials(token: String, units: Dictionary) -> TDOutcome:
	if not kitchen_available() or not token.begins_with(day_namespace()): return TDOutcome.new(false,"STALE_MATERIAL_REQUEST")
	if _s.seen.has(token): return TDOutcome.new(false,"DUPLICATE")
	if units.is_empty(): return TDOutcome.new(false,"EMPTY_CART")
	var delta: Dictionary={}
	for id: Variant in units:
		if not catalog.config.costs.has(id) or not TDServiceCatalog.integer(units[id],1,100000): return TDOutcome.new(false,"INVALID_QUANTITY")
		if available(id)<int(units[id]): return TDOutcome.new(false,"INSUFFICIENT_STOCK","材料不足，本次加料未生效。")
		delta[id]=-int(units[id])
	var expiry: Dictionary={}
	for id: String in units: expiry[id]=TDFoodStock.first_expiry(_s.inventory_lots,id)
	_s.seen[token]=true; _record("consumption",0,delta,token)
	return TDOutcome.new(true,"CONSUMED","",{"expires_on":expiry})

func sync_kitchen(snapshots: Array) -> void:
	# Cooling changes revision every tick, but never changes whether an order has enough food.
	var key: String=JSON.stringify([_s.inventory,_s.orders.map(func(o:Dictionary)->Array:return [o.id,o.status]),snapshots.map(func(e:Dictionary)->Array:return [e.location,e.dish.session_id,e.dish.recipe_id,e.dish.state,e.dish.ingredients.values().map(func(f:Dictionary)->Array:return [f.id,f.ingredient_id,f.amount]),e.get("future_materials",{})])])
	if key==_kitchen_key: return
	_kitchen_key=key
	_kitchen=[]
	var seen: Dictionary={}
	for entry: Dictionary in snapshots:
		var dish: Dictionary=entry.dish
		if not str(dish.get("session_id","")).begins_with(day_namespace()) or seen.has(dish.session_id) or dish.get("state") in ["delivered","discarded","cancelled"]: continue
		seen[dish.session_id]=true
		var foods: Dictionary={}
		for id: String in dish.ingredients:
			var food: Dictionary=dish.ingredients[id]
			foods[id]={"id":id,"ingredient_id":food.ingredient_id,"amount":food.amount}
		var steps: Array=dish.steps.map(func(s:Dictionary)->Dictionary:return {"operation":s.operation,"parameters":{"mode":s.parameters.get("mode","")}})
		var value: Dictionary={"session_id":dish.session_id,"recipe_id":dish.recipe_id,"state":dish.state,"ingredients":foods,"steps":steps}
		if entry.has("future_materials"): value.future_materials=entry.future_materials.duplicate(true)
		_kitchen.append({"location":entry.location,"dish":value})
	if _s.phase in ["OPEN","DRAINING"]:
		for id: String in _allocation().rejected: cancel_order(id,"REJECTED_STOCK")

func _allocation(extra: Dictionary = {}) -> Dictionary:
	var pool: Dictionary=_s.inventory.duplicate(true); var pots: Array=[]; var seen: Dictionary={}
	for food: Dictionary in _s.get("cold_foods",[]):
		seen[food.id]=true; pool[food.ingredient_id]=int(pool.get(food.ingredient_id,0))+roundi(float(food.amount)*1000)
	for entry: Dictionary in _kitchen:
		if entry.get("location")=="pot":
			if not entry.dish.ingredients.is_empty(): pots.append(entry.dish)
		else:
			for food: Dictionary in entry.dish.ingredients.values():
				if seen.has(food.id): continue
				seen[food.id]=true; pool[food.ingredient_id]=int(pool.get(food.ingredient_id,0))+roundi(float(food.amount)*1000)
	var requests: Array=pending_orders()
	if not extra.is_empty(): requests.append(extra)
	var rejected: Array[String]=[]
	for item: Dictionary in requests:
		var profile: TDCookingCatalog=profile_for(item)
		if profile==null: rejected.append(str(item.id)); continue
		var family: String=family_id(item.recipe_id)
		var chosen: int=-2; var remaining: Dictionary={}
		# Existing physical food is allocated only once; pantry covers unfinished steps.
		for i: int in range(-1,pots.size()):
			var pot: Dictionary={} if i<0 else pots[i]
			if i>=0 and pot.recipe_id!=family: continue
			var need: Dictionary={} if pot.get("state")=="plated" else pot.get("future_materials",catalog.material_needs(profile,family,pot.get("steps",[]))).duplicate(true)
			if i>=0:
				for food: Dictionary in pot.ingredients.values():
					if food.ingredient_id in catalog.offer(family).primary: need[food.ingredient_id]=maxi(0,int(need.get(food.ingredient_id,0))-roundi(float(food.amount)*1000))
			var enough: bool=true
			for id: String in need:
				if int(pool.get(id,0))<int(need[id]): enough=false; break
			if enough:
				chosen=i; remaining=need
				if i>=0: break
		if chosen==-2: rejected.append(str(item.id)); continue
		for id: String in remaining: pool[id]-=int(remaining[id])
		if chosen>=0: pots.remove_at(chosen)
	return {"rejected":rejected}

func menu_available(id: String, customer: Dictionary = {}) -> bool:
	if offer(id).is_empty() or not is_unlocked(family_id(id)): return false
	return "prospective" not in _allocation({"id":"prospective","recipe_id":id,"customer":customer}).rejected

func _init(content: TDServiceCatalog, run_id: String = "", seed_value: int = 101, starter_ids: Array = []) -> void:
	catalog = content
	_starter_override=starter_ids.duplicate();research_controlled=not starter_ids.is_empty()
	var identity: String = run_id if not run_id.is_empty() else "shop-%d-%d" % [Time.get_unix_time_from_system(),Time.get_ticks_usec()]
	var inventory: Dictionary = {}; var menu: Dictionary = {}; var fame: Dictionary = {}
	for id: String in catalog.config.costs: inventory[id] = 0
	for item: Dictionary in catalog.config.offers:
		menu[item.id] = {"enabled":item.id == "service.tomato_egg","price_cents":int(item.reference_cents)}; fame[item.id] = 0
	_s = {"schema_version":1,"run_id":identity,"seed":seed_value,"day":1,"phase":"PREPARE","elapsed_sec":0.0,"money_cents":int(catalog.config.settings.initial_cents),"inventory":inventory,"menu":menu,"orders":[],"ledger":[],"seen":{},"custom":[],"serial":0,"order_serial":0,"popularity":int(catalog.config.settings.initial_popularity),"reputation":0,"reputation_status":"DEFERRED","fame":fame,"settled_days":[],"grant_days":[]}
	_rng = TDBusinessRandom.new(seed_value)
	_s.cold_foods=[]; _s.unlocked=_initial_unlocks(); _s.progress_version=1
	_s.material_version=1; _s.stock_version=1; _s.inventory_lots=TDFoodStock.migrate(inventory,1,stock_rules)
	_s.mastery_version=1; _s.mastery={}; _s.mastery_dishes={}

func _initial_unlocks() -> Array:
	if not _starter_override.is_empty(): return _starter_override.duplicate()
	return catalog.config.offers.filter(func(o:Dictionary)->bool:return catalog.cooking.for_recipe(o.id).recipe.get("initially_unlocked",true)).map(func(o:Dictionary)->String:return o.id)

func is_unlocked(id: String) -> bool:
	return id in _s.unlocked

func grant_recipe(id: String) -> TDOutcome:
	var item := offer(id)
	if item.is_empty(): return TDOutcome.new(false,"UNKNOWN_RECIPE")
	if id not in _s.unlocked: _s.unlocked.append(id)
	if not _s.menu.has(id): _s.menu[id] = {"enabled":true,"price_cents":int(item.reference_cents)}
	else: _s.menu[id].enabled = true
	if not _s.fame.has(id): _s.fame[id] = 0
	return TDOutcome.new(true,"RECIPE_GRANTED",str(catalog.cooking.for_recipe(id).get("recipe",{}).get("name",id)))

func observe_finished(dish: Dictionary) -> TDOutcome:
	var id: String=str(dish.get("recipe_id",""))
	if not kitchen_available() or not str(dish.get("session_id","")).begins_with(day_namespace()) or dish.get("state") not in ["plated","delivered"]: return TDOutcome.new(false,"INVALID_DISH")
	if catalog.offer(id).is_empty() or dish.get("failed_dish",false): return TDOutcome.new(false,"UNKNOWN_RECIPE")
	var learned:=observe_mastery(dish)
	if learned.code=="MASTERY_GAINED": return learned
	if is_unlocked(id): return TDOutcome.new(true,"ALREADY_UNLOCKED")
	if research_controlled: return TDOutcome.new(false,"RESEARCH_REQUIRED","请在菜谱研习中通过谱面后解锁。")
	if not dish.get("missing_required") is Array or not dish.missing_required.is_empty() or not dish.get("steps") is Array or dish.steps.is_empty(): return TDOutcome.new(false,"NOT_PERFECT")
	var threshold: float=float(catalog.cooking.data().rules.perfect_grade_threshold)
	for step: Dictionary in dish.steps:
		if not step.get("quality") is float and not step.get("quality") is int: return TDOutcome.new(false,"INVALID_DISH")
		if not is_finite(float(step.quality)) or float(step.quality)<threshold: return TDOutcome.new(false,"NOT_PERFECT")
	var recipe: Dictionary=catalog.cooking.for_recipe(id).recipe
	for kind: String in recipe.required_steps:
		if not dish.steps.any(func(s:Dictionary)->bool:return s.operation==kind): return TDOutcome.new(false,"NOT_PERFECT")
	_s.unlocked.append(id); _record("recipe_unlock",0,{},id,{"dish_id":dish.dish_id})
	return TDOutcome.new(true,"RECIPE_UNLOCKED","提前解锁："+recipe.name)

func mastery(id: String) -> Dictionary:
	var points: float=float(_s.get("mastery",{}).get(family_id(id),0.0))
	return {"points":points,"threshold":400.0,"automatic_available":points>=400.0,"recipe_id":family_id(id)}

func observe_mastery(dish: Dictionary) -> TDOutcome:
	if not kitchen_available() or not str(dish.get("session_id","")).begins_with(day_namespace()) or dish.get("state") not in ["plated","delivered"]: return TDOutcome.new(false,"INVALID_DISH")
	var id: String=str(dish.get("recipe_id","")); var identity: String=str(dish.get("dish_id",""))
	if not is_unlocked(id) or identity.is_empty() or dish.get("failed_dish",false) or dish.get("production_mode","manual")!="manual": return TDOutcome.new(false,"NOT_MANUAL_RECIPE")
	if _s.mastery_dishes.has(identity): return TDOutcome.new(true,"MASTERY_ALREADY_RECORDED")
	if not dish.get("missing_required") is Array or not dish.missing_required.is_empty(): return TDOutcome.new(false,"INCOMPLETE_RECIPE")
	var score: Variant=dish.get("performance_score")
	if not (score is float or score is int) or not is_finite(float(score)) or score<0 or score>100: return TDOutcome.new(false,"INVALID_PERFORMANCE")
	_s.mastery_dishes[identity]=true
	if float(score)<80.0: return TDOutcome.new(true,"MASTERY_BELOW_TARGET")
	_s.mastery[id]=minf(1000000.0,float(_s.mastery.get(id,0))+float(score))
	return TDOutcome.new(true,"MASTERY_GAINED","%s 手艺 +%.1f · %.1f/400%s"%[recipe_name(id),score,float(_s.mastery[id])," · 已可自动制作" if float(_s.mastery[id])>=400 else ""],mastery(id))

func store_food(data: Dictionary) -> TDOutcome:
	if not kitchen_available(): return TDOutcome.new(false,"KITCHEN_UNAVAILABLE")
	var checked:=_check_food(data)
	if not checked.ok: return checked
	if int(data.get("expires_on",0))>0 and int(data.expires_on)<=int(_s.day): return TDOutcome.new(false,"FOOD_EXPIRED","食材已过期，不能再入库。")
	if _s.cold_foods.any(func(f:Dictionary)->bool:return f.id==data.id): return TDOutcome.new(false,"DUPLICATE")
	var stored: Dictionary=data.duplicate(true)
	if int(stored.get("expires_on",0))==0: stored.expires_on=int(_s.day)+int(stock_rules.get(stored.ingredient_id,{}).get("shelf_days",3))
	_s.cold_foods.append(stored); _kitchen_key=""
	return TDOutcome.new(true,"FOOD_STORED","已放回冰箱，切型和处理结果保留。")

func stored_food(id: String) -> Dictionary:
	for food: Dictionary in _s.cold_foods:
		if food.id==id: return food.duplicate(true)
	return {}

func take_stored(id: String) -> TDOutcome:
	if not kitchen_available(): return TDOutcome.new(false,"KITCHEN_UNAVAILABLE")
	for i: int in _s.cold_foods.size():
		if _s.cold_foods[i].id==id:
			var food: Dictionary=_s.cold_foods.pop_at(i); _kitchen_key=""
			return TDOutcome.new(true,"FOOD_TAKEN","",food)
	return TDOutcome.new(false,"NOT_FOUND")

func _check_food(data: Variant) -> TDOutcome:
	if not data is Dictionary or not catalog.config.costs.has(data.get("ingredient_id")): return TDOutcome.new(false,"INVALID_STORED_FOOD")
	var model:=TDCookingModel.new("storage-validation",1,catalog.cooking.for_recipe("service.tomato_egg"),{"pc_controls":true,"document_rules":true})
	return model.restore_portable(data)

func snapshot() -> Dictionary:
	return _s.duplicate(true)

func kitchen_available() -> bool:
	if kitchen_gate.is_valid() and not kitchen_gate.call(): return false
	return _s.get("phase","") in ["PREPARE","OPEN","DRAINING","SETTLED"]

func arrival_interval_sec() -> float:
	if commerce!=null: return float(catalog.config.settings.day_sec)/float(commerce.config.slots_per_day)
	return float(catalog.config.settings.arrival_sec)*(1.3-float(_s.popularity)/200.0)

func visitor_forecast() -> Dictionary:
	if commerce!=null: return commerce.forecast(economic_menu(true),float(day_minute_reader.call()) if day_minute_reader.is_valid() else -1.0)
	# No RNG draw: consulting the forecast cannot change who arrives next.
	var center: int=ceili(maxf(0,float(catalog.config.settings.day_sec)-1.0)/arrival_interval_sec())
	var uncertainty: float=float(catalog.config.settings.get("forecast_uncertainty_percent",20))/100.0
	return {"day":int(_s.day),"min_visitors":floori(center*(1.0-uncertainty)),"max_visitors":ceili(center*(1.0+uncertainty)),"expected_visitors":center}

func offer(id: String) -> Dictionary:
	var original: Dictionary = catalog.offer(id)
	if not original.is_empty(): return original
	for entry: Dictionary in _s.custom:
		if entry.id == id:
			var value: Dictionary = catalog.offer(entry.plan.recipe_id)
			value.id = id; value.name = entry.name; value.custom_entry = entry.duplicate(true)
			return value
	return {}

func recipe_name(id: String) -> String:
	var item: Dictionary = offer(id)
	if item.has("custom_entry"): return str(item.custom_entry.name)
	return str(catalog.cooking.for_recipe(id).get("recipe",{}).get("name",id))

func order(id: String) -> Dictionary:
	for item: Dictionary in _s.orders:
		if item.id == id: return item.duplicate(true)
	return {}

func _order_index(id: String) -> int:
	for i: int in _s.orders.size():
		if _s.orders[i].id == id: return i
	return -1

func available(id: String) -> int:
	return int(_s.inventory.get(id,0))

static func amount_cost(units: int, cents_per_portion: int) -> int:
	return roundi(float(units) * cents_per_portion / 1000.0)

func kit_cost(id: String, missing_only: bool = false) -> int:
	var total: int = 0
	for ingredient: String in offer(id).get("stock",{}):
		var units: int = int(offer(id).stock[ingredient])
		if missing_only: units = maxi(0,units - available(ingredient))
		total += amount_cost(units,int(catalog.config.costs[ingredient]))
	return total

func buy(cart: Dictionary, token: String, price_override: Dictionary = {}) -> TDOutcome:
	if _s.phase != "PREPARE": return TDOutcome.new(false,"NOT_PREPARING")
	if token.is_empty() or _s.seen.has(token): return TDOutcome.new(false,"DUPLICATE")
	if cart.is_empty(): return TDOutcome.new(false,"EMPTY_CART")
	var cost: int = 0; var change: Dictionary = {}
	for id: Variant in cart:
		if not market_sells(str(id)): return TDOutcome.new(false,"INGREDIENT_LOCKED","原料不可购买；特色调料需先开放对应菜系。")
		if not catalog.config.costs.has(id) or not TDServiceCatalog.integer(cart[id],1,100000) or int(_s.inventory[id])+int(cart[id])>1000000: return TDOutcome.new(false,"INVALID_QUANTITY")
		if price_override.has(id) and not TDServiceCatalog.integer(price_override[id],1,10000000): return TDOutcome.new(false,"INVALID_QUOTE")
		change[id] = int(cart[id]); cost += amount_cost(int(cart[id]),int(price_override.get(id,catalog.config.costs[id])))
	if cost > int(_s.money_cents): return TDOutcome.new(false,"INSUFFICIENT_FUNDS")
	_s.seen[token] = true; _record("purchase",-cost,change,token)
	return TDOutcome.new(true,"PURCHASED","",{"cost_cents":cost})

func world_adjustment(delta_cents: int, token: String, label: String) -> TDOutcome:
	if _s.phase not in ["PREPARE","SETTLED"]: return TDOutcome.new(false,"NOT_AT_BOUNDARY")
	if token.is_empty() or _s.seen.has(token): return TDOutcome.new(false,"DUPLICATE")
	if absi(delta_cents)>100000000 or int(_s.money_cents)+delta_cents<0: return TDOutcome.new(false,"INSUFFICIENT_FUNDS")
	_s.seen[token]=true
	_record("world_adjustment",delta_cents,{},token,{"label":label})
	if commerce!=null and delta_cents>0: _pay_economic_debt()
	return TDOutcome.new(true,"RECORDED")

func bank_adjustment(delta_cents: int, token: String, action: String) -> TDOutcome:
	if _s.phase not in ["PREPARE","SETTLED"]: return TDOutcome.new(false,"NOT_AT_BOUNDARY")
	if token.is_empty() or _s.seen.has(token): return TDOutcome.new(false,"DUPLICATE")
	if absi(delta_cents)>100000000 or int(_s.money_cents)+delta_cents<0: return TDOutcome.new(false,"INSUFFICIENT_FUNDS")
	_s.seen[token]=true;_record("bank_transfer",delta_cents,{},token,{"action":action})
	return TDOutcome.new(true,"BANK_RECORDED")

func branch_adjustment(cents: int, token: String, label: String, store_id: String) -> TDOutcome:
	if token.is_empty() or _s.seen.has(token): return TDOutcome.new(false,"DUPLICATE")
	if (not store_id.begins_with("player-branch:") and store_id not in ["player_diner","employee-roster","supplier-network"]) or absi(cents)>100000000 or int(_s.money_cents)+cents<0: return TDOutcome.new(false,"INSUFFICIENT_FUNDS","可用现金不足，未扣款。")
	_s.seen[token]=true
	_record("branch_transfer",cents,{},token,{"label":label,"store_id":store_id})
	return TDOutcome.new(true,"BRANCH_RECORDED")

func receive_supply(units: Dictionary, token: String, inventory_cost_cents: int = 0, continuous: bool = false) -> TDOutcome:
	if inventory_cost_cents<0: return TDOutcome.new(false,"INVALID_COST")
	if _s.phase not in ["PREPARE","SETTLED"] and not continuous: return TDOutcome.new(false,"NOT_AT_BOUNDARY")
	if token.is_empty() or _s.seen.has(token): return TDOutcome.new(false,"DUPLICATE")
	if units.is_empty(): return TDOutcome.new(false,"EMPTY_DELIVERY")
	for id: Variant in units:
		if not _s.inventory.has(id) or not TDServiceCatalog.integer(units[id],1,1000000) or int(_s.inventory[id])+int(units[id])>1000000: return TDOutcome.new(false,"STOCK_CAPACITY")
	_s.seen[token]=true;_record("supply_delivery",0,units,token,{"inventory_cost_cents":inventory_cost_cents})
	return TDOutcome.new(true,"RECEIVED","订货已送入厨房库存。")

func set_menu(id: String, enabled: bool, price_cents: int) -> TDOutcome:
	if _s.phase != "PREPARE" or offer(id).is_empty(): return TDOutcome.new(false,"INVALID_MENU")
	if enabled and not is_unlocked(family_id(id)): return TDOutcome.new(false,"RECIPE_NOT_UNLOCKED")
	if price_cents < 1 or price_cents > 1000000: return TDOutcome.new(false,"INVALID_PRICE")
	_s.menu[id] = {"enabled":enabled,"price_cents":price_cents}
	return TDOutcome.new(true,"MENU_UPDATED")

func configure_menu(chosen: Array) -> TDOutcome:
	# Stage the entire menu: a bad row must never leave half-applied prices behind.
	if _s.phase not in ["PREPARE","SETTLED"]: return TDOutcome.new(false,"NOT_AT_BOUNDARY","请在筹备或日结后调整菜单。")
	if chosen.is_empty() or chosen.size()>_s.menu.size(): return TDOutcome.new(false,"EMPTY_MENU","请至少选择一道已掌握的菜。")
	var next: Dictionary=_s.menu.duplicate(true);var seen: Dictionary={}
	for id: String in next: next[id].enabled=false
	for row: Variant in chosen:
		if not row is Dictionary or not row.get("id") is String or not next.has(row.id) or seen.has(row.id) or offer(row.id).is_empty() or not is_unlocked(family_id(row.id)): return TDOutcome.new(false,"INVALID_MENU","菜单中有未掌握、重复或未知的菜谱。")
		if not TDServiceCatalog.integer(row.get("price_cents"),1,1000000): return TDOutcome.new(false,"INVALID_PRICE","价格必须在0.01至10000金币之间。")
		seen[row.id]=true;next[row.id]={"enabled":true,"price_cents":int(row.price_cents)}
	_s.menu=next
	return TDOutcome.new(true,"MENU_UPDATED","菜单与价格已更新。")

func sold_out(id: String) -> TDOutcome:
	if not _s.menu.has(id): return TDOutcome.new(false,"UNKNOWN_RECIPE")
	_s.menu[id].enabled = false
	return TDOutcome.new(true,"SOLD_OUT")

func open_day(random_source: RefCounted = null) -> TDOutcome:
	if _s.phase != "PREPARE": return TDOutcome.new(false,"INVALID_STATE")
	if _s.menu.values().filter(func(x:Dictionary)->bool:return x.enabled).is_empty(): return TDOutcome.new(false,"EMPTY_MENU")
	if before_open.is_valid(): before_open.call()
	_s.phase = "OPEN"; _s.elapsed_sec = 0.0; _s.orders = []; _next_arrival = 1.0
	_s.day_open_money_cents = int(_s.money_cents)
	_s.day_open_popularity = int(_s.popularity)
	_day_end_reason = "time"
	_kitchen_key=""
	_rng = random_source if random_source != null else TDBusinessRandom.new(int(_s.seed)+int(_s.day))
	if commerce!=null:
		if day_minute_reader.is_valid():
			_opening_minute=float(day_minute_reader.call())
			commerce.skip_closed_before(_opening_minute)
			_next_arrival=_scheduled_arrival()
		commerce.begin_day()
	day_opened.emit()
	return TDOutcome.new(true,"OPENED")

func advance(seconds: float, paused: bool = false) -> TDOutcome:
	if not is_finite(seconds) or seconds < 0: return TDOutcome.new(false,"INVALID_TIME")
	if paused: return TDOutcome.new(true,"IDLE")
	if _s.phase not in ["OPEN","DRAINING"]:
		_tick_dining(seconds)
		return TDOutcome.new(true,"IDLE")
	_tick_dining(0.0)
	tick_crew(seconds)
	var end: float = float(_s.elapsed_sec)+seconds
	for iteration: int in 1024:
		var next: float = end
		if _s.phase == "OPEN": next = minf(next,minf(_next_arrival,business_close_sec()))
		for item: Dictionary in _s.orders:
			if item.status in ["ARRIVING","WAITING","COOKING"]: next = minf(next,float(item.deadline_sec))
		if dining_boundary.is_valid(): next=minf(next,float(_s.elapsed_sec)+maxf(.0000001,float(dining_boundary.call(next-float(_s.elapsed_sec)))))
		var step: float=next-float(_s.elapsed_sec)
		_s.elapsed_sec = next
		for item: Dictionary in _s.orders.duplicate(true):
			if item.status in ["ARRIVING","WAITING","COOKING"] and next >= float(item.deadline_sec): cancel_order(item.id,"TIMED_OUT")
		_tick_dining(step)
		if _s.phase == "OPEN" and next >= business_close_sec(): _s.phase = "DRAINING"
		if _s.phase == "OPEN" and next >= _next_arrival:
			_arrive()
			_next_arrival = _scheduled_arrival() if day_minute_reader.is_valid() and commerce!=null else _next_arrival+arrival_interval_sec()
		_tick_dining(0.0)
		if _s.phase == "DRAINING" and pending_orders().is_empty():
			var settled:=settle_day()
			_tick_dining(maxf(0.0,end-next))
			return settled
		if next >= end: return TDOutcome.new(true,"ADVANCED")
	return TDOutcome.new(false,"TIME_LIMIT")

func _tick_dining(seconds: float) -> void:
	if dining_tick.is_valid(): dining_tick.call(seconds)

func next_boundary(maximum: float) -> float:
	# Expire orders before allowing cooking callbacks beyond a business boundary.
	if _s.phase not in ["OPEN","DRAINING"]: return maximum
	var target: float=float(_s.elapsed_sec)+maximum
	if _s.phase=="OPEN": target=minf(target,minf(_next_arrival,business_close_sec()))
	for item: Dictionary in _s.orders:
		if item.status in ["ARRIVING","WAITING","COOKING"]: target=minf(target,float(item.deadline_sec))
	if dining_boundary.is_valid(): target=minf(target,float(_s.elapsed_sec)+maxf(.0000001,float(dining_boundary.call(target-float(_s.elapsed_sec)))))
	return maxf(.0000001,target-float(_s.elapsed_sec))

func economic_menu(assume_restocked: bool = false) -> Array:
	var result: Array=[]
	var definitions: Array=catalog.cooking.data().ingredients
	for id: String in _s.menu:
		if not _s.menu[id].enabled or (not assume_restocked and not menu_available(id)): continue
		var family:=family_id(id)
		var entry:=offer(id)
		var taste: Dictionary={}
		for flavor: int in TDEconomicCustomer.TASTES.size():
			var total: float=0.0;var count: int=0
			for ingredient: Dictionary in definitions:
				if ingredient.id in entry.get("primary",[]) and ingredient.get("base_tastes") is Array:
					total+=float(ingredient.base_tastes[flavor])/100.0;count+=1
			taste[TDEconomicCustomer.TASTES[flavor]]=total/maxi(1,count)
		result.append({"id":id,"family_id":family,"price_cents":int(_s.menu[id].price_cents),"reference_cents":int(entry.reference_cents),"available":true,"taste":taste,"culture":str(recipe_cultures.get(family,"chinese"))})
	return result

func _arrive_economic() -> void:
	var slot:=floori(maxf(0,float(_s.elapsed_sec)-1.0)/arrival_interval_sec()+0.000001)
	var arrivals: Array
	if day_minute_reader.is_valid(): arrivals=commerce.arrivals_at(_opening_minute+float(_s.elapsed_sec),economic_menu(),pending_orders().size(),int(catalog.config.settings.max_orders),catalog.cooking.data().customers,float(catalog.config.settings.patience_sec))
	else: arrivals=commerce.arrivals(slot,economic_menu(),pending_orders().size(),int(catalog.config.settings.max_orders),catalog.cooking.data().customers,float(catalog.config.settings.patience_sec))
	for arrival: Dictionary in arrivals:
		var id: String=arrival.intent.recipe_id
		var customer: Dictionary=arrival.template.duplicate(true)
		customer.id=arrival.person.id
		customer.name=commerce.config.groups.filter(func(g:Dictionary)->bool:return g.id==arrival.intent.group_id)[0].name
		if arrival.person.has("display_name"): customer.name=str(arrival.person.display_name)
		if family_id(id)!="service.tomato_egg": customer.requirements=customer.requirements.filter(func(r:Dictionary)->bool:return str(r.get("ingredient_id","")).is_empty())
		if not menu_available(id,customer) and menu_available(id):
			var relaxed: Dictionary=customer.duplicate(true)
			var kept: Array=[]
			for requirement: Dictionary in customer.get("requirements",[]):
				if str(requirement.get("kind",""))!="flavor": kept.append(requirement)
			relaxed.requirements=kept
			if menu_available(id,relaxed): customer=relaxed
		if not menu_available(id,customer):
			commerce.society.release(arrival.intent.opportunity_id)
			commerce.state.day_stats.admitted-=1
			commerce.state.day_stats.capacity_rejected+=1
			continue
		_s.order_serial+=1
		var identity: String="%s:d%d:o%d"%[_s.run_id,_s.day,_s.order_serial]
		_s.orders.append(_prepare_arrival({"id":identity,"recipe_id":id,"family_id":family_id(id),"culture":str(recipe_cultures.get(family_id(id),"chinese")),"status":"WAITING","price_cents":int(arrival.intent.quoted_cents),"reference_cents":int(arrival.reference_cents),"customer":customer,"economic_profile":arrival.person,"economic_intent":arrival.intent,"arrival_sec":float(_s.elapsed_sec),"deadline_sec":float(_s.elapsed_sec)+guest_patience(float(arrival.intent.patience_seconds)),"lane":-1,"reserved":{},"used":{},"prepaid_cents":0,"refunded_cents":0,"tip_cents":0,"dish_id":"","score":{},"plan":{}}))

func _economic_review(item: Dictionary) -> void:
	if item.status!="SERVED" and item.has("economic_intent"): commerce.society.release(item.economic_intent.opportunity_id)
	item.finished_sec=float(_s.elapsed_sec)
	item.visit_review=commerce.record_visit(item)

func _pay_economic_debt() -> void:
	var paid:=commerce.pay_debt(int(_s.money_cents))
	if paid>0: _record("operating_payment",-paid,{},"fees:%d:%d"%[_s.day,_s.serial+1])

func _arrive() -> void:
	if commerce!=null:
		_arrive_economic()
		return
	var menu: Array = []
	var profiles: Array = catalog.cooking.data().customers
	var prospective: Dictionary=profiles[int(_s.order_serial)%profiles.size()].duplicate(true)
	for id: String in _s.menu:
		if _s.menu[id].enabled and menu_available(id,prospective): menu.append(id)
	if menu.is_empty() or pending_orders().size() >= int(catalog.config.settings.max_orders): return
	var id: String = menu[mini(menu.size()-1,int(float(_rng.call("unit"))*menu.size()))]
	_s.order_serial += 1
	var customer: Dictionary = profiles[(int(_s.order_serial)-1)%profiles.size()].duplicate(true)
	# Remove tomato-only texture requests for unrelated recipes; do not invent hidden requirements.
	var definition: Dictionary=offer(id)
	var base_id: String=str(definition.custom_entry.plan.recipe_id) if definition.has("custom_entry") else id
	if base_id != "service.tomato_egg":
		customer.requirements = customer.requirements.filter(func(r:Dictionary)->bool:return str(r.get("ingredient_id","")).is_empty())
		customer.name = "偏甜的客人" if int(_s.order_serial)%2==1 else "偏鲜的客人"
	var identity: String = "%s:d%d:o%d" % [_s.run_id,_s.day,_s.order_serial]
	_s.orders.append(_prepare_arrival({"id":identity,"recipe_id":id,"status":"WAITING","price_cents":int(_s.menu[id].price_cents),"customer":customer,"deadline_sec":float(_s.elapsed_sec)+guest_patience(float(catalog.config.settings.patience_sec)),"lane":-1,"reserved":{},"used":{},"prepaid_cents":0,"refunded_cents":0,"tip_cents":0,"dish_id":"","score":{},"plan":{}}))

func _prepare_arrival(item: Dictionary) -> Dictionary:
	item.arrival_sec=float(_s.elapsed_sec)
	if require_seating:
		item.status="ARRIVING"
		item.patience_seconds=float(item.deadline_sec)-float(item.arrival_sec)
		item.deadline_sec=float(_s.elapsed_sec)+float(catalog.config.settings.get("arrival_wait_sec",120.0))
	return item

func confirm_seated(id: String, seat_id: String) -> TDOutcome:
	var index:=_order_index(id)
	if index<0 or seat_id.is_empty(): return TDOutcome.new(false,"INVALID_VISIT")
	var item: Dictionary=_s.orders[index]
	if item.has("ordered_sec"):
		return TDOutcome.new(true,"ALREADY_ORDERED") if item.get("seat_id")==seat_id else TDOutcome.new(false,"SEAT_MISMATCH")
	if _s.phase not in ["OPEN","DRAINING"] or item.status!="ARRIVING": return TDOutcome.new(false,"STALE_VISIT")
	if float(_s.elapsed_sec)>=float(item.deadline_sec): return TDOutcome.new(false,"VISIT_EXPIRED")
	if id in _allocation().rejected: return cancel_order(id,"REJECTED_STOCK")
	item.status="WAITING";item.seat_id=seat_id;item.ordered_sec=float(_s.elapsed_sec)
	item.deadline_sec=float(_s.elapsed_sec)+float(item.patience_seconds)
	return TDOutcome.new(true,"ORDERED","已落座点单。",{"id":id,"seat_id":seat_id})

func pending_orders() -> Array:
	return _s.orders.filter(func(x:Dictionary)->bool:return x.status in ["ARRIVING","WAITING","COOKING"]).duplicate(true)

func active_orders() -> Array:
	return _s.orders.filter(func(x:Dictionary)->bool:return x.status in ["WAITING","COOKING"]).duplicate(true)

func order_label(id: String) -> String:
	var item:=order(id)
	var name: String=str(item.get("economic_profile",{}).get("display_name",""))
	return name if name!="" else "%02d号客人"%int(id.get_slice(":o",1))

func cancel_order(id: String, reason: String = "CANCELLED") -> TDOutcome:
	var i: int = _order_index(id)
	if i < 0: return TDOutcome.new(false,"UNKNOWN_ORDER")
	var item: Dictionary = _s.orders[i]
	if item.status not in ["ARRIVING","WAITING","COOKING"]: return TDOutcome.new(false,"ALREADY_FINISHED")
	item.status = reason if reason in ["TIMED_OUT","REJECTED_STOCK"] else "CANCELLED"
	item.refunded_cents = int(item.prepaid_cents)
	_record("refund_cancel",-int(item.prepaid_cents),{},id,{"waste":item.used.duplicate(true),"reason":item.status})
	_apply_popularity(-(int(catalog.config.settings.get("stock_rejection_popularity",1)) if reason=="REJECTED_STOCK" else 2), item)
	if commerce!=null: _economic_review(item)
	if reason=="REJECTED_STOCK": item.feedback="食材不足，未能供应这道菜。"
	return TDOutcome.new(true,item.status)

func can_deliver(id: String, dish: Dictionary) -> TDOutcome:
	var item: Dictionary = order(id)
	if item.is_empty() or item.status not in ["WAITING","COOKING"]: return TDOutcome.new(false,"INVALID_ORDER")
	if not dish.get("failed_dish",false) and dish.get("recipe_id") != family_id(item.recipe_id): return TDOutcome.new(false,"WRONG_ORDER")
	if first_order_for(dish).get("id")!=id: return TDOutcome.new(false,"EARLIER_MATCHING_ORDER")
	if not dish.get("session_id") is String or not dish.session_id.begins_with(day_namespace()): return TDOutcome.new(false,"WRONG_ORDER_SESSION")
	if dish.get("state") not in ["plated","delivered"] or not dish.get("dish_id") is String or dish.dish_id.is_empty(): return TDOutcome.new(false,"INVALID_DISH")
	for other: Dictionary in _s.orders:
		if other.dish_id == dish.dish_id: return TDOutcome.new(false,"DUPLICATE_DISH")
	if dish.get("failed_dish",false):
		return TDOutcome.new(true,"FAILED_DISH","",{"satisfaction":0.0,"quality":0.0,"harmony":0.0,"stars":0,"reasons":[{"message":"收到无法食用的失败菜品。","penalty":100.0,"source":"failed_dish"}]})
	return scorer.evaluate(dish,item.customer)

func guest_patience(base: float) -> float:
	return base * (crew.cook_pace() if crew != null else 1.0)

var _crew_jobs: Dictionary = {}
var _crew_skip: Dictionary = {}
var _crew_note: String = ""
var crew_external: bool = false
var crew_status_source: Callable
var cook_step_source: Callable
var cook_job_source: Callable

func cook_job_id(person_id: String) -> String:
	if crew_external:
		return str(cook_job_source.call(person_id)) if cook_job_source.is_valid() else ""
	for id: String in _crew_jobs:
		if str(_crew_jobs[id].get("cook_id",""))==person_id: return id
	return ""

func crew_work(person_id: String) -> String:
	if crew_external:
		return str(crew_status_source.call(person_id)) if crew_status_source.is_valid() else ""
	for job: Variant in _crew_jobs.values():
		var record: Dictionary = job
		if str(record.get("cook_id", "")) != person_id:
			continue
		if bool(record.get("paused", false)):
			return ""
		return "缺料" if bool(record.get("blocked", false)) else "做菜"
	return ""

func cook_step(person_id: String) -> String:
	if crew_external:
		return str(cook_step_source.call(person_id)) if cook_step_source.is_valid() else ""
	if crew == null:
		return ""
	var steps: Array[String] = ["取料", "切菜", "热锅", "翻炒", "调味", "出餐"]
	for job: Variant in _crew_jobs.values():
		var record: Dictionary = job
		if str(record.get("cook_id", "")) != person_id or bool(record.get("paused", false)) or bool(record.get("blocked", false)):
			continue
		var total: float = crew.cook_seconds(person_id)
		var left: float = float(record.get("left", total))
		var done: float = clampf(1.0 - left / maxf(0.001, total), 0.0, 0.999)
		return steps[mini(steps.size() - 1, int(done * float(steps.size())))]
	return ""

func take_crew_note() -> String:
	var text := _crew_note
	_crew_note = ""
	return text

func tick_crew(seconds: float) -> void:
	# A real kitchen owns formal-game production. Do not also run the legacy timer.
	if crew_external: return
	if crew == null or not is_finite(seconds) or seconds <= 0.0 or _s.phase not in ["OPEN", "DRAINING"]:
		return
	var cooks := crew.cooks()
	if cooks.is_empty():
		_crew_jobs.clear()
		return
	var open_orders := {}
	for live: Dictionary in _s.orders:
		if str(live.get("status", "")) in ["WAITING", "COOKING"]:
			open_orders[str(live.id)] = live
	var stale: Array[String] = []
	for job_id: Variant in _crew_jobs.keys():
		if not open_orders.has(String(job_id)):
			stale.append(String(job_id))
	for skipped_id: Variant in _crew_skip.keys():
		if not open_orders.has(String(skipped_id)):
			stale.append(String(skipped_id))
	for stale_id: String in stale:
		_crew_jobs.erase(stale_id)
		_crew_skip.erase(stale_id)
	var busy := {}
	for record: Variant in _crew_jobs.values():
		busy[str((record as Dictionary).get("cook_id", ""))] = true
	var idle_cooks: Array[Dictionary] = []
	for cook: Dictionary in cooks:
		if not busy.has(str(cook.get("id", ""))):
			idle_cooks.append(cook)
	for item: Dictionary in _s.orders:
		if idle_cooks.is_empty():
			break
		var waiting_id := str(item.get("id", ""))
		if str(item.get("status", "")) != "WAITING" or _crew_jobs.has(waiting_id) or _crew_skip.has(waiting_id):
			continue
		if _hands_on_recipe(family_id(str(item.get("recipe_id", "")))):
			continue
		var next_cook: Dictionary = idle_cooks[0]
		idle_cooks.remove_at(0)
		var index := _order_index(waiting_id)
		if index < 0:
			continue
		_s.orders[index].status = "COOKING"
		_crew_jobs[waiting_id] = {"cook_id": str(next_cook.get("id", "")), "left": crew.cook_seconds(str(next_cook.get("id", ""))), "blocked": false, "paused": false}
	var finished: Array[String] = []
	for job_key: Variant in _crew_jobs.keys():
		var order_id := String(job_key)
		var job: Dictionary = _crew_jobs[order_id]
		var recipe_id := str(open_orders.get(order_id, {}).get("recipe_id", ""))
		if _hands_on_recipe(family_id(recipe_id)):
			job.paused = true
			continue
		job.paused = false
		job.left = float(job.get("left", 0.0)) - seconds
		if float(job.left) > 0.0:
			continue
		var plated := _crew_plate(order_id)
		if plated.code == "INSUFFICIENT_STOCK":
			if not bool(job.get("blocked", false)):
				_crew_note = "后厨缺料，厨师还做不了这单。"
			job.blocked = true
			job.left = 1.0
		elif plated.code == "EARLIER_MATCHING_ORDER":
			job.left = 0.25
		elif plated.ok:
			var who := crew.person(str(job.get("cook_id", "")))
			var spoken := "%s做好了%s。" % [str(who.get("name", "厨师")), recipe_name(str(plated.data.get("recipe_id", recipe_id)))]
			_crew_note = spoken if _crew_note.is_empty() else _crew_note + spoken
			finished.append(order_id)
		elif plated.code == "GONE":
			finished.append(order_id)
		else:
			_crew_skip[order_id] = true
			_crew_note = "厨师没能把这单做出餐台。"
			finished.append(order_id)
	for done_id: String in finished:
		_crew_jobs.erase(done_id)

func _hands_on_recipe(family: String) -> bool:
	if family.is_empty():
		return false
	for entry: Dictionary in _kitchen:
		var dish: Dictionary = entry.get("dish", {})
		if str(dish.get("recipe_id", "")) != family:
			continue
		var foods: Variant = dish.get("ingredients", {})
		var steps: Variant = dish.get("steps", [])
		if str(dish.get("state", "")) in ["operating", "plated"]:
			return true
		if foods is Dictionary and not (foods as Dictionary).is_empty():
			return true
		if steps is Array and not (steps as Array).is_empty():
			return true
	return false

func _crew_plate(order_id: String) -> TDOutcome:
	var item := order(order_id)
	if item.is_empty() or str(item.get("status", "")) not in ["WAITING", "COOKING"]:
		return TDOutcome.new(false, "GONE")
	var family := family_id(str(item.get("recipe_id", "")))
	var profile := profile_for(item)
	if profile == null:
		return TDOutcome.new(false, "NO_PROFILE", "厨师没有这道菜的做法。")
	var template := catalog.cooking.for_recipe(family)
	if template.is_empty():
		return TDOutcome.new(false, "NO_RECIPE", "厨师不会这道菜。")
	var needs: Dictionary = catalog.material_needs(profile, family, [])
	var units := {}
	for ingredient_id: Variant in needs.keys():
		var amount := int(needs[ingredient_id])
		if amount <= 0:
			continue
		if available(String(ingredient_id)) < amount:
			return TDOutcome.new(false, "INSUFFICIENT_STOCK", "后厨缺料。")
		units[String(ingredient_id)] = amount
	var session := TDCookingSession.new(day_namespace() + "crew:" + order_id, 1, template, {"pc_controls": true})
	var dish: Dictionary = session.snapshot().to_dict()
	dish.state = "delivered"
	dish.dish_id = day_namespace() + "crew-plate:" + order_id
	if not dish.get("dish_attributes") is Dictionary:
		return TDOutcome.new(false, "INVALID_DISH", "厨师没有做出可出餐的菜。")
	_crew_aim(dish, item.get("customer", {}))
	var preview := can_deliver(order_id, dish)
	if not preview.ok:
		return preview
	if not units.is_empty():
		var consumed := consume_materials(day_namespace() + "crew-stock:" + order_id, units)
		if not consumed.ok:
			return consumed
	var rows: Array = []
	for ingredient_id: Variant in units.keys():
		rows.append({"ingredient_id": String(ingredient_id), "amount": float(units[ingredient_id]) / 1000.0})
	dish.consumed_ingredients = rows
	return deliver(order_id, dish)

func _crew_aim(dish: Dictionary, customer: Variant) -> void:
	var attributes: Dictionary = dish.dish_attributes
	attributes.completion = 85.0
	attributes.harmony = 85.0
	if not customer is Dictionary or not (customer as Dictionary).get("requirements") is Array:
		return
	var foods: Dictionary = {}
	var steps: Array = []
	var existing: Variant = dish.get("steps", [])
	if existing is Array:
		steps = (existing as Array).duplicate()
	for requirement: Variant in (customer as Dictionary).requirements:
		if not requirement is Dictionary:
			continue
		var ask: Dictionary = requirement
		var target := _crew_midpoint(ask)
		if is_nan(target):
			continue
		var kind := str(ask.get("kind", ""))
		match kind:
			"flavor":
				var taste := int(ask.get("taste", -1))
				var slot := int(ask.get("slot", -1))
				var matrix: Variant = attributes.get("flavor", [])
				if matrix is Array and taste >= 0 and taste < (matrix as Array).size() and slot >= 0:
					var row: Variant = (matrix as Array)[taste]
					if row is Array and slot < (row as Array).size():
						(row as Array)[slot] = target
			"temperature":
				attributes.temperature_c = target
			"aroma":
				var tag := str(ask.get("tag", ""))
				if tag.is_empty():
					continue
				if not attributes.get("aroma") is Dictionary:
					attributes.aroma = {}
				attributes.aroma[tag] = target
			"texture":
				var axis := str(ask.get("axis", ""))
				if axis in ["A", "B", "C"]:
					if str(ask.get("ingredient_id", "")).is_empty():
						if not attributes.get("texture") is Dictionary:
							attributes.texture = {"A": 0.0, "B": 0.0, "C": 0.0}
						attributes.texture[axis] = target
					else:
						_crew_food(foods, str(ask.ingredient_id)).texture[axis] = target
			"fine":
				if not str(ask.get("ingredient_id", "")).is_empty():
					_crew_food(foods, str(ask.ingredient_id)).fine = clampf(target, 0.0, 1.0)
			"ingredient":
				if not str(ask.get("ingredient_id", "")).is_empty():
					_crew_food(foods, str(ask.ingredient_id)).amount = maxf(target, 0.0)
			"step":
				var operation := str(ask.get("operation", ""))
				if operation.is_empty():
					continue
				var have := 0
				for step: Variant in steps:
					if step is Dictionary and str((step as Dictionary).get("operation", "")) == operation:
						have += 1
				while float(have) + 0.0001 < target:
					steps.append({"operation": operation, "parameters": {}, "quality": 0.85})
					have += 1
	if not foods.is_empty():
		dish.ingredients = foods
	dish.steps = steps

func _crew_food(foods: Dictionary, ingredient_id: String) -> Dictionary:
	if not foods.has(ingredient_id):
		foods[ingredient_id] = {
			"ingredient_id": ingredient_id,
			"fine": 0.5,
			"amount": 1.0,
			"texture": {"A": 0.0, "B": 0.0, "C": 0.0},
		}
	return foods[ingredient_id]

func _crew_midpoint(requirement: Dictionary) -> float:
	var has_min := requirement.get("min") is float or requirement.get("min") is int
	var has_max := requirement.get("max") is float or requirement.get("max") is int
	if has_min and has_max:
		return (float(requirement.min) + float(requirement.max)) * 0.5
	if has_min:
		return float(requirement.min)
	if has_max:
		return float(requirement.max)
	return NAN

func accrue_wage(cents: int, reference: String) -> TDOutcome:
	if cents<0 or reference.is_empty() or commerce==null: return TDOutcome.new(false,"INVALID_WAGE")
	if _s.seen.has(reference): return TDOutcome.new(true,"ALREADY_ACCRUED")
	_s.seen[reference]=true
	if cents>0:
		commerce.state.debt_cents+=cents
		_record("wage",0,{},reference,{"label":"员工当日日薪","wage_expense_cents":cents})
	return TDOutcome.new(true,"WAGE_ACCRUED")

func pay_wage(cents: int, reference: String) -> TDOutcome:
	if cents <= 0 or reference.is_empty():
		return TDOutcome.new(false, "INVALID_WAGE", "工资无效。")
	if int(_s.money_cents) < cents:
		return TDOutcome.new(false, "BROKE", "手头不够付今日日薪。")
	_record("wage", -cents, {}, reference, {"label": "雇员日薪"})
	return TDOutcome.new(true, "PAID", "已支付日薪。")

func deliver(id: String, dish: Dictionary) -> TDOutcome:
	if dish.get("state")!="delivered": return TDOutcome.new(false,"NOT_DELIVERED")
	var preview := order(id)
	var customer: Dictionary = preview.get("customer", {}) if preview.get("customer") is Dictionary else {}
	var plated: Dictionary = dish if crew == null or preview.is_empty() else crew.apply_dish(dish, customer)
	var scored := can_deliver(id, plated)
	if not scored.ok: return scored
	var item: Dictionary = _s.orders[_order_index(id)]
	if dish.get("failed_dish",false):
		if commerce!=null and item.has("economic_intent"): commerce.society.release(item.economic_intent.opportunity_id)
		item.status="SERVED"; item.dish_id=dish.dish_id; item.score=scored.data; item.plan={}; item.feedback="误送失败菜品，客人差评离开。"
		_apply_popularity(-int(catalog.config.settings.get("failed_dish_popularity",4)), item)
		_record("failed_delivery",0,{},id,{"dish_id":dish.dish_id})
		if commerce!=null: _economic_review(item);_pay_economic_debt()
		return TDOutcome.new(true,"SERVED",item.feedback,item)
	var requested_tip:=roundi(float(item.price_cents)*maxf(0.0,float(scored.data.satisfaction)-80.0)/200.0 * (crew.tip_scale() if crew != null else 1.0))
	if commerce!=null and item.has("economic_intent"):
		var paid:=commerce.society.pay(item.economic_intent.opportunity_id,requested_tip)
		if not paid.ok: return paid
		requested_tip=int(paid.data.tip_cents)
	if item.status in ["WAITING", "COOKING"] and int(item.prepaid_cents) == 0:
		item.prepaid_cents=int(item.price_cents); _record("prepayment",int(item.price_cents),{},id,{"timing":"delivery"})
		for food: Dictionary in dish.get("consumed_ingredients",[]): item.used[food.ingredient_id]=int(item.used.get(food.ingredient_id,0))+roundi(float(food.amount)*1000)
		item.reserved=item.used.duplicate(true)
	item.status = "SERVED"; item.dish_id = dish.dish_id; item.score = scored.data; item.plan = dish.get("custom_plan",{}).duplicate(true)
	var satisfaction: float = float(scored.data.satisfaction)
	item.tip_cents = requested_tip
	_record("tip",int(item.tip_cents),{},id)
	var ratio: float = float(item.price_cents)/float(offer(item.recipe_id).reference_cents)
	var pricing: float = -30.0*(ratio-1.0) if ratio > 1.0 else 5.0*(1.0-ratio)
	if commerce==null: _apply_popularity(roundi(pricing+(satisfaction-60.0)/20.0), item)
	_s.fame[item.recipe_id] = maxi(0,int(_s.fame.get(item.recipe_id,0))+roundi((satisfaction-50.0)/10.0))
	if satisfaction < float(catalog.config.settings.refund_below): refund(id)
	if commerce!=null: _economic_review(item);_pay_economic_debt()
	if cooking_reward.is_valid(): cooking_reward.call(int(_s.day),family_id(item.recipe_id),satisfaction)
	var growth := ""
	if crew != null:
		growth = "，".join(PackedStringArray(crew.record_served_order()))
	return TDOutcome.new(true,"SERVED",growth,item)

func refund(id: String) -> TDOutcome:
	var i: int = _order_index(id)
	if i < 0 or _s.orders[i].status != "SERVED": return TDOutcome.new(false,"INVALID_ORDER")
	var item: Dictionary = _s.orders[i]
	if int(item.refunded_cents) > 0: return TDOutcome.new(false,"DUPLICATE")
	if commerce!=null and _s.phase not in ["OPEN","DRAINING"]: return TDOutcome.new(false,"NOT_OPEN")
	if int(_s.money_cents)<int(item.prepaid_cents)+int(item.tip_cents): return TDOutcome.new(false,"INSUFFICIENT_FUNDS")
	if commerce!=null and item.has("economic_intent"):
		var refunded:=commerce.society.refund(item.economic_intent.opportunity_id,int(item.prepaid_cents)+int(item.tip_cents))
		if not refunded.ok: return refunded
	item.refunded_cents = int(item.prepaid_cents)+int(item.tip_cents)
	_record("refund_served",-int(item.refunded_cents),{},id)
	return TDOutcome.new(true,"REFUNDED")

func close_early() -> TDOutcome:
	if _s.phase != "OPEN": return TDOutcome.new(false,"INVALID_STATE")
	_day_end_reason = "early"
	_s.phase = "DRAINING"
	if pending_orders().is_empty(): return settle_day()
	return TDOutcome.new(true,"DRAINING")

func close_for_night() -> TDOutcome:
	if _s.phase=="SETTLED": return TDOutcome.new(true,"ALREADY_SETTLED")
	if _s.phase not in ["PREPARE","OPEN","DRAINING"]: return TDOutcome.new(false,"INVALID_STATE")
	_day_end_reason="night"
	# Suppress new arrivals before ending existing orders through their usual path.
	_s.phase="DRAINING"
	for item: Dictionary in pending_orders():
		var cancelled:=cancel_order(str(item.id),"TIMED_OUT")
		if not cancelled.ok: return cancelled
	if _s.phase=="SETTLED": return TDOutcome.new(true,"SETTLED")
	return settle_day()

func note_night_cleanup(returned: int, waste: Dictionary) -> void:
	var token:=day_namespace()+"night-cleanup"
	if _s.seen.has(token): return
	_s.seen[token]=true
	_record("night_cleanup",0,{},token,{"returned_portions":returned,"waste":waste.duplicate(true)})

func settle_day() -> TDOutcome:
	if _s.phase != "DRAINING" or not pending_orders().is_empty() or int(_s.day) in _s.settled_days: return TDOutcome.new(false,"INVALID_SETTLEMENT")
	if before_settlement.is_valid(): before_settlement.call()
	if commerce!=null:
		var summary:=day_summary()
		commerce.settle(_s.ledger,int(summary.received_cents)+int(summary.tip_cents)-int(summary.refunded_cents),_s.has("day_open_money_cents"))
		_pay_economic_debt()
		var account:=commerce.society.bank.account("player")
		var due: int=int(account.interest_cents)+(int(account.principal_cents) if int(account.due_day)>0 and int(_s.day)>=int(account.due_day) else 0)
		if due>0 and int(_s.money_cents)>0:
			var payment:=commerce.society.bank.transact("player","repay",mini(due,int(_s.money_cents)),int(_s.money_cents),int(_s.day),"player:daily:%s:%d"%[_s.run_id,_s.day],true)
			if payment.ok: _record("bank_transfer",int(payment.data.cash_delta_cents),{},str(payment.data.token),{"action":"repay","interest_paid_cents":payment.data.interest_paid_cents})
		_s.popularity=roundi(commerce.state.popularity)
	_s.settled_days.append(int(_s.day)); _s.phase = "SETTLED"; _record("settlement",0,{},"day-%d" % _s.day,{"reason":_day_end_reason})
	day_settled.emit(int(_s.day))
	return TDOutcome.new(true,"SETTLED")

func next_day(expected_day: int) -> TDOutcome:
	if _s.phase != "SETTLED" or int(_s.day) != expected_day: return TDOutcome.new(false,"DUPLICATE_DAY")
	_s.day += 1; _s.phase = "PREPARE"; _s.elapsed_sec = 0.0; _s.orders = []
	_s.erase("day_open_money_cents"); _s.erase("day_open_popularity")
	var expired: Dictionary=TDFoodStock.expired(_s.inventory_lots,int(_s.day))
	var delta: Dictionary={}
	for id: String in expired: delta[id]=-int(expired[id])
	var cold_expired: Array=_s.cold_foods.filter(func(f:Dictionary)->bool:return int(f.get("expires_on",int(_s.day)+1))<=int(_s.day))
	_s.cold_foods=_s.cold_foods.filter(func(f:Dictionary)->bool:return int(f.get("expires_on",int(_s.day)+1))>int(_s.day))
	if not delta.is_empty() or not cold_expired.is_empty(): _record("spoilage",0,delta,"expiry:%d"%int(_s.day),{"cold_foods":cold_expired})
	_s.mastery_dishes={} # All kitchen sessions are cleared at the same day boundary.
	return TDOutcome.new(true,"NEXT_DAY","新的一天，过期食材已清理。" if not delta.is_empty() or not cold_expired.is_empty() else "新的一天开始了。")

func spoiled_today() -> Dictionary:
	var totals: Dictionary={}
	for event: Dictionary in _s.ledger:
		if int(event.day)!=int(_s.day) or event.kind!="spoilage": continue
		for id: String in event.inventory_delta: totals[id]=int(totals.get(id,0))-int(event.inventory_delta[id])
		for food: Dictionary in event.extra.get("cold_foods",[]): totals[food.ingredient_id]=int(totals.get(food.ingredient_id,0))+roundi(float(food.amount)*1000)
	return totals

func day_summary() -> Dictionary:
	var purchased := 0
	var received := 0
	var tips := 0
	var refunded := 0
	var grant := 0
	var world_net := 0
	var operating_paid := 0
	var bank_net := 0
	var reason := ""
	for event: Dictionary in _s.ledger:
		if int(event.day) != int(_s.day):
			continue
		match String(event.kind):
			"purchase":
				purchased += -int(event.cents)
			"prepayment":
				received += int(event.cents)
			"tip":
				tips += int(event.cents)
			"refund_cancel", "refund_served":
				refunded += -int(event.cents)
			"emergency_grant":
				grant += int(event.cents)
			"world_adjustment", "branch_transfer":
				world_net += int(event.cents)
			"operating_payment":
				operating_paid += -int(event.cents)
			"bank_transfer": bank_net+=int(event.cents)
			"settlement":
				reason = str(event.extra.get("reason", ""))
	var rows: Array = []
	var summed_popularity := 0
	for item: Dictionary in _s.orders:
		var row := _order_effect(item)
		summed_popularity += int(row.popularity_delta)
		rows.append(row)
	var net := received + tips - refunded - purchased + grant + world_net - operating_paid + bank_net
	var open_money := int(_s.get("day_open_money_cents", int(_s.money_cents) - (received + tips - refunded)))
	var open_popularity := int(_s.get("day_open_popularity", int(_s.popularity) - summed_popularity))
	return {
		"day": int(_s.day),
		"spoiled_units": spoiled_today(),
		"reason": reason,
		"purchased_cents": purchased,
		"received_cents": received,
		"tip_cents": tips,
		"refunded_cents": refunded,
		"grant_cents": grant,
		"world_net_cents": world_net,
		"operating_paid_cents": operating_paid,
		"bank_net_cents": bank_net,
		"economy": commerce.state.books.back().duplicate(true) if commerce!=null and not commerce.state.books.is_empty() and int(commerce.state.books.back().day)==int(_s.day) else {},
		"net_cents": net,
		"open_money_cents": open_money,
		"money_cents": int(_s.money_cents),
		"service_cents": int(_s.money_cents) - open_money,
		"open_popularity": open_popularity,
		"popularity": int(_s.popularity),
		"popularity_delta": int(_s.popularity) - open_popularity,
		"orders": rows,
	}

func _apply_popularity(delta: int, item: Dictionary) -> void:
	if commerce!=null: item.popularity_delta=0;return
	var before := int(_s.popularity)
	_s.popularity = clampi(before + delta, 0, 100)
	item.popularity_delta = int(_s.popularity) - before

func _order_effect(item: Dictionary) -> Dictionary:
	var failed := _failed_order(item)
	var delta := int(item.popularity_delta) if item.has("popularity_delta") else _legacy_popularity_delta(item, failed)
	var score: Dictionary = item.score
	var fame := 0
	if item.status == "SERVED" and not score.is_empty() and not failed:
		fame = roundi((float(score.satisfaction) - 50.0) / 10.0)
	return {
		"id": str(item.id),
		"recipe_id": str(item.recipe_id),
		"name": recipe_name(str(item.recipe_id)),
		"customer": str(item.customer.get("name", "客人")),
		"status": str(item.status),
		"money_cents": int(item.prepaid_cents) + int(item.tip_cents) - int(item.refunded_cents),
		"tip_cents": int(item.tip_cents),
		"refunded_cents": int(item.refunded_cents),
		"satisfaction": float(score.satisfaction) if not score.is_empty() else -1.0,
		"stars": int(score.get("stars", 0)) if not score.is_empty() else 0,
		"reasons": score.get("reasons", []).duplicate(true),
		"feedback": str(item.get("feedback", "")),
		"popularity_delta": delta,
		"fame_delta": fame,
		"failed": failed,
	}

func _failed_order(item: Dictionary) -> bool:
	if str(item.get("feedback", "")).begins_with("误送失败"):
		return true
	for event: Dictionary in _s.ledger:
		if event.kind == "failed_delivery" and str(event.reference) == str(item.id):
			return true
	return false

func _legacy_popularity_delta(item: Dictionary, failed: bool) -> int:
	if item.status == "REJECTED_STOCK":
		return -int(catalog.config.settings.get("stock_rejection_popularity", 1))
	if item.status in ["CANCELLED", "TIMED_OUT"]:
		return -2
	if failed:
		return -int(catalog.config.settings.get("failed_dish_popularity", 4))
	if item.status != "SERVED" or item.score.is_empty():
		return 0
	var ratio := float(item.price_cents) / float(offer(str(item.recipe_id)).reference_cents)
	var pricing := -30.0 * (ratio - 1.0) if ratio > 1.0 else 5.0 * (1.0 - ratio)
	return roundi(pricing + (float(item.score.satisfaction) - 60.0) / 20.0)

func claim_grant() -> TDOutcome:
	if _s.phase != "PREPARE" or int(_s.day) < 2 or int(_s.day) in _s.grant_days: return TDOutcome.new(false,"GRANT_UNAVAILABLE")
	var minimum: int = 1000000000
	for item: Dictionary in catalog.config.offers: minimum = mini(minimum,kit_cost(item.id,true))
	if int(_s.money_cents) >= minimum: return TDOutcome.new(false,"GRANT_NOT_NEEDED")
	_s.grant_days.append(int(_s.day)); _record("emergency_grant",int(catalog.config.settings.grant_cents),{},"grant-%d" % _s.day)
	if commerce!=null: _pay_economic_debt()
	return TDOutcome.new(true,"GRANTED")

func save_plan(title: String, plan: Dictionary, identity: String = "") -> TDOutcome:
	if _s.phase not in ["PREPARE","SETTLED"]: return TDOutcome.new(false,"NOT_AT_BOUNDARY")
	if title.strip_edges().is_empty() or title.length()>60 or catalog.offer(str(plan.get("recipe_id",""))).is_empty(): return TDOutcome.new(false,"INVALID_PLAN")
	var checked := TDRecipeLibrary.new("",catalog.cooking.data()).validate_plan(plan)
	if not checked.ok or checked.data.get("scope") == "TEST_ONLY": return TDOutcome.new(false,"INVALID_PLAN",checked.code)
	var index: int = -1; var version: int = 1
	if not identity.is_empty():
		for i: int in _s.custom.size():
			if _s.custom[i].id == identity: index=i; version=int(_s.custom[i].version)+1
		if index < 0: return TDOutcome.new(false,"UNKNOWN_RECIPE")
	else: identity="custom.%s.%d" % [_s.run_id,_s.custom.size()+1]
	var entry: Dictionary = {"id":identity,"name":title.strip_edges(),"version":version,"scope":"CUSTOM","plan":plan.duplicate(true)}
	var compiled:=catalog.compile_plan(entry)
	if not compiled.ok: return compiled
	if index < 0: _s.custom.append(entry); _s.menu[identity]={"enabled":false,"price_cents":int(offer(identity).reference_cents)}; _s.fame[identity]=0
	else: _s.custom[index]=entry
	return TDOutcome.new(true,"PLAN_SAVED","",entry)

func _record(kind: String, cents: int, inventory_delta: Dictionary, reference: String, extra: Dictionary = {}) -> void:
	_s.serial += 1; _s.money_cents += cents
	for id: String in inventory_delta:
		var units: int=int(inventory_delta[id])
		if units>0: TDFoodStock.add(_s.inventory_lots,id,units,int(_s.day),int(stock_rules.get(id,{}).get("shelf_days",3)))
		elif units<0: TDFoodStock.take(_s.inventory_lots,id,-units)
		_s.inventory[id] += units
	_s.ledger.append({"id":"%s:txn-%d" % [_s.run_id,_s.serial],"day":int(_s.day),"kind":kind,"cents":cents,"inventory_delta":inventory_delta.duplicate(true),"reference":reference,"extra":extra.duplicate(true)})
	if commerce!=null: commerce.sync_costs(_s.ledger)

func restore(data: Variant) -> TDOutcome:
	var checked := validate_save(data)
	if not checked.ok: return checked
	_s = normalize_save(data)
	for id: String in catalog.config.get("material_cost_ids",[]):
		if not _s.inventory.has(id): _s.inventory[id]=0
	_s.material_version=1
	for id:String in catalog.config.get("research_cost_ids",[]):
		if not _s.inventory.has(id): _s.inventory[id]=0
	for item:Dictionary in catalog.config.offers:
		if item.id.begins_with("study.") and not _s.menu.has(item.id):
			_s.menu[item.id]={"enabled":false,"price_cents":int(item.reference_cents)};_s.fame[item.id]=0
	if not _s.has("progress_version"):
		_s.progress_version=1; _s.unlocked=_initial_unlocks(); _s.cold_foods=[]
		for item: Dictionary in catalog.config.offers:
			if not _s.menu.has(item.id): _s.menu[item.id]={"enabled":false,"price_cents":int(item.reference_cents)}; _s.fame[item.id]=0
		for id: String in catalog.config.costs:
			if not _s.inventory.has(id): _s.inventory[id]=0
	if not _s.has("stock_version"):
		_s.stock_version=1; _s.inventory_lots=TDFoodStock.migrate(_s.inventory,int(_s.day),stock_rules)
		for food: Dictionary in _s.cold_foods:
			if int(food.get("expires_on",0))==0: food.expires_on=int(_s.day)+int(stock_rules.get(food.ingredient_id,{}).get("shelf_days",3))
	for id: String in _s.inventory:
		if not _s.inventory_lots.has(id): _s.inventory_lots[id]=[]
	if not _s.has("mastery_version"): _s.mastery_version=1; _s.mastery={}; _s.mastery_dishes={}
	return TDOutcome.new(true,"RESTORED")

static func normalize_save(data: Dictionary) -> Dictionary:
	var value: Dictionary=data.duplicate(true)
	if value.has("stock_version"):
		value.stock_version=int(value.stock_version)
		for lots: Array in value.inventory_lots.values():
			for lot: Dictionary in lots:
				for key: String in ["units","stored_on","expires_on"]: lot[key]=int(lot[key])
	if value.has("mastery_version"):
		value.mastery_version=int(value.mastery_version)
		for id: String in value.mastery: value.mastery[id]=float(value.mastery[id])
	if value.has("progress_version"): value.progress_version=int(value.progress_version)
	for food: Dictionary in value.get("cold_foods",[]):
		if food.has("expires_on"): food.expires_on=int(food.expires_on)
		food.schema_version=int(food.schema_version); food.amount=float(food.amount)
		for cut: Dictionary in food.cuts:
			cut.quality=float(cut.quality); cut.elapsed_sec=float(cut.elapsed_sec)
			for i: int in cut.directions.size(): cut.directions[i]=int(cut.directions[i])
		for entry: Dictionary in food.get("processing_state",{}).get("history",[]):
			if entry.get("operation")=="cut":
				entry.quality=float(entry.quality)
				for i: int in entry.successful_directions.size(): entry.successful_directions[i]=int(entry.successful_directions[i])
	for key: String in ["schema_version","seed","day","money_cents","serial","order_serial","popularity","reputation"]: value[key]=int(value[key])
	for key: String in ["day_open_money_cents","day_open_popularity"]:
		if value.has(key): value[key]=int(value[key])
	for field: String in ["inventory","fame"]:
		for id: String in value[field]: value[field][id]=int(value[field][id])
	for item: Dictionary in value.menu.values(): item.price_cents=int(item.price_cents)
	for field: String in ["settled_days","grant_days"]:
		for i: int in value[field].size(): value[field][i]=int(value[field][i])
	for item: Dictionary in value.ledger:
		item.day=int(item.day); item.cents=int(item.cents)
		for id: String in item.inventory_delta: item.inventory_delta[id]=int(item.inventory_delta[id])
	for item: Dictionary in value.orders:
		for key: String in ["lane","price_cents","prepaid_cents","refunded_cents","tip_cents"]: item[key]=int(item[key])
		if item.has("popularity_delta"): item.popularity_delta=int(item.popularity_delta)
		for field: String in ["reserved","used"]:
			for id: String in item[field]: item[field][id]=int(item[field][id])
	for item: Dictionary in value.custom: item.version=int(item.version)
	return value

func validate_save(data: Variant) -> TDOutcome:
	if not data is Dictionary or data.get("schema_version") != 1: return TDOutcome.new(false,"UNSUPPORTED_VERSION")
	if data.has("material_version") and data.material_version!=1: return TDOutcome.new(false,"UNKNOWN_MATERIAL_VERSION")
	if data.has("stock_version"):
		if data.stock_version!=1 or not data.get("inventory") is Dictionary or not TDServiceCatalog.integer(data.get("day"),1,1000000000) or not TDFoodStock.valid(data.get("inventory_lots"),data.inventory,int(data.day)): return TDOutcome.new(false,"INVALID_STOCK_BATCHES")
	elif data.has("inventory_lots"): return TDOutcome.new(false,"INVALID_STOCK_BATCHES")
	if data.has("mastery_version"):
		if data.mastery_version!=1 or not data.get("mastery") is Dictionary or not data.get("mastery_dishes") is Dictionary: return TDOutcome.new(false,"INVALID_MASTERY")
		for id: Variant in data.mastery:
			if not id is String or catalog.offer(id).is_empty() or not TDServiceCatalog._number(data.mastery[id],0,1000000): return TDOutcome.new(false,"INVALID_MASTERY")
		for id: Variant in data.mastery_dishes:
			if not id is String or id.is_empty() or data.mastery_dishes[id]!=true: return TDOutcome.new(false,"INVALID_MASTERY")
	elif data.has("mastery") or data.has("mastery_dishes"): return TDOutcome.new(false,"INVALID_MASTERY")
	if not data.has("progress_version") and (data.has("unlocked") or data.has("cold_foods")): return TDOutcome.new(false,"INVALID_PROGRESS")
	if data.get("phase") not in ["PREPARE","SETTLED"]: return TDOutcome.new(false,"NOT_AT_BOUNDARY")
	if data.has("progress_version"):
		if data.progress_version!=1: return TDOutcome.new(false,"UNSUPPORTED_VERSION")
		if not data.get("unlocked") is Array or not data.get("cold_foods") is Array: return TDOutcome.new(false,"INVALID_PROGRESS")
		var seen_food: Dictionary={}; var seen_recipe: Dictionary={}
		for id: Variant in data.unlocked:
			if not id is String or catalog.offer(id).is_empty() or seen_recipe.has(id): return TDOutcome.new(false,"INVALID_PROGRESS")
			seen_recipe[id]=true
		for food: Variant in data.cold_foods:
			if not _check_food(food).ok or seen_food.has(food.id): return TDOutcome.new(false,"INVALID_STORED_FOOD")
			if data.has("stock_version") and not TDServiceCatalog.integer(food.get("expires_on"),int(data.day)+1,int(data.day)+1000): return TDOutcome.new(false,"INVALID_STORED_FOOD")
			seen_food[food.id]=true
	for field: String in ["inventory","menu","seen","fame"]:
		if not data.get(field) is Dictionary: return TDOutcome.new(false,"INVALID_SAVE",field)
	for field: String in ["orders","ledger","custom","settled_days","grant_days"]:
		if not data.get(field) is Array: return TDOutcome.new(false,"INVALID_SAVE",field)
	for field: String in ["day","money_cents","seed","serial","order_serial","popularity","reputation"]:
		if not TDServiceCatalog.integer(data.get(field),0,1000000000): return TDOutcome.new(false,"INVALID_SAVE",field)
	if data.day < 1 or data.popularity > 100 or data.reputation != 0 or data.get("reputation_status") != "DEFERRED" or not data.get("run_id") is String or data.run_id.is_empty(): return TDOutcome.new(false,"INVALID_SAVE")
	var recipes: Dictionary = {}; var ids: Dictionary = {}
	for item: Dictionary in catalog.config.offers: recipes[item.id]=true
	for value: Variant in data.custom:
		if not value is Dictionary or not value.get("id") is String or not value.id.begins_with("custom.") or recipes.has(value.id) or not value.get("name") is String or value.name.strip_edges().is_empty() or not TDServiceCatalog.integer(value.get("version"),1,100000): return TDOutcome.new(false,"INVALID_CUSTOM")
		var result := TDRecipeLibrary.new("",catalog.cooking.data()).validate_plan(value.get("plan"))
		if not result.ok or result.data.scope == "TEST_ONLY" or catalog.offer(str(value.plan.recipe_id)).is_empty(): return TDOutcome.new(false,"INVALID_CUSTOM")
		if not catalog.compile_plan(value).ok: return TDOutcome.new(false,"INVALID_CUSTOM")
		recipes[value.id]=true
	for id: Variant in data.menu:
		var item: Variant=data.menu[id]
		if not recipes.has(id) or not item is Dictionary or not item.get("enabled") is bool or not TDServiceCatalog.integer(item.get("price_cents"),1,1000000): return TDOutcome.new(false,"INVALID_MENU")
		if data.has("progress_version") and not catalog.offer(id).is_empty() and item.enabled and id not in data.unlocked: return TDOutcome.new(false,"INVALID_MENU")
	for id: Variant in data.fame:
		if not recipes.has(id) or not TDServiceCatalog.integer(data.fame[id],0,1000000000): return TDOutcome.new(false,"INVALID_FAME")
	for id: String in recipes:
		if data.menu.has(id) and data.fame.has(id): continue
		if id.begins_with("phase3.") or id.begins_with("study."): continue
		if data.has("progress_version") or id!="service.qiguoji": return TDOutcome.new(false,"MISSING_RECIPE_STATE")
	var money: int = int(catalog.config.settings.initial_cents); var inventory: Dictionary = {}
	for id: String in catalog.config.costs: inventory[id]=0
	for event: Variant in data.ledger:
		if not event is Dictionary or not event.get("id") is String or ids.has(event.id) or not event.get("kind") is String or not TDServiceCatalog.integer(event.get("cents"),-1000000000,1000000000) or not event.get("inventory_delta") is Dictionary or not TDServiceCatalog.integer(event.get("day"),1,int(data.day)): return TDOutcome.new(false,"INVALID_LEDGER")
		if not event.get("reference") is String or not event.get("extra") is Dictionary or event.kind not in ["purchase","prepayment","consumption","tip","refund_cancel","refund_served","settlement","emergency_grant","recipe_unlock","failed_delivery","world_adjustment","supply_delivery","operating_payment","bank_transfer","spoilage","wage","night_cleanup","branch_transfer"]: return TDOutcome.new(false,"INVALID_LEDGER")
		if event.kind=="wage" and event.extra.has("wage_expense_cents") and (not TDServiceCatalog.integer(event.extra.wage_expense_cents,0,10000000) or event.cents!=0): return TDOutcome.new(false,"INVALID_WAGE_LEDGER")
		if event.kind=="branch_transfer" and (not event.extra.get("store_id") is String or (not event.extra.store_id.begins_with("player-branch:") and event.extra.store_id not in ["player_diner","employee-roster","supplier-network"]) or not event.extra.get("label") is String): return TDOutcome.new(false,"INVALID_BRANCH_LEDGER")
		if event.kind=="spoilage":
			if int(event.cents)!=0 or not event.extra.get("cold_foods") is Array: return TDOutcome.new(false,"INVALID_LEDGER")
			for quantity: Variant in event.inventory_delta.values():
				if not TDServiceCatalog.integer(quantity,-1000000,-1): return TDOutcome.new(false,"INVALID_LEDGER")
			for food: Variant in event.extra.cold_foods:
				if not _check_food(food).ok: return TDOutcome.new(false,"INVALID_LEDGER")
		if event.extra.has("waste"):
			if not event.extra.waste is Dictionary: return TDOutcome.new(false,"INVALID_LEDGER")
			for id: Variant in event.extra.waste:
				if not inventory.has(id) or not TDServiceCatalog.integer(event.extra.waste[id],0,1000000): return TDOutcome.new(false,"INVALID_LEDGER")
		ids[event.id]=true; money+=int(event.cents)
		for id: Variant in event.inventory_delta:
			if not inventory.has(id) or not TDServiceCatalog.integer(event.inventory_delta[id],-1000000,1000000): return TDOutcome.new(false,"INVALID_LEDGER")
			inventory[id]+=int(event.inventory_delta[id])
	var optional: Array=catalog.config.get("research_cost_ids",[]).duplicate()
	if not data.has("material_version"): optional.append_array(catalog.config.get("material_cost_ids",[]))
	var added_missing:int=0
	for id:String in optional:
		if not data.inventory.has(id): added_missing+=1
	if money != int(data.money_cents) or int(data.serial)!=data.ledger.size() or (data.inventory.size()+added_missing!=inventory.size() and (data.has("progress_version") or data.inventory.size()+added_missing!=inventory.size()-1)): return TDOutcome.new(false,"LEDGER_MISMATCH")
	for id: String in inventory:
		if id in optional and not data.inventory.has(id) and inventory[id]==0: continue
		if id=="mushroom" and not data.has("progress_version") and not data.inventory.has(id): continue
		if not TDServiceCatalog.integer(data.inventory.get(id),0,1000000) or int(data.inventory[id]) != inventory[id]: return TDOutcome.new(false,"STOCK_MISMATCH")
	var order_ids: Dictionary={}
	for item: Variant in data.orders:
		if not item is Dictionary or item.get("status") not in ["SERVED","CANCELLED","TIMED_OUT","REJECTED_STOCK"] or not recipes.has(item.get("recipe_id")) or not item.get("id") is String or order_ids.has(item.id) or not item.id.begins_with(data.run_id+":d%d:" % int(data.day)): return TDOutcome.new(false,"ACTIVE_OR_INVALID_ORDER")
		if item.has("feedback") and not item.feedback is String: return TDOutcome.new(false,"INVALID_ORDER")
		if item.has("patience_seconds"):
			if not TDServiceCatalog._number(item.patience_seconds,.1,1000000) or not TDServiceCatalog._number(item.get("arrival_sec"),0,1000000000): return TDOutcome.new(false,"INVALID_VISIT")
		if item.has("ordered_sec") or item.has("seat_id"):
			if not item.has("patience_seconds") or not TDServiceCatalog._number(item.get("ordered_sec"),float(item.get("arrival_sec",0)),1000000000) or not item.get("seat_id") is String or item.seat_id.is_empty(): return TDOutcome.new(false,"INVALID_VISIT")
		if item.has("economic_intent"):
			if not TDMealIntent.validate(item.economic_intent).ok or not TDEconomicCustomer.validate(item.get("economic_profile")).ok: return TDOutcome.new(false,"INVALID_ECONOMIC_ORDER")
			if item.economic_intent.customer_id!=item.economic_profile.id or item.economic_intent.recipe_id!=item.recipe_id: return TDOutcome.new(false,"INVALID_ECONOMIC_ORDER")
		order_ids[item.id]=true
		for key: String in ["price_cents","prepaid_cents","refunded_cents","tip_cents"]:
			if not TDServiceCatalog.integer(item.get(key),0,1000000000): return TDOutcome.new(false,"INVALID_ORDER_MONEY")
		if not TDServiceCatalog.integer(item.get("lane"),-1,1) or not item.get("dish_id") is String or not item.get("customer") is Dictionary or not item.customer.get("name") is String or not item.customer.get("requirements") is Array: return TDOutcome.new(false,"INVALID_ORDER")
		for requirement: Variant in item.customer.requirements:
			if not requirement is Dictionary or not requirement.get("label") is String: return TDOutcome.new(false,"INVALID_REQUIREMENTS")
		for field: String in ["reserved","used","score","plan"]:
			if not item.get(field) is Dictionary: return TDOutcome.new(false,"INVALID_ORDER",field)
		for field: String in ["reserved","used"]:
			for id: Variant in item[field]:
				if not catalog.config.costs.has(id) or not TDServiceCatalog.integer(item[field][id],0,100000): return TDOutcome.new(false,"INVALID_ORDER_STOCK")
		for id: String in item.used:
			if int(item.used[id])>int(item.reserved.get(id,0)): return TDOutcome.new(false,"INVALID_ORDER_STOCK")
		if not item.score.is_empty():
			for key: String in ["satisfaction","quality","harmony"]:
				if not (item.score.get(key) is int or item.score.get(key) is float) or not is_finite(float(item.score[key])) or item.score[key]<0 or item.score[key]>100: return TDOutcome.new(false,"INVALID_SCORE")
			if not item.score.get("reasons") is Array: return TDOutcome.new(false,"INVALID_SCORE")
			for reason: Variant in item.score.reasons:
				if not reason is Dictionary or not reason.get("message") is String: return TDOutcome.new(false,"INVALID_SCORE")
	for field: String in ["settled_days","grant_days"]:
		var seen_days: Dictionary={}
		for day: Variant in data[field]:
			if not TDServiceCatalog.integer(day,1,int(data.day)) or seen_days.has(int(day)): return TDOutcome.new(false,"INVALID_DAY_HISTORY")
			seen_days[int(day)]=true
	if data.settled_days.size() != int(data.day)-(0 if data.phase=="SETTLED" else 1): return TDOutcome.new(false,"INVALID_DAY_HISTORY")
	for i: int in data.settled_days.size():
		if int(data.settled_days[i])!=i+1: return TDOutcome.new(false,"INVALID_DAY_HISTORY")
	for token: Variant in data.seen:
		if not token is String or token.is_empty() or data.seen[token] != true: return TDOutcome.new(false,"INVALID_RECEIPT")
	if not (data.get("elapsed_sec") is float or data.get("elapsed_sec") is int) or not is_finite(float(data.elapsed_sec)) or data.elapsed_sec<0: return TDOutcome.new(false,"INVALID_TIME")
	return TDOutcome.new(true,"VALID")
