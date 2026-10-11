class_name TDKitchenLink
extends RefCounted

const STIR_CHART := "service.tomato_egg"
const STEAM_CHART := "service.qiguoji"

static func install(service: TDServiceCatalog, dishes: Array) -> Array[String]:
	var ids: Array[String] = []
	for item: Variant in dishes:
		if not item is Dictionary:
			continue
		var recipe_id := _ensure(service, item)
		if recipe_id != "":
			ids.append(recipe_id)
	return ids

static func _ensure(service: TDServiceCatalog, dish: Dictionary) -> String:
	var existing := String(dish.get("service_recipe", ""))
	if existing != "":
		if service.cooking.for_recipe(existing).is_empty():
			return ""
		return existing
	var recipe_id := "phase3." + String(dish.get("id", ""))
	if not service.cooking.for_recipe(recipe_id).is_empty():
		return recipe_id
	var kitchen: Dictionary = dish.get("kitchen", {})
	var chart_id := String(kitchen.get("chart", ""))
	var template_pack := service.cooking.for_recipe(chart_id)
	if template_pack.is_empty() or chart_id not in [STIR_CHART, STEAM_CHART]:
		return ""
	var template: Dictionary = template_pack.recipe
	var sheets: Dictionary = service.cooking.data().pc_operations.document_sheets
	if not sheets.has(chart_id):
		return ""
	var primary: Array = kitchen.get("primary", [])
	var cut := String(kitchen.get("cut", ""))
	if not sheets.has(cut) or primary.size() != 2:
		return ""
	var recipe := template.duplicate(true)
	recipe["id"] = recipe_id
	recipe["name"] = String(dish.get("name", recipe_id))
	recipe["initially_unlocked"] = false
	recipe["failed_dish"] = false
	recipe["is_custom"] = false
	recipe["cooking_method"] = String(kitchen.get("method", "stir"))
	recipe["guided_profile"] = recipe_id
	recipe["required_ingredients"] = []
	recipe["preparation_sheets"] = {}
	recipe.allowed_ingredients = (template.get("allowed_ingredients", []) as Array).duplicate()
	for index in primary.size():
		var ingredient := String(primary[index])
		recipe.required_ingredients.append({
			"id": ingredient,
			"min_amount": 1,
			"min_fine": 0.0,
			"max_fine": 1.0,
			"min_heat_dose": 0.2,
		})
		if ingredient not in recipe.allowed_ingredients:
			recipe.allowed_ingredients.append(ingredient)
		if recipe.cooking_method == "steam" or index == 0:
			recipe.preparation_sheets[ingredient] = cut
	var sheet: Dictionary = (sheets[chart_id] as Dictionary).duplicate(true)
	sheet["id"] = recipe_id
	sheet["dish"] = recipe["name"]
	service.cooking.adopt_recipe(recipe, sheet)
	service.config.offers.append({
		"id": recipe_id,
		"reference_cents": maxi(1, int(dish.get("price", 1)) * 100),
		"source": "Phase3 learned " + String(dish.get("id", "")),
		"primary": primary.duplicate(),
		"parameter_status": "PROPOSED",
		"stock": _stock(service, primary),
	})
	service.config.recipes.append(recipe)
	return recipe_id

static func _stock(service: TDServiceCatalog, primary: Array) -> Dictionary:
	var stock := {}
	for ingredient: Variant in service.offer(STIR_CHART).get("stock", {}):
		stock[String(ingredient)] = int(service.offer(STIR_CHART).stock[ingredient])
	for ingredient: Variant in primary:
		stock[String(ingredient)] = 1000
	return stock
