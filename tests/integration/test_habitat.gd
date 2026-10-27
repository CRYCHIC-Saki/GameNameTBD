extends GutTest
const DRIVER=preload("res://tools/test_support/kitchen_input.gd")
var app:TDApplication
var shell:TDGameShell
var driver:RefCounted

func before_each() -> void:
	app=load("res://src/app/main.tscn").instantiate()
	app.settings_path="res://artifacts/habitat-tests/%d/settings.json"%Time.get_ticks_usec()
	add_child_autofree(app);shell=app.game_shell;shell.automatic_time=false
	assert_true(shell.create_game("slot-01").ok)
	driver=DRIVER.new();driver.viewport=get_tree().root;driver.kitchen=shell.kitchen_view.kitchen
	await wait_physics_frames(2)

func after_each() -> void:
	for action:String in ["world_left","world_right","world_up","world_down"]: Input.action_release(action)
	shell.go_title();get_tree().paused=false
	await get_tree().process_frame

func button(label:String) -> Button:
	for b:Button in shell._modal_box.find_children("*","Button",true,false):
		if b.text==label: return b
	return null

func test_screen_speed_is_equal_in_eight_directions_and_entrance_cannot_escape() -> void:
	shell.travel("restaurant");await wait_physics_frames(2)
	var room:=shell.restaurant;var lengths:Array[float]=[]
	for actions:Array in [["world_right"],["world_left"],["world_up"],["world_down"],["world_right","world_up"],["world_right","world_down"],["world_left","world_up"],["world_left","world_down"]]:
		room.teleport_player(Vector2i(6,8));await wait_physics_frames(1)
		var before:=room.player_position()
		for action:String in actions: Input.action_press(action)
		await wait_physics_frames(6)
		for action:String in actions: Input.action_release(action)
		var delta:Vector2=(room.player_position()-before)/64.0
		lengths.append(Vector2((delta.x-delta.y)*32,(delta.x+delta.y)*16).length())
	for distance:float in lengths: assert_almost_eq(distance,lengths[0],.1,"Equal actual on-screen movement")
	assert_gt(lengths[0],15.0)
	room.teleport_player(Vector2i(1,0))
	assert_not_null(room._player.move_and_collide(Vector2(0,-300)),"Door interaction is not a hole through the perimeter")
	assert_gt(room.player_position().y,0.0)

func test_four_faces_select_only_front_building_and_cottage_is_a_real_room() -> void:
	var town:=shell.town;town.spawn_at_plot("player_cottage")
	assert_eq(town.facing_plot().get("id"),"player_cottage")
	var correct:=town._player.facing;town._player.face(-Vector2(correct))
	driver.tap(KEY_E);assert_ne(shell.location,"cottage","Facing another building must never enter the cottage")
	shell.travel("town");town.spawn_at_plot("player_cottage")
	town._player.face(Vector2(correct));driver.tap(KEY_E);assert_eq(shell.location,"cottage")
	var hashes:Dictionary={}
	for face:Vector2i in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:
		shell.cottage.player.face(Vector2(face));hashes[TDChefArt.texture(face).get_image().get_data().hex_encode()]=true
	assert_eq(hashes.size(),4)
	var body:=shell.cottage.player
	body.position=TDCottageWorld.BED_ANCHOR;body.face(Vector2.RIGHT)
	assert_eq(shell.cottage.target(),"rest")
	assert_not_null(body.move_and_collide(Vector2(200,0)),"Bed is solid")
	body.position=TDCottageWorld.BED_ANCHOR;driver.tap(KEY_E)
	assert_not_null(button("保存进度"));assert_false(body.controls_enabled)
	var before:=body.position;Input.action_press("world_down");await wait_physics_frames(3);Input.action_release("world_down")
	assert_eq(body.position,before)
	shell._close_dialog();assert_true(body.controls_enabled)
	body.position=TDCottageWorld.DOOR-Vector2(0,40);body.face(Vector2.DOWN);driver.tap(KEY_E)
	assert_eq(shell.location,"town");assert_eq(town.facing_plot().get("id"),"player_cottage")

func test_bed_saves_next_day_once_and_loads_there_with_existing_progress() -> void:
	assert_eq(shell.location,"town")
	shell.profile.shop.open_day();shell.profile.shop.close_early()
	assert_eq(shell.profile.shop.snapshot().phase,"SETTLED")
	shell.travel("cottage",true);driver.tap(KEY_E)
	var action:Callable=button("休息到明天").pressed.get_connections()[0].callable
	action.call();action.call()
	assert_eq(shell.profile.shop.snapshot().day,2)
	assert_eq(shell.location,"cottage");assert_eq(shell.cottage.player.position,TDCottageWorld.BED_ANCHOR)
	var before:=shell.profile.snapshot()
	shell.go_title();assert_true(shell.load_game("slot-01").ok)
	assert_eq(shell.location,"cottage");assert_eq(shell.cottage.target(),"rest")
	assert_true(TDLevelProgression.same_value(shell.profile.snapshot(),before))
	assert_false(shell.restaurant.interaction_points().any(func(p:Dictionary)->bool:return p.action=="rest"))
	var old:=before.duplicate(true);old.schema_version=3;old.erase("residence")
	var migrated:=TDGameProfile.new();var result:=migrated.restore(old)
	assert_true(result.ok,result.code);assert_eq(migrated.snapshot().schema_version,4)
	assert_true(TDLevelProgression.same_value(migrated.research.snapshot(),shell.profile.research.snapshot()));migrated.close()
	var invalid:=before.duplicate(true);invalid.residence.schema_version=99
	var unchanged:=shell.profile.snapshot()
	assert_eq(shell.profile.restore(invalid).code,"INVALID_RESIDENCE");assert_eq(shell.profile.snapshot(),unchanged)

func test_bed_write_failure_cannot_advance_or_destroy_last_good_slot() -> void:
	shell.profile.shop.open_day();shell.profile.shop.close_early();shell.travel("cottage",true)
	assert_true(shell.save_game().ok)
	var path:=shell.slots.path_for("slot-01");var bytes:=FileAccess.get_file_as_bytes(path)
	shell.profile.persistence=func(_id:String,_data:Dictionary)->TDOutcome:return TDOutcome.new(false,"INJECTED_WRITE_FAILURE")
	driver.tap(KEY_E);button("休息到明天").pressed.emit()
	assert_eq(shell.profile.shop.snapshot().day,1);assert_eq(shell.profile.shop.snapshot().phase,"SETTLED")
	assert_eq(FileAccess.get_file_as_bytes(path),bytes);assert_false(shell._rest_busy)
	shell._close_dialog();shell.profile.persistence=shell.slots.save_slot
	driver.tap(KEY_E);button("休息到明天").pressed.emit();assert_eq(shell.profile.shop.snapshot().day,2)
	shell.profile.shop.open_day();assert_eq(shell.travel("cottage").code,"SHOP_OPEN")

func test_music_context_hidden_kitchen_pause_and_real_qte() -> void:
	await get_tree().process_frame
	assert_eq(shell.music.context,"casual");assert_lte(shell.kitchen_view.kitchen.beat_audio.volume_db,-70.0)
	for id:String in ["casual","service","cooking"]:
		var stream:=TDGameMusic.loop_track(id)
		assert_eq(stream.loop_mode,AudioStreamWAV.LOOP_FORWARD);assert_gt(stream.get_length(),15.0)
		assert_eq(stream.loop_end,roundi((24.0 if id=="casual" else (32.0*60/104 if id=="service" else 16.0))*stream.mix_rate),"Loop endpoints use samples, including compressed imports")
	assert_true(shell.profile.buy({"tomato":1000}).ok)
	shell.start_day();await get_tree().process_frame;assert_eq(shell.music.context,"service")
	shell.show_pause();await get_tree().process_frame;assert_true(shell.music.player.stream_paused)
	shell._close_dialog();shell.travel("kitchen")
	driver.kitchen=shell.kitchen_view.kitchen
	var picked:=shell.kitchen_view.pick_ingredient("tomato");assert_true(picked.ok,picked.code)
	driver.station("kitchen.board")
	var cut:=shell.kitchen_view.choose_cut("chunk");assert_true(cut.ok,cut.code)
	driver.kitchen.advance(3.0)
	assert_not_null(driver.kitchen.prep.qte)
	await get_tree().process_frame;await get_tree().process_frame
	assert_true(driver.kitchen.music_audible());assert_eq(shell.music.context,"silent")
	assert_eq(driver.kitchen.beat_audio.stream.get_length(),16.0,"32-beat music matches the 120 BPM chart")
	var stream:AudioStream=driver.kitchen.beat_audio.stream
	shell._pause(true);assert_true(driver.kitchen.beat_audio.stream_paused)
	shell._pause(false);assert_same(driver.kitchen.beat_audio.stream,stream)
	shell.travel("restaurant");await get_tree().process_frame;await get_tree().process_frame
	assert_false(driver.kitchen.music_audible());assert_lte(driver.kitchen.beat_audio.volume_db,-70.0)
