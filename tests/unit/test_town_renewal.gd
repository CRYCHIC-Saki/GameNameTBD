extends GutTest

func test_three_meal_peaks_and_repeatable_bounded_schedule() -> void:
	var schedule:=TDMealSchedule.new();assert_true(schedule.error.ok)
	var events:=schedule.events(10000,101,2,"chengdu")
	assert_eq(events.size(),10000)
	assert_eq(events,schedule.events(10000,101,2,"chengdu"))
	assert_ne(events,schedule.events(10000,102,2,"chengdu"))
	var bounds_ok: bool=true;var sorted_ok: bool=true
	var near_peaks: int=0;var unusual: int=0;var prior: float=-1
	var counts: Dictionary={"breakfast":0,"lunch":0,"dinner":0,"off_peak":0}
	for row: Dictionary in events:
		bounds_ok=bounds_ok and row.minute>=480 and row.minute<=1559
		sorted_ok=sorted_ok and row.minute>=prior;prior=row.minute
		counts[row.period]+=1
		if (row.minute>=480 and row.minute<=600) or (row.minute>=660 and row.minute<=780) or (row.minute>=1020 and row.minute<=1140): near_peaks+=1
		else: unusual+=1
	assert_true(bounds_ok);assert_true(sorted_ok)
	assert_eq(counts,{"breakfast":2500,"lunch":3500,"dinner":3000,"off_peak":1000})
	assert_gt(near_peaks,8000);assert_gt(unusual,500)
	var bad:=schedule.config.duplicate(true);bad.peaks[0].sigma=0
	assert_false(TDMealSchedule.validate(bad).ok)

func test_daylight_changes_gradually_and_indoor_stays_readable() -> void:
	assert_eq(TDDaylight.sample(720).tint,Color.WHITE)
	assert_eq(TDDaylight.sample(480).period,"晨间")
	assert_eq(TDDaylight.sample(1100).period,"黄昏")
	assert_eq(TDDaylight.sample(1320).period,"夜晚")
	assert_gt(float(TDDaylight.sample(1320).lamps),.99)
	assert_eq(float(TDDaylight.sample(720).lamps),0.0)
	assert_gt(TDDaylight.sample(1320,true).tint.r,TDDaylight.sample(1320).tint.r)
	assert_lt(absf(TDDaylight.sample(1080).tint.r-TDDaylight.sample(1080.1).tint.r),.001)

func test_planned_map_terrain_roads_and_facilities() -> void:
	var world:=TDPhase3Session.new();world.map_version=2
	assert_true(world.load_default().ok);assert_true(world.build_home("chinese").ok)
	var map:=world.town_map
	assert_eq(map.extent,73)
	assert_false(map.is_walkable(54,30));assert_false(map.can_place(54,30,1,1))
	assert_eq(map.terrain_at(Vector2i(54,30)).terrain_type,"water")
	assert_true(map.is_walkable(54,23));assert_eq(map.terrain_at(Vector2i(54,23)).surface_type,"bridge")
	assert_false(map.is_walkable(30,2));assert_false(map.can_place(30,2,1,1))
	for x: int in range(19,23): assert_true(map.is_road(x,20))
	var connected:=map._connected_roads()
	for p: Dictionary in map.plots:
		if p.kind=="housing": continue
		assert_true(connected.has(Vector2i(p.approach_x,p.approach_y)),"reachable entrance "+str(p.id))
	assert_eq(map.factory_lots().size(),8)
	assert_eq(map.commercial_parcels().size(),6)
	assert_true(map.validate_cottage(map.choose_cottage()).ok)
	assert_ne(TDPlannedTown.branch_site(map,12,18),Vector2i(-1,-1))
	var invalid:=TDPlannedTown.definition();invalid.plots[0].rect=[72,30,4,4]
	assert_false(TDPlannedTown.validate(invalid).ok)
	var geography:=TDEconomicGeography.new();geography.configure("chengdu",map.plots,{},2)
	var river:=geography.cell(Vector2i(54,30))
	assert_eq(river.terrain_type,"water");assert_false(river.reachable)
	assert_true(TDEconomicCell.validate(river).ok)
	assert_true(geography.cell(Vector2i(54,23)).reachable)
	river.terrain_type="unknown";assert_false(TDEconomicCell.validate(river).ok)

func legacy_snapshot() -> Dictionary:
	var p:=TDGameProfile.new();p.slot_id="slot-01"
	p.world.map_version=1;p.world.town_map.cottage={};p.world._rebuild_map()
	p.world.factory_built["chengdu:factory-2"]=true;p.world._rebuild_map()
	p.commerce=TDWorldEconomy.new(p.service.config.costs,"chengdu",101,1)
	p._wire_commerce();p.initialize_residence()
	var raw:=p.snapshot();raw.schema_version=5;raw.world.erase("map_version")
	raw.residence={"schema_version":1,"anchor":"cottage_bed","plot":raw.residence.plot}
	p.close();return raw

func test_legacy_geometry_migration_preserves_progress_and_rejects_tamper() -> void:
	var raw:=legacy_snapshot()
	assert_true(TDGameProfile.validate_save(raw).ok)
	var before:=raw.duplicate(true)
	var result:=TDMapMigration.convert(raw)
	assert_true(result.ok,result.code)
	if not result.ok: return
	assert_eq(raw,before,"migration does not mutate input")
	assert_eq(result.data.shop,raw.shop);assert_eq(result.data.research,raw.research)
	assert_eq(result.data.characters,raw.characters);assert_eq(result.data.layout,raw.layout)
	assert_eq(result.data.world.factory_built,raw.world.factory_built)
	assert_eq(result.data.economy.society,raw.economy.society)
	assert_true(TDGameProfile.validate_save(result.data).ok)
	for town: String in raw.economy.expansion.parcels:
		for id: String in raw.economy.expansion.parcels[town]:
			for field: String in ["owner_id","store_id","version","land_cents"]: assert_eq(result.data.economy.expansion.parcels[town][id][field],raw.economy.expansion.parcels[town][id][field])
	assert_eq(TDMapMigration.convert(result.data).data,result.data,"idempotent")
	var malformed:=result.data.duplicate(true)
	malformed.economy.expansion.parcels.chengdu["competitor:shop:0"].x=54
	assert_false(TDGameProfile.validate_save(malformed).ok,"cannot forge ownership on river")
	var loaded:=TDGameProfile.new();assert_true(loaded.restore(raw).ok)
	assert_true(loaded.map_migrated_on_load);assert_eq(loaded.world.map_version,2)
	assert_true(TDGameProfile.validate_save(loaded.snapshot()).ok)
	loaded.close()

func test_new_profile_extended_service_and_late_open_no_backfill() -> void:
	var p:=TDGameProfile.new();assert_true(p.error.ok,p.error.code)
	p.characters.clock.minute=1020
	var expected: int=p.commerce.meal_events().filter(func(e:Dictionary)->bool:return e.minute<1020).size()
	assert_true(p.shop.open_day().ok)
	assert_eq(int(p.commerce.state.day_stats.opportunities),expected,"missed breakfast/lunch spent outside player shop")
	assert_true(p.shop.snapshot().orders.is_empty())
	assert_true(p.shop.advance(361).ok)
	assert_eq(p.shop.snapshot().phase,"OPEN","still open after old six hour limit")
	assert_true(p.shop.close_for_night().ok)
	assert_eq(p.shop.snapshot().phase,"SETTLED")
	var cents: int=int(p.shop.snapshot().money_cents)
	assert_true(p.shop.close_for_night().ok);assert_eq(int(p.shop.snapshot().money_cents),cents)
	p.close()

func test_old_branch_and_largest_home_keep_their_size_and_ownership() -> void:
	var raw:=legacy_snapshot()
	raw.world.home_size="huge";raw.world.home_w=12;raw.world.home_h=18
	raw.world.branch_open=true;raw.world.branch_town="paris";raw.world.branch_size="large"
	raw.world.branch_w=6;raw.world.branch_h=9;raw.world.branch_x=2;raw.world.branch_y=2
	assert_true(TDGameProfile.validate_save(raw).ok)
	var result:=TDMapMigration.convert(raw);assert_true(result.ok,result.code)
	if not result.ok: return
	assert_true(TDGameProfile.validate_save(result.data).ok)
	assert_eq(result.data.world.home_size,"huge")
	assert_eq(int(result.data.world.home_w)*int(result.data.world.home_h),216)
	assert_eq(result.data.world.branch_town,"paris")
	var remote:=TDTownMap.new();remote.layout_version=2
	var world:=TDPhase3Session.new();world.load_default()
	remote.build(world.catalog,TDTownMap.seed_of("paris"))
	var w: Dictionary=result.data.world
	assert_true(remote.can_place(int(w.branch_x),int(w.branch_y),6,9))
	assert_true(remote._touches_road(int(w.branch_x),int(w.branch_y),6,9))
