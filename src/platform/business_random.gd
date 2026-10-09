class_name TDBusinessRandom
extends RefCounted

var _generator := RandomNumberGenerator.new()

func _init(seed_value: int) -> void:
	_generator.seed = seed_value

func unit() -> float:
	return _generator.randf()
