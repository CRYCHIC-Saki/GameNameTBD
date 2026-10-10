extends SceneTree
var app: TDApplication
var view: TDShopView
var kitchen: TDFullKitchen
var sent: Dictionary={}
var captured: Dictionary={}
func _initialize() -> void: call_deferred("_run")
func capture(id: String) -> void:
	await process_frame; await RenderingServer.frame_post_draw
	var error: Error=root.get_texture().get_image().save_png("res://artifacts/d020-"+id+".png")
	if error!=OK: push_error("Capture failed"); quit(1); return
	captured[id]=true
func key(code: Key,pressed: bool=true) -> void:
	var e:=InputEventKey.new(); e.keycode=code; e.physical_keycode=code; e.pressed=pressed; root.push_input(e,true)
func tap(code: Key) -> void: key(code); key(code,false)
func station(id: String, button: Key=KEY_E) -> void:
	for entry: Dictionary in kitchen.world.stations():
		if entry.id==id: (kitchen.world.get_node("Player") as TDKitchenPlayer).position=entry.position+Vector2(0,40); tap(button); return
func click(at: Vector2) -> void:
	var motion:=InputEventMouseMotion.new(); motion.position=at; motion.global_position=at; root.push_input(motion,true)
	for down: bool in [true,false]:
		var e:=InputEventMouseButton.new(); e.position=at; e.global_position=at; e.button_index=MOUSE_BUTTON_LEFT; e.pressed=down; root.push_input(e,true)
func hold_mouse(at: Vector2,pressed: bool) -> void:
	var event:=InputEventMouseButton.new(); event.position=at; event.global_position=at; event.button_index=MOUSE_BUTTON_LEFT; event.pressed=pressed; root.push_input(event,true)

func play(seconds: float) -> void:
	for frame: int in int(seconds/.025):
		kitchen.advance(.025)
		if not kitchen.stage.visible: continue
		for lane: TDCookingLane in kitchen.stage.lanes.duplicate():
			if lane.qte==null: continue
			var p: Dictionary=lane.progress.duplicate(true)
			var module: String=p.pc_module
			var id: String=module+"-"+str(p.kind)
			if lane.thermal_qte!=null: id+="-temperature"
			if kitchen.stage.lanes.size()==2: id="dual"
			if not captured.has(id) and float(p.elapsed_sec)>.2: await capture(id)
			if module=="M3" and not captured.has("paused"):
				app.toggle_pause(); await capture("paused"); app.toggle_pause()
			if module=="M6" and int(p.get("hold_index",-1))>=0 and float(p.get("note_held_sec",0))>.2 and not captured.has("M6-holding"): await capture("M6-holding")
			if module=="M6":
				var phase: String=TDGuidedCookingView.season_prompt(p).phase
				if not captured.has("season-"+phase): await capture("season-"+phase)
				if p.get("free_seasoning",false):
					if not captured.has("free-seasoning"): await capture("free-seasoning")
					var done: int=p.actual_actions.size()
					if int(p.hold_index)>=0 and float(p.note_held_sec)+.000001>=.5+done*.25:
						hold_mouse(kitchen.stage.spice_rect(lane.lane_index,str(p.hold_action).trim_prefix("spice:")).get_center(),false)
					elif int(p.hold_index)<0 and done<2 and float(p.elapsed_sec)>.5+done*2:
						hold_mouse(kitchen.stage.spice_rect(lane.lane_index,"sugar" if done==0 else "salt").get_center(),true)
					continue
			var token: String=str(p.operation_id); var kind: String=p.qte_kind
			if p.has("hold_durations_sec") and int(p.hold_index)>=0 and float(p.note_held_sec)+.000001>=float(p.hold_durations_sec[int(p.hold_index)]):
				hold_mouse(kitchen.stage.spice_rect(lane.lane_index,str(p.hold_action).trim_prefix("spice:")).get_center(),false)
			if kind in ["rhythm","sequence"]:
				for index: int in p.beat_times_sec.size():
					var marker: String=token+":"+str(index)
					if sent.has(marker) or float(p.elapsed_sec)+.000001<float(p.beat_times_sec[index]): continue
					sent[marker]=true
					var action: String=str(p.cut_actions[index]) if kind=="rhythm" and not p.get("cut_actions",[]).is_empty() else ("primary" if kind=="rhythm" else str(p.sequence[index]))
					if action.begins_with("spice:"):
						var at: Vector2=kitchen.stage.spice_rect(lane.lane_index,action.trim_prefix("spice:")).get_center()
						if p.has("hold_durations_sec"): hold_mouse(at,true)
						else: click(at)
					else:
						var codes: Dictionary={"primary":KEY_SPACE,"rotate_left":KEY_A,"rotate_right":KEY_D,"up":KEY_W,"left":KEY_A,"down":KEY_S,"right":KEY_D} if lane.lane_index!=1 else {"primary":KEY_SPACE,"up":KEY_UP,"left":KEY_LEFT,"down":KEY_DOWN,"right":KEY_RIGHT}
						tap(codes[action])
			elif kind=="window" and not sent.has(token) and float(p.elapsed_sec)+.000001>=float(p.target_sec): sent[token]=true; tap(KEY_SPACE)
			elif kind=="charge":
				if not sent.has(token) and float(p.get("preview_remaining_sec",0))<=.000001: sent[token]=true; key(KEY_SPACE)
				elif float(p.held_sec)+.000001>=(float(p.target_min_sec)+float(p.target_max_sec))*.5: key(KEY_SPACE,false)
				if module=="M7" and float(p.held_sec)>1 and not captured.has("M7-holding"): await capture("M7-holding")
			if lane.feedback_remaining()>.8:
				var feedback_id: String="feedback-"+str(lane.judgement_feedback.grade)
				if not captured.has(feedback_id): await capture(feedback_id)
				if module=="M1" and lane.judgement_feedback.get("action")=="rotate_right" and not captured.has("cut-turn"): await capture("cut-turn")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://artifacts/test-storage")
	app=load("res://src/app/main.tscn").instantiate() as TDApplication
	app.settings_path="res://artifacts/test-storage/shop-visual-settings.json"
	app.shop_save_path="res://artifacts/test-storage/shop-visual-%d.json" % Time.get_ticks_usec()
	root.add_child(app); await capture("menu"); app.enter_shop(); view=app.shop_view; kitchen=view.kitchen; kitchen.auto_advance=false
	await capture("planning")
	for i: int in 3: view.buy_kit("service.tomato_egg",false)
	view.buy_kit("service.beef_noodles"); view.buy_kit("service.qiguoji")
	await capture("purchased")
	view.open_day(); kitchen=view.kitchen; kitchen.auto_advance=false
	for lane: TDCookingLane in kitchen.lanes+[kitchen.prep]: lane.beat_offset_sec=0
	kitchen.advance(100); var order_id: String=view.shop.active_orders()[0].id
	await capture("three-orders")
	view.pick_ingredient("beef"); station("kitchen.board"); await capture("cut-choices"); view.choose_cut("dice"); await play(12)
	station("kitchen.board"); station("kitchen.stove.left"); await capture("pot-contents")
	station("kitchen.stove.left",KEY_Q); await capture("retrieve"); var beef_id: String=kitchen.lanes[0].snapshot().ingredients.keys()[0]
	view.take_pot_ingredient(0,beef_id); view._close_popup(); station("kitchen.fridge")
	station("kitchen.fridge"); await capture("cold-storage"); view._close_popup()
	station("kitchen.fridge"); await capture("pantry")
	view.pick_ingredient("tomato"); view._close_popup(); station("kitchen.board"); view.choose_cut("chunk"); await play(12)
	station("kitchen.board"); station("kitchen.stove.left")
	station("kitchen.fridge"); view.pick_ingredient("egg"); view._close_popup(); station("kitchen.stove.left")
	station("kitchen.stove.left",KEY_F); await play(62)
	station("kitchen.stove.left"); station("kitchen.serve"); await capture("delivered")
	var delivered: bool=view.shop.order(order_id).status=="SERVED"
	view.shop.close_early(); for order: Dictionary in view.shop.active_orders(): view.cancel_order(order.id)
	kitchen.advance(.01); view.refresh(true); await capture("day-end")
	var plan:=view.save_order_plan(order_id,"小店招牌炒蛋"); var saved:=view.save_boundary()
	view._show_ledger(); await capture("ledger"); view._close_popup()
	app.return_to_menu(); await process_frame; app.enter_shop(true); view=app.shop_view; kitchen=view.kitchen; kitchen.auto_advance=false
	await capture("continued")
	var focus_paused: bool=paused
	if paused: app.toggle_pause()
	view.next_day(); await capture("next-day")
	var continued: bool=view.shop.snapshot().day==2 and view.shop.snapshot().phase=="PREPARE"
	view.open_day(); kitchen=view.kitchen; kitchen.auto_advance=false
	for food: String in ["chicken","mushroom"]: view.pick_ingredient(food); station("kitchen.steamer")
	station("kitchen.steamer",KEY_F); await play(40); await capture("steamed-unlocked")
	var unlocked: bool=view.shop.is_unlocked("service.qiguoji")
	view.pick_stored(beef_id); station("kitchen.stove.left"); station("kitchen.stove.left",KEY_F); await play(85)
	await capture("failed-dish"); var failed: bool=kitchen.lanes[0].snapshot().get("failed_dish",false) and kitchen.lanes[0].snapshot().state=="plated"
	station("kitchen.stove.left"); station("kitchen.trash"); await capture("trash-cleared")
	var cleared: bool=kitchen.lanes[0].snapshot().ingredients.is_empty() and kitchen.handling.hand==null
	var report: Dictionary={"captures":captured.keys(),"continued":continued,"unlocked":unlocked,"failed":failed,"trash_cleared":cleared,"delivered":delivered,"custom_saved":plan.ok,"saved":saved.ok,"continued_day":view.shop.snapshot().day,"continued_phase":view.shop.snapshot().phase,"focus_pause_resumed":focus_paused,"last_code":view.last_result.code,"renderer":RenderingServer.get_video_adapter_name(),"physical_input":"NOT_RUN","playtest":"PENDING"}
	var file:=FileAccess.open("res://artifacts/d020-visual.json",FileAccess.WRITE); file.store_string(JSON.stringify(report,"\t")); file.close()
	print("SHOP_VISUAL ",JSON.stringify(report))
	var passed: bool=delivered and plan.ok and saved.ok and continued and unlocked and failed and cleared
	app.return_to_menu(); app.queue_free(); await process_frame; await process_frame
	quit(0 if passed else 1)
