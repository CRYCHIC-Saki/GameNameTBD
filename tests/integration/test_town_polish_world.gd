extends GutTest
const DRIVER=preload("res://tools/test_support/kitchen_input.gd")

func test_town_perimeter_corners_and_facility_priority_through_real_input() -> void:
	var profile:=TDGameProfile.new();var town:=TDTownWorld.new()
	town.session=profile.world;town.player_mode=true;town.characters=profile.characters;town.story=profile.story
	profile.story.beat="done";profile.characters.sync_map(profile.world.town_map)
	add_child_autofree(town);await get_tree().process_frame
	var map:=profile.world.town_map;var tested: int=0
	for id: String in ["player_diner","market-small","market-mid","factory-1","commercial_street:bank"]:
		var p:=map._by_id(id);var r:=TDInteractionRange.plot_bounds(p,town.CELL,town._origin())
		var candidates: Array[Vector2]=[Vector2(r.position.x-20,r.get_center().y),Vector2(r.end.x+20,r.get_center().y),Vector2(r.get_center().x,r.position.y-20),Vector2(r.get_center().x,r.end.y+20),r.end+Vector2(18,18)]
		for at: Vector2 in candidates:
			var cell:=Vector2i((at-town._origin())/town.CELL)
			if not map.is_walkable(cell.x,cell.y): continue
			town._player.position=at;town._player.face(at-r.get_center())
			assert_eq(str(town.facing_plot().get("id","")),id,"Any reachable side: "+id+str(at));tested+=1
	assert_gte(tested,15)
	town.spawn_at_home();var actor: Dictionary=profile.characters.runtime.aling
	actor.cell=town._player_cell();actor.route=[];actor.phase="town"
	assert_eq(town._story_faced(),"aling","An NPC is actually in dialogue range")
	watch_signals(town);var driver:=DRIVER.new();driver.viewport=get_tree().root;driver.tap(KEY_E)
	assert_signal_emitted(town,"restaurant_requested");assert_false(town._talk_open())
	# No facility at this safe road stop, so the same E opens the existing daily conversation.
	var at:=profile.characters.safe_stop_near(Vector2i(29,24),"aling")
	actor.cell=at;actor.route=[];town._player.position=town._origin()+(Vector2(at)+Vector2(.5,.5))*town.CELL
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
	assert_eq(texture.get_width(),map.extent*24)
	assert_eq(profile.snapshot(),before)
	profile.close()

func test_scenery_has_real_base_collisions_and_yields_to_new_buildings() -> void:
	var profile:=TDGameProfile.new();var map:=profile.world.town_map
	var items:=TDTownScenery.dressing(map).duplicate(true)
	assert_gte(items.size(),15,"Actual landscape groups, beyond changing the grass colour")
	for item: Dictionary in items:
		var bounds: Rect2=item.bounds
		for corner: Vector2 in [bounds.position,bounds.end,bounds.get_center()]:
			assert_false(map.is_road(int(corner.x),int(corner.y)))
		for plot: Dictionary in map.plots:
			if TDInteractionRange.facility(plot): assert_false(TDInteractionRange.plot_bounds(plot).grow(1.1).intersects(bounds))
	var town:=TDTownWorld.new();town.session=profile.world;town.player_mode=true;add_child_autofree(town)
	await wait_physics_frames(2)
	var r: Rect2=items[0].bounds
	town._player.position=town._origin()+Vector2(r.position.x*town.CELL-20,r.get_center().y*town.CELL)
	assert_not_null(town._player.move_and_collide(Vector2(150,0)),"Solid decoration matches its visible base")
	var at: Vector2=items[0].feet
	map.plots.append({"id":"test-new-building","kind":"market","x":int(at.x)-1,"y":int(at.y)-1,"w":3,"h":3})
	assert_false(TDTownScenery.dressing(map).any(func(p:Dictionary)->bool:return p.feet==at),"Cosmetics never occupy a newly built parcel")
	profile.close()
