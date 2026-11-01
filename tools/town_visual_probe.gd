extends SceneTree
const OUT := "res://artifacts/town-renewal/visual"
var captures: Array[String]=[]
func _initialize() -> void: call_deferred("run")
func capture(label: String) -> void:
	await process_frame;await process_frame
	RenderingServer.force_draw(false)
	var path:=OUT.path_join(label+".png")
	if root.get_texture().get_image().save_png(path)!=OK: push_error("Capture failed");quit(1);return
	captures.append(path);print("TOWN_CAPTURE ",label)
func run() -> void:
	root.size=Vector2i(1280,800)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var app:TDApplication=load("res://src/app/main.tscn").instantiate()
	app.settings_path=OUT.path_join("slot-%d/settings.json"%Time.get_ticks_usec());root.add_child(app)
	var shell:=app.game_shell;shell.automatic_time=false
	if not shell.create_game("slot-01","烟火人家").ok: push_error("Cannot create isolated slot");quit(1);return
	shell.profile.story.beat="done";shell.town.sync_characters(0)
	var map:=shell.profile.world.town_map
	var p:=map._by_id("market-small")
	shell.town._player.position=shell.town._origin()+(Vector2(p.approach_x,p.approach_y)+Vector2(.5,.5))*shell.town.CELL
	for minute: int in [540,720,1080,1320]:
		shell.profile.characters.clock.minute=minute;shell.town._camera.reset_smoothing()
		await capture("town-"+str(minute))
	# Show the full actual authored map from the same scene.
	shell.town.set_process(false);shell.town.set_physics_process(false)
	shell.town._camera.position_smoothing_enabled=false
	shell.town._camera.zoom=Vector2.ONE*.20
	shell.town._camera.position=shell.town._origin()+Vector2.ONE*map.extent*24
	shell.town._player.position=shell.town._camera.position
	shell.profile.characters.clock.minute=720
	await capture("town-overview")
	shell.town.set_process(true);shell.town.set_physics_process(true)
	shell.travel("restaurant");await capture("restaurant-day")
	shell.profile.characters.clock.minute=1320;await capture("restaurant-night")
	shell.travel("kitchen");shell.profile.characters.clock.minute=720;await capture("kitchen-day")
	shell.profile.characters.clock.minute=1320;await capture("kitchen-night")
	var file:=FileAccess.open(OUT.path_join("report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"captures":captures,"renderer":RenderingServer.get_current_rendering_method(),"human_acceptance":"PENDING"},"\t"));file.close()
	shell.go_title();shell.request_quit()
