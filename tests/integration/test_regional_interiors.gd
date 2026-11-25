extends GutTest

func test_all_three_cuisines_have_matching_default_furniture_without_fallback() -> void:
	var catalog := TDRestaurantCatalog.new()
	assert_true(catalog.load_file().ok)
	var expected := {"cn":"chinese", "eu":"french", "jp":"japanese"}
	for cuisine: String in expected:
		var room := TDRestaurantLayout.make_sized(catalog,16,16,TDPlayerBranches.CULTURES[cuisine])
		assert_eq(room.culture, str(expected[cuisine]), cuisine)
		assert_true(room.furnish_player_home().ok)
		for item: Dictionary in room.pieces(): assert_eq(str(item.style_id),str(expected[cuisine])+"_low")
		var restored := TDRestaurantLayout.import_dict(room.to_dict(),catalog)
		assert_not_null(restored,TDRestaurantLayout.import_code)
		assert_eq(restored.to_dict(),room.to_dict())

func test_customized_old_layout_is_not_redecorated_and_templates_are_isolated() -> void:
	var catalog := TDRestaurantCatalog.new(); assert_true(catalog.load_file().ok)
	var room := TDRestaurantLayout.make_sized(catalog,16,16,"chinese")
	assert_true(room.furnish_player_home().ok)
	assert_true(room.set_surface_finish("carpet").ok)
	assert_true(room.set_surface_finish("floral").ok)
	var table := room.piece_by_kind("dining_table")
	assert_true(room.restyle_piece(table.id,"japanese","high").ok)
	var saved := room.to_dict()
	var other := TDRestaurantLayout.make_sized(catalog,16,16,"latin_american")
	assert_true(other.furnish_player_home().ok)
	var restored := TDRestaurantLayout.import_dict(saved,catalog)
	assert_eq(restored.to_dict(),saved)
	assert_eq(str(restored.piece(table.id).style_id),"japanese_high")
	assert_eq(restored.finish_at(5,8),"carpet")
	assert_eq(restored.finish_at(0,0),"floral")
	assert_eq(room.to_dict(),saved)

func test_art_routes_to_distinct_regions_and_keeps_chinese_occupied_assembly() -> void:
	var source_regions: Array=[]
	for theme: String in ["french","japanese"]:
		var table := {"kind":"dining_table","style_id":theme+"_low"}
		assert_false(TDFurnitureModel.uses_occupied_pose(table),"Regional chair must not become the red Chinese chair on sitting")
		for index: int in 3:
			var art := TDRegionalInterior.sprite(theme,index)
			assert_gt(art.get_width(),100);assert_gt(art.get_height(),100)
			assert_false(source_regions.has(art.region));source_regions.append(art.region)
		assert_eq(TDFurnitureModel.table_texture(table),TDRegionalInterior.sprite(theme,0))
		assert_eq(TDFurnitureModel.stool_texture(table),TDRegionalInterior.sprite(theme,1))
	assert_true(TDFurnitureModel.uses_occupied_pose({"kind":"dining_table","style_id":"chinese_low"}))

func test_kitchen_theme_switch_is_live_and_does_not_move_stations_or_colliders() -> void:
	var world: TDKitchenWorld=load("res://src/world/kitchen_world.tscn").instantiate()
	world.single_fridge=true;world.service_door=true;add_child_autofree(world)
	await wait_physics_frames(2)
	var before := world.stations()
	var top: CollisionShape2D=world.get_node("CountersAndWalls/Top")
	var size: Vector2=top.shape.size
	for cuisine: String in ["cn","eu","jp"]:
		world.cuisine_id=cuisine;world.station_names=TDCuisineKitchen.names(cuisine)
		await wait_process_frames(1)
		assert_eq(world.stations(),before)
		assert_eq(top.position,Vector2(640,140));assert_eq(top.shape.size,size)
		assert_eq(world.get_node("Background").visible,cuisine=="cn")
		world._player.position=Vector2(420,315)
		assert_eq(str(world._station_at_player().id),"kitchen.board")
		world._player.position=Vector2(640,315)
		assert_eq(str(world._station_at_player().id),"kitchen.stove.left")
		world._player.position=Vector2(640,694)
		assert_true(world.staff_walkable(Vector2(640,440)))
	watch_signals(world)
	world.set_controls_enabled(true)
	var key:=InputEventAction.new();key.action="world_interact";key.pressed=true
	get_viewport().push_input(key,true);await wait_process_frames(2)
	assert_signal_emitted(world,"dining_requested")

func test_furniture_rotation_preserves_center_and_reading_does_not_mutate_layout() -> void:
	var catalog:=TDRestaurantCatalog.new();assert_true(catalog.load_file().ok)
	for theme: String in ["french","japanese"]:
		var room:=TDRestaurantLayout.make_sized(catalog,16,16,theme);assert_true(room.furnish_player_home().ok)
		var item:=room.piece_by_kind("dining_table");var before:=room.to_dict()
		var center:=TDFurnitureModel.center(item)
		for rotation: int in [0,90,180,270]:
			item.rotation=rotation
			assert_eq(TDFurnitureModel.center(item),center)
			assert_gt(TDFurnitureModel.table_texture(item).get_width(),0)
			assert_false(TDFurnitureModel.dining_occlusion(item,Rect2(-100,-90,200,100)).is_empty())
		assert_eq(room.to_dict(),before)
