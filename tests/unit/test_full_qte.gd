extends GutTest

const QTE = preload("res://src/qte/cooking_qte.gd")
const Clock = preload("res://src/platform/session_clock.gd")
const Request = preload("res://src/contracts/operation_request.gd")
const Random = preload("res://src/platform/business_random.gd")

class FixedRandom extends RefCounted:
	var value := 0.0
	var calls := 0
	func _init(sample: float = 0.0) -> void:
		value = sample
	func unit() -> float:
		calls += 1
		return value

func request(kind: String = "cut", oid: String = "test-operation") -> TDRequest:
	var value := Request.new("test-session", 1, oid, kind, 0)
	value.schema_version = 3
	return value

func config(kind: String) -> Dictionary:
	match kind:
		"charge": return {"kind": kind, "timeout_sec": 4.0, "target_min_sec": 1.2, "target_max_sec": 1.6, "good_margin_sec": 0.25}
		"rhythm": return {"kind": kind, "beats": 4, "interval_sec": 0.5, "lead_in_sec": 1.0, "perfect_sec": 0.06, "good_sec": 0.14, "input_offset_sec": 0.0}
		"window": return {"kind": kind, "target_sec": 1.8, "perfect_sec": 0.06, "good_sec": 0.14, "timeout_sec": 2.5}
		"maintain": return {"kind": kind, "duration_sec": 4.0, "target_min": 0.4, "target_max": 0.6, "initial_value": 0.5, "disturbance_amplitude": 0.25, "disturbance_period_sec": 4.0}
		"sequence": return {"kind": kind, "sequence": ["up", "left", "down", "right"], "timeout_sec": 5.0}
	return {}

func make(kind: String, clock: TDClock, operation: String = "cut") -> QTE:
	return QTE.new(request(operation), config(kind), clock, FixedRandom.new())

func test_all_five_lifecycle_identity_and_no_input_are_real_failures() -> void:
	for kind in QTE.KINDS:
		var clock := Clock.new()
		var qte := make(kind, clock, "stir")
		assert_eq(qte.finish().code, "NOT_STARTED", kind)
		assert_true(qte.start().ok, kind)
		assert_eq(qte.start().code, "ALREADY_STARTED")
		assert_eq(qte.finish().code, "NOT_READY")
		clock.advance(100.0)
		var result := qte.finish()
		assert_true(result.ok, kind)
		assert_lt(float(result.data.quality), 1.0, kind + " cannot pass unattended")
		assert_eq(result.data.schema_version, 3)
		assert_eq(result.data.session_id, "test-session")
		assert_eq(result.data.operation_id, "test-operation")
		assert_eq(result.data.kind, "stir")
		assert_eq(result.data.qte_kind, kind)
		assert_eq(result.data.status, "completed")
		assert_eq(qte.finish().code, "ALREADY_FINISHED")
		assert_eq(qte.cancel().code, "ALREADY_FINISHED")

func test_charge_target_and_good_boundaries_are_inclusive() -> void:
	var cases := [[0.949999, 0.0], [0.95, 0.6], [1.199999, 0.6], [1.2, 1.0], [1.6, 1.0], [1.600001, 0.6], [1.85, 0.6], [1.850001, 0.0]]
	for item in cases:
		var clock := Clock.new()
		var qte := make("charge", clock, "preheat")
		qte.start()
		qte.input(1, 0.0, "primary", true)
		clock.advance(float(item[0]))
		assert_true(qte.input(2, clock.qte_sec, "primary", false).ok)
		var result := qte.finish()
		assert_almost_eq(result.data.held_sec, float(item[0]), 0.0000001)
		assert_almost_eq(result.data.quality, float(item[1]), 0.0000001, str(item))

func test_charge_early_overcharge_and_timeout_reasons() -> void:
	for item in [[0.5, "EARLY_RELEASE"], [2.5, "OVERCHARGED"]]:
		var clock := Clock.new()
		var qte := make("charge", clock)
		qte.start()
		qte.input(1, 0.0, "primary", true)
		clock.advance(float(item[0]))
		qte.input(2, clock.qte_sec, "primary", false)
		assert_eq(qte.finish().data.reason, item[1])
	var clock := Clock.new()
	var qte := make("charge", clock)
	qte.start()
	qte.input(1, 0.0, "primary", true)
	clock.advance(20.0)
	var result := qte.finish()
	assert_eq(result.data.reason, "TIMEOUT")
	assert_eq(result.data.quality, 0.0)
	assert_eq(result.data.elapsed_sec, 4.0)

func test_charge_pause_preserves_active_time_and_needs_fresh_press() -> void:
	var clock := Clock.new()
	var qte := make("charge", clock)
	qte.start()
	qte.input(1, 0.0, "primary", true)
	clock.advance(0.6)
	clock.paused = true
	clock.advance(80.0)
	assert_eq(qte.input(2, clock.qte_sec, "primary", false).code, "PAUSED")
	assert_almost_eq(qte.update().data.held_sec, 0.6, 0.0000001)
	assert_false(qte.update().data.ready_to_finish)
	clock.paused = false
	clock.advance(0.5)
	assert_almost_eq(qte.update().data.held_sec, 0.6, 0.0000001)
	qte.input(2, clock.qte_sec, "primary", true)
	clock.advance(0.6)
	qte.input(3, clock.qte_sec, "primary", false)
	assert_almost_eq(qte.finish().data.quality, 1.0, 0.0000001)

func test_window_perfect_good_early_and_late_edges() -> void:
	for error in [-0.140001, -0.14, -0.060001, -0.06, 0.06, 0.060001, 0.14, 0.140001]:
		var clock := Clock.new()
		var qte := make("window", clock, "starch")
		qte.start()
		clock.advance(1.8 + error)
		qte.input(1, clock.qte_sec, "primary", true)
		var result := qte.finish()
		if absf(error) <= 0.06:
			assert_eq(result.data.grade, "perfect", str(error))
		elif absf(error) <= 0.14:
			assert_eq(result.data.grade, "good", str(error))
		else:
			assert_eq(result.data.grade, "miss", str(error))
			assert_eq(result.data.reason, "EARLY_PRESS" if error < 0.0 else "LATE_PRESS")

func test_window_resolves_once_and_result_time_does_not_drift() -> void:
	var clock := Clock.new()
	var qte := make("window", clock)
	qte.start()
	clock.advance(1.8)
	qte.input(1, clock.qte_sec, "primary", true)
	assert_eq(qte.input(2, clock.qte_sec, "primary", false).code, "READY_TO_FINISH")
	clock.advance(10.0)
	var result := qte.finish()
	assert_almost_eq(result.data.elapsed_sec, 1.8, 0.0000001)
	assert_eq(result.data.quality, 1.0)

func test_rhythm_final_right_edge_can_receive_input_after_update() -> void:
	var clock := Clock.new()
	var qte := make("rhythm", clock)
	qte.start()
	clock.advance(2.64)
	assert_true(qte.update().data.ready_to_finish)
	assert_eq(qte.input(1, clock.qte_sec, "primary", true).data.judgement, "good")
	var result := qte.finish()
	assert_eq(result.data.good, 1)
	assert_eq(result.data.miss, 3)
	assert_almost_eq(result.data.quality, 0.15, 0.0000001)

func test_rhythm_duplicate_held_and_wrong_action_cannot_add_hits() -> void:
	var clock := Clock.new()
	var qte := make("rhythm", clock)
	qte.start()
	clock.advance(1.0)
	assert_eq(qte.input(1, clock.qte_sec, "up", true).code, "INVALID_ACTION")
	assert_true(qte.input(1, clock.qte_sec, "primary", true).ok)
	assert_eq(qte.input(1, clock.qte_sec, "primary", true).code, "STALE_INPUT")
	clock.advance(0.5)
	assert_eq(qte.input(2, clock.qte_sec, "primary", true).code, "HELD_INPUT")
	assert_eq(qte.update().data.hits, 1)
	qte.input(3, clock.qte_sec, "primary", false)
	assert_true(qte.input(4, clock.qte_sec, "primary", true).ok)
	assert_eq(qte.update().data.hits, 2)

func test_rhythm_extra_presses_break_combo_and_have_explicit_penalty() -> void:
	var clock := Clock.new()
	var qte := make("rhythm", clock)
	qte.start()
	clock.advance(1.0)
	qte.input(1, clock.qte_sec, "primary", true)
	qte.input(2, clock.qte_sec, "primary", false)
	clock.advance(0.25)
	assert_eq(qte.input(3, clock.qte_sec, "primary", true).code, "OUTSIDE_WINDOW")
	assert_eq(qte.update().data.combo, 0)
	qte.input(4, clock.qte_sec, "primary", false)
	clock.advance(0.35)
	qte.input(5, clock.qte_sec, "primary", true)
	clock.advance(2.0)
	var result := qte.finish()
	assert_eq(result.data.perfect, 1)
	assert_eq(result.data.good, 1)
	assert_eq(result.data.miss, 2)
	assert_eq(result.data.extra_inputs, 1)
	assert_eq(result.data.max_combo, 1)
	assert_almost_eq(result.data.quality, 0.32, 0.0000001)

func test_rhythm_perfect_sequence_has_max_combo_and_grade() -> void:
	var clock := Clock.new()
	var qte := make("rhythm", clock)
	qte.start()
	clock.advance(1.0)
	for index in 4:
		qte.input(index * 2 + 1, clock.qte_sec, "primary", true)
		qte.input(index * 2 + 2, clock.qte_sec, "primary", false)
		clock.advance(0.5)
	var result := qte.finish()
	assert_eq(result.data.max_combo, 4)
	assert_eq(result.data.grade, "perfect")
	assert_eq(result.data.reason, "ALL_HIT")

func test_offset_applies_to_rhythm_and_window_with_nonzero_clock_origin() -> void:
	for kind in ["rhythm", "window"]:
		var clock := Clock.new()
		clock.advance(10.0)
		var settings := config(kind)
		settings.input_offset_sec = 0.1
		var qte := QTE.new(request(), settings, clock, FixedRandom.new())
		qte.start()
		clock.advance(1.1 if kind == "rhythm" else 1.9)
		assert_eq(qte.input(1, clock.qte_sec, "primary", true).data.judgement, "perfect")

func test_maintain_visible_disturbance_and_hand_calculated_integral() -> void:
	var clock := Clock.new()
	var qte := make("maintain", clock, "heat")
	assert_almost_eq(qte.start().data.power, 0.75, 0.0000001)
	clock.advance(1.0)
	assert_almost_eq(qte.update().data.power, 0.5, 0.0000001)
	clock.advance(1.0)
	assert_almost_eq(qte.update().data.power, 0.25, 0.0000001)
	clock.advance(2.0)
	var result := qte.finish()
	# One triangular cycle mean .5 for four seconds; target .4-.6 covers 40%.
	assert_almost_eq(result.data.heat_dose, 2.0, 0.0000001)
	assert_almost_eq(result.data.inside_sec, 1.6, 0.0000001)
	assert_almost_eq(result.data.quality, 0.4, 0.0000001)
	assert_eq(result.data.grade, "miss")

func test_maintain_adjustment_changes_actual_dose_and_clamps_power() -> void:
	var clock := Clock.new()
	var qte := make("maintain", clock, "boil")
	qte.start()
	qte.input(1, 0.0, "adjust", true, 1.0)
	clock.advance(100.0)
	var result := qte.finish()
	# Clamped high half-cycle is 1, low half-cycle averages .875.
	assert_almost_eq(result.data.heat_dose, 3.75, 0.0000001)
	assert_eq(result.data.quality, 0.0)
	assert_eq(result.data.end_power, 1.0)
	assert_eq(result.data.elapsed_sec, 4.0)

func test_maintain_update_partition_does_not_change_result() -> void:
	var clock_a := Clock.new()
	var clock_b := Clock.new()
	var a := make("maintain", clock_a)
	var b := make("maintain", clock_b)
	a.start()
	b.start()
	clock_a.advance(0.731)
	a.input(1, clock_a.qte_sec, "adjust", true, 0.63)
	clock_a.advance(3.269)
	for index in 73:
		clock_b.advance(0.01)
		b.update()
	clock_b.advance(0.001)
	b.input(1, clock_b.qte_sec, "adjust", true, 0.63)
	for index in 326:
		clock_b.advance(0.01)
		b.update()
	clock_b.advance(0.009)
	var result_a := a.finish().data
	var result_b := b.finish().data
	assert_almost_eq(result_a.heat_dose, result_b.heat_dose, 0.00000001)
	assert_almost_eq(result_a.inside_sec, result_b.inside_sec, 0.00000001)
	assert_almost_eq(result_a.quality, result_b.quality, 0.00000001)

func test_seeded_random_is_reproducible_and_samples_once_at_start() -> void:
	var clock_a := Clock.new()
	var clock_b := Clock.new()
	var a := QTE.new(request(), config("maintain"), clock_a, Random.new(4321))
	var b := QTE.new(request(), config("maintain"), clock_b, Random.new(4321))
	assert_eq(a.start().data.power, b.start().data.power)
	clock_a.advance(4.0)
	clock_b.advance(4.0)
	assert_eq(a.finish().data, b.finish().data)
	var source := FixedRandom.new()
	var qte := QTE.new(request(), config("maintain"), Clock.new(), source)
	assert_eq(source.calls, 0)
	qte.start()
	qte.start()
	qte.update()
	assert_eq(source.calls, 1)

func test_sequence_wrong_repeat_and_corrected_order_are_explained() -> void:
	var clock := Clock.new()
	var qte := make("sequence", clock, "season")
	qte.start()
	assert_eq(qte.input(1, 0.0, "left", true).code, "WRONG_STEP")
	assert_eq(qte.input(2, 0.0, "left", true).code, "HELD_INPUT")
	qte.input(3, 0.0, "left", false)
	assert_eq(qte.update().data.next_action, "up")
	var index := 4
	for action in ["up", "left", "down", "right"]:
		assert_true(qte.input(index, clock.qte_sec, action, true).ok)
		index += 1
	var result := qte.finish()
	assert_eq(result.data.wrong, 1)
	assert_eq(result.data.correct, 4)
	assert_eq(result.data.missing, 0)
	assert_eq(result.data.reason, "CORRECTED_SEQUENCE")
	assert_almost_eq(result.data.quality, 0.8, 0.0000001)

func test_sequence_timeout_retains_partial_progress_and_missing_steps() -> void:
	var clock := Clock.new()
	var qte := make("sequence", clock)
	qte.start()
	qte.input(1, 0.0, "up", true)
	qte.input(2, 0.0, "left", true)
	clock.advance(8.0)
	var result := qte.finish()
	assert_eq(result.data.correct, 2)
	assert_eq(result.data.missing, 2)
	assert_eq(result.data.reason, "MISSING_STEPS")
	assert_eq(result.data.quality, 0.5)

func test_sequence_right_boundary_accepts_final_step() -> void:
	var clock := Clock.new()
	var qte := make("sequence", clock)
	qte.start()
	qte.input(1, 0.0, "up", true)
	qte.input(2, 0.0, "left", true)
	qte.input(3, 0.0, "down", true)
	clock.advance(5.0)
	qte.update()
	assert_true(qte.input(4, clock.qte_sec, "right", true).ok)
	assert_eq(qte.finish().data.grade, "perfect")

func test_all_types_cancel_reset_reject_old_sequence_and_clear_state() -> void:
	for kind in QTE.KINDS:
		var clock := Clock.new()
		var qte := make(kind, clock)
		qte.start()
		clock.advance(0.1)
		assert_true(qte.cancel().ok)
		assert_eq(qte.cancel().code, "CANCELLED")
		assert_eq(qte.update().code, "CANCELLED")
		assert_eq(qte.input(1, clock.qte_sec, "primary", true).code, "CANCELLED")
		assert_true(qte.reset(request("plate", "next-operation"), config(kind), clock, FixedRandom.new()).ok)
		var progress := qte.start().data
		assert_eq(progress.operation_id, "next-operation")
		assert_eq(progress.elapsed_sec, 0.0)
		assert_eq(progress.quality, 0.0)
		assert_eq(progress.status, "running")

func test_clock_and_input_corruption_do_not_mutate_progress() -> void:
	for kind in QTE.KINDS:
		var clock := Clock.new()
		var qte := make(kind, clock)
		qte.start()
		var action := "adjust" if kind == "maintain" else ("up" if kind == "sequence" else "primary")
		assert_eq(qte.input(1, NAN, action, true).code, "INVALID_INPUT")
		assert_eq(qte.input(1, 0.0, action, true, INF).code, "INVALID_INPUT")
		assert_eq(qte.input(1, 0.0, action, true, -0.1).code, "INVALID_INPUT")
		assert_eq(qte.input(1, 0.5, action, true).code, "STALE_INPUT")
		clock.qte_sec = NAN
		assert_eq(qte.update().code, "INVALID_CLOCK")
		clock.qte_sec = 1.0
		qte.update()
		clock.qte_sec = 0.5
		assert_eq(qte.update().code, "INVALID_CLOCK")
		clock.qte_sec = 1.0
		assert_eq(qte.input(1, 0.5, action, true).code, "STALE_INPUT")
		assert_eq(qte.update().data.elapsed_sec, 1.0)

func test_configuration_ranges_and_missing_fields_fail_before_start() -> void:
	for kind in QTE.KINDS:
		var settings := config(kind)
		for field in settings.keys():
			if field == "kind":
				continue
			var bad := settings.duplicate(true)
			bad[field] = NAN
			assert_eq(QTE.new(request(), bad, Clock.new(), FixedRandom.new()).start().code, "INVALID_CONFIG", kind + ":" + field)
	var invalids := [
		{"kind": "unknown"},
		{"kind": "sequence", "sequence": [], "timeout_sec": 5.0},
		{"kind": "sequence", "sequence": ["north"], "timeout_sec": 5.0},
		{"kind": "sequence", "sequence": ["up"], "timeout_sec": 0.0}]
	for settings in invalids:
		assert_eq(QTE.new(request(), settings, Clock.new(), FixedRandom.new()).start().code, "INVALID_CONFIG")
	var old_request := request()
	old_request.schema_version = 2
	assert_eq(QTE.new(old_request, config("rhythm"), Clock.new(), FixedRandom.new()).start().code, "INVALID_CONFIG")
	assert_eq(QTE.new(request(), config("maintain"), Clock.new(), null).start().code, "INVALID_CONFIG")
	assert_eq(QTE.new(request(), config("maintain"), Clock.new(), FixedRandom.new(NAN)).start().code, "INVALID_RANDOM")

func test_config_and_progress_arrays_are_isolated_copies() -> void:
	var clock := Clock.new()
	var settings := config("sequence")
	var qte := QTE.new(request(), settings, clock, FixedRandom.new())
	settings.sequence[0] = "right"
	var result := qte.start()
	result.data.sequence[0] = "left"
	assert_eq(qte.update().data.next_action, "up")
	assert_true(qte.input(1, 0.0, "up", true).ok)

func test_pause_freezes_all_types_and_releases_transient_buttons() -> void:
	for kind in QTE.KINDS:
		var clock := Clock.new()
		var qte := make(kind, clock)
		qte.start()
		clock.advance(0.5)
		clock.paused = true
		clock.advance(100.0)
		assert_eq(qte.update().data.elapsed_sec, 0.5)
		assert_eq(qte.finish().code, "PAUSED")
		assert_eq(qte.input(1, clock.qte_sec, "primary", true).code, "PAUSED")
		clock.paused = false
		clock.advance(0.25)
		assert_eq(qte.update().data.elapsed_sec, 0.75)

func test_all_types_long_frame_and_time_partition_match() -> void:
	for kind in QTE.KINDS:
		var clock_a := Clock.new()
		var clock_b := Clock.new()
		var a := make(kind, clock_a)
		var b := make(kind, clock_b)
		a.start()
		b.start()
		clock_a.advance(10.0)
		for index in 100:
			clock_b.advance(0.1)
			b.update()
		var result_a := a.finish().data
		var result_b := b.finish().data
		assert_almost_eq(result_a.quality, result_b.quality, 0.0000001, kind)
		assert_eq(result_a.reason, result_b.reason, kind)
		assert_eq(result_a.elapsed_sec, result_b.elapsed_sec, kind)

func test_sequence_error_weight_is_configurable_and_same_direction_needs_release() -> void:
	var clock := Clock.new()
	var settings := config("sequence")
	settings.sequence = ["up", "up"]
	settings.error_weight = 2.0
	var qte := QTE.new(request(), settings, clock, FixedRandom.new())
	qte.start()
	qte.input(1, 0.0, "left", true)
	qte.input(2, 0.0, "up", true)
	assert_eq(qte.input(3, 0.0, "up", true).code, "HELD_INPUT")
	assert_eq(qte.update().data.correct, 1)
	qte.input(4, 0.0, "up", false)
	qte.input(5, 0.0, "up", true)
	assert_almost_eq(qte.finish().data.quality, 0.5, 0.0000001)
