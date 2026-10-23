extends GutTest
const APP:=preload("res://src/app/main.tscn")
var app: TDApplication
var kitchen: TDFullKitchen
var layer: CanvasLayer
var sent: Dictionary

func before_each() -> void:
	DirAccess.make_dir_recursive_absolute("res://artifacts/test-storage")
	layer=CanvasLayer.new(); layer.layer=129; autofree(layer); get_tree().root.add_child(layer)
	app=APP.instantiate() as TDApplication; app.settings_path="res://artifacts/test-storage/guided.json"; layer.add_child(app)
	app.enter_full_kitchen(); kitchen=app.full_kitchen; kitchen.auto_advance=false; sent={}
	for lane: TDCookingLane in kitchen.lanes+[kitchen.prep]: lane.beat_offset_sec=0
	await get_tree().process_frame
func after_each() -> void:
	get_tree().paused=false; app.return_to_menu(); await get_tree().process_frame; await get_tree().process_frame
func key(code: Key,pressed: bool=true) -> void:
	var e:=InputEventKey.new(); e.keycode=code; e.physical_keycode=code; e.pressed=pressed; get_tree().root.push_input(e,true)
func tap(code: Key) -> void: key(code); key(code,false)
func station(id: String) -> void:
	for entry: Dictionary in TDKitchenWorld.STATIONS:
		if entry.id==id: (kitchen.world.get_node("Player") as TDKitchenPlayer).position=entry.position+Vector2(0,40); tap(KEY_E); return
func click(at: Vector2) -> void:
	var motion:=InputEventMouseMotion.new(); motion.position=at; motion.global_position=at; get_tree().root.push_input(motion,true)
	for down: bool in [true,false]:
		var e:=InputEventMouseButton.new(); e.position=at; e.global_position=at; e.button_index=MOUSE_BUTTON_LEFT; e.pressed=down; get_tree().root.push_input(e,true)
func play(seconds: float, input_enabled: bool=true) -> void:
	for frame: int in int(seconds/.025):
		kitchen.advance(.025)
		if not input_enabled or not kitchen.stage.visible: continue
		for lane: TDCookingLane in kitchen.stage.lanes.duplicate():
			if lane.qte==null: continue
			var p: Dictionary=lane.progress.duplicate(true)
			var token: String=str(p.operation_id)
			var kind: String=p.qte_kind
			if kind in ["rhythm","sequence"]:
				for index: int in p.beat_times_sec.size():
					var marker: String=token+":"+str(index)
					if sent.has(marker) or float(p.elapsed_sec)+.000001<float(p.beat_times_sec[index]): continue
					sent[marker]=true
					var action: String=str(p.cut_actions[index]) if kind=="rhythm" and not p.get("cut_actions",[]).is_empty() else ("primary" if kind=="rhythm" else str(p.sequence[index]))
					if action.begins_with("spice:"):
						var r: Rect2=kitchen.stage.spice_rect(lane.lane_index,action.trim_prefix("spice:")); click(r.get_center())
					else:
						var codes: Dictionary={"primary":KEY_SPACE,"rotate_left":KEY_A,"rotate_right":KEY_D,"up":KEY_W,"left":KEY_A,"down":KEY_S,"right":KEY_D} if lane.lane_index!=1 else {"primary":KEY_SPACE,"up":KEY_UP,"left":KEY_LEFT,"down":KEY_DOWN,"right":KEY_RIGHT}
						tap(codes[action])
			elif kind=="window" and not sent.has(token) and float(p.elapsed_sec)+.000001>=float(p.target_sec): sent[token]=true; tap(KEY_SPACE)
			elif kind=="charge":
				if not sent.has(token) and float(p.get("preview_remaining_sec",0))<=.000001: sent[token]=true; key(KEY_SPACE)
				elif float(p.held_sec)+.000001>=(float(p.target_min_sec)+float(p.target_max_sec))*.5: key(KEY_SPACE,false)

func prepared_to(stove: String) -> void:
	station("kitchen.supply.tomato"); station("kitchen.board")
	assert_true(kitchen.stage.visible)
	play(8)
	assert_false(kitchen.stage.visible)
	station("kitchen.board"); station(stove)
	station("kitchen.supply.egg"); station(stove)

func test_actual_counters_and_complete_automatic_tomato_egg_no_operation_menu() -> void:
	watch_signals(kitchen)
	prepared_to("kitchen.stove.left")
	station("kitchen.stove.left")
	assert_true(kitchen.stage.visible); assert_false(kitchen.panel.visible)
	assert_eq(kitchen.stage.find_children("*","Button",true,false).size(),0)
	play(58)
	var dish: Dictionary=kitchen.lanes[0].snapshot()
	assert_eq(dish.state,"plated")
	var operations: Array=[]
	for step: Dictionary in dish.steps: operations.append(step.operation)
	assert_eq(operations,["cut","preheat","season","stir","stir","stir","stir","heat","season","starch","plate"])
	assert_true(dish.ingredients.values().any(func(item: Dictionary)->bool:return item.ingredient_id=="starch"))
	station("kitchen.stove.left"); station("kitchen.serve")
	assert_signal_emit_count(kitchen,"dish_delivered",1)
	assert_false(kitchen.stage.feedback.is_empty())
	tap(KEY_E); station("kitchen.serve"); assert_signal_emit_count(kitchen,"dish_delivered",1)

func test_no_input_still_advances_every_stage_and_pause_freezes_schedule() -> void:
	prepared_to("kitchen.stove.left"); station("kitchen.stove.left")
	var before: float=kitchen.shared_clock.qte_sec
	app.toggle_pause(); kitchen.advance(100); assert_eq(kitchen.shared_clock.qte_sec,before); app.toggle_pause()
	play(58,false)
	assert_eq(kitchen.lanes[0].snapshot().state,"plated")
	assert_lt(float(kitchen.lanes[0].snapshot().dish_attributes.completion),40.0)

func test_dual_pots_run_independent_profiles_and_share_mouse_without_menu_toggle() -> void:
	prepared_to("kitchen.stove.left"); prepared_to("kitchen.stove.right")
	station("kitchen.stove.left"); tap(KEY_E); station("kitchen.stove.right")
	assert_eq(kitchen.stage.lanes.size(),2)
	play(20)
	assert_not_null(kitchen.lanes[0].thermal_qte); assert_not_null(kitchen.lanes[1].thermal_qte)
	var r: Rect2=kitchen.stage.thermal_rect(0)
	assert_eq(r.position.x,kitchen.stage.thermal_rect(1).position.x)
	assert_eq(r.size.x,kitchen.stage.thermal_rect(1).size.x)
	var e:=InputEventMouseMotion.new(); e.position=r.get_center(); e.global_position=e.position; get_tree().root.push_input(e,true)
	for lane: TDCookingLane in kitchen.lanes:
		assert_gt(float(lane.thermal_progress.attraction),0.0)
		assert_almost_eq(float(lane.thermal_progress.control),.5,.000001)
	assert_lt(float(kitchen.lanes[0].thermal_progress.target_max),float(kitchen.lanes[1].thermal_progress.target_min))
	play(45)
	for lane: TDCookingLane in kitchen.lanes: assert_eq(lane.snapshot().state,"plated")

func test_steam_flow_and_simmer_persistent_edge_meter() -> void:
	prepared_to("kitchen.steamer"); station("kitchen.steamer")
	play(29)
	assert_eq(kitchen.lanes[1].snapshot().state,"plated")
	assert_eq(kitchen.lanes[1].snapshot().recipe_id,"steamed_egg")
	assert_eq(kitchen.lanes[1].snapshot().steps.map(func(x:Dictionary)->String:return x.operation),["cut","season","steam","plate"])
	station("kitchen.supply.beef"); station("kitchen.stove.left"); station("kitchen.stove.left")
	play(7); tap(KEY_E); kitchen.advance(1)
	assert_false(kitchen.world.simmer_meters.is_empty())
	var time: float=kitchen.lanes[0].thermal_progress.elapsed_sec
	kitchen.advance(1); assert_gt(float(kitchen.lanes[0].thermal_progress.elapsed_sec),time)
	station("kitchen.supply.tomato"); station("kitchen.board"); kitchen.advance(.1)
	assert_true(kitchen.stage.visible); assert_false(kitchen.stage.simmer_meters.is_empty())

func test_unexpected_space_is_a_real_m3_mistake() -> void:
	prepared_to("kitchen.stove.left"); station("kitchen.stove.left")
	play(5,false)
	while kitchen.lanes[0].progress.get("pc_module")!="M3": kitchen.advance(.025)
	var lane: TDCookingLane=kitchen.lanes[0]
	kitchen.advance(float(lane.progress.beat_times_sec[0])-float(lane.progress.elapsed_sec))
	tap(KEY_SPACE)
	assert_eq(int(lane.progress.miss),1)

func test_guided_restart_cleans_schedules_and_main_menu_has_only_play_and_exit() -> void:
	prepared_to("kitchen.stove.left"); station("kitchen.stove.left"); play(8)
	var old: TDFullKitchen=kitchen
	app.return_to_menu(); await get_tree().process_frame; await get_tree().process_frame
	assert_false(is_instance_valid(old))
	var labels: Array=[]
	for button: Button in app._menu.find_children("*","Button",true,false): labels.append(button.text)
	assert_eq(labels,["新开一间店   →","继续经营","菜谱研习","布置餐厅","走进小镇","退出"])
	app.enter_full_kitchen(); kitchen=app.full_kitchen; kitchen.auto_advance=false
	assert_false(kitchen.stage.visible)
	assert_eq(kitchen.get_signal_connection_list("dish_delivered").size(),0)
	for lane: TDCookingLane in kitchen.lanes:
		assert_null(lane.sheet); assert_null(lane.qte); assert_null(lane.thermal_qte)
		assert_true(lane.snapshot().ingredients.is_empty())
	assert_eq(kitchen.beat_audio.playing,true)

func wait_for_module(lane: TDCookingLane,module: String,limit: float=60) -> bool:
	for frame: int in int(limit/.025):
		kitchen.advance(.025)
		if lane.qte!=null and lane.progress.get("pc_module")==module: return true
	return false

func test_real_recipe_notes_make_chunks_and_feedback_survives_release_pause_and_finish() -> void:
	station("kitchen.supply.tomato"); station("kitchen.board")
	assert_true(kitchen.stage.visible)
	assert_null(kitchen.prep.last_result)
	await get_tree().process_frame
	var lane: TDCookingLane=kitchen.prep
	assert_true(wait_for_module(lane,"M1",5))
	assert_eq(lane.progress.cut_actions,["primary","rotate_right","primary"])
	kitchen.advance(2-float(lane.progress.elapsed_sec)); tap(KEY_SPACE)
	assert_eq(lane.judgement_feedback.grade,"perfect")
	assert_gt(lane.feedback_remaining(),.8)
	assert_true(lane._audio.stream is AudioStreamWAV)
	var event: Dictionary=lane.judgement_feedback.duplicate(true)
	var life: float=lane.feedback_remaining()
	app.toggle_pause(); kitchen.advance(15); assert_eq(lane.feedback_remaining(),life); app.toggle_pause()
	kitchen.advance(.1); assert_eq(lane.judgement_feedback,event)
	kitchen.advance(.9); tap(KEY_D); assert_eq(int(lane.progress.cut_hits),1)
	kitchen.advance(1); tap(KEY_SPACE); kitchen.advance(.15)
	assert_null(lane.qte); assert_gt(lane.feedback_remaining(),.6)
	var ingredient: Dictionary=lane.snapshot().ingredients.values()[0]
	assert_eq(ingredient.shape,"chunk"); assert_eq(float(ingredient.fine),.25)
	assert_eq(float(lane.snapshot().steps[0].quality),1.0)
	lane.cancel_operation(); assert_true(lane.judgement_feedback.is_empty())

func test_dual_seasoning_reserves_mouse_and_keeps_other_heat_unscored() -> void:
	prepared_to("kitchen.stove.left"); prepared_to("kitchen.stove.right")
	station("kitchen.stove.left"); play(17); tap(KEY_E); station("kitchen.stove.right")
	var left: TDCookingLane=kitchen.lanes[0]; var right: TDCookingLane=kitchen.lanes[1]
	assert_true(wait_for_module(left,"M6"))
	assert_null(left.thermal_qte); assert_not_null(right.thermal_qte)
	kitchen.advance(.01)
	var before: Dictionary=right.thermal_progress.duplicate(true)
	assert_true(bool(before.control_suspended))
	click(kitchen.stage.spice_rect(0,"salt").get_center())
	kitchen.advance(.4)
	assert_eq(float(right.thermal_progress.power),float(before.power))
	assert_eq(float(right.thermal_progress.inside_sec),float(before.inside_sec))
	assert_almost_eq(float(right.thermal_progress.suspended_sec)-float(before.suspended_sec),.4,.000001)
	assert_gt(float(right.thermal_progress.elapsed_sec),float(before.elapsed_sec))
	play(7,false)
	if right.thermal_qte!=null:
		assert_false(bool(right.thermal_progress.control_suspended))
		assert_eq(float(right.thermal_progress.attraction),0.0)

func test_real_late_plating_waits_for_complete_cursor_travel() -> void:
	prepared_to("kitchen.stove.left"); station("kitchen.stove.left")
	var lane: TDCookingLane=kitchen.lanes[0]
	assert_true(wait_for_module(lane,"M7"))
	tap(KEY_SPACE); assert_false(bool(lane.progress.charge_started))
	kitchen.advance(3.7-float(lane.progress.elapsed_sec)); key(KEY_SPACE)
	kitchen.advance(1.5); assert_not_null(lane.qte)
	assert_almost_eq(float(lane.progress.held_sec),1.5,.000001)
	kitchen.advance(.5); key(KEY_SPACE,false)
	assert_eq(lane.snapshot().state,"plated")
	assert_eq(float(lane.snapshot().steps.back().quality),1.0)
	assert_eq(lane.judgement_feedback.grade,"perfect")
	assert_true(kitchen.stage.visible)
