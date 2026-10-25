class_name TDServiceCatalog
extends RefCounted

var cooking := TDCookingCatalog.new()
var config: Dictionary = {}
var _profiles: Dictionary = {}
var _needs: Dictionary = {}

func load_file(path: String = "res://content/service_content.json") -> TDOutcome:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return load_data(parsed)

func load_data(raw: Variant) -> TDOutcome:
	config = {}
	_profiles.clear()
	_needs.clear()
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
	if raw.has("playability"):
		var tuning: Variant=raw.playability
		if not tuning is Dictionary or not _number(tuning.get("deviation_grace"),0,20) or not _number(tuning.get("deviation_factor"),.25,1) or not tuning.get("harmony_scores") is Array or tuning.harmony_scores.size()!=5: return TDOutcome.new(false,"INVALID_PLAYABILITY")
		for i: int in 5:
			if not _number(tuning.harmony_scores[i],0,100): return TDOutcome.new(false,"INVALID_PLAYABILITY")
			data.rules.harmony_levels[i].score=tuning.harmony_scores[i]
		data.scoring_rules["deviation_grace"]=tuning.deviation_grace;data.scoring_rules["deviation_factor"]=tuning.deviation_factor
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
		if recipe.get("cooking_method","stir") not in ["stir","steam"] or not recipe.get("failed_dish",false) is bool or not recipe.get("initially_unlocked",true) is bool: return TDOutcome.new(false,"INVALID_RECIPE")
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
		if recipe.is_empty() or recipe.scope == "TEST_ONLY" or recipe.get("failed_dish",false) or not offer.get("source") is String or offer.source.is_empty() or not integer(offer.get("reference_cents"),1,1000000): return TDOutcome.new(false,"INVALID_OFFER")
		if not offer.get("stock") is Dictionary or offer.stock.is_empty() or not offer.get("primary") is Array or offer.primary.is_empty(): return TDOutcome.new(false,"INVALID_STOCK")
		for id: Variant in offer.stock:
			if not raw.costs.has(id) or not integer(offer.stock[id],1,100000): return TDOutcome.new(false,"INVALID_STOCK")
		for id: Variant in offer.primary:
			if not offer.stock.has(id) or offer.stock[id] != 1000: return TDOutcome.new(false,"INVALID_PRIMARY")
		if not data.pc_operations.document_sheets.has(recipe.get("guided_profile","")): return TDOutcome.new(false,"MISSING_CHART")
	for key: String in ["initial_cents","day_sec","arrival_sec","patience_sec","max_orders","grant_cents","initial_popularity","refund_below"]:
		if not integer(raw.settings.get(key),1,1000000): return TDOutcome.new(false,"INVALID_SETTINGS",key)
	if raw.settings.max_orders > 8 or raw.settings.initial_popularity > 100 or raw.settings.refund_below > 100: return TDOutcome.new(false,"INVALID_SETTINGS")
	if not integer(raw.settings.get("forecast_uncertainty_percent",20),0,50): return TDOutcome.new(false,"INVALID_SETTINGS","forecast_uncertainty_percent")
	if not integer(raw.settings.get("stock_rejection_popularity",1),0,10): return TDOutcome.new(false,"INVALID_SETTINGS","stock_rejection_popularity")
	if not integer(raw.settings.get("failed_dish_popularity",4),0,20): return TDOutcome.new(false,"INVALID_SETTINGS","failed_dish_popularity")
	if not raw.get("preparation_choices") is Dictionary: return TDOutcome.new(false,"INVALID_PREPARATION_CHOICES")
	for shape: Variant in raw.preparation_choices:
		if shape not in ["chunk","slice","strip","dice"] or not data.pc_operations.document_sheets.has(raw.preparation_choices[shape]): return TDOutcome.new(false,"INVALID_PREPARATION_CHOICES")
	if raw.has("request_rules"):
		var rules: Variant=raw.request_rules
		if not rules is Dictionary or rules.get("status")!="PROPOSED" or not rules.get("flavor_targets") is Array or not rules.get("small_cut_actions") is Array: return TDOutcome.new(false,"INVALID_REQUEST_RULES")
		if not _number(rules.get("fine_threshold"),0,1) or not _number(rules.get("small_cut_interval_beats"),.5,4) or rules.small_cut_actions.size()>12 or rules.small_cut_actions.size()<3: return TDOutcome.new(false,"INVALID_REQUEST_RULES")
		for action: Variant in rules.small_cut_actions:
			if action not in ["primary","rotate_left","rotate_right"]: return TDOutcome.new(false,"INVALID_REQUEST_RULES")
		var tastes: Dictionary={}
		for target: Variant in rules.flavor_targets:
			if not target is Dictionary or not integer(target.get("taste"),0,6) or tastes.has(int(target.taste)) or not raw.costs.has(target.get("ingredient_id")) or names[target.ingredient_id].category!="seasoning" or not _number(target.get("amount"),.01,.4): return TDOutcome.new(false,"INVALID_REQUEST_RULES")
			tastes[int(target.taste)]=true
	config = raw.duplicate(true)
	var stock: Dictionary=TDFoodStock.load_rules()
	for id: String in config.costs:
		if not stock.has(id): return TDOutcome.new(false,"MISSING_STOCK_DEFINITION",id)
	return TDOutcome.new(true,"LOADED")

static func integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and value >= low and value <= high

static func _number(value: Variant, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value>=low and value<=high

func request_profile(family: String, customer: Dictionary, entry: Dictionary = {}) -> TDCookingCatalog:
	var key: String=JSON.stringify([family,customer,entry])
	if _profiles.has(key): return _profiles[key]
	var data: Dictionary=cooking.data()
	var recipe: Dictionary=cooking.for_recipe(family).get("recipe",{})
	if recipe.is_empty(): return null
	var source_chart: Dictionary=data.pc_operations.document_sheets[recipe.guided_profile].duplicate(true)
	if not entry.is_empty():
		var compiled:=compile_plan(entry)
		if not compiled.ok: return null
		source_chart=compiled.data.sheets[entry.id].duplicate(true)
		recipe.preparation_sheets=compiled.data.recipe.preparation_sheets.duplicate(true)
	var rules: Dictionary=config.get("request_rules",{})
	var targets: Dictionary={}
	for requirement: Dictionary in ([] if rules.is_empty() else customer.get("requirements",[])):
		if float(requirement.get("weight",0))<=0: continue
		if requirement.get("kind")=="fine" and float(requirement.get("min",0))>=float(rules.get("fine_threshold",.6)):
			var ingredient: String=str(requirement.get("ingredient_id",""))
			if recipe.preparation_sheets.has(ingredient):
				var cut: Dictionary=data.pc_operations.document_sheets.prepare.duplicate(true)
				cut.id="request.small"; cut.dish="按要求切小丁"
				cut.groups.cut.label="番茄切小丁 · 按谱密集落刀与转向"
				cut.beats=cut.beats.filter(func(row:Dictionary)->bool:return float(row.t)<5)
				var actions: Array=rules.get("small_cut_actions",[])
				for i: int in actions.size(): cut.beats.append({"t":5+i*float(rules.small_cut_interval_beats),"lanes":{"hand":{"group":"cut","op":"cut","input":actions[i],"form":"tap"}}})
				cut.beats.append({"t":6+actions.size()*float(rules.small_cut_interval_beats),"rest":true,"lanes":{}})
				data.pc_operations.document_sheets[cut.id]=cut; recipe.preparation_sheets[ingredient]=cut.id
		if requirement.get("kind")=="flavor":
			for target: Dictionary in rules.get("flavor_targets",[]):
				if int(requirement.get("taste",-1))==int(target.taste): targets[target.ingredient_id]=float(target.amount)
	var chart: Dictionary=source_chart.duplicate(true)
	chart.id="request.cook"; recipe.guided_profile=chart.id
	var notes: Array=[]
	for row: Dictionary in chart.beats:
		var mouse: Dictionary=row.lanes.get("mouse",{})
		if mouse.get("group")=="season": notes.append(mouse)
	var claimed: Array=[]
	for ingredient: String in targets:
		var chosen: int=-1
		for i: int in notes.size():
			if notes[i].input=="spice:"+ingredient: chosen=i; break
		if chosen<0:
			for i: int in range(notes.size()-1,-1,-1):
				if i not in claimed: chosen=i; break
		if chosen>=0:
			claimed.append(chosen); notes[chosen].input="spice:"+ingredient; notes[chosen].form="hold"
			notes[chosen].hold_beats=float(targets[ingredient])/float(chart.groups.season.get("pour_rate_per_sec",.2))/(60.0/float(chart.bpm))
	var shift: float=0
	for row: Dictionary in chart.beats:
		row.t=float(row.t)+shift
		var mouse: Dictionary=row.lanes.get("mouse",{})
		if mouse.get("group")=="season": shift+=ceil(maxf(0,float(mouse.get("hold_beats",1))*1.5+.2/(60.0/float(chart.bpm))-2))
	data.pc_operations.document_sheets[chart.id]=chart
	for i: int in data.recipes.size():
		if data.recipes[i].id==family: data.recipes[i]=recipe
	var result:=TDCookingCatalog.new()
	if not result.load_data(data,"customer request chart").ok: return null
	_profiles[key]=result
	return result

func material_needs(profile: TDCookingCatalog, family: String, completed: Array = []) -> Dictionary:
	var key: String=family+":"+str(profile.get_instance_id())+JSON.stringify(completed.map(func(s:Dictionary)->Array:return [s.operation,s.parameters.get("mode","")]))
	if _needs.has(key): return _needs[key].duplicate(true)
	var needed: Dictionary={}
	for id: String in offer(family).get("primary",[]): needed[id]=1000
	var recipe: Dictionary=profile.for_recipe(family).recipe
	var chart: Dictionary=profile.data().pc_operations.document_sheets[recipe.guided_profile]
	var used_modules: Dictionary={}
	for step: Dictionary in completed:
		var tag: String=str(step.operation)+":"+str(step.parameters.get("mode",""))
		used_modules[tag]=int(used_modules.get(tag,0))+1
	for group_id: String in chart.groups:
		var group: Dictionary=chart.groups[group_id]
		if group.operation not in ["season","starch"]: continue
		var tag: String=str(group.operation)+":"+str(group.parameters.get("mode",""))
		if int(used_modules.get(tag,0))>0: used_modules[tag]-=1; continue
		if group.operation=="season" and group.parameters.get("mode")=="precise":
			for row: Dictionary in chart.beats:
				var note: Dictionary=row.lanes.get("mouse",{})
				if note.get("group")!=group_id: continue
				var id: String=str(note.input).trim_prefix("spice:")
				var units: int=roundi(float(note.get("hold_beats",1))*(60.0/float(chart.bpm))*float(group.get("pour_rate_per_sec",.2))*1000)
				needed[id]=int(needed.get(id,0))+units
		elif group.parameters.has("ingredient_id"):
			var id: String=str(group.parameters.ingredient_id)
			needed[id]=int(needed.get(id,0))+roundi(float(group.parameters.get("amount",.1))*1000)
	_needs[key]=needed.duplicate(true)
	return needed

func offer(id: String) -> Dictionary:
	for item: Dictionary in config.get("offers",[]):
		if item.id == id: return item.duplicate(true)
	return {}

func is_primary(id: String) -> bool:
	return config.offers.any(func(item:Dictionary)->bool:return id in item.primary)

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
	var steam: bool=recipe.get("cooking_method","stir")=="steam"
	var chart: Dictionary = data.pc_operations.document_sheets[recipe.guided_profile].duplicate(true)
	chart.id=entry.id; chart.dish=entry.name
	var made: Dictionary = {}; var cuts: Dictionary = {}; var precise: Array=[]; var precise_amounts: Array=[]; var counts: Dictionary={}
	var last_rank: int=-1
	for step: Dictionary in plan.operations:
		var rank: int=int({"add":0,"cut":0,"preheat":1,"season":2,"stir":3,"heat":4,"starch":6,"plate":7}.get(step.operation,-1))
		if step.operation=="season" and step.parameters.has("sequence"): rank=5
		if steam: rank=int({"add":0,"cut":0,"season":1,"steam":2,"plate":3}.get(step.operation,-1))
		if rank<last_rank: return TDOutcome.new(false,"PLAN_ORDER_UNSUPPORTED","首版只支持按当前菜谱流程完成的方案。")
		last_rank=rank
		if step.parameters.has("batch_id") and step.parameters.batch_id!="main": return TDOutcome.new(false,"PLAN_STRUCTURE_UNSUPPORTED")
		if step.operation=="season" and not step.parameters.has("sequence") and step.parameters.ingredient_id!="oil": return TDOutcome.new(false,"PLAN_STRUCTURE_UNSUPPORTED")
		if step.operation=="starch" and step.parameters.ingredient_id!="starch": return TDOutcome.new(false,"PLAN_STRUCTURE_UNSUPPORTED")
		made[step.operation]=true
		counts[step.operation]=int(counts.get(step.operation,0))+1
		if step.operation=="cut": cuts[step.parameters.ingredient_id]=step.parameters.shape
		if step.operation=="season" and step.parameters.has("sequence"):
			precise=step.parameters.sequence.duplicate(); precise_amounts=step.parameters.get("amounts",[]).duplicate()
		if step.operation in ["season","starch"] and not is_equal_approx(float(step.parameters.get("amount",.1)),.1): return TDOutcome.new(false,"PLAN_AMOUNT_UNSUPPORTED")
	var expected: Dictionary={"add":original.primary.size(),"cut":recipe.preparation_sheets.size()}
	if steam: expected.cut=cuts.size()
	for group: Dictionary in chart.groups.values(): expected[group.operation]=int(expected.get(group.operation,0))+1
	for operation: String in counts:
		if int(counts[operation])!=int(expected.get(operation,0)): return TDOutcome.new(false,"PLAN_STRUCTURE_UNSUPPORTED")
	for operation: String in expected:
		if int(expected[operation])!=int(counts.get(operation,0)): return TDOutcome.new(false,"INCOMPLETE_PLAN")
	for group: Dictionary in chart.groups.values():
		if not made.has(group.operation): return TDOutcome.new(false,"INCOMPLETE_PLAN","完成全部工序后才能保存营业方案。")
	if precise.is_empty() or precise.size()>3: return TDOutcome.new(false,"INCOMPLETE_PLAN","至少实际加入一份调料后保存方案。")
	var note: int=0
	var pour_rate: float=float(chart.groups.season.get("pour_rate_per_sec",.2))
	var beat_shift: float=0
	for row: Dictionary in chart.beats:
		row.t=float(row.t)+beat_shift
		var mouse: Dictionary=row.lanes.get("mouse",{})
		if mouse.get("group")=="season":
			if note<precise.size():
				mouse.input="spice:"+str(precise[note])
				if not precise_amounts.is_empty():
					mouse.form="hold"; mouse.hold_beats=float(precise_amounts[note])/pour_rate/(60.0/float(chart.bpm))
					# Keep every later module after the full hold/timeout budget.
					beat_shift+=ceil(maxf(0,float(mouse.hold_beats)*1.5+.2/(60.0/float(chart.bpm))-2.0))
			else: row.lanes.erase("mouse"); row.rest=row.lanes.is_empty()
			note+=1
	chart.groups.season.parameters.ingredient_id=precise[0]
	var preparations: Dictionary={}; var additions: Dictionary={entry.id:chart}
	for ingredient: String in (cuts if steam else recipe.get("preparation_sheets",{})):
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
