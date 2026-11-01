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
var context: Dictionary = {}
var presentation: String = "interaction"
var left_portrait: String = "hero"
var right_portrait: String = ""
var active_side: String = ""
var cancelled: bool = false
var hero_name: String = "我"
var emotion: String = "calm"
var action: String = ""
var left_emotion: String = "calm"
var right_emotion: String = "calm"
var display_kind: String = "line"
var cg_id: String = ""
var cg_elapsed: float = 0.0
var cg_duration: float = 0.0
var cg_paused: bool = false

var _beats: Array = []
var _index: int = 0
var _started: bool = false
var _type_wait: float = 0.0
var _press_time: float = 0.0
var _armed: bool = false
var _fast_wait: float = 0.0

func add_line(speaker: String, portrait: String, text: String, mood: String="calm", pose: String="", kind: String="line") -> void:
	_beats.append({"kind":"line","display_kind":kind,"speaker":speaker,"portrait":portrait,"text":text,"emotion":mood,"action":pose})

func add_cg(id: String, caption: String, duration: float=3.5) -> void:
	_beats.append({"kind":"line","display_kind":"cg","cg":id,"duration":duration,"speaker":"","portrait":"page","text":caption})

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
	cancelled = false
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
	if not is_finite(delta) or delta < 0 or finished or choices_open or exhausted:
		return
	if display_kind == "cg":
		if cg_paused: return
		var remaining := delta
		# Carry time only through adjacent film clips. Never spend it on the next line.
		while display_kind == "cg" and not finished and not choices_open:
			var consumed := minf(remaining, maxf(0, cg_duration - cg_elapsed))
			cg_elapsed += consumed
			remaining -= consumed
			if cg_elapsed < cg_duration: break
			skip_cg()
			if remaining <= 0: break
		return
	if _armed or shown >= body.length(): return
	_type_wait += delta
	while _type_wait >= TYPE_SEC and shown < body.length():
		_type_wait -= TYPE_SEC
		shown += 1

func skip_cg() -> void:
	if finished or display_kind != "cg": return
	cg_paused = false
	_press_time = 0; _armed = false; _fast_wait = 0
	_forward()
	if exhausted: finished = true

func pause_cg(value: bool) -> void:
	if display_kind == "cg" and not finished: cg_paused = value

func name_hero(value: String) -> bool:
	var cleaned:=value.strip_edges()
	if cleaned.is_empty() or cleaned.length()>20 or action!="enter_name": return false
	body=body.replace(hero_name,cleaned)
	_beats[_index].text=body;hero_name=cleaned;shown=0
	return true

func pointer_down() -> void:
	_press_time = 0.0
	_armed = false
	_fast_wait = 0.0

func hold(delta: float, down: bool) -> void:
	_ensure()
	if not down or display_kind == "cg":
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
	while _fast_wait >= FAST_STEP and not choices_open and not exhausted and not finished and display_kind != "cg":
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
	if finished or choices_open or display_kind == "cg":
		return
	if exhausted:
		finished = true
		return
	if shown < body.length():
		shown = body.length()
		return
	if display_kind=="cg" and cg_elapsed<cg_duration: return
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
		if presentation=="story":
			# Show the player's selected sentence before the NPC's reply.
			_beats[_index]={"kind":"line","speaker":hero_name,"portrait":"hero","text":str(item.get("label",""))}
			_beats.insert(_index+1,{"kind":"line","speaker":reply_speaker,"portrait":reply_portrait,"text":str(item.get("text",""))})
			choices_open=false
			_show_line(_beats[_index])
			return true
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
	cancelled = true
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
	display_kind=str(beat.get("display_kind","line"));cg_id=str(beat.get("cg",""))
	cg_duration=maxf(.01,float(beat.get("duration",0)));cg_elapsed=0;cg_paused=false
	_press_time=0;_armed=false;_fast_wait=0
	emotion=str(beat.get("emotion","calm"));action=str(beat.get("action",""))
	speaker_name = String(beat.get("speaker", ""))
	portrait_id = String(beat.get("portrait", "guest"))
	active_side=""
	if presentation=="story" and portrait_id not in ["page",""]:
		if portrait_id=="hero": active_side="left";left_emotion=emotion
		else: right_portrait=portrait_id;active_side="right";right_emotion=emotion
	body = String(beat.get("text", ""))
	shown = 0
	_type_wait = 0.0

func story_layout(hero: String, counterpart: String) -> void:
	presentation="story";hero_name=hero;left_portrait="hero";right_portrait=counterpart
	context={"kind":"story"}
