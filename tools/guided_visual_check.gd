extends SceneTree
## Real rendered production scenes and Viewport input. No physical-device claim.
var app: TDApplication
var kitchen: TDFullKitchen
var sent: Dictionary={}
var captured: Dictionary={}

func _initialize() -> void: call_deferred("_run")
func capture(id: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var error: Error=root.get_texture().get_image().save_png("res://artifacts/d016-"+id+".png")
	if error!=OK: push_error("Capture failed"); quit(1); return
	captured[id]=true
func key(code: Key,pressed: bool=true) -> void:
	var e:=InputEventKey.new(); e.keycode=code; e.physical_keycode=code; e.pressed=pressed; root.push_input(e,true)
func tap(code: Key) -> void: key(code); key(code,false)
func station(id: String) -> void:
	for entry: Dictionary in TDKitchenWorld.STATIONS:
		if entry.id==id: (kitchen.world.get_node("Player") as TDKitchenPlayer).position=entry.position+Vector2(0,40); (kitchen.world.get_node("Player") as TDKitchenPlayer).face(Vector2.UP); tap(KEY_E); return
func click(at: Vector2) -> void:
	var motion:=InputEventMouseMotion.new(); motion.position=at; motion.global_position=at; root.push_input(motion,true)
	for down: bool in [true,false]:
		var e:=InputEventMouseButton.new(); e.position=at; e.global_position=at; e.button_index=MOUSE_BUTTON_LEFT; e.pressed=down; root.push_input(e,true)
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
			var token: String=str(p.operation_id); var kind: String=p.qte_kind
			if kind in ["rhythm","sequence"]:
				for index: int in p.beat_times_sec.size():
					var marker: String=token+":"+str(index)
					if sent.has(marker) or float(p.elapsed_sec)+.000001<float(p.beat_times_sec[index]): continue
					sent[marker]=true
					var action: String=str(p.cut_actions[index]) if kind=="rhythm" and not p.get("cut_actions",[]).is_empty() else ("primary" if kind=="rhythm" else str(p.sequence[index]))
					if action.begins_with("spice:"): click(kitchen.stage.spice_rect(lane.lane_index,action.trim_prefix("spice:")).get_center())
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
func prepare(stove: String) -> void:
	station("kitchen.supply.tomato"); station("kitchen.board"); await play(8)
	station("kitchen.board"); station(stove); station("kitchen.supply.egg"); station(stove)
func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://artifacts/test-storage")
	app=load("res://src/app/main.tscn").instantiate() as TDApplication
	app.settings_path="res://artifacts/test-storage/guided-visual.json"; root.add_child(app); app.enter_full_kitchen()
	kitchen=app.full_kitchen; kitchen.auto_advance=false
	for lane: TDCookingLane in kitchen.lanes+[kitchen.prep]: lane.beat_offset_sec=0
	# Capture genuine Good and wrong-key feedback through the same Viewport path.
	station("kitchen.supply.tomato"); station("kitchen.board")
	for i: int in 200:
		kitchen.advance(.025)
		if kitchen.prep.qte!=null: break
	kitchen.advance(1.925-float(kitchen.prep.progress.elapsed_sec)); tap(KEY_SPACE); await capture("feedback-good")
	kitchen.advance(3-float(kitchen.prep.progress.elapsed_sec)); tap(KEY_A); await capture("feedback-miss")
	app.return_to_menu(); await process_frame; app.enter_full_kitchen(); kitchen=app.full_kitchen; kitchen.auto_advance=false; sent.clear()
	for lane: TDCookingLane in kitchen.lanes+[kitchen.prep]: lane.beat_offset_sec=0
	await capture("world")
	await prepare("kitchen.stove.left"); station("kitchen.stove.left"); await play(58)
	station("kitchen.stove.left"); station("kitchen.serve"); await capture("feedback")
	var delivered: bool=kitchen.lanes[0].snapshot().state=="delivered"
	tap(KEY_E)
	await prepare("kitchen.stove.left"); await prepare("kitchen.stove.right")
	station("kitchen.stove.left"); tap(KEY_E); station("kitchen.stove.right"); await play(20)
	await capture("dual-temperature")
	app.return_to_menu(); await process_frame; app.enter_full_kitchen(); kitchen=app.full_kitchen; kitchen.auto_advance=false; sent.clear()
	await prepare("kitchen.steamer"); station("kitchen.steamer"); await play(29)
	station("kitchen.supply.beef"); station("kitchen.stove.left"); station("kitchen.stove.left"); await play(7); await capture("simmer"); tap(KEY_E); kitchen.advance(1); await capture("simmer-world")
	station("kitchen.supply.tomato"); station("kitchen.board"); kitchen.advance(2.5); await capture("simmer-while-cutting")
	var file:=FileAccess.open("res://artifacts/d016-visual.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"captures":captured.keys(),"renderer":RenderingServer.get_video_adapter_name(),"delivered":delivered,"physical_input":"NOT_RUN","playtest":"PENDING"},"\t")); file.close()
	app.return_to_menu(); app.queue_free(); await process_frame; await process_frame; await create_timer(.05).timeout
	print("GUIDED_VISUAL captures=",captured.size()," delivered=",delivered)
	quit(0 if delivered else 1)
