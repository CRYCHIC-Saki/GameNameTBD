class_name TDTownMap
extends RefCounted

const SIZE := 41
const CENTER := 20
const LONG_KINDS: Array[String] = ["plaza", "amusement", "snack_street", "commercial_street"]
const MARKET_TIERS: Array = [
	{"id": "market-small", "name": "街口菜摊", "tier": 1, "w": 2, "h": 2, "unlocks": ["tomato", "egg", "scallion", "oil", "salt"]},
	{"id": "market-mid", "name": "社区菜市", "tier": 2, "w": 4, "h": 3, "unlocks": ["tomato", "egg", "scallion", "oil", "salt", "noodles", "tofu", "pork", "chili", "flour"]},
	{"id": "market-large", "name": "城南大市", "tier": 3, "w": 6, "h": 4, "unlocks": []},
]

var plots: Array = []
var housing_names: Array[String] = []
var roads: Dictionary = {}

static func seed_of(town_id: String) -> int:
	var value := 20261012
	for index in town_id.length():
		value = (value * 33 + town_id.unicode_at(index)) % 1000003
	return value

func build(catalog: TDTownCatalog, seed_value: int, home_size: String = "small", place_diner: bool = true, reserve: Dictionary = {}) -> void:
	var rng := TDBusinessRandom.new(seed_value)
	_grow_roads(rng)
	plots = []
	housing_names = []
	var used := {}
	if place_diner:
		_place_home_diner(home_size, used)
	if not reserve.is_empty():
		var reserved_width := int(reserve.get("w", 0))
		var reserved_height := int(reserve.get("h", 0))
		var reserved_origin := Vector2i(int(reserve.get("x", -1)), int(reserve.get("y", -1)))
		if _fits(reserved_origin, reserved_width, reserved_height, used):
			_commit("player_diner", String(reserve.get("name", "分店")), reserved_origin.x, reserved_origin.y, reserved_width, reserved_height, used, {"id": "branch_diner", "size": String(reserve.get("size", "small"))})
	var pending: Array[String] = []
	for id: String in TDTownCatalog.ZONE_IDS:
		if id == "player_diner" or id == "market":
			continue
		pending.append(id)
	pending.sort_custom(func(a: String, b: String) -> bool:
		var left := _span(catalog, a)
		var right := _span(catalog, b)
		return left.x * left.y > right.x * right.y
	)
	for id: String in pending:
		var zone := catalog_zone(catalog, id)
		var span := _span(catalog, id)
		_place(id, String(zone.get("name", id)), span.x, span.y, used, rng, {})
	for tier: Variant in MARKET_TIERS:
		var row: Dictionary = tier
		_place("market", String(row["name"]), int(row["w"]), int(row["h"]), used, rng, row)
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
			var door := _approach(x, y, 1, 1)
			house["approach_x"] = door.x
			house["approach_y"] = door.y
			plots.append(house)
	_copy_catalog(catalog)

func _copy_catalog(catalog: TDTownCatalog) -> void:
	for index in plots.size():
		var plot: Dictionary = plots[index]
		var kind := String(plot["kind"])
		if kind == "housing" or kind == "market":
			continue
		var zone := catalog_zone(catalog, kind)
		plot["pool"] = int(zone.get("pool", 0))
		plot["budget_shift"] = int(zone.get("budget_shift", 0))
		plot["foreign_scale"] = float(zone.get("foreign_scale", 1.0))
		if String(plot["id"]) == kind:
			plot["name"] = String(zone.get("name", plot["name"]))
		plots[index] = plot

func is_road(x: int, y: int) -> bool:
	return roads.has(Vector2i(x, y))

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

func can_place(x: int, y: int, width: int, height: int) -> bool:
	if width <= 0 or height <= 0 or x < 0 or y < 0 or x + width > SIZE or y + height > SIZE:
		return false
	for cy in height:
		for cx in width:
			if is_road(x + cx, y + cy):
				return false
			var plot := plot_at(x + cx, y + cy)
			if plot.is_empty():
				continue
			if String(plot.get("kind", "")) != "housing":
				return false
	return true

func covers_road(plot: Dictionary) -> bool:
	for y in int(plot.get("h", 1)):
		for x in int(plot.get("w", 1)):
			if is_road(int(plot["x"]) + x, int(plot["y"]) + y):
				return true
	return false

func arm_length(direction: Vector2i) -> int:
	var length := 0
	var cursor := Vector2i(CENTER, CENTER) + direction
	while is_road(cursor.x, cursor.y):
		length += 1
		cursor += direction
	return length

func set_enabled(id: String, enabled: bool) -> void:
	for index in plots.size():
		var plot: Dictionary = plots[index]
		var kind := String(plot["kind"])
		if kind == "player_diner" or kind == "plaza":
			continue
		if String(plot["id"]) == id or kind == id:
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

func market(id: String) -> Dictionary:
	for item: Variant in plots:
		var plot: Dictionary = item
		if String(plot["id"]) == id and String(plot["kind"]) == "market":
			return plot.duplicate(true)
	return {}

func markets() -> Array:
	var rows: Array = []
	for item: Variant in plots:
		var plot: Dictionary = item
		if String(plot["kind"]) == "market":
			rows.append(plot.duplicate(true))
	return rows

func distance_to(id: String) -> int:
	var plot := _by_id(id)
	if plot.is_empty():
		return 0
	return absi(int(plot["approach_x"]) - CENTER) + absi(int(plot["approach_y"]) - CENTER)

func attraction_bonus() -> int:
	var total := 0
	for kind: String in ["amusement", "landmark"]:
		var plot := _by_kind(kind)
		if plot.is_empty() or not bool(plot.get("enabled", true)):
			continue
		var distance := absi(int(plot["approach_x"]) - CENTER) + absi(int(plot["approach_y"]) - CENTER)
		total += TDSanRules.near_bonus(distance)
	return total

func _by_kind(kind: String) -> Dictionary:
	for item: Variant in plots:
		var plot: Dictionary = item
		if String(plot["kind"]) == kind:
			return plot
	return {}

func _by_id(id: String) -> Dictionary:
	for item: Variant in plots:
		var plot: Dictionary = item
		if String(plot["id"]) == id:
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
		"approach_x": x,
		"approach_y": y,
		"tier": 0,
		"unlocks": [],
	}

func _span(catalog: TDTownCatalog, id: String) -> Vector2i:
	var zone := catalog_zone(catalog, id)
	var width := maxi(1, int(zone.get("w", 1)))
	var height := maxi(1, int(zone.get("h", 1)))
	if id in LONG_KINDS and maxi(width, height) < 10:
		width = 10
		height = maxi(height, 4)
	return Vector2i(width, height)

func _claim(used: Dictionary, plot: Dictionary) -> void:
	for y in int(plot.get("h", 1)):
		for x in int(plot.get("w", 1)):
			used[Vector2i(int(plot["x"]) + x, int(plot["y"]) + y)] = true

func _grow_roads(rng: TDBusinessRandom) -> void:
	roads = {}
	roads[Vector2i(CENTER, CENTER)] = true
	var directions: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
	for direction: Vector2i in directions:
		var length := 8 + int(rng.unit() * 8.0)
		var cursor := Vector2i(CENTER, CENTER)
		for _step in length:
			cursor += direction
			if not _inside(cursor):
				break
			roads[cursor] = true
	var arms: Array = []
	for key: Variant in roads.keys():
		var cell: Vector2i = key
		if cell.x == CENTER or cell.y == CENTER:
			if cell != Vector2i(CENTER, CENTER):
				arms.append(cell)
	for _branch in 6:
		if arms.is_empty():
			break
		var origin: Vector2i = arms[int(rng.unit() * float(arms.size())) % arms.size()]
		var side := Vector2i(0, 1 if rng.unit() < 0.5 else -1) if origin.y == CENTER else Vector2i(1 if rng.unit() < 0.5 else -1, 0)
		var length := 3 + int(rng.unit() * 5.0)
		var cursor := origin
		for _step in length:
			cursor += side
			if not _inside(cursor):
				break
			roads[cursor] = true

func _place_home_diner(size_id: String, used: Dictionary) -> void:
	var foot := TDRestaurantSizes.footprint(size_id)
	var spot := _home_spot(foot.x, foot.y, used)
	var width := foot.x
	var height := foot.y
	if spot.x < 0:
		spot = _home_spot(foot.y, foot.x, used)
		width = foot.y
		height = foot.x
	if spot.x < 0:
		return
	_commit("player_diner", "主人公餐厅", spot.x, spot.y, width, height, used, {"id": "player_diner", "size": size_id})

func _home_spot(width: int, height: int, used: Dictionary) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_distance := 9999
	if width <= 0 or height <= 0:
		return best
	for y in range(0, SIZE - height + 1):
		for x in range(0, SIZE - width + 1):
			if not _fits(Vector2i(x, y), width, height, used):
				continue
			if not _touches_hub(x, y, width, height):
				continue
			var distance := absi(x + width / 2 - CENTER) + absi(y + height / 2 - CENTER)
			if distance < best_distance:
				best_distance = distance
				best = Vector2i(x, y)
	return best

func _touches_hub(x: int, y: int, width: int, height: int) -> bool:
	for cy in height:
		for cx in width:
			var cell := Vector2i(x + cx, y + cy)
			for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var neighbor := cell + step
				var distance := absi(neighbor.x - CENTER) + absi(neighbor.y - CENTER)
				if is_road(neighbor.x, neighbor.y) and distance <= 2:
					return true
	return false

func _place(kind: String, title: String, width: int, height: int, used: Dictionary, rng: TDBusinessRandom, extra: Dictionary) -> void:
	var roads_list := _road_cells()
	if roads_list.is_empty():
		return
	var start := int(rng.unit() * float(roads_list.size())) % roads_list.size()
	var directions: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
	var orientations: Array[Vector2i] = [Vector2i(width, height), Vector2i(height, width)]
	for step in roads_list.size():
		var road: Vector2i = roads_list[(start + step) % roads_list.size()]
		for normal: Vector2i in directions:
			for orient: Vector2i in orientations:
				if _try_place(kind, title, road, normal, orient.x, orient.y, used, extra):
					return
	for y in range(1, SIZE - height):
		for x in range(1, SIZE - width):
			if _fits(Vector2i(x, y), width, height, used):
				_commit(kind, title, x, y, width, height, used, extra)
				_connect(Vector2i(x, y), width, height)
				return

func _try_place(kind: String, title: String, road: Vector2i, normal: Vector2i, width: int, height: int, used: Dictionary, extra: Dictionary) -> bool:
	var touch := road + normal
	var slides := maxi(width, height)
	for slide in slides:
		var origin := touch
		if normal.x != 0:
			var left := touch.x if normal.x > 0 else touch.x - (width - 1)
			origin = Vector2i(left, road.y - slide)
		else:
			var top := touch.y if normal.y > 0 else touch.y - (height - 1)
			origin = Vector2i(road.x - slide, top)
		if _fits(origin, width, height, used):
			_commit(kind, title, origin.x, origin.y, width, height, used, extra)
			return true
	return false

func _fits(origin: Vector2i, width: int, height: int, used: Dictionary) -> bool:
	if origin.x < 0 or origin.y < 0 or origin.x + width > SIZE or origin.y + height > SIZE:
		return false
	for y in height:
		for x in width:
			var cell := Vector2i(origin.x + x, origin.y + y)
			if used.has(cell) or is_road(cell.x, cell.y):
				return false
	return true

func _commit(kind: String, title: String, x: int, y: int, width: int, height: int, used: Dictionary, extra: Dictionary) -> void:
	var plot := {
		"id": String(extra.get("id", kind)),
		"name": title,
		"kind": kind,
		"x": x,
		"y": y,
		"w": width,
		"h": height,
		"enabled": true,
		"walkable": false,
		"pool": 0,
		"budget_shift": 0,
		"foreign_scale": 1.0,
		"tier": int(extra.get("tier", 0)),
		"unlocks": (extra.get("unlocks", []) as Array).duplicate(),
		"size": String(extra.get("size", "")),
	}
	if extra.is_empty():
		plot["id"] = kind
	var door := _approach(x, y, width, height)
	plot["approach_x"] = door.x
	plot["approach_y"] = door.y
	_claim(used, plot)
	plots.append(plot)

func _connect(origin: Vector2i, width: int, height: int) -> void:
	var door := _approach(origin.x, origin.y, width, height)
	if door == Vector2i(CENTER, CENTER) and not _touches(origin, width, height):
		var target := Vector2i(origin.x, CENTER)
		var cursor := Vector2i(CENTER, CENTER)
		while cursor != target:
			cursor.x += 1 if target.x > cursor.x else -1
			roads[cursor] = true
		cursor = target
		var goal_y := origin.y if origin.y > 0 else origin.y + height - 1
		while cursor.y != goal_y:
			cursor.y += 1 if goal_y > cursor.y else -1
			if cursor.x >= origin.x and cursor.x < origin.x + width and cursor.y >= origin.y and cursor.y < origin.y + height:
				break
			roads[cursor] = true

func _touches(origin: Vector2i, width: int, height: int) -> bool:
	for y in height:
		for x in width:
			for direction: Vector2i in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
				var cell := origin + Vector2i(x, y) + direction
				if is_road(cell.x, cell.y):
					return true
	return false

func _approach(x: int, y: int, width: int, height: int) -> Vector2i:
	var best := Vector2i(CENTER, CENTER)
	var best_distance := 9999
	var found := false
	for yy in height:
		for xx in width:
			for direction: Vector2i in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
				var cell := Vector2i(x + xx, y + yy) + direction
				if not is_road(cell.x, cell.y):
					continue
				var distance := absi(cell.x - CENTER) + absi(cell.y - CENTER)
				if not found or distance < best_distance:
					best = cell
					best_distance = distance
					found = true
	return best

func _road_cells() -> Array:
	var cells: Array = []
	for key: Variant in roads.keys():
		cells.append(key)
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x)
	)
	return cells

func _inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < SIZE and cell.y < SIZE

func _house_name(rng: TDBusinessRandom, serial: int) -> String:
	var faces := ["青瓦", "白墙", "红门", "木窗", "窄巷", "天台"]
	return "%s住户%d" % [faces[int(rng.unit() * float(faces.size())) % faces.size()], serial]
