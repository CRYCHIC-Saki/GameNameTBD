extends GutTest

const Coast := preload("res://src/town/jiangnan_coast_art.gd")
const District := preload("res://src/town/jiangnan_district_terrain.gd")

func _main_map() -> TDTownMap:
	var catalog := TDTownCatalog.new()
	assert_true(catalog.load_file().ok)
	var map := TDTownMap.new()
	map.layout_version=2
	map.build(catalog,TDTownMap.seed_of("chengdu"),"small",true)
	return map

func test_approved_coast_is_shared_by_terrain_and_the_maps() -> void:
	var map := _main_map()
	var survey := TDPlannedTown.definition()
	assert_eq(map.extent,73)
	assert_eq(int(survey.coast_height),42)
	assert_eq(survey.bridge_spans.size(),2)
	assert_eq(map._connected_roads().size(),map.roads.size(),"public paths share a connected network")
	assert_gt(map.roads.size(),600)
	var streets := TDTownScenery.ground(map).get_image()
	var miniature := Coast.build(map,6,true)
	assert_eq(streets.get_size(),Vector2i.ONE*73*TDTownScenery.SCALE)
	assert_eq(miniature.get_size(),Vector2i(73,42)*6)
	for at: Vector2i in [Vector2i(46,1),Vector2i(41,14),Vector2i(46,29),Vector2i(69,37)]:
		assert_false(map.is_walkable(at.x,at.y),"channel or sea at %s" % at)
		assert_false(map.can_place(at.x,at.y,1,1),"wet ground is protected")
	for middle: Vector2i in [Vector2i(41,10),Vector2i(39,24)]:
		assert_eq(map.terrain_at(middle).surface_type,"bridge")
		assert_true(map.is_walkable(middle.x,middle.y))
	var dock := TDHarbor.lot("deck")
	assert_true(map.is_walkable(dock.position.x,dock.position.y))
	assert_false(map.can_place(dock.position.x,dock.position.y,1,1))

func test_ordinary_grass_on_both_banks_has_no_authored_markers() -> void:
	var map := _main_map()
	assert_eq(District.sites(map).size(),0)
	for region: Vector2i in [Vector2i(24,12),Vector2i(67,12),Vector2i(65,19)]:
		assert_eq(map.terrain_at(region).surface_type,"lawn")
		assert_true(map.terrain_at(region).buildable)
		assert_false(map.is_road(region.x,region.y))

func test_stone_is_drawn_for_the_fresh_market_and_scenery_keeps_map_data() -> void:
	var map := _main_map()
	var before := map.plots.duplicate(true)
	var roads := map.roads.duplicate()
	var frame := Image.create_empty(73*16,73*16,false,Image.FORMAT_RGBA8)
	var grass := Color("#8b9f57")
	frame.fill(grass)
	District.paint_approved_market(frame,map,16)
	var at := Vector2i(18,11)*16
	assert_ne(frame.get_pixelv(at),grass,"fresh market paving")
	assert_eq(frame.get_pixelv(Vector2i(26,12)*16),grass,"neighboring lawn")
	assert_eq(map.plots,before)
	assert_eq(map.roads,roads)

func test_town_uses_native_layers_and_sprites_and_accepts_cell_edits() -> void:
	var map := _main_map()
	var scene := TDJiangnanReferenceArt.make_scene()
	add_child_autofree(scene)
	assert_false(scene.has_node("MarketClay"),"no large clay sheets at the two markets")
	for id: String in ["Water","Land","Woodlands","Shore","GroundDetails","ContactShadows","Streets","Squares","QuayWall","Wharf","BridgeDeck"]:
		var layer := scene.get_node(id) as TileMapLayer
		assert_not_null(layer, id)
		assert_gt(layer.get_used_cells().size(), 50, id + " contains individual editor cells")
	assert_gt(scene.get_node("Props").get_child_count(), 200)
	var land := scene.get_node("Land") as TileMapLayer
	var at := Vector2(640,260) * TDJiangnanReferenceArt.world_scale(map, TDJiangnanReferenceArt.CELL_SIZE)
	var tile := land.local_to_map(land.transform.affine_inverse() * at)
	assert_true(TDJiangnanReferenceArt.terrain_walkable(scene, at))
	var atlas := land.get_cell_atlas_coords(tile)
	land.erase_cell(tile)
	assert_false(TDJiangnanReferenceArt.terrain_walkable(scene, at), "Erasing native land changes the gameplay surface")
	land.set_cell(tile,0,atlas)
	assert_true(TDJiangnanReferenceArt.terrain_walkable(scene, at))
	var entries := TDJiangnanReferenceArt.facades(map,TDJiangnanReferenceArt.CELL_SIZE,Vector2.ZERO)
	var seen := {}
	for part: Dictionary in entries:
		seen[part.reference_id] = part
		assert_almost_eq(part.rect.size.aspect(), (part.art as Texture2D).get_size().aspect(), .002)
	assert_eq(seen.size(),entries.size(),"Stable independent scene objects")
	for id: String in ["diner","chen-food-shop","bank","plaza_banyan","harbor-terminal","ferry-junk"]:
		assert_has(seen,id)
	assert_eq(seen.diner.plot.id, "player_diner")
	assert_eq(seen["harbor-terminal"].plot.id, TDHarbor.ID)
	assert_gt(seen.plaza_banyan.bases.size(),0)

func test_parcel_centers_follow_the_playable_tile_layers() -> void:
	var map := _main_map()
	var scene := TDJiangnanReferenceArt.make_scene()
	add_child_autofree(scene)
	var mismatch: Array[Vector2i] = []
	var layers := {"BridgeDeck":"bridge","Wharf":"quay","Squares":"square","Streets":"stone","Woodlands":"woodland","Land":"lawn"}
	for y: int in 42:
		for x: int in 73:
			var pos := (Vector2(x,y)+Vector2.ONE*.5)*TDJiangnanReferenceArt.CELL_SIZE
			var expected := "water"
			for layer: String in layers:
				if TDJiangnanReferenceArt._contains_tile(scene.get_node(layer),pos):
					expected = layers[layer]
					break
			var surface: String = map.terrain_at(Vector2i(x,y)).surface_type
			if surface=="sea": surface="water"
			if surface=="sand": surface="lawn"
			if surface!=expected: mismatch.append(Vector2i(x,y))
	assert_eq(mismatch,[],"Every displayed parcel center follows the native surface")

func test_quay_walkway_and_wet_side_have_distinct_economic_properties() -> void:
	var map := _main_map()
	var geo := TDEconomicGeography.new()
	geo.configure("chengdu", map.plots, {}, 2)
	var dry := geo.cell(Vector2i(56,28))
	var sea := geo.cell(Vector2i(57,29))
	assert_eq(dry.surface_type,"quay")
	assert_true(dry.reachable)
	assert_false(dry.buildable)
	assert_almost_eq(float(dry.travel_minutes.station),2.6,.001)
	assert_eq(sea.surface_type,"sea")
	assert_false(sea.reachable)
	assert_false(sea.buildable)
	assert_eq(sea.rent_quote_cents_per_day,0)
	assert_eq(sea.land_value_cents,0)
	assert_false(map.branch_ground_available(Vector2i(56,28)))
