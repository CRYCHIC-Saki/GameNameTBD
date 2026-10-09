class_name TDFrame
extends RefCounted

var schema_version: int = 1
var session_id: String
var generation: int
var operation_id: String
var sequence: int
var held_sec: float
var elapsed_sec: float
var status: String

func _init(sid: String, gen: int, oid: String, seq: int, held: float, elapsed: float, state: String) -> void:
	session_id = sid
	generation = gen
	operation_id = oid
	sequence = seq
	held_sec = held
	elapsed_sec = elapsed
	status = state
