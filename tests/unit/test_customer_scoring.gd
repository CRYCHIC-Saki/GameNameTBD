extends GutTest

const Scorer = preload("res://src/scoring/customer_scorer.gd")

func _dish() -> Dictionary:
	var flavor: Array = []
	for _taste: int in range(7):
		flavor.append([0.0, 0.0, 0.0, 0.0])
	flavor[1][1] = 60.0
	return {
		"schema_version": 2,
		"dish_attributes": {"flavor": flavor, "temperature_c": 62.0,
			"texture": {"A": 0.5, "B": 0.0, "C": 0.0}, "aroma": {"tomato": 30.0},
			"completion": 82.0, "harmony": 70.0},
		"ingredients": {"tomato": {"fine": 0.25, "texture": {"A": 0.4, "B": 0.0, "C": 0.0}}},
		"base_reasons": [{"code": "AROMA_WEAK", "message": "基础香味已经影响 Q/H。"}],
		"scoring_rules": {"quality_weight": 0.35, "harmony_weight": 0.25, "requirements_weight": 0.4}
	}

func _sweet(minimum: float = 50.0, maximum: float = 70.0, weight: float = 1.0) -> Dictionary:
	return {"id": "sweet", "label": "主味甜度", "kind": "flavor", "taste": 1, "slot": 1,
		"min": minimum, "max": maximum, "scale": 100.0, "weight": weight}

func test_hand_calculated_score_and_distinct_customers() -> void:
	var scorer := Scorer.new()
	var dish: Dictionary = _dish()
	var sweet: TDOutcome = scorer.evaluate(dish, {"requirements": [_sweet()]})
	var mild: TDOutcome = scorer.evaluate(dish, {"requirements": [_sweet(0.0, 10.0)]})
	assert_true(sweet.ok)
	assert_almost_eq(sweet.data["satisfaction"], 86.2, 0.00001)
	assert_almost_eq(mild.data["deviation"], 50.0, 0.00001)
	assert_almost_eq(mild.data["satisfaction"], 66.2, 0.00001)
	assert_eq(mild.data["reasons"][-1]["source"], "requirements")
	assert_almost_eq(mild.data["reasons"][-1]["penalty"], 20.0, 0.00001)

func test_playability_grace_reduces_small_errors_but_preserves_preferences() -> void:
	var dish:=_dish();dish.scoring_rules["deviation_grace"]=8.0;dish.scoring_rules["deviation_factor"]=.75
	var before:=dish.duplicate(true);var scorer:=Scorer.new()
	assert_almost_eq(float(scorer.evaluate(dish,{"requirements":[_sweet(0,52)]}).data.satisfaction),86.2,.00001)
	var strong:=scorer.evaluate(dish,{"requirements":[_sweet(0,10)]})
	assert_almost_eq(float(strong.data.satisfaction),73.6,.00001)
	assert_almost_eq(float(strong.data.requirements[0].raw_deviation),50.0,.00001)
	assert_almost_eq(float(scorer.evaluate(dish,{"requirements":[]}).data.satisfaction),86.2,.00001)
	assert_eq(dish,before)

func test_only_declared_dimensions_contribute() -> void:
	var scorer := Scorer.new()
	var first: Dictionary = _dish()
	var second: Dictionary = first.duplicate(true)
	second["dish_attributes"]["temperature_c"] = 10.0
	second["dish_attributes"]["aroma"] = {}
	second["dish_attributes"]["flavor"][0][0] = 100.0
	second["dish_attributes"]["texture"]["A"] = -1.0
	var customer: Dictionary = {"requirements": [_sweet()]}
	assert_eq(scorer.evaluate(first, customer).data["satisfaction"], scorer.evaluate(second, customer).data["satisfaction"])

func test_no_requirements_and_all_zero_weights_are_zero_deviation() -> void:
	var scorer := Scorer.new()
	var none: TDOutcome = scorer.evaluate(_dish(), {"requirements": []})
	var zero: TDOutcome = scorer.evaluate(_dish(), {"requirements": [_sweet(0.0, 1.0, 0.0)]})
	assert_true(none.ok)
	assert_true(zero.ok)
	assert_eq(none.data["deviation"], 0.0)
	assert_eq(zero.data["deviation"], 0.0)
	assert_almost_eq(zero.data["satisfaction"], 86.2, 0.00001)
	assert_eq(zero.data["requirements"][0]["normalized_weight"], 0.0)

func test_weighted_interval_bounds_and_saturation() -> void:
	var scorer := Scorer.new()
	var requirements: Array = [_sweet(0.0, 10.0, 3.0),
		{"id": "temp", "label": "热度", "kind": "temperature", "min": 62.0, "max": 65.0, "scale": 100.0, "weight": 1.0}]
	var result: TDOutcome = scorer.evaluate(_dish(), {"requirements": requirements})
	assert_almost_eq(result.data["deviation"], 37.5, 0.00001)
	assert_almost_eq(result.data["satisfaction"], 71.2, 0.00001)
	requirements[0]["scale"] = 0.1
	result = scorer.evaluate(_dish(), {"requirements": requirements})
	assert_almost_eq(result.data["deviation"], 75.0, 0.00001)

func test_fine_ingredient_texture_and_aroma_are_supported() -> void:
	var scorer := Scorer.new()
	var requirements: Array = [
		{"id": "fine", "label": "大块", "kind": "fine", "ingredient_id": "tomato", "max": 0.5, "weight": 1.0, "scale": 1.0},
		{"id": "tender", "label": "番茄口感", "kind": "texture", "ingredient_id": "tomato", "axis": "A", "min": 0.4, "weight": 1.0, "scale": 2.0},
		{"id": "scent", "label": "清香", "kind": "aroma", "tag": "tomato", "min": 60.0, "weight": 2.0}]
	var result: TDOutcome = scorer.evaluate(_dish(), {"requirements": requirements})
	assert_true(result.ok)
	assert_almost_eq(result.data["deviation"], 25.0, 0.00001)
	requirements[2]["tag"] = "absent"
	result = scorer.evaluate(_dish(), {"requirements": requirements})
	assert_almost_eq(result.data["deviation"], 50.0, 0.00001)
	assert_true(result.data["requirements"][2]["missing"])
	requirements = [{"id": "egg", "label": "鸡蛋要嫩", "kind": "texture", "ingredient_id": "egg", "axis": "A", "min": 0.5, "weight": 1.0}]
	result = scorer.evaluate(_dish(), {"requirements": requirements})
	assert_true(result.ok)
	assert_eq(result.data["deviation"], 100.0)

func test_invalid_requirements_are_rejected_even_at_zero_weight() -> void:
	var scorer := Scorer.new()
	for malformed: Dictionary in [
		_sweet(0.0, 10.0, -1.0),
		{"id": "bad", "label": "缺字段", "kind": "temperature", "weight": 0.0},
		{"id": "bad", "label": "坏维度", "kind": "unknown", "min": 0.0, "weight": 0.0},
		{"id": "bad", "label": "坏范围", "kind": "temperature", "min": INF, "weight": 1.0},
		{"id": "bad", "label": "反向范围", "kind": "temperature", "min": 50.0, "max": 10.0, "weight": 1.0},
		{"id": "bad", "label": "零尺度", "kind": "temperature", "min": 0.0, "scale": 0.0, "weight": 1.0}]:
		assert_eq(scorer.evaluate(_dish(), {"requirements": [malformed]}).code, "INVALID_REQUIREMENTS")
	var bad_index: Dictionary = _sweet()
	bad_index["taste"] = 7
	assert_eq(scorer.evaluate(_dish(), {"requirements": [bad_index]}).code, "INVALID_REQUIREMENTS")
	assert_eq(scorer.evaluate(_dish(), {"requirements": [_sweet(), _sweet()]}).code, "INVALID_REQUIREMENTS")
	assert_eq(scorer.evaluate(_dish(), {}).code, "INVALID_REQUIREMENTS")

func test_invalid_dish_shape_ranges_and_nonfinite_values_are_rejected() -> void:
	var scorer := Scorer.new()
	var dish: Dictionary = _dish()
	dish["dish_attributes"]["flavor"][0].pop_back()
	assert_eq(scorer.evaluate(dish, {"requirements": []}).code, "INVALID_DISH")
	dish = _dish()
	dish["dish_attributes"]["completion"] = 101.0
	assert_eq(scorer.evaluate(dish, {"requirements": []}).code, "INVALID_DISH")
	dish = _dish()
	dish["dish_attributes"]["temperature_c"] = NAN
	assert_eq(scorer.evaluate(dish, {"requirements": []}).code, "INVALID_DISH")
	dish = _dish()
	dish["ingredients"]["tomato"]["fine"] = 2.0
	assert_eq(scorer.evaluate(dish, {"requirements": []}).code, "INVALID_DISH")
	dish = _dish()
	dish["scoring_rules"]["quality_weight"] = 0.9
	assert_eq(scorer.evaluate(dish, {"requirements": []}).code, "INVALID_DISH")

func test_requirement_target_ranges_are_validated_even_with_zero_weight() -> void:
	var scorer := Scorer.new()
	var valid: Array[Dictionary] = [
		_sweet(),
		{"id": "fine", "label": "切型", "kind": "fine", "ingredient_id": "tomato", "min": 0.0, "max": 1.0, "weight": 0.0},
		{"id": "texture", "label": "口感", "kind": "texture", "axis": "A", "min": -1.0, "max": 1.0, "weight": 0.0}]
	var lower_limits: Array[float] = [0.0, 0.0, -1.0]
	var upper_limits: Array[float] = [100.0, 1.0, 1.0]
	for index: int in range(valid.size()):
		var requirement: Dictionary = valid[index].duplicate(true)
		requirement["weight"] = 0.0
		requirement["min"] = lower_limits[index]
		requirement["max"] = upper_limits[index]
		assert_true(scorer.evaluate(_dish(), {"requirements": [requirement]}).ok)
		requirement["min"] = lower_limits[index] - 0.01
		assert_eq(scorer.evaluate(_dish(), {"requirements": [requirement]}).code, "INVALID_REQUIREMENTS")
		requirement["min"] = lower_limits[index]
		requirement["max"] = upper_limits[index] + 0.01
		assert_eq(scorer.evaluate(_dish(), {"requirements": [requirement]}).code, "INVALID_REQUIREMENTS")

func test_feedback_gives_declared_target_and_action_without_hidden_requirements() -> void:
	var scorer := Scorer.new()
	var result: TDOutcome = scorer.evaluate(_dish(), {"requirements": [_sweet(0.0, 10.0)]})
	var feedback: Dictionary = result.data["reasons"][-1]
	assert_eq(feedback["source"], "requirements")
	assert_string_contains(feedback["message"], "目标 0.00–10.00")
	assert_string_contains(feedback["message"], "减少糖量")
	assert_eq(result.data["requirements"].size(), 1)
	var no_customer_requirements: TDOutcome = scorer.evaluate(_dish(), {"requirements": []})
	for reason: Dictionary in no_customer_requirements.data["reasons"]:
		assert_eq(reason["source"], "base")
	var fine: Dictionary = {"id": "fine", "label": "要切丁", "kind": "fine", "ingredient_id": "tomato", "min": 0.8, "weight": 1.0}
	result = scorer.evaluate(_dish(), {"requirements": [fine]})
	assert_string_contains(result.data["reasons"][-1]["message"], "切得更细")

func test_scoring_is_repeatable_readonly_and_keeps_base_reasons_separate() -> void:
	var scorer := Scorer.new()
	var dish: Dictionary = _dish()
	var customer: Dictionary = {"requirements": [_sweet(0.0, 10.0)]}
	var original_dish: Dictionary = dish.duplicate(true)
	var original_customer: Dictionary = customer.duplicate(true)
	var first: TDOutcome = scorer.evaluate(dish, customer)
	var second: TDOutcome = scorer.evaluate(dish, customer)
	assert_eq(first.to_dict(), second.to_dict())
	assert_eq(dish, original_dish)
	assert_eq(customer, original_customer)
	assert_eq(first.data["reasons"][0]["source"], "base")
	assert_true(first.data["reasons"][0]["already_applied"])
	first.data["base_reasons"][0]["message"] = "外部修改"
	first.data["requirements"][0]["actual"] = -100.0
	assert_eq(dish, original_dish)
	assert_eq(customer, original_customer)
