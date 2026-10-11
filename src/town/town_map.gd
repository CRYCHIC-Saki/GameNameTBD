class_name TDTownMap
extends RefCounted

const SIZE := 21
const CENTER := 10

var plots: Array = []
var housing_names: Array[String] = []

func build(catalog: TDTownCatalog, seed_value: int) -> void:
	var rng := TDBusinessRandom.new(seed_value)
	var fixed := {
		"player_diner": Vector2i(11, 11),
		"market": Vector2i(14, 11),
		"commercial_street": Vector2i(11, 14),
		"snack_street": Vector2i(6, 11),
		"urban_village": Vector2i(2, 11),
		"competitor": Vector2i(11, 7),
		"rich_district": Vector2i(15, 7),
		"amusement": Vector2i(4, 7),
		"zoo": Vector2i(1, 7),
		"landmark": Vector2i(11, 2),
	}
	plots = []
	var plaza := _plot("plaza", "城市广场", CENTER, CENTER, catalog)
	plaza["walkable"] = true
	plots.append(plaza)
	var used := {}
	_claim(used, plaza)
	for id: String in fixed.keys():
		var cell: Vector2i = fixed[id]
		var zone := catalog_zone(catalog, id)
		var plot := _plot(id, String(zone.get("name", id)), cell.x, cell.y, catalog)
		_claim(used, plot)
		plots.append(plot)
	housing_names = []
	var serial := 1
	for y in SIZE:
		for x in SIZE:
			if is_road(x, y) or used.has(Vector2i(x, y)):
				continue
			var name := _house_name(rng, serial)
			serial += 1
			housing_names.append(name)
			var house := {
				"id": "house-%d" % serial,
				"name": name,
				"kind": "housing",
				"x": x,
				"y": y,
				"w": 1,
				"h": 1,
				"enabled": true,
				"walkable": false,
				"pool": 1,
				"budget_shift": 0,
				"foreign_scale": 1.0,
			}
			house["approach_x"] = _approach(x, y).x
			house["approach_y"] = _approach(x, y).y
			plots.append(house)

func is_road(x: int, y: int) -> bool:
	return x == CENTER or y == CENTER

func is_walkable(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < SIZE and y < SIZE and is_road(x, y)

func plot_at(x: int, y: int) -> Dictionary:
	for item: Variant in plots:
		var plot: Dictionary = item
		var width := int(plot.get("w", 1))
		var height := int(plot.get("h", 1))
		if x >= int(plot["x"]) and y >= int(plot["y"]) and x < int(plot["x"]) + width and y < int(plot["y"]) + height:
			return plot.duplicate(true)
	return {}

func covers_road(plot: Dictionary) -> bool:
	for y in int(plot.get("h", 1)):
		for x in int(plot.get("w", 1)):
			if is_road(int(plot["x"]) + x, int(plot["y"]) + y):
				return true
	return false

func set_enabled(id: String, enabled: bool) -> void:
	for index in plots.size():
		var plot: Dictionary = plots[index]
		if String(plot["id"]) == id and String(plot["kind"]) != "player_diner" and String(plot["kind"]) != "plaza":
			plot["enabled"] = enabled
			plots[index] = plot

func set_housing_enabled(enabled: bool) -> void:
	for index in plots.size():
		var plot: Dictionary = plots[index]
		if String(plot["kind"]) == "housing":
			plot["enabled"] = enabled
			plots[index] = plot

func housing_enabled() -> int:
	var count := 0
	for item: Variant in plots:
		var plot: Dictionary = item
		if String(plot["kind"]) == "housing" and bool(plot["enabled"]):
			count += 1
	return count

func zone_rows(catalog: TDTownCatalog) -> Array:
	var rows: Array = []
	for id: String in TDTownCatalog.ZONE_IDS:
		var zone := catalog_zone(catalog, id)
		var plot := _by_kind(id)
		zone["enabled"] = bool(plot.get("enabled", true))
		rows.append(zone)
	return rows

func _by_kind(kind: String) -> Dictionary:
	for item: Variant in plots:
		var plot: Dictionary = item
		if String(plot["kind"]) == kind:
			return plot
	return {}

func catalog_zone(catalog: TDTownCatalog, id: String) -> Dictionary:
	for item: Variant in catalog.zones:
		var zone: Dictionary = item
		if String(zone["id"]) == id:
			return zone.duplicate(true)
	return {"id": id, "name": id, "pool": 0, "budget_shift": 0, "foreign_scale": 1.0}

func _plot(kind: String, title: String, x: int, y: int, catalog: TDTownCatalog) -> Dictionary:
	var zone := catalog_zone(catalog, kind)
	var approach := _approach(x, y)
	return {
		"id": kind,
		"name": title,
		"kind": kind,
		"x": x,
		"y": y,
		"w": maxi(1, int(zone.get("w", 1))),
		"h": maxi(1, int(zone.get("h", 1))),
		"enabled": true,
		"walkable": false,
		"pool": int(zone.get("pool", 0)),
		"budget_shift": int(zone.get("budget_shift", 0)),
		"foreign_scale": float(zone.get("foreign_scale", 1.0)),
		"approach_x": approach.x,
		"approach_y": approach.y,
	}

func _claim(used: Dictionary, plot: Dictionary) -> void:
	for y in int(plot.get("h", 1)):
		for x in int(plot.get("w", 1)):
			used[Vector2i(int(plot["x"]) + x, int(plot["y"]) + y)] = true

func _approach(x: int, y: int) -> Vector2i:
	if is_road(x, y):
		return Vector2i(x, y)
	if is_walkable(x, CENTER):
		return Vector2i(x, CENTER)
	return Vector2i(CENTER, y)

func _house_name(rng: TDBusinessRandom, serial: int) -> String:
	var faces := ["青瓦", "白墙", "红门", "木窗", "窄巷", "天台"]
	return "%s住户%d" % [faces[int(rng.unit() * float(faces.size())) % faces.size()], serial]
