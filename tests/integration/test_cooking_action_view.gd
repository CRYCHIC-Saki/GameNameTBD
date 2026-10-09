extends GutTest

const View = preload("res://src/qte/cooking_action_view.gd")
const QTE = preload("res://src/qte/cooking_qte.gd")
const Clock = preload("res://src/platform/session_clock.gd")
const Request = preload("res://src/contracts/operation_request.gd")
const Random = preload("res://src/platform/business_random.gd")

func request(operation: String, oid: String = "view-test-op") -> TDRequest:
	var result := Request.new("view-test-session", 1, oid, operation, 0)
	result.schema_version = 3
	return result

func rhythm_config() -> Dictionary:
	return {"kind": "rhythm", "beats": 4, "interval_sec": 0.5, "lead_in_sec": 1.0,
		"perfect_sec": 0.06, "good_sec": 0.14}

func test_real_qte_input_drives_action_then_pause_keeps_the_same_pose() -> void:
	var view := View.new()
	view.size = Vector2(380.0, 158.0)
	add_child_autofree(view)
	var clock := Clock.new()
	var qte := QTE.new(request("cut"), rhythm_config(), clock, Random.new(5))
	view.set_progress("cut", qte.start().data)
	clock.advance(1.0)
	view.set_progress("cut", qte.input(1, clock.qte_sec, "primary", true).data)
	view.pulse_input("primary", true)
	assert_eq(view.presentation_state().pulse, 1.0)
	assert_eq(view.presentation_state().progress.hits, 1)
	clock.advance(0.09)
	view.set_progress("cut", qte.update().data)
	assert_almost_eq(view.presentation_state().pulse, 0.5, 0.0000001)
	clock.paused = true
	clock.advance(10.0)
	view.set_progress("cut", qte.update().data)
	var paused_pose := view.presentation_state()
	await wait_process_frames(3)
	assert_eq(view.presentation_state(), paused_pose)
	assert_false(view.is_processing(), "The view cannot animate from wall time while QTE time is paused")

func test_progress_is_a_copy_and_view_cannot_change_controller_score() -> void:
	var clock := Clock.new()
	var qte := QTE.new(request("stir"), rhythm_config(), clock, Random.new(5))
	var view := View.new()
	add_child_autofree(view)
	var result := qte.start()
	view.set_progress("stir", result.data)
	result.data.judgements[0] = "perfect"
	assert_eq(view.presentation_state().progress.judgements[0], "pending")
	var displayed := view.presentation_state()
	displayed.progress.judgements[0] = "good"
	assert_eq(view.presentation_state().progress.judgements[0], "pending")
	view.pulse_input("primary", true)
	clock.advance(5.0)
	assert_eq(qte.finish().data.quality, 0.0, "A visual pulse does not submit input to the controller")

func test_new_operation_and_rewind_clear_old_input_pose() -> void:
	var view := View.new()
	add_child_autofree(view)
	view.set_progress("cut", {"operation_id": "one", "elapsed_sec": 1.0, "qte_kind": "rhythm"})
	view.pulse_input("primary", true)
	assert_eq(view.presentation_state().pulse, 1.0)
	view.set_progress("cut", {"operation_id": "two", "elapsed_sec": 1.0, "qte_kind": "rhythm"})
	assert_eq(view.presentation_state().pulse, 0.0)
	assert_eq(view.presentation_state().last_action, "")
	view.pulse_input("primary", true)
	view.set_progress("cut", {"operation_id": "two", "elapsed_sec": 0.0, "qte_kind": "rhythm"})
	assert_eq(view.presentation_state().pulse, 0.0)

func test_all_nine_operations_have_scene_views_and_allow_input_passthrough() -> void:
	var operations := {"cut": "rhythm", "preheat": "charge", "stir": "rhythm", "heat": "maintain", "boil": "maintain",
		"season": "sequence", "ferment": "sequence", "starch": "window", "plate": "window"}
	for operation in operations:
		var view := View.new()
		add_child_autofree(view)
		view.size = Vector2(440.0, 176.0)
		view.set_progress(operation, {"qte_kind": operations[operation], "elapsed_sec": 1.0, "status": "running"})
		view.pulse_input("up" if operations[operation] == "sequence" else "primary", true)
		assert_eq(view.presentation_state().operation, operation)
		assert_eq(view.mouse_filter, Control.MOUSE_FILTER_IGNORE)
		assert_eq(view.custom_minimum_size, Vector2(380.0, 158.0))
	await wait_process_frames(3)

func test_maintain_progress_uses_real_disturbance_without_advancing_it() -> void:
	var settings := {"kind": "maintain", "duration_sec": 4.0, "target_min": 0.4, "target_max": 0.6,
		"initial_value": 0.5, "disturbance_amplitude": 0.25, "disturbance_period_sec": 4.0}
	var clock := Clock.new()
	var qte := QTE.new(request("heat"), settings, clock, Random.new(18))
	var view := View.new()
	add_child_autofree(view)
	view.set_progress("heat", qte.start().data)
	clock.advance(1.0)
	var state := qte.update().data
	view.set_progress("heat", state)
	assert_eq(view.presentation_state().progress.power, state.power)
	assert_eq(view.presentation_state().progress.control, state.control)
	await wait_process_frames(3)
	assert_eq(clock.qte_sec, 1.0)
	assert_eq(qte.update().data, state)
