extends GutTest
const APP := preload("res://src/app/main.tscn")
var app: TDApplication
var bench: TDFullKitchen
var lane: TDCookingLane

func before_each() -> void:
	DirAccess.make_dir_recursive_absolute("res://artifacts/test-storage")
	app = APP.instantiate() as TDApplication
	app.settings_path = "res://artifacts/test-storage/full-settings.json"
	add_child_autofree(app)
	app.enter_full_kitchen()
	bench = app.full_kitchen
	bench.guided_controls = false
	bench.auto_advance = false
	bench.library_path = "res://artifacts/test-storage/full-recipes.json"
	# Historical controller compatibility remains covered. The current PC station
	# flow is exercised separately through real world/input events in test_pc_kitchen.
	for item: TDCookingLane in bench.lanes:
		item.pc_controls = false
		item.new_session("tomato_egg")
		item.library = TDRecipeLibrary.new(bench.library_path, bench.catalog.data())
	lane = bench.lanes[0]
	bench.open_bench()
	await get_tree().process_frame

func after_each() -> void:
	get_tree().paused = false
	app.return_to_menu()
	await get_tree().process_frame
	await get_tree().process_frame

func _key(code: Key, down: bool = true, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code; event.keycode = code; event.pressed = down; event.echo = echo
	Input.parse_input_event(event); Input.flush_buffered_events()

func _tap(code: Key = KEY_SPACE) -> void:
	_key(code); _key(code, false)

func _do(kind: String, args: Dictionary = {}) -> void:
	assert_true(lane.perform(kind, args).ok, kind)
	_complete_current()

func _complete_current() -> void:
	var kind: String = lane.snapshot().pending_operation
	var qkind: String = lane.progress.qte_kind
	match qkind:
		"charge":
			_key(KEY_SPACE); bench.advance(1.4); _key(KEY_SPACE, false)
		"rhythm":
			var beats: Array = lane.progress.beat_times_sec.duplicate()
			for at: float in beats:
				bench.advance(at - float(lane.progress.elapsed_sec)); _tap()
			bench.advance(.3)
		"window":
			bench.advance(float(lane.progress.target_sec)); _tap()
		"sequence":
			for code: Key in [KEY_W, KEY_A, KEY_S, KEY_D]: _tap(code)
		"maintain":
			for frame: int in 120:
				# Inject a reproducible actual control timeline, not a fake completed result.
				lane.input_action("adjust", true, clampf(.55 - float(lane.progress.disturbance), 0, 1))
				bench.advance(.05)
			bench.advance(.0001)
	assert_null(lane.qte, kind + " must finish through real inputs")
	assert_true(lane.last_result.ok, kind + " model accepted real QTE")

func test_save_load_remake_preserves_distinct_instances_and_requires_new_qtes() -> void:
	var first: String = lane.perform("add", {"ingredient_id": "tomato"}).data.instance_id
	_do("cut", {"instance_id": first, "shape": "slice"})
	var second: String = lane.perform("add", {"ingredient_id": "tomato"}).data.instance_id
	_do("cut", {"instance_id": second, "shape": "dice"})
	lane._recipe_name.text = "集成测试两种切型"
	var saved := lane.save_current()
	assert_true(saved.ok, saved.code)
	if not saved.ok: return
	var loaded := lane.library.load_library()
	assert_true(loaded.ok)
	var entry: Dictionary = loaded.data.entries.back()
	lane.new_session(entry.plan.recipe_id, entry)
	assert_true(lane.snapshot().is_custom)
	assert_eq(lane.snapshot().ingredients.size(), 0)
	assert_eq(lane.snapshot().steps.size(), 0)
	for index: int in entry.plan.operations.size():
		lane._plan_steps.select(index)
		lane._run_plan_step()
		if lane.qte != null: _complete_current()
	assert_eq(lane.snapshot().ingredients.size(), 2)
	var instances: Array = lane.snapshot().ingredients.values()
	assert_eq(instances[0].shape, "slice")
	assert_eq(instances[1].shape, "dice")
	assert_eq(lane.snapshot().steps.size(), 2)
	assert_lte(float(lane.snapshot().dish_attributes.completion), 90.0)

func test_scene_fixed_seed_and_long_frame_heat_match_split_updates() -> void:
	lane.perform("add", {"ingredient_id": "egg"}); lane.perform("heat")
	lane.input_action("adjust", true, .7)
	bench.advance(7)
	var first: Dictionary = lane.snapshot().dish_attributes
	lane.new_session("tomato_egg")
	lane.perform("add", {"ingredient_id": "egg"}); lane.perform("heat")
	lane.input_action("adjust", true, .7)
	for frame: int in 140: bench.advance(.05)
	var second: Dictionary = lane.snapshot().dish_attributes
	assert_almost_eq(float(first.temperature_c), float(second.temperature_c), .00001)
	assert_almost_eq(float(first.completion), float(second.completion), .00001)
	for taste: int in 7:
		for slot: int in 4:
			assert_almost_eq(float(first.flavor[taste][slot]), float(second.flavor[taste][slot]), .000000001)

func test_walk_to_stove_opens_real_bench_and_reenter_keeps_same_session() -> void:
	bench.close_bench()
	assert_false(bench.panel.visible)
	(bench.world.get_node("Player") as TDKitchenPlayer).position = Vector2(588, 310);(bench.world.get_node("Player") as TDKitchenPlayer).face(Vector2.UP)
	_key(KEY_E); _key(KEY_E, false)
	assert_true(bench.panel.visible)
	var identity: String = lane.snapshot().session_id
	bench.close_bench(); bench.open_bench()
	assert_eq(lane.snapshot().session_id, identity)
	assert_eq(bench.lanes.size(), 2)

func test_all_five_real_qtes_cook_plate_deliver_and_explain_two_customers() -> void:
	watch_signals(bench)
	_do("preheat")
	var tomato := lane.perform("add", {"ingredient_id": "tomato"})
	assert_true(lane.perform("add", {"ingredient_id": "egg"}).ok)
	_do("cut", {"instance_id": tomato.data.instance_id, "shape": "chunk"})
	_do("heat")
	_do("season", {"ingredient_id": "sugar", "amount": .1})
	_do("plate")
	assert_eq(lane.snapshot().state, "plated")
	assert_signal_emit_count(bench, "dish_delivered", 0)
	assert_true(lane.perform("deliver").ok)
	assert_signal_emit_count(bench, "dish_delivered", 1)
	assert_false(lane.perform("deliver").ok)
	assert_signal_emit_count(bench, "dish_delivered", 1)
	var dish: Dictionary = lane.snapshot()
	var first := bench.scorer.evaluate(dish, bench.catalog.data().customers[0])
	var second := bench.scorer.evaluate(dish, bench.catalog.data().customers[1])
	assert_true(first.ok); assert_true(second.ok)
	assert_ne(first.data.satisfaction, second.data.satisfaction)
	assert_eq(dish, lane.snapshot(), "scoring must be read only")
	assert_gt(lane._feedback.text.length(), 30)

func test_dual_input_routing_same_frame_pause_and_single_side_restart() -> void:
	bench.set_dual(true)
	var right: TDCookingLane = bench.lanes[1]
	lane.perform("preheat"); right.perform("preheat")
	_key(KEY_W); _key(KEY_UP)
	bench.advance(.7)
	_key(KEY_W, true, true)
	assert_almost_eq(float(lane.progress.held_sec), .7, .00001)
	assert_almost_eq(float(right.progress.held_sec), .7, .00001)
	app.toggle_pause(); bench.advance(20)
	assert_almost_eq(lane.clock.qte_sec, .7, .00001)
	app.toggle_pause()
	_key(KEY_W, false); _key(KEY_UP, false)
	_key(KEY_UP); bench.advance(.7); _key(KEY_UP, false)
	assert_null(right.qte)
	var right_before: Dictionary = right.snapshot()
	var old: String = lane.progress.operation_id
	lane.cancel_operation(); lane.new_session("tomato_egg"); lane.perform("preheat")
	assert_eq(lane.input_action("primary", true, 1, old).code, "STALE_OPERATION")
	assert_eq(right_before, right.snapshot())
	_key(KEY_SPACE); _key(KEY_SPACE, false)
	assert_eq(float(lane.progress.held_sec), 0.0, "Space cannot feed two lanes in dual mode")

func test_free_plating_mouse_signals_rework_spill_and_independent_other_dish() -> void:
	lane.perform("add", {"ingredient_id": "egg"})
	_do("plate")
	var dish: Dictionary = lane.snapshot()
	var piece: String = dish.plating[0].id
	lane._plate.moved.emit(piece, Vector2(.2, .1), true)
	assert_eq(dish.dish_attributes, lane.snapshot().dish_attributes)
	assert_true(lane.perform("rework").ok)
	_do("heat"); _do("plate")
	var other: Dictionary = bench.lanes[1].snapshot()
	lane._plate.moved.emit(piece, Vector2(2, 0), false)
	assert_eq(lane.perform("deliver").code, "PLATING_IN_PROGRESS")
	lane._plate.moved.emit(piece, Vector2(2, 0), true)
	assert_eq(lane.snapshot().state, "discarded")
	assert_false(lane.perform("rework").ok)
	assert_eq(other, bench.lanes[1].snapshot())

func test_data_only_cold_recipe_runs_and_test_content_is_opt_in() -> void:
	assert_eq(lane._recipes.item_count, 1)
	lane.new_session("test.cold_salad")
	lane.perform("add", {"ingredient_id": "cucumber"})
	_do("stir"); _do("plate")
	assert_true(lane.perform("deliver").ok)
	assert_true(lane.snapshot().missing_required.is_empty())
	assert_lt(float(lane.snapshot().dish_attributes.temperature_c), 22.0)
	assert_true(bench.scorer.evaluate(lane.snapshot(), {"requirements": []}).ok)

func test_remaining_operations_and_fermentation_wait_use_same_scene_pipeline() -> void:
	lane.new_session("test.reaction_pan")
	for identity: String in ["beef", "sugar", "oil", "starch", "culture"]:
		assert_true(lane.perform("add", {"ingredient_id": identity}).ok)
	_do("heat"); _do("heat"); _do("boil"); _do("starch"); _do("ferment")
	assert_gt(lane.snapshot().fermentations.size(), 0)
	bench.advance(4)
	var reaction_ids: Array = []
	for event: Dictionary in lane.snapshot().events:
		if event.type == "reaction": reaction_ids.append(event.reaction_id)
	assert_has(reaction_ids, "starch_gel")
	assert_has(reaction_ids, "fermentation")
	_do("plate")
	assert_true(lane.perform("deliver").ok)

func test_real_mouse_drag_changes_plating_position_without_scoring_changes() -> void:
	# Put a fresh application above GUT's own GUI; reparenting would intentionally close its sessions.
	app.return_to_menu(); app.queue_free()
	await get_tree().process_frame
	app = APP.instantiate() as TDApplication
	app.settings_path = "res://artifacts/test-storage/mouse-settings.json"
	autofree(app)
	get_tree().root.add_child(app)
	app.enter_full_kitchen()
	bench = app.full_kitchen; bench.guided_controls = false; bench.auto_advance = false; bench.open_bench()
	lane = bench.lanes[0]
	lane.pc_controls = false; lane.new_session("tomato_egg")
	lane.perform("add", {"ingredient_id": "egg"})

	_do("plate")
	await get_tree().process_frame
	await get_tree().process_frame
	var view: TDPlatingView = lane._plate
	var original: Dictionary = lane.snapshot()
	var piece: Dictionary = original.plating[0]
	var center: Vector2 = view.global_position + view.size * .5
	var start: Vector2 = center + Vector2(piece.position[0], piece.position[1]) * view._radius()
	var finish: Vector2 = center + Vector2(.25, .1) * view._radius()
	var press := InputEventMouseButton.new(); press.button_index = MOUSE_BUTTON_LEFT; press.pressed = true; press.position = start; press.global_position = start
	get_tree().root.push_input(press, true)
	assert_false(view._drag.is_empty(), "real GUI press must pick a food piece")
	var move := InputEventMouseMotion.new(); move.position = finish; move.global_position = finish; move.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_tree().root.push_input(move, true)
	var release := InputEventMouseButton.new(); release.button_index = MOUSE_BUTTON_LEFT; release.pressed = false; release.position = finish; release.global_position = finish
	get_tree().root.push_input(release, true)
	assert_eq(lane.snapshot().state, "plated")
	assert_ne(lane.snapshot().plating[0].position, piece.position)
	assert_eq(lane.snapshot().dish_attributes, original.dish_attributes)
	assert_false(lane.snapshot().plating_dragging)

func test_cancel_reopen_focus_and_late_completion_do_not_modify_new_session() -> void:
	lane.perform("preheat")
	_key(KEY_SPACE); bench.advance(.5)
	var old: TDCookingQTE = lane.qte
	app._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert_true(lane.clock.paused)
	app.toggle_pause()
	lane.new_session("tomato_egg")
	assert_eq(old.finish().code, "CANCELLED")
	assert_eq(lane.snapshot().steps.size(), 0)
	for index: int in 3:
		app.return_to_menu(); app.enter_full_kitchen()
		assert_eq(app.full_kitchen.lanes.size(), 2)
		assert_eq(app.full_kitchen.lanes[0].snapshot().ingredients.size(), 0)
