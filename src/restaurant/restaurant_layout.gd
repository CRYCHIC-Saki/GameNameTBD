class_name TDRestaurantLayout
extends RefCounted

static var import_code: String = ""

const ZONE_OF := {"#": "facade", "+": "movement", ".": "movement", "R": "reception", "O": "ordering", "D": "dining"}
const CHAR_OF := {"facade": "#", "movement": ".", "reception": "R", "ordering": "O", "dining": "D"}

var culture: String = "plain"
var tier: String = "low"
var columns: int = 0
var rows: int = 0
var cell_px: int = 64
var _catalog: TDRestaurantCatalog
var _zones: PackedStringArray = PackedStringArray()
var _entrances: Array[Vector2i] = []
var _pieces: Array = []
var _staff: Dictionary = {}
var _serial: int = 100

static var floor_error: String = ""

static func make_sized(catalog: TDRestaurantCatalog, columns_value: int, rows_value: int, culture_id: String = "chinese") -> TDRestaurantLayout:
	floor_error = ""
	if catalog == null or columns_value < 8 or rows_value < 8:
		floor_error = "店内至少要 8×8，才放得下迎宾台和收银台"
		return null
	var style := culture_id
	if not catalog.has_style(style, "low"):
		style = "chinese"
	var layout := TDRestaurantLayout.new()
	layout._catalog = catalog
	layout.columns = columns_value
	layout.rows = rows_value
	layout.cell_px = catalog.cell_px()
	layout.culture = style
	layout.tier = "low"
	layout._staff = {"greeter": false, "cashier": false}
	layout._zones = PackedStringArray()
	layout._zones.resize(columns_value * rows_value)
	layout._entrances = []
	layout._pieces = []
	for y in rows_value:
		for x in columns_value:
			var zone := "movement"
			var entrance_cell := false
			if y == 0 or y == rows_value - 1 or x == 0 or x == columns_value - 1:
				zone = "facade"
				if x == 1 and y == 0:
					zone = "movement"
					entrance_cell = true
			elif y >= 2 and y <= 3 and x >= 2 and x <= 3:
				zone = "reception"
			elif y == 2 and x >= 5 and x <= 6:
				zone = "ordering"
			elif y == 3 and x == 5:
				zone = "ordering"
			elif y == 5 and x >= 2 and x <= 3:
				zone = "dining"
			elif y == 5 and x >= 8 and x < columns_value - 1 and x % 2 == 0:
				zone = "dining"
			layout._write_cell(x, y, zone, entrance_cell)
	var style_id := "%s_low" % style
	var welcome := layout._commit(-1, layout._make_piece("welcome", "welcome_desk", 2, 2, 0, style_id))
	if not welcome.ok:
		floor_error = welcome.message
		return null
	var cashier := layout._commit(-1, layout._make_piece("cashier", "cashier", 5, 2, 0, style_id))
	if not cashier.ok:
		floor_error = cashier.message
		return null
	var kiosk := layout._commit(-1, layout._make_piece("kiosk", "kiosk", 5, 3, 0, style_id))
	if not kiosk.ok:
		floor_error = kiosk.message
		return null
	var stool := layout._commit(-1, layout._make_piece("stool", "stool", 2, 5, 0, style_id))
	if not stool.ok:
		floor_error = stool.message
		return null
	var seat_serial := 1
	for x in range(8, columns_value - 1):
		if x % 2 != 0 or layout.cell_zone(x, 5) != "dining":
			continue
		seat_serial += 1
		layout._commit(-1, layout._make_piece("stool-%d" % seat_serial, "stool", x, 5, 0, style_id))
	return layout

static func import_dict(data: Dictionary, catalog: TDRestaurantCatalog) -> TDRestaurantLayout:
	import_code = "OK"
	var layout := TDRestaurantLayout.new()
	var result := layout._load(data, catalog)
	if not result.ok:
		import_code = result.code
		return null
	return layout

func furnish_player_home() -> TDOutcome:
	# Only for a new profile. Loading an existing layout never calls this method.
	for item: Dictionary in pieces():
		if item.seat_use=="dining" or item.kind=="kiosk": remove_piece(item.id)
	for y: int in rows:
		for x: int in columns:
			if cell_zone(x,y)=="dining": paint(x,y,".")
	for point: Vector2i in [Vector2i(3,5),Vector2i(8,5),Vector2i(3,10),Vector2i(8,10)]:
		if point.x+2>=columns-1 or point.y+2>=rows-2: continue
		for y: int in range(point.y,point.y+2):
			for x: int in range(point.x,point.x+2):
				var painted:=paint(x,y,"D")
				if not painted.ok: return painted
		var placed:=place("dining_table",point.x,point.y,0,"chinese_low")
		if not placed.ok: return placed
	return TDOutcome.new(true,"FURNISHED")

func pieces() -> Array:
	var copy: Array = []
	for piece: Variant in _pieces:
		copy.append((piece as Dictionary).duplicate(true))
	return copy

func piece(id: String) -> Dictionary:
	var index := _index_of(id)
	if index < 0:
		return {}
	return (_pieces[index] as Dictionary).duplicate(true)

func piece_by_kind(kind: String) -> Dictionary:
	for item: Variant in _pieces:
		var found: Dictionary = item
		if String(found["kind"]) == kind:
			return found.duplicate(true)
	return {}

func cell_zone(x: int, y: int) -> String:
	if not _inside(x, y):
		return ""
	return _zones[y * columns + x]

func is_walkable(x: int, y: int) -> bool:
	# Floor zoning controls placement; only walls and occupied furniture block feet.
	if cell_zone(x,y) not in ["movement","reception","ordering","dining"]:
		return false
	for item: Dictionary in _pieces:
		if bool(item.blocks) and _contains(item,x,y): return false
	return true

func is_entrance(x: int, y: int) -> bool:
	return _entrances.has(Vector2i(x, y))

func entrance() -> Vector2i:
	return _entrances[0] if not _entrances.is_empty() else Vector2i(-1, -1)

func staff_hired(role: String) -> bool:
	return bool(_staff.get(role, false))

func cell_center(cell: Vector2i) -> Vector2:
	return Vector2((cell.x + 0.5) * cell_px, (cell.y + 0.5) * cell_px)

func sit_cell(piece: Dictionary) -> Vector2i:
	var approach := Vector2i(int(piece["approach_x"]), int(piece["approach_y"]))
	var best := Vector2i(int(piece["x"]), int(piece["y"]))
	var best_distance := 1 << 30
	for dy in int(piece["h"]):
		for dx in int(piece["w"]):
			var cell := Vector2i(int(piece["x"]) + dx, int(piece["y"]) + dy)
			var distance := absi(cell.x - approach.x) + absi(cell.y - approach.y)
			var nearer := distance < best_distance
			var tie := distance == best_distance and (cell.x < best.x or (cell.x == best.x and cell.y < best.y))
			if nearer or tie:
				best = cell
				best_distance = distance
	return best

func place(kind: String, x: int, y: int, rotation: int, style_id: String = "") -> TDOutcome:
	var id := "piece-%d" % _serial
	_serial += 1
	var result := _commit(-1, _make_piece(id, kind, x, y, rotation, style_id if style_id != "" else _venue_style()))
	if not result.ok:
		_serial -= 1
	return result

func remove_piece(id: String) -> TDOutcome:
	var index := _index_of(id)
	if index < 0:
		return _fail("MISSING", "没有这件家具")
	_pieces.remove_at(index)
	return TDOutcome.new(true, "REMOVED", "已拆除")

func move_piece(id: String, x: int, y: int) -> TDOutcome:
	var current := piece(id)
	if current.is_empty():
		return _fail("MISSING", "没有这件家具")
	return _commit(_index_of(id), _make_piece(id, String(current["kind"]), x, y, int(current["rotation"]), String(current["style_id"])))

func rotate_piece(id: String) -> TDOutcome:
	var current := piece(id)
	if current.is_empty():
		return _fail("MISSING", "没有这件家具")
	var rotation := (int(current["rotation"]) + 90) % 360
	return _commit(_index_of(id), _make_piece(id, String(current["kind"]), int(current["x"]), int(current["y"]), rotation, String(current["style_id"])))

func restyle_piece(id: String, next_culture: String, next_tier: String) -> TDOutcome:
	if _catalog == null or not _catalog.has_style(next_culture, next_tier):
		return _fail("BAD_STYLE", "没有这种装修风格")
	var index := _index_of(id)
	if index < 0:
		return _fail("MISSING", "没有这件家具")
	(_pieces[index] as Dictionary)["style_id"] = "%s_%s" % [next_culture, next_tier]
	return TDOutcome.new(true, "RESTYLED", "这件家具已换风格")

func apply_venue_style(next_culture: String, next_tier: String) -> TDOutcome:
	if _catalog == null or not _catalog.has_style(next_culture, next_tier):
		return _fail("BAD_STYLE", "没有这种装修风格")
	culture = next_culture
	tier = next_tier
	var style := _venue_style()
	for item: Variant in _pieces:
		(item as Dictionary)["style_id"] = style
	return TDOutcome.new(true, "RESTYLED", "全店已换成%s%s" % [_catalog.culture_name(culture), _catalog.tier_name(tier)])

func set_staff(role: String, hired: bool) -> TDOutcome:
	if not _staff.has(role):
		return _fail("INVALID_ROLE", "没有这个岗位")
	_staff[role] = hired
	var title := "迎宾" if role == "greeter" else "收银"
	return TDOutcome.new(true, "STAFF", title + ("已到岗" if hired else "已离岗"))

func paint(x: int, y: int, symbol: String) -> TDOutcome:
	if not _inside(x, y):
		return _fail("OUT_OF_BOUNDS", "超出餐厅边界")
	if _occupant(x, y) != "":
		return _fail("OCCUPIED", "先移开这格上的家具")
	if not ZONE_OF.has(symbol):
		return _fail("BAD_ZONE", "不能刷成这个区域")
	var was_entrance := is_entrance(x, y)
	if was_entrance and symbol != "+" and _entrances.size() <= 1:
		return _fail("LAST_ENTRANCE", "至少保留一个门口")
	var previous_zone := cell_zone(x, y)
	_write_cell(x, y, String(ZONE_OF[symbol]), symbol == "+")
	if not _fixtures_valid():
		_write_cell(x, y, previous_zone, was_entrance)
		return _fail("PAINT_BREAKS_FIXTURE", "这样改会让已有家具离开它的区域或失去落脚点")
	return TDOutcome.new(true, "PAINTED", "区域已修改")

func interact_code(id: String) -> String:
	var current := piece(id)
	if current.is_empty():
		return "MISSING"
	var role := String(current["role"])
	if role == "greeter" and not staff_hired("greeter"):
		return "NEED_GREETER"
	if role == "cashier" and not staff_hired("cashier"):
		return "NEED_CASHIER"
	return "READY"

func path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if not is_walkable(from.x, from.y) or not is_walkable(to.x, to.y):
		return empty
	if from == to:
		return [from]
	var queue: Array[Vector2i] = [from]
	var came: Dictionary = {}
	var seen: Dictionary = {_key(from): true}
	var found := false
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		if current == to:
			found = true
			break
		for step: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			var next := current + step
			var key := _key(next)
			if seen.has(key) or not is_walkable(next.x, next.y):
				continue
			seen[key] = true
			came[key] = current
			queue.append(next)
	if not found:
		return empty
	var chain: Array[Vector2i] = [to]
	var cursor := to
	while cursor != from:
		cursor = came[_key(cursor)]
		chain.append(cursor)
	chain.reverse()
	return chain

func route_guest(occupied_seat_ids: Array) -> Dictionary:
	var denied := {"ok": false, "code": "", "message": "", "path": [], "seat_id": "", "desk_id": ""}
	if not staff_hired("greeter"):
		denied["code"] = "NEED_GREETER"
		denied["message"] = "迎宾台还没有迎宾，客人停在门口"
		return denied
	var desks := _pieces_of("welcome_desk")
	if desks.is_empty():
		denied["code"] = "NO_DESK"
		denied["message"] = "没有迎宾台"
		return denied
	var desk: Dictionary = desks[0]
	var start := entrance()
	var desk_cell := Vector2i(int(desk["approach_x"]), int(desk["approach_y"]))
	var to_desk := path(start, desk_cell)
	if to_desk.is_empty():
		denied["code"] = "UNREACHABLE"
		denied["message"] = "过道被堵住，客人走不到迎宾台"
		return denied
	var best_path: Array[Vector2i] = []
	var best_id := ""
	for seat: Variant in _pieces:
		var item: Dictionary = seat
		if String(item["seat_use"]) != "dining" or occupied_seat_ids.has(item["id"]):
			continue
		var to_seat := path(desk_cell, Vector2i(int(item["approach_x"]), int(item["approach_y"])))
		if to_seat.is_empty():
			continue
		if best_id == "" or to_seat.size() < best_path.size() or (to_seat.size() == best_path.size() and String(item["id"]) < best_id):
			best_path = to_seat
			best_id = String(item["id"])
	if best_id == "":
		denied["code"] = "NO_SEAT"
		denied["message"] = "没有能走到的空位"
		denied["path"] = to_desk
		denied["desk_id"] = desk["id"]
		return denied
	var full := _join_paths(to_desk, best_path)
	return {
		"ok": true, "code": "SEATED", "message": "客人正在入座",
		"path": full, "seat_id": best_id, "desk_id": desk["id"],
	}

func to_dict() -> Dictionary:
	var lines: Array[String] = []
	for y in rows:
		var line := ""
		for x in columns:
			line += "+" if is_entrance(x, y) else String(CHAR_OF[cell_zone(x, y)])
		lines.append(line)
	var exported: Array = []
	for item: Variant in _pieces:
		var current: Dictionary = item
		exported.append({
			"id": current["id"], "kind": current["kind"], "x": current["x"], "y": current["y"],
			"rotation": current["rotation"], "style_id": current["style_id"],
		})
	return {
		"schema_version": 1, "columns": columns, "cell_px": cell_px,
		"culture": culture, "tier": tier, "staff": _staff.duplicate(true),
		"rows": lines, "pieces": exported,
	}

func _load(data: Dictionary, catalog: TDRestaurantCatalog) -> TDOutcome:
	_catalog = catalog
	if not TDServiceCatalog.integer(data.get("columns"), 8, 64) or not data.get("rows") is Array or data.rows.size() < 8 or data.rows.size() > 64:
		return _fail("BAD_GRID", "餐厅网格范围为8至64格")
	columns = int(data.columns)
	rows = data.rows.size()
	cell_px = catalog.cell_px()
	culture = String(data.get("culture", ""))
	tier = String(data.get("tier", ""))
	if not catalog.has_style(culture, tier):
		return _fail("BAD_STYLE", "默认风格不存在")
	var staff: Variant = data.get("staff")
	if not staff is Dictionary:
		return _fail("INVALID_ROLE", "岗位记录无效")
	_staff = {}
	for role: String in ["greeter", "cashier"]:
		if not (staff as Dictionary).get(role) is bool:
			return _fail("INVALID_ROLE", "缺少迎宾或收银到岗记录")
		_staff[role] = (staff as Dictionary)[role]
	var lines: Variant = data.get("rows")
	if not lines is Array or (lines as Array).size() != rows:
		return _fail("BAD_GRID", "区域行数不正确")
	_zones = PackedStringArray()
	_zones.resize(columns * rows)
	_entrances = []
	for y in rows:
		var line: Variant = (lines as Array)[y]
		if not line is String or (line as String).length() != columns:
			return _fail("BAD_GRID", "某一行的区域长度不正确")
		for x in columns:
			var symbol := (line as String).substr(x, 1)
			if not ZONE_OF.has(symbol):
				return _fail("BAD_ZONE", "区域符号无效")
			_write_cell(x, y, String(ZONE_OF[symbol]), symbol == "+")
	if _entrances.is_empty():
		return _fail("LAST_ENTRANCE", "至少要有一个门口")
	if not data.get("pieces") is Array:
		return _fail("INVALID_CONTENT", "家具列表无效")
	_pieces = []
	for value: Variant in data["pieces"]:
		if not value is Dictionary:
			return _fail("INVALID_CONTENT", "家具必须是对象")
		var item: Dictionary = value
		var id := String(item.get("id", ""))
		if id.is_empty() or _index_of(id) >= 0:
			return _fail("DUPLICATE_ID", "家具 ID 重复或为空")
		var built := _make_piece(id, String(item.get("kind", "")), int(item.get("x", -1)), int(item.get("y", -1)), int(item.get("rotation", -1)), String(item.get("style_id", "")))
		var committed := _commit(-1, built)
		if not committed.ok:
			return committed
		if id.begins_with("piece-") and id.trim_prefix("piece-").is_valid_int():
			_serial = maxi(_serial, int(id.trim_prefix("piece-")) + 1)
	return TDOutcome.new(true, "OK")

func _commit(index: int, built: Dictionary) -> TDOutcome:
	if built.is_empty():
		return _fail("UNKNOWN_KIND", "没有这种家具")
	var previous: Variant = null
	if index >= 0:
		previous = _pieces[index]
		_pieces.remove_at(index)
	var checked := _validate_piece(built)
	if not checked.ok:
		if previous != null:
			_pieces.insert(index, previous)
		return checked
	if checked.ok:
		checked = TDOutcome.new(true, "PLACED", "已放置", {"id": String(built["id"])})
	if index >= 0:
		_pieces.insert(index, built)
	else:
		_pieces.append(built)
	return checked

func _make_piece(id: String, kind: String, x: int, y: int, rotation: int, style_id: String) -> Dictionary:
	if _catalog == null:
		return {}
	var definition := _catalog.furniture(kind)
	if definition.is_empty():
		return {}
	if rotation != 0 and rotation != 90 and rotation != 180 and rotation != 270:
		return {}
	var size := _rotated_size(int(definition["width"]), int(definition["height"]), rotation)
	var approach := Vector2i(-999, -999)
	var has_approach := definition["approach"] != null
	if has_approach:
		var offset := _rotated_approach(int(definition["approach"][0]), int(definition["approach"][1]), int(definition["width"]), int(definition["height"]), rotation)
		approach = Vector2i(x, y) + offset
	return {
		"id": id, "kind": kind, "name": definition["name"], "x": x, "y": y,
		"w": size.x, "h": size.y, "rotation": rotation, "style_id": style_id,
		"zone": definition["zone"], "blocks": definition["blocks"], "role": definition["role"],
		"seat_use": definition["seat_use"], "surface": definition["surface"], "service": definition["service"],
		"has_approach": has_approach, "approach_x": approach.x, "approach_y": approach.y,
	}

func _validate_piece(built: Dictionary) -> TDOutcome:
	if built.is_empty():
		return _fail("UNKNOWN_KIND", "没有这种家具")
	var parts := String(built["style_id"]).split("_")
	if parts.size() != 2 or _catalog == null or not _catalog.has_style(parts[0], parts[1]):
		return _fail("BAD_STYLE", "家具风格无效")
	for y in int(built["h"]):
		for x in int(built["w"]):
			var cell_x := int(built["x"]) + x
			var cell_y := int(built["y"]) + y
			if not _inside(cell_x, cell_y):
				return _fail("OUT_OF_BOUNDS", "家具超出餐厅边界")
			if cell_zone(cell_x, cell_y) != String(built["zone"]):
				return _fail("WRONG_ZONE", "%s只能放在对应区域" % String(built["name"]))
			if _occupant(cell_x, cell_y, String(built["id"])) != "":
				return _fail("OVERLAP", "和已有家具重叠")
	if bool(built["has_approach"]):
		var ax := int(built["approach_x"])
		var ay := int(built["approach_y"])
		# Service approaches still require a dedicated aisle, preserving saved layouts.
		if cell_zone(ax,ay)!="movement":
			return _fail("BAD_APPROACH", "%s旁边没有顾客能走的格子" % String(built["name"]))
		if _contains(built, ax, ay):
			return _fail("BAD_APPROACH", "落脚点不能压在家具上")
	return TDOutcome.new(true, "PLACED", "已放置")

func _fixtures_valid() -> bool:
	for item: Variant in _pieces:
		if not _validate_piece(item).ok:
			return false
	return true

func _write_cell(x: int, y: int, zone: String, entrance_cell: bool) -> void:
	_zones[y * columns + x] = zone
	var cell := Vector2i(x, y)
	var existing := _entrances.find(cell)
	if entrance_cell and existing < 0:
		_entrances.append(cell)
		_entrances.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	elif not entrance_cell and existing >= 0:
		_entrances.remove_at(existing)

func _rotated_size(width: int, height: int, rotation: int) -> Vector2i:
	if rotation == 90 or rotation == 270:
		return Vector2i(height, width)
	return Vector2i(width, height)

func _rotated_approach(ax: int, ay: int, width: int, height: int, rotation: int) -> Vector2i:
	match rotation:
		90:
			return Vector2i(ay, width - 1 - ax)
		180:
			return Vector2i(width - 1 - ax, height - 1 - ay)
		270:
			return Vector2i(height - 1 - ay, ax)
		_:
			return Vector2i(ax, ay)

func _pieces_of(kind: String) -> Array:
	var found: Array = []
	for item: Variant in _pieces:
		if String((item as Dictionary)["kind"]) == kind:
			found.append(item)
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["id"]) < String(b["id"]))
	return found

func _join_paths(first: Array[Vector2i], second: Array[Vector2i]) -> Array[Vector2i]:
	var full: Array[Vector2i] = []
	full.append_array(first)
	var start := 1 if not full.is_empty() and not second.is_empty() and full[-1] == second[0] else 0
	for index in range(start, second.size()):
		full.append(second[index])
	return full

func _occupant(x: int, y: int, ignore_id: String = "") -> String:
	for item: Variant in _pieces:
		var found: Dictionary = item
		if String(found["id"]) == ignore_id:
			continue
		if _contains(found, x, y):
			return String(found["id"])
	return ""

func _contains(item: Dictionary, x: int, y: int) -> bool:
	return x >= int(item["x"]) and y >= int(item["y"]) and x < int(item["x"]) + int(item["w"]) and y < int(item["y"]) + int(item["h"])

func _index_of(id: String) -> int:
	for index in _pieces.size():
		if String((_pieces[index] as Dictionary)["id"]) == id:
			return index
	return -1

func _inside(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < columns and y < rows

func _venue_style() -> String:
	return "%s_%s" % [culture, tier]

func _key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]

func _fail(code: String, message: String) -> TDOutcome:
	return TDOutcome.new(false, code, message)
