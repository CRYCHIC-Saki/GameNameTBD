class_name TDMaterial
extends Resource

@export var stable_id: String = ""
@export var metadata: Dictionary = {}

func to_data() -> Dictionary:
	return {"id": stable_id, "metadata": metadata.duplicate(true)}
