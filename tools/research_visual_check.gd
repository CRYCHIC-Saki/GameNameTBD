extends SceneTree
const DRIVER=preload("res://tools/test_support/research_input.gd")
var app:TDApplication
var captures:int=0
func _initialize() -> void: call_deferred("run")
func capture(id:String) -> void:
	await process_frame;await RenderingServer.frame_post_draw
	var result:=root.get_texture().get_image().save_png("res://artifacts/research-"+id+".png")
	if result!=OK: push_error("RESEARCH_CAPTURE_FAILED");quit(1)
	captures+=1
func run() -> void:
	root.size=Vector2i(1280,800);DirAccess.make_dir_recursive_absolute("res://artifacts/test-storage")
	app=load("res://src/app/main.tscn").instantiate();app.research_save_path="res://artifacts/test-storage/research-visual-%d.json"%Time.get_ticks_usec();app.settings_path=app.research_save_path+".settings";app.shop_save_path=app.research_save_path+".shop";root.add_child(app)
	await capture("menu");app.enter_research();await capture("atlas")
	app.atlas.select_recipe("C09");app.atlas.reveal_selection();await capture("C09-border")
	app.atlas.select_recipe("C10");await capture("C10-border")
	app.atlas.select_recipe("C11");app.atlas.reveal_selection();await capture("C11-prerequisites")
	app.atlas.select_recipe("C16");app.atlas.reveal_selection();await capture("C16-prerequisites")
	app.atlas.set_zoom(.7);app.atlas._tree_scroll.scroll_vertical=110;await capture("tree-overview")
	app.atlas.set_zoom(1.0)
	app.atlas.switch_cuisine("jp");await capture("story-locked")
	app.atlas.select_recipe("C03");app.atlas.reveal_selection();await capture("study-ready");app.atlas.start_selected();app.atlas.trial.automated_clock=true
	var sent:Dictionary={};var token:String=app.atlas.trial.token;var got_perfect:bool=false
	for i:int in 10000:
		if app.research.progress().get("ready_to_finish",false): break
		DRIVER.tick(app.research,token,sent,root)
		var lane:=app.research.controller.active_lane()
		if not got_perfect and not lane.judgement_feedback.is_empty():
			got_perfect=true;await capture("perfect");app.toggle_pause();await capture("paused");app.toggle_pause()
	await capture("result")
	app.atlas.trial._continue.pressed.emit();app.enter_shop();await capture("unlocked-menu")
	DRIVER.key(root,KEY_B,true);DRIVER.key(root,KEY_B,false);await capture("in-game-book")
	app.atlas.select_recipe("C04");app.atlas.start_selected();app.atlas.trial.automated_clock=true;app.research.advance(5);await capture("seasoning-study")
	app.research.advance(200);await capture("failed-retry")
	app.atlas.trial._retry_attempt.pressed.emit();app.atlas.trial.automated_clock=true;await capture("immediate-retry")
	app.return_to_menu();app.queue_free();await process_frame;await process_frame
	print("RESEARCH_VISUAL captures=%d exit=0; physical input/audio playtest=PENDING"%captures);quit(0)
