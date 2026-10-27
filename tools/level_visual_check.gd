extends SceneTree
## Isolated GPU probe with real shop days and real GUI input. Not human playtesting.
var failures: Array[String]=[]
var captures: int=0
var shell: TDGameShell
var driver: RefCounted
var focus_pauses: int=0

func _initialize() -> void: call_deferred("run")

func capture(label: String) -> void:
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	# Native focus loss correctly opens the pause menu. Resume it for a deterministic
	# visual capture; the automatic upgrade opening is asserted before yielding below.
	if paused:
		focus_pauses+=1;shell._close_dialog()
		if label=="ledger": driver.tap(KEY_E)
		else: shell.show_levels()
		await process_frame;await process_frame;await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png("res://artifacts/level-"+label+".png")!=OK: failures.append("capture:"+label)
	captures+=1

func run() -> void:
	root.size=Vector2i(1280,800)
	var app:TDApplication=load("res://src/app/main.tscn").instantiate()
	app.settings_path="res://artifacts/level-visual/%d/settings.json"%Time.get_ticks_usec()
	root.add_child(app)
	shell=app.game_shell;shell.automatic_time=false
	var started:=shell.create_game("slot-01","街角烟火")
	if not started.ok: push_error(started.code);quit(1);return
	shell.travel("restaurant")
	driver=load("res://tools/test_support/kitchen_input.gd").new();driver.viewport=root
	var point:Dictionary=shell.restaurant.interaction_points().filter(func(item:Dictionary)->bool:return item.action=="ledger")[0]
	shell.restaurant.teleport_player(Vector2i(point.cell));driver.tap(KEY_E)
	await capture("ledger")
	var buttons:=shell._modal_box.find_children("*","Button",true,false).filter(func(node:Button)->bool:return node.text.begins_with("经营等级"))
	if buttons.is_empty(): failures.append("missing-level-entry")
	else: driver.click(buttons[0].get_global_rect().get_center())
	await capture("new-game")
	if shell._modal_box.find_child("LevelRewardsView",true,false)==null: failures.append("real-click-did-not-open")
	shell._close_dialog()
	for day: int in range(1,9):
		if not shell.start_day().ok: failures.append("open-day");break
		shell._process(0);shell.profile.shop.advance(360)
		for order:Dictionary in shell.profile.shop.active_orders(): shell.profile.shop.cancel_order(order.id)
		shell.profile.shop.advance(1000);shell._process(0)
		if shell.profile.progression.progress().level>=2: break
		if not shell.profile.next_day().ok: failures.append("next-day");break
		shell._process(0)
	if shell.profile.progression.progress().level!=2: failures.append("missing-upgrade")
	if shell._modal_box.find_child("LevelRewardsView",true,false)==null: failures.append("automatic-upgrade-page-not-open")
	await capture("upgrade")
	var points:=int(shell.profile.research.snapshot().points)
	var bar:ProgressBar=shell._modal_box.find_child("LevelExperienceBar",true,false)
	if bar==null: failures.append("upgrade-page-not-open")
	var scroll:ScrollContainer=shell._modal_box.get_parent()
	scroll.ensure_control_visible(shell._modal_box.find_child("LevelReward5",true,false))
	await capture("rewards")
	scroll.scroll_vertical=0
	root.size=Vector2i(1024,640);await capture("small-window")
	driver.tap(KEY_ESCAPE)
	if shell._modal!=null: failures.append("escape")
	shell.go_title()
	await process_frame;await process_frame
	if not shell.load_game("slot-01").ok: failures.append("reload")
	await process_frame;await process_frame
	if int(shell.profile.research.snapshot().points)!=points or shell.profile.progression.progress().level!=2: failures.append("reward-roundtrip")
	root.size=Vector2i(1280,800);shell.show_levels();await capture("reloaded")
	shell.go_title();app.queue_free();await process_frame;await process_frame
	print(JSON.stringify({"probe":"level-progression","captures":captures,"focus_pauses_resumed":focus_pauses,"failures":failures,"success":failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)
