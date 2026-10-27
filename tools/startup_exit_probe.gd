extends SceneTree
## This driver is injected only into a disposable PCK; production resources stay unchanged.
func _initialize() -> void: call_deferred("run")

func run() -> void:
	var storage:String=""
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--probe-root="): storage=argument.trim_prefix("--probe-root=")
	if not storage.is_absolute_path(): push_error("Isolated --probe-root required");quit(1);return
	root.size=Vector2i(1280,800)
	var app:TDApplication=load("res://src/app/main.tscn").instantiate()
	app.settings_path=storage.path_join("startup-settings.json");root.add_child(app)
	for frame:int in 12: await process_frame
	var shell:=app.game_shell
	if shell.music.context!="casual" or not shell.music.player.playing:
		push_error("Actual title music was not running");quit(1);return
	var exit_button:Button
	for b:Button in shell._title_screen.find_children("*","Button",true,false):
		if b.text=="退出游戏": exit_button=b
	if exit_button==null: push_error("Missing quit button");quit(1);return
	var at:=exit_button.get_global_rect().get_center()
	for down:bool in [true,false]:
		var click:=InputEventMouseButton.new();click.position=at;click.global_position=at;click.button_index=MOUSE_BUTTON_LEFT;click.pressed=down
		root.push_input(click,true)
	if not shell._quitting or shell.music.player.playing:
		push_error("Actual quit action did not stop music");quit(1);return
	print("STARTUP_EXIT success=true checks=4")
	# The real application performs the delayed quit. A missing quit is a process timeout.
