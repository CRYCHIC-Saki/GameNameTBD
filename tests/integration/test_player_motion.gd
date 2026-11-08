extends GutTest

var room: TDRestaurantWorld

func before_each() -> void:
	room = TDRestaurantWorld.new()
	add_child_autofree(room)
	await wait_physics_frames(2)

func after_each() -> void:
	shift_key(false)
	for action: String in ["world_left", "world_right", "world_up", "world_down", "world_sprint"]:
		if InputMap.has_action(action): Input.action_release(action)
	get_tree().paused = false

func shift_key(pressed: bool, side: int = KEY_LOCATION_LEFT) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_SHIFT
	event.physical_keycode = KEY_SHIFT
	event.location = side
	event.shift_pressed = pressed
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func screen_point(point: Vector2) -> Vector2:
	# Independent rendering projection, not the controller's inverse transform.
	return TDRestaurantIsoView.project(point.x / room.layout.cell_px, point.y / room.layout.cell_px)

func test_real_restaurant_wall_slides_never_exceed_screen_walk_budget() -> void:
	var starts: Array[Vector2i] = [Vector2i(1,7), Vector2i(7,1), Vector2i(room.layout.columns-2,7), Vector2i(7,room.layout.rows-2)]
	var actions: Array = [["world_left","world_up"],["world_left","world_up"],["world_right","world_down"],["world_right","world_down"]]
	var peak := 0.0
	var slides := 0
	for i: int in starts.size():
		room.teleport_player(starts[i])
		await wait_physics_frames(2)
		for action: String in actions[i]: Input.action_press(action)
		for tick: int in 45:
			var before := room.player_position()
			await get_tree().physics_frame
			var travel := screen_point(room.player_position()) - screen_point(before)
			peak = maxf(peak, travel.length())
			if absf(travel.x) > 0.1: slides += 1 # Vertical input deflected along a real wall.
			assert_lte(travel.length(), 180.0 / Engine.physics_ticks_per_second + 0.08, "Wall slide cannot accelerate in screen space")
		for action: String in actions[i]: Input.action_release(action)
	print("RESTAURANT_COLLISION peak_screen_step=", peak, " sliding_frames=", slides)
	assert_gt(slides, 10, "Exercise real sliding contacts, not only open floor")
	room.teleport_player(Vector2i(6,8))
	await wait_physics_frames(2)
	Input.action_press("world_right")
	await wait_physics_frames(2)
	var before := room.player_position()
	await get_tree().physics_frame
	assert_almost_eq(screen_point(room.player_position()).distance_to(screen_point(before)), 3.0, 0.05, "Leaving the wall restores the original walk speed")
	Input.action_release("world_right")

func test_both_shift_keys_hold_to_sprint_eight_directions_and_release_to_walk() -> void:
	assert_true(InputMap.has_action("world_sprint"))
	var directions: Array = [["world_right"],["world_left"],["world_up"],["world_down"],["world_right","world_up"],["world_right","world_down"],["world_left","world_up"],["world_left","world_down"]]
	for side: int in [KEY_LOCATION_LEFT, KEY_LOCATION_RIGHT]:
		shift_key(true, side)
		assert_true(Input.is_action_pressed("world_sprint"), "Real Shift event maps to the action")
		for actions: Array in directions:
			room.teleport_player(Vector2i(6,8))
			for action: String in actions: Input.action_press(action)
			await wait_physics_frames(2)
			var before := room.player_position()
			await get_tree().physics_frame
			assert_almost_eq(screen_point(room.player_position()).distance_to(screen_point(before)), 4.8, 0.05, "Eight directions sprint at 288 screen px/s")
			for action: String in actions: Input.action_release(action)
		shift_key(false, side)
		assert_false(Input.is_action_pressed("world_sprint"))
		room.teleport_player(Vector2i(6,8))
		Input.action_press("world_right")
		await wait_physics_frames(2)
		var before := room.player_position()
		await get_tree().physics_frame
		assert_almost_eq(screen_point(room.player_position()).distance_to(screen_point(before)), 3.0, 0.05)
		Input.action_release("world_right")
		await wait_physics_frames(2)
		before = room.player_position()
		shift_key(true, side)
		await wait_physics_frames(3)
		assert_eq(room.player_position(), before, "Shift alone is not movement")
		shift_key(false, side)

func test_sprinting_into_table_edges_and_room_corner_cannot_tunnel_or_accelerate() -> void:
	var table := room.layout.piece_by_kind("dining_table")
	var table_area := Rect2(Vector2(table.x,table.y)*64.0,Vector2(128,128))
	var starts: Array[Vector2i] = [Vector2i(table.x-1,table.y),Vector2i(table.x,table.y-1),Vector2i(1,1)]
	var actions: Array = [["world_right","world_down"],["world_right","world_down"],["world_left","world_up"]]
	var contacts := 0
	shift_key(true)
	for i: int in starts.size():
		room.teleport_player(starts[i])
		await wait_physics_frames(2)
		for action: String in actions[i]: Input.action_press(action)
		for tick: int in 32:
			var before := room.player_position()
			var heading := Vector2.DOWN if i<2 else Vector2.UP
			if room._player.move_and_collide(room._player.motion_transform.basis_xform(heading*8.0),true)!=null: contacts+=1
			await get_tree().physics_frame
			assert_lte(screen_point(room.player_position()).distance_to(screen_point(before)),4.88)
			assert_false(table_area.has_point(room.player_position()), "Feet never enter the table")
			assert_gt(room.player_position().x,0.0)
			assert_gt(room.player_position().y,0.0)
		for action: String in actions[i]: Input.action_release(action)
	assert_gt(contacts,10,"Exercise physical contacts while sprinting")
	shift_key(false)

func test_sprint_is_shared_by_all_rooms_and_cannot_bypass_modal_pause_or_hidden_controls() -> void:
	# Dispose the standalone room so it cannot collide with the real application.
	room.queue_free()
	await get_tree().process_frame
	var app: TDApplication = load("res://src/app/main.tscn").instantiate()
	app.settings_path = "res://artifacts/player-motion-tests/%d/settings.json" % Time.get_ticks_usec()
	add_child_autofree(app)
	var shell := app.game_shell
	shell.automatic_time = false
	assert_true(shell.create_game("slot-01").ok);shell.guide.dialogue.finish_now()
	# Shared-room locomotion fixture already owns the house; gating is covered in homecoming.
	shell.profile.residence.stage="door";assert_true(shell.profile.unlock_residence().ok)
	for destination: String in ["town","cottage","kitchen","restaurant"]:
		assert_true(shell.travel(destination).ok)
		var body: TDKitchenPlayer
		match destination:
			"town":
				body = shell.town._player
				body.position = shell.town._origin()+Vector2.ONE*(TDTownMap.CENTER+0.5)*TDTownWorld.CELL
			"cottage": body=shell.cottage.player;body.position=Vector2(570,420)
			"kitchen": body=shell.kitchen_view.kitchen.world._player;body.position=Vector2(640,420)
			"restaurant": body=shell.restaurant._player;shell.restaurant.teleport_player(Vector2i(6,8))
		shift_key(true)
		Input.action_press("world_right")
		await wait_physics_frames(2)
		var before := body.position
		var before_global := body.global_position
		await get_tree().physics_frame
		# move_and_slide uses global physics units; the kitchen is inside a scaled UI.
		var travel := body.global_position.distance_to(before_global)
		if destination=="restaurant":
			travel = TDRestaurantIsoView.project(body.position.x/64,body.position.y/64).distance_to(TDRestaurantIsoView.project(before.x/64,before.y/64))
		assert_almost_eq(travel,4.8 if destination=="restaurant" else 368.0/60.0,0.06,destination+" uses shared sprint")
		shell.show_pause()
		before=body.position
		await wait_physics_frames(3)
		assert_eq(body.position,before,"Pause blocks Shift+movement")
		# Release Shift while paused; closing the menu cannot latch sprint on.
		shift_key(false)
		Input.action_release("world_right")
		shell._close_dialog()
		await wait_physics_frames(2)
		assert_eq(body.walk_frame,-1)
		shift_key(true)
		shell._lock_controls(false)
		Input.action_press("world_right")
		before=body.position
		await wait_physics_frames(3)
		assert_eq(body.position,before,"QTE/modal input lock also blocks sprint")
		Input.action_release("world_right")
		shift_key(false)
		shell._lock_controls(true)
		var hidden := shell.cottage.player if destination!="cottage" else shell.restaurant._player
		before=hidden.position
		Input.action_press("world_down");shift_key(true)
		await wait_physics_frames(3)
		assert_eq(hidden.position,before,"Hidden scene does not sprint")
		Input.action_release("world_down");shift_key(false)
	shell.go_title()
	await wait_physics_frames(2)
