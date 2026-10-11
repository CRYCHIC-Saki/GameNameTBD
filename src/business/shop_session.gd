class_name TDShopSession
extends RefCounted
## Money, orders and stock have one owner. The kitchen provides real dish snapshots.
var catalog: TDServiceCatalog
var scorer := TDCustomerScorer.new()
var _s: Dictionary = {}
var _rng: RefCounted
var _next_arrival: float = 1.0
var _kitchen: Array = []
var _kitchen_key: String = ""
var _day_end_reason: String = "time"

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
	if _s.phase not in ["OPEN","DRAINING"] or not token.begins_with(day_namespace()): return TDOutcome.new(false,"STALE_MATERIAL_REQUEST")
	if _s.seen.has(token): return TDOutcome.new(false,"DUPLICATE")
	if units.is_empty(): return TDOutcome.new(false,"EMPTY_CART")
	var delta: Dictionary={}
	for id: Variant in units:
		if not catalog.config.costs.has(id) or not TDServiceCatalog.integer(units[id],1,100000): return TDOutcome.new(false,"INVALID_QUANTITY")
		if available(id)<int(units[id]): return TDOutcome.new(false,"INSUFFICIENT_STOCK","材料不足，本次加料未生效。")
		delta[id]=-int(units[id])
	_s.seen[token]=true; _record("consumption",0,delta,token)
	return TDOutcome.new(true,"CONSUMED")

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
	var requests: Array=active_orders()
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

func _init(content: TDServiceCatalog, run_id: String = "", seed_value: int = 101) -> void:
	catalog = content
	var identity: String = run_id if not run_id.is_empty() else "shop-%d-%d" % [Time.get_unix_time_from_system(),Time.get_ticks_usec()]
	var inventory: Dictionary = {}; var menu: Dictionary = {}; var fame: Dictionary = {}
	for id: String in catalog.config.costs: inventory[id] = 0
	for item: Dictionary in catalog.config.offers:
		menu[item.id] = {"enabled":item.id == "service.tomato_egg","price_cents":int(item.reference_cents)}; fame[item.id] = 0
	_s = {"schema_version":1,"run_id":identity,"seed":seed_value,"day":1,"phase":"PREPARE","elapsed_sec":0.0,"money_cents":int(catalog.config.settings.initial_cents),"inventory":inventory,"menu":menu,"orders":[],"ledger":[],"seen":{},"custom":[],"serial":0,"order_serial":0,"popularity":int(catalog.config.settings.initial_popularity),"reputation":0,"reputation_status":"DEFERRED","fame":fame,"settled_days":[],"grant_days":[]}
	_rng = TDBusinessRandom.new(seed_value)
	_s.cold_foods=[]; _s.unlocked=_initial_unlocks(); _s.progress_version=1

func _initial_unlocks() -> Array:
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
	if _s.phase not in ["OPEN","DRAINING"] or not str(dish.get("session_id","")).begins_with(day_namespace()) or dish.get("state") not in ["plated","delivered"]: return TDOutcome.new(false,"INVALID_DISH")
	if catalog.offer(id).is_empty() or dish.get("failed_dish",false): return TDOutcome.new(false,"UNKNOWN_RECIPE")
	if is_unlocked(id): return TDOutcome.new(true,"ALREADY_UNLOCKED")
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

func store_food(data: Dictionary) -> TDOutcome:
	if _s.phase not in ["OPEN","DRAINING"]: return TDOutcome.new(false,"NOT_OPEN")
	var checked:=_check_food(data)
	if not checked.ok: return checked
	if _s.cold_foods.any(func(f:Dictionary)->bool:return f.id==data.id): return TDOutcome.new(false,"DUPLICATE")
	_s.cold_foods.append(data.duplicate(true)); _kitchen_key=""
	return TDOutcome.new(true,"FOOD_STORED","已放回冰箱，切型和处理结果保留。")

func stored_food(id: String) -> Dictionary:
	for food: Dictionary in _s.cold_foods:
		if food.id==id: return food.duplicate(true)
	return {}

func take_stored(id: String) -> TDOutcome:
	if _s.phase not in ["OPEN","DRAINING"]: return TDOutcome.new(false,"NOT_OPEN")
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

func arrival_interval_sec() -> float:
	return float(catalog.config.settings.arrival_sec)*(1.3-float(_s.popularity)/200.0)

func visitor_forecast() -> Dictionary:
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

func buy(cart: Dictionary, token: String) -> TDOutcome:
	if _s.phase != "PREPARE": return TDOutcome.new(false,"NOT_PREPARING")
	if token.is_empty() or _s.seen.has(token): return TDOutcome.new(false,"DUPLICATE")
	if cart.is_empty(): return TDOutcome.new(false,"EMPTY_CART")
	var cost: int = 0; var change: Dictionary = {}
	for id: Variant in cart:
		if not catalog.config.costs.has(id) or not TDServiceCatalog.integer(cart[id],1,100000) or int(_s.inventory[id])+int(cart[id])>1000000: return TDOutcome.new(false,"INVALID_QUANTITY")
		change[id] = int(cart[id]); cost += amount_cost(int(cart[id]),int(catalog.config.costs[id]))
	if cost > int(_s.money_cents): return TDOutcome.new(false,"INSUFFICIENT_FUNDS")
	_s.seen[token] = true; _record("purchase",-cost,change,token)
	return TDOutcome.new(true,"PURCHASED","",{"cost_cents":cost})

func set_menu(id: String, enabled: bool, price_cents: int) -> TDOutcome:
	if _s.phase != "PREPARE" or offer(id).is_empty(): return TDOutcome.new(false,"INVALID_MENU")
	if enabled and not is_unlocked(family_id(id)): return TDOutcome.new(false,"RECIPE_NOT_UNLOCKED")
	if price_cents < 1 or price_cents > 1000000: return TDOutcome.new(false,"INVALID_PRICE")
	_s.menu[id] = {"enabled":enabled,"price_cents":price_cents}
	return TDOutcome.new(true,"MENU_UPDATED")

func sold_out(id: String) -> TDOutcome:
	if not _s.menu.has(id): return TDOutcome.new(false,"UNKNOWN_RECIPE")
	_s.menu[id].enabled = false
	return TDOutcome.new(true,"SOLD_OUT")

func open_day(random_source: RefCounted = null) -> TDOutcome:
	if _s.phase != "PREPARE": return TDOutcome.new(false,"INVALID_STATE")
	if _s.menu.values().filter(func(x:Dictionary)->bool:return x.enabled).is_empty(): return TDOutcome.new(false,"EMPTY_MENU")
	_s.phase = "OPEN"; _s.elapsed_sec = 0.0; _s.orders = []; _next_arrival = 1.0
	_s.day_open_money_cents = int(_s.money_cents)
	_s.day_open_popularity = int(_s.popularity)
	_day_end_reason = "time"
	_kitchen.clear()
	_rng = random_source if random_source != null else TDBusinessRandom.new(int(_s.seed)+int(_s.day))
	return TDOutcome.new(true,"OPENED")

func advance(seconds: float, paused: bool = false) -> TDOutcome:
	if not is_finite(seconds) or seconds < 0: return TDOutcome.new(false,"INVALID_TIME")
	if paused or _s.phase not in ["OPEN","DRAINING"]: return TDOutcome.new(true,"IDLE")
	var end: float = float(_s.elapsed_sec)+seconds
	for iteration: int in 1024:
		var next: float = end
		if _s.phase == "OPEN": next = minf(next,minf(_next_arrival,float(catalog.config.settings.day_sec)))
		for item: Dictionary in _s.orders:
			if item.status in ["WAITING","COOKING"]: next = minf(next,float(item.deadline_sec))
		_s.elapsed_sec = next
		for item: Dictionary in _s.orders.duplicate(true):
			if item.status in ["WAITING","COOKING"] and next >= float(item.deadline_sec): cancel_order(item.id,"TIMED_OUT")
		if _s.phase == "OPEN" and next >= float(catalog.config.settings.day_sec): _s.phase = "DRAINING"
		if _s.phase == "OPEN" and next >= _next_arrival:
			_arrive()
			_next_arrival += arrival_interval_sec()
		if _s.phase == "DRAINING" and active_orders().is_empty(): return settle_day()
		if next >= end: return TDOutcome.new(true,"ADVANCED")
	return TDOutcome.new(false,"TIME_LIMIT")

func next_boundary(maximum: float) -> float:
	# Expire orders before allowing cooking callbacks beyond a business boundary.
	if _s.phase not in ["OPEN","DRAINING"]: return maximum
	var target: float=float(_s.elapsed_sec)+maximum
	if _s.phase=="OPEN": target=minf(target,minf(_next_arrival,float(catalog.config.settings.day_sec)))
	for item: Dictionary in _s.orders:
		if item.status in ["WAITING","COOKING"]: target=minf(target,float(item.deadline_sec))
	return maxf(.0000001,target-float(_s.elapsed_sec))

func _arrive() -> void:
	var menu: Array = []
	var profiles: Array = catalog.cooking.data().customers
	var prospective: Dictionary=profiles[int(_s.order_serial)%profiles.size()].duplicate(true)
	for id: String in _s.menu:
		if _s.menu[id].enabled and menu_available(id,prospective): menu.append(id)
	if menu.is_empty() or active_orders().size() >= int(catalog.config.settings.max_orders): return
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
	_s.orders.append({"id":identity,"recipe_id":id,"status":"WAITING","price_cents":int(_s.menu[id].price_cents),"customer":customer,"deadline_sec":float(_s.elapsed_sec)+float(catalog.config.settings.patience_sec),"lane":-1,"reserved":{},"used":{},"prepaid_cents":0,"refunded_cents":0,"tip_cents":0,"dish_id":"","score":{},"plan":{}})

func active_orders() -> Array:
	return _s.orders.filter(func(x:Dictionary)->bool:return x.status in ["WAITING","COOKING"]).duplicate(true)

func cancel_order(id: String, reason: String = "CANCELLED") -> TDOutcome:
	var i: int = _order_index(id)
	if i < 0: return TDOutcome.new(false,"UNKNOWN_ORDER")
	var item: Dictionary = _s.orders[i]
	if item.status not in ["WAITING","COOKING"]: return TDOutcome.new(false,"ALREADY_FINISHED")
	item.status = reason if reason in ["TIMED_OUT","REJECTED_STOCK"] else "CANCELLED"
	item.refunded_cents = int(item.prepaid_cents)
	_record("refund_cancel",-int(item.prepaid_cents),{},id,{"waste":item.used.duplicate(true),"reason":item.status})
	_apply_popularity(-(int(catalog.config.settings.get("stock_rejection_popularity",1)) if reason=="REJECTED_STOCK" else 2), item)
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

func deliver(id: String, dish: Dictionary) -> TDOutcome:
	if dish.get("state")!="delivered": return TDOutcome.new(false,"NOT_DELIVERED")
	var scored := can_deliver(id,dish)
	if not scored.ok: return scored
	var item: Dictionary = _s.orders[_order_index(id)]
	if dish.get("failed_dish",false):
		item.status="SERVED"; item.dish_id=dish.dish_id; item.score=scored.data; item.plan={}; item.feedback="误送失败菜品，客人差评离开。"
		_apply_popularity(-int(catalog.config.settings.get("failed_dish_popularity",4)), item)
		_record("failed_delivery",0,{},id,{"dish_id":dish.dish_id})
		return TDOutcome.new(true,"SERVED",item.feedback,item)
	if item.status=="WAITING":
		item.prepaid_cents=int(item.price_cents); _record("prepayment",int(item.price_cents),{},id,{"timing":"delivery"})
		for food: Dictionary in dish.get("consumed_ingredients",[]): item.used[food.ingredient_id]=int(item.used.get(food.ingredient_id,0))+roundi(float(food.amount)*1000)
		item.reserved=item.used.duplicate(true)
	item.status = "SERVED"; item.dish_id = dish.dish_id; item.score = scored.data; item.plan = dish.get("custom_plan",{}).duplicate(true)
	var satisfaction: float = float(scored.data.satisfaction)
	item.tip_cents = roundi(float(item.price_cents)*maxf(0.0,satisfaction-80.0)/200.0)
	_record("tip",int(item.tip_cents),{},id)
	var ratio: float = float(item.price_cents)/float(offer(item.recipe_id).reference_cents)
	var pricing: float = -30.0*(ratio-1.0) if ratio > 1.0 else 5.0*(1.0-ratio)
	_apply_popularity(roundi(pricing+(satisfaction-60.0)/20.0), item)
	_s.fame[item.recipe_id] = maxi(0,int(_s.fame.get(item.recipe_id,0))+roundi((satisfaction-50.0)/10.0))
	if satisfaction < float(catalog.config.settings.refund_below): refund(id)
	return TDOutcome.new(true,"SERVED","",item)

func refund(id: String) -> TDOutcome:
	var i: int = _order_index(id)
	if i < 0 or _s.orders[i].status != "SERVED": return TDOutcome.new(false,"INVALID_ORDER")
	var item: Dictionary = _s.orders[i]
	if int(item.refunded_cents) > 0: return TDOutcome.new(false,"DUPLICATE")
	item.refunded_cents = int(item.prepaid_cents)+int(item.tip_cents)
	_record("refund_served",-int(item.refunded_cents),{},id)
	return TDOutcome.new(true,"REFUNDED")

func close_early() -> TDOutcome:
	if _s.phase != "OPEN": return TDOutcome.new(false,"INVALID_STATE")
	_day_end_reason = "early"
	_s.phase = "DRAINING"
	if active_orders().is_empty(): return settle_day()
	return TDOutcome.new(true,"DRAINING")

func settle_day() -> TDOutcome:
	if _s.phase != "DRAINING" or not active_orders().is_empty() or int(_s.day) in _s.settled_days: return TDOutcome.new(false,"INVALID_SETTLEMENT")
	_s.settled_days.append(int(_s.day)); _s.phase = "SETTLED"; _record("settlement",0,{},"day-%d" % _s.day,{"reason":_day_end_reason})
	return TDOutcome.new(true,"SETTLED")

func next_day(expected_day: int) -> TDOutcome:
	if _s.phase != "SETTLED" or int(_s.day) != expected_day: return TDOutcome.new(false,"DUPLICATE_DAY")
	_s.day += 1; _s.phase = "PREPARE"; _s.elapsed_sec = 0.0; _s.orders = []
	_s.erase("day_open_money_cents"); _s.erase("day_open_popularity")
	return TDOutcome.new(true,"NEXT_DAY")

func day_summary() -> Dictionary:
	var purchased := 0
	var received := 0
	var tips := 0
	var refunded := 0
	var grant := 0
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
			"settlement":
				reason = str(event.extra.get("reason", ""))
	var rows: Array = []
	var summed_popularity := 0
	for item: Dictionary in _s.orders:
		var row := _order_effect(item)
		summed_popularity += int(row.popularity_delta)
		rows.append(row)
	var net := received + tips - refunded - purchased + grant
	var open_money := int(_s.get("day_open_money_cents", int(_s.money_cents) - (received + tips - refunded)))
	var open_popularity := int(_s.get("day_open_popularity", int(_s.popularity) - summed_popularity))
	return {
		"day": int(_s.day),
		"reason": reason,
		"purchased_cents": purchased,
		"received_cents": received,
		"tip_cents": tips,
		"refunded_cents": refunded,
		"grant_cents": grant,
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
	for id: String in inventory_delta: _s.inventory[id] += int(inventory_delta[id])
	_s.ledger.append({"id":"%s:txn-%d" % [_s.run_id,_s.serial],"day":int(_s.day),"kind":kind,"cents":cents,"inventory_delta":inventory_delta.duplicate(true),"reference":reference,"extra":extra.duplicate(true)})

func restore(data: Variant) -> TDOutcome:
	var checked := validate_save(data)
	if not checked.ok: return checked
	_s = normalize_save(data)
	if not _s.has("progress_version"):
		_s.progress_version=1; _s.unlocked=_initial_unlocks(); _s.cold_foods=[]
		for item: Dictionary in catalog.config.offers:
			if not _s.menu.has(item.id): _s.menu[item.id]={"enabled":false,"price_cents":int(item.reference_cents)}; _s.fame[item.id]=0
		for id: String in catalog.config.costs:
			if not _s.inventory.has(id): _s.inventory[id]=0
	return TDOutcome.new(true,"RESTORED")

static func normalize_save(data: Dictionary) -> Dictionary:
	var value: Dictionary=data.duplicate(true)
	if value.has("progress_version"): value.progress_version=int(value.progress_version)
	for food: Dictionary in value.get("cold_foods",[]):
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
		if id.begins_with("phase3."): continue
		if data.has("progress_version") or id!="service.qiguoji": return TDOutcome.new(false,"MISSING_RECIPE_STATE")
	var money: int = int(catalog.config.settings.initial_cents); var inventory: Dictionary = {}
	for id: String in catalog.config.costs: inventory[id]=0
	for event: Variant in data.ledger:
		if not event is Dictionary or not event.get("id") is String or ids.has(event.id) or not event.get("kind") is String or not TDServiceCatalog.integer(event.get("cents"),-1000000000,1000000000) or not event.get("inventory_delta") is Dictionary or not TDServiceCatalog.integer(event.get("day"),1,int(data.day)): return TDOutcome.new(false,"INVALID_LEDGER")
		if not event.get("reference") is String or not event.get("extra") is Dictionary or event.kind not in ["purchase","prepayment","consumption","tip","refund_cancel","refund_served","settlement","emergency_grant","recipe_unlock","failed_delivery"]: return TDOutcome.new(false,"INVALID_LEDGER")
		if event.extra.has("waste"):
			if not event.extra.waste is Dictionary: return TDOutcome.new(false,"INVALID_LEDGER")
			for id: Variant in event.extra.waste:
				if not inventory.has(id) or not TDServiceCatalog.integer(event.extra.waste[id],0,1000000): return TDOutcome.new(false,"INVALID_LEDGER")
		ids[event.id]=true; money+=int(event.cents)
		for id: Variant in event.inventory_delta:
			if not inventory.has(id) or not TDServiceCatalog.integer(event.inventory_delta[id],-1000000,1000000): return TDOutcome.new(false,"INVALID_LEDGER")
			inventory[id]+=int(event.inventory_delta[id])
	if money != int(data.money_cents) or int(data.serial)!=data.ledger.size() or (data.inventory.size()!=inventory.size() and (data.has("progress_version") or data.inventory.size()!=inventory.size()-1)): return TDOutcome.new(false,"LEDGER_MISMATCH")
	for id: String in inventory:
		if id=="mushroom" and not data.has("progress_version") and not data.inventory.has(id): continue
		if not TDServiceCatalog.integer(data.inventory.get(id),0,1000000) or int(data.inventory[id]) != inventory[id]: return TDOutcome.new(false,"STOCK_MISMATCH")
	var order_ids: Dictionary={}
	for item: Variant in data.orders:
		if not item is Dictionary or item.get("status") not in ["SERVED","CANCELLED","TIMED_OUT","REJECTED_STOCK"] or not recipes.has(item.get("recipe_id")) or not item.get("id") is String or order_ids.has(item.id) or not item.id.begins_with(data.run_id+":d%d:" % int(data.day)): return TDOutcome.new(false,"ACTIVE_OR_INVALID_ORDER")
		if item.has("feedback") and not item.feedback is String: return TDOutcome.new(false,"INVALID_ORDER")
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
