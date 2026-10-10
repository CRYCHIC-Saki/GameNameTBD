class_name TDCookingQTE
extends RefCounted
## Schema 3 pure controller. Input timestamps and update share TDClock.qte_sec.
## PROPOSED timing/quality defaults are overrideable content values, not balance facts.

const EPSILON := 0.000000001
const INTEGRATION_HZ := 240.0
const KINDS := ["charge", "rhythm", "window", "maintain", "sequence"]
const DIRECTIONS := ["up", "left", "down", "right"]

var _identity: Dictionary = {}
var _config: Dictionary = {}
var _clock: TDClock
var _random: RefCounted
var _kind := ""
var _state := "ready"
var _valid := false
var _start_sec := 0.0
var _last_sec := 0.0
var _elapsed_sec := 0.0
var _duration_sec := 1.0
var _sequence := 0
var _pressed: Dictionary = {}
var _resolved := false
var _reason := "WAITING"
var _quality := 0.0
var _held_sec := 0.0
var _charge_started := false
var _beats: Array[float] = []
var _judgements: Array[String] = []
var _perfect := 0
var _good := 0
var _miss := 0
var _errors := 0
var _combo := 0
var _max_combo := 0
var _control := 0.5
var _phase := 0.0
var _heat_dose := 0.0
var _inside_sec := 0.0
var _steps: Array[String] = []
var _step_index := 0
var _cut_direction: int = 0
var _cut_directions: Array = []
var _actual_actions: Array = []
var _cursor: float = 0.5
var _attraction: float = 0.0
var _drifts: Array[float] = []
var _cut_actions: Array[String] = []
var _cut_targets: Array[int] = []
var _last_judgement: Dictionary = {}
var _judgement_serial: int = 0
var _control_suspended: bool = false
var _suspended_sec: float = 0.0

func _init(request: TDRequest, config: Dictionary, clock: TDClock, random_source: RefCounted) -> void:
	reset(request, config, clock, random_source)

func reset(request: TDRequest, config: Dictionary, clock: TDClock, random_source: RefCounted) -> TDOutcome:
	_identity = {}
	if request != null:
		_identity = {"schema_version": request.schema_version, "session_id": request.session_id,
			"generation": request.generation, "operation_id": request.operation_id, "kind": request.operation}
	_config = config.duplicate(true)
	_clock = clock
	_random = random_source
	_kind = str(_config.get("kind", ""))
	_state = "ready"
	_start_sec = 0.0
	_last_sec = 0.0
	_elapsed_sec = 0.0
	_duration_sec = 1.0
	_sequence = 0
	_pressed.clear()
	_resolved = false
	_reason = "WAITING"
	_quality = 0.0
	_held_sec = 0.0
	_charge_started = false
	_beats.clear()
	_judgements.clear()
	_perfect = 0
	_good = 0
	_miss = 0
	_errors = 0
	_combo = 0
	_max_combo = 0
	_control = 0.5
	_phase = 0.0
	_heat_dose = 0.0
	_inside_sec = 0.0
	_steps.clear()
	_step_index = 0
	_cut_direction = 0
	_cut_directions.clear()
	_actual_actions.clear()
	_cursor = float(_config.get("initial_value", .5))
	_attraction = 0.0
	_drifts.clear()
	_cut_actions.clear(); _cut_targets.clear(); _last_judgement.clear()
	_judgement_serial = 0; _control_suspended = false; _suspended_sec = 0.0
	_valid = _valid_config()
	if not _valid:
		return _outcome(false, "INVALID_CONFIG")
	match _kind:
		"charge", "window", "sequence":
			_duration_sec = float(_config.timeout_sec)
		"rhythm":
			for index in int(_config.beats):
				_beats.append(float(_config.lead_in_sec) + float(index) * float(_config.interval_sec))
				_judgements.append("pending")
			_duration_sec = _beats.back() + float(_config.good_sec) + _offset()
		"maintain":
			_duration_sec = float(_config.duration_sec)
			_control = float(_config.initial_value)
	if _kind == "sequence":
		for step in _config.sequence:
			_steps.append(str(step))
		if _config.get("on_beat", false):
			for index: int in _steps.size():
				_beats.append(float(_config.lead_in_sec) + index * float(_config.interval_sec))
				_judgements.append("pending")
			_duration_sec = _beats.back() + float(_config.interval_sec) * .5 + maxf(0, _offset())
	if _config.has("beat_times_sec") and _kind in ["sequence","rhythm"]:
		var times: Variant = _config.beat_times_sec
		if not times is Array or times.size() != _beats.size(): _valid = false; return _outcome(false,"INVALID_CONFIG")
		var previous: float = -1
		for value: Variant in times:
			if not _number(value) or float(value) < 0 or float(value) <= previous: _valid = false; return _outcome(false,"INVALID_CONFIG")
			previous = float(value)
		_beats.assign(times)
		_duration_sec = _beats.back() + float(_config.good_sec) + maxf(0,_offset())
	if _config.has("cut_actions"):
		var actions: Variant = _config.cut_actions
		if _kind != "rhythm" or not actions is Array or actions.size() != _beats.size() or "primary" not in actions:
			_valid = false; return _outcome(false,"INVALID_CONFIG")
		var direction: int = 0
		for action: Variant in actions:
			if action not in ["primary","rotate_left","rotate_right"]:
				_valid = false; return _outcome(false,"INVALID_CONFIG")
			_cut_actions.append(action)
			if action != "primary": direction = posmod(direction + (-1 if action == "rotate_left" else 1),3)
			_cut_targets.append(direction)
	if _kind == "charge" and _config.has("charge_preview_sec"):
		_duration_sec = float(_config.charge_preview_sec) + float(_config.start_grace_sec)
	return _outcome(true, "RESET")

func start() -> TDOutcome:
	if not _valid:
		return _outcome(false, "INVALID_CONFIG")
	if _state != "ready":
		return _outcome(false, "ALREADY_STARTED")
	if not is_finite(_clock.qte_sec) or _clock.qte_sec < 0.0:
		return _outcome(false, "INVALID_CLOCK")
	if _clock.paused:
		return _outcome(false, "PAUSED")
	if _kind == "maintain":
		var sample: Variant = _random.call("unit")
		if not _number(sample) or float(sample) < 0.0 or float(sample) >= 1.0:
			return _outcome(false, "INVALID_RANDOM")
		_phase = float(sample)
		if _config.get("attraction", false):
			for index: int in int(ceil(_duration_sec / float(_config.disturbance_period_sec))) + 1:
				var draw: Variant = _random.call("unit")
				if not _number(draw) or float(draw) < 0 or float(draw) >= 1: return _outcome(false, "INVALID_RANDOM")
				_drifts.append((float(draw) * 2 - 1) * float(_config.disturbance_amplitude))
	_start_sec = _clock.qte_sec
	_last_sec = _start_sec
	_state = "running"
	_reason = "RUNNING"
	return _outcome(true, "STARTED")

func input(sequence: int, timestamp_sec: float, action: String, pressed: bool, value: float = 1.0) -> TDOutcome:
	var gate := _running_gate()
	if gate != "":
		return _outcome(false, gate)
	if _clock.paused:
		release_input()
		return _outcome(false, "PAUSED")
	if not is_finite(timestamp_sec) or not is_finite(value) or value < 0.0 or value > 1.0:
		return _outcome(false, "INVALID_INPUT")
	if sequence <= _sequence or timestamp_sec < _last_sec - EPSILON or timestamp_sec > _clock.qte_sec + EPSILON:
		return _outcome(false, "STALE_INPUT")
	if not _action_allowed(action):
		return _outcome(false, "INVALID_ACTION")
	if _resolved or timestamp_sec - _start_sec > _duration_sec + EPSILON:
		return _outcome(false, "READY_TO_FINISH")
	_sequence = sequence
	_advance_to(timestamp_sec)
	_last_sec = timestamp_sec
	if action == "wrong":
		if pressed:
			_errors += 1; _combo = 0
			_judge("miss","WRONG_KEY",action)
		return _outcome(false, "WRONG_LANE")
	if _kind == "maintain":
		if _control_suspended: return _outcome(false,"CONTROL_SUSPENDED")
		if _config.get("attraction", false):
			_control = value
			_attraction = (float(_config.drag_strength) if action == "drag" else float(_config.hover_strength)) if pressed else 0.0
		elif pressed:
			_control = value
		return _outcome(true, "INPUT_APPLIED" if pressed else "RELEASED")
	if _kind == "rhythm" and _cut_actions.is_empty() and _config.get("directional_cut", false) and action in ["rotate_left", "rotate_right"]:
		if pressed and not bool(_pressed.get(action, false)):
			_cut_direction = posmod(_cut_direction + (-1 if action == "rotate_left" else 1), 3)
		_pressed[action] = pressed
		return _outcome(true, "DIRECTION_CHANGED")
	if not pressed:
		var was_pressed := bool(_pressed.get(action, false))
		_pressed[action] = false
		if _kind == "charge" and was_pressed and _charge_started:
			_resolve_charge()
			return _outcome(true, "JUDGED")
		return _outcome(true, "RELEASED")
	if bool(_pressed.get(action, false)):
		return _outcome(false, "HELD_INPUT")
	if _kind == "charge" and _config.has("charge_preview_sec") and not _charge_started and _elapsed_sec < float(_config.charge_preview_sec) - EPSILON:
		return _outcome(false,"PREVIEW")
	_pressed[action] = true
	match _kind:
		"charge":
			if _config.has("charge_preview_sec"):
				# Waiting, actual held time and release tolerance have separate budgets.
				_duration_sec = _elapsed_sec + maxf(0,float(_config.target_max_sec)-_held_sec) + float(_config.good_margin_sec) + .001
			_charge_started = true
			return _outcome(true, "HOLD_STARTED")
		"rhythm":
			return _rhythm_press(timestamp_sec,action)
		"window":
			_resolve_window(timestamp_sec)
			return _outcome(true, "JUDGED")
		"sequence":
			if _config.get("on_beat", false): return _timed_sequence_press(action, timestamp_sec)
			return _sequence_press(action)
	return _outcome(false, "INVALID_ACTION")

func update() -> TDOutcome:
	var gate := _running_gate()
	if gate != "":
		return _outcome(false, gate)
	_advance_to(_clock.qte_sec)
	_last_sec = _clock.qte_sec
	if _clock.paused:
		release_input()
	return _outcome(true, "PROGRESS")

func finish() -> TDOutcome:
	var progress := update()
	if not progress.ok:
		return progress
	if _clock.paused:
		return _outcome(false, "PAUSED")
	if not _ready():
		return _outcome(false, "NOT_READY")
	if not _resolved:
		match _kind:
			"charge", "window":
				_quality = 0.0
				_reason = "TIMEOUT"
				_judge("miss","TIMEOUT","primary")
			"rhythm":
				for index in _judgements.size():
					if _judgements[index] == "pending":
						_judgements[index] = "miss"
						_miss += 1
						_combo = 0
				_reason = "ALL_HIT" if _miss == 0 and _errors == 0 else "MISSED_OR_EXTRA_BEATS"
			"maintain":
				_reason = "STABLE" if _inside_sec >= _duration_sec - EPSILON else "OUTSIDE_TARGET"
				_judge(_grade(_current_quality()),"THERMAL_RESULT","adjust")
			"sequence":
				_reason = "MISSING_STEPS"
		_resolved = true
	_state = "completed"
	_pressed.clear()
	_attraction = 0.0
	return _outcome(true, "COMPLETED")

func set_control_suspended(value: bool) -> void:
	if _kind != "maintain" or _state != "running" or _control_suspended == value: return
	update()
	_control_suspended = value
	_attraction = 0.0
	_pressed.clear()

func cancel() -> TDOutcome:
	if _state == "cancelled":
		return _outcome(false, "CANCELLED")
	if _state == "completed":
		return _outcome(false, "ALREADY_FINISHED")
	_state = "cancelled"
	_reason = "CANCELLED"
	_pressed.clear()
	return _outcome(true, "CANCELLED")

func release_input() -> void:
	# Pause/blur is not a charge release judgement. It preserves active held time,
	# clears transient keys, and requires a fresh press after resuming.
	if _valid and _state == "running" and is_finite(_clock.qte_sec) and _clock.qte_sec >= _last_sec:
		_advance_to(_clock.qte_sec)
		_last_sec = _clock.qte_sec
	_pressed.clear()
	_attraction = 0.0

func _advance_to(timestamp_sec: float) -> void:
	if _resolved:
		return
	var next_sec := clampf(timestamp_sec - _start_sec, 0.0, _duration_sec)
	var delta_sec := maxf(0.0, next_sec - _elapsed_sec)
	if _kind == "charge" and bool(_pressed.get("primary", false)):
		_held_sec += delta_sec
	if _kind == "maintain":
		if _control_suspended:
			_suspended_sec += delta_sec
			_heat_dose += _cursor * delta_sec
		else: _integrate_maintain(_elapsed_sec, next_sec)
	_elapsed_sec = maxf(_elapsed_sec, next_sec)
	if _kind == "rhythm" or (_kind == "sequence" and _config.get("on_beat", false)):
		var adjusted_sec := _elapsed_sec - _offset()
		for index in _beats.size():
			var expiry: float = float(_config.interval_sec) * .5 if _kind == "sequence" and not _config.get("document_rules",false) else float(_config.good_sec)
			if _judgements[index] == "pending" and adjusted_sec > _beats[index] + expiry + EPSILON:
				_judgements[index] = "miss"
				_miss += 1
				_combo = 0
				var action: String = _steps[index] if _kind == "sequence" else (_cut_actions[index] if not _cut_actions.is_empty() else "primary")
				_judge("miss","MISSED_NOTE",action,index,0.0,_start_sec+_beats[index]+expiry+_offset())

func _integrate_maintain(from_sec: float, to_sec: float) -> void:
	# The fixed absolute grid is the simulation model (piecewise constant power),
	# not frame-count scoring. Split frames/input events integrate identical cells.
	var cursor := from_sec
	while cursor < to_sec - EPSILON:
		var cell := int(floor((cursor + EPSILON) * INTEGRATION_HZ))
		var next := minf(to_sec, float(cell + 1) / INTEGRATION_HZ)
		var power := _power_at((float(cell) + 0.5) / INTEGRATION_HZ)
		var duration := maxf(0.0, next - cursor)
		if _config.get("attraction", false):
			_integrate_attraction(duration, (float(cell) + .5) / INTEGRATION_HZ)
			cursor = next
			continue
		_heat_dose += power * duration
		if power >= float(_config.target_min) - EPSILON and power <= float(_config.target_max) + EPSILON:
			_inside_sec += duration
		cursor = next

func _power_at(elapsed: float) -> float:
	if _config.get("attraction", false): return _cursor
	return clampf(_control + _disturbance_at(elapsed), 0.0, 1.0)

func _disturbance_at(elapsed: float) -> float:
	if _config.get("attraction", false):
		return _drifts[mini(_drifts.size() - 1, int(elapsed / float(_config.disturbance_period_sec)))] if not _drifts.is_empty() else 0.0
	var cycle := fposmod(elapsed / float(_config.disturbance_period_sec) + _phase, 1.0)
	return (4.0 * absf(cycle - 0.5) - 1.0) * float(_config.disturbance_amplitude)

func _resolve_charge() -> void:
	var low := float(_config.target_min_sec)
	var high := float(_config.target_max_sec)
	var margin := float(_config.good_margin_sec)
	if _config.get("document_rules",false):
		var center: float = float(_config.get("perfect_center_sec", (low+high)*.5))
		_quality = 1.0 if absf(_held_sec-center) <= float(_config.get("perfect_sec",.05))+EPSILON else (float(_config.good_quality) if _held_sec >= low-EPSILON and _held_sec <= high+EPSILON else 0.0)
		_reason = "TARGET_HOLD" if _quality == 1 else ("NEAR_HOLD" if _quality > 0 else ("EARLY_RELEASE" if _held_sec < low else "OVERCHARGED"))
		_resolved = true
		_judge(_grade(_quality),_reason,"primary",-1,_held_sec-center)
		return
	if _held_sec >= low - EPSILON and _held_sec <= high + EPSILON:
		_quality = 1.0
		_reason = "TARGET_HOLD"
	elif _held_sec >= low - margin - EPSILON and _held_sec <= high + margin + EPSILON:
		_quality = float(_config.get("good_quality", 0.6))
		_reason = "NEAR_HOLD"
	else:
		_quality = 0.0
		_reason = "EARLY_RELEASE" if _held_sec < low else "OVERCHARGED"
	_resolved = true

func _resolve_window(timestamp_sec: float) -> void:
	var error := timestamp_sec - _start_sec - _offset() - float(_config.target_sec)
	if absf(error) <= float(_config.perfect_sec) + EPSILON:
		_quality = 1.0
		_reason = "PERFECT_WINDOW"
	elif absf(error) <= float(_config.good_sec) + EPSILON:
		_quality = float(_config.get("good_quality", 0.6))
		_reason = "GOOD_WINDOW"
	else:
		_quality = 0.0
		_reason = "EARLY_PRESS" if error < 0.0 else "LATE_PRESS"
	_resolved = true
	_judge(_grade(_quality),_reason,"primary",-1,error)

func _rhythm_press(timestamp_sec: float, action: String = "primary") -> TDOutcome:
	var adjusted := timestamp_sec - _start_sec - _offset()
	var nearest := -1
	var distance := INF
	for index in _beats.size():
		if _judgements[index] != "pending":
			continue
		var candidate := absf(adjusted - _beats[index])
		if candidate <= float(_config.good_sec) + EPSILON and candidate < distance:
			nearest = index
			distance = candidate
	if nearest < 0:
		_errors += 1
		_combo = 0
		_judge("miss","OUTSIDE_WINDOW",action)
		return _outcome(false, "OUTSIDE_WINDOW")
	var judgement := "good"
	var correct: bool = _cut_actions.is_empty() or action == _cut_actions[nearest]
	var direction_ok: bool = _cut_actions.is_empty() or action != "primary" or _cut_direction == _cut_targets[nearest]
	if not correct or not direction_ok:
		judgement = "miss"; _miss += 1
	elif distance <= float(_config.perfect_sec) + EPSILON:
		judgement = "perfect"
		_perfect += 1
	else:
		_good += 1
	_judgements[nearest] = judgement
	if judgement != "miss" and _config.get("directional_cut", false):
		if action == "primary": _cut_directions.append(_cut_direction)
		else: _cut_direction = posmod(_cut_direction + (-1 if action == "rotate_left" else 1),3)
	_combo = _combo + 1 if judgement != "miss" else 0
	_max_combo = maxi(_max_combo, _combo)
	_judge(judgement,"WRONG_KEY" if not correct else ("WRONG_DIRECTION" if not direction_ok else "TIMING"),action,nearest,adjusted-_beats[nearest])
	var result := _outcome(true, "HIT")
	result.data["judgement"] = judgement
	result.data["beat_index"] = nearest
	result.data["error_sec"] = adjusted - _beats[nearest]
	return result

func _sequence_press(action: String) -> TDOutcome:
	if action != _steps[_step_index]:
		_errors += 1
		_combo = 0
		return _outcome(false, "WRONG_STEP")
	_step_index += 1
	_combo += 1
	_max_combo = maxi(_max_combo, _combo)
	if _step_index == _steps.size():
		_resolved = true
		_reason = "CORRECT_SEQUENCE" if _errors == 0 else "CORRECTED_SEQUENCE"
	return _outcome(true, "STEP_HIT")

func _ready() -> bool:
	return _resolved or _elapsed_sec >= _duration_sec - EPSILON

func _current_quality() -> float:
	if not _valid:
		return 0.0
	var error_weight := float(_config.get("error_weight", 1.0))
	match _kind:
		"rhythm":
			return (float(_perfect) + float(_good) * float(_config.get("good_quality", 0.6))) / maxf(1.0, float(_beats.size()) + float(_errors) * error_weight)
		"maintain":
			var assessed: float = _duration_sec - _suspended_sec
			var ratio: float = clampf(_inside_sec / assessed, 0.0, 1.0) if assessed > EPSILON else 0.0
			if _config.get("document_rules",false): return 1.0 if ratio > .8+EPSILON else (.6 if ratio >= .5-EPSILON else 0.0)
			return ratio
		"sequence":
			if _config.get("on_beat", false):
				var bad: int = _miss + _errors + _judgements.count("pending")
				if _config.get("cabinet", false): return 0.0 if bad > 0 else (1.0 if _good == 0 else float(_config.good_quality))
				bad += _good
				return 1.0 if bad == 0 else (float(_config.good_quality) if bad == 1 else 0.0)
			return float(_step_index) / maxf(1.0, float(_steps.size()) + float(_errors) * error_weight)
	return _quality

func _grade(quality: float) -> String:
	if not _valid:
		return "miss"
	if _kind == "maintain" and _config.get("attraction", false):
		return "perfect" if quality > .8 + EPSILON else ("good" if quality >= .5 - EPSILON else "miss")
	if quality >= float(_config.get("perfect_quality", 0.95)) - EPSILON:
		return "perfect"
	if quality >= float(_config.get("good_grade_quality", 0.6)) - EPSILON:
		return "good"
	return "miss"

func _progress() -> Dictionary:
	var quality := _current_quality()
	var data := _identity.duplicate(true)
	data.merge({"qte_kind": _kind, "status": _state, "quality": quality, "grade": _grade(quality),
		"reason": _reason, "elapsed_sec": _elapsed_sec,
		"progress": 1.0 if _resolved else clampf(_elapsed_sec / _duration_sec, 0.0, 1.0),
		"remaining_sec": 0.0 if _resolved else maxf(0.0, _duration_sec - _elapsed_sec),
		"duration_sec": _duration_sec, "ready_to_finish": _ready()}, true)
	if not _valid:
		return data
	data.pc_module = _config.get("pc_module", "")
	data.input_offset_sec = _offset()
	data.last_judgement = _last_judgement.duplicate(true)
	match _kind:
		"charge":
			data.merge({"held_sec": _held_sec, "target_min_sec": _config.target_min_sec,
				"target_max_sec": _config.target_max_sec, "holding": bool(_pressed.get("primary", false))})
			data.perfect_center_sec = float(_config.get("perfect_center_sec",(float(_config.target_min_sec)+float(_config.target_max_sec))*.5))
			data.perfect_sec = float(_config.get("perfect_sec",.05))
			data.preview_remaining_sec = maxf(0,float(_config.get("charge_preview_sec",0))-_elapsed_sec) if not _charge_started else 0.0
			data.charge_started = _charge_started
		"rhythm":
			var next_beat := -1.0
			for index in _beats.size():
				if _judgements[index] == "pending":
					next_beat = _beats[index]
					break
			data.merge({"beat_times_sec": _beats.duplicate(), "judgements": _judgements.duplicate(),
				"next_beat_sec": next_beat, "perfect": _perfect, "good": _good, "miss": _miss,
				"hits": _perfect + _good, "extra_inputs": _errors, "combo": _combo, "max_combo": _max_combo})
			data.cut_direction = _cut_direction
			data.cut_directions = _cut_directions.duplicate()
			data.cut_actions = _cut_actions.duplicate()
			data.cut_hits = _cut_directions.size()
		"window":
			data.merge({"target_sec": _config.target_sec, "perfect_sec": _config.perfect_sec,
				"good_sec": _config.good_sec, "judgement": _grade(quality) if _resolved else "pending"})
			data.cursor = .5 + .45 * sin(TAU * (_elapsed_sec - float(_config.target_sec)) / float(_config.get("sweep_period_sec", 2)))
			var period: float=float(_config.get("sweep_period_sec",2))
			data.target_min = .5-.45*sin(TAU*float(_config.good_sec)/period)
			data.target_max = .5+.45*sin(TAU*float(_config.good_sec)/period)
		"maintain":
			data.merge({"control": _control, "power": _power_at(_elapsed_sec),
				"end_power": _power_at(_elapsed_sec), "target_min": _config.target_min, "target_max": _config.target_max,
				"disturbance": _disturbance_at(_elapsed_sec), "inside_sec": _inside_sec, "heat_dose": _heat_dose})
			data.attraction = _attraction
			data.control_suspended = _control_suspended
			data.suspended_sec = _suspended_sec
			data.assessed_sec = maxf(0,_elapsed_sec-_suspended_sec)
		"sequence":
			data.merge({"sequence": _steps.duplicate(), "sequence_index": _step_index,
				"next_action": _steps[_step_index] if _step_index < _steps.size() else "",
				"correct": _step_index, "wrong": _errors, "missing": _steps.size() - _step_index,
				"combo": _combo, "max_combo": _max_combo})
			if _config.get("on_beat", false):
				data.beat_times_sec = _beats.duplicate()
				data.judgements = _judgements.duplicate()
				data.actual_actions = _actual_actions.duplicate(true)
				data.sequence_index = _judgements.find("pending")
				data.next_action = _steps[data.sequence_index] if data.sequence_index >= 0 else ""
				data.perfect = _perfect; data.good = _good; data.miss = _miss
	return data

func _outcome(ok: bool, code: String) -> TDOutcome:
	return TDOutcome.new(ok, code, "", _progress())

func _judge(grade: String, reason: String, action: String, index: int = -1, error: float = 0.0, at: float = -1.0) -> void:
	_judgement_serial += 1
	_last_judgement = {"serial":_judgement_serial,"grade":grade,"reason":reason,"action":action,
		"beat_index":index,"error_sec":error,"at_sec":_clock.qte_sec if at < 0 else at}

func _running_gate() -> String:
	if not _valid:
		return "INVALID_CONFIG"
	if _state == "cancelled":
		return "CANCELLED"
	if _state == "completed":
		return "ALREADY_FINISHED"
	if _state != "running":
		return "NOT_STARTED"
	if not is_finite(_clock.qte_sec) or _clock.qte_sec < _last_sec - EPSILON:
		return "INVALID_CLOCK"
	return ""

func _action_allowed(action: String) -> bool:
	if action == "wrong" and _config.has("pc_module"): return true
	if _kind == "maintain":
		return action in ["adjust", "drag", "hover"] if _config.get("attraction", false) else action == "adjust"
	if _kind == "sequence":
		if _config.get("cabinet", false): return action in _config.get("allowed_actions", [])
		if _config.get("on_beat", false): return action in DIRECTIONS or action == "primary"
		return action in DIRECTIONS
	if _kind == "rhythm" and _config.get("directional_cut", false): return action in ["primary", "rotate_left", "rotate_right"]
	return action == "primary"

func _offset() -> float:
	return float(_config.get("input_offset_sec", 0.0))

func _valid_config() -> bool:
	if _clock == null or _identity.is_empty() or _identity.get("schema_version") != 3 or not _kind in KINDS:
		return false
	if str(_identity.session_id).is_empty() or str(_identity.operation_id).is_empty() or str(_identity.kind).is_empty() or int(_identity.generation) < 0:
		return false
	for field in ["input_offset_sec", "good_quality", "perfect_quality", "good_grade_quality", "error_weight"]:
		if _config.has(field) and not _number(_config[field]):
			return false
	if absf(_offset()) > 1.0:
		return false
	if _config.has("charge_preview_sec"):
		if not _number(_config.charge_preview_sec) or not _in_range(float(_config.charge_preview_sec),0,10) or not _number(_config.get("start_grace_sec")) or not _in_range(float(_config.start_grace_sec),.1,10): return false
	if _config.get("on_beat", false):
		for field: String in ["lead_in_sec", "interval_sec", "perfect_sec", "good_sec"]:
			if not _number(_config.get(field)) or float(_config[field]) < 0: return false
		if float(_config.interval_sec) <= 0 or float(_config.good_sec) * 2 >= float(_config.interval_sec) or float(_config.perfect_sec) > float(_config.good_sec): return false
	if _config.get("attraction", false):
		for field: String in ["hover_strength", "drag_strength"]:
			if not _number(_config.get(field)) or float(_config[field]) <= 0 or float(_config[field]) > 30: return false
	if not _in_range(float(_config.get("error_weight", 1.0)), 0.0, 4.0):
		return false
	if not _in_range(float(_config.get("good_quality", 0.6)), 0.0, 1.0) \
		or not _in_range(float(_config.get("good_grade_quality", 0.6)), 0.0, 1.0) \
		or not _in_range(float(_config.get("perfect_quality", 0.95)), float(_config.get("good_grade_quality", 0.6)), 1.0):
		return false
	var fields: Array = []
	match _kind:
		"charge": fields = ["timeout_sec", "target_min_sec", "target_max_sec", "good_margin_sec"]
		"rhythm": fields = ["beats", "interval_sec", "lead_in_sec", "perfect_sec", "good_sec"]
		"window": fields = ["target_sec", "perfect_sec", "good_sec", "timeout_sec"]
		"maintain": fields = ["duration_sec", "target_min", "target_max", "initial_value", "disturbance_amplitude", "disturbance_period_sec"]
		"sequence": fields = ["timeout_sec"]
	for field in fields:
		if not _number(_config.get(field)):
			return false
	match _kind:
		"charge":
			return _positive_duration(float(_config.timeout_sec)) and float(_config.target_min_sec) > 0.0 \
				and float(_config.target_max_sec) >= float(_config.target_min_sec) \
				and float(_config.good_margin_sec) >= 0.0 and float(_config.target_min_sec) > float(_config.good_margin_sec) \
				and float(_config.target_max_sec) + float(_config.good_margin_sec) <= float(_config.timeout_sec)
		"rhythm":
			return _in_range(float(_config.beats), 1.0, 1024.0) and float(_config.beats) == floorf(float(_config.beats)) \
				and float(_config.interval_sec) > 0.0 and float(_config.lead_in_sec) >= 0.0 \
				and float(_config.lead_in_sec) + _offset() >= 0.0 and _timing_windows_valid() \
				and float(_config.good_sec) * 2.0 < float(_config.interval_sec) \
				and _positive_duration(float(_config.lead_in_sec) + (float(_config.beats) - 1.0) * float(_config.interval_sec) + float(_config.good_sec) + _offset())
		"window":
			return _positive_duration(float(_config.timeout_sec)) and float(_config.target_sec) > 0.0 \
				and _timing_windows_valid() and float(_config.target_sec) - float(_config.good_sec) + _offset() >= 0.0 \
				and float(_config.target_sec) + float(_config.good_sec) + _offset() <= float(_config.timeout_sec)
		"maintain":
			return _random != null and _random.has_method("unit") and _positive_duration(float(_config.duration_sec)) \
				and _in_range(float(_config.target_min), 0.0, 1.0) \
				and _in_range(float(_config.target_max), float(_config.target_min), 1.0) \
				and _in_range(float(_config.initial_value), 0.0, 1.0) \
				and float(_config.disturbance_amplitude) > 0.0 and float(_config.disturbance_amplitude) <= 1.0 \
				and float(_config.disturbance_period_sec) >= 0.05
		"sequence":
			if not _positive_duration(float(_config.timeout_sec)) or not _config.get("sequence") is Array:
				return false
			if _config.sequence.is_empty() or _config.sequence.size() > 1024:
				return false
			for action in _config.sequence:
				var allowed: Array = DIRECTIONS.duplicate()
				if _config.get("on_beat", false): allowed.append("primary")
				if _config.get("cabinet", false): allowed = _config.get("allowed_actions", [])
				if not action is String or not action in allowed:
					return false
			return true
	return false

func _timing_windows_valid() -> bool:
	return float(_config.perfect_sec) >= 0.0 and float(_config.good_sec) > 0.0 \
		and float(_config.perfect_sec) <= float(_config.good_sec)

func _positive_duration(value: float) -> bool:
	return value > 0.0 and value <= 120.0

func _in_range(value: float, low: float, high: float) -> bool:
	return value >= low and value <= high

func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

func accepts_primary() -> bool:
	if _kind == "sequence": return str(_progress().get("next_action", "")) == "primary"
	return _kind in ["charge", "rhythm", "window"] and not _resolved

func _timed_sequence_press(action: String, timestamp_sec: float) -> TDOutcome:
	var adjusted: float = timestamp_sec - _start_sec - _offset()
	var nearest: int = -1
	var distance: float = INF
	for index: int in _beats.size():
		var offset: float = absf(adjusted - _beats[index])
		if _judgements[index] == "pending" and offset <= float(_config.interval_sec) * .5 + EPSILON and offset < distance:
			nearest = index; distance = offset
	if nearest < 0:
		_errors += 1; _combo = 0
		_judge("miss","OUTSIDE_WINDOW",action)
		return _outcome(false, "OUTSIDE_WINDOW")
	_actual_actions.append({"action": action, "beat_index": nearest, "error_sec": adjusted - _beats[nearest]})
	var correct: bool = action == _steps[nearest]
	var grade: String = "miss"
	if correct and distance <= float(_config.perfect_sec) + EPSILON:
		grade = "perfect"; _perfect += 1
	elif correct and (distance <= float(_config.good_sec) + EPSILON or (_config.get("cabinet", false) and not _config.get("document_rules",false))):
		grade = "good"; _good += 1
	else:
		_miss += 1
	_judgements[nearest] = grade
	_combo = _combo + 1 if grade != "miss" else 0
	_max_combo = maxi(_combo, _max_combo)
	_step_index += 1
	_judge(grade,"TIMING" if correct else "WRONG_KEY",action,nearest,adjusted-_beats[nearest])
	if not _judgements.has("pending"):
		_resolved = true; _reason = "BEAT_SEQUENCE_COMPLETE"
	return _outcome(true, "JUDGED")

func _integrate_attraction(duration: float, sample_time: float) -> void:
	# Exact solution within an absolute grid cell: partitioning a frame does not
	# change the trajectory or time inside the target. Mouse events split the cell.
	var force: float = _disturbance_at(sample_time)
	var start: float = _cursor
	var rate: float = _attraction
	var equilibrium: float = _control + force / rate if rate > 0 else 0.0
	var finish: float = equilibrium + (start - equilibrium) * exp(-rate * duration) if rate > 0 else start + force * duration
	var low: float = float(_config.target_min)
	var high: float = float(_config.target_max)
	var cuts: Array[float] = [0.0, duration]
	for bound: float in [0.0, low, high, 1.0]:
		var crossing: float = -1.0
		if rate > 0 and absf(start - equilibrium) > EPSILON:
			var fraction: float = (bound - equilibrium) / (start - equilibrium)
			if fraction > 0: crossing = -log(fraction) / rate
		elif absf(force) > EPSILON: crossing = (bound - start) / force
		if crossing > EPSILON and crossing < duration - EPSILON: cuts.append(crossing)
	cuts.sort()
	for index: int in cuts.size() - 1:
		var a: float = cuts[index]; var b: float = cuts[index + 1]
		var mid: float = (a + b) * .5
		var value: float = equilibrium + (start - equilibrium) * exp(-rate * mid) if rate > 0 else start + force * mid
		if value >= low and value <= high: _inside_sec += b - a
		if value <= 0: continue
		if value >= 1: _heat_dose += b - a
		elif rate > 0: _heat_dose += equilibrium * (b - a) + (start - equilibrium) * (exp(-rate * a) - exp(-rate * b)) / rate
		else: _heat_dose += start * (b - a) + force * (b * b - a * a) * .5
	_cursor = clampf(finish, 0, 1)
