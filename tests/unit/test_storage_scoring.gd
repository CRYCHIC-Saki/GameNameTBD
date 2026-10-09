extends GutTest
const Store = preload("res://src/platform/settings_store.gd")
const Scorer = preload("res://src/scoring/customer_scorer.gd")
var base_path: String

func before_each() -> void:
	base_path = "res://artifacts/test-storage/" + str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(base_path)

func test_settings_roundtrip() -> void:
	var store := Store.new(base_path + "/settings.json")
	assert_eq(store.load_settings().code, "NOT_FOUND")
	assert_true(store.save_settings({"show_debug": true}).ok)
	assert_true(store.load_settings().data["show_debug"])

func test_bad_and_unknown_files_not_overwritten() -> void:
	var path := base_path + "/settings.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{bad")
	file.close()
	var store := Store.new(path)
	assert_eq(store.load_settings().code, "INVALID_JSON")
	assert_false(store.save_settings({"show_debug": true}).ok)
	assert_eq(FileAccess.get_file_as_string(path), "{bad")
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string('{"schema_version":99,"show_debug":false}')
	file.close()
	assert_eq(store.load_settings().code, "UNSUPPORTED_VERSION")
	assert_false(store.save_settings({"show_debug": true}).ok)

func test_write_failure_and_invalid_data_are_explicit() -> void:
	var store := Store.new(base_path + "/missing/settings.json")
	assert_eq(store.save_settings({"show_debug": true}).code, "WRITE_FAILED")
	store = Store.new(base_path + "/settings.json")
	assert_false(store.save_settings({"show_debug": 42}).ok)

func test_scoring_is_explicitly_unimplemented_and_readonly() -> void:
	var scorer := Scorer.new()
	var source := {"work_units": 7.0, "material": {"tags": ["DEV_ONLY"]}}
	var before := source.duplicate(true)
	var result = scorer.evaluate(source, {})
	assert_false(result.ok)
	assert_eq(result.code, "NOT_IMPLEMENTED")
	assert_eq(source, before)
	assert_false(result.data.has("satisfaction"))
