extends GutTest

func test_map_labels_and_walking_services_share_the_eight_neighborhoods() -> void:
	var profile := TDGameProfile.new()
	profile.slot_id="slot-01"
	var live := profile.world.town_map
	var copy := TDTravelCatalog.map_for(profile,"chengdu")
	var atlas := TDTravelMapView.new()
	atlas.maps={"chengdu":copy}
	add_child_autofree(atlas)
	var zones := {}
	for zone: Dictionary in TDPlannedTown.panorama_zones(live): zones[zone.id]=zone.at
	assert_eq(atlas._jiangnan_zones,TDPlannedTown.panorama_zones(live))
	assert_eq(zones.size(),8)
	assert_lt(zones.inn.x,zones.square.x)
	assert_gt(zones.inn.y,zones.square.y)
	assert_lt(zones.fresh_market.y,zones.pickle_lane.y)
	assert_lt(zones.crafts.y,zones.fresh_market.y)
	assert_gt(zones.night_market.y,zones.square.y)
	assert_gt(zones.diner_bank.x,zones.square.x)
	assert_gt(zones.pavilion.y,zones.diner_bank.y)
	assert_eq(live.plot_at(30,20).id,"player_diner")
	assert_eq(live.plot_at(9,25).id,"hotel")
	assert_eq(live.plot_at(27,27).id,"snack_street")
	assert_eq(live.plot_at(16,11).id,"market-mid")
	assert_eq(live.plot_at(38,20).id,"commercial_street:bank")
	assert_gt(TDHarbor.ARRIVAL.x,50)
	assert_eq(copy.roads,live.roads)
	profile.close()

func test_actual_map_services_open_the_same_shop_and_return_from_the_diner() -> void:
	var app := load("res://src/app/main.tscn").instantiate() as TDApplication
	app.settings_path="res://artifacts/approved-jiangnan/tests/%d/settings.json"%Time.get_ticks_usec()
	add_child_autofree(app)
	var shell := app.game_shell
	shell.automatic_time=false
	assert_true(shell.create_game("slot-01","江南地图测试").ok)
	shell.guide.dialogue.finish_now()
	shell.profile.story.beat="done"
	var town := shell.town
	var map := town.session.town_map
	assert_true(shell.travel("restaurant").ok)
	shell._object("town")
	assert_eq(shell.location,"town")
	assert_eq(town._player_cell(),town._diner_door())
	assert_eq(town.facing_plot().get("id",""),"player_diner")
	assert_true(town._can_stand(town._player.position))
	for id: String in ["market-small","market-mid","commercial_street:bank"]:
		var plot := map._by_id(id)
		town._player.position=town._origin()+(Vector2(plot.approach_x,plot.approach_y)+Vector2.ONE*.5)*town.cell_size()
		assert_true(town._can_stand(town._player.position),id)
		assert_eq(town.facing_plot().get("id",""),id)
		town._interact()
		assert_true(is_instance_valid(shell._modal),id+" opened")
		if id.begins_with("market"): assert_eq(shell.profile.world.selected_market,id)
		shell._close_dialog()
	var landing := TDPlannedTown.pavilion_landing()
	town._player.position=town._origin()+Rect2(landing).get_center()*town.cell_size()
	assert_true(town._can_stand(town._player.position))
	assert_false(map.can_place(landing.position.x,landing.position.y,1,1))
	shell.go_title()
	await wait_process_frames(2)

func test_reference_bridges_guide_routes_and_buildable_grass() -> void:
	var app := load("res://src/app/main.tscn").instantiate() as TDApplication
	app.settings_path = "res://artifacts/approved-jiangnan/tests/%d/settings.json" % Time.get_ticks_usec()
	add_child_autofree(app)
	var shell := app.game_shell
	shell.automatic_time = false
	assert_true(shell.create_game("slot-01").ok)
	shell.guide.dialogue.finish_now()
	var town := shell.town
	var unit := TDPlannedTown.REFERENCE_PIXELS_PER_CELL
	assert_eq(town._reference_map.scene_file_path, TDJiangnanReferenceArt.MAP_PATH)
	var layer := town._reference_map.get_node("Land") as TileMapLayer
	var lawn := Vector2(638,258) * town.cell_size() / unit
	var feet := town._origin() + lawn
	var tile := layer.local_to_map(layer.transform.affine_inverse() * lawn)
	var painted := layer.get_cell_atlas_coords(tile)
	assert_true(town._can_stand(feet), "Painted lawn is walkable in the actual town")
	layer.erase_cell(tile)
	assert_false(town._can_stand(feet), "An erased land cell stops actual player movement")
	layer.set_cell(tile,0,painted)
	assert_true(town._can_stand(feet), "The restored cell accepts the player again")
	var bridge := town._reference_map.get_node("BridgeDeck") as TileMapLayer
	for crest: Vector2 in [Vector2(954,242),Vector2(904,568)]:
		var local := crest * town.cell_size() / unit
		var stone := bridge.local_to_map(bridge.transform.affine_inverse() * local)
		var atlas := bridge.get_cell_atlas_coords(stone)
		assert_true(town._can_stand(town._origin()+local), "The top of each arch supports the player's feet")
		bridge.erase_cell(stone)
		assert_false(town._can_stand(town._origin()+local), "The visible rail and fascia cannot support the player")
		bridge.set_cell(stone,0,atlas)
	for pixel: Vector2 in [Vector2(952, 248), Vector2(897, 575), Vector2(1379, 647), Vector2(1360, 674), Vector2(809, 769)]:
		assert_true(town._reference_escort_can_stand(pixel / unit), "Visible stone or wharf at %s" % pixel)
	for pixel: Vector2 in [Vector2(952, 289), Vector2(898, 616), Vector2(1382, 710), Vector2(430, 41)]:
		assert_false(town._reference_escort_can_stand(pixel / unit), "Water or dense forest at %s" % pixel)
	for span: Array in [
		[Vector2(879,262),Vector2(921,250),Vector2(953,242),Vector2(990,247),Vector2(1048,269)],
		[Vector2(827,589),Vector2(857,579),Vector2(895,568),Vector2(930,572),Vector2(981,588)],
		[Vector2(761,743),Vector2(781,748),Vector2(796,761),Vector2(811,771),Vector2(840,781)],
		[Vector2(1357,627),Vector2(1357,646),Vector2(1357,672),Vector2(1357,687)],
	]:
		for index: int in range(1, span.size()):
			town._player.position = town._origin() + span[index-1] * town.cell_size() / unit
			var next_point := town._origin() + Vector2(span[index]) * town.cell_size() / unit
			assert_true(town._feet_on_road(next_point), "Walkable connected segment at %s" % span[index])
	var start := Vector2(TDHarbor.GUIDE_STOP) + Vector2.ONE * .5
	var destination := Vector2(town._aling_market_cell()) + Vector2.ONE * .5
	var route := town.reference_walk_path(start, destination)
	assert_gt(route.size(), 60, "The visible roads connect the port and Chen's stop")
	if not route.is_empty():
		assert_eq(route[0], start)
		assert_eq(route[-1], destination)
		for index: int in range(1, route.size()):
			var from := route[index - 1]
			var to := route[index]
			assert_true(town._reference_escort_can_stand(from.lerp(to, .5)), "Guide never cuts a blocked shoreline")
	assert_false(TDPlannedTown.reference_buildable_cell(Vector2i(41, 10)), "A public bridge cannot be leased")
	assert_false(TDPlannedTown.reference_buildable_cell(Vector2i(18, 20)), "Banyan and the market square are public")
	assert_true(TDPlannedTown.reference_buildable_cell(Vector2i(32, 11)), "West-bank lawn can remain unmarked")
	assert_true(TDPlannedTown.reference_buildable_cell(Vector2i(67, 18)), "East-bank lawn can remain unmarked")
	shell.go_title()
	await wait_process_frames(2)
