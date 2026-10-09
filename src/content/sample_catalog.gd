class_name TDCatalog
extends RefCounted

var _templates: Dictionary = {}

func ids() -> Array:
	return _templates.keys()

func get_template(stable_id: String) -> TDTemplate:
	if not _templates.has(stable_id):
		return null
	# Reconstruct explicitly, including nested Resource and value containers.
	return TDTemplate.from_data(_templates[stable_id])

func load_file(path: String) -> TDOutcome:
	_templates.clear()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return TDOutcome.new(false, "READ_FAILED", path)
	var parser := JSON.new()
	var error := parser.parse(file.get_as_text())
	if error != OK:
		return TDOutcome.new(false, "INVALID_JSON", "%s:%d %s" % [path, parser.get_error_line(), parser.get_error_message()])
	return load_data(parser.data, path)

func load_data(raw: Variant, source: String) -> TDOutcome:
	_templates.clear()
	if not raw is Dictionary:
		return _bad(source, "root", "must be object")
	var data: Dictionary = raw
	if data.get("schema_version") != 1 or data.get("scope") != "DEV_ONLY":
		return _bad(source, "schema_version/scope", "expected 1 / DEV_ONLY")
	if not data.get("samples") is Array or not data.get("active") is Array or data["active"].is_empty():
		return _bad(source, "samples/active", "expected arrays; active must not be empty")
	var index: Dictionary = {}
	for value: Variant in data["samples"]:
		if not value is Dictionary or not value.get("id") is String or value["id"].is_empty():
			return _bad(source, "samples.id", "required string")
		if index.has(value["id"]):
			return TDOutcome.new(false, "DUPLICATE_ID", source + ": samples." + value["id"])
		index[value["id"]] = value
	var pending: Dictionary = {}
	for id: Variant in data["active"]:
		if not id is String or not index.has(id):
			return TDOutcome.new(false, "MISSING_REFERENCE", source + ": active." + str(id))
		if pending.has(id):
			return TDOutcome.new(false, "DUPLICATE_ID", source + ": active." + id)
		var entry: Dictionary = index[id]
		var checked := _validate(entry, source + ": samples." + id)
		if not checked.ok:
			return checked
		pending[id] = entry.duplicate(true)
	_templates = pending
	return TDOutcome.new(true, "OK", source, {"count": _templates.size()})

func _validate(entry: Dictionary, source: String) -> TDOutcome:
	if entry.get("schema_version") != 1 or entry.get("scope") != "DEV_ONLY":
		return _bad(source, "schema_version/scope", "unsupported")
	if entry.get("operation") != "probe_hold":
		return _bad(source, "operation", "unsupported")
	for field: String in ["rate_units_per_sec", "timeout_sec"]:
		if not _number(entry.get(field)) or float(entry[field]) <= 0.0 or float(entry[field]) > 100.0:
			return _bad(source, field, "expected finite number in (0,100]")
	var target: Variant = entry.get("target_sec")
	if not target is Array or target.size() != 2:
		return _bad(source, "target_sec", "expected [min,max]")
	if not _number(target[0]) or not _number(target[1]):
		return _bad(source, "target_sec", "expected finite seconds")
	if target[0] <= 0 or target[0] > target[1] or target[1] >= entry["timeout_sec"]:
		return _bad(source, "target_sec", "require 0 < min <= max < timeout")
	var material: Variant = entry.get("material")
	if not material is Dictionary or not material.get("id") is String or material["id"].is_empty():
		return _bad(source, "material.id", "required identity")
	if not material.get("metadata") is Dictionary or not material["metadata"].get("labels") is Array:
		return _bad(source, "material.metadata.labels", "required string array")
	if not _value_data(material["metadata"]):
		return _bad(source, "material.metadata", "only finite JSON value data is allowed")
	for label: Variant in material["metadata"]["labels"]:
		if not label is String:
			return _bad(source, "material.metadata.labels", "expected strings")
	return TDOutcome.new(true)

func _value_data(value: Variant) -> bool:
	if value == null or value is String or value is bool or value is int:
		return true
	if value is float:
		return is_finite(value)
	if value is Array:
		for child: Variant in value:
			if not _value_data(child):
				return false
		return true
	if value is Dictionary:
		for key: Variant in value:
			if not key is String or not _value_data(value[key]):
				return false
		return true
	return false

func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

func _bad(source: String, field: String, reason: String) -> TDOutcome:
	return TDOutcome.new(false, "INVALID_CONFIG", "%s.%s: %s" % [source, field, reason])
