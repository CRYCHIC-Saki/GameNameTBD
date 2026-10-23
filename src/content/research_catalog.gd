class_name TDResearchCatalog
extends RefCounted

const PATH := "res://content/research/recipe_atlas.json"
var data: Dictionary = {}
var nodes: Dictionary = {}

func load_file(path: String = PATH) -> TDOutcome:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return load_data(raw)

func load_data(raw: Variant) -> TDOutcome:
	if not raw is Dictionary or not raw.get("recipes") is Array or not raw.get("cuisines") is Array or not raw.get("charts") is Dictionary:
		return TDOutcome.new(false,"INVALID_ATLAS")
	var found: Dictionary = {}; var cuisines: Array = []
	for c: Variant in raw.cuisines:
		if not c is Dictionary or not c.get("id") is String or c.id in cuisines: return TDOutcome.new(false,"INVALID_CUISINE")
		cuisines.append(c.id)
	for r: Variant in raw.recipes:
		if not r is Dictionary or not r.get("id") is String or r.id.is_empty() or found.has(r.id): return TDOutcome.new(false,"DUPLICATE_ID")
		if r.get("cuisine_id") not in cuisines or not r.get("prerequisites") is Array or not integer(r.get("cost"),0,1000000) or not integer(r.get("tier"),1,100): return TDOutcome.new(false,"INVALID_NODE")
		for field: String in ["name","ingredients","flavor","description"]:
			if not r.get(field) is String: return TDOutcome.new(false,"INVALID_NODE")
		found[r.id]=r.duplicate(true)
	if found.is_empty(): return TDOutcome.new(false,"EMPTY_ATLAS")
	for id: String in found:
		var seen: Array=[]
		for p: Variant in found[id].prerequisites:
			if not p is String or not found.has(p) or p in seen or found[p].cuisine_id!=found[id].cuisine_id: return TDOutcome.new(false,"INVALID_REFERENCE")
			seen.append(p)
	var marks: Dictionary={}
	for id: String in found:
		if not _visit(id,found,marks): return TDOutcome.new(false,"CYCLIC_ATLAS")
	if not raw.get("unlock_rules") is Dictionary or not integer(raw.unlock_rules.get("default_points"),0,1000000) or not raw.unlock_rules.get("initial_unlocked_ids") is Array: return TDOutcome.new(false,"INVALID_DEFAULTS")
	for id: Variant in raw.unlock_rules.initial_unlocked_ids:
		if not found.has(id) or found[id].cuisine_id!="cn": return TDOutcome.new(false,"INVALID_STARTERS")
	if not raw.get("settings") is Dictionary: return TDOutcome.new(false,"INVALID_SETTINGS")
	for field: String in ["pass_score","good_quality","perfect_sec","good_sec","error_weight","attempt_hours","input_offset_sec"]:
		if not number(raw.settings.get(field)): return TDOutcome.new(false,"INVALID_SETTINGS")
	if raw.settings.pass_score<0 or raw.settings.pass_score>100 or raw.settings.attempt_hours!=1: return TDOutcome.new(false,"INVALID_SETTINGS")
	var service:=TDServiceCatalog.new()
	if not service.load_file().ok or not TDResearchRuntime.install(service).ok: return TDOutcome.new(false,"INVALID_KITCHEN_CONTENT")
	for id: String in raw.charts:
		var c: Variant=raw.charts[id]
		if not found.has(id) or not c is Dictionary or c.get("kind")!="kitchen" or not integer(c.get("version"),2,100) or not c.get("primary") is Array or c.primary.is_empty(): return TDOutcome.new(false,"INVALID_CHART")
		var recipe:Dictionary=service.cooking.for_recipe(str(c.get("recipe_id",""))).get("recipe",{})
		if recipe.is_empty(): return TDOutcome.new(false,"INVALID_CHART")
		var required:Array=recipe.required_ingredients.map(func(r:Dictionary)->String:return r.id)
		if c.primary.size()!=required.size(): return TDOutcome.new(false,"INVALID_CHART")
		var seen:Array=[]
		for ingredient:Variant in c.primary:
			if not ingredient is String or ingredient not in required or ingredient in seen: return TDOutcome.new(false,"INVALID_CHART")
			seen.append(ingredient)
	if not raw.get("runtime_mapping") is Dictionary: return TDOutcome.new(false,"INVALID_MAPPING")
	var mapped: Array=[]
	for id: String in raw.runtime_mapping:
		var runtime: Variant=raw.runtime_mapping[id]
		if not found.has(id) or not runtime is String or runtime.is_empty() or runtime in mapped: return TDOutcome.new(false,"INVALID_MAPPING")
		mapped.append(runtime)
	data=raw.duplicate(true); nodes=found
	return TDOutcome.new(true,"LOADED")

func node(id: String) -> Dictionary:
	return nodes.get(id,{}).duplicate(true)

func chart(id: String, offset: float = 0.0) -> Dictionary:
	if not data.charts.has(id): return {}
	var result:Dictionary=data.charts[id].duplicate(true)
	result.input_offset_sec=clampf(offset,-.2,.2)
	return result

func runtime_id(id: String) -> String:
	return String(data.runtime_mapping.get(id,""))

func atlas_id(runtime: String) -> String:
	for id: String in data.runtime_mapping:
		if data.runtime_mapping[id]==runtime: return id
	return ""

static func _visit(id: String, found: Dictionary, marks: Dictionary) -> bool:
	if marks.get(id,0)==1: return false
	if marks.get(id,0)==2: return true
	marks[id]=1
	for parent: String in found[id].prerequisites:
		if not _visit(parent,found,marks): return false
	marks[id]=2
	return true

static func number(v: Variant) -> bool:
	return (v is int or v is float) and is_finite(float(v))

static func integer(v: Variant, low: int, high: int) -> bool:
	return number(v) and float(v)==floor(float(v)) and float(v)>=low and float(v)<=high
