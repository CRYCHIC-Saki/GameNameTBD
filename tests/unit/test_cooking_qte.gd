extends GutTest

const Clock = preload("res://src/platform/session_clock.gd")
const Request = preload("res://src/contracts/operation_request.gd")
const Rhythm = preload("res://src/qte/rhythm_qte.gd")
const Heat = preload("res://src/qte/heat_qte.gd")

func request(kind: String, oid: String = "operation-1") -> TDRequest:
	var result := Request.new("session-1", 1, oid, kind, 0)
	result.schema_version = 2
	return result

func rhythm_config() -> Dictionary:
	return {"beats": 8, "interval_sec": 0.5, "lead_in_sec": 1.0, "perfect_sec": 0.06,
		"good_sec": 0.14, "good_quality": 0.6, "input_offset_sec": 0.0}

func heat_config() -> Dictionary:
	return {"duration_sec": 6.0, "target_power_min": 0.4, "target_power_max": 0.7, "initial_power": 0.5}

func test_rhythm_inclusive_windows_and_one_microsecond_outside() -> void:
	for edge in [-0.140001, -0.14, -0.060001, -0.06, 0.06, 0.060001, 0.14, 0.140001]:
		var clock := Clock.new()
		var rhythm := Rhythm.new(request("cut"), rhythm_config(), clock)
		assert_true(rhythm.start().ok)
		clock.advance(1.0 + edge)
		var hit := rhythm.input(1, clock.qte_sec, 1.0)
		if absf(edge) <= 0.06:
			assert_eq(hit.data.get("judgement"), "perfect", str(edge))
		elif absf(edge) <= 0.14:
			assert_eq(hit.data.get("judgement"), "good", str(edge))
		else:
			assert_eq(hit.code, "OUTSIDE_WINDOW", str(edge))

func test_rhythm_duplicate_input_and_held_key_do_not_cut_twice() -> void:
	var clock := Clock.new()
	var rhythm := Rhythm.new(request("cut"), rhythm_config(), clock)
	rhythm.start()
	clock.advance(1.0)
	assert_true(rhythm.input(1, clock.qte_sec, 1.0).ok)
	assert_eq(rhythm.input(1, clock.qte_sec, 1.0).code, "STALE_INPUT")
	clock.advance(0.5)
	assert_eq(rhythm.input(2, clock.qte_sec, 1.0).code, "HELD_INPUT")
	assert_true(rhythm.input(3, clock.qte_sec, 0.0).ok)
	assert_true(rhythm.input(4, clock.qte_sec, 1.0).ok)
	assert_eq(rhythm.update().data.hits, 2)

func test_rhythm_hand_calculated_quality_and_result_identity() -> void:
	var clock := Clock.new()
	var rhythm := Rhythm.new(request("cut"), rhythm_config(), clock)
	rhythm.start()
	clock.advance(1.0)
	rhythm.input(1, clock.qte_sec, 1.0)
	rhythm.input(2, clock.qte_sec, 0.0)
	clock.advance(0.6)
	rhythm.input(3, clock.qte_sec, 1.0)
	clock.advance(4.0)
	assert_true(rhythm.update().data.ready_to_finish)
	var result := rhythm.finish()
	assert_true(result.ok)
	assert_eq(result.data.perfect, 1)
	assert_eq(result.data.good, 1)
	assert_eq(result.data.miss, 6)
	assert_almost_eq(result.data.quality, 0.2, 0.000001)
	assert_almost_eq(result.data.elapsed_sec, 4.64, 0.000001)
	assert_eq(result.data.session_id, "session-1")
	assert_eq(result.data.operation_id, "operation-1")
	assert_eq(result.data.schema_version, 2)
	assert_eq(result.data.kind, "cut")
	assert_eq(result.data.status, "completed")
	assert_eq(rhythm.finish().code, "ALREADY_FINISHED")

func test_rhythm_pause_release_cancel_and_reset() -> void:
	var clock := Clock.new()
	var rhythm := Rhythm.new(request("cut"), rhythm_config(), clock)
	assert_eq(rhythm.input(1, 0.0, 1.0).code, "NOT_STARTED")
	rhythm.start()
	assert_eq(rhythm.start().code, "ALREADY_STARTED")
	assert_eq(rhythm.finish().code, "NOT_READY")
	clock.advance(1.0)
	rhythm.input(1, clock.qte_sec, 1.0)
	clock.paused = true
	clock.advance(20.0)
	assert_eq(rhythm.input(2, clock.qte_sec, 1.0).code, "PAUSED")
	assert_almost_eq(rhythm.update().data.elapsed_sec, 1.0, 0.000001)
	clock.paused = false
	clock.advance(0.5)
	assert_true(rhythm.input(2, clock.qte_sec, 1.0).ok)
	assert_true(rhythm.cancel().ok)
	assert_eq(rhythm.finish().code, "CANCELLED")
	assert_eq(rhythm.input(3, clock.qte_sec, 1.0).code, "CANCELLED")
	assert_true(rhythm.reset(request("cut", "new-operation"), rhythm_config(), clock).ok)
	assert_true(rhythm.start().ok)
	clock.advance(5.0)
	var result := rhythm.finish()
	assert_eq(result.data.operation_id, "new-operation")
	assert_eq(result.data.hits, 0)
	assert_eq(result.data.miss, 8)

func test_rhythm_offset_and_clock_origin() -> void:
	var clock := Clock.new()
	clock.advance(10.0)
	var config := rhythm_config()
	config.input_offset_sec = 0.1
	var rhythm := Rhythm.new(request("cut"), config, clock)
	rhythm.start()
	clock.advance(1.1)
	assert_eq(rhythm.input(1, clock.qte_sec, 1.0).data.judgement, "perfect")
	clock.advance(3.54)
	assert_false(rhythm.update().data.ready_to_finish)
	clock.advance(0.1)
	assert_true(rhythm.update().data.ready_to_finish)

func test_rhythm_long_frame_and_partition_are_equivalent() -> void:
	var clock_a := Clock.new()
	var clock_b := Clock.new()
	var a := Rhythm.new(request("cut"), rhythm_config(), clock_a)
	var b := Rhythm.new(request("cut"), rhythm_config(), clock_b)
	a.start()
	b.start()
	clock_a.advance(10.0)
	a.update()
	for index in 100:
		clock_b.advance(0.1)
		b.update()
	assert_eq(a.finish().data, b.finish().data)

func test_rhythm_invalid_configuration_and_input_are_side_effect_free() -> void:
	for field in ["beats", "interval_sec", "lead_in_sec", "perfect_sec", "good_sec", "input_offset_sec", "good_quality"]:
		var config := rhythm_config()
		config[field] = NAN
		assert_eq(Rhythm.new(request("cut"), config, Clock.new()).start().code, "INVALID_CONFIG")
	for field in ["beats", "interval_sec", "good_sec"]:
		var config := rhythm_config()
		config[field] = 0
		assert_eq(Rhythm.new(request("cut"), config, Clock.new()).start().code, "INVALID_CONFIG")
	var clock := Clock.new()
	var rhythm := Rhythm.new(request("cut"), rhythm_config(), clock)
	rhythm.start()
	clock.advance(1.0)
	assert_eq(rhythm.input(1, clock.qte_sec, NAN).code, "INVALID_INPUT")
	assert_eq(rhythm.input(1, NAN, 1.0).code, "INVALID_INPUT")
	assert_eq(rhythm.input(1, 2.0, 1.0).code, "STALE_INPUT")
	assert_true(rhythm.input(1, clock.qte_sec, 1.0).ok)
	assert_eq(rhythm.update().data.hits, 1)

func test_heat_piecewise_integral_and_quality_are_hand_calculated() -> void:
	var clock := Clock.new()
	var heat := Heat.new(request("heat"), heat_config(), clock)
	heat.start()
	clock.advance(2.0)
	assert_true(heat.input(1, clock.qte_sec, 1.0).ok)
	clock.advance(1.0)
	assert_true(heat.input(2, clock.qte_sec, 0.4).ok)
	clock.advance(3.0)
	var progress := heat.update()
	assert_true(progress.data.ready_to_finish)
	assert_almost_eq(progress.data.heat_dose, 3.2, 0.000001)
	var result := heat.finish()
	assert_almost_eq(result.data.quality, 5.0 / 6.0, 0.000001)
	assert_almost_eq(result.data.end_power, 0.4, 0.000001)
	assert_almost_eq(result.data.elapsed_sec, 6.0, 0.000001)
	assert_eq(result.data.kind, "heat")
	assert_eq(heat.finish().code, "ALREADY_FINISHED")

func test_heat_long_frame_integral_clamps_and_is_partition_invariant() -> void:
	var clock_a := Clock.new()
	var clock_b := Clock.new()
	var a := Heat.new(request("heat"), heat_config(), clock_a)
	var b := Heat.new(request("heat"), heat_config(), clock_b)
	a.start()
	b.start()
	a.input(1, 0.0, 0.7)
	b.input(1, 0.0, 0.7)
	clock_a.advance(100.0)
	a.update()
	for index in 100:
		clock_b.advance(0.1)
		b.update()
	var result_a := a.finish().data
	var result_b := b.finish().data
	assert_almost_eq(result_a.heat_dose, 4.2, 0.000001)
	assert_almost_eq(result_b.heat_dose, 4.2, 0.000001)
	assert_almost_eq(result_a.quality, 1.0, 0.000001)
	assert_almost_eq(result_b.quality, 1.0, 0.000001)

func test_heat_pause_releases_input_and_preserves_clock() -> void:
	var clock := Clock.new()
	var heat := Heat.new(request("heat"), heat_config(), clock)
	heat.start()
	heat.input(1, 0.0, 1.0)
	clock.advance(1.0)
	clock.paused = true
	clock.advance(100.0)
	assert_eq(heat.input(2, clock.qte_sec, 1.0).code, "PAUSED")
	assert_almost_eq(heat.update().data.heat_dose, 1.0, 0.000001)
	clock.paused = false
	clock.advance(5.0)
	var result := heat.finish()
	assert_almost_eq(result.data.heat_dose, 3.5, 0.000001)
	assert_almost_eq(result.data.quality, 5.0 / 6.0, 0.000001)

func test_qte_rejects_corrupt_or_reversed_clock_without_changing_state() -> void:
	var clock := Clock.new()
	var heat := Heat.new(request("heat"), heat_config(), clock)
	var rhythm := Rhythm.new(request("cut"), rhythm_config(), clock)
	heat.start()
	rhythm.start()
	clock.qte_sec = NAN
	assert_eq(heat.input(1, 0.0, 1.0).code, "INVALID_CLOCK")
	assert_eq(rhythm.input(1, 0.0, 1.0).code, "INVALID_CLOCK")
	assert_eq(heat.update().code, "INVALID_CLOCK")
	assert_eq(rhythm.update().code, "INVALID_CLOCK")
	clock.qte_sec = 1.0
	assert_true(heat.update().ok)
	assert_true(rhythm.update().ok)
	clock.qte_sec = 0.5
	assert_eq(heat.update().code, "INVALID_CLOCK")
	assert_eq(rhythm.update().code, "INVALID_CLOCK")
	clock.qte_sec = 1.0
	assert_almost_eq(heat.update().data.heat_dose, 0.5, 0.000001)
	assert_eq(rhythm.update().data.hits, 0)

func test_heat_invalid_input_duplicate_cancel_and_reset() -> void:
	var clock := Clock.new()
	var heat := Heat.new(request("heat"), heat_config(), clock)
	assert_eq(heat.finish().code, "NOT_STARTED")
	heat.start()
	assert_eq(heat.finish().code, "NOT_READY")
	assert_eq(heat.input(1, 0.0, -0.1).code, "INVALID_INPUT")
	assert_eq(heat.input(1, 0.0, INF).code, "INVALID_INPUT")
	assert_true(heat.input(1, 0.0, 0.0).ok)
	assert_eq(heat.input(1, 0.0, 1.0).code, "STALE_INPUT")
	clock.advance(1.0)
	heat.update()
	assert_eq(heat.input(2, 0.5, 1.0).code, "STALE_INPUT")
	assert_almost_eq(heat.update().data.heat_dose, 0.0, 0.000001)
	assert_true(heat.cancel().ok)
	assert_eq(heat.update().code, "CANCELLED")
	assert_eq(heat.finish().code, "CANCELLED")
	assert_true(heat.reset(request("heat", "operation-2"), heat_config(), clock).ok)
	heat.start()
	clock.advance(6.0)
	var result := heat.finish()
	assert_eq(result.data.operation_id, "operation-2")
	assert_almost_eq(result.data.heat_dose, 3.0, 0.000001)
	assert_almost_eq(result.data.quality, 1.0, 0.000001)

func test_heat_rejects_zero_duration_bad_ranges_and_nonfinite_configuration() -> void:
	for field in ["duration_sec", "target_power_min", "target_power_max", "initial_power"]:
		var config := heat_config()
		config[field] = NAN
		assert_eq(Heat.new(request("heat"), config, Clock.new()).start().code, "INVALID_CONFIG")
	var config := heat_config()
	config.duration_sec = 0
	assert_eq(Heat.new(request("heat"), config, Clock.new()).start().code, "INVALID_CONFIG")
	config = heat_config()
	config.target_power_min = 0.8
	assert_eq(Heat.new(request("heat"), config, Clock.new()).start().code, "INVALID_CONFIG")
	config = heat_config()
	config.initial_power = 1.1
	assert_eq(Heat.new(request("heat"), config, Clock.new()).start().code, "INVALID_CONFIG")
