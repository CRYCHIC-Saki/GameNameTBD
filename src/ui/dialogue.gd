class_name TDDialogue
extends RefCounted
## One conversation. The view only displays this state.
## Short click reveals the line, then advances. A held pointer fast-forwards.
## Skip jumps to the next reply choice, or ends the talk when no choice remains.

const TYPE_SEC := 0.03
const HOLD_ARM := 0.32
const FAST_STEP := 0.07

var speaker_name: String = ""
var portrait_id: String = ""
var body: String = ""
var shown: int = 0
var choices_open: bool = false
var exhausted: bool = false
var finished: bool = false
var picks: Array[String] = []

var _beats: Array = []
var _index: int = 0
var _started: bool = false
var _type_wait: float = 0.0
var _press_time: float = 0.0
var _armed: bool = false
var _fast_wait: float = 0.0

func add_line(speaker: String, portrait: String, text: String) -> void:
	_beats.append({"kind": "line", "speaker": speaker, "portrait": portrait, "text": text})

func add_choice(options: Array) -> void:
	_beats.append({"kind": "choice", "options": options})

func begin() -> void:
	_started = true
	_index = 0
	shown = 0
	choices_open = false
	exhausted = false
	finished = false
	picks = []
	_type_wait = 0.0
	_press_time = 0.0
	_armed = false
	_fast_wait = 0.0
	if _beats.is_empty():
		finished = true
		return
	var beat: Dictionary = _beats[0]
	if String(beat.get("kind", "")) == "choice":
		choices_open = true
		return
	_show_line(beat)

func visible_text() -> String:
	return body.substr(0, shown)

func full_text() -> String:
	return body

func options() -> Array:
	if not choices_open or _index < 0 or _index >= _beats.size():
		return []
	var beat: Dictionary = _beats[_index]
	var found: Variant = beat.get("options", [])
	return found if found is Array else []

func tick(delta: float) -> void:
	_ensure()
	if finished or choices_open or exhausted or _armed:
		return
	if shown >= body.length():
		return
	_type_wait += delta
	while _type_wait >= TYPE_SEC and shown < body.length():
		_type_wait -= TYPE_SEC
		shown += 1

func pointer_down() -> void:
	_press_time = 0.0
	_armed = false
	_fast_wait = 0.0

func hold(delta: float, down: bool) -> void:
	_ensure()
	if not down:
		return
	if finished:
		return
	_press_time += delta
	if _press_time < HOLD_ARM:
		return
	_armed = true
	if choices_open or exhausted:
		return
	_fast_wait += delta
	while _fast_wait >= FAST_STEP and not choices_open and not exhausted and not finished:
		_fast_wait -= FAST_STEP
		if shown < body.length():
			shown = body.length()
		else:
			_forward()

func release() -> void:
	_ensure()
	var tapped := not _armed
	_press_time = 0.0
	_armed = false
	_fast_wait = 0.0
	if tapped:
		click()

func click() -> void:
	_ensure()
	if finished or choices_open:
		return
	if exhausted:
		finished = true
		return
	if shown < body.length():
		shown = body.length()
		return
	_forward()

func skip() -> void:
	_ensure()
	if finished or choices_open:
		return
	var choice_at := -1
	for i in range(_index, _beats.size()):
		var beat: Dictionary = _beats[i]
		if String(beat.get("kind", "")) == "choice":
			choice_at = i
			break
	if choice_at < 0:
		var last := _index
		for i in range(_index, _beats.size()):
			var beat: Dictionary = _beats[i]
			if String(beat.get("kind", "")) == "line":
				last = i
		if last >= 0 and last < _beats.size() and String((_beats[last] as Dictionary).get("kind", "")) == "line":
			_index = last
			_show_line(_beats[last])
			shown = body.length()
		finished = true
		return
	var spoken := choice_at - 1
	if spoken >= 0 and String((_beats[spoken] as Dictionary).get("kind", "")) == "line":
		_index = spoken
		_show_line(_beats[spoken])
		shown = body.length()
	_index = choice_at
	choices_open = true

func pick(id: String) -> bool:
	_ensure()
	if not choices_open:
		return false
	for option: Variant in options():
		var item: Dictionary = option
		if String(item.get("id", "")) != id:
			continue
		picks.append(id)
		var reply_speaker := String(item.get("speaker", speaker_name))
		var reply_portrait := String(item.get("portrait", portrait_id))
		_beats[_index] = {
			"kind": "line",
			"speaker": reply_speaker,
			"portrait": reply_portrait,
			"text": String(item.get("text", "")),
		}
		choices_open = false
		_show_line(_beats[_index])
		return true
	return false

func force_close() -> void:
	_ensure()
	finished = true

func _ensure() -> void:
	if not _started:
		begin()

func _forward() -> void:
	_index += 1
	if _index >= _beats.size():
		exhausted = true
		return
	var beat: Dictionary = _beats[_index]
	if String(beat.get("kind", "")) == "choice":
		choices_open = true
		return
	_show_line(beat)

func _show_line(beat: Dictionary) -> void:
	speaker_name = String(beat.get("speaker", ""))
	portrait_id = String(beat.get("portrait", "guest"))
	body = String(beat.get("text", ""))
	shown = 0
	_type_wait = 0.0
