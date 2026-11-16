extends SceneTree
const OUT:="res://artifacts/vn-triggers-20261116/runtime"
var checks:Array[Dictionary]=[]
func _initialize() -> void: run.call_deferred()
func expect(value:bool,label:String) -> void:
	checks.append({"name":label,"pass":value})
	if not value:printerr("TRIGGER_RUNTIME_FAIL "+label)
func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT));root.size=Vector2i(1280,800)
	var app:TDApplication=load("res://src/app/main.tscn").instantiate();app.settings_path=OUT+"/%d/settings.json"%Time.get_ticks_usec();root.add_child(app)
	var shell:=app.game_shell;shell.automatic_time=false
	expect(shell.create_game("slot-01","演出检查").ok,"real new isolated slot")
	shell.guide.dialogue.finish_now();shell.guide.set_process(false)
	shell.profile.story.beat="done";shell.profile.story.completed_scenes=["intro"]
	shell.profile.residence.stage="door";shell.profile.unlock_residence()
	expect(shell.travel("restaurant").ok,"real restaurant entry")
	shell.guide._process(0);await process_frame;await process_frame
	expect(shell.guide.presenting(),"registered location starts native playback")
	var stage:=shell.guide.dialogue._vn_stage
	expect(stage.runner.current_text=="这段演出由进入餐厅触发。","registered file is source authority")
	expect(shell.guide.dialogue._chapter.text=="餐厅触发示例","authored title replaces port title")
	expect(stage.main.host_managed and VNEngineMain.save_data().memory_only,"no independent VN save")
	stage.dialog._reveal_to_end();await create_timer(.5).timeout;RenderingServer.force_draw(true)
	expect(root.get_texture().get_image().save_png(OUT+"/native-event.png")==OK,"native game screenshot")
	var frozen:=shell.profile.characters.clock.minute;shell._on_active_time(5)
	expect(shell.profile.characters.clock.minute==frozen,"story freezes shared game time")
	shell.guide.dialogue.finish_now();expect(shell.profile.story_events.counts.is_empty(),"cancel does not complete")
	shell.travel("town");shell.guide._process(0);shell.travel("restaurant");shell.guide._process(0)
	await process_frame;await process_frame
	expect(shell.guide.presenting(),"leave and reenter retries cancelled event")
	for _i:int in 8:
		if not shell.guide.presenting():break
		shell.guide.dialogue._vn_stage.dialog._advance_dialog();await process_frame
	await process_frame;await process_frame
	expect(not shell.guide.presenting(),"normal end returns gameplay")
	expect("jp" in shell.profile.research.snapshot().cuisines,"actual cuisine reward")
	expect(shell.profile.story_events.counts.size()==1,"completion recorded once")
	expect(shell.slots.load_slot("slot-01").data.story_events.counts.is_empty(),"ordinary completion not autosave")
	expect(shell.save_game().ok,"explicit save succeeds")
	expect(shell.load_game("slot-01").ok,"reload same slot")
	shell.guide.set_process(false);shell.travel("restaurant");shell.guide._process(0)
	expect(not shell.guide.presenting(),"saved one-time event does not replay")
	shell.go_title();app.queue_free();await process_frame;await process_frame
	expect(VNEngineMain.instance()==null,"runtime lifecycle cleaned")
	var failures:=0
	for item:Dictionary in checks:
		if not item.pass:failures+=1
	var report:=FileAccess.open(OUT+"/report.json",FileAccess.WRITE);report.store_string(JSON.stringify({"count":checks.size(),"failures":failures,"checks":checks},"\t"));report.close()
	print("VN_TRIGGER_RUNTIME checks=%d failures=%d"%[checks.size(),failures]);quit(1 if failures else 0)
