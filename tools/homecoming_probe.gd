extends SceneTree
const OUT: String="res://artifacts/homecoming/gpu"
var records: Array=[]

func _initialize() -> void: call_deferred("run")

func capture(name: String) -> void:
	await process_frame;await RenderingServer.frame_post_draw
	var picture:=root.get_texture().get_image()
	var code:=picture.save_png(OUT.path_join(name+".png"))
	records.append({"frame":name,"save_exit":code})
	if code!=OK: quit(1)

func run() -> void:
	root.size=Vector2i(1280,800)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var view:=TDCutsceneView.new();view.size=Vector2(1280,800);root.add_child(view)
	for shot: String in ["soup_stall","black_soup","intervene","ledger","uncover","supplies","tasting","certificate","sign"]:
		for at: float in [.1,.5,.9]:
			view.show_shot(shot,at*6,6,true);await capture(shot+"-"+str(int(at*10)))
	for at: float in [1.2,3.5,6.0]:
		view.show_shot("messenger",at,10,true);await capture("ledger-arrival-"+str(int(at*10)))
	view.queue_free();await process_frame
	var dialogue:=TDDialogueView.new();root.add_child(dialogue)
	for mood: String in ["calm","puzzled","sad","angry"]:
		var talk:=TDDialogue.new();talk.story_layout("赤焰","aling")
		talk.add_line("阿铃","aling","夜鸦的密令，已经记下了。",mood)
		dialogue.present(talk);dialogue.set_process(false);talk.tick(10);dialogue._refresh()
		await capture("cover-"+mood);dialogue.finish_now()
	dialogue.queue_free();await process_frame
	var app:=load("res://src/app/main.tscn").instantiate() as TDApplication
	app.settings_path=OUT.path_join("isolated-%d/settings.json"%Time.get_ticks_usec());root.add_child(app)
	var shell:=app.game_shell;shell.automatic_time=false
	if not shell.create_game("slot-01").ok: quit(1);return
	shell.guide.dialogue.finish_now();shell.profile.story.beat="founded";shell.profile.story.setup_seen=true
	shell.profile.shop.open_day();shell.profile.shop.close_early();shell.guide._process(0)
	shell.guide.dialogue.talk.tick(50);shell.guide.dialogue._refresh();await capture("home-invitation")
	shell.guide.dialogue.talk.skip();shell.guide.dialogue._emit_if_finished()
	for step: int in 400:
		if shell.profile.residence.stage!="following": break
		shell.town._tick_escort(.5);shell.town._player.position=shell.town.escort_position()-Vector2(60,0)
		shell.town._follow_camera();shell.town.sync_characters(0)
		if step==20: await capture("home-follow")
	if shell.profile.residence.stage!="door": printerr("Home route failed");quit(1);return
	await capture("home-arrival")
	shell._place("cottage","player_cottage");shell.guide.dialogue.talk.tick(50);shell.guide.dialogue._refresh();await capture("home-key")
	shell.guide.dialogue.talk.skip();shell.guide.dialogue._emit_if_finished();await capture("cottage-bed")
	shell.cottage.player.position=TDCottageWorld.DOOR-Vector2(0,55);await capture("cottage-door")
	shell.go_title();shell.show_slots(false);await capture("load-delete")
	shell._confirm_delete_slot("slot-01");await capture("delete-confirm")
	shell._close_dialog();app.queue_free();await process_frame
	var file:=FileAccess.open(OUT.path_join("manifest.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"renderer":RenderingServer.get_current_rendering_method(),"captures":records,"human_playtest":"PENDING"},"\t"));file.close()
	print("HOMECOMING_GPU frames=",records.size());quit(0)
