class_name TDResearchRuntime
extends RefCounted
const PATH: String="res://content/research/runtime_recipes.json"

static func data() -> Dictionary:
	var raw:Variant=JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return raw if raw is Dictionary else {}

static func dishes() -> Array:
	var result:Array=[]
	for item:Dictionary in data().get("dishes",[]): result.append(item.world.duplicate(true))
	return result

static func install(service:TDServiceCatalog) -> TDOutcome:
	if not service.cooking.for_recipe("study.egg_fried_rice").is_empty(): return TDOutcome.new(true,"INSTALLED")
	var raw:=data()
	if raw.get("schema_version")!=1 or not raw.get("ingredients") is Array or not raw.get("dishes") is Array: return TDOutcome.new(false,"INVALID_RUNTIME")
	var cooking:Dictionary=service.cooking.data();var config:Dictionary=service.config.duplicate(true)
	config.research_cost_ids=[]
	for item:Dictionary in raw.ingredients:
		var definition:Dictionary=item.definition
		if not TDServiceCatalog.integer(item.get("cost_cents_per_unit"),1,1000000): return TDOutcome.new(false,"INVALID_COST")
		cooking.ingredients.append(definition.duplicate(true));cooking.active.ingredients.append(definition.id)
		config.ingredients.append(definition.duplicate(true));config.costs[definition.id]=item.cost_cents_per_unit;config.research_cost_ids.append(definition.id)
	for item:Dictionary in raw.dishes:
		if not item.recipe.id.begins_with("study.") or item.recipe.id!=item.world.service_recipe or item.sheet.id!=item.recipe.id or item.offer.id!=item.recipe.id: return TDOutcome.new(false,"INVALID_RUNTIME_REFERENCE")
		for id:Variant in item.offer.stock:
			if not config.costs.has(id) or not TDServiceCatalog.integer(item.offer.stock[id],1,100000): return TDOutcome.new(false,"INVALID_STOCK")
		cooking.recipes.append(item.recipe.duplicate(true));cooking.active.recipes.append(item.recipe.id);cooking.pc_operations.document_sheets[item.sheet.id]=item.sheet.duplicate(true)
		config.recipes.append(item.recipe.duplicate(true));config.offers.append(item.offer.duplicate(true))
	var checked:=TDCookingCatalog.new();var result:=checked.load_data(cooking,"D030 explicit runtime additions")
	if not result.ok: return result
	service.cooking=checked;service.config=config
	return TDOutcome.new(true,"INSTALLED")
