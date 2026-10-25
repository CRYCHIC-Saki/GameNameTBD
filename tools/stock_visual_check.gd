extends SceneTree
## GPU/layout probe with isolated saves and generated input; not human playtesting.
var app: TDApplication
var shell: TDGameShell
var captures: int=0
var failures: Array[String]=[]

func _initialize() -> void: call_deferred("run")

func capture(id: String) -> void:
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png("res://artifacts/stock-"+id+".png")!=OK: failures.append("capture:"+id)
	captures+=1

func run() -> void:
	root.size=Vector2i(1280,800)
	app=load("res://src/app/main.tscn").instantiate()
	app.settings_path="res://artifacts/stock-visual/%d/settings.json"%Time.get_ticks_usec()
	root.add_child(app);shell=app.game_shell;shell.automatic_time=false
	if not shell.create_game("slot-01","库存检查").ok: push_error("stock visual create failed");quit(1);return
	shell.show_market();await capture("market");shell._close_dialog()
	var factories: Array=shell.profile.world.town_map.plots.filter(func(p:Dictionary)->bool:return p.get("supply")=="seasoning")
	if not factories.is_empty():
		shell.profile.world_transaction(shell.profile.world.build_factory.bind(factories[0].id),"建厂")
		shell.town._open_factory_panel(shell.profile.world._plot_by_id(factories[0].id));await capture("factory");shell.town._close_factory_panel()
	if not shell.profile.buy({"tomato":3000,"egg":3000,"oil":1000,"starch":1000,"salt":30,"sugar":1000}).ok: failures.append("purchase")
	shell.travel("restaurant");shell.start_day();shell.travel("kitchen")
	var view:=shell.kitchen_view;var kitchen:=view.kitchen
	var driver=load("res://tools/test_support/kitchen_input.gd").new();driver.viewport=root;driver.kitchen=kitchen
	for lane: TDCookingLane in kitchen.lanes+[kitchen.prep]: lane.beat_offset_sec=0
	driver.station("kitchen.fridge");await capture("fridge");view._close_popup()
	view.pick_ingredient("tomato");driver.station("kitchen.board");view.choose_cut("chunk");driver.play(12);driver.station("kitchen.board");driver.station("kitchen.stove.left")
	view.pick_ingredient("egg");driver.station("kitchen.stove.left");driver.station("kitchen.stove.left",KEY_F)
	var seen: bool=false
	for step: int in 1800:
		driver.play(.05)
		if kitchen.lanes[0].progress.get("pc_module")=="M6" and kitchen.lanes[0].qte!=null:
			seen=true;await capture("seasoning");break
	if not seen: failures.append("no-seasoning-stage")
	for step: int in 200:
		driver.play(.025)
		if view.shop.available("salt")==0:
			var actions: Array=kitchen.lanes[0].progress.get("actual_actions",[]).duplicate(true)
			driver.click(kitchen.stage.spice_rect(0,"salt").get_center())
			if kitchen.lanes[0].progress.get("actual_actions",[])!=actions or view.shop.available("salt")!=0: failures.append("empty-spice-click")
			await capture("empty-spice");break
	if view.shop.available("salt")!=0: failures.append("salt-not-consumed")
	# A second isolated profile: replenishment remains forbidden while business is open.
	shell.go_title();await process_frame;await process_frame
	if not shell.create_game("slot-02","自动制作检查").ok: failures.append("create-second")
	shell.profile.buy({"tomato":3000,"egg":3000,"oil":1000,"starch":1000,"salt":1000,"sugar":1000,"soy_sauce":1000})
	shell.travel("restaurant");shell.start_day();shell.travel("kitchen")
	view=shell.kitchen_view;kitchen=view.kitchen;driver.kitchen=kitchen;driver.sent={}
	# Explicit mastery precondition for inspecting the real stove action (not evidence of manual mastery).
	for i: int in 4:
		view.shop.observe_mastery({"session_id":view.shop.day_namespace()+"visual","recipe_id":"service.tomato_egg","dish_id":"visual-%d"%i,"state":"plated","missing_required":[],"performance_score":100.0})
	kitchen.close_bench()
	for ingredient: String in ["tomato","egg"]: view.pick_ingredient(ingredient);driver.station("kitchen.stove.right")
	driver.station("kitchen.stove.right",KEY_F);await capture("automatic-choice")
	for button: Button in view._popup.find_children("*","Button",true,false):
		if button.text=="自动制作": driver.click(button.get_global_rect().get_center());break
	if not kitchen.lanes[1].automatic: failures.append("automatic-button")
	kitchen.advance(4);kitchen.open_station_view("kitchen.stove.right");await capture("automatic-progress")
	kitchen.close_bench();await capture("kitchen-progress")
	shell.go_title();app.queue_free();await process_frame;await process_frame
	print("STOCK_VISUAL success=%s captures=%d failures=%s; physical_input=NOT_RUN human_playtest=PENDING"%[failures.is_empty(),captures,str(failures)])
	quit(0 if failures.is_empty() else 1)
