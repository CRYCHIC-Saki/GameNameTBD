extends GutTest
const DRIVER=preload("res://tools/test_support/kitchen_input.gd")
const RESEARCH_DRIVER=preload("res://tools/test_support/research_input.gd")
var app: TDApplication
var shell: TDGameShell
var layer: CanvasLayer
var driver: RefCounted

func before_each() -> void:
	layer=CanvasLayer.new();layer.layer=130;autofree(layer);get_tree().root.add_child(layer)
	app=load("res://src/app/main.tscn").instantiate()
	app.settings_path="res://artifacts/game-tests/%d/settings.json"%Time.get_ticks_usec()
	layer.add_child(app);shell=app.game_shell;shell.automatic_time=false
	shell.legacy_shop_path=app.settings_path+".legacy-shop";shell.legacy_research_path=app.settings_path+".legacy-research"
	driver=DRIVER.new();driver.viewport=get_tree().root
	await get_tree().process_frame

func after_each() -> void:
	shell.go_title();get_tree().paused=false
	await get_tree().process_frame;await get_tree().process_frame

func start() -> void:
	var result:=shell.create_game("slot-01","灶间烟火")
	assert_true(result.ok,result.code)
	driver.kitchen=shell.kitchen_view.kitchen

func button(label: String, within: Node) -> Button:
	for node: Button in within.find_children("*","Button",true,false):
		if node.text==label: return node
	return null

func test_title_new_slot_real_doors_and_repeated_entry_keep_same_session() -> void:
	for label: String in ["开始游戏","继续游戏","载入存档","设置","退出游戏"]: assert_not_null(button(label,shell))
	assert_true(button("继续游戏",shell).disabled)
	driver.tap(KEY_B);assert_null(app.atlas);assert_null(shell.atlas)
	start();assert_eq(shell.location,"town");assert_true(shell.profile.world.home_built)
	var profile:=shell.profile;var kitchen:=shell.kitchen_view.kitchen
	# New-game spawn really is within interaction range of its own front door.
	driver.tap(KEY_E);assert_eq(shell.location,"restaurant")
	for i: int in 3:
		var point: Dictionary=shell.restaurant.interaction_points().filter(func(p:Dictionary)->bool:return p.action=="kitchen")[0]
		shell.restaurant.teleport_player(Vector2i(point.cell));driver.tap(KEY_E)
		assert_eq(shell.location,"kitchen")
		kitchen.world.get_node("Player").position=TDKitchenWorld.DOOR_POS
		driver.tap(KEY_E);assert_eq(shell.location,"restaurant")
	assert_same(shell.profile,profile);assert_same(shell.kitchen_view.kitchen,kitchen)
	assert_eq(kitchen.time_advanced.get_connections().size(),1)
	assert_false(shell.restaurant._play_row.visible)
	shell.restaurant._toggle_edit();shell.show_ledger()
	assert_false(shell.restaurant.is_processing_input(),"Ledger clicks must not paint the restaurant beneath it")
	shell._close_dialog();assert_true(shell.restaurant.is_processing_input())
	shell.restaurant._toggle_edit()

func test_market_inventory_menu_open_and_real_kitchen_delivery_three_day_save_loop() -> void:
	start()
	for day: int in range(1,4):
		shell.show_market();await get_tree().process_frame
		# Buy through the real market buttons, not an independent demonstration inventory.
		for row: Node in shell._modal_box.get_children():
			if row is HBoxContainer and row.get_child_count()==3 and row.get_child(2) is Button:
				row.get_child(2).pressed.emit()
		assert_gt(shell.profile.shop.available("tomato"),0)
		shell._close_dialog();shell.travel("restaurant");shell.show_menu()
		var open:=button("确认菜单，开门营业",shell._modal_box);assert_not_null(open);open.pressed.emit()
		assert_eq(shell.profile.shop.snapshot().phase,"OPEN")
		assert_eq(shell.travel("town").code,"SHOP_OPEN")
		assert_eq(shell.profile.buy({"egg":1000}).code,"SHOP_OPEN")
		shell.travel("kitchen");driver.kitchen=shell.kitchen_view.kitchen;driver.sent={}
		var view:=shell.kitchen_view;var kitchen:=view.kitchen
		for lane: TDCookingLane in kitchen.lanes+[kitchen.prep]: lane.beat_offset_sec=0
		kitchen.advance(1);assert_gt(view.shop.active_orders().size(),0)
		if view.shop.active_orders().is_empty(): return
		var order_id:String=view.shop.active_orders()[0].id
		view.pick_ingredient("tomato");driver.station("kitchen.board");view.choose_cut("chunk")
		driver.play(12);driver.station("kitchen.board");driver.station("kitchen.stove.left")
		view.pick_ingredient("egg");driver.station("kitchen.stove.left");driver.station("kitchen.stove.left",KEY_F)
		assert_true(kitchen.stage.visible);driver.play(70)
		assert_eq(kitchen.lanes[0].snapshot().state,"plated")
		driver.station("kitchen.stove.left");driver.station("kitchen.serve")
		assert_eq(view.shop.order(order_id).status,"SERVED")
		var paid:=view.shop.snapshot();driver.station("kitchen.serve");assert_eq(view.shop.snapshot(),paid)
		view.shop.close_early()
		for remaining: Dictionary in view.shop.active_orders(): view.shop.cancel_order(remaining.id)
		kitchen.advance(.01);assert_eq(view.shop.snapshot().phase,"SETTLED")
		assert_true(shell.save_game().ok)
		var before:Dictionary=shell.profile.snapshot()
		shell.go_title();assert_true(shell.load_game("slot-01").ok)
		assert_eq(shell.profile.shop.snapshot().day,day)
		assert_eq(JSON.parse_string(JSON.stringify(shell.profile.shop.snapshot())),JSON.parse_string(JSON.stringify(before.shop)))
		assert_eq(JSON.parse_string(JSON.stringify(shell.profile.research.snapshot())),JSON.parse_string(JSON.stringify(before.research)))
		assert_true(shell.profile.next_day().ok)
		shell.kitchen_view._make_kitchen();shell.kitchen_view.kitchen.auto_advance=false

func test_book_uses_real_kitchen_unlocks_within_slot_and_never_in_other_slot() -> void:
	start();driver.tap(KEY_B);assert_not_null(shell.atlas)
	shell.atlas.select_recipe("C03");shell.atlas.start_selected()
	assert_not_null(shell.atlas.trial)
	shell.atlas.trial.automated_clock=true
	var token:String=shell.atlas.trial.token
	assert_true(RESEARCH_DRIVER.play(shell.profile.research,token,get_tree().root))
	await get_tree().process_frame
	assert_has(shell.profile.research.snapshot().unlocked,"C03")
	shell.close_atlas();assert_true(shell.save_game().ok)
	var old:=shell.profile
	shell.go_title();assert_true(shell.create_game("slot-02").ok)
	assert_eq(shell.profile.research.snapshot().unlocked,["C01","C02"])
	assert_eq(old._research_candidate(old.research.snapshot()).code,"STALE_PROFILE")
	shell.go_title();assert_true(shell.load_game("slot-01").ok)
	assert_has(shell.profile.research.snapshot().unlocked,"C03")
	assert_true(shell.profile.shop.is_unlocked(shell.profile.world.catalog.kitchen_recipe_id(shell.profile.research.catalog.runtime_id("C03"))))

func test_pause_console_and_modal_prevent_underlay_input_and_keep_business_clock() -> void:
	start();shell.travel("restaurant");shell.start_day();shell.travel("kitchen")
	var kitchen:=shell.kitchen_view.kitchen;driver.kitchen=kitchen
	var elapsed:float=shell.profile.shop.snapshot().elapsed_sec
	driver.tap(KEY_ESCAPE);assert_true(get_tree().paused)
	kitchen.advance(5);assert_eq(shell.profile.shop.snapshot().elapsed_sec,elapsed)
	shell._close_dialog();kitchen.advance(1);assert_gt(shell.profile.shop.snapshot().elapsed_sec,elapsed)
	shell.travel("restaurant");kitchen.advance(1);assert_gt(shell.profile.shop.snapshot().elapsed_sec,elapsed+1)
	assert_eq(shell.execute_command("san 10"),"请先输入 debug。")
	shell.show_console();shell._console.text="debug";shell._console.text_submitted.emit("debug")
	assert_true(shell.debug_enabled)
	await get_tree().process_frame
	assert_same(get_viewport().gui_get_focus_owner(),shell._console)
	driver.tap(KEY_ESCAPE);assert_null(shell._modal);assert_false(get_tree().paused)
	shell.show_console();shell._console.text_submitted.emit("tools")
	assert_not_null(shell._modal);assert_null(shell._console)
	shell._close_dialog();shell.open_atlas()
	assert_eq(shell.atlas.begin_handler.call("C03").code,"SHOP_OPEN")
	var before:=shell.profile.shop.snapshot();kitchen.advance(10);assert_eq(shell.profile.shop.snapshot(),before)
	shell.close_atlas();assert_false(get_tree().paused)

func test_slot_layout_round_trip_and_old_file_explicit_import_is_read_only() -> void:
	start();assert_true(shell.profile.layout.apply_venue_style("chinese","high").ok)
	var layout:=shell.profile.layout.to_dict();assert_true(shell.save_game().ok)
	var old_shop:=TDShopStore.new(shell.legacy_shop_path,shell.profile.shop)
	assert_true(old_shop.save_game(shell.profile.shop.snapshot()).ok)
	var old_research:=TDResearchStore.new(shell.legacy_research_path,shell.profile.research.validate_save)
	assert_true(old_research.save_game(shell.profile.research.snapshot()).ok)
	var shop_bytes:=FileAccess.get_file_as_bytes(shell.legacy_shop_path)
	var research_bytes:=FileAccess.get_file_as_bytes(shell.legacy_research_path)
	shell.go_title();assert_true(shell.import_legacy().ok)
	assert_true(shell.profile.imported_legacy)
	assert_eq(FileAccess.get_file_as_bytes(shell.legacy_shop_path),shop_bytes)
	assert_eq(FileAccess.get_file_as_bytes(shell.legacy_research_path),research_bytes)
	assert_eq(shell.import_legacy().code,"ALREADY_IMPORTED")
	shell.go_title();assert_true(shell.load_game("slot-01").ok)
	assert_eq(JSON.stringify(shell.profile.layout.to_dict()),JSON.stringify(layout))

func test_settings_and_debug_are_separate_from_profile_and_stale_callbacks_rejected() -> void:
	assert_true(shell.preferences.change(.35,false).ok)
	assert_almost_eq(float(TDPlayerPreferences.new(shell.preferences_path).values.volume),.35,.0001)
	assert_false(shell.preferences.change(-1,false).ok)
	start();var bytes:=FileAccess.get_file_as_bytes(shell.slots.path_for("slot-01"))
	shell.show_settings();assert_not_null(shell._modal)
	assert_eq(FileAccess.get_file_as_bytes(shell.slots.path_for("slot-01")),bytes)
	shell._close_dialog();shell.show_console();shell._console.text_submitted.emit("debug")
	shell._console.text_submitted.emit("tools")
	button("厨房",shell._modal_box).pressed.emit()
	assert_null(shell.profile);assert_not_null(app.full_kitchen)
	var saved_bytes:=FileAccess.get_file_as_bytes(shell.slots.path_for("slot-01"))
	app.full_kitchen.advance(10)
	assert_eq(FileAccess.get_file_as_bytes(shell.slots.path_for("slot-01")),saved_bytes)
	app.return_to_menu()
