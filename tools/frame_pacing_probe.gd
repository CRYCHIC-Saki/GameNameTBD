extends SceneTree
## The same player inputs and 60 Hz simulation on each build, timed with a wall clock.
const WARMUP := 40
const FRAMES := 180
var shell: TDGameShell
var out := "user://frame-pacing"

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): out = arg.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(out)
	var app := load("res://src/app/main.tscn").instantiate() as TDApplication
	app.settings_path = out.path_join("session-%d/settings.json" % Time.get_ticks_usec())
	root.add_child(app)
	await process_frame
	shell = app.game_shell
	if not shell.create_game("slot-01", "帧耗时测试").ok: quit(1); return
	shell.guide.dialogue.finish_now()
	shell.profile.story.beat = "done"
	if OS.get_cmdline_user_args().has("--stocked"):
		shell.profile.world.supply.stock = {"tomato":4,"salt":3,"egg":2}
	shell.travel("town")
	shell.kitchen_view.kitchen.auto_advance = false
	shell.town.spawn_at_harbor()
	print("ADAPTER ", RenderingServer.get_video_adapter_name(), " VIEWPORT ", root.size)
	await sample("jiangnan")
	for town: String in ["tokyo","paris","chengdu"]:
		if shell.visiting == null: shell.town.spawn_at_harbor()
		else: shell.visiting.player.position = (Vector2(TDTravelCatalog.port(shell.visiting_town))+Vector2.ONE*.5)*shell.visiting.cell_size
		if not shell.voyage(town).ok: quit(2); return
		if town != "chengdu": await sample(town)
	if not shell.travel("restaurant").ok: quit(3); return
	await sample("restaurant")
	if not shell.travel("kitchen").ok: quit(4); return
	await sample("kitchen")
	if OS.get_cmdline_user_args().has("--service"):
		if not await sample_service(): quit(5); return
	shell.travel("town")
	shell._open_management("challenge")
	shell._challenge.selection.get_child(0).pressed.emit()
	await sample("challenge")
	print("FRAME_PACING_COMPLETE")
	quit(0)

func sample_service() -> bool:
	if not shell.travel("restaurant").ok: return false
	var shop := shell.profile.shop
	var meal := "service.tomato_egg"
	for id: String in shop.snapshot().menu:
		if not shop.set_menu(id,id == meal,1300).ok: return false
	if not shop.buy(shop.offer(meal).stock,"frame-pacing-service").ok: return false
	if not shop.open_day().ok: return false
	for step: int in 180:
		shell.kitchen_view.kitchen.advance(1)
		if not shop.active_orders().is_empty():
			print("SERVICE active=",shop.active_orders().size())
			await sample("restaurant_open")
			return true
	return false

func sample(scene: String) -> void:
	var intervals := PackedFloat64Array()
	var calls := PackedFloat64Array()
	var directions := ["world_right","world_left","world_down","world_up"]
	var last := Time.get_ticks_usec()
	for i: int in WARMUP+FRAMES:
		if scene != "challenge":
			if i % 18 == 0:
				for direction: String in directions: Input.action_release(direction)
				Input.action_press(directions[floori(i/18.0) % directions.size()])
			shell.kitchen_view.kitchen.advance(1.0/60.0)
		elif i % 19 == 0:
			var dir := Vector2i.LEFT if i % 2 else Vector2i.RIGHT
			shell._challenge._move(dir)
		await process_frame
		var now := Time.get_ticks_usec()
		if i >= WARMUP:
			intervals.append((now-last)/1000.0)
			calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		last = now
	for direction: String in directions: Input.action_release(direction)
	intervals.sort()
	calls.sort()
	print("FRAME ", scene, " ", JSON.stringify({"n":FRAMES,"median_ms":intervals[FRAMES/2],"p95_ms":intervals[ceili(FRAMES*.95)-1],"draw_calls":calls[FRAMES/2]}))
