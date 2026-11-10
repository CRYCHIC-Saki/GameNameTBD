extends GutTest
var profiles: Array[TDGameProfile]=[]

func after_each() -> void:
	for profile: TDGameProfile in profiles: profile.close()
	profiles.clear()
	await wait_process_frames(2)

func profile_case() -> TDGameProfile:
	var profile:=TDGameProfile.new();profiles.append(profile)
	assert_true(profile.error.ok,profile.error.code)
	return profile

func test_hud_has_seven_distinct_actions_and_does_not_emit_when_locked() -> void:
	var hud:=TDGameHUD.new();add_child_autofree(hud)
	var received: Array[String]=[]
	hud.action_requested.connect(func(id:String)->void:received.append(id))
	assert_eq(hud.buttons.size(),7)
	var keys: Array[String]=[]
	for action: Dictionary in TDGameHUD.ACTIONS:
		var button:=hud.button_for(str(action.id))
		assert_not_null(button);assert_true(button.tooltip_text.contains("["+str(action.key)+"]"))
		assert_false(str(action.key) in keys);keys.append(str(action.key))
		button.pressed.emit()
	assert_eq(received,["employees","recipes","quests","map","branches","suppliers","relationships"] as Array[String])
	hud.set_menu_enabled(false)
	for button: Button in hud.buttons.values():
		assert_true(button.disabled);button.pressed.emit()
	assert_eq(received.size(),7)
	hud.set_menu_enabled(true);hud.button_for("recipes").pressed.emit()
	assert_eq(received.size(),8)

func test_status_and_menu_stay_on_one_row_at_supported_sizes() -> void:
	var viewport:=SubViewport.new();viewport.size=Vector2i(1280,800);add_child_autofree(viewport)
	var hud:=TDGameHUD.new();viewport.add_child(hud)
	await wait_process_frames(3)
	for dimensions: Vector2i in [Vector2i(1280,800),Vector2i(1920,1080)]:
		viewport.size=dimensions;await wait_process_frames(3)
		assert_lt(hud._status.get_rect().end.x,hud._actions.position.x)
		assert_lte(hud._actions.get_rect().end.x,float(dimensions.x))
		var last_right: float=-1
		for action: Dictionary in TDGameHUD.ACTIONS:
			var rect:=hud.button_for(str(action.id)).get_global_rect()
			assert_eq(rect.position.y,12.0)
			assert_gt(rect.position.x,last_right);last_right=rect.end.x
		assert_eq(hud._status.position.y,hud._actions.position.y)

func test_profile_status_uses_shop_awareness_not_dish_fame_and_is_read_only() -> void:
	var profile:=profile_case();var hud:=TDGameHUD.new();add_child_autofree(hud)
	profile.commerce.state.awareness=.63
	profile.characters.clock.minute=687
	var before:=profile.snapshot()
	hud.update_profile(profile)
	assert_eq(hud.values.awareness,"63")
	assert_eq(hud.values.time,"11:27")
	assert_eq(hud.values.popularity,str(roundi(float(profile.shop.snapshot().popularity))))
	assert_eq(profile.snapshot(),before)
	var sample:={"money":"123.00"};hud.set_values(sample);sample.money="999.00"
	assert_eq(hud.values.money,"123.00")

func test_relationships_only_show_met_people_and_do_not_change_affection() -> void:
	var profile:=profile_case()
	for id: String in profile.characters.records: profile.characters.records[id].flags.erase("met")
	var panel:=TDManagementPanels.RelationshipPanel.new();add_child_autofree(panel);panel.configure(profile)
	assert_eq(panel.visible_ids.size(),0)
	profile.characters.records.aling.flags.met=true
	profile.characters.records.aling.affection=26
	var before:=profile.characters.snapshot();panel.refresh()
	assert_eq(panel.visible_ids,["aling"] as Array[String])
	assert_eq(profile.characters.snapshot(),before)
	profile.characters.records.chen.flags.met=true;panel.refresh()
	assert_eq(panel.visible_ids.size(),2)
	assert_eq(TDManagementPanels.RelationshipPanel.public_biography("镇上引路人。开发注释：只用于验证。"),"镇上引路人。")

func test_value_formatting_uses_currency_cents_and_real_production_time() -> void:
	assert_eq(TDGameHUD.money_text(12345),"123.45")
	assert_eq(TDManagementPanels.SupplierPanel.time_text(59.2),"60 秒")
	assert_eq(TDManagementPanels.SupplierPanel.time_text(180),"3.0 分钟")
	assert_eq(TDManagementPanels.SupplierPanel.time_text(7200),"2.0 小时")

func test_employee_panel_signs_named_candidate_once_per_click_then_assigns_from_warehouse() -> void:
	var profile:=profile_case();var panel:=TDManagementPanels.EmployeePanel.new();add_child_autofree(panel)
	var before:=profile.snapshot();panel.configure(profile)
	assert_eq(profile.snapshot(),before,"browsing never signs or saves")
	assert_eq(panel.market_candidates.size(),8)
	var offer: Dictionary=panel.market_candidates[0];var cash: int=int(profile.shop.snapshot().money_cents)
	panel.sign_candidate(offer.id,offer.offer_key);panel.sign_candidate(offer.id,offer.offer_key)
	assert_eq(profile.employees.roster_count(),1)
	assert_eq(int(profile.shop.snapshot().money_cents),cash-int(offer.sign_fee_cents))
	assert_eq(profile.employees.employee_info(offer.id).assigned,"")
	panel.select_tab("warehouse");assert_eq(panel._employee_grid.get_child_count(),1)
	panel.assign_employee(offer.id,"player_diner")
	assert_eq(profile.employees.assigned("player_diner","cook").size(),1)
	panel.assign_employee(offer.id,"");assert_eq(profile.employees.assigned("player_diner","cook").size(),0)
	await wait_process_frames(2)

func test_supplier_panel_quotes_real_catalogue_and_prevents_same_frame_double_order() -> void:
	var profile:=profile_case();var panel:=TDManagementPanels.SupplierPanel.new();add_child_autofree(panel)
	var before:=profile.snapshot();panel.configure(profile)
	assert_eq(profile.snapshot(),before,"browsing does not purchase or automate")
	assert_eq(panel.TOWNS.size(),5)
	panel.select_item("tomato");assert_false(panel._order_button.disabled)
	panel.place_order();panel.place_order()
	assert_eq(profile.suppliers.state.lines.size(),1)
	assert_eq(str(profile.suppliers.state.lines[0].store_id),"player_diner")
	assert_true(panel._order_info.text.contains("游戏小时"))
	await wait_process_frames(2)
	assert_false(panel._order_button.disabled)

func test_employee_panel_pages_owned_people_without_rendering_the_entire_name_pool() -> void:
	var profile:=profile_case()
	for index: int in 61:
		var id: String="employee.v1.s001.n%03d"%(index+1)
		profile.employees.state.owned[id]={"id":id,"copies":1,"xp":0,"assigned":""}
	var panel:=TDManagementPanels.EmployeePanel.new();add_child_autofree(panel);panel.configure(profile);panel.select_tab("warehouse");panel.select_role("")
	assert_eq(panel._employee_grid.get_child_count(),20)
	assert_true(panel._page_label.text.contains("61 人"));assert_true(panel._page_label.text.contains("1 / 4"))
	panel.change_page(1);assert_eq(panel.page,1);assert_eq(panel._employee_grid.get_child_count(),20)
	panel.change_page(2);assert_eq(panel.page,3);assert_eq(panel._employee_grid.get_child_count(),1)
	assert_eq(profile.employees.roster_rows().size(),61,"default full roster remains available to branch/save validation")
	panel.select_role("cook");assert_eq(panel.page,0);assert_eq(panel._employee_grid.get_child_count(),20)
	await wait_process_frames(2)
