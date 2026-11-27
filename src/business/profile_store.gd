class_name TDProfileStore
extends RefCounted
## Slot IDs are fixed identifiers, never display names or user-supplied paths.
const SLOT_COUNT := 6
const STORY := "story"
const DAILY := "daily"
const CHECKPOINTS := [STORY, DAILY, ""]
var root: String
var validator: Callable
var interrupt_at: String = ""
var _validated_slots: Dictionary = {}

func _init(directory: String, validate: Callable) -> void:
	root=directory.trim_suffix("/");validator=validate

func slot_id(index: int) -> String:
	return "slot-%02d" % index

func valid_id(id: String) -> bool:
	for index: int in range(1,SLOT_COUNT+1):
		if id==slot_id(index): return true
	return false

func path_for(id: String, kind: String = "") -> String:
	if not valid_id(id) or kind not in CHECKPOINTS: return ""
	return root.path_join(id + ("." + kind if not kind.is_empty() else "") + ".json")

func backend(id: String, kind: String = "") -> TDResearchStore:
	# Bind identity into validation before any backup recovery or file replacement.
	var store := TDResearchStore.new(path_for(id, kind), _validate_slot.bind(id, kind))
	store.interrupt_at=interrupt_at
	return store

func _validate_slot(raw: Variant, id: String, kind: String) -> TDOutcome:
	# The backend has already checked the on-disk checksum. Skip domain checks
	# only for the same validated payload, even if the file was written again.
	var key := path_for(id, kind)
	var previous: Dictionary = _validated_slots.get(key, {})
	if previous.get("validator") == validator and previous.get("payload") == raw:
		return TDOutcome.new(true, "VALIDATED")
	var result: TDOutcome = validator.call(raw)
	if not result.ok:
		return result
	if raw.slot_id != id:
		return TDOutcome.new(false, "SLOT_MISMATCH")
	if raw.get("checkpoint", "") != kind:
		return TDOutcome.new(false, "CHECKPOINT_MISMATCH")
	_validated_slots[key] = {"validator": validator, "payload": raw.duplicate(true)}
	return result

func load_slot(id: String, kind: String = "latest") -> TDOutcome:
	if not valid_id(id) or (kind != "latest" and kind not in CHECKPOINTS):
		return TDOutcome.new(false,"INVALID_SLOT")
	var recovery:=_recover_deletion(id)
	if not recovery.ok: return recovery
	if kind != "latest": return backend(id, kind).load_game()
	return _latest_checkpoint(_read_checkpoints(id))

func _read_checkpoints(id: String) -> Dictionary:
	var results := {}
	for kind: String in CHECKPOINTS:
		var result := backend(id, kind).load_game()
		if result.code != "NOT_FOUND": results[kind] = result
	return results

func _latest_checkpoint(checkpoints: Dictionary) -> TDOutcome:
	var latest := TDOutcome.new(false, "NOT_FOUND")
	for result: TDOutcome in checkpoints.values():
		if latest.code == "NOT_FOUND" or (result.ok and (not latest.ok or int(result.data.updated_at) > int(latest.data.updated_at))):
			latest = result
	return latest

func save_slot(id: String, data: Dictionary, kind: String = "") -> TDOutcome:
	if not valid_id(id) or data.get("slot_id")!=id or kind not in CHECKPOINTS:
		return TDOutcome.new(false,"INVALID_SLOT")
	var recovery:=_recover_deletion(id)
	if not recovery.ok: return recovery
	if DirAccess.make_dir_recursive_absolute(root)!=OK: return TDOutcome.new(false,"DIRECTORY_FAILED")
	var payload := data.duplicate()
	if not kind.is_empty(): payload.checkpoint = kind
	return backend(id, kind).save_game(payload)

func recover_slot(id: String, temporary: bool = false, kind: String = "") -> TDOutcome:
	if not valid_id(id) or kind not in CHECKPOINTS: return TDOutcome.new(false,"INVALID_SLOT")
	return backend(id, kind).recover(temporary)

func slots() -> Array[Dictionary]:
	var rows: Array[Dictionary]=[]
	for index: int in range(1,SLOT_COUNT+1):
		var id := slot_id(index)
		var recovery := _recover_deletion(id)
		var checkpoints := _read_checkpoints(id) if recovery.ok else {}
		var result := _latest_checkpoint(checkpoints) if recovery.ok else recovery
		var row: Dictionary={"slot_id":id,"ok":result.ok,"code":result.code,"empty":result.code=="NOT_FOUND"}
		if result.ok:
			var data:=result.data
			row.merge({"title":data.title,"day":data.shop.day,"money_cents":data.shop.money_cents,"updated_at":data.updated_at,"unlocked":data.research.unlocked.size()})
		else: row.merge(result.data)
		var entries: Array[Dictionary] = []
		for kind: String in checkpoints:
			var checkpoint: TDOutcome = checkpoints[kind]
			var entry := {"kind":kind, "ok":checkpoint.ok, "code":checkpoint.code}
			if checkpoint.ok:
				var data := checkpoint.data
				var state: Dictionary = data.get("story", {}).get("revised", {})
				entry.merge({"day":data.shop.day,"chapter":TDRevisedMainline.finished_chapter(state),
					"story_title":TDRevisedMainline.checkpoint_title(state)})
			else: entry.merge(checkpoint.data)
			entries.append(entry)
		row.checkpoints = entries
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
	for kind: String in [STORY, DAILY]:
		var checkpoint := path_for(id, kind).get_file()
		if name in [checkpoint, checkpoint+".bak", checkpoint+".tmp"] or name.begins_with(checkpoint+".preserved-"):
			return true
	var prefix:=id+".json"
	return name==prefix or name in [prefix+".bak",prefix+".tmp"] or name.begins_with(prefix+".preserved-") or name.begins_with(prefix+".before-map-v2") or name.begins_with(prefix+".before-region-v2") or name.begins_with(prefix+".before-jiangnan-v2") or name.begins_with(prefix+".before-shiomi-v3") or name.begins_with(prefix+".before-egret-v4") or name.begins_with(prefix+".before-egret-v5") or name.begins_with(prefix+".before-egret-v6") or name.begins_with(prefix+".before-egret-v7") or name.begins_with(prefix+".before-egret-v8") or name.begins_with(prefix+".before-egret-v9") or name.begins_with(prefix+".before-egret-v10") or name.begins_with(prefix+".before-egret-v11") or name.begins_with(prefix+".before-egret-v12") or name.begins_with(prefix+".before-three-towns")

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

func backup_map_migration(id: String, regional: bool=false, jiangnan: bool=false, regions_retired: bool=false) -> TDOutcome:
	if not valid_id(id): return TDOutcome.new(false,"INVALID_SLOT")
	var source:=path_for(id)
	var checked:=load_slot(id, "")
	if not checked.ok: return checked
	var suffix: String=".before-region-v2" if regional else ".before-map-v2"
	if regional and checked.data.get("region_layout_version",1)==2: suffix=".before-shiomi-v3"
	if regional and checked.data.get("region_layout_version",1)==3: suffix=".before-egret-v4"
	if regional and int(checked.data.get("region_layout_version",1)) in [4,5,6,7,8,9,10,11]: suffix=".before-egret-v12"
	if jiangnan and not regional: suffix=".before-jiangnan-v2"
	if regions_retired: suffix=".before-three-towns"
	var destination:=source+suffix+".bak"
	if FileAccess.file_exists(destination):
		# Never replace the first original. A prior interrupted migration can retry.
		if FileAccess.get_sha256(source)==FileAccess.get_sha256(destination): return TDOutcome.new(true,"MIGRATION_BACKUP_EXISTS")
		destination=source+suffix+"."+FileAccess.get_sha256(source).substr(0,12)+".bak"
	if not FileAccess.file_exists(destination) and DirAccess.copy_absolute(source,destination)!=OK: return TDOutcome.new(false,"MIGRATION_BACKUP_FAILED")
	if FileAccess.get_sha256(source)!=FileAccess.get_sha256(destination): return TDOutcome.new(false,"MIGRATION_BACKUP_MISMATCH")
	return TDOutcome.new(true,"MIGRATION_BACKUP_READY","",{"path":destination})
