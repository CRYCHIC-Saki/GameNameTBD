extends SceneTree
const OUT := "res://artifacts/town-polish/visual"
var captures: Array[String]=[]
func _initialize() -> void: call_deferred("run")
func capture(label: String) -> void:
	await process_frame;await process_frame
	RenderingServer.force_draw(false)
	if root.get_texture().get_image().save_png(OUT.path_join(label+".png"))!=OK: push_error("Capture failed");quit(1);return
	captures.append(label);print("POLISH_CAPTURE ",label)
func run() -> void:
	root.size=Vector2i(1280,800)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var app: TDApplication=load("res://src/app/main.tscn").instantiate()
	app.settings_path=OUT.path_join("slot-%d/settings.json"%Time.get_ticks_usec());root.add_child(app)
	var shell:=app.game_shell;shell.automatic_time=false
	if not shell.create_game("slot-01","烟火人家").ok: push_error("Cannot create isolated slot");quit(1);return
	shell.profile.story.beat="done";shell.town.sync_characters(0)
	var town:=shell.town;var people:=shell.profile.characters
	for id: String in ["market-small","player_diner","plaza","landmark"]:
		town.spawn_at_plot(id);town._camera.reset_smoothing();await capture(id)
	people.clock.minute=760;town.sync_characters(60)
	town._player.position=town._origin()+(Vector2(people.runtime.aling.cell)+Vector2(.5,.5))*town.CELL
	await capture("npc-lunch-activity")
	town.spawn_at_plot("market-small");people.clock.minute=1320;await capture("market-night")
	town.set_process(false);town.set_physics_process(false);town._camera.zoom=Vector2.ONE*.20
	town._camera.position=town._origin()+Vector2.ONE*shell.profile.world.town_map.extent*24
	town._player.position=town._camera.position;people.clock.minute=720;await capture("overview")
	var f:=FileAccess.open(OUT.path_join("report.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify({"captures":captures,"renderer":RenderingServer.get_current_rendering_method(),"human_acceptance":"PENDING"},"\t"));f.close()
	shell.go_title();shell.request_quit()
