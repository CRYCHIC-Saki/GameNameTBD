class_name TDResearchSession
extends RefCounted
signal changed
signal attempt_completed(result:Dictionary)
var catalog: TDResearchCatalog
var save_sink: Callable
var clock:=TDClock.new()
var controller: TDResearchLesson
var _state: Dictionary={}
var _active: Dictionary={}
var _input_serial: int=0
var last_result: Dictionary={}
var load_error: String=""

func _init(definitions: TDResearchCatalog) -> void:
	catalog=definitions
	_state={"schema_version":1,"points":int(catalog.data.unlock_rules.default_points),"cuisines":["cn"],"unlocked":catalog.data.unlock_rules.initial_unlocked_ids.duplicate(),"licensed":[],"grandfathered":[],"legacy_ids":[],"best":{},"events":{},"attempt_serial":0,"completed_attempts":0,"study_hours":0,"world_time":{"day":1,"phase":"morning","spent":0.0},"input_offset_sec":0.0}

func snapshot() -> Dictionary:
	return _state.duplicate(true)

func has(id: String) -> bool:
	return id in _state.unlocked

func status(id: String) -> String:
	var node:=catalog.node(id)
	if node.is_empty(): return "UNKNOWN_RECIPE"
	if has(id): return "UNLOCKED"
	if node.cuisine_id not in _state.cuisines: return "STORY_LOCKED"
	for parent: String in node.prerequisites:
		if not has(parent): return "PREREQUISITES"
	if catalog.chart(id).is_empty(): return "CHART_PENDING"
	if id in _state.licensed: return "RESEARCHABLE"
	return "AVAILABLE" if _state.points>=node.cost else "POINTS_SHORT"

func begin(id: String, time: Dictionary={"day":1,"phase":"morning","spent":0.0}, _available_hours: float=100.0) -> TDOutcome:
	if not _active.is_empty(): return TDOutcome.new(false,"BUSY")
	if load_error!="": return TDOutcome.new(false,load_error)
	if status(id) not in ["AVAILABLE","RESEARCHABLE"]: return TDOutcome.new(false,status(id))
	# D032: practice has no daily time budget; retain the argument for callers.
	if time.get("phase") not in ["morning","evening"]: return TDOutcome.new(false,"SHOP_OPEN")
	var lesson:=TDResearchLesson.new()
	var prepared:=lesson.configure(catalog.chart(id,float(_state.input_offset_sec)))
	if not prepared.ok: lesson.free(); return prepared
	var candidate:=snapshot(); var cost:int=0
	if id not in candidate.licensed:
		cost=int(catalog.node(id).cost); candidate.points-=cost; candidate.licensed.append(id)
	candidate.attempt_serial+=1; candidate.world_time=time.duplicate(true)
	var saved:=_commit(candidate)
	if not saved.ok: lesson.free(); return saved
	var token: String="study-%d"%int(_state.attempt_serial)
	controller=lesson; controller.token=token; clock=controller.clock
	_active={"token":token,"recipe_id":id,"time":time.duplicate(true)}; last_result={}
	return TDOutcome.new(true,"STARTED","",{"token":token,"cost":cost,"recipe_id":id})

func advance(delta: float) -> TDOutcome:
	if _active.is_empty(): return TDOutcome.new(false,"NO_ATTEMPT")
	return controller.advance(delta)

func input(token: String, action: String, pressed: bool, value: float=1.0) -> TDOutcome:
	if _active.is_empty() or token!=_active.token: return TDOutcome.new(false,"STALE_ATTEMPT")
	return controller.input_action(action,pressed,value)

func progress() -> Dictionary:
	return controller.update().data if not _active.is_empty() else last_result.duplicate(true)

func finish(token: String) -> TDOutcome:
	if _active.is_empty() or token!=_active.token: return TDOutcome.new(false,"STALE_ATTEMPT")
	var result:=controller.finish()
	# Completed results remain retryable when the storage transaction fails.
	if not result.ok and result.code=="ALREADY_FINISHED": result=TDOutcome.new(true,"COMPLETED","",last_result)
	if not result.ok: return result
	last_result=result.data.duplicate(true)
	var score:float=clampf(float(result.data.quality)*100.0,0,100)
	var id:String=_active.recipe_id; var candidate:=snapshot()
	candidate.best[id]=maxf(float(candidate.best.get(id,0)),score)
	candidate.completed_attempts+=1
	candidate.world_time=_active.time.duplicate(true)
	var passed:bool=score+0.0000001>=float(catalog.data.settings.pass_score)
	if passed and id not in candidate.unlocked: candidate.unlocked.append(id)
	var saved:=_commit(candidate)
	if not saved.ok: return saved
	_active.clear(); controller.dispose(); controller=null
	last_result.merge({"score":score,"passed":passed,"recipe_id":id,"token":token},true)
	attempt_completed.emit(last_result.duplicate(true))
	return TDOutcome.new(true,"UNLOCKED" if passed else "LOW_SCORE","",last_result.duplicate(true))

func cancel(token: String) -> TDOutcome:
	if _active.is_empty() or token!=_active.token: return TDOutcome.new(false,"STALE_ATTEMPT")
	controller.dispose(); controller=null; _active.clear(); last_result={}
	return TDOutcome.new(true,"CANCELLED")

func set_paused(value: bool) -> void:
	if controller!=null: controller.set_paused(value)
	clock.paused=value

func calibrate(offset: float) -> TDOutcome:
	if not is_finite(offset) or absf(offset)>.2 or not _active.is_empty(): return TDOutcome.new(false,"INVALID_OFFSET")
	var candidate:=snapshot(); candidate.input_offset_sec=offset
	return _commit(candidate)

func recommend_cuisine(event_id: String, cuisine_id: String) -> TDOutcome:
	var valid:bool=false
	for row: Dictionary in catalog.data.cuisines:
		if row.id==cuisine_id: valid=true
	if not valid: return TDOutcome.new(false,"UNKNOWN_CUISINE")
	return _event(event_id,{"kind":"recommend","cuisine":cuisine_id})

func grant_inspiration(event_id: String, amount: int) -> TDOutcome:
	if amount<1 or amount>10000: return TDOutcome.new(false,"INVALID_REWARD")
	return _event(event_id,{"kind":"inspiration","amount":amount})

func record_cooking(day: int, recipe_id: String, score: float) -> TDOutcome:
	if day<1 or recipe_id.is_empty() or not is_finite(score) or score<80 or score>100: return TDOutcome.new(false,"NO_REWARD")
	return grant_inspiration("cooking:%d:%s"%[day,recipe_id],1)

func _event(id: String, payload: Dictionary) -> TDOutcome:
	if id.is_empty() or id.length()>160: return TDOutcome.new(false,"INVALID_EVENT")
	if _state.events.has(id): return TDOutcome.new(_state.events[id]==payload,"ALREADY_APPLIED" if _state.events[id]==payload else "EVENT_CONFLICT")
	var candidate:=snapshot(); candidate.events[id]=payload.duplicate(true)
	if payload.kind=="recommend":
		if payload.cuisine not in candidate.cuisines: candidate.cuisines.append(payload.cuisine)
	else:
		if candidate.points+payload.amount>1000000: return TDOutcome.new(false,"POINT_LIMIT")
		candidate.points+=payload.amount
	return _commit(candidate)

func inherit_legacy(runtime_ids: Array) -> TDOutcome:
	var candidate:=snapshot()
	for runtime: Variant in runtime_ids:
		if not runtime is String or runtime.is_empty(): return TDOutcome.new(false,"INVALID_LEGACY")
		if runtime not in candidate.legacy_ids: candidate.legacy_ids.append(runtime)
		var id:=catalog.atlas_id(runtime)
		if id!="" and id not in candidate.unlocked:
			candidate.unlocked.append(id); candidate.grandfathered.append(id)
	return _commit(candidate)

func restore(raw: Variant) -> TDOutcome:
	var valid:=validate_save(raw)
	if not valid.ok: return valid
	if not _active.is_empty(): return TDOutcome.new(false,"BUSY")
	_state=raw.duplicate(true); load_error=""; changed.emit()
	return TDOutcome.new(true,"RESTORED")

func _commit(candidate: Dictionary) -> TDOutcome:
	if load_error!="": return TDOutcome.new(false,load_error)
	var checked:=validate_save(candidate)
	if not checked.ok: return checked
	if save_sink.is_valid():
		var saved:TDOutcome=save_sink.call(candidate)
		if not saved.ok: return saved
	_state=candidate.duplicate(true); changed.emit()
	return TDOutcome.new(true,"APPLIED")

func validate_save(raw: Variant) -> TDOutcome:
	if not raw is Dictionary: return TDOutcome.new(false,"INVALID_SAVE")
	if raw.get("schema_version")!=1: return TDOutcome.new(false,"UNSUPPORTED_VERSION")
	for field: String in ["points","attempt_serial","completed_attempts","study_hours"]:
		if not TDResearchCatalog.integer(raw.get(field),0,1000000): return TDOutcome.new(false,"INVALID_COUNTER")
	# Historical charged hours remain valid; current attempts no longer add hours.
	if raw.completed_attempts>raw.attempt_serial or raw.study_hours>raw.completed_attempts: return TDOutcome.new(false,"INVALID_COUNTER")
	for field: String in ["cuisines","unlocked","licensed","grandfathered","legacy_ids"]:
		if not raw.get(field) is Array or raw[field].size()>1000: return TDOutcome.new(false,"INVALID_IDS")
		var seen:Array=[]
		for id:Variant in raw[field]:
			if not id is String or id.is_empty() or id in seen: return TDOutcome.new(false,"INVALID_IDS")
			seen.append(id)
			if field in ["unlocked","licensed","grandfathered"] and not catalog.nodes.has(id): return TDOutcome.new(false,"UNKNOWN_RECIPE")
			if field=="cuisines" and id not in ["cn","eu","jp","sea","lat"]: return TDOutcome.new(false,"UNKNOWN_CUISINE")
	if "cn" not in raw.cuisines: return TDOutcome.new(false,"INVALID_CUISINES")
	for id:String in raw.grandfathered:
		if id not in raw.unlocked or catalog.runtime_id(id) not in raw.legacy_ids: return TDOutcome.new(false,"INVALID_INHERITANCE")
	for id:String in raw.unlocked:
		if id in raw.grandfathered: continue
		if id not in catalog.data.unlock_rules.initial_unlocked_ids:
			if id not in raw.licensed or not raw.get("best") is Dictionary or not TDResearchCatalog.number(raw.best.get(id)) or raw.best[id]<float(catalog.data.settings.pass_score): return TDOutcome.new(false,"INVALID_UNLOCK")
		if catalog.node(id).cuisine_id not in raw.cuisines: return TDOutcome.new(false,"INVALID_UNLOCK")
		for parent:String in catalog.node(id).prerequisites:
			if parent not in raw.unlocked: return TDOutcome.new(false,"INVALID_UNLOCK")
	for id:String in raw.licensed:
		if catalog.node(id).cuisine_id not in raw.cuisines: return TDOutcome.new(false,"INVALID_LICENSE")
		if catalog.chart(id).is_empty(): return TDOutcome.new(false,"INVALID_LICENSE")
		for parent:String in catalog.node(id).prerequisites:
			if parent not in raw.unlocked: return TDOutcome.new(false,"INVALID_LICENSE")
	if not raw.get("best") is Dictionary or not raw.get("events") is Dictionary or raw.events.size()>20000: return TDOutcome.new(false,"INVALID_RESULTS")
	for id:String in raw.best:
		if not catalog.nodes.has(id) or not TDResearchCatalog.number(raw.best[id]) or raw.best[id]<0 or raw.best[id]>100: return TDOutcome.new(false,"INVALID_SCORE")
	for id:Variant in raw.events:
		var row:Variant=raw.events[id]
		if not id is String or id.is_empty() or id.length()>160 or not row is Dictionary: return TDOutcome.new(false,"INVALID_EVENT")
		if row.get("kind")=="recommend":
			if row.get("cuisine") not in raw.cuisines: return TDOutcome.new(false,"INVALID_EVENT")
		elif row.get("kind")=="inspiration":
			if not TDResearchCatalog.integer(row.get("amount"),1,10000): return TDOutcome.new(false,"INVALID_EVENT")
		else: return TDOutcome.new(false,"INVALID_EVENT")
	if not raw.get("world_time") is Dictionary or not TDResearchCatalog.integer(raw.world_time.get("day"),1,1000000) or raw.world_time.get("phase") not in ["morning","evening"] or not TDResearchCatalog.number(raw.world_time.get("spent")) or raw.world_time.spent<0 or raw.world_time.spent>24: return TDOutcome.new(false,"INVALID_WORLD_TIME")
	if not TDResearchCatalog.number(raw.get("input_offset_sec")) or absf(float(raw.input_offset_sec))>.2: return TDOutcome.new(false,"INVALID_OFFSET")
	return TDOutcome.new(true,"VALID")
