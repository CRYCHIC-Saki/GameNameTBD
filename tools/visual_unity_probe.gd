extends SceneTree
const OUT: String="res://artifacts/visual-unity/visual"
var captures: Array[String]=[]
var walk_samples: Array[Dictionary]=[]
func _initialize() -> void: call_deferred("run")
func capture(label: String) -> void:
	await process_frame;await process_frame
	RenderingServer.force_draw(false)
	if root.get_texture().get_image().save_png(OUT.path_join(label+".png"))!=OK: push_error("Capture failed");quit(1);return
	captures.append(label);print("UNITY_CAPTURE ",label)

func run() -> void:
	root.size=Vector2i(1280,800);DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var app: TDApplication=load("res://src/app/main.tscn").instantiate()
	app.settings_path=OUT.path_join("slot-%d/settings.json"%Time.get_ticks_usec());root.add_child(app)
	var shell:=app.game_shell;shell.automatic_time=false
	if not shell.create_game("slot-01","烟火人家").ok: push_error("Isolated game failed");quit(1);return
	shell.profile.story.beat="done";shell.town.sync_characters(0)
	var town:=shell.town
	for id: String in ["player_diner","market-small","plaza","urban_village"]:
		town.spawn_at_plot(id);await capture(id)
	shell.profile.characters.clock.minute=1320;town.spawn_at_plot("market-small");await capture("night")
	shell.profile.characters.clock.minute=510;town.sync_characters(.01)
	shell.automatic_time=true;shell.kitchen_view.kitchen.auto_advance=true
	for i: int in 32:
		await create_timer(.09).timeout
		for person: Dictionary in town._story_people():
			if person.id=="aling": town._player.position=town._origin()+(Vector2(person.get("position",Vector2(person.cell)))+Vector2(3.5,2.5))*town.CELL
		var gait: TDNpcGait=town._npc_gaits.get("aling")
		walk_samples.append({"index":i,"frame":gait.frame if gait!=null else -1,"position":str(shell.profile.characters.runtime.aling.cell)})
		await capture("walk-%02d"%i)
	shell.automatic_time=false;shell.kitchen_view.kitchen.auto_advance=false;shell.travel("restaurant")
	var room:=shell.restaurant
	room.teleport_player(Vector2i(6,8));await capture("restaurant-floor")
	room.teleport_player(Vector2i(5,4));await capture("restaurant-counter")
	room.teleport_player(Vector2i(room.layout.columns-3,room.layout.rows-3));await capture("restaurant-kitchen-door")
	room._editing=true;await capture("restaurant-overview");room._editing=false
	var file:=FileAccess.open(OUT.path_join("report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"captures":captures,"walk_samples":walk_samples,"renderer":RenderingServer.get_current_rendering_method(),"human_acceptance":"PENDING"},"\t"));file.close()
	var frames: Dictionary={}
	for sample: Dictionary in walk_samples:
		if int(sample.frame)>=0: frames[int(sample.frame)]=true
	if frames.size()<3: push_error("Walking capture did not exercise real moving frames");quit(1);return
	shell.go_title();shell.request_quit()
