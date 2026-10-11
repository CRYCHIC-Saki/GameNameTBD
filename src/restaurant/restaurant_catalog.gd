class_name TDRestaurantCatalog
extends RefCounted

const SOURCE := "res://content/restaurant.json"
const ZONES: Array[String] = ["facade", "reception", "ordering", "dining"]
const SEAT_USES: Array[String] = ["", "waiting", "dining"]
const SURFACES: Array[String] = ["", "induction"]

var _furniture: Dictionary = {}
var _cultures: Array[String] = []
var _tiers: Array[String] = []
var _roles: Array[String] = []
var _culture_names: Dictionary = {}
var _tier_names: Dictionary = {}
var _grid: Dictionary = {}
var _default: Dictionary = {}

func load_file(path: String = SOURCE) -> TDOutcome:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return TDOutcome.new(false, "READ_FAILED", path)
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return TDOutcome.new(false, "INVALID_JSON", "%s:%d" % [path, parser.get_error_line()])
	return load_data(parser.data, path)

func load_data(raw: Variant, source: String) -> TDOutcome:
	_clear()
	if not raw is Dictionary:
		return _bad(source, "root", "必须是对象")
	var data: Dictionary = raw
	if int(data.get("schema_version", -1)) != 1:
		return _bad(source, "schema_version", "需要版本 1")
	var cultures := _string_list(data.get("cultures"), source, "cultures")
	if not cultures.ok:
		return cultures
	var tiers := _string_list(data.get("tiers"), source, "tiers")
	if not tiers.ok:
		return tiers
	var roles := _string_list(data.get("roles"), source, "roles")
	if not roles.ok:
		return roles
	var culture_names := _name_map(data.get("culture_names"), cultures.data["values"], source, "culture_names")
	if not culture_names.ok:
		return culture_names
	var tier_names := _name_map(data.get("tier_names"), tiers.data["values"], source, "tier_names")
	if not tier_names.ok:
		return tier_names
	var grid := _grid_of(data.get("grid"), source)
	if not grid.ok:
		return grid
	if not data.get("furniture") is Array or (data["furniture"] as Array).is_empty():
		return _bad(source, "furniture", "至少一件家具")
	var pending: Dictionary = {}
	for value: Variant in data["furniture"]:
		var checked := _furniture_of(value, cultures.data["values"], roles.data["values"], source)
		if not checked.ok:
			return checked
		var kind: String = checked.data["id"]
		if pending.has(kind):
			return TDOutcome.new(false, "DUPLICATE_ID", source + ": " + kind)
		pending[kind] = checked.data["entry"]
	var default_layout: Variant = data.get("default_layout")
	if not default_layout is Dictionary:
		return _bad(source, "default_layout", "必须是对象")
	_furniture = pending
	_cultures = cultures.data["values"]
	_tiers = tiers.data["values"]
	_roles = roles.data["values"]
	_culture_names = culture_names.data["values"]
	_tier_names = tier_names.data["values"]
	_grid = grid.data["grid"]
	var payload: Dictionary = (default_layout as Dictionary).duplicate(true)
	payload["columns"] = _grid["columns"]
	payload["cell_px"] = _grid["cell_px"]
	var layout := TDRestaurantLayout.import_dict(payload, self)
	if layout == null:
		var reason := TDRestaurantLayout.import_code
		_clear()
		return TDOutcome.new(false, reason, source + ": default_layout")
	var seen: Dictionary = {}
	for piece: Variant in layout.pieces():
		seen[(piece as Dictionary)["kind"]] = true
	for kind: String in pending:
		if not seen.has(kind):
			_clear()
			return _bad(source, kind, "默认布置缺少这种家具")
	_default = payload.duplicate(true)
	return TDOutcome.new(true, "OK", source, {"count": _furniture.size()})

func furniture(kind: String) -> Dictionary:
	if not _furniture.has(kind):
		return {}
	return (_furniture[kind] as Dictionary).duplicate(true)

func kinds() -> Array[String]:
	var result: Array[String] = []
	for kind: Variant in _furniture.keys():
		result.append(String(kind))
	result.sort()
	return result

func cultures() -> Array[String]:
	return _cultures.duplicate()

func tiers() -> Array[String]:
	return _tiers.duplicate()

func culture_name(culture: String) -> String:
	return String(_culture_names.get(culture, culture))

func tier_name(tier: String) -> String:
	return String(_tier_names.get(tier, tier))

func has_style(culture: String, tier: String) -> bool:
	return _cultures.has(culture) and _tiers.has(tier)

func grid_columns() -> int:
	return int(_grid.get("columns", 0))

func grid_rows() -> int:
	return int(_grid.get("rows", 0))

func cell_px() -> int:
	return int(_grid.get("cell_px", 0))

func default_layout() -> TDRestaurantLayout:
	return TDRestaurantLayout.import_dict(_default.duplicate(true), self)

func _clear() -> void:
	_furniture = {}
	_cultures = []
	_tiers = []
	_roles = []
	_culture_names = {}
	_tier_names = {}
	_grid = {}
	_default = {}

func _furniture_of(value: Variant, cultures: Array, roles: Array, source: String) -> TDOutcome:
	if not value is Dictionary:
		return _bad(source, "furniture", "必须是对象")
	var entry: Dictionary = value
	var id := String(entry.get("id", ""))
	if id.is_empty() or not _ident(id):
		return _bad(source, "furniture.id", "需要稳定英文 ID")
	var name := String(entry.get("name", ""))
	if name.is_empty():
		return _bad(source, id + ".name", "需要显示名")
	var zone := String(entry.get("zone", ""))
	if not ZONES.has(zone):
		return _bad(source, id + ".zone", "区域不在门面/接待/点餐/用餐")
	var width := int(entry.get("width", 0))
	var height := int(entry.get("height", 0))
	if width < 1 or width > 8 or height < 1 or height > 8:
		return _bad(source, id + ".size", "占地为 1 到 8 格")
	if not entry.get("blocks") is bool or not entry.get("service") is bool:
		return _bad(source, id + ".blocks/service", "必须是布尔值")
	var role := String(entry.get("role", ""))
	if role != "" and not roles.has(role):
		return _bad(source, id + ".role", "岗位未定义")
	var seat_use := String(entry.get("seat_use", ""))
	if not SEAT_USES.has(seat_use):
		return _bad(source, id + ".seat_use", "座位用途无效")
	var surface := String(entry.get("surface", ""))
	if not SURFACES.has(surface):
		return _bad(source, id + ".surface", "桌面装置无效")
	var approach: Variant = entry.get("approach")
	var needs_approach := bool(entry["blocks"]) or role != "" or seat_use != ""
	if needs_approach:
		if not approach is Array or (approach as Array).size() != 2:
			return _bad(source, id + ".approach", "需要落脚点偏移")
		if not _int_like(approach[0]) or not _int_like(approach[1]):
			return _bad(source, id + ".approach", "偏移必须是整数")
	elif approach != null:
		return _bad(source, id + ".approach", "不挡路的门面不设落脚点")
	for culture: Variant in cultures:
		if not culture is String:
			return _bad(source, "cultures", "必须是字符串")
	var stored := {
		"id": id, "name": name, "zone": zone, "width": width, "height": height,
		"blocks": entry["blocks"], "role": role, "seat_use": seat_use, "surface": surface,
		"service": entry["service"], "approach": null if approach == null else [int(approach[0]), int(approach[1])],
	}
	return TDOutcome.new(true, "OK", "", {"id": id, "entry": stored})

func _grid_of(value: Variant, source: String) -> TDOutcome:
	if not value is Dictionary:
		return _bad(source, "grid", "必须是对象")
	var grid: Dictionary = value
	var columns := int(grid.get("columns", 0))
	var rows := int(grid.get("rows", 0))
	var cell_px := int(grid.get("cell_px", 0))
	if columns < 4 or columns > 64 or rows < 4 or rows > 64 or cell_px < 16 or cell_px > 128:
		return _bad(source, "grid", "网格超出可用范围")
	return TDOutcome.new(true, "OK", "", {"grid": {"columns": columns, "rows": rows, "cell_px": cell_px}})

func _string_list(value: Variant, source: String, field: String) -> TDOutcome:
	if not value is Array or (value as Array).is_empty():
		return _bad(source, field, "不能为空")
	var result: Array[String] = []
	for item: Variant in value:
		if not item is String or (item as String).is_empty() or result.has(item):
			return _bad(source, field, "需要不重复的非空字符串")
		result.append(item)
	return TDOutcome.new(true, "OK", "", {"values": result})

func _name_map(value: Variant, keys: Array, source: String, field: String) -> TDOutcome:
	if not value is Dictionary:
		return _bad(source, field, "必须是对象")
	var names: Dictionary = {}
	for key: Variant in keys:
		var label: Variant = (value as Dictionary).get(key, "")
		if not label is String or (label as String).is_empty():
			return _bad(source, field + "." + String(key), "需要显示名")
		names[key] = label
	return TDOutcome.new(true, "OK", "", {"values": names})

func _ident(value: String) -> bool:
	if value.is_empty():
		return false
	for index in value.length():
		var code := value.unicode_at(index)
		var ok := (code >= 48 and code <= 57) or (code >= 97 and code <= 122) or code == 95
		if not ok:
			return false
	return true

func _int_like(value: Variant) -> bool:
	return value is int or (value is float and is_finite(value) and float(value) == int(value))

func _bad(source: String, field: String, expected: String) -> TDOutcome:
	return TDOutcome.new(false, "INVALID_CONTENT", "%s: %s %s" % [source, field, expected])
