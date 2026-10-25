class_name TDEconomicCustomer
extends RefCounted
## Persistent identity/preferences. A visit's choice and deadline belong to TDMealIntent.
## Money: integer cents. Taste intensities: 0..100. Familiarity: 0..1.
const TASTES: Array[String] = ["sour", "sweet", "bitter", "spicy", "salty", "umami", "numbing"]
const PHASES: Array[String] = ["front", "main", "after", "finish"]
var _data: Dictionary = {}
var error: TDOutcome
var id: String:
	get: return str(_data.get("id", ""))
var group_id: String:
	get: return str(_data.get("group_id", ""))
var budget_cents: int:
	get: return int(_data.get("budget_cents", 0))

func _init(raw: Dictionary = {}) -> void:
	error = validate(raw)
	if error.ok: _data = raw.duplicate(true)

func snapshot() -> Dictionary:
	return _data.duplicate(true)

static func validate(raw: Variant) -> TDOutcome:
	if not raw is Dictionary or raw.get("schema_version") != 1:
		return TDOutcome.new(false, "INVALID_CUSTOMER_VERSION")
	if raw.has("household_id") and (not raw.household_id is String or raw.household_id.strip_edges().is_empty() or raw.household_id.length()>120):
		return TDOutcome.new(false, "INVALID_HOUSEHOLD_ID")
	for field: String in ["id", "group_id", "home_town_id", "origin_id"]:
		if not raw.get(field) is String or raw[field].strip_edges().is_empty() or raw[field].length() > 120:
			return TDOutcome.new(false, "INVALID_CUSTOMER_ID", field)
	for field: String in ["budget_cents", "hard_budget_cents"]:
		if not TDServiceCatalog.integer(raw.get(field), 1, 10000000):
			return TDOutcome.new(false, "INVALID_CUSTOMER_BUDGET", field)
	if raw.hard_budget_cents < raw.budget_cents:
		return TDOutcome.new(false, "INVALID_CUSTOMER_BUDGET")
	if not raw.get("taste") is Dictionary or raw.taste.size() != TASTES.size():
		return TDOutcome.new(false, "INVALID_TASTE")
	for taste: String in TASTES:
		if not raw.taste.get(taste) is Array or raw.taste[taste].size() != PHASES.size():
			return TDOutcome.new(false, "INVALID_TASTE", taste)
		for value: Variant in raw.taste[taste]:
			if not finite_range(value, 0, 100): return TDOutcome.new(false, "INVALID_TASTE", taste)
	if not raw.get("familiarity") is Dictionary:
		return TDOutcome.new(false, "INVALID_FAMILIARITY")
	for culture: Variant in raw.familiarity:
		if not culture is String or culture.is_empty() or not finite_range(raw.familiarity[culture], 0, 1):
			return TDOutcome.new(false, "INVALID_FAMILIARITY")
	# Only declared requirements are passed to the existing food scorer. Taste is choice evidence.
	if not raw.get("declared_requirements") is Array or raw.declared_requirements.size() > 32:
		return TDOutcome.new(false, "INVALID_REQUIREMENTS")
	var ids: Dictionary = {}
	for requirement: Variant in raw.declared_requirements:
		if not requirement is Dictionary: return TDOutcome.new(false, "INVALID_REQUIREMENTS")
		for field: String in ["id", "label", "kind"]:
			if not requirement.get(field) is String or requirement[field].is_empty():
				return TDOutcome.new(false, "INVALID_REQUIREMENTS", field)
		if ids.has(requirement.id): return TDOutcome.new(false, "DUPLICATE_REQUIREMENT")
		ids[requirement.id] = true
		if requirement.kind not in ["flavor", "temperature", "texture", "fine", "aroma", "ingredient", "step"] or not finite_range(requirement.get("weight"), 0, 1000):
			return TDOutcome.new(false, "INVALID_REQUIREMENTS")
		if requirement.kind == "flavor" and (not TDServiceCatalog.integer(requirement.get("taste"), 0, 6) or not TDServiceCatalog.integer(requirement.get("slot"), 0, 3)):
			return TDOutcome.new(false, "INVALID_REQUIREMENTS")
		for bound: String in ["min", "max"]:
			if requirement.has(bound) and not finite_range(requirement[bound], -1000, 1000):
				return TDOutcome.new(false, "INVALID_REQUIREMENTS")
		if requirement.has("min") and requirement.has("max") and requirement.min > requirement.max:
			return TDOutcome.new(false, "INVALID_REQUIREMENTS")
		if requirement.has("scale") and not finite_range(requirement.scale, 0.000001, 10000):
			return TDOutcome.new(false, "INVALID_REQUIREMENTS")
	return TDOutcome.new(true, "VALID_CUSTOMER")

static func finite_range(value: Variant, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= low and float(value) <= high
