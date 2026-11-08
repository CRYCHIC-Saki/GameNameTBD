extends GutTest

const IDLE_PATH := "res://assets/characters/protagonist/protagonist-idle-four-directions-v1.png"
const WALK_PATH := "res://assets/characters/protagonist/protagonist-walk-four-directions-v1.png"
const FACES: Array[Vector2i] = [Vector2i.DOWN, Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT]
var app: TDApplication
var shell: TDGameShell

func before_each() -> void:
	app = load("res://src/app/main.tscn").instantiate()
	app.settings_path = "res://artifacts/protagonist-tests/%d/settings.json" % Time.get_ticks_usec()
	add_child_autofree(app)
	shell = app.game_shell
	shell.automatic_time = false
	assert_true(shell.create_game("slot-01").ok);shell.guide.dialogue.finish_now()
	# Shared-room locomotion fixture already owns the house; gating is covered in homecoming.
	shell.profile.residence.stage="door";assert_true(shell.profile.unlock_residence().ok)
	await wait_physics_frames(2)

func after_each() -> void:
	for action: String in ["world_left", "world_right", "world_up", "world_down"]:
		Input.action_release(action)
	get_tree().paused = false
	shell.go_title()
	await get_tree().process_frame

func test_user_idle_and_two_opposite_strides_form_a_four_beat_walk_cycle() -> void:
	var idle_regions: Array[Rect2] = [Rect2(214,30,312,595), Rect2(728,30,307,595), Rect2(255,649,254,576), Rect2(746,649,259,576)]
	var idle_hashes: Dictionary = {}
	for index: int in FACES.size():
		var idle := TDChefArt.texture(FACES[index]) as AtlasTexture
		assert_not_null(idle)
		assert_eq(idle.atlas.resource_path, IDLE_PATH)
		assert_eq(idle.region, idle_regions[index], "User atlas alignment comes from inspected source metadata")
		idle_hashes[idle.get_image().get_data().hex_encode().sha256_text()] = true
		var walk_hashes: Dictionary = {}
		for frame: int in 4:
			var walk := TDChefArt.texture(FACES[index], frame) as AtlasTexture
			assert_not_null(walk)
			assert_eq(walk.atlas.resource_path, WALK_PATH if frame in [0,2] else IDLE_PATH)
			if frame in [1,3]: assert_same(walk, idle, "Passing poses retain the approved original art")
			assert_true(Rect2(Vector2.ZERO, walk.atlas.get_size()).encloses(walk.region))
			assert_gt(walk.region.size.y, 20.0)
			walk_hashes[walk.get_image().get_data().hex_encode().sha256_text()] = true
		assert_eq(walk_hashes.size(), 3, "Two distinct stride drawings plus the idle passing pose")
	assert_eq(idle_hashes.size(), 4)

func test_real_move_plays_full_cycle_release_and_solid_wall_return_to_idle() -> void:
	assert_true(shell.travel("kitchen").ok)
	var body: TDKitchenPlayer = shell.kitchen_view.kitchen.world._player
	body.position = Vector2(640, 420)
	await wait_physics_frames(2)
	var seen: Dictionary = {}
	Input.action_press("world_down")
	for tick: int in 38:
		await wait_physics_frames(1)
		seen[body.walk_frame] = true
	Input.action_release("world_down")
	assert_eq(body.facing, Vector2i.DOWN)
	for frame: int in 4: assert_true(seen.has(frame), "Real input reaches walk frame %d" % frame)
	assert_gt(body.position.y, 500.0)
	await wait_physics_frames(2)
	assert_eq(body.walk_frame, -1)
	assert_same(body.animation_texture(), TDChefArt.texture(Vector2i.DOWN))
	body.position = Vector2(640, 310)
	Input.action_press("world_up")
	await wait_physics_frames(30)
	var blocked_at := body.position
	assert_eq(body.walk_frame, -1, "Held key against a straight wall must not walk in place")
	await wait_physics_frames(4)
	assert_almost_eq(body.position.y, blocked_at.y, .01)
	assert_gt(body.position.y, 280.0, "New visible countertop blocks the real feet")
	Input.action_release("world_up")
	assert_eq(body.facing, Vector2i.UP)

func test_pause_modal_and_hidden_room_do_not_advance_animation_or_move_body() -> void:
	shell.travel("kitchen")
	var body: TDKitchenPlayer = shell.kitchen_view.kitchen.world._player
	body.position = Vector2(640, 420)
	Input.action_press("world_right")
	await wait_physics_frames(12)
	assert_gte(body.walk_frame, 0)
	get_tree().paused = true
	var paused_frame := body.walk_frame
	var paused_at := body.position
	await wait_physics_frames(6)
	assert_eq(body.walk_frame, paused_frame)
	assert_eq(body.position, paused_at)
	Input.action_release("world_right")
	get_tree().paused = false
	await wait_physics_frames(2)
	shell.show_pause()
	Input.action_press("world_down")
	await wait_physics_frames(5)
	assert_eq(body.walk_frame, -1)
	assert_eq(body.position, paused_at)
	Input.action_release("world_down")
	shell._close_dialog()
	shell.travel("restaurant")
	Input.action_press("world_right")
	await wait_physics_frames(6)
	assert_eq(body.walk_frame, -1)
	assert_eq(body.position, paused_at)
	Input.action_release("world_right")
	shell.travel("kitchen")
	await wait_physics_frames(2)
	assert_eq(body.walk_frame, -1)

func test_all_rooms_share_protagonist_and_restaurant_projects_same_frame_and_feet() -> void:
	for location: String in ["town", "restaurant", "kitchen", "cottage"]:
		assert_true(shell.travel(location).ok)
		var body: TDKitchenPlayer
		match location:
			"town": body = shell.town._player
			"restaurant": body = shell.restaurant._player
			"kitchen": body = shell.kitchen_view.kitchen.world._player
			"cottage": body = shell.cottage.player
		for facing: Vector2i in FACES:
			body.face(Vector2(facing))
			assert_same(body.animation_texture(), TDChefArt.texture(facing))
			assert_eq(body._sprite.texture, body.animation_texture())
			var bottom := body._sprite.position.y + body._sprite.texture.get_height() * body._sprite.scale.y * .5
			assert_almost_eq(bottom, 0.0, .001, "Feet anchor is independent of image whitespace")
	shell.travel("restaurant")
	var room := shell.restaurant
	room.teleport_player(Vector2i(6,8))
	Input.action_press("world_right")
	var seen: Dictionary = {}
	for tick: int in 50:
		await wait_physics_frames(1)
		room._iso.sync(room._player, room.guest_nodes())
		assert_eq(room._iso.player_walk_frame, room._player.walk_frame)
		assert_eq(room._iso.player_facing, Vector2i.RIGHT)
		seen[room._iso.player_walk_frame] = true
		var rect := room._iso.chef_rect(room.player_position())
		var grid := room.player_position()/float(room.layout.cell_px)
		assert_almost_eq(rect.end.y, TDRestaurantIsoView.project(grid.x,grid.y).y, .001)
	Input.action_release("world_right")
	assert_gte(seen.size(), 3, "Self-drawn restaurant really follows changing walk frames")
	assert_false(room._player._sprite.visible, "Restaurant keeps its one projected visual")
	await wait_physics_frames(2)
	room._iso.sync(room._player, room.guest_nodes())
	assert_eq(room._iso.player_walk_frame, -1)

func test_restaurant_stride_counts_rendered_pixels_once_in_each_direction() -> void:
	assert_true(shell.travel("restaurant").ok)
	var room := shell.restaurant
	var body := room._player
	for action: String in ["world_right", "world_left", "world_up", "world_down"]:
		body.set_controls_enabled(false)
		room.teleport_player(Vector2i(6,8))
		await wait_physics_frames(2)
		var start := room.player_position() / float(room.layout.cell_px)
		var screen_start := TDRestaurantIsoView.project(start.x, start.y)
		body.set_controls_enabled(true)
		Input.action_press(action)
		await wait_physics_frames(6)
		Input.action_release(action)
		var finish := room.player_position() / float(room.layout.cell_px)
		var traveled := TDRestaurantIsoView.project(finish.x, finish.y).distance_to(screen_start)
		# Independent draw projection and accepted distances; never call the
		# production inverse transform or read its stride settings as the oracle.
		# Single grid-axis keys now render diagonally; their horizontal component
		# dominates the 2:1 projection, selecting the left/right walking pose.
		var pixels_per_cycle := 140.0
		assert_gt(traveled, 15.0, "Real input moved the on-screen feet")
		assert_lt(traveled, 25.0, "Six physics ticks retain the real 180 px/s speed")
		assert_almost_eq(body._walk_phase * pixels_per_cycle, traveled, .001, action+": each drawn pixel advances the stride only once")
