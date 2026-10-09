class_name TDSettingsStore
extends RefCounted

var _path: String

func _init(path: String) -> void:
	_path = path

func load_settings() -> TDOutcome:
	if not FileAccess.file_exists(_path):
		return TDOutcome.new(false, "NOT_FOUND", _path)
	var file := FileAccess.open(_path, FileAccess.READ)
	if file == null:
		return TDOutcome.new(false, "READ_FAILED", _path)
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		return TDOutcome.new(false, "INVALID_JSON", _path)
	var data: Dictionary = parser.data
	if data.get("schema_version") != 1:
		return TDOutcome.new(false, "UNSUPPORTED_VERSION", _path)
	if not data.get("show_debug") is bool:
		return TDOutcome.new(false, "INVALID_SETTINGS", _path + ": show_debug")
	return TDOutcome.new(true, "LOADED", "", data)

func save_settings(settings: Dictionary) -> TDOutcome:
	if not settings.get("show_debug") is bool:
		return TDOutcome.new(false, "INVALID_SETTINGS", "show_debug must be boolean")
	var existing := load_settings()
	if not existing.ok and existing.code != "NOT_FOUND":
		return existing
	var temporary := _path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return TDOutcome.new(false, "WRITE_FAILED", temporary)
	file.store_string(JSON.stringify({"schema_version": 1, "show_debug": settings["show_debug"]}))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		return TDOutcome.new(false, "WRITE_FAILED", temporary)
	# Preserve the previous valid file if replacing the target fails.
	var backup := _path + ".bak"
	if FileAccess.file_exists(backup):
		if DirAccess.remove_absolute(backup) != OK:
			return TDOutcome.new(false, "WRITE_FAILED", backup)
	if existing.ok and DirAccess.rename_absolute(_path, backup) != OK:
		return TDOutcome.new(false, "WRITE_FAILED", _path)
	if DirAccess.rename_absolute(temporary, _path) != OK:
		if existing.ok:
			DirAccess.rename_absolute(backup, _path)
		return TDOutcome.new(false, "WRITE_FAILED", _path)
	return TDOutcome.new(true, "SAVED")
