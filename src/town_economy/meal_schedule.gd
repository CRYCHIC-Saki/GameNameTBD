class_name TDMealSchedule
extends RefCounted
## One small immutable daily schedule. Querying it never advances economic RNG.
var config: Dictionary = {}
var error := TDOutcome.new(true)
var _cache: Dictionary = {}

func _init() -> void:
	var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://content/town_economy/meal_schedule.json"))
	error=validate(raw)
	if error.ok: config=raw

static func validate(raw: Variant) -> TDOutcome:
	if not raw is Dictionary or raw.get("schema_version")!=1 or not raw.get("peaks") is Array or raw.peaks.size()!=3: return TDOutcome.new(false,"INVALID_MEAL_SCHEDULE")
	var total: float=0
	for key: String in ["start_minute","end_minute","off_peak_end"]:
		if not TDEconomicCustomer.finite_range(raw.get(key),0,2880): return TDOutcome.new(false,"INVALID_MEAL_TIME")
	if raw.start_minute>=raw.off_peak_end or raw.off_peak_end>raw.end_minute: return TDOutcome.new(false,"INVALID_MEAL_TIME")
	if not TDEconomicCustomer.finite_range(raw.get("off_peak_weight"),0,1): return TDOutcome.new(false,"INVALID_MEAL_WEIGHT")
	var ids: Dictionary={}
	for p: Variant in raw.peaks:
		if not p is Dictionary or not p.get("id") is String or ids.has(p.id): return TDOutcome.new(false,"INVALID_MEAL_PEAK")
		ids[p.id]=true
		if not TDEconomicCustomer.finite_range(p.get("mean"),raw.start_minute,raw.end_minute) or not TDEconomicCustomer.finite_range(p.get("sigma"),1,300) or not TDEconomicCustomer.finite_range(p.get("weight"),0,1): return TDOutcome.new(false,"INVALID_MEAL_PEAK")
		total+=float(p.weight)
	return TDOutcome.new(is_equal_approx(total+float(raw.off_peak_weight),1.0),"MEAL_WEIGHTS")

func events(count: int, seed_value: int, day: int, town: String) -> Array:
	if not error.ok or count<=0: return []
	var key: String="%d:%d:%s:%d"%[seed_value,day,town,count]
	if _cache.has(key): return _cache[key].duplicate(true)
	var rng:=TDBusinessRandom.new(("meals:"+key).hash())
	var rows: Array=[]
	for index: int in count:
		var fraction: float=(index+0.5)/count
		var accumulated: float=0
		var peak: Dictionary={}
		for p: Dictionary in config.peaks:
			accumulated+=float(p.weight)
			if fraction<accumulated: peak=p;break
		var minute: float
		var period: String="off_peak"
		if peak.is_empty(): minute=lerpf(float(config.start_minute),float(config.off_peak_end),rng.unit())
		else:
			period=peak.id
			minute=float(peak.mean)+float(peak.sigma)*sqrt(-2.0*log(maxf(0.000001,rng.unit())))*cos(TAU*rng.unit())
		rows.append({"minute":clampf(minute,float(config.start_minute),float(config.end_minute)-1),"period":period,"serial":index})
	rows.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return a.minute<b.minute or (a.minute==b.minute and a.serial<b.serial))
	# Keep only this day's tiny array; five towns do not create live NPC nodes.
	if _cache.size()>10: _cache.clear()
	_cache[key]=rows.duplicate(true)
	return rows
