class_name TDInput
extends RefCounted

var schema_version: int = 1
var session_id: String
var generation: int
var operation_id: String
var sequence: int
var timestamp_sec: float
var strength: float
var action: StringName = &"probe_hold"

func _init(sid: String, gen: int, oid: String, seq: int, at_sec: float, value: float) -> void:
	session_id = sid
	generation = gen
	operation_id = oid
	sequence = seq
	timestamp_sec = at_sec
	strength = value
