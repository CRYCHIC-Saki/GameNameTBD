extends GutTest
var shop: TDShopSession
var store: TDShopStore
var path: String

func before_each() -> void:
	DirAccess.make_dir_recursive_absolute("res://artifacts/test-storage")
	var catalog:=TDServiceCatalog.new(); assert_true(catalog.load_file().ok)
	shop=TDShopSession.new(catalog,"save-test",2)
	path="res://artifacts/test-storage/shop-%d.json" % Time.get_ticks_usec()
	store=TDShopStore.new(path,shop)

func test_boundary_roundtrip_and_actual_interrupted_writes() -> void:
	assert_true(store.save_game(shop.snapshot()).ok)
	var old: Dictionary=shop.snapshot()
	shop.buy({"tomato":1000},"p")
	for point: String in ["partial_write","after_temp"]:
		store.interrupt_at=point; assert_eq(store.save_game(shop.snapshot()).code,"INTERRUPTED")
		assert_eq(store.load_game().data,old)
	store.interrupt_at="after_backup"; assert_eq(store.save_game(shop.snapshot()).code,"INTERRUPTED")
	assert_eq(store.load_game().code,"INTERRUPTED_SAVE")
	assert_true(store.recover().ok); assert_eq(store.load_game().data,old)
	store.interrupt_at=""; assert_true(store.save_game(shop.snapshot()).ok)
	assert_eq(store.load_game().data,shop.snapshot())

func test_corrupt_unknown_and_live_save_do_not_overwrite() -> void:
	assert_true(store.save_game(shop.snapshot()).ok)
	shop.open_day(); assert_eq(store.save_game(shop.snapshot()).code,"NOT_AT_BOUNDARY")
	var file:=FileAccess.open(path,FileAccess.WRITE); file.store_string('{"schema_version":99}'); file.close()
	var bytes: PackedByteArray=FileAccess.get_file_as_bytes(path)
	assert_eq(store.load_game().code,"UNSUPPORTED_VERSION")
	assert_eq(store.recover().code,"UNSUPPORTED_VERSION")
	shop.close_early(); assert_false(store.save_game(shop.snapshot()).ok)
	assert_eq(FileAccess.get_file_as_bytes(path),bytes)

func test_checksum_corruption_is_not_treated_as_new_game() -> void:
	store.save_game(shop.snapshot()); shop.buy({"egg":1000},"p"); store.save_game(shop.snapshot())
	var envelope: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path)); envelope.payload+=' '
	var file:=FileAccess.open(path,FileAccess.WRITE); file.store_string(JSON.stringify(envelope)); file.close()
	assert_eq(store.load_game().code,"CHECKSUM_MISMATCH")
	assert_false(store.save_game(shop.snapshot()).ok)
	assert_true(store.recover().ok)
	assert_eq(store.load_game().data.money_cents,30000)

func test_first_save_interruption_recovers_only_valid_temporary_on_request() -> void:
	store.interrupt_at="partial_write"; assert_eq(store.save_game(shop.snapshot()).code,"INTERRUPTED")
	assert_eq(store.load_game().code,"INTERRUPTED_SAVE")
	assert_false(store.load_game().data.temporary_available)
	assert_false(store.recover(true).ok)
	assert_true(FileAccess.file_exists(path+".tmp"))
	# A separate empty slot demonstrates a complete temporary write before rename.
	store=TDShopStore.new(path+"-complete",shop); store.interrupt_at="after_temp"
	assert_eq(store.save_game(shop.snapshot()).code,"INTERRUPTED")
	assert_false(FileAccess.file_exists(path+"-complete"))
	assert_true(store.load_game().data.temporary_available)
	assert_true(store.recover(true).ok)
	assert_eq(store.load_game().data,shop.snapshot())
