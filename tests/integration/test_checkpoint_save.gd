extends GutTest

# Only intercept process shutdown; all UI/profile/storage paths remain real.
class QuitProbe extends TDGameShell:
	var quit_confirmed: bool=false
	func _finish_quit() -> void: quit_confirmed=true

var shell: QuitProbe

func before_each() -> void:
	shell=QuitProbe.new()
	var base: String="res://artifacts/d059/save-tests/%d"%Time.get_ticks_usec()
	shell.profile_root=base+"/profiles";shell.preferences_path=base+"/settings.json"
	shell.automatic_time=false;add_child_autofree(shell)
	assert_true(shell.create_game("slot-01","小镇食堂",false).ok);shell.guide.dialogue.finish_now()
	shell.profile.story.beat="done"
	shell.profile.residence.stage="door";assert_true(shell.profile.unlock_residence().ok)
	assert_true(shell.profile.save().ok) # Seed a legacy snapshot for rollback tests.
	await wait_process_frames(2)

func after_each() -> void:
	shell.go_title();get_tree().paused=false
	await wait_process_frames(2)

func button(label: String) -> Button:
	for node: Button in shell._modal_box.find_children("*","Button",true,false):
		if node.text==label: return node
	return null

func change_live_progress() -> void:
	assert_true(shell.restaurant.layout.set_surface_finish("carpet").ok)
	assert_true(shell.profile.buy({"tomato":1000,"egg":1000}).ok)
	assert_true(shell.profile.research.begin("C03").ok)
	shell.profile.research.cancel(str(shell.profile.research._active.token))
	assert_true(shell.profile.research.calibrate(.05).ok)
	assert_true(shell.profile.recommend_route("tokyo","test-route").ok)
	shell.profile.story.hero_name="未保存的昵称"

func test_return_without_save_rolls_back_all_domains_to_one_checkpoint() -> void:
	var baseline:=shell.slots.load_slot("slot-01").data
	var path:=shell.slots.path_for("slot-01");var bytes:=FileAccess.get_file_as_bytes(path)
	change_live_progress()
	shell.advance_world_time(180)
	assert_eq(shell.profile.characters.clock.minute, 660.0)
	assert_eq(FileAccess.get_file_as_bytes(path),bytes,"Research and route events cannot save unrelated progress")
	shell.request_title();assert_not_null(shell.profile,"Returning asks before discarding")
	button("确认返回主菜单").pressed.emit()
	assert_eq(FileAccess.get_file_as_bytes(path),bytes)
	assert_true(shell.load_game("slot-01").ok)
	assert_eq(shell.location,"town","The legacy slot resumes at the revised opening")
	assert_eq(shell.profile.characters.clock.minute, 480.0)
	var restored:=shell.profile.snapshot()
	for key: String in ["layout","research","shop","economy"]:
		assert_true(TDLevelProgression.same_value(restored[key],baseline[key]),key+" restored together")
	assert_eq(shell.profile.story.revised.cursor,0)

func test_quit_offer_cannot_write_and_returns_to_morning() -> void:
	var path := shell.slots.path_for("slot-01")
	var bytes := FileAccess.get_file_as_bytes(path)
	change_live_progress()
	shell.advance_world_time(240)
	assert_eq(shell.profile.characters.clock.minute, 720.0)
	shell.request_quit()
	assert_null(button("保存并退出"))
	button("确认退出").pressed.emit()
	assert_true(shell.quit_confirmed)
	assert_eq(FileAccess.get_file_as_bytes(path),bytes)
	shell.go_title();assert_true(shell.load_game("slot-01").ok)
	assert_eq(shell.profile.characters.clock.minute, 480.0)
	assert_eq(int(shell.profile.shop.snapshot().inventory.egg),0)
	assert_false(shell.profile.research.snapshot().licensed.has("C03"))

func test_open_close_do_not_checkpoint_but_sleep_saves_the_next_morning() -> void:
	change_live_progress()
	var path:=shell.slots.path_for("slot-01");var bytes:=FileAccess.get_file_as_bytes(path)
	assert_true(shell.start_day().ok)
	var start_xp := int(shell.profile.progression.progress().total_xp)
	assert_true(shell.profile.shop.close_early().ok)
	await wait_process_frames(3)
	assert_eq(FileAccess.get_file_as_bytes(path),bytes,"Opening and ordinary settlement are not saves")
	assert_eq(shell.slots.load_slot("slot-01",TDProfileStore.DAILY).code,"NOT_FOUND")
	assert_eq(int(shell.profile.progression.progress().total_xp),start_xp)
	assert_eq(shell.save_game().code,"AUTO_SAVE_ONLY")
	shell.profile.use_revised_mainline()
	shell._close_dialog();assert_true(shell.travel("cottage",true).ok)
	shell.show_rest();button("休息到明天").pressed.emit()
	assert_eq(int(shell.profile.shop.snapshot().day),2)
	assert_true(shell.slots.load_slot("slot-01",TDProfileStore.DAILY).ok)
	shell.go_title();assert_true(shell.load_game("slot-01").ok)
	assert_eq(int(shell.profile.shop.snapshot().day),2)
	assert_has(shell.profile.research.snapshot().licensed,"C03")
	assert_eq(shell.location,"cottage")

func test_midnight_waits_for_sleep_and_failed_write_retries_same_morning() -> void:
	change_live_progress()
	var path:=shell.slots.path_for("slot-01");var bytes:=FileAccess.get_file_as_bytes(path)
	shell.profile.characters.clock.minute=1560
	assert_true(shell.finish_night().ok)
	assert_eq(FileAccess.get_file_as_bytes(path),bytes,"02:00 is not a checkpoint")
	shell.slots.interrupt_at="after_temp"
	shell.show_rest();button("休息到明天").pressed.emit()
	assert_eq(FileAccess.get_file_as_bytes(path),bytes)
	assert_eq(shell.profile.characters.clock.day,2)
	var levels := shell.profile.progression.snapshot()
	assert_true(get_tree().paused)
	shell.slots.interrupt_at=""
	button("重试保存").pressed.emit()
	var saved:=shell.slots.load_slot("slot-01",TDProfileStore.DAILY).data
	assert_eq(shell.profile.progression.snapshot(),levels,"Retry only writes, without awarding experience again")
	assert_has(saved.research.licensed,"C03")
	assert_eq(saved.shop.phase,"PREPARE")
	assert_eq(saved.story.hero_name,"未保存的昵称")
	assert_eq(int(saved.shop.day),2)
	assert_eq(float(saved.characters.clock.minute),480.0)

func test_legacy_preparation_save_loads_at_morning_without_rewriting_file() -> void:
	shell.profile.characters.clock.minute = 710.0
	assert_true(shell.profile.save().ok)
	var path := shell.slots.path_for("slot-01")
	var bytes := FileAccess.get_file_as_bytes(path)
	shell.go_title()
	assert_true(shell.load_game("slot-01").ok)
	assert_eq(shell.profile.characters.clock.minute, 480.0)
	assert_eq(FileAccess.get_file_as_bytes(path), bytes)

func test_story_checkpoint_and_hotel_checkpoint_are_independent() -> void:
	var boundaries := [1,4,7,12,17,20,22,25]
	for cursor: int in range(27):
		assert_eq(TDRevisedMainline.finished_chapter({"cursor":cursor}),boundaries.filter(func(end: int)->bool: return end<=cursor).size())
	shell.go_title()
	assert_true(shell.create_game("slot-02","临海食堂").ok)
	assert_eq(shell.slots.load_slot("slot-02").code,"NOT_FOUND")
	var view := shell.guide.dialogue
	for frame: int in range(120):
		if not shell.guide.presenting(): break
		if view._vn_stage.runner != null:
			view._vn_stage.dialog._reveal_to_end()
			view._vn_stage.dialog._advance_dialog()
		await get_tree().process_frame
		await get_tree().process_frame
	await wait_process_frames(3)
	var story := shell.slots.load_slot("slot-02",TDProfileStore.STORY)
	assert_true(story.ok,story.code)
	if not story.ok: return
	assert_eq(int(story.data.story.revised.cursor),1)
	var story_path := shell.slots.path_for("slot-02",TDProfileStore.STORY)
	var bytes := FileAccess.get_file_as_bytes(story_path)
	shell._offer_rest("旅馆","chengdu")
	var rest := button("支付 ¥6.00 并休息")
	assert_not_null(rest)
	if rest==null: return
	rest.pressed.emit()
	var daily := shell.slots.load_slot("slot-02",TDProfileStore.DAILY)
	assert_true(daily.ok,daily.code)
	assert_eq(int(daily.data.shop.day),2)
	assert_eq(daily.data.rest_town,"chengdu")
	assert_eq(FileAccess.get_file_as_bytes(story_path),bytes)
	assert_eq(shell.slots.load_slot("slot-02").data.checkpoint,TDProfileStore.DAILY)
	assert_true(shell.load_game("slot-02",TDProfileStore.STORY).ok)
	assert_eq(shell.profile.characters.clock.day,1)
	assert_true(shell.load_game("slot-02",TDProfileStore.DAILY).ok)
	assert_eq(shell.profile.characters.clock.day,2)
	assert_eq(shell.location,"town")
