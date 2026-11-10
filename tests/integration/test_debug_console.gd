extends GutTest
var app: TDApplication
var shell: TDGameShell
func start(active: bool=true) -> void:
	app=load("res://src/app/main.tscn").instantiate();app.settings_path="res://artifacts/console/tests/%d/settings.json"%Time.get_ticks_usec();add_child(app)
	await wait_process_frames(2);shell=app.game_shell;shell.automatic_time=false
	if active:
		assert_true(shell.create_game("slot-01","控制台测试").ok);shell.guide.close();get_tree().paused=false
func after_each() -> void:
	if is_instance_valid(app): shell.go_title();app.queue_free();app=null
	get_tree().paused=false;await wait_process_frames(2)
func command(value: String) -> String: return shell.execute_command(value)
func key(code: Key) -> void:
	var event:=InputEventKey.new();event.physical_keycode=code;event.keycode=code;event.pressed=true;Input.parse_input_event(event);await wait_process_frames(1)
	event=InputEventKey.new();event.physical_keycode=code;event.keycode=code;Input.parse_input_event(event);await wait_process_frames(1)
func test_parser_quotes_decimal_units_and_bad_numbers() -> void:
	var parsed:=TDDebugCommands.tokenize(" give  \"番茄\"\t1.125 main ")
	assert_true(parsed.ok);assert_eq(Array(parsed.data.words),["give","番茄","1.125","main"])
	assert_false(TDDebugCommands.tokenize("give 'tomato").ok);assert_false(TDDebugCommands.tokenize("x".repeat(513)).ok)
	assert_eq(TDDebugCommands.scaled("12.34",2,0,100000).data.value,1234)
	assert_eq(TDDebugCommands.scaled("-0.01",2,-1000,1000).data.value,-1)
	assert_eq(TDDebugCommands.scaled("1.125",3,1,100000).data.value,1125)
	for raw: String in ["nan","inf","1e3","12.345","0x10","--1","99999999999999999999"]: assert_false(TDDebugCommands.scaled(raw,2,0,100000).ok,raw)
func test_debug_gate_no_slot_help_and_unknown() -> void:
	await start(false)
	assert_true(command("help").contains("money"));assert_eq(command("san 10"),"请先输入 debug。")
	command("debug");assert_true(shell.debug_enabled);assert_true(command("give tomato 10").contains("没有活动存档"))
	assert_true(command("nonsense").contains("未知命令"));command("debug off");assert_false(shell.debug_enabled)
func test_money_stock_inspiration_only_memory_and_roundtrip() -> void:
	await start();var p:=shell.profile;var disk:=FileAccess.get_file_as_bytes(shell.slots.path_for("slot-01"));command("debug")
	var before: int=int(p.shop.snapshot().money_cents)
	assert_true(command("money add 123.45").contains("成功"));assert_eq(int(p.shop.snapshot().money_cents),before+12345)
	assert_true(command("money add -0.05").contains("成功"));assert_eq(int(p.shop.snapshot().money_cents),before+12340)
	var stock: int=int(p.shop.snapshot().inventory.tomato)
	assert_true(command("give tomato 1.125").contains("成功"));assert_eq(int(p.shop.snapshot().inventory.tomato),stock+1125)
	var points: int=int(p.research.snapshot().points);assert_true(command("inspiration add 50").contains("成功"));assert_eq(int(p.research.snapshot().points),points+50)
	assert_eq(FileAccess.get_file_as_bytes(shell.slots.path_for("slot-01")),disk)
	assert_true(TDGameProfile.validate_save(p.snapshot()).ok);assert_eq(int(p.commerce.cash_audit(int(p.shop.snapshot().money_cents)).difference_cents),0)
	assert_true(command("save").contains("成功"));assert_ne(FileAccess.get_file_as_bytes(shell.slots.path_for("slot-01")),disk)
	shell.go_title();assert_false(shell.debug_enabled);assert_true(shell.load_game("slot-01").ok)
	assert_eq(int(shell.profile.shop.snapshot().inventory.tomato),stock+1125)
func test_invalid_commands_leave_full_profile_unchanged() -> void:
	await start();command("debug");var before:=shell.profile.snapshot()
	for raw: String in ["money add 1e9","money add -999999","money add 1.001","money add 5 extra","give nope 1","give tomato -1","give tomato 0","give tomato 1001","give tomato 1 wrong-shop","give tomato \"1","inspiration add -1","inspiration add 10001","recipe unlock MISSING","cuisine open bad","time set 02:00","time set 26:00","time set 07:59","san 101","shop auto main maybe","employee assign unknown main"]:
		assert_false(command(raw).contains("成功"),raw);assert_eq(shell.profile.snapshot(),before,raw)
func test_recipe_debug_unlock_has_explicit_provenance_no_fake_score_and_rejects_corruption() -> void:
	await start();command("debug");var p:=shell.profile
	assert_true(command("recipe unlock C09").contains("成功"));var data:=p.research.snapshot()
	assert_true(data.unlocked.has("C09"));assert_true(data.events.has("debug:recipe:C09"));assert_false(data.best.has("C09"));assert_eq(int(data.completed_attempts),0);assert_false(data.grandfathered.has("C09"))
	for id: String in p.research.catalog.node("C09").prerequisites: assert_true(data.unlocked.has(id))
	assert_true(TDGameProfile.validate_save(p.snapshot()).ok)
	var restored:=TDGameProfile.new();assert_true(restored.restore(p.snapshot()).ok);assert_true(restored.research.has("C09"));restored.close()
	var previous:=p.snapshot();command("recipe unlock C09");assert_eq(p.snapshot(),previous)
	data.events["debug:recipe:C09"].recipe="C08";assert_false(p.research.validate_save(data).ok)
	data=p.research.snapshot();data.events.erase("debug:recipe:C09");assert_false(p.research.validate_save(data).ok)
	assert_true(command("cuisine open jp").contains("成功"));assert_true(p.research.snapshot().cuisines.has("jp"))
func test_clock_preview_no_simulation_or_write_and_rejects_open_day() -> void:
	await start();command("debug");var p:=shell.profile;var stock: Dictionary=p.shop.snapshot().inventory;var disk:=FileAccess.get_file_as_bytes(shell.slots.path_for("slot-01"))
	assert_true(command("time set 18:00").contains("18:00"));assert_eq(p.characters.clock.minute,1080.0)
	assert_true(command("time set 00:30").contains("00:30"));assert_eq(p.characters.clock.minute,1470.0)
	assert_eq(int(p.shop.snapshot().day),1);assert_eq(p.shop.snapshot().inventory,stock);assert_eq(FileAccess.get_file_as_bytes(shell.slots.path_for("slot-01")),disk)
	assert_true(p.shop.open_day().ok);var before:=p.snapshot()
	for raw: String in ["time set 18:00","money add 50","give tomato 1","recipe unlock C05"]: assert_true(command(raw).contains("营业中"));assert_eq(p.snapshot(),before)
func test_employee_real_hiring_assignment_automation_and_cash_integrity() -> void:
	await start();command("debug");var p:=shell.profile;command("money add 10000")
	var row: Dictionary=p.employees.market_rows("chengdu","manager")[0];var money: int=int(p.shop.snapshot().money_cents)
	assert_true(command("employee market chengdu manager").contains(row.id))
	assert_true(command("employee hire "+row.id).contains("成功"));assert_eq(int(p.shop.snapshot().money_cents),money-int(row.sign_fee_cents));assert_true(p.employees.state.contracts.has(row.id))
	var before:=p.snapshot();assert_false(command("employee hire "+row.id).contains("成功"));assert_eq(p.snapshot(),before)
	assert_true(command("employee assign %s main"%row.id).contains("成功"));assert_true(command("shop auto main on").contains("成功"));assert_true(p.main_management_auto)
	assert_true(command("employee owned").contains(row.id));assert_true(command("employee assign %s idle"%row.id).contains("成功"))
	assert_eq(int(p.commerce.cash_audit(int(p.shop.snapshot().money_cents)).difference_cents),0);assert_true(TDGameProfile.validate_save(p.snapshot()).ok)
func test_branch_supply_is_isolated_and_preserves_save_contract() -> void:
	await start();command("debug");var p:=shell.profile;command("money add 10000")
	var row: Dictionary=p.employees.market_rows("chengdu","manager")[0];command("employee hire "+row.id)
	var result:=p.branches.open_store("chengdu",[6,48,3,4],"cn",row.id,"console-test-branch");assert_true(result.ok)
	var id: String=result.data.store_id;var before: Dictionary=p.shop.snapshot().inventory
	assert_true(command("give tomato 2.5 "+id).contains("成功"));assert_eq(int(p.branches.state.stores[id].inventory.tomato),2500);assert_eq(p.shop.snapshot().inventory,before)
	assert_true(command("shop list").contains(id));assert_true(command("stock "+id).contains("2.500"));assert_true(TDGameProfile.validate_save(p.snapshot()).ok)
func test_query_commands_and_task_tracking_do_not_finish_story() -> void:
	await start();command("debug");var p:=shell.profile;var before:=p.snapshot()
	for raw: String in ["status","check","items tomato","stock main","recipes C03","time","orders","supply","quest","employee owned","shop list","shop info main"]: assert_ne(command(raw),"",raw);assert_eq(p.snapshot(),before,raw)
	var beat: String=p.story.beat;command("quest track off");assert_false(p.story.tracked);assert_eq(p.story.beat,beat);command("quest track on");assert_true(p.story.tracked)
func test_actual_console_history_completion_clear_pause_and_input_isolation() -> void:
	await start();shell.show_console();assert_true(get_tree().paused)
	shell._console.text="debug";await key(KEY_ENTER);assert_true(shell.debug_enabled);assert_same(get_viewport().gui_get_focus_owner(),shell._console)
	shell._console.text="money add 10";await key(KEY_ENTER);assert_eq(shell._command_history.size(),2)
	shell._console.text="draft";await key(KEY_UP);assert_eq(shell._console.text,"money add 10",str(shell._command_history)+" cursor="+str(shell._history_cursor));await key(KEY_DOWN);assert_eq(shell._console.text,"draft")
	shell._console.text="stat";await key(KEY_TAB);assert_eq(shell._console.text,"status")
	await key(KEY_ENTER);assert_true(shell._console_output.text.contains("slot-01"))
	shell._console.text="clear";await key(KEY_ENTER);assert_false(shell._console_output.text.contains("money add"))
	var minute: float=shell.profile.characters.clock.minute;shell.kitchen_view.kitchen.advance(20);assert_eq(shell.profile.characters.clock.minute,minute)
	await key(KEY_ESCAPE);assert_null(shell._console);assert_false(get_tree().paused)
	assert_true(shell.profile.shop.open_day().ok)
	shell.show_console();shell._console.text="tools";await key(KEY_ENTER);assert_null(shell._console);assert_not_null(shell._modal)
func test_completion_queries_and_clock_san_do_not_mutate_templates() -> void:
	await start();command("debug");var p:=shell.profile;var definitions:=p.service.cooking.data();var before:=p.snapshot()
	assert_true(TDDebugCommands.complete("give toma",p).has("give tomato "));assert_true(TDDebugCommands.complete("open sh",p).has("open shops"));assert_eq(p.snapshot(),before)
	assert_true(command("san 10").contains("SAN = 10"));assert_eq(p.world.san,10);assert_eq(p.service.cooking.data(),definitions)
	shell.kitchen_view.kitchen.stage.show();before=p.snapshot();assert_true(command("money add 1").contains("QTE"));assert_eq(p.snapshot(),before);shell.kitchen_view.kitchen.stage.hide()
