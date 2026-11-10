extends GutTest
var app: TDApplication
func after_each() -> void:
	if is_instance_valid(app): app.game_shell.go_title();app.queue_free();app=null
	get_tree().paused=false
	await wait_process_frames(2)
func test_real_shell_clock_pause_ui_creation_sleep_save_roundtrip() -> void:
	app=load("res://src/app/main.tscn").instantiate()
	app.settings_path="res://artifacts/supplier-lines/isolated-%d/settings.json"%Time.get_ticks_usec()
	add_child(app);await wait_process_frames(3)
	var shell: TDGameShell=app.game_shell;shell.automatic_time=false
	var created:=shell.create_game("slot-01","产线测试");assert_true(created.ok,created.code+":"+created.message)
	if not created.ok: return
	var p:=shell.profile
	shell.guide.dialogue.finish_now();shell.guide.close();get_tree().paused=false;await wait_process_frames(2)
	shell.automatic_time=false;shell.kitchen_view.set_paused(false)
	var panel:=TDManagementPanels.SupplierPanel.new();add_child_autofree(panel);panel.configure(p)
	panel.select_item("tomato");panel.quantity=20;panel.place_order();panel.place_order()
	assert_eq(p.suppliers.state.lines.size(),1);assert_true(p.suppliers.state.orders.is_empty())
	get_tree().paused=true;shell.advance_world_time(100);assert_true(p.suppliers.state.orders.is_empty())
	get_tree().paused=false;shell.advance_world_time(10)
	assert_eq(p.suppliers.state.orders.size(),1);assert_eq(float(p.suppliers.state.orders[0].jobs[0].elapsed),600.0)
	var saved:=p.snapshot();var checked:=TDGameProfile.validate_save(saved);assert_true(checked.ok,checked.code)
	assert_true(shell.save_game().ok)
	var q:=TDGameProfile.new();var restored:=q.restore(saved);assert_true(restored.ok,restored.code)
	assert_eq(q.suppliers.snapshot(),p.suppliers.snapshot());q.close()
	await wait_process_frames(2)
