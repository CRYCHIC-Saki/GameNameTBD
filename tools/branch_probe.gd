extends SceneTree
const OUT := "res://artifacts/branch-world/gpu"
var app: TDApplication
var shell: TDGameShell
var checks: int=0
var failed: bool=false
var captures: int=0

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	checks+=1
	print(("PASS " if value else "FAIL ")+message)
	if not value: failed=true

func capture(name: String) -> void:
	await process_frame; await process_frame; await RenderingServer.frame_post_draw
	var result:=root.get_texture().get_image().save_png(OUT.path_join(name+".png"))
	check(result==OK,"capture "+name); captures+=1

func panel() -> TDBranchPanel:
	for child: Node in shell._modal_box.get_children():
		if child is TDBranchPanel: return child
	return null

func event_at(view: TDBranchPanel.SiteMap, cell: Vector2i, pressed: bool) -> void:
	var event:=InputEventMouseButton.new(); event.button_index=MOUSE_BUTTON_LEFT; event.pressed=pressed
	event.position=view.get_global_transform_with_canvas()*view.cell_to_screen(view.selected_town,Vector2(cell)+Vector2.ONE*.5)
	root.push_input(event)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	root.size=Vector2i(1280,800)
	app=load("res://src/app/main.tscn").instantiate()
	app.settings_path="res://artifacts/branch-world/probe-slots/%d/settings.json"%Time.get_ticks_usec()
	root.add_child(app); shell=app.game_shell; shell.automatic_time=false
	await process_frame
	var made:=shell.create_game("slot-01","分店演示")
	check(made.ok,"isolated official new slot")
	shell.guide.dialogue.finish_now()
	check(shell.profile.shop.world_adjustment(300000,"probe-funds","fixture").ok,"isolated review funds")
	shell.show_branch(); panel().begin_site()
	await process_frame; await process_frame
	await capture("01-site-map")
	var view:=panel()
	var scroll:=shell._modal_box.get_parent() as ScrollContainer
	scroll.scroll_vertical=150
	await process_frame; await process_frame
	view.map_view.choose_town("chengdu")
	event_at(view.map_view,Vector2i(6,48),true); event_at(view.map_view,Vector2i(8,51),false)
	await process_frame
	check(view.selected_rect==[6,48,3,4],"real viewport pointer rectangle")
	check(view.map_view.valid,"real map quote valid")
	await capture("02-rectangle")
	view.site_button.pressed.emit(); scroll.scroll_vertical=0
	await process_frame
	view._choose_manager("manager.host")
	await capture("03-managers")
	check(not view.create_button.disabled,"manager required before commit")
	view.create_button.pressed.emit()
	await process_frame
	check(shell.profile.branches.state.stores.size()==1,"first local branch created")
	await capture("04-branch-books")
	view=panel(); view.manage("player-branch:1"); scroll.scroll_vertical=0
	await capture("05-menu-budget")
	for id: String in TDRegionalLayout.IDS:
		view.begin_site(); scroll.scroll_vertical=150
		await process_frame; await process_frame
		var atlas:=view.map_view
		var at:=atlas.get_global_transform_with_canvas()*atlas.world_to_screen(TDTravelMapView.ORIGINS[id]+Vector2.ONE*110)
		var down:=InputEventMouseButton.new();down.button_index=MOUSE_BUTTON_LEFT;down.position=at;down.pressed=true;root.push_input(down)
		var up:=InputEventMouseButton.new();up.button_index=MOUSE_BUTTON_LEFT;up.position=at;up.pressed=false;root.push_input(up)
		await process_frame
		check(view.selected_town==id,"world atlas pointer selects "+id)
		check(atlas.caption_text()==TDTravelCatalog.info(id).caption,"selected town description "+id)
		var site:=TDRegionMigration.find_site(shell.profile.branches.town_map(id),[6,48,3,4])
		var center:=Vector2(site[0]+site[2]*.5,site[1]+site[3]*.5)
		atlas.zoom_at(atlas.cell_to_screen(id,center),1.5)
		atlas.pan+=atlas.size*.5-atlas.cell_to_screen(id,center);atlas.queue_redraw()
		await process_frame
		event_at(atlas,Vector2i(site[0]+site[2]-1,site[1]+site[3]-1),true)
		event_at(atlas,Vector2i(site[0],site[1]),false)
		await process_frame
		check(view.selected_rect==site and atlas.valid,"overseas land quote "+id)
		await capture("overseas-"+id)
		view.site_button.pressed.emit();view._choose_manager("manager.steady");view.create_button.pressed.emit()
		await process_frame
		check(shell.profile.branches.plots(id).size()==1,"real overseas creation "+id)
	check(shell.profile.commerce.state.routes==["chengdu"],"opening abroad never unlocks cargo routes")
	var second:=shell.profile.branches.open_store("chengdu",[6,53,3,4],"cn","manager.master","probe-second")
	check(second.ok,"second local branch")
	check(shell.save_game().ok,"explicit save with six branches")
	var before:=shell.profile.snapshot()
	check(shell.profile.branches.open_store("chengdu",[6,53,3,4],"cn","manager.steady","overlap").code=="OCCUPIED","occupied rectangle rejected")
	check(shell.profile.snapshot()==before,"rejected operation is atomic")
	shell._close_dialog(); shell.travel("town")
	var town:=shell.town
	town._player.position=Vector2(10,52)*TDTownWorld.CELL
	await process_frame; await process_frame
	await capture("06-town-branches")
	town._player.position=town._origin()+Vector2(5.5,50)*TDTownWorld.CELL
	await process_frame; await process_frame
	var interact:=InputEventKey.new(); interact.physical_keycode=KEY_E; interact.pressed=true; root.push_input(interact)
	interact=InputEventKey.new(); interact.physical_keycode=KEY_E; interact.pressed=false; root.push_input(interact)
	await process_frame
	check(shell._modal!=null and shell._modal_box.find_children("*","TDBranchPanel",true,false).size()==1,"nearby E opens branch management")
	shell._close_dialog()
	for day: int in 3:
		check(shell.profile.shop.close_for_night().ok,"real day settlement "+str(day))
		var raw:=shell.profile.snapshot()
		var valid:=TDGameProfile.validate_save(raw)
		check(valid.ok,"complete package validates: "+valid.code)
		if day<2: check(shell.profile.next_day().ok,"advance one day")
	shell.show_branch(); panel().manage("player-branch:1")
	await process_frame; await process_frame
	scroll=shell._modal_box.get_parent() as ScrollContainer; scroll.scroll_vertical=2000
	await capture("07-day-ledger")
	var stores: Dictionary=shell.profile.branches.snapshot().stores
	check(stores["player-branch:1"].books.size()==2,"only post-opening days charged")
	var audit:=shell.profile.commerce.cash_audit(int(shell.profile.shop.snapshot().money_cents))
	check(int(audit.difference_cents)==0,"world cash conserved")
	var saved:=shell.save_game(); check(saved.ok,"final explicit checkpoint")
	var money: int=int(shell.profile.shop.snapshot().money_cents)
	shell.go_title(); check(shell.load_game("slot-01").ok,"reload legal checkpoint")
	check(int(shell.profile.shop.snapshot().money_cents)==money,"cash unchanged after reload")
	var loaded: Dictionary=shell.profile.branches.snapshot().stores
	var expected_file:=FileAccess.open(OUT.path_join("expected-stores.json"),FileAccess.WRITE); expected_file.store_string(JSON.stringify(stores,"  ")); expected_file.close()
	var actual_file:=FileAccess.open(OUT.path_join("loaded-stores.json"),FileAccess.WRITE); actual_file.store_string(JSON.stringify(loaded,"  ")); actual_file.close()
	print("JSON numeric type before/after: ",typeof(stores["player-branch:1"].rect[0])," / ",typeof(loaded["player-branch:1"].rect[0]))
	check(TDLevelProgression.same_value(loaded,stores),"branch books survive disk JSON roundtrip")
	shell.go_title(); app.queue_free(); await process_frame; await process_frame
	var file:=FileAccess.open(OUT.path_join("summary.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"status":"FAIL" if failed else "PASS","checks":checks,"captures":captures,"renderer":"Compatibility","human_playtest":"PENDING"})); file.close()
	quit(1 if failed else 0)
