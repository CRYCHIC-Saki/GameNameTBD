class_name TDServiceCatalog
extends RefCounted

var cooking := TDCookingCatalog.new()
var config: Dictionary = {}

func load_file(path: String = "res://content/service_content.json") -> TDOutcome:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return load_data(parsed)

func load_data(raw: Variant) -> TDOutcome:
	config = {}
	if not raw is Dictionary or raw.get("schema_version") != 1 or raw.get("scope") != "SINGLE_STORE" or raw.get("parameter_status") != "PROPOSED": return TDOutcome.new(false,"INVALID_SERVICE_CONTENT")
	for field: String in ["ingredient_overrides","ingredients","recipes","offers"]:
		if not raw.get(field) is Array: return TDOutcome.new(false,"INVALID_SERVICE_CONTENT",field)
	for field: String in ["sheets","costs","settings"]:
		if not raw.get(field) is Dictionary: return TDOutcome.new(false,"INVALID_SERVICE_CONTENT",field)
	if raw.get("base") != "res://content/cooking_system.json": return TDOutcome.new(false,"INVALID_BASE")
	var base := TDCookingCatalog.new()
	var loaded := base.load_file(raw.base)
	if not loaded.ok: return loaded
	var data: Dictionary = base.data()
	for replacement: Variant in raw.ingredient_overrides:
		if not replacement is Dictionary or replacement.get("scope") != "PROTOTYPE": return TDOutcome.new(false,"INVALID_OVERRIDE")
		var found: bool = false
		for i: int in data.ingredients.size():
			if data.ingredients[i].id == replacement.get("id"): data.ingredients[i] = replacement.duplicate(true); found = true
		if not found: return TDOutcome.new(false,"MISSING_REFERENCE")
	for item: Variant in raw.ingredients:
		if not item is Dictionary: return TDOutcome.new(false,"INVALID_INGREDIENT")
		data.ingredients.append(item.duplicate(true)); data.active.ingredients.append(item.get("id",""))
	for recipe: Variant in raw.recipes:
		if not recipe is Dictionary: return TDOutcome.new(false,"INVALID_RECIPE")
		data.recipes.append(recipe.duplicate(true)); data.active.recipes.append(recipe.get("id",""))
	data.pc_operations.document_sheets.merge(raw.sheets.duplicate(true))
	var checked := cooking.load_data(data,"service_content explicit merge")
	if not checked.ok: return checked
	var names: Dictionary = {}
	for item: Dictionary in data.ingredients: names[item.id] = item
	for id: Variant in raw.costs:
		if not id is String or not names.has(id) or not integer(raw.costs[id],1,1000000) or names[id].scope == "TEST_ONLY": return TDOutcome.new(false,"INVALID_COST")
	var seen: Dictionary = {}
	if raw.offers.size() < 5 or raw.offers.size() > 8: return TDOutcome.new(false,"INVALID_MENU_COUNT")
	for offer: Variant in raw.offers:
		if not offer is Dictionary or not offer.get("id") is String or seen.has(offer.id): return TDOutcome.new(false,"INVALID_OFFER")
		seen[offer.id] = true
		var recipe: Dictionary = cooking.for_recipe(offer.id).get("recipe",{})
		if recipe.is_empty() or recipe.scope == "TEST_ONLY" or not offer.get("source") is String or offer.source.is_empty() or not integer(offer.get("reference_cents"),1,1000000): return TDOutcome.new(false,"INVALID_OFFER")
		if not offer.get("stock") is Dictionary or offer.stock.is_empty() or not offer.get("primary") is Array or offer.primary.is_empty(): return TDOutcome.new(false,"INVALID_STOCK")
		for id: Variant in offer.stock:
			if not raw.costs.has(id) or not integer(offer.stock[id],1,100000): return TDOutcome.new(false,"INVALID_STOCK")
		for id: Variant in offer.primary:
			if not offer.stock.has(id) or offer.stock[id] != 1000: return TDOutcome.new(false,"INVALID_PRIMARY")
		if not data.pc_operations.document_sheets.has(recipe.get("guided_profile","")): return TDOutcome.new(false,"MISSING_CHART")
	for key: String in ["initial_cents","day_sec","arrival_sec","patience_sec","max_orders","grant_cents","initial_popularity","refund_below"]:
		if not integer(raw.settings.get(key),1,1000000): return TDOutcome.new(false,"INVALID_SETTINGS",key)
	if raw.settings.max_orders > 8 or raw.settings.initial_popularity > 100 or raw.settings.refund_below > 100: return TDOutcome.new(false,"INVALID_SETTINGS")
	config = raw.duplicate(true)
	return TDOutcome.new(true,"LOADED")

static func integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and value >= low and value <= high

func offer(id: String) -> Dictionary:
	for item: Dictionary in config.get("offers",[]):
		if item.id == id: return item.duplicate(true)
	return {}

func compile_plan(entry: Dictionary) -> TDOutcome:
	var plan: Dictionary = entry.plan
	var checked := TDRecipeLibrary.new("",cooking.data()).validate_plan(plan)
	if not checked.ok: return checked
	var original: Dictionary = offer(plan.recipe_id)
	if original.is_empty(): return TDOutcome.new(false,"UNKNOWN_RECIPE")
	var amounts: Dictionary = {}
	for item: Dictionary in plan.ingredients: amounts[item.ingredient_id]=float(amounts.get(item.ingredient_id,0))+float(item.amount)
	for id: String in original.primary:
		if not is_equal_approx(float(amounts.get(id,0)),1.0): return TDOutcome.new(false,"PLAN_PRIMARY_AMOUNT","首版自建方案保留每种主料一份。")
	for id: String in amounts:
		if not original.stock.has(id) or roundi(float(amounts[id])*1000)>int(original.stock[id]): return TDOutcome.new(false,"PLAN_STOCK_LIMIT")
	var data: Dictionary = cooking.data()
	var recipe: Dictionary = cooking.for_recipe(plan.recipe_id).recipe
	var chart: Dictionary = data.pc_operations.document_sheets[recipe.guided_profile].duplicate(true)
	chart.id=entry.id; chart.dish=entry.name
	var made: Dictionary = {}; var cuts: Dictionary = {}; var precise: Array=[]; var counts: Dictionary={}
	var last_rank: int=-1
	for step: Dictionary in plan.operations:
		var rank: int=int({"add":0,"cut":0,"preheat":1,"season":2,"stir":3,"heat":4,"starch":6,"plate":7}.get(step.operation,-1))
		if step.operation=="season" and step.parameters.has("sequence"): rank=5
		if rank<last_rank: return TDOutcome.new(false,"PLAN_ORDER_UNSUPPORTED","首版只支持按当前菜谱流程完成的方案。")
		last_rank=rank
		if step.parameters.has("batch_id") and step.parameters.batch_id!="main": return TDOutcome.new(false,"PLAN_STRUCTURE_UNSUPPORTED")
		if step.operation=="season" and not step.parameters.has("sequence") and step.parameters.ingredient_id!="oil": return TDOutcome.new(false,"PLAN_STRUCTURE_UNSUPPORTED")
		if step.operation=="starch" and step.parameters.ingredient_id!="starch": return TDOutcome.new(false,"PLAN_STRUCTURE_UNSUPPORTED")
		made[step.operation]=true
		counts[step.operation]=int(counts.get(step.operation,0))+1
		if step.operation=="cut": cuts[step.parameters.ingredient_id]=step.parameters.shape
		if step.operation=="season" and step.parameters.has("sequence"): precise=step.parameters.sequence.duplicate()
		if step.operation in ["season","starch"] and not is_equal_approx(float(step.parameters.get("amount",.1)),.1): return TDOutcome.new(false,"PLAN_AMOUNT_UNSUPPORTED")
	var expected: Dictionary={"add":original.primary.size(),"cut":recipe.preparation_sheets.size()}
	for group: Dictionary in chart.groups.values(): expected[group.operation]=int(expected.get(group.operation,0))+1
	for operation: String in counts:
		if int(counts[operation])!=int(expected.get(operation,0)): return TDOutcome.new(false,"PLAN_STRUCTURE_UNSUPPORTED")
	for operation: String in expected:
		if int(expected[operation])!=int(counts.get(operation,0)): return TDOutcome.new(false,"INCOMPLETE_PLAN")
	for group: Dictionary in chart.groups.values():
		if not made.has(group.operation): return TDOutcome.new(false,"INCOMPLETE_PLAN","完成全部工序后才能保存营业方案。")
	if precise.is_empty() or precise.size()>3: return TDOutcome.new(false,"INCOMPLETE_PLAN","至少实际加入一份调料后保存方案。")
	var note: int=0
	for row: Dictionary in chart.beats:
		var mouse: Dictionary=row.lanes.get("mouse",{})
		if mouse.get("group")=="season":
			if note<precise.size(): mouse.input="spice:"+str(precise[note])
			else: row.lanes.erase("mouse"); row.rest=row.lanes.is_empty()
			note+=1
	chart.groups.season.parameters.ingredient_id=precise[0]
	var preparations: Dictionary={}; var additions: Dictionary={entry.id:chart}
	for ingredient: String in recipe.get("preparation_sheets",{}):
		var shape: String=str(cuts.get(ingredient,"whole"))
		if shape=="whole": return TDOutcome.new(false,"INCOMPLETE_PLAN","先完成有效备菜再保存方案。")
		preparations[ingredient]={"slice":"service.slice","strip":"service.strips","chunk":"prepare","dice":"service.dice"}[shape]
	recipe.id=entry.id; recipe.name=entry.name; recipe.version=int(entry.version); recipe.is_custom=true
	recipe.guided_profile=entry.id; recipe.preparation_sheets=preparations
	return TDOutcome.new(true,"COMPILED","",{"recipe":recipe,"sheets":additions})

func with_plans(entries: Array) -> TDOutcome:
	var data: Dictionary=cooking.data()
	for entry: Dictionary in entries:
		var compiled:=compile_plan(entry)
		if not compiled.ok: return compiled
		data.recipes.append(compiled.data.recipe); data.active.recipes.append(entry.id)
		data.pc_operations.document_sheets.merge(compiled.data.sheets)
	return TDOutcome.new(true,"COMPOSED","",data)
