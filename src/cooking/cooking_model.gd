class_name TDCookingModel
extends RefCounted

signal result_ready(result: TDOutcome)
const CatalogValidator = preload("res://src/content/cooking_catalog.gd")

var _id: String
var _generation: int
var _config: Dictionary
var _recipe: Dictionary
var _definitions: Dictionary = {}
var _ingredients: Dictionary = {}
var _batches: Dictionary = {"main": {"temperature_c": 22.0}}
var _state: String = "preparing"
var _revision: int = 0
var _operation_id: String = ""
var _pending: Dictionary = {}
var _done: Dictionary = {}
var _cancelled: Dictionary = {}
var _steps: Array = []
var _history: Array = []
var _events: Array = []
var _plating: Array = []
var _instance_counter: int = 0
var _container: String = "normal"
var _san: float = 100.0
var _san_spent: float = 0.0
var _random: RefCounted
var _variant_id: String = ""
var _reaction_harmony: float = 0.0
var _consumed: Array = []
var _plan: Array = []
var _recovery_sec: float = 0.0
var _initial_error: String = ""
var _dragged_piece: String = ""
var _fermenting: Dictionary = {}
var _prepared_random: float = 0.0
var _pc_controls: bool = false
var _jobs: Dictionary = {}
var _transfers: Dictionary = {}
var _document_rules: bool = false
var material_sink: Callable

func select_recipe(config: Dictionary) -> TDOutcome:
	if _state != "preparing" or not _jobs.is_empty() or _steps.any(func(s:Dictionary)->bool:return s.operation != "cut"):
		return _error("RECIPE_LOCKED")
	if not config.has("recipe") or config.get("ingredients") != _config.ingredients: return _error("INCOMPATIBLE_CONTENT")
	_config = config.duplicate(true); _recipe = _config.recipe.duplicate(true)
	return TDOutcome.new(true,"RECIPE_SELECTED")

func _take_materials(token: String, amounts: Dictionary) -> TDOutcome:
	if amounts.is_empty() or not material_sink.is_valid(): return TDOutcome.new(true)
	return material_sink.call(_id+":"+token,amounts)

func _init(sid: String, generation: int, config: Dictionary, options: Dictionary = {}) -> void:
	_id = sid
	_generation = generation
	_config = config.duplicate(true)
	_pc_controls = bool(options.get("pc_controls", false))
	_document_rules = _pc_controls and bool(options.get("document_rules",false))
	_recipe = _config.recipe.duplicate(true)
	if options.get("custom_recipe") is Dictionary:
		var candidate: Dictionary = _recipe.duplicate(true)
		candidate.merge(options.custom_recipe.duplicate(true), true)
		candidate.is_custom = true
		var validation_data: Dictionary = _config.duplicate(true)
		validation_data.erase("selected_recipe_id")
		validation_data.erase("recipe")
		# Validate the candidate in the real catalog context; preparation defaults
		# may legitimately reference the other existing recipes.
		validation_data.recipes = validation_data.recipes.filter(func(entry:Dictionary)->bool:return entry.id != candidate.id)
		validation_data.recipes.append(candidate)
		validation_data.active.recipes = [candidate.get("id", "")]
		var checked: TDOutcome = CatalogValidator.new().load_data(validation_data, "custom_recipe")
		if checked.ok: _recipe = candidate
		else: _initial_error = checked.message
	if not _finite(options.get("san", 100), 0, 100):
		_initial_error = "SAN must be finite and in [0,100]"
	else:
		_san = float(options.get("san", 100))
	var random: Variant = options.get("random_source", TDBusinessRandom.new(12345))
	if not random is RefCounted or not random.has_method("unit"):
		_initial_error = "random_source must implement unit()"
		_random = TDBusinessRandom.new(12345)
	else:
		_random = random
	for definition: Dictionary in _config.ingredients:
		_definitions[definition.id] = definition.duplicate(true)
	_batches.main.temperature_c = float(_config.rules.room_temperature_c)

func begin(request: TDRequest) -> TDOutcome:
	if not _initial_error.is_empty():
		return _error("INVALID_CONFIG", _initial_error)
	if request == null:
		return _error("INVALID_REQUEST")
	if request.schema_version != 3:
		return _error("UNSUPPORTED_VERSION")
	if request.session_id != _id or request.generation != _generation:
		return _error("WRONG_SESSION")
	if request.operation_id.is_empty():
		return _error("INVALID_ID")
	if _done.has(request.operation_id):
		return _error("ALREADY_FINISHED")
	if _cancelled.has(request.operation_id):
		return _error("CANCELLED")
	if _state in ["delivered", "discarded", "cancelled"]:
		return _error("ALREADY_FINISHED")
	if _state == "operating" and not _parallel_allowed(request.operation):
		return _error("BUSY")
	if _recovery_sec > .000001 and request.operation != "discard":
		return _error("RECOVERING", "切菜失误，稍等片刻再继续。")
	if request.expected_revision != _revision:
		return _error("REVISION_MISMATCH")
	var kind: String = request.operation
	var args: Dictionary = request.parameters.duplicate(true)
	var checked: TDOutcome = _validate(kind, args)
	if not checked.ok:
		return checked
	if kind == "add":
		var stock := _take_materials(request.operation_id,{str(args.ingredient_id):roundi(float(args.get("amount",1))*1000)})
		if not stock.ok: return stock
	_operation_id = request.operation_id
	var before: Dictionary = _derive().attributes
	_revision += 1
	if _config.operations.has(kind):
		_pending = {"operation": kind, "parameters": args, "before": before}
		_jobs[_operation_id] = _pending.duplicate(true)
		_state = "operating"
		return TDOutcome.new(true, "STARTED", "", {"qte_config": _qte_config(kind, args), "snapshot": snapshot()})
	var extra: Dictionary = {}
	match kind:
		"add":
			extra.instance_id = _add(args)
			extra.local_id = _ingredients[extra.instance_id].local_id
		"merge":
			for ingredient: Dictionary in _ingredients.values():
				if ingredient.batch_id == args.source_batch:
					ingredient.batch_id = args.target_batch
			_batches.erase(args.source_batch)
		"container": _container = args.kind
		"rework":
			_state = "preparing"
			_plating.clear()
		"discard":
			_state = "discarded"
			_events.append({"type": "dish_discarded", "dish_id": _dish_id()})
		"deliver": _deliver()
	_done[_operation_id] = true
	_record(kind, args, before, {})
	var code: String = "DELIVERED" if kind == "deliver" else ("DISCARDED" if kind == "discard" else "APPLIED")
	extra.merge(snapshot())
	var result := TDOutcome.new(true, code, "", extra)
	if kind in ["deliver", "discard"]:
		result_ready.emit(result)
	return result

func _validate(kind: String, args: Dictionary) -> TDOutcome:
	if kind not in ["add", "merge", "container", "rework", "deliver", "discard"] and not _config.operations.has(kind):
		return _error("UNSUPPORTED_OPERATION")
	if _state == "plated" and kind not in ["rework", "deliver", "discard", "container"]:
		return _error("REWORK_REQUIRED", "成盘后先选择回锅，再继续加工。")
	if kind in ["rework", "deliver"] and _state != "plated":
		return _error("INVALID_STATE", "先完成出锅摆盘。")
	if kind == "deliver" and not _dragged_piece.is_empty():
		return _error("PLATING_IN_PROGRESS", "先松开正在摆放的食物，再交付。")
	var allowed: Array = []
	match kind:
		"add", "season": allowed = ["ingredient_id", "amount", "batch_id"] + (["mode","sequence"] if _pc_controls and kind == "season" else [])
		"cut": allowed = ["instance_id", "shape", "batch_id"] + (["beats"] if _pc_controls else [])
		"merge": allowed = ["source_batch", "target_batch"]
		"container": allowed = ["kind"]
		"preheat", "heat", "boil", "stir", "starch", "ferment", "steam": allowed = ["batch_id"]
	if _document_rules and kind == "starch": allowed += ["ingredient_id","amount"]
	for key: Variant in args:
		if key not in allowed:
			return _error("INVALID_PARAMETERS", "Unknown field: " + str(key))
	if args.has("batch_id") and (not args.batch_id is String or args.batch_id.strip_edges().is_empty()):
		return _error("INVALID_BATCH")
	var batch: String = args.get("batch_id", "main")
	if _document_rules and kind == "starch" and args.has("ingredient_id"):
		if args.ingredient_id != "starch": return _error("INVALID_TARGET")
		var check := _validate("add",args)
		if not check.ok: return check
	if kind in ["add", "season"]:
		if _ingredients.size() >= int(_config.rules.maximum_instances):
			return _error("INSTANCE_LIMIT")
		if not args.get("ingredient_id") is String or not _definitions.has(args.ingredient_id):
			return _error("INVALID_TARGET")
		var definition: Dictionary = _definitions[args.ingredient_id]
		if not definition.available:
			return _error("UNAVAILABLE_INGREDIENT")
		if kind == "season" and definition.category != "seasoning":
			return _error("INVALID_TARGET", "顺序调味需要调料。")
		if not _finite(args.get("amount", 1.0), .001, float(definition.max_amount)):
			return _error("INVALID_AMOUNT")
		var used: float = 0.0
		for ingredient: Dictionary in _ingredients.values():
			if ingredient.ingredient_id == definition.id:
				used += float(ingredient.amount)
		if used + float(args.get("amount", 1.0)) > float(definition.max_amount):
			return _error("AMOUNT_LIMIT")
	if kind == "cut":
		if not args.get("instance_id") is String or not _ingredients.has(args.instance_id):
			return _error("INVALID_TARGET")
		var item: Dictionary = _ingredients[args.instance_id]
		if "cuttable" not in item.special or (not _pc_controls and not _config.cut_shapes.has(args.get("shape", ""))):
			return _error("INVALID_SHAPE")
		if _pc_controls and (not _finite(args.get("beats", 2), 1, 12) or int(args.get("beats", 2)) != args.get("beats", 2)): return _error("INVALID_PARAMETERS")
		if not _pc_controls and float(_config.cut_shapes[args.shape].fine) < float(item.fine):
			return _error("COARSER_CUT", "已经切细的食材不能恢复成大块。")
	if kind == "season" and args.get("mode", "precise") not in ["precise", "common"]: return _error("INVALID_PARAMETERS")
	if kind == "season" and args.has("sequence"):
		if not args.sequence is Array or args.sequence.is_empty() or args.sequence.size() > 5: return _error("INVALID_PARAMETERS")
		for ingredient: Variant in args.sequence:
			if not ingredient is String or "spice:"+ingredient not in _config.pc_operations.modules.season.allowed_actions: return _error("INVALID_PARAMETERS")
	if kind in ["stir", "heat", "boil", "season", "starch", "ferment", "steam"] and _members(batch).is_empty():
		return _error("NO_TARGET")
	if kind == "plate" and _ingredients.is_empty():
		return _error("NO_TARGET", "空盘不能产出菜品。")
	if kind == "merge":
		if not args.get("source_batch") is String or not args.get("target_batch") is String or args.source_batch == args.target_batch or not _batches.has(args.source_batch) or not _batches.has(args.target_batch):
			return _error("INVALID_BATCH")
	if kind == "container" and args.get("kind") not in ["normal", "insulated"]:
		return _error("INVALID_CONTAINER")
	if kind == "deliver" and _variant_eligible():
		return _prepare_random()
	return TDOutcome.new(true)

func complete_operation(result: TDOutcome) -> TDOutcome:
	if result == null:
		return _error("INVALID_RESULT")
	var values: Dictionary = result.data
	if values.get("session_id") != _id or values.get("generation") != _generation:
		return _error("STALE_OPERATION")
	var identity: Variant = values.get("operation_id")
	if _cancelled.has(identity) or _state == "cancelled":
		return _error("CANCELLED")
	if _done.has(identity):
		return _error("ALREADY_FINISHED")
	if not _jobs.has(identity):
		return _error("STALE_OPERATION")
	if _state != "operating":
		return _error("INVALID_STATE")
	var job: Dictionary = _jobs[identity]
	var kind: String = job.operation
	if not result.ok or values.get("schema_version") != 3 or values.get("kind") != kind or values.get("status") != "completed" or not _finite(values.get("quality"), 0, 1) or not _finite(values.get("elapsed_sec"), 0, 3600):
		return _error("INVALID_RESULT")
	if values.has("heat_dose") and not _finite(values.heat_dose, 0, float(values.elapsed_sec) + .000001):
		return _error("INVALID_RESULT")
	if values.has("held_sec") and not _finite(values.held_sec, 0, float(values.elapsed_sec) + .000001):
		return _error("INVALID_RESULT")
	if _pc_controls:
		if kind == "cut":
			if not values.get("cut_directions") is Array or values.cut_directions.size() > int(job.parameters.get("beats", 2)): return _error("INVALID_RESULT")
			for direction: Variant in values.cut_directions:
				if not _finite(direction, 0, 2) or int(direction) != direction: return _error("INVALID_RESULT")
		if kind == "season" and job.parameters.get("mode", "precise") != "common":
			var seasoning_check := _validate_season_result(values, job.parameters)
			if not seasoning_check.ok: return seasoning_check
	if kind == "cut" and float(values.quality) < float(_config.rules.cut_injury_quality_threshold):
		var random_check: TDOutcome = _prepare_random()
		if not random_check.ok: return random_check
	var args: Dictionary = job.parameters
	var needed: Dictionary = {}
	if kind == "season" and _pc_controls and args.get("mode","precise") != "common":
		for actual: Dictionary in values.actual_actions:
			var material: String = str(actual.action).trim_prefix("spice:")
			needed[material] = int(needed.get(material,0))+roundi(float(actual.get("amount",args.get("amount",.1)))*1000)
	elif kind == "season" or (_document_rules and kind == "starch" and args.has("ingredient_id")):
		needed[str(args.ingredient_id)] = roundi(float(args.get("amount",1))*1000)
	var stocked := _take_materials(str(identity),needed)
	if not stocked.ok: return stocked
	_operation_id = str(identity)
	var before: Dictionary = job.before
	var batch: String = args.get("batch_id", "main")
	var quality: float = values.quality
	var elapsed: float = values.elapsed_sec
	var created_instance: String = ""
	_steps.append({"operation": kind, "operation_id": _operation_id, "parameters": args.duplicate(true), "quality": quality, "grade": "Perfect" if quality >= float(_config.rules.perfect_grade_threshold) else "Other", "elapsed_sec": elapsed, "module":_module(kind,args)})
	if _document_rules and kind == "starch" and args.has("ingredient_id"): _add(args)
	match kind:
		"cut":
			if _pc_controls: _cut_from_hits(args.instance_id, values.cut_directions, quality)
			else: _cut(args.instance_id, args.shape, quality)
		"preheat":
			_ensure_batch(batch)
			if _pc_controls:
				_batches[batch].temperature_c = lerpf(float(_config.rules.room_temperature_c), float(_config.rules.max_temperature_c), clampf(float(values.get("cursor", 0)), 0, 1))
			else: _batches[batch].temperature_c = minf(float(_config.rules.max_temperature_c), float(_config.rules.room_temperature_c) + float(values.get("held_sec", elapsed)) * float(_config.rules.degrees_per_heat_dose))
		"heat", "boil": _heat(batch, kind, float(values.get("heat_dose", elapsed * (.35 + .5 * quality))), elapsed)
		"steam": _heat(batch, "boil", float(values.get("held_sec", 0)) * .5, elapsed)
		"stir":
			for item: Dictionary in _members(batch):
				if _pc_controls: item.texture.C = clampf(float(item.texture.C) + (quality - .5) * float(_config.pc_operations.stir_texture_gain), -1, 1)
				for tag: String in item.aroma:
					item.aroma[tag] = minf(100, float(item.aroma[tag]) + quality * float(_config.rules.stir_aroma_gain))
			if _pc_controls: _reaction_harmony += (quality - .5) * float(_config.pc_operations.stir_harmony_gain)
		"season":
			if _pc_controls and args.get("mode", "precise") != "common":
				for actual: Dictionary in values.actual_actions:
					var identity_material: String = str(actual.action).trim_prefix("spice:")
					created_instance = _add({"ingredient_id": identity_material, "amount": actual.get("amount",args.get("amount", .1)), "batch_id": batch})
					_season_quality(created_instance, quality, int(actual.beat_index))
			else:
				created_instance = _add(args)
				_season_quality(created_instance, quality, 0)
		"starch", "ferment":
			_react(batch, kind, elapsed)
			if kind == "ferment": _start_fermentation(batch)
		"plate":
			_apply_plating_timing(values)
			_plating.clear()
			_dragged_piece = ""
			var index: int = 0
			for item: Dictionary in _ingredients.values():
				var angle: float = float(index) * 2.399963229728653
				var radius: float = .8 * sqrt(float(index) / maxf(1, float(_ingredients.size() - 1)))
				_plating.append({"id": item.id, "position": [cos(angle) * radius, sin(angle) * radius]})
				index += 1
	_jobs.erase(identity)
	_state = "operating" if not _jobs.is_empty() else ("plated" if kind == "plate" else "preparing")
	_done[_operation_id] = true
	_pending = _jobs.values()[0] if not _jobs.is_empty() else {}
	_revision += 1
	_record(kind, args, before, values)
	var message: String = "菌种开始发酵，剩余时间见发酵进度；可等待或继续其他工序。" if kind == "ferment" and not _fermenting.is_empty() else ""
	var data: Dictionary = snapshot()
	if not created_instance.is_empty():
		data.instance_id = created_instance
		data.local_id = _ingredients[created_instance].local_id
	return TDOutcome.new(true, "PLATED" if kind == "plate" else "APPLIED", message, data)

func cancel_operation(operation_id: String = "") -> TDOutcome:
	if _state != "operating":
		return _error("INVALID_STATE")
	if not operation_id.is_empty() and not _jobs.has(operation_id): return _error("STALE_OPERATION")
	for identity: String in _jobs.keys():
		if operation_id.is_empty() or operation_id == identity:
			_cancelled[identity] = true; _jobs.erase(identity)
	_pending = _jobs.values()[0] if not _jobs.is_empty() else {}
	_state = "operating" if not _jobs.is_empty() else "preparing"
	_revision += 1
	return TDOutcome.new(true, "CANCELLED")

func cancel() -> TDOutcome:
	if _state in ["delivered", "discarded", "cancelled"]:
		return _error("ALREADY_FINISHED")
	if not _pending.is_empty():
		for identity: String in _jobs: _cancelled[identity] = true
	_jobs.clear()
	_pending.clear()
	_state = "cancelled"
	_revision += 1
	return TDOutcome.new(true, "CANCELLED")

func advance_time(delta: float) -> TDOutcome:
	if not _finite(delta, 0, 86400):
		return _error("INVALID_TIME")
	if _state in ["delivered", "discarded", "cancelled"]:
		return _error("INVALID_STATE")
	var room: float = _config.rules.room_temperature_c
	_recovery_sec = maxf(0, _recovery_sec - delta)
	var decay: float = 1.0 if _container == "insulated" else exp(-delta / float(_config.rules.cooling_tau_sec))
	var starting_temperatures: Dictionary = {}
	for item: Dictionary in _ingredients.values():
		starting_temperatures[item.id] = item.temperature_c
		item.temperature_c = room + (float(item.temperature_c) - room) * decay
		if float(item.fine) > 0:
			item.exposure_sec += delta
			for reaction: Dictionary in _config.reactions:
				if reaction.trigger == "exposure":
					item.reaction_exposure[reaction.id] = float(item.reaction_exposure.get(reaction.id, 0)) + _eligible_time(float(starting_temperatures[item.id]), float(item.temperature_c), float(reaction.min_temperature), delta)
					if float(item.reaction_exposure[reaction.id]) >= float(reaction.min_duration): _apply_reaction(item, reaction)
	for batch: Dictionary in _batches.values():
		batch.temperature_c = room + (float(batch.temperature_c) - room) * decay
	_advance_fermentation(delta, starting_temperatures)
	return TDOutcome.new(true, "TIME_ADVANCED")

func move_plating(piece_id: String, position: Vector2, drop: bool) -> TDOutcome:
	if _state != "plated":
		return _error("INVALID_STATE")
	if not position.is_finite():
		return _error("INVALID_POSITION")
	for piece: Dictionary in _plating:
		if piece.id == piece_id:
			if not drop:
				_dragged_piece = piece_id
				piece.preview_position = [position.x, position.y]
				return TDOutcome.new(true, "DRAGGING")
			_dragged_piece = ""
			piece.erase("preview_position")
			if drop and position.length_squared() > 1.0:
				_state = "discarded"
				_events.append({"type": "dish_discarded", "reason": "SPILLED", "dish_id": _dish_id()})
				var result := TDOutcome.new(true, "DISCARDED", "食物倒出盘外，这份菜已报废。", snapshot())
				result_ready.emit(result)
				return result
			piece.position = [position.x, position.y]
			return TDOutcome.new(true, "MOVED")
	return _error("INVALID_TARGET")

func _add(args: Dictionary) -> String:
	var definition: Dictionary = _definitions[args.ingredient_id]
	var batch: String = args.get("batch_id", "main")
	_ensure_batch(batch)
	_instance_counter += 1
	var id: String = "%s:%d:ingredient:%d" % [_id, _generation, _instance_counter]
	var flavor: Array = _matrix()
	for taste: int in range(7):
		for slot: int in range(4):
			flavor[taste][slot] = clampf(float(definition.base_tastes[taste]) * float(definition.slot_profile[slot]), 0, 100)
	_ingredients[id] = {"id": id, "ingredient_id": definition.id, "name": definition.name, "category": definition.category, "subcategory": definition.subcategory, "quality": definition.quality,
		"amount": float(args.get("amount", 1)), "batch_id": batch, "shape": "whole", "fine": 0.0, "temperature_c": float(definition.temperature_c), "texture": definition.texture.duplicate(true), "flavor": flavor, "aroma": definition.aroma.duplicate(true), "special": definition.special.duplicate(), "region": definition.region.duplicate(), "history": [], "heat_dose": 0.0, "exposure_sec": 0.0, "reaction_exposure": {}, "reactions": []}
	_ingredients[id].local_id = "ingredient_%d" % _instance_counter
	var pot: float = _batches[batch].temperature_c
	if pot > float(_config.rules.room_temperature_c):
		_ingredients[id].temperature_c = maxf(float(definition.temperature_c), float(definition.temperature_c) + (pot - float(definition.temperature_c)) * float(_config.rules.preheat_transfer))
	var consumption: Dictionary = {"instance_id": id, "local_id": _ingredients[id].local_id, "ingredient_id": definition.id, "amount": float(args.get("amount", 1)), "batch_id": batch}
	_consumed.append(consumption)
	_events.append({"type": "ingredient_consumed", "data": consumption.duplicate(true)})
	return id

func _cut(id: String, shape: String, quality: float) -> void:
	var item: Dictionary = _ingredients[id]
	var old: float = item.fine
	var fine: float = _config.cut_shapes[shape].fine
	for taste: int in range(7):
		for slot: int in [0, 2]:
			var gain: float = _config.rules.cut_release_front if slot == 0 else _config.rules.cut_release_after
			item.flavor[taste][slot] = clampf(float(item.flavor[taste][slot]) * (1 + fine * gain) / (1 + old * gain), 0, 100)
	item.fine = fine
	item.shape = shape
	item.history.append({"operation": "cut", "shape": shape, "quality": quality})
	if quality < 1:
		_recovery_sec += float(_config.rules.cut_miss_delay_sec) * (1 - quality)
		var san_cost: float = 0.0
		if quality < float(_config.rules.cut_injury_quality_threshold) and _prepared_random < float(_config.rules.cut_injury_probability):
			san_cost = float(_config.rules.cut_miss_san_cost)
			_san = maxf(0, _san - san_cost)
			_san_spent += san_cost
		_events.append({"type": "cut_mistake", "instance_id": id, "delay_sec": _recovery_sec, "san_cost": san_cost})

func _heat(batch: String, kind: String, dose: float, elapsed: float) -> void:
	var rules: Dictionary = _config.rules
	for item: Dictionary in _members(batch):
		var previous: float = item.heat_dose
		item.heat_dose += dose
		var ceiling: float = rules.boil_max_temperature_c if kind == "boil" else rules.max_temperature_c
		item.temperature_c = minf(ceiling, float(item.temperature_c) + dose * float(rules.degrees_per_heat_dose))
		for taste: int in range(7):
			for slot: int in range(4):
				var value: float = float(item.flavor[taste][slot]) + float(rules.heat_taste_delta[taste]) * dose
				if slot == 0: value *= exp(-dose * float(rules.heat_front_loss_per_dose))
				if slot == 2: value += dose * float(rules.heat_after_gain_per_dose)
				item.flavor[taste][slot] = clampf(value, 0, 100)
		var overcook: float = maxf(0, float(item.heat_dose) - float(rules.heat_overcook_dose)) - maxf(0, previous - float(rules.heat_overcook_dose))
		item.texture.A = clampf(float(item.texture.A) + dose * float(rules.heat_tenderness_per_dose) - overcook * float(rules.heat_overcook_hardness), -1, 1)
		item.texture.B = clampf(float(item.texture.B) - dose * float(rules.heat_crispness_loss_per_dose), -1, 1)
		item.history.append({"operation": kind, "heat_dose": dose, "elapsed_sec": elapsed})
	_batches[batch].temperature_c = _batch_temperature(batch)
	_react(batch, kind, elapsed)

func _react(batch: String, kind: String, elapsed: float) -> void:
	var members: Array = _members(batch)
	var tags: Array = []
	for item: Dictionary in members:
		for tag: String in item.special:
			if tag not in tags: tags.append(tag)
	for reaction: Dictionary in _config.reactions:
		if reaction.trigger != kind:
			continue
		var eligible: bool = reaction.requires_any.is_empty()
		for tag: String in reaction.requires_any:
			eligible = eligible or tag in tags
		for tag: String in reaction.requires_all:
			eligible = eligible and tag in tags
		if not eligible:
			continue
		for item: Dictionary in members:
			if float(item.temperature_c) < float(reaction.min_temperature):
				continue
			item.reaction_exposure[reaction.id] = float(item.reaction_exposure.get(reaction.id, 0)) + elapsed
			if float(item.reaction_exposure[reaction.id]) >= float(reaction.min_duration):
				_apply_reaction(item, reaction)

func _apply_reaction(item: Dictionary, reaction: Dictionary) -> void:
	if reaction.id in item.reactions:
		return
	if reaction.trigger == "exposure" and "cuttable" not in item.special:
		return
	item.reactions.append(reaction.id)
	for taste: int in range(7):
		for slot: int in range(4):
			item.flavor[taste][slot] = clampf(float(item.flavor[taste][slot]) + float(reaction.flavor_delta[taste]), 0, 100)
	for tag: String in reaction.aroma:
		item.aroma[tag] = clampf(float(item.aroma.get(tag, 0)) + float(reaction.aroma[tag]), 0, 100)
	for axis: String in reaction.get("texture_delta", {}):
		item.texture[axis] = clampf(float(item.texture[axis]) + float(reaction.texture_delta[axis]), -1, 1)
	var contribution: float=float(reaction.harmony_delta) / maxf(1, float(_ingredients.size()))
	_reaction_harmony += contribution
	item.reaction_harmony_contribution=float(item.get("reaction_harmony_contribution",0))+contribution
	item.history.append({"reaction": reaction.id})
	_events.append({"type": "reaction", "reaction_id": reaction.id, "instance_id": item.id})

func _start_fermentation(batch: String) -> void:
	var members: Array = _members(batch)
	var tags: Array = []
	for item: Dictionary in members:
		for tag: String in item.special:
			if tag not in tags: tags.append(tag)
	for reaction: Dictionary in _config.reactions:
		if reaction.trigger != "ferment": continue
		var eligible: bool = reaction.requires_any.is_empty()
		for tag: String in reaction.requires_any: eligible = eligible or tag in tags
		for tag: String in reaction.requires_all: eligible = eligible and tag in tags
		if not eligible: continue
		for item: Dictionary in members:
			if reaction.id in item.reactions: continue
			var key: String = item.id + ":" + reaction.id
			_fermenting[key] = {"instance_id": item.id, "reaction_id": reaction.id, "name": reaction.name, "elapsed_sec": float(item.reaction_exposure.get(reaction.id, 0)), "required_sec": float(reaction.min_duration), "remaining_sec": maxf(0, float(reaction.min_duration) - float(item.reaction_exposure.get(reaction.id, 0)))}

func _advance_fermentation(delta: float, starting_temperatures: Dictionary) -> void:
	var finished: Array = []
	for key: String in _fermenting:
		var job: Dictionary = _fermenting[key]
		var item: Dictionary = _ingredients[job.instance_id]
		for reaction: Dictionary in _config.reactions:
			if reaction.id != job.reaction_id: continue
			if reaction.id in item.reactions:
				finished.append(key)
				break
			item.reaction_exposure[reaction.id] = float(item.reaction_exposure.get(reaction.id, 0)) + _eligible_time(float(starting_temperatures.get(item.id, item.temperature_c)), float(item.temperature_c), float(reaction.min_temperature), delta)
			job.elapsed_sec = float(item.reaction_exposure.get(reaction.id, 0))
			job.remaining_sec = maxf(0, float(reaction.min_duration) - float(job.elapsed_sec))
			if job.remaining_sec <= .000001:
				_apply_reaction(item, reaction)
				finished.append(key)
	for key: String in finished: _fermenting.erase(key)

func _eligible_time(start: float, end: float, threshold: float, delta: float) -> float:
	if start >= threshold and end >= threshold: return delta
	if start < threshold and end < threshold: return 0.0
	if delta <= 0: return 0.0
	var room: float = _config.rules.room_temperature_c
	var ratio: float = (threshold - room) / (start - room)
	if ratio <= 0: return delta if end >= threshold else 0.0
	var crossing: float = clampf(-float(_config.rules.cooling_tau_sec) * log(ratio), 0, delta)
	return delta - crossing if end >= threshold else crossing

func _apply_plating_timing(result: Dictionary) -> void:
	var reason: String = str(result.get("reason", ""))
	var factor: float = 1.0
	var extra_heat: float = 0.0
	if reason in ["EARLY_PRESS", "EARLY_RELEASE"]: factor = _config.rules.plate_early_aroma_factor
	elif reason in ["LATE_PRESS", "OVERCHARGED"]: extra_heat = _config.rules.plate_late_heat_dose
	elif reason == "TIMEOUT":
		factor = _config.rules.plate_miss_aroma_factor
		extra_heat = _config.rules.plate_late_heat_dose
	if factor < 1:
		for item: Dictionary in _ingredients.values():
			for tag: String in item.aroma: item.aroma[tag] = float(item.aroma[tag]) * factor
	if extra_heat > 0:
		for batch: String in _batches:
			if not _members(batch).is_empty(): _heat(batch, "heat", extra_heat, 0.0)
	if factor < 1 or extra_heat > 0:
		_events.append({"type": "plating_timing", "reason": reason, "aroma_factor": factor, "extra_heat_dose": extra_heat})

func _derive() -> Dictionary:
	var rules: Dictionary = _config.rules
	var flavor: Array = _matrix()
	var texture: Dictionary = {"A": 0.0, "B": 0.0, "C": 0.0}
	var aroma: Dictionary = {}
	var temperature: float = 0.0
	var quantity: float = 0.0
	var ingredient_quality: float = 0.0
	for item: Dictionary in _ingredients.values():
		var amount: float = item.amount
		quantity += amount
		ingredient_quality += float(item.quality) * amount
		temperature += float(item.temperature_c) * amount
		for taste: int in range(7):
			for slot: int in range(4):
				flavor[taste][slot] += float(item.flavor[taste][slot]) * amount
		for axis: String in texture:
			texture[axis] += float(item.texture[axis]) * amount
		for tag: String in item.aroma:
			aroma[tag] = float(aroma.get(tag, 0)) + float(item.aroma[tag]) * amount
	if quantity > 0:
		temperature /= quantity
		ingredient_quality /= quantity
		for taste: int in range(7):
			for slot: int in range(4):
				flavor[taste][slot] /= quantity
		for axis: String in texture:
			texture[axis] /= quantity
		for tag: String in aroma:
			aroma[tag] = clampf(float(aroma[tag]) / quantity, 0, 100)
	else:
		temperature = rules.room_temperature_c
	var band: Dictionary = rules.temperature_bands[2]
	if temperature < float(rules.temperature_bands[0].max_c):
		band = rules.temperature_bands[0]
	elif temperature <= float(rules.temperature_bands[1].max_c):
		band = rules.temperature_bands[1]
	for taste: int in range(7):
		for slot: int in range(4):
			flavor[taste][slot] = clampf(float(flavor[taste][slot]) * float(band.taste_factors[taste]) * float(band.slot_factors[slot]), 0, 100)
	var missing: Array = []
	for requirement: Dictionary in _recipe.required_ingredients:
		var matching_amount: float = 0.0
		for item: Dictionary in _ingredients.values():
			if _matches_requirement(item, requirement):
				matching_amount += float(item.amount)
		if matching_amount + .000001 < float(requirement.min_amount):
			missing.append("ingredient:" + requirement.id)
	for kind: String in _recipe.required_steps:
		var found: bool = false
		for step: Dictionary in _steps:
			found = found or step.operation == kind
		if not found: missing.append("step:" + kind)
	var weighted: float = 0.0
	var total_weight: float = 0.0
	var counts: Dictionary = {}
	for step: Dictionary in _steps:
		var weight: float = _weight(step.operation)
		weighted += float(step.quality) * weight
		total_weight += weight
		counts[step.operation] = int(counts.get(step.operation, 0)) + 1
	var modules: Dictionary = module_scores()
	if _document_rules:
		weighted = 0; total_weight = 0
		for value: Dictionary in modules.values():
			weighted += float(value.quality)*float(value.weight); total_weight += float(value.weight)
	var quality: float = 100.0 * weighted / total_weight if total_weight > 0 else 0.0
	if total_weight > 0:
		quality = minf(100, quality + ingredient_quality * float(rules.quality_bonus_max))
	var extra_steps: int = 0
	for kind: String in counts:
		var recommended_count: int = _recipe.recommended_steps.count(kind)
		if _document_rules:
			recommended_count = 1 if kind == "cut" else 0
			for definition: Dictionary in _config.pc_operations.document_sheets.values():
				var count: int = 0
				for group: Dictionary in definition.groups.values():
					if group.operation == kind: count += 1
				recommended_count = maxi(recommended_count,count)
		extra_steps += maxi(0, int(counts[kind]) - recommended_count)
	var extras: int = 0
	for item: Dictionary in _ingredients.values():
		if item.ingredient_id not in _recipe.allowed_ingredients:
			extras += 1
	var reasons: Array = []
	for step: Dictionary in _steps:
		if _document_rules: continue
		if float(step.quality) < 1 and total_weight > 0:
			var loss: float = (1 - float(step.quality)) * _weight(step.operation) * 100 / total_weight
			reasons.append(_reason("QTE_" + step.operation, _config.operations[step.operation].name + "操作品质", loss))
	if _document_rules and total_weight > 0:
		for module: String in modules:
			var value: Dictionary = modules[module]
			if value.quality < 1 and value.weight > 0: reasons.append(_reason("QTE_"+module,module+"操作品质",(1-float(value.quality))*float(value.weight)*100/total_weight))
	if extra_steps > 0:
		var loss: float = extra_steps * float(rules.extra_step_penalty)
		quality -= loss
		reasons.append(_reason("EXTRA_STEPS", "%d次额外工序" % extra_steps, loss))
	if extras > 0:
		var loss: float = extras * float(rules.extra_ingredient_penalty)
		quality -= loss
		reasons.append(_reason("EXTRA_INGREDIENTS", "%d份配方外食材" % extras, loss))
	quality = maxf(0, quality)
	var dominant: Array = []
	var compound: Array = []
	var names: Array = ["酸", "甜", "苦", "辣", "咸", "鲜", "麻"]
	var maximum: float = 0.0
	for taste: int in range(7): maximum = maxf(maximum, float(flavor[taste][1]))
	var active: Array = []
	for taste: int in range(7):
		var strength: float = flavor[taste][1]
		if maximum > float(rules.dominant_epsilon) and absf(strength - maximum) <= float(rules.dominant_epsilon):
			dominant.append(names[taste])
		elif strength >= float(rules.compound_threshold):
			compound.append(names[taste])
		if strength >= float(rules.compound_threshold): active.append(taste)
	var relation: float = 0.0
	for i: int in range(active.size()):
		for j: int in range(i + 1, active.size()):
			relation += float(rules.harmony_pairs.get("%d:%d" % [active[i], active[j]], 0))
	var harmony: float = rules.harmony_levels[0].score
	for level: Dictionary in rules.harmony_levels:
		if relation >= float(level.min): harmony = level.score
	harmony += _reaction_harmony
	for tag: String in _recipe.expected_aroma:
		if float(aroma.get(tag, 0)) > 0:
			harmony += float(rules.harmony_aroma_bonus)
			break
	for axis: String in _recipe.get("ideal_texture", {}):
		var target: Array = _recipe.ideal_texture[axis]
		if float(texture[axis]) >= float(target[0]) and float(texture[axis]) <= float(target[1]):
			harmony += float(rules.harmony_texture_bonus)
	for tag: String in rules.negative_aromas:
		if float(aroma.get(tag, 0)) > 0:
			harmony -= float(rules.negative_aroma_penalty)
			reasons.append(_reason("NEGATIVE_AROMA", "出现负向香味：" + tag, float(rules.negative_aroma_penalty)))
	if not missing.is_empty():
		reasons.append(_reason("MISSING_REQUIRED", "菜谱必需项缺失：" + ", ".join(missing), quality * (1 - float(rules.missing_required_multiplier))))
		quality *= float(rules.missing_required_multiplier)
	var has_aroma: bool = false
	for intensity: float in aroma.values(): has_aroma = has_aroma or intensity > 0
	if _recipe.expects_aroma and not has_aroma:
		reasons.append(_reason("NO_AROMA", "菜谱期待香气但完全无香", quality * (1 - float(rules.no_aroma_quality_multiplier))))
		quality *= float(rules.no_aroma_quality_multiplier)
		harmony -= float(rules.no_aroma_harmony_penalty)
	if _recipe.is_custom:
		quality = minf(quality, float(rules.custom_completion_cap))
	return {"attributes": {"flavor": flavor, "temperature_c": temperature, "aroma": aroma, "texture": texture, "completion": clampf(quality, 0, 100), "harmony": clampf(harmony, 0, 100), "dominant": dominant, "compound": compound}, "missing": missing, "reasons": reasons}

func snapshot() -> Dictionary:
	var derived: Dictionary = _derive()
	var plan_ingredients: Array = []
	for item: Dictionary in _consumed:
		plan_ingredients.append({"local_id": item.local_id, "ingredient_id": item.ingredient_id, "amount": item.amount, "batch_id": item.batch_id})
	return {"schema_version": 3, "scope": "COOKING_SYSTEM", "session_id": _id, "generation": _generation, "revision": _revision,
		"recipe_id": _recipe.id, "recipe_version": _recipe.version, "recipe_name": "失败的菜品" if _recipe.get("failed_dish",false) and _state in ["plated","delivered"] else _recipe.name, "failed_dish":bool(_recipe.get("failed_dish",false)), "is_custom": _recipe.is_custom, "recipe": _recipe.duplicate(true),
		"state": _state, "operation_id": _operation_id, "pending_operation": _pending.get("operation", ""), "ingredients": _ingredients.duplicate(true), "batches": _batches.duplicate(true),
		"pending_operations": _jobs.duplicate(true), "pc_controls": _pc_controls,
		"steps": _steps.duplicate(true), "history": _history.duplicate(true), "plating": _plating.duplicate(true), "events": _events.duplicate(true),
		"dish_attributes": derived.attributes, "missing_required": derived.missing, "base_reasons": derived.reasons, "scoring_rules": _config.scoring_rules.duplicate(true),
		"container": _container, "san_context": {"current": _san, "window_multiplier": _san_multiplier()}, "san_spent": _san_spent, "variant_id": _variant_id,
		"recovery_sec": _recovery_sec,
		"plating_dragging": not _dragged_piece.is_empty(), "fermentations": _fermenting.values().duplicate(true), "initialization_error": _initial_error,
		"consumed_ingredients": _consumed.duplicate(true), "dish_id": _dish_id(), "custom_plan": {"schema_version": (3 if _plan.any(func(step:Dictionary)->bool:return step.parameters.has("amounts")) else 2) if _pc_controls else 1, "recipe_id": _recipe.id, "ingredients": plan_ingredients, "operations": _plan.duplicate(true)}}

func _deliver() -> void:
	var eligible: bool = _variant_eligible()
	var cost: float = _recipe.san_cost.amount
	if eligible:
		var draw: float = _prepared_random
		var cumulative: float = 0.0
		for candidate: Dictionary in _config.variants:
			if candidate.id not in _recipe.variant_ids: continue
			cumulative += float(candidate.probability)
			if draw < cumulative or (float(candidate.probability) >= 1 and draw == 1):
				_variant_id = candidate.id
				cost = candidate.san_cost.amount
				for item: Dictionary in _ingredients.values():
					for taste: int in range(7):
						for slot: int in range(4):
							item.flavor[taste][slot] = clampf(float(item.flavor[taste][slot]) + float(candidate.flavor_delta[taste]), 0, 100)
					for tag: String in candidate.aroma:
						item.aroma[tag] = clampf(float(item.aroma.get(tag, 0)) + float(candidate.aroma[tag]), 0, 100)
				_events.append({"type": "variant_unlocked", "variant_id": _variant_id, "dish_id": _dish_id()})
				break
		_events.append({"type": "variant_roll", "draw": draw, "variant_id": _variant_id})
	_san_spent += cost
	_events.append({"type": "san_cost", "event": "deliver", "amount": cost, "dish_id": _dish_id()})
	_events.append({"type": "dish_delivered", "dish_id": _dish_id(), "variant_id": _variant_id, "recipe_id": _recipe.id})
	if _recipe.is_custom:
		_recognize_presets()
	_state = "delivered"

func _variant_eligible() -> bool:
	var all_perfect: bool = not _steps.is_empty()
	for step: Dictionary in _steps:
		all_perfect = all_perfect and float(step.quality) >= float(_config.rules.perfect_grade_threshold)
	return _san < 30 and all_perfect and _derive().missing.is_empty() and not _recipe.variant_ids.is_empty()

func _prepare_random() -> TDOutcome:
	var value: Variant = _random.call("unit")
	if not _finite(value, 0, 1): return _error("INVALID_RANDOM", "业务随机源必须返回[0,1]内有限数。")
	_prepared_random = float(value)
	return TDOutcome.new(true)

func _recognize_presets() -> void:
	var attrs: Dictionary = _derive().attributes
	for candidate: Dictionary in _config.recipes:
		if candidate.is_custom or candidate.scope == "TEST_ONLY": continue
		var qualifies: bool = true
		for requirement: Dictionary in candidate.required_ingredients:
			var amount: float = 0.0
			for item: Dictionary in _ingredients.values():
				if _matches_requirement(item, requirement):
					amount += float(item.amount)
			qualifies = qualifies and amount >= float(requirement.min_amount)
		for kind: String in candidate.required_steps:
			var found: bool = false
			for step: Dictionary in _steps: found = found or step.operation == kind
			qualifies = qualifies and found
		qualifies = qualifies and float(attrs.temperature_c) >= float(candidate.ideal_temperature[0]) and float(attrs.temperature_c) <= float(candidate.ideal_temperature[1])
		for target: Dictionary in candidate.ideal_flavor:
			var value: float = attrs.flavor[int(target.taste)][int(target.slot)]
			qualifies = qualifies and value >= float(target.min) and value <= float(target.max)
		for axis: String in candidate.ideal_texture:
			qualifies = qualifies and float(attrs.texture[axis]) >= float(candidate.ideal_texture[axis][0]) and float(attrs.texture[axis]) <= float(candidate.ideal_texture[axis][1])
		for tag: String in candidate.expected_aroma:
			qualifies = qualifies and float(attrs.aroma.get(tag, 0)) > 0
		for tag: String in candidate.get("required_regions", []):
			var found: bool = false
			for item: Dictionary in _ingredients.values(): found = found or tag in item.region
			qualifies = qualifies and found
		if qualifies:
			_events.append({"type": "preset_recognized", "recipe_id": candidate.id, "dish_id": _dish_id()})

func _matches_requirement(item: Dictionary, requirement: Dictionary) -> bool:
	var matches: bool = item.ingredient_id == requirement.id
	if not matches and requirement.has("substitute_category"):
		matches = item.category == requirement.substitute_category
		if requirement.has("substitute_subcategory"):
			matches = matches and item.subcategory == requirement.substitute_subcategory
	return matches and float(item.fine) >= float(requirement.min_fine) and float(item.fine) <= float(requirement.max_fine) and float(item.heat_dose) >= float(requirement.get("min_heat_dose", 0))

func _qte_config(kind: String, args: Dictionary = {}) -> Dictionary:
	var value: Dictionary = _config.qtes[_config.operations[kind].qte].duplicate(true)
	if _pc_controls:
		value = _config.pc_operations.modules["oil" if kind == "season" and args.get("mode") == "common" else kind].duplicate(true)
		if kind == "cut": value.beats = args.get("beats", 2)
		if kind == "season" and args.has("sequence"):
			value.sequence = []
			for ingredient: String in args.sequence: value.sequence.append("spice:"+ingredient)
	var factor: float = _san_multiplier()
	for field: String in ["perfect_sec", "good_sec", "good_margin_sec"]:
		if value.has(field): value[field] = float(value[field]) * factor
	if value.kind == "charge":
		var middle: float = (float(value.target_min_sec) + float(value.target_max_sec)) * .5
		var half: float = (float(value.target_max_sec) - float(value.target_min_sec)) * .5 * factor
		value.target_min_sec = middle - half
		value.target_max_sec = middle + half
	if value.kind == "maintain":
		var middle: float = (float(value.target_min) + float(value.target_max)) * .5
		var half: float = (float(value.target_max) - float(value.target_min)) * .5 * factor
		value.target_min = middle - half
		value.target_max = middle + half
	if value.kind == "sequence" and not value.get("on_beat", false): value.timeout_sec = float(value.timeout_sec) * factor
	value.san_multiplier = factor
	return value

func _weight(kind: String) -> float:
	return float(_config.pc_operations.weights.get(kind, 1)) if _pc_controls else float(_config.operations[kind].quality_weight)

func _parallel_allowed(kind: String) -> bool:
	if not _pc_controls or _jobs.size() != 1: return false
	var other: String = _jobs.values()[0].operation
	return (kind in ["heat", "boil"] and other in ["stir", "season", "starch"]) or (other in ["heat", "boil"] and kind in ["stir", "season", "starch"])

func _cut_from_hits(id: String, directions: Array, quality: float) -> void:
	var item: Dictionary = _ingredients[id]
	var previous: Array = item.get("cut_directions", []).duplicate()
	previous.append_array(directions)
	var count: int = previous.size()
	var shape: String = "whole"
	if count == 1: shape = "slice"
	elif count == 2: shape = "strip" if previous[0] == previous[1] else "chunk"
	elif count >= 3: shape = "dice"
	var old: float = item.fine
	var fine: float = minf(1, float(count) / float(_config.pc_operations.max_fine_steps))
	var diagonal: float = 1 + float(previous.count(2)) / maxf(1, count) * float(_config.pc_operations.diagonal_release_bonus)
	var old_diagonal: float = float(item.get("cut_release_factor", 1))
	for taste: int in 7:
		for slot: int in [0, 2]:
			var gain: float = _config.rules.cut_release_front if slot == 0 else _config.rules.cut_release_after
			item.flavor[taste][slot] = clampf(float(item.flavor[taste][slot]) * (1 + fine * gain) / (1 + old * gain) * diagonal / old_diagonal, 0, 100)
	item.fine = fine; item.shape = shape; item.cut_directions = previous; item.cut_release_factor = diagonal
	item.history.append({"operation":"cut", "shape":shape, "quality":quality, "successful_directions":directions.duplicate()})
	if quality < 1:
		_recovery_sec += float(_config.rules.cut_miss_delay_sec) * (1 - quality)
		if quality < float(_config.rules.cut_injury_quality_threshold) and _prepared_random < float(_config.rules.cut_injury_probability):
			var cost: float = float(_config.rules.cut_miss_san_cost)
			_san = maxf(0, _san - cost); _san_spent += cost
			item.cut_san_spent=float(item.get("cut_san_spent",0))+cost
		_events.append({"type":"cut_mistake", "instance_id":id, "delay_sec":_recovery_sec})

func _validate_season_result(values: Dictionary, args: Dictionary) -> TDOutcome:
	if not values.get("actual_actions") is Array or values.actual_actions.size() > (32 if values.get("free_seasoning",false) else 5): return _error("INVALID_RESULT")
	var totals: Dictionary = {}
	for item: Dictionary in _ingredients.values(): totals[item.ingredient_id] = float(totals.get(item.ingredient_id, 0)) + float(item.amount)
	if _ingredients.size() + values.actual_actions.size() > int(_config.rules.maximum_instances): return _error("INSTANCE_LIMIT")
	var seen: Dictionary = {}
	for actual: Variant in values.actual_actions:
		if not actual is Dictionary or actual.get("action") not in _config.pc_operations.modules.season.allowed_actions or not _finite(actual.get("beat_index"), 0, 31 if values.get("free_seasoning",false) else 4) or int(actual.beat_index) != actual.beat_index or seen.has(actual.beat_index): return _error("INVALID_RESULT")
		seen[actual.beat_index] = true
		var id: String = str(actual.action).trim_prefix("spice:")
		var amount: Variant = actual.get("amount",args.get("amount",.1))
		if not _finite(amount,.001,float(_definitions[id].max_amount)): return _error("INVALID_RESULT")
		if actual.has("amount") and (not _finite(actual.get("held_sec"),0,20 if values.get("free_seasoning",false) else 6) or not is_equal_approx(float(amount)*1000,roundf(float(amount)*1000))): return _error("INVALID_RESULT")
		if actual.has("amount"):
			if not _finite(values.get("pour_rate_per_sec"),.01,1) or not is_equal_approx(float(amount),roundi(float(actual.held_sec)*float(values.pour_rate_per_sec)*1000)/1000.0): return _error("INVALID_RESULT")
		totals[id] = float(totals.get(id, 0)) + float(amount)
		if totals[id] > float(_definitions[id].max_amount): return _error("AMOUNT_LIMIT")
	return TDOutcome.new(true)

func _season_quality(id: String, quality: float, order: int) -> void:
	var seasoning: Dictionary = _ingredients[id]
	for taste: int in 7:
		seasoning.flavor[taste][0] = minf(100, float(seasoning.flavor[taste][0]) * (1 + (1 - quality) * float(_config.rules.season_error_overpour)))
		if _pc_controls: seasoning.flavor[taste][1] *= 1.0 - .05 * order

func transfer_to(destination: TDCookingModel, instance_id: String, transfer_id: String) -> TDOutcome:
	if transfer_id.is_empty(): return _error("INVALID_ID")
	if _transfers.has(transfer_id): return _error("ALREADY_TRANSFERRED")
	if destination == null or destination == self: return _error("INVALID_TARGET")
	if _state != "preparing" or destination._state != "preparing" or not _jobs.is_empty() or not destination._jobs.is_empty(): return _error("BUSY")
	if not _ingredients.has(instance_id): return _error("INVALID_TARGET")
	if not is_cold() or not destination.is_cold(): return _error("COOKING_STARTED")
	var item: Dictionary = _ingredients[instance_id]
	if destination._ingredients.has(instance_id) or destination._transfers.has(transfer_id): return _error("ALREADY_TRANSFERRED")
	if not destination._definitions.has(item.ingredient_id) or destination._definitions[item.ingredient_id] != _definitions[item.ingredient_id]: return _error("INCOMPATIBLE_CONTENT")
	var check := destination._validate("add", {"ingredient_id":item.ingredient_id, "amount":item.amount, "batch_id":"main"})
	if not check.ok: return check
	# All gates precede either mutation. The runtime object is moved once; templates stay untouched.
	var before: Dictionary = destination._derive().attributes
	var moved: Dictionary = item.duplicate(true)
	destination._instance_counter += 1
	moved.local_id = "ingredient_%d" % destination._instance_counter
	moved.batch_id = "main"
	var pot: float = destination._batches.main.temperature_c
	if pot > float(_config.rules.room_temperature_c): moved.temperature_c = maxf(float(moved.temperature_c),float(moved.temperature_c)+(pot-float(moved.temperature_c))*float(_config.rules.preheat_transfer))
	destination._ingredients[instance_id] = moved
	var entry: Dictionary = {"instance_id":instance_id,"local_id":moved.local_id,"ingredient_id":moved.ingredient_id,"amount":moved.amount,"batch_id":"main"}
	destination._consumed.append(entry)
	destination._plan.append({"operation":"add","parameters":{"ingredient_id":moved.ingredient_id,"amount":moved.amount,"batch_id":"main","local_id":moved.local_id}})
	for step: Dictionary in _steps.filter(func(s:Dictionary)->bool:return s.parameters.get("instance_id")==instance_id):
		destination._steps.append(step.duplicate(true))
		if step.operation == "cut": destination._plan.append({"operation":"cut","parameters":{"ingredient_id":moved.ingredient_id,"target_local_id":moved.local_id,"batch_id":"main","shape":moved.shape,"beats":step.parameters.get("beats",2)}})
	destination._history.append_array(_history.filter(func(h:Dictionary)->bool:return h.parameters.get("instance_id")==instance_id).duplicate(true))
	var cost: float=float(item.get("cut_san_spent",0))
	destination._san=maxf(0,destination._san-cost); destination._san_spent+=cost
	_san_spent=maxf(0,_san_spent-cost); _san=minf(100,_san+cost)
	var harmony: float=float(item.get("reaction_harmony_contribution",0))
	destination._reaction_harmony+=harmony; _reaction_harmony-=harmony
	destination._events.append({"type":"ingredient_transferred","instance_id":instance_id,"transfer_id":transfer_id})
	destination._history.append({"operation":"transfer","operation_id":transfer_id,"parameters":entry,"before":before,"after":destination._derive().attributes,"result":{}})
	destination._transfers[transfer_id] = true; _transfers[transfer_id] = true
	destination._revision += 1
	var old_local: String=item.local_id
	_ingredients.erase(instance_id)
	_steps=_steps.filter(func(s:Dictionary)->bool:return s.parameters.get("instance_id")!=instance_id)
	_consumed=_consumed.filter(func(s:Dictionary)->bool:return s.instance_id!=instance_id)
	_plan=_plan.filter(func(s:Dictionary)->bool:return s.parameters.get("local_id")!=old_local and s.parameters.get("target_local_id")!=old_local)
	_history=_history.filter(func(h:Dictionary)->bool:return h.parameters.get("instance_id")!=instance_id)
	_state = "cancelled" if _ingredients.is_empty() else "preparing"; _revision += 1
	return TDOutcome.new(true, "TRANSFERRED", "", {"instance_id":instance_id})

func is_cold() -> bool:
	return _state=="preparing" and _jobs.is_empty() and not _steps.any(func(s:Dictionary)->bool:return s.operation!="cut")

func portable_data() -> TDOutcome:
	if not is_cold() or _ingredients.size()!=1: return _error("COOKING_STARTED")
	var item: Dictionary=_ingredients.values()[0]
	var cuts: Array=[]
	for step: Dictionary in _steps:
		var history: Array=item.history.filter(func(h:Dictionary)->bool:return h.get("operation")=="cut")
		var index: int=cuts.size()
		if index>=history.size(): return _error("INVALID_PORTABLE")
		cuts.append({"directions":history[index].get("successful_directions",[]).duplicate(),"quality":step.quality,"elapsed_sec":step.elapsed_sec,"operation_id":step.operation_id})
	var attributes: Dictionary={}
	for field: String in ["temperature_c","exposure_sec","reaction_exposure","reactions","flavor","texture","aroma","history"]: attributes[field]=item[field]
	return TDOutcome.new(true,"PORTABLE","",{"schema_version":1,"id":item.id,"ingredient_id":item.ingredient_id,"amount":item.amount,"cuts":cuts,"cut_san_spent":float(item.get("cut_san_spent",0)),"reaction_harmony":float(item.get("reaction_harmony_contribution",0)),"processing_state":attributes.duplicate(true)})

func restore_portable(raw: Variant) -> TDOutcome:
	if not is_cold() or not _ingredients.is_empty(): return _error("BUSY")
	if not raw is Dictionary or raw.get("schema_version")!=1 or not raw.get("id") is String or raw.id.is_empty() or not _definitions.has(raw.get("ingredient_id")) or not raw.get("cuts") is Array or raw.cuts.size()>64: return _error("INVALID_PORTABLE")
	var checked:=_validate("add",{"ingredient_id":raw.ingredient_id,"amount":raw.get("amount"),"batch_id":"main"})
	if not checked.ok: return checked
	if not _finite(raw.get("cut_san_spent",0),0,1000): return _error("INVALID_PORTABLE")
	if not _finite(raw.get("reaction_harmony",0),-1000,1000): return _error("INVALID_PORTABLE")
	for cut: Variant in raw.cuts:
		if not cut is Dictionary or not cut.get("directions") is Array or cut.directions.size()>32 or not _finite(cut.get("quality"),0,1) or not _finite(cut.get("elapsed_sec"),0,120) or not cut.get("operation_id") is String: return _error("INVALID_PORTABLE")
		for direction: Variant in cut.directions:
			if not _finite(direction,0,2) or int(direction)!=direction: return _error("INVALID_PORTABLE")
	if raw.has("processing_state") and not _valid_cold_state(raw.processing_state,raw.cuts): return _error("INVALID_PORTABLE")
	# Restore only validated raw identity and actual cut inputs, never arbitrary saved attributes.
	var generated: String=_add({"ingredient_id":raw.ingredient_id,"amount":raw.amount,"batch_id":"main"})
	var item: Dictionary=_ingredients[generated]; _ingredients.erase(generated); item.id=raw.id; _ingredients[raw.id]=item
	_consumed[0].instance_id=raw.id
	_plan.append({"operation":"add","parameters":{"ingredient_id":raw.ingredient_id,"amount":raw.amount,"batch_id":"main","local_id":item.local_id}})
	var random_before: float=_prepared_random; _prepared_random=1.0
	for cut: Dictionary in raw.cuts:
		_cut_from_hits(raw.id,cut.directions.map(func(value:Variant)->int:return int(value)),float(cut.quality))
		var args: Dictionary={"instance_id":raw.id,"batch_id":"main"}
		_steps.append({"operation":"cut","operation_id":cut.operation_id,"parameters":args,"quality":cut.quality,"grade":"Perfect" if float(cut.quality)>=float(_config.rules.perfect_grade_threshold) else "Other","elapsed_sec":cut.elapsed_sec,"module":"M1"})
		_plan.append({"operation":"cut","parameters":{"ingredient_id":raw.ingredient_id,"target_local_id":item.local_id,"batch_id":"main","shape":item.shape,"beats":cut.directions.size()}})
	_prepared_random=random_before; _recovery_sec=0
	_san_spent=float(raw.get("cut_san_spent",0)); _san=maxf(0,100-_san_spent)
	if _san_spent>0: item.cut_san_spent=_san_spent
	_reaction_harmony=float(raw.get("reaction_harmony",0))
	if not is_zero_approx(_reaction_harmony): item.reaction_harmony_contribution=_reaction_harmony
	if raw.has("processing_state"):
		var restored: Dictionary=raw.processing_state.duplicate(true)
		for field: String in restored: item[field]=restored[field]
		for entry: Dictionary in item.history:
			if entry.get("operation")=="cut": entry.successful_directions=entry.successful_directions.map(func(v:Variant)->int:return int(v))
		# Serialized values remain private and preserve exposure/reacted flavor, not just cut shape.
		_ingredients[raw.id]=item.duplicate(true)
	_revision+=1
	return TDOutcome.new(true,"RESTORED_PORTABLE")

func _valid_cold_state(value: Variant, cuts: Array) -> bool:
	if not value is Dictionary or value.size()!=8: return false
	if not _finite(value.get("temperature_c"),-100,1000) or not _finite(value.get("exposure_sec"),0,1000000000): return false
	if not value.get("flavor") is Array or value.flavor.size()!=7: return false
	for row: Variant in value.flavor:
		if not row is Array or row.size()!=4: return false
		for number: Variant in row:
			if not _finite(number,0,100): return false
	if not value.get("texture") is Dictionary or value.texture.size()!=3: return false
	for axis: String in ["A","B","C"]:
		if not _finite(value.texture.get(axis),-1,1): return false
	if not value.get("aroma") is Dictionary: return false
	for tag: Variant in value.aroma:
		if not tag is String or tag.is_empty() or not _finite(value.aroma[tag],0,100): return false
	var known: Array=_config.reactions.filter(func(r:Dictionary)->bool:return r.trigger=="exposure").map(func(r:Dictionary)->String:return r.id)
	if not value.get("reaction_exposure") is Dictionary or not value.get("reactions") is Array or not value.get("history") is Array: return false
	for id: Variant in value.reaction_exposure:
		if id not in known or not _finite(value.reaction_exposure[id],0,1000000000): return false
	var seen: Array=[]
	for id: Variant in value.reactions:
		if id not in known or id in seen: return false
		seen.append(id)
	var index: int=0
	for entry: Variant in value.history:
		if not entry is Dictionary: return false
		if entry.has("reaction"):
			if entry.reaction not in seen: return false
		elif entry.get("operation")=="cut":
			if index>=cuts.size() or not entry.get("successful_directions") is Array or entry.successful_directions.size()!=cuts[index].directions.size() or entry.get("quality")!=cuts[index].quality or entry.get("shape") not in ["whole","chunk","dice","strip","slice"]: return false
			for i: int in entry.successful_directions.size():
				if entry.successful_directions[i]!=cuts[index].directions[i]: return false
			index+=1
		else: return false
	return index==cuts.size()

func _record(kind: String, args: Dictionary, before: Dictionary, result: Dictionary) -> void:
	_history.append({"operation": kind, "operation_id": _operation_id, "parameters": args.duplicate(true), "before": before.duplicate(true), "after": _derive().attributes, "result": result.duplicate(true)})
	if kind not in ["deliver", "discard", "container", "rework"]:
		var plan_args: Dictionary = args.duplicate(true)
		if _pc_controls and kind == "season" and args.get("mode","precise") != "common":
			var count: int = result.get("actual_actions",[]).size()
			if count == 0: return
			var sequence: Array = []; var local_ids: Array = []; var amounts: Array = []
			for item: Dictionary in _consumed.slice(_consumed.size()-count):
				sequence.append(item.ingredient_id); local_ids.append(item.local_id); amounts.append(item.amount)
			var parameters: Dictionary = {"ingredient_id":sequence[0],"amount":args.get("amount",.1),"batch_id":args.get("batch_id","main"),"sequence":sequence,"local_ids":local_ids}
			if result.has("hold_durations_sec"): parameters.amounts = amounts
			_plan.append({"operation":"season","parameters":parameters})
			return
		if plan_args.has("instance_id"):
			var target: Dictionary = _ingredients[plan_args.instance_id]
			plan_args.erase("instance_id")
			plan_args.target_local_id = target.local_id
			plan_args.ingredient_id = target.ingredient_id
			plan_args.batch_id = target.batch_id
			if _pc_controls: plan_args.shape = target.shape
		if kind in ["add", "season", "starch"] and not _consumed.is_empty():
			plan_args.local_id = _consumed.back().local_id
		_plan.append({"operation": kind, "parameters": plan_args})

func _members(batch: String) -> Array:
	var values: Array = []
	for item: Dictionary in _ingredients.values():
		if item.batch_id == batch: values.append(item)
	return values

func _ensure_batch(id: String) -> void:
	if not _batches.has(id): _batches[id] = {"temperature_c": float(_config.rules.room_temperature_c)}

func _batch_temperature(id: String) -> float:
	var total: float = 0.0
	var amount: float = 0.0
	for item: Dictionary in _members(id):
		total += float(item.temperature_c) * float(item.amount)
		amount += float(item.amount)
	return total / amount if amount > 0 else float(_batches.get(id, {}).get("temperature_c", _config.rules.room_temperature_c))

func _san_multiplier() -> float:
	return 1.0 if _san >= 60 else .6 + .4 * _san / 60.0

func _dish_id() -> String:
	return "%s:%d:dish" % [_id, _generation]

func _reason(code: String, label: String, loss: float) -> Dictionary:
	return {"code": code, "label": label, "message": "%s；基础品质影响 %.1f" % [label, loss], "penalty": loss}

func _error(code: String, message: String = "") -> TDOutcome:
	return TDOutcome.new(false, code, message)

func _finite(value: Variant, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= low and value <= high

func _matrix() -> Array:
	return [[0.0,0.0,0.0,0.0],[0.0,0.0,0.0,0.0],[0.0,0.0,0.0,0.0],[0.0,0.0,0.0,0.0],[0.0,0.0,0.0,0.0],[0.0,0.0,0.0,0.0],[0.0,0.0,0.0,0.0]]

func _module(kind: String, args: Dictionary) -> String:
	if kind == "season": return "M3" if args.get("mode") == "common" else "M6"
	return {"cut":"M1","preheat":"M2","stir":"M3","starch":"M3","steam":"M3","ferment":"M3","heat":"M4","boil":"M5","plate":"M7"}.get(kind,"M1")

func module_scores() -> Dictionary:
	var result: Dictionary = {}
	if not _document_rules: return result
	for step: Dictionary in _steps:
		var module: String = step.get("module",_module(step.operation,step.parameters))
		if not result.has(module): result[module] = {"sum":0.0,"count":0,"weight":float(_config.pc_operations.document_weights.get(module,0))}
		result[module].sum += float(step.quality); result[module].count += 1
	for value: Dictionary in result.values(): value.quality = float(value.sum)/int(value.count)
	return result
