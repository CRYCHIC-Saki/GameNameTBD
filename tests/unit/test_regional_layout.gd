extends GutTest

func make_map(id: String, version: int=2) -> TDTownMap:
	var catalog:=TDTownCatalog.new();assert_true(catalog.load_file().ok)
	var map:=TDTownMap.new();map.layout_version=2
	var built:=map.build_economic_layout(catalog,TDTownMap.seed_of(id),version)
	assert_true(built.ok,built.code+":"+built.message)
	return map

func test_distinct_geography_all_roads_and_landmarks_reachable() -> void:
	var signatures: Dictionary={}
	for id: String in TDRegionalLayout.IDS:
		var map:=make_map(id)
		var start:=TDRegionalLayout.port(id)
		var queue: Array[Vector2i]=[start];var reached: Dictionary={start:true};var cursor: int=0
		while cursor<queue.size():
			var at:=queue[cursor];cursor+=1
			for direction: Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
				var next:=at+direction
				if next.x<0 or next.y<0 or next.x>=73 or next.y>=73 or reached.has(next): continue
				if map.terrain_at(next).walkable and map.plot_at(next.x,next.y).is_empty(): reached[next]=true;queue.append(next)
		var disconnected: Array=[]
		for at: Vector2i in map.roads:
			if not reached.has(at): disconnected.append(at)
		assert_eq(disconnected.size(),0,id+" connected streets")
		for p: Dictionary in map.plots: assert_has(reached,Vector2i(p.approach_x,p.approach_y),id+":"+str(p.id))
		var signature:=str(map.roads).sha256_text()
		assert_false(signatures.has(signature),"unique street plan "+id);signatures[signature]=true
		assert_eq(map.commercial_parcels().size(),6)

func test_japanese_island_is_surrounded_by_sea_and_has_bridges() -> void:
	var map:=make_map("tokyo")
	for n: int in 73:
		for at: Vector2i in [Vector2i(n,0),Vector2i(n,72),Vector2i(0,n),Vector2i(72,n)]:
			assert_eq(map.terrain_at(at).terrain_type,"water");assert_false(map.terrain_at(at).walkable)
	var bridges: int=0
	for at: Vector2i in map.roads:
		if map.terrain_at(at).surface_type=="bridge": bridges+=1
	assert_gt(bridges,0)

func test_map_economic_and_property_terrain_share_authority() -> void:
	for id: String in TDRegionalLayout.IDS:
		var map:=make_map(id);var geo:=TDEconomicGeography.new();geo.configure(id,map.plots,{},2)
		for at: Vector2i in [Vector2i(0,0),Vector2i(20,20),Vector2i(48,34),TDRegionalLayout.port(id)]:
			var terrain:=map.terrain_at(at);var cell:=geo.cell(at)
			for key: String in ["terrain_type","buildable","walkable","surface_type"]: assert_eq(cell[key],terrain[key],id+":"+key)
			assert_true(TDEconomicCell.validate(cell).ok)
		var copy:=TDRegionalLayout.definition(id);copy.port=[1,1]
		assert_ne(TDRegionalLayout.port(id),Vector2i(1,1),"configuration not shared mutable state")

func test_bad_configuration_and_impossible_branch_are_rejected() -> void:
	var raw: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(TDRegionalLayout.SOURCE))
	assert_true(TDRegionalLayout.validate(raw).ok)
	raw.towns.tokyo.plots.append(raw.towns.tokyo.plots[0].duplicate())
	assert_false(TDRegionalLayout.validate(raw).ok)
	assert_eq(TDRegionMigration.find_site(make_map("tokyo"),[0,0,72,72]),[])

func test_legacy_maps_remain_available_for_validation() -> void:
	var legacy:=make_map("tokyo",1);var current:=make_map("tokyo")
	assert_eq(legacy.region_id,"");assert_eq(current.region_id,"tokyo")
	assert_ne(legacy.roads,current.roads)
	assert_eq(legacy._by_id("competitor").x,int(TDPlannedTown.definition().plots.filter(func(p:Dictionary)->bool:return p.id=="competitor")[0].rect[0]))
