class_name TDOutcome
extends RefCounted

var ok: bool
var code: String
var message: String
var data: Dictionary

func _init(success: bool, reason: String = "OK", detail: String = "", values: Dictionary = {}) -> void:
	ok = success
	code = reason
	message = detail
	data = values.duplicate(true)

func to_dict() -> Dictionary:
	return {"ok": ok, "code": code, "message": message, "data": data.duplicate(true)}
