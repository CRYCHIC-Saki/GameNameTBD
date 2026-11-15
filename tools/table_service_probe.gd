extends SceneTree
## Real main scene and InputEvents, isolated save slot, Compatibility renderer.
const OUT: String="res://artifacts/table-service-20261111/gpu"
const DRIVER=preload("res://tools/test_support/kitchen_input.gd")
var checks: int=0
var failed: bool=false
var captures: int=0
var app: TDApplication
var shell: TDGameShell
var driver: RefCounted

func _initialize() -> void: call_deferred("run")
func check(value: bool, note: String) -> void:
	checks+=1;print("TABLE_SERVICE_CHECK ",checks," ","PASS " if value else "FAIL ",note)
	if not value: failed=true
func shot(name: String) -> void:
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var pixels:=root.get_texture().get_image()
	check(pixels.get_width()>=1200,"actual viewport image "+name)
	check(pixels.save_png(OUT+"/"+name+".png")==OK,"capture "+name);captures+=1

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	root.size=Vector2i(1280,800)
	app=load("res://src/app/main.tscn").instantiate()
	app.settings_path=OUT+"/slot-%d/settings.json"%Time.get_ticks_usec();root.add_child(app)
	shell=app.game_shell;shell.automatic_time=false
	check(shell.create_game("slot-01","送餐验证").ok,"isolated new slot through main scene")
	shell.guide.dialogue.finish_now()
	shell.profile.story.beat="awaken";shell._apply_story(shell.profile.story.complete_scene("awaken"))
	shell.profile.story.tutorials.assign(["M1","M2","M3","M4","M5","M6","M7"])
	check(shell.profile.shop.table_service_enabled,"production shell uses physical service")
	shell.travel("restaurant")
	var room:=shell.restaurant
	for pair: Array in [["world_right",Vector2.RIGHT],["world_left",Vector2.LEFT],["world_up",Vector2.UP],["world_down",Vector2.DOWN],["world_right+world_down",Vector2(1,1).normalized()]]:
		room.teleport_player(Vector2i(6,8));await physics_frame;await physics_frame
		for action: String in str(pair[0]).split("+"): Input.action_press(action)
		await physics_frame;await physics_frame
		var before:=room.player_position()/64.0
		await physics_frame
		var after:=room.player_position()/64.0
		for action: String in str(pair[0]).split("+"): Input.action_release(action)
		var delta:=TDRestaurantIsoView.project(after.x,after.y)-TDRestaurantIsoView.project(before.x,before.y)
		check(delta.normalized().dot(pair[1])>.999,"screen axis "+str(pair[0]))
		check(absf(delta.length()-3.0)<.08,"constant visible movement speed")
	await shot("01-movement")
	shell.travel("kitchen")
	var view:=shell.kitchen_view;var kitchen:=view.kitchen
	driver=DRIVER.new();driver.kitchen=kitchen;driver.viewport=root
	for lane: TDCookingLane in kitchen.lanes+[kitchen.prep]: lane.beat_offset_sec=0
	var money:=int(view.shop.snapshot().money_cents)
	check(view.pick_ingredient("tomato").ok,"real tutorial tomato")
	driver.station("kitchen.board");check(view.choose_cut("chunk").ok,"real cutting sheet")
	driver.play(12);driver.station("kitchen.board");driver.station("kitchen.stove.left")
	check(view.pick_ingredient("egg").ok,"real tutorial egg")
	driver.station("kitchen.stove.left");driver.station("kitchen.stove.left",KEY_F)
	check(kitchen.stage.visible,"real cooking UI")
	driver.play(70);check(kitchen.lanes[0].snapshot().state=="plated","real input produced finished dish")
	driver.station("kitchen.stove.left");driver.station("kitchen.serve")
	check(view.shop.table_service.rows().size()==1,"kitchen deposits real dish")
	check(shell.profile.story.score==-1,"pass is not delivery")
	check(shell.save_game().code=="PASS_NOT_CLEAR","cannot silently lose unserved food on save")
	await shot("02-kitchen-pass")
	shell.travel("restaurant");room._sync_business_guests()
	room.teleport_player(room.service_window_cell())
	await shot("03-pass-before-pickup")
	driver.tap(KEY_E)
	check(room._plate_order!="","real E takes plate")
	check(shell.guide.objective().target=="trial","quest now points to Aling")
	check(room._hatch_plate_count()==0,"claimed plate no longer drawn at hatch")
	await shot("04-carrying")
	var guest:=room._guest_by_ticket(TDTableService.TRIAL_ORDER)
	check(guest!=null,"Aling has an actual reachable table")
	if guest!=null:
		room.teleport_player(room._beside_seat(guest.seat_id));await shot("05-table-handoff")
		driver.tap(KEY_E)
		check(view.shop.table_service.empty(),"plate handed to tutorial customer")
		check(shell.profile.story.score>=0 and shell.profile.story.beat=="verdict","story advances only at table")
		check(view.shop.snapshot().money_cents==money,"tutorial never invents ordinary sales")
	await shot("06-received")
	shell.go_title();app.queue_free();await process_frame;await process_frame
	print("TABLE_SERVICE_PROBE success=",not failed," checks=",checks," captures=",captures)
	quit(1 if failed else 0)
