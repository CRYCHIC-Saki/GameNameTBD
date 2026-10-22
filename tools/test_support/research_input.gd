extends RefCounted
## Authored input driver only: no result/score injection. Viewport mode uses real keys/mouse.
static func key(viewport:Viewport,code:Key,down:bool) -> void:
	var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=down;viewport.push_input(event,true)

static func action(session:TDResearchSession,token:String,lane:TDCookingLane,name:String,down:bool,value:float,viewport:Viewport) -> void:
	if viewport==null:
		session.input(token,name,down,value);return
	var stage:=session.controller.kitchen.stage
	if name in ["drag","hover"] or name.begins_with("spice:"):
		var at:Vector2=stage.spice_rect(lane.lane_index,name.trim_prefix("spice:")).get_center() if name.begins_with("spice:") else stage.thermal_rect(lane.lane_index).position+stage.thermal_rect(lane.lane_index).size*Vector2(value,.5)
		if name in ["drag","hover"]:
			var motion:=InputEventMouseMotion.new();motion.position=at;motion.global_position=at;motion.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0;viewport.push_input(motion,true)
		else:
			var event:=InputEventMouseButton.new();event.position=at;event.global_position=at;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;viewport.push_input(event,true)
		return
	var keys:Dictionary={"primary":KEY_SPACE,"rotate_left":KEY_A,"rotate_right":KEY_D,"up":KEY_W,"left":KEY_A,"down":KEY_S,"right":KEY_D}
	if lane.lane_index==1: keys.merge({"up":KEY_UP,"left":KEY_LEFT,"down":KEY_DOWN,"right":KEY_RIGHT},true)
	key(viewport,keys[name],down)

static func tick(session:TDResearchSession,token:String,sent:Dictionary,viewport:Viewport=null) -> void:
	session.advance(.025)
	var lane:=session.controller.active_lane()
	if lane.thermal_qte!=null:
		var p:=lane.thermal_progress
		action(session,token,lane,"drag",true,(float(p.target_min)+float(p.target_max))*.5,viewport)
	if lane.qte==null: return
	var p:Dictionary=lane.progress.duplicate(true);var op:String=p.operation_id
	if p.has("hold_durations_sec") and int(p.hold_index)>=0 and float(p.note_held_sec)+.000001>=float(p.hold_durations_sec[int(p.hold_index)]):
		action(session,token,lane,p.hold_action,false,1,viewport)
	if p.qte_kind in ["rhythm","sequence"]:
		for i:int in p.beat_times_sec.size():
			var marker:String=op+":"+str(i)
			if sent.has(marker) or float(p.elapsed_sec)+.000001<float(p.beat_times_sec[i])+lane.input_offset_sec: continue
			sent[marker]=true
			var name:String=p.cut_actions[i] if p.qte_kind=="rhythm" else p.sequence[i]
			action(session,token,lane,name,true,1,viewport)
			if not name.begins_with("spice:") or not p.has("hold_durations_sec"): action(session,token,lane,name,false,1,viewport)
	elif p.qte_kind=="window" and not sent.has(op) and float(p.elapsed_sec)+.000001>=float(p.target_sec)+lane.input_offset_sec:
		sent[op]=true;action(session,token,lane,"primary",true,1,viewport);action(session,token,lane,"primary",false,1,viewport)
	elif p.qte_kind=="charge":
		if not sent.has(op) and float(p.get("preview_remaining_sec",0))<=.000001:
			sent[op]=true;action(session,token,lane,"primary",true,1,viewport)
		elif float(p.held_sec)+.000001>=(float(p.target_min_sec)+float(p.target_max_sec))*.5: action(session,token,lane,"primary",false,1,viewport)

static func play(session:TDResearchSession,token:String,viewport:Viewport=null) -> bool:
	var sent:Dictionary={}
	for i:int in 10000:
		if session.progress().get("ready_to_finish",false): return true
		tick(session,token,sent,viewport)
	return false
