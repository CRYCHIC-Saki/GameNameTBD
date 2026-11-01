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
	var result := backend(id).load_game()
	if result.ok and result.data.slot_id!=id: return TDOutcome.new(false,"SLOT_MISMATCH")
	return result

func save_slot(id: String, data: Dictionary) -> TDOutcome:
	if not valid_id(id) or data.get("slot_id")!=id: return TDOutcome.new(false,"INVALID_SLOT")
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

func backup_map_migration(id: String) -> TDOutcome:
	if not valid_id(id): return TDOutcome.new(false,"INVALID_SLOT")
	var source:=path_for(id)
	var checked:=load_slot(id)
	if not checked.ok: return checked
	var destination:=source+".before-map-v2.bak"
	if FileAccess.file_exists(destination):
		# Never replace the first original. A prior interrupted migration can retry.
		if FileAccess.get_sha256(source)==FileAccess.get_sha256(destination): return TDOutcome.new(true,"MIGRATION_BACKUP_EXISTS")
		destination=source+".before-map-v2."+FileAccess.get_sha256(source).substr(0,12)+".bak"
	if not FileAccess.file_exists(destination) and DirAccess.copy_absolute(source,destination)!=OK: return TDOutcome.new(false,"MIGRATION_BACKUP_FAILED")
	if FileAccess.get_sha256(source)!=FileAccess.get_sha256(destination): return TDOutcome.new(false,"MIGRATION_BACKUP_MISMATCH")
	return TDOutcome.new(true,"MIGRATION_BACKUP_READY","",{"path":destination})
