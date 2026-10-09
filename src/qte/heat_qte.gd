class_name TDHeatQTE
extends RefCounted
## Integrates piecewise constant power by seconds, never by frame count.

const EPSILON := 0.000000001

var _request: Dictionary = {}
var _config: Dictionary = {}
var _clock: TDClock
var _state := "ready"
var _valid := false
var _start_sec := 0.0
var _cursor_sec := 0.0
var _duration_sec := 0.0
var _elapsed_sec := 0.0
var _heat_dose := 0.0
var _target_sec := 0.0
var _power := 0.5
var _sequence := 0

func _init(request: TDRequest, config: Dictionary, clock: TDClock) -> void:
	reset(request, config, clock)

func reset(request: TDRequest, config: Dictionary, clock: TDClock) -> TDOutcome:
	_request = {}
	if request != null:
		_request = {"schema_version": request.schema_version, "session_id": request.session_id,
			"generation": request.generation, "operation_id": request.operation_id, "kind": request.operation}
	_config = config.duplicate(true)
	_clock = clock
	_state = "ready"
	_start_sec = 0.0
	_cursor_sec = 0.0
	_elapsed_sec = 0.0
	_heat_dose = 0.0
	_target_sec = 0.0
	_sequence = 0
	_valid = _valid_config()
	if not _valid:
		return TDOutcome.new(false, "INVALID_CONFIG", "Invalid heat configuration, request or clock.")
	_duration_sec = float(_config.duration_sec)
	_power = float(_config.get("initial_power", 0.5))
	return TDOutcome.new(true, "RESET")

func start() -> TDOutcome:
	if not _valid:
		return TDOutcome.new(false, "INVALID_CONFIG")
	if _state != "ready":
		return TDOutcome.new(false, "ALREADY_STARTED")
	if _clock.paused:
		return TDOutcome.new(false, "PAUSED")
	if not is_finite(_clock.qte_sec) or _clock.qte_sec < 0.0:
		return TDOutcome.new(false, "INVALID_CLOCK")
	_start_sec = _clock.qte_sec
	_cursor_sec = _start_sec
	_state = "running"
	return TDOutcome.new(true, "STARTED", "", _progress())

func input(sequence: int, timestamp_sec: float, value: float) -> TDOutcome:
	var gate := _running_gate()
	if gate != "":
		return TDOutcome.new(false, gate)
	if not is_finite(_clock.qte_sec) or _clock.qte_sec < _cursor_sec - EPSILON:
		return TDOutcome.new(false, "INVALID_CLOCK")
	if _clock.paused:
		release_input()
		return TDOutcome.new(false, "PAUSED")
	if not is_finite(timestamp_sec) or not is_finite(value) or value < 0.0 or value > 1.0:
		return TDOutcome.new(false, "INVALID_INPUT")
	if sequence <= _sequence or timestamp_sec < _cursor_sec - EPSILON or timestamp_sec > _clock.qte_sec + EPSILON:
		return TDOutcome.new(false, "STALE_INPUT")
	if timestamp_sec - _start_sec >= _duration_sec - EPSILON:
		return TDOutcome.new(false, "READY_TO_FINISH")
	_sequence = sequence
	_advance_to(timestamp_sec)
	_power = value
	return TDOutcome.new(true, "INPUT_APPLIED", "", _progress())

func update() -> TDOutcome:
	var gate := _running_gate()
	if gate != "":
		return TDOutcome.new(false, gate)
	if not is_finite(_clock.qte_sec) or _clock.qte_sec < _cursor_sec - EPSILON:
		return TDOutcome.new(false, "INVALID_CLOCK")
	_advance_to(_clock.qte_sec)
	if _clock.paused:
		release_input()
	return TDOutcome.new(true, "PROGRESS", "", _progress())

func finish() -> TDOutcome:
	var progress := update()
	if not progress.ok:
		return progress
	if _clock.paused:
		return TDOutcome.new(false, "PAUSED")
	if not bool(progress.data.ready_to_finish):
		return TDOutcome.new(false, "NOT_READY")
	_state = "completed"
	var values := _progress()
	values["status"] = "completed"
	values["kind"] = "heat"
	values["end_power"] = _power
	return TDOutcome.new(true, "COMPLETED", "", values)

func cancel() -> TDOutcome:
	if _state == "cancelled":
		return TDOutcome.new(false, "CANCELLED")
	if _state == "completed":
		return TDOutcome.new(false, "ALREADY_FINISHED")
	_state = "cancelled"
	release_input()
	return TDOutcome.new(true, "CANCELLED")

func release_input() -> void:
	# Frozen clock time includes the final active interval before the pause.
	# Integrate it before returning to neutral, without consuming paused time.
	if _valid and _state == "running" \
			and is_finite(_clock.qte_sec) and _clock.qte_sec >= _cursor_sec:
		_advance_to(_clock.qte_sec)
	_power = float(_config.get("initial_power", 0.5)) if _valid else 0.5

func _advance_to(timestamp_sec: float) -> void:
	var next_sec := minf(timestamp_sec, _start_sec + _duration_sec)
	var delta_sec := maxf(0.0, next_sec - _cursor_sec)
	_heat_dose += _power * delta_sec
	if _power >= float(_config.target_power_min) and _power <= float(_config.target_power_max):
		_target_sec += delta_sec
	_cursor_sec = maxf(_cursor_sec, next_sec)
	_elapsed_sec = clampf(_cursor_sec - _start_sec, 0.0, _duration_sec)

func _progress() -> Dictionary:
	var values := _request.duplicate(true)
	values.merge({"status": _state, "elapsed_sec": _elapsed_sec,
		"progress": clampf(_elapsed_sec / _duration_sec, 0.0, 1.0),
		"ready_to_finish": _elapsed_sec >= _duration_sec - EPSILON,
		"power": _power, "heat_dose": _heat_dose,
		"quality": clampf(_target_sec / _duration_sec, 0.0, 1.0)}, true)
	return values

func _running_gate() -> String:
	if not _valid:
		return "INVALID_CONFIG"
	if _state == "cancelled":
		return "CANCELLED"
	if _state == "completed":
		return "ALREADY_FINISHED"
	if _state != "running":
		return "NOT_STARTED"
	return ""

func _valid_config() -> bool:
	if _clock == null or _request.is_empty() or _request.get("schema_version") != 2 or _request.get("kind") != "heat":
		return false
	if str(_request.session_id).is_empty() or str(_request.operation_id).is_empty() or int(_request.generation) < 0:
		return false
	for field in ["duration_sec", "target_power_min", "target_power_max"]:
		if not _number(_config.get(field)):
			return false
	if not _number(_config.get("initial_power", 0.5)):
		return false
	return float(_config.duration_sec) > 0.0 and float(_config.target_power_min) >= 0.0 \
		and float(_config.target_power_max) <= 1.0 \
		and float(_config.target_power_min) <= float(_config.target_power_max) \
		and float(_config.get("initial_power", 0.5)) >= 0.0 and float(_config.get("initial_power", 0.5)) <= 1.0

func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))
