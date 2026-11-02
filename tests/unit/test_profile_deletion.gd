extends GutTest
var store: TDProfileStore

func before_each() -> void:
	store=TDProfileStore.new("res://artifacts/homecoming/delete/%d"%Time.get_ticks_usec(),func(_raw:Variant)->TDOutcome:return TDOutcome.new(true))
	DirAccess.make_dir_recursive_absolute(store.root)

func put(name: String, value: String) -> void:
	var file:=FileAccess.open(store.root.path_join(name),FileAccess.WRITE);file.store_string(value);file.close()

func test_delete_archives_corrupt_primary_backups_and_migrations_without_parsing() -> void:
	var names: Array[String]=["slot-01.json","slot-01.json.bak","slot-01.json.tmp","slot-01.json.preserved-123","slot-01.json.before-map-v2.bak"]
	for name: String in names: put(name,"broken "+name)
	put("slot-02.json","other slot");put("slot-010.json","unrelated")
	var result:=store.archive_slot("slot-01");assert_true(result.ok,result.code)
	for name: String in names:
		assert_false(FileAccess.file_exists(store.root.path_join(name)))
		assert_eq(FileAccess.get_file_as_string(result.data.archive.path_join(name)),"broken "+name)
	assert_eq(store.load_slot("slot-01").code,"NOT_FOUND")
	assert_eq(FileAccess.get_file_as_string(store.root.path_join("slot-02.json")),"other slot")
	assert_eq(FileAccess.get_file_as_string(store.root.path_join("slot-010.json")),"unrelated")
	assert_eq(store.archive_slot("../slot-01").code,"INVALID_SLOT")
	assert_eq(store.archive_slot("slot-01").code,"NOT_FOUND")

func test_crash_after_one_move_rolls_back_on_new_store_before_loading() -> void:
	put("slot-01.json","primary");put("slot-01.json.bak","backup")
	store.interrupt_at="delete_after_first"
	assert_eq(store.archive_slot("slot-01").code,"DELETE_INTERRUPTED")
	var restarted:=TDProfileStore.new(store.root,store.validator)
	assert_eq(restarted.load_slot("slot-01").code,"INVALID_JSON")
	assert_eq(FileAccess.get_file_as_string(store.path_for("slot-01")),"primary")
	assert_eq(FileAccess.get_file_as_string(store.path_for("slot-01")+".bak"),"backup")
	assert_true(restarted.archive_slot("slot-01").ok)
	assert_eq(restarted.load_slot("slot-01").code,"NOT_FOUND")

func test_move_failure_rolls_back_and_conflicting_recovery_never_overwrites() -> void:
	put("slot-01.json","primary");put("slot-01.json.bak","backup")
	store.interrupt_at="delete_move_failed"
	assert_eq(store.archive_slot("slot-01").code,"DELETE_MOVE_FAILED")
	assert_eq(FileAccess.get_file_as_string(store.path_for("slot-01")),"primary")
	store.interrupt_at="delete_after_first";store.archive_slot("slot-01")
	put("slot-01.json","conflict")
	assert_eq(store.load_slot("slot-01").code,"DELETE_RECOVERY_CONFLICT")
	assert_eq(FileAccess.get_file_as_string(store.path_for("slot-01")),"conflict")
