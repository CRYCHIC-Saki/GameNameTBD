class_name TDSnapshot
extends RefCounted

var _values: Dictionary

func _init(values: Dictionary) -> void:
	_values = values.duplicate(true)

func to_dict() -> Dictionary:
	return _values.duplicate(true)
