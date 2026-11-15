extends SceneTree
## Production main/Shell, roster and cooking rules; only time and profile are isolated fixtures.
const OUT: String="res://artifacts/chef-workflow-20261114/gpu"
var checks: int=0
var failures: int=0
var events: Array=[]
var captures: Dictionary={}
func _initialize() -> void: call_deferred("run")
func verify(value: bool, description: String) -> void:
	checks+=1
	if not value: failures+=1;printerr("FAIL ",description)
	else: print("PASS ",description)
func capture(label: String) -> void:
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	verify(root.get_texture().get_image().save_png(OUT.path_join(label+".png"))==OK,"screenshot "+label)
	captures[label]=true
func resume_focus_pause(shell: TDGameShell) -> void:
	# Windows can move focus while a capture is shown. Exercise the normal resume path.
	if root.get_tree().paused and shell._modal!=null:
		var before:=shell.kitchen_view.staff.rows()
		shell.kitchen_view.kitchen.advance(1)
		verify(shell.kitchen_view.staff.rows()==before,"OS focus pause freezes employee")
		shell._close_dialog()
		verify(not root.get_tree().paused,"resume from actual pause menu")
func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT));root.size=Vector2i(1280,800)
	var app:=load("res://src/app/main.tscn").instantiate() as TDApplication
	app.settings_path=OUT.path_join("slots-%d/settings.json"%Time.get_ticks_usec());root.add_child(app)
	var shell:=app.game_shell;shell.automatic_time=false
	verify(shell.create_game("slot-01","厨师验证").ok,"main scene isolated profile")
	shell.guide.dialogue.finish_now();shell.profile.story.beat="done"
	shell.profile.story.tutorials.assign(["M1","M2","M3","M4","M5","M6","M7"])
	shell.town.external_story_frozen=false;shell.restaurant.story_frozen=false
	var shop:=shell.profile.shop;shop.commerce=null
	verify(shop.world_adjustment(500000,"probe-funds","isolated fixture").ok,"fixture funding")
	var offer: Dictionary=shell.profile.employees.market_rows("chengdu","cook")[0]
	verify(shell.profile.employees.sign_employee(offer.id,"probe-hire",offer.offer_key).ok,"actual roster signed")
	verify(shell.profile.employees.assign(offer.id,"player_diner").ok,"actual roster assigned")
	var waiter: Dictionary=shell.profile.employees.market_rows("chengdu","waiter")[0]
	verify(shell.profile.employees.sign_employee(waiter.id,"probe-waiter",waiter.offer_key).ok,"actual waiter signed before opening")
	verify(shell.profile.employees.assign(waiter.id,"player_diner").ok,"actual waiter assigned before opening")
	var cart: Dictionary=shop.offer("service.tomato_egg").stock
	verify(shop.buy(cart,"probe-stock").ok,"real stock purchase")
	for id: String in shop.snapshot().menu: shop.set_menu(id,id=="service.tomato_egg",1200)
	verify(shop.open_day().ok,"real day open")
	shell.travel("kitchen");var view:=shell.kitchen_view;view.set_paused(false)
	for lane: TDCookingLane in view.kitchen.lanes+[view.kitchen.prep]: lane.beat_offset_sec=0
	view.staff.action_completed.connect(func(event:Dictionary)->void:events.append(event.duplicate(true)))
	await process_frame;await process_frame
	view.set_paused(false)
	view.kitchen.advance(1);shop._next_arrival=350
	var stock: Dictionary=shop.snapshot().inventory;var money: int=shop.snapshot().money_cents
	for i: int in 700:
		resume_focus_pause(shell)
		view.kitchen.advance(.2);view.kitchen.world._sync_staff()
		var job:=view.staff.job_for(offer.id)
		if not job.is_empty():
			var phase:=str(job.phase);var ingredient_at:=int(job.ingredient_at)
			var label: String=""
			if phase=="to_fridge" and ingredient_at==0: label="01-fridge-walk"
			elif phase=="cut": label="02-real-cutting"
			elif phase=="to_fridge" and ingredient_at==1: label="03-return-for-egg"
			elif phase=="cook": label="04-real-stove"
			elif phase=="to_pass": label="05-carry-to-pass"
			if label!="" and not captures.has(label):
				verify(view.kitchen.world.get_node("Cook0") is TDKitchenStaffActor,"visible real employee "+phase)
				await capture(label)
				if phase=="cut":
					var before:=view.staff.rows();view.set_paused(true);view.kitchen.advance(3)
					verify(view.staff.rows()==before,"narrative pause freezes actor and actual food")
					view.set_paused(false)
		if events.any(func(e:Dictionary)->bool:return e.action=="dish_deposited"): break
	verify(events.map(func(e:Dictionary)->String:return e.action+":"+e.ingredient)==[
		"picked:tomato","cut_started:tomato","cut_finished:tomato","ingredient_deposited:tomato",
		"picked:egg","ingredient_deposited:egg","cook_started:","dish_picked:","dish_deposited:"],"physical tomato egg chronology")
	if events.size()!=9: print("DIAGNOSTIC ",JSON.stringify({"events":events,"jobs":view.staff.rows(),"paused":view.kitchen.shared_clock.paused,"story":shell.profile.story.beat,"talk":shell.guide.presenting(),"stock":shop.snapshot().inventory,"orders":shop.snapshot().orders}))
	verify(shop.table_service.rows().size()==1,"real dish only at pass")
	verify(shop.snapshot().money_cents==money,"no sale before actual table handoff")
	verify(shop.available("tomato")==int(stock.tomato)-1000 and shop.available("egg")==int(stock.egg)-1000,"consume each ingredient once")
	await capture("06-pass-arrival")
	shell.travel("restaurant")
	for i: int in 250:
		resume_focus_pause(shell)
		view.kitchen.advance(.2)
		if shop.table_service.empty(): break
	verify(shop.table_service.empty(),"real waiter picked up and delivered plate")
	verify(shop.snapshot().money_cents>money,"real table service earns sale")
	await capture("07-restaurant-served")
	shell.go_title();app.queue_free();await process_frame;await process_frame
	var report:=FileAccess.open(OUT.path_join("report.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures,"captures":captures.keys(),"events":events},"\t"));report.close()
	print("CHEF_GPU checks=",checks," failures=",failures," captures=",captures.size())
	quit(0 if failures==0 else 1)
