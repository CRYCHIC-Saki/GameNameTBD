extends SceneTree
const OUT := "res://artifacts/residential/visual"
var captures: Array[String]=[]
func _initialize() -> void: call_deferred("run")
func capture(label: String) -> void:
	await process_frame;await process_frame
	RenderingServer.force_draw(false)
	if root.get_texture().get_image().save_png(OUT.path_join(label+".png"))!=OK: push_error("Capture failed");quit(1);return
	captures.append(label);print("RESIDENTIAL_CAPTURE ",label)
func run() -> void:
	root.size=Vector2i(1280,800)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var app:TDApplication=load("res://src/app/main.tscn").instantiate()
	app.settings_path=OUT.path_join("slot-%d/settings.json"%Time.get_ticks_usec());root.add_child(app)
	var shell:=app.game_shell;shell.automatic_time=false
	if not shell.create_game("slot-01","烟火人家").ok: push_error("Cannot create isolated slot");quit(1);return
	shell.profile.story.beat="done";shell.town.sync_characters(0)
	var town:=shell.town
	town._player.position=town._origin()+Vector2(12,14.5)*town.CELL
	shell.profile.characters.clock.minute=660;await capture("neighbourhood-day")
	shell.profile.characters.clock.minute=1320;await capture("neighbourhood-night")
	shell.profile.characters.clock.minute=660;town._player.position=town._origin()+Vector2(8.5,21.5)*town.CELL;await capture("courtyard")
	var driver:=preload("res://tools/test_support/kitchen_input.gd").new();driver.viewport=root;driver.tap(KEY_E)
	if shell._modal_box==null: push_error("Real E did not open neighbourhood notice");quit(1);return
	await capture("notice");shell._close_dialog()
	town.spawn_at_plot("player_cottage");await capture("own-cottage")
	var f:=FileAccess.open(OUT.path_join("report.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify({"captures":captures,"renderer":RenderingServer.get_current_rendering_method(),"human_acceptance":"PENDING"},"\t"));f.close()
	shell.go_title();shell.request_quit()
