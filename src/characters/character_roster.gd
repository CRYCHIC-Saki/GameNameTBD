class_name TDCharacterRoster
extends RefCounted
## Save-slot relationships and schedules; dining still uses EconomicCustomer/MealIntent.
const ORIGINAL_RESIDENTS := ["aling", "chen"]
const SOURCE := "res://content/characters/roster.json"
var strict_encounters := false
var definitions: Dictionary = {}
var settings: Dictionary = {}
var records: Dictionary = {}
var clock := TDWorldDayClock.new()
var error := TDOutcome.new(true)
var runtime: Dictionary = {} # Transient world position and current order, never a second wallet.
var pinned: Dictionary = {}
var _map: TDTownMap
# Scheduled residents use exactly the same ground clearance as the player's feet.
var foot_clear: Callable
var step_clear: Callable
var _neighbors: Dictionary = {}
var _cells: Dictionary = {}
const FOOT_OFFSET := Vector2(.5, .62)
var _held: Dictionary = {}
var _targets: Dictionary = {}
var _safe_roads: Array[Vector2i]=[]
var _activity_points: Dictionary={}

func _init() -> void:
	var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
	error=validate_config(parsed)
	if not error.ok: return
	settings=parsed.settings.duplicate(true)
	for row: Dictionary in parsed.characters:
		definitions[row.id]=row.duplicate(true)
		_reset_record(row.id)

static func validate_config(raw: Variant) -> TDOutcome:
	if not raw is Dictionary or raw.get("schema_version")!=1 or not raw.get("characters") is Array or not raw.get("settings") is Dictionary: return TDOutcome.new(false,"INVALID_CHARACTERS_CONFIG")
	for field: String in ["chat_gain","good_meal_score","bad_meal_score","good_meal_gain","bad_meal_gain","friend_at","close_at"]:
		if not TDServiceCatalog.integer(raw.settings.get(field),-100,100): return TDOutcome.new(false,"INVALID_RELATIONSHIP_SETTINGS",field)
	if not TDEconomicCustomer.finite_range(raw.settings.get("walk_step_sec"),0.1,5): return TDOutcome.new(false,"INVALID_WALK_TIME")
	if raw.settings.bad_meal_score>=raw.settings.good_meal_score or raw.settings.friend_at>=raw.settings.close_at: return TDOutcome.new(false,"INVALID_RELATIONSHIP_THRESHOLDS")
	var ids: Dictionary={};var bindings: Dictionary={}
	for row: Variant in raw.characters:
		if not row is Dictionary: return TDOutcome.new(false,"INVALID_CHARACTER")
		for field: String in ["id","name","portrait","town_id","biography"]:
			if not row.get(field) is String or row[field].is_empty(): return TDOutcome.new(false,"INVALID_CHARACTER",field)
		if ids.has(row.id) or row.id=="linxia": return TDOutcome.new(false,"DUPLICATE_CHARACTER")
		ids[row.id]=true
		if not row.get("traits") is Array or not row.get("schedule") is Array or not row.get("dialogue") is Dictionary or not row.get("economic_binding") is Dictionary: return TDOutcome.new(false,"INVALID_CHARACTER_FIELDS")
		for characteristic: Variant in row.traits:
			if not characteristic is String or characteristic.is_empty(): return TDOutcome.new(false,"INVALID_TRAIT")
		var binding: Dictionary=row.economic_binding
		if binding.get("group_id") not in ["value","commuter","explorer","leisure"] or not TDServiceCatalog.integer(binding.get("family_index"),0,15) or not TDServiceCatalog.integer(binding.get("template_index"),0,1) or binding.get("preferred_taste") not in TDEconomicCustomer.TASTES: return TDOutcome.new(false,"INVALID_CHARACTER_BINDING")
		var key:="%s:%s:%d"%[row.town_id,binding.group_id,int(binding.family_index)]
		if bindings.has(key): return TDOutcome.new(false,"DUPLICATE_CHARACTER_BINDING")
		bindings[key]=true
		var previous:=480
		for span: Variant in row.schedule:
			if not span is Dictionary or not TDServiceCatalog.integer(span.get("from"),480,1560) or not TDServiceCatalog.integer(span.get("until"),481,1560) or int(span.from)!=previous or int(span.until)<=previous or span.get("zone") not in ["market","player_diner","plaza","landmark","station","offstage"]: return TDOutcome.new(false,"INVALID_CHARACTER_SCHEDULE")
			if span.has("meal") and not span.meal is bool: return TDOutcome.new(false,"INVALID_CHARACTER_SCHEDULE")
			if span.get("activity","roam") not in ["stand","roam"] or not TDEconomicCustomer.finite_range(span.get("radius_tiles",7),3,12) or not TDEconomicCustomer.finite_range(span.get("rest_sec",12),1,120): return TDOutcome.new(false,"INVALID_CHARACTER_ACTIVITY")
			previous=int(span.until)
		if previous!=1560: return TDOutcome.new(false,"INCOMPLETE_CHARACTER_SCHEDULE")
		for tier: String in ["stranger","friend","close"]:
			if not row.dialogue.get(tier) is Array or row.dialogue[tier].is_empty(): return TDOutcome.new(false,"INVALID_CHARACTER_DIALOGUE")
			for line: Variant in row.dialogue[tier]:
				if not line is String or line.is_empty(): return TDOutcome.new(false,"INVALID_CHARACTER_DIALOGUE")
		if not row.dialogue.get("about") is String: return TDOutcome.new(false,"INVALID_CHARACTER_DIALOGUE")
	return TDOutcome.new(true,"VALID_CHARACTERS")

func _reset_record(id: String) -> void:
	records[id]={"affection":0,"last_chat_day":0,"last_meal_day":0,"last_attempt_day":0,"last_visit_day":0,"last_meal_token":"","flags":{}}

func mark_met(id: String) -> void:
	if records.has(id): records[id].flags["met"]=true

func has_met(id: String) -> bool:
	return bool(records.get(id,{}).get("flags",{}).get("met",false))

func _requires_encounter(id: String) -> bool:
	return strict_encounters or definitions.get(id, {}).get("story_only", false)

func can_chat(id: String) -> bool:
	return definitions.has(id) and (has_met(id) or not _requires_encounter(id))

func sync_story_encounters(state: Dictionary) -> void:
	strict_encounters = not state.is_empty()
	if not strict_encounters: return
	for id: String in definitions:
		var scene: String = TDRevisedMainline.FIRST_ENCOUNTERS.get(id, "")
		if scene in state.completed: mark_met(id)
		else: records[id].flags.erase("met")

func definition(id: String) -> Dictionary:
	return definitions.get(id,{}).duplicate(true)

func relationship(id: String) -> Dictionary:
	return records.get(id,{}).duplicate(true)

func character_for(person: Dictionary) -> String:
	var id:=str(person.get("id",""))
	for key: String in definitions:
		if id=="character:"+key: return key
	return ""

func tier(id: String) -> String:
	var affection:=int(records.get(id,{}).get("affection",0))
	return "close" if affection>=int(settings.close_at) else ("friend" if affection>=int(settings.friend_at) else "stranger")

func schedule(id: String) -> Dictionary:
	return schedule_at(id,clock.minute)

func schedule_at(id: String, minute: float) -> Dictionary:
	for row: Dictionary in definitions.get(id,{}).get("schedule",[]):
		if minute>=float(row.from) and minute<float(row.until): return row.duplicate(true)
	return {"zone":"offstage","meal":false}

func kitchen_available() -> bool:
	return clock.closed_day!=clock.day

func candidate(raw: Dictionary, templates: Array, family_count: int, minute: float = -1.0) -> Dictionary:
	if minute<0: minute=clock.minute
	if family_count<=0 or templates.is_empty(): return {}
	for id: String in definitions:
		var d: Dictionary=definitions[id];var b: Dictionary=d.economic_binding
		if d.get("story_only", false): continue
		var source_id:="resident:%s:%s:%d"%[d.town_id,b.group_id,int(b.family_index)%family_count]
		if str(raw.id)!=source_id: continue
		if not can_chat(id): return raw.duplicate(true)
		if pinned.has(id) or _held.has(id) or int(records[id].last_attempt_day)==clock.day or not bool(schedule_at(id,minute).get("meal",false)) or minute>=TDWorldDayClock.END_MINUTE: return {}
		records[id].last_attempt_day=clock.day
		var person:=raw.duplicate(true)
		person.id="character:"+id;person.character_id=id;person.display_name=d.name
		person.origin_id="market" if schedule_at(id,minute).zone=="market" else "residential"
		for taste: String in TDEconomicCustomer.TASTES:
			person.taste[taste]=[35.0,55.0,35.0,20.0] if taste==b.preferred_taste else [15.0,20.0,15.0,10.0]
		person.declared_requirements=templates[int(b.template_index)%templates.size()].requirements.duplicate(true)
		return person
	return raw.duplicate(true)

func hold(id: String, value: bool) -> void:
	if value: _held[id]=true
	else: _held.erase(id)

func conversation(id: String) -> TDDialogue:
	var talk:=TDDialogue.new()
	if not can_chat(id): return talk
	var d: Dictionary=definitions[id]
	talk.context={"kind":"resident","character_id":id,"day":clock.day}
	var lines: Array=d.dialogue[tier(id)]
	var intro: String=lines[(clock.day-1)%lines.size()]
	talk.add_line(d.name,d.portrait,intro)
	talk.add_choice([
		{"id":"chat","label":"聊聊今天的事。","speaker":d.name,"portrait":d.portrait,"text":lines[clock.day%lines.size()]},
		{"id":"about","label":"再说说你自己的事吧。","speaker":d.name,"portrait":d.portrait,"text":d.dialogue.about},
	])
	return talk

func complete_chat(context: Dictionary, completed: bool, picks: Array) -> TDOutcome:
	var id:=str(context.get("character_id",""))
	if context.get("kind")!="resident" or not can_chat(id) or int(context.get("day",0))!=clock.day: return TDOutcome.new(false,"STALE_CONVERSATION")
	if not completed or not picks.any(func(p: Variant)->bool:return p in ["chat","about"]): return TDOutcome.new(true,"CHAT_CANCELLED")
	mark_met(id)
	if int(records[id].last_chat_day)==clock.day: return TDOutcome.new(true,"CHAT_ALREADY_COUNTED")
	records[id].last_chat_day=clock.day
	records[id].affection=clampi(int(records[id].affection)+int(settings.chat_gain),0,100)
	return TDOutcome.new(true,"RELATIONSHIP_CHANGED")

func observe_orders(orders: Array) -> void:
	for order: Dictionary in orders:
		var id:=character_for(order.get("economic_profile",{}))
		if id.is_empty() or not can_chat(id) or int(order.get("economic_intent",{}).get("day",0))!=clock.day: continue
		var r: Dictionary=records[id]
		if order.status=="SERVED": mark_met(id)
		if order.status=="SERVED" and int(r.last_meal_day)<clock.day and not order.get("score",{}).is_empty():
			var score:=float(order.score.get("satisfaction",0))
			var gain:=int(settings.good_meal_gain) if score>=float(settings.good_meal_score) else (int(settings.bad_meal_gain) if score<float(settings.bad_meal_score) else 0)
			r.affection=clampi(int(r.affection)+gain,0,100);r.last_meal_day=clock.day;r.last_meal_token=str(order.id)
		if not runtime.has(id): continue
		var actor: Dictionary=runtime[id]
		if int(r.last_visit_day)<clock.day and order.status in ["ARRIVING","WAITING","COOKING","SERVED"]:
			r.last_visit_day=clock.day;actor.order_id=str(order.id);actor.phase="to_diner";actor.route=[];actor.erase("bypass");actor.goal=Vector2i(-1,-1);actor.entered=false
		if str(actor.order_id)==str(order.id) and order.status not in ["ARRIVING","WAITING","COOKING","SERVED"] and not actor.get("entered",false):
			finish_visit(id,str(order.id))

func finish_visit(id: String, order_id: String) -> void:
	if not runtime.has(id) or str(runtime[id].order_id)!=order_id: return
	runtime[id].order_id="";runtime[id].phase="town";runtime[id].entered=false;runtime[id].route=[];runtime[id].erase("bypass");runtime[id].goal=Vector2i(-1,-1)

func begin_visit(id: String, order_id: String) -> void:
	if can_enter(id,order_id): runtime[id].entered=true

func can_enter(id: String, order_id: String) -> bool:
	return runtime.has(id) and runtime[id].phase=="dining" and str(runtime[id].order_id)==order_id

func sync_map(map: TDTownMap) -> void:
	_map=map
	_neighbors.clear(); _cells.clear()
	_targets.clear()
	_activity_points.clear();_safe_roads.clear()
	for at: Vector2i in map.roads:
		if not _clear_cell(at): continue
		var safe: bool=true
		for plot: Dictionary in map.plots:
			if TDInteractionRange.facility(plot) and TDInteractionRange.distance(Vector2(at)+Vector2(.5,.5),TDInteractionRange.plot_bounds(plot))<=1.5:
				safe=false;break
		if safe: _safe_roads.append(at)
	_safe_roads.sort_custom(func(a:Vector2i,b:Vector2i)->bool:return a.y<b.y or (a.y==b.y and a.x<b.x))
	for id: String in definitions:
		if definitions[id].get("story_only", false): continue
		if runtime.has(id):
			if not _clear_cell(runtime[id].cell):
				runtime[id].cell = safe_stop_near(runtime[id].cell,id,_reserved_stops(id))
			runtime[id].erase("bypass");runtime[id].goal=Vector2i(-1,-1);runtime[id].route=[];runtime[id].activity_key="";runtime[id].wait=0.0
			continue
		var at:=_zone_target(str(schedule(id).zone),id)
		if at.x<0: at=_zone_target("market",id)
		at=safe_stop_near(at,id,_reserved_stops(id))
		runtime[id]={"id":id,"name":definitions[id].name,"cell":at,"facing":Vector2i.DOWN,"goal":Vector2i(-1,-1),"route":[],"wait":0.0,"phase":"town","order_id":"","patrol":0,"activity_key":"","dwell":0.0}

func advance(seconds: float, orders: Array = [], minute_from: float = -1.0) -> void:
	if _map==null or not is_finite(seconds) or seconds<0: return
	observe_orders(orders)
	for id: String in runtime:
		var a: Dictionary=runtime[id]
		if pinned.has(id):
			a.cell=pinned[id];a.phase="town";a.route=[];a.erase("bypass");a.goal=Vector2i(-1,-1);a.wait=0.0;a.activity_key="";continue
		if _held.has(id) or a.phase=="dining": continue
		var minute: float=clock.minute if minute_from<0 else minute_from
		var left: float=seconds
		# Split at schedule boundaries, not at display frames. Legacy callers may hold the clock.
		while true:
			var span:=schedule_at(id,minute)
			var step: float=left if minute_from<0 else minf(left,maxf(0.0,float(span.get("until",1560))-minute))
			_advance_actor(id,a,span,step)
			left-=step;minute+=step
			if left<.000001 or step==0: break

func _advance_actor(id: String, a: Dictionary, span: Dictionary, seconds: float) -> void:
	if a.phase!="to_diner" and span.zone=="offstage": a.phase="offstage";a.route=[];a.erase("bypass");a.wait=0.0;return
	if a.phase=="offstage": a.phase="town"
	var key: String="visit:"+str(a.order_id) if a.phase=="to_diner" else "%s:%s"%[span.zone,span.get("from",0)]
	if not a.has("bypass") and (str(a.get("activity_key",""))!=key or a.goal==Vector2i(-1,-1)):
		a.activity_key=key;a.patrol=0;a.dwell=0.0;a.wait=0.0
		_set_goal(a,_zone_target("player_diner",id) if a.phase=="to_diner" else _patrol_target(id,span,a))
	var left: float=seconds
	a.detour_cooldown=maxf(0.0,float(a.get("detour_cooldown",0.0))-seconds)
	while true:
		if a.has("bypass"):
			left=_advance_bypass(id,a,left)
			if left<=.000001 or a.has("bypass"): return
		if not a.route.is_empty():
			var duration := float(settings.walk_step_sec)
			var step := minf(left,maxf(0.0,duration-float(a.wait)))
			var start := Vector2(a.cell)+FOOT_OFFSET
			var target := Vector2(a.route[0])+FOOT_OFFSET
			var before := start.lerp(target,float(a.wait)/duration)
			var after := start.lerp(target,minf(1.0,(float(a.wait)+step)/duration))
			if step>0.0 and step_clear.is_valid() and not step_clear.call(id,before,after):
				if float(a.wait)>0.0:
					var retreat := minf(left,float(a.wait))
					var back := start.lerp(target,(float(a.wait)-retreat)/duration)
					if not step_clear.call(id,before,back): return
					a.wait-=retreat
					left-=retreat
					if float(a.wait)>0.0 or left<=.000001: return
				if a.phase=="to_diner" and a.route.size()==1:
					# A person across the threshold blocks this last step. Enter
					# from the adjacent, clear approach instead of crossing them.
					a.goal=a.cell
					a.route.clear()
					continue
				if a.detour_cooldown>0.0: return
				a.detour_cooldown=.4
				if _start_bypass(id,a,start,target): continue
				var detour := _path(a.cell,a.goal,id)
				if detour.is_empty(): return
				a.route=detour
				continue
			a.detour_cooldown=maxf(0.0,float(a.detour_cooldown)-step)
			a.wait+=step;left-=step
			if a.wait+0.000001<float(settings.walk_step_sec): return
			var next: Vector2i=a.route.pop_front();a.facing=next-a.cell;a.cell=next;a.wait=0.0
			if a.route.is_empty(): a.dwell=float(span.get("rest_sec",12))
		else:
			if a.phase=="to_diner":
				if a.cell==a.goal: a.phase="dining"
				return
			if span.get("activity","roam")=="stand": return
			var rest: float=minf(left,float(a.get("dwell",0)))
			a.dwell-=rest;left-=rest
			if a.dwell>.000001: return
			a.patrol+=1
			var target:=_patrol_target(id,span,a)
			_set_goal(a,target)
			if a.route.is_empty(): a.dwell=float(span.get("rest_sec",12));return
		if left<.000001: return

func _set_goal(a: Dictionary, target: Vector2i) -> void:
	a.goal=target;a.route=_path(a.cell,target);a.wait=0.0

func _start_bypass(id: String, actor: Dictionary, start: Vector2, target: Vector2) -> bool:
	var side := start.direction_to(target).orthogonal()
	for index: int in range(mini(actor.route.size(),4)):
		var finish := Vector2(actor.route[index])+FOOT_OFFSET
		for width: float in [.38,-.38,.58,-.58,.8,-.8]:
			var points := [start+side*width,target+side*width,finish+side*width,finish]
			var previous := start
			for point: Vector2 in points:
				if not _bypass_segment_clear(id,previous,point): break
				previous=point
			if previous!=finish: continue
			actor.bypass={"at":start,"points":points,"skip":index+1}
			return true
	return false

func _bypass_segment_clear(id: String, from: Vector2, to: Vector2) -> bool:
	return TDPlannedTown._reference_segment_clear(from,to,foot_clear) and step_clear.call(id,from,to)

func _advance_bypass(id: String, actor: Dictionary, remaining: float) -> float:
	var bypass: Dictionary=actor.bypass
	var at: Vector2=bypass.at
	var goal: Vector2=bypass.points.front()
	var step := minf(remaining,at.distance_to(goal)*float(settings.walk_step_sec))
	var next := at.move_toward(goal,step/float(settings.walk_step_sec))
	if at!=next and not step_clear.call(id,at,next): return 0.0
	bypass.at=next
	if at!=next: actor.facing=TDStoryArt.four_way_facing(next-at)
	if next==goal:
		bypass.points.pop_front()
		if bypass.points.is_empty():
			for count: int in int(bypass.skip):
				actor.cell=actor.route.pop_front()
			actor.erase("bypass")
		elif remaining>step:
			return _advance_bypass(id,actor,remaining-step)
	return remaining-step

func clear_story_stop(at: Vector2i) -> Vector2i:
	if not foot_clear.is_valid() or at.x < 0 or _clear_cell(at): return at
	for radius: int in range(1,4):
		var closest := Vector2i(-1,-1)
		var distance := INF
		for y: int in range(-radius,radius+1):
			for x: int in range(-radius,radius+1):
				var candidate := at+Vector2i(x,y)
				if not _clear_cell(candidate): continue
				var gap := at.distance_squared_to(candidate)
				if gap < distance:
					closest=candidate; distance=gap
		if closest.x >= 0: return closest
	return safe_stop_near(at,"")

func safe_stop_near(at: Vector2i, id: String, reserved: Array=[]) -> Vector2i:
	var best:=at;var distance: float=INF
	for point: Vector2i in _safe_roads:
		if reserved.any(func(other:Vector2i)->bool:return point.distance_to(other)<2.0): continue
		# Deterministic per-person tie break, independent of shared RNG or update order.
		var gap: float=Vector2(point).distance_squared_to(Vector2(at))+float(absi((str(point)+id).hash())%100)*.0001
		if gap<distance: best=point;distance=gap
	return best

func _patrol_target(id: String, span: Dictionary, a: Dictionary) -> Vector2i:
	var reserved:=_reserved_stops(id)
	var anchor:=safe_stop_near(_zone_target(str(span.zone),id),id,reserved)
	if span.get("activity","roam")=="stand" or int(a.patrol)==0: return anchor
	var radius := float(span.get("radius_tiles",7))
	var key := "%s:%s:%s:%s"%[span.zone,id,radius,anchor]
	if not _activity_points.has(key):
		var points: Array[Vector2i]=[]
		for point: Vector2i in _safe_roads:
			if point.distance_to(anchor)<=radius*2: points.append(point)
		_activity_points[key]=points
	var candidates: Array=_activity_points[key]
	if candidates.is_empty(): return anchor
	var start := (absi(id.hash())+int(a.patrol)*17)%candidates.size()
	# Expand along the adjoining street if another resident is using the only local stop.
	for reach: float in [radius, radius * 1.5, radius * 2.0]:
		for i: int in candidates.size():
			var point: Vector2i=candidates[(start+i)%candidates.size()]
			if point.distance_to(anchor)>reach or point.distance_to(a.cell)<=4.0: continue
			if reserved.any(func(other:Vector2i)->bool:return point.distance_to(other)<2.0): continue
			if not _path(a.cell,point).is_empty(): return point
	return anchor

func _reserved_stops(id: String) -> Array:
	var result: Array=[]
	for other: String in runtime:
		if other==id or runtime[other].phase in ["offstage","dining"]: continue
		result.append(runtime[other].cell)
		if runtime[other].goal!=Vector2i(-1,-1): result.append(runtime[other].goal)
	return result

func visible_people() -> Array:
	var result: Array=[]
	for id: String in runtime:
		if runtime[id].phase not in ["dining","offstage"]:
			var person: Dictionary=runtime[id].duplicate(true)
			person.position=Vector2(person.cell)
			if person.has("bypass"):
				person.position=Vector2(person.bypass.at)-FOOT_OFFSET
			elif not person.route.is_empty():
				person.position=Vector2(person.cell).lerp(Vector2(person.route[0]),clampf(float(person.wait)/float(settings.walk_step_sec),0,1))
				person.facing=Vector2i(person.route[0])-Vector2i(person.cell)
			result.append(person)
	return result

func _zone_target(zone: String, id: String) -> Vector2i:
	if _map==null or zone=="offstage": return Vector2i(-1,-1)
	var key:=zone+":"+id
	if _targets.has(key): return _targets[key]
	var plot: Dictionary={}
	for item: Dictionary in _map.plots:
		if str(item.id)==zone or str(item.kind)==zone or str(item.get("zone_id",""))==zone: plot=item;break
	if plot.is_empty():
		for item: Dictionary in _map.plots:
			if str(item.get("kind",""))=="market": plot=item;break
	var center:=Vector2i(int(plot.get("x",10))+int(plot.get("w",1))/2,int(plot.get("y",10))+int(plot.get("h",1)))
	var best:=Vector2i(-1,-1);var distance:=100000
	for y: int in _map.extent:
		for x: int in _map.extent:
			if not _map.is_road(x,y) or not _clear_cell(Vector2i(x,y)): continue
			var d:=absi(x-center.x)+absi(y-center.y)
			if d<distance: distance=d;best=Vector2i(x,y)
	if zone!="player_diner" and id=="aling":
		var next:=_road_neighbors(best)
		if not next.is_empty(): best=next[0]
	_targets[key]=best
	return best

func _clear_cell(at: Vector2i) -> bool:
	if not foot_clear.is_valid(): return true
	if not _cells.has(at): _cells[at] = foot_clear.call(Vector2(at) + FOOT_OFFSET)
	return _cells[at]

func _road_neighbors(at: Vector2i) -> Array[Vector2i]:
	if _neighbors.has(at): return _neighbors[at]
	var result: Array[Vector2i]=[]
	for step: Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
		var next := at + step
		if not _clear_cell(next): continue
		if not _map.is_road(next.x,next.y):
			# A narrow verge lets people walk around furniture placed on a street.
			if not foot_clear.is_valid(): continue
			if not (_map.roads.has(next+Vector2i.LEFT) or _map.roads.has(next+Vector2i.RIGHT)
					or _map.roads.has(next+Vector2i.UP) or _map.roads.has(next+Vector2i.DOWN)): continue
		if foot_clear.is_valid() and not TDPlannedTown._reference_segment_clear(
				Vector2(at)+FOOT_OFFSET,Vector2(next)+FOOT_OFFSET,foot_clear): continue
		result.append(next)
	_neighbors[at] = result
	return result

func _path(start: Vector2i, target: Vector2i, avoiding_for: String = "") -> Array:
	if start==target: return []
	var queue: Array[Vector2i]=[start];var parents: Dictionary={start:start};var head:=0
	while head<queue.size():
		var here: Vector2i=queue[head];head+=1
		for next: Vector2i in _road_neighbors(here):
			if parents.has(next): continue
			if not avoiding_for.is_empty() and not step_clear.call(avoiding_for,Vector2(here)+FOOT_OFFSET,Vector2(next)+FOOT_OFFSET): continue
			parents[next]=here
			if next==target:
				var result: Array=[];var cursor:=target
				while cursor!=start: result.push_front(cursor);cursor=parents[cursor]
				return result
			queue.append(next)
	return []

func snapshot() -> Dictionary:
	return {"schema_version":1,"clock":clock.snapshot(),"records":records.duplicate(true)}

func validate_save(raw: Variant, day: int) -> TDOutcome:
	if not raw is Dictionary or raw.get("schema_version")!=1 or not raw.get("records") is Dictionary: return TDOutcome.new(false,"INVALID_CHARACTERS_SAVE")
	var valid:=TDWorldDayClock.validate(raw.get("clock"))
	if not valid.ok: return valid
	if int(raw.clock.day)!=day: return TDOutcome.new(false,"INCONSISTENT_CHARACTERS_DAY")
	for id: String in ORIGINAL_RESIDENTS:
		if not raw.records.has(id): return TDOutcome.new(false,"MISSING_CHARACTER")
	for id: String in raw.records:
		if not definitions.has(id): return TDOutcome.new(false,"UNKNOWN_CHARACTER")
		if not raw.records.get(id) is Dictionary: return TDOutcome.new(false,"MISSING_CHARACTER")
		var r: Dictionary=raw.records[id]
		if not TDServiceCatalog.integer(r.get("affection"),0,100): return TDOutcome.new(false,"INVALID_AFFECTION")
		for key: String in ["last_chat_day","last_meal_day","last_attempt_day","last_visit_day"]:
			if not TDServiceCatalog.integer(r.get(key),0,day): return TDOutcome.new(false,"INVALID_CHARACTER_DAY")
		if not r.get("last_meal_token") is String or r.last_meal_token.length()>160 or not r.get("flags") is Dictionary or r.flags.size()>128: return TDOutcome.new(false,"INVALID_CHARACTER_FLAGS")
		for flag: Variant in r.flags:
			if not flag is String or flag.is_empty() or flag.length()>120 or not r.flags[flag] is bool: return TDOutcome.new(false,"INVALID_CHARACTER_FLAGS")
	return TDOutcome.new(true,"VALID_CHARACTERS_SAVE")

func restore(raw: Dictionary, day: int) -> TDOutcome:
	var valid:=validate_save(raw,day)
	if not valid.ok: return valid
	clock.restore(raw.clock);records=raw.records.duplicate(true);runtime.clear();pinned.clear();_held.clear()
	for id: String in records:
		if not _requires_encounter(id) and (int(records[id].last_chat_day)>0 or int(records[id].last_meal_day)>0): mark_met(id)
	for id: String in definitions:
		if not records.has(id): _reset_record(id)
	return TDOutcome.new(true,"CHARACTERS_RESTORED")

func migrate(day: int, settled: bool) -> void:
	for id: String in definitions: _reset_record(id)
	clock.day=day;clock.minute=1200.0 if settled else TDWorldDayClock.START_MINUTE;clock.closed_day=0
	runtime.clear();pinned.clear();_held.clear()

func next_day(day: int) -> void:
	clock.next_day(day);runtime.clear();pinned.clear();_held.clear()
	if _map!=null: sync_map(_map)
