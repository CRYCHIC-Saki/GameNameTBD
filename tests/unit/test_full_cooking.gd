extends GutTest

const Catalog = preload("res://src/content/cooking_catalog.gd")

var _counter: int = 0

class FixedRandom:
	extends RefCounted
	var value: float = 0.0
	var draws: int = 0
	func unit() -> float:
		draws += 1
		return value

func _session(recipe: String = "tomato_egg", options: Dictionary = {}) -> TDCookingSession:
	var catalog := Catalog.new()
	assert_true(catalog.load_file("res://content/cooking_system.json").ok)
	return TDCookingSession.new("unit", 1, catalog.for_recipe(recipe), options)

func _op(session: TDCookingSession, kind: String, args: Dictionary = {}) -> TDOutcome:
	_counter += 1
	var snap: Dictionary = session.snapshot().to_dict()
	var request := TDRequest.new("unit", 1, "op_%d" % _counter, kind, int(snap.revision), args)
	request.schema_version = 3
	return session.begin(request)

# Explicit rule-boundary result fixture; actual input lifecycle is covered separately.
func _finish(session: TDCookingSession, quality: float = 1.0, seconds: float = 6.0) -> TDOutcome:
	var snap: Dictionary = session.snapshot().to_dict()
	return session.complete_operation(TDOutcome.new(true, "COMPLETED", "", {"schema_version": 3, "session_id": "unit", "generation": 1, "operation_id": snap.operation_id, "kind": snap.pending_operation, "status": "completed", "quality": quality, "grade": "Perfect" if quality >= .95 else "Miss", "elapsed_sec": seconds, "heat_dose": seconds * .6}))

func _add(session: TDCookingSession, id: String, batch: String = "main", amount: float = 1.0) -> String:
	var result: TDOutcome = _op(session, "add", {"ingredient_id": id, "amount": amount, "batch_id": batch})
	assert_true(result.ok, result.message)
	return str(result.data.get("instance_id", ""))

func test_instances_batches_and_templates_are_independent() -> void:
	var a := _session()
	var b := _session()
	var first: String = _add(a, "tomato", "prep")
	var second: String = _add(a, "tomato")
	assert_true(_op(a, "cut", {"instance_id": first, "shape": "dice"}).ok)
	assert_true(_finish(a).ok)
	var values: Dictionary = a.snapshot().to_dict().ingredients
	assert_eq(values[first].fine, .8)
	assert_eq(values[second].fine, 0.0)
	assert_eq(b.snapshot().to_dict().ingredients.size(), 0)
	values[first].texture.A = -1.0
	assert_ne(a.snapshot().to_dict().ingredients[first].texture.A, -1.0)

func test_illegal_order_cancel_and_duplicate_results_do_not_mutate() -> void:
	var session := _session()
	assert_false(_op(session, "heat").ok)
	var id: String = _add(session, "tomato")
	assert_true(_op(session, "cut", {"instance_id": id, "shape": "chunk"}).ok)
	assert_true(session.cancel_operation().ok)
	assert_eq(_finish(session).code, "CANCELLED")
	assert_eq(session.snapshot().to_dict().ingredients[id].fine, 0.0)
	assert_true(_op(session, "cut", {"instance_id": id, "shape": "dice"}).ok)
	assert_true(_finish(session).ok)
	assert_eq(_finish(session).code, "ALREADY_FINISHED")
	assert_false(_op(session, "cut", {"instance_id": id, "shape": "chunk"}).ok)

func test_cold_recipe_does_not_require_heat_and_plate_is_not_delivery() -> void:
	var session := _session("test.cold_salad")
	_add(session, "cucumber")
	assert_true(_op(session, "stir").ok)
	assert_true(_finish(session).ok)
	assert_true(_op(session, "plate").ok)
	assert_true(_finish(session).ok)
	var snap: Dictionary = session.snapshot().to_dict()
	assert_eq(snap.state, "plated")
	assert_true(snap.missing_required.is_empty())
	assert_true(_op(session, "deliver").ok)
	assert_false(_op(session, "deliver").ok)
	assert_false(_op(session, "rework").ok)

func test_plating_position_does_not_change_score_and_drop_discards_once() -> void:
	var session := _session("test.cold_salad")
	_add(session, "cucumber")
	_op(session, "plate")
	_finish(session)
	var before: Dictionary = session.snapshot().to_dict()
	var piece: String = before.plating[0].id
	assert_true(session.move_plating(piece, Vector2(.3, .2), true).ok)
	assert_eq(session.snapshot().to_dict().dish_attributes, before.dish_attributes)
	assert_true(session.move_plating(piece, Vector2(2, 0), false).ok)
	assert_eq(session.snapshot().to_dict().state, "plated")
	assert_true(session.move_plating(piece, Vector2(2, 0), true).ok)
	assert_eq(session.snapshot().to_dict().state, "discarded")
	assert_false(session.move_plating(piece, Vector2(2, 0), true).ok)

func test_rework_keeps_irreversible_history_and_completed_steps() -> void:
	var session := _session()
	var id: String = _add(session, "tomato")
	_op(session, "cut", {"instance_id": id, "shape": "dice"})
	_finish(session)
	_op(session, "plate")
	_finish(session)
	assert_true(_op(session, "rework").ok)
	assert_eq(session.snapshot().to_dict().ingredients[id].fine, .8)
	assert_gte(session.snapshot().to_dict().steps.size(), 2)

func test_merge_keeps_instance_histories_and_does_not_backfill_heat() -> void:
	var session := _session("test.reaction_pan")
	var first: String = _add(session, "beef", "hot")
	_op(session, "heat", {"batch_id": "hot"})
	_finish(session, 1.0, 6.0)
	var second: String = _add(session, "beef", "cold")
	assert_true(_op(session, "merge", {"source_batch": "cold", "target_batch": "hot"}).ok)
	var values: Dictionary = session.snapshot().to_dict().ingredients
	assert_gt(values[first].heat_dose, values[second].heat_dose)
	assert_eq(values[second].heat_dose, 0.0)
	assert_eq(values[first].batch_id, values[second].batch_id)

func test_san_multiplier_boundaries_and_config_do_not_mutate_catalog() -> void:
	for san: float in [0.0, 30.0, 60.0, 100.0]:
		var session := _session("tomato_egg", {"san": san})
		var id: String = _add(session, "tomato")
		var started: TDOutcome = _op(session, "cut", {"instance_id": id, "shape": "chunk"})
		var expected: float = .06 * (1.0 if san >= 60.0 else .6 + .4 * san / 60.0)
		assert_almost_eq(float(started.data.qte_config.perfect_sec), expected, .000001)

func test_cooling_partition_and_insulation() -> void:
	var a := _session("test.reaction_pan")
	var b := _session("test.reaction_pan")
	_add(a, "beef")
	_add(b, "beef")
	_op(a, "heat")
	_op(b, "heat")
	_finish(a)
	_finish(b)
	a.advance_time(10.0)
	for _i: int in range(100):
		b.advance_time(.1)
	assert_almost_eq(a.snapshot().to_dict().dish_attributes.temperature_c, b.snapshot().to_dict().dish_attributes.temperature_c, .000001)
	_op(a, "container", {"kind": "insulated"})
	var temperature: float = a.snapshot().to_dict().dish_attributes.temperature_c
	a.advance_time(50.0)
	assert_almost_eq(a.snapshot().to_dict().dish_attributes.temperature_c, temperature, .000001)

func test_custom_plan_excludes_scores_and_custom_quality_is_capped() -> void:
	var catalog := Catalog.new()
	catalog.load_file("res://content/cooking_system.json")
	var custom: Dictionary = catalog.for_recipe("test.cold_salad").recipe
	custom.is_custom = true
	var session := _session("test.cold_salad", {"custom_recipe": custom})
	_add(session, "cucumber")
	_op(session, "stir")
	_finish(session)
	var snap: Dictionary = session.snapshot().to_dict()
	assert_true(snap.is_custom)
	assert_lte(snap.dish_attributes.completion, 90.0)
	assert_false(JSON.stringify(snap.custom_plan).contains("quality"))
	assert_false(JSON.stringify(snap.custom_plan).contains("satisfaction"))

func test_zero_quality_weight_is_finite_and_snapshot_read_is_pure() -> void:
	var session := _session()
	_add(session, "tomato")
	var before: Dictionary = session.snapshot().to_dict()
	assert_eq(before.dish_attributes.completion, 0.0)
	for _i: int in range(10):
		assert_eq(session.snapshot().to_dict(), before)

func _has_reaction(session: TDCookingSession, id: String) -> bool:
	for event: Dictionary in session.snapshot().to_dict().events:
		if event.type == "reaction" and event.reaction_id == id:
			return true
	return false

func test_four_heat_reactions_require_conditions_and_do_not_reapply() -> void:
	var session := _session("test.reaction_pan")
	_add(session, "beef")
	_add(session, "sugar")
	_add(session, "oil")
	_op(session, "heat")
	_finish(session)
	assert_true(_has_reaction(session, "maillard"))
	assert_true(_has_reaction(session, "caramelization"))
	assert_false(_has_reaction(session, "hydrolysis"))
	assert_false(_has_reaction(session, "fat_oxidation"))
	_op(session, "heat")
	_finish(session)
	assert_true(_has_reaction(session, "fat_oxidation"))
	var reaction_count: int = 0
	for event: Dictionary in session.snapshot().to_dict().events:
		if event.type == "reaction": reaction_count += 1
	_op(session, "heat")
	_finish(session)
	var repeated_count: int = 0
	for event: Dictionary in session.snapshot().to_dict().events:
		if event.type == "reaction": repeated_count += 1
	assert_eq(repeated_count, reaction_count)
	var boiled := _session("test.reaction_pan")
	_add(boiled, "beef")
	_op(boiled, "boil")
	_finish(boiled)
	assert_true(_has_reaction(boiled, "hydrolysis"))
	assert_false(_has_reaction(boiled, "maillard"))
	assert_false(_has_reaction(boiled, "caramelization"))

func test_starch_fermentation_and_exposure_have_positive_negative_and_boundary() -> void:
	var session := _session("test.reaction_pan")
	var beef: String = _add(session, "beef")
	_op(session, "starch")
	_finish(session)
	assert_false(_has_reaction(session, "starch_gel"))
	_add(session, "starch")
	_op(session, "heat")
	_finish(session)
	_op(session, "starch")
	_finish(session)
	assert_true(_has_reaction(session, "starch_gel"))
	assert_gt(session.snapshot().to_dict().ingredients[beef].texture.C, 0.0)
	var ferment := _session("test.cold_salad")
	_add(ferment, "cucumber")
	_op(ferment, "ferment")
	_finish(ferment)
	assert_false(_has_reaction(ferment, "fermentation"))
	_add(ferment, "culture")
	_op(ferment, "ferment")
	_finish(ferment, 1.0, 2.99)
	assert_false(_has_reaction(ferment, "fermentation"))
	_op(ferment, "ferment")
	_finish(ferment, 1.0, .01)
	assert_true(_has_reaction(ferment, "fermentation"))
	var exposed := _session()
	var tomato: String = _add(exposed, "tomato")
	_op(exposed, "cut", {"instance_id": tomato, "shape": "chunk"})
	_finish(exposed)
	exposed.advance_time(11.99)
	assert_false(_has_reaction(exposed, "cut_oxidation"))
	exposed.advance_time(.01)
	assert_true(_has_reaction(exposed, "cut_oxidation"))
	var before: Array = exposed.snapshot().to_dict().ingredients[tomato].flavor.duplicate(true)
	exposed.advance_time(30.0)
	assert_eq(exposed.snapshot().to_dict().ingredients[tomato].flavor, before)

func test_low_san_rolls_only_once_on_delivery_and_zero_one_probabilities() -> void:
	for probability: float in [0.0, 1.0]:
		var catalog := Catalog.new()
		catalog.load_file("res://content/cooking_system.json")
		var config: Dictionary = catalog.for_recipe("test.reaction_pan")
		config.variants[0].probability = probability
		var rng := FixedRandom.new()
		var session := TDCookingSession.new("unit", 1, config, {"san": 0, "random_source": rng})
		_add(session, "beef")
		_op(session, "heat")
		_finish(session)
		_op(session, "plate")
		_finish(session)
		assert_eq(rng.draws, 0)
		assert_true(_op(session, "deliver").ok)
		assert_eq(rng.draws, 1)
		assert_eq(session.snapshot().to_dict().san_spent, 5.0)
		assert_eq(session.snapshot().to_dict().variant_id.is_empty(), probability == 0)
		for _i: int in range(5): session.snapshot()
		assert_false(_op(session, "deliver").ok)
		assert_eq(rng.draws, 1)

func test_san_no_candidate_nonperfect_and_high_san_do_not_roll() -> void:
	for san: float in [29.0, 30.0, 100.0]:
		var rng := FixedRandom.new()
		var session := _session("test.reaction_pan", {"san": san, "random_source": rng})
		_add(session, "beef")
		_op(session, "heat")
		_finish(session, .5)
		_op(session, "plate")
		_finish(session)
		_op(session, "deliver")
		assert_eq(rng.draws, 0)
	var rng := FixedRandom.new()
	var cold := _session("test.cold_salad", {"san": 0, "random_source": rng})
	_add(cold, "cucumber")
	_op(cold, "stir")
	_finish(cold)
	_op(cold, "plate")
	_finish(cold)
	_op(cold, "deliver")
	assert_eq(rng.draws, 0)

func test_substitution_retains_actual_identity_and_amount_requirements() -> void:
	var session := _session()
	var tomato: String = _add(session, "cherry_tomato", "main", .5)
	_add(session, "egg")
	_op(session, "cut", {"instance_id": tomato, "shape": "chunk"})
	_finish(session)
	_op(session, "heat")
	_finish(session)
	assert_true("ingredient:tomato" in session.snapshot().to_dict().missing_required)
	var extra: String = _add(session, "cherry_tomato", "main", .5)
	_op(session, "cut", {"instance_id": extra, "shape": "chunk"})
	_finish(session)
	_op(session, "heat")
	_finish(session)
	assert_false("ingredient:tomato" in session.snapshot().to_dict().missing_required)
	assert_eq(session.snapshot().to_dict().ingredients[tomato].ingredient_id, "cherry_tomato")

func test_zero_weight_operations_empty_flavor_ties_and_finite_ranges() -> void:
	var catalog := Catalog.new()
	catalog.load_file("res://content/cooking_system.json")
	var config: Dictionary = catalog.for_recipe("test.cold_salad")
	for operation: Dictionary in config.operations.values(): operation.quality_weight = 0.0
	for ingredient: Dictionary in config.ingredients:
		if ingredient.id == "cucumber": ingredient.base_tastes = [0, 0, 0, 0, 0, 0, 0]
	var session := TDCookingSession.new("unit", 1, config)
	_add(session, "cucumber")
	_op(session, "stir")
	_finish(session)
	var snap: Dictionary = session.snapshot().to_dict()
	assert_eq(snap.dish_attributes.completion, 0.0)
	assert_true(snap.dish_attributes.dominant.is_empty())
	assert_true(snap.dish_attributes.compound.is_empty())
	assert_false(_op(session, "add", {"ingredient_id": "salt", "amount": -1.0}).ok)
	assert_false(session.advance_time(NAN).ok)

func test_harmony_uses_all_five_pair_relation_levels_and_ties_are_explicit() -> void:
	var catalog := Catalog.new()
	catalog.load_file("res://content/cooking_system.json")
	var relation_values: Array = [-3.0, -1.0, 1.0, 3.0, 5.0]
	var expected_scores: Array = [25.0, 40.0, 55.0, 70.0, 85.0]
	for index: int in range(5):
		var config: Dictionary = catalog.for_recipe("test.cold_salad")
		config.recipe.expected_aroma = []
		config.recipe.expects_aroma = false
		config.rules.harmony_pairs = {"0:1": relation_values[index]}
		for band: Dictionary in config.rules.temperature_bands:
			band.taste_factors = [1,1,1,1,1,1,1]
		for ingredient: Dictionary in config.ingredients:
			if ingredient.id == "cucumber": ingredient.base_tastes = [30,30,0,0,0,0,0]
		var session := TDCookingSession.new("unit", 1, config)
		_add(session, "cucumber")
		var attributes: Dictionary = session.snapshot().to_dict().dish_attributes
		assert_eq(attributes.harmony, expected_scores[index])
		assert_eq(attributes.dominant, ["酸", "甜"])

func test_heat_order_changes_newly_added_ingredient_and_extra_costs_are_separate() -> void:
	var first := _session("test.cold_salad")
	_add(first, "cucumber")
	_op(first, "heat")
	_finish(first)
	var fresh: String = _add(first, "tomato")
	assert_eq(first.snapshot().to_dict().ingredients[fresh].heat_dose, 0.0)
	_op(first, "stir")
	_finish(first)
	var reasons: Array = first.snapshot().to_dict().base_reasons
	var has_extra_food: bool = false
	var has_extra_step: bool = false
	for reason: Dictionary in reasons:
		has_extra_food = has_extra_food or reason.code == "EXTRA_INGREDIENTS"
		has_extra_step = has_extra_step or reason.code == "EXTRA_STEPS"
	assert_true(has_extra_food)
	assert_true(has_extra_step)

func test_preheat_changes_next_ingredient_temperature_and_sequence_failure_changes_release() -> void:
	var preheated := _session()
	_op(preheated, "preheat")
	_finish(preheated, 1, 1.4)
	var hot: String = _add(preheated, "tomato")
	assert_gt(preheated.snapshot().to_dict().ingredients[hot].temperature_c, 22.0)
	var good := _session()
	var bad := _session()
	_add(good, "tomato")
	_add(bad, "tomato")
	_op(good, "season", {"ingredient_id": "sugar", "amount": .1})
	_op(bad, "season", {"ingredient_id": "sugar", "amount": .1})
	_finish(good, 1)
	_finish(bad, 0)
	assert_gt(bad.snapshot().to_dict().dish_attributes.flavor[1][0], good.snapshot().to_dict().dish_attributes.flavor[1][0])

func test_custom_preset_recognition_uses_conditions_not_name_and_keeps_custom_identity() -> void:
	var catalog := Catalog.new()
	catalog.load_file("res://content/cooking_system.json")
	var config: Dictionary = catalog.for_recipe("tomato_egg")
	config.recipes[0].ideal_temperature = [-100, 1000]
	var custom: Dictionary = config.recipe.duplicate(true)
	custom.id = "user.unrelated_name"
	custom.name = "名字不会解锁食谱"
	var session := TDCookingSession.new("unit", 1, config, {"custom_recipe": custom})
	var tomato: String = _add(session, "tomato")
	_add(session, "egg")
	_op(session, "cut", {"instance_id": tomato, "shape": "chunk"})
	_finish(session)
	_op(session, "heat")
	_finish(session)
	_op(session, "plate")
	_finish(session)
	_op(session, "deliver")
	var found: bool = false
	for event: Dictionary in session.snapshot().to_dict().events:
		found = found or event.type == "preset_recognized"
	assert_true(found)
	assert_true(session.snapshot().to_dict().is_custom)
	assert_eq(session.snapshot().to_dict().recipe_id, "user.unrelated_name")

func test_each_thermal_reaction_exact_threshold_and_below_threshold() -> void:
	var cases: Array = [
		{"id": "maillard", "ingredients": ["beef", "sugar"], "operation": "heat", "temperature": 110.0, "duration": 2.0},
		{"id": "caramelization", "ingredients": ["sugar"], "operation": "heat", "temperature": 140.0, "duration": 2.0},
		{"id": "hydrolysis", "ingredients": ["beef"], "operation": "boil", "temperature": 70.0, "duration": 3.0},
		{"id": "fat_oxidation", "ingredients": ["oil"], "operation": "heat", "temperature": 140.0, "duration": 8.0}
	]
	var catalog := Catalog.new()
	catalog.load_file("res://content/cooking_system.json")
	for item: Dictionary in cases:
		for below: bool in [true, false]:
			var config: Dictionary = catalog.for_recipe("test.reaction_pan")
			config.rules.degrees_per_heat_dose = 0.0
			for ingredient: Dictionary in config.ingredients:
				ingredient.temperature_c = float(item.temperature) - (1.0 if below else 0.0)
			var session := TDCookingSession.new("unit", 1, config)
			for ingredient_id: String in item.ingredients: _add(session, ingredient_id)
			_op(session, item.operation)
			_finish(session, 1.0, float(item.duration) - .01)
			assert_false(_has_reaction(session, item.id))
			_op(session, item.operation)
			_finish(session, 1.0, .01)
			assert_eq(_has_reaction(session, item.id), not below, item.id)

func test_cut_mistake_delay_and_optional_san_event_apply_once() -> void:
	var rng := FixedRandom.new()
	var session := _session("tomato_egg", {"san": 60, "random_source": rng})
	var id: String = _add(session, "tomato")
	_op(session, "cut", {"instance_id": id, "shape": "dice"})
	_finish(session, 0)
	assert_eq(rng.draws, 1)
	assert_eq(session.snapshot().to_dict().san_context.current, 59.0)
	assert_eq(_op(session, "heat").code, "RECOVERING")
	session.advance_time(.3)
	assert_true(_op(session, "heat").ok)
	assert_eq(session.snapshot().to_dict().san_spent, 1.0)
	assert_eq(session.snapshot().to_dict().ingredients[id].fine, .8)

func test_many_initial_pieces_are_inside_plate_and_unfinished_drag_blocks_delivery() -> void:
	var session := _session("test.cold_salad")
	for _i: int in range(30): _add(session, "cucumber", "main", .1)
	_op(session, "plate")
	_finish(session)
	for piece: Dictionary in session.snapshot().to_dict().plating:
		assert_lte(Vector2(piece.position[0], piece.position[1]).length(), 1.0)
	var piece: Dictionary = session.snapshot().to_dict().plating[0]
	assert_true(session.move_plating(piece.id, Vector2(2, 0), false).ok)
	assert_eq(_op(session, "deliver").code, "PLATING_IN_PROGRESS")
	assert_eq(session.snapshot().to_dict().plating[0].position, piece.position)
	assert_true(session.move_plating(piece.id, Vector2(.2, 0), true).ok)
	assert_true(_op(session, "deliver").ok)

func test_plan_keeps_distinct_targets_for_same_template_in_same_batch() -> void:
	var session := _session()
	var first: String = _add(session, "tomato", "main", .5)
	var second: String = _add(session, "tomato", "main", .5)
	_op(session, "cut", {"instance_id": first, "shape": "slice"})
	_finish(session)
	_op(session, "cut", {"instance_id": second, "shape": "dice"})
	_finish(session)
	var plan: Dictionary = session.snapshot().to_dict().custom_plan
	assert_ne(plan.ingredients[0].local_id, plan.ingredients[1].local_id)
	assert_eq(plan.operations[2].parameters.target_local_id, plan.ingredients[0].local_id)
	assert_eq(plan.operations[3].parameters.target_local_id, plan.ingredients[1].local_id)
	assert_false(JSON.stringify(plan).contains("unit:1:ingredient"))

func test_plate_early_late_and_timeout_have_actual_attribute_consequences() -> void:
	var results: Dictionary = {}
	for reason: String in ["PERFECT_WINDOW", "EARLY_PRESS", "LATE_PRESS", "TIMEOUT"]:
		var session := _session("test.cold_salad")
		_add(session, "cucumber")
		_op(session, "plate")
		var snap: Dictionary = session.snapshot().to_dict()
		assert_true(session.complete_operation(TDOutcome.new(true, "COMPLETED", "", {"schema_version": 3, "session_id": "unit", "generation": 1, "operation_id": snap.operation_id, "kind": "plate", "status": "completed", "quality": 1.0 if reason == "PERFECT_WINDOW" else 0.0, "elapsed_sec": 1.8, "reason": reason})).ok)
		results[reason] = session.snapshot().to_dict().dish_attributes
	assert_lt(results.EARLY_PRESS.aroma.fresh, results.PERFECT_WINDOW.aroma.fresh)
	assert_gt(results.LATE_PRESS.temperature_c, results.PERFECT_WINDOW.temperature_c)
	assert_lt(results.TIMEOUT.aroma.fresh, results.PERFECT_WINDOW.aroma.fresh)

func test_fast_perfect_ferment_continues_in_game_time_and_exposes_remaining_time() -> void:
	var session := _session("test.cold_salad")
	_add(session, "cucumber")
	_add(session, "culture", "main", .1)
	_op(session, "ferment")
	var result: TDOutcome = _finish(session, 1, .5)
	assert_true(result.ok)
	assert_false(result.message.is_empty())
	assert_false(_has_reaction(session, "fermentation"))
	assert_almost_eq(float(session.snapshot().to_dict().fermentations[0].remaining_sec), 2.5, .000001)
	session.advance_time(2.49)
	assert_false(_has_reaction(session, "fermentation"))
	session.advance_time(.01)
	assert_true(_has_reaction(session, "fermentation"))
	assert_true(session.snapshot().to_dict().fermentations.is_empty())

func test_invalid_injected_context_and_nonfinite_result_metric_reject_without_state_change() -> void:
	var invalid_san := _session("tomato_egg", {"san": NAN})
	assert_eq(_op(invalid_san, "preheat").code, "INVALID_CONFIG")
	var invalid_custom := _session("tomato_egg", {"custom_recipe": {"required_ingredients": null}})
	assert_eq(_op(invalid_custom, "preheat").code, "INVALID_CONFIG")
	var session := _session()
	_op(session, "preheat")
	var before: Dictionary = session.snapshot().to_dict()
	var result := TDOutcome.new(true, "COMPLETED", "", {"schema_version": 3, "session_id": "unit", "generation": 1, "operation_id": before.operation_id, "kind": "preheat", "status": "completed", "quality": 1, "elapsed_sec": 1.5, "held_sec": NAN})
	assert_eq(session.complete_operation(result).code, "INVALID_RESULT")
	assert_eq(session.snapshot().to_dict(), before)

func test_invalid_random_is_rejected_before_cut_or_delivery_mutates_state() -> void:
	var rng := FixedRandom.new()
	rng.value = NAN
	var session := _session("tomato_egg", {"random_source": rng})
	var id: String = _add(session, "tomato")
	_op(session, "cut", {"instance_id": id, "shape": "dice"})
	var before: Dictionary = session.snapshot().to_dict()
	assert_eq(_finish(session, 0).code, "INVALID_RANDOM")
	assert_eq(session.snapshot().to_dict(), before)
	var dark := _session("test.reaction_pan", {"san": 0, "random_source": rng})
	_add(dark, "beef")
	_op(dark, "heat")
	_finish(dark)
	_op(dark, "plate")
	_finish(dark)
	before = dark.snapshot().to_dict()
	assert_eq(_op(dark, "deliver").code, "INVALID_RANDOM")
	assert_eq(dark.snapshot().to_dict(), before)

func test_fermentation_temperature_crossing_is_independent_of_update_slices() -> void:
	var catalog := Catalog.new()
	catalog.load_file("res://content/cooking_system.json")
	var config: Dictionary = catalog.for_recipe("test.cold_salad")
	for ingredient: Dictionary in config.ingredients: ingredient.temperature_c = -25.0
	var one := TDCookingSession.new("unit", 1, config)
	var many := TDCookingSession.new("unit", 1, config)
	for session: TDCookingSession in [one, many]:
		_add(session, "cucumber")
		_add(session, "culture", "main", .1)
		_op(session, "ferment")
		_finish(session, 1, .5)
	one.advance_time(12.0)
	for _i: int in range(120): many.advance_time(.1)
	assert_almost_eq(float(one.snapshot().to_dict().fermentations[0].remaining_sec), float(many.snapshot().to_dict().fermentations[0].remaining_sec), .000001)
	one.advance_time(3.0)
	for _i: int in range(30): many.advance_time(.1)
	assert_true(_has_reaction(one, "fermentation"))
	assert_true(_has_reaction(many, "fermentation"))
	assert_eq(one.snapshot().to_dict().dish_attributes.flavor, many.snapshot().to_dict().dish_attributes.flavor)

func test_completed_seasoning_returns_created_identity_for_saved_plan_mapping() -> void:
	var session := _session()
	_add(session, "tomato")
	_op(session, "season", {"ingredient_id": "sugar", "amount": .1})
	var completed: TDOutcome = _finish(session)
	assert_true(completed.data.has("instance_id"))
	assert_eq(completed.data.local_id, completed.data.ingredients[completed.data.instance_id].local_id)
	assert_eq(completed.data.custom_plan.operations.back().parameters.local_id, completed.data.local_id)
