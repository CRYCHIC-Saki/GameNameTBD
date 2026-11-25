extends GutTest
var service: TDServiceCatalog

func before_all() -> void:
	service=TDServiceCatalog.new()
	assert_true(service.load_file().ok)
	var result:=TDResearchRuntime.install(service)
	assert_true(result.ok,result.message)

func test_default_runtime_copies_keep_local_recipe_changes_out_of_other_profiles() -> void:
	var first := TDServiceCatalog.new()
	assert_true(TDResearchRuntime.load_default(first).ok)
	var recipe := first.cooking.recipe_data("service.tomato_egg")
	var sheet := first.cooking.sheet_data(recipe.guided_profile)
	var original_label := str(sheet.dish)
	var original_price := int(first.config.costs.egg)
	first.config.costs.egg = original_price + 1
	recipe.id = "test.local_recipe"
	sheet.dish = "local change"
	first.cooking.adopt_recipe(recipe, sheet)
	var second := TDServiceCatalog.new()
	assert_true(TDResearchRuntime.load_default(second).ok)
	assert_true(second.cooking.recipe_data("test.local_recipe").is_empty())
	assert_eq(str(second.cooking.sheet_data(sheet.id).dish), original_label)
	assert_eq(int(second.config.costs.egg), original_price)

func test_all_sixty_have_playable_individual_charts_and_research() -> void:
	var content:=TDResearchRuntime.expanded()
	assert_eq(content.dishes.size(),60)
	var counts: Dictionary={};var signatures: Dictionary={}
	var operations: Dictionary=service.cooking.data().operations
	for dish: Dictionary in content.dishes:
		var recipe: Dictionary=dish.recipe
		counts[recipe.cuisine_id]=int(counts.get(recipe.cuisine_id,0))+1
		for chart_id: String in [recipe.guided_profile,recipe.research_profile]:
			var chart: Dictionary=content.sheets[chart_id]
			var sequence: Array=[]
			for row: Dictionary in chart.beats:
				var tracks: Dictionary={}
				for track: String in row.lanes:
					var note: Dictionary=row.lanes[track]
					tracks[track]=[note.op,note.input,note.form,note.get("hold_beats",0)]
				sequence.append([row.t,tracks])
			var signature:=JSON.stringify(sequence)
			assert_false(signatures.has(signature),"duplicate inputs: "+chart_id)
			signatures[signature]=chart_id
			var schedule:=TDBeatSheet.new()
			assert_true(schedule.configure(chart,operations,{"perfect_sec":.1,"good_sec":.2}).ok,chart_id)
			assert_gt(schedule.duration_sec,20.0)
		assert_false(dish.offer.primary.is_empty())
		for id: String in dish.offer.primary: assert_true(service.config.costs.has(id),id)
		var needed:=service.material_needs(service.cooking,recipe.id)
		for id: String in needed: assert_gte(int(dish.offer.stock.get(id,0)),int(needed[id]),recipe.id+" procurement kit: "+id)
	assert_eq(counts,{"cn":20,"eu":20,"jp":20})

func test_cold_sushi_dishes_do_not_require_frying_or_heating() -> void:
	for id: String in ["study.j08","study.j12"]:
		var recipe:=service.cooking.recipe_data(id)
		assert_eq(recipe.required_steps,[])
		for food: Dictionary in recipe.required_ingredients: assert_eq(float(food.min_heat_dose),0.0)
		var actions: Array=recipe.technique_plan.map(func(p:Dictionary)->String:return p.technique)
		assert_false("heat" in actions);assert_false("steam" in actions)
	assert_eq(service.cooking.recipe_data("study.j08").workstation,"sushi")
	assert_true(service.cooking.recipe_data("study.l04").is_empty())

func test_cuisine_techniques_have_explicit_order() -> void:
	var souffle: Array=service.cooking.recipe_data("study.e18").technique_plan.map(func(p:Dictionary)->String:return p.technique)
	assert_eq(souffle,["mix","season","fold","preheat","bake"])
	var tempura: Array=service.cooking.recipe_data("study.j09").technique_plan.map(func(p:Dictionary)->String:return p.technique)
	assert_eq(tempura,["mix","shape","preheat","fry","flip","fry","season"])
	assert_true(service.cooking.recipe_data("study.l08").is_empty())

func test_original_stable_recipe_and_primary_contracts_survive() -> void:
	assert_eq(service.offer("service.tomato_egg").primary,["tomato","egg"])
	assert_eq(service.offer("study.egg_fried_rice").primary,["rice","egg"])
	assert_eq(service.offer("study.yangchun_noodles").primary,["wheat_noodles","water"])
	assert_false(service.offer("service.beef_noodles").is_empty())

func test_content_snapshots_cannot_mutate_shared_templates() -> void:
	var recipe:=service.cooking.recipe_data("study.j08")
	recipe.required_ingredients[0].min_amount=99
	assert_eq(float(service.cooking.recipe_data("study.j08").required_ingredients[0].min_amount),1.0)
	var data:=TDResearchRuntime.expanded();data.dishes[0].recipe.name="bad"
	assert_eq(TDResearchRuntime.expanded().dishes[0].recipe.name,"蛋炒饭")
	var ingredients:=service.cooking.ingredient_definitions();ingredients[0].name="changed"
	assert_ne(service.cooking.ingredient_definitions()[0].name,"changed")
	var customers:=service.cooking.customer_definitions();customers[0].name="changed"
	assert_ne(service.cooking.customer_definitions()[0].get("name",""),"changed")
	var sheet:=service.cooking.sheet_data("study.j08");sheet.beats.clear()
	assert_false(service.cooking.sheet_data("study.j08").beats.is_empty())

func test_control_ranges_and_overlaps_rejected() -> void:
	var content:=TDResearchRuntime.expanded();var chart: Dictionary=content.sheets["study.e18"].duplicate(true)
	for group: Dictionary in chart.groups.values():
		if group.operation=="heat": group.control.target_min=1;group.control.target_max=.1
	assert_eq(TDBeatSheet.new().configure(chart,service.cooking.data().operations).code,"INVALID_CONTROL")

func test_every_research_node_has_chart_and_keeps_story_cuisine_gates() -> void:
	var atlas:=TDResearchCatalog.new();var loaded:=atlas.load_file()
	assert_true(loaded.ok,loaded.code)
	assert_eq(atlas.data.charts.size(),60)
	assert_eq(atlas.data.unlock_rules.initial_unlocked_ids,["C01","C02"])
	for id: String in atlas.nodes:
		assert_false(atlas.chart(id).is_empty(),id)
		assert_false(atlas.runtime_id(id).is_empty(),id)

func test_every_dish_accepts_declared_flavor_request_without_reusing_another_dish_chart() -> void:
	for item: Dictionary in TDResearchRuntime.expanded().dishes:
		var profile:=service.request_profile(item.recipe.id,{"requirements":[{"kind":"flavor","taste":1,"slot":1,"target":25,"weight":1}]})
		assert_not_null(profile,item.atlas_id)
		if profile!=null:
			var recipe:=profile.recipe_data(item.recipe.id)
			assert_eq(recipe.technique_plan,item.recipe.technique_plan)
			var spice:=TDMaterialCatalog.preference_spice(item.recipe.cuisine_id,1,"sugar")
			if not spice.is_empty(): assert_has(recipe.allowed_ingredients,spice)
