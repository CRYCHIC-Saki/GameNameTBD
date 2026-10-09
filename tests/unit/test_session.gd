extends GutTest
const Catalog = preload("res://src/content/sample_catalog.gd")
const Session = preload("res://src/cooking/cooking_session.gd")
const Request = preload("res://src/contracts/operation_request.gd")
const Frame = preload("res://src/contracts/operation_frame.gd")

func template():
	var catalog := Catalog.new()
	catalog.load_file("res://content/dev_samples.json")
	return catalog.get_template("dev.hold_probe")

func request(sid: String = "s1", generation: int = 1):
	return Request.new(sid, generation, "op1", "probe_hold", 0)

func test_sessions_and_snapshot_are_isolated() -> void:
	var source = template()
	var one := Session.new("s1", 1, source)
	var two := Session.new("s2", 1, source)
	one.begin(request())
	one.accept(Frame.new("s1", 1, "op1", 1, 0.5, 0.5, "running"))
	assert_almost_eq(one.snapshot().to_dict()["work_units"], 5.0, 0.0001)
	assert_eq(two.snapshot().to_dict()["work_units"], 0.0)
	var exposed := one.snapshot().to_dict()
	exposed["material"]["metadata"]["labels"].append("bad")
	assert_eq(one.snapshot().to_dict()["material"]["metadata"]["labels"], ["DEV_ONLY"])
	assert_eq(source.material.metadata["labels"], ["DEV_ONLY"])

func test_invalid_begin_has_no_side_effects() -> void:
	var session := Session.new("s1", 1, template())
	assert_eq(session.begin(request("wrong")).code, "WRONG_SESSION")
	var invalid = request()
	invalid.operation = "not_implemented"
	assert_eq(session.begin(invalid).code, "UNSUPPORTED_OPERATION")
	invalid = request()
	invalid.expected_revision = 7
	assert_eq(session.begin(invalid).code, "REVISION_MISMATCH")
	assert_eq(session.snapshot().to_dict()["state"], "ready")

func test_duplicate_completion_is_rejected_once() -> void:
	var session := Session.new("s1", 1, template())
	assert_true(session.begin(request()).ok)
	var frame := Frame.new("s1", 1, "op1", 1, 1.5, 1.5, "completed")
	assert_true(session.accept(frame).ok)
	assert_eq(session.accept(frame).code, "ALREADY_FINISHED")
	assert_eq(session.snapshot().to_dict()["work_units"], 15.0)

func test_cancel_rejects_old_callbacks_and_other_generation() -> void:
	var session := Session.new("s1", 2, template())
	session.begin(request("s1", 2))
	assert_true(session.cancel().ok)
	assert_eq(session.accept(Frame.new("s1", 2, "op1", 1, 1.0, 1.0, "completed")).code, "CANCELLED")
	assert_eq(session.accept(Frame.new("s1", 1, "op1", 1, 1.0, 1.0, "completed")).code, "STALE_OPERATION")
	assert_eq(session.snapshot().to_dict()["work_units"], 0.0)

func test_non_monotonic_or_non_finite_frames_are_atomic() -> void:
	var session := Session.new("s1", 1, template())
	session.begin(request())
	assert_false(session.accept(Frame.new("s1", 1, "op1", 1, NAN, 0.5, "running")).ok)
	assert_true(session.accept(Frame.new("s1", 1, "op1", 1, 0.5, 0.5, "running")).ok)
	assert_eq(session.accept(Frame.new("s1", 1, "op1", 1, 1.0, 1.0, "running")).code, "STALE_FRAME")
	assert_false(session.accept(Frame.new("s1", 1, "op1", 2, 0.2, 0.6, "running")).ok)
	assert_almost_eq(session.snapshot().to_dict()["work_units"], 5.0, 0.0001)

func test_terminal_frames_cannot_fake_zero_work_or_early_timeout() -> void:
	var session := Session.new("s1", 1, template())
	session.begin(request())
	assert_false(session.accept(Frame.new("s1", 1, "op1", 1, 0.0, 0.0, "completed")).ok)
	assert_false(session.accept(Frame.new("s1", 1, "op1", 1, 0.0, 0.1, "timed_out")).ok)
	assert_eq(session.snapshot().to_dict()["state"], "running")
