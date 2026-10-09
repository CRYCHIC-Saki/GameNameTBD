class_name TDTemplate
extends Resource

@export var stable_id: String = ""
@export var schema_version: int = 1
@export var operation: String = "probe_hold"
@export var rate_units_per_sec: float = 10.0
@export var target_min_sec: float = 1.2
@export var target_max_sec: float = 1.8
@export var timeout_sec: float = 6.0
@export var material: TDMaterial

static func from_data(values: Dictionary) -> TDTemplate:
	var template := TDTemplate.new()
	template.stable_id = values["id"]
	template.schema_version = int(values["schema_version"])
	template.operation = values["operation"]
	template.rate_units_per_sec = float(values["rate_units_per_sec"])
	template.target_min_sec = float(values["target_sec"][0])
	template.target_max_sec = float(values["target_sec"][1])
	template.timeout_sec = float(values["timeout_sec"])
	template.material = TDMaterial.new()
	template.material.stable_id = values["material"]["id"]
	template.material.metadata = values["material"]["metadata"].duplicate(true)
	return template

func to_data() -> Dictionary:
	return {
		"id": stable_id, "schema_version": schema_version, "scope": "DEV_ONLY",
		"operation": operation, "rate_units_per_sec": rate_units_per_sec,
		"target_sec": [target_min_sec, target_max_sec], "timeout_sec": timeout_sec,
		"material": material.to_data()
	}
