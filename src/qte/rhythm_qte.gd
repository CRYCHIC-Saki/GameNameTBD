class_name TDRhythmQTE
extends RefCounted
## Pure rhythm controller. Times are absolute TDClock.qte_sec seconds.
## The caller owns audio playback and supplies the same calibrated time domain.

const EPSILON := 0.000000001

var _request: Dictionary = {}
var _config: Dictionary = {}
var _clock: TDClock
var _state := "ready"
var _valid := false
var _start_sec := 0.0
var _last_sec := 0.0
var _elapsed_sec := 0.0
var _duration_sec := 0.0
var _sequence := 0
var _pressed := false
var _beats: Array[float] = []
var _judgements: Array[String] = []
var _perfect := 0
var _good := 0
var _miss := 0

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
	_last_sec = 0.0
	_elapsed_sec = 0.0
	_sequence = 0
	_pressed = false
	_beats.clear()
	_judgements.clear()
	_perfect = 0
	_good = 0
	_miss = 0
	_valid = _valid_config()
	if not _valid:
		return TDOutcome.new(false, "INVALID_CONFIG", "Invalid rhythm configuration, request or clock.")
	for index in int(_config.beats):
		_beats.append(float(_config.lead_in_sec) + float(index) * float(_config.interval_sec))
		_judgements.append("pending")
	_duration_sec = _beats.back() + float(_config.good_sec) + float(_config.input_offset_sec)
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
	_last_sec = _start_sec
	_state = "running"
	return TDOutcome.new(true, "STARTED", "", _progress())

func input(sequence: int, timestamp_sec: float, value: float) -> TDOutcome:
	var gate := _running_gate()
	if gate != "":
		return TDOutcome.new(false, gate)
	if not is_finite(_clock.qte_sec) or _clock.qte_sec < _last_sec - EPSILON:
		return TDOutcome.new(false, "INVALID_CLOCK")
	if _clock.paused:
		release_input()
		return TDOutcome.new(false, "PAUSED")
	if not is_finite(timestamp_sec) or not is_finite(value) or value < 0.0 or value > 1.0:
		return TDOutcome.new(false, "INVALID_INPUT")
	if sequence <= _sequence or timestamp_sec < _last_sec - EPSILON or timestamp_sec > _clock.qte_sec + EPSILON:
		return TDOutcome.new(false, "STALE_INPUT")
	_sequence = sequence
	_last_sec = timestamp_sec
	_update_time(timestamp_sec)
	if value == 0.0:
		_pressed = false
		return TDOutcome.new(true, "RELEASED", "", _progress())
	if _pressed:
		return TDOutcome.new(false, "HELD_INPUT")
	_pressed = true
	var adjusted_sec := timestamp_sec - _start_sec - float(_config.input_offset_sec)
	var nearest := -1
	var nearest_distance := INF
	for index in _beats.size():
		if _judgements[index] != "pending":
			continue
		var distance := absf(adjusted_sec - _beats[index])
		if distance <= float(_config.good_sec) + EPSILON and distance < nearest_distance:
			nearest = index
			nearest_distance = distance
	if nearest < 0:
		return TDOutcome.new(false, "OUTSIDE_WINDOW", "", _progress())
	var judgement := "good"
	if nearest_distance <= float(_config.perfect_sec) + EPSILON:
		judgement = "perfect"
		_perfect += 1
	else:
		_good += 1
	_judgements[nearest] = judgement
	var values := _progress()
	values["judgement"] = judgement
	values["beat_index"] = nearest
	values["error_sec"] = adjusted_sec - _beats[nearest]
	return TDOutcome.new(true, "HIT", "", values)

func update() -> TDOutcome:
	var gate := _running_gate()
	if gate != "":
		return TDOutcome.new(false, gate)
	if not is_finite(_clock.qte_sec) or _clock.qte_sec < _last_sec - EPSILON:
		return TDOutcome.new(false, "INVALID_CLOCK")
	# Frozen clock time still includes any active interval before the pause.
	_update_time(_clock.qte_sec)
	_last_sec = _clock.qte_sec
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
	for index in _judgements.size():
		if _judgements[index] == "pending":
			_judgements[index] = "miss"
			_miss += 1
	_state = "completed"
	release_input()
	var values := _progress()
	values["status"] = "completed"
	values["kind"] = "cut"
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
	_pressed = false

func _update_time(timestamp_sec: float) -> void:
	_elapsed_sec = clampf(timestamp_sec - _start_sec, 0.0, _duration_sec)
	var adjusted_sec := timestamp_sec - _start_sec - float(_config.input_offset_sec)
	for index in _beats.size():
		if _judgements[index] == "pending" and adjusted_sec > _beats[index] + float(_config.good_sec) + EPSILON:
			_judgements[index] = "miss"
			_miss += 1

func _progress() -> Dictionary:
	var values := _request.duplicate(true)
	var next_beat_sec := -1.0
	for index in _beats.size():
		if _judgements[index] == "pending":
			next_beat_sec = _beats[index]
			break
	values.merge({"status": _state, "elapsed_sec": _elapsed_sec,
		"progress": clampf(_elapsed_sec / _duration_sec, 0.0, 1.0),
		"ready_to_finish": _elapsed_sec >= _duration_sec - EPSILON,
		"perfect": _perfect, "good": _good, "miss": _miss, "hits": _perfect + _good,
		"quality": (float(_perfect) + float(_good) * float(_config.get("good_quality", 0.6))) / float(_beats.size()),
		"next_beat_sec": next_beat_sec, "beat_times_sec": _beats.duplicate(),
		"judgements": _judgements.duplicate()}, true)
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
	if _clock == null or _request.is_empty() or _request.get("schema_version") != 2 or _request.get("kind") != "cut":
		return false
	if str(_request.session_id).is_empty() or str(_request.operation_id).is_empty() or int(_request.generation) < 0:
		return false
	for field in ["beats", "interval_sec", "lead_in_sec", "perfect_sec", "good_sec", "input_offset_sec"]:
		if not _number(_config.get(field)):
			return false
	if not _number(_config.get("good_quality", 0.6)):
		return false
	var beats := float(_config.beats)
	var interval := float(_config.interval_sec)
	var lead_in := float(_config.lead_in_sec)
	var perfect := float(_config.perfect_sec)
	var good := float(_config.good_sec)
	var offset := float(_config.input_offset_sec)
	var good_quality := float(_config.get("good_quality", 0.6))
	return beats >= 1.0 and beats <= 1024.0 and beats == floorf(beats) \
		and interval > 0.0 and lead_in >= 0.0 and perfect >= 0.0 and good > 0.0 \
		and perfect <= good and good * 2.0 < interval and lead_in + offset >= 0.0 \
		and absf(offset) <= 1.0 and good_quality >= 0.0 and good_quality <= 1.0 \
		and is_finite(lead_in + (beats - 1.0) * interval + good + offset)

func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))
