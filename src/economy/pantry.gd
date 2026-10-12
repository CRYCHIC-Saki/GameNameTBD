class_name TDPantry
extends RefCounted

const SOURCE := "res://content/pantry.json"

var shelf_days: Dictionary = {}
var costs: Dictionary = {}
var devices: Array = []
var dishes: Dictionary = {}
var notes: Dictionary = {}
var lots: Array = []
var _serial: int = 1

func load_rules(path: String = SOURCE) -> TDOutcome:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return TDOutcome.new(false, "READ_FAILED", path)
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return TDOutcome.new(false, "INVALID_JSON", "%s:%d" % [path, parser.get_error_line()])
	return load_data(parser.data)

func load_data(raw: Variant) -> TDOutcome:
	if not raw is Dictionary or int((raw as Dictionary).get("schema_version", -1)) != 1:
		return TDOutcome.new(false, "BAD_VERSION", "备料配置需要版本 1")
	var data: Dictionary = raw
	if not data.get("shelf_days") is Dictionary or not data.get("costs") is Dictionary or not data.get("devices") is Array or not data.get("dishes") is Dictionary:
		return TDOutcome.new(false, "INVALID_CONTENT", "备料配置不完整")
	if (data["devices"] as Array).is_empty():
		return TDOutcome.new(false, "INVALID_CONTENT", "至少要有一种存放设备")
	shelf_days = (data["shelf_days"] as Dictionary).duplicate(true)
	costs = (data["costs"] as Dictionary).duplicate(true)
	devices = (data["devices"] as Array).duplicate(true)
	dishes = (data["dishes"] as Dictionary).duplicate(true)
	notes = {}
	if data.get("notes") is Dictionary:
		notes = (data["notes"] as Dictionary).duplicate(true)
	return TDOutcome.new(true, "OK", "")

func device(id: String) -> Dictionary:
	for item: Variant in devices:
		if String((item as Dictionary).get("id", "")) == id:
			return (item as Dictionary).duplicate(true)
	return {}

func note(dish_id: String) -> String:
	return String(notes.get(dish_id, ""))

func bill(dish_id: String) -> Array[String]:
	if not dishes.has(dish_id) or not dishes[dish_id] is Array:
		return []
	var result: Array[String] = []
	for id: Variant in dishes[dish_id]:
		result.append(String(id))
	return result

func cost_of(item: Dictionary) -> int:
	return maxi(1, int(costs.get(String(item.get("category", "")), 1)))

func life_days(category: String, device_id: String) -> int:
	var base := maxi(1, int(shelf_days.get(category, 1)))
	var factors: Dictionary = device(device_id).get("factor", {})
	var factor := float(factors.get(category, factors.get("default", 1.0)))
	if factor < 1.0:
		factor = 1.0
	return maxi(1, ceili(float(base) * factor))

func store(item: Dictionary, device_id: String, day: int) -> Dictionary:
	var life := life_days(String(item["category"]), device_id)
	var lot := {
		"id": "lot-%d" % _serial,
		"ingredient_id": String(item["id"]),
		"name": String(item["name"]),
		"category": String(item["category"]),
		"device_id": device_id,
		"stored_on": day,
		"life_days": life,
		"expires_on": day + life,
	}
	_serial += 1
	lots.append(lot)
	return lot.duplicate(true)

func take(ingredient_id: String) -> Dictionary:
	for index in lots.size():
		var lot: Dictionary = lots[index]
		if String(lot["ingredient_id"]) != ingredient_id:
			continue
		lots.remove_at(index)
		return lot.duplicate(true)
	return {}

func count(ingredient_id: String) -> int:
	var total := 0
	for item: Variant in lots:
		if String((item as Dictionary)["ingredient_id"]) == ingredient_id:
			total += 1
	return total

func spoil(day: int) -> Array:
	var gone: Array = []
	var kept: Array = []
	for item: Variant in lots:
		var lot: Dictionary = item
		if int(lot["expires_on"]) <= day:
			gone.append(lot.duplicate(true))
		else:
			kept.append(lot)
	lots = kept
	return gone

func summary(today: int, limit: int = 8) -> String:
	if lots.is_empty():
		return "原料库存是空的。"
	var lines: PackedStringArray = []
	var shown := mini(limit, lots.size())
	for index in shown:
		var lot: Dictionary = lots[index]
		var left := int(lot["expires_on"]) - today
		lines.append("%s %s 剩%d天" % [String(lot["name"]), _device_name(String(lot["device_id"])), left])
	if lots.size() > shown:
		lines.append("还有%d份" % [lots.size() - shown])
	return "、".join(lines)

func _device_name(id: String) -> String:
	var found := device(id)
	if found.is_empty():
		return id
	return String(found["name"])
