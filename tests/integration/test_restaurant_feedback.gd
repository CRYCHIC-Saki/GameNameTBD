extends GutTest

var room: TDRestaurantWorld

func before_each() -> void:
	room=TDRestaurantWorld.new();room.player_mode=true
	add_child_autofree(room)
	await wait_physics_frames(2)

func after_each() -> void:
	for action: String in ["world_left","world_right","world_up","world_down"]: Input.action_release(action)
	room.close()

func test_grid_keys_follow_each_floor_edge_and_combinations_keep_visible_speed() -> void:
	var keys: Array=[["world_right"],["world_left"],["world_down"],["world_up"],["world_right","world_up"],["world_left","world_up"],["world_right","world_down"],["world_left","world_down"]]
	var expected: Array[Vector2]=[Vector2(2,1),Vector2(-2,-1),Vector2(-2,1),Vector2(2,-1),Vector2.RIGHT,Vector2.UP,Vector2.DOWN,Vector2.LEFT]
	for index: int in keys.size():
		room.teleport_player(Vector2i(6,8));await wait_physics_frames(2)
		for action: String in keys[index]: Input.action_press(action)
		await wait_physics_frames(2)
		var before:=room.player_position()/64.0
		await get_tree().physics_frame
		var after:=room.player_position()/64.0
		var travel:=TDRestaurantIsoView.project(after.x,after.y)-TDRestaurantIsoView.project(before.x,before.y)
		assert_gt(travel.normalized().dot(expected[index].normalized()),.9999,"Actual projected movement follows tile edges")
		assert_almost_eq(travel.length(),3.0,.05,"All eight headings remain 180px/s")
		for action: String in keys[index]: Input.action_release(action)

func test_seated_proportions_and_whole_body_mirror_for_every_appearance() -> void:
	var table:=room.layout.piece_by_kind("dining_table")
	var original:=table.duplicate(true)
	for rotation: int in [0,90,180,270]:
		table.rotation=rotation
		for who: String in ["","aling","chen"]:
			for variant: int in 6:
				var art:=TDDinerArt.dining_sprite(variant,who)
				var hip:=TDDinerArt.hip_ratio(variant,who)
				var box:=TDFurnitureModel.dining_pose_rect(table,art,hip)
				if rotation in [90,270]: hip.x=1.0-hip.x
				var actual:=box.position+box.size*hip
				var center:=TDRestaurantIsoView.project(table.x+table.w*.5,table.y+table.h*.5)
				# Independent stool cushion: moved outwards with the whole sitter.
				assert_almost_eq(actual.x-center.x,55.296 if rotation in [90,270] else -55.296,.001)
				assert_almost_eq(actual.y-center.y,-27.91425,.002)
				assert_almost_eq(box.size.y,83.52,.001,"Original chibi scale, no forced floor contact")
				assert_almost_eq(box.size.x/box.size.y,float(art.get_width())/art.get_height(),.0001,"No nonuniform texture stretch")
				assert_gt(art.get_width(),50)
	assert_eq(room.layout.piece(original.id),original,"Visual queries cannot change layout")

func test_stools_are_separate_and_further_from_table_without_larger_footprint() -> void:
	var table:=room.layout.piece_by_kind("dining_table")
	var original:=table.duplicate(true)
	assert_ne(TDFurnitureModel.dining_part(0).region,TDFurnitureModel.dining_part(1).region)
	for side: float in [-1.0,1.0]:
		var stool:=TDFurnitureModel.dining_stool_rect(table,side)
		assert_gt(absf(stool.get_center().x)-42.336,12.0,"Moved away from old baked stool center")
		assert_almost_eq(stool.end.y,5.0,.001)
		assert_true(TDFurnitureModel.bounds(table).encloses(stool),"Stool stays within furniture selection bounds")
	assert_eq(room.layout.piece(original.id),original)

func test_occupied_assembly_keeps_one_ground_anchor_and_uniform_scale() -> void:
	var table:=room.layout.piece_by_kind("dining_table")
	for rotation: int in [0,90,180,270]:
		table.rotation=rotation
		for who: String in ["","aling","chen"]:
			for variant: int in 6:
				var art:=TDDinerArt.occupied_sprite(variant,who)
				var foot:=TDDinerArt.occupied_base(variant,who)
				var box:=TDFurnitureModel.occupied_pose_rect(table,art,foot)
				if rotation in [90,270]: foot.x=1-foot.x
				var actual:=box.position+box.size*foot-TDFurnitureModel.center(table)
				assert_almost_eq(actual.x,55.296 if rotation in [90,270] else -55.296,.001)
				assert_almost_eq(actual.y,5.0,.001)
				assert_almost_eq(box.size.y,108.0,.001,"Includes the stool, not a stretched character")
				assert_almost_eq(box.size.x/box.size.y,float(art.get_width())/art.get_height(),.0001)
				assert_between(art.get_height(),490,565,"Explicit atlas rows exclude the adjacent character")

func test_only_current_seated_actor_suppresses_the_empty_stool() -> void:
	var id: String=room.layout.piece_by_kind("dining_table").id
	room._iso.actors=[{"seat_id":id,"seated":false,"gone":false}]
	assert_false(room._iso.seat_is_occupied(id))
	room._iso.actors[0].seated=true
	assert_true(room._iso.seat_is_occupied(id))
	assert_false(room._iso.seat_is_occupied("other-seat"))
	room._iso.actors[0].gone=true
	assert_false(room._iso.seat_is_occupied(id))
	room._iso.actors.clear()
	assert_false(room._iso.seat_is_occupied(id))

func test_table_occlusion_is_bounded_to_lower_body_and_mirrors_with_furniture() -> void:
	var table:=room.layout.piece_by_kind("dining_table")
	var crop:=Rect2(-70,-55,60,45)
	for rotation: int in [0,90,180,270]:
		table.rotation=rotation
		var mirrored: bool=rotation in [90,270]
		var lower:=Rect2(Vector2(-crop.end.x,crop.position.y),crop.size) if mirrored else crop
		var polygons:=TDFurnitureModel.dining_occlusion(table,lower)
		assert_false(polygons.is_empty(),"Real tabletop/apron intersects the knees")
		for polygon: PackedVector2Array in polygons:
			for point: Vector2 in polygon:
				assert_true(lower.grow(.01).has_point(point),"No foreground outside body clip")
		var top:=Rect2(-70,-130,60,15)
		assert_true(TDFurnitureModel.dining_occlusion(table,top).is_empty(),"No table layer at head height")

func test_default_player_mapping_is_unchanged_outside_restaurant() -> void:
	var body:=TDKitchenPlayer.new()
	for heading: Vector2 in [Vector2.UP,Vector2.DOWN,Vector2.LEFT,Vector2.RIGHT]:
		assert_eq(body.screen_input(heading),heading)
	body.free()
