extends GutTest
var catalog: TDCookingCatalog
var path: String = "res://artifacts/test-storage/full-library-unit.json"
var library: TDRecipeLibrary

func before_each() -> void:
	DirAccess.make_dir_recursive_absolute("res://artifacts/test-storage")
	for suffix: String in ["", ".tmp", ".bak"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	catalog = TDCookingCatalog.new()
	assert_true(catalog.load_file("res://content/cooking_system.json").ok)
	library = TDRecipeLibrary.new(path, catalog.data())

func _plan() -> Dictionary:
	return {"schema_version": 1, "recipe_id": "tomato_egg", "ingredients": [{"ingredient_id": "tomato", "amount": 1.0, "batch_id": "main", "local_id": "ingredient_1"}], "operations": [{"operation": "add", "parameters": {"ingredient_id": "tomato", "amount": 1.0, "batch_id": "main", "local_id": "ingredient_1"}}, {"operation": "cut", "parameters": {"ingredient_id": "tomato", "shape": "dice", "batch_id": "main", "target_local_id": "ingredient_1"}}]}

func _write(data: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE); file.store_string(data); file.close()

func test_plan_roundtrip_and_new_version_keep_old_version_immutable() -> void:
	var original: Dictionary = _plan()
	var first := library.save_plan("我的菜", original)
	assert_true(first.ok)
	original.ingredients[0].amount = 2.0
	original.operations[0].parameters.amount = 2.0
	var second := library.save_plan("我的菜·改量", original, first.data.id)
	assert_true(second.ok); assert_eq(second.data.version, 2)
	var loaded := TDRecipeLibrary.new(path, catalog.data()).load_library()
	assert_eq(loaded.data.entries.size(), 2)
	assert_eq(float(loaded.data.entries[0].plan.ingredients[0].amount), 1.0)
	assert_eq(float(loaded.data.entries[1].plan.ingredients[0].amount), 2.0)

func test_corrupt_unknown_missing_reference_and_write_failure_are_preserved() -> void:
	for invalid: String in ["broken", '{"schema_version":99,"entries":[]}']:
		_write(invalid)
		assert_false(library.save_plan("菜", _plan()).ok)
		assert_eq(FileAccess.get_file_as_string(path), invalid)
	var plan: Dictionary = _plan(); plan.ingredients[0].ingredient_id = "missing"
	assert_eq(library.validate_plan(plan).code, "MISSING_REFERENCE")
	var impossible := TDRecipeLibrary.new("res://artifacts/no-such-parent/deep/library.json", catalog.data())
	assert_eq(impossible.save_plan("菜", _plan()).code, "WRITE_FAILED")

func test_scores_inputs_runtime_objects_and_bad_amount_cannot_be_saved() -> void:
	var plan: Dictionary = _plan(); plan.satisfaction = 100
	assert_false(library.validate_plan(plan).ok)
	plan = _plan(); plan.operations[0].parameters.quality = 1
	assert_false(library.validate_plan(plan).ok)
	plan = _plan(); plan.ingredients[0].amount = NAN
	assert_false(library.validate_plan(plan).ok)
	plan = _plan(); plan.recipe_id = "test.cold_salad"
	assert_eq(library.validate_plan(plan).data.scope, "TEST_ONLY")

func _dish() -> Dictionary:
	var session := TDCookingSession.new("scoring", 1, catalog.for_recipe("tomato_egg"))
	var request := TDRequest.new("scoring", 1, "add", "add", 0, {"ingredient_id": "tomato"}); request.schema_version = 3
	assert_true(session.begin(request).ok)
	return session.snapshot().to_dict()

func test_v3_declared_ingredient_step_and_fine_requirements_are_not_ignored() -> void:
	var dish: Dictionary = _dish()
	var scorer := TDCustomerScorer.new()
	var before: Dictionary = dish.duplicate(true)
	var customer: Dictionary = {"requirements": [{"id":"amount", "label":"两份番茄", "kind":"ingredient", "ingredient_id":"tomato", "min":2, "scale":2, "weight":1}, {"id":"heat", "label":"加热一次", "kind":"step", "operation":"heat", "min":1, "weight":1}]}
	var result := scorer.evaluate(dish, customer)
	assert_true(result.ok)
	assert_almost_eq(float(result.data.deviation), 75.0, .0001)
	assert_eq(dish, before)
	assert_eq(scorer.evaluate(dish, {"requirements":[]}).data.deviation, 0.0)

func test_v3_fine_uses_worst_instance_without_hiding_an_uncut_batch() -> void:
	var dish: Dictionary = _dish()
	var item: Dictionary = dish.ingredients.values()[0].duplicate(true); item.fine = .8
	dish.ingredients["extra"] = item
	var result := TDCustomerScorer.new().evaluate(dish, {"requirements":[{"id":"fine", "label":"小丁", "kind":"fine", "ingredient_id":"tomato", "min":.7, "max":1, "scale":1, "weight":1}]})
	assert_true(result.ok, result.message)
	assert_almost_eq(float(result.data.deviation), 70.0, .00001)
