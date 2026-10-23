class_name TDResearchStore
extends RefCounted
## Independent research domain. Never opens the legacy shop save for writing.
var path: String
var validator: Callable
var interrupt_at: String=""

func _init(save_path: String, validate: Callable) -> void:
	path=save_path; validator=validate

func read_file(file_path: String) -> TDOutcome:
	if not FileAccess.file_exists(file_path): return TDOutcome.new(false,"NOT_FOUND")
	var file:=FileAccess.open(file_path,FileAccess.READ)
	if file==null: return TDOutcome.new(false,"READ_FAILED")
	if file.get_length()>2000000: return TDOutcome.new(false,"FILE_TOO_LARGE")
	var parser:=JSON.new()
	if parser.parse(file.get_as_text())!=OK: return TDOutcome.new(false,"INVALID_JSON")
	var raw: Variant=parser.data
	if not raw is Dictionary: return TDOutcome.new(false,"INVALID_JSON")
	if raw.get("schema_version")!=1: return TDOutcome.new(false,"UNSUPPORTED_VERSION")
	if not raw.get("payload") is String or raw.get("sha256")!=raw.payload.sha256_text(): return TDOutcome.new(false,"CHECKSUM_MISMATCH")
	if parser.parse(raw.payload)!=OK: return TDOutcome.new(false,"INVALID_JSON")
	var data: Variant=parser.data
	var check: TDOutcome=validator.call(data)
	return TDOutcome.new(true,"LOADED","",data) if check.ok else check

func load_game() -> TDOutcome:
	var result:=read_file(path)
	if not result.ok:
		result.data={"backup_available":read_file(path+".bak").ok,"temporary_available":read_file(path+".tmp").ok}
		if result.code=="NOT_FOUND" and (FileAccess.file_exists(path+".tmp") or FileAccess.file_exists(path+".bak")): result.code="INTERRUPTED_SAVE"
	return result

func save_game(data: Dictionary) -> TDOutcome:
	var check: TDOutcome=validator.call(data)
	if not check.ok: return check
	var before:=load_game()
	if not before.ok and before.code!="NOT_FOUND": return before
	var payload:=JSON.stringify(data)
	var text:=JSON.stringify({"schema_version":1,"payload":payload,"sha256":payload.sha256_text()})
	var tmp:=path+".tmp"
	var file:=FileAccess.open(tmp,FileAccess.WRITE)
	if file==null: return TDOutcome.new(false,"WRITE_FAILED")
	file.store_string(text.left(text.length()/2) if interrupt_at=="partial_write" else text)
	file.flush(); var error:=file.get_error(); file.close()
	if error!=OK: return TDOutcome.new(false,"WRITE_FAILED")
	if interrupt_at=="partial_write": return TDOutcome.new(false,"INTERRUPTED")
	if not read_file(tmp).ok: return TDOutcome.new(false,"READBACK_FAILED")
	if interrupt_at=="after_temp": return TDOutcome.new(false,"INTERRUPTED")
	if before.ok:
		if FileAccess.file_exists(path+".bak") and DirAccess.remove_absolute(path+".bak")!=OK: return TDOutcome.new(false,"BACKUP_FAILED")
		if DirAccess.rename_absolute(path,path+".bak")!=OK: return TDOutcome.new(false,"BACKUP_FAILED")
	if interrupt_at=="after_backup": return TDOutcome.new(false,"INTERRUPTED")
	if DirAccess.rename_absolute(tmp,path)!=OK: return TDOutcome.new(false,"REPLACE_FAILED")
	return TDOutcome.new(true,"SAVED")

func recover(use_temporary: bool=false) -> TDOutcome:
	if read_file(path).code=="UNSUPPORTED_VERSION": return TDOutcome.new(false,"UNSUPPORTED_VERSION")
	var source:=path+(".tmp" if use_temporary else ".bak")
	var recovered:=read_file(source)
	if not recovered.ok: return recovered
	if FileAccess.file_exists(path) and DirAccess.rename_absolute(path,path+".preserved-%d"%Time.get_ticks_usec())!=OK: return TDOutcome.new(false,"PRESERVE_FAILED")
	if DirAccess.copy_absolute(source,path)!=OK: return TDOutcome.new(false,"RECOVER_FAILED")
	return read_file(path)
