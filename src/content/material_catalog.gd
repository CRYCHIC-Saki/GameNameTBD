class_name TDMaterialCatalog
extends RefCounted
## One runtime material registry. Culture provenance is not procurement geography.
const PATH := "res://content/culinary_materials.json"
const REGIONS := ["chengdu","paris","tokyo","bangkok","mexico_city"]
const CUISINES := ["cn","eu","jp","sea","lat"]
static var _cache: Dictionary={}
static func _raw() -> Dictionary:
	if _cache.is_empty():
		var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary: _cache=parsed
	return _cache
static func data() -> Dictionary: return _raw().duplicate(true)
static func item(id: String) -> Dictionary: return _raw().get("items",{}).get(id,{}).duplicate(true)
static func definition(id: String) -> Dictionary: return item(id).get("definition",{}).duplicate(true)
static func name_for(id: String) -> String: return str(_raw().get("items",{}).get(id,{}).get("definition",{}).get("name",id))
static func added(id: String) -> bool: return _raw().get("items",{}).has(id) and id not in _raw().get("legacy_ids",[])
static func supplies(town: String,id: String) -> bool: return town in _raw().get("items",{}).get(id,{}).get("supply_regions",[])
static func condiment_unlocked(id: String,cuisines: Array) -> bool:
	# Cuisine usage is independent of where suppliers produce the material.
	for cuisine: String in _raw().get("items",{}).get(id,{}).get("unlock_cuisines",[]):
		if cuisine in cuisines: return true
	return false
static func cuisine_text(id: String) -> String:
	var names: Array[String]=[]
	var labels: Dictionary={"cn":"中式","eu":"欧陆","jp":"日本","sea":"东南亚","lat":"拉美"}
	for cuisine: String in _raw().get("items",{}).get(id,{}).get("unlock_cuisines",[]): names.append(labels.get(cuisine,cuisine))
	return " / ".join(names)
static func regions_text(id: String) -> String:
	var names: Array[String]=[]
	var labels: Dictionary={"chengdu":"中式镇","paris":"欧陆镇","tokyo":"日本镇","bangkok":"东南亚镇","mexico_city":"拉美镇"}
	for region: String in _raw().get("items",{}).get(id,{}).get("supply_regions",[]): names.append(labels.get(region,region))
	return "五镇共有" if names.size()==5 else " / ".join(names)
static func recipes() -> Array: return _raw().get("recipes",[]).duplicate(true)
static func needed_by_unlocked(id: String,unlocked: Array) -> bool:
	for recipe: Dictionary in _raw().get("recipes",[]):
		if recipe.id in unlocked and id in recipe.ingredients+recipe.seasonings: return true
	return false
static func palette(cuisine: String, required: Array=[]) -> Array[String]:
	var result: Array[String]=[]
	for raw_id: Variant in required:
		var id: String=str(raw_id).trim_prefix("spice:")
		if _raw().items.has(id) and bool(_raw().items[id].stock.condiment) and id not in result: result.append(id)
	for id: String in _raw().palettes.get(cuisine,_raw().palettes.cn):
		if id not in result and result.size()<10: result.append(id)
	return result
static func preference_spice(cuisine: String,taste: int,legacy: String) -> String:
	if cuisine=="cn": return legacy
	var choices:=palette(cuisine)
	var selected: String="";var strength: float=0
	for id: String in choices:
		var tastes: Array=_raw().items[id].definition.base_tastes
		if taste>=0 and taste<tastes.size() and float(tastes[taste])>strength:
			strength=float(tastes[taste]);selected=id
	return selected

static func validate(raw: Variant) -> TDOutcome:
	if not raw is Dictionary or raw.get("schema_version")!=1 or raw.get("revision")!=1: return TDOutcome.new(false,"MATERIAL_VERSION")
	if not raw.get("items") is Dictionary or not raw.get("recipes") is Array or not raw.get("palettes") is Dictionary or not raw.get("legacy_ids") is Array: return TDOutcome.new(false,"MATERIAL_FIELDS")
	for id: Variant in raw.items:
		var row: Variant=raw.items[id]
		if not id is String or not row is Dictionary or not row.get("definition") is Dictionary or row.definition.get("id")!=id or not row.definition.get("name") is String or not row.get("culture_tags") is Array or not row.get("source_id") is String: return TDOutcome.new(false,"MATERIAL_ID")
		if not row.get("supply_regions") is Array or row.supply_regions.is_empty(): return TDOutcome.new(false,"MATERIAL_REGIONS")
		var seen: Array=[]
		for region: Variant in row.supply_regions:
			if region not in REGIONS or region in seen: return TDOutcome.new(false,"MATERIAL_REGIONS")
			seen.append(region)
		if not TDServiceCatalog.integer(row.get("cost_cents"),1,1000000) or not row.get("stock") is Dictionary: return TDOutcome.new(false,"MATERIAL_COST")
		var stock: Dictionary=row.stock
		if stock.get("group") not in ["vegetable","fruit","meat","seasoning"] or not stock.get("condiment") is bool or not TDServiceCatalog.integer(stock.get("shelf_days"),1,1000) or stock.get("pack_units")!=1000 or stock.get("unit") not in ["份","袋","瓶"]: return TDOutcome.new(false,"MATERIAL_STOCK")
		if stock.condiment:
			if not row.get("unlock_cuisines") is Array or row.unlock_cuisines.is_empty(): return TDOutcome.new(false,"MATERIAL_CUISINES")
			var cuisines: Array=[]
			for cuisine: Variant in row.unlock_cuisines:
				if cuisine not in CUISINES or cuisine in cuisines: return TDOutcome.new(false,"MATERIAL_CUISINES")
				cuisines.append(cuisine)
		if not row.get("icon") is Dictionary or row.icon.get("shape") not in ["bottle","grain","fish","meat","leaf"] or not row.icon.get("color") is String or not Color.html_is_valid(row.icon.color): return TDOutcome.new(false,"MATERIAL_ICON")
	var ids: Array=[]
	for recipe: Variant in raw.recipes:
		if not recipe is Dictionary or not recipe.get("id") is String or recipe.id in ids or recipe.get("cuisine_id") not in CUISINES or not recipe.get("ingredients") is Array or recipe.ingredients.is_empty() or not recipe.get("seasonings") is Array: return TDOutcome.new(false,"MATERIAL_RECIPE")
		ids.append(recipe.id)
		for id: Variant in recipe.ingredients+recipe.seasonings:
			if not id is String or not raw.items.has(id): return TDOutcome.new(false,"MATERIAL_RECIPE_REFERENCE")
			if raw.items[id].stock.condiment and recipe.cuisine_id not in raw.items[id].unlock_cuisines: return TDOutcome.new(false,"MATERIAL_CUISINE_REFERENCE")
		for id: String in recipe.seasonings:
			if not raw.items[id].stock.condiment: return TDOutcome.new(false,"MATERIAL_SEASONING")
	for cuisine: String in CUISINES:
		if not raw.palettes.get(cuisine) is Array or raw.palettes[cuisine].is_empty() or raw.palettes[cuisine].size()>10: return TDOutcome.new(false,"MATERIAL_PALETTE")
		var seen: Array=[]
		for id: Variant in raw.palettes[cuisine]:
			if not id is String or id in seen or not raw.items.has(id) or not raw.items[id].stock.condiment: return TDOutcome.new(false,"MATERIAL_PALETTE")
			if cuisine not in raw.items[id].unlock_cuisines: return TDOutcome.new(false,"MATERIAL_CUISINE_REFERENCE")
			seen.append(id)
	for id: Variant in raw.legacy_ids:
		if not raw.items.has(id): return TDOutcome.new(false,"MATERIAL_LEGACY_REFERENCE")
	return TDOutcome.new(true,"VALID")
static func install(service: TDServiceCatalog) -> TDOutcome:
	var raw:=_raw();var checked:=validate(raw)
	if not checked.ok: return checked
	var cooking:=service.cooking.data();var known: Dictionary={}
	for row: Dictionary in cooking.ingredients: known[row.id]=true
	service.config.material_cost_ids=[]
	for id: String in raw.items:
		var row: Dictionary=raw.items[id]
		if not known.has(id): cooking.ingredients.append(row.definition.duplicate(true));cooking.active.ingredients.append(id)
		elif added(id):
			for i: int in cooking.ingredients.size():
				if cooking.ingredients[i].id==id: cooking.ingredients[i]=row.definition.duplicate(true)
		if not service.config.costs.has(id): service.config.costs[id]=int(row.cost_cents)
		if added(id): service.config.material_cost_ids.append(id)
		if bool(row.stock.condiment) and row.definition.category=="seasoning":
			var action: String="spice:"+id
			if action not in cooking.pc_operations.modules.season.allowed_actions: cooking.pc_operations.modules.season.allowed_actions.append(action)
	return service.cooking.load_data(cooking,"D069 explicit material expansion")
