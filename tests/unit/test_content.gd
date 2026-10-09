extends GutTest
const Catalog = preload("res://src/content/sample_catalog.gd")

func test_valid_active_sample_and_detached_template() -> void:
	var catalog := Catalog.new()
	var result := catalog.load_file("res://content/dev_samples.json")
	assert_true(result.ok)
	assert_eq(catalog.ids(), ["dev.hold_probe"])
	var first = catalog.get_template("dev.hold_probe")
	first.material.metadata["labels"].append("mutation")
	var second = catalog.get_template("dev.hold_probe")
	assert_eq(second.material.metadata["labels"], ["DEV_ONLY"])
	assert_null(catalog.get_template("missing"))

func test_invalid_schema_fields_duplicates_references_and_ranges() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/dev_samples.json"))
	var catalog := Catalog.new()
	var bad := raw.duplicate(true)
	bad["schema_version"] = 9
	assert_false(catalog.load_data(bad, "fixture").ok)
	bad = raw.duplicate(true)
	bad["samples"][0].erase("rate_units_per_sec")
	assert_string_contains(catalog.load_data(bad, "fixture").message, "rate_units_per_sec")
	bad = raw.duplicate(true)
	bad["samples"].append(bad["samples"][0].duplicate(true))
	assert_eq(catalog.load_data(bad, "fixture").code, "DUPLICATE_ID")
	bad = raw.duplicate(true)
	bad["active"] = ["absent"]
	assert_eq(catalog.load_data(bad, "fixture").code, "MISSING_REFERENCE")
	bad = raw.duplicate(true)
	bad["samples"][0]["target_sec"] = [3.0, 1.0]
	assert_false(catalog.load_data(bad, "fixture").ok)
	bad = raw.duplicate(true)
	bad["samples"][0]["operation"] = "unknown"
	assert_false(catalog.load_data(bad, "fixture").ok)
	bad = raw.duplicate(true)
	bad["samples"][0]["rate_units_per_sec"] = INF
	assert_false(catalog.load_data(bad, "fixture").ok)
	assert_true(catalog.ids().is_empty(), "Failure must not leave partially loaded content")

func test_missing_and_malformed_files_are_reported() -> void:
	var catalog := Catalog.new()
	assert_eq(catalog.load_file("res://absent.json").code, "READ_FAILED")
	assert_eq(catalog.load_file("res://project.godot").code, "INVALID_JSON")

func test_metadata_rejects_nested_object_aliases_and_nonfinite_values() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/dev_samples.json"))
	var catalog := Catalog.new()
	raw["samples"][0]["material"]["metadata"]["extra"] = {"nested": [Resource.new()]}
	assert_false(catalog.load_data(raw, "fixture").ok)
	raw["samples"][0]["material"]["metadata"]["extra"] = {"nested": [NAN]}
	assert_false(catalog.load_data(raw, "fixture").ok)
