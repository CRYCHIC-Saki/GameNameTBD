extends GutTest
const DRIVER=preload("res://tools/test_support/kitchen_input.gd")
var app:TDApplication
var shell:TDGameShell
var driver:RefCounted

func before_each() -> void:
	app=load("res://src/app/main.tscn").instantiate()
	app.settings_path="res://artifacts/habitat-tests/%d/settings.json"%Time.get_ticks_usec()
	add_child_autofree(app);shell=app.game_shell;shell.automatic_time=false
	assert_true(shell.create_game("slot-01").ok);shell.guide.dialogue.finish_now()
	# These regressions exercise an already acquired cottage; new-slot gating has dedicated tests.
	shell.profile.residence.stage="door";assert_true(shell.profile.unlock_residence().ok)
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
		lengths.append((TDRestaurantIsoView.project(delta.x,delta.y)-TDRestaurantIsoView.project(0,0)).length())
	for distance:float in lengths: assert_almost_eq(distance,lengths[0],.1,"Equal actual on-screen movement")
	assert_gt(lengths[0],15.0)
	room.teleport_player(Vector2i(1,0))
	assert_not_null(room._player.move_and_collide(Vector2(0,-300)),"Door interaction is not a hole through the perimeter")
	assert_gt(room.player_position().y,0.0)

func test_four_faces_nearby_building_and_cottage_is_a_real_room() -> void:
	var town:=shell.town;town.spawn_at_plot("player_cottage")
	assert_eq(town.facing_plot().get("id"),"player_cottage")
	var correct:=town._player.facing;town._player.face(-Vector2(correct))
	driver.tap(KEY_E);assert_eq(shell.location,"cottage","Nearby interaction is independent of facing")
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
	assert_null(button("保存进度"));assert_false(body.controls_enabled)
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
	assert_true(result.ok,result.code);assert_eq(migrated.snapshot().schema_version,9)
	assert_true(TDLevelProgression.same_value(migrated.research.snapshot(),shell.profile.research.snapshot()));migrated.close()
	var invalid:=before.duplicate(true);invalid.residence.schema_version=99
	var unchanged:=shell.profile.snapshot()
	assert_eq(shell.profile.restore(invalid).code,"INVALID_RESIDENCE");assert_eq(shell.profile.snapshot(),unchanged)

func test_bed_write_failure_preserves_last_good_slot_and_retry_commits_once() -> void:
	shell.profile.shop.open_day();shell.profile.shop.close_early();shell.travel("cottage",true)
	assert_true(shell.save_game().ok)
	var path:=shell.slots.path_for("slot-01");var bytes:=FileAccess.get_file_as_bytes(path)
	shell.profile.persistence=func(_id:String,_data:Dictionary)->TDOutcome:return TDOutcome.new(false,"INJECTED_WRITE_FAILURE")
	driver.tap(KEY_E);button("休息到明天").pressed.emit()
	assert_eq(shell.profile.shop.snapshot().day,2);assert_eq(shell.profile.shop.snapshot().phase,"PREPARE")
	assert_eq(FileAccess.get_file_as_bytes(path),bytes);assert_true(get_tree().paused)
	shell.profile.persistence=shell.slots.save_slot
	button("重试保存").pressed.emit();assert_eq(shell.profile.shop.snapshot().day,2)
	assert_eq(int(shell.slots.load_slot("slot-01").data.shop.day),2)
	shell.profile.shop.open_day();assert_true(shell.travel("cottage").ok)

func test_music_context_hidden_kitchen_pause_and_real_qte() -> void:
	await get_tree().process_frame
	assert_eq(shell.music.context,"casual");assert_lte(shell.kitchen_view.kitchen.beat_audio.volume_db,-70.0)
	for id:String in ["casual","service","cooking"]:
		var stream:=TDGameMusic.loop_track(id)
		assert_eq(stream.loop_mode,AudioStreamWAV.LOOP_FORWARD);assert_gt(stream.get_length(),15.0)
		assert_eq(stream.loop_begin,0)
		assert_eq(stream.loop_end,source_pcm_frames("res://assets/audio/%s.wav"%id),"Loop covers every source sample, including compressed imports")
	assert_true(shell.profile.buy({"tomato":1000}).ok)
	shell.start_day();await get_tree().process_frame;assert_eq(shell.music.context,"service")
	shell.show_pause();await get_tree().process_frame;assert_true(shell.music.player.stream_paused)
	shell._close_dialog();shell.travel("kitchen")
	driver.kitchen=shell.kitchen_view.kitchen
	var picked:=shell.kitchen_view.pick_ingredient("tomato");assert_true(picked.ok,picked.code)
	driver.station("kitchen.board")
	var cut:=shell.kitchen_view.choose_cut("chunk");assert_true(cut.ok,cut.code)
	for i: int in 100:
		if driver.kitchen.prep.qte!=null: break
		driver.kitchen.advance(.1)
	assert_not_null(driver.kitchen.prep.qte)
	await get_tree().process_frame;await get_tree().process_frame
	assert_true(driver.kitchen.music_audible());assert_eq(shell.music.context,"silent")
	var cooking_track := driver.kitchen.beat_audio.stream as AudioStreamWAV
	assert_eq(cooking_track.loop_end,96*cooking_track.mix_rate,"48 full bars stay on the original recording beat across every loop")
	assert_lt(cooking_track.loop_end,source_pcm_frames("res://assets/audio/cooking.wav"),"Exclude the off-grid trailing fade")
	var stream:AudioStream=driver.kitchen.beat_audio.stream
	shell._pause(true);assert_true(driver.kitchen.beat_audio.stream_paused)
	shell._pause(false);assert_same(driver.kitchen.beat_audio.stream,stream)
	shell.travel("restaurant");await get_tree().process_frame;await get_tree().process_frame
	assert_false(driver.kitchen.music_audible());assert_lte(driver.kitchen.beat_audio.volume_db,-70.0)

func test_interaction_keeps_bgm_while_pause_still_freezes_rules() -> void:
	await get_tree().process_frame
	var stream: AudioStream=shell.music.player.stream
	shell.show_relationships()
	await get_tree().process_frame
	assert_true(get_tree().paused,"interaction freezes gameplay")
	assert_false(shell.music.player.stream_paused,"interaction keeps ambient music")
	assert_same(shell.music.player.stream,stream,"interaction does not restart the track")
	shell._close_dialog()
	shell._story_frozen=true
	assert_false(shell._music_should_pause(),"dialogue freeze is separate from explicit pause")
	shell.show_pause();await get_tree().process_frame
	assert_true(shell.music.player.stream_paused)
	shell._close_dialog();await get_tree().process_frame
	assert_false(shell.music.player.stream_paused)

# Independently read source RIFF metadata; do not derive expectations from the
# imported AudioStream's duration or the production loop calculation.
func source_pcm_frames(path: String) -> int:
	var file:=FileAccess.open(path,FileAccess.READ)
	assert_not_null(file)
	if file==null: return -1
	assert_eq(file.get_buffer(4).get_string_from_ascii(),"RIFF")
	file.seek(8)
	assert_eq(file.get_buffer(4).get_string_from_ascii(),"WAVE")
	var frame_bytes: int=0
	var data_bytes: int=0
	while file.get_position()+8<=file.get_length():
		var kind:=file.get_buffer(4).get_string_from_ascii()
		var length:=file.get_32()
		var start:=file.get_position()
		if kind=="fmt ":
			file.seek(start+12);frame_bytes=file.get_16()
		elif kind=="data": data_bytes=length
		file.seek(start+length+length%2)
	file.close()
	assert_gt(frame_bytes,0);assert_gt(data_bytes,0)
	return int(data_bytes/frame_bytes) if frame_bytes>0 else -1
