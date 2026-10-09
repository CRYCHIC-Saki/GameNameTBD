class_name TDHoldProbe
extends RefCounted

var target_sec: float
var held_sec: float = 0.0
var _request: Dictionary
var _clock: TDClock
var _timeout_sec: float
var _start_sec: float
var _last_sec: float
var _elapsed_sec: float = 0.0
var _strength: float = 0.0
var _input_sequence: int = 0
var _frame_sequence: int = 0
var _finished: bool = false

func _init(request: TDRequest, template: TDTemplate, clock: TDClock, random_source: RefCounted) -> void:
	_request = {"session_id": request.session_id, "generation": request.generation, "operation_id": request.operation_id}
	_clock = clock
	_timeout_sec = template.timeout_sec
	_start_sec = clock.qte_sec
	_last_sec = clock.qte_sec
	var sample: float = random_source.call("unit")
	target_sec = lerpf(template.target_min_sec, template.target_max_sec, clampf(sample, 0.0, 1.0))

func input(sample: TDInput) -> TDOutcome:
	if _finished:
		return TDOutcome.new(false, "ALREADY_FINISHED")
	if _clock.paused:
		return TDOutcome.new(false, "PAUSED")
	if sample.session_id != _request["session_id"] or sample.generation != _request["generation"] or sample.operation_id != _request["operation_id"]:
		return TDOutcome.new(false, "STALE_INPUT")
	if sample.schema_version != 1 or sample.action != &"probe_hold" or sample.sequence <= _input_sequence:
		return TDOutcome.new(false, "STALE_INPUT")
	if not is_finite(sample.strength) or sample.strength < 0.0 or sample.strength > 1.0:
		return TDOutcome.new(false, "INVALID_INPUT")
	if not is_finite(sample.timestamp_sec) or not is_equal_approx(sample.timestamp_sec, _clock.qte_sec):
		return TDOutcome.new(false, "STALE_INPUT")
	_input_sequence = sample.sequence
	_strength = sample.strength
	return TDOutcome.new(true)

func advance() -> TDFrame:
	if _finished:
		return null
	var delta_sec := maxf(0.0, _clock.qte_sec - _last_sec)
	_last_sec = _clock.qte_sec
	delta_sec = minf(delta_sec, maxf(0.0, _timeout_sec - _elapsed_sec))
	if _strength > 0.0:
		delta_sec = minf(delta_sec, maxf(0.0, target_sec - held_sec) / _strength)
	held_sec += delta_sec * _strength
	_elapsed_sec += delta_sec
	var state := "running"
	if held_sec >= target_sec - 0.000001:
		state = "completed"
	elif _elapsed_sec >= _timeout_sec - 0.000001:
		state = "timed_out"
	_finished = state != "running"
	_frame_sequence += 1
	return TDFrame.new(_request["session_id"], _request["generation"], _request["operation_id"], _frame_sequence, held_sec, _elapsed_sec, state)

func release_input() -> void:
	_strength = 0.0

func cancel() -> void:
	_finished = true
	release_input()
