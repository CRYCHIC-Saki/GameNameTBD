extends SceneTree

func _initialize() -> void:
	print("VISUAL_START")
	call_deferred("_run")

func _run() -> void:
	print("VISUAL_RUN")
	var world := TDRestaurantWorld.new()
	root.add_child(world)
	for frame: int in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	if not _save("restaurant-play"):
		quit(1)
		return
	world._toggle_edit()
	await process_frame
	await RenderingServer.frame_post_draw
	if not _save("restaurant-edit"):
		quit(1)
		return
	world.hire_role("greeter", true)
	world.hire_role("cashier", true)
	if not world.spawn_guest().ok:
		quit(1)
		return
	for step: int in 40:
		for guest: TDRestaurantGuest in world.guest_nodes():
			guest.advance(80.0)
		await process_frame
	await RenderingServer.frame_post_draw
	if not _save("restaurant-guest"):
		quit(1)
		return
	print("VISUAL_OK")
	quit(0)

func _save(id: String) -> bool:
	var texture := root.get_texture()
	print("CAPTURE ", id, " texture=", texture)
	if texture == null:
		return false
	var path := ProjectSettings.globalize_path("res://artifacts/" + id + ".png")
	var error := texture.get_image().save_png(path)
	print("SAVED ", path, " ", error)
	return error == OK
