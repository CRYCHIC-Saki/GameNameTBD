class_name TDRecipeCatalog
extends RefCounted

var _data: Dictionary = {}
var _ingredient_ids: Dictionary = {}

func data() -> Dictionary:
	return _data.duplicate(true)

func load_file(path: String) -> TDOutcome:
	_data.clear()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return TDOutcome.new(false, "READ_FAILED", path)
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return TDOutcome.new(false, "INVALID_JSON", "%s:%d %s" % [path, parser.get_error_line(), parser.get_error_message()])
	return load_data(parser.data)

func load_data(raw: Variant) -> TDOutcome:
	_data.clear()
	_ingredient_ids.clear()
	if not raw is Dictionary or not _json_value(raw):
		return _bad("root", "finite JSON value data required")
	if raw.get("schema_version") != 2 or raw.get("scope") != "COOKING_PROTOTYPE" or raw.get("parameter_status") != "PROPOSED":
		return _bad("schema_version/scope/parameter_status", "expected 2 / COOKING_PROTOTYPE / PROPOSED")
	for field: String in ["recipe", "cut_shapes", "qte", "rules", "scoring_rules"]:
		if not raw.get(field) is Dictionary:
			return _bad(field, "object required")
	if not raw.get("ingredients") is Array or raw["ingredients"].is_empty():
		return _bad("ingredients", "nonempty array required")
	for value: Variant in raw["ingredients"]:
		if not value is Dictionary or not _identity(value.get("id")) or not _identity(value.get("name")):
			return _bad("ingredients", "id and name required")
		if _ingredient_ids.has(value["id"]):
			return TDOutcome.new(false, "DUPLICATE_ID", "ingredients." + value["id"])
		if value.get("category") not in ["food", "seasoning"] or not value.get("can_cut") is bool:
			return _bad(value["id"], "invalid category/can_cut")
		if not _range(value.get("max_amount"), 1.0, 10.0) or not _matrix(value.get("base_flavor")) or not _texture(value.get("texture")):
			return _bad(value["id"], "invalid amount, 7×4 flavor, or texture")
		if not value.get("aroma") is Dictionary:
			return _bad(value["id"], "aroma object required")
		for tag: String in value["aroma"]:
			if tag.is_empty() or not _range(value["aroma"][tag], 0.0, 100.0):
				return _bad(value["id"] + ".aroma", "invalid intensity")
		_ingredient_ids[value["id"]] = value
	var recipe: Dictionary = raw["recipe"]
	if not _identity(recipe.get("id")) or not _identity(recipe.get("name")) or not recipe.get("expects_aroma") is bool:
		return _bad("recipe", "identity and expects_aroma required")
	if not raw.get("active") is Array or raw["active"] != [recipe["id"]]:
		return TDOutcome.new(false, "MISSING_REFERENCE", "active must contain the single prototype recipe ID")
	for field: String in ["required_ingredients", "required_cut"]:
		if not recipe.get(field) is Array or recipe[field].is_empty():
			return _bad("recipe." + field, "nonempty array required")
		var seen: Dictionary = {}
		for id: Variant in recipe[field]:
			if not id is String or not _ingredient_ids.has(id):
				return TDOutcome.new(false, "MISSING_REFERENCE", "recipe." + field)
			if seen.has(id):
				return TDOutcome.new(false, "DUPLICATE_ID", "recipe." + field)
			if _ingredient_ids[id]["category"] != "food" or (field == "required_cut" and not _ingredient_ids[id]["can_cut"]):
				return _bad("recipe." + field, "requires compatible food")
			seen[id] = true
	if recipe.get("required_steps") != ["cut", "heat"]:
		return _bad("recipe.required_steps", "prototype supports cut and heat")
	if not recipe.get("expected_aroma") is Array:
		return _bad("recipe.expected_aroma", "array required")
	for tag: Variant in recipe["expected_aroma"]:
		if not _identity(tag):
			return _bad("recipe.expected_aroma", "tag strings required")
	for shape: String in ["chunk", "dice"]:
		if not raw["cut_shapes"].get(shape) is Dictionary or not _identity(raw["cut_shapes"][shape].get("name")) or not _range(raw["cut_shapes"][shape].get("fine"), 0.0, 1.0):
			return _bad("cut_shapes." + shape, "name and fine in [0,1] required")
	if raw["cut_shapes"]["chunk"]["fine"] >= raw["cut_shapes"]["dice"]["fine"]:
		return _bad("cut_shapes", "chunk must be coarser than dice")
	var checked := _qte(raw["qte"])
	if not checked.ok:
		return checked
	checked = _rules(raw["rules"], raw["scoring_rules"])
	if not checked.ok:
		return checked
	if not raw.get("customers") is Array or raw["customers"].size() < 2:
		return _bad("customers", "at least two customers required")
	var customer_ids: Dictionary = {}
	for customer: Variant in raw["customers"]:
		if not customer is Dictionary or not _identity(customer.get("id")) or not _identity(customer.get("name")) or not _identity(customer.get("description")) or not customer.get("requirements") is Array:
			return _bad("customers", "identity, description and requirements required")
		if customer_ids.has(customer["id"]):
			return TDOutcome.new(false, "DUPLICATE_ID", "customers." + customer["id"])
		customer_ids[customer["id"]] = true
		var ids: Dictionary = {}
		for requirement: Variant in customer["requirements"]:
			checked = _requirement(requirement)
			if not checked.ok:
				return checked
			if ids.has(requirement["id"]):
				return TDOutcome.new(false, "DUPLICATE_ID", "requirements." + requirement["id"])
			ids[requirement["id"]] = true
	_data = raw.duplicate(true)
	return TDOutcome.new(true, "OK", "PROPOSED prototype content", {"ingredients": _ingredient_ids.size(), "customers": customer_ids.size()})

func _qte(qte: Dictionary) -> TDOutcome:
	if not qte.get("cut") is Dictionary or not qte.get("heat") is Dictionary:
		return _bad("qte", "cut and heat objects required")
	var cut: Dictionary = qte["cut"]
	if not _range(cut.get("beats"), 1.0, 64.0) or int(cut["beats"]) != cut["beats"]:
		return _bad("qte.cut.beats", "integer in [1,64]")
	for field: String in ["interval_sec", "lead_in_sec", "perfect_sec", "good_sec"]:
		if not _range(cut.get(field), 0.001, 10.0):
			return _bad("qte.cut." + field, "positive seconds required")
	if cut["perfect_sec"] > cut["good_sec"] or cut["good_sec"] * 2.0 >= cut["interval_sec"] or not _range(cut.get("input_offset_sec"), -0.5, 0.5):
		return _bad("qte.cut", "non-overlapping windows and bounded offset required")
	if not _range(cut.get("good_quality"), 0.0, 1.0) or float(cut["lead_in_sec"]) + float(cut["input_offset_sec"]) < 0.0:
		return _bad("qte.cut", "valid quality and nonnegative calibrated first beat required")
	var heat: Dictionary = qte["heat"]
	if not _range(heat.get("duration_sec"), 0.1, 120.0) or not _range(heat.get("target_power_min"), 0.0, 1.0) or not _range(heat.get("target_power_max"), 0.0, 1.0) or heat["target_power_min"] > heat["target_power_max"]:
		return _bad("qte.heat", "valid duration and ordered power interval required")
	if not _range(heat.get("initial_power"), 0.0, 1.0):
		return _bad("qte.heat.initial_power", "power in [0,1] required")
	return TDOutcome.new(true)

func _rules(rules: Dictionary, scoring: Dictionary) -> TDOutcome:
	for field: String in ["room_temperature_c", "max_temperature_c", "degrees_per_heat_dose", "minimum_cooking_dose", "cut_release_front", "cut_release_after", "heat_front_loss_per_dose", "heat_after_gain_per_dose", "heat_tenderness_per_dose", "heat_overcook_dose", "heat_overcook_hardness", "heat_crisp_loss_per_dose", "caramel_min_temperature_c", "caramel_aroma_per_dose", "extra_step_penalty", "no_aroma_harmony_penalty", "harmony_base", "harmony_pair_bonus", "harmony_aroma_bonus", "harmony_texture_bonus"]:
		if not _range(rules.get(field), 0.0, 200.0):
			return _bad("rules." + field, "finite number in [0,200] required")
	if rules["max_temperature_c"] < rules["room_temperature_c"] or not _range(rules.get("cooling_tau_sec"), 0.01, 10000.0):
		return _bad("rules.temperature", "ordered limits and positive cooling time required")
	for field: String in ["missing_required_multiplier", "no_aroma_quality_multiplier"]:
		if not _range(rules.get(field), 0.0, 1.0):
			return _bad("rules." + field, "multiplier in [0,1]")
	if not _vector(rules.get("heat_taste_delta"), 7, -100.0, 100.0):
		return _bad("rules.heat_taste_delta", "seven finite deltas required")
	if not rules.get("heated_aroma") is Dictionary or not rules.get("quality_weights") is Dictionary:
		return _bad("rules", "heated_aroma and quality_weights required")
	for id: String in rules["heated_aroma"]:
		if not _ingredient_ids.has(id):
			return TDOutcome.new(false, "MISSING_REFERENCE", "rules.heated_aroma." + id)
		if not _range(rules["heated_aroma"][id], 0.0, 100.0):
			return _bad("rules.heated_aroma", "range [0,100]")
	for field: String in ["caramel_ingredient_id", "harmony_texture_ingredient"]:
		if not rules.get(field) is String or not _ingredient_ids.has(rules[field]):
			return TDOutcome.new(false, "MISSING_REFERENCE", "rules." + field)
	if rules.get("harmony_texture_axis") not in ["A", "B", "C"] or not _range(rules.get("harmony_texture_min"), -1.0, 1.0):
		return _bad("rules.harmony_texture", "axis and threshold required")
	for kind: String in ["cut", "heat"]:
		if not _range(rules["quality_weights"].get(kind), 0.0, 100.0):
			return _bad("rules.quality_weights", "nonnegative weights required")
	if float(rules["quality_weights"]["cut"]) + float(rules["quality_weights"]["heat"]) <= 0.0:
		return _bad("rules.quality_weights", "sum must be positive")
	if not rules.get("temperature_bands") is Array or rules["temperature_bands"].size() != 3:
		return _bad("rules.temperature_bands", "three bands required")
	var last_max: float = -INF
	for band: Variant in rules["temperature_bands"]:
		if not band is Dictionary or not _identity(band.get("id")) or not _range(band.get("max_c"), 0.0, 200.0) or not _vector(band.get("taste_factors"), 7, 0.0, 3.0) or not _vector(band.get("slot_factors"), 4, 0.0, 3.0):
			return _bad("rules.temperature_bands", "invalid band")
		if float(band["max_c"]) <= last_max:
			return _bad("rules.temperature_bands", "limits must ascend")
		last_max = float(band["max_c"])
	if last_max < float(rules["max_temperature_c"]):
		return _bad("rules.temperature_bands", "must cover maximum temperature")
	var sum: float = 0.0
	for field: String in ["quality_weight", "harmony_weight", "requirements_weight"]:
		if not _range(scoring.get(field), 0.0, 1.0):
			return _bad("scoring_rules." + field, "weight in [0,1]")
		sum += float(scoring[field])
	if absf(sum - 1.0) > 0.00001:
		return _bad("scoring_rules", "weights must sum to one")
	return TDOutcome.new(true)

func _requirement(requirement: Variant) -> TDOutcome:
	if not requirement is Dictionary or not _identity(requirement.get("id")) or not _identity(requirement.get("label")):
		return _bad("requirements", "identity and label required")
	var kind: String = str(requirement.get("kind", ""))
	if kind not in ["flavor", "temperature", "texture", "fine", "aroma"] or not _range(requirement.get("weight"), 0.0, 100.0) or not _range(requirement.get("scale", 100.0), 0.000001, 10000.0):
		return _bad("requirements", "invalid kind/weight/scale")
	if not requirement.has("min") and not requirement.has("max"):
		return _bad("requirements", "one bound is required")
	for bound: String in ["min", "max"]:
		if requirement.has(bound) and not _range(requirement[bound], -200.0, 200.0):
			return _bad("requirements." + bound, "finite bound required")
		if requirement.has(bound):
			var minimum: float = -200.0 if kind == "temperature" else (-1.0 if kind == "texture" else 0.0)
			var maximum: float = 200.0 if kind == "temperature" else (1.0 if kind in ["texture", "fine"] else 100.0)
			if not _range(requirement[bound], minimum, maximum):
				return _bad("requirements." + bound, "target outside dimension range")
	if float(requirement.get("min", -INF)) > float(requirement.get("max", INF)):
		return _bad("requirements", "min exceeds max")
	if kind == "flavor":
		if not _range(requirement.get("taste"), 0, 6) or not _range(requirement.get("slot"), 0, 3) or int(requirement["taste"]) != requirement["taste"] or int(requirement["slot"]) != requirement["slot"]:
			return _bad("requirements.flavor", "valid matrix indexes required")
	if kind == "texture" and requirement.get("axis") not in ["A", "B", "C"]:
		return _bad("requirements.texture", "axis required")
	if kind == "fine" or requirement.has("ingredient_id"):
		if not requirement.get("ingredient_id") is String or not _ingredient_ids.has(requirement["ingredient_id"]):
			return TDOutcome.new(false, "MISSING_REFERENCE", "requirements.ingredient_id")
	if kind == "aroma" and not _identity(requirement.get("tag")):
		return _bad("requirements.aroma", "tag required")
	return TDOutcome.new(true)

func _matrix(value: Variant) -> bool:
	if not value is Array or value.size() != 7:
		return false
	for row: Variant in value:
		if not _vector(row, 4, 0.0, 100.0):
			return false
	return true

func _texture(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for axis: String in ["A", "B", "C"]:
		if not _range(value.get(axis), -1.0, 1.0):
			return false
	return true

func _vector(value: Variant, count: int, minimum: float, maximum: float) -> bool:
	if not value is Array or value.size() != count:
		return false
	for number: Variant in value:
		if not _range(number, minimum, maximum):
			return false
	return true

func _range(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= minimum and value <= maximum

func _identity(value: Variant) -> bool:
	return value is String and not value.is_empty()

func _json_value(value: Variant) -> bool:
	if value == null or value is bool or value is String or value is int:
		return true
	if value is float:
		return is_finite(value)
	if value is Array:
		for child: Variant in value:
			if not _json_value(child):
				return false
		return true
	if value is Dictionary:
		for key: Variant in value:
			if not key is String or not _json_value(value[key]):
				return false
		return true
	return false

func _bad(field: String, reason: String) -> TDOutcome:
	return TDOutcome.new(false, "INVALID_CONFIG", field + ": " + reason)
