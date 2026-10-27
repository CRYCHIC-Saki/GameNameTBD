extends GutTest
const APP := preload("res://src/app/main.tscn")
var app: TDApplication
var kitchen: TDFullKitchen
var game_layer: CanvasLayer

func before_each() -> void:
	DirAccess.make_dir_recursive_absolute("res://artifacts/test-storage")
	app = APP.instantiate() as TDApplication
	app.settings_path = "res://artifacts/test-storage/pc-settings.json"
	# GUT uses a layer at 128. Put the actual game above its test-output UI so
	# mouse events reach real game Controls, with normal Viewport GUI dispatch.
	game_layer=CanvasLayer.new(); game_layer.layer=129
	autofree(game_layer); get_tree().root.add_child(game_layer); game_layer.add_child(app)
	app.enter_full_kitchen(); kitchen = app.full_kitchen; kitchen.auto_advance = false
	# Historical free-operation PC controls; strict player flow has its own suite.
	kitchen.guided_controls = false
	for lane: TDCookingLane in kitchen.lanes + [kitchen.prep]:
		lane.document_rules=false; lane.new_session("tomato_egg")
		lane.beat_offset_sec = 0
		lane.library = TDRecipeLibrary.new("res://artifacts/test-storage/pc-recipes.json", kitchen.catalog.data())
	await get_tree().process_frame

func after_each() -> void:
	get_tree().paused = false
	app.return_to_menu()
	await get_tree().process_frame
	await get_tree().process_frame

func key(code: Key, down: bool = true) -> void:
	var event := InputEventKey.new(); event.physical_keycode=code; event.keycode=code; event.pressed=down
	get_tree().root.push_input(event,true)

func tap(code: Key) -> void:
	key(code); key(code,false)

func station(id: String) -> void:
	for entry: Dictionary in TDKitchenWorld.STATIONS:
		if entry.id == id:
			(kitchen.world.get_node("Player") as TDKitchenPlayer).position = entry.position + Vector2(0,40); (kitchen.world.get_node("Player") as TDKitchenPlayer).face(Vector2.UP)
			tap(KEY_E)
			return
	fail_test("Unknown station " + id)

func cut_prepared() -> String:
	station("kitchen.supply.tomato")
	assert_eq(kitchen.handling.hand_kind,"ingredient")
	station("kitchen.board")
	assert_true(kitchen.prep.visible)
	var lane: TDCookingLane = kitchen.prep
	var id: String = lane.snapshot().ingredients.keys()[0]
	assert_true(lane.perform("cut",{"instance_id":id,"beats":2}).ok)
	var beats: Array = lane.progress.beat_times_sec.duplicate()
	for index: int in beats.size():
		kitchen.advance(float(beats[index])-float(lane.progress.elapsed_sec))
		if index == 1: tap(KEY_D)
		tap(KEY_SPACE)
	kitchen.advance(.101)
	assert_null(lane.qte)
	assert_eq(lane.snapshot().ingredients[id].shape,"chunk")
	kitchen._take_and_leave()
	assert_false(kitchen.panel.visible)
	return id

func load_pot() -> void:
	station("kitchen.supply.egg"); station("kitchen.stove.left"); station("kitchen.stove.left")
	assert_true(kitchen.panel.visible)

func finish_commands(lane: TDCookingLane) -> void:
	var steps: Array = lane.progress.sequence.duplicate()
	var times: Array = lane.progress.beat_times_sec.duplicate()
	for index: int in steps.size():
		kitchen.advance(maxf(0,float(times[index])-float(lane.progress.elapsed_sec)))
		var codes: Dictionary = {"up":KEY_UP,"left":KEY_LEFT,"down":KEY_DOWN,"right":KEY_RIGHT,"primary":KEY_SPACE} if lane.lane_index == 1 else {"up":KEY_W,"left":KEY_A,"down":KEY_S,"right":KEY_D,"primary":KEY_SPACE}
		tap(codes[steps[index]])
	assert_null(lane.qte)

func mouse(position: Vector2, pressed: bool) -> void:
	var motion := InputEventMouseMotion.new(); motion.position=position; motion.global_position=position; motion.button_mask=0 if pressed else MOUSE_BUTTON_MASK_LEFT
	get_tree().root.push_input(motion,true)
	var event := InputEventMouseButton.new(); event.position=position; event.global_position=position; event.button_index=MOUSE_BUTTON_LEFT; event.pressed=pressed
	get_tree().root.push_input(event,true)

func test_real_world_pick_prepare_move_cook_plate_carry_and_serve_once() -> void:
	watch_signals(kitchen)
	var id: String = cut_prepared()
	var prepared: Dictionary = kitchen.handling.hand.snapshot().to_dict().ingredients[id]
	station("kitchen.stove.left")
	assert_null(kitchen.handling.hand)
	var lane: TDCookingLane = kitchen.lanes[0]
	assert_eq(lane.snapshot().ingredients[id].flavor,prepared.flavor)
	assert_eq(lane.snapshot().ingredients[id].fine,.25)
	station("kitchen.supply.egg"); station("kitchen.stove.left"); station("kitchen.stove.left")
	assert_true(lane.perform("preheat").ok)
	kitchen.advance(float(lane.progress.target_sec)); tap(KEY_SPACE)
	assert_null(lane.qte)
	assert_true(lane.perform("heat").ok); assert_true(lane.perform("stir").ok)
	finish_commands(lane)
	assert_not_null(lane.thermal_qte)
	kitchen.advance(16)
	assert_null(lane.thermal_qte)
	assert_true(lane.perform("plate").ok)
	key(KEY_SPACE); kitchen.advance(1); key(KEY_SPACE,false)
	assert_eq(lane.snapshot().state,"plated")
	kitchen.close_bench(); station("kitchen.stove.left")
	assert_eq(kitchen.handling.hand_kind,"dish")
	station("kitchen.serve")
	assert_eq(lane.snapshot().state,"delivered")
	assert_signal_emit_count(kitchen,"dish_delivered",1)
	assert_gt(lane._feedback.text.length(),30)
	kitchen.close_bench(); station("kitchen.serve")
	assert_signal_emit_count(kitchen,"dish_delivered",1)

func test_real_mouse_attraction_and_cabinet_run_with_keyboard_track() -> void:
	load_pot()
	var lane: TDCookingLane = kitchen.lanes[0]
	lane.perform("heat"); lane.perform("stir")
	await get_tree().process_frame; await get_tree().process_frame
	var area: Rect2 = lane.temperature_view.bar_rect()
	mouse(area.position+area.size*Vector2(.52,.5),true)
	assert_gt(float(lane.thermal_progress.attraction),0.0)
	finish_commands(lane)
	mouse(area.position+area.size*Vector2(.52,.5),false)
	assert_true(lane.perform("season",{"ingredient_id":"salt","amount":.1}).ok)
	await get_tree().process_frame; await get_tree().process_frame
	var times: Array = lane.progress.beat_times_sec.duplicate()
	for index: int in 3:
		kitchen.advance(maxf(0,float(times[index])-float(lane.progress.elapsed_sec)))
		var button := lane._cabinet.get_child(index) as Button
		var point: Vector2 = button.global_position+button.size*.5
		mouse(point,true); mouse(point,false)
	assert_null(lane.qte)
	assert_eq(lane.snapshot().ingredients.size(),4)
	if lane.snapshot().ingredients.size() > 1: assert_eq(lane.snapshot().ingredients.values()[1].ingredient_id,"salt")
	assert_not_null(lane.thermal_qte)

func test_simmer_keeps_advancing_while_player_prepares_other_food_and_pause_freezes() -> void:
	load_pot(); var lane: TDCookingLane = kitchen.lanes[0]
	lane.perform("boil"); kitchen.close_bench(); kitchen.advance(2)
	assert_gt(float(lane.thermal_progress.elapsed_sec),1.9)
	assert_true(kitchen.world._simmer_label.text.contains("炖煮"))
	var elapsed: float = lane.clock.qte_sec
	app.toggle_pause(); kitchen.advance(10)
	assert_eq(lane.clock.qte_sec,elapsed)
	app.toggle_pause()
	cut_prepared()
	assert_gt(float(lane.thermal_progress.elapsed_sec),2.0)
	assert_eq(kitchen.handling.hand_kind,"ingredient")

func test_dual_shared_mouse_and_space_do_not_mix_sessions() -> void:
	load_pot(); kitchen.set_dual(true)
	var left: TDCookingLane = kitchen.lanes[0]; var right: TDCookingLane = kitchen.lanes[1]
	right.perform("add",{"ingredient_id":"egg"})
	left.perform("heat"); right.perform("heat")
	left.perform("stir"); right.perform("stir")
	await get_tree().process_frame; await get_tree().process_frame
	var area: Rect2 = left.temperature_view.bar_rect(); mouse(area.position+area.size*.5,true)
	assert_gt(float(left.thermal_progress.attraction),0.0); assert_gt(float(right.thermal_progress.attraction),0.0)
	var times: Array = left.progress.beat_times_sec.duplicate()
	for index: int in 5:
		kitchen.advance(maxf(0,float(times[index])-float(left.progress.elapsed_sec)))
		if index == 4: tap(KEY_SPACE)
		else:
			tap([KEY_W,KEY_A,KEY_S,KEY_D][index]); tap([KEY_UP,KEY_LEFT,KEY_DOWN,KEY_RIGHT][index])
	assert_null(left.qte); assert_null(right.qte)
	assert_eq(float(left.progress.quality),1.0); assert_eq(float(right.progress.quality),1.0)
	var other: Dictionary = right.snapshot()
	left.cancel_operation(); left.new_session("tomato_egg")
	assert_eq(other,right.snapshot())

func test_beat_sheet_no_input_produces_misses_but_reaches_plate_without_fake_success() -> void:
	load_pot(); var lane: TDCookingLane = kitchen.lanes[0]
	assert_true(lane.start_sheet("stir_fry").ok)
	kitchen.advance(35)
	assert_eq(lane.snapshot().state,"plated")
	assert_false(lane.sheet.running)
	assert_eq(lane.snapshot().steps.size(),7)
	assert_lt(float(lane.snapshot().dish_attributes.completion),50.0)
	assert_eq(lane.snapshot().ingredients.size(),2,"only command oil is applied; untouched cabinet adds nothing")

func test_steam_sheet_and_cancel_restart_leave_no_old_callbacks() -> void:
	load_pot(); var lane: TDCookingLane = kitchen.lanes[0]
	assert_true(lane.perform("steam").ok)
	key(KEY_SPACE); kitchen.advance(4); key(KEY_SPACE,false)
	assert_gt(float(lane.snapshot().ingredients.values()[0].heat_dose),0.0)
	lane.perform("heat"); lane.perform("stir")
	var old: TDCookingQTE = lane.thermal_qte
	lane.cancel_operation(); lane.new_session("tomato_egg")
	assert_eq(old.finish().code,"CANCELLED")
	assert_true(lane.snapshot().ingredients.is_empty())
	assert_true(lane.snapshot().pending_operations.is_empty())
	for index: int in 2:
		app.return_to_menu(); app.enter_full_kitchen(); kitchen=app.full_kitchen; kitchen.auto_advance=false
		assert_eq(kitchen.lanes.size(),2)
		assert_null(kitchen.handling.hand)

func test_calibration_widget_applies_to_board_and_both_stoves() -> void:
	for lane: TDCookingLane in kitchen.lanes:
		assert_almost_eq(lane._pc_amount.value, .1, 0.000000001, "default portion must not snap to .11")
	station("kitchen.supply.tomato"); station("kitchen.board")
	var offset: SpinBox
	for node: Node in kitchen.find_children("*", "SpinBox", true, false):
		if (node as SpinBox).suffix == "ms补偿": offset = node as SpinBox
	assert_not_null(offset)
	if offset == null: return
	offset.value = 125
	for lane: TDCookingLane in kitchen.lanes + [kitchen.prep]:
		assert_eq(lane.input_offset_sec, .125)
	var prep: TDCookingLane = kitchen.prep
	prep.perform("cut", {"instance_id":prep.snapshot().ingredients.keys()[0], "beats":1})
	# A late physical event is judged on the calibrated timestamp in the real lane.
	kitchen.advance(float(prep.progress.beat_times_sec[0]) + .125)
	tap(KEY_SPACE)
	kitchen.advance(.25)
	assert_null(prep.qte)
	assert_eq(str(prep.progress.grade), "perfect")
