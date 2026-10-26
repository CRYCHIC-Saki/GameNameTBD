extends GutTest

const WORLD := preload("res://src/world/kitchen_world.tscn")
var world: TDKitchenWorld

func before_each() -> void:
	world = WORLD.instantiate() as TDKitchenWorld
	add_child_autofree(world)
	await get_tree().physics_frame

func after_each() -> void:
	for action: String in ["world_left", "world_right", "world_up", "world_down", "world_interact"]:
		Input.action_release(action)
	get_tree().paused = false

func _press_e(echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_E
	event.keycode = KEY_E
	event.pressed = true
	event.echo = echo
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	event = InputEventKey.new()
	event.physical_keycode = KEY_E
	event.keycode = KEY_E
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func test_actual_scene_uses_generated_assets_and_character_body() -> void:
	assert_true(world.get_node("Player") is CharacterBody2D)
	assert_not_null((world.get_node("Background") as Sprite2D).texture)
	assert_not_null((world.get_node("Player/Sprite2D") as Sprite2D).texture)
	assert_false(world.interaction_available())
	watch_signals(world)
	_press_e()
	assert_signal_emit_count(world, "cooking_requested", 0)

func test_near_stove_input_emits_identity_once_until_reenabled() -> void:
	var player := world.get_node("Player") as TDKitchenPlayer
	player.position = Vector2(588.0, 310.0)
	assert_true(world.interaction_available())
	watch_signals(world)
	_press_e(true)
	assert_signal_emit_count(world, "cooking_requested", 0)
	_press_e()
	assert_signal_emitted_with_parameters(world, "cooking_requested", ["kitchen.stove.left"])
	assert_false(world.interaction_available())
	_press_e()
	assert_signal_emit_count(world, "cooking_requested", 1)
	world.set_controls_enabled(true)
	player.position = Vector2(693.0, 310.0)
	_press_e()
	assert_signal_emitted_with_parameters(world, "cooking_requested", ["kitchen.stove.right"])
	assert_signal_emit_count(world, "cooking_requested", 2)

func test_real_movement_and_engine_collision_block_counter() -> void:
	var player := world.get_node("Player") as TDKitchenPlayer
	var initial := world.player_position()
	Input.action_press("world_right")
	await wait_physics_frames(5)
	Input.action_release("world_right")
	assert_gt(world.player_position().x, initial.x)
	player.position = Vector2(588.0, 310.0)
	await get_tree().physics_frame
	var collision := player.move_and_collide(Vector2(0.0, -200.0))
	assert_not_null(collision, "The actual counter collider must stop walking")
	assert_gt(player.position.y, 252.0)
	assert_lt(player.position.y, 310.0)

func test_disabled_controls_and_paused_world_cannot_move_or_interact() -> void:
	var player := world.get_node("Player") as TDKitchenPlayer
	player.position = Vector2(588.0, 310.0)
	world.set_controls_enabled(false)
	var initial := world.player_position()
	Input.action_press("world_down")
	await wait_physics_frames(4)
	assert_eq(world.player_position(), initial)
	assert_false(world.request_interaction())
	Input.action_release("world_down")
	world.set_controls_enabled(true)
	get_tree().paused = true
	assert_false(world.interaction_available())
	assert_false(world.request_interaction())
	get_tree().paused = false
	assert_true(world.interaction_available())

func test_hired_cooks_stay_at_the_stoves() -> void:
	var crew := TDRestaurantCrew.new()
	assert_true(crew.hire("cook-he").ok)
	assert_true(crew.hire("cook-zhou").ok)
	world.crew = crew
	world._crew_time = 0.0
	world._sync_staff()
	var cook := world.get_node("Cook0") as Node2D
	var start := cook.position
	assert_gt(start.distance_to((world.get_node("Cook1") as Node2D).position), 40.0)
	world._crew_time = 2.0
	world._sync_staff()
	assert_eq(cook.position, start)
	assert_eq((world.get_node("Cook0/Body") as Sprite2D).position.y, -47.0)
	var counter := Rect2(Vector2(924.0, 514.0), Vector2(232.0, 102.0))
	for index: int in 2:
		var point := TDKitchenWorld.cook_point(index, 3.0)
		assert_gt(point.x, 108.0)
		assert_lt(point.x, 1172.0)
		assert_gt(point.y, 264.0)
		assert_lt(point.y, 700.0)
		assert_false(counter.has_point(point))
		assert_eq(point, TDKitchenWorld.cook_point(index, 0.0))

func test_close_disables_world_and_reentry_starts_fresh() -> void:
	(world.get_node("Player") as TDKitchenPlayer).position = Vector2(588.0, 310.0)
	world.close()
	assert_false(world.request_interaction())
	var second := WORLD.instantiate() as TDKitchenWorld
	add_child_autofree(second)
	await get_tree().physics_frame
	assert_eq(second.player_position(), Vector2(640.0, 530.0))
	assert_false(second.interaction_available())
	assert_true((second.get_node("Player") as TDKitchenPlayer).controls_enabled)
