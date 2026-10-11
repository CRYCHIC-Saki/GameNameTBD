extends GutTest

func test_budget_peaks_at_the_documented_mode_and_stays_above_fifteen() -> void:
	assert_eq(TDEconomyMath.budget_from_unit(0.0), 15)
	assert_eq(TDEconomyMath.budget_from_unit(35.0 / 115.0), 50)
	assert_eq(TDEconomyMath.budget_from_unit(1.0), 130)
	var rng := TDBusinessRandom.new(3)
	var low := 0
	var mid := 0
	var high := 0
	for _index in 800:
		var budget := TDEconomyMath.budget_from_unit(rng.unit())
		assert_gte(budget, 15)
		if budget <= 25:
			low += 1
		if budget >= 40 and budget <= 70:
			mid += 1
		if budget >= 110:
			high += 1
	assert_gt(mid, low)
	assert_gt(mid, high)

func test_review_formula_matches_the_hand_calculation() -> void:
	assert_almost_eq(TDEconomyMath.reference_price(10.0, 1.5, 5.0), 20.0, 0.0001)
	var offer := TDEconomyMath.evaluate_offer(50.0, 20.0, 20.0, 1.0, 40.0, 50.0, 1.0, 2, 0, 0.5)
	assert_almost_eq(float(offer["pre_dish"]), 100.0, 0.0001)
	assert_almost_eq(float(offer["pre_decor"]), -10.0, 0.0001)
	assert_almost_eq(float(offer["pre_brand"]), 102.0, 0.0001)
	assert_almost_eq(float(offer["advantage"]), 192.0, 0.0001)
	var meal := TDEconomyMath.evaluate_meal(offer, 80.0, 40.0)
	assert_almost_eq(float(meal["dish_review"]), 200.0, 0.0001)
	assert_almost_eq(float(meal["overall_raw"]), 292.0 / 3.0, 0.0001)
	assert_eq(int(meal["stars"]), 5)
	assert_eq(TDEconomyMath.stars(0.0), 1)
	assert_eq(TDEconomyMath.stars(39.9), 1)
	assert_eq(TDEconomyMath.stars(40.0), 2)
	assert_eq(TDEconomyMath.stars(60.0), 3)
	assert_eq(TDEconomyMath.stars(80.0), 4)
	assert_eq(TDEconomyMath.stars(90.0), 5)

func test_same_culture_high_tier_and_wildcard_change_unity() -> void:
	var plain := [_piece("chinese_low"), _piece("chinese_low"), _piece("chinese_low"), _piece("chinese_low")]
	var foreign := [_piece("chinese_low"), _piece("chinese_low"), _piece("chinese_low"), _piece("french_low")]
	var wildcard := [_piece("chinese_low"), _piece("chinese_low"), _piece("chinese_low"), _piece("modern_low")]
	var upgraded := [_piece("chinese_low"), _piece("chinese_low"), _piece("chinese_low"), _piece("chinese_high")]
	var base := TDEconomyMath.decor_of(plain, ["plain", "modern", "life"])
	var mixed := TDEconomyMath.decor_of(foreign, ["plain", "modern", "life"])
	var wild := TDEconomyMath.decor_of(wildcard, ["plain", "modern", "life"])
	var high := TDEconomyMath.decor_of(upgraded, ["plain", "modern", "life"])
	assert_almost_eq(float(base["unity"]), 56.0, 0.001)
	assert_lt(float(mixed["unity"]), float(base["unity"]))
	assert_gt(float(wild["unity"]), float(mixed["unity"]))
	assert_gt(float(high["unity"]), float(base["unity"]))
	assert_almost_eq(float(base["effect"]), float(base["unity"]) / 100.0 * float(base["luxury"]), 0.001)

func test_recipe_unlocks_only_after_an_accepted_score_of_sixty() -> void:
	var book := TDRecipeBook.new()
	book.unlock_score = 60.0
	assert_eq(String(book.consider("kaoya", false, 90.0)["code"]), "REFUSED")
	assert_false(book.has("kaoya"))
	assert_eq(String(book.consider("kaoya", true, 59.9)["code"]), "LOW_SCORE")
	assert_false(book.has("kaoya"))
	assert_eq(String(book.consider("kaoya", true, 60.0)["code"]), "LEARNED")
	assert_true(book.has("kaoya"))
	assert_eq(String(book.consider("kaoya", true, 100.0)["code"]), "KNOWN")

func test_supply_arrives_next_day_unless_a_buff_is_active() -> void:
	var book := TDSupplyBook.new()
	var delayed := book.order(1, "tomato", 2)
	assert_eq(int(delayed["arrive"]), 2)
	assert_eq(book.count("tomato"), 0)
	assert_eq(book.collect(1).size(), 0)
	assert_eq(book.collect(2).size(), 1)
	assert_eq(book.count("tomato"), 2)
	book.pipeline = true
	var today := book.order(3, "egg", 1)
	assert_eq(int(today["arrive"]), 3)
	assert_eq(book.count("egg"), 1)

func test_low_budget_has_one_preference_and_high_budget_can_have_more() -> void:
	assert_eq(TDEconomyMath.preference_roll_count(20, 1.0, 0.0, 0.0, 0.0), 0)
	assert_eq(TDEconomyMath.preference_roll_count(100, 1.0, 0.0, 0.0, 0.0), 2)
	assert_eq(TDEconomyMath.preference_roll_count(110, 0.2, 0.5, 0.5, 0.5), 0)
	assert_eq(TDEconomyMath.preference_roll_count(110, 1.0, 0.5, 0.5, 0.5), 3)
	var session := TDPhase3Session.new()
	var loaded := session.load_default()
	assert_true(loaded.ok, loaded.message)
	assert_eq(session.catalog.playable_towns().size(), 13)
	assert_true(session.recipes.has("mapodoufu"))
	assert_false(session.recipes.has("kaoya"))
	for npc: Variant in session.npcs:
		assert_gte(int((npc as Dictionary)["budget"]), 15)
	var before := session.npcs.size()
	var shift_before := int((session.pool["plan"] as Dictionary)["budget_shift"])
	var scale_before := float((session.pool["plan"] as Dictionary)["foreign_scale"])
	session.set_zone_enabled("snack_street", false)
	assert_eq(session.npcs.size(), before - 8)
	assert_eq(int((session.pool["plan"] as Dictionary)["budget_shift"]), shift_before + 4)
	assert_gt(float((session.pool["plan"] as Dictionary)["foreign_scale"]), scale_before)
	session.competitors = []
	var npc := {
		"id": "fixed", "budget": 80, "home": "chengdu", "preferences": ["chinese"],
		"decor_expect": 68.0, "quality_expect": 79.2, "reputation_pref": 0.5,
	}
	var choice := session.choose_for(npc, {"effect": 70.0, "majority": "chinese", "unity": 100.0, "luxury": 70.0})
	assert_eq(String(choice["restaurant_id"]), "player")
	session.prices["kaoya"] = 10
	var learned := session.settle_visit(npc, "kaoya", 90.0, {"effect": 70.0, "majority": "chinese", "unity": 100.0, "luxury": 70.0}, true)
	assert_true(bool((learned["learning"] as Dictionary)["learned"]))
	assert_gte(float((learned["meal"] as Dictionary)["overall"]), 60.0)
	var refused := session.settle_visit(npc, "changfen", 99.0, {"effect": 70.0, "majority": "chinese"}, false)
	assert_false(bool((refused["learning"] as Dictionary)["learned"]))
	assert_false(session.recipes.has("changfen"))

func test_town_roads_reach_four_edges_and_fixed_zones_exist() -> void:
	var catalog := TDTownCatalog.new()
	assert_true(catalog.load_file().ok)
	var map := TDTownMap.new()
	map.build(catalog, 11)
	assert_true(map.is_walkable(TDTownMap.CENTER, 0))
	assert_true(map.is_walkable(TDTownMap.CENTER, TDTownMap.SIZE - 1))
	assert_true(map.is_walkable(0, TDTownMap.CENTER))
	assert_true(map.is_walkable(TDTownMap.SIZE - 1, TDTownMap.CENTER))
	for kind: String in ["player_diner", "competitor", "market", "plaza", "urban_village", "rich_district", "commercial_street", "snack_street", "amusement", "zoo", "landmark"]:
		var found := false
		for item: Variant in map.plots:
			if String((item as Dictionary)["kind"]) == kind:
				found = true
		assert_true(found, kind)
	assert_gt(map.housing_enabled(), 0)
	var diner: Dictionary = {}
	for item: Variant in map.plots:
		if String((item as Dictionary)["kind"]) == "player_diner":
			diner = item
	assert_eq(String(diner["kind"]), "player_diner")
	assert_gt(int(diner["w"]) * int(diner["h"]), 1)
	assert_false(map.covers_road(diner))
	assert_eq(String(map.plot_at(int(diner["x"]) + int(diner["w"]) - 1, int(diner["y"]) + int(diner["h"]) - 1)["id"]), "player_diner")
	var occupied := {}
	for item: Variant in map.plots:
		var plot: Dictionary = item
		if String(plot["kind"]) == "plaza":
			continue
		assert_false(map.covers_road(plot), String(plot["id"]))
		for y in int(plot["h"]):
			for x in int(plot["w"]):
				var cell := Vector2i(int(plot["x"]) + x, int(plot["y"]) + y)
				assert_false(occupied.has(cell), String(plot["id"]))
				occupied[cell] = true

func test_rent_utilities_and_wages_come_out_of_cash() -> void:
	var session := TDPhase3Session.new()
	assert_true(session.load_default().ok)
	var start := session.money
	assert_eq(session.employ("greeter").code, "HIRED")
	assert_eq(session.money, start - 8)
	assert_eq(session.employ("greeter").code, "ALREADY")
	session.money = 0
	assert_eq(session.employ("cashier").code, "BROKE")
	assert_false(session.staff_on("cashier"))
	session.money = 100
	assert_true(session.employ("cashier").ok)
	session.player_pieces = [{}, {}, {}]
	var before_close := session.money
	session.close_day()
	assert_eq(session.money, before_close - 18 - 6 - 3 - 16)
	assert_true(session.staff_on("greeter"))
	assert_true(session.staff_on("cashier"))
	assert_true(session.report().contains("租金"))
	session.dismiss("greeter")
	session.dismiss("cashier")
	session.player_pieces = []
	session.money = 5
	session.close_day()
	assert_eq(session.money, 0)
	assert_false(session.staff_on("greeter"))

func test_learned_dish_joins_the_kitchen_sheet() -> void:
	var session := TDPhase3Session.new()
	assert_true(session.load_default().ok)
	assert_eq(session.recipes.consider("kaoya", true, 60.0)["code"], "LEARNED")
	assert_eq(session.recipes.consider("qiguoji", true, 60.0)["code"], "LEARNED")
	var service := TDServiceCatalog.new()
	assert_true(service.load_file().ok, "service content")
	var shop := TDShopSession.new(service)
	var saved := shop.snapshot()
	var linked := TDKitchenLink.install(service, session.learned_kitchen_dishes())
	assert_true(linked.has("phase3.kaoya"))
	assert_true(linked.has("service.qiguoji"))
	var resumed := TDShopSession.new(service)
	var restored := resumed.restore(saved)
	assert_true(restored.ok, restored.message)
	assert_true(resumed.grant_recipe("phase3.kaoya").ok)
	assert_true(resumed.grant_recipe("service.qiguoji").ok)
	assert_true(resumed.is_unlocked("phase3.kaoya"))
	assert_true(resumed.is_unlocked("service.qiguoji"))
	assert_true(bool(resumed.snapshot().menu["phase3.kaoya"].enabled))
	var cooked := service.cooking.for_recipe("phase3.kaoya")
	assert_false(cooked.is_empty())
	assert_eq(String(cooked.recipe.guided_profile), "phase3.kaoya")
	assert_eq(String(cooked.recipe.preparation_sheets.chicken), "service.strips")
	assert_eq(String(cooked.recipe.cooking_method), "stir")
	var sheet: Dictionary = service.cooking.data().pc_operations.document_sheets["phase3.kaoya"]
	assert_eq(String(sheet.dish), "北京烤鸭")
	assert_gt((sheet.beats as Array).size(), 0)
	var composed := service.with_plans([])
	assert_true(composed.ok, composed.message)
	var kitchen := TDCookingCatalog.new()
	var loaded := kitchen.load_data(composed.data, "phase3 kitchen")
	assert_true(loaded.ok, loaded.message)
	assert_false(kitchen.for_recipe("phase3.kaoya").is_empty())
	assert_true(session.report().contains("phase3.kaoya"))

func test_raw_ingredients_can_be_prepped_by_dish_or_by_pick() -> void:
	var session := TDPhase3Session.new()
	var loaded := session.load_default()
	assert_true(loaded.ok, loaded.message)
	assert_gt(session.ingredients.items.size(), 200)
	assert_eq(String(session.ingredients.get_item("tomato")["name"]), "西红柿")
	assert_eq(session.pantry.life_days("meat", "counter"), 2)
	assert_eq(session.pantry.life_days("meat", "fridge"), 6)
	assert_eq(session.pantry.life_days("meat", "freezer"), 16)
	assert_gt(session.pantry.life_days("spice", "dry_store"), session.pantry.life_days("spice", "fridge"))
	for dish: Variant in session.catalog.dish_list():
		var dish_id := String((dish as Dictionary)["id"])
		var bill := session.pantry.bill(dish_id)
		assert_false(bill.is_empty(), dish_id)
		for ingredient_id: String in bill:
			assert_false(session.ingredients.get_item(ingredient_id).is_empty(), "%s:%s" % [dish_id, ingredient_id])
	var start := session.money
	var by_dish := session.prep_dish("mapodoufu")
	assert_eq(by_dish.code, "PREPPED")
	assert_eq(session.money, start - 11)
	assert_eq(session.pantry.count("firmtofu"), 1)
	assert_eq(session.pantry.count("doubanjiang"), 1)
	assert_eq(session.pantry.count("porkloin"), 1)
	session.money = 0
	assert_eq(session.prep_dish("kaoya").code, "BROKE")
	assert_eq(session.pantry.count("duck"), 0)
	assert_eq(session.pantry.lots.size(), 3)
	session.money = 80
	session.pantry_device = "counter"
	session.pantry_category = "vegetable"
	var scallion := session.ingredients.ids_in("vegetable").find("scallion")
	assert_gte(scallion, 0)
	session.pantry_index = scallion
	assert_eq(String(session.current_pantry_item()["id"]), "scallion")
	assert_eq(session.prep_selected_ingredient().code, "PREPPED")
	session.pantry_device = "fridge"
	assert_eq(session.prep_selected_ingredient().code, "PREPPED")
	assert_gt(session.pantry.life_days("vegetable", "fridge"), session.pantry.life_days("vegetable", "counter"))
	for _step in session.pantry.life_days("vegetable", "counter"):
		session.close_day()
	assert_eq(session.pantry.count("scallion"), 1)
	for lot: Variant in session.pantry.lots:
		if String((lot as Dictionary)["ingredient_id"]) == "scallion":
			assert_eq(String((lot as Dictionary)["device_id"]), "fridge")
	var before := session.money
	assert_eq(session.prep_dish("missing-dish").code, "NO_BILL")
	assert_eq(session.money, before)
	var pear := session.prep_dish("dongli")
	assert_true(pear.ok, pear.message)
	assert_true(pear.message.contains("苹果"))
	assert_eq(session.pantry.count("apple"), 1)
	session.money = 30
	var ordered := session.order_supply("egg")
	assert_true(ordered.ok, ordered.message)
	assert_gt(int(ordered.data["arrive"]), session.day)
	assert_eq(session.pantry.count("egg"), 0)
	assert_true(session.pantry_text().contains("冷藏"))
	assert_true(session.report().contains("原料"))

func test_iso_projection_picks_the_same_cell_and_counts_two_walls() -> void:
	assert_eq(TDRestaurantIsoView.wall_count(20, 11), 31)
	for cell: Vector2i in [Vector2i(0, 0), Vector2i(4, 6), Vector2i(19, 10)]:
		var projected := TDRestaurantIsoView.project(float(cell.x) + 0.5, float(cell.y) + 0.5)
		assert_eq(TDRestaurantIsoView.pick_cell(projected), cell)

func _piece(style_id: String) -> Dictionary:
	return {"style_id": style_id}
