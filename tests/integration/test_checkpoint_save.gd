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
	assert_true(shell.create_game("slot-01").ok);shell.guide.dialogue.finish_now()
	shell.profile.story.beat="done"
	shell.profile.residence.stage="door";assert_true(shell.profile.unlock_residence().ok)
	assert_true(shell.save_game().ok)
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
	assert_eq(FileAccess.get_file_as_bytes(path),bytes,"Research and route events cannot save unrelated progress")
	shell.request_title();assert_not_null(shell.profile,"Returning asks before discarding")
	button("确认返回主菜单").pressed.emit()
	assert_eq(FileAccess.get_file_as_bytes(path),bytes)
	assert_true(shell.load_game("slot-01").ok)
	assert_eq(shell.location,"cottage")
	var restored:=shell.profile.snapshot()
	for key: String in ["layout","research","shop","economy","story"]:
		assert_true(TDLevelProgression.same_value(restored[key],baseline[key]),key+" restored together")

func test_explicit_save_keeps_changes_but_quit_alone_never_writes() -> void:
	change_live_progress()
	shell.request_quit();button("保存并退出").pressed.emit()
	assert_true(shell.quit_confirmed)
	var saved:=shell.slots.load_slot("slot-01").data
	assert_has(saved.research.licensed,"C03")
	assert_eq(saved.story.hero_name,"未保存的昵称")
	assert_eq(int(saved.shop.inventory.tomato),1000)
	var path:=shell.slots.path_for("slot-01");var bytes:=FileAccess.get_file_as_bytes(path)
	shell._close_dialog();shell.quit_confirmed=false
	assert_true(shell.profile.buy({"egg":1000}).ok)
	shell.request_quit();button("确认退出").pressed.emit()
	assert_true(shell.quit_confirmed)
	assert_eq(FileAccess.get_file_as_bytes(path),bytes)
	shell.go_title();assert_true(shell.load_game("slot-01").ok)
	assert_eq(int(shell.profile.shop.snapshot().inventory.egg),1000)
	assert_has(shell.profile.research.snapshot().licensed,"C03")

func test_open_close_do_not_checkpoint_but_sleep_saves_the_next_morning() -> void:
	change_live_progress()
	var path:=shell.slots.path_for("slot-01");var bytes:=FileAccess.get_file_as_bytes(path)
	assert_true(shell.start_day().ok)
	assert_true(shell.profile.shop.close_early().ok)
	await wait_process_frames(3)
	assert_eq(FileAccess.get_file_as_bytes(path),bytes,"Opening and ordinary settlement are not saves")
	shell._close_dialog();assert_true(shell.travel("cottage",true).ok)
	shell.show_rest();button("休息到明天").pressed.emit()
	assert_eq(int(shell.profile.shop.snapshot().day),2)
	shell.go_title();assert_true(shell.load_game("slot-01").ok)
	assert_eq(int(shell.profile.shop.snapshot().day),2)
	assert_has(shell.profile.research.snapshot().licensed,"C03")
	assert_eq(shell.location,"cottage")

func test_midnight_safety_save_and_failed_manual_save_keep_consistent_snapshot() -> void:
	change_live_progress()
	var path:=shell.slots.path_for("slot-01");var bytes:=FileAccess.get_file_as_bytes(path)
	shell.profile.persistence=func(_slot: String,_data: Dictionary)->TDOutcome: return TDOutcome.new(false,"INTERRUPTED")
	shell.request_title();button("保存并返回主菜单").pressed.emit()
	assert_not_null(shell.profile,"Failed save cannot exit and discard live progress")
	assert_eq(FileAccess.get_file_as_bytes(path),bytes)
	shell._close_dialog();shell.profile.persistence=shell.slots.save_slot
	shell.profile.characters.clock.minute=1560
	assert_true(shell.finish_night().ok)
	var saved:=shell.slots.load_slot("slot-01").data
	assert_has(saved.research.licensed,"C03")
	assert_eq(saved.shop.phase,"SETTLED")
	assert_eq(saved.story.hero_name,"未保存的昵称")
	assert_eq(shell.profile.save().code,"SAVED")
