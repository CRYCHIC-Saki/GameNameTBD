class_name TDEconomicDemand
extends RefCounted
## Pure finite-choice model. No RNG/state writes; callers consume one opportunity once.
static func choices(person: Dictionary, stores: Array, outside: float = 1.0, tau: float = 0.8) -> Array:
	if tau <= 0.0 or not is_finite(tau): return []
	var rows: Array = [{"store_id":"outside", "recipe_id":"", "log_weight":outside}]
	for store: Dictionary in stores:
		if not store.get("open", true) or not store.get("reachable", true): continue
		var menu: Array = store.get("menu", []).filter(func(d:Dictionary)->bool: return d.get("available",true) and d.price_cents <= person.hard_budget_cents)
		if menu.is_empty(): continue
		var counts: Dictionary = {}
		for dish: Dictionary in menu: counts[dish.family_id] = int(counts.get(dish.family_id,0)) + 1
		var values: Array[float] = []
		for dish: Dictionary in menu:
			var ratio: float = float(dish.price_cents) / maxf(1.0, float(dish.reference_cents))
			var food: float = clampf(float(dish.get("food",0.68)),0,1)
			var tastes: Dictionary = dish.get("taste",{})
			if tastes.has(person.preferred_taste): food = clampf(food + 0.12 * float(tastes[person.preferred_taste]),0,1)
			var v: float = person.food_weight * food + person.culture_weight * float(dish.get("familiarity",0.5))
			v -= person.price_weight * (1.0-0.2*clampf(float(store.get("brand",0.3)),0,1)) * float(dish.price_cents)/float(person.budget_cents)
			v -= 1.2 * pow(maxf(0,ratio-1.0),2)
			values.append(v/tau - log(float(counts[dish.family_id])))
		var inclusive := log_sum_exp(values)
		var visibility := clampf(float(store.get("visibility",0.4)),0,1)
		var awareness := clampf(float(store.get("awareness",0.3)),0,1)
		var discovery := 0.02 + 0.98*(1.0-(1.0-awareness)*(1.0-visibility))
		var utility: float = tau*inclusive + float(store.get("service",0.68)) + float(store.get("decor_match",0.3))
		utility -= person.travel_weight*float(store.get("travel_minutes",3)) + person.wait_weight*float(store.get("wait_minutes",0))
		for i: int in menu.size():
			rows.append({"store_id":store.id,"recipe_id":menu[i].id,"log_weight":log(discovery)+utility+values[i]-inclusive})
	var all_weights: Array[float] = []
	for row: Dictionary in rows: all_weights.append(row.log_weight)
	var total := log_sum_exp(all_weights)
	for row: Dictionary in rows: row.probability = exp(row.log_weight-total)
	return rows

static func log_sum_exp(values: Array[float]) -> float:
	var maximum: float = values.max()
	var total: float = 0.0
	for value: float in values: total += exp(value-maximum)
	return maximum+log(total)

static func pick(rows: Array, unit: float) -> Dictionary:
	var remaining := clampf(unit,0.0,0.999999999)
	for row: Dictionary in rows:
		remaining -= float(row.probability)
		if remaining < 0: return row.duplicate(true)
	return rows.back().duplicate(true) if not rows.is_empty() else {}
