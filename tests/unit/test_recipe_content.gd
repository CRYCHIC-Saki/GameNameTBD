extends GutTest
const RecipeCatalog = preload("res://src/content/recipe_catalog.gd")

func source() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://content/cooking_prototype.json"))

func test_valid_content_has_two_customers_and_detached_values() -> void:
	var catalog := RecipeCatalog.new()
	assert_true(catalog.load_file("res://content/cooking_prototype.json").ok)
	var one := catalog.data()
	assert_eq(one["customers"].size(), 2)
	assert_eq(one["parameter_status"], "PROPOSED")
	one["ingredients"][0]["base_flavor"][0][0] = 99
	assert_eq(catalog.data()["ingredients"][0]["base_flavor"][0][0], 12.0)

func test_missing_files_and_non_json_are_reported() -> void:
	var catalog := RecipeCatalog.new()
	assert_eq(catalog.load_file("res://absent-cooking.json").code, "READ_FAILED")
	assert_eq(catalog.load_file("res://project.godot").code, "INVALID_JSON")

func test_invalid_ranges_matrices_enums_and_nan_are_atomic() -> void:
	var catalog := RecipeCatalog.new()
	var bad := source()
	bad["ingredients"][0]["base_flavor"][0].pop_back()
	assert_false(catalog.load_data(bad).ok)
	bad = source()
	bad["ingredients"][0]["texture"]["A"] = 2.0
	assert_false(catalog.load_data(bad).ok)
	bad = source()
	bad["qte"]["cut"]["perfect_sec"] = NAN
	assert_false(catalog.load_data(bad).ok)
	bad = source()
	bad["customers"][0]["requirements"][0]["kind"] = "mystery"
	assert_false(catalog.load_data(bad).ok)
	bad = source()
	bad["rules"]["room_temperature_c"] = Resource.new()
	assert_false(catalog.load_data(bad).ok)
	assert_true(catalog.data().is_empty())

func test_duplicate_ids_and_missing_references_fail() -> void:
	var catalog := RecipeCatalog.new()
	var bad := source()
	bad["ingredients"].append(bad["ingredients"][0].duplicate(true))
	assert_eq(catalog.load_data(bad).code, "DUPLICATE_ID")
	bad = source()
	bad["recipe"]["required_ingredients"].append("missing")
	assert_eq(catalog.load_data(bad).code, "MISSING_REFERENCE")
	bad = source()
	bad["customers"][0]["requirements"][2]["ingredient_id"] = "missing"
	assert_eq(catalog.load_data(bad).code, "MISSING_REFERENCE")

func test_qte_windows_and_zero_scoring_weights_are_validated() -> void:
	var catalog := RecipeCatalog.new()
	var bad := source()
	bad["qte"]["cut"]["good_sec"] = 0.3
	assert_false(catalog.load_data(bad).ok)
	bad = source()
	bad["scoring_rules"] = {"quality_weight": 0, "harmony_weight": 0, "requirements_weight": 0}
	assert_false(catalog.load_data(bad).ok)
	bad = source()
	for requirement: Dictionary in bad["customers"][0]["requirements"]:
		requirement["weight"] = 0
	assert_true(catalog.load_data(bad).ok, "A customer may declare no weighted preferences")
