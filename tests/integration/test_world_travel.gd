extends GutTest
var app: TDApplication
var shell: TDGameShell

func before_each() -> void:
	app=load("res://src/app/main.tscn").instantiate()
	app.settings_path="res://artifacts/travel/tests/%d/settings.json"%Time.get_ticks_usec()
	add_child_autofree(app);shell=app.game_shell;shell.automatic_time=false
	await wait_process_frames(1)
	assert_true(shell.create_game("slot-01","航线测试").ok)
	shell.guide.dialogue.finish_now();shell.profile.story.beat="done"
	shell.travel("town");shell.town.spawn_at_harbor()

func after_each() -> void:
	for action: String in ["world_left","world_right","world_up","world_down","world_sprint"]: Input.action_release(action)
	get_tree().paused=false;shell._close_dialog();shell._dispose_game()
	await wait_process_frames(2)

func test_four_towns_round_trip_does_not_mutate_home_or_unlocks() -> void:
	var before:=shell.profile.snapshot()
	for id: String in ["tokyo","paris","bangkok","mexico_city"]:
		assert_true(shell.voyage(id).ok,id)
		assert_eq(shell.location,"voyage");assert_eq(shell.visiting.town_id,id)
		assert_eq(shell.visiting.nearby().get("kind"),"harbor")
		assert_eq(shell.voyage(id).code,"INVALID_DESTINATION")
		var map:=shell.visiting.map
		assert_true(map.is_walkable(TDTravelCatalog.port(id).x,TDTravelCatalog.port(id).y));assert_false(map.is_walkable(0,0))
		assert_gt(shell.visiting._buildings.size(),6)
		assert_eq(shell.profile.snapshot(),before)
	assert_true(shell.voyage("chengdu").ok)
	assert_null(shell.visiting);assert_eq(shell.location,"town")
	assert_eq(shell.profile.snapshot(),before)

func test_map_key_pause_return_and_no_remote_teleport_from_map() -> void:
	assert_true(shell.voyage("tokyo").ok)
	var key:=InputEventAction.new();key.action="world_map";key.pressed=true
	shell._input(key)
	assert_true(shell._map_open);assert_true(get_tree().paused);assert_false(shell.visiting.player.controls_enabled)
	var before:=shell.visiting.player.position
	shell._input(key)
	assert_false(shell._map_open);assert_false(get_tree().paused);assert_true(shell.visiting.player.controls_enabled)
	assert_eq(shell.visiting.player.position,before)
	shell.visiting.player.position=Vector2(20.5,20.5)*48
	assert_eq(shell.voyage("paris").code,"NOT_AT_PORT")
	assert_eq(shell.visiting_town,"tokyo")

func test_unknown_destination_and_protected_water_and_paused_clock() -> void:
	var before:=shell.profile.snapshot()
	assert_false(shell.voyage("bad-town").ok);assert_eq(shell.profile.snapshot(),before)
	assert_true(shell.voyage("mexico_city").ok)
	var safe:=shell.visiting.player.position
	assert_false(shell.visiting._confine(Vector2(.5,.5)*48))
	shell.show_world_map();var minute:=shell.profile.characters.clock.minute
	shell.advance_world_time(30);assert_eq(shell.profile.characters.clock.minute,minute)
	shell._close_dialog()

func test_saved_branch_footprints_are_same_on_travel_map() -> void:
	var home: TDTownMap=shell.profile.world.town_map
	var copy:=TDTravelCatalog.map_for(shell.profile,"chengdu")
	assert_eq(copy.roads,home.roads);assert_eq(copy.plots,home.plots)
	copy.plots.clear();assert_false(home.plots.is_empty())
	var tex:=TDTravelCatalog.sprite("paris",0) as AtlasTexture
	assert_eq(tex.atlas.resource_path,"res://assets/town/restaurant-european-v1.png")
	assert_almost_eq(tex.get_width()/float(tex.get_height()),1.5,.001,"New facade preserves the old collision canvas aspect")
	var house:=TDTravelCatalog.sprite("paris",1) as AtlasTexture
	assert_eq(house.region.position,Vector2(384,256));assert_eq(house.region.size,Vector2(384,256))

func test_service_can_leave_but_procurement_policy_stays_separate() -> void:
	assert_true(shell.kitchen_view.buy_kit("service.tomato_egg").ok)
	assert_true(shell.profile.shop.open_day().ok)
	assert_true(shell.travel("restaurant").ok);assert_true(shell.travel("town").ok)
	shell.town.spawn_at_harbor();assert_true(shell.voyage("bangkok").ok)
	assert_false(shell.profile.can_leave_shop()) # existing purchase boundary, not travel permission
	assert_true(shell.kitchen_view.staff_status().contains("缺厨师"))

func test_night_forces_return_from_foreign_town_and_rejects_stale_travel() -> void:
	assert_true(shell.voyage("paris").ok)
	shell.advance_world_time(TDWorldDayClock.END_MINUTE-shell.profile.characters.clock.minute)
	assert_null(shell.visiting)
	assert_eq(shell.location,"town") # new slot: homecoming story precedes the locked cottage
	assert_eq(shell.visiting_town,"chengdu")
	assert_eq(shell.profile.characters.clock.closed_day,shell.profile.characters.clock.day)
	assert_eq(shell.voyage("tokyo").code,"NIGHT_CLOSED")

func test_player_pot_and_missing_cook_are_never_taken_over() -> void:
	var view:=shell.kitchen_view
	assert_true(view.buy_kit("service.tomato_egg").ok)
	assert_true(shell.profile.shop.open_day().ok)
	var lane: TDCookingLane=view.kitchen.lanes[0]
	assert_true(lane.perform("add",{"ingredient_id":"tomato","amount":1.0}).ok)
	var before:=lane.snapshot();view.staff_away=true;view.tick_staff()
	assert_eq(lane.snapshot(),before)
	shell.profile.employees.state.owned["cook-he"]={"id":"cook-he","copies":1,"xp":0,"assigned":""}
	assert_eq(shell.profile.employees.assign("cook-he","player_diner").code,"NOT_AT_BOUNDARY")
	# Staffing fixture for the takeover boundary; player reassignment during OPEN remains forbidden.
	shell.profile.employees.state.owned["cook-he"].assigned="player_diner"
	shell.profile.employees.sync_main_crew()
	view.tick_staff();assert_eq(lane.snapshot(),before)
	shell._pause(true);view.tick_staff();assert_eq(lane.snapshot(),before);shell._pause(false)

func test_employee_cook_uses_real_qte_stock_and_does_not_grant_mastery() -> void:
	# Real standalone shop + front room, with deterministic default arrival clock.
	var catalog:=TDServiceCatalog.new();assert_true(catalog.load_file().ok)
	var shop:=TDShopSession.new(catalog,"staff-travel",59)
	var room:=TDRestaurantWorld.new();room.player_mode=true;room.floor_service=true;room.business=shop
	add_child(room);room.bind_dining_clock()
	var view:=TDShopView.new();view.service=catalog;view.shop=shop;view.embedded=true
	view.save_path="res://artifacts/travel/staff-%d.json"%Time.get_ticks_usec();add_child(view);view.kitchen.auto_advance=false
	shop.crew=room.layout.crew;assert_true(shop.crew.hire("cook-he").ok)
	assert_true(shop.buy(shop.offer("service.tomato_egg").stock,"staff-stock").ok)
	for id: String in shop.snapshot().menu: shop.set_menu(id,id=="service.tomato_egg",1200)
	assert_true(shop.open_day().ok);view.staff_away=true
	var before: int=shop.available("tomato")
	for n: int in 1500: view.kitchen.advance(.1)
	var served: Array=shop.snapshot().orders.filter(func(o:Dictionary)->bool:return o.status=="SERVED")
	assert_gt(served.size(),0,"employee real dish reaches original delivery")
	assert_lt(shop.available("tomato"),before)
	assert_eq(shop.mastery("service.tomato_egg").points,0.0)
	var after: int=int(shop.snapshot().money_cents)
	for n: int in 10: view.tick_staff()
	assert_eq(shop.snapshot().money_cents,after)
	view.close();room.close();view.queue_free();room.queue_free();await wait_process_frames(2)

func held(action: String, frames: int, sprint: bool=false) -> Vector2:
	var before:=shell.visiting.player.position
	Input.action_press(action)
	if sprint: Input.action_press("world_sprint")
	for i: int in frames: await get_tree().physics_frame
	Input.action_release(action);Input.action_release("world_sprint")
	await get_tree().physics_frame
	return shell.visiting.player.position-before

func test_actual_physics_movement_sprint_collision_pause_and_reentry_all_towns() -> void:
	for id: String in TDRegionalLayout.IDS:
		assert_true(shell.voyage(id).ok,id)
		var view:=shell.visiting;var start:=view.player.position
		assert_true(view._confine(start),id+" arrival collision-free")
		var walk:=await held("world_left",10)
		assert_lt(walk.x,-12.0,id+" actual held movement from arrival")
		view.player.position=start
		var sprint:=await held("world_left",10,true)
		assert_gt(sprint.length(),walk.length()*1.3,id+" Shift movement")
		# Hold against a real rendered building base: stop outside it, no acceleration.
		var wall: Rect2=view._solids[0]
		view.player.position=Vector2(wall.get_center().x,wall.end.y+25)
		await held("world_up",30)
		assert_gte(view.player.position.y,wall.end.y+8.5,id+" building collision")
		assert_lt(view.player.position.y,wall.end.y+25,id+" approached wall")
		shell.show_world_map();var frozen:=view.player.position
		Input.action_press("world_down")
		await wait_process_frames(5)
		assert_eq(view.player.position,frozen,id+" frozen under map")
		Input.action_release("world_down");shell._close_dialog()
		view.player.position=start
		assert_gt((await held("world_left",6)).length(),10.0,id+" controls restored")
		view.player.position=start
	assert_true(shell.voyage("chengdu").ok)
	assert_true(shell.voyage("tokyo").ok)
	assert_gt((await held("world_left",8)).length(),15.0,"reentry has a live input callback")

func test_world_map_five_towns_wheel_anchor_drag_and_limits() -> void:
	shell.show_world_map()
	var view: TDTravelMapView
	for child: Node in shell._modal_box.get_children():
		if child is TDTravelMapView: view=child
	assert_not_null(view)
	await wait_process_frames(2)
	assert_eq(view.maps.size(),5)
	var cursor:=view.size*.5;var anchor:=view.screen_to_world(cursor)
	var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_WHEEL_UP;event.pressed=true;event.position=cursor
	view._gui_input(event)
	assert_gt(view.zoom,1.0)
	assert_lt(view.screen_to_world(cursor).distance_to(anchor),.001,"cursor anchored zoom")
	var press:=InputEventMouseButton.new();press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true;view._gui_input(press)
	var motion:=InputEventMouseMotion.new();motion.relative=Vector2(40,20);motion.position=cursor;view._gui_input(motion)
	assert_eq(view.pan,Vector2(40,20))
	press.pressed=false;view._gui_input(press)
	for i: int in 20: view.zoom_at(cursor,1.5)
	assert_eq(view.zoom,5.0)
	view.reset_view();assert_eq(view.zoom,1.0);assert_eq(view.pan,Vector2.ZERO)
	assert_eq(shell.visiting_town,"chengdu","atlas never teleports")

func test_interrupted_migration_write_keeps_old_bytes_and_live_profile_then_retries() -> void:
	var p:=shell.profile
	p.region_layout_version=1
	for id: String in TDRegionalLayout.IDS: p.commerce.expansion.state.parcels.erase(id)
	p._wire_commerce()
	assert_true(shell.save_game().ok)
	var path:=shell.slots.path_for("slot-01");var bytes:=FileAccess.get_file_as_bytes(path)
	var before:=p.snapshot()
	shell.slots.interrupt_at="after_temp"
	assert_eq(shell.load_game("slot-01").code,"INTERRUPTED")
	assert_same(shell.profile,p,"failed candidate is never activated")
	assert_eq(p.snapshot(),before)
	assert_eq(FileAccess.get_file_as_bytes(path),bytes)
	assert_eq(FileAccess.get_file_as_bytes(path+".before-region-v2.bak"),bytes)
	shell.slots.interrupt_at=""
	assert_true(shell.load_game("slot-01").ok)
	assert_true(shell.profile.region_migrated_on_load)
	assert_eq(int(shell.slots.load_slot("slot-01").data.region_layout_version),2)
	var revision:=shell.profile.revision
	assert_true(shell.load_game("slot-01").ok)
	assert_false(shell.profile.region_migrated_on_load)
	assert_eq(shell.profile.revision,revision,"migration does not save repeatedly")
