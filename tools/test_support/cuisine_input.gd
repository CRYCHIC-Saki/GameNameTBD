extends RefCounted
## Input timeline injection only; no result or grade injection.
static func play(lesson: TDResearchLesson, observe: Callable = Callable()) -> bool:
	var sent: Dictionary={}
	for step: int in 16000:
		var result:=lesson.advance(.05)
		if not result.ok: return false
		if observe.is_valid(): observe.call(lesson.active_lane())
		if result.data.ready_to_finish: return true
		drive(lesson.active_lane(),sent)
	return false

static func drive(lane: TDCookingLane,sent: Dictionary) -> void:
	if lane.thermal_qte!=null:
		var thermal:=lane.thermal_progress
		lane.input_action("drag",true,(float(thermal.target_min)+float(thermal.target_max))*.5)
	if lane.qte==null: return
	var p:=lane.progress.duplicate(true);var op: String=p.operation_id
	if p.has("hold_durations_sec") and int(p.hold_index)>=0 and float(p.note_held_sec)+.000001>=float(p.hold_durations_sec[int(p.hold_index)]): lane.input_action(p.hold_action,false)
	if p.qte_kind in ["rhythm","sequence"]:
		for i: int in p.beat_times_sec.size():
			var key:=op+":"+str(i)
			if sent.has(key) or float(p.elapsed_sec)+.000001<float(p.beat_times_sec[i]): continue
			sent[key]=true
			var action: String=p.cut_actions[i] if p.qte_kind=="rhythm" else p.sequence[i]
			lane.input_action(action,true)
			if not action.begins_with("spice:") or not p.has("hold_durations_sec"): lane.input_action(action,false)
	elif p.qte_kind=="window" and not sent.has(op) and float(p.elapsed_sec)+.000001>=float(p.target_sec):
		sent[op]=true;lane.input_action("primary",true);lane.input_action("primary",false)
	elif p.qte_kind=="charge":
		if not sent.has(op) and float(p.get("preview_remaining_sec",0))<=.000001:
			sent[op]=true;lane.input_action("primary",true)
		elif float(p.held_sec)+.000001>=(float(p.target_min_sec)+float(p.target_max_sec))*.5: lane.input_action("primary",false)
