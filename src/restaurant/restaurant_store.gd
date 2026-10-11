class_name TDRestaurantStore
extends RefCounted

var loaded_layout: TDRestaurantLayout
var _path: String

func _init(path: String) -> void:
	_path = path

func load_layout(catalog: TDRestaurantCatalog) -> TDOutcome:
	loaded_layout = null
	var envelope := _read()
	if not envelope.ok:
		return envelope
	var layout := TDRestaurantLayout.import_dict(envelope.data, catalog)
	if layout == null:
		return TDOutcome.new(false, TDRestaurantLayout.import_code, _path)
	loaded_layout = layout
	return TDOutcome.new(true, "LOADED", _path)

func save_layout(layout: TDRestaurantLayout) -> TDOutcome:
	var existing := _read()
	if not existing.ok and existing.code != "NOT_FOUND":
		return existing
	var temporary := _path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return TDOutcome.new(false, "WRITE_FAILED", temporary)
	file.store_string(JSON.stringify(layout.to_dict()))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		return TDOutcome.new(false, "WRITE_FAILED", temporary)
	var backup := _path + ".bak"
	if FileAccess.file_exists(backup) and DirAccess.remove_absolute(backup) != OK:
		return TDOutcome.new(false, "WRITE_FAILED", backup)
	if existing.ok and DirAccess.rename_absolute(_path, backup) != OK:
		return TDOutcome.new(false, "WRITE_FAILED", _path)
	if DirAccess.rename_absolute(temporary, _path) != OK:
		if existing.ok:
			DirAccess.rename_absolute(backup, _path)
		return TDOutcome.new(false, "WRITE_FAILED", _path)
	return TDOutcome.new(true, "SAVED", "布置已保存")

func _read() -> TDOutcome:
	if not FileAccess.file_exists(_path):
		return TDOutcome.new(false, "NOT_FOUND", _path)
	var file := FileAccess.open(_path, FileAccess.READ)
	if file == null:
		return TDOutcome.new(false, "READ_FAILED", _path)
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		return TDOutcome.new(false, "INVALID_JSON", "布置档损坏，原文件未改动")
	var data: Dictionary = parser.data
	if int(data.get("schema_version", -1)) != 1:
		return TDOutcome.new(false, "UNSUPPORTED_VERSION", "布置档版本无法识别，原文件未改动")
	return TDOutcome.new(true, "READ", "", data)
