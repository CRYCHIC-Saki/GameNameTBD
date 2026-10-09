class_name TDRecipeLibrary
extends RefCounted
## Local, versioned plans only. Never stores QTE input, scores or dish instances.
var _path: String
var _config: Dictionary

func _init(path: String, config: Dictionary) -> void:
	_path = path
	_config = config.duplicate(true)

func load_library() -> TDOutcome:
	if not FileAccess.file_exists(_path):
		return TDOutcome.new(true, "EMPTY", "", {"schema_version": 1, "entries": []})
	var file := FileAccess.open(_path, FileAccess.READ)
	if file == null: return TDOutcome.new(false, "READ_FAILED")
	if file.get_length() > 2000000: return TDOutcome.new(false, "FILE_TOO_LARGE")
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		return TDOutcome.new(false, "INVALID_JSON")
	var data: Dictionary = parser.data
	if data.get("schema_version") != 1: return TDOutcome.new(false, "UNSUPPORTED_VERSION")
	if not data.get("entries") is Array: return TDOutcome.new(false, "INVALID_LIBRARY")
	var seen: Dictionary = {}
	for value: Variant in data.entries:
		if not value is Dictionary: return TDOutcome.new(false, "INVALID_ENTRY")
		var entry: Dictionary = value
		if not entry.get("id") is String or entry.id.is_empty() or not entry.get("name") is String or entry.name.strip_edges().is_empty():
			return TDOutcome.new(false, "INVALID_ENTRY")
		if not _number(entry.get("version"), 1, 100000) or float(entry.version) != floorf(float(entry.version)):
			return TDOutcome.new(false, "INVALID_VERSION")
		var key: String = entry.id + ":" + str(int(entry.version))
		if seen.has(key): return TDOutcome.new(false, "DUPLICATE_ID")
		seen[key] = true
		var checked := validate_plan(entry.get("plan"))
		if not checked.ok: return checked
		if entry.get("scope") != checked.data.scope: return TDOutcome.new(false, "INVALID_SCOPE")
	return TDOutcome.new(true, "LOADED", "", data.duplicate(true))

func validate_plan(value: Variant) -> TDOutcome:
	if not value is Dictionary: return TDOutcome.new(false, "INVALID_PLAN")
	var plan: Dictionary = value
	if plan.get("schema_version") != 1 and plan.get("schema_version") != 2: return TDOutcome.new(false, "UNSUPPORTED_PLAN")
	for key: String in plan:
		if key not in ["schema_version", "recipe_id", "ingredients", "operations"]:
			return TDOutcome.new(false, "UNEXPECTED_PLAN_FIELD", key)
	var recipe: Dictionary = {}
	for item: Dictionary in _config.recipes:
		if item.id == plan.get("recipe_id"): recipe = item
	if recipe.is_empty(): return TDOutcome.new(false, "MISSING_REFERENCE", "recipe_id")
	if not plan.get("ingredients") is Array or plan.ingredients.is_empty() or not plan.get("operations") is Array:
		return TDOutcome.new(false, "INVALID_PLAN")
	var test_only: bool = recipe.scope == "TEST_ONLY"
	var definitions: Dictionary = {}
	var declared: Dictionary = {}
	var introduced: Dictionary = {}
	var total_amounts: Dictionary = {}
	for item: Dictionary in _config.ingredients: definitions[item.id] = item
	for item: Variant in plan.ingredients:
		if not item is Dictionary or not definitions.has(item.get("ingredient_id")): return TDOutcome.new(false, "MISSING_REFERENCE", "ingredient_id")
		for key: String in item:
			if key not in ["ingredient_id", "amount", "batch_id", "local_id"]: return TDOutcome.new(false, "UNEXPECTED_PLAN_FIELD", key)
		if not _number(item.get("amount"), .001, float(definitions[item.ingredient_id].max_amount)): return TDOutcome.new(false, "INVALID_AMOUNT")
		if not item.get("batch_id") is String or item.batch_id.is_empty(): return TDOutcome.new(false, "INVALID_BATCH")
		if not item.get("local_id") is String or item.local_id.is_empty() or declared.has(item.local_id): return TDOutcome.new(false, "INVALID_LOCAL_ID")
		declared[item.local_id] = item
		total_amounts[item.ingredient_id] = float(total_amounts.get(item.ingredient_id, 0)) + float(item.amount)
		if total_amounts[item.ingredient_id] > float(definitions[item.ingredient_id].max_amount): return TDOutcome.new(false, "AMOUNT_LIMIT")
		test_only = test_only or definitions[item.ingredient_id].scope == "TEST_ONLY"
	for step: Variant in plan.operations:
		if not step is Dictionary or not step.get("parameters") is Dictionary or step.get("operation") not in _config.operations.keys() + ["add", "merge"]:
			return TDOutcome.new(false, "INVALID_OPERATION")
		if step.size() != 2: return TDOutcome.new(false, "UNEXPECTED_PLAN_FIELD")
		var args: Dictionary = step.parameters
		var allowed: Array = ["batch_id"]
		match str(step.operation):
			"add", "season": allowed = ["ingredient_id", "amount", "batch_id", "local_id"] + (["mode","sequence","local_ids"] if plan.schema_version == 2 and step.operation == "season" else [])
			"cut": allowed = ["ingredient_id", "shape", "batch_id", "target_local_id"] + (["beats"] if plan.schema_version == 2 else [])
			"merge": allowed = ["source_batch", "target_batch"]
			"plate": allowed = []
		for key: String in args:
			if key not in allowed: return TDOutcome.new(false, "UNEXPECTED_PLAN_FIELD", key)
		if step.operation in ["cut", "add", "season"] and not definitions.has(args.get("ingredient_id")):
			return TDOutcome.new(false, "MISSING_REFERENCE")
		if step.operation in ["add", "season"] and not _number(args.get("amount", 1), .001, float(definitions[args.ingredient_id].max_amount)):
			return TDOutcome.new(false, "INVALID_AMOUNT")
		if step.operation == "cut" and not _config.cut_shapes.has(args.get("shape")) and not (plan.schema_version == 2 and args.get("shape") == "whole"):
			return TDOutcome.new(false, "INVALID_SHAPE")
		if step.operation == "cut" and args.has("beats") and (not _number(args.beats,1,12) or int(args.beats) != args.beats): return TDOutcome.new(false,"INVALID_PARAMETERS")
		if step.operation == "season" and args.has("sequence"):
			if not args.sequence is Array or not args.get("local_ids") is Array or args.sequence.is_empty() or args.sequence.size() > 5 or args.sequence.size() != args.local_ids.size(): return TDOutcome.new(false,"INVALID_PARAMETERS")
			for index: int in args.sequence.size():
				var local_id: Variant = args.local_ids[index]
				if not local_id is String or not declared.has(local_id) or introduced.has(local_id): return TDOutcome.new(false,"INVALID_LOCAL_ID")
				var item: Dictionary = declared[local_id]
				if item.ingredient_id != args.sequence[index] or definitions[item.ingredient_id].category != "seasoning" or not is_equal_approx(float(item.amount),float(args.get("amount",1))) or item.batch_id != args.get("batch_id","main"): return TDOutcome.new(false,"PLAN_MISMATCH")
				introduced[local_id] = item.ingredient_id
			continue
		if step.operation in ["add", "season"]:
			if not args.get("local_id") is String or not declared.has(args.local_id) or introduced.has(args.local_id): return TDOutcome.new(false, "INVALID_LOCAL_ID")
			var item: Dictionary = declared[args.local_id]
			if item.ingredient_id != args.ingredient_id or not is_equal_approx(float(item.amount), float(args.get("amount", 1))) or item.batch_id != args.get("batch_id", "main"):
				return TDOutcome.new(false, "PLAN_MISMATCH")
			introduced[args.local_id] = item.ingredient_id
		if step.operation == "cut":
			if not args.get("target_local_id") is String or introduced.get(args.target_local_id, "") != args.ingredient_id: return TDOutcome.new(false, "MISSING_LOCAL_TARGET")
		for key: String in ["batch_id", "source_batch", "target_batch"]:
			if args.has(key) and (not args[key] is String or args[key].is_empty()): return TDOutcome.new(false, "INVALID_BATCH")
	if introduced.size() != declared.size(): return TDOutcome.new(false, "PLAN_MISMATCH")
	return TDOutcome.new(true, "VALID", "", {"scope": "TEST_ONLY" if test_only else "CUSTOM"})

func save_plan(title: String, plan: Dictionary, identity: String = "") -> TDOutcome:
	if title.strip_edges().is_empty() or title.length() > 60: return TDOutcome.new(false, "INVALID_NAME")
	var valid := validate_plan(plan)
	if not valid.ok: return valid
	var loaded := load_library()
	if not loaded.ok: return loaded
	var data: Dictionary = loaded.data
	var version: int = 1
	if identity.is_empty():
		identity = "custom.%d.%d" % [Time.get_unix_time_from_system(), data.entries.size()]
	else:
		var found: bool = false
		for entry: Dictionary in data.entries:
			if entry.id == identity:
				found = true
				version = maxi(version, int(entry.version) + 1)
		if not found: return TDOutcome.new(false, "MISSING_REFERENCE", "custom id")
	var entry: Dictionary = {"id": identity, "name": title.strip_edges(), "version": version, "scope": valid.data.scope, "plan": plan.duplicate(true)}
	data.entries.append(entry)
	var temporary: String = _path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return TDOutcome.new(false, "WRITE_FAILED")
	file.store_string(JSON.stringify(data, "\t"))
	file.flush()
	var error: Error = file.get_error()
	file.close()
	if error != OK: return TDOutcome.new(false, "WRITE_FAILED")
	var backup: String = _path + ".bak"
	if FileAccess.file_exists(backup) and DirAccess.remove_absolute(backup) != OK: return TDOutcome.new(false, "WRITE_FAILED")
	var exists: bool = FileAccess.file_exists(_path)
	if exists and DirAccess.rename_absolute(_path, backup) != OK: return TDOutcome.new(false, "WRITE_FAILED")
	if DirAccess.rename_absolute(temporary, _path) != OK:
		if exists: DirAccess.rename_absolute(backup, _path)
		return TDOutcome.new(false, "WRITE_FAILED")
	return TDOutcome.new(true, "SAVED", "", entry)

func _number(value: Variant, low: float, high: float) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and float(value) >= low and float(value) <= high
