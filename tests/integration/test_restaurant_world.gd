extends GutTest

const APP := preload("res://src/app/main.tscn")
var world: TDRestaurantWorld

func before_each() -> void:
	world = TDRestaurantWorld.new()
	add_child_autofree(world)
	await get_tree().physics_frame

func after_each() -> void:
	for action: String in ["world_left", "world_right", "world_up", "world_down", "world_interact"]:
		Input.action_release(action)
	get_tree().paused = false

func test_scene_builds_a_walkable_room_with_placeholder_fixtures() -> void:
	assert_true(world.get_node("Player") is CharacterBody2D)
	assert_not_null((world.get_node("Floor") as Sprite2D).texture)
	assert_gte(world.fixture_count(), 13)
	assert_eq(world.spawn_guest().code, "NEED_GREETER")
	assert_eq(world.guest_nodes().size(), 0)
	assert_false(world.request_interaction())

func test_the_entrance_opens_the_kitchen_link() -> void:
	var opened: Array[bool] = []
	world.kitchen_requested.connect(func() -> void: opened.append(true))
	world.teleport_player(world.layout.entrance())
	assert_true(world.request_interaction())
	assert_eq(opened.size(), 1)
	assert_true(world._status.text.contains("后厨"))

func test_player_walks_the_aisle_and_walls_stop_them() -> void:
	var player := world.get_node("Player") as TDKitchenPlayer
	var initial := world.player_position()
	Input.action_press("world_right")
	await wait_physics_frames(6)
	Input.action_release("world_right")
	assert_gt(world.player_position().x, initial.x)
	world.teleport_player(world.layout.entrance())
	await get_tree().physics_frame
	var collision := player.move_and_collide(Vector2(-50, 0))
	assert_not_null(collision, "The facade wall must stop the player")
	assert_gt(player.position.x, 64.0)
	player.set_controls_enabled(false)
	var held := world.player_position()
	Input.action_press("world_down")
	await wait_physics_frames(4)
	assert_eq(world.player_position(), held)

func test_interact_reports_staff_needs_and_ignores_key_repeat() -> void:
	var welcome := world.layout.piece_by_kind("welcome_desk")
	world.teleport_player(Vector2i(int(welcome["approach_x"]), int(welcome["approach_y"])))
	watch_signals(world)
	_press_e(true)
	assert_signal_emit_count(world, "fixture_used", 0)
	_press_e()
	assert_signal_emitted_with_parameters(world, "fixture_used", [welcome["id"], "NEED_GREETER"])
	var cashier := world.layout.piece_by_kind("cashier")
	world.teleport_player(Vector2i(int(cashier["approach_x"]), int(cashier["approach_y"])))
	_press_e()
	assert_signal_emitted_with_parameters(world, "fixture_used", [cashier["id"], "NEED_CASHIER"])
	assert_true(world.hire_role("cashier", true).ok)
	_press_e()
	assert_signal_emitted_with_parameters(world, "fixture_used", [cashier["id"], "READY"])

func test_pause_freezes_walking() -> void:
	var initial := world.player_position()
	get_tree().paused = true
	Input.action_press("world_right")
	await wait_physics_frames(4)
	assert_eq(world.player_position(), initial)

func test_hired_guest_reaches_the_seat_approach() -> void:
	assert_true(world.hire_role("greeter", true).ok)
	var spawned := world.spawn_guest()
	assert_true(spawned.ok, spawned.message)
	var guest := world.guest_nodes()[0]
	var guard := 0
	while not guest.finished and guard < 80:
		guest.advance(96)
		guard += 1
	assert_true(guest.finished)
	var seat := world.layout.piece(guest.seat_id)
	assert_eq(String(seat["seat_use"]), "dining")
	assert_eq(guest.position, world.layout.cell_center(Vector2i(int(seat["approach_x"]), int(seat["approach_y"]))))
	var second := world.spawn_guest()
	assert_true(second.ok, second.message)
	assert_ne(world.guest_nodes()[1].seat_id, guest.seat_id)

func test_edit_paint_moves_a_blocked_player_and_can_add_a_stool() -> void:
	world.teleport_player(Vector2i(8, 8))
	var painted := world.paint_cell(8, 8, "#")
	assert_true(painted.ok, painted.message)
	assert_false(world.layout.is_walkable(8, 8))
	assert_eq(world.cell_of_player(), world.layout.entrance())
	var before := world.fixture_count()
	var placed := world.place_kind("stool", 11, 6)
	assert_true(placed.ok, placed.message)
	assert_eq(world.fixture_count(), before + 1)
	var floor := world.get_node("Floor") as Sprite2D
	var low := floor.texture.get_image().get_pixel(136, 72)
	world._culture = "french"
	world._tier = "high"
	assert_true(world.restyle_venue().ok)
	assert_ne((world.get_node("Floor") as Sprite2D).texture.get_image().get_pixel(136, 72), low)
	assert_eq(String(world.layout.piece_by_kind("hotpot_table")["style_id"]), "french_high")

func test_menu_opens_restaurant_without_writing_player_saves() -> void:
	var app := APP.instantiate() as TDApplication
	add_child_autofree(app)
	await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute("res://artifacts/test-storage")
	var user := "user://restaurant-layout-v1.json"
	var shop := "user://shop-v1.json"
	var user_before := FileAccess.get_file_as_bytes(user) if FileAccess.file_exists(user) else PackedByteArray()
	var shop_before := FileAccess.get_file_as_bytes(shop) if FileAccess.file_exists(shop) else PackedByteArray()
	var path := "res://artifacts/test-storage/restaurant-menu-%d.json" % Time.get_ticks_usec()
	app.enter_restaurant(path)
	await get_tree().process_frame
	assert_eq(app.restaurant.save_path, path)
	assert_gt(app.restaurant.player_position().x, 0.0)
	app.return_to_menu()
	await get_tree().process_frame
	assert_null(app.restaurant)
	var user_after := FileAccess.get_file_as_bytes(user) if FileAccess.file_exists(user) else PackedByteArray()
	var shop_after := FileAccess.get_file_as_bytes(shop) if FileAccess.file_exists(shop) else PackedByteArray()
	assert_eq(user_after, user_before)
	assert_eq(shop_after, shop_before)

func test_edit_click_selects_places_and_removes_through_a_blocking_parent() -> void:
	var shell := Control.new()
	shell.mouse_filter = Control.MOUSE_FILTER_STOP
	shell.position = Vector2.ZERO
	shell.size = get_viewport().get_visible_rect().size
	add_child_autofree(shell)
	var room := TDRestaurantWorld.new()
	shell.add_child(room)
	await get_tree().process_frame
	room._toggle_edit()
	var piece: Dictionary = room.layout.pieces()[0]
	var id := String(piece["id"])
	_click_room(room, int(piece["x"]), int(piece["y"]), MOUSE_BUTTON_LEFT)
	assert_eq(room._selected, id)
	var spot := _open_dining_cell(room)
	assert_ne(spot, Vector2i(-1, -1))
	var before := room.layout.pieces().size()
	room._tool = "place"
	room._armed_kind = "stool"
	_click_room(room, spot.x, spot.y, MOUSE_BUTTON_LEFT)
	assert_eq(room.layout.pieces().size(), before + 1, room._status.text)
	_click_room(room, int(piece["x"]), int(piece["y"]), MOUSE_BUTTON_RIGHT)
	assert_true(room.layout.piece(id).is_empty())

func test_edit_bar_tracks_viewport_size_changes() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 800)
	add_child_autofree(viewport)
	var room := TDRestaurantWorld.new()
	viewport.add_child(room)
	await get_tree().process_frame
	room._toggle_edit()
	assert_eq(room._bar.position.y + room._bar.size.y, 800.0)
	assert_eq(room._bar.size.x, 1280.0)
	viewport.size = Vector2i(1600, 1000)
	await get_tree().process_frame
	assert_eq(room._bar.position.y + room._bar.size.y, 1000.0)
	assert_eq(room._bar.size.x, 1600.0)
	var spot := _open_dining_cell(room)
	var local := TDRestaurantIsoView.project(spot.x + 0.5, spot.y + 0.5)
	assert_false(room._pointer_on_chrome(room._iso.get_global_transform_with_canvas() * local))

func test_waiters_stay_put_until_a_guest_is_waiting_for_food() -> void:
	assert_true(world.layout.crew.hire("waiter-ning").ok)
	assert_true(world.layout.crew.hire("waiter-tao").ok)
	var idle: Array = world._crew_points(0.5)
	var still: Array = world._crew_points(0.5)
	assert_eq(idle.size(), 2)
	assert_eq((still[0] as Dictionary).point, (idle[0] as Dictionary).point)
	assert_eq((still[1] as Dictionary).point, (idle[1] as Dictionary).point)
	assert_false(bool((still[0] as Dictionary).moving))
	var seat := world.layout.piece_by_kind("dining_table")
	var table := world.layout.cell_center(world.approach_cell(String(seat["id"])))
	var guest := TDRestaurantGuest.new()
	guest.phase = "wait_serve"
	guest.seat_id = String(seat["id"])
	world._guests.add_child(guest)
	var serving: Array = world._crew_points(0.25)
	var home: Vector2 = idle[0].point
	assert_gt(home.distance_to((serving[0] as Dictionary).point), 1.0)
	assert_lt((serving[0] as Dictionary).point.distance_to(table), home.distance_to(table))
	assert_eq((serving[1] as Dictionary).point, (idle[1] as Dictionary).point)
	guest.phase = "leave"
	var returning: Array = world._crew_points(0.25)
	assert_lt((returning[0] as Dictionary).point.distance_to(home), (serving[0] as Dictionary).point.distance_to(home))

func test_business_guest_follows_the_shop_order_through_leaving() -> void:
	var service := TDServiceCatalog.new()
	assert_true(service.load_file().ok)
	var shop := TDShopSession.new(service, "floor-guest", 22)
	assert_true(shop.buy(shop.offer("service.tomato_egg").stock, "buy").ok)
	assert_true(shop.open_day().ok)
	shop.advance(1.0)
	assert_eq(shop.active_orders().size(), 1)
	var order_id := str(shop.active_orders()[0].id)
	world.player_mode = true
	world.business = shop
	world._sync_business_guests()
	assert_eq(world.guest_nodes().size(), 1)
	var guest := world.guest_nodes()[0]
	assert_eq(guest.phase, "approach")
	assert_true(world._order_board.text.contains("装修效果"))
	var guard := 0
	while guest.phase == "approach" and guard < 40:
		guest.advance(240.0)
		world._sync_business_guests()
		guard += 1
	assert_eq(guest.phase, "wait_serve")
	assert_true(guest.dish_name.contains("等上菜"))
	var elapsed := float(shop.snapshot().elapsed_sec)
	shop._s.orders[0].status = "SERVED"
	shop._s.orders[0].score = {"satisfaction": 91.0}
	shop._s.orders[0].prepaid_cents = 1200
	world._sync_business_guests()
	assert_eq(guest.phase, "eat")
	assert_true(guest.dish_name.contains("91"))
	shop._s.elapsed_sec = elapsed + 6.0
	world._sync_business_guests()
	assert_eq(guest.phase, "pay")
	assert_true(guest.dish_name.contains("结账"))
	shop._s.elapsed_sec = elapsed + 9.0
	world._sync_business_guests()
	assert_eq(guest.phase, "leave")
	guard = 0
	while is_instance_valid(guest) and world._business_guests.has(order_id) and guard < 50:
		guest.advance(240.0)
		world._sync_business_guests()
		guard += 1
	assert_false(world._business_guests.has(order_id))
	assert_true(world.layout.crew.hire("cook-he").ok)
	var saw_cook := false
	for person: Variant in world._crew_points(0.0):
		if str((person as Dictionary).label).begins_with("后厨"):
			saw_cook = true
	assert_true(saw_cook)

func test_unhired_floor_posts_wait_for_the_player_and_do_not_charge_again() -> void:
	var service := TDServiceCatalog.new()
	assert_true(service.load_file().ok)
	var shop := TDShopSession.new(service, "floor-posts", 22)
	assert_true(shop.buy(shop.offer("service.tomato_egg").stock, "buy").ok)
	assert_true(shop.open_day().ok)
	shop.advance(1.0)
	var order_id := str(shop.active_orders()[0].id)
	var cents := int(shop.snapshot().money_cents)
	world.player_mode = true
	world.floor_service = true
	world.business = shop
	world._sync_business_guests()
	var guest := world.guest_nodes()[0]
	assert_eq(guest.phase, "approach")
	assert_false(bool(guest.get_meta("welcomed", false)))
	assert_true(world._order_board.text.contains("你来"))
	world.teleport_player(world._cell_at(guest.position))
	assert_true(world.request_interaction())
	assert_true(bool(guest.get_meta("welcomed", false)))
	var guard := 0
	while guest.phase == "approach" and guard < 40:
		guest.advance(240.0)
		world._sync_business_guests()
		guard += 1
	assert_eq(guest.phase, "wait_serve")
	var elapsed := float(shop.snapshot().elapsed_sec)
	shop._s.orders[0].status = "SERVED"
	shop._s.orders[0].score = {"satisfaction": 91.0}
	shop._s.orders[0].prepaid_cents = 1200
	world._sync_business_guests()
	assert_eq(guest.phase, "wait_serve")
	world.teleport_player(world.pass_cell())
	assert_true(world.request_interaction())
	assert_eq(world._plate_order, order_id)
	world.teleport_player(world._cell_at(guest.position))
	assert_true(world.request_interaction())
	world._sync_business_guests()
	assert_eq(guest.phase, "eat")
	shop._s.elapsed_sec = elapsed + 6.0
	world._sync_business_guests()
	assert_eq(guest.phase, "pay")
	shop._s.elapsed_sec = elapsed + 9.0
	world._sync_business_guests()
	assert_eq(guest.phase, "pay")
	assert_true(world.request_interaction())
	world._sync_business_guests()
	assert_eq(guest.phase, "leave")
	assert_eq(str(shop.order(order_id).status), "SERVED")
	assert_eq(int(shop.snapshot().money_cents), cents)

func test_hired_greeter_runner_and_cashier_carry_the_visit() -> void:
	var service := TDServiceCatalog.new()
	assert_true(service.load_file().ok)
	var shop := TDShopSession.new(service, "floor-hired", 22)
	assert_true(shop.buy(shop.offer("service.tomato_egg").stock, "buy").ok)
	assert_true(shop.open_day().ok)
	shop.advance(1.0)
	world.player_mode = true
	world.floor_service = true
	world.business = shop
	assert_true(world.hire_role("greeter", true).ok)
	assert_true(world.hire_role("runner", true).ok)
	assert_true(world.hire_role("cashier", true).ok)
	world._sync_business_guests()
	var guest := world.guest_nodes()[0]
	var guard := 0
	while guest.phase == "approach" and guard < 40:
		guest.advance(240.0)
		world._sync_business_guests()
		guard += 1
	assert_eq(guest.phase, "wait_serve")
	var saw_greeter := false
	for person: Variant in world._crew_points(0.0):
		if str((person as Dictionary).label) == "迎宾":
			saw_greeter = true
	assert_true(saw_greeter)
	var elapsed := float(shop.snapshot().elapsed_sec)
	shop._s.orders[0].status = "SERVED"
	shop._s.orders[0].score = {"satisfaction": 80.0}
	world._sync_business_guests()
	assert_eq(guest.phase, "eat")
	shop._s.elapsed_sec = elapsed + 6.0
	world._sync_business_guests()
	assert_eq(guest.phase, "pay")
	shop._s.elapsed_sec = elapsed + 9.0
	world._sync_business_guests()
	assert_eq(guest.phase, "leave")

func _open_dining_cell(room: TDRestaurantWorld) -> Vector2i:
	for y in room.layout.rows - 1:
		for x in room.layout.columns:
			if room.layout.cell_zone(x, y) != "dining":
				continue
			if room._piece_at(Vector2i(x, y)) != "":
				continue
			if not room.layout.is_walkable(x, y + 1):
				continue
			return Vector2i(x, y)
	return Vector2i(-1, -1)

func _click_room(room: TDRestaurantWorld, x: int, y: int, button: int) -> void:
	var local := TDRestaurantIsoView.project(float(x) + 0.5, float(y) + 0.5)
	var camera := room.get_node("IsoView/IsoCamera") as Camera2D
	var screen := local - camera.position + get_viewport().get_visible_rect().size * 0.5
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	event.position = screen
	event.global_position = screen
	get_tree().root.push_input(event, true)

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
