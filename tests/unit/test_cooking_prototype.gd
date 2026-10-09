extends GutTest
const RecipeCatalog = preload("res://src/content/recipe_catalog.gd")
const Session = preload("res://src/cooking/cooking_session.gd")
const Request = preload("res://src/contracts/operation_request.gd")
const Outcome = preload("res://src/contracts/outcome.gd")
var _serial: int = 0

func config() -> Dictionary:
	var catalog := RecipeCatalog.new()
	catalog.load_file("res://content/cooking_prototype.json")
	return catalog.data()

func action(session: TDCookingSession, kind: String, parameters: Dictionary = {}) -> TDOutcome:
	_serial += 1
	var state := session.snapshot().to_dict()
	var request := Request.new(state["session_id"], state["generation"], "op%d" % _serial, kind, state["revision"], parameters)
	request.schema_version = 2
	return session.begin(request)

func completed(session: TDCookingSession, kind: String, quality: float = 1.0, dose: float = 3.0) -> TDOutcome:
	var state := session.snapshot().to_dict()
	var payload := {"schema_version": 2, "session_id": state["session_id"], "generation": state["generation"], "operation_id": state["operation_id"], "kind": kind, "status": "completed", "quality": quality, "elapsed_sec": 6.0}
	if kind == "cut":
		payload.merge({"hits": 8 if quality == 1 else 0, "perfect": 8 if quality == 1 else 0, "good": 0, "miss": 0 if quality == 1 else 8})
	else:
		payload.merge({"heat_dose": dose, "end_power": dose / 6.0})
	return Outcome.new(true, "COMPLETED", "", payload)

func ingredients(session: TDCookingSession) -> void:
	action(session, "add", {"ingredient_id": "tomato"})
	action(session, "add", {"ingredient_id": "egg"})

func cook(session: TDCookingSession, shape: String = "chunk") -> void:
	ingredients(session)
	action(session, "cut", {"ingredient_id": "tomato", "shape": shape})
	assert_true(session.complete_operation(completed(session, "cut")).ok)
	action(session, "heat")
	assert_true(session.complete_operation(completed(session, "heat")).ok)

func test_empty_plate_is_allowed_and_missing_rules_apply_once() -> void:
	var session := Session.new("s", 1, config())
	assert_true(action(session, "plate").ok)
	var first := session.snapshot().to_dict()
	assert_eq(first["state"], "plated")
	assert_eq(first["dish_attributes"]["completion"], 0.0)
	assert_eq(first["dish_attributes"]["harmony"], 45.0)
	assert_true(first["missing_required"].has("ingredient:tomato"))
	assert_eq(first["base_reasons"].size(), 2)
	assert_eq(session.snapshot().to_dict(), first)
	assert_eq(action(session, "plate").code, "ALREADY_FINISHED")
	assert_eq(session.snapshot().to_dict(), first)

func test_cut_shape_and_skill_are_independent_and_per_ingredient() -> void:
	var chunk := Session.new("chunk", 1, config())
	var dice := Session.new("dice", 1, config())
	var poor := Session.new("poor", 1, config())
	for session: TDCookingSession in [chunk, dice, poor]:
		ingredients(session)
		action(session, "cut", {"ingredient_id": "tomato", "shape": "dice" if session == dice else "chunk"})
		session.complete_operation(completed(session, "cut", 0.0 if session == poor else 1.0))
	assert_eq(chunk.snapshot().to_dict()["ingredients"]["tomato"]["fine"], 0.25)
	assert_eq(dice.snapshot().to_dict()["ingredients"]["tomato"]["fine"], 0.8)
	assert_eq(poor.snapshot().to_dict()["ingredients"]["tomato"]["fine"], 0.25)
	assert_eq(dice.snapshot().to_dict()["ingredients"]["egg"]["fine"], 0.0)
	assert_gt(dice.snapshot().to_dict()["dish_attributes"]["flavor"][0][0], chunk.snapshot().to_dict()["dish_attributes"]["flavor"][0][0])
	assert_gt(chunk.snapshot().to_dict()["dish_attributes"]["completion"], poor.snapshot().to_dict()["dish_attributes"]["completion"])

func test_temperature_is_projected_once_and_cooling_is_explicit() -> void:
	var session := Session.new("s", 1, config())
	cook(session)
	var hot := session.snapshot().to_dict()
	assert_almost_eq(hot["dish_attributes"]["temperature_c"], 64.0, 0.0001)
	for index: int in range(5):
		assert_eq(session.snapshot().to_dict(), hot)
	assert_true(session.advance_time(90.0).ok)
	assert_almost_eq(session.snapshot().to_dict()["dish_attributes"]["temperature_c"], 37.451, 0.002, "22+42/e hand calculation")
	var cooled := session.snapshot().to_dict()
	assert_eq(session.advance_time(-1).code, "INVALID_TIME")
	assert_eq(session.snapshot().to_dict(), cooled)

func test_perfect_recipe_has_hand_calculated_quality_and_tenderness() -> void:
	var session := Session.new("s", 1, config())
	cook(session)
	action(session, "plate")
	var dish := session.snapshot().to_dict()
	assert_eq(dish["dish_attributes"]["completion"], 100.0)
	assert_eq(dish["dish_attributes"]["harmony"], 100.0)
	assert_almost_eq(dish["ingredients"]["egg"]["texture"]["A"], 0.55, 0.0001)
	assert_true(dish["missing_required"].is_empty())
	assert_eq(dish["dish_attributes"]["flavor"].size(), 7)
	assert_eq(dish["dish_attributes"]["flavor"][0].size(), 4)

func test_missing_recipe_items_and_no_aroma_penalize_exactly_once() -> void:
	var session := Session.new("s", 1, config())
	action(session, "add", {"ingredient_id": "tomato"})
	action(session, "cut", {"ingredient_id": "tomato", "shape": "chunk"})
	session.complete_operation(completed(session, "cut"))
	action(session, "plate")
	assert_almost_eq(session.snapshot().to_dict()["dish_attributes"]["completion"], 28.0, 0.001, "100 * .4 * .7")
	assert_eq(session.snapshot().to_dict()["dish_attributes"]["harmony"], 45.0)
	assert_almost_eq(session.snapshot().to_dict()["dish_attributes"]["completion"], 28.0, 0.001)

func test_season_before_heat_and_after_heat_are_different() -> void:
	var early := Session.new("early", 1, config())
	var late := Session.new("late", 1, config())
	ingredients(early)
	action(early, "season", {"ingredient_id": "sugar", "amount": 1})
	action(early, "heat")
	early.complete_operation(completed(early, "heat", 0.0, 6.0))
	ingredients(late)
	action(late, "heat")
	late.complete_operation(completed(late, "heat", 0.0, 6.0))
	action(late, "season", {"ingredient_id": "sugar", "amount": 1})
	assert_true(early.snapshot().to_dict()["dish_attributes"]["aroma"].has("caramel"))
	assert_false(late.snapshot().to_dict()["dish_attributes"]["aroma"].has("caramel"))
	assert_ne(early.snapshot().to_dict()["dish_attributes"]["flavor"], late.snapshot().to_dict()["dish_attributes"]["flavor"])

func test_invalid_operations_busy_duplicates_cancel_and_old_results_are_atomic() -> void:
	var session := Session.new("s", 1, config())
	assert_eq(action(session, "heat").code, "NO_TARGET")
	assert_eq(action(session, "cut", {"ingredient_id": "tomato", "shape": "chunk"}).code, "NO_TARGET")
	ingredients(session)
	assert_eq(action(session, "add", {"ingredient_id": "tomato"}).code, "ALREADY_PRESENT")
	assert_eq(action(session, "cut", {"ingredient_id": "egg", "shape": "chunk"}).code, "INVALID_TARGET")
	assert_eq(action(session, "season", {"ingredient_id": "salt", "amount": -1}).code, "INVALID_AMOUNT")
	action(session, "cut", {"ingredient_id": "tomato", "shape": "dice"})
	var pending := completed(session, "cut")
	assert_eq(action(session, "heat").code, "BUSY")
	assert_true(session.complete_operation(pending).ok)
	var snapshot := session.snapshot().to_dict()
	assert_eq(session.complete_operation(pending).code, "ALREADY_FINISHED")
	assert_eq(action(session, "cut", {"ingredient_id": "tomato", "shape": "chunk"}).code, "COARSER_CUT")
	assert_eq(session.snapshot().to_dict(), snapshot)
	action(session, "heat")
	var cancelled := completed(session, "heat")
	assert_true(session.cancel_operation().ok)
	assert_eq(session.complete_operation(cancelled).code, "CANCELLED")
	assert_true(action(session, "heat").ok)
	assert_eq(session.complete_operation(cancelled).code, "CANCELLED")
	assert_true(session.cancel().ok)
	assert_eq(session.complete_operation(completed(session, "heat")).code, "CANCELLED")

func test_bad_results_never_apply_effects() -> void:
	var session := Session.new("s", 1, config())
	ingredients(session)
	action(session, "heat")
	var before := session.snapshot().to_dict()
	var bad := completed(session, "heat")
	bad.data["quality"] = NAN
	assert_eq(session.complete_operation(bad).code, "INVALID_RESULT")
	bad = completed(session, "heat")
	bad.data["heat_dose"] = 7.0
	assert_eq(session.complete_operation(bad).code, "INVALID_RESULT")
	bad = completed(session, "heat")
	bad.data["generation"] = 0
	assert_eq(session.complete_operation(bad).code, "STALE_OPERATION")
	assert_eq(session.snapshot().to_dict(), before)

func test_sessions_configuration_and_history_are_detached() -> void:
	var template := config()
	var one := Session.new("one", 1, template)
	var two := Session.new("two", 1, template)
	cook(one)
	var external := one.snapshot().to_dict()
	external["ingredients"]["tomato"]["texture"]["A"] = -1
	external["history"].clear()
	template["ingredients"][0]["base_flavor"][0][0] = 99
	assert_true(two.snapshot().to_dict()["ingredients"].is_empty())
	assert_eq(one.snapshot().to_dict()["history"].size(), 4)
	assert_ne(one.snapshot().to_dict()["ingredients"]["tomato"]["texture"]["A"], -1.0)
	assert_eq(config()["ingredients"][0]["base_flavor"][0][0], 12.0)

func test_input_timeline_partition_and_repeated_heat_stay_bounded() -> void:
	var one := Session.new("s", 1, config())
	var two := Session.new("s", 1, config())
	cook(one)
	cook(two)
	one.advance_time(2.0)
	for index: int in range(20):
		two.advance_time(0.1)
	assert_almost_eq(one.snapshot().to_dict()["dish_attributes"]["temperature_c"], two.snapshot().to_dict()["dish_attributes"]["temperature_c"], 0.000001)
	for index: int in range(5):
		action(one, "heat")
		one.complete_operation(completed(one, "heat", 0.0, 6.0))
	var state := one.snapshot().to_dict()
	assert_lte(state["dish_attributes"]["temperature_c"], 120.0)
	assert_gte(state["ingredients"]["egg"]["texture"]["A"], -1.0)
	for row: Array in state["dish_attributes"]["flavor"]:
		for value: float in row:
			assert_between(value, 0.0, 100.0)

func test_cut_result_must_match_judgements_and_cannot_complete_instantly() -> void:
	var session := Session.new("s", 1, config())
	ingredients(session)
	action(session, "cut", {"ingredient_id": "tomato", "shape": "chunk"})
	var before := session.snapshot().to_dict()
	var bad := completed(session, "cut", 0.0)
	bad.data["quality"] = 1.0
	assert_eq(session.complete_operation(bad).code, "INVALID_RESULT")
	bad = completed(session, "cut")
	bad.data["elapsed_sec"] = 0.0
	assert_eq(session.complete_operation(bad).code, "INVALID_RESULT")
	bad = completed(session, "cut")
	bad.data["elapsed_sec"] = 4.0
	assert_eq(session.complete_operation(bad).code, "INVALID_RESULT", "Last Good window remains open until 4.14 even at minimum calibration")
	assert_eq(session.snapshot().to_dict(), before)
	var good := completed(session, "cut")
	good.data.merge({"perfect": 0, "good": 8, "hits": 8, "miss": 0, "quality": 0.6}, true)
	good.data["elapsed_sec"] = 4.14
	assert_true(session.complete_operation(good).ok)
	assert_almost_eq(session.snapshot().to_dict()["dish_attributes"]["completion"], 16.8, 0.0001, "60 * .4 * .7")
	var reasons: Array = session.snapshot().to_dict()["base_reasons"]
	assert_eq(reasons[0]["code"], "QTE_CUT")
	assert_string_contains(reasons[0]["message"], "跟随拍点")
	assert_string_contains(reasons[1]["message"], "加热番茄")
	assert_false(str(reasons[1]["message"]).contains("heat:tomato"))

func test_aroma_penalty_requires_recipe_expectation_and_zero_qte_weight_is_safe() -> void:
	var adjusted := config()
	adjusted["recipe"]["expects_aroma"] = false
	adjusted["rules"]["quality_weights"]["cut"] = 0.0
	var session := Session.new("s", 1, adjusted)
	ingredients(session)
	action(session, "cut", {"ingredient_id": "tomato", "shape": "chunk"})
	session.complete_operation(completed(session, "cut"))
	assert_eq(session.snapshot().to_dict()["dish_attributes"]["completion"], 0.0)
	assert_eq(session.snapshot().to_dict()["dish_attributes"]["harmony"], 80.0)
	for reason: Dictionary in session.snapshot().to_dict()["base_reasons"]:
		assert_ne(reason["code"], "NO_AROMA")

func test_heat_quality_and_dose_must_be_physically_consistent() -> void:
	var session := Session.new("s", 1, config())
	ingredients(session)
	action(session, "heat")
	var before := session.snapshot().to_dict()
	for invalid: Array in [[1.0, 0.0], [1.0, 2.39], [1.0, 4.21], [0.5, 1.19], [0.5, 5.11]]:
		assert_eq(session.complete_operation(completed(session, "heat", invalid[0], invalid[1])).code, "INVALID_RESULT")
		assert_eq(session.snapshot().to_dict(), before, "Rejected heat results cannot alter any state")
	# Half the time at power .4 and half at zero => quality .5 and dose 1.2.
	assert_true(session.complete_operation(completed(session, "heat", 0.5, 1.2)).ok)
	assert_almost_eq(session.snapshot().to_dict()["dish_attributes"]["temperature_c"], 38.8, 0.00001)
	for boundary: Array in [[1.0, 2.4], [1.0, 4.2], [0.5, 5.1]]:
		var other := Session.new("boundary", 1, config())
		ingredients(other)
		action(other, "heat")
		assert_true(other.complete_operation(completed(other, "heat", boundary[0], boundary[1])).ok)
