class_name TDPhase3Session
extends RefCounted

var catalog := TDTownCatalog.new()
var town_map := TDTownMap.new()
var supply := TDSupplyBook.new()
var recipes := TDRecipeBook.new()
var ingredients := TDIngredientBook.new()
var pantry := TDPantry.new()
var floor := TDFloorBoard.new()
var rng := TDBusinessRandom.new(20261011)
var ready: bool = false
var research: TDResearchSession
var factory_products_provider: Callable
var factory_item_provider: Callable

func factory_products(supply_id: String) -> Array:
	return factory_products_provider.call(supply_id) if factory_products_provider.is_valid() else TDTownMap.products_of(supply_id)

func factory_product(supply_id: String, item_id: String) -> Dictionary:
	for item: Dictionary in factory_products(supply_id):
		if item.id==item_id: return item.duplicate(true)
	return {}

func attach_research(value:TDResearchSession) -> void:
	research=value
	for dish:Dictionary in TDResearchRuntime.dishes():
		catalog.dishes[dish.id]=dish.duplicate(true);prices[dish.id]=int(dish.price)
	if not research.changed.is_connected(_sync_research): research.changed.connect(_sync_research)
	_sync_research()

func _sync_research() -> void:
	if research==null: return
	var previous:Array=recipes.ids()
	recipes.unlocked.clear()
	var progress:=research.snapshot()
	for id:String in progress.unlocked:
		var runtime:=research.catalog.runtime_id(id)
		if catalog.dishes.has(runtime): recipes.grant(runtime)
	for id:String in progress.legacy_ids:
		if catalog.dishes.has(id): recipes.grant(id)
	if ready and previous!=recipes.ids(): refresh_pool()

func research_service_ids() -> Array:
	var ids:Array=[]
	if research==null: return ids
	for id:String in recipes.ids():
		var service_id:=catalog.kitchen_recipe_id(id)
		if not service_id.is_empty(): ids.append(service_id)
	return ids
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
const ROLES: Array[String] = ["greeter", "cashier", "cleaner", "prep", "chef", "manager", "runner"]
const ROLE_TITLE := {"greeter": "迎宾", "cashier": "收银", "cleaner": "保洁", "prep": "备菜", "chef": "主厨", "manager": "店长", "runner": "传菜员"}
const CLAIM_FEE := 20
var staff: Dictionary = {"greeter": false, "cashier": false, "cleaner": false, "prep": false, "chef": false, "manager": false, "runner": false}
var wage_paid: Dictionary = {"greeter": 0, "cashier": 0, "cleaner": 0, "prep": 0, "chef": 0, "manager": 0, "runner": 0}
var home_skill: Dictionary = {"greeter": 20, "cashier": 20, "cleaner": 20, "prep": 20, "chef": 20, "manager": 20, "runner": 20}
var home_chef_recipes: Array = []
var home_town_id: String = ""
var home_size: String = "small"
var home_built: bool = false
var home_venue: String = ""
var home_w: int = 0
var home_h: int = 0
var claim_size: String = "small"
var scaled_interior: bool = false
var factory_built: Dictionary = {}
var factory_level: Dictionary = {}
var factory_jobs: Dictionary = {}
const FACTORY_HOUR_SECONDS := 3600.0
var branch_open: bool = false
var branch_town: String = ""
var branch_culture: String = ""
var branch_size: String = "small"
var branch_x: int = 0
var branch_y: int = 0
var branch_w: int = 0
var branch_h: int = 0
var branch_menu: Array = []
var branch_stock: Dictionary = {}
var branch_staff: Dictionary = {"greeter": false, "cashier": false, "cleaner": false, "prep": false, "chef": false, "manager": false, "runner": false}
var branch_wage_paid: Dictionary = {"greeter": 0, "cashier": 0, "cleaner": 0, "prep": 0, "chef": 0, "manager": 0, "runner": 0}
var branch_skill: Dictionary = {"greeter": 20, "cashier": 20, "cleaner": 20, "prep": 20, "chef": 20, "manager": 20, "runner": 20}
var branch_chef_recipes: Array = []
var branch_settled: Dictionary = {}
var custom_recipes: Dictionary = {}
var duty: Dictionary = {"dish_id": "", "prep": "", "cook": "", "quality": -1}
var staff_profiles: Dictionary = {}
var _profile_serial: int = 0
var san: int = 80
var open_hour: int = 11
var close_hour: int = 20
var day_phase: String = "morning"
var selected_market: String = ""
var map_revision: int = 0
var free_spent: float = 0.0
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
	if home_town_id == "":
		home_town_id = town_id
	_rebuild_map()
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
	selected_market = ""
	_rebuild_map()
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
	if not _supply_open(item_id):
		return TDOutcome.new(false, "LOCKED", "这家菜市场没有%s" % String(item["name"]))
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
		if research!=null or service_id == "" or service_id == "service.qiguoji":
			result.append(current)
	return result

func staff_on(role: String) -> bool:
	return bool(staff.get(role, false))

func employ(role: String, store_id: String = "home") -> TDOutcome:
	if not ROLES.has(role):
		return TDOutcome.new(false, "INVALID_ROLE", "没有这个岗位")
	if store_id == "branch":
		return _employ_branch(role)
	if store_id != "home":
		return TDOutcome.new(false, "MISSING", "没有这家店")
	if staff_on(role):
		return TDOutcome.new(false, "ALREADY", "%s已经在岗" % _role_title(role))
	_open_profile("home", role)
	var paid := _pay_role(role)
	if not paid.ok:
		_drop_profile("home", role)
		return paid
	staff[role] = true
	_start_role("home", role)
	if paid.code != "ALREADY_PAID":
		_tick_mood("home", role)
	return TDOutcome.new(true, "HIRED", _hire_message("home", role))

func dismiss(role: String, store_id: String = "home") -> TDOutcome:
	if not ROLES.has(role):
		return TDOutcome.new(false, "INVALID_ROLE", "没有这个岗位")
	if store_id == "branch":
		branch_staff[role] = false
		if role == "chef":
			branch_chef_recipes = []
		_drop_profile("branch", role)
		return TDOutcome.new(true, "DISMISSED", "分店%s已离岗，今天付过的工资不退。" % _role_title(role))
	staff[role] = false
	if role == "chef":
		home_chef_recipes = []
	_drop_profile("home", role)
	return TDOutcome.new(true, "DISMISSED", "%s已离岗，今天付过的工资不退。" % _role_title(role))

func set_san(value: int) -> TDOutcome:
	if day_phase != "morning":
		return TDOutcome.new(false, "LATE", "只能在每天开局、还没营业时改 SAN")
	san = clampi(value, 0, 100)
	return TDOutcome.new(true, "SAN", "SAN 设为 %d。" % san)

func shift_open(delta: int) -> TDOutcome:
	if day_phase != "morning":
		return TDOutcome.new(false, "LATE", "营业开始后不能改时间")
	open_hour = clampi(open_hour + delta, 0, close_hour - 1)
	refresh_pool()
	return TDOutcome.new(true, "OPEN", "开门改为 %02d:00。" % open_hour)

func shift_close(delta: int) -> TDOutcome:
	if day_phase != "morning":
		return TDOutcome.new(false, "LATE", "营业开始后不能改时间")
	close_hour = clampi(close_hour + delta, open_hour + 1, 24)
	refresh_pool()
	return TDOutcome.new(true, "CLOSE", "收摊改为 %02d:00。" % close_hour)

func schedule() -> Dictionary:
	var selected := selected_market != ""
	var distance := town_map.distance_to(selected_market) if selected else 0
	return TDSanRules.day_plan(open_hour, close_hour, distance, selected, staff_on("cleaner"), staff_on("cashier"))

func free_hours() -> float:
	var plan := schedule()
	if day_phase == "evening":
		return float(plan["evening_free_hours"])
	if day_phase == "morning":
		return float(plan["morning_free_hours"])
	return 0.0

func start_service() -> TDOutcome:
	if day_phase != "morning":
		return TDOutcome.new(false, "LATE", "现在不是开业前的自由活动")
	day_phase = "service"
	free_spent = 0.0
	var plan := schedule()
	_log("开始营业。备货%d分钟，收拾%d分钟。" % [int(plan["stock_minutes"]), int(plan["clean_minutes"])])
	return TDOutcome.new(true, "OPEN", "开始营业。准备要%d分钟，其中收拾%d分钟。" % [int(plan["stock_minutes"]) + int(plan["clean_minutes"]), int(plan["clean_minutes"])])

func end_service() -> TDOutcome:
	if day_phase != "service":
		return TDOutcome.new(false, "LATE", "还没在营业")
	var loss := TDSanRules.hour_points(float(schedule()["work_hours"]), -1)
	san = TDSanRules.clamp_san(float(san + loss))
	day_phase = "evening"
	free_spent = 0.0
	_log("收摊。工作扣了%d点 SAN，现在是 %d。" % [-loss, san])
	return TDOutcome.new(true, "CLOSED", "收了摊。整理%d分钟，SAN 还剩 %d。" % [int(schedule()["tidy_minutes"]), san])

func rest() -> TDOutcome:
	var left := maxf(0.0, free_hours() - free_spent)
	var gain := TDSanRules.hour_points(left, 1)
	san = TDSanRules.clamp_san(float(san + gain))
	var ended := close_day()
	return TDOutcome.new(true, "REST", "休息了%.1f小时，SAN %+d，现在 %d。进入第%d天。" % [left, gain, san, int(ended["day"])])

func select_market(id: String) -> TDOutcome:
	var stall := town_map.market(id)
	if stall.is_empty():
		return TDOutcome.new(false, "MISSING", "这里不是菜市场")
	selected_market = id
	refresh_pool()
	var tier := int(stall.get("tier", 1))
	var count := catalog.supply_items.size() if tier >= 3 else (stall.get("unlocks", []) as Array).size()
	return TDOutcome.new(true, "MARKET", "选定%s。距离%d格，能买%d种，备货%d分钟。" % [String(stall["name"]), town_map.distance_to(id), count, int(schedule()["stock_minutes"])])

func visit_zone(kind: String) -> TDOutcome:
	if day_phase == "service":
		return TDOutcome.new(false, "BUSY", "营业中不能离开去恢复 SAN")
	var offer := TDSanRules.recovery(kind)
	if offer.is_empty():
		return TDOutcome.new(false, "NO_VISIT", "这里不能这样打发时间")
	var hours := float(offer["hours"])
	if free_spent + hours > free_hours() + 0.001:
		return TDOutcome.new(false, "NO_TIME", "这段自由活动不够用")
	var cost := int(offer["cost"])
	if money < cost:
		return TDOutcome.new(false, "BROKE", "钱不够")
	money -= cost
	free_spent += hours
	san = TDSanRules.clamp_san(float(san + int(offer["san"])))
	return TDOutcome.new(true, "VISITED", "花了%d元和%.0f小时，SAN 回到 %d。" % [cost, hours, san])

func advance_day() -> Dictionary:
	if day_phase == "service":
		end_service()
	return close_day()

func close_day() -> Dictionary:
	settle_branch()
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
	day_phase = "morning"
	free_spent = 0.0
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
	var hours := schedule()
	plan["count"] = maxi(0, int(plan["count"]) + int(hours["meal_guests"]) + town_map.attraction_bonus())
	plan["meal_guests"] = int(hours["meal_guests"])
	plan["attraction"] = town_map.attraction_bonus()
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
	if recipes.has("tomato_preserved_egg") and rng.unit() < TDSanRules.dark_order_chance(String(npc.get("meal", ""))):
		var dark := catalog.dish("tomato_preserved_egg")
		if not dark.is_empty():
			return {"dish": dark, "off_menu": false}
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

func settle_visit(npc: Dictionary, dish_id: String, quality: float, player_decor: Dictionary, accepted: bool, reason: String = "") -> Dictionary:
	var dish := catalog.dish(dish_id)
	var offer := _offer(npc, dish, price_of(dish_id), player_decor, good_count, bad_count)
	var meal := TDEconomyMath.evaluate_meal(offer, quality, float(npc["quality_expect"]))
	var learning:Dictionary={"learned":false,"code":"RESEARCH_REQUIRED"} if research!=null else recipes.consider(dish_id, accepted, float(meal["overall"]))
	if research!=null and accepted:
		research.record_cooking(day,dish_id,clampf(quality,0,100))
	var dark_name := ""
	if research==null and accepted and TDSanRules.dark_triggered(float(san), quality, rng.unit()):
		for item: Variant in catalog.dish_list():
			var candidate: Dictionary = item
			if String(candidate.get("dark_of", "")) != dish_id:
				continue
			if recipes.grant(String(candidate["id"])):
				dark_name = String(candidate["name"])
				_log("低 SAN 下这道%s变成了阴暗版本，学会了%s。" % [String(dish.get("name", dish_id)), dark_name])
			break
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
		"dark_name": dark_name,
	}
	if not accepted:
		if reason == "timeout":
			_log("%s等太久，没吃到%s就离开了，菜谱没变。" % [String(npc["id"]), String(dish.get("name", dish_id))])
		else:
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
	lines.append("固定开支：租金%d元，水电%d元，每件家具设备维护%d元，主店规模维护%d元。推荐日薪仍是迎宾%d、收银%d。" % [int(catalog.expenses.get("rent", 0)), int(catalog.expenses.get("utilities", 0)), int(catalog.expenses.get("hardware_per_piece", 0)), store_upkeep("home"), catalog.wage_of("greeter"), catalog.wage_of("cashier")])
	lines.append(_staff_mood_line("home"))
	lines.append("在岗：迎宾%s，收银%s，保洁%s，备菜%s，主厨%s，店长%s，传菜%s。家具%d件。" % ["是" if staff_on("greeter") else "否", "是" if staff_on("cashier") else "否", "是" if staff_on("cleaner") else "否", "是" if staff_on("prep") else "否", "是" if staff_on("chef") else "否", "是" if staff_on("manager") else "否", "是" if staff_on("runner") else "否", player_pieces.size()])
	lines.append(_branch_line())
	var hours := schedule()
	var meal_names: PackedStringArray = []
	for item: Variant in hours["meals"]:
		meal_names.append(String((item as Dictionary)["name"]))
	var meal_text := "、".join(meal_names) if not meal_names.is_empty() else "没有正餐时段"
	lines.append("SAN %d。营业 %02d:00–%02d:00，覆盖%s。准备备货%d分钟、收拾%d分钟，收摊后整理%d分钟。" % [san, open_hour, close_hour, meal_text, int(hours["stock_minutes"]), int(hours["clean_minutes"]), int(hours["tidy_minutes"])])
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
	for _step in catalog.supply_items.size():
		_supply_cursor = (_supply_cursor + 1) % catalog.supply_items.size()
		var item: Dictionary = catalog.supply_items[_supply_cursor]
		if _supply_open(String(item["id"])):
			return item.duplicate(true)
	return {}

func current_supply_item() -> Dictionary:
	if catalog.supply_items.is_empty():
		return {}
	for _step in catalog.supply_items.size():
		var item: Dictionary = catalog.supply_items[_supply_cursor]
		if _supply_open(String(item["id"])):
			return item.duplicate(true)
		_supply_cursor = (_supply_cursor + 1) % catalog.supply_items.size()
	return {}

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
	var meal := _meal_for(index)
	budget = maxi(15, budget + int(meal["shift"]))
	var expect := TDEconomyMath.expectations(budget)
	return {
		"id": "npc-%d-%d" % [day, index + 1],
		"budget": budget,
		"home": town_id,
		"meal": String(meal["id"]),
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

func _supply_open(item_id: String) -> bool:
	if selected_market == "":
		return true
	var stall := town_map.market(selected_market)
	if stall.is_empty() or int(stall.get("tier", 0)) >= 3:
		return true
	return item_id in stall.get("unlocks", [])

func _meal_for(index: int) -> Dictionary:
	var rows: Array = schedule()["meals"]
	if rows.is_empty():
		return {"id": "off", "name": "错峰", "shift": 0, "guests": 0}
	return (rows[posmod(index, rows.size())] as Dictionary).duplicate(true)

func _supply_item(item_id: String) -> Dictionary:
	if factory_item_provider.is_valid():
		var item: Dictionary=factory_item_provider.call(item_id)
		if not item.is_empty(): return item
	for item: Variant in catalog.supply_items:
		if String((item as Dictionary)["id"]) == item_id:
			return (item as Dictionary).duplicate(true)
	return {}

func _role_title(role: String) -> String:
	return String(ROLE_TITLE.get(role, role))

func _pay_role(role: String) -> TDOutcome:
	if int(wage_paid.get(role, 0)) == day:
		return TDOutcome.new(true, "ALREADY_PAID", "")
	var amount := _offered_wage("home", role)
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
	var upkeep := store_upkeep("home")
	var spent := _pay_down(rent, "租金") + _pay_down(utilities, "水电") + _pay_down(hardware, "设备维护") + _pay_down(upkeep, "主店维护")
	for role: String in ROLES:
		if not staff_on(role) or int(wage_paid.get(role, 0)) == day:
			continue
		var paid := _pay_role(role)
		if paid.ok:
			spent += _offered_wage("home", role)
			_tick_mood("home", role)
		else:
			staff[role] = false
			_drop_profile("home", role)
			_log("%s工资没付上，离岗。" % _role_title(role))
	return {"rent": rent, "utilities": utilities, "hardware": hardware, "upkeep": upkeep, "spent": spent}

func _pay_retained_staff() -> void:
	for role: String in ROLES:
		if not staff_on(role):
			continue
		var paid := _pay_role(role)
		if paid.ok and paid.code != "ALREADY_PAID":
			_tick_mood("home", role)
		elif not paid.ok:
			staff[role] = false
			_drop_profile("home", role)
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

func interior_grid() -> Vector2i:
	if branch_open and town_id == branch_town:
		return TDRestaurantSizes.interior(branch_size)
	if home_built and home_size == "quarter" and home_w > 0 and home_h > 0:
		return Vector2i(maxi(8, home_w * 2), maxi(8, home_h * 2))
	return TDRestaurantSizes.interior(home_size)

func interior_culture() -> String:
	if branch_open and town_id == branch_town and branch_culture != "":
		return branch_culture
	if home_venue == "western":
		return "french"
	if home_venue == "chinese":
		return "chinese"
	return String(catalog.town(home_town_id).get("culture", "chinese"))

func build_venue(venue: String) -> TDOutcome:
	if venue != "chinese" and venue != "western":
		return TDOutcome.new(false, "MISSING", "只能建中餐厅或西餐厅。")
	if town_id != home_town_id:
		return TDOutcome.new(false, "WRONG_TOWN", "只能在主小镇的餐厅建设区建店。")
	if home_built:
		return TDOutcome.new(false, "ALREADY", "主店已经建好了。")
	var lot := town_map.diner_lot()
	if lot.is_empty():
		return TDOutcome.new(false, "MISSING", "这座小镇没有餐厅建设区。")
	home_w = maxi(1, int(lot["w"]) / 2)
	home_h = maxi(1, int(lot["h"]) / 2)
	home_venue = venue
	home_size = "quarter"
	home_built = true
	_rebuild_map()
	var diner := _plot_by_id("player_diner")
	var lot_area := int(lot["w"]) * int(lot["h"])
	if diner.is_empty() or int(diner.get("w", 0)) * int(diner.get("h", 0)) * 4 != lot_area:
		home_built = false
		home_venue = ""
		home_w = 0
		home_h = 0
		home_size = "small"
		_rebuild_map()
		return TDOutcome.new(false, "BLOCKED", "建设区落店失败，保持空地。")
	var label := "西餐厅" if venue == "western" else "中餐厅"
	return TDOutcome.new(true, "BUILT", "%s建好了，占建设区四分之一（%d×%d）。走到店里就能进去。" % [label, int(diner["w"]), int(diner["h"])])

func build_home(venue: String = "chinese") -> TDOutcome:
	return build_venue(venue)

func build_factory(plot_id: String) -> TDOutcome:
	var plot := _plot_by_id(plot_id)
	if plot.is_empty():
		return TDOutcome.new(false, "MISSING", "没有这块原料厂空地。")
	if String(plot.get("kind", "")) != "factory_lot":
		if String(plot.get("kind", "")) == "supply_factory":
			return TDOutcome.new(false, "ALREADY", "%s已经建好了。" % TDTownMap.supply_name(String(plot.get("supply", "")), true))
		return TDOutcome.new(false, "INVALID", "只能在原料厂空地上建设。")
	var key := _factory_key(plot_id)
	if bool(factory_built.get(key, false)):
		return TDOutcome.new(false, "ALREADY", "%s已经建好了。" % TDTownMap.supply_name(String(plot.get("supply", "")), true))
	factory_built[key] = true
	if not town_map.mark_factory_built(plot_id):
		factory_built.erase(key)
		return TDOutcome.new(false, "MISSING", "没有这块原料厂空地。")
	var supply := String(plot.get("supply", ""))
	return TDOutcome.new(true, "BUILT", "%s建好了，提供%s。点击厂房安排生产。" % [TDTownMap.supply_name(supply, true), TDTownMap.supply_goods(supply)])

func factory_level_of(plot_id: String) -> int:
	return clampi(int(factory_level.get(_factory_key(plot_id), 1)), 1, TDTownMap.FACTORY_LEVEL_MAX)

func factory_quote(item_id: String) -> int:
	var base := int(_supply_item(item_id).get("cost", 0))
	if base <= 0:
		return 0
	var distance := 0
	if selected_market != "":
		distance = town_map.distance_to(selected_market)
	return maxi(1, int(round(float(base) * (1.0 + float(distance) * 0.05))))

func factory_hours(plot_id: String, item_id: String, qty: int) -> float:
	var plot := _plot_by_id(plot_id)
	var product := factory_product(String(plot.get("supply", "")), item_id)
	if product.is_empty():
		return 0.0
	return float(product["hours"]) * float(maxi(qty, 0)) * TDTownMap.time_scale(factory_level_of(plot_id))

func factory_lines(plot_id: String) -> int:
	return factory_level_of(plot_id)

func factory_running(plot_id: String) -> Array:
	var rows: Array = []
	for item: Variant in _factory_job_list(plot_id):
		if item is Dictionary:
			rows.append((item as Dictionary).duplicate(true))
	return rows

func factory_job(plot_id: String) -> Dictionary:
	var rows := factory_running(plot_id)
	if rows.is_empty():
		return {}
	return (rows[0] as Dictionary).duplicate(true)

func factory_progress(plot_id: String) -> float:
	var job := factory_job(plot_id)
	if job.is_empty():
		return 0.0
	var total := float(job.get("unit_hours", 0.0))
	var elapsed := float(job.get("unit_elapsed", 0.0))
	if total <= 0.001:
		total = float(job.get("total_hours", 0.0))
		elapsed = float(job.get("elapsed_hours", 0.0))
	if total <= 0.001:
		return 1.0
	return clampf(elapsed / total, 0.0, 1.0)

func _factory_job_list(plot_id: String) -> Array:
	var key := _factory_key(plot_id)
	var raw: Variant = factory_jobs.get(key, [])
	if raw is Array:
		return raw
	var wrapped: Array = []
	if raw is Dictionary and not (raw as Dictionary).is_empty():
		wrapped.append(raw)
	if not wrapped.is_empty() or factory_jobs.has(key):
		factory_jobs[key] = wrapped
	return wrapped

func factory_goods() -> Array:
	var rows: Array = []
	for supply_id: String in ["seasoning", "vegetable", "meat", "fruit"]:
		for item: Variant in factory_products(supply_id):
			var item_id := String((item as Dictionary).get("id", ""))
			var qty := supply.count(item_id)
			if qty <= 0:
				continue
			rows.append({
				"supply": supply_id,
				"id": item_id,
				"name": String(_supply_item(item_id).get("name", item_id)),
				"qty": qty,
			})
	return rows

func produce_factory(plot_id: String, item_id: String, qty: int, line_no: int = 0) -> TDOutcome:
	var plot := _plot_by_id(plot_id)
	if plot.is_empty() or String(plot.get("kind", "")) != "supply_factory":
		return TDOutcome.new(false, "MISSING", "先建成这家原料厂。")
	if qty < TDTownMap.FACTORY_QTY_MIN or qty > TDTownMap.FACTORY_QTY_MAX:
		return TDOutcome.new(false, "RANGE", "数量要在%d到%d之间。" % [TDTownMap.FACTORY_QTY_MIN, TDTownMap.FACTORY_QTY_MAX])
	var product := factory_product(String(plot.get("supply", "")), item_id)
	if product.is_empty():
		return TDOutcome.new(false, "WRONG", "这家厂不生产这种原料。")
	var key := _factory_key(plot_id)
	var running := _factory_job_list(plot_id)
	var used := {}
	for item: Variant in running:
		var existing: Dictionary = item
		used[int(existing.get("line", 0))] = true
	var line := line_no
	if line > 0:
		if line > factory_lines(plot_id):
			return TDOutcome.new(false, "MISSING", "没有这条产线。")
		if used.has(line):
			return TDOutcome.new(false, "BUSY", "产线%d正在生产。" % line)
	else:
		if running.size() >= factory_lines(plot_id):
			var current: Dictionary = running[0]
			return TDOutcome.new(false, "BUSY", "产线都在生产，当前是%s×%d。" % [String(current.get("name", "")), int(current.get("qty", 0))])
		line = 1
		while used.has(line):
			line += 1
	var unit_hours := factory_hours(plot_id, item_id, 1)
	var unit := factory_quote(item_id)
	var cost := unit * qty
	if money < cost:
		return TDOutcome.new(false, "BROKE", "生产要%d元。" % cost)
	var name := String(_supply_item(item_id).get("name", item_id))
	money -= cost
	running.append({
		"plot_id": plot_id,
		"line": line,
		"item_id": item_id,
		"name": name,
		"qty": qty,
		"cost": cost,
		"unit_hours": unit_hours,
		"unit_elapsed": 0.0,
		"total_hours": unit_hours * float(qty),
		"elapsed_hours": 0.0,
	})
	factory_jobs[key] = running
	_log("%s产线%d开始生产%s×%d，花%d元，每份%.1f小时。" % [String(plot.get("name", "原料厂")), line, name, qty, cost, unit_hours])
	return TDOutcome.new(true, "STARTED", "产线%d开始生产%s×%d，每份%.1f小时。做完一份就放进背包。" % [line, name, qty, unit_hours])

func tick_factories(delta_sec: float) -> Array:
	var finished: Array = []
	if delta_sec <= 0.0 or factory_jobs.is_empty():
		return finished
	var step := maxf(delta_sec, 0.0) / FACTORY_HOUR_SECONDS
	var pending: Array[String] = []
	for key: Variant in factory_jobs.keys():
		pending.append(String(key))
	for key: String in pending:
		var jobs: Array = []
		var raw: Variant = factory_jobs.get(key, [])
		if raw is Array:
			jobs = raw
		elif raw is Dictionary and not (raw as Dictionary).is_empty():
			jobs = [raw]
		var keep: Array = []
		for item: Variant in jobs:
			var job: Dictionary = item
			var unit_hours := float(job.get("unit_hours", 0.0))
			if unit_hours <= 0.001:
				var whole := maxi(int(job.get("qty", 1)), 1)
				unit_hours = float(job.get("total_hours", 0.0)) / float(whole)
				job["unit_hours"] = unit_hours
				job["unit_elapsed"] = float(job.get("elapsed_hours", 0.0))
			job["unit_elapsed"] = float(job.get("unit_elapsed", 0.0)) + step
			while unit_hours > 0.001 and float(job["unit_elapsed"]) + 0.0001 >= unit_hours and int(job.get("qty", 0)) > 0:
				job["unit_elapsed"] = float(job["unit_elapsed"]) - unit_hours
				job["qty"] = int(job.get("qty", 0)) - 1
				var item_id := String(job.get("item_id", ""))
				supply.stock[item_id] = int(supply.stock.get(item_id, 0)) + 1
				var done := job.duplicate(true)
				done["qty"] = 1
				done["stock"] = supply.count(item_id)
				finished.append(done)
				_log("产线%d的%s做好一份，背包里有%d。" % [int(job.get("line", 0)), String(job.get("name", item_id)), supply.count(item_id)])
			job["elapsed_hours"] = float(job.get("elapsed_hours", 0.0)) + step
			if int(job.get("qty", 0)) > 0:
				keep.append(job)
		if keep.is_empty():
			factory_jobs.erase(key)
		else:
			factory_jobs[key] = keep
	return finished

func upgrade_factory(plot_id: String) -> TDOutcome:
	var plot := _plot_by_id(plot_id)
	if plot.is_empty() or String(plot.get("kind", "")) != "supply_factory":
		return TDOutcome.new(false, "MISSING", "先建成这家原料厂。")
	var level := factory_level_of(plot_id)
	if level >= TDTownMap.FACTORY_LEVEL_MAX:
		return TDOutcome.new(false, "MAX", "厂房已经升到%d级。" % TDTownMap.FACTORY_LEVEL_MAX)
	var cost := 30 * level
	if money < cost:
		return TDOutcome.new(false, "BROKE", "升级要%d元。" % cost)
	money -= cost
	factory_level[_factory_key(plot_id)] = level + 1
	return TDOutcome.new(true, "UPGRADED", "升到%d级，新增一条产线，现在有%d条。新批次的时间变为原来的%.0f%%。" % [level + 1, level + 1, TDTownMap.time_scale(level + 1) * 100.0])

func click_build_at(cell: Vector2i) -> TDOutcome:
	var plot := town_map.plot_at(cell.x, cell.y)
	if plot.is_empty():
		return TDOutcome.new(false, "EMPTY", "这里没有可建设的空地。")
	var kind := String(plot.get("kind", ""))
	if kind == "diner_lot":
		return TDOutcome.new(false, "CHOOSE", "先选择中餐厅或西餐厅。")
	if kind == "factory_lot":
		return build_factory(String(plot.get("id", "")))
	if kind == "player_diner":
		return TDOutcome.new(false, "ALREADY", "餐厅已经建在这里。")
	if kind == "supply_factory":
		return TDOutcome.new(false, "ALREADY", "%s已经建在这里。" % TDTownMap.supply_name(String(plot.get("supply", "")), true))
	return TDOutcome.new(false, "INVALID", "点餐厅建设区或原料厂空地才能建设。")

func resize_home(size_id: String) -> TDOutcome:
	if not TDRestaurantSizes.IDS.has(size_id):
		return TDOutcome.new(false, "MISSING", "没有这种面积")
	if town_id != home_town_id:
		return TDOutcome.new(false, "WRONG_TOWN", "先回到主小镇，再改主店面积。")
	if not home_built:
		return TDOutcome.new(false, "NEED_HOME", "先在餐厅建设区点空地建店。")
	var lot := town_map.diner_lot()
	var foot := TDRestaurantSizes.footprint(size_id)
	var width := foot.x
	var height := foot.y
	if not lot.is_empty() and not _span_fits(width, height, lot):
		if _span_fits(height, width, lot):
			width = foot.y
			height = foot.x
		else:
			return TDOutcome.new(false, "BLOCKED", "建设区放不下这个面积，主店保持原样。")
	var previous_size := home_size
	var previous_w := home_w
	var previous_h := home_h
	home_size = size_id
	home_w = width
	home_h = height
	_rebuild_map()
	var diner := _plot_by_id("player_diner")
	if int(diner.get("w", 0)) * int(diner.get("h", 0)) != width * height:
		home_size = previous_size
		home_w = previous_w
		home_h = previous_h
		_rebuild_map()
		return TDOutcome.new(false, "BLOCKED", "建设区放不下这个面积，主店保持原样。")
	var room := TDRestaurantSizes.interior(size_id)
	return TDOutcome.new(true, "RESIZED", "主店地图%d×%d，店内%d×%d。" % [int(diner["w"]), int(diner["h"]), room.x, room.y])

func claim_branch(size_id: String, origin: Vector2i) -> TDOutcome:
	if not TDRestaurantSizes.IDS.has(size_id):
		return TDOutcome.new(false, "MISSING", "没有这种面积")
	if town_id == home_town_id:
		return TDOutcome.new(false, "HOME", "主店在餐厅建设区建造。别的小镇才能自己划分店。")
	if branch_open and branch_town != town_id:
		return TDOutcome.new(false, "ONE_BRANCH", "已经有一家分店。先关掉，才能在另一座小镇划地。")
	var foot := TDRestaurantSizes.footprint(size_id)
	var spot := _fit_claim(origin, foot.x, foot.y)
	if spot.is_empty():
		spot = _fit_claim(origin, foot.y, foot.x)
	if spot.is_empty():
		return TDOutcome.new(false, "BLOCKED", "这一格旁边的空地放不下%s店。站到一块空地的左上角再划。" % TDRestaurantSizes.name_of(size_id))
	var moving := branch_open and branch_town == town_id
	if not moving and money < CLAIM_FEE:
		return TDOutcome.new(false, "BROKE", "划地要%d元。" % CLAIM_FEE)
	if not moving:
		money -= CLAIM_FEE
	branch_open = true
	branch_town = town_id
	branch_culture = String(catalog.town(town_id).get("culture", ""))
	branch_size = size_id
	branch_x = int(spot["x"])
	branch_y = int(spot["y"])
	branch_w = int(spot["w"])
	branch_h = int(spot["h"])
	if branch_menu.is_empty():
		var town := catalog.town(town_id)
		var ids: Array = town.get("dish_ids", [])
		if not ids.is_empty():
			set_branch_menu([String(ids[0])])
	_rebuild_map()
	var room := TDRestaurantSizes.interior(size_id)
	return TDOutcome.new(true, "CLAIMED", "分店划在%s，地图%d×%d，店内%d×%d。饮食偏好是%s。" % [town_name(), branch_w, branch_h, room.x, room.y, branch_culture])

func close_branch() -> TDOutcome:
	if not branch_open:
		return TDOutcome.new(false, "CLOSED", "没有开着的分店。")
	branch_open = false
	branch_town = ""
	branch_menu = []
	branch_stock = {}
	for role: String in ROLES:
		branch_staff[role] = false
		_drop_profile("branch", role)
	branch_chef_recipes = []
	_rebuild_map()
	return TDOutcome.new(true, "CLOSED", "分店关了。同一天已经结算过的账还在，不会再算一遍。")

func set_branch_menu(dish_ids: Array) -> TDOutcome:
	if not branch_open:
		return TDOutcome.new(false, "CLOSED", "先开分店，再定菜单。")
	var next: Array = []
	for item: Variant in dish_ids:
		var snap := _snapshot_dish(String(item))
		if snap.is_empty():
			return TDOutcome.new(false, "MISSING", "没有%s这道菜。" % String(item))
		next.append(snap)
	branch_menu = next
	return TDOutcome.new(true, "MENU", "分店菜单换成了%d道菜。改原菜不会自动改这里，要单独同步。" % next.size())

func set_branch_price(dish_id: String, price: int) -> int:
	var next := maxi(1, price)
	for index in branch_menu.size():
		var entry: Dictionary = branch_menu[index]
		if String(entry.get("dish_id", "")) != dish_id:
			continue
		entry["price"] = next
		branch_menu[index] = entry
	return next

func stock_branch() -> TDOutcome:
	if not branch_open:
		return TDOutcome.new(false, "CLOSED", "分店还没开。")
	if branch_menu.is_empty():
		return TDOutcome.new(false, "EMPTY", "分店菜单是空的。")
	var entry: Dictionary = branch_menu[0]
	var ids: Array = (entry.get("snapshot", {}) as Dictionary).get("ingredients", [])
	if not _pantry_has(ids):
		return TDOutcome.new(false, "SHORT", "共享仓库里不够做一份%s。" % String((entry.get("snapshot", {}) as Dictionary).get("name", entry.get("dish_id", ""))))
	for item: Variant in ids:
		var ingredient_id := String(item)
		pantry.take(ingredient_id)
		branch_stock[ingredient_id] = int(branch_stock.get(ingredient_id, 0)) + 1
	return TDOutcome.new(true, "STOCKED", "从共享仓库拨了一份原料到分店。分店库存和主店原料分开记。")

func define_custom(id: String, title: String, culture_id: String, cost: int, ingredient_ids: Array) -> Dictionary:
	var version := 1
	if custom_recipes.has(id):
		version = int((custom_recipes[id] as Dictionary).get("version", 1)) + 1
	var row := {
		"id": id,
		"version": version,
		"name": title,
		"culture": culture_id,
		"ingredient_cost": maxi(1, cost),
		"ingredients": ingredient_ids.duplicate(),
		"reference": float(maxi(1, cost)),
	}
	custom_recipes[id] = row
	return row.duplicate(true)

func sync_branch_recipe(dish_id: String) -> TDOutcome:
	var current := _snapshot_dish(dish_id)
	if current.is_empty():
		return TDOutcome.new(false, "MISSING", "没有这道菜可同步。")
	for index in branch_menu.size():
		var entry: Dictionary = branch_menu[index]
		if String(entry.get("dish_id", "")) != dish_id:
			continue
		var history: Array = []
		if entry.get("history") is Array:
			history = (entry["history"] as Array).duplicate(true)
		history.append((entry.get("snapshot", {}) as Dictionary).duplicate(true))
		entry["history"] = history
		entry["version"] = int(current["version"])
		entry["snapshot"] = (current["snapshot"] as Dictionary).duplicate(true)
		entry["price"] = int(current["price"])
		branch_menu[index] = entry
		return TDOutcome.new(true, "SYNCED", "分店改用第%d版。上一版还留着。" % int(current["version"]))
	return TDOutcome.new(false, "MISSING", "分店菜单里没有这道菜。")

func teach_chef(store_id: String, dish_id: String) -> TDOutcome:
	var hired := staff_on("chef")
	if store_id == "branch":
		hired = bool(branch_staff.get("chef", false))
	if not hired:
		return TDOutcome.new(false, "NEED_CHEF", "还没有主厨。")
	if not recipes.has(dish_id) and not custom_recipes.has(dish_id):
		return TDOutcome.new(false, "LOCKED", "这道菜还没学会，不能教给主厨。")
	if money < 10:
		return TDOutcome.new(false, "BROKE", "教一道菜要10元。")
	money -= 10
	var version := 1
	if custom_recipes.has(dish_id):
		version = int((custom_recipes[dish_id] as Dictionary).get("version", 1))
	var book := _recipe_book(store_id)
	for index in book.size():
		var known: Dictionary = book[index]
		if String(known.get("dish_id", "")) != dish_id:
			continue
		known["proficiency"] = mini(100, int(known.get("proficiency", 20)) + 10)
		known["version"] = version
		book[index] = known
		_store_recipes(store_id, book)
		return TDOutcome.new(true, "TRAINED", "主厨把%s练到了%d。" % [_dish_name(dish_id), int(known["proficiency"])])
	book.append({"dish_id": dish_id, "version": version, "proficiency": 20})
	_store_recipes(store_id, book)
	return TDOutcome.new(true, "TRAINED", "主厨学会了%s。熟练度20，不会做成满分。" % _dish_name(dish_id))

func settle_branch() -> Dictionary:
	if not branch_open:
		return {"ok": false, "code": "CLOSED", "day": day, "revenue": 0, "wages": 0, "waste": 0, "served": 0, "guests": 0, "events": "分店还没开。"}
	var key := str(day)
	if branch_settled.has(key):
		var cached: Dictionary = (branch_settled[key] as Dictionary).duplicate(true)
		cached["code"] = "REPEAT"
		return cached
	var events := PackedStringArray()
	var wages := 0
	for role: String in ROLES:
		if not bool(branch_staff.get(role, false)):
			continue
		if int(branch_wage_paid.get(role, 0)) == day:
			continue
		var amount := _offered_wage("branch", role)
		if money < amount:
			branch_staff[role] = false
			if role == "chef":
				branch_chef_recipes = []
			_drop_profile("branch", role)
			events.append("%s付不出工资，离开。" % _role_title(role))
			continue
		money -= amount
		branch_wage_paid[role] = day
		wages += amount
		_tick_mood("branch", role)
		events.append("付了%s工资%d元。" % [_role_title(role), amount])
	var upkeep_due := store_upkeep("branch")
	var upkeep_paid := mini(money, upkeep_due)
	money -= upkeep_paid
	if upkeep_paid < upkeep_due:
		events.append("分店维护要%d元，只付了%d元。" % [upkeep_due, upkeep_paid])
	else:
		events.append("分店维护%d元。" % upkeep_paid)
	var revenue := 0
	var waste := 0
	var served := 0
	var guests := 0
	if not bool(branch_staff.get("manager", false)):
		events.append("缺店长，今天没有营业。")
	elif not bool(branch_staff.get("chef", false)):
		events.append("缺主厨，没有菜出锅。")
	elif branch_menu.is_empty():
		events.append("菜单是空的。")
	else:
		var lead: Dictionary = branch_menu[0]
		var lead_snap: Dictionary = lead.get("snapshot", {})
		guests = TDBranchSim.guest_count(branch_culture, String(lead_snap.get("culture", "")), int(lead.get("price", 1)), float(lead_snap.get("reference", 0)), bool(branch_staff.get("prep", false)))
		var chef_prof := int(branch_skill.get("chef", 20))
		for index in guests:
			var entry: Dictionary = branch_menu[index % branch_menu.size()]
			var dish_id := String(entry.get("dish_id", ""))
			var snap: Dictionary = entry.get("snapshot", {})
			var known := _chef_recipe("branch", dish_id)
			if known.is_empty():
				events.append("主厨不会%s。" % String(snap.get("name", dish_id)))
				continue
			var ids: Array = snap.get("ingredients", [])
			if not _branch_has(ids):
				events.append("缺货：%s。" % String(snap.get("name", dish_id)))
				continue
			_branch_consume(ids)
			var chef_profile := _profile("branch", "chef")
			var accident := TDBranchSim.accident_chance(chef_prof, String(chef_profile.get("care", "")), String(chef_profile.get("drive", "")), int(chef_profile.get("mood", 50)))
			if rng.unit() < accident:
				waste += int(snap.get("ingredient_cost", 0))
				events.append("%s做砸了，原料损耗。" % String(snap.get("name", dish_id)))
				continue
			var base_quality := TDBranchSim.cook_quality(int(known.get("proficiency", 20)))
			var quality := _adjusted_quality("branch", "chef", base_quality)
			var shift := _staff_shift("branch", "chef")
			revenue += int(entry.get("price", 0))
			served += 1
			events.append("卖出%s，品质%d，状态%+d，用的是第%d版。" % [String(snap.get("name", dish_id)), quality, shift, int(snap.get("version", 1))])
		if served > 0:
			branch_skill["chef"] = mini(100, chef_prof + 1)
		money += revenue
	var result := {
		"ok": true,
		"code": "SETTLED",
		"day": day,
		"revenue": revenue,
		"wages": wages,
		"waste": waste,
		"served": served,
		"guests": guests,
		"upkeep": upkeep_paid,
		"events": "；".join(events),
	}
	branch_settled[key] = result.duplicate(true)
	return result.duplicate(true)

func player_prep() -> TDOutcome:
	var dish_id := pantry_dish
	if String(duty.get("dish_id", "")) == dish_id and String(duty.get("prep", "")) == "prep" and String(duty.get("cook", "")) == "":
		return TDOutcome.new(false, "BUSY", "这道菜的备菜已经交给备菜岗，你不能再切一遍。")
	var taken := _take_bill(dish_id)
	if not taken.ok:
		return taken
	duty = {"dish_id": dish_id, "prep": "player", "cook": "", "quality": -1}
	return TDOutcome.new(true, "PREPPED", "你亲手备好了%s。" % _dish_name(dish_id))

func hand_prep() -> TDOutcome:
	if not staff_on("prep"):
		return TDOutcome.new(false, "NEED_PREP", "没有备菜岗。你可以自己备。")
	var dish_id := pantry_dish
	if String(duty.get("dish_id", "")) == dish_id and String(duty.get("prep", "")) == "player" and String(duty.get("cook", "")) == "":
		return TDOutcome.new(false, "BUSY", "你已经在备这道，备菜岗不能同时切。")
	var taken := _take_bill(dish_id)
	if not taken.ok:
		return taken
	duty = {"dish_id": dish_id, "prep": "prep", "cook": "", "quality": -1}
	home_skill["prep"] = mini(100, int(home_skill.get("prep", 20)) + 1)
	return TDOutcome.new(true, "PREPPED", "备菜岗用仓库里的原料备好了%s。这一步不用你切。" % _dish_name(dish_id))

func hand_cook() -> TDOutcome:
	if not staff_on("chef"):
		return TDOutcome.new(false, "NEED_CHEF", "没有主厨。")
	if String(duty.get("prep", "")) == "" or String(duty.get("cook", "")) != "":
		if String(duty.get("cook", "")) != "":
			return TDOutcome.new(false, "BUSY", "这道菜的烹调已经有人做了。")
		return TDOutcome.new(false, "NEED_PREP", "还没有备好的菜。主厨不会凭空出一份。")
	if String(duty.get("lock", "")) == "player":
		return TDOutcome.new(false, "BUSY", "你接手了这单，主厨不能同时做。")
	var dish_id := String(duty.get("dish_id", ""))
	var known := _chef_recipe("home", dish_id)
	if known.is_empty():
		return TDOutcome.new(false, "CANT", "主厨不会%s。先教会，或者你自己做。" % _dish_name(dish_id))
	var quality := 0
	var code := "ACCIDENT"
	var text := "%s做砸了，原料已经用掉。" % _dish_name(dish_id)
	var home_profile := _profile("home", "chef")
	var home_accident := TDBranchSim.accident_chance(int(home_skill.get("chef", 20)), String(home_profile.get("care", "")), String(home_profile.get("drive", "")), int(home_profile.get("mood", 50)))
	if rng.unit() >= home_accident:
		quality = _adjusted_quality("home", "chef", TDBranchSim.cook_quality(int(known.get("proficiency", 20))))
		code = "COOKED"
		text = "主厨做出%s，品质%d，状态%+d。不是满分，原料来自刚才的备菜。" % [_dish_name(dish_id), quality, _staff_shift("home", "chef")]
		known["proficiency"] = mini(100, int(known.get("proficiency", 20)) + 1)
		_write_recipe("home", known)
		home_skill["chef"] = mini(100, int(home_skill.get("chef", 20)) + 1)
	duty["cook"] = "chef"
	duty["quality"] = quality
	return TDOutcome.new(code != "ACCIDENT", code, text, {"quality": quality})

func player_finish(quality: int) -> TDOutcome:
	if String(duty.get("cook", "")) == "chef":
		return TDOutcome.new(false, "BUSY", "主厨已经做了烹调。同一工序不能再由你做一遍。")
	if String(duty.get("prep", "")) == "":
		return TDOutcome.new(false, "NEED_PREP", "还没有备好的菜。")
	if String(duty.get("cook", "")) == "player":
		return TDOutcome.new(false, "ALREADY", "你已经做完这道。")
	duty["cook"] = "player"
	duty["quality"] = clampi(quality, 0, 100)
	return TDOutcome.new(true, "COOKED", "你亲手做完了%s。" % _dish_name(String(duty.get("dish_id", ""))))

func take_over() -> TDOutcome:
	if String(duty.get("cook", "")) != "":
		return TDOutcome.new(false, "DONE", "这道菜已经出锅，不能再接手。")
	if String(duty.get("prep", "")) == "":
		return TDOutcome.new(false, "EMPTY", "还没有交给员工的工序。")
	duty["lock"] = "player"
	duty["prep"] = "player"
	return TDOutcome.new(true, "TAKEN", "你接手了。主厨不会再做这道。")

func export_phase4() -> Dictionary:
	return {
		"day": day,
		"money": money,
		"town_id": town_id,
		"home_town_id": home_town_id,
		"home_size": home_size,
		"home_built": home_built,
		"home_venue": home_venue,
		"home_w": home_w,
		"home_h": home_h,
		"factory_built": factory_built.duplicate(true),
		"factory_level": factory_level.duplicate(true),
		"factory_jobs": factory_jobs.duplicate(true),
		"branch_open": branch_open,
		"branch_town": branch_town,
		"branch_culture": branch_culture,
		"branch_size": branch_size,
		"branch_x": branch_x,
		"branch_y": branch_y,
		"branch_w": branch_w,
		"branch_h": branch_h,
		"branch_menu": branch_menu.duplicate(true),
		"branch_stock": branch_stock.duplicate(true),
		"branch_staff": branch_staff.duplicate(true),
		"branch_wage_paid": branch_wage_paid.duplicate(true),
		"branch_skill": branch_skill.duplicate(true),
		"branch_chef_recipes": branch_chef_recipes.duplicate(true),
		"branch_settled": branch_settled.duplicate(true),
		"home_chef_recipes": home_chef_recipes.duplicate(true),
		"home_skill": home_skill.duplicate(true),
		"custom_recipes": custom_recipes.duplicate(true),
		"staff": staff.duplicate(true),
		"wage_paid": wage_paid.duplicate(true),
		"staff_profiles": staff_profiles.duplicate(true),
		"profile_serial": _profile_serial,
	}

func import_phase4(data: Dictionary) -> void:
	day = int(data.get("day", day))
	money = int(data.get("money", money))
	town_id = String(data.get("town_id", town_id))
	home_town_id = String(data.get("home_town_id", home_town_id))
	home_size = String(data.get("home_size", home_size))
	home_built = bool(data.get("home_built", false))
	home_venue = String(data.get("home_venue", ""))
	home_w = int(data.get("home_w", 0))
	home_h = int(data.get("home_h", 0))
	factory_built = (data.get("factory_built", {}) as Dictionary).duplicate(true)
	factory_level = (data.get("factory_level", {}) as Dictionary).duplicate(true)
	factory_jobs = (data.get("factory_jobs", {}) as Dictionary).duplicate(true)
	branch_open = bool(data.get("branch_open", false))
	branch_town = String(data.get("branch_town", ""))
	branch_culture = String(data.get("branch_culture", ""))
	branch_size = String(data.get("branch_size", "small"))
	branch_x = int(data.get("branch_x", 0))
	branch_y = int(data.get("branch_y", 0))
	branch_w = int(data.get("branch_w", 0))
	branch_h = int(data.get("branch_h", 0))
	branch_menu = (data.get("branch_menu", []) as Array).duplicate(true)
	branch_stock = (data.get("branch_stock", {}) as Dictionary).duplicate(true)
	branch_staff = (data.get("branch_staff", {}) as Dictionary).duplicate(true)
	branch_wage_paid = (data.get("branch_wage_paid", {}) as Dictionary).duplicate(true)
	branch_skill = (data.get("branch_skill", {}) as Dictionary).duplicate(true)
	branch_chef_recipes = (data.get("branch_chef_recipes", []) as Array).duplicate(true)
	branch_settled = (data.get("branch_settled", {}) as Dictionary).duplicate(true)
	home_chef_recipes = (data.get("home_chef_recipes", []) as Array).duplicate(true)
	home_skill = (data.get("home_skill", {}) as Dictionary).duplicate(true)
	custom_recipes = (data.get("custom_recipes", {}) as Dictionary).duplicate(true)
	staff = (data.get("staff", {}) as Dictionary).duplicate(true)
	wage_paid = (data.get("wage_paid", {}) as Dictionary).duplicate(true)
	staff_profiles = (data.get("staff_profiles", {}) as Dictionary).duplicate(true)
	_profile_serial = int(data.get("profile_serial", 0))
	_rebuild_map()

func _rebuild_map() -> void:
	var reserve := {}
	if branch_open and town_id == branch_town:
		reserve = {"x": branch_x, "y": branch_y, "w": branch_w, "h": branch_h, "size": branch_size, "name": "分店"}
	var at_home := town_id == home_town_id
	var span := Vector2i(home_w, home_h) if at_home and home_built else Vector2i.ZERO
	town_map.build(catalog, TDTownMap.seed_of(town_id), home_size if at_home else "small", at_home and home_built, reserve, _built_factory_ids(), span, home_venue if at_home else "")
	map_revision += 1

func _built_factory_ids() -> Array:
	var rows: Array = []
	var prefix := "%s:" % town_id
	for key: Variant in factory_built.keys():
		var text := String(key)
		if not bool(factory_built[key]):
			continue
		if text.begins_with(prefix):
			rows.append(text.substr(prefix.length()))
	return rows

func _factory_key(plot_id: String) -> String:
	return "%s:%s" % [town_id, plot_id]

func _span_fits(width: int, height: int, lot: Dictionary) -> bool:
	return width <= int(lot.get("w", 0)) and height <= int(lot.get("h", 0))

func _footprint_fits_lot(foot: Vector2i, lot: Dictionary) -> bool:
	return _span_fits(foot.x, foot.y, lot) or _span_fits(foot.y, foot.x, lot)

func _employ_branch(role: String) -> TDOutcome:
	if not branch_open:
		return TDOutcome.new(false, "CLOSED", "先划地开分店，再雇分店的人。")
	if bool(branch_staff.get(role, false)):
		return TDOutcome.new(false, "ALREADY", "分店%s已经在岗" % _role_title(role))
	_open_profile("branch", role)
	var paid := _pay_branch_role(role)
	if not paid.ok:
		_drop_profile("branch", role)
		return paid
	branch_staff[role] = true
	_start_role("branch", role)
	if paid.code != "ALREADY_PAID":
		_tick_mood("branch", role)
	return TDOutcome.new(true, "HIRED", _hire_message("branch", role))

func _pay_branch_role(role: String) -> TDOutcome:
	if int(branch_wage_paid.get(role, 0)) == day:
		return TDOutcome.new(true, "ALREADY_PAID", "")
	var amount := _offered_wage("branch", role)
	if amount <= 0:
		return TDOutcome.new(false, "MISSING", "没有这个岗位的工资")
	if money < amount:
		return TDOutcome.new(false, "BROKE", "现金不够付分店%s工资%d元" % [_role_title(role), amount])
	money -= amount
	branch_wage_paid[role] = day
	_log("付了分店%s工资%d元。" % [_role_title(role), amount])
	return TDOutcome.new(true, "PAID", "")

func store_upkeep(store_id: String) -> int:
	if store_id == "branch":
		return TDRestaurantSizes.upkeep(branch_size)
	return TDRestaurantSizes.upkeep(home_size)

func set_wage(role: String, store_id: String, delta: int) -> TDOutcome:
	if not ROLES.has(role):
		return TDOutcome.new(false, "INVALID_ROLE", "没有这个岗位")
	var hired := staff_on(role)
	if store_id == "branch":
		hired = bool(branch_staff.get(role, false))
	if not hired:
		return TDOutcome.new(false, "NEED", "%s还没到岗。" % _role_title(role))
	var profile := _profile(store_id, role)
	if profile.is_empty():
		_open_profile(store_id, role)
		profile = _profile(store_id, role)
	var recommended := catalog.wage_of(role)
	var next := maxi(1, int(profile.get("wage", recommended)) + delta)
	profile["wage"] = next
	_write_profile(store_id, role, profile)
	var relation := "等于推荐"
	if next > recommended:
		relation = "高于推荐%d元，服务质量会提高" % [next - recommended]
	elif next < recommended:
		relation = "低于推荐%d元，服务质量会下降" % [recommended - next]
	return TDOutcome.new(true, "WAGE", "%s日薪改为%d元，推荐%d，%s。情绪下次发薪时再变。" % [_role_title(role), next, recommended, relation])

func staff_card(store_id: String, role: String) -> Dictionary:
	var profile := _profile(store_id, role)
	var recommended := catalog.wage_of(role)
	var wage := recommended
	var mood := 50
	var drive := ""
	var care := ""
	if not profile.is_empty():
		wage = int(profile.get("wage", recommended))
		mood = int(profile.get("mood", 50))
		drive = String(profile.get("drive", ""))
		care = String(profile.get("care", ""))
	return {
		"role": role,
		"wage": wage,
		"recommended": recommended,
		"mood": mood,
		"drive": drive,
		"care": care,
		"shift": TDBranchSim.quality_shift(mood, drive, care, wage, recommended),
	}

func _profile_key(store_id: String, role: String) -> String:
	return "%s:%s" % [store_id, role]

func _profile(store_id: String, role: String) -> Dictionary:
	var found: Variant = staff_profiles.get(_profile_key(store_id, role), {})
	if found is Dictionary:
		return (found as Dictionary).duplicate(true)
	return {}

func _write_profile(store_id: String, role: String, profile: Dictionary) -> void:
	staff_profiles[_profile_key(store_id, role)] = profile.duplicate(true)

func _open_profile(store_id: String, role: String) -> void:
	var drive := "lazy"
	if posmod(_profile_serial, 2) == 0:
		drive = "diligent"
	var care := "careless"
	if posmod(_profile_serial, 4) < 2:
		care = "careful"
	_profile_serial += 1
	_write_profile(store_id, role, {
		"wage": catalog.wage_of(role),
		"mood": 70,
		"drive": drive,
		"care": care,
	})

func _drop_profile(store_id: String, role: String) -> void:
	staff_profiles.erase(_profile_key(store_id, role))

func _offered_wage(store_id: String, role: String) -> int:
	var profile := _profile(store_id, role)
	if profile.is_empty():
		return catalog.wage_of(role)
	return maxi(1, int(profile.get("wage", catalog.wage_of(role))))

func _tick_mood(store_id: String, role: String) -> void:
	var profile := _profile(store_id, role)
	if profile.is_empty():
		return
	var recommended := catalog.wage_of(role)
	var delta := TDBranchSim.mood_delta(int(profile.get("wage", recommended)), recommended, String(profile.get("drive", "")))
	profile["mood"] = clampi(int(profile.get("mood", 70)) + delta, 0, 100)
	_write_profile(store_id, role, profile)

func _staff_shift(store_id: String, role: String) -> int:
	var card := staff_card(store_id, role)
	return int(card["shift"])

func _adjusted_quality(store_id: String, role: String, base: int) -> int:
	var card := staff_card(store_id, role)
	return TDBranchSim.service_quality(base, int(card["mood"]), String(card["drive"]), String(card["care"]), int(card["wage"]), int(card["recommended"]))

func _hire_message(store_id: String, role: String) -> String:
	var card := staff_card(store_id, role)
	var where := "分店" if store_id == "branch" else ""
	return "%s%s已到岗，日薪%d元，推荐%d。%s、%s，情绪%d。%s" % [where, _role_title(role), int(card["wage"]), int(card["recommended"]), TDBranchSim.drive_name(String(card["drive"])), TDBranchSim.care_name(String(card["care"])), int(card["mood"]), _chef_note(store_id, role)]

func _staff_mood_line(store_id: String) -> String:
	var bits := PackedStringArray()
	for role: String in ROLES:
		var hired := staff_on(role)
		if store_id == "branch":
			hired = bool(branch_staff.get(role, false))
		if not hired:
			continue
		var card := staff_card(store_id, role)
		bits.append("%s 日薪%d/推荐%d 情绪%d %s%s 状态%+d" % [_role_title(role), int(card["wage"]), int(card["recommended"]), int(card["mood"]), TDBranchSim.drive_name(String(card["drive"])), TDBranchSim.care_name(String(card["care"])), int(card["shift"])])
	if bits.is_empty():
		return "还没有在岗员工。工资可以高于推荐值，情绪和性格会改服务质量。"
	return "；".join(bits)

func _start_role(store_id: String, role: String) -> void:
	if role != "chef":
		return
	var card: Array = [{"dish_id": "tomato_egg", "version": 1, "proficiency": 40}]
	if store_id == "branch":
		branch_skill["chef"] = 25
		branch_chef_recipes = card.duplicate(true)
	else:
		home_skill["chef"] = 25
		home_chef_recipes = card.duplicate(true)

func _chef_note(store_id: String, role: String) -> String:
	if role != "chef":
		return ""
	return "会做：%s。不会的菜不能出锅，也不会凭空变成满分。" % _chef_names(store_id)

func _chef_names(store_id: String) -> String:
	var names := PackedStringArray()
	for item: Variant in _recipe_book(store_id):
		names.append(_dish_name(String((item as Dictionary).get("dish_id", ""))))
	if names.is_empty():
		return "还没有菜"
	return "、".join(names)

func _recipe_book(store_id: String) -> Array:
	if store_id == "branch":
		return branch_chef_recipes
	return home_chef_recipes

func _chef_recipe(store_id: String, dish_id: String) -> Dictionary:
	var book := _recipe_book(store_id)
	for item: Variant in book:
		var known: Dictionary = item
		if String(known.get("dish_id", "")) == dish_id:
			return known.duplicate(true)
	return {}

func _write_recipe(store_id: String, known: Dictionary) -> void:
	var book := _recipe_book(store_id)
	for index in book.size():
		if String((book[index] as Dictionary).get("dish_id", "")) != String(known.get("dish_id", "")):
			continue
		book[index] = known.duplicate(true)
	_store_recipes(store_id, book)

func _store_recipes(store_id: String, book: Array) -> void:
	if store_id == "branch":
		branch_chef_recipes = book
	else:
		home_chef_recipes = book

func _take_bill(dish_id: String) -> TDOutcome:
	var ids := pantry.bill(dish_id)
	if ids.is_empty():
		return TDOutcome.new(false, "NO_BILL", "这道菜没有原料清单")
	if not _pantry_has(ids):
		return TDOutcome.new(false, "SHORT", "仓库里的原料不够备%s。" % _dish_name(dish_id))
	for ingredient_id: String in ids:
		pantry.take(ingredient_id)
	return TDOutcome.new(true, "TAKEN", "")

func _pantry_has(ids: Array) -> bool:
	var need := {}
	for item: Variant in ids:
		var key := String(item)
		need[key] = int(need.get(key, 0)) + 1
	for key: Variant in need.keys():
		if pantry.count(String(key)) < int(need[key]):
			return false
	return true

func _branch_has(ids: Array) -> bool:
	var need := {}
	for item: Variant in ids:
		var key := String(item)
		need[key] = int(need.get(key, 0)) + 1
	for key: Variant in need.keys():
		if int(branch_stock.get(String(key), 0)) < int(need[key]):
			return false
	return true

func _branch_consume(ids: Array) -> void:
	for item: Variant in ids:
		var key := String(item)
		branch_stock[key] = int(branch_stock.get(key, 0)) - 1

func _snapshot_dish(dish_id: String) -> Dictionary:
	if custom_recipes.has(dish_id):
		var custom: Dictionary = (custom_recipes[dish_id] as Dictionary).duplicate(true)
		return {
			"dish_id": dish_id,
			"version": int(custom.get("version", 1)),
			"price": maxi(1, int(custom.get("ingredient_cost", 1)) + 4),
			"snapshot": custom,
			"history": [],
		}
	var dish := catalog.dish(dish_id)
	if dish.is_empty():
		return {}
	var ingredients: Array = []
	for ingredient_id: String in pantry.bill(dish_id):
		ingredients.append(ingredient_id)
	return {
		"dish_id": dish_id,
		"version": 1,
		"price": price_of(dish_id),
		"history": [],
		"snapshot": {
			"id": dish_id,
			"version": 1,
			"name": String(dish.get("name", dish_id)),
			"culture": String(dish.get("culture", "")),
			"ingredient_cost": int(dish.get("ingredient_cost", 1)),
			"ingredients": ingredients,
			"reference": catalog.reference_of(dish_id),
		},
	}

func _fit_claim(origin: Vector2i, width: int, height: int) -> Dictionary:
	if town_map.can_place(origin.x, origin.y, width, height):
		return {"x": origin.x, "y": origin.y, "w": width, "h": height}
	return {}

func _plot_by_id(id: String) -> Dictionary:
	for item: Variant in town_map.plots:
		var plot: Dictionary = item
		if String(plot.get("id", "")) == id:
			return plot
	return {}

func _dish_name(dish_id: String) -> String:
	if custom_recipes.has(dish_id):
		return String((custom_recipes[dish_id] as Dictionary).get("name", dish_id))
	return String(catalog.dish(dish_id).get("name", dish_id))

func _branch_line() -> String:
	if not home_built:
		return "主店还没建。点餐厅建设区空地建店；点原料厂空地建厂。分店仍在别的小镇划地，同时只开一家。"
	if not branch_open:
		return "分店还没开。主店在餐厅建设区，默认%s。别的小镇可以自己划地，同时只开一家。" % TDRestaurantSizes.name_of(home_size)
	var room := TDRestaurantSizes.interior(branch_size)
	return "分店在%s，地图%d×%d，店内%d×%d。菜单和员工跟主店分开，钱和学会的菜谱共用。" % [branch_town, branch_w, branch_h, room.x, room.y]

func _log(text: String) -> void:
	log_lines.append(text)
	if log_lines.size() > 12:
		log_lines.remove_at(0)
