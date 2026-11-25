extends SceneTree
## Test stops and complete walking routes against painted points on the Jiangnan map.
const ACTIONS := {Vector2.LEFT: "world_left", Vector2.RIGHT: "world_right",
	Vector2.UP: "world_up", Vector2.DOWN: "world_down"}
var town: TDTownWorld
var player: TDKitchenPlayer
var view: SubViewport
var camera: Camera2D
var shot_dir := ""
var visits: Array[String] = []
var failures := 0
var checks := 0

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			shot_dir = arg.trim_prefix("--shots=")
			DirAccess.make_dir_recursive_absolute(shot_dir)
	var profile := TDGameProfile.new()
	view = SubViewport.new()
	view.size = Vector2i(840, 460)
	view.world_2d = World2D.new()
	view.disable_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	town = TDTownWorld.new()
	town.player_mode = true
	town.management_menus = true
	town.session = profile.world
	view.add_child(town)
	town.set_process(false)
	town.set_day_minute(720)
	town.place_requested.connect(func(_kind: String, id: String) -> void: visits.append(id))
	for child: Node in town.get_children():
		if child is CanvasLayer:
			child.hide()
	player = town._player
	camera = Camera2D.new()
	town.add_child(camera)
	camera.zoom = Vector2.ONE * .85
	camera.make_current()

	for sample: Array in [
		["fish tubs", Vector2(326,264)], ["fish barrel", Vector2(298,253)],
		["fish crate", Vector2(353,254)], ["cream produce crate", Vector2(345,237)],
		["yellow counter legs", Vector2(427,277)], ["greens basket", Vector2(382,257)],
		["barrel by yellow stall", Vector2(411,271)], ["mill at Chen's shop",Vector2(216,361)],
		["quay produce counter", Vector2(330,730)], ["quay basket", Vector2(415,714)],
		["quay barrel", Vector2(346,729)], ["quay lamp foot", Vector2(286.5,722)]]:
		check(not town._can_stand(world_at(sample[1])), sample[0]+" has a solid base")

	await walk_path("behind fish awning", [Vector2(295,228), Vector2(333,228)])
	await walk_path("behind yellow awning", [Vector2(488,239), Vector2(432,239)])
	await walk_path("between cream counter and loose greens", [Vector2(365,247), Vector2(398,247)])
	await walk_path("around both sides of greens", [Vector2(364,247), Vector2(364,282),
		Vector2(399,282), Vector2(399,247)])
	await walk_path("fresh market apron", [Vector2(285,286), Vector2(402,286), Vector2(490,286)])
	await walk_path("waterfront promenade", [Vector2(225,746), Vector2(320,746), Vector2(411,746)])

	await stop_at("side of fish barrel", Vector2(281,253), Vector2.RIGHT, Vector2(293,253))
	await stop_at("front of fish tubs", Vector2(326,284), Vector2.UP, Vector2(326,267))
	interact("market-mid")
	await screenshot("fish", Vector2(374,247))
	await stop_at("front of loose greens", Vector2(382,277), Vector2.UP, Vector2(382,262))
	await screenshot("greens", Vector2(386,248))
	await stop_at("yellow produce counter", Vector2(427,294), Vector2.UP, Vector2(427,280))
	await stop_at("Chen's counter", Vector2(251.5,377), Vector2.UP, Vector2(251.5,360))
	interact("market-small")
	await stop_at("quay counter", Vector2(249,739), Vector2.UP, Vector2(249,718))
	interact("market-large")
	await screenshot("quay", Vector2(288,716))
	print("MARKET CONTACT ", checks, " checks, ", failures, " failures")
	profile.close()
	quit(1 if failures else 0)

func world_at(point: Vector2) -> Vector2:
	return town._origin() + point * town.cell_size() / TDPlannedTown.REFERENCE_PIXELS_PER_CELL

func map_at(point: Vector2) -> Vector2:
	return (point - town._origin()) * TDPlannedTown.REFERENCE_PIXELS_PER_CELL / town.cell_size()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", label)
	else:
		print("PASS ", label)

func walk_path(label: String, route: Array[Vector2]) -> void:
	player.position = world_at(route[0])
	check(town._can_stand(player.position), label+" starts on clear ground")
	Input.action_press("world_sprint")
	for i: int in range(1, route.size()):
		var delta := route[i] - route[i-1]
		var action: String = ACTIONS[delta.normalized().round()]
		var goal := world_at(route[i])
		Input.action_press(action)
		for tick: int in 160:
			if (goal - player.position).dot(delta.normalized()) <= 3.0:
				break
			await physics_frame
		Input.action_release(action)
		check(goal.distance_to(player.position) < 9.0, label+" reaches "+str(route[i])+" at "+str(map_at(player.position)))
	Input.action_release("world_sprint")

func stop_at(label: String, start: Vector2, direction: Vector2, expected: Vector2) -> void:
	player.position = world_at(start)
	check(town._can_stand(player.position), label+" approach is clear")
	var action: String = ACTIONS[direction]
	Input.action_press(action)
	Input.action_press("world_sprint")
	for tick: int in 40:
		await physics_frame
	Input.action_release(action)
	Input.action_release("world_sprint")
	var stopped := map_at(player.position)
	check(stopped.distance_to(expected) < 2.4 and stopped.distance_to(start) > 5, label+" stops at "+str(stopped))
	check(town._can_stand(player.position) and not town._can_stand(player.position+direction*7), label+" cannot cross")

func interact(id: String) -> void:
	visits.clear()
	var press := InputEventAction.new()
	press.action = "world_interact"
	press.pressed = true
	town._unhandled_input(press)
	check(visits == [id], "E at the counter opens "+id+" (received "+str(visits)+")")

func screenshot(label: String, center: Vector2) -> void:
	if shot_dir.is_empty(): return
	camera.position = world_at(center)
	camera.force_update_scroll()
	player.reset_physics_interpolation()
	await process_frame
	await RenderingServer.frame_post_draw
	view.get_texture().get_image().save_png(shot_dir.path_join(label+".png"))
