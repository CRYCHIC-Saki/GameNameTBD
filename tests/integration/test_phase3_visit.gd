extends GutTest

var world: TDRestaurantWorld

func before_each() -> void:
	world = TDRestaurantWorld.new()
	add_child_autofree(world)
	await get_tree().physics_frame

func test_service_guest_can_be_refused_or_served_without_touching_the_shop_save() -> void:
	var shop := "user://shop-v1.json"
	var before := FileAccess.get_file_as_bytes(shop) if FileAccess.file_exists(shop) else PackedByteArray()
	assert_true(world.hire_role("greeter", true).ok)
	assert_true(world.hire_role("cashier", true).ok)
	var denied := world.spawn_service_guest("kaoya")
	world.hire_role("greeter", false)
	assert_eq(world.spawn_service_guest("kaoya").code, "NEED_GREETER")
	assert_true(world.hire_role("greeter", true).ok)
	assert_eq(denied.code, "VISIT")
	var guest := world.guest_nodes()[0]
	assert_true(_until(guest, func() -> bool: return guest.is_waiting() and guest.phase == "order"))
	assert_true(guest.off_menu)
	world._refuse_order()
	assert_true(_until(guest, func() -> bool: return guest.phase == "gone"))
	assert_false(world.session.recipes.has("kaoya"))
	var served := world.spawn_service_guest("changfen")
	assert_true(served.ok, served.message)
	var second := world.guest_nodes()[1]
	assert_true(_until(second, func() -> bool: return second.is_waiting() and second.phase == "order"))
	world._accept_order()
	assert_true(_until(second, func() -> bool: return second.is_waiting() and second.phase == "wait_serve"))
	world._serve(92.0)
	assert_true(_until(second, func() -> bool: return second.phase == "gone"))
	assert_gte(second.review_score, 0.0)
	assert_eq(world.session.recipes.has("changfen"), second.review_score >= 60.0)
	var after := FileAccess.get_file_as_bytes(shop) if FileAccess.file_exists(shop) else PackedByteArray()
	assert_eq(after, before)

func test_town_crossroads_supply_delay_and_zone_pool() -> void:
	var town := TDTownWorld.new()
	add_child_autofree(town)
	await get_tree().physics_frame
	var player := town.get_node("Player") as TDKitchenPlayer
	var initial := player.position
	Input.action_press("world_right")
	await wait_physics_frames(6)
	Input.action_release("world_right")
	assert_gt(player.position.x, initial.x)
	var camera := town.get_node("TownCamera") as Camera2D
	assert_gt(camera.zoom.x, 1.5)
	assert_true(camera.is_current())
	var seen := camera.position.x
	player.position += Vector2(240, 0)
	await wait_process_frames(20)
	assert_gt(camera.position.x, seen)
	var ordered := town.session.order_supply("tomato")
	assert_true(ordered.ok, ordered.message)
	assert_eq(int((town.session.supply.incoming[0] as Dictionary)["arrive"]), town.session.day + 1)
	assert_true(town.session.enable_buff("nearby_market").ok)
	var rushed := town.session.order_supply("egg")
	assert_eq(int(rushed.data["arrive"]), town.session.day)
	assert_eq(town.session.supply.count("egg"), 1)
	var before := town.session.npcs.size()
	town.session.set_zone_enabled("urban_village", false)
	assert_eq(town.session.npcs.size(), before - 10)
	assert_gt(town.session.report().length(), 40)

func test_a_plate_reaches_only_the_guest_who_ordered_it() -> void:
	assert_true(world.hire_role("greeter", true).ok)
	assert_true(world.hire_role("cashier", true).ok)
	assert_eq(world.session.catalog.dish_id_for_kitchen("service.tomato_egg"), "tomato_egg")
	assert_eq(world.session.catalog.dish_id_for_kitchen("phase3.changfen"), "changfen")
	var visit := world.spawn_service_guest("tomato_egg")
	assert_true(visit.ok, visit.message)
	var guest := world.guest_nodes()[0]
	assert_ne(guest.ticket_id, "")
	assert_true(_until(guest, func() -> bool: return guest.is_waiting() and guest.phase == "wait_serve"))
	var wrong := world.deliver_to_guest("changfen", 90.0, false)
	assert_false(wrong.ok)
	assert_eq(wrong.code, "NO_GUEST")
	assert_true(guest.is_waiting())
	var unmatched := world.deliver_to_guest("", 90.0, false)
	assert_eq(unmatched.code, "UNKNOWN_DISH")
	assert_true(guest.is_waiting())
	var served := world.deliver_to_guest("tomato_egg", 88.0, false)
	assert_true(served.ok, served.message)
	assert_eq(guest.quality, 88.0)
	assert_false(guest.is_waiting())
	assert_eq(String(served.data["id"]), guest.ticket_id)
	var shop := "user://shop-v1.json"
	var before := FileAccess.get_file_as_bytes(shop) if FileAccess.file_exists(shop) else PackedByteArray()
	var after := FileAccess.get_file_as_bytes(shop) if FileAccess.file_exists(shop) else PackedByteArray()
	assert_eq(after, before)

func test_a_seated_guest_leaves_when_the_plate_never_comes() -> void:
	assert_true(world.hire_role("greeter", true).ok)
	var visit := world.spawn_service_guest("tomato_egg")
	assert_true(visit.ok, visit.message)
	var guest := world.guest_nodes()[0]
	assert_true(_until(guest, func() -> bool: return guest.is_waiting() and guest.phase == "wait_serve"))
	for item: Variant in world.session.floor.tickets:
		(item as Dictionary)["patience"] = 0.25
	world.pump_service(4, 0.2)
	assert_true(guest.walkout)
	assert_true(_until(guest, func() -> bool: return guest.phase == "gone"))
	assert_false(bool(world.last_visit["accepted"]))
	assert_true(world.session.log_lines[world.session.log_lines.size() - 1].contains("等太久"))

func test_player_cannot_leave_the_town_roads() -> void:
	var town := TDTownWorld.new()
	add_child_autofree(town)
	await get_tree().physics_frame
	var player := town.get_node("Player") as TDKitchenPlayer
	var spot := _road_with_blocked_neighbor(town.session.town_map, Vector2i(0, -1))
	player.position = Vector2(300, 24) + Vector2((spot.x + 0.5) * TDTownWorld.CELL, (spot.y + 0.5) * TDTownWorld.CELL)
	Input.action_press("world_up")
	await wait_physics_frames(8)
	Input.action_release("world_up")
	var stayed := town._player_cell()
	assert_true(town.session.town_map.is_road(stayed.x, stayed.y))
	assert_ne(stayed, spot + Vector2i(0, -1))
	Input.action_press("world_right")
	await wait_physics_frames(6)
	Input.action_release("world_right")
	var moved := town._player_cell()
	assert_true(town.session.town_map.is_road(moved.x, moved.y))

func _road_with_blocked_neighbor(map: TDTownMap, neighbor: Vector2i) -> Vector2i:
	for y in TDTownMap.SIZE:
		for x in TDTownMap.SIZE:
			if not map.is_road(x, y):
				continue
			if map.is_road(x + neighbor.x, y + neighbor.y):
				continue
			return Vector2i(x, y)
	return Vector2i(TDTownMap.CENTER, TDTownMap.CENTER)

func _until(guest: TDRestaurantGuest, ready: Callable) -> bool:
	var guard := 0
	while not bool(ready.call()) and guest.phase != "gone" and guard < 500:
		world.pump_service(1, 0.25)
		guard += 1
	return bool(ready.call())
