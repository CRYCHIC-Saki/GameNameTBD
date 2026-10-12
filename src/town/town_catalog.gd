class_name TDTownCatalog
extends RefCounted

const SOURCE := "res://content/phase3_world.json"
const PLAYABLE_IDS: Array[String] = ["london", "delhi", "paris", "stockholm", "moscow", "guangzhou", "shanghai", "wuhan", "beijing", "urumqi", "harbin", "chengdu", "xian"]
const ZONE_IDS: Array[String] = ["player_diner", "competitor", "market", "plaza", "urban_village", "rich_district", "commercial_street", "snack_street", "amusement", "zoo", "landmark"]
const KITCHEN_INGREDIENTS: Array[String] = ["tomato", "egg", "beef", "noodles", "tofu", "bean_paste", "chicken", "peanut", "pork", "chili", "mushroom", "scallion", "sugar", "oil", "garlic", "pepper", "wine", "ginger", "salt", "vinegar", "soy_sauce", "starch"]
const KITCHEN_CUTS: Array[String] = ["prepare", "service.slice", "service.strips", "service.dice", "service.small"]
const RESERVED_PRIMARIES: Array[String] = ["egg|tomato", "beef|noodles", "bean_paste|tofu", "chicken|peanut", "chili|pork", "chicken|mushroom"]

var unlock_score: float = 60.0
var off_menu_chance: float = 0.45
var starter_money: int = 300
var pool_base: int = 12
var housing_cap: int = 12
var zone_effect_note: String = ""
var wildcards: Array[String] = []
var buffs: Dictionary = {}
var expenses: Dictionary = {}
var kitchen_cards: Dictionary = {}
var supply_items: Array = []
var zones: Array = []
var towns: Array = []
var dishes: Dictionary = {}

func load_file(path: String = SOURCE) -> TDOutcome:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return TDOutcome.new(false, "READ_FAILED", path)
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return TDOutcome.new(false, "INVALID_JSON", "%s:%d" % [path, parser.get_error_line()])
	return load_data(parser.data)

func load_data(raw: Variant) -> TDOutcome:
	if not raw is Dictionary:
		return TDOutcome.new(false, "INVALID_CONTENT", "Phase3 配置必须是对象")
	var data: Dictionary = raw
	if int(data.get("schema_version", -1)) != 1:
		return TDOutcome.new(false, "BAD_VERSION", "Phase3 配置需要版本 1")
	unlock_score = float(data.get("unlock_score", 60))
	off_menu_chance = float(data.get("off_menu_chance", 0.45))
	starter_money = int(data.get("starter_money", 300))
	pool_base = int(data.get("pool_base", 12))
	housing_cap = int(data.get("housing_cap", 12))
	zone_effect_note = String(data.get("zone_effect_note", ""))
	var wildcard_list := _strings(data.get("wildcards"))
	if not wildcard_list.ok:
		return wildcard_list
	var zone_list := _zones(data.get("zones"))
	if not zone_list.ok:
		return zone_list
	var town_list := _towns(data.get("towns"))
	if not town_list.ok:
		return town_list
	var dish_list := _dishes(data.get("dishes"), town_list.data["ids"])
	if not dish_list.ok:
		return dish_list
	var cards := _kitchen_cards(data.get("kitchen_cards"), dish_list.data["values"])
	if not cards.ok:
		return cards
	var expense_book := _expenses(data.get("expenses"))
	if not expense_book.ok:
		return expense_book
	var supply := _supply(data.get("supply"))
	if not supply.ok:
		return supply
	if not data.get("buffs") is Dictionary:
		return TDOutcome.new(false, "INVALID_CONTENT", "缺少供货加成")
	wildcards = wildcard_list.data["values"]
	zones = zone_list.data["values"]
	towns = town_list.data["values"]
	dishes = dish_list.data["values"]
	kitchen_cards = cards.data["values"]
	expenses = expense_book.data["values"]
	supply_items = supply.data["values"]
	buffs = (data["buffs"] as Dictionary).duplicate(true)
	return TDOutcome.new(true, "OK", "")

func playable_towns() -> Array:
	var result: Array = []
	for item: Variant in towns:
		var town: Dictionary = item
		if bool(town["playable"]):
			result.append(town.duplicate(true))
	return result

func town(id: String) -> Dictionary:
	for item: Variant in towns:
		var current: Dictionary = item
		if String(current["id"]) == id:
			return current.duplicate(true)
	return {}

func dish(id: String) -> Dictionary:
	if not dishes.has(id):
		return {}
	var current: Dictionary = (dishes[id] as Dictionary).duplicate(true)
	if kitchen_cards.has(id):
		current["kitchen"] = (kitchen_cards[id] as Dictionary).duplicate(true)
	return current

func kitchen_recipe_id(dish_id: String) -> String:
	var current := dish(dish_id)
	if current.is_empty():
		return ""
	var service_id := String(current.get("service_recipe", ""))
	if service_id != "":
		return service_id
	if current.has("kitchen"):
		return "phase3." + dish_id
	return ""

func dish_id_for_kitchen(recipe_id: String) -> String:
	if recipe_id == "":
		return ""
	for item: Variant in dish_list():
		var current: Dictionary = item
		var id := String(current["id"])
		if kitchen_recipe_id(id) == recipe_id:
			return id
	return ""

func wage_of(role: String) -> int:
	return int((expenses.get("wages", {}) as Dictionary).get(role, 0))

func dish_list() -> Array:
	var result: Array = []
	for key: Variant in dishes.keys():
		result.append(dish(String(key)))
	return result

func reference_of(id: String) -> float:
	var current := dish(id)
	if current.is_empty():
		return 0.0
	return TDEconomyMath.reference_price(float(current["ingredient_cost"]), float(current["labor_factor"]), float(current["value_offset"]))

func _strings(raw: Variant) -> TDOutcome:
	if not raw is Array or (raw as Array).is_empty():
		return TDOutcome.new(false, "INVALID_CONTENT", "通配风格不能为空")
	var values: Array[String] = []
	for item: Variant in raw:
		if not item is String or String(item) == "":
			return TDOutcome.new(false, "INVALID_CONTENT", "通配风格无效")
		values.append(String(item))
	return TDOutcome.new(true, "OK", "", {"values": values})

func _zones(raw: Variant) -> TDOutcome:
	if not raw is Array:
		return TDOutcome.new(false, "INVALID_CONTENT", "功能区无效")
	var values: Array = []
	var seen := {}
	for item: Variant in raw:
		if not item is Dictionary:
			return TDOutcome.new(false, "INVALID_CONTENT", "功能区必须是对象")
		var zone: Dictionary = (item as Dictionary).duplicate(true)
		var id := String(zone.get("id", ""))
		if id == "" or seen.has(id):
			return TDOutcome.new(false, "DUPLICATE_ID", id)
		seen[id] = true
		if int(zone.get("w", 0)) < 1 or int(zone.get("h", 0)) < 1:
			return TDOutcome.new(false, "INVALID_CONTENT", id)
		zone["enabled"] = true
		values.append(zone)
	for id: String in ZONE_IDS:
		if not seen.has(id):
			return TDOutcome.new(false, "MISSING", id)
	return TDOutcome.new(true, "OK", "", {"values": values})

func _towns(raw: Variant) -> TDOutcome:
	if not raw is Array:
		return TDOutcome.new(false, "INVALID_CONTENT", "小镇无效")
	var values: Array = []
	var ids := {}
	for item: Variant in raw:
		if not item is Dictionary:
			return TDOutcome.new(false, "INVALID_CONTENT", "小镇必须是对象")
		var town: Dictionary = (item as Dictionary).duplicate(true)
		var id := String(town.get("id", ""))
		if id == "" or ids.has(id):
			return TDOutcome.new(false, "DUPLICATE_ID", id)
		if String(town.get("culture", "")) == "" or String(town.get("nickname", "")) == "":
			return TDOutcome.new(false, "INVALID_CONTENT", id)
		ids[id] = true
		values.append(town)
	for id: String in PLAYABLE_IDS:
		var found: Dictionary = {}
		for item: Variant in values:
			if String((item as Dictionary)["id"]) == id:
				found = item
		if found.is_empty() or not bool(found.get("playable", false)):
			return TDOutcome.new(false, "MISSING", id)
	return TDOutcome.new(true, "OK", "", {"values": values, "ids": ids})

func _dishes(raw: Variant, town_ids: Dictionary) -> TDOutcome:
	if not raw is Array or (raw as Array).is_empty():
		return TDOutcome.new(false, "INVALID_CONTENT", "菜谱不能为空")
	var values := {}
	for item: Variant in raw:
		if not item is Dictionary:
			return TDOutcome.new(false, "INVALID_CONTENT", "菜谱必须是对象")
		var dish: Dictionary = (item as Dictionary).duplicate(true)
		var id := String(dish.get("id", ""))
		if id == "" or values.has(id):
			return TDOutcome.new(false, "DUPLICATE_ID", id)
		if not town_ids.has(String(dish.get("town_id", ""))):
			return TDOutcome.new(false, "MISSING", id)
		if float(dish.get("labor_factor", 0)) <= 0.0 or float(dish.get("price", 0)) <= 0.0:
			return TDOutcome.new(false, "INVALID_CONTENT", id)
		if String(dish.get("source", "")) != "towns.json" and String(dish.get("source", "")) != "PROPOSED" and String(dish.get("source", "")) != "onboarding":
			return TDOutcome.new(false, "INVALID_CONTENT", id)
		values[id] = dish
	return TDOutcome.new(true, "OK", "", {"values": values})

func _kitchen_cards(raw: Variant, dish_values: Dictionary) -> TDOutcome:
	if not raw is Dictionary:
		return TDOutcome.new(false, "INVALID_CONTENT", "厨房谱面表无效")
	var values := {}
	var seen := {}
	for dish_id: Variant in dish_values.keys():
		var dish: Dictionary = dish_values[dish_id]
		var service_id := String(dish.get("service_recipe", ""))
		if service_id != "":
			continue
		if not (raw as Dictionary).has(dish_id):
			return TDOutcome.new(false, "MISSING", String(dish_id))
	for dish_id: Variant in raw:
		if not dish_id is String or not dish_values.has(dish_id):
			return TDOutcome.new(false, "MISSING", String(dish_id))
		var dish: Dictionary = dish_values[dish_id]
		if String(dish.get("service_recipe", "")) != "":
			return TDOutcome.new(false, "INVALID_CONTENT", String(dish_id))
		var card: Dictionary = (raw[dish_id] as Dictionary).duplicate(true) if raw[dish_id] is Dictionary else {}
		if card.is_empty():
			return TDOutcome.new(false, "INVALID_CONTENT", String(dish_id))
		var method := String(card.get("method", ""))
		var chart := String(card.get("chart", ""))
		if method == "stir" and chart != "service.tomato_egg":
			return TDOutcome.new(false, "INVALID_CONTENT", String(dish_id))
		if method == "steam" and chart != "service.qiguoji":
			return TDOutcome.new(false, "INVALID_CONTENT", String(dish_id))
		if method not in ["stir", "steam"]:
			return TDOutcome.new(false, "INVALID_CONTENT", String(dish_id))
		if String(card.get("cut", "")) not in KITCHEN_CUTS:
			return TDOutcome.new(false, "INVALID_CONTENT", String(dish_id))
		var primary: Variant = card.get("primary", [])
		if not primary is Array or (primary as Array).size() != 2:
			return TDOutcome.new(false, "INVALID_CONTENT", String(dish_id))
		var names: Array[String] = []
		for ingredient: Variant in primary:
			if not ingredient is String or String(ingredient) not in KITCHEN_INGREDIENTS:
				return TDOutcome.new(false, "INVALID_CONTENT", String(dish_id))
			names.append(String(ingredient))
		names.sort()
		var key := "|".join(names)
		if seen.has(key) or key in RESERVED_PRIMARIES:
			return TDOutcome.new(false, "DUPLICATE_ID", key)
		seen[key] = true
		card["primary"] = names
		values[String(dish_id)] = card
	return TDOutcome.new(true, "OK", "", {"values": values})

func _expenses(raw: Variant) -> TDOutcome:
	if not raw is Dictionary:
		return TDOutcome.new(false, "INVALID_CONTENT", "开支无效")
	var book: Dictionary = raw
	for field: String in ["rent", "utilities", "hardware_per_piece"]:
		if int(book.get(field, -1)) < 0:
			return TDOutcome.new(false, "INVALID_CONTENT", field)
	var wages: Variant = book.get("wages", {})
	if not wages is Dictionary or int((wages as Dictionary).get("greeter", 0)) <= 0 or int((wages as Dictionary).get("cashier", 0)) <= 0:
		return TDOutcome.new(false, "INVALID_CONTENT", "wages")
	return TDOutcome.new(true, "OK", "", {"values": book.duplicate(true)})

func _supply(raw: Variant) -> TDOutcome:
	if not raw is Array or (raw as Array).is_empty():
		return TDOutcome.new(false, "INVALID_CONTENT", "供货清单不能为空")
	var values: Array = []
	var seen := {}
	for item: Variant in raw:
		if not item is Dictionary:
			return TDOutcome.new(false, "INVALID_CONTENT", "供货必须是对象")
		var row: Dictionary = (item as Dictionary).duplicate(true)
		var id := String(row.get("id", ""))
		if id == "" or seen.has(id) or int(row.get("cost", -1)) < 0:
			return TDOutcome.new(false, "INVALID_CONTENT", id)
		seen[id] = true
		values.append(row)
	return TDOutcome.new(true, "OK", "", {"values": values})
