class_name TDPhase3Session
extends RefCounted

var catalog := TDTownCatalog.new()
var town_map := TDTownMap.new()
var supply := TDSupplyBook.new()
var recipes := TDRecipeBook.new()
var ingredients := TDIngredientBook.new()
var pantry := TDPantry.new()
var rng := TDBusinessRandom.new(20261011)
var ready: bool = false
var day: int = 1
var money: int = 300
var town_id: String = "chengdu"
var good_count: int = 0
var bad_count: int = 0
var prices: Dictionary = {}
var npcs: Array = []
var competitors: Array = []
var pool: Dictionary = {}
var log_lines: Array[String] = []
var last_visit: Dictionary = {}
var player_pieces: Array = []
var staff: Dictionary = {"greeter": false, "cashier": false}
var wage_paid: Dictionary = {"greeter": 0, "cashier": 0}
var pantry_device: String = "fridge"
var pantry_category: String = "vegetable"
var pantry_index: int = 0
var pantry_dish: String = "mapodoufu"
var _supply_cursor: int = 0

func load_default() -> TDOutcome:
	var loaded := catalog.load_file()
	if not loaded.ok:
		return loaded
	recipes.unlock_score = catalog.unlock_score
	recipes.learn_starters(catalog.dish_list())
	money = catalog.starter_money
	for item: Variant in catalog.dish_list():
		var dish: Dictionary = item
		prices[String(dish["id"])] = int(dish["price"])
	town_map.build(catalog, 20261011)
	var book := ingredients.load_file()
	if not book.ok:
		return book
	var rules := pantry.load_rules()
	if not rules.ok:
		return rules
	var categories := ingredients.category_ids()
	if not categories.is_empty():
		pantry_category = categories[0]
	ready = true
	refresh_pool()
	return TDOutcome.new(true, "OK", "")

func town_name() -> String:
	var town := catalog.town(town_id)
	if town.is_empty():
		return town_id
	return "%s（%s）" % [String(town["real"]), String(town["nickname"])]

func set_town(next_id: String) -> TDOutcome:
	var town := catalog.town(next_id)
	if town.is_empty() or not bool(town.get("playable", false)):
		return TDOutcome.new(false, "MISSING", "没有这个小镇")
	town_id = next_id
	refresh_pool()
	return TDOutcome.new(true, "TOWN", town_name())

func set_zone_enabled(id: String, enabled: bool) -> void:
	town_map.set_enabled(id, enabled)
	refresh_pool()

func set_housing_enabled(enabled: bool) -> void:
	town_map.set_housing_enabled(enabled)
	refresh_pool()

func set_player_pieces(pieces: Array) -> void:
	player_pieces = pieces.duplicate(true)
	if npcs.is_empty():
		refresh_pool()
		return
	var choices: Array = []
	var decor := decor_from_pieces(player_pieces)
	for npc: Variant in npcs:
		choices.append(choose_for(npc, decor))
	pool["choices"] = choices

func adjust_price(dish_id: String, delta: int) -> int:
	var next := maxi(1, int(prices.get(dish_id, 1)) + delta)
	prices[dish_id] = next
	return next

func price_of(dish_id: String) -> int:
	return int(prices.get(dish_id, int(catalog.dish(dish_id).get("price", 1))))

func decor_from_pieces(pieces: Array) -> Dictionary:
	return TDEconomyMath.decor_of(pieces, catalog.wildcards)

func order_supply(item_id: String) -> TDOutcome:
	var item := _supply_item(item_id)
	if item.is_empty():
		return TDOutcome.new(false, "MISSING", "没有这种货")
	var cost := int(item["cost"])
	if money < cost:
		return TDOutcome.new(false, "BROKE", "钱不够订%s" % String(item["name"]))
	money -= cost
	var placed := supply.order(day, item_id, 1)
	var when := "今天到" if int(placed["arrive"]) <= day else "明天到"
	_log("订了%s，%s。" % [String(item["name"]), when])
	return TDOutcome.new(true, "ORDERED", when, placed)

func enable_buff(buff_id: String) -> TDOutcome:
	if not catalog.buffs.has(buff_id):
		return TDOutcome.new(false, "MISSING", "没有这个供货加成")
	var buff: Dictionary = catalog.buffs[buff_id]
	var upkeep := int(buff["upkeep"])
	if money < upkeep:
		return TDOutcome.new(false, "BROKE", "维护费不够")
	money -= upkeep
	if buff_id == "pipeline":
		supply.pipeline = true
	else:
		supply.nearby_market = true
	_log("%s开始生效，每天维护%d元。" % [String(buff["name"]), upkeep])
	return TDOutcome.new(true, "BUFF", String(buff["name"]))

func learned_kitchen_dishes() -> Array:
	var result: Array = []
	for dish_id: String in recipes.ids():
		var current := catalog.dish(dish_id)
		if current.is_empty():
			continue
		var service_id := String(current.get("service_recipe", ""))
		if service_id == "" or service_id == "service.qiguoji":
			result.append(current)
	return result

func staff_on(role: String) -> bool:
	return bool(staff.get(role, false))

func employ(role: String) -> TDOutcome:
	if role not in ["greeter", "cashier"]:
		return TDOutcome.new(false, "INVALID_ROLE", "没有这个岗位")
	if staff_on(role):
		return TDOutcome.new(false, "ALREADY", "%s已经在岗" % _role_title(role))
	var paid := _pay_role(role)
	if not paid.ok:
		return paid
	staff[role] = true
	return TDOutcome.new(true, "HIRED", "%s已到岗，付了%d元。" % [_role_title(role), catalog.wage_of(role)])

func dismiss(role: String) -> TDOutcome:
	if role not in ["greeter", "cashier"]:
		return TDOutcome.new(false, "INVALID_ROLE", "没有这个岗位")
	staff[role] = false
	return TDOutcome.new(true, "DISMISSED", "%s已离岗，今天付过的工资不退。" % _role_title(role))

func close_day() -> Dictionary:
	var bill := _settle_overhead()
	for buff_id: String in ["pipeline", "nearby_market"]:
		var active := supply.pipeline if buff_id == "pipeline" else supply.nearby_market
		if not active:
			continue
		var upkeep := int((catalog.buffs[buff_id] as Dictionary)["upkeep"])
		var title := String((catalog.buffs[buff_id] as Dictionary)["name"])
		if money < upkeep:
			if buff_id == "pipeline":
				supply.pipeline = false
			else:
				supply.nearby_market = false
			_log("%s没交维护费，失效了。" % title)
		else:
			money -= upkeep
	day += 1
	var spoiled := pantry.spoil(day)
	if not spoiled.is_empty():
		_log("过期清掉%d份原料。" % spoiled.size())
	_pay_retained_staff()
	var arrived := supply.collect(day)
	if not arrived.is_empty():
		_log("第%d天到货%d批。" % [day, arrived.size()])
	refresh_pool()
	return {"day": day, "arrived": arrived, "pool": pool.duplicate(true), "bill": bill}

func refresh_pool() -> void:
	var plan := TDEconomyMath.pool_plan(catalog.pool_base, town_map.zone_rows(catalog), town_map.housing_enabled(), catalog.housing_cap)
	npcs = []
	for index in int(plan["count"]):
		npcs.append(_make_npc(index, int(plan["budget_shift"]), float(plan["foreign_scale"])))
	competitors = [_competitor("rival-a", "对街小馆", 0), _competitor("rival-b", "巷口饭庄", 1)]
	var choices := []
	for npc: Variant in npcs:
		choices.append(choose_for(npc, decor_from_pieces(player_pieces)))
	pool = {
		"plan": plan,
		"npc_count": npcs.size(),
		"choices": choices,
		"town_id": town_id,
	}

func make_visit_npc() -> Dictionary:
	if npcs.is_empty():
		refresh_pool()
	return (npcs[int(rng.unit() * float(npcs.size())) % npcs.size()] as Dictionary).duplicate(true)

func roll_order(npc: Dictionary, forced_dish: String = "") -> Dictionary:
	if forced_dish != "":
		var forced := catalog.dish(forced_dish)
		return {"dish": forced, "off_menu": not recipes.has(forced_dish)}
	var local: Array = []
	for item: Variant in catalog.dish_list():
		var dish: Dictionary = item
		if String(dish["town_id"]) == String(npc["home"]):
			local.append(dish)
	var locked: Array = []
	var open: Array = []
	for item: Variant in local:
		var dish: Dictionary = item
		if recipes.has(String(dish["id"])):
			open.append(dish)
		else:
			locked.append(dish)
	if not locked.is_empty() and rng.unit() < catalog.off_menu_chance:
		return {"dish": locked[int(rng.unit() * float(locked.size())) % locked.size()], "off_menu": true}
	if not open.is_empty():
		return {"dish": open[int(rng.unit() * float(open.size())) % open.size()], "off_menu": false}
	var any_open: Array = []
	for item: Variant in catalog.dish_list():
		if recipes.has(String((item as Dictionary)["id"])):
			any_open.append(item)
	if not any_open.is_empty():
		return {"dish": any_open[int(rng.unit() * float(any_open.size())) % any_open.size()], "off_menu": false}
	var fallback: Dictionary = local[0] if not local.is_empty() else catalog.dish_list()[0]
	return {"dish": fallback, "off_menu": true}

func choose_for(npc: Dictionary, player_decor: Dictionary) -> Dictionary:
	var best := {"advantage": -1.0e12, "restaurant_id": "", "restaurant_name": "", "dish_id": "", "dish_name": "", "offer": {}}
	_consider_menu(best, npc, "player", "你的餐厅", player_decor, good_count, bad_count, _player_menu())
	for rival: Variant in competitors:
		var row: Dictionary = rival
		_consider_menu(best, npc, String(row["id"]), String(row["name"]), row["decor"], int(row["good"]), int(row["bad"]), row["menu"])
	return best

func settle_visit(npc: Dictionary, dish_id: String, quality: float, player_decor: Dictionary, accepted: bool) -> Dictionary:
	var dish := catalog.dish(dish_id)
	var offer := _offer(npc, dish, price_of(dish_id), player_decor, good_count, bad_count)
	var meal := TDEconomyMath.evaluate_meal(offer, quality, float(npc["quality_expect"]))
	var learning := recipes.consider(dish_id, accepted, float(meal["overall"]))
	if accepted:
		if bool(meal["good"]):
			good_count += 1
		elif bool(meal["bad"]):
			bad_count += 1
	last_visit = {
		"npc": npc.duplicate(true),
		"dish_id": dish_id,
		"dish_name": String(dish.get("name", dish_id)),
		"accepted": accepted,
		"quality": quality,
		"offer": offer,
		"meal": meal,
		"learning": learning,
	}
	if not accepted:
		_log("%s点的%s被拒绝，菜谱没变。" % [String(npc["id"]), String(dish.get("name", dish_id))])
	elif bool(learning["learned"]):
		_log("学会了%s，总体评价%.1f。回厨房可以按%s的谱做。" % [String(dish.get("name", dish_id)), float(meal["overall"]), catalog.kitchen_recipe_id(dish_id)])
	else:
		_log("%s的评价是%.1f，%s。" % [String(dish.get("name", dish_id)), float(meal["overall"]), String(learning["code"])])
	return last_visit.duplicate(true)

func report() -> String:
	var plan: Dictionary = pool.get("plan", {})
	var lines: PackedStringArray = []
	lines.append("第%d天  %s  现金%d元" % [day, town_name(), money])
	lines.append("固定开支：租金%d元，水电%d元，每件家具设备维护%d元。迎宾日薪%d元，收银日薪%d元。" % [int(catalog.expenses.get("rent", 0)), int(catalog.expenses.get("utilities", 0)), int(catalog.expenses.get("hardware_per_piece", 0)), catalog.wage_of("greeter"), catalog.wage_of("cashier")])
	lines.append("在岗：迎宾%s，收银%s。家具%d件。" % ["是" if staff_on("greeter") else "否", "是" if staff_on("cashier") else "否", player_pieces.size()])
	lines.append(catalog.zone_effect_note)
	lines.append("NPC池%d人，预算平移%d，外来偏好倍率%.2f" % [npcs.size(), int(plan.get("budget_shift", 0)), float(plan.get("foreign_scale", 1))])
	lines.append("口碑 = 100×好评%d - 5000×差评%d = %.0f" % [good_count, bad_count, TDEconomyMath.reputation_score(good_count, bad_count)])
	var known := PackedStringArray()
	for dish_id: String in recipes.ids():
		known.append(dish_id)
	lines.append("解锁线：总体评价≥%.0f。当前已会：%s" % [catalog.unlock_score, "、".join(known)])
	var cookable := PackedStringArray()
	for dish_id: String in recipes.ids():
		var mapped := catalog.kitchen_recipe_id(dish_id)
		if mapped.begins_with("phase3.") or mapped == "service.qiguoji":
			if recipes.has(dish_id) and (mapped.begins_with("phase3.") or dish_id == "qiguoji"):
				cookable.append("%s→%s" % [String(catalog.dish(dish_id).get("name", dish_id)), mapped])
	if not cookable.is_empty():
		lines.append("可回厨房按谱做：" + "、".join(cookable))
	lines.append("供货：%s。流水线%s，近市%s。" % [_stock_text(), "开" if supply.pipeline else "关", "开" if supply.nearby_market else "关"])
	lines.append("原料%d份。%s" % [pantry.lots.size(), pantry.summary(day)])
	if not supply.incoming.is_empty():
		lines.append("在途%d批，最早第%d天到。" % [supply.incoming.size(), int((supply.incoming[0] as Dictionary)["arrive"])])
	lines.append("预算抽样：15起快速升到50最多，之后慢降到130。下面是今天的人数。")
	lines.append(_histogram())
	lines.append("功能区贡献：")
	for row: Variant in plan.get("rows", []):
		var zone: Dictionary = row
		lines.append("%s %s 人数%+d 预算%+d 外来%.2f" % ["开" if bool(zone["enabled"]) else "关", String(zone["name"]), int(zone["pool"]), int(zone["budget_shift"]), float(zone["foreign_scale"])])
	lines.append("住房计入%d户（上限%d）。" % [int(plan.get("housing", 0)), catalog.housing_cap])
	var shown := mini(3, npcs.size())
	for index in shown:
		lines.append(_npc_line(npcs[index], pool.get("choices", [])[index] if index < (pool.get("choices", []) as Array).size() else {}))
	if not last_visit.is_empty():
		var meal: Dictionary = last_visit["meal"]
		lines.append("最近一桌：%s %s 总体%.1f（%d星） 菜品%.1f 装修%.1f 品牌%.1f %s" % [
			String(last_visit["dish_name"]),
			"接受" if bool(last_visit["accepted"]) else "拒绝",
			float(meal["overall"]),
			int(meal["stars"]),
			float(meal["dish_review"]),
			float(meal["decor_review"]),
			float(meal["brand_review"]),
			String((last_visit["learning"] as Dictionary)["code"]),
		])
	lines.append("参考价 = 食材成本×制作系数+基础偏移。装修效果 = 统一度/100×高端度。")
	lines.append("竞争优势 = 前菜品 + 前装修 + 前品牌。总体评价 = 三者里把菜品换成实际质量后再除以3。")
	if not log_lines.is_empty():
		var tail := PackedStringArray()
		var start := maxi(0, log_lines.size() - 4)
		for index in range(start, log_lines.size()):
			tail.append(log_lines[index])
		lines.append("记录：" + " ".join(tail))
	return "\n".join(lines)

func next_supply_item() -> Dictionary:
	if catalog.supply_items.is_empty():
		return {}
	_supply_cursor = (_supply_cursor + 1) % catalog.supply_items.size()
	return (catalog.supply_items[_supply_cursor] as Dictionary).duplicate(true)

func current_supply_item() -> Dictionary:
	if catalog.supply_items.is_empty():
		return {}
	return (catalog.supply_items[_supply_cursor] as Dictionary).duplicate(true)

func _make_npc(index: int, shift: int, foreign_scale: float) -> Dictionary:
	var budget := maxi(15, TDEconomyMath.budget_from_unit(rng.unit()) + shift)
	var home := catalog.town(town_id)
	var culture := String(home.get("culture", "chinese"))
	var preferences: Array[String] = [culture]
	var extra := TDEconomyMath.preference_roll_count(budget, foreign_scale, rng.unit(), rng.unit(), rng.unit())
	var options := _other_cultures(culture, preferences)
	for _unused in extra:
		if options.is_empty():
			break
		var pick := options[int(rng.unit() * float(options.size())) % options.size()]
		preferences.append(pick)
		options.erase(pick)
	var expect := TDEconomyMath.expectations(budget)
	return {
		"id": "npc-%d-%d" % [day, index + 1],
		"budget": budget,
		"home": town_id,
		"preferences": preferences,
		"decor_expect": float(expect["decor"]),
		"quality_expect": float(expect["quality"]),
		"reputation_pref": float(expect["reputation"]),
	}

func _other_cultures(home_culture: String, current: Array[String]) -> Array[String]:
	var options: Array[String] = []
	var seen := {}
	for item: Variant in catalog.playable_towns():
		var culture := String((item as Dictionary)["culture"])
		if culture == home_culture or current.has(culture) or seen.has(culture):
			continue
		seen[culture] = true
		options.append(culture)
	return options

func _competitor(id: String, title: String, salt: int) -> Dictionary:
	var local: Array = []
	var rest: Array = []
	for item: Variant in catalog.dish_list():
		var dish: Dictionary = item
		if String(dish["town_id"]) == town_id:
			local.append(dish)
		else:
			rest.append(dish)
	var menu: Array = []
	while menu.size() < 10 and (not local.is_empty() or not rest.is_empty()):
		var source: Array = local if not local.is_empty() else rest
		var dish: Dictionary = source.pop_front()
		var reference := catalog.reference_of(String(dish["id"]))
		var price := maxi(1, int(round(reference * (0.85 + float((salt + menu.size()) % 5) * 0.08))))
		menu.append({"id": dish["id"], "name": dish["name"], "culture": dish["culture"], "price": price, "reference": reference})
	var luxury := 28.0 + float((salt + 1) * 18)
	return {
		"id": id,
		"name": title,
		"good": 1 + salt,
		"bad": salt,
		"decor": {"unity": 60.0 + salt * 10.0, "luxury": luxury, "effect": (60.0 + salt * 10.0) / 100.0 * luxury, "majority": String(catalog.town(town_id).get("culture", "chinese"))},
		"menu": menu,
	}

func _player_menu() -> Array:
	var menu: Array = []
	for dish_id: String in recipes.ids():
		var dish := catalog.dish(dish_id)
		menu.append({
			"id": dish_id,
			"name": String(dish.get("name", dish_id)),
			"culture": String(dish.get("culture", "")),
			"price": price_of(dish_id),
			"reference": catalog.reference_of(dish_id),
		})
	return menu

func _consider_menu(best: Dictionary, npc: Dictionary, restaurant_id: String, restaurant_name: String, decor: Dictionary, good_value: int, bad_value: int, menu: Array) -> void:
	for item: Variant in menu:
		var dish: Dictionary = item
		var offer := _offer(npc, dish, float(dish["price"]), decor, good_value, bad_value)
		if float(offer["advantage"]) > float(best["advantage"]):
			best["advantage"] = offer["advantage"]
			best["restaurant_id"] = restaurant_id
			best["restaurant_name"] = restaurant_name
			best["dish_id"] = String(dish["id"])
			best["dish_name"] = String(dish["name"])
			best["offer"] = offer

func _offer(npc: Dictionary, dish: Dictionary, price: float, decor: Dictionary, good_value: int, bad_value: int) -> Dictionary:
	var type_pref := TDEconomyMath.type_preference(String(dish.get("culture", "")), npc["preferences"])
	var style_pref := TDEconomyMath.style_preference(String(decor.get("majority", "")), catalog.wildcards, npc["preferences"])
	var reference := float(dish["reference"]) if dish.has("reference") else catalog.reference_of(String(dish.get("id", "")))
	var offer := TDEconomyMath.evaluate_offer(float(npc["budget"]), price, reference, type_pref, float(decor.get("effect", 0)), float(npc["decor_expect"]), style_pref, good_value, bad_value, float(npc["reputation_pref"]))
	offer["price"] = price
	offer["reference"] = reference
	offer["type_pref"] = type_pref
	offer["style_pref"] = style_pref
	return offer

func _histogram() -> String:
	var bins := {"15-29": 0, "30-44": 0, "45-59": 0, "60-79": 0, "80-99": 0, "100+": 0}
	for item: Variant in npcs:
		var budget := int((item as Dictionary)["budget"])
		var key := "100+"
		if budget < 30:
			key = "15-29"
		elif budget < 45:
			key = "30-44"
		elif budget < 60:
			key = "45-59"
		elif budget < 80:
			key = "60-79"
		elif budget < 100:
			key = "80-99"
		bins[key] = int(bins[key]) + 1
	var text := ""
	for key: String in ["15-29", "30-44", "45-59", "60-79", "80-99", "100+"]:
		var count := int(bins[key])
		text += "%s %s%d\n" % [key, "█".repeat(mini(count, 40)), count]
	return text

func _npc_line(npc: Dictionary, choice: Dictionary) -> String:
	var prefs := PackedStringArray()
	for item: Variant in npc["preferences"]:
		prefs.append(String(item))
	var where := String(choice.get("restaurant_name", "还没选"))
	var dish_name := String(choice.get("dish_name", ""))
	return "%s 预算%d 偏好%s → %s的%s（优势%.1f）" % [String(npc["id"]), int(npc["budget"]), "、".join(prefs), where, dish_name, float(choice.get("advantage", 0))]

func _stock_text() -> String:
	if supply.stock.is_empty():
		return "库存空"
	var parts: PackedStringArray = []
	for key: Variant in supply.stock.keys():
		parts.append("%s×%d" % [String(key), int(supply.stock[key])])
	return "、".join(parts)

func _supply_item(item_id: String) -> Dictionary:
	for item: Variant in catalog.supply_items:
		if String((item as Dictionary)["id"]) == item_id:
			return (item as Dictionary).duplicate(true)
	return {}

func _role_title(role: String) -> String:
	return "迎宾" if role == "greeter" else "收银"

func _pay_role(role: String) -> TDOutcome:
	if int(wage_paid.get(role, 0)) == day:
		return TDOutcome.new(true, "ALREADY_PAID", "")
	var amount := catalog.wage_of(role)
	if amount <= 0:
		return TDOutcome.new(false, "MISSING", "没有这个岗位的工资")
	if money < amount:
		return TDOutcome.new(false, "BROKE", "现金不够付%s工资%d元" % [_role_title(role), amount])
	money -= amount
	wage_paid[role] = day
	_log("付了%s工资%d元。" % [_role_title(role), amount])
	return TDOutcome.new(true, "PAID", "")

func _pay_down(amount: int, label: String) -> int:
	if amount <= 0:
		return 0
	var paid := mini(money, amount)
	money -= paid
	if paid < amount:
		_log("%s要%d元，只付了%d元。" % [label, amount, paid])
	else:
		_log("付了%s%d元。" % [label, paid])
	return paid

func _settle_overhead() -> Dictionary:
	var rent := int(catalog.expenses.get("rent", 0))
	var utilities := int(catalog.expenses.get("utilities", 0))
	var hardware := player_pieces.size() * int(catalog.expenses.get("hardware_per_piece", 0))
	var spent := _pay_down(rent, "租金") + _pay_down(utilities, "水电") + _pay_down(hardware, "设备维护")
	for role: String in ["greeter", "cashier"]:
		if not staff_on(role) or int(wage_paid.get(role, 0)) == day:
			continue
		var paid := _pay_role(role)
		if paid.ok:
			spent += catalog.wage_of(role)
		else:
			staff[role] = false
			_log("%s工资没付上，离岗。" % _role_title(role))
	return {"rent": rent, "utilities": utilities, "hardware": hardware, "spent": spent}

func _pay_retained_staff() -> void:
	for role: String in ["greeter", "cashier"]:
		if not staff_on(role):
			continue
		var paid := _pay_role(role)
		if not paid.ok:
			staff[role] = false
			_log("%s付不出下一天的工资，离岗。" % _role_title(role))

func current_pantry_item() -> Dictionary:
	var ids := ingredients.ids_in(pantry_category)
	if ids.is_empty():
		return {}
	pantry_index = posmod(pantry_index, ids.size())
	return ingredients.get_item(ids[pantry_index])

func cycle_pantry_category() -> String:
	var ids := ingredients.category_ids()
	if ids.is_empty():
		return ""
	var index := ids.find(pantry_category)
	pantry_category = ids[(index + 1) % ids.size()] if index >= 0 else ids[0]
	pantry_index = 0
	return _category_name(pantry_category)

func cycle_pantry_ingredient() -> String:
	var ids := ingredients.ids_in(pantry_category)
	if ids.is_empty():
		return ""
	pantry_index = (pantry_index + 1) % ids.size()
	return String(current_pantry_item().get("name", ""))

func cycle_pantry_device() -> String:
	if pantry.devices.is_empty():
		return ""
	var index := -1
	for item: Variant in pantry.devices:
		index += 1
		if String((item as Dictionary)["id"]) == pantry_device:
			break
	var next: Dictionary = pantry.devices[(index + 1) % pantry.devices.size()]
	pantry_device = String(next["id"])
	return String(next.get("name", pantry_device))

func cycle_pantry_dish() -> String:
	var ids := _pantry_dish_ids()
	if ids.is_empty():
		return ""
	var index := ids.find(pantry_dish)
	pantry_dish = ids[(index + 1) % ids.size()] if index >= 0 else ids[0]
	return String(catalog.dish(pantry_dish).get("name", pantry_dish))

func prep_dish(dish_id: String = "") -> TDOutcome:
	var id := pantry_dish if dish_id == "" else dish_id
	var ids := pantry.bill(id)
	if ids.is_empty():
		return TDOutcome.new(false, "NO_BILL", "这道菜没有原料清单")
	var rows: Array = []
	var cost := 0
	for ingredient_id: String in ids:
		var item := ingredients.get_item(ingredient_id)
		if item.is_empty():
			return TDOutcome.new(false, "MISSING", "食材表里没有%s" % ingredient_id)
		rows.append(item)
		cost += pantry.cost_of(item)
	var title := String(catalog.dish(id).get("name", id))
	if money < cost:
		return TDOutcome.new(false, "BROKE", "备%s需要%d元" % [title, cost])
	money -= cost
	var names := PackedStringArray()
	for item: Variant in rows:
		var lot := pantry.store(item, pantry_device, day)
		names.append("%s剩%d天" % [String((item as Dictionary)["name"]), int(lot["life_days"])])
	var device_name := String(pantry.device(pantry_device).get("name", pantry_device))
	var text := "按%s备了%s，放进%s，花了%d元。" % [title, "、".join(names), device_name, cost]
	var gap := pantry.note(id)
	if gap != "":
		text += gap
	_log(text)
	return TDOutcome.new(true, "PREPPED", text, {"cost": cost, "count": rows.size()})

func prep_selected_ingredient() -> TDOutcome:
	var item := current_pantry_item()
	if item.is_empty():
		return TDOutcome.new(false, "MISSING", "没有选中食材")
	var cost := pantry.cost_of(item)
	if money < cost:
		return TDOutcome.new(false, "BROKE", "备%s需要%d元" % [String(item["name"]), cost])
	money -= cost
	var lot := pantry.store(item, pantry_device, day)
	var device_name := String(pantry.device(pantry_device).get("name", pantry_device))
	var text := "备了%s，放进%s，保质%d天，花了%d元。" % [String(item["name"]), device_name, int(lot["life_days"]), cost]
	_log(text)
	return TDOutcome.new(true, "PREPPED", text, lot)

func pantry_text() -> String:
	var lines: PackedStringArray = []
	var item := current_pantry_item()
	lines.append("第%d天  现金%d元  原料%d份" % [day, money, pantry.lots.size()])
	lines.append("按一道菜会一次买齐它的原料。也可以先换一类，再点选一种食材。钱从这本现金账扣，不写原来的营业档。")
	var device_bits := PackedStringArray()
	for device: Variant in pantry.devices:
		var row: Dictionary = device
		var mark := "（当前）" if String(row["id"]) == pantry_device else ""
		var days := 0
		if not item.is_empty():
			days = pantry.life_days(String(item["category"]), String(row["id"]))
		device_bits.append("%s%s %d天" % [String(row["name"]), mark, days])
	lines.append("这一份放进不同设备：" + "，".join(device_bits))
	var names := PackedStringArray()
	var cost := 0
	for ingredient_id: String in pantry.bill(pantry_dish):
		var row := ingredients.get_item(ingredient_id)
		if row.is_empty():
			names.append(ingredient_id)
			continue
		names.append(String(row["name"]))
		cost += pantry.cost_of(row)
	lines.append("按菜：%s，%s，共%d元。" % [String(catalog.dish(pantry_dish).get("name", pantry_dish)), "、".join(names), cost])
	var gap := pantry.note(pantry_dish)
	if gap != "":
		lines.append(gap)
	if not item.is_empty():
		lines.append("点选：%s / %s，这一份%d元。" % [String(item["category_name"]), String(item["name"]), pantry.cost_of(item)])
	lines.append(pantry.summary(day, 12))
	if not log_lines.is_empty():
		lines.append(log_lines[log_lines.size() - 1])
	return "\n".join(lines)

func _pantry_dish_ids() -> Array[String]:
	var result: Array[String] = []
	for dish: Variant in catalog.dish_list():
		var id := String((dish as Dictionary)["id"])
		if not pantry.bill(id).is_empty():
			result.append(id)
	return result

func _category_name(category_id: String) -> String:
	for group: Variant in ingredients.categories:
		if String((group as Dictionary)["id"]) == category_id:
			return String((group as Dictionary)["name"])
	return category_id

func _log(text: String) -> void:
	log_lines.append(text)
	if log_lines.size() > 12:
		log_lines.remove_at(0)
