extends GutTest
const Clock = preload("res://src/platform/session_clock.gd")
const Random = preload("res://src/platform/business_random.gd")
const Probe = preload("res://src/qte/hold_probe.gd")
const Sample = preload("res://src/contracts/input_sample.gd")
const Request = preload("res://src/contracts/operation_request.gd")
const Catalog = preload("res://src/content/sample_catalog.gd")

class FixedRandom extends RefCounted:
	func unit() -> float:
		return 0.5

func make_probe(clock):
	var catalog := Catalog.new()
	catalog.load_file("res://content/dev_samples.json")
	return Probe.new(Request.new("s1", 1, "op1", "probe_hold", 0), catalog.get_template("dev.hold_probe"), clock, FixedRandom.new())

func test_pause_real_time_and_invalid_delta() -> void:
	var clock := Clock.new()
	assert_true(clock.advance(0.5))
	clock.paused = true
	clock.advance(1.0)
	assert_eq(clock.real_sec, 1.5)
	assert_eq(clock.game_sec, 0.5)
	assert_eq(clock.qte_sec, 0.5)
	assert_false(clock.advance(-1.0))
	assert_false(clock.advance(INF))
	clock.paused = false
	clock.advance(0.5)
	assert_eq(clock.game_sec, 1.0)

func test_continuous_input_updates_before_final_result() -> void:
	var clock := Clock.new()
	var probe = make_probe(clock)
	assert_almost_eq(probe.target_sec, 1.5, 0.0001)
	assert_true(probe.input(Sample.new("s1", 1, "op1", 1, 0.0, 1.0)).ok)
	clock.advance(0.4)
	var frame = probe.advance()
	assert_eq(frame.status, "running")
	assert_almost_eq(frame.held_sec, 0.4, 0.0001)
	clock.advance(2.0)
	frame = probe.advance()
	assert_eq(frame.status, "completed")
	assert_almost_eq(frame.held_sec, 1.5, 0.0001)
	assert_null(probe.advance(), "terminal controller must not emit twice")

func test_timeout_cancel_and_stale_input() -> void:
	var clock := Clock.new()
	var probe = make_probe(clock)
	assert_eq(probe.input(Sample.new("s2", 1, "op1", 1, 0.0, 1.0)).code, "STALE_INPUT")
	clock.advance(10.0)
	assert_eq(probe.advance().status, "timed_out")
	assert_false(probe.input(Sample.new("s1", 1, "op1", 2, 10.0, 1.0)).ok)
	probe = make_probe(Clock.new())
	probe.cancel()
	assert_null(probe.advance())

func test_fractional_input_split_time_and_pause_release() -> void:
	var clock := Clock.new()
	var probe = make_probe(clock)
	probe.input(Sample.new("s1", 1, "op1", 1, 0.0, 0.5))
	for index in 10:
		clock.advance(0.1)
		probe.advance()
	assert_almost_eq(probe.held_sec, 0.5, 0.0001)
	probe.release_input()
	clock.paused = true
	clock.advance(5.0)
	probe.advance()
	clock.paused = false
	clock.advance(0.2)
	probe.advance()
	assert_almost_eq(probe.held_sec, 0.5, 0.0001)

func test_duplicate_and_invalid_input_are_rejected() -> void:
	var clock := Clock.new()
	var probe = make_probe(clock)
	assert_true(probe.input(Sample.new("s1", 1, "op1", 1, 0.0, 1.0)).ok)
	assert_eq(probe.input(Sample.new("s1", 1, "op1", 1, 0.0, 1.0)).code, "STALE_INPUT")
	assert_false(probe.input(Sample.new("s1", 1, "op1", 2, 0.0, NAN)).ok)

func test_seed_reproducibility_and_independence() -> void:
	var one := Random.new(42)
	var two := Random.new(42)
	for index in 10:
		assert_eq(one.unit(), two.unit())
	var isolated := Random.new(42)
	assert_eq(isolated.unit(), Random.new(42).unit())
	one.unit()
	assert_ne(one.unit(), Random.new(42).unit())

func test_time_partition_invariance_and_timeout_edge() -> void:
	var one_clock := Clock.new()
	var two_clock := Clock.new()
	var one = make_probe(one_clock)
	var two = make_probe(two_clock)
	one.input(Sample.new("s1", 1, "op1", 1, 0.0, 1.0))
	two.input(Sample.new("s1", 1, "op1", 1, 0.0, 1.0))
	one_clock.advance(1.0)
	one.advance()
	for index in 10:
		two_clock.advance(0.1)
		two.advance()
	assert_almost_eq(one.held_sec, two.held_sec, 0.000001)
	var timeout_clock := Clock.new()
	var timeout_probe = make_probe(timeout_clock)
	timeout_clock.advance(5.999)
	assert_eq(timeout_probe.advance().status, "running")
	timeout_clock.advance(0.001)
	assert_eq(timeout_probe.advance().status, "timed_out")
