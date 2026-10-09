extends GutTest

const Catalog = preload("res://src/content/cooking_catalog.gd")

func _raw() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://content/cooking_system.json"))

func test_active_catalog_has_normal_and_structurally_distinct_test_recipes() -> void:
	var catalog := Catalog.new()
	assert_true(catalog.load_data(_raw()).ok)
	assert_eq(catalog.recipe_ids(false), ["tomato_egg"])
	assert_eq(catalog.recipe_ids(true).size(), 5)
	assert_eq(catalog.for_recipe("test.cold_salad").recipe.required_steps, ["stir"])
	var returned: Dictionary = catalog.data()
	returned.ingredients[0].texture.A = -1
	assert_ne(catalog.data().ingredients[0].texture.A, -1.0)

func test_invalid_config_reports_source_field_and_clears_old_data() -> void:
	var catalog := Catalog.new()
	assert_true(catalog.load_data(_raw()).ok)
	var raw: Dictionary = _raw()
	raw.ingredients[0].base_tastes = [1, 2]
	var result: TDOutcome = catalog.load_data(raw, "bad sample.json")
	assert_false(result.ok)
	assert_true(result.message.contains("bad sample.json:ingredients.tomato"))
	assert_true(catalog.data().is_empty())

func test_duplicate_ids_missing_references_and_unsupported_operations_fail() -> void:
	var catalog := Catalog.new()
	var raw: Dictionary = _raw()
	raw.ingredients.append(raw.ingredients[0].duplicate(true))
	assert_eq(catalog.load_data(raw).code, "DUPLICATE_ID")
	raw = _raw()
	raw.recipes[0].required_ingredients[0].id = "missing"
	assert_eq(catalog.load_data(raw).code, "MISSING_REFERENCE")
	raw = _raw()
	raw.operations.teleport = {"target": "batch", "qte": "window", "quality_weight": 1}
	assert_false(catalog.load_data(raw).ok)

func test_nonfinite_negative_amount_inverted_range_and_bad_enum_fail() -> void:
	var catalog := Catalog.new()
	var raw: Dictionary = _raw()
	raw.ingredients[0].max_amount = -1
	assert_false(catalog.load_data(raw).ok)
	raw = _raw()
	raw.ingredients[0].quality = NAN
	assert_false(catalog.load_data(raw).ok)
	raw = _raw()
	raw.recipes[0].ideal_temperature = [70, 40]
	assert_false(catalog.load_data(raw).ok)
	raw = _raw()
	raw.qtes.sequence.sequence = ["jump"]
	assert_false(catalog.load_data(raw).ok)

func test_inactive_candidate_body_is_not_assumed_runtime_content() -> void:
	var raw: Dictionary = _raw()
	raw.ingredients.append({"id": "unresolved.source", "description": "未经映射的荔枝味"})
	var catalog := Catalog.new()
	assert_true(catalog.load_data(raw).ok)
	assert_eq(catalog.data().ingredients.size(), raw.active.ingredients.size())

func test_customer_zero_scale_invalid_axis_and_duplicate_recipe_requirement_fail() -> void:
	var catalog := Catalog.new()
	var raw: Dictionary = _raw()
	raw.customers[0].requirements[0].scale = 0
	assert_false(catalog.load_data(raw).ok)
	raw = _raw()
	raw.customers[1].requirements[2].axis = "D"
	assert_false(catalog.load_data(raw).ok)
	raw = _raw()
	raw.recipes[0].required_ingredients.append(raw.recipes[0].required_ingredients[0].duplicate(true))
	assert_eq(catalog.load_data(raw).code, "DUPLICATE_ID")

func test_missing_runtime_fields_bad_effect_axis_and_bad_table_entry_reject_atomically() -> void:
	var catalog := Catalog.new()
	var mutations: Array = ["scope", "operation_name", "reaction_axis", "band_type", "level_type"]
	for mutation: String in mutations:
		assert_true(catalog.load_data(_raw()).ok)
		var raw: Dictionary = _raw()
		match mutation:
			"scope": raw.recipes[0].erase("scope")
			"operation_name": raw.operations.cut.erase("name")
			"reaction_axis": raw.reactions[0].texture_delta = {"D": .2}
			"band_type": raw.rules.temperature_bands[0] = "broken"
			"level_type": raw.rules.harmony_levels[0] = 5
		assert_false(catalog.load_data(raw).ok, mutation)
		assert_true(catalog.data().is_empty())

func test_negative_release_cost_and_excess_variant_probability_are_invalid() -> void:
	var catalog := Catalog.new()
	for field: String in ["cut_release_front", "cut_release_after", "cut_miss_san_cost", "cut_miss_delay_sec"]:
		var raw: Dictionary = _raw()
		raw.rules[field] = -4
		assert_false(catalog.load_data(raw).ok, field)
	var raw: Dictionary = _raw()
	var extra: Dictionary = raw.variants[0].duplicate(true)
	extra.id = "test.second_variant"
	extra.probability = .7
	raw.variants.append(extra)
	raw.recipes[2].variant_ids.append(extra.id)
	assert_false(catalog.load_data(raw).ok)

func test_new_data_only_recipe_is_selectable_without_core_changes() -> void:
	var raw: Dictionary = _raw()
	var recipe: Dictionary = raw.recipes[1].duplicate(true)
	recipe.id = "test.new_fruit"
	recipe.required_ingredients = [{"id": "tomato", "min_amount": .5, "min_fine": 0, "max_fine": 1}]
	recipe.required_steps = []
	recipe.expects_aroma = false
	raw.recipes.append(recipe)
	raw.active.recipes.append(recipe.id)
	var catalog := Catalog.new()
	assert_true(catalog.load_data(raw).ok)
	assert_eq(catalog.for_recipe("test.new_fruit").recipe.required_steps, [])
	var session := TDCookingSession.new("new-data", 1, catalog.for_recipe("test.new_fruit"))
	var request := TDRequest.new("new-data", 1, "add", "add", 0, {"ingredient_id": "tomato", "amount": .5})
	request.schema_version = 3
	assert_true(session.begin(request).ok)
	request = TDRequest.new("new-data", 1, "plate", "plate", 1)
	request.schema_version = 3
	assert_true(session.begin(request).ok)
	assert_true(session.complete_operation(TDOutcome.new(true, "COMPLETED", "", {"schema_version": 3, "session_id": "new-data", "generation": 1, "operation_id": "plate", "kind": "plate", "status": "completed", "quality": 1.0, "elapsed_sec": 1.8})).ok)
	request = TDRequest.new("new-data", 1, "deliver", "deliver", int(session.snapshot().to_dict().revision))
	request.schema_version = 3
	assert_true(session.begin(request).ok)
	assert_eq(session.snapshot().to_dict().state, "delivered")
	assert_eq(session.snapshot().to_dict().recipe_id, "test.new_fruit")
