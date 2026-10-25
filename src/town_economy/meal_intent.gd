class_name TDMealIntent
extends RefCounted
## Immutable one-use opportunity result; outside is a real choice, not a failed order.
## Meal timestamps use game minutes; patience_seconds is the existing kitchen clock's seconds.
var _data: Dictionary = {}
var error: TDOutcome
var id: String:
	get: return str(_data.get("opportunity_id", ""))

func _init(raw: Dictionary = {}) -> void:
	error = validate(raw)
	if error.ok: _data = raw.duplicate(true)

func snapshot() -> Dictionary:
	return _data.duplicate(true)

static func validate(raw: Variant) -> TDOutcome:
	if not raw is Dictionary or raw.get("schema_version") != 1:
		return TDOutcome.new(false, "INVALID_INTENT_VERSION")
	for field: String in ["opportunity_id", "customer_id", "town_id", "origin_id", "group_id", "store_id"]:
		if not raw.get(field) is String or raw[field].is_empty() or raw[field].length() > 160:
			return TDOutcome.new(false, "INVALID_INTENT_ID", field)
	if not TDServiceCatalog.integer(raw.get("day"), 1, 1000000) or not TDServiceCatalog.integer(raw.get("slot"), 0, 10000):
		return TDOutcome.new(false, "INVALID_INTENT_TIME")
	if not raw.get("recipe_id") is String:
		return TDOutcome.new(false, "INVALID_INTENT_RECIPE")
	if (raw.store_id == "outside") != raw.recipe_id.is_empty():
		return TDOutcome.new(false, "INVALID_INTENT_RECIPE")
	if not TDServiceCatalog.integer(raw.get("quoted_cents"), 0, 10000000):
		return TDOutcome.new(false, "INVALID_INTENT_PRICE")
	for field: String in ["travel_minutes", "expected_wait_minutes", "patience_seconds"]:
		if not TDEconomicCustomer.finite_range(raw.get(field), 0, 100000):
			return TDOutcome.new(false, "INVALID_INTENT_TIME", field)
	if not raw.get("reasons") is Array or raw.reasons.size() > 16:
		return TDOutcome.new(false, "INVALID_INTENT_REASON")
	for reason: Variant in raw.reasons:
		if not reason is String: return TDOutcome.new(false, "INVALID_INTENT_REASON")
	return TDOutcome.new(true, "VALID_INTENT")
