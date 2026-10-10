class_name TDBeatSheet
extends RefCounted
## A small data schedule; the kitchen remains the owner of sessions and QTEs.
var _events: Array = []
var _next: int = 0
var _origin: float = 0.0
var _interval: float = .5
var running: bool = false
var cells: Array = []
var duration_sec: float = 0.0
var pre_roll_beats: float = 0.0

func configure(sheet: Dictionary, operations: Dictionary) -> TDOutcome:
	running = false
	_events.clear()
	cells.clear()
	pre_roll_beats=0
	if sheet.has("beats"): return _configure_beats(sheet, operations)
	if not sheet.get("bpm") is float and not sheet.get("bpm") is int: return TDOutcome.new(false, "INVALID_BEAT_SHEET")
	if not is_finite(float(sheet.bpm)) or float(sheet.bpm) < 30 or float(sheet.bpm) > 240 or not sheet.get("events") is Array or sheet.events.is_empty(): return TDOutcome.new(false, "INVALID_BEAT_SHEET")
	var previous: float = -1
	var occupied: Dictionary = {}
	for event: Variant in sheet.events:
		if not event is Dictionary or not event.get("parameters") is Dictionary or not operations.has(event.get("operation", "")): return TDOutcome.new(false, "INVALID_BEAT_SHEET")
		if not event.get("beat") is int and not event.get("beat") is float: return TDOutcome.new(false, "INVALID_BEAT_SHEET")
		var at: float = float(event.beat)
		if not is_finite(at) or at < previous or at < 0 or at > 1024: return TDOutcome.new(false, "INVALID_BEAT_SHEET")
		var track: String = "thermal" if event.operation in ["heat", "boil"] else "hand"
		var key: String = str(at) + ":" + track
		if occupied.has(key): return TDOutcome.new(false, "CONFLICTING_BEAT")
		occupied[key] = true; previous = at
	_events = sheet.events.duplicate(true)
	_interval = 60.0 / float(sheet.bpm)
	return TDOutcome.new(true, "CONFIGURED")

func start(origin_sec: float) -> TDOutcome:
	if _events.is_empty() or not is_finite(origin_sec) or origin_sec < 0: return TDOutcome.new(false, "INVALID_BEAT_SHEET")
	_next = 0; _origin = origin_sec; running = true
	return TDOutcome.new(true, "STARTED")

func due(now_sec: float) -> Array:
	var result: Array = []
	while running and _next < _events.size() and now_sec + .000000001 >= _origin + float(_events[_next].beat) * _interval:
		result.append(_events[_next].duplicate(true)); _next += 1
		if _next == _events.size(): running = false
	return result

func next_in(now_sec: float) -> float:
	return maxf(0, _origin + float(_events[_next].beat) * _interval - now_sec) if running else INF

func cancel() -> void:
	running = false

func snapshot() -> Dictionary:
	return {"running": running, "next": _next, "origin_sec": _origin, "events": _events.duplicate(true), "cells":cells.duplicate(true), "duration_sec":duration_sec,"pre_roll_beats":pre_roll_beats}

func _configure_beats(sheet: Dictionary, operations: Dictionary) -> TDOutcome:
	if not _number(sheet.get("bpm")) or float(sheet.bpm) < 30 or float(sheet.bpm) > 240 or not sheet.get("beats") is Array or not sheet.get("groups") is Dictionary or sheet.beats.is_empty(): return TDOutcome.new(false,"INVALID_BEAT_SHEET")
	_interval = 60.0 / float(sheet.bpm)
	var groups: Dictionary = {}
	if not _number(sheet.get("preview_beats",1.0)) or not _number(sheet.get("charge_start_grace_beats",4.0)): return TDOutcome.new(false,"INVALID_BEAT_SHEET")
	var preview: float = float(sheet.get("preview_beats",1.0))
	var start_grace: float = float(sheet.get("charge_start_grace_beats",4.0)) * _interval
	if preview < 1 or preview > 16 or start_grace <= 0 or start_grace > 10: return TDOutcome.new(false,"INVALID_BEAT_SHEET")
	var previous: float = 0
	for row: Variant in sheet.beats:
		if not row is Dictionary or not _number(row.get("t")) or row.t <= previous or row.t > 1024 or not row.get("lanes") is Dictionary: return TDOutcome.new(false,"INVALID_BEAT_SHEET")
		previous = float(row.t)
		if row.get("rest",false) and not row.lanes.is_empty(): return TDOutcome.new(false,"CONFLICTING_BEAT")
		for track: String in row.lanes:
			var cell: Variant = row.lanes[track]
			if track not in ["hand","mouse"] or not cell is Dictionary or not sheet.groups.has(cell.get("group","")) or cell.get("form") not in ["tap","hold"]: return TDOutcome.new(false,"INVALID_BEAT_SHEET")
			var id: String = cell.group
			var group: Variant = sheet.groups[id]
			if not group is Dictionary or not operations.has(group.get("operation","")) or not group.get("parameters") is Dictionary or cell.get("op") != group.operation: return TDOutcome.new(false,"INVALID_BEAT_SHEET")
			if not cell.get("input") is String or (cell.input not in ["primary","up","left","down","right","rotate_left","rotate_right","Mouse"] and not cell.input.begins_with("spice:")): return TDOutcome.new(false,"INVALID_BEAT_SHEET")
			if (cell.input == "Mouse" or cell.input.begins_with("spice:")) != (track == "mouse"): return TDOutcome.new(false,"INVALID_TRACK")
			if not groups.has(id): groups[id] = {"first":row.t,"last":row.t,"track":track,"form":cell.form,"times":[],"inputs":[],"durations":[]}
			var compiled: Dictionary = groups[id]
			if compiled.track != track or compiled.form != cell.form: return TDOutcome.new(false,"CONFLICTING_BEAT")
			compiled.last = row.t; compiled.times.append(float(row.t)); compiled.inputs.append(cell.input)
			if group.operation == "season" and cell.form == "hold":
				if not _number(cell.get("hold_beats")) or float(cell.hold_beats) <= 0 or float(cell.hold_beats)*_interval > 4: return TDOutcome.new(false,"INVALID_HOLD")
				compiled.durations.append(float(cell.hold_beats)*_interval)
	if groups.size() != sheet.groups.size(): return TDOutcome.new(false,"UNUSED_GROUP")
	for id: String in groups:
		if sheet.groups[id].operation not in ["heat","boil"]: continue
		for other: String in groups:
			if other == id or groups[other].track != "mouse": continue
			if float(groups[other].first) <= float(groups[id].last) and float(groups[other].last) >= float(groups[id].first): return TDOutcome.new(false,"CONTENDED_MOUSE_TRACK")
	var busy_until: Dictionary = {"hand":0.0,"mouse":0.0}
	for id: String in groups:
		var g: Dictionary = groups[id]
		var definition: Dictionary = sheet.groups[id]
		var operation: String=definition.operation
		if operation in ["heat","boil"]:
			if g.track!="mouse" or g.form!="hold" or g.inputs.any(func(x:String)->bool:return x!="Mouse"): return TDOutcome.new(false,"INVALID_HOLD")
		elif operation in ["plate","steam"]:
			if g.form!="hold" or g.track!="hand" or g.last-g.first+1!=g.times.size() or g.inputs.any(func(x:String)->bool:return x!="primary"): return TDOutcome.new(false,"INVALID_HOLD")
		elif operation in ["cut","preheat"]:
			var allowed: Array = ["primary","rotate_left","rotate_right"] if operation == "cut" else ["primary"]
			if g.form!="tap" or g.track!="hand" or g.inputs.any(func(x:String)->bool:return x not in allowed) or "primary" not in g.inputs: return TDOutcome.new(false,"INVALID_TAP")
			if operation=="preheat" and g.times.size()!=1: return TDOutcome.new(false,"INVALID_TAP")
		elif operation in ["stir","starch"] or (operation=="season" and definition.parameters.get("mode")=="common"):
			if g.form!="tap" or g.track!="hand" or g.inputs.size()<3 or g.inputs.size()>7 or g.inputs.back()!="primary": return TDOutcome.new(false,"INVALID_SEQUENCE")
		elif operation=="season":
			if g.track!="mouse" or g.inputs.is_empty() or g.inputs.size()>5: return TDOutcome.new(false,"INVALID_SEQUENCE")
		# A single mouse cannot control temperature and select spices at once.
		if definition.operation not in ["heat","boil"]:
			if g.first <= busy_until[g.track]: return TDOutcome.new(false,"OVERLAPPING_GROUP")
			busy_until[g.track] = g.last
		var settings: Dictionary = {"document_rules":true}
		var origin_beat: float = float(g.first)-1-preview
		var relative: Array = []
		for at: float in g.times: relative.append((at-1-origin_beat)*_interval)
		if definition.operation in ["heat","boil"]:
			origin_beat = float(g.first)-1
			settings.duration_sec = (float(g.last)-float(g.first)+1)*_interval
		elif definition.operation in ["plate","steam"]:
			var hold: float = g.times.size()*_interval
			settings.target_min_sec = hold-.1; settings.target_max_sec = hold+.1
			settings.perfect_center_sec = hold; settings.perfect_sec = .05
			settings.charge_preview_sec = preview * _interval
			settings.start_grace_sec = start_grace
			settings.timeout_sec = settings.charge_preview_sec + start_grace + hold + .3
		elif definition.operation == "preheat":
			origin_beat = float(g.first)-5
			settings.target_sec = (float(g.first)-1-origin_beat)*_interval
			settings.sweep_period_sec = settings.target_sec*4; settings.timeout_sec = settings.target_sec+.101
		else:
			settings.beat_times_sec = relative
			if definition.operation != "cut": settings.sequence = g.inputs.duplicate()
			else:
				settings.beats = g.inputs.size()
				settings.cut_actions = g.inputs.duplicate()
			if definition.operation == "season" and g.form == "hold":
				settings.hold_durations_sec = g.durations.duplicate()
				settings.pour_rate_per_sec = definition.get("pour_rate_per_sec",.2)
			if definition.operation == "season" and definition.get("free_seasoning",false):
				if not _number(definition.get("free_duration_sec")) or float(definition.free_duration_sec)<1 or float(definition.free_duration_sec)>20: return TDOutcome.new(false,"INVALID_FREE_DURATION")
				settings.free_seasoning=true
				settings.free_duration_sec=definition.free_duration_sec
				settings.pour_rate_per_sec=definition.get("pour_rate_per_sec",.2)
		_events.append({"beat":origin_beat,"operation":definition.operation,"parameters":definition.parameters.duplicate(true),"settings":settings,"group":id,"label":definition.get("label",id)})
	_events.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.beat < b.beat)
	# Beat 1 may need an approach/ignition cue. Add whole-bar count-in only
	# when needed; target coordinates and strong-beat phases stay unchanged.
	if not _events.is_empty(): pre_roll_beats=ceil(maxf(0,-float(_events[0].beat))/4)*4
	for event: Dictionary in _events: event.beat+=pre_roll_beats
	# A preview is not an occupied input beat. Adjacent legal sequences may
	# shorten the next preview while preserving every absolute target time.
	var ends: Dictionary = {"hand":-1.0,"thermal":-1.0}
	for event: Dictionary in _events:
		var track: String = "thermal" if event.operation in ["heat","boil"] else "hand"
		var g: Dictionary = groups[event.group]
		var overlap: float=float(ends[track])-float(event.beat)*_interval
		if overlap>.000001:
			var settings: Dictionary=event.settings
			if settings.has("beat_times_sec"):
				if float(settings.beat_times_sec[0])-overlap<.101: return TDOutcome.new(false,"OVERLAPPING_GROUP")
				for index: int in settings.beat_times_sec.size(): settings.beat_times_sec[index]-=overlap
			elif event.operation=="preheat":
				if float(settings.target_sec)-overlap<.101: return TDOutcome.new(false,"OVERLAPPING_GROUP")
				settings.target_sec-=overlap; settings.timeout_sec-=overlap
				settings.sweep_period_sec=settings.target_sec*4
			else: return TDOutcome.new(false,"OVERLAPPING_GROUP")
			event.beat=float(ends[track])/_interval
		ends[track] = (float(g.last)-1+pre_roll_beats)*_interval + (.101 if g.form == "tap" else _interval)
		if event.operation == "season" and g.form == "hold": ends[track] = (float(g.last)-1+pre_roll_beats)*_interval+float(g.durations.back())*1.5+.101
		if event.settings.get("free_seasoning",false): ends[track]=float(event.beat)*_interval+float(event.settings.free_duration_sec)
		if event.operation in ["plate","steam"]: ends[track] += start_grace + .201
	_events.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return a.beat<b.beat)
	cells = sheet.beats.duplicate(true)
	duration_sec = (previous+pre_roll_beats)*_interval + .5
	return TDOutcome.new(true,"CONFIGURED")

func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0
