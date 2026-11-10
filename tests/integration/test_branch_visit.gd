extends GutTest
var app: TDApplication
var shell: TDGameShell
func before_each() -> void:
	app=load("res://src/app/main.tscn").instantiate();app.settings_path="res://artifacts/branch-visit/%d/settings.json"%Time.get_ticks_usec()
	add_child_autofree(app);shell=app.game_shell;shell.automatic_time=false
	await get_tree().process_frame
	var created:=shell.create_game("slot-01","分店巡视测试");assert_true(created.ok,created.code+": "+created.message)
	shell.guide.dialogue.finish_now();shell.profile.shop.world_adjustment(300000,"fixture","test")
func after_each() -> void:
	shell.go_title();get_tree().paused=false
	await wait_process_frames(2)
func next_day() -> void:
	assert_true(shell.profile.shop.close_for_night().ok)
	assert_true(shell.profile.next_day().ok)
	await wait_process_frames(3)
func key_e() -> void:
	var key:=InputEventAction.new();key.action="world_interact";key.pressed=true;Input.parse_input_event(key)
	await wait_process_frames(2)
	key=InputEventAction.new();key.action="world_interact";key.pressed=false;Input.parse_input_event(key)
	await wait_process_frames(2)
func stand_by(id: String) -> bool:
	var store: Dictionary=shell.profile.branches.state.stores[id];var r: Array=store.rect
	for y: int in range(int(r[1])-1,int(r[1]+r[3])+1):
		for x: int in range(int(r[0])-1,int(r[0]+r[2])+1):
			if shell.visiting==null:
				if not shell.town._walkable(x,y): continue
				shell.town._player.position=shell.town._origin()+(Vector2(x,y)+Vector2.ONE*.5)*TDTownWorld.CELL
				if shell.town.facing_plot().get("branch_id")==id: return true
			else:
				var feet: Vector2=(Vector2(x,y)+Vector2.ONE*.5)*TDTravelWorld.CELL
				if not shell.visiting._can_stand(feet): continue
				shell.visiting.player.position=feet
				if shell.visiting.nearby().get("branch_id")==id: return true
	return false
func test_home_construction_blocks_entry_then_real_room_signals_preserve_main_state() -> void:
	var result:=shell.profile.branches.open_store("chengdu",[6,48,3,4],"cn","","build")
	assert_true(result.ok);var id: String=result.data.store_id
	shell.travel("town");assert_true(stand_by(id))
	await key_e();assert_null(shell.branch_visit);assert_eq(shell.location,"town")
	await next_day();shell.travel("town");assert_true(stand_by(id));var return_point: Vector2=shell.town._player.position
	var before:=shell.profile.snapshot()
	await key_e();assert_not_null(shell.branch_visit)
	if shell.branch_visit==null: return
	assert_eq(shell.location,"branch");assert_eq(shell.branch_visit.store_id,id)
	assert_false(shell.restaurant._player.controls_enabled);assert_false(shell.kitchen_view.kitchen.world._player.controls_enabled)
	var visit:=shell.branch_visit;assert_eq(visit.room,"restaurant")
	assert_false(visit.layout.path(Vector2i(visit.player.position/visit.layout.cell_px),Vector2i(visit.kitchen_point/visit.layout.cell_px)).is_empty(),"door and kitchen connected")
	visit.player.position=visit.kitchen_point;await key_e();assert_eq(visit.room,"kitchen")
	visit.kitchen._player.position=Vector2(200,330);await key_e()
	assert_not_null(shell._modal)
	var panel:=shell._modal_box.find_children("*","TDBranchPanel",true,false)[0] as TDBranchPanel
	assert_eq(panel.selected_id,id);assert_eq(panel.current_tab,"books")
	shell._close_dialog();assert_true(visit.kitchen._player.controls_enabled)
	visit.kitchen._player.position=TDKitchenWorld.DOOR_POS;await key_e();assert_eq(visit.room,"restaurant")
	visit.player.position=visit.exit_point;await key_e()
	assert_null(shell.branch_visit);assert_eq(shell.location,"town");assert_eq(shell.town._player.position,return_point)
	assert_eq(shell.profile.snapshot(),before,"inspection does not mutate main inventory, payroll or orders")
	assert_true(TDGameProfile.validate_save(shell.profile.snapshot()).ok)
	for repeat: int in 2:
		assert_true(stand_by(id));await key_e();assert_not_null(shell.branch_visit);shell.exit_branch();await wait_process_frames(2)
	assert_eq(shell.find_children("*","TDBranchInterior",true,false).size(),0)
func test_remote_branch_returns_same_town_and_pause_blocks_room_input() -> void:
	var rect: Array=[]
	for y: int in range(4,68):
		for x: int in range(2,68):
			if shell.profile.branches.quote("tokyo",[x,y,3,4],"cn").ok: rect=[x,y,3,4];break
		if not rect.is_empty(): break
	assert_false(rect.is_empty());var result:=shell.profile.branches.open_store("tokyo",rect,"cn","","build")
	assert_true(result.ok);var id: String=result.data.store_id
	await next_day();shell.travel("town");shell.town.spawn_at_harbor()
	assert_true(shell.voyage("tokyo").ok);assert_true(stand_by(id))
	var position: Vector2=shell.visiting.player.position
	await key_e();assert_not_null(shell.branch_visit)
	if shell.branch_visit==null: return
	assert_eq(shell.visiting_town,"tokyo");assert_false(shell.visiting.visible);assert_false(shell.visiting._layer.visible)
	var visit:=shell.branch_visit;visit.player.position=visit.kitchen_point
	shell.show_pause();await key_e();assert_eq(visit.room,"restaurant")
	shell._close_dialog();await key_e();assert_eq(visit.room,"kitchen")
	shell.open_atlas();assert_eq(visit.kitchen._player.process_mode,Node.PROCESS_MODE_DISABLED);await key_e();assert_eq(visit.room,"kitchen");shell.close_atlas()
	visit.kitchen._player.position=TDKitchenWorld.DOOR_POS;await key_e();assert_eq(visit.room,"restaurant")
	visit.player.position=visit.exit_point;await key_e();assert_eq(shell.location,"voyage")
	assert_eq(shell.visiting_town,"tokyo");assert_eq(shell.visiting.player.position,position);assert_true(shell.visiting.visible)
func test_real_payment_ui_no_manager_choice_and_cancel_is_read_only() -> void:
	shell.show_branch();var panel:=shell._modal_box.find_children("*","TDBranchPanel",true,false)[0] as TDBranchPanel
	panel.begin_site();panel.map_view.choose_town("chengdu");panel.selected_rect=[6,48,3,4];panel._update_quote()
	var before:=shell.profile.snapshot();panel.list_stores();assert_eq(shell.profile.snapshot(),before)
	panel.begin_site();panel.map_view.choose_town("chengdu");panel.selected_rect=[6,48,3,4];panel._update_quote();panel.site_button.pressed.emit()
	assert_false(panel.create_button.disabled);assert_eq(panel.manager_box.find_children("ManagerCards","",true,false).size(),0)
	panel.create_button.pressed.emit();await wait_process_frames(2)
	assert_eq(shell.profile.branches.paid_ids().size(),1)
	var store: Dictionary=shell.profile.branches.state.stores.values()[0]
	assert_eq(store.manager_id,"");assert_true(shell.profile.employees.assigned(store.id).is_empty())
	assert_eq(int(before.shop.money_cents)-int(shell.profile.shop.snapshot().money_cents),30800)
	assert_true(TDGameProfile.validate_save(shell.profile.snapshot()).ok)
