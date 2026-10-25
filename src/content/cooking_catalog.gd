class_name TDCookingCatalog
extends RefCounted

var _data: Dictionary = {}
var _source: String = "<memory>"
const OPERATIONS: Array[String] = ["cut", "preheat", "stir", "heat", "boil", "season", "starch", "ferment", "plate", "steam"]

func load_file(path: String) -> TDOutcome:
	_source = path
	if not FileAccess.file_exists(path):
		return _bad("$", "file not found", "NOT_FOUND")
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK:
		return _bad("$", "invalid JSON line %d" % parser.get_error_line(), "INVALID_JSON")
	return load_data(parser.data, path)

func load_data(raw: Variant, source: String = "<memory>") -> TDOutcome:
	_data = {}
	_source = source
	if not raw is Dictionary or not _json_value(raw):
		return _bad("$", "finite JSON object required")
	if raw.has("pc_operations") and not raw.pc_operations is Dictionary: return _bad("pc_operations","object required")
	if raw.get("schema_version") != 3 or raw.get("scope") != "COOKING_SYSTEM" or raw.get("parameter_status") != "PROPOSED":
		return _bad("schema_version", "expected schema 3 COOKING_SYSTEM")
	for field: String in ["active", "operations", "qtes", "rules", "scoring_rules", "cut_shapes"]:
		if not raw.get(field) is Dictionary:
			return _bad(field, "object required")
	var indexed: Dictionary = {}
	for field: String in ["ingredients", "recipes", "reactions", "variants", "customers"]:
		if not raw.get(field) is Array:
			return _bad(field, "array required")
		indexed[field] = {}
		for entry: Variant in raw[field]:
			if not entry is Dictionary or not _id(entry.get("id")):
				return _bad(field, "entry identity required")
			if indexed[field].has(entry.id):
				return _bad(field + "." + entry.id, "duplicate ID", "DUPLICATE_ID")
			indexed[field][entry.id] = entry
	for field: String in ["ingredients", "recipes"]:
		if not raw.active.get(field) is Array or raw.active[field].is_empty():
			return _bad("active." + field, "nonempty ID list required")
		var seen: Dictionary = {}
		for id: Variant in raw.active[field]:
			if not id is String or not indexed[field].has(id):
				return _bad("active." + field, "missing reference", "MISSING_REFERENCE")
			if seen.has(id):
				return _bad("active." + field, "duplicate reference", "DUPLICATE_ID")
			seen[id] = true
	for id: String in raw.active.ingredients:
		var item: Dictionary = indexed.ingredients[id]
		var path: String = "ingredients." + id
		for key: String in ["name", "category", "subcategory", "scope"]:
			if not _id(item.get(key)):
				return _bad(path + "." + key, "nonempty string required")
		if not _vector(item.get("base_tastes"), 7, 0, 100) or not _vector(item.get("slot_profile"), 4, 0, 2):
			return _bad(path + ".base_tastes/slot_profile", "seven tastes and four slots required")
		if not _texture(item.get("texture")) or not _aroma(item.get("aroma")):
			return _bad(path + ".texture/aroma", "invalid attribute ranges")
		if not _range(item.get("quality"), 0, 1) or not _range(item.get("max_amount"), .001, 1000) or not _range(item.get("temperature_c"), -100, 1000):
			return _bad(path, "quality, amount or temperature range")
		if not _strings(item.get("special")) or not _strings(item.get("region")) or not item.get("available") is bool:
			return _bad(path, "special, region and availability required")
		for tag: String in item.special:
			if tag not in ["cuttable", "protein", "sugar", "meat", "nuts", "fat", "starch", "culture"]:
				return _bad(path + ".special", "unsupported special property")
	for shape: String in ["slice", "chunk", "strip", "dice"]:
		if not raw.cut_shapes.get(shape) is Dictionary or not _range(raw.cut_shapes[shape].get("fine"), 0, 1):
			return _bad("cut_shapes." + shape, "fine required in [0,1]")
	for id: String in raw.operations:
		var op: Variant = raw.operations[id]
		if id not in OPERATIONS or not op is Dictionary or not _id(op.get("name")) or op.get("id") != id or op.get("target") not in ["instance", "batch", "dish"] or not _range(op.get("quality_weight"), 0, 100):
			return _bad("operations." + id, "unsupported operation or target")
		if not raw.qtes.has(op.get("qte", "")):
			return _bad("operations." + id + ".qte", "missing QTE", "MISSING_REFERENCE")
	for id: String in raw.qtes:
		var result: TDOutcome = _check_qte(raw.qtes[id], "qtes." + id)
		if not result.ok:
			return result
	for id: String in raw.active.recipes:
		var recipe: Dictionary = indexed.recipes[id]
		var path: String = "recipes." + id
		if not _id(recipe.get("name")) or recipe.get("scope") not in ["PROTOTYPE", "TEST_ONLY"] or not _range(recipe.get("version"), 1, 100000) or int(recipe.version) != recipe.version or not recipe.get("is_custom") is bool or not recipe.get("expects_aroma") is bool:
			return _bad(path, "version and identity required")
		if not recipe.get("required_ingredients") is Array:
			return _bad(path + ".required_ingredients", "array required")
		var required_seen: Dictionary = {}
		for requirement: Variant in recipe.required_ingredients:
			if not requirement is Dictionary or requirement.get("id") not in raw.active.ingredients:
				return _bad(path + ".required_ingredients", "missing active ingredient", "MISSING_REFERENCE")
			if not _range(requirement.get("min_amount"), .001, 1000) or not _range(requirement.get("min_fine"), 0, 1) or not _range(requirement.get("max_fine"), float(requirement.min_fine), 1):
				return _bad(path + ".required_ingredients", "invalid amount/fine bounds")
			if required_seen.has(requirement.id):
				return _bad(path + ".required_ingredients", "duplicate ingredient requirement", "DUPLICATE_ID")
			required_seen[requirement.id] = true
			if requirement.has("min_heat_dose") and not _range(requirement.min_heat_dose, 0, 3600):
				return _bad(path + ".required_ingredients.min_heat_dose", "nonnegative dose required")
		for key: String in ["required_steps", "recommended_steps"]:
			if not _strings(recipe.get(key)):
				return _bad(path + "." + key, "operation list required")
			for op: String in recipe[key]:
				if not raw.operations.has(op):
					return _bad(path + "." + key, "unknown operation", "MISSING_REFERENCE")
		if recipe.has("preparation_sheets"):
			if not recipe.preparation_sheets is Dictionary: return _bad(path,"preparation sheet map required")
			for ingredient_id: String in recipe.preparation_sheets:
				var sheet_id: Variant = recipe.preparation_sheets[ingredient_id]
				var charts: Variant = raw.get("pc_operations",{}).get("document_sheets",{})
				if not charts is Dictionary: return _bad(path,"preparation sheet collection required")
				if ingredient_id not in raw.active.ingredients or not sheet_id is String or not charts.has(sheet_id): return _bad(path,"unknown preparation ingredient/sheet","MISSING_REFERENCE")
				if not charts[sheet_id].get("groups") is Dictionary: return _bad(path,"invalid preparation sheet")
				for group: Dictionary in charts[sheet_id].groups.values():
					if group.get("operation") != "cut": return _bad(path,"preparation must contain cut operations")
		for key: String in ["allowed_ingredients", "variant_ids", "expected_aroma"]:
			if not _strings(recipe.get(key)):
				return _bad(path + "." + key, "string list required")
		for ingredient: String in recipe.allowed_ingredients:
			if ingredient not in raw.active.ingredients:
				return _bad(path + ".allowed_ingredients", "missing reference", "MISSING_REFERENCE")
		for variant: String in recipe.variant_ids:
			if not indexed.variants.has(variant):
				return _bad(path + ".variant_ids", "missing reference", "MISSING_REFERENCE")
		if not _vector(recipe.get("ideal_temperature"), 2, -100, 1000) or recipe.ideal_temperature[0] > recipe.ideal_temperature[1]:
			return _bad(path + ".ideal_temperature", "ordered range required")
		if not _cost(recipe.get("san_cost")):
			return _bad(path + ".san_cost", "explicit deliver event and amount required")
		if not recipe.get("ideal_texture") is Dictionary or not recipe.get("ideal_flavor") is Array:
			return _bad(path, "ideal texture/flavor constraints required")
		for axis: String in recipe.ideal_texture:
			if axis not in ["A", "B", "C"] or not _vector(recipe.ideal_texture[axis], 2, -1, 1) or recipe.ideal_texture[axis][0] > recipe.ideal_texture[axis][1]:
				return _bad(path + ".ideal_texture", "invalid axis/range")
		for target: Variant in recipe.ideal_flavor:
			if not target is Dictionary or not _range(target.get("taste"), 0, 6) or not _range(target.get("slot"), 0, 3) or int(target.taste) != target.taste or int(target.slot) != target.slot or not _range(target.get("min"), 0, 100) or not _range(target.get("max"), float(target.min), 100):
				return _bad(path + ".ideal_flavor", "invalid taste/slot/range")
		if recipe.has("required_regions") and not _strings(recipe.required_regions):
			return _bad(path + ".required_regions", "region string list required")
	for reaction: Dictionary in raw.reactions:
		if not _id(reaction.get("name")) or reaction.get("trigger") not in ["heat", "boil", "starch", "ferment", "exposure"] or not _strings(reaction.get("requires_any")) or not _strings(reaction.get("requires_all")):
			return _bad("reactions." + reaction.id, "invalid trigger/requirements")
		if not _vector(reaction.get("flavor_delta"), 7, -100, 100) or not _aroma(reaction.get("aroma")) or not _range(reaction.get("min_duration"), 0, 3600) or not _range(reaction.get("min_temperature"), -100, 1000) or not _range(reaction.get("harmony_delta"), -100, 100):
			return _bad("reactions." + reaction.id, "invalid effect or threshold")
		if reaction.has("texture_delta"):
			if not reaction.texture_delta is Dictionary:
				return _bad("reactions." + reaction.id + ".texture_delta", "axis map required")
			for axis: String in reaction.texture_delta:
				if axis not in ["A", "B", "C"] or not _range(reaction.texture_delta[axis], -2, 2):
					return _bad("reactions." + reaction.id + ".texture_delta", "unsupported axis or nonfinite delta")
		for tag: String in reaction.requires_any + reaction.requires_all:
			if tag not in ["cuttable", "protein", "sugar", "meat", "nuts", "fat", "starch", "culture"]:
				return _bad("reactions." + reaction.id, "unknown condition tag")
	for variant: Dictionary in raw.variants:
		if variant.get("scope") != "TEST_ONLY" or not _range(variant.get("probability"), 0, 1) or not _vector(variant.get("flavor_delta"), 7, -100, 100) or not _aroma(variant.get("aroma")) or not _cost(variant.get("san_cost")):
			return _bad("variants." + variant.id, "invalid test variant")
	for id: String in raw.active.recipes:
		var probability: float = 0.0
		var seen_candidates: Dictionary = {}
		for variant_id: String in indexed.recipes[id].variant_ids:
			if seen_candidates.has(variant_id):
				return _bad("recipes." + id + ".variant_ids", "duplicate candidate", "DUPLICATE_ID")
			seen_candidates[variant_id] = true
			probability += float(indexed.variants[variant_id].probability)
		if probability > 1.0 + .000001:
			return _bad("recipes." + id + ".variant_ids", "candidate probabilities must sum to at most one")
	for customer: Dictionary in raw.customers:
		if not customer.get("requirements") is Array:
			return _bad("customers." + customer.id, "requirements array required")
		var seen_requirements: Dictionary = {}
		for requirement: Variant in customer.requirements:
			if not requirement is Dictionary or not _id(requirement.get("id")) or requirement.get("kind") not in ["flavor", "temperature", "texture", "fine", "aroma", "ingredient", "step"] or not _range(requirement.get("weight"), 0, 1000):
				return _bad("customers." + customer.id, "invalid declared requirement")
			if seen_requirements.has(requirement.id):
				return _bad("customers." + customer.id, "duplicate requirement", "DUPLICATE_ID")
			seen_requirements[requirement.id] = true
			if requirement.has("ingredient_id") and requirement.ingredient_id not in raw.active.ingredients:
				return _bad("customers." + customer.id, "missing ingredient reference", "MISSING_REFERENCE")
			if requirement.kind == "flavor" and (not _range(requirement.get("taste"), 0, 6) or not _range(requirement.get("slot"), 0, 3) or int(requirement.taste) != requirement.taste or int(requirement.slot) != requirement.slot):
				return _bad("customers." + customer.id, "invalid flavor matrix coordinates")
			if requirement.kind == "texture" and requirement.get("axis") not in ["A", "B", "C"]:
				return _bad("customers." + customer.id, "invalid texture axis")
			if requirement.kind in ["flavor", "temperature", "texture", "fine"] and (not _range(requirement.get("min"), -1000, 1000) or not _range(requirement.get("max"), float(requirement.min), 1000) or not _range(requirement.get("scale"), .000001, 10000)):
				return _bad("customers." + customer.id, "invalid range or zero scale")
	for key: String in ["quality_weight", "harmony_weight", "requirements_weight"]:
		if not _range(raw.scoring_rules.get(key), 0, 1):
			return _bad("scoring_rules." + key, "weight in [0,1] required")
	var rules_check: TDOutcome = _check_rules(raw.rules)
	if not rules_check.ok:
		return rules_check
	if raw.has("pc_operations"):
		var pc_check: TDOutcome = _check_pc(raw.pc_operations, raw.operations, indexed.ingredients,indexed.recipes)
		if not pc_check.ok: return pc_check
	_data = raw.duplicate(true)
	# Candidate entries outside the explicit active set are not runtime definitions.
	_data.ingredients = []
	_data.recipes = []
	for id: String in raw.active.ingredients:
		_data.ingredients.append(indexed.ingredients[id].duplicate(true))
	for id: String in raw.active.recipes:
		_data.recipes.append(indexed.recipes[id].duplicate(true))
	return TDOutcome.new(true, "LOADED")

func data() -> Dictionary:
	return _data.duplicate(true)

func adopt_recipe(recipe: Dictionary, sheet: Dictionary) -> void:
	_data.recipes.append(recipe.duplicate(true))
	if not (_data.active.recipes as Array).has(recipe.id):
		_data.active.recipes.append(recipe.id)
	_data.pc_operations.document_sheets[String(sheet.get("id", ""))] = sheet.duplicate(true)

func recipe_ids(include_test: bool = false) -> Array:
	var values: Array = []
	for recipe: Dictionary in _data.get("recipes", []):
		if include_test or recipe.scope != "TEST_ONLY":
			values.append(recipe.id)
	return values

func for_recipe(id: String) -> Dictionary:
	for recipe: Dictionary in _data.get("recipes", []):
		if recipe.id == id:
			var config: Dictionary = data()
			config.selected_recipe_id = id
			config.recipe = recipe.duplicate(true)
			return config
	return {}

func _check_qte(qte: Variant, path: String) -> TDOutcome:
	if not qte is Dictionary or qte.get("kind") not in ["charge", "rhythm", "window", "maintain", "sequence"]:
		return _bad(path, "unsupported QTE kind")
	var fields: Array = []
	match qte.kind:
		"charge": fields = ["timeout_sec", "target_min_sec", "target_max_sec", "good_margin_sec"]
		"rhythm": fields = ["beats", "interval_sec", "lead_in_sec", "perfect_sec", "good_sec", "good_quality"]
		"window": fields = ["target_sec", "perfect_sec", "good_sec", "timeout_sec"]
		"maintain": fields = ["duration_sec", "target_min", "target_max", "initial_value", "disturbance_amplitude", "disturbance_period_sec"]
		"sequence": fields = ["timeout_sec"]
	for field: String in fields:
		if not _range(qte.get(field), 0, 3600):
			return _bad(path + "." + field, "finite nonnegative parameter required")
	if qte.kind in ["rhythm", "window"] and (qte.perfect_sec <= 0 or qte.good_sec < qte.perfect_sec):
		return _bad(path, "ordered positive windows required")
	if qte.kind == "rhythm" and (qte.beats < 1 or int(qte.beats) != qte.beats or qte.interval_sec <= 0 or qte.good_quality > 1):
		return _bad(path, "positive integer beat count and interval required")
	if qte.kind == "window" and qte.timeout_sec < qte.target_sec + qte.good_sec:
		return _bad(path, "timeout must include the final valid window")
	if qte.kind == "charge" and (qte.target_min_sec <= 0 or qte.target_max_sec < qte.target_min_sec or qte.timeout_sec <= qte.target_max_sec):
		return _bad(path, "charge range exceeds timeout")
	if qte.kind == "maintain" and (qte.target_min >= qte.target_max or qte.target_max > 1 or qte.duration_sec <= 0 or qte.disturbance_period_sec <= 0 or qte.disturbance_amplitude <= 0):
		return _bad(path, "invalid continuous control range/disturbance")
	if qte.kind == "sequence":
		if qte.timeout_sec <= 0:
			return _bad(path, "positive timeout required")
		if not _strings(qte.get("sequence")) or qte.sequence.is_empty():
			return _bad(path, "nonempty direction sequence required")
		for action: String in qte.sequence:
			if action not in ["up", "left", "down", "right"]:
				return _bad(path, "unknown direction")
	return TDOutcome.new(true)

func _check_rules(rules: Dictionary) -> TDOutcome:
	for field: String in ["room_temperature_c", "cooling_tau_sec", "max_temperature_c", "min_temperature_c", "degrees_per_heat_dose", "boil_max_temperature_c", "heat_front_loss_per_dose", "heat_after_gain_per_dose", "heat_tenderness_per_dose", "heat_overcook_dose", "heat_overcook_hardness", "cut_release_front", "cut_release_after", "stir_aroma_gain", "quality_bonus_max", "extra_step_penalty", "extra_ingredient_penalty", "missing_required_multiplier", "no_aroma_quality_multiplier", "no_aroma_harmony_penalty", "custom_completion_cap", "harmony_aroma_bonus", "harmony_texture_bonus", "compound_threshold", "dominant_epsilon", "perfect_grade_threshold", "negative_aroma_penalty", "cut_miss_delay_sec", "cut_miss_san_cost"]:
		if not _range(rules.get(field), -1000, 10000):
			return _bad("rules." + field, "finite parameter required")
	if rules.cooling_tau_sec <= 0 or rules.min_temperature_c > rules.max_temperature_c:
		return _bad("rules", "temperature/cooling range invalid")
	if not _range(rules.get("preheat_transfer"), 0, 1) or not _range(rules.get("season_error_overpour"), 0, 10) or not _range(rules.get("maximum_instances"), 1, 1000):
		return _bad("rules", "preheat transfer, seasoning error and instance limit required")
	if not _range(rules.get("cut_injury_probability"), 0, 1) or not _range(rules.get("cut_injury_quality_threshold"), 0, 1):
		return _bad("rules", "cut injury probability/threshold must be in [0,1]")
	for field: String in ["missing_required_multiplier", "no_aroma_quality_multiplier", "perfect_grade_threshold"]:
		if not _range(rules[field], 0, 1):
			return _bad("rules." + field, "multiplier must be in [0,1]")
	for field: String in ["quality_bonus_max", "extra_step_penalty", "extra_ingredient_penalty", "custom_completion_cap", "no_aroma_harmony_penalty", "harmony_aroma_bonus", "harmony_texture_bonus", "compound_threshold", "negative_aroma_penalty"]:
		if not _range(rules[field], 0, 100):
			return _bad("rules." + field, "score parameter must be in [0,100]")
	for field: String in ["degrees_per_heat_dose", "heat_front_loss_per_dose", "heat_after_gain_per_dose", "heat_tenderness_per_dose", "heat_overcook_dose", "heat_overcook_hardness", "cut_release_front", "cut_release_after", "stir_aroma_gain", "dominant_epsilon", "cut_miss_delay_sec", "cut_miss_san_cost"]:
		if not _range(rules[field], 0, 100):
			return _bad("rules." + field, "nonnegative bounded parameter required")
	for field: String in ["plate_early_aroma_factor", "plate_miss_aroma_factor"]:
		if not _range(rules.get(field), 0, 1):
			return _bad("rules." + field, "aroma multiplier in [0,1] required")
	for field: String in ["plate_late_heat_dose", "heat_crispness_loss_per_dose"]:
		if not _range(rules.get(field), 0, 10):
			return _bad("rules." + field, "nonnegative effect required")
	if not _strings(rules.get("negative_aromas")):
		return _bad("rules.negative_aromas", "string list required")
	if not _vector(rules.get("heat_taste_delta"), 7, -100, 100) or not rules.get("harmony_pairs") is Dictionary or not rules.get("harmony_levels") is Array or rules.harmony_levels.size() != 5 or not rules.get("temperature_bands") is Array or rules.temperature_bands.size() != 3:
		return _bad("rules", "heat vector, harmony table and three bands required")
	var previous: float = -INF
	for band: Variant in rules.temperature_bands:
		if not band is Dictionary or not _range(band.get("max_c"), -100, 10000) or band.max_c <= previous or not _vector(band.get("taste_factors"), 7, 0, 10) or not _vector(band.get("slot_factors"), 4, 0, 10):
			return _bad("rules.temperature_bands", "invalid ordered band")
		previous = band.max_c
	previous = -INF
	for level: Variant in rules.harmony_levels:
		if not level is Dictionary or not _range(level.get("min"), -10000, 10000) or level.min <= previous or not _range(level.get("score"), 0, 100):
			return _bad("rules.harmony_levels", "invalid five levels")
		previous = level.min
	for pair: String in rules.harmony_pairs:
		var parts: PackedStringArray = pair.split(":")
		if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int() or int(parts[0]) < 0 or int(parts[1]) > 6 or int(parts[0]) >= int(parts[1]) or not _range(rules.harmony_pairs[pair], -10, 10):
			return _bad("rules.harmony_pairs", "taste pair must be ordered 0..6 and finite")
	return TDOutcome.new(true)

func _cost(value: Variant) -> bool:
	return value is Dictionary and value.get("event") == "deliver" and _range(value.get("amount"), 0, 100)

func _check_pc(pc: Variant, operations: Dictionary, ingredients: Dictionary, recipes: Dictionary) -> TDOutcome:
	if not pc is Dictionary or not _range(pc.get("bpm"), 30, 240) or not _range(pc.get("max_fine_steps"), 1, 16) or not pc.get("modules") is Dictionary or not pc.get("sheets") is Dictionary or not pc.get("weights") is Dictionary: return _bad("pc_operations", "invalid PC configuration")
	for field: String in ["diagonal_release_bonus", "stir_texture_gain", "stir_harmony_gain"]:
		if not _range(pc.get(field), 0, 10): return _bad("pc_operations." + field, "bounded coefficient required")
	if not _vector(pc.get("dual_target_offsets"),2,-.3,.3): return _bad("pc_operations.dual_target_offsets","two bounded offsets required")
	for kind: String in operations:
		if not _range(pc.weights.get(kind), 0, 100) or not pc.modules.get(kind) is Dictionary: return _bad("pc_operations", "missing module or weight")
	for kind: String in pc.modules:
		var request := TDRequest.new("validation", 0, kind, kind, 0)
		request.schema_version = 3
		var controller := TDCookingQTE.new(request, pc.modules[kind], TDClock.new(), TDBusinessRandom.new(1))
		if not controller.start().ok: return _bad("pc_operations.modules." + kind, "invalid QTE configuration")
		if pc.modules[kind].get("cabinet", false):
			for action: Variant in pc.modules[kind].get("allowed_actions", []):
				var identity: String = str(action).trim_prefix("spice:")
				if not ingredients.has(identity) or ingredients[identity].category != "seasoning": return _bad("pc_operations.modules." + kind, "invalid cabinet ingredient")
	for id: String in pc.sheets:
		if not pc.sheets[id] is Dictionary or pc.sheets[id].get("id") != id: return _bad("pc_operations.sheets", "identity mismatch")
		if pc.sheets[id].get("bpm") != pc.bpm: return _bad("pc_operations.sheets","sheets share the kitchen BPM")
		var sheet := TDBeatSheet.new()
		if not sheet.configure(pc.sheets[id], operations).ok: return _bad("pc_operations.sheets." + id, "invalid or conflicting beat sheet")
	if pc.has("document_sheets"):
		if not pc.document_sheets is Dictionary or not pc.get("document_weights") is Dictionary: return _bad("pc_operations.document_sheets","typed sheets and weights required")
		if not pc.get("document_rules") is Dictionary or not pc.document_rules.get("preparation_recipes") is Dictionary or not _range(pc.document_rules.get("feedback_sec"),.5,3): return _bad("document_rules","preparation map and bounded feedback lifetime required")
		if not pc.document_rules.get("assistance",{}) is Dictionary: return _bad("document_rules.assistance","object required")
		var assistance: Dictionary=pc.document_rules.get("assistance",{})
		if not assistance.is_empty():
			if not _range(assistance.get("perfect_sec"),.01,.15) or not _range(assistance.get("good_sec"),float(assistance.perfect_sec),.24) or not _range(assistance.get("good_quality"),.5,1) or not _range(assistance.get("automatic_quality",.85),0,1) or not assistance.get("aggregate_score") is bool or not assistance.get("smooth_maintain") is bool: return _bad("document_rules.assistance","bounded playability values required")
		for ingredient: String in pc.document_rules.preparation_recipes:
			var target: Variant=pc.document_rules.preparation_recipes[ingredient]
			if not ingredients.has(ingredient) or not target is String or not recipes.has(target): return _bad("document_rules.preparation_recipes","unknown ingredient/recipe","MISSING_REFERENCE")
		for module: String in ["M1","M2","M3","M4","M5","M6","M7"]:
			if not _range(pc.document_weights.get(module),0,100): return _bad("document_weights","invalid module weight")
		for id: String in pc.document_sheets:
			var sheet := TDBeatSheet.new()
			if not pc.document_sheets[id] is Dictionary or pc.document_sheets[id].get("id") != id or pc.document_sheets[id].get("bpm") != pc.bpm or not sheet.configure(pc.document_sheets[id],operations,assistance).ok: return _bad("document_sheets."+id,"invalid beat/track/reference/overlap")
			for event: Dictionary in sheet.snapshot().events:
				var base: String="oil" if event.operation=="season" and event.parameters.get("mode")=="common" else event.operation
				var settings: Dictionary=pc.modules[base].duplicate(true); settings.merge(event.settings,true)
				settings.merge(assistance,true)
				var request:=TDRequest.new("validation",0,event.group,event.operation,0); request.schema_version=3
				if not TDCookingQTE.new(request,settings,TDClock.new(),TDBusinessRandom.new(1)).start().ok: return _bad("document_sheets."+id+"."+event.group,"compiled QTE or material reference invalid")
	return TDOutcome.new(true)

func _id(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty()

func _strings(value: Variant) -> bool:
	if not value is Array:
		return false
	for item: Variant in value:
		if not _id(item):
			return false
	return true

func _range(value: Variant, low: float, high: float) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and value >= low and value <= high

func _vector(value: Variant, count: int, low: float, high: float) -> bool:
	if not value is Array or value.size() != count:
		return false
	for item: Variant in value:
		if not _range(item, low, high):
			return false
	return true

func _texture(value: Variant) -> bool:
	return value is Dictionary and _range(value.get("A"), -1, 1) and _range(value.get("B"), -1, 1) and _range(value.get("C"), -1, 1)

func _aroma(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for key: Variant in value:
		if not _id(key) or not _range(value[key], 0, 100):
			return false
	return true

func _json_value(value: Variant) -> bool:
	if value is Array:
		for child: Variant in value:
			if not _json_value(child): return false
		return true
	if value is Dictionary:
		for key: Variant in value:
			if not key is String or not _json_value(value[key]): return false
		return true
	return value == null or value is bool or value is String or ((value is int or value is float) and is_finite(float(value)))

func _bad(field: String, reason: String, code: String = "INVALID_CONFIG") -> TDOutcome:
	_data = {}
	return TDOutcome.new(false, code, "%s:%s: %s" % [_source, field, reason])
