extends SceneTree
## Actual renderer and real UI/input, always using an isolated slot directory.
const OUT := "res://artifacts/story-fixes/gpu"
const DRIVER = preload("res://tools/test_support/kitchen_input.gd")
var captures: Array[String]=[]
var failed: bool=false

func _initialize() -> void:
	call_deferred("run")

func capture(label: String) -> void:
	await process_frame;await RenderingServer.frame_post_draw
	var result:=root.get_texture().get_image().save_png(OUT.path_join(label+".png"))
	if result!=OK: failed=true
	captures.append(label)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.size=Vector2i(1280,800)
	var app:=load("res://src/app/main.tscn").instantiate() as TDApplication
	app.settings_path=OUT.path_join("slots/%d/settings.json"%Time.get_ticks_usec())
	root.add_child(app);var shell:=app.game_shell;shell.automatic_time=false
	if not shell.create_game("slot-01").ok: quit(2);return
	var view:=shell.guide.dialogue;view.set_process(false)
	var talk:=view.talk
	talk.skip_cg();view._refresh();await capture("01-unknown-name")
	for n: int in 30:
		if talk.action=="enter_name": break
		if talk.display_kind=="cg":
			if talk.cg_id=="messenger":
				talk.cg_elapsed=5.4;view._refresh();await capture("02-book-opening")
				talk.cg_elapsed=5.9;view._refresh();await capture("03-book-written")
			talk.skip_cg()
		else: talk.shown=talk.body.length();talk.click()
	view._refresh();await capture("04-my-name")
	view._hero_input.text="小满";view._confirm_hero_name();talk.shown=talk.body.length();view._refresh()
	await capture("05-chosen-name")
	talk.skip();view._emit_if_finished()
	shell.profile.story.beat="follow";var town:=shell.town
	town._tick_escort(0);town.set_process(false)
	var gate: Dictionary={}
	for tick: int in 2000:
		town._player.position=town.escort_position()+Vector2(0,65)
		town._tick_escort(.1);town.sync_characters(0);town._follow_camera()
		if town._escort.y in [34,33,32,31,30] and town._escort.x==64 and not gate.has(town._escort.y):
			gate[town._escort.y]=true;await capture("06-gate-y%d"%town._escort.y)
		if shell.profile.story.beat!="follow": break
	if shell.profile.story.beat!="soup": failed=true
	town._player.position=town.chen_door_point()+Vector2(0,26);town.sync_characters(0);town._follow_camera()
	await capture("07-chen-door")
	town._interact();await capture("08-chen-story")
	shell.guide.dialogue.finish_now();shell.profile.story.beat="bowl";town._interact();await capture("09-indoor-soup")
	shell._close_dialog();shell.profile.story.beat="awaken";shell._apply_story(shell.profile.story.complete_scene("awaken"))
	shell.profile.story.tutorials.assign(["M1","M2","M3","M4","M5","M6","M7"])
	shell.travel("restaurant");await process_frame;await capture("10-restaurant-scale")
	# Generic diners and named actors share the increased visual height.
	var iso:=shell.restaurant._iso
	iso.actors=[{"position":shell.restaurant.player_position()+Vector2(160,160),"gone":false,"seated":false,"label":"食客","shirt":Color("497f92"),"character_id":"","appearance_id":1,"facing":Vector2i.DOWN,"frame":-1},
		{"position":shell.restaurant.player_position()+Vector2(-96,0),"gone":false,"seated":false,"label":"老陈","shirt":Color("82719c"),"character_id":"chen","appearance_id":0,"facing":Vector2i.DOWN,"frame":-1}]
	shell.restaurant.set_process(false);iso.queue_redraw();await capture("11-restaurant-actors")
	shell.travel("kitchen")
	var kitchen_view:=shell.kitchen_view;var kitchen:=kitchen_view.kitchen
	kitchen_view._show_pantry();await capture("12-practice-fridge");kitchen_view._close_popup()
	var driver:=DRIVER.new();driver.kitchen=kitchen;driver.viewport=root
	for lane: TDCookingLane in kitchen.lanes+[kitchen.prep]: lane.beat_offset_sec=0
	kitchen_view.pick_ingredient("tomato");driver.station("kitchen.stove.left");driver.station("kitchen.stove.left",KEY_F)
	await capture("13-missing-egg")
	# Take it out and follow the actual preparation/cooking/delivery interfaces.
	var food_id: String=str(kitchen.lanes[0].snapshot().ingredients.keys()[0])
	kitchen_view.take_pot_ingredient(0,food_id);driver.station("kitchen.board");kitchen_view.choose_cut("chunk")
	driver.play(12);driver.station("kitchen.board");driver.station("kitchen.stove.left")
	kitchen_view.pick_ingredient("egg");driver.station("kitchen.stove.left");driver.station("kitchen.stove.left",KEY_F)
	driver.play(70);driver.station("kitchen.stove.left");driver.station("kitchen.serve")
	await process_frame;await capture("14-served-feedback")
	if shell.profile.story.beat!="verdict": failed=true
	var record: Dictionary={"captures":captures,"renderer":RenderingServer.get_current_rendering_method(),"served":shell.profile.story.beat=="verdict","score":shell.profile.story.score,"human_playtest":"PENDING","status":"FAIL" if failed else "PASS"}
	shell.go_title();app.queue_free();await process_frame;await process_frame
	var file:=FileAccess.open(OUT.path_join("summary.json"),FileAccess.WRITE);file.store_string(JSON.stringify(record,"\t"));file.close()
	print(JSON.stringify(record));quit(1 if failed else 0)
