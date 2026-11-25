extends GutTest

func test_towns_keep_local_lawn_water_and_the_four_away_street_materials() -> void:
	var swatch_size := Vector2i(120,120)
	var streets := preload("res://assets/town/map-surfaces-v2.png").get_image()
	if streets.is_compressed(): streets.decompress()
	streets.convert(Image.FORMAT_RGBA8)
	var ids := ["chengdu","tokyo","paris"]
	for row: int in ids.size():
		var surfaces_by_column := [["lawn","grass","woodland"],["stone"],[],["water"]]
		for col: int in surfaces_by_column.size():
			if ids[row]=="chengdu" and col==1: continue
			var start := Vector2i(roundi(streets.get_width()*col/4.0),roundi(streets.get_height()*row/5.0))
			var end := Vector2i(roundi(streets.get_width()*(col+1)/4.0),roundi(streets.get_height()*(row+1)/5.0))
			var original := streets.get_region(Rect2i(start,end-start).grow(-2))
			original.resize(swatch_size.x,swatch_size.y,Image.INTERPOLATE_NEAREST)
			# An interior patch excludes the atlas seam treatment. Check it again one full repeat away.
			var patch := Vector2i.ONE*TDTownScenery.SCALE
			var expected := original.get_region(Rect2i(patch,patch)).get_data()
			var ground := Image.create(240,240,false,Image.FORMAT_RGBA8)
			for surface: String in surfaces_by_column[col]:
				for at: Vector2i in [Vector2i.ONE,Vector2i.ONE+swatch_size/patch]:
					TDTownScenery.paint_cell(ground,at,{at:surface},ids[row])
					assert_true(ground.get_region(Rect2i(at*patch,patch)).get_data()==expected,"%s %s at %s" % [ids[row],surface,at])

func test_reference_flagstones_have_grass_at_both_edges() -> void:
	var scene := TDJiangnanReferenceArt.make_scene()
	add_child_autofree(scene)
	var road := scene.get_node("Streets") as TileMapLayer
	var land := scene.get_node("Land") as TileMapLayer
	assert_true(_painted_at(road,Vector2(1221,296)))
	for pixel: Vector2 in [Vector2(1201,296),Vector2(1240,296)]:
		assert_false(_painted_at(road,pixel),"Verge has ordinary grass")
		assert_true(_painted_at(land,pixel))

func test_reference_road_bends_along_the_east_residences() -> void:
	var scene := TDJiangnanReferenceArt.make_scene()
	add_child_autofree(scene)
	var road := scene.get_node("Streets") as TileMapLayer
	assert_true(_painted_at(road,Vector2(1383,124)))
	assert_true(_painted_at(road,Vector2(1392,169)))
	assert_false(_painted_at(road,Vector2(1399,125)))
	assert_false(_painted_at(road,Vector2(1374,169)))

func _painted_at(layer: TileMapLayer, source_pixel: Vector2) -> bool:
	var world := source_pixel * TDJiangnanReferenceArt.WORLD_SIZE.x / TDJiangnanReferenceArt.SIZE.x
	return TDJiangnanReferenceArt._contains_tile(layer,world)

func test_jiangnan_puddles_and_worn_thresholds_stay_on_passable_dry_stone() -> void:
	var map := make_map("chengdu",2,1)
	var detail := TDTownScenery.JiangnanPaving
	var size := TDTownScenery.SCALE
	var surface := TDTownScenery.smooth_surfaces(map)
	var affected: Array[Vector2i]=[]
	affected.assign(detail.PUDDLES.keys())
	assert_lt(affected.size(),map.roads.size()/100,"puddles are isolated low spots")
	for bank: Vector2i in detail.BRIDGE_STEPS:
		affected.append(bank)
		affected.append(bank+Vector2i.DOWN)
	var frame := Image.create(map.extent*size,map.extent*size,false,Image.FORMAT_RGBA8)
	for at: Vector2i in affected:
		assert_eq(surface[at],"stone")
		assert_true(map.is_walkable(at.x,at.y))
		var cell := Rect2i(at*size,Vector2i.ONE*size)
		TDTownScenery.paint(frame,cell,1)
		var before := frame.get_region(cell)
		TDTownScenery.paint_cell(frame,at,{at:"stone"})
		assert_ne(frame.get_region(cell).get_data(),before.get_data(),"dry stone carries local weathering "+str(at))

func test_jiangnan_square_gates_continue_the_blue_street_material() -> void:
	var map := make_map("chengdu",2,1)
	var size := TDTownScenery.SCALE
	var court := TDTownScenery.PublicSquare.bounds(map)
	var ink := TDTownScenery.JiangnanDistrictTerrain.Pedestrian.walk_stone()
	var ground := TDTownScenery.ground(map).get_image()
	var gates := TDTownScenery.PublicSquare.entrances(map,court)
	assert_eq(gates.size(),4)
	for gate: Dictionary in gates:
		var side: Vector2i = gate.side
		var tangent := Vector2i(absi(side.y),absi(side.x))
		var mouth := Vector2i(gate.edge)*size+Vector2i.ONE*(size/2)+side*(size/2)
		var street_center := (int(gate.depth)-1)*size+size/2
		var gaps := 0
		for along: int in range(-12,street_center+1):
			for across: int in range(-14,15):
				var pixel := mouth+side*along+tangent*across
				if ground.get_pixelv(pixel)!=ink.get_pixelv(pixel%ink.get_size()): gaps+=1
		assert_eq(gaps,0,"stone walkway from the market court across the verge to the street "+str(side))

func test_all_residential_lots_and_free_frontages_use_local_lawn() -> void:
	for id: String in TDTravelCatalog.IDS:
		var map := make_map(id)
		if id == "chengdu":
			var catalog := TDTownCatalog.new()
			assert_true(catalog.load_file().ok)
			map.build(catalog,TDTownMap.seed_of(id),"small",true)
		var ground := TDTownScenery.smooth_surfaces(map)
		var homes := 0
		for p: Dictionary in map.plots:
			if p.kind not in ["housing","player_cottage","urban_village","rich_district"]: continue
			homes += 1
			var lot := Rect2i(p.x,p.y,p.w,p.h)
			for y: int in range(lot.position.y-1,lot.end.y+1):
				for x: int in range(lot.position.x-1,lot.end.x+1):
					var at := Vector2i(x,y)
					var raw_surface: String = map.terrain_at(at).surface_type
					if raw_surface in ["stone","bridge","water","woodland"]:
						assert_eq(ground[at],raw_surface,id+" protected terrain "+str(at))
					elif lot.has_point(at) or map.plot_at(x,y).is_empty():
						assert_eq(ground[at],"lawn","%s %s %s" % [id,p.id,at])
		assert_gt(homes,0,id+" checked actual residences")

func test_all_five_walkable_maps_reserve_pavement_for_roads() -> void:
	for id: String in TDTravelCatalog.IDS:
		var map := make_map(id,2,1 if id=="chengdu" else 2)
		var drawn := TDTownScenery.smooth_surfaces(map)
		var plaza := map._by_id("plaza")
		var civic := Rect2i(plaza.x,plaza.y,plaza.w,plaza.h)
		var adjacent := map._by_id("landmark")
		if adjacent.get("x",-1)==civic.end.x and adjacent.y==plaza.y and adjacent.h==plaza.h:
			civic.size.x+=int(adjacent.w)
		var mismatches: Array[Vector2i] = []
		var dry_count := 0
		var decks := 0
		for at: Vector2i in drawn:
			var terrain := map.terrain_at(at)
			if terrain.terrain_type=="water":
				var separate_lookout := id=="chengdu" and TDLegacyJiangnanLayout.pavilion_landing().has_point(at)
				var through_bridge: bool = terrain.walkable and not separate_lookout
				if through_bridge: decks+=1
				if drawn[at]!=("bridge" if through_bridge else "water"): mismatches.append(at)
			elif map.is_road(at.x,at.y):
				var grass_approach := id=="chengdu" and Rect2i(24,20,5,2).has_point(at)
				if drawn[at]!=("lawn" if grass_approach else "stone"): mismatches.append(at)
			elif civic.has_point(at) and terrain.terrain_type=="plain":
				if drawn[at]!="civic_paving": mismatches.append(at)
			else:
				dry_count+=1
				if drawn[at] not in ["grass","lawn","woodland"]: mismatches.append(at)
		assert_eq(mismatches.slice(0,6),[],id+" street and river mask")
		assert_gt(dry_count,500,id+" covers land beyond the residential blocks")
		assert_gt(decks,0,id+" includes real crossings")

func test_bridge_decks_run_between_the_banks_and_cast_a_face_over_water() -> void:
	var size := TDTownScenery.SCALE
	for town: String in TDTravelCatalog.IDS:
		var surface := {}
		var scene := Image.create(7*size,7*size,false,Image.FORMAT_RGBA8)
		for y: int in 7:
			for x: int in 7:
				var at := Vector2i(x,y)
				var span := x
				var lane := y
				surface[at]="water" if span in [2,3,4] else "grass"
				if lane in [2,3,4]: surface[at]="bridge" if span in [2,3,4] else "stone"
		for at: Vector2i in surface: TDTownScenery.paint_cell(scene,at,surface,town)
		var bank := Vector2i(1,3)
		var side := Vector2i(3,5)
		var tile := Vector2i.ONE*size
		var street_before := scene.get_region(Rect2i(bank*size,tile)).get_data()
		var water_before := scene.get_region(Rect2i(side*size,tile))
		TDTownScenery.RiverBridge.paint(scene,surface,town,size)
		assert_eq(scene.get_region(Rect2i(bank*size,tile)).get_data(),street_before,town+" leaves the bank entrance open")
		var after := scene.get_region(Rect2i(side*size,tile))
		assert_false(after.get_data()==water_before.get_data(),town+" bridge side projects over the water")
		assert_eq(after.get_pixel(size-1,size-1),water_before.get_pixel(size-1,size-1),town+" water still visible below span")
		var deck := scene.get_region(Rect2i(Vector2i(3,3)*size,tile))
		var road := Image.create(size,size,false,Image.FORMAT_RGBA8)
		TDTownScenery.paint(road,Rect2i(Vector2i.ZERO,tile),1,town)
		assert_false(deck.get_data()==road.get_data(),town+" centre of a wide bridge has its own deck")

func test_irregular_crossings_keep_all_dry_bank_pixels() -> void:
	for row: Array in [["tokyo",Vector2i(44,45)],["paris",Vector2i(59,52)]]:
		var map := make_map(row[0])
		var center: Vector2i = row[1]
		assert_eq(map.terrain_at(center).surface_type,"stone")
		var surfaces := {}
		var size := TDTownScenery.SCALE
		var scene := Image.create(9*size,9*size,false,Image.FORMAT_RGBA8)
		for y: int in 9:
			for x: int in 9:
				var at := Vector2i(x,y)
				surfaces[at] = map.terrain_at(center+at-Vector2i(4,4)).surface_type
		for at: Vector2i in surfaces: TDTownScenery.paint_cell(scene,at,surfaces,row[0])
		var before := scene.duplicate() as Image
		TDTownScenery.RiverBridge.paint(scene,surfaces,row[0],size)
		var changed_decks := 0
		var leaked: Array[Vector2i] = []
		for at: Vector2i in surfaces:
			var rect := Rect2i(at*size,Vector2i.ONE*size)
			if before.get_region(rect).get_data()==scene.get_region(rect).get_data(): continue
			if surfaces[at]=="bridge": changed_decks+=1
			elif surfaces[at]!="water": leaked.append(at)
		assert_eq(leaked,[],str(row[0])+" stone and grass up to the waterline")
		assert_gt(changed_decks,0)

func make_map(id: String, version: int=2, jiangnan_revision: int=2) -> TDTownMap:
	var catalog:=TDTownCatalog.new();assert_true(catalog.load_file().ok)
	var map:=TDTownMap.new()
	map.jiangnan_layout_revision=jiangnan_revision;map.layout_version=2
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
	assert_eq(legacy._by_id("competitor").x,int(TDLegacyJiangnanLayout.definition().plots.filter(func(p:Dictionary)->bool:return p.id=="competitor")[0].rect[0]))

func test_public_services_land_use_and_existing_buildable_sites_in_all_towns() -> void:
	# Every previously rentable rectangle of a legal size and frontage, captured
	# before reshaping the waterways, plus the newly fronted eastern quay in
	# Mexico (10 rectangles) and river market lane in Thailand (23 rectangles).
	var previous_leases := {
		"chengdu":"27defb44b733d0eab5a5ef96a9b2c4acf8fcef595e66f5da3b1483b22c89534e",
		"tokyo":"8dc3802563d0be29a54431d080a394d4d3979d8aafebcf91c268e8c4984b0c1d",
		"paris":"3d763a3fa2c96ca5322aaa64db5ac2eb26892c96ac5bf0c9edf8fd3b50279ce3"}
	for id: String in TDTravelCatalog.IDS:
		var map := make_map(id,2,1 if id=="chengdu" else 2)
		if id=="chengdu":
			var catalog:=TDTownCatalog.new()
			assert_true(catalog.load_file().ok)
			map.build(catalog,TDTownMap.seed_of(id),"small",true)
		var surfaces: Dictionary={}
		var free_prefix:=PackedInt32Array()
		var road_prefix:=PackedInt32Array()
		# One guard cell on each side permits testing all four street frontages.
		var stride:=map.extent+3
		free_prefix.resize(stride*stride)
		road_prefix.resize(stride*stride)
		for y: int in range(-1,map.extent+1):
			for x: int in range(-1,map.extent+1):
				var free:=0
				var road:=0
				if x>=0 and y>=0 and x<map.extent and y<map.extent:
					var t:=map.terrain_at(Vector2i(x,y))
					free=int(t.buildable and map.plot_at(x,y).is_empty())
					road=int(map.is_road(x,y))
					surfaces[t.surface_type]=true
				var i:=(y+2)*stride+x+2
				free_prefix[i]=free+free_prefix[i-1]+free_prefix[i-stride]-free_prefix[i-stride-1]
				road_prefix[i]=road+road_prefix[i-1]+road_prefix[i-stride]-road_prefix[i-stride-1]
		var signatures:=PackedByteArray()
		for h: int in range(3,13):
			for w: int in range(3,13):
				if w*h>108: continue
				for y: int in range(map.extent-h+1):
					for x: int in range(map.extent-w+1):
						var pos:=(y+1)*stride+x+1
						if _rect_sum(free_prefix,pos,w,h,stride)!=w*h: continue
						var horizontal:=_rect_sum(road_prefix,pos-stride,w,1,stride)+_rect_sum(road_prefix,pos+h*stride,w,1,stride)
						var vertical:=_rect_sum(road_prefix,pos-1,1,h,stride)+_rect_sum(road_prefix,pos+w,1,h,stride)
						if horizontal+vertical>0:
							signatures.append(x)
							signatures.append(y)
							signatures.append(w)
							signatures.append(h)
		assert_eq(signatures.hex_encode().sha256_text(),previous_leases[id],id+" preserves all previous leases in the historical layout")
		for s: String in ["lawn","square","quay","earth","water","grass"]: assert_has(surfaces,s,id)
		assert_true(map.apply_commercial_occupancy({}).ok)
		var geo:=TDEconomicGeography.new()
		geo.configure(id,map.plots,{},2)
		for kind: String in ["hotel","bank","market","plaza","landmark","urban_village","rich_district"]:
			var matches:=map.plots.filter(func(p:Dictionary)->bool:return p.kind==kind)
			assert_false(matches.is_empty(),id+":"+kind)
			if matches.is_empty(): continue
			var p:Dictionary=matches[0]
			# The home bamboo courtyard has a one-tile setback before the public lane.
			var doorstep_margin := 2 if id=="chengdu" and p.id=="rich_district" else 1
			assert_true(Rect2i(int(p.x),int(p.y),int(p.w),int(p.h)).grow(doorstep_margin).has_point(Vector2i(p.approach_x,p.approach_y)),id+":"+kind+" has a nearby entrance")
			var center:=Vector2i(int(p.x)+int(p.w)/2,int(p.y)+int(p.h)/2)
			var cell:=geo.cell(center)
			assert_eq(cell.zone_id,kind,id+":"+str(p.id))
			assert_eq(cell.district_id,map.terrain_at(center).district_id)
			assert_true(TDEconomicCell.validate(cell).ok)
		var water:=geo.cell(Vector2i(71,20) if id=="chengdu" else Vector2i(0,0))
		if not water.walkable: assert_eq(water.rent_quote_cents_per_day,0)

func test_bad_frontage_and_district_are_rejected() -> void:
	var raw: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(TDRegionalLayout.SOURCE))
	raw.towns.tokyo.frontages.plaza[0][3]=65
	assert_eq(TDRegionalLayout.validate(raw).code,"REGION_FRONTAGE_WIDTH")
	raw.towns.tokyo.districts[0].surface="typo"
	assert_eq(TDRegionalLayout.validate(raw).code,"REGION_DISTRICTS")

func test_jiangnan_inlet_water_and_footbridge_are_real_terrain() -> void:
	var map:=make_map("chengdu",2,1)
	var geo:=TDEconomicGeography.new()
	geo.configure("chengdu",map.plots,{},2)
	# Follow the water under the footbridge, from the main river back to it.
	var course: Array[Vector2i]=[Vector2i(55,27),Vector2i(56,27),Vector2i(57,27),Vector2i(58,27),Vector2i(58,28),Vector2i(59,28),Vector2i(59,29),Vector2i(60,29),Vector2i(60,30),Vector2i(60,31),Vector2i(59,31),Vector2i(58,31),Vector2i(58,32),Vector2i(57,32),Vector2i(56,32),Vector2i(55,32)]
	for at: Vector2i in course:
		var wet:=map.terrain_at(at)
		assert_eq(wet.terrain_type,"water",str(at))
		assert_false(wet.buildable)
		assert_eq(map.is_walkable(at.x,at.y),wet.surface_type=="bridge")
		assert_eq(geo.cell(at).surface_type,wet.surface_type)
	for x: int in range(58,63):
		var at:=Vector2i(x,30)
		assert_true(map.is_walkable(x,30),"public bank → footbridge → island")
		assert_true(geo.cell(at).reachable)
		if x in [60,61]: assert_eq(map.terrain_at(at).surface_type,"bridge")
	assert_eq(map.terrain_at(Vector2i(56,29)).surface_type,"grass")
	assert_true(map.is_walkable(69,34))

func test_player_collision_crosses_the_north_bridge_but_not_open_water() -> void:
	var profile:=TDGameProfile.new()
	var town:=TDTownWorld.new()
	town.session=profile.world;town.player_mode=true
	add_child_autofree(town)
	await get_tree().process_frame
	var scale_factor := TDJiangnanReferenceArt.world_scale(profile.world.town_map, town.cell_size())
	var to_world := func(pixel: Vector2) -> Vector2: return town._origin()+pixel*scale_factor
	town._player.position = to_world.call(Vector2(885,267))
	for pixel: Vector2 in [Vector2(916,258),Vector2(954,248),Vector2(990,254),Vector2(1044,270)]:
		var next: Vector2 = to_world.call(pixel)
		assert_true(town._feet_on_road(next), "Swept feet cross the actual curved stone deck")
		town._player.position = next
	town._player.position = to_world.call(Vector2(954,248))
	assert_false(town._feet_on_road(to_world.call(Vector2(954,289))),"Leaving the bridge toward the water is blocked")
	profile.close()

func _rect_sum(prefix: PackedInt32Array, pos: int, w: int, h: int, stride: int) -> int:
	var bottom:=pos+h*stride
	return prefix[bottom+w]-prefix[bottom]-prefix[pos+w]+prefix[pos]

func test_every_river_runs_to_its_open_sea_and_bridges_are_straight() -> void:
	var coastal_cells:={"chengdu":Vector2i(72,66),"tokyo":Vector2i(42,70),"paris":Vector2i(70,70)}
	for id: String in TDTravelCatalog.IDS:
		var map:=make_map(id,2,1 if id=="chengdu" else 2)
		var wet:={}
		var decks:={}
		var home_pier:=Rect2i(71,33,2,3)
		for y: int in map.extent:
			for x: int in map.extent:
				var at:=Vector2i(x,y)
				var t:=map.terrain_at(at)
				if t.terrain_type=="water":
					wet[at]=true
					if t.walkable and not (id=="chengdu" and (home_pier.has_point(at) or TDLegacyJiangnanLayout.pavilion_landing().has_point(at))): decks[at]=true
		# Independently follow contiguous water, including water under the bridges.
		var wave:Array[Vector2i]=[coastal_cells[id]]
		assert_true(wet.erase(wave[0]),id+" actual estuary")
		var i:=0
		while i<wave.size():
			var at:=wave[i]
			i+=1
			for d:Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
				if wet.erase(at+d): wave.append(at+d)
		# Only require river channels to drain to this sea. Other edges of an
		# inland town may have a separate narrow off-map sea background.
		var course:Array=TDPlannedTown.definition().get("rivers",[]) if id=="chengdu" else TDRegionalLayout.definition(id).rivers
		var sources:Array[Vector2i]=[]
		if id=="chengdu": sources.assign([Vector2i(54,4),Vector2i(60,30)])
		for line:Array in course:
			for p:Array in line:
				var at:=Vector2i(clampi(p[0],0,72),clampi(p[1],0,72))
				if map.terrain_at(at).terrain_type=="water": sources.append(at)
		assert_gt(sources.size(),0)
		for source:Vector2i in sources: assert_false(wet.has(source),id+" water flows from "+str(source))
		while not decks.is_empty():
			var first:Vector2i=decks.keys()[0]
			var component:Array[Vector2i]=[first]
			decks.erase(first)
			var bounds:=Rect2i(first,Vector2i.ONE)
			i=0
			while i<component.size():
				var at:=component[i]
				i+=1
				for d:Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
					if decks.erase(at+d):
						component.append(at+d)
						bounds=bounds.merge(Rect2i(at+d,Vector2i.ONE))
			assert_gt(bounds.size.x,bounds.size.y,id+" only east-west crossings "+str(bounds))
			assert_eq(component.size(),bounds.get_area(),id+" no longitudinal spurs")
			for y:int in range(bounds.position.y,bounds.end.y):
				for x:int in [bounds.position.x-1,bounds.end.x]:
					var bank:=map.terrain_at(Vector2i(x,y))
					assert_true(bank.walkable and bank.terrain_type=="plain",id+" connects both banks "+str(bounds))
