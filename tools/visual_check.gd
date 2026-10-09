extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var app := load("res://src/app/main.tscn").instantiate() as TDApplication
	app.settings_path = "res://artifacts/visual-settings.json"
	root.add_child(app)
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var err := image.save_png("res://artifacts/menu.png")
	if err != OK:
		printerr("VISUAL_CAPTURE_FAILED ", err)
		quit(1)
		return
	app.enter_kitchen()
	app.kitchen.automatic_time = false
	app.kitchen.start_operation()
	var event := InputEventKey.new()
	event.keycode = KEY_SPACE
	event.physical_keycode = KEY_SPACE
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	app.kitchen.advance_time(0.6)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/kitchen.png")
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	app.toggle_pause()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/paused.png")
	app.return_to_menu()
	await process_frame
	print("VISUAL_CHECK renderer=", RenderingServer.get_video_adapter_name(), " captures=3 flow=PASS")
	app.queue_free()
	await process_frame
	quit(0)
