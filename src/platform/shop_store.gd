class_name TDShopStore
extends RefCounted
## No automatic fallback overwrites. Tests inject interruption into actual file writes.
var path: String
var session: TDShopSession
var interrupt_at: String = ""

func _init(save_path: String, validator: TDShopSession) -> void:
	path = save_path; session = validator

func _read(file_path: String) -> TDOutcome:
	if not FileAccess.file_exists(file_path): return TDOutcome.new(false,"NOT_FOUND")
	var file := FileAccess.open(file_path,FileAccess.READ)
	if file == null: return TDOutcome.new(false,"READ_FAILED")
	if file.get_length()>4000000: return TDOutcome.new(false,"FILE_TOO_LARGE")
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary: return TDOutcome.new(false,"INVALID_JSON")
	var envelope: Dictionary = parser.data
	if envelope.get("schema_version") != 1: return TDOutcome.new(false,"UNSUPPORTED_VERSION")
	if not envelope.get("payload") is String or not envelope.get("sha256") is String or envelope.payload.sha256_text()!=envelope.sha256: return TDOutcome.new(false,"CHECKSUM_MISMATCH")
	var data: Variant = JSON.parse_string(envelope.payload)
	var checked := session.validate_save(data)
	if not checked.ok: return checked
	return TDOutcome.new(true,"LOADED","",TDShopSession.normalize_save(data))

func load_game() -> TDOutcome:
	var result := _read(path)
	if not result.ok:
		result.data = {"backup_available":_read(path+".bak").ok,"temporary_available":_read(path+".tmp").ok}
		if result.code=="NOT_FOUND" and (FileAccess.file_exists(path+".bak") or FileAccess.file_exists(path+".tmp")): result.code="INTERRUPTED_SAVE"
	return result

func save_game(data: Dictionary) -> TDOutcome:
	var checked := session.validate_save(data)
	if not checked.ok: return checked
	var existing := load_game()
	if not existing.ok and existing.code != "NOT_FOUND": return existing
	var payload: String = JSON.stringify(data)
	var text: String = JSON.stringify({"schema_version":1,"payload":payload,"sha256":payload.sha256_text()})
	var temporary: String = path+".tmp"
	var file := FileAccess.open(temporary,FileAccess.WRITE)
	if file==null: return TDOutcome.new(false,"WRITE_FAILED")
	file.store_string(text.left(text.length()/2) if interrupt_at=="partial_write" else text)
	file.flush(); var error: Error = file.get_error(); file.close()
	if error!=OK: return TDOutcome.new(false,"WRITE_FAILED")
	if interrupt_at=="partial_write": return TDOutcome.new(false,"INTERRUPTED")
	if not _read(temporary).ok: return TDOutcome.new(false,"READBACK_FAILED")
	if interrupt_at=="after_temp": return TDOutcome.new(false,"INTERRUPTED")
	var backup: String = path+".bak"
	if existing.ok:
		if FileAccess.file_exists(backup) and DirAccess.remove_absolute(backup)!=OK: return TDOutcome.new(false,"BACKUP_FAILED")
		if DirAccess.rename_absolute(path,backup)!=OK: return TDOutcome.new(false,"BACKUP_FAILED")
	if interrupt_at=="after_backup": return TDOutcome.new(false,"INTERRUPTED")
	if DirAccess.rename_absolute(temporary,path)!=OK: return TDOutcome.new(false,"REPLACE_FAILED")
	return TDOutcome.new(true,"SAVED")

func recover(use_temporary: bool = false) -> TDOutcome:
	var current := _read(path)
	if current.code=="UNSUPPORTED_VERSION": return current
	var source: String = path+(".tmp" if use_temporary else ".bak")
	var recovered := _read(source)
	if not recovered.ok: return recovered
	if FileAccess.file_exists(path):
		if DirAccess.rename_absolute(path,path+".preserved-%d" % Time.get_ticks_usec())!=OK: return TDOutcome.new(false,"PRESERVE_FAILED")
	if DirAccess.copy_absolute(source,path)!=OK: return TDOutcome.new(false,"RECOVER_FAILED")
	return _read(path)

func archive_for_new_game() -> TDOutcome:
	# Only called after the player explicitly confirms replacing the save slot.
	if _read(path).code=="UNSUPPORTED_VERSION": return TDOutcome.new(false,"UNSUPPORTED_VERSION")
	var suffix: String=".preserved-new-game-%d" % Time.get_ticks_usec()
	for source: String in [path,path+".bak",path+".tmp"]:
		if FileAccess.file_exists(source) and DirAccess.rename_absolute(source,source+suffix)!=OK: return TDOutcome.new(false,"PRESERVE_FAILED")
	return TDOutcome.new(true,"ARCHIVED")
