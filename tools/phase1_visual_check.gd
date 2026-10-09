extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _capture(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png("res://artifacts/phase1-" + name + ".png")
	if error != OK:
		printerr("CAPTURE_FAILED ", name, " ", error)
		quit(1)

func _run() -> void:
	var app := load("res://src/app/main.tscn").instantiate() as TDApplication
	app.settings_path = "res://artifacts/test-storage/visual-phase1.json"
	root.add_child(app)
	await _capture("menu")
	app.enter_cooking()
	var kitchen := app.cooking_kitchen
	kitchen.automatic_time = false
	kitchen.audio_enabled = false
	kitchen.accept_order()
	kitchen.perform("add", {"ingredient_id": "tomato"})
	kitchen.perform("add", {"ingredient_id": "egg"})
	kitchen.perform("cut", {"ingredient_id": "tomato", "shape": "dice"})
	kitchen.advance_time(1.0)
	await _capture("cut")
	for beat: int in 8:
		var event := InputEventKey.new()
		event.keycode = KEY_SPACE
		event.physical_keycode = KEY_SPACE
		event.pressed = true
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		event = event.duplicate()
		event.pressed = false
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		kitchen.advance_time(0.5 if beat < 7 else 0.15)
	kitchen.perform("season", {"ingredient_id": "sugar", "amount": 3})
	kitchen.perform("heat")
	kitchen.route_input(1.0)
	kitchen.advance_time(3.0)
	app.toggle_pause()
	await _capture("paused")
	app.toggle_pause()
	kitchen.route_input(1.0)
	kitchen.advance_time(3.0)
	var result := kitchen.perform("plate")
	await _capture("feedback")
	var feedback := kitchen.last_feedback()
	var file := FileAccess.open("res://artifacts/phase1-visual.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"renderer": RenderingServer.get_video_adapter_name(), "captures": 4, "flow": "PASS" if result.ok and feedback.get("ok", false) else "FAIL", "feedback": feedback, "physical_input": "NOT_RUN"}, "\t"))
	file.close()
	app.return_to_menu()
	app.queue_free()
	await process_frame
	print("PHASE1_VISUAL captures=4 flow=", result.ok and feedback.get("ok", false))
	quit(0 if result.ok and feedback.get("ok", false) else 1)
