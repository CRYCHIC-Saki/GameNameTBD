class_name TDResearchRuntime
extends RefCounted
const PATH: String="res://content/research/runtime_recipes.json"
const CUISINE_PATH: String="res://content/cuisine_recipes.json"
static var _expanded: Dictionary={}
static var _default_service: TDServiceCatalog

static func load_default(service: TDServiceCatalog) -> TDOutcome:
	# Packaged content is fixed for this run. Validate it once, then give each
	# caller a fresh copy so legacy recipes and request caches stay local.
	if _default_service == null:
		var template := TDServiceCatalog.new()
		var result := template.load_file()
		if not result.ok:
			return result
		result = install(template)
		if not result.ok:
			return result
		_default_service = template
	service.copy_content_from(_default_service)
	return TDOutcome.new(true, "LOADED")

static func expanded() -> Dictionary:
	return _source_content().duplicate(true)

static func _source_content() -> Dictionary:
	if _expanded.is_empty():
		var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string(CUISINE_PATH))
		if raw is Dictionary: _expanded=raw
	return _expanded

static func data() -> Dictionary:
	var raw:Variant=JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return raw if raw is Dictionary else {}

static func dishes() -> Array:
	var result:Array=[]
	for item:Dictionary in _source_content().get("dishes",[]): result.append(item.world.duplicate(true))
	return result

static func install(service:TDServiceCatalog) -> TDOutcome:
	if service.config.get("cuisine_revision",0)==1: return TDOutcome.new(true,"INSTALLED")
	var raw:=data()
	if raw.get("schema_version")!=1 or not raw.get("ingredients") is Array or not raw.get("dishes") is Array: return TDOutcome.new(false,"INVALID_RUNTIME")
	var cooking:Dictionary=service.cooking.data();var config:Dictionary=service.config.duplicate(true)
	config.research_cost_ids=[]
	for item:Dictionary in raw.ingredients:
		var definition:Dictionary=item.definition
		if not TDServiceCatalog.integer(item.get("cost_cents_per_unit"),1,1000000): return TDOutcome.new(false,"INVALID_COST")
		if definition.id not in cooking.active.ingredients:
			cooking.ingredients.append(definition.duplicate(true));cooking.active.ingredients.append(definition.id)
		config.ingredients.append(definition.duplicate(true));config.costs[definition.id]=item.cost_cents_per_unit;config.research_cost_ids.append(definition.id)
	var extension:=expanded()
	if extension.get("schema_version")!=1 or not extension.get("dishes") is Array or not extension.get("sheets") is Dictionary: return TDOutcome.new(false,"INVALID_CUISINE_CONTENT")
	config.legacy_cooking={}
	for recipe: Dictionary in cooking.recipes:
		if recipe.has("guided_profile") and cooking.pc_operations.document_sheets.has(recipe.guided_profile):
			config.legacy_cooking[recipe.id]={"recipe":recipe.duplicate(true),"sheet":cooking.pc_operations.document_sheets[recipe.guided_profile].duplicate(true)}
	for item: Dictionary in raw.dishes: config.legacy_cooking[item.recipe.id]={"recipe":item.recipe.duplicate(true),"sheet":item.sheet.duplicate(true)}
	var seen: Dictionary={}
	for item:Dictionary in extension.dishes:
		if seen.has(item.recipe.id) or item.recipe.id!=item.world.service_recipe or item.offer.id!=item.recipe.id: return TDOutcome.new(false,"INVALID_RUNTIME_REFERENCE")
		seen[item.recipe.id]=true
		for id:Variant in item.offer.stock:
			if not config.costs.has(id) or not TDServiceCatalog.integer(item.offer.stock[id],1,100000): return TDOutcome.new(false,"INVALID_STOCK")
		cooking.recipes=cooking.recipes.filter(func(r:Dictionary)->bool:return r.id!=item.recipe.id)
		config.recipes=config.recipes.filter(func(r:Dictionary)->bool:return r.id!=item.recipe.id)
		config.offers=config.offers.filter(func(r:Dictionary)->bool:return r.id!=item.recipe.id)
		cooking.recipes.append(item.recipe.duplicate(true))
		if item.recipe.id not in cooking.active.recipes: cooking.active.recipes.append(item.recipe.id)
		config.recipes.append(item.recipe.duplicate(true));config.offers.append(item.offer.duplicate(true))
	cooking.pc_operations.document_sheets.merge(extension.sheets,true)
	config.cuisine_revision=1
	var checked:=TDCookingCatalog.new();var result:=checked.load_data(cooking,"D030 explicit runtime additions")
	if not result.ok: return result
	service.cooking=checked;service.config=config
	return TDOutcome.new(true,"INSTALLED")
