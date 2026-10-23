extends RefCounted
var kitchen: TDFullKitchen
var viewport: Viewport
var sent: Dictionary={}
var season_duration_scale: float=1.0
var release_outside: bool=false
func key(code: Key,pressed: bool=true) -> void:
	var e:=InputEventKey.new(); e.keycode=code; e.physical_keycode=code; e.pressed=pressed; viewport.push_input(e,true)
func tap(code: Key) -> void: key(code); key(code,false)
func station(id: String, button: Key=KEY_E) -> void:
	for entry: Dictionary in kitchen.world.stations():
		if entry.id==id: (kitchen.world.get_node("Player") as TDKitchenPlayer).position=entry.position+Vector2(0,40); tap(button); return
func click(at: Vector2) -> void:
	var motion:=InputEventMouseMotion.new(); motion.position=at; motion.global_position=at; viewport.push_input(motion,true)
	for down: bool in [true,false]:
		var e:=InputEventMouseButton.new(); e.position=at; e.global_position=at; e.button_index=MOUSE_BUTTON_LEFT; e.pressed=down; viewport.push_input(e,true)
func hold_mouse(at: Vector2,pressed: bool) -> void:
	var event:=InputEventMouseButton.new(); event.position=at; event.global_position=at; event.button_index=MOUSE_BUTTON_LEFT; event.pressed=pressed; viewport.push_input(event,true)

func play(seconds: float, input_enabled: bool=true) -> void:
	for frame: int in int(seconds/.025):
		kitchen.advance(.025)
		if not input_enabled or not kitchen.stage.visible: continue
		for lane: TDCookingLane in kitchen.stage.lanes.duplicate():
			if lane.qte==null: continue
			var p: Dictionary=lane.progress.duplicate(true)
			var token: String=str(p.operation_id)
			var kind: String=p.qte_kind
			if p.get("free_seasoning",false):
				var done: int=p.actual_actions.size()
				if int(p.hold_index)>=0 and float(p.note_held_sec)+.000001>=.5+float(done)*.25:
					hold_mouse(kitchen.stage.spice_rect(lane.lane_index,str(p.hold_action).trim_prefix("spice:")).get_center(),false)
				elif int(p.hold_index)<0 and done<2 and float(p.elapsed_sec)>.5+done*2:
					hold_mouse(kitchen.stage.spice_rect(lane.lane_index,"sugar" if done==0 else "salt").get_center(),true)
				continue
			if p.has("hold_durations_sec") and int(p.hold_index)>=0 and float(p.note_held_sec)+.000001>=float(p.hold_durations_sec[int(p.hold_index)])*season_duration_scale:
				hold_mouse(Vector2(1270,20) if release_outside else kitchen.stage.spice_rect(lane.lane_index,str(p.hold_action).trim_prefix("spice:")).get_center(),false)
			if kind in ["rhythm","sequence"]:
				for index: int in p.beat_times_sec.size():
					var marker: String=token+":"+str(index)
					if sent.has(marker) or float(p.elapsed_sec)+.000001<float(p.beat_times_sec[index]): continue
					sent[marker]=true
					var action: String=str(p.cut_actions[index]) if kind=="rhythm" and not p.get("cut_actions",[]).is_empty() else ("primary" if kind=="rhythm" else str(p.sequence[index]))
					if action.begins_with("spice:"):
						var r: Rect2=kitchen.stage.spice_rect(lane.lane_index,action.trim_prefix("spice:"));
						if p.has("hold_durations_sec"): hold_mouse(r.get_center(),true)
						else: click(r.get_center())
					else:
						var codes: Dictionary={"primary":KEY_SPACE,"rotate_left":KEY_A,"rotate_right":KEY_D,"up":KEY_W,"left":KEY_A,"down":KEY_S,"right":KEY_D} if lane.lane_index!=1 else {"primary":KEY_SPACE,"up":KEY_UP,"left":KEY_LEFT,"down":KEY_DOWN,"right":KEY_RIGHT}
						tap(codes[action])
			elif kind=="window" and not sent.has(token) and float(p.elapsed_sec)+.000001>=float(p.target_sec): sent[token]=true; tap(KEY_SPACE)
			elif kind=="charge":
				if not sent.has(token) and float(p.get("preview_remaining_sec",0))<=.000001: sent[token]=true; key(KEY_SPACE)
				elif float(p.held_sec)+.000001>=(float(p.target_min_sec)+float(p.target_max_sec))*.5: key(KEY_SPACE,false)
