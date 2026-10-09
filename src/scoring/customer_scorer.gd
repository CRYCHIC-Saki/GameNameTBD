class_name TDCustomerScorer
extends RefCounted

## Read-only comparison: all recipe/base-quality effects already belong to the dish.
func evaluate(dish_snapshot: Dictionary, customer: Dictionary) -> TDOutcome:
	var version: Variant = dish_snapshot.get("schema_version", 1)
	if version == 1:
		return TDOutcome.new(false, "NOT_IMPLEMENTED", "开发探针没有菜品属性，不能评分。")
	if version not in [2, 3]:
		return TDOutcome.new(false, "INVALID_DISH", "不支持的菜品版本。")
	var dish_error: String = _validate_dish(dish_snapshot)
	if not dish_error.is_empty():
		return TDOutcome.new(false, "INVALID_DISH", dish_error)
	if not customer.get("requirements") is Array:
		return TDOutcome.new(false, "INVALID_REQUIREMENTS", "requirements 必须为数组。")
	var attributes: Dictionary = dish_snapshot["dish_attributes"]
	var rules: Dictionary = dish_snapshot["scoring_rules"]
	var checked: Array[Dictionary] = []
	var seen: Dictionary = {}
	var total_weight: float = 0.0
	for value: Variant in customer["requirements"]:
		if not value is Dictionary:
			return TDOutcome.new(false, "INVALID_REQUIREMENTS", "需求条目必须为对象。")
		var requirement: Dictionary = value
		var check: TDOutcome = _check_requirement(requirement, dish_snapshot)
		if not check.ok:
			return check
		var identity: String = requirement["id"]
		if seen.has(identity):
			return TDOutcome.new(false, "INVALID_REQUIREMENTS", "需求 ID 重复：" + identity)
		seen[identity] = true
		total_weight += float(requirement["weight"])
		checked.append(check.data)
	if not is_finite(total_weight):
		return TDOutcome.new(false, "INVALID_REQUIREMENTS", "需求总权重超出有限范围。")
	var deviation: float = 0.0
	var reasons: Array[Dictionary] = []
	for value: Variant in dish_snapshot.get("base_reasons", []):
		var base: Dictionary = value
		reasons.append({
			"id": str(base.get("id", base.get("code", "base_quality"))),
			"label": str(base.get("label", base.get("message", "菜谱与基础品质"))),
			"message": str(base.get("message", base.get("label", "已计入基础 Q/H。"))),
			"penalty": 0.0, "source": "base", "already_applied": true,
			"details": base.duplicate(true)
		})
	for requirement: Dictionary in checked:
		var normalized: float = float(requirement["weight"]) / total_weight if total_weight > 0.0 else 0.0
		var contribution: float = float(requirement["deviation"]) * normalized
		deviation += contribution
		requirement["normalized_weight"] = normalized
		requirement["contribution"] = contribution
		requirement["satisfaction_penalty"] = contribution * float(rules["requirements_weight"])
		if contribution > 0.0:
			reasons.append({
				"id": requirement["id"], "label": requirement["label"],
				"penalty": requirement["satisfaction_penalty"],
				"message": str(requirement["label"]) + "：" + str(requirement["explanation"]),
				"source": "requirements", "already_applied": false
			})
	var quality: float = float(attributes["completion"])
	var harmony: float = float(attributes["harmony"])
	var satisfaction: float = clampf(
		float(rules["quality_weight"]) * quality + float(rules["harmony_weight"]) * harmony
		+ float(rules["requirements_weight"]) * (100.0 - deviation), 0.0, 100.0)
	var stars: int = 0
	for threshold: Variant in rules.get("star_thresholds", []):
		if _number_in(threshold, 0.0, 100.0) and satisfaction >= float(threshold):
			stars += 1
	return TDOutcome.new(true, "SCORED", "", {
		"stars": stars,
		"satisfaction": satisfaction, "deviation": deviation,
		"quality": quality, "harmony": harmony,
		"reasons": reasons, "requirements": checked,
		"base_reasons": dish_snapshot.get("base_reasons", []).duplicate(true)
	})

func _validate_dish(dish: Dictionary) -> String:
	if not dish.get("dish_attributes") is Dictionary or not dish.get("scoring_rules") is Dictionary:
		return "缺少菜品属性或评分参数。"
	var attributes: Dictionary = dish["dish_attributes"]
	if not _number_in(attributes.get("completion"), 0.0, 100.0) or not _number_in(attributes.get("harmony"), 0.0, 100.0):
		return "Q/H 必须为 0–100 的有限数。"
	if not _finite_number(attributes.get("temperature_c")):
		return "温度必须为有限数，单位摄氏度。"
	if not attributes.get("flavor") is Array or attributes["flavor"].size() != 7:
		return "口味必须为 7×4 矩阵。"
	for row: Variant in attributes["flavor"]:
		if not row is Array or row.size() != 4:
			return "口味必须为 7×4 矩阵。"
		for strength: Variant in row:
			if not _number_in(strength, 0.0, 100.0):
				return "口味强度必须为 0–100 的有限数。"
	if not _valid_texture(attributes.get("texture")):
		return "口感必须含 A/B/C 三轴，各轴范围 −1–1。"
	if not attributes.get("aroma") is Dictionary:
		return "香味必须为标签与强度对象。"
	for tag: Variant in attributes["aroma"]:
		if not tag is String or tag.is_empty() or not _number_in(attributes["aroma"][tag], 0.0, 100.0):
			return "香味标签非空，强度须为 0–100 的有限数。"
	if not dish.get("ingredients") is Dictionary:
		return "缺少食材处理状态。"
	for ingredient_id: Variant in dish["ingredients"]:
		var ingredient: Variant = dish["ingredients"][ingredient_id]
		if not ingredient_id is String or ingredient_id.is_empty() or not ingredient is Dictionary:
			return "食材状态必须由稳定 ID 索引。"
		if not _number_in(ingredient.get("fine"), 0.0, 1.0) or not _valid_texture(ingredient.get("texture")):
			return "食材细碎度范围为 0–1，口感需保留三轴。"
	var rules: Dictionary = dish["scoring_rules"]
	var sum: float = 0.0
	for field: String in ["quality_weight", "harmony_weight", "requirements_weight"]:
		if not _number_in(rules.get(field), 0.0, 1.0):
			return "评分权重必须为 0–1 的有限数。"
		sum += float(rules[field])
	if not is_equal_approx(sum, 1.0):
		return "评分三项权重之和必须为 1。"
	if not dish.get("base_reasons", []) is Array:
		return "基础原因必须为数组。"
	for reason: Variant in dish.get("base_reasons", []):
		if not reason is Dictionary:
			return "基础原因条目必须为对象。"
	return ""

func _check_requirement(requirement: Dictionary, dish: Dictionary) -> TDOutcome:
	for text_field: String in ["id", "label", "kind"]:
		if not requirement.get(text_field) is String or requirement[text_field].is_empty():
			return _bad_requirement("需求缺少非空 " + text_field)
	if not _finite_number(requirement.get("weight")) or float(requirement["weight"]) < 0.0:
		return _bad_requirement("需求权重必须为非负有限数。")
	var kind: String = requirement["kind"]
	for bound: String in ["min", "max"]:
		if requirement.has(bound) and not _finite_number(requirement[bound]):
			return _bad_requirement("需求区间必须为有限数。")
	var attributes: Dictionary = dish["dish_attributes"]
	var actual: float = 0.0
	var absent: bool = false
	var default_scale: float = 100.0
	match kind:
		"flavor":
			if not _index_in(requirement.get("taste"), 7) or not _index_in(requirement.get("slot"), 4):
				return _bad_requirement("口味需求索引须为 taste 0–6 / slot 0–3。")
			actual = float(attributes["flavor"][int(requirement["taste"])][int(requirement["slot"])])
		"temperature":
			actual = float(attributes["temperature_c"])
		"texture", "fine":
			var target: Dictionary = attributes
			if kind == "fine" or requirement.has("ingredient_id"):
				if not requirement.get("ingredient_id") is String or requirement["ingredient_id"].is_empty():
					return _bad_requirement("细碎度或指定食材口感需要 ingredient_id。")
				var identity: String = requirement["ingredient_id"]
				var matches: Array[Dictionary] = _matching_ingredients(dish, identity)
				if matches.is_empty():
					absent = true
				else:
					# Use the worst offending instance, so an uncut batch cannot hide in an average.
					target = matches[0]
					var worst: float = -1.0
					for item: Dictionary in matches:
						var amount: float = float(item.fine) if kind == "fine" else float(item.texture.get(requirement.get("axis", "A"), 0.0))
						var distance: float = maxf(0.0, maxf(float(requirement.get("min", amount)) - amount, amount - float(requirement.get("max", amount))))
						if distance > worst:
							worst = distance
							target = item
			if kind == "fine":
				default_scale = 1.0
				if not absent:
					actual = float(target["fine"])
			else:
				if requirement.get("axis") not in ["A", "B", "C"]:
					return _bad_requirement("口感需求 axis 必须为 A/B/C。")
				default_scale = 2.0
				if not absent:
					actual = float(target["texture"][requirement["axis"]])
		"aroma":
			if not requirement.get("tag") is String or requirement["tag"].is_empty():
				return _bad_requirement("香味需求需要非空 tag。")
			if not _number_in(requirement.get("min"), 0.0, 100.0):
				return _bad_requirement("香味最低强度必须为 0–100 的有限数。")
			absent = not attributes["aroma"].has(requirement["tag"])
			actual = float(attributes["aroma"].get(requirement["tag"], 0.0))
			default_scale = maxf(float(requirement["min"]), 1.0)
		"ingredient":
			if not requirement.get("ingredient_id") is String or requirement.ingredient_id.is_empty():
				return _bad_requirement("食材要求需要ingredient_id。")
			for item: Dictionary in _matching_ingredients(dish, requirement.ingredient_id):
				actual += float(item.get("amount", 1.0))
			default_scale = maxf(float(requirement.get("min", 1.0)), 1.0)
		"step":
			if not requirement.get("operation") is String or requirement.operation.is_empty():
				return _bad_requirement("工序要求需要operation。")
			for step: Dictionary in dish.get("steps", []):
				if step.get("operation") == requirement.operation:
					actual += 1.0
			default_scale = maxf(float(requirement.get("min", 1.0)), 1.0)
		_:
			return _bad_requirement("不支持的需求维度：" + kind)
	if not requirement.has("min") and not requirement.has("max"):
		return _bad_requirement("需求至少声明 min 或 max。")
	for bound: String in ["min", "max"]:
		if requirement.has(bound) and not _finite_number(requirement[bound]):
			return _bad_requirement("需求区间必须为有限数。")
		if requirement.has(bound):
			var boundary: float = float(requirement[bound])
			if kind in ["flavor", "aroma"] and (boundary < 0.0 or boundary > 100.0):
				return _bad_requirement("口味与香味的需求目标范围为 0–100。")
			if kind == "texture" and (boundary < -1.0 or boundary > 1.0):
				return _bad_requirement("口感的需求目标范围为 −1–1。")
			if kind == "fine" and (boundary < 0.0 or boundary > 1.0):
				return _bad_requirement("细碎度的需求目标范围为 0–1。")
	if requirement.has("min") and requirement.has("max") and float(requirement["min"]) > float(requirement["max"]):
		return _bad_requirement("需求 min 不能大于 max。")
	var scale: Variant = requirement.get("scale", default_scale)
	if not _finite_number(scale) or float(scale) <= 0.0:
		return _bad_requirement("需求 scale 必须为正有限数。")
	var distance: float = 0.0
	if requirement.has("min"):
		distance = maxf(distance, float(requirement["min"]) - actual)
	if requirement.has("max"):
		distance = maxf(distance, actual - float(requirement["max"]))
	var deviation: float = 100.0 if absent else clampf(distance / float(scale) * 100.0, 0.0, 100.0)
	var explanation: String = "实际 %.2f，目标%s；需求偏差 %.1f/100。" % [actual, _target_text(requirement), deviation]
	if absent:
		explanation = "缺少订单声明的香味，目标%s。" % _target_text(requirement) if kind == "aroma" else "缺少订单点名的食材，目标%s。" % _target_text(requirement)
	if deviation > 0.0:
		explanation += _adjustment_hint(requirement, actual, absent)
	var result: Dictionary = requirement.duplicate(true)
	result.merge({"actual": actual, "missing": absent, "deviation": deviation, "scale": float(scale), "explanation": explanation}, true)
	return TDOutcome.new(true, "VALID_REQUIREMENT", "", result)

func _target_text(requirement: Dictionary) -> String:
	var unit: String = "℃" if requirement["kind"] == "temperature" else ""
	if requirement.has("min") and requirement.has("max"):
		return " %.2f–%.2f%s" % [float(requirement["min"]), float(requirement["max"]), unit]
	if requirement.has("min"):
		return " ≥ %.2f%s" % [float(requirement["min"]), unit]
	return " ≤ %.2f%s" % [float(requirement["max"]), unit]

func _adjustment_hint(requirement: Dictionary, actual: float, absent: bool) -> String:
	var kind: String = requirement["kind"]
	if absent and kind != "aroma":
		return "下次补齐这项食材，再按订单要求加工。"
	var too_low: bool = requirement.has("min") and actual < float(requirement["min"])
	match kind:
		"flavor":
			match int(requirement["taste"]):
				1:
					return "下次增加一点糖，再观察甜味变化。" if too_low else "下次减少糖量，再观察甜味变化。"
				4:
					return "下次增加一点盐，再观察咸味变化。" if too_low else "下次减少盐量，再观察咸味变化。"
				0:
					return "下次尝试更细的酸味食材切型，观察变化。" if too_low else "下次减少酸味来源或尝试较粗切型。"
				_:
					return "下次调整调味或火候，提高这项已声明的味道。" if too_low else "下次调整调味或火候，降低这项已声明的味道。"
		"temperature":
			return "下次适当提高火力，出锅后及时交付。" if too_low else "下次降低火力，或出锅后稍等片刻再交付。"
		"fine":
			return "下次把订单点名的食材切得更细。" if too_low else "下次把订单点名的食材切得更粗。"
		"texture":
			var direction: String = "提高" if too_low else "降低"
			return "下次调整火候与加热时长，%s这项口感轴；查看工序前后变化。" % direction
		"aroma":
			return "下次调整加热与出锅时机，保留订单要求的香味。" if too_low or absent else "下次减少这项香味的来源，并查看工序变化。"
		"ingredient":
			return "下次按声明调整这项食材的份量。"
		"step":
			return "下次按声明调整这道工序的次数。"
	return ""

func _matching_ingredients(dish: Dictionary, identity: String) -> Array[Dictionary]:
	var matching: Array[Dictionary] = []
	for key: String in dish.ingredients:
		var item: Dictionary = dish.ingredients[key]
		if key == identity or item.get("ingredient_id", "") == identity:
			matching.append(item)
	return matching

func _bad_requirement(message: String) -> TDOutcome:
	return TDOutcome.new(false, "INVALID_REQUIREMENTS", message)

func _finite_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

func _number_in(value: Variant, minimum: float, maximum: float) -> bool:
	return _finite_number(value) and float(value) >= minimum and float(value) <= maximum

func _index_in(value: Variant, size: int) -> bool:
	return _finite_number(value) and float(value) == floorf(float(value)) and float(value) >= 0.0 and float(value) < size

func _valid_texture(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for axis: String in ["A", "B", "C"]:
		if not _number_in(value.get(axis), -1.0, 1.0):
			return false
	return true
