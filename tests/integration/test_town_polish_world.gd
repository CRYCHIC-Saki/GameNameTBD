extends GutTest
const DRIVER=preload("res://tools/test_support/kitchen_input.gd")

func test_jiangnan_square_keeps_real_paths_between_distinct_groups() -> void:
	var profile := TDGameProfile.new()
	var town := TDTownWorld.new()
	town.session=profile.world
	town.player_mode=true
	add_child_autofree(town)
	await wait_physics_frames(2)
	var features := {}
	for piece: Dictionary in town._facades:
		if piece.has("reference_id"): features[piece.reference_id] = piece
	for kind: String in ["square-stage", "plaza_banyan", "square-upper-stall", "square-cart", "square-east-stool"]:
		assert_true(features.has(kind),kind+" visible in the real town")
	if features.has("plaza_banyan") and features.has("square-stage") and features.has("square-upper-stall"):
		var tree: Rect2 = features.plaza_banyan.rect
		var stage: Rect2 = features["square-stage"].rect
		var tea: Rect2 = features["square-upper-stall"].rect
		assert_lt(tea.get_center().x,tree.get_center().x,"vendors line the west side of the banyan")
		assert_lt(tree.get_center().x,stage.get_center().x,"theatre lies east of the banyan")
		assert_false(town._can_stand(features.plaza_banyan.bases[0].get_center()),"the banyan's trunk blocks feet")
		assert_false(town._can_stand(features["square-stage"].bases[0].get_center()),"the stage blocks feet")
	for step: int in 24:
		var across := town._origin()+Vector2(300+step*10,531)*TDJiangnanReferenceArt.world_scale(profile.world.town_map, town.cell_size())
		assert_true(town._can_stand(across),"open promenade in front of the trees and stalls at "+str(step))
	profile.close()

func test_three_towns_plant_banks_avenues_and_groves_in_local_species() -> void:
	var profile := TDGameProfile.new()
	var accents := {}
	for town: String in TDTravelCatalog.IDS:
		var map := TDTravelCatalog.map_for(profile,town)
		var plants := TDTownScenery.dressing(map)
		var habitats := {}
		var flowers := 0
		var repeated_feet := false
		var blocked := false
		var feet_seen := {}
		for plant: Dictionary in plants:
			var cell := Vector2i(Vector2(plant.feet).floor())
			var terrain := map.terrain_at(cell)
			if plant.habitat=="woodland":
				assert_eq(terrain.terrain_type,"hill","forest plants stay in the wooded fringe")
			else:
				blocked = blocked or map.is_road(cell.x,cell.y) or not terrain.walkable
			repeated_feet = repeated_feet or feet_seen.has(cell)
			feet_seen[cell]=true
			habitats[plant.habitat] = int(habitats.get(plant.habitat,0))+1
			if plant.index==3: flowers+=1
		# Egret's stone seawall and working quay occupy the waterfront.
		var expected := ["avenue","grove"] if town=="paris" else ["bank","avenue","grove"]
		if town=="paris":
			assert_true(map.terrain_at(Vector2i(TDTravelCatalog.harbor_rect(town).get_center())).walkable)
		for habitat: String in expected:
			assert_gte(int(habitats.get(habitat,0)),5,town+" has planted "+habitat)
		assert_false(blocked,town+" planting avoids public paths and water")
		assert_false(repeated_feet,town+" no stacked trunks")
		assert_gt(flowers,0,town+" uses its local signature planting")
		var tex: AtlasTexture=TDTravelCatalog.plant(town,3)
		assert_not_null(tex.atlas)
		accents[tex.region]=true
		print("GREENBELT ",town," ",plants.size()," plants ",habitats," signature ",flowers)
	assert_eq(accents.size(),TDTravelCatalog.IDS.size(),"each town draws a distinct signature plant")
	profile.close()

func test_chens_paved_walkway_leads_to_his_shop_and_story_door() -> void:
	var profile := TDGameProfile.new()
	var town := TDTownWorld.new()
	town.session=profile.world
	town.story=profile.story
	town.player_mode=true
	add_child_autofree(town)
	await wait_physics_frames(2)
	var map := profile.world.town_map
	var plot := map._by_id("market-small")
	var door := Vector2i(plot.approach_x,plot.approach_y)
	assert_true(map._connected_roads().has(door))
	assert_ne(town._aling_market_cell(),town._chen_cell())
	assert_true(town._can_stand(town.chen_door_point()))
	town._player.position=town.chen_door_point()
	assert_eq(town.facing_plot().get("id",""),"market-small")
	town.story.beat="soup"
	assert_true(town.at_chen_door())
	profile.close()

func test_visible_diner_base_blocks_steps_but_empty_part_of_plot_is_walkable() -> void:
	var profile := TDGameProfile.new()
	var town := TDTownWorld.new()
	town.session = profile.world
	town.player_mode = true
	add_child_autofree(town)
	await wait_physics_frames(2)
	var facade: Dictionary = town._facades.filter(func(item: Dictionary) -> bool: return item.get("plot", {}).get("id") == "player_diner")[0]
	var base: Rect2 = facade.bases[0]
	var door := Vector2(base.get_center().x, base.end.y + 64.0)
	town._player.position = door
	Input.action_press("world_up")
	await wait_physics_frames(25)
	Input.action_release("world_up")
	assert_lt(town._player.position.y, door.y)
	assert_gte(town._player.position.y, base.end.y + town.FOOT_RADIUS - 0.1)
	assert_eq(str(town.facing_plot().get("id", "")), "player_diner")
	var plot := profile.world.town_map._by_id("player_diner")
	var land := TDInteractionRange.plot_bounds(plot, town.cell_size(), town._origin())
	var empty := Vector2(minf(land.position.x-22.0, facade.rect.position.x-20.0), land.end.y-24.0)
	assert_true(town._can_stand(empty))
	assert_false((facade.rect as Rect2).has_point(empty))
	town._player.position = empty
	Input.action_press("world_up")
	await wait_physics_frames(12)
	Input.action_release("world_up")
	assert_lt(town._player.position.y, empty.y - 15.0, "Walking on visible empty land cannot hit the old plot rectangle")
	profile.close()

func test_town_perimeter_corners_and_facility_priority_through_real_input() -> void:
	var profile:=TDGameProfile.new();var town:=TDTownWorld.new()
	town.session=profile.world;town.player_mode=true;town.characters=profile.characters;town.story=profile.story
	profile.story.beat="done";profile.characters.sync_map(profile.world.town_map)
	add_child_autofree(town);await get_tree().process_frame
	var map:=profile.world.town_map;var tested: int=0
	for id: String in ["player_diner","market-small","market-mid","factory-1","commercial_street:bank"]:
		var p:=map._by_id(id);var r:=TDInteractionRange.plot_bounds(p,town.cell_size(),town._origin())
		var candidates: Array[Vector2]=[Vector2(r.position.x-20,r.get_center().y),Vector2(r.end.x+20,r.get_center().y),Vector2(r.get_center().x,r.position.y-20),Vector2(r.get_center().x,r.end.y+20),r.end+Vector2(18,18)]
		for at: Vector2 in candidates:
			if not town._can_stand(at): continue
			var border := TDInteractionRange.closest(at,r)
			var occupied_by_neighbor := false
			for other: Dictionary in map.plots:
				if other.id==id or other.kind in ["plaza","public_walk"] or not TDInteractionRange.facility(other): continue
				var bounds := TDInteractionRange.plot_bounds(other,town.cell_size(),town._origin())
				if at.distance_to(TDInteractionRange.closest(at,bounds))<=at.distance_to(border):
					occupied_by_neighbor=true
					break
			if occupied_by_neighbor: continue
			town._player.position=at;town._player.face(at-r.get_center())
			assert_eq(str(town.facing_plot().get("id","")),id,"Any reachable side: "+id+str(at));tested+=1
	assert_gte(tested,10)
	town.spawn_at_home();var actor: Dictionary=profile.characters.runtime.aling
	actor.cell=town._player_cell();actor.route=[];actor.phase="town"
	assert_eq(town._story_faced(),"aling","An NPC is actually in dialogue range")
	watch_signals(town);var driver:=DRIVER.new();driver.viewport=get_tree().root;driver.tap(KEY_E)
	assert_signal_emitted(town,"restaurant_requested");assert_false(town._talk_open())
	# No facility at this safe road stop, so the same E opens the existing daily conversation.
	var at:=profile.characters.safe_stop_near(Vector2i(32,12),"aling")
	actor.cell=at;actor.route=[];town._player.position=town._origin()+(Vector2(at)+Vector2(.5,.5))*town.cell_size()
	assert_true(town.facing_plot().is_empty());driver.tap(KEY_E)
	assert_true(town._talk_open());assert_eq(town._talk_view.talk.context.kind,"resident")
	town._dismiss_talk();profile.close()

func test_room_objects_use_edges_instead_of_one_front_anchor() -> void:
	var world:=load("res://src/world/kitchen_world.tscn").instantiate() as TDKitchenWorld
	world.single_fridge=true;add_child_autofree(world);await get_tree().process_frame
	for id: String in ["kitchen.board","kitchen.stove.left","kitchen.fridge","kitchen.serve"]:
		var station: Dictionary={}
		for row: Dictionary in world.stations():
			if row.id==id: station=row;break
		assert_false(station.is_empty(),id)
		if station.is_empty(): continue
		var r:=world.station_bounds(station)
		for at: Vector2 in [Vector2(r.position.x-6,r.end.y+18),Vector2(r.end.x+6,r.end.y+18),Vector2(r.get_center().x,r.end.y+30)]:
			world._player.position=at;world._player.face(Vector2.DOWN)
			assert_eq(str(world._station_at_player().get("id","")),id)
	var cottage:=TDCottageWorld.new();add_child_autofree(cottage);await get_tree().process_frame
	for at: Vector2 in [Vector2(770,340),Vector2(950,340),Vector2(865,400),Vector2(865,185)]:
		cottage.player.position=at;cottage.player.face(Vector2.DOWN);assert_eq(cottage.target(),"rest")

func test_ground_cache_is_read_only_and_does_not_change_buildability() -> void:
	var profile:=TDGameProfile.new();var map:=profile.world.town_map
	var before: Dictionary=profile.snapshot();var texture:=TDTownArt.ground(map)
	assert_same(TDTownArt.ground(map),texture)
	assert_eq(texture.get_width(),map.extent*TDTownScenery.SCALE)
	assert_eq(profile.snapshot(),before)
	profile.close()

func test_reference_tree_base_blocks_walkers_and_protects_the_site() -> void:
	var profile:=TDGameProfile.new();var map:=profile.world.town_map
	var town:=TDTownWorld.new();town.session=profile.world;town.player_mode=true;add_child_autofree(town)
	await wait_physics_frames(2)
	var foliage := town._facades.filter(func(e: Dictionary) -> bool: return e.get("reference_layer") == "foliage")
	assert_gte(foliage.size(), 20)
	var trees := foliage.filter(func(e: Dictionary) -> bool: return e.reference_id == "market_east_tree")
	assert_eq(trees.size(), 1)
	if not trees.is_empty():
		var base: Rect2 = trees[0].bases[0]
		town._player.position = Vector2(base.position.x-18,base.get_center().y)
		assert_not_null(town._player.move_and_collide(Vector2(40,0)),"The physical trunk matches its illustrated base")
		var at := Vector2i(((base.get_center()-town._origin())/town.cell_size()).floor())
		assert_false(TDPlannedTown.reference_buildable_cell(at))
	assert_true(TDPlannedTown.approved(map))
	profile.close()
