extends GutTest
var profiles: Array[TDGameProfile]=[]

func after_each() -> void:
	for p: TDGameProfile in profiles: p.close()
	profiles.clear()

func legacy() -> TDGameProfile:
	var p:=TDGameProfile.new();profiles.append(p);assert_true(p.error.ok,p.error.code)
	p.slot_id="slot-01";p.region_layout_version=1
	for id: String in TDRegionalLayout.IDS: p.commerce.expansion.state.parcels.erase(id)
	p._wire_commerce();assert_true(p.error.ok)
	return p

func raw_save(p: TDGameProfile) -> Dictionary:
	var raw:=p.snapshot();raw.erase("region_layout_version");raw.erase("region_migration")
	assert_true(TDGameProfile.validate_save(raw).ok)
	return raw

func test_old_owned_properties_branches_inventory_and_books_survive_once() -> void:
	var p:=legacy()
	assert_true(p.shop.world_adjustment(300000,"fixture","测试资金").ok)
	assert_true(p.recommend_route("tokyo","fixture-route").ok)
	for y: int in [48,53]: assert_true(p.branches.open_store("tokyo",[6,y,3,4],"cn","manager.steady","fixture:%d"%y).ok)
	var raw:=raw_save(p);var before:=raw.duplicate(true)
	var next:=TDGameProfile.new();profiles.append(next)
	var result:=next.restore(raw);assert_true(result.ok,result.code+":"+result.message)
	assert_true(next.region_migrated_on_load)
	assert_eq(raw,before,"candidate conversion never mutates caller snapshot")
	var saved:=next.snapshot();assert_true(TDGameProfile.validate_save(saved).ok)
	assert_eq(saved.shop,before.shop);assert_eq(saved.research,before.research);assert_eq(saved.world,before.world)
	for id: String in before.branches.stores:
		var old: Dictionary=before.branches.stores[id];var now: Dictionary=saved.branches.stores[id]
		for key: String in old:
			if key not in ["rect","place"]: assert_eq(now[key],old[key],id+":"+key)
		assert_eq(now.rect.slice(2),old.rect.slice(2))
		assert_has(saved.region_migration.branches,id)
	for id: String in TDRegionalLayout.IDS:
		for key: String in before.economy.expansion.parcels[id]:
			var old: Dictionary=before.economy.expansion.parcels[id][key];var now: Dictionary=saved.economy.expansion.parcels[id][key]
			for field: String in ["owner_id","store_id","land_cents","version"]: assert_eq(now[field],old[field])
	var again:=TDGameProfile.new();profiles.append(again)
	assert_true(again.restore(saved).ok);assert_false(again.region_migrated_on_load)
	assert_eq(again.snapshot(),saved)

func test_corrupt_geometry_or_unknown_version_does_not_change_live_profile() -> void:
	var p:=legacy();var raw:=raw_save(p)
	var target:=TDGameProfile.new();profiles.append(target);target.slot_id="slot-02"
	var before:=target.snapshot()
	raw.region_layout_version=99
	assert_eq(target.restore(raw).code,"UNKNOWN_REGION_VERSION");assert_eq(target.snapshot(),before)
	raw.erase("region_layout_version");raw.economy.expansion.parcels.tokyo["competitor:shop:0"].x=1
	assert_false(target.restore(raw).ok);assert_eq(target.snapshot(),before)

func test_backup_preserves_exact_old_bytes_and_new_save_reloads() -> void:
	var p:=legacy();var raw:=raw_save(p)
	var store:=TDProfileStore.new("res://artifacts/travel-r1/save/%d"%Time.get_ticks_usec(),TDGameProfile.validate_save)
	assert_true(store.save_slot("slot-01",raw).ok)
	var bytes:=FileAccess.get_file_as_bytes(store.path_for("slot-01"))
	var next:=TDGameProfile.new();profiles.append(next);assert_true(next.restore(raw).ok)
	var backup:=store.backup_map_migration("slot-01",true);assert_true(backup.ok)
	assert_eq(FileAccess.get_file_as_bytes(backup.data.path),bytes)
	next.persistence=store.save_slot;assert_true(next.save().ok)
	assert_eq(int(store.load_slot("slot-01").data.region_layout_version),2)
	assert_eq(FileAccess.get_file_as_bytes(backup.data.path),bytes)
	assert_true(store._slot_file("slot-01",str(backup.data.path).get_file()))
