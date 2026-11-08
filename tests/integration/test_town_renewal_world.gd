extends GutTest

func test_nearby_town_targets_all_directions_and_distinct_frontages() -> void:
	var profile:=TDGameProfile.new();assert_true(profile.error.ok,profile.error.code)
	var town:=TDTownWorld.new();town.session=profile.world;town.player_mode=true
	add_child_autofree(town);await get_tree().process_frame
	var map:=profile.world.town_map
	for id: String in ["player_diner","player_cottage","market-small","market-mid","market-large","factory-1","factory-2","competitor:shop:0","competitor:shop:1","commercial_street:bank"]:
		var p:=map._by_id(id);assert_false(p.is_empty(),id)
		if p.is_empty(): continue
		town._player.position=town._origin()+(Vector2(p.approach_x,p.approach_y)+Vector2(.5,.5))*town.CELL
		for facing: Vector2i in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:
			town._player.facing=facing
			assert_eq(str(town.facing_plot().get("id","")),id,"exclusive entrance "+id)
	assert_lt(town._blockers.get_child_count(),1000,"merged collision spans")
	town.set_day_minute(1320);assert_ne(town.self_modulate,Color.WHITE)
	profile.close()

func test_real_kitchen_nearby_stations_emit_their_own_identity() -> void:
	var world:=load("res://src/world/kitchen_world.tscn").instantiate() as TDKitchenWorld
	world.single_fridge=true;world.service_door=true
	add_child_autofree(world);await get_tree().process_frame
	watch_signals(world)
	for p: Dictionary in world.stations():
		world._player.position=p.position
		world._player.face(Vector2.DOWN)
		world.set_controls_enabled(true)
		assert_eq(str(world._station_at_player().get("id","")),str(p.id))
		assert_true(world.request_interaction())
		assert_signal_emitted_with_parameters(world,"cooking_requested",[str(p.id)])
	world.set_day_minute(1320)
	assert_ne(world.self_modulate,Color.WHITE)
	assert_eq(world._hud.modulate,Color.WHITE,"HUD does not inherit environmental dimming")

func test_migration_backup_and_interrupted_write_preserve_original() -> void:
	var helper: GutTest=load("res://tests/unit/test_town_renewal.gd").new()
	var old: Dictionary=helper.legacy_snapshot();helper.free()
	var directory: String="res://artifacts/town-renewal/migration-%d"%Time.get_ticks_usec()
	var store:=TDProfileStore.new(directory,TDGameProfile.validate_save)
	assert_true(store.save_slot("slot-01",old).ok)
	assert_true(store.backup_map_migration("slot-01").ok)
	var original:=FileAccess.get_sha256(store.path_for("slot-01"))
	var p:=TDGameProfile.new();assert_true(p.restore(old).ok)
	store.interrupt_at="partial_write"
	assert_false(store.save_slot("slot-01",p.snapshot()).ok)
	assert_eq(FileAccess.get_sha256(store.path_for("slot-01")),original)
	assert_eq(FileAccess.get_sha256(store.path_for("slot-01")+".before-map-v2.bak"),original)
	store.interrupt_at=""
	assert_true(store.save_slot("slot-01",p.snapshot()).ok)
	assert_eq(int(store.load_slot("slot-01").data.world.map_version),2)
	assert_eq(FileAccess.get_sha256(store.path_for("slot-01")+".before-map-v2.bak"),original)
	p.close()

func simulate_real_clock(chunks: Array) -> Dictionary:
	var app: TDApplication=load("res://src/app/main.tscn").instantiate()
	app.settings_path="res://artifacts/town-renewal/clock-%d/settings.json"%Time.get_ticks_usec()
	add_child(app);var shell:=app.game_shell;shell.automatic_time=false
	assert_true(shell.create_game("slot-01").ok);shell.guide.dialogue.finish_now()
	shell.profile.story.beat="done"
	var kitchen:=shell.kitchen_view.kitchen
	# Drive the actual cooking signal clock deterministically, without wall time.
	shell.automatic_time=true;kitchen.auto_advance=false
	assert_true(shell.profile.shop.open_day().ok)
	for seconds: float in chunks: kitchen.advance(seconds)
	var result: Dictionary={"minute":shell.profile.characters.clock.minute,"elapsed":shell.profile.shop.snapshot().elapsed_sec,"opportunities":shell.profile.commerce.state.day_stats.opportunities,"firms":shell.profile.commerce.state.competitors.duplicate(true)}
	shell.kitchen_view.set_paused(true);kitchen.advance(30)
	assert_almost_eq(shell.profile.characters.clock.minute,float(result.minute),.0001,"pause freezes the one authoritative clock")
	shell.kitchen_view.set_paused(false)
	kitchen.advance(30)
	assert_almost_eq(shell.profile.characters.clock.minute,float(result.minute)+30,.0001)
	shell.go_title();app.free()
	await get_tree().process_frame;await get_tree().process_frame
	return result

func test_actual_clock_signal_long_frame_and_split_updates_agree() -> void:
	var large: Dictionary=await simulate_real_clock([400.0])
	var small: Dictionary=await simulate_real_clock([40.0,40.0,40.0,40.0,40.0,40.0,40.0,40.0,40.0,40.0])
	assert_almost_eq(float(large.minute),880.0,.0001)
	assert_almost_eq(float(large.elapsed),400.0,.0001)
	assert_almost_eq(float(large.minute),float(small.minute),.0001)
	assert_eq(large.opportunities,small.opportunities)
	assert_eq(large.firms,small.firms,"same real background economic transactions")

func test_real_load_migrates_only_after_backup_and_successful_write() -> void:
	var helper: GutTest=load("res://tests/unit/test_town_renewal.gd").new()
	var old: Dictionary=helper.legacy_snapshot();helper.free()
	var app: TDApplication=load("res://src/app/main.tscn").instantiate()
	app.settings_path="res://artifacts/town-renewal/load-%d/settings.json"%Time.get_ticks_usec()
	add_child(app);var shell:=app.game_shell;shell.automatic_time=false
	assert_true(shell.slots.save_slot("slot-01",old).ok)
	var path:=shell.slots.path_for("slot-01");var checksum:=FileAccess.get_sha256(path)
	shell.slots.interrupt_at="partial_write"
	assert_false(shell.load_game("slot-01").ok);assert_null(shell.profile)
	assert_eq(FileAccess.get_sha256(path),checksum)
	assert_eq(FileAccess.get_sha256(path+".before-map-v2.bak"),checksum)
	shell.slots.interrupt_at=""
	assert_true(shell.load_game("slot-01").ok);assert_eq(shell.location,"cottage")
	assert_eq(shell.profile.world.map_version,2)
	assert_eq(int(shell.slots.load_slot("slot-01").data.schema_version),7)
	assert_eq(FileAccess.get_sha256(path+".before-map-v2.bak"),checksum)
	var malformed:=shell.profile.snapshot();malformed.map_migration="bad"
	assert_false(TDGameProfile.validate_save(malformed).ok)
	shell.go_title();app.free()
	await get_tree().process_frame;await get_tree().process_frame
