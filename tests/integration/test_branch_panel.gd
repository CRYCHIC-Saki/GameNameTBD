extends GutTest
var app: TDApplication
var shell: TDGameShell

func before_each() -> void:
	app=load("res://src/app/main.tscn").instantiate()
	app.settings_path="res://artifacts/branch-ui/%d/settings.json"%Time.get_ticks_usec()
	add_child_autofree(app); shell=app.game_shell; shell.automatic_time=false
	await get_tree().process_frame
	assert_true(shell.create_game("slot-01","分店测试").ok)
	shell.guide.dialogue.finish_now()
	shell.profile.shop.world_adjustment(300000,"fixture","test")
	# D063: selection is from owned cards, never free anonymous managers.
	for id: String in ["manager.steady","manager.host","manager.master"]:
		shell.profile.employees.state.owned[id]={"id":id,"copies":1,"xp":0,"assigned":""}

func after_each() -> void:
	shell.go_title(); get_tree().paused=false
	await wait_process_frames(2)

func panel() -> TDBranchPanel:
	return shell._modal_box.find_children("*","TDBranchPanel",true,false)[0] as TDBranchPanel

func click_map(view: TDBranchPanel.SiteMap, at: Vector2i, pressed: bool) -> void:
	var event:=InputEventMouseButton.new(); event.button_index=MOUSE_BUTTON_LEFT; event.pressed=pressed
	event.position=view.cell_to_screen(view.selected_town,Vector2(at)+Vector2.ONE*.5)
	view._gui_input(event)

func test_real_entry_rectangle_drag_manager_selection_creation_and_reentry() -> void:
	shell.show_branch(); var view:=panel(); view.begin_site()
	await wait_process_frames(3)
	view.map_view.choose_town("chengdu")
	var before:=shell.profile.snapshot()
	click_map(view.map_view,Vector2i(8,51),true); click_map(view.map_view,Vector2i(6,48),false)
	assert_eq(view.selected_rect,[6,48,3,4])
	assert_true(view.create_button.disabled)
	assert_eq(shell.profile.snapshot(),before)
	view.site_button.pressed.emit()
	assert_false(view.create_button.disabled)
	view.create_button.pressed.emit()
	await wait_process_frames(2)
	assert_eq(shell.profile.branches.state.stores.size(),1)
	assert_eq(shell.profile.branches.state.stores.values()[0].manager_id,"")
	assert_eq(int(before.shop.money_cents)-int(shell.profile.shop.snapshot().money_cents),30800)
	shell._close_dialog(); shell.show_branch()
	assert_eq(shell.profile.branches.state.stores.size(),1)
	assert_eq(panel().find_children("*","TDBranchPanel",true,false).size(),0)
	var checked:=TDGameProfile.validate_save(shell.profile.snapshot()); assert_true(checked.ok,checked.code)

func test_cancel_and_protected_drag_do_not_change_profile() -> void:
	shell.show_branch(); var view:=panel(); view.begin_site(); await wait_process_frames(2)
	view.map_view.choose_town("chengdu")
	var before:=shell.profile.snapshot()
	click_map(view.map_view,Vector2i(19,48),true); click_map(view.map_view,Vector2i(22,51),false)
	assert_true(view.create_button.disabled)
	view.list_stores(); shell._close_dialog()
	assert_eq(shell.profile.snapshot(),before)

func test_new_branch_and_menu_changes_only_persist_after_explicit_save() -> void:
	assert_true(shell.save_game().ok)
	var original:=shell.profile.snapshot()
	var opened:=shell.profile.branches.open_store("chengdu",[6,48,3,4],"cn","manager.steady","open-fixture")
	assert_true(opened.ok,opened.code)
	var store: TDProfileStore=shell.slots
	var saved: TDOutcome=store.load_slot("slot-01")
	assert_true(saved.ok)
	assert_true(saved.data.branches.stores.is_empty())
	assert_eq(int(saved.data.shop.money_cents),int(original.shop.money_cents))
	assert_true(shell.save_game().ok)
	saved=store.load_slot("slot-01")
	assert_eq(saved.data.branches.stores.size(),1)
	shell.profile.branches.configure_store(opened.data.store_id,shell.profile.branches.state.stores[opened.data.store_id].menu,0,true)
	var restored:=TDGameProfile.new(); var result:=restored.restore(saved.data)
	assert_true(result.ok,result.code)
	assert_false(restored.branches.state.stores[opened.data.store_id].paused)
	restored.close()

func atlas_click(view: TDBranchPanel.SiteMap, position: Vector2, pressed: bool) -> void:
	var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.position=position;event.pressed=pressed
	view._gui_input(event)

func test_world_atlas_selects_all_five_towns_resets_selection_and_never_teleports() -> void:
	shell.show_branch();var view:=panel();view.begin_site();await wait_process_frames(3)
	var before:=shell.profile.snapshot();var location: String=shell.visiting_town
	var atlas:=view.map_view
	assert_true(atlas is TDTravelMapView)
	assert_eq(atlas.selected_town,"")
	for id: String in TDTravelCatalog.IDS:
		atlas.reset_view()
		var at:=atlas.world_to_screen(TDTravelMapView.ORIGINS[id]+Vector2.ONE*110)
		atlas_click(atlas,at,true);atlas_click(atlas,at,false)
		assert_eq(view.selected_town,id);assert_eq(atlas.selected_town,id)
		assert_eq(view.selected_rect,[]);assert_true(view.site_button.disabled)
		assert_gte(atlas.zoom,4.0)
		assert_eq(atlas.caption_text(),TDTravelCatalog.info(id).caption)
		assert_eq(atlas.town_id,"chengdu","selection does not move player marker")
	assert_eq(shell.visiting_town,location);assert_eq(shell.profile.snapshot(),before)
	atlas.choose_town("chengdu");click_map(atlas,Vector2i(6,48),true);click_map(atlas,Vector2i(8,51),false)
	atlas.choose_town("tokyo")
	assert_eq(view.selected_rect,[]);assert_eq(view.selected_manager,"");assert_true(view.create_button.disabled)

func test_zoom_pan_reverse_rectangle_and_aborted_drags_keep_last_valid_selection() -> void:
	shell.show_branch();var view:=panel();view.begin_site();await wait_process_frames(3)
	var atlas:=view.map_view;atlas.choose_town("chengdu")
	atlas.zoom_at(atlas.cell_to_screen("chengdu",Vector2(7,49)),1.4)
	var middle:=InputEventMouseButton.new();middle.button_index=MOUSE_BUTTON_MIDDLE;middle.pressed=true
	atlas._gui_input(middle)
	var motion:=InputEventMouseMotion.new();motion.relative=Vector2(40,-12);motion.position=atlas.size*.5
	atlas._gui_input(motion);middle.pressed=false;atlas._gui_input(middle)
	click_map(atlas,Vector2i(8,51),true);click_map(atlas,Vector2i(6,48),false)
	assert_eq(view.selected_rect,[6,48,3,4]);assert_true(atlas.valid)
	var expected:=atlas.selection;var before:=shell.profile.snapshot()
	click_map(atlas,Vector2i(6,48),true)
	atlas_click(atlas,Vector2(-20,200),false)
	assert_eq(atlas.selection,expected)
	click_map(atlas,Vector2i(6,48),true);atlas._notification(NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	click_map(atlas,Vector2i(11,51),false);assert_eq(atlas.selection,expected)
	click_map(atlas,Vector2i(6,48),true)
	var wheel:=InputEventMouseButton.new();wheel.button_index=MOUSE_BUTTON_WHEEL_UP;wheel.position=atlas.size*.5;wheel.pressed=true
	atlas._gui_input(wheel);click_map(atlas,Vector2i(11,51),false);assert_eq(atlas.selection,expected)
	click_map(atlas,Vector2i(6,48),true)
	motion.position=Vector2(-20,200);atlas._gui_input(motion)
	click_map(atlas,Vector2i(11,51),false);assert_eq(atlas.selection,expected)
	assert_eq(view.selected_rect,[6,48,3,4]);assert_eq(shell.profile.snapshot(),before)

func test_large_manager_roster_does_not_force_hiring_before_construction() -> void:
	for n: int in 40:
		var id: String="employee.v1.s001.n%03d"%(n*3+1)
		shell.profile.employees.state.owned[id]={"id":id,"copies":3,"xp":0,"assigned":""}
	shell.show_branch();var view:=panel();view.begin_site();await wait_process_frames(2)
	view.map_view.choose_town("chengdu");view.selected_rect=[6,48,3,4];view._update_quote();view._toggle_site()
	assert_eq(view.manager_box.find_children("ManagerCards","",true,false).size(),0)
	assert_false(view.create_button.disabled)
	var roster:=shell.profile.employees.snapshot()
	view._toggle_site();view._toggle_site();view.confirm();await wait_process_frames(2)
	assert_eq(shell.profile.branches.state.stores.values()[0].manager_id,"")
	assert_eq(shell.profile.employees.snapshot(),roster)
	var checked:=TDGameProfile.validate_save(shell.profile.snapshot());assert_true(checked.ok,checked.code)
