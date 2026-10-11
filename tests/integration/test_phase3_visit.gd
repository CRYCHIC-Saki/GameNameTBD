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

func _until(guest: TDRestaurantGuest, ready: Callable) -> bool:
	var guard := 0
	while not bool(ready.call()) and guest.phase != "gone" and guard < 500:
		world.pump_service(1, 0.25)
		guard += 1
	return bool(ready.call())
