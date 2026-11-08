class_name TDProfileStore
extends RefCounted
## Slot IDs are fixed identifiers, never display names or user-supplied paths.
const SLOT_COUNT := 6
var root: String
var validator: Callable
var interrupt_at: String = ""

func _init(directory: String, validate: Callable) -> void:
	root=directory.trim_suffix("/");validator=validate

func slot_id(index: int) -> String:
	return "slot-%02d" % index

func valid_id(id: String) -> bool:
	for index: int in range(1,SLOT_COUNT+1):
		if id==slot_id(index): return true
	return false

func path_for(id: String) -> String:
	return root.path_join(id+".json") if valid_id(id) else ""

func backend(id: String) -> TDResearchStore:
	# Bind identity into validation before any backup recovery or file replacement.
	var check:=func(raw:Variant)->TDOutcome:
		var result:TDOutcome=validator.call(raw)
		if result.ok and raw.slot_id!=id: return TDOutcome.new(false,"SLOT_MISMATCH")
		return result
	var store := TDResearchStore.new(path_for(id),check)
	store.interrupt_at=interrupt_at
	return store

func load_slot(id: String) -> TDOutcome:
	if not valid_id(id): return TDOutcome.new(false,"INVALID_SLOT")
	var recovery:=_recover_deletion(id)
	if not recovery.ok: return recovery
	var result := backend(id).load_game()
	if result.ok and result.data.slot_id!=id: return TDOutcome.new(false,"SLOT_MISMATCH")
	return result

func save_slot(id: String, data: Dictionary) -> TDOutcome:
	if not valid_id(id) or data.get("slot_id")!=id: return TDOutcome.new(false,"INVALID_SLOT")
	var recovery:=_recover_deletion(id)
	if not recovery.ok: return recovery
	if DirAccess.make_dir_recursive_absolute(root)!=OK: return TDOutcome.new(false,"DIRECTORY_FAILED")
	return backend(id).save_game(data)

func recover_slot(id: String, temporary: bool = false) -> TDOutcome:
	if not valid_id(id): return TDOutcome.new(false,"INVALID_SLOT")
	return backend(id).recover(temporary)

func slots() -> Array[Dictionary]:
	var rows: Array[Dictionary]=[]
	for index: int in range(1,SLOT_COUNT+1):
		var id:=slot_id(index);var result:=load_slot(id)
		var row: Dictionary={"slot_id":id,"ok":result.ok,"code":result.code,"empty":result.code=="NOT_FOUND"}
		if result.ok:
			var data:=result.data
			row.merge({"title":data.title,"day":data.shop.day,"money_cents":data.shop.money_cents,"updated_at":data.updated_at,"unlocked":data.research.unlocked.size()})
		else: row.merge(result.data)
		rows.append(row)
	return rows

func latest() -> String:
	var id: String="";var stamp: int=-1
	for row: Dictionary in slots():
		if row.ok and int(row.updated_at)>stamp: stamp=int(row.updated_at);id=row.slot_id
	return id

func archive_slot(id: String) -> TDOutcome:
	if not valid_id(id): return TDOutcome.new(false,"INVALID_SLOT")
	var recovery:=_recover_deletion(id)
	if not recovery.ok: return recovery
	var names: Array[String]=[]
	if not DirAccess.dir_exists_absolute(root): return TDOutcome.new(false,"NOT_FOUND")
	for name: String in DirAccess.get_files_at(root):
		if _slot_file(id,name): names.append(name)
	if names.is_empty(): return TDOutcome.new(false,"NOT_FOUND")
	names.sort()
	var archive:=root.path_join("deleted").path_join(id+"-"+str(Time.get_unix_time_from_system()).replace(".","-"))
	if DirAccess.make_dir_recursive_absolute(archive)!=OK: return TDOutcome.new(false,"DELETE_DIRECTORY_FAILED")
	var manifest: Dictionary={"slot_id":id,"complete":false,"files":{}}
	for name: String in names: manifest.files[name]=FileAccess.get_sha256(root.path_join(name))
	if not _write_delete_manifest(archive,manifest): return TDOutcome.new(false,"DELETE_MANIFEST_FAILED")
	for index: int in names.size():
		var name:=names[index]
		# Crash injection leaves a recoverable journal, just like a process exit here.
		if index==1 and interrupt_at=="delete_after_first": return TDOutcome.new(false,"DELETE_INTERRUPTED")
		if (index==1 and interrupt_at=="delete_move_failed") or DirAccess.rename_absolute(root.path_join(name),archive.path_join(name))!=OK:
			var rolled:=_rollback_delete(archive,manifest)
			return TDOutcome.new(false,"DELETE_MOVE_FAILED" if rolled.ok else rolled.code)
	# The journal is immutable. A separate verified commit marker avoids truncating
	# recovery instructions if power is lost while marking the deletion complete.
	var marker:=FileAccess.open(archive.path_join("committed"),FileAccess.WRITE)
	if marker!=null:
		marker.store_string(FileAccess.get_sha256(archive.path_join("manifest.json")));marker.flush();marker.close()
	if not _delete_committed(archive):
		var rolled:=_rollback_delete(archive,manifest)
		return TDOutcome.new(false,"DELETE_MANIFEST_FAILED" if rolled.ok else rolled.code)
	return TDOutcome.new(true,"SLOT_DELETED","存档位已腾空。原文件保留在本机删除归档中。",{"archive":archive})

func _slot_file(id: String, name: String) -> bool:
	var prefix:=id+".json"
	return name==prefix or name in [prefix+".bak",prefix+".tmp"] or name.begins_with(prefix+".preserved-") or name.begins_with(prefix+".before-map-v2") or name.begins_with(prefix+".before-region-v2")

func _write_delete_manifest(directory: String, data: Dictionary) -> bool:
	var path:=directory.path_join("manifest.json")
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file==null: return false
	file.store_string(JSON.stringify(data));file.flush();var ok:=file.get_error()==OK;file.close()
	return ok and JSON.parse_string(FileAccess.get_file_as_string(path))==data

func _recover_deletion(id: String) -> TDOutcome:
	var deleted:=root.path_join("deleted")
	if not DirAccess.dir_exists_absolute(deleted): return TDOutcome.new(true,"NO_DELETIONS")
	for name: String in DirAccess.get_directories_at(deleted):
		if not name.begins_with(id+"-"): continue
		var archive:=deleted.path_join(name)
		var path:=archive.path_join("manifest.json")
		if not FileAccess.file_exists(path): continue # No journal means no files were moved.
		var data: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
		if not data is Dictionary or data.get("slot_id")!=id or not data.get("files") is Dictionary or not data.get("complete") is bool: return TDOutcome.new(false,"DELETE_RECOVERY_REQUIRED",archive)
		if _delete_committed(archive): continue
		var restored:=_rollback_delete(archive,data)
		if not restored.ok: return restored
	return TDOutcome.new(true,"DELETE_RECOVERY_OK")

func _delete_committed(archive: String) -> bool:
	var marker:=archive.path_join("committed")
	return FileAccess.file_exists(marker) and FileAccess.get_file_as_string(marker)==FileAccess.get_sha256(archive.path_join("manifest.json"))

func _rollback_delete(archive: String, data: Dictionary) -> TDOutcome:
	for name: String in data.files:
		if not _slot_file(str(data.slot_id),name) or name.get_file()!=name: return TDOutcome.new(false,"DELETE_RECOVERY_REQUIRED")
		var source:=archive.path_join(name);var destination:=root.path_join(name)
		if FileAccess.file_exists(destination):
			if FileAccess.get_sha256(destination)!=data.files[name]: return TDOutcome.new(false,"DELETE_RECOVERY_CONFLICT")
		elif not FileAccess.file_exists(source) or FileAccess.get_sha256(source)!=data.files[name] or DirAccess.rename_absolute(source,destination)!=OK:
			return TDOutcome.new(false,"DELETE_RECOVERY_REQUIRED",archive)
	# Removing the journal after full rollback cannot hide a missing source file.
	if DirAccess.remove_absolute(archive.path_join("manifest.json"))!=OK: return TDOutcome.new(false,"DELETE_RECOVERY_REQUIRED")
	return TDOutcome.new(true,"DELETE_ROLLED_BACK")

func backup_map_migration(id: String, regional: bool=false) -> TDOutcome:
	if not valid_id(id): return TDOutcome.new(false,"INVALID_SLOT")
	var source:=path_for(id)
	var checked:=load_slot(id)
	if not checked.ok: return checked
	var suffix: String=".before-region-v2" if regional else ".before-map-v2"
	var destination:=source+suffix+".bak"
	if FileAccess.file_exists(destination):
		# Never replace the first original. A prior interrupted migration can retry.
		if FileAccess.get_sha256(source)==FileAccess.get_sha256(destination): return TDOutcome.new(true,"MIGRATION_BACKUP_EXISTS")
		destination=source+suffix+"."+FileAccess.get_sha256(source).substr(0,12)+".bak"
	if not FileAccess.file_exists(destination) and DirAccess.copy_absolute(source,destination)!=OK: return TDOutcome.new(false,"MIGRATION_BACKUP_FAILED")
	if FileAccess.get_sha256(source)!=FileAccess.get_sha256(destination): return TDOutcome.new(false,"MIGRATION_BACKUP_MISMATCH")
	return TDOutcome.new(true,"MIGRATION_BACKUP_READY","",{"path":destination})
