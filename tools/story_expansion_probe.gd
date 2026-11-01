extends SceneTree
const OUT := "res://artifacts/story-expansion/visual"
var app: TDApplication
var shell: TDGameShell
var captures: Array=[]
func _initialize() -> void: call_deferred("run")
func capture(label: String) -> void:
	await process_frame;await process_frame
	if paused and shell._modal!=null and not label.begins_with("journal") and not label.begins_with("lesson"): shell._close_dialog();await process_frame
	RenderingServer.force_draw(false)
	var path:=OUT.path_join(label+".png")
	if root.get_texture().get_image().save_png(path)!=OK: push_error("Capture failed");quit(1);return
	captures.append(path);print("CAPTURE ",label)
func run() -> void:
	root.size=Vector2i(1280,800);DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	app=load("res://src/app/main.tscn").instantiate();app.settings_path=OUT.path_join("slot-%d/settings.json"%Time.get_ticks_usec());root.add_child(app)
	shell=app.game_shell;shell.automatic_time=false
	if not shell.create_game("slot-01","赤焰之手").ok: quit(1);return
	shell.guide.dialogue.finish_now() # This legacy probe covers later chapter beats.
	await capture("town-quest")
	shell.guide.show_journal();await capture("journal");shell._close_dialog()
	shell.town._player.position=shell.town._origin()+Vector2(70.5,33.5)*shell.town.CELL;shell.town._follow_camera()
	await capture("harbor");shell.town._interact();await capture("journal-harbor");shell._close_dialog();shell.town.spawn_at_home()
	for who: String in ["hero","aling","chen"]:
		for mood: String in TDStoryArt.EMOTIONS:
			var talk:=TDDialogue.new();talk.story_layout("赤焰之手",who if who!="hero" else "aling");talk.context={"kind":"preview"}
			talk.add_line({"hero":"赤焰之手","aling":"阿铃","chen":"老陈"}[who],who,"表情与动作 · "+mood,mood)
			shell.guide.show_talk(talk);talk.click();await capture("portrait-"+who+"-"+mood);shell.guide.dialogue.finish_now()
	var scenes: Dictionary=TDOpeningScript.data().scenes
	var done: Dictionary={}
	for sequence: Array in scenes.values():
		for row: Dictionary in sequence:
			if row.kind!="cg" or done.has(row.cg): continue
			done[row.cg]=true
			var talk:=TDDialogue.new();talk.story_layout("赤焰之手","aling");talk.context={"kind":"preview"};talk.add_cg(row.cg,row.text,3.5)
			shell.guide.show_talk(talk);talk.click();talk.cg_elapsed=.2;await capture("cg-"+str(row.cg)+"-a")
			talk.cg_elapsed=3.1;await capture("cg-"+str(row.cg)+"-b");shell.guide.dialogue.finish_now()
	shell.profile.story.beat="follow";shell.town._tick_escort(.01);shell.town._player.position=shell.town.escort_position()+Vector2(340,0);shell.town._tick_escort(.1)
	await capture("escort-wait")
	shell.profile.story.beat="awaken";shell._apply_story(shell.profile.story.complete_scene("awaken"));shell.travel("kitchen");shell.profile.story.recipe_viewed=true
	await capture("kitchen-guide")
	for module: String in TDStoryGuide.LESSONS:
		shell.guide._pending_tutorial=module;shell.guide.show_lesson(module);await capture("lesson-"+module);shell.guide._pending_tutorial="";shell._close_dialog()
	var driver:=preload("res://tools/test_support/kitchen_input.gd").new();driver.viewport=root;driver.kitchen=shell.kitchen_view.kitchen
	shell.kitchen_view.pick_ingredient("tomato");driver.station("kitchen.board");shell.kitchen_view.choose_cut("chunk")
	shell.kitchen_view.kitchen.advance(10);await process_frame;await capture("lesson-M1-real-stage")
	shell._close_dialog();shell.profile.story.tutorials.append("M1");shell.guide._pending_tutorial=""
	shell.guide.say_bark("hero","happy","赤焰流 · 断界！",10);await capture("cooking-bark")
	var f:=FileAccess.open(OUT.path_join("report.json"),FileAccess.WRITE);f.store_string(JSON.stringify({"captures":captures,"renderer":RenderingServer.get_current_rendering_method(),"human":"PENDING"},"\t"));f.close()
	shell.go_title();shell.request_quit()
