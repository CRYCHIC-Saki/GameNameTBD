extends SceneTree
const OUT := "res://artifacts/story-kitchen/visual"
var captures: Array[String]=[]

func _initialize() -> void: call_deferred("run")

func capture(label: String) -> void:
	await process_frame;await process_frame
	RenderingServer.force_draw(false)
	var path:=OUT.path_join(label+".png")
	if root.get_texture().get_image().save_png(path)!=OK: push_error("Capture failed");quit(1);return
	captures.append(path);print("STORY_CAPTURE ",label)

func run() -> void:
	root.size=Vector2i(1280,800)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var app:TDApplication=load("res://src/app/main.tscn").instantiate()
	app.settings_path=OUT.path_join("slot-%d/settings.json"%Time.get_ticks_usec());root.add_child(app)
	var shell:=app.game_shell;shell.automatic_time=false
	if not shell.create_game("slot-01","试做食堂").ok: push_error("Cannot create isolated slot");quit(1);return
	for who:String in ["aling","chen"]:
		shell.profile.story.beat="soup" if who=="chen" else "arrive"
		var person:Dictionary=shell.town._story_people().filter(func(p:Dictionary)->bool:return p.id==who)[0]
		shell.town._player.position=shell.town._origin()+(Vector2(person.cell)+Vector2(.5,1.5))*TDTownWorld.CELL
		shell.town._player.face(Vector2.UP)
		await capture(who+"-town")
		shell.profile.story.beat="cook"
		var lines:=shell.profile.story.talk(who,"试做食堂",false,100)
		shell.town._open_talk(lines);lines.click()
		await capture(who+"-dialogue")
		shell.town._dismiss_talk()
	var f:=FileAccess.open(OUT.path_join("report.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify({"captures":captures,"renderer":RenderingServer.get_current_rendering_method(),"human_acceptance":"PENDING"},"\t"));f.close()
	shell.go_title();shell.request_quit()
