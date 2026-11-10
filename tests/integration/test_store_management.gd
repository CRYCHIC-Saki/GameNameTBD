extends GutTest
var profiles: Array[TDGameProfile]=[]
var app: TDApplication
func make_profile() -> TDGameProfile:
	var p:=TDGameProfile.new();profiles.append(p);p.slot_id="slot-01";assert_true(p.error.ok,p.error.code)
	p.shop.world_adjustment(300000,"test-funds","fixture")
	return p
func own(p: TDGameProfile,id: String,store: String="") -> void:
	p.employees.state.owned[id]={"id":id,"copies":1,"xp":0,"assigned":""}
	if not store.is_empty(): assert_true(p.employees.assign(id,store).ok)
func open_branch(p: TDGameProfile) -> String:
	own(p,"manager.host")
	var result:=p.branches.open_store("chengdu",[6,48,3,4],"cn","manager.host","test-branch");assert_true(result.ok,result.code)
	return str(result.data.store_id)
func after_each() -> void:
	if is_instance_valid(app): app.game_shell.go_title();app.queue_free();app=null
	get_tree().paused=false
	for p: TDGameProfile in profiles: p.close()
	profiles.clear();await wait_process_frames(2)
func test_main_bulk_menu_is_atomic_readonly_snapshot_and_accepts_settled_boundary() -> void:
	var p:=make_profile();var rows:=p.main_menu_rows();assert_gte(rows.size(),2)
	var id: String=rows[0].id;var other: String=rows[1].id
	var before:=p.snapshot();rows[0].price_cents=1;assert_eq(p.snapshot(),before)
	for invalid: Array in [[{"id":id,"price_cents":1234},{"id":"missing","price_cents":500}],[{"id":id,"price_cents":1234},{"id":id,"price_cents":1500}],[{"id":id,"price_cents":0}],[{"id":id,"price_cents":INF}],[7],[]]:
		assert_false(p.shop.configure_menu(invalid).ok);assert_eq(p.snapshot(),before)
	assert_true(p.shop.configure_menu([{"id":id,"price_cents":1234}]).ok)
	assert_eq(int(p.shop.snapshot().menu[id].price_cents),1234);assert_false(p.shop.snapshot().menu[other].enabled)
	assert_true(p.shop.close_for_night().ok)
	assert_true(p.shop.configure_menu([{"id":other,"price_cents":2345}]).ok)
	assert_eq(int(p.shop.snapshot().menu[other].price_cents),2345)
func test_main_menu_rejects_locked_recipe_and_open_changes() -> void:
	var p:=make_profile();var before:=p.snapshot()
	var locked: String=""
	for entry: Dictionary in p.service.config.offers:
		if not p.shop.is_unlocked(p.shop.family_id(entry.id)): locked=entry.id;break
	assert_ne(locked,"");assert_false(p.shop.configure_menu([{"id":locked,"price_cents":100}]).ok);assert_eq(p.snapshot(),before)
	assert_true(p.shop.open_day().ok);before=p.snapshot()
	assert_false(p.shop.configure_menu([{"id":p.main_menu_rows()[0].id,"price_cents":100}]).ok)
	assert_false(p.set_main_management(true).ok);assert_eq(p.snapshot(),before)
func test_manager_required_then_auto_uses_idle_owned_people_without_spending() -> void:
	var p:=make_profile();var branch:=open_branch(p)
	own(p,"cook-he",branch);own(p,"cook-zhou");own(p,"waiter-ning")
	var before:=p.snapshot();assert_eq(p.set_main_management(true).code,"MANAGER_REQUIRED");assert_eq(p.snapshot(),before)
	own(p,"manager.steady","player_diner")
	var money: int=int(p.shop.snapshot().money_cents);var orders:=p.suppliers.snapshot();var owned_count:=p.employees.roster_count()
	assert_true(p.set_main_management(true).ok);assert_true(p.main_management_auto)
	assert_eq(p.employees.employee_info("cook-he").assigned,branch)
	assert_eq(p.employees.employee_info("cook-zhou").assigned,"player_diner")
	assert_eq(p.employees.employee_info("waiter-ning").assigned,"player_diner")
	assert_eq(int(p.shop.snapshot().money_cents),money);assert_eq(p.suppliers.snapshot(),orders);assert_eq(p.employees.roster_count(),owned_count)
	assert_lte(p.main_menu_rows().filter(func(row:Dictionary)->bool:return row.enabled).size(),3)
	assert_false(p.branches.state.stores.has("player_diner"))
	before=p.snapshot();p.prepare_management();assert_eq(p.employees.snapshot(),before.employees,"same-day prepare cannot add wages")
func test_auto_disable_preserves_config_and_missing_manager_stops_configuration() -> void:
	var p:=make_profile();own(p,"manager.steady","player_diner");own(p,"cook-he");own(p,"waiter-ning")
	assert_true(p.set_main_management(true).ok)
	var menu: Dictionary=p.shop.snapshot().menu;var people:=p.employees.snapshot()
	assert_true(p.set_main_management(false).ok);assert_eq(p.shop.snapshot().menu,menu);assert_eq(p.employees.snapshot(),people)
	var id: String=p.main_menu_rows()[0].id
	assert_true(p.shop.configure_menu([{"id":id,"price_cents":1234}]).ok);p.prepare_management();assert_eq(int(p.shop.snapshot().menu[id].price_cents),1234)
	assert_true(p.set_main_management(true).ok);assert_true(p.employees.assign("manager.steady","").ok)
	assert_true(p.shop.configure_menu([{"id":id,"price_cents":2345}]).ok);menu=p.shop.snapshot().menu;p.prepare_management();assert_eq(p.shop.snapshot().menu,menu)
func test_settled_enable_applies_next_prepare_and_keeps_salary_day_boundary() -> void:
	var p:=make_profile();own(p,"manager.steady");own(p,"cook-he");own(p,"waiter-ning")
	assert_true(p.shop.close_for_night().ok);assert_true(p.employees.assign("manager.steady","player_diner").ok)
	var before: Dictionary=p.shop.snapshot().menu;assert_true(p.set_main_management(true).ok)
	assert_eq(p.shop.snapshot().menu,before);assert_true(p.employees.assigned("player_diner","cook").is_empty())
	assert_eq(int(p.employees.payroll_for("player_diner",1).total_cents),0)
	assert_true(p.next_day().ok);assert_eq(p.employees.assigned("player_diner","cook").size(),1)
	assert_gt(int(p.employees.payroll_for("player_diner",2).total_cents),0)
func test_main_management_slot_roundtrip_old_default_invalid_and_no_implicit_save() -> void:
	var p:=make_profile();var disk:=TDProfileStore.new("res://artifacts/store-management/slots/%d"%Time.get_ticks_usec(),TDGameProfile.validate_save);p.persistence=disk.save_slot
	own(p,"manager.steady","player_diner");assert_true(p.save().ok)
	assert_true(p.set_main_management(true).ok)
	assert_false(disk.load_slot("slot-01").data.main_management_auto)
	assert_true(p.save().ok);var raw: Dictionary=disk.load_slot("slot-01").data
	var q:=make_profile();assert_true(q.restore(raw).ok);assert_true(q.main_management_auto)
	assert_eq(q.shop.snapshot().menu,p.shop.snapshot().menu)
	raw.erase("main_management_auto");assert_true(q.restore(raw).ok);assert_false(q.main_management_auto)
	var before:=q.snapshot();raw.main_management_auto="true";assert_false(q.restore(raw).ok);assert_eq(q.snapshot(),before)
func make_ui() -> TDBranchPanel:
	app=load("res://src/app/main.tscn").instantiate();app.settings_path="res://artifacts/store-management/ui/%d/settings.json"%Time.get_ticks_usec();add_child(app)
	await wait_process_frames(2)
	app.game_shell.automatic_time=false;assert_true(app.game_shell.create_game("slot-01","店铺测试").ok)
	app.game_shell.guide.close();get_tree().paused=false
	app.game_shell.profile.shop.world_adjustment(300000,"fixture","fixture")
	app.game_shell.show_branch()
	return app.game_shell._modal_box.get_child(-1) as TDBranchPanel
func test_real_list_includes_home_branches_and_detail_navigation_is_read_only() -> void:
	var panel:=await make_ui();var p:=panel.profile;var branch:=open_branch(p);panel.list_stores()
	var before:=p.snapshot();assert_eq(panel.store_buttons.size(),2);assert_true(panel.store_buttons.has("player_diner"));assert_true(panel.store_buttons.has(branch))
	assert_eq(app.game_shell._hud.button_for("branches").caption,"店铺")
	for id: String in ["player_diner",branch,"player_diner"]:
		panel.store_buttons[id].pressed.emit();assert_eq(panel.selected_id,id)
		for tab: String in ["menu","staff","management","books"]:
			panel.select_tab(tab);assert_eq(panel.current_tab,tab)
		panel.list_stores()
	assert_eq(p.snapshot(),before)
func test_main_detail_applies_menu_assigns_manager_and_enables_management() -> void:
	var panel:=await make_ui();var p:=panel.profile
	own(p,"manager.steady");own(p,"cook-he");own(p,"waiter-ning")
	panel.manage("player_diner");var id: String=panel.menu_rows.keys()[0]
	panel.menu_rows[id].price.value=12.34;panel.apply_menu()
	assert_eq(int(p.shop.snapshot().menu[id].price_cents),1234)
	panel.select_tab("staff");panel.assign_employee("manager.steady","player_diner")
	assert_eq(p.employees.manager_for("player_diner").id,"manager.steady")
	panel.select_tab("management");panel.set_management(true)
	assert_true(p.main_management_auto);assert_eq(p.employees.assigned("player_diner","cook").size(),1)
	panel.select_tab("menu");assert_true(panel.menu_rows[id].check.disabled,"turn management off before manual menu editing")
func test_branch_detail_uses_own_menu_budget_and_shared_employee_warehouse() -> void:
	var panel:=await make_ui();var p:=panel.profile;var branch:=open_branch(p);own(p,"cook-he")
	var home_menu: Dictionary=p.shop.snapshot().menu
	panel.manage(branch);var id: String=panel.menu_rows.keys()[0]
	panel.menu_rows[id].check.button_pressed=true;panel.menu_rows[id].price.value=15.75;panel.budget_input.value=88;panel.apply_menu()
	assert_eq(int(p.branches.state.stores[branch].budget_cents),8800)
	assert_eq(p.shop.snapshot().menu,home_menu)
	panel.select_tab("staff");panel.assign_employee("cook-he",branch)
	assert_eq(p.employees.employee_info("cook-he").assigned,branch)
	panel.list_stores();assert_eq(panel.store_buttons.size(),2)
