extends GutTest
var profiles: Array[TDGameProfile]=[]
var app: TDApplication

func make_profile() -> TDGameProfile:
	var p:=TDGameProfile.new();profiles.append(p);p.slot_id="slot-01"
	assert_true(p.error.ok,p.error.code)
	p.shop.world_adjustment(500000,"test-funds","fixture")
	return p

func own(p: TDGameProfile, id: String, copies: int=1) -> void:
	p.employees.state.owned[id]={"id":id,"copies":copies,"xp":0,"assigned":""}

func ready_branch(p: TDGameProfile) -> String:
	own(p,"manager.steady");own(p,"cook-he");own(p,"waiter-ning")
	var result:=p.branches.open_store("chengdu",[6,48,3,4],"cn","manager.steady","test-open")
	assert_true(result.ok,result.code)
	return str(result.data.get("store_id",""))

func sign_first(p: TDGameProfile, role: String, token: String) -> Dictionary:
	var offer: Dictionary=p.employees.market_rows("chengdu",role)[0]
	var result:=p.employees.sign_employee(offer.id,token,offer.offer_key);assert_true(result.ok,result.code)
	return offer

func next_day(p: TDGameProfile) -> void:
	if p.shop.snapshot().phase=="PREPARE": assert_true(p.shop.close_for_night().ok)
	assert_true(p.next_day().ok)

func after_each() -> void:
	if is_instance_valid(app):
		app.game_shell.go_title();app.queue_free();app=null
	get_tree().paused=false
	for p: TDGameProfile in profiles: p.close()
	profiles.clear()
	await wait_process_frames(2)

func test_schema9_real_contract_supplier_paid_order_roundtrip_and_duplicate() -> void:
	var p:=make_profile()
	var offer:=sign_first(p,"cook","sign-once")
	assert_true(p.suppliers.order("chengdu","player_diner",{"tomato":1000},"supply-once").ok)
	var raw:=p.snapshot();var checked:=TDGameProfile.validate_save(raw)
	assert_true(checked.ok,checked.code)
	var q:=make_profile();var restored:=q.restore(raw)
	assert_true(restored.ok,restored.code)
	assert_eq(q.employees.snapshot(),p.employees.snapshot())
	assert_eq(q.suppliers.snapshot(),p.suppliers.snapshot())
	var cash: int=int(q.shop.snapshot().money_cents)
	assert_false(q.employees.sign_employee(offer.id,"sign-once",offer.offer_key).ok)
	assert_false(q.suppliers.order("chengdu","player_diner",{"tomato":1000},"supply-once").ok)
	assert_eq(int(q.shop.snapshot().money_cents),cash)
	var start: int=int(q.shop.available("tomato"))
	q.suppliers.advance(100000)
	assert_eq(int(q.shop.available("tomato")),start+1000)
	q.suppliers.advance(100000)
	assert_eq(int(q.shop.available("tomato")),start+1000)
	checked=TDGameProfile.validate_save(q.snapshot());assert_true(checked.ok,checked.code)

func test_paid_and_delivered_cross_references_reject_corruption() -> void:
	var p:=make_profile();assert_true(p.suppliers.order("chengdu","player_diner",{"tomato":1000},"paid").ok)
	var raw:=p.snapshot();raw.shop.seen.erase("paid")
	assert_eq(TDGameProfile.validate_save(raw).code,"UNPAID_SUPPLIER_ORDER")
	raw=p.snapshot();raw.suppliers.orders[0].token="test-funds"
	assert_eq(TDGameProfile.validate_save(raw).code,"INVALID_SUPPLIER_PAYMENT")
	raw=p.snapshot();raw.suppliers.orders[0].jobs[0].delivered=true;raw.suppliers.orders[0].jobs[0].elapsed=raw.suppliers.orders[0].jobs[0].seconds
	assert_eq(TDGameProfile.validate_save(raw).code,"INCONSISTENT_SUPPLY_RECEIPT")
	raw=p.snapshot();raw.employees.owned["cook-he"]={"id":"cook-he","copies":1,"xp":0,"assigned":"player-branch:999"}
	assert_false(TDGameProfile.validate_save(raw).ok)

func test_branch_needs_three_owned_roles_and_supplier_inventory() -> void:
	var p:=make_profile();var id:=ready_branch(p)
	assert_false(p.employees.ready_for(id))
	assert_true(p.employees.assign("cook-he",id).ok)
	assert_true(p.employees.assign("waiter-ning",id).ok)
	assert_false(p.employees.ready_for(id),"staff alone cannot open an unfinished site")
	next_day(p)
	assert_true(p.employees.ready_for(id))
	var cash: int=int(p.shop.snapshot().money_cents)
	p.branches.prepare()
	assert_eq(int(p.shop.snapshot().money_cents),cash,"Prepare cannot secretly buy ingredients")
	var dish: Dictionary=p.branches.state.stores[id].menu[0]
	assert_false(p.branches._enough(p.branches.state.stores[id],dish))
	var before: Dictionary=p.shop.snapshot().inventory
	assert_true(p.suppliers.order("chengdu",id,dish.ingredients,"branch-food").ok)
	p.suppliers.advance(100000)
	assert_true(p.branches._enough(p.branches.state.stores[id],dish))
	assert_eq(p.shop.snapshot().inventory,before,"Branch delivery must not alter home inventory")
	var check:=TDGameProfile.validate_save(p.snapshot());assert_true(check.ok,check.code)
	assert_true(p.employees.assign("cook-he","").ok)
	assert_true(p.branches.candidates("chengdu",{}).is_empty(),"Missing cook blocks sale candidates")

func test_main_payroll_accrues_once_as_operating_cost_and_debt() -> void:
	var p:=make_profile();own(p,"cook-he")
	assert_true(p.employees.assign("cook-he","player_diner").ok)
	var wage: int=p.employees.wages_for("player_diner")
	p._accrue_main_payroll();p._accrue_main_payroll()
	assert_eq(int(p.commerce.state.debt_cents),wage)
	assert_true(p.shop.close_for_night().ok)
	var book: Dictionary=p.shop.day_summary().economy
	assert_eq(int(book.wages_cents),wage)
	var money: int=int(p.shop.snapshot().money_cents)
	assert_false(p.shop.settle_day().ok)
	assert_eq(int(p.shop.snapshot().money_cents),money)
	assert_eq(int(p.commerce.state.debt_cents),0)
	var result:=TDGameProfile.validate_save(p.snapshot());assert_true(result.ok,result.code)

func test_legacy8_migrates_existing_workers_manager_and_supply_entitlements() -> void:
	var p:=make_profile();p.branches.managed=false
	assert_true(p.branches.open_store("chengdu",[6,48,3,4],"cn","manager.master","legacy-open").ok)
	var raw:=p.snapshot();raw.schema_version=8;raw.erase("employees");raw.erase("suppliers")
	var crew:=TDRestaurantCrew.new();assert_true(crew.hire("cook-he").ok)
	raw.layout.crew=crew.export_state()
	var q:=make_profile();var migrated:=q.restore(raw)
	assert_true(migrated.ok,migrated.code)
	assert_true(q.employees.employee_info("cook-he").owned)
	assert_false(q.employees.ready_for("player-branch:1"),"old paid site retains its next-day opening boundary")
	assert_eq(q.employees.manager_for("player-branch:1").stars,3)
	assert_eq(int(q.shop.snapshot().money_cents),int(raw.shop.money_cents))
	var checked:=TDGameProfile.validate_save(q.snapshot());assert_true(checked.ok,checked.code+JSON.stringify(q.characters.snapshot()))

func test_manual_save_owns_employees_supply_and_relationships_together() -> void:
	var p:=make_profile();var store:=TDProfileStore.new("res://artifacts/management-ui/saves/%d"%Time.get_ticks_usec(),TDGameProfile.validate_save)
	p.persistence=store.save_slot;assert_true(p.save().ok)
	sign_first(p,"waiter","unsaved-sign")
	p.characters.mark_met("aling")
	assert_true(TDGameProfile.validate_save(p.snapshot()).ok)
	var disk:=store.load_slot("slot-01");assert_true(disk.ok)
	assert_true(disk.data.employees.owned.is_empty())
	assert_false(bool(disk.data.characters.records.aling.flags.get("met",false)))
	assert_true(p.save().ok)
	disk=store.load_slot("slot-01");assert_true(TDLevelProgression.same_value(disk.data.employees.owned,p.employees.snapshot().owned))
	assert_true(disk.data.characters.records.aling.flags.met)

func test_real_shell_seven_buttons_shortcuts_pause_and_old_entries_removed() -> void:
	app=load("res://src/app/main.tscn").instantiate()
	app.settings_path="res://artifacts/management-ui/scene/%d/settings.json"%Time.get_ticks_usec()
	add_child(app);await wait_process_frames(2)
	var shell: TDGameShell=app.game_shell;shell.automatic_time=false
	assert_true(shell.create_game("slot-01","管理测试").ok)
	shell.guide.dialogue.finish_now();shell.profile.story.beat="done"
	await wait_process_frames(2)
	for pair: Array in [["employees","employees_menu"],["quests","quest_journal"],["map","world_map"],["branches","branches_menu"],["suppliers","suppliers_menu"],["relationships","relationships_menu"]]:
		shell._hud.button_for(pair[0]).pressed.emit()
		assert_not_null(shell._modal,pair[0]);assert_true(get_tree().paused)
		var event:=InputEventAction.new();event.action=pair[1];event.pressed=true;shell._input(event)
		assert_null(shell._modal,pair[0]+" shortcut closes same panel");assert_false(get_tree().paused)
	assert_eq(shell._hud.buttons.size(),7)
	shell._hud.button_for("recipes").pressed.emit();assert_not_null(shell.atlas)
	var close:=InputEventAction.new();close.action="recipe_book";close.pressed=true;shell._input(close)
	assert_null(shell.atlas);assert_false(get_tree().paused)
	for marker: Dictionary in shell.restaurant.interaction_points(): assert_false(marker.action in ["hire","recipes"])
	assert_true(shell.town.management_menus)
	var old_lots: Array=shell.profile.world.town_map.plots.filter(func(p:Dictionary)->bool:return p.kind=="factory_lot")
	assert_false(old_lots.is_empty())
	var lot: Dictionary=old_lots[0]
	shell.town._player.position=shell.town._origin()+Vector2(lot.x+.5,lot.y+.5)*TDTownWorld.CELL
	assert_ne(shell.town.facing_plot().get("id",""),lot.id)
	assert_true(shell.town._walkable(int(lot.x),int(lot.y)))

func test_boundary_receives_completed_main_supply_before_next_open() -> void:
	var p:=make_profile()
	assert_true(p.suppliers.order("chengdu","player_diner",{"tomato":1000},"prepaid").ok)
	assert_true(p.shop.open_day().ok)
	var before: int=int(p.shop.available("tomato"))
	p.suppliers.advance(100000)
	assert_eq(int(p.shop.available("tomato")),before)
	assert_true(p.shop.close_for_night().ok)
	assert_true(p.next_day().ok)
	assert_eq(int(p.shop.available("tomato")),before+1000)
	assert_true(p.suppliers.state.orders[0].jobs[0].delivered)

func test_legacy_prepaid_wage_is_not_charged_twice() -> void:
	var p:=make_profile();own(p,"cook-he")
	assert_true(p.employees.assign("cook-he","player_diner").ok)
	var wage: int=p.employees.wages_for("player_diner")
	assert_true(p.shop.pay_wage(wage,"crew:cook-he:1").ok)
	assert_true(p.shop.close_for_night().ok)
	assert_eq(int(p.shop.day_summary().economy.wages_cents),wage)
	assert_eq(int(p.commerce.state.debt_cents),0)

func test_bad_profile_fields_reject_without_runtime_exception() -> void:
	var p:=make_profile();var raw:=p.snapshot();raw.erase("economy")
	assert_false(TDGameProfile.validate_save(raw).ok)
	raw=p.snapshot();raw.economy=3;assert_false(TDGameProfile.validate_save(raw).ok)
	raw=p.snapshot();raw.branches.stores["player-branch:1"]=3;assert_false(TDGameProfile.validate_save(raw).ok)

func test_after_settlement_branch_purchase_stays_in_cash_book() -> void:
	var p:=make_profile();var id:=ready_branch(p);next_day(p)
	assert_true(p.shop.close_for_night().ok)
	var before: Dictionary=p.branches.state.stores[id].books.back().duplicate(true)
	var ordered:=p.suppliers.order("chengdu",id,{"tomato":1000},"after-close")
	assert_true(ordered.ok,ordered.code)
	var book: Dictionary=p.branches.state.stores[id].books.back()
	assert_eq(int(book.purchase_cents),int(before.purchase_cents)+int(ordered.data.total_cents))
	assert_eq(int(book.profit_cents),int(before.profit_cents))
	var q:=make_profile();assert_true(q.restore(p.snapshot()).ok)
	assert_eq(q.branches.state.stores[id].books.back().purchase_cents,book.purchase_cents)
	assert_true(q.next_day().ok)
	assert_eq(q.branches.state.stores[id].books.back().purchase_cents,book.purchase_cents)

func test_management_auto_only_assigns_idle_owned_workers_and_never_draws_or_buys() -> void:
	var p:=make_profile();var id:=ready_branch(p)
	next_day(p)
	var cash: int=int(p.shop.snapshot().money_cents);var draws: int=int(p.employees.state.draw_count)
	assert_true(p.branches.set_management(id,true).ok)
	assert_true(p.employees.ready_for(id))
	assert_eq(int(p.shop.snapshot().money_cents),cash)
	assert_eq(int(p.employees.state.draw_count),draws)
	assert_true(p.suppliers.state.orders.is_empty())
	assert_true(p.branches.state.stores[id].inventory.is_empty())
	var configured: Array=p.branches.state.stores[id].menu.duplicate(true)
	assert_true(p.branches.set_management(id,false).ok)
	p.branches.automate()
	assert_eq(p.branches.state.stores[id].menu,configured)

func test_fixed_manager_branch_and_schema_one_employee_compatibility() -> void:
	var p:=make_profile();var hired:=sign_first(p,"manager","fixed-manager")
	var manager: String=str(hired.id)
	var name_before: String=str(hired.name)
	var opened:=p.branches.open_store("chengdu",[6,48,3,4],"cn",manager,"generated-branch")
	assert_true(opened.ok,opened.code)
	var raw: Dictionary=JSON.parse_string(JSON.stringify(p.snapshot()));var checked:=TDGameProfile.validate_save(raw)
	assert_true(checked.ok,checked.code)
	var q:=make_profile();checked=q.restore(raw);assert_true(checked.ok,checked.code)
	assert_eq(q.employees.manager_for(str(opened.data.store_id)).id,manager)
	assert_eq(q.employees.employee_info(manager).name,name_before)
	assert_eq(q.employees.employee_info(manager).stars,p.employees.employee_info(manager).stars)
	sign_first(q,"cook","post-reload")
	var old:=make_profile();own(old,"cook-he",3);assert_true(old.employees.assign("cook-he","player_diner").ok)
	var old_raw:=old.snapshot();old_raw.employees.schema_version=1
	checked=q.restore(old_raw);assert_true(checked.ok,checked.code)
	assert_eq(q.employees.employee_info("cook-he").name,"阿禾");assert_eq(int(q.employees.state.schema_version),3)

func test_contract_payment_amount_day_and_receipt_must_match() -> void:
	var p:=make_profile();var offer:=sign_first(p,"cook","fee-check")
	var raw:=p.snapshot();raw.employees.contracts[offer.id].fee_cents+=1
	assert_false(TDGameProfile.validate_save(raw).ok)
	raw=p.snapshot();raw.employees.contracts[offer.id].token="test-funds";raw.employees.seen["test-funds"]=true
	assert_false(TDGameProfile.validate_save(raw).ok)
	raw=p.snapshot();raw.shop.seen.erase("fee-check")
	assert_eq(TDGameProfile.validate_save(raw).code,"UNPAID_EMPLOYEE_RECRUITMENT")
	# A valid negative payment of another size cannot stand in for this employee's fee.
	assert_true(p.shop.branch_adjustment(-100,"wrong-fee","fixture","employee-roster").ok)
	raw=p.snapshot();raw.employees.contracts[offer.id].token="wrong-fee";raw.employees.seen["wrong-fee"]=true
	assert_eq(TDGameProfile.validate_save(raw).code,"INVALID_EMPLOYEE_CONTRACT_PAYMENT")
