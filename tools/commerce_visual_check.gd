extends SceneTree
var app: TDApplication
var shell: TDGameShell
var captures: int=0
var failures: Array[String]=[]

func _initialize() -> void: call_deferred("run")

func capture(id: String) -> void:
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png("res://artifacts/commerce-"+id+".png")!=OK: failures.append("capture:"+id)
	captures+=1

func run() -> void:
	root.size=Vector2i(1280,800)
	app=load("res://src/app/main.tscn").instantiate()
	app.settings_path="res://artifacts/commerce-visual/%d/settings.json"%Time.get_ticks_usec()
	root.add_child(app);shell=app.game_shell;shell.automatic_time=false
	if not shell.create_game("slot-01","杏花食堂").ok:
		push_error("Commerce visual: creation failed");quit(1);return
	shell.show_market();await capture("market")
	shell.show_supplier();await capture("routes")
	if not shell.profile.recommend_route("paris","visual:story-hook:paris").ok: failures.append("story-interface")
	shell.show_remote_market("paris");await capture("remote")
	shell._close_dialog()
	var banks:=shell.profile.world.town_map.plots.filter(func(p:Dictionary)->bool:return p.kind=="bank")
	if banks.is_empty(): failures.append("bank-place")
	else:
		var driver=load("res://tools/test_support/kitchen_input.gd").new();driver.viewport=root
		shell.town._player.position=shell.town._origin()+Vector2(int(banks[0].approach_x)+.5,int(banks[0].approach_y)+.5)*TDTownWorld.CELL
		driver.tap(KEY_E);await capture("bank")
		if shell._modal_box==null or shell._modal_box.find_child("BankAmount",true,false)==null: failures.append("bank-interaction")
		else:
			for control: Button in shell._modal_box.find_children("*","Button",true,false):
				if control.text=="存入": control.pressed.emit();break
			if int(shell.profile.commerce.society.bank.account("player").deposit_cents)!=10000: failures.append("bank-deposit")
			await capture("bank-deposit")
	shell._close_dialog();shell.travel("restaurant");shell.show_menu();await capture("menu")
	shell._close_dialog()
	if not shell.profile.buy({"tomato":6000,"egg":6000,"oil":2000,"salt":1000,"sugar":1000,"starch":1000}).ok: failures.append("buy")
	if not shell.start_day().ok: failures.append("open")
	shell.travel("kitchen");shell.kitchen_view.kitchen.advance(91);await capture("orders")
	shell.profile.shop.close_early()
	for order: Dictionary in shell.profile.shop.active_orders(): shell.profile.shop.cancel_order(order.id)
	shell.kitchen_view.kitchen.advance(.01)
	shell.travel("restaurant");shell.show_ledger();await capture("ledger")
	if not shell.save_game().ok: failures.append("save")
	shell.go_title()
	if not shell.load_game("slot-01").ok: failures.append("load")
	shell.show_ledger();await capture("restored-ledger")
	# Background competition is advanced through real day boundaries; no synthetic profit.
	for day: int in 84:
		if shell.profile.shop.snapshot().phase=="SETTLED": shell.profile.next_day()
		shell.profile.shop.open_day();shell.profile.shop.close_early()
		var firms: Array=shell.profile.commerce.state.competitors[shell.profile.commerce.state.home]
		if firms.size()>3:
			shell.profile.sync_commercial_map();shell.profile.world.map_revision+=1
			shell._close_dialog();shell.travel("town");await process_frame;await process_frame
			var parcel: Dictionary=shell.profile.world._plot_by_id(firms.back().parcel_id)
			shell.town._player.position=shell.town._origin()+Vector2(int(parcel.approach_x)+.5,int(parcel.approach_y)+.5)*TDTownWorld.CELL
			await capture("expansion-street")
			var inspector=load("res://tools/test_support/kitchen_input.gd").new();inspector.viewport=root;inspector.tap(KEY_E)
			if shell._modal==null: failures.append("competitor-interaction")
			await capture("expansion-notice")
			break
	if shell.profile.commerce.state.competitors[shell.profile.commerce.state.home].size()<=3: failures.append("no-autonomous-local-expansion")
	shell.go_title();app.queue_free();await process_frame;await process_frame
	print("COMMERCE_VISUAL success=%s captures=%d failures=%s; physical_input=NOT_RUN human_playtest=PENDING"%[failures.is_empty(),captures,str(failures)])
	quit(0 if failures.is_empty() else 1)
