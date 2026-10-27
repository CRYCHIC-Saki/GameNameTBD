extends SceneTree
var app: TDApplication
var kitchen: TDFullKitchen
var captures: int = 0

func _initialize() -> void: call_deferred("_run")

func capture(id: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var error: Error = root.get_texture().get_image().save_png("res://artifacts/pc-"+id+".png")
	if error != OK: push_error("Capture failed"); quit(1)
	captures += 1

func key(code: Key, pressed: bool = true) -> void:
	var event := InputEventKey.new(); event.physical_keycode=code; event.keycode=code; event.pressed=pressed
	root.push_input(event,true)

func station(id: String) -> void:
	for entry: Dictionary in TDKitchenWorld.STATIONS:
		if entry.id == id:
			(kitchen.world.get_node("Player") as TDKitchenPlayer).position=entry.position+Vector2(0,40); (kitchen.world.get_node("Player") as TDKitchenPlayer).face(Vector2.UP)
	key(KEY_E); key(KEY_E,false)

func _run() -> void:
	app=load("res://src/app/main.tscn").instantiate() as TDApplication
	app.settings_path="res://artifacts/test-storage/pc-visual-settings.json"
	root.add_child(app); app.enter_full_kitchen(); kitchen=app.full_kitchen; kitchen.auto_advance=false
	await capture("world")
	station("kitchen.supply.tomato")
	await capture("carrying")
	station("kitchen.board")
	var prep: TDCookingLane=kitchen.prep
	prep._pc_perform("cut")
	kitchen.advance(float(prep.progress.beat_times_sec[0])); key(KEY_SPACE); key(KEY_SPACE,false)
	await capture("cut")
	key(KEY_D); key(KEY_D,false)
	kitchen.advance(.5); key(KEY_SPACE); key(KEY_SPACE,false); kitchen.advance(.101)
	kitchen._take_and_leave(); station("kitchen.stove.left"); station("kitchen.supply.egg"); station("kitchen.stove.left"); station("kitchen.stove.left")
	var lane: TDCookingLane=kitchen.lanes[0]
	lane.perform("heat"); lane.perform("stir"); kitchen.advance(.1)
	await capture("stir")
	lane.cancel_operation(); lane.perform("heat"); lane.perform("season",{"ingredient_id":"salt","amount":.1})
	await capture("cabinet")
	var times: Array = lane.progress.beat_times_sec.duplicate()
	for index: int in 3:
		kitchen.advance(maxf(0,float(times[index])-float(lane.progress.elapsed_sec)))
		var button := lane._cabinet.get_child(index) as Button
		var point: Vector2 = button.global_position+button.size*.5
		var motion := InputEventMouseMotion.new(); motion.position=point; motion.global_position=point; root.push_input(motion,true)
		for down: bool in [true,false]:
			var click := InputEventMouseButton.new(); click.position=point; click.global_position=point; click.button_index=MOUSE_BUTTON_LEFT; click.pressed=down; root.push_input(click,true)
	var cabinet_ok: bool = lane.qte == null and lane.snapshot().ingredients.size() == 5
	lane.cancel_operation(); lane.perform("plate"); key(KEY_SPACE); kitchen.advance(1); key(KEY_SPACE,false)
	await capture("plated")
	kitchen.close_bench(); station("kitchen.stove.left"); station("kitchen.serve")
	await capture("feedback")
	var delivered: bool = lane.snapshot().state == "delivered"
	kitchen.close_bench(); kitchen.set_dual(true); kitchen.open_bench()
	for item: TDCookingLane in kitchen.lanes:
		item.new_session("tomato_egg"); item.perform("add",{"ingredient_id":"egg"}); item.perform("heat"); item.perform("stir")
	await capture("dual")
	var file := FileAccess.open("res://artifacts/pc-visual.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"captures":captures,"renderer":RenderingServer.get_video_adapter_name(),"delivered":delivered,"cabinet_gui":cabinet_ok,"physical_input":"NOT_RUN","playtest":"PENDING"},"\t")); file.close()
	app.return_to_menu(); app.queue_free(); await process_frame; await process_frame
	await create_timer(.05).timeout
	print("PC_VISUAL captures=",captures," delivered=",delivered," cabinet=",cabinet_ok)
	quit(0 if delivered and cabinet_ok else 1)
