extends SceneTree
const OUT := "res://artifacts/characters/visual"
var captures: Array[String]=[]

func _initialize() -> void: call_deferred("run")

func capture(label: String) -> void:
	await process_frame;await process_frame
	RenderingServer.force_draw(false)
	var path:=OUT.path_join(label+".png")
	if root.get_texture().get_image().save_png(path)!=OK: push_error("Capture failed");quit(1);return
	captures.append(path);print("CHARACTERS_CAPTURE ",label)

func run() -> void:
	root.size=Vector2i(1280,800)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var app:TDApplication=load("res://src/app/main.tscn").instantiate()
	app.settings_path=OUT.path_join("slot-%d/settings.json"%Time.get_ticks_usec());root.add_child(app)
	var shell:=app.game_shell;shell.automatic_time=false
	if not shell.create_game("slot-01","灶间烟火").ok: push_error("Cannot create isolated slot");quit(1);return
	var story:=shell.profile.story
	story.beat="follow"
	var talk:=story.talk("chen","灶间烟火",false,100)
	shell.town._open_talk(talk)
	while talk.active_side!="right" and not talk.finished and not talk.choices_open: talk.click()
	talk.click()
	await capture("story-chen-active")
	talk.skip();shell.town._talk_view._choose("refuse");talk.click()
	await capture("story-hero-active")
	shell.town._dismiss_talk()
	story.beat="done";shell.town.sync_characters(1)
	talk=shell.profile.characters.conversation("aling");shell.town._open_talk(talk);talk.click()
	await capture("everyday-aling")
	shell.town._dismiss_talk();shell.travel("kitchen")
	await capture("kitchen-clock")
	shell.profile.characters.clock.minute=1560
	var closed:=shell.finish_night()
	if not closed.ok: push_error("Night closure: "+closed.code);quit(1);return
	await capture("night-cottage")
	var file:=FileAccess.open(OUT.path_join("report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"captures":captures,"renderer":RenderingServer.get_current_rendering_method(),"human_acceptance":"PENDING"},"\t"));file.close()
	shell.go_title();shell.request_quit()
