class_name TDCookingSession
extends RefCounted

signal result_ready(result: TDOutcome)
const FullModel = preload("res://src/cooking/cooking_model.gd")

var _id: String
var _generation: int
var _template: Dictionary
var _state: String = "ready"
var _revision: int = 0
var _operation_id: String = ""
var _frame_sequence: int = 0
var _held_sec: float = 0.0
var _elapsed_sec: float = 0.0
var _work_units: float = 0.0
var _version: int = 1
var _config: Dictionary = {}
var _ingredients: Dictionary = {}
var _ingredient_templates: Dictionary = {}
var _dish: Dictionary = {}
var _steps: Array = []
var _history: Array = []
var _pending: Dictionary = {}
var _finished_operations: Dictionary = {}
var _cancelled_operations: Dictionary = {}
var _missing_required: Array = []
var _base_reasons: Array = []
var _temperature_c: float = 22.0
var _full: RefCounted

func set_material_sink(sink: Callable) -> void:
	if _version == 3: _full.material_sink = sink

func select_recipe(config: Dictionary) -> TDOutcome:
	return _full.select_recipe(config) if _version == 3 else TDOutcome.new(false,"UNSUPPORTED_VERSION")

func portable_data() -> TDOutcome:
	return _full.portable_data() if _version==3 else TDOutcome.new(false,"UNSUPPORTED_VERSION")

func restore_portable(data: Variant) -> TDOutcome:
	return _full.restore_portable(data) if _version==3 else TDOutcome.new(false,"UNSUPPORTED_VERSION")

func is_cold() -> bool:
	return _version==3 and _full.is_cold()

func _init(sid: String, generation: int, template: Variant, options: Dictionary = {}) -> void:
	_id = sid
	_generation = generation
	if template is Dictionary and template.get("schema_version") == 3:
		_version = 3
		_full = FullModel.new(sid, generation, template, options)
		_full.result_ready.connect(_forward_full_result)
		return
	if template is Dictionary:
		_version = 2
		_config = template.duplicate(true)
		_state = "preparing"
		for ingredient: Dictionary in _config["ingredients"]:
			_ingredient_templates[ingredient["id"]] = ingredient.duplicate(true)
		_temperature_c = float(_config["rules"]["room_temperature_c"])
		_refresh_attributes()
	else:
		_template = template.to_data()

func begin(request: TDRequest) -> TDOutcome:
	if _version == 3:
		return _full.begin(request)
	if _version == 2:
		return _begin_cooking(request)
	if request.schema_version != 1:
		return TDOutcome.new(false, "UNSUPPORTED_VERSION")
	if request.session_id != _id or request.generation != _generation:
		return TDOutcome.new(false, "WRONG_SESSION")
	if request.operation != _template["operation"]:
		return TDOutcome.new(false, "UNSUPPORTED_OPERATION")
	if request.operation_id.is_empty():
		return TDOutcome.new(false, "INVALID_ID")
	if request.expected_revision != _revision:
		return TDOutcome.new(false, "REVISION_MISMATCH")
	if _state != "ready":
		return TDOutcome.new(false, "INVALID_STATE")
	_operation_id = request.operation_id
	_state = "running"
	_revision += 1
	return TDOutcome.new(true, "STARTED", "", snapshot().to_dict())

func accept(frame: TDFrame) -> TDOutcome:
	if _version != 1:
		return TDOutcome.new(false, "UNSUPPORTED_VERSION")
	if frame.session_id != _id or frame.generation != _generation or frame.operation_id != _operation_id:
		return TDOutcome.new(false, "STALE_OPERATION")
	if _state == "cancelled":
		return TDOutcome.new(false, "CANCELLED")
	if _state in ["completed", "timed_out"]:
		return TDOutcome.new(false, "ALREADY_FINISHED")
	if _state != "running":
		return TDOutcome.new(false, "INVALID_STATE")
	if frame.schema_version != 1 or frame.status not in ["running", "completed", "timed_out"]:
		return TDOutcome.new(false, "INVALID_FRAME")
	if frame.sequence <= _frame_sequence:
		return TDOutcome.new(false, "STALE_FRAME")
	if not is_finite(frame.held_sec) or not is_finite(frame.elapsed_sec):
		return TDOutcome.new(false, "INVALID_FRAME")
	if frame.held_sec < _held_sec or frame.elapsed_sec < _elapsed_sec or frame.held_sec > frame.elapsed_sec + 0.000001:
		return TDOutcome.new(false, "INVALID_FRAME")
	if frame.elapsed_sec > float(_template["timeout_sec"]) + 0.000001:
		return TDOutcome.new(false, "INVALID_FRAME")
	if frame.held_sec > float(_template["target_sec"][1]) + 0.000001:
		return TDOutcome.new(false, "INVALID_FRAME")
	if frame.status == "completed" and frame.held_sec < float(_template["target_sec"][0]) - 0.000001:
		return TDOutcome.new(false, "INVALID_FRAME")
	if frame.status == "timed_out" and frame.elapsed_sec < float(_template["timeout_sec"]) - 0.000001:
		return TDOutcome.new(false, "INVALID_FRAME")
	_frame_sequence = frame.sequence
	_held_sec = frame.held_sec
	_elapsed_sec = frame.elapsed_sec
	_work_units = _held_sec * float(_template["rate_units_per_sec"])
	_state = frame.status
	_revision += 1
	var result := TDOutcome.new(true, frame.status.to_upper(), "", snapshot().to_dict())
	if _state != "running":
		result_ready.emit(result)
	return result

func cancel() -> TDOutcome:
	if _version == 3:
		return _full.cancel()
	if _state == "cancelled":
		return TDOutcome.new(false, "CANCELLED")
	if _state in ["completed", "timed_out", "plated"]:
		return TDOutcome.new(false, "ALREADY_FINISHED")
	if _version == 2 and not _pending.is_empty():
		_cancelled_operations[_operation_id] = true
		_pending.clear()
	_state = "cancelled"
	_revision += 1
	return TDOutcome.new(true, "CANCELLED", "", snapshot().to_dict())

func snapshot() -> TDSnapshot:
	if _version == 3:
		return TDSnapshot.new(_full.snapshot())
	if _version == 2:
		return TDSnapshot.new({
			"schema_version": 2, "scope": "COOKING_PROTOTYPE", "session_id": _id,
			"generation": _generation, "recipe_id": _config["recipe"]["id"],
			"operation_id": _operation_id, "state": _state, "revision": _revision,
			"ingredients": _ingredients, "steps": _steps, "history": _history,
			"dish_attributes": _dish, "missing_required": _missing_required,
			"base_reasons": _base_reasons, "scoring_rules": _config["scoring_rules"]
		})
	return TDSnapshot.new({
		"schema_version": 1, "scope": "DEV_ONLY", "session_id": _id,
		"generation": _generation, "template_id": _template["id"],
		"operation_id": _operation_id, "state": _state, "revision": _revision,
		"work_units": _work_units, "held_sec": _held_sec, "elapsed_sec": _elapsed_sec,
		"material": _template["material"], "dish_attributes": null
	})

func _begin_cooking(request: TDRequest) -> TDOutcome:
	if request.schema_version != 2:
		return TDOutcome.new(false, "UNSUPPORTED_VERSION")
	if request.session_id != _id or request.generation != _generation:
		return TDOutcome.new(false, "WRONG_SESSION")
	if _state == "cancelled":
		return TDOutcome.new(false, "CANCELLED")
	if _state == "plated":
		return TDOutcome.new(false, "ALREADY_FINISHED")
	if request.operation_id.is_empty():
		return TDOutcome.new(false, "INVALID_ID")
	if _finished_operations.has(request.operation_id):
		return TDOutcome.new(false, "ALREADY_FINISHED")
	if _cancelled_operations.has(request.operation_id):
		return TDOutcome.new(false, "CANCELLED")
	if request.expected_revision != _revision:
		return TDOutcome.new(false, "REVISION_MISMATCH")
	if _state == "operating":
		return TDOutcome.new(false, "BUSY")
	if request.operation not in ["add", "cut", "season", "heat", "plate"]:
		return TDOutcome.new(false, "UNSUPPORTED_OPERATION")
	var parameters: Dictionary = request.parameters.duplicate(true)
	var checked := _validate_operation(request.operation, parameters)
	if not checked.ok:
		return checked
	_operation_id = request.operation_id
	_pending = {"operation": request.operation, "parameters": parameters, "before": _dish.duplicate(true)}
	_revision += 1
	if request.operation in ["cut", "heat"]:
		_state = "operating"
		return TDOutcome.new(true, "STARTED", "", snapshot().to_dict())
	_apply_operation(request.operation, parameters, {})
	if request.operation == "plate":
		_state = "plated"
	_record_step(request.operation, parameters, {})
	var result := TDOutcome.new(true, "PLATED" if _state == "plated" else "APPLIED", "", snapshot().to_dict())
	if _state == "plated":
		result_ready.emit(result)
	return result

func _validate_operation(kind: String, args: Dictionary) -> TDOutcome:
	var expected_keys: Array = []
	if kind in ["add", "cut", "season"]:
		expected_keys = ["ingredient_id"]
		if kind == "cut":
			expected_keys.append("shape")
		if kind == "season":
			expected_keys.append("amount")
	for key: Variant in args:
		if key not in expected_keys:
			return TDOutcome.new(false, "INVALID_PARAMETERS", "Unknown parameter: " + str(key))
	if kind in ["add", "cut", "season"]:
		if not args.get("ingredient_id") is String or not _ingredient_templates.has(args["ingredient_id"]):
			return TDOutcome.new(false, "INVALID_TARGET")
		var id: String = args["ingredient_id"]
		var definition: Dictionary = _ingredient_templates[id]
		if kind == "add":
			if definition["category"] != "food":
				return TDOutcome.new(false, "INVALID_TARGET")
			if _ingredients.has(id):
				return TDOutcome.new(false, "ALREADY_PRESENT")
		if kind == "cut":
			if not _ingredients.has(id):
				return TDOutcome.new(false, "NO_TARGET")
			if not definition["can_cut"]:
				return TDOutcome.new(false, "INVALID_TARGET")
			if args.get("shape") not in ["chunk", "dice"]:
				return TDOutcome.new(false, "INVALID_SHAPE")
			if float(_config["cut_shapes"][args["shape"]]["fine"]) < float(_ingredients[id]["fine"]):
				return TDOutcome.new(false, "COARSER_CUT", "已切碎的食材不能恢复成大块；可重新开始。")
		if kind == "season":
			if definition["category"] != "seasoning":
				return TDOutcome.new(false, "INVALID_TARGET")
			if not _has_food():
				return TDOutcome.new(false, "NO_TARGET")
			var amount: Variant = args.get("amount", 1.0)
			if not _finite_range(amount, 0.01, float(definition["max_amount"])):
				return TDOutcome.new(false, "INVALID_AMOUNT")
			var current: float = float(_ingredients.get(id, {}).get("amount", 0.0))
			if current + float(amount) > float(definition["max_amount"]):
				return TDOutcome.new(false, "AMOUNT_LIMIT")
	if kind == "heat" and not _has_food():
		return TDOutcome.new(false, "NO_TARGET")
	return TDOutcome.new(true)

func complete_operation(result: TDOutcome) -> TDOutcome:
	if _version == 3:
		return _full.complete_operation(result)
	if _version != 2:
		return TDOutcome.new(false, "UNSUPPORTED_VERSION")
	if result == null:
		return TDOutcome.new(false, "INVALID_RESULT")
	var values: Dictionary = result.data
	if values.get("session_id") != _id or values.get("generation") != _generation:
		return TDOutcome.new(false, "STALE_OPERATION")
	var result_id: Variant = values.get("operation_id")
	if not result_id is String:
		return TDOutcome.new(false, "INVALID_RESULT")
	if _state == "cancelled" or _cancelled_operations.has(result_id):
		return TDOutcome.new(false, "CANCELLED")
	if _finished_operations.has(result_id):
		return TDOutcome.new(false, "ALREADY_FINISHED")
	if result_id != _operation_id:
		return TDOutcome.new(false, "STALE_OPERATION")
	if _state != "operating" or _pending.is_empty():
		return TDOutcome.new(false, "INVALID_STATE")
	var kind: String = _pending["operation"]
	if not result.ok or values.get("schema_version") != 2 or values.get("kind") != kind or values.get("status") != "completed" or not _finite_range(values.get("quality"), 0.0, 1.0) or not _finite_range(values.get("elapsed_sec"), 0.0, 3600.0):
		return TDOutcome.new(false, "INVALID_RESULT")
	if kind == "cut":
		for field: String in ["hits", "perfect", "good", "miss"]:
			if not _finite_range(values.get(field), 0.0, float(_config["qte"]["cut"]["beats"])) or int(values[field]) != values[field]:
				return TDOutcome.new(false, "INVALID_RESULT")
		if int(values["perfect"]) + int(values["good"]) != int(values["hits"]) or int(values["hits"]) + int(values["miss"]) != int(_config["qte"]["cut"]["beats"]):
			return TDOutcome.new(false, "INVALID_RESULT")
		var rhythm: Dictionary = _config["qte"]["cut"]
		var computed_quality: float = (float(values["perfect"]) + float(values["good"]) * float(rhythm["good_quality"])) / float(rhythm["beats"])
		# Audio can add a device lead-in; allow the full supported negative calibration range.
		var earliest_final_window: float = maxf(0.0, float(rhythm["lead_in_sec"]) + (float(rhythm["beats"]) - 1.0) * float(rhythm["interval_sec"]) + float(rhythm["good_sec"]) - 0.5)
		if absf(float(values["quality"]) - computed_quality) > 0.00001 or float(values["elapsed_sec"]) < earliest_final_window - 0.000001:
			return TDOutcome.new(false, "INVALID_RESULT")
	else:
		var duration: float = float(_config["qte"]["heat"]["duration_sec"])
		if not _finite_range(values.get("heat_dose"), 0.0, duration) or not _finite_range(values.get("end_power"), 0.0, 1.0) or absf(float(values["elapsed_sec"]) - duration) > 0.00001:
			return TDOutcome.new(false, "INVALID_RESULT")
		var heat: Dictionary = _config["qte"]["heat"]
		var quality: float = float(values["quality"])
		var minimum_dose: float = quality * duration * float(heat["target_power_min"])
		var maximum_dose: float = quality * duration * float(heat["target_power_max"]) + (1.0 - quality) * duration
		var dose: float = float(values["heat_dose"])
		if dose < minimum_dose - 0.000001 or dose > maximum_dose + 0.000001:
			return TDOutcome.new(false, "INVALID_RESULT", "控火品质与累计火力不一致")
	var args: Dictionary = _pending["parameters"]
	_apply_operation(kind, args, values)
	_state = "preparing"
	_revision += 1
	_record_step(kind, args, values)
	return TDOutcome.new(true, "APPLIED", "", snapshot().to_dict())

func cancel_operation(operation_id: String = "") -> TDOutcome:
	if _version == 3:
		return _full.cancel_operation(operation_id)
	if _version != 2:
		return TDOutcome.new(false, "UNSUPPORTED_VERSION")
	if _state == "cancelled":
		return TDOutcome.new(false, "CANCELLED")
	if _state != "operating":
		return TDOutcome.new(false, "INVALID_STATE")
	_cancelled_operations[_operation_id] = true
	_pending.clear()
	_state = "preparing"
	_revision += 1
	return TDOutcome.new(true, "CANCELLED", "本次工序未提交效果", snapshot().to_dict())

func advance_time(delta_sec: float) -> TDOutcome:
	if _version == 3:
		return _full.advance_time(delta_sec)
	if _version != 2:
		return TDOutcome.new(false, "UNSUPPORTED_VERSION")
	if not is_finite(delta_sec) or delta_sec < 0.0:
		return TDOutcome.new(false, "INVALID_TIME")
	if _state in ["cancelled", "plated"]:
		return TDOutcome.new(false, "INVALID_STATE")
	if delta_sec == 0.0:
		return TDOutcome.new(true, "UNCHANGED")
	var rules: Dictionary = _config["rules"]
	var room: float = float(rules["room_temperature_c"])
	_temperature_c = room + (_temperature_c - room) * exp(-delta_sec / float(rules["cooling_tau_sec"]))
	_refresh_attributes()
	# Clock progress does not invalidate an already issued operation request revision.
	return TDOutcome.new(true, "TIME_ADVANCED")

func _apply_operation(kind: String, args: Dictionary, result: Dictionary) -> void:
	if kind == "add" or kind == "season":
		_add_ingredient(args["ingredient_id"], float(args.get("amount", 1.0)))
	elif kind == "cut":
		_cut_ingredient(args["ingredient_id"], args["shape"])
	elif kind == "heat":
		_heat_ingredients(float(result["heat_dose"]))
	# Completion/harmony are rebuilt from source operation facts, never multiplied in place.
	var step := {"operation": kind, "operation_id": _operation_id, "parameters": args.duplicate(true)}
	if result.has("quality"):
		step["quality"] = float(result["quality"])
	_steps.append(step)
	_refresh_attributes()

func _record_step(kind: String, args: Dictionary, result: Dictionary) -> void:
	_history.append({"operation": kind, "operation_id": _operation_id, "parameters": args.duplicate(true), "before": _pending["before"].duplicate(true), "after": _dish.duplicate(true), "result": result.duplicate(true)})
	_finished_operations[_operation_id] = true
	_pending.clear()

func _add_ingredient(id: String, amount: float) -> void:
	var definition: Dictionary = _ingredient_templates[id]
	if not _ingredients.has(id):
		_ingredients[id] = {"id": id, "name": definition["name"], "category": definition["category"], "amount": 0.0,
			"shape": "whole", "fine": 0.0, "cut_count": 0, "heat_dose": 0.0,
			"flavor": _zero_matrix(), "texture": definition["texture"].duplicate(true), "aroma": {}}
	var ingredient: Dictionary = _ingredients[id]
	ingredient["amount"] = float(ingredient["amount"]) + amount
	for taste: int in range(7):
		for slot: int in range(4):
			ingredient["flavor"][taste][slot] = clampf(float(ingredient["flavor"][taste][slot]) + float(definition["base_flavor"][taste][slot]) * amount, 0.0, 100.0)
	for tag: String in definition["aroma"]:
		ingredient["aroma"][tag] = clampf(float(ingredient["aroma"].get(tag, 0.0)) + float(definition["aroma"][tag]) * amount, 0.0, 100.0)

func _cut_ingredient(id: String, shape: String) -> void:
	var ingredient: Dictionary = _ingredients[id]
	var old_fine: float = float(ingredient["fine"])
	var fine: float = float(_config["cut_shapes"][shape]["fine"])
	var rules: Dictionary = _config["rules"]
	for taste: int in range(7):
		for slot: int in [0, 2]:
			var gain: float = float(rules["cut_release_front"] if slot == 0 else rules["cut_release_after"])
			ingredient["flavor"][taste][slot] = clampf(float(ingredient["flavor"][taste][slot]) * (1.0 + fine * gain) / (1.0 + old_fine * gain), 0.0, 100.0)
	ingredient["fine"] = fine
	ingredient["shape"] = shape
	ingredient["cut_count"] = int(ingredient["cut_count"]) + 1

func _heat_ingredients(dose: float) -> void:
	var rules: Dictionary = _config["rules"]
	_temperature_c = clampf(_temperature_c + dose * float(rules["degrees_per_heat_dose"]), float(rules["room_temperature_c"]), float(rules["max_temperature_c"]))
	for id: String in _ingredients:
		var ingredient: Dictionary = _ingredients[id]
		var old_dose: float = float(ingredient["heat_dose"])
		var total_dose: float = old_dose + dose
		ingredient["heat_dose"] = total_dose
		for taste: int in range(7):
			for slot: int in range(4):
				var value: float = float(ingredient["flavor"][taste][slot])
				# Only a taste already present in this ingredient receives a heat modifier.
				if value > 0.0 or (taste == 2 and dose > 0.0):
					value += float(rules["heat_taste_delta"][taste]) * dose
					if slot == 0:
						value *= maxf(0.0, 1.0 - dose * float(rules["heat_front_loss_per_dose"]))
					if slot == 2:
						value += dose * float(rules["heat_after_gain_per_dose"])
					ingredient["flavor"][taste][slot] = clampf(value, 0.0, 100.0)
		if ingredient["category"] == "food":
			var overcook_delta: float = maxf(0.0, total_dose - float(rules["heat_overcook_dose"])) - maxf(0.0, old_dose - float(rules["heat_overcook_dose"]))
			ingredient["texture"]["A"] = clampf(float(ingredient["texture"]["A"]) + dose * float(rules["heat_tenderness_per_dose"]) - overcook_delta * float(rules["heat_overcook_hardness"]), -1.0, 1.0)
			ingredient["texture"]["B"] = clampf(float(ingredient["texture"]["B"]) - dose * float(rules["heat_crisp_loss_per_dose"]), -1.0, 1.0)
		if rules["heated_aroma"].has(id) and dose > 0.0:
			ingredient["aroma"][id] = clampf(float(ingredient["aroma"].get(id, 0.0)) + dose * float(rules["heated_aroma"][id]), 0.0, 100.0)
		if id == rules["caramel_ingredient_id"] and _temperature_c >= float(rules["caramel_min_temperature_c"]) and dose > 0.0:
			ingredient["aroma"]["caramel"] = clampf(float(ingredient["aroma"].get("caramel", 0.0)) + dose * float(rules["caramel_aroma_per_dose"]), 0.0, 100.0)

func _refresh_attributes() -> void:
	var rules: Dictionary = _config["rules"]
	var recipe: Dictionary = _config["recipe"]
	var flavor: Array = _zero_matrix()
	var aroma: Dictionary = {}
	var texture: Dictionary = {"A": 0.0, "B": 0.0, "C": 0.0}
	var food_count: int = 0
	for ingredient: Dictionary in _ingredients.values():
		for taste: int in range(7):
			for slot: int in range(4):
				flavor[taste][slot] += float(ingredient["flavor"][taste][slot])
		for tag: String in ingredient["aroma"]:
			aroma[tag] = clampf(float(aroma.get(tag, 0.0)) + float(ingredient["aroma"][tag]), 0.0, 100.0)
		if ingredient["category"] == "food":
			food_count += 1
			for axis: String in texture:
				texture[axis] += float(ingredient["texture"][axis])
	if food_count > 0:
		for axis: String in texture:
			texture[axis] /= food_count
	var bands: Array = rules["temperature_bands"]
	var band: Dictionary = bands[2]
	if _temperature_c < float(bands[0]["max_c"]):
		band = bands[0]
	elif _temperature_c <= float(bands[1]["max_c"]):
		band = bands[1]
	for taste: int in range(7):
		for slot: int in range(4):
			flavor[taste][slot] = clampf(float(flavor[taste][slot]) * float(band["taste_factors"][taste]) * float(band["slot_factors"][slot]), 0.0, 100.0)
	_missing_required = []
	for id: String in recipe["required_ingredients"]:
		if not _ingredients.has(id):
			_missing_required.append("ingredient:" + id)
		elif float(_ingredients[id]["heat_dose"]) < float(rules["minimum_cooking_dose"]):
			_missing_required.append("heat:" + id)
	for id: String in recipe["required_cut"]:
		if not _ingredients.has(id) or int(_ingredients[id]["cut_count"]) == 0:
			_missing_required.append("cut:" + id)
	var weighted_quality: float = 0.0
	var quality_weight: float = 0.0
	var counts: Dictionary = {"cut": 0, "heat": 0}
	for step: Dictionary in _steps:
		var kind: String = step["operation"]
		if kind in ["cut", "heat"]:
			var weight: float = float(rules["quality_weights"][kind])
			weighted_quality += float(step["quality"]) * weight
			quality_weight += weight
			counts[kind] += 1
	var quality: float = 100.0 * weighted_quality / quality_weight if quality_weight > 0.0 else 0.0
	var extra_steps: int = maxi(0, int(counts["cut"]) - recipe["required_cut"].size()) + maxi(0, int(counts["heat"]) - 1)
	quality = maxf(0.0, quality - float(extra_steps) * float(rules["extra_step_penalty"]))
	var harmony: float = float(rules["harmony_base"])
	var full_pair: bool = true
	for id: String in recipe["required_ingredients"]:
		full_pair = full_pair and _ingredients.has(id)
	if full_pair:
		harmony += float(rules["harmony_pair_bonus"])
	for tag: String in recipe["expected_aroma"]:
		if float(aroma.get(tag, 0.0)) > 0.0:
			harmony += float(rules["harmony_aroma_bonus"])
			break
	var texture_id: String = rules["harmony_texture_ingredient"]
	if _ingredients.has(texture_id) and float(_ingredients[texture_id]["texture"][rules["harmony_texture_axis"]]) >= float(rules["harmony_texture_min"]):
		harmony += float(rules["harmony_texture_bonus"])
	_base_reasons = []
	if quality_weight > 0.0:
		for kind: String in ["cut", "heat"]:
			var loss: float = 0.0
			for step: Dictionary in _steps:
				if step["operation"] == kind:
					loss += (1.0 - float(step["quality"])) * float(rules["quality_weights"][kind]) * 100.0 / quality_weight
			if loss > 0.00001:
				var label: String = "切菜节奏品质" if kind == "cut" else "控火品质"
				var advice: String = "跟随拍点，每拍按下后松开；切型选择不决定节奏品质。" if kind == "cut" else "将火力保持在提示的目标区间；长时间猛火会使鸡蛋变硬。"
				_base_reasons.append({"code": "QTE_" + kind.to_upper(), "label": label, "message": "%s使基础完成度少 %.1f；%s" % [label, loss, advice], "penalty": loss})
	if extra_steps > 0:
		_base_reasons.append({"code": "EXTRA_STEPS", "label": "额外工序", "message": "%d 次重复加工，每次完成度 −%.1f" % [extra_steps, rules["extra_step_penalty"]], "penalty": extra_steps * float(rules["extra_step_penalty"])})
	if not _missing_required.is_empty():
		var missing_labels: Array[String] = []
		for missing: String in _missing_required:
			var parts: PackedStringArray = missing.split(":")
			var name: String = _ingredient_templates[parts[1]]["name"]
			missing_labels.append("加入" + name if parts[0] == "ingredient" else ("加热" + name if parts[0] == "heat" else "切" + name))
		_base_reasons.append({"code": "MISSING_REQUIRED", "label": "菜谱必需项缺失", "message": "尚未完成：%s；完成度一次 ×%.1f" % ["、".join(missing_labels), rules["missing_required_multiplier"]], "penalty": quality * (1.0 - float(rules["missing_required_multiplier"]))})
		quality *= float(rules["missing_required_multiplier"])
	var has_aroma: bool = false
	for intensity: float in aroma.values():
		has_aroma = has_aroma or intensity > 0.0
	if recipe["expects_aroma"] and not has_aroma:
		_base_reasons.append({"code": "NO_AROMA", "label": "菜谱期待香气但完全无香", "message": "完成度一次 ×%.1f，搭配度 −%.1f" % [rules["no_aroma_quality_multiplier"], rules["no_aroma_harmony_penalty"]], "penalty": quality * (1.0 - float(rules["no_aroma_quality_multiplier"]))})
		quality *= float(rules["no_aroma_quality_multiplier"])
		harmony -= float(rules["no_aroma_harmony_penalty"])
	_dish = {"flavor": flavor, "temperature_c": _temperature_c, "aroma": aroma, "texture": texture, "completion": clampf(quality, 0.0, 100.0), "harmony": clampf(harmony, 0.0, 100.0)}

func _zero_matrix() -> Array:
	var matrix: Array = []
	for taste: int in range(7):
		matrix.append([0.0, 0.0, 0.0, 0.0])
	return matrix

func _has_food() -> bool:
	for ingredient: Dictionary in _ingredients.values():
		if ingredient["category"] == "food":
			return true
	return false

func _finite_range(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= minimum and value <= maximum

func move_plating(piece_id: String, position: Vector2, drop: bool) -> TDOutcome:
	if _version != 3:
		return TDOutcome.new(false, "UNSUPPORTED_VERSION")
	return _full.move_plating(piece_id, position, drop)

func _forward_full_result(result: TDOutcome) -> void:
	result_ready.emit(result)

func transfer_to(destination: TDCookingSession, instance_id: String, transfer_id: String) -> TDOutcome:
	if _version != 3 or destination == null or destination._version != 3: return TDOutcome.new(false, "UNSUPPORTED_VERSION")
	return _full.transfer_to(destination._full, instance_id, transfer_id)
