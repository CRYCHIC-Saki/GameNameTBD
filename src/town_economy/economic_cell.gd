class_name TDEconomicCell
extends RefCounted
## One location's economic snapshot. Same visual tile does not imply the same value.
## Quotes are cents per cell (land) and cents per cell/day (rent); not an active lease.
## Lease charges belong to parcel_id and must be booked once per parcel, never per draw call.
var _data: Dictionary = {}
var error: TDOutcome
var id: String:
	get: return str(_data.get("id", ""))
var coordinate: Vector2i:
	get: return Vector2i(int(_data.get("x", 0)), int(_data.get("y", 0)))

func _init(raw: Dictionary = {}) -> void:
	error = validate(raw)
	if error.ok: _data = raw.duplicate(true)

func snapshot() -> Dictionary:
	return _data.duplicate(true)

static func identity(town_id: String, cell: Vector2i) -> String:
	return "%s:%d:%d" % [town_id, cell.x, cell.y]

static func validate(raw: Variant) -> TDOutcome:
	if not raw is Dictionary or raw.get("schema_version") != 1:
		return TDOutcome.new(false, "INVALID_CELL_VERSION")
	for field: String in ["id", "town_id", "zone_id", "parcel_id"]:
		if not raw.get(field) is String or raw[field].is_empty() or raw[field].length() > 160:
			return TDOutcome.new(false, "INVALID_CELL_ID", field)
	for field: String in ["x", "y"]:
		if not TDServiceCatalog.integer(raw.get(field), -100000, 100000):
			return TDOutcome.new(false, "INVALID_CELL_COORDINATE")
	if raw.id != identity(raw.town_id, Vector2i(int(raw.x), int(raw.y))):
		return TDOutcome.new(false, "CELL_ID_MISMATCH")
	for field: String in ["land_value_cents", "rent_quote_cents_per_day"]:
		if not TDServiceCatalog.integer(raw.get(field), 0, 1000000000):
			return TDOutcome.new(false, "INVALID_CELL_PRICE", field)
	for field: String in ["visibility", "attractiveness"]:
		if not TDEconomicCustomer.finite_range(raw.get(field), 0, 1):
			return TDOutcome.new(false, "INVALID_CELL_FACTOR", field)
	if not raw.get("reachable") is bool or not raw.get("travel_minutes") is Dictionary:
		return TDOutcome.new(false, "INVALID_CELL_ACCESS")
	for origin: Variant in raw.travel_minutes:
		if not origin is String or origin.is_empty() or not TDEconomicCustomer.finite_range(raw.travel_minutes[origin], 0, 100000):
			return TDOutcome.new(false, "INVALID_CELL_ACCESS")
	return TDOutcome.new(true, "VALID_CELL")
