class_name TDRequest
extends RefCounted

var schema_version: int = 1
var session_id: String
var generation: int
var operation_id: String
var operation: String
var expected_revision: int
var parameters: Dictionary

func _init(sid: String, gen: int, oid: String, kind: String, revision: int, args: Dictionary = {}) -> void:
	session_id = sid
	generation = gen
	operation_id = oid
	operation = kind
	expected_revision = revision
	parameters = args.duplicate(true)
