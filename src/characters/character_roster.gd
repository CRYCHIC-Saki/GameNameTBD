class_name TDCharacterRoster
extends RefCounted
## Save-slot relationships and schedules; dining still uses EconomicCustomer/MealIntent.
const SOURCE := "res://content/characters/roster.json"
var definitions: Dictionary = {}
var settings: Dictionary = {}
var records: Dictionary = {}
var clock := TDWorldDayClock.new()
var error := TDOutcome.new(true)
var runtime: Dictionary = {} # Transient world position and current order, never a second wallet.
var pinned: Dictionary = {}
var _map: TDTownMap
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
		var source_id:="resident:%s:%s:%d"%[d.town_id,b.group_id,int(b.family_index)%family_count]
		if str(raw.id)!=source_id: continue
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
	if not definitions.has(id): return talk
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
	if context.get("kind")!="resident" or not records.has(id) or int(context.get("day",0))!=clock.day: return TDOutcome.new(false,"STALE_CONVERSATION")
	if not completed or not picks.any(func(p: Variant)->bool:return p in ["chat","about"]): return TDOutcome.new(true,"CHAT_CANCELLED")
	mark_met(id)
	if int(records[id].last_chat_day)==clock.day: return TDOutcome.new(true,"CHAT_ALREADY_COUNTED")
	records[id].last_chat_day=clock.day
	records[id].affection=clampi(int(records[id].affection)+int(settings.chat_gain),0,100)
	return TDOutcome.new(true,"RELATIONSHIP_CHANGED")

func observe_orders(orders: Array) -> void:
	for order: Dictionary in orders:
		var id:=character_for(order.get("economic_profile",{}))
		if id.is_empty() or int(order.get("economic_intent",{}).get("day",0))!=clock.day: continue
		var r: Dictionary=records[id]
		if order.status=="SERVED": mark_met(id)
		if order.status=="SERVED" and int(r.last_meal_day)<clock.day and not order.get("score",{}).is_empty():
			var score:=float(order.score.get("satisfaction",0))
			var gain:=int(settings.good_meal_gain) if score>=float(settings.good_meal_score) else (int(settings.bad_meal_gain) if score<float(settings.bad_meal_score) else 0)
			r.affection=clampi(int(r.affection)+gain,0,100);r.last_meal_day=clock.day;r.last_meal_token=str(order.id)
		if not runtime.has(id): continue
		var actor: Dictionary=runtime[id]
		if int(r.last_visit_day)<clock.day and order.status in ["ARRIVING","WAITING","COOKING","SERVED"]:
			r.last_visit_day=clock.day;actor.order_id=str(order.id);actor.phase="to_diner";actor.route=[];actor.goal=Vector2i(-1,-1);actor.entered=false
		if str(actor.order_id)==str(order.id) and order.status not in ["ARRIVING","WAITING","COOKING","SERVED"] and not actor.get("entered",false):
			finish_visit(id,str(order.id))

func finish_visit(id: String, order_id: String) -> void:
	if not runtime.has(id) or str(runtime[id].order_id)!=order_id: return
	runtime[id].order_id="";runtime[id].phase="town";runtime[id].entered=false;runtime[id].route=[];runtime[id].goal=Vector2i(-1,-1)

func begin_visit(id: String, order_id: String) -> void:
	if can_enter(id,order_id): runtime[id].entered=true

func can_enter(id: String, order_id: String) -> bool:
	return runtime.has(id) and runtime[id].phase=="dining" and str(runtime[id].order_id)==order_id

func sync_map(map: TDTownMap) -> void:
	_map=map
	_targets.clear()
	_activity_points.clear();_safe_roads.clear()
	for at: Vector2i in map.roads:
		var safe: bool=true
		for plot: Dictionary in map.plots:
			if TDInteractionRange.facility(plot) and TDInteractionRange.distance(Vector2(at)+Vector2(.5,.5),TDInteractionRange.plot_bounds(plot))<=1.5:
				safe=false;break
		if safe: _safe_roads.append(at)
	_safe_roads.sort_custom(func(a:Vector2i,b:Vector2i)->bool:return a.y<b.y or (a.y==b.y and a.x<b.x))
	for id: String in definitions:
		if runtime.has(id):
			runtime[id].goal=Vector2i(-1,-1);runtime[id].route=[];runtime[id].activity_key="";runtime[id].wait=0.0
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
			a.cell=pinned[id];a.phase="town";a.route=[];a.goal=Vector2i(-1,-1);a.wait=0.0;a.activity_key="";continue
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
	if a.phase!="to_diner" and span.zone=="offstage": a.phase="offstage";a.route=[];a.wait=0.0;return
	if a.phase=="offstage": a.phase="town"
	var key: String="visit:"+str(a.order_id) if a.phase=="to_diner" else "%s:%s"%[span.zone,span.get("from",0)]
	if str(a.get("activity_key",""))!=key or a.goal==Vector2i(-1,-1):
		a.activity_key=key;a.patrol=0;a.dwell=0.0;a.wait=0.0
		_set_goal(a,_zone_target("player_diner",id) if a.phase=="to_diner" else _patrol_target(id,span,a))
	var left: float=seconds
	while true:
		if not a.route.is_empty():
			var step: float=minf(left,maxf(0.0,float(settings.walk_step_sec)-float(a.wait)))
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
	var key: String="%s:%s:%s"%[span.zone,id,span.get("radius_tiles",7)]
	if not _activity_points.has(key):
		var candidates: Array[Vector2i]=[]
		for point: Vector2i in _safe_roads:
			if Vector2(point).distance_to(Vector2(anchor))<=float(span.get("radius_tiles",7)): candidates.append(point)
		_activity_points[key]=candidates
	var points: Array=_activity_points[key]
	if points.is_empty(): return anchor
	var start: int=(absi(id.hash())+int(a.patrol)*17)%points.size()
	for i: int in points.size():
		var point: Vector2i=points[(start+i)%points.size()]
		if Vector2(point).distance_to(Vector2(a.cell))>=4.0 and not reserved.any(func(other:Vector2i)->bool:return point.distance_to(other)<2.0): return point
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
			if not person.route.is_empty():
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
			if not _map.is_road(x,y): continue
			var d:=absi(x-center.x)+absi(y-center.y)
			if d<distance: distance=d;best=Vector2i(x,y)
	if zone!="player_diner" and id=="aling":
		var next:=_road_neighbors(best)
		if not next.is_empty(): best=next[0]
	_targets[key]=best
	return best

func _road_neighbors(at: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i]=[]
	for step: Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
		if _map.is_road(at.x+step.x,at.y+step.y): result.append(at+step)
	return result

func _path(start: Vector2i, target: Vector2i) -> Array:
	if start==target: return []
	var queue: Array[Vector2i]=[start];var parents: Dictionary={start:start};var head:=0
	while head<queue.size():
		var here: Vector2i=queue[head];head+=1
		for next: Vector2i in _road_neighbors(here):
			if parents.has(next): continue
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
	if int(raw.clock.day)!=day or raw.records.size()!=definitions.size(): return TDOutcome.new(false,"INCONSISTENT_CHARACTERS_DAY")
	for id: String in definitions:
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
		if int(records[id].last_chat_day)>0 or int(records[id].last_meal_day)>0: mark_met(id)
	return TDOutcome.new(true,"CHARACTERS_RESTORED")

func migrate(day: int, settled: bool) -> void:
	for id: String in definitions: _reset_record(id)
	clock.day=day;clock.minute=1200.0 if settled else TDWorldDayClock.START_MINUTE;clock.closed_day=0
	runtime.clear();pinned.clear();_held.clear()

func next_day(day: int) -> void:
	clock.next_day(day);runtime.clear();pinned.clear();_held.clear()
	if _map!=null: sync_map(_map)
