extends GutTest

var _profiles: Array[TDGameProfile] = []

func after_each() -> void:
	for profile: TDGameProfile in _profiles:
		profile.close()
	_profiles.clear()

func _profile() -> TDGameProfile:
	var profile := TDGameProfile.new()
	_profiles.append(profile)
	assert_true(profile.error.ok,profile.error.code)
	profile.slot_id="slot-01"
	return profile

func _old_profile() -> TDGameProfile:
	var profile := _profile()
	profile.world.town_map.cottage={}
	profile.world.town_map.jiangnan_layout_revision=1
	profile.world._rebuild_map()
	profile.commerce.expansion.state.parcels.erase("chengdu")
	profile._wire_commerce()
	assert_true(profile.initialize_residence().ok)
	profile.residence.stage="door"
	assert_true(profile.unlock_residence().ok)
	assert_true(profile.world.resize_home("huge").ok)
	assert_true(profile.shop.world_adjustment(300000,"jiangnan-fixture","测试资金").ok)
	var built := profile.branches.open_store("chengdu",[6,48,3,4],"cn","","jiangnan-fixture-branch")
	assert_true(built.ok,built.code)
	return profile

func test_old_paid_store_and_cottage_are_migrated_with_their_entitlements() -> void:
	var old := _old_profile()
	var raw := old.snapshot()
	raw.erase("jiangnan_layout_revision")
	raw.erase("jiangnan_migration")
	assert_true(TDGameProfile.validate_save(raw).ok)
	var original := raw.duplicate(true)
	var disk := TDProfileStore.new("res://artifacts/jiangnan-map-preview/slots/%d"%Time.get_ticks_usec(),TDGameProfile.validate_save)
	assert_true(disk.save_slot(old.slot_id,raw).ok)
	var original_bytes := FileAccess.get_file_as_bytes(disk.path_for(old.slot_id))
	var fresh := _profile()
	var result := fresh.restore(raw)
	assert_true(result.ok,result.code+":"+result.message)
	if not result.ok: return
	assert_true(fresh.jiangnan_migrated_on_load)
	assert_eq(raw,original,"Candidate migration never edits the source snapshot")
	assert_true(fresh.has_residence())
	assert_true(fresh.world.town_map.validate_cottage(fresh.residence.plot).ok)
	assert_eq(fresh.world.interior_grid(),TDRestaurantSizes.interior("huge"))
	assert_eq(fresh.world.town_map.diner_estate_span(),Vector2i(12,18))
	assert_eq(fresh.shop.snapshot().money_cents,original.shop.money_cents)
	var id := "player-branch:1"
	var updated: Dictionary = fresh.branches.state.stores[id]
	var previous: Dictionary = original.branches.stores[id]
	assert_eq(updated.rect.slice(2),previous.rect.slice(2))
	assert_ne(updated.rect,previous.rect,"The older y=48 site now lies offshore")
	for key: String in previous:
		if key not in ["place","rect"]: assert_eq(updated[key],previous[key],key)
	var plot := fresh.world.town_map._by_id(id)
	assert_true(fresh.world.town_map.is_road(plot.approach_x,plot.approach_y))
	for parcel: String in original.economy.expansion.parcels.chengdu:
		var was: Dictionary = original.economy.expansion.parcels.chengdu[parcel]
		var now: Dictionary = fresh.commerce.expansion.state.parcels.chengdu[parcel]
		for field: String in ["owner_id","store_id","land_cents","version"]:
			assert_eq(now[field],was[field],parcel+":"+field)
	var backup := disk.backup_map_migration(old.slot_id,false,true)
	assert_true(backup.ok,backup.code)
	assert_true(disk._slot_file(old.slot_id,backup.data.path.get_file()))
	fresh.persistence=disk.save_slot
	assert_true(fresh.save().ok)
	assert_eq(FileAccess.get_file_as_bytes(backup.data.path),original_bytes)
	var reread := disk.load_slot(old.slot_id)
	assert_true(reread.ok,reread.code)
	var restored := _profile()
	assert_true(restored.restore(reread.data).ok)
	assert_false(restored.jiangnan_migrated_on_load)
	assert_eq(restored.branches.state.stores[id],reread.data.branches.stores[id])

func test_invalid_old_branch_location_is_rejected_before_relocation() -> void:
	var raw := _old_profile().snapshot()
	raw.erase("jiangnan_layout_revision")
	raw.branches.stores["player-branch:1"].rect = [53,36,3,4]
	var current := _profile()
	var before := current.snapshot()
	assert_eq(current.restore(raw).code,"PROTECTED_BRANCH_GEOMETRY")
	assert_eq(current.snapshot(),before)

func test_branch_selection_uses_normal_roadside_grass_on_both_banks() -> void:
	var current := _profile()
	var map := current.world.town_map
	for columns: Vector2i in [Vector2i(2,40),Vector2i(46,69)]:
		var rect: Array = []
		for y: int in range(5,31):
			for x: int in range(columns.x,columns.y):
				if map.terrain_at(Vector2i(x,y)).surface_type != "lawn": continue
				if current.branches.quote("chengdu",[x,y,3,3],"cn").ok:
					rect = [x,y,3,3]
					break
			if not rect.is_empty(): break
		assert_false(rect.is_empty(),"An ordinary roadside site is available on each bank")
		if rect.is_empty(): continue
		assert_eq(map.terrain_at(Vector2i(rect[0],rect[1])).surface_type,"lawn")
		for dy: int in 3:
			for dx: int in 3:
				assert_true(TDPlannedTown.reference_buildable_cell(Vector2i(rect[0]+dx,rect[1]+dy)))
	for reserved: Dictionary in map.commercial_parcels():
		var rect := [reserved.x,reserved.y,reserved.w,reserved.h]
		for y: int in range(int(reserved.y),int(reserved.y+reserved.h)):
			for x: int in range(int(reserved.x),int(reserved.x+reserved.w)):
				assert_true(map.terrain_at(Vector2i(x,y)).buildable,reserved.id)
		assert_true(TDPlannedTown.reference_street_in_cell(Vector2i(reserved.approach_x,reserved.approach_y)),reserved.id)
		assert_eq(current.branches.quote("chengdu",rect,"cn").code,"PROTECTED_LAND",reserved.id)
	var port_site := [55,25,3,3]
	assert_eq(current.branches.quote("chengdu",port_site,"cn").code,"PROTECTED_LAND","Harbor ticket office")

func test_pre_survey_titles_move_to_dry_ground_and_preserve_ownership() -> void:
	var current := _profile()
	var old := current.snapshot()
	var titles: Dictionary = old.economy.expansion.parcels.chengdu
	for lease: Dictionary in TDPlannedTown.definition().commercial_parcels:
		var title: Dictionary = titles[lease.id]
		title.x=lease.rect[0]; title.y=lease.rect[1]
		title.approach_x=lease.approach[0]; title.approach_y=lease.approach[1]
	var restored := _profile()
	assert_true(restored.restore(old).ok)
	var result := restored.snapshot()
	assert_eq(result.shop.money_cents,old.shop.money_cents)
	for id: String in titles:
		var title: Dictionary = result.economy.expansion.parcels.chengdu[id]
		assert_eq(title.owner_id,titles[id].owner_id)
		assert_eq(title.store_id,titles[id].store_id)
		assert_eq(restored.world.town_map.terrain_at(Vector2i(title.x,title.y)).surface_type,"lawn")
		if not str(title.owner_id).is_empty(): assert_eq(title.land_cents,titles[id].land_cents)
	assert_true(TDGameProfile.validate_save(result).ok)

func test_preexisting_branch_retains_its_site_when_commercial_frontage_moves() -> void:
	var map := _profile().world.town_map
	var title: Dictionary=map.commercial_parcels()[0]
	var existing:=Rect2i(int(title.x),int(title.y),3,3)
	map.sync_survey_reservations({"old":{"town_id":"chengdu","rect":[existing.position.x,existing.position.y,3,3]}})
	for site: Dictionary in map.commercial_parcels():
		assert_false(existing.intersects(Rect2i(site.x,site.y,site.w,site.h)))
		assert_true(TDPlannedTown.reference_street_in_cell(Vector2i(site.approach_x,site.approach_y)))
	assert_eq(map.commercial_parcels()[0].id,title.id)
