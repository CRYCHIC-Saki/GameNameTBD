extends SceneTree
var app: TDApplication
var shell: TDGameShell
var captures: int=0
func _initialize() -> void: call_deferred("run")
func capture(id: String) -> void:
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var result:=root.get_texture().get_image().save_png("res://artifacts/game-"+id+".png")
	if result!=OK: push_error("GAME_CAPTURE_FAILED");quit(1)
	captures+=1
func run() -> void:
	root.size=Vector2i(1280,800)
	app=load("res://src/app/main.tscn").instantiate()
	app.settings_path="res://artifacts/game-visual/%d/settings.json"%Time.get_ticks_usec()
	root.add_child(app);shell=app.game_shell;shell.automatic_time=false
	await capture("title")
	shell.create_game("slot-01","杏花食堂");await capture("town")
	shell.show_market();await capture("market");shell._close_dialog()
	shell.travel("restaurant");await capture("restaurant")
	shell.show_menu();await capture("menu");shell._close_dialog()
	shell.profile.buy({"tomato":3000,"egg":3000,"oil":1000,"salt":1000,"sugar":1000,"starch":1000})
	shell.start_day();shell.kitchen_view.kitchen.advance(100);await capture("guests")
	shell.travel("kitchen");await capture("kitchen")
	shell.show_pause();await capture("pause");shell._close_dialog()
	shell.open_atlas();await capture("atlas");shell.close_atlas()
	shell.go_title();shell.show_slots(false);await capture("slots");shell._close_dialog()
	shell.show_settings();await capture("settings");shell._close_dialog()
	shell.show_console();shell._console.text_submitted.emit("debug");await capture("console")
	shell.go_title();app.queue_free();await process_frame;await process_frame
	print("GAME_VISUAL captures=%d exit=0; human_playtest=PENDING"%captures);quit(0)
