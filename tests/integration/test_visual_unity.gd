extends GutTest
const DRIVER=preload("res://tools/test_support/kitchen_input.gd")
var app: TDApplication
var shell: TDGameShell

func before_each() -> void:
	app=load("res://src/app/main.tscn").instantiate()
	app.settings_path="res://artifacts/visual-unity/slots-%d/settings.json"%Time.get_ticks_usec()
	add_child_autofree(app);shell=app.game_shell;shell.automatic_time=false
	assert_true(shell.create_game("slot-01").ok);shell.guide.dialogue.finish_now()
	await get_tree().process_frame

func after_each() -> void:
	get_tree().paused=false;shell.go_title();await get_tree().process_frame

func test_town_schedule_and_story_escort_really_animate_and_pause() -> void:
	var town:=shell.town;shell.profile.story.beat="done";town.sync_characters(0)
	town._refresh_npc_gaits();var frames: Dictionary={}
	for i: int in 60:
		town.sync_characters(.06);town._refresh_npc_gaits()
		frames[town._npc_gaits.aling.frame]=true
	assert_true(frames.has(0));assert_true(frames.has(2))
	get_tree().paused=true
	var frame: int=town._npc_gaits.aling.frame
	town._refresh_npc_gaits();assert_eq(town._npc_gaits.aling.frame,frame)
	get_tree().paused=false
	shell.profile.story.beat="follow";town._tick_escort(.1);town.sync_characters(0)
	var first: Vector2=_aling_position(town)
	town._tick_escort(.1);var second: Vector2=_aling_position(town)
	assert_gt(first.distance_to(second),.01);assert_lt(first.distance_to(second),.5,"Escort interpolates rather than jumping a tile")
	town._refresh_npc_gaits();town._tick_escort(.1);town._refresh_npc_gaits()
	assert_gte(town._npc_gaits.aling.frame,0)

func _aling_position(town: TDTownWorld) -> Vector2:
	for p: Dictionary in town._story_people():
		if p.id=="aling": return p.get("position",Vector2(p.cell))
	return Vector2(-99,-99)

func test_real_guest_movement_drives_named_and_generic_animation_not_waiting_clock() -> void:
	shell.travel("restaurant");var room:=shell.restaurant
	var guest:=TDRestaurantGuest.new();room._guests.add_child(guest)
	guest.character_id="chen";guest.set_process(false)
	guest.set_path([Vector2i(5,8),Vector2i(6,8),Vector2i(7,8)],room.layout.cell_px)
	room._iso.sync(room._player,[guest]);var frames: Dictionary={}
	for i: int in 18:
		guest.advance(5);room._iso.sync(room._player,[guest]);frames[room._iso.actors[0].frame]=true
	assert_gte(frames.size(),3);assert_ne(room._iso.actors[0].facing,Vector2i.ZERO)
	var frozen_frame: int=room._iso.actors[0].frame
	room._iso.sync(room._player,[guest],true);assert_eq(room._iso.actors[0].frame,frozen_frame)
	room._iso.sync(room._player,[guest]);assert_eq(room._iso.actors[0].frame,-1)
	guest.character_id="";guest.advance(5);room._iso.sync(room._player,[guest]);assert_gte(room._iso.actors[0].frame,0)
	guest.seated=true;room._iso.sync(room._player,[guest]);assert_eq(room._iso.actors[0].frame,-1)
	room._iso.sync(room._player,[]);assert_true(room._iso._gaits.is_empty(),"Departed view state released")
	guest.queue_free()
	room._iso.crew_people=[{"actor_id":"test-worker","label":"待命","point":Vector2(64,64),"color":Color("#d7a15a"),"moving":true}]
	room._iso.sync(room._player,[])
	var staff_gait: TDNpcGait=room._iso._gaits["staff:test-worker"]
	room._iso.crew_people=[{"actor_id":"test-worker","label":"招呼","point":Vector2(90,64),"color":Color("#d7a15a"),"moving":true}]
	room._iso.sync(room._player,[])
	assert_same(room._iso._gaits["staff:test-worker"],staff_gait,"Caption changes are not new identities")
	assert_gte(staff_gait.frame,0)

func test_spacious_projection_and_function_markers_preserve_layout_and_reachability() -> void:
	shell.travel("restaurant");var room:=shell.restaurant
	var before: Dictionary=shell.profile.snapshot();var driver:=DRIVER.new();driver.viewport=get_tree().root
	assert_eq(TDRestaurantIsoView.project(1,0)-TDRestaurantIsoView.project(0,0),Vector2(48,24))
	for marker: Dictionary in room.interaction_points():
		var bounds: Rect2=marker.get("bounds",Rect2(marker.cell,Vector2.ONE))
		var reachable: bool=false
		for y: int in room.layout.rows:
			for x: int in room.layout.columns:
				if room.layout.is_walkable(x,y) and TDInteractionRange.distance(Vector2(x+.5,y+.5),bounds)<=1.0: reachable=true
		assert_true(reachable,"Reachable "+str(marker.action))
	var cashier:=room.layout.piece_by_kind("cashier")
	var book: Dictionary=room.interaction_points().filter(func(m:Dictionary)->bool:return m.action=="ledger")[0]
	assert_true(book.on_counter);assert_eq(book.bounds,Rect2(cashier.x,cashier.y,cashier.w,cashier.h))
	room.teleport_player(Vector2i(cashier.approach_x,cashier.approach_y));driver.tap(KEY_E)
	assert_not_null(shell._modal_box);shell._close_dialog()
	assert_eq(shell.profile.snapshot(),before,"Visual space expansion never reallocates saved furniture or money")
	assert_eq(room._iso._camera.zoom,Vector2.ONE)

func test_ledger_follows_moved_rotated_counter_and_survives_removal() -> void:
	shell.travel("restaurant");var room:=shell.restaurant;var layout:=room.layout
	var cashier:=layout.piece_by_kind("cashier")
	assert_true(room._apply(layout.move_piece(str(cashier.id),7,2)).ok)
	assert_true(room._apply(layout.rotate_piece(str(cashier.id))).ok)
	var moved:=layout.piece_by_kind("cashier")
	var book: Dictionary=room.interaction_points().filter(func(m:Dictionary)->bool:return m.action=="ledger")[0]
	var shown: Dictionary=room._iso.interaction_markers.filter(func(m:Dictionary)->bool:return m.action=="ledger")[0]
	assert_eq(book,shown);assert_eq(book.bounds,Rect2(moved.x,moved.y,moved.w,moved.h))
	assert_true(room._apply(layout.remove_piece(str(cashier.id))).ok)
	book=room.interaction_points().filter(func(m:Dictionary)->bool:return m.action=="ledger")[0]
	assert_false(book.on_counter);assert_eq(book.cell.y,0.0)
	room.teleport_player(Vector2i(int(book.cell.x),1))
	var driver:=DRIVER.new();driver.viewport=get_tree().root;driver.tap(KEY_E)
	assert_not_null(shell._modal_box);shell._close_dialog()
