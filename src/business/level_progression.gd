class_name TDLevelProgression
extends RefCounted
## Portfolio-wide daily growth. No wallet, scene, wall clock or random dependencies.
const PATH := "res://content/brand/progression.json"
var config: Dictionary = {}
var error := TDOutcome.new(true)
var _state: Dictionary = {}

func _init(definitions: Dictionary = {}) -> void:
	var raw: Variant = definitions if not definitions.is_empty() else JSON.parse_string(FileAccess.get_file_as_string(PATH))
	error = validate_config(raw)
	if not error.ok: return
	config = raw.duplicate(true)
	start(1, {})

static func integer(value: Variant, low: int, high: int) -> bool:
	return TDServiceCatalog.integer(value, low, high)

static func metric(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0 and float(value) <= 100

static func identity(value: Variant) -> bool:
	return value is String and not value.is_empty() and value.length() <= 120

static func same_value(a: Variant, b: Variant) -> bool:
	# JSON parses numbers as floats. Do not mistake a valid round-trip for corruption,
	# and never coerce strings, fractional counters or non-finite values into integers.
	if (a is int or a is float) and (b is int or b is float):
		if not is_finite(float(a)) or not is_finite(float(b)): return false
		if a is int or b is int: return float(a)==float(b)
		return absf(a-b)<=0.000000001*maxf(1.0,maxf(absf(a),absf(b)))
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size(): return false
		for key: Variant in a:
			if not b.has(key) or not same_value(a[key],b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size(): return false
		for i: int in a.size():
			if not same_value(a[i],b[i]): return false
		return true
	return typeof(a)==typeof(b) and a==b

static func validate_config(raw: Variant) -> TDOutcome:
	if not raw is Dictionary or raw.get("schema_version") != 1 or raw.get("rules_version") != 1: return TDOutcome.new(false,"INVALID_LEVEL_CONFIG_VERSION")
	if not integer(raw.get("max_level"),2,100): return TDOutcome.new(false,"INVALID_LEVEL_CONFIG")
	for field: String in ["curve","daily","rewards"]:
		if not raw.get(field) is Dictionary: return TDOutcome.new(false,"INVALID_LEVEL_CONFIG",field)
	for key: String in ["base_xp","linear_xp","quadratic_xp"]:
		if not integer(raw.curve.get(key),1 if key=="base_xp" else 0,100000): return TDOutcome.new(false,"INVALID_LEVEL_CURVE")
	for key: String in ["profit_reference_cents","profit_cap_xp","popularity_cap_xp","awareness_cap_xp","growth_xp_per_point","max_xp"]:
		if not integer(raw.daily.get(key),1,1000000): return TDOutcome.new(false,"INVALID_LEVEL_MAPPING")
	if int(raw.daily.max_xp) > 1000 or int(raw.daily.max_xp) != int(raw.daily.profit_cap_xp)+int(raw.daily.popularity_cap_xp)+int(raw.daily.awareness_cap_xp): return TDOutcome.new(false,"INVALID_LEVEL_CAP")
	if not integer(raw.rewards.get("inspiration"),1,5000) or not integer(raw.rewards.get("milestone_bonus"),0,5000) or not integer(raw.rewards.get("milestone_every"),1,100): return TDOutcome.new(false,"INVALID_LEVEL_REWARD")
	if not raw.get("hooks") is Array or raw.hooks.size()>200: return TDOutcome.new(false,"INVALID_LEVEL_HOOKS")
	var seen: Dictionary = {}
	for hook: Variant in raw.hooks:
		if not hook is Dictionary or not identity(hook.get("id")) or seen.has(hook.id) or not identity(hook.get("target_id")) or not integer(hook.get("level"),2,int(raw.max_level)) or hook.get("kind") not in ["feature","furniture","story","event"]: return TDOutcome.new(false,"INVALID_LEVEL_HOOK")
		seen[hook.id]=true
	return TDOutcome.new(true,"VALID")

func start(day: int, baselines: Dictionary, migrated: bool = false) -> void:
	_state={"schema_version":1,"rules_version":1,"level":1,"total_xp":0,"origin_day":day,"last_day":day-1,"migrated":migrated,"baselines":baselines.duplicate(true),"rewards":[],"events":{},"recent":[]}

func snapshot() -> Dictionary:
	return _state.duplicate(true)

func required_xp(level: int) -> int:
	var n := maxi(0,level-1)
	return int(config.curve.base_xp)+int(config.curve.linear_xp)*n+int(config.curve.quadratic_xp)*n*n

func threshold(level: int) -> int:
	var total := 0
	for current: int in range(1,level): total += required_xp(current)
	return total

func level_for(total: int) -> int:
	var level := 1
	while level<int(config.max_level) and total>=threshold(level+1): level+=1
	return level

func reward_for(level: int) -> Dictionary:
	var amount := int(config.rewards.inspiration)
	if level % int(config.rewards.milestone_every)==0: amount+=int(config.rewards.milestone_bonus)
	return {"level":level,"inspiration":amount,"grant_id":"level:v1:%d:inspiration"%level}

func progress() -> Dictionary:
	var level := int(_state.level)
	return {"level":level,"total_xp":int(_state.total_xp),"current_xp":int(_state.total_xp)-threshold(level),"required_xp":required_xp(level),"max_level":int(config.max_level),"at_cap":level==int(config.max_level),"migrated":bool(_state.migrated),"origin_day":int(_state.origin_day)}

func _report(raw: Variant) -> TDOutcome:
	if not raw is Dictionary or not integer(raw.get("day"),1,1000000) or not raw.get("stores") is Array or raw.stores.is_empty() or raw.stores.size()>1000: return TDOutcome.new(false,"INVALID_LEVEL_REPORT")
	var rows: Array = []
	var seen: Dictionary = {}
	for row: Variant in raw.stores:
		if not row is Dictionary or not identity(row.get("store_id")) or seen.has(row.store_id) or not integer(row.get("scale_milli"),1000,1000000) or not integer(row.get("profit_cents"),-1000000000000,1000000000000): return TDOutcome.new(false,"INVALID_LEVEL_STORE")
		var normalized: Dictionary={"store_id":str(row.store_id),"scale_milli":int(row.scale_milli),"profit_cents":int(row.profit_cents)}
		for key: String in ["popularity_before","popularity_after","awareness_before","awareness_after"]:
			if not metric(row.get(key)): return TDOutcome.new(false,"INVALID_LEVEL_METRIC",key)
			normalized[key]=roundf(float(row[key])*1000000.0)/1000000.0
		seen[row.store_id]=true;rows.append(normalized)
	rows.sort_custom(func(a: Dictionary,b: Dictionary)->bool:return a.store_id<b.store_id)
	return TDOutcome.new(true,"VALID","",{"day":int(raw.day),"stores":rows})

func evaluate(raw: Variant) -> TDOutcome:
	if not error.ok: return error
	var checked := _report(raw)
	if not checked.ok: return checked
	var profit: int=0
	var scale: int=0
	var popularity: float=0
	var awareness: float=0
	for row: Dictionary in checked.data.stores:
		profit+=int(row.profit_cents);scale+=int(row.scale_milli)
		popularity+=(float(row.popularity_after)-float(row.popularity_before))*int(row.scale_milli)
		awareness+=(float(row.awareness_after)-float(row.awareness_before))*int(row.scale_milli)
	popularity/=scale;awareness/=scale
	var normalized_profit: float=float(maxi(0,profit))*1000.0/scale
	var daily: Dictionary=config.daily
	var income_xp := floori(float(daily.profit_cap_xp)*normalized_profit/(normalized_profit+int(daily.profit_reference_cents)))
	var popularity_xp := mini(int(daily.popularity_cap_xp),floori(maxf(0,popularity)*int(daily.growth_xp_per_point)+0.0000001))
	var awareness_xp := mini(int(daily.awareness_cap_xp),floori(maxf(0,awareness)*int(daily.growth_xp_per_point)+0.0000001))
	return TDOutcome.new(true,"EVALUATED","",{"day":int(checked.data.day),"input":checked.data,"profit_cents":profit,"scale_milli":scale,"store_count":checked.data.stores.size(),"normalized_profit_cents":normalized_profit,"popularity_delta":popularity,"awareness_delta":awareness,"profit_xp":income_xp,"popularity_xp":popularity_xp,"awareness_xp":awareness_xp,"mapped_xp":income_xp+popularity_xp+awareness_xp})

func settle(raw: Variant) -> TDOutcome:
	var evaluated := evaluate(raw)
	if not evaluated.ok: return evaluated
	var day := int(evaluated.data.day)
	if day==int(_state.last_day):
		if not _state.recent.is_empty() and same_value(_state.recent.back().input,evaluated.data.input): return TDOutcome.new(true,"ALREADY_APPLIED","",_state.recent.back().duplicate(true))
		return TDOutcome.new(false,"DAY_CONFLICT")
	if day!=int(_state.last_day)+1: return TDOutcome.new(false,"INVALID_LEVEL_DAY")
	for row: Dictionary in evaluated.data.input.stores:
		if _state.baselines.has(row.store_id):
			var old: Dictionary=_state.baselines[row.store_id]
			if not is_equal_approx(float(old.popularity),float(row.popularity_before)) or not is_equal_approx(float(old.awareness),float(row.awareness_before)): return TDOutcome.new(false,"LEVEL_BASELINE_CONFLICT")
	var next := snapshot()
	var old_level := int(next.level)
	next.total_xp=mini(threshold(int(config.max_level)),int(next.total_xp)+int(evaluated.data.mapped_xp))
	next.level=level_for(int(next.total_xp));next.last_day=day;next.baselines={}
	for row: Dictionary in evaluated.data.input.stores: next.baselines[row.store_id]={"popularity":row.popularity_after,"awareness":row.awareness_after}
	var gained: Array=[]
	for level: int in range(old_level+1,int(next.level)+1):
		var reward := reward_for(level)
		next.rewards.append(reward);gained.append(reward.duplicate(true))
		var event_id := "level:v1:%d:reached"%level
		next.events[event_id]={"event_id":event_id,"level":level,"kind":"level_reached","target_id":"","status":"pending"}
		for hook: Dictionary in config.hooks:
			if int(hook.level)!=level: continue
			var id := "level:v1:hook:"+str(hook.id)
			next.events[id]={"event_id":id,"level":level,"kind":str(hook.kind),"target_id":str(hook.target_id),"status":"pending"}
	var record := evaluated.data.duplicate(true)
	record.xp=int(next.total_xp)-int(_state.total_xp);record.level_before=old_level;record.level_after=int(next.level);record.rewards=gained
	next.recent.append(record)
	while next.recent.size()>28: next.recent.pop_front()
	_state=next
	return TDOutcome.new(true,"LEVEL_SETTLED","",record.duplicate(true))

func pending_events() -> Array:
	return _state.events.values().filter(func(event: Dictionary)->bool:return event.status=="pending").duplicate(true)

func acknowledge(id: String) -> TDOutcome:
	if not _state.events.has(id): return TDOutcome.new(false,"UNKNOWN_LEVEL_EVENT")
	if _state.events[id].status=="acknowledged": return TDOutcome.new(true,"ALREADY_APPLIED")
	_state.events[id].status="acknowledged"
	return TDOutcome.new(true,"ACKNOWLEDGED")

func has_entitlement(kind: String, target_id: String) -> bool:
	if kind not in ["feature","furniture"]: return false
	return _state.events.values().any(func(event:Dictionary)->bool:return event.kind==kind and event.target_id==target_id)

func validate_save(raw: Variant) -> TDOutcome:
	if not raw is Dictionary or raw.get("schema_version")!=1 or raw.get("rules_version")!=1: return TDOutcome.new(false,"UNSUPPORTED_LEVEL_VERSION")
	if not integer(raw.get("total_xp"),0,threshold(int(config.max_level))) or not integer(raw.get("level"),1,int(config.max_level)) or int(raw.level)!=level_for(int(raw.total_xp)): return TDOutcome.new(false,"INVALID_LEVEL_XP")
	if not integer(raw.get("origin_day"),1,1000001) or not integer(raw.get("last_day"),0,1000000) or int(raw.last_day)<int(raw.origin_day)-1 or not raw.get("migrated") is bool: return TDOutcome.new(false,"INVALID_LEVEL_CURSOR")
	if not raw.get("baselines") is Dictionary or raw.baselines.size()>1000 or not raw.get("recent") is Array or raw.recent.size()>28 or not raw.get("rewards") is Array or not raw.get("events") is Dictionary: return TDOutcome.new(false,"INVALID_LEVEL_STATE")
	for id: Variant in raw.baselines:
		var row: Variant=raw.baselines[id]
		if not identity(id) or not row is Dictionary or not metric(row.get("popularity")) or not metric(row.get("awareness")): return TDOutcome.new(false,"INVALID_LEVEL_BASELINE")
	if raw.rewards.size()!=int(raw.level)-1: return TDOutcome.new(false,"INVALID_LEVEL_REWARDS")
	var expected_events: Dictionary={}
	for level: int in range(2,int(raw.level)+1):
		var row: Variant=raw.rewards[level-2]
		var expected := reward_for(level)
		if not row is Dictionary or not same_value(row,expected): return TDOutcome.new(false,"INVALID_LEVEL_REWARDS")
		var event_id := "level:v1:%d:reached"%level
		expected_events[event_id]={"event_id":event_id,"level":level,"kind":"level_reached","target_id":""}
		for hook: Dictionary in config.hooks:
			if int(hook.level)==level:
				var id := "level:v1:hook:"+str(hook.id)
				expected_events[id]={"event_id":id,"level":level,"kind":str(hook.kind),"target_id":str(hook.target_id)}
	if raw.events.size()!=expected_events.size(): return TDOutcome.new(false,"INVALID_LEVEL_EVENTS")
	for id: String in expected_events:
		if not raw.events.get(id) is Dictionary: return TDOutcome.new(false,"INVALID_LEVEL_EVENT")
		var row: Dictionary=raw.events[id].duplicate(true)
		if row.get("status") not in ["pending","acknowledged"]: return TDOutcome.new(false,"INVALID_LEVEL_EVENT")
		row.erase("status")
		if not same_value(row,expected_events[id]): return TDOutcome.new(false,"INVALID_LEVEL_EVENT")
	var previous: int = int(raw.last_day)-raw.recent.size()
	var recent_xp := 0
	for record: Variant in raw.recent:
		if not record is Dictionary or not integer(record.get("day"),int(raw.origin_day),int(raw.last_day)) or int(record.day)!=previous+1 or not integer(record.get("xp"),0,int(config.daily.max_xp)): return TDOutcome.new(false,"INVALID_LEVEL_HISTORY")
		var mapped := evaluate(record.get("input"))
		if not mapped.ok or mapped.data.day!=record.day: return TDOutcome.new(false,"INVALID_LEVEL_HISTORY")
		for key: String in mapped.data:
			if not record.has(key) or not same_value(record[key],mapped.data[key]): return TDOutcome.new(false,"INVALID_LEVEL_HISTORY",key)
		if int(record.xp)>int(record.mapped_xp) or not integer(record.get("level_before"),1,int(raw.level)) or not integer(record.get("level_after"),int(record.level_before),int(raw.level)) or not record.get("rewards") is Array: return TDOutcome.new(false,"INVALID_LEVEL_HISTORY")
		recent_xp+=int(record.xp);previous=int(record.day)
	if raw.recent.size()!=mini(28,int(raw.last_day)-int(raw.origin_day)+1) or recent_xp>int(raw.total_xp): return TDOutcome.new(false,"INVALID_LEVEL_HISTORY")
	if int(raw.last_day)-int(raw.origin_day)+1<=28 and recent_xp!=int(raw.total_xp): return TDOutcome.new(false,"INVALID_LEVEL_HISTORY")
	var running_xp: int=int(raw.total_xp)-recent_xp
	for record: Dictionary in raw.recent:
		if level_for(running_xp)!=int(record.level_before): return TDOutcome.new(false,"INVALID_LEVEL_HISTORY")
		running_xp+=int(record.xp)
		if level_for(running_xp)!=int(record.level_after): return TDOutcome.new(false,"INVALID_LEVEL_HISTORY")
		var expected_rewards: Array=[]
		for level: int in range(int(record.level_before)+1,int(record.level_after)+1): expected_rewards.append(reward_for(level))
		if not same_value(record.rewards,expected_rewards): return TDOutcome.new(false,"INVALID_LEVEL_HISTORY")
	if not raw.recent.is_empty():
		var baselines: Dictionary={}
		for row: Dictionary in raw.recent.back().input.stores: baselines[row.store_id]={"popularity":row.popularity_after,"awareness":row.awareness_after}
		if not same_value(raw.baselines,baselines): return TDOutcome.new(false,"INVALID_LEVEL_BASELINE")
	return TDOutcome.new(true,"VALID")

func restore(raw: Variant) -> TDOutcome:
	var valid := validate_save(raw)
	if not valid.ok: return valid
	_state=raw.duplicate(true)
	for key: String in ["schema_version","rules_version","level","total_xp","origin_day","last_day"]: _state[key]=int(_state[key])
	for row: Dictionary in _state.rewards:
		row.level=int(row.level);row.inspiration=int(row.inspiration)
	for row: Dictionary in _state.events.values(): row.level=int(row.level)
	return TDOutcome.new(true,"RESTORED")
