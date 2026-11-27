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
		if entry.id==id: (kitchen.world.get_node("Player") as TDKitchenPlayer).position=entry.position+Vector2(0,40); (kitchen.world.get_node("Player") as TDKitchenPlayer).face(Vector2.UP); tap(KEY_E); return
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

func test_only_one_pot_can_take_food_or_run_a_chart() -> void:
	prepared_to("kitchen.stove.left")
	station("kitchen.stove.left")
	assert_eq(kitchen.stage.lanes,[kitchen.lanes[0]])
	tap(KEY_E)
	station("kitchen.supply.egg")
	station("kitchen.stove.right")
	assert_true(kitchen.lanes[1].snapshot().ingredients.is_empty())
	assert_eq(kitchen.handling.hand_kind,"ingredient")
	assert_eq(kitchen.lanes[1].start_sheet("tomato_egg").code,"OTHER_POT_IN_USE")
	kitchen.handling.clear_ingredient()
	station("kitchen.stove.left")
	play(62)
	assert_eq(kitchen.lanes[0].snapshot().state,"plated")
	station("kitchen.stove.left"); station("kitchen.serve"); tap(KEY_E)
	assert_false(kitchen.other_pot_in_use(1))

func test_steam_flow_and_simmer_persistent_edge_meter() -> void:
	prepared_to("kitchen.steamer"); station("kitchen.steamer")
	play(29)
	assert_eq(kitchen.lanes[1].snapshot().state,"plated")
	assert_eq(kitchen.lanes[1].snapshot().recipe_id,"steamed_egg")
	assert_eq(kitchen.lanes[1].snapshot().steps.map(func(x:Dictionary)->String:return x.operation),["cut","season","steam","plate"])
	station("kitchen.steamer"); station("kitchen.serve"); tap(KEY_E)
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
	assert_eq(int(lane.progress.wrong),1)
	assert_eq(lane.progress.judgements[0],"pending")

func test_stalled_frame_preserves_the_retimed_cues_after_a_mistake() -> void:
	station("kitchen.supply.tomato"); station("kitchen.board")
	var lane := kitchen.prep
	assert_true(wait_for_module(lane,"M1",5))
	var notes: Array = lane.progress.beat_times_sec.duplicate()
	kitchen.advance(float(notes[0])-float(lane.progress.elapsed_sec))
	tap(KEY_D)
	assert_eq(lane.progress.judgements,["pending","pending","pending"])
	var after_wrong: Array = lane.progress.beat_times_sec.duplicate()
	assert_eq(after_wrong[0],notes[0])
	assert_lt(float(after_wrong[1]),float(notes[1]))
	var before := lane.clock.qte_sec
	kitchen._last_ticks = Time.get_ticks_usec()-3000000
	kitchen._sync_time()
	assert_almost_eq(lane.clock.qte_sec-before,TDFullKitchen.MAX_INTERACTIVE_DELTA,.001)
	assert_eq(lane.progress.beat_times_sec,after_wrong)
	assert_eq(lane.progress.judgements,["pending","pending","pending"])
	var expires := float(notes[0])+float(lane.qte._config.good_sec)+.001
	kitchen.advance(expires-float(lane.progress.elapsed_sec))
	assert_eq(lane.progress.judgements[0],"miss")
	kitchen.advance(float(lane.progress.beat_times_sec[1])-float(lane.progress.elapsed_sec))
	tap(KEY_D)
	assert_eq(lane.judgement_feedback.grade,"perfect")

func test_guided_restart_cleans_schedules_and_returns_to_player_title() -> void:
	prepared_to("kitchen.stove.left"); station("kitchen.stove.left"); play(8)
	var old: TDFullKitchen=kitchen
	app.return_to_menu(); await get_tree().process_frame; await get_tree().process_frame
	assert_false(is_instance_valid(old))
	var labels: Array=[]
	assert_false(app.game_shell._hud_layer.visible,"in-game shortcuts stay hidden at the title")
	for button: Button in app._menu.find_children("*","Button",true,false):
		if button.is_visible_in_tree(): labels.append(button.text)
	assert_eq(labels,["开始游戏","继续游戏","载入存档","设置","退出游戏"])
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
	kitchen.advance(float(lane.progress.beat_times_sec[0])-float(lane.progress.elapsed_sec)); tap(KEY_SPACE)
	assert_eq(lane.judgement_feedback.grade,"perfect")
	assert_gt(lane.feedback_remaining(),.8)
	assert_true(lane._audio.stream is AudioStreamWAV)
	var event: Dictionary=lane.judgement_feedback.duplicate(true)
	var life: float=lane.feedback_remaining()
	app.toggle_pause(); kitchen.advance(15); assert_eq(lane.feedback_remaining(),life); app.toggle_pause()
	kitchen.advance(.1); assert_eq(lane.judgement_feedback,event)
	var impulse: float = TDGuidedCookingView.CLOSEUP.impulse(lane)
	assert_gt(impulse,.6,"Accepted note drives the utensil rebound")
	app.toggle_pause(); kitchen.advance(2)
	assert_eq(TDGuidedCookingView.CLOSEUP.impulse(lane),impulse,"Paused artwork stays on the accepted note")
	app.toggle_pause()
	kitchen.advance(float(lane.progress.beat_times_sec[1])-float(lane.progress.elapsed_sec)); tap(KEY_D); assert_eq(int(lane.progress.cut_hits),1)
	kitchen.advance(float(lane.progress.beat_times_sec[2])-float(lane.progress.elapsed_sec)); tap(KEY_SPACE); kitchen.advance(.25) # Production Good window is now inclusive through +200ms.
	assert_null(lane.qte); assert_gt(lane.feedback_remaining(),.6)
	var ingredient: Dictionary=lane.snapshot().ingredients.values()[0]
	assert_eq(ingredient.shape,"chunk"); assert_eq(float(ingredient.fine),.25)
	assert_eq(float(lane.snapshot().steps[0].quality),1.0)
	lane.cancel_operation(); assert_true(lane.judgement_feedback.is_empty())
	assert_eq(TDGuidedCookingView.CLOSEUP.impulse(lane),0.0,"No previous strike on restarting")

func test_casual_full_song_loops_without_pitch_change_at_shared_140_bpm() -> void:
	var duration := TDBeatAudio.LOOP_SEC
	assert_almost_eq(TDBeatAudio.phase_error(.008,duration-.008),.016,.000001)
	assert_almost_eq(TDBeatAudio.phase_error(duration-.030,.010),-.040,.000001)
	var audio := kitchen.beat_audio
	audio.prepare_cooking_music(140.0)
	var wav := audio.stream as AudioStreamWAV
	assert_eq(wav.loop_end,roundi(wav.mix_rate*duration))
	assert_eq(audio.pitch_scale,1.0)
	assert_almost_eq(float(wav.loop_end)/wav.mix_rate,duration,.0001)

func test_seasoning_after_attempted_second_pot_keeps_first_schedule() -> void:
	prepared_to("kitchen.stove.left"); station("kitchen.stove.left")
	var left: TDCookingLane=kitchen.lanes[0]; var right: TDCookingLane=kitchen.lanes[1]
	assert_true(wait_for_module(left,"M6"))
	assert_eq(right.start_sheet("tomato_egg").code,"OTHER_POT_IN_USE")
	assert_eq(kitchen.stage.lanes,[left])
	assert_true(kitchen.stage.spice_rect(0,"salt").has_area())
	assert_false(kitchen.stage.spice_rect(1,"salt").has_area())

func test_real_late_plating_waits_for_complete_cursor_travel() -> void:
	prepared_to("kitchen.stove.left"); station("kitchen.stove.left")
	var lane: TDCookingLane=kitchen.lanes[0]
	assert_true(wait_for_module(lane,"M7"))
	tap(KEY_SPACE); assert_false(bool(lane.progress.charge_started))
	kitchen.advance(111.0/35-float(lane.progress.elapsed_sec)); key(KEY_SPACE) # Late inside the 8-beat start window at 140 BPM.
	kitchen.advance(1.5); assert_not_null(lane.qte)
	assert_almost_eq(float(lane.progress.held_sec),1.5,.000001)
	kitchen.advance(12.0/7-1.5); key(KEY_SPACE,false) # Complete all four hold beats.
	assert_eq(lane.snapshot().state,"plated")
	assert_eq(float(lane.snapshot().steps.back().quality),1.0)
	assert_eq(lane.judgement_feedback.grade,"perfect")
	assert_true(kitchen.stage.visible)
