extends SceneTree
var captures: int = 0
func _initialize() -> void: call_deferred("_run")
func _capture(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png("res://artifacts/full-" + name + ".png")
	if error != OK: printerr("CAPTURE_FAILED ", name); quit(1)
	captures += 1

func _run() -> void:
	var app := load("res://src/app/main.tscn").instantiate() as TDApplication
	app.settings_path = "res://artifacts/test-storage/full-visual-settings.json"
	root.add_child(app)
	app.enter_full_kitchen()
	var kitchen: TDFullKitchen = app.full_kitchen
	kitchen.auto_advance = false
	await _capture("world")
	kitchen.open_bench()
	kitchen.set_dual(true)
	var left: TDCookingLane = kitchen.lanes[0]
	var right: TDCookingLane = kitchen.lanes[1]
	var tomato := left.perform("add", {"ingredient_id": "tomato"})
	left.perform("add", {"ingredient_id": "egg"})
	left.perform("cut", {"instance_id": tomato.data.instance_id, "shape": "dice"})
	right.perform("add", {"ingredient_id": "egg"}); right.perform("heat")
	kitchen.advance(.8)
	await _capture("dual")
	left.cancel_operation(); right.cancel_operation()
	kitchen.set_dual(false)
	left.perform("plate")
	kitchen.advance(1.8)
	left.input_action("primary", true)
	await _capture("plate")
	var result := left.perform("deliver")
	await _capture("feedback")
	app.toggle_pause()
	await _capture("paused")
	app.toggle_pause()
	var file := FileAccess.open("res://artifacts/full-visual.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"renderer": RenderingServer.get_video_adapter_name(), "captures": captures, "flow": result.ok, "physical_input":"NOT_RUN", "manual_playtest":"PENDING"}, "\t")); file.close()
	app.return_to_menu(); app.queue_free()
	await process_frame
	await process_frame
	print("FULL_VISUAL captures=", captures, " flow=", result.ok)
	quit(0 if result.ok else 1)
