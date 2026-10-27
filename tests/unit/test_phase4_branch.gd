extends GutTest

func test_sizes_grow_the_interior_and_the_floor_still_seats_a_guest() -> void:
	assert_eq(TDRestaurantSizes.footprint("small"), Vector2i(3, 4))
	assert_eq(TDRestaurantSizes.footprint("medium"), Vector2i(4, 6))
	assert_eq(TDRestaurantSizes.footprint("large"), Vector2i(6, 9))
	assert_eq(TDRestaurantSizes.footprint("huge"), Vector2i(12, 18))
	assert_eq(TDRestaurantSizes.upkeep("small"), 6)
	assert_eq(TDRestaurantSizes.upkeep("medium"), 12)
	assert_eq(TDRestaurantSizes.upkeep("large"), 27)
	assert_eq(TDRestaurantSizes.upkeep("huge"), 108)
	var previous := 0
	var catalog := TDRestaurantCatalog.new()
	assert_true(catalog.load_file().ok, catalog.load_file().message)
	for size_id: String in TDRestaurantSizes.IDS:
		var room := TDRestaurantSizes.interior(size_id)
		assert_gt(room.x * room.y, previous, size_id)
		previous = room.x * room.y
		var layout := TDRestaurantLayout.make_sized(catalog, room.x, room.y)
		assert_not_null(layout, "%s %s" % [size_id, TDRestaurantLayout.floor_error])
		assert_eq(layout.columns * layout.rows, room.x * room.y)
		assert_true(layout.set_staff("greeter", true).ok)
		assert_true(layout.set_staff("cashier", true).ok)
		var plan := TDRestaurantService.plan(layout, [], false, true)
		assert_true(bool(plan["ok"]), "%s %s" % [size_id, String(plan["message"])])
	var session := TDPhase3Session.new()
	assert_true(session.load_default().ok)
	assert_true(_plot(session, "player_diner").is_empty())
	assert_false(session.town_map.diner_lot().is_empty())
	assert_eq(session.town_map.factory_lots().size(), TDTownMap.FACTORY_SLOTS)
	assert_eq(session.build_venue("chinese").code, "BUILT")
	var diner := _plot(session, "player_diner")
	var lot := session.town_map.diner_lot()
	assert_eq(int(diner["w"]) * 2, int(lot["w"]))
	assert_eq(int(diner["h"]) * 2, int(lot["h"]))
	assert_eq(String(diner["name"]), "中餐厅")
	assert_eq(session.interior_culture(), "chinese")
	assert_true(session.town_map.is_walkable(int(diner["x"]), int(diner["y"])))
	assert_false(session.town_map.covers_road(diner))
	assert_true(session.town_map.plot_at(TDTownMap.CENTER, TDTownMap.CENTER).is_empty())
	var western := TDPhase3Session.new()
	assert_true(western.load_default().ok)
	assert_eq(western.build_venue("western").code, "BUILT")
	assert_eq(String(_plot(western, "player_diner")["name"]), "西餐厅")
	assert_eq(western.interior_culture(), "french")
	assert_eq(session.resize_home("medium").code, "RESIZED")
	diner = _plot(session, "player_diner")
	assert_eq(int(diner["w"]) * int(diner["h"]), 24)
	assert_eq(session.interior_grid(), Vector2i(8, 12))
	var factory_id := String((session.town_map.factory_lots()[0] as Dictionary)["id"])
	assert_eq(session.build_factory(factory_id).code, "BUILT")
	assert_eq(session.build_factory(factory_id).code, "ALREADY")
	assert_eq(session.click_build_at(Vector2i(int(diner["x"]), int(diner["y"]))).code, "ALREADY")

func test_factory_production_prices_follow_the_market_and_upgrades_cut_time() -> void:
	var session := _session()
	assert_eq(session.build_factory("factory-1").code, "BUILT")
	assert_eq(session.factory_quote("salt"), 1)
	var market: Dictionary = session.town_map.markets()[0]
	var distance := session.town_map.distance_to(String(market["id"]))
	session.selected_market = String(market["id"])
	var expected := maxi(1, int(round(8.0 * (1.0 + float(distance) * 0.05))))
	assert_eq(session.factory_quote("beef"), expected)
	session.selected_market = ""
	assert_eq(session.factory_quote("beef"), 8)
	var slow := session.factory_hours("factory-1", "salt", 2)
	assert_almost_eq(slow, 1.0, 0.01)
	session.money = 200
	assert_eq(session.produce_factory("factory-1", "salt", 2).code, "STARTED")
	assert_eq(session.supply.count("salt"), 0)
	assert_eq(session.money, 198)
	assert_false(session.factory_job("factory-1").is_empty())
	assert_eq(session.produce_factory("factory-1", "salt", 1).code, "BUSY")
	assert_eq(session.tick_factories(TDPhase3Session.FACTORY_HOUR_SECONDS * 0.4).size(), 0)
	assert_eq(session.supply.count("salt"), 0)
	assert_gt(session.factory_progress("factory-1"), 0.3)
	var one: Array = session.tick_factories(TDPhase3Session.FACTORY_HOUR_SECONDS * 0.1)
	assert_eq(one.size(), 1)
	assert_eq(int(one[0].get("qty", 0)), 1)
	assert_eq(session.supply.count("salt"), 1)
	assert_eq(int(session.factory_job("factory-1").get("qty", 0)), 1)
	var done: Array = session.tick_factories(TDPhase3Session.FACTORY_HOUR_SECONDS * 0.5)
	assert_eq(done.size(), 1)
	assert_eq(session.supply.count("salt"), 2)
	assert_true(session.factory_job("factory-1").is_empty())
	assert_eq(session.factory_goods().size(), 1)
	assert_eq(session.produce_factory("factory-1", "salt", 0).code, "RANGE")
	assert_eq(session.produce_factory("factory-1", "tomato", 1).code, "WRONG")
	session.money = 0
	assert_eq(session.produce_factory("factory-1", "salt", 1).code, "BROKE")
	session.money = 200
	assert_eq(session.upgrade_factory("factory-1").code, "UPGRADED")
	assert_lt(session.factory_hours("factory-1", "salt", 2), slow)
	assert_eq(session.factory_lines("factory-1"), 2)
	assert_eq(session.produce_factory("factory-1", "salt", 1).code, "STARTED")
	assert_eq(session.produce_factory("factory-1", "sugar", 1).code, "STARTED")
	assert_eq(session.factory_running("factory-1").size(), 2)
	assert_eq(session.produce_factory("factory-1", "salt", 1).code, "BUSY")
	assert_eq(session.tick_factories(TDPhase3Session.FACTORY_HOUR_SECONDS).size(), 2)
	assert_eq(session.factory_lines("factory-1"), 2)
	assert_true(session.factory_job("factory-1").is_empty())
	assert_eq(session.upgrade_factory("factory-1").code, "UPGRADED")
	assert_eq(session.upgrade_factory("factory-1").code, "MAX")
	assert_eq(session.factory_level_of("factory-1"), TDTownMap.FACTORY_LEVEL_MAX)

func test_upkeep_grows_with_size_and_wage_mood_personality_change_quality() -> void:
	assert_gt(TDBranchSim.quality_shift(70, "diligent", "careful", 20, 16), TDBranchSim.quality_shift(70, "diligent", "careful", 16, 16))
	assert_gt(TDBranchSim.quality_shift(100, "diligent", "careful", 24, 16), TDBranchSim.quality_shift(0, "lazy", "careless", 8, 16))
	assert_eq(TDBranchSim.mood_delta(20, 16, "diligent"), 6)
	assert_eq(TDBranchSim.mood_delta(8, 16, "lazy"), -11)
	assert_gt(TDBranchSim.accident_chance(25, "careless", "lazy", 20), TDBranchSim.accident_chance(25, "careful", "diligent", 80))
	var high := TDBranchSim.service_quality(70, 100, "diligent", "careful", 24, 16)
	var low := TDBranchSim.service_quality(70, 0, "lazy", "careless", 8, 16)
	assert_gt(high, low)
	assert_lt(high, 100)
	assert_gte(low, 40)
	var session := _session()
	assert_eq(session.store_upkeep("home"), 6)
	assert_eq(session.resize_home("medium").code, "RESIZED")
	assert_eq(session.store_upkeep("home"), 12)
	assert_eq(session.employ("chef").code, "HIRED")
	var card := session.staff_card("home", "chef")
	assert_eq(int(card["wage"]), int(card["recommended"]))
	var hired_mood := clampi(70 + TDBranchSim.mood_delta(int(card["wage"]), int(card["recommended"]), String(card["drive"])), 0, 100)
	assert_eq(int(card["mood"]), hired_mood)
	assert_eq(session.set_wage("chef", "home", 4).code, "WAGE")
	card = session.staff_card("home", "chef")
	assert_eq(int(card["wage"]), int(card["recommended"]) + 4)
	assert_eq(int(card["mood"]), hired_mood)
	assert_gt(int(card["shift"]), TDBranchSim.quality_shift(hired_mood, String(card["drive"]), String(card["care"]), int(card["recommended"]), int(card["recommended"])))

func test_player_can_work_alone_and_staff_use_real_stock() -> void:
	var session := _session()
	var start := session.money
	assert_true(session.prep_dish("tomato_egg").ok)
	var tomatoes := session.pantry.count("tomato")
	assert_eq(session.player_prep().code, "PREPPED")
	assert_eq(session.pantry.count("tomato"), tomatoes - 1)
	assert_true(session.player_finish(80).ok)
	assert_eq(session.hand_prep().code, "NEED_PREP")
	assert_eq(session.employ("prep").code, "HIRED")
	assert_eq(session.money, start - _bill(session, "tomato_egg") - 7)
	assert_true(session.prep_dish("tomato_egg").ok)
	tomatoes = session.pantry.count("tomato")
	assert_eq(session.hand_prep().code, "PREPPED")
	assert_eq(session.pantry.count("tomato"), tomatoes - 1)
	assert_eq(session.player_prep().code, "BUSY")
	assert_eq(session.employ("chef").code, "HIRED")
	session.pantry_dish = "tomato_egg"
	var cooked := _cook_until_done(session)
	assert_eq(String(cooked["code"]), "COOKED")
	assert_lt(int(cooked["quality"]), 100)
	assert_gte(int(cooked["quality"]), 40)
	assert_eq(session.player_finish(100).code, "BUSY")
	session.pantry_dish = "mapodoufu"
	assert_true(session.prep_dish("mapodoufu").ok)
	assert_eq(session.hand_prep().code, "PREPPED")
	assert_eq(session.hand_cook().code, "CANT")
	assert_eq(session.teach_chef("home", "mapodoufu").code, "TRAINED")
	var taught := _cook_until_done(session)
	assert_ne(String(taught["code"]), "CANT")
	assert_lt(int(taught["quality"]), 100)

func test_branch_culture_price_and_thirty_days_do_not_double_settle() -> void:
	var local := TDBranchSim.guest_count("french", "french", 16, 14.0, true)
	var abroad := TDBranchSim.guest_count("chinese", "french", 16, 14.0, true)
	var everyday := TDBranchSim.guest_count("chinese", "plain", 8, 8.0, false)
	var everyday_abroad := TDBranchSim.guest_count("french", "plain", 8, 8.0, false)
	var pricey := TDBranchSim.guest_count("french", "french", 80, 14.0, true)
	assert_gt(local, abroad)
	assert_eq(everyday, everyday_abroad)
	assert_lt(pricey, local)
	var session := _session()
	assert_eq(session.claim_branch("small", Vector2i(21, 21)).code, "HOME")
	assert_true(session.set_town("paris").ok)
	var spot := _open_cell(session, "small")
	assert_ne(spot, Vector2i(-1, -1))
	session.money = 5000
	var claimed := session.claim_branch("small", spot)
	assert_eq(claimed.code, "CLAIMED", claimed.message)
	assert_eq(session.branch_culture, "french")
	assert_eq(session.money, 4980)
	var branch := _plot(session, "branch_diner")
	assert_eq(int(branch["w"]) * int(branch["h"]), 12)
	assert_false(session.town_map.covers_road(branch))
	assert_true(session.set_town("london").ok)
	var london := _open_cell(session, "medium")
	assert_eq(session.claim_branch("medium", london).code, "ONE_BRANCH")
	assert_true(session.set_town("paris").ok)
	session.define_custom("custom.soup", "例汤", "french", 4, ["flour"])
	assert_eq(session.set_branch_menu(["custom.soup"]).code, "MENU")
	assert_eq(int(session.branch_menu[0]["version"]), 1)
	session.define_custom("custom.soup", "例汤", "french", 5, ["flour", "butter"])
	assert_eq(int(session.branch_menu[0]["version"]), 1)
	assert_eq(session.sync_branch_recipe("custom.soup").code, "SYNCED")
	assert_eq(int(session.branch_menu[0]["version"]), 2)
	assert_eq((session.branch_menu[0]["history"] as Array).size(), 1)
	assert_eq(int(((session.branch_menu[0]["history"] as Array)[0] as Dictionary)["version"]), 1)
	assert_true(session.recipes.grant("kegsong"))
	assert_eq(session.employ("manager", "branch").code, "HIRED")
	assert_eq(session.employ("chef", "branch").code, "HIRED")
	assert_eq(session.employ("prep", "branch").code, "HIRED")
	assert_false(session.staff_on("chef"))
	assert_eq(session.teach_chef("branch", "kegsong").code, "TRAINED")
	assert_eq(session.set_branch_menu(["kegsong"]).code, "MENU")
	session.branch_stock = {"flour": 400, "butter": 400}
	var home_recipes := session.home_chef_recipes.duplicate(true)
	assert_true(home_recipes.is_empty())
	var before := session.money
	var revenue := 0
	var wages := 0
	var upkeep := 0
	for index in 30:
		session.day = index + 1
		var result := session.settle_branch()
		assert_eq(String(result["code"]), "SETTLED", String(result["events"]))
		revenue += int(result["revenue"])
		wages += int(result["wages"])
		upkeep += int(result["upkeep"])
		var again := session.settle_branch()
		assert_eq(String(again["code"]), "REPEAT")
		assert_eq(session.money, before + revenue - wages - upkeep)
	assert_gt(revenue, 0)
	assert_eq(session.money, before + revenue - wages - upkeep)
	assert_eq(upkeep, TDRestaurantSizes.upkeep("small") * 30)
	session.dismiss("manager", "branch")
	session.day = 31
	var unmanaged := session.settle_branch()
	assert_eq(int(unmanaged["revenue"]), 0)
	assert_true(String(unmanaged["events"]).contains("缺店长"))
	assert_eq(session.employ("manager", "branch").code, "HIRED")
	session.day = 32
	session.branch_stock = {}
	var dry := session.settle_branch()
	assert_true(String(dry["events"]).contains("缺货"))
	assert_eq(int(dry["revenue"]), 0)
	session.day = 33
	session.money = 0
	var broke := session.settle_branch()
	assert_true(String(broke["events"]).contains("离开"))
	assert_false(bool(session.branch_staff["manager"]))
	var saved_money := session.money
	var repeated := session.settle_branch()
	assert_eq(String(repeated["code"]), "REPEAT")
	assert_eq(session.money, saved_money)
	var blob := session.export_phase4()
	var restored := TDPhase3Session.new()
	assert_true(restored.load_default().ok)
	restored.import_phase4(blob)
	var loaded := restored.settle_branch()
	assert_eq(String(loaded["code"]), "REPEAT")
	assert_eq(restored.money, saved_money)
	assert_false(session.staff_on("prep"))

func test_building_a_factory_keeps_the_map_and_the_player() -> void:
	var session := TDPhase3Session.new()
	assert_true(session.load_default().ok)
	var parcels: Array = session.town_map.commercial_parcels()
	if not parcels.is_empty():
		var sample: Dictionary = parcels[0]
		var ownership := {}
		ownership[String(sample["id"])] = {"owner_id": "npc", "store_id": "store-a", "name": "街坊餐馆", "construction": false}
		var placed := session.town_map.apply_commercial_occupancy(ownership)
		assert_true(placed.ok, placed.message)
	var roads: Dictionary = session.town_map.roads.duplicate()
	var places: Array[String] = []
	for item: Variant in session.town_map.plots:
		var plot: Dictionary = item
		places.append("%s|%s|%d|%d|%d|%d" % [String(plot["id"]), String(plot["kind"]), int(plot["x"]), int(plot["y"]), int(plot["w"]), int(plot["h"])])
	var revision := session.map_revision
	var factory: Dictionary = session.town_map.factory_lots()[0]
	var town := TDTownWorld.new()
	town.session = session
	town.player_mode = true
	add_child_autofree(town)
	await get_tree().process_frame
	var away := Vector2i(TDTownMap.CENTER + 3, TDTownMap.CENTER)
	assert_true(session.town_map.is_walkable(away.x, away.y))
	town._player.position = town._origin() + (Vector2(away) + Vector2(0.5, 0.5)) * TDTownWorld.CELL
	assert_eq(session.build_factory(String(factory["id"])).code, "BUILT")
	await get_tree().process_frame
	assert_eq(town._player_cell(), away)
	assert_eq(session.map_revision, revision)
	assert_eq(session.town_map.roads, roads)
	var changed := 0
	assert_eq(session.town_map.plots.size(), places.size())
	for index: int in places.size():
		var plot: Dictionary = session.town_map.plots[index]
		var line := "%s|%s|%d|%d|%d|%d" % [String(plot["id"]), String(plot["kind"]), int(plot["x"]), int(plot["y"]), int(plot["w"]), int(plot["h"])]
		if line == places[index]:
			continue
		changed += 1
		assert_eq(String(plot["id"]), String(factory["id"]))
		assert_eq(String(plot["kind"]), "supply_factory")
		assert_eq(int(plot["x"]), int(factory["x"]))
		assert_eq(int(plot["y"]), int(factory["y"]))
	assert_eq(changed, 1)

func _session() -> TDPhase3Session:
	var session := TDPhase3Session.new()
	assert_true(session.load_default().ok)
	assert_eq(session.build_venue("chinese").code, "BUILT")
	session.money = 800
	session.pantry_dish = "tomato_egg"
	session.rng = TDBusinessRandom.new(7)
	return session

func _bill(session: TDPhase3Session, dish_id: String) -> int:
	var cost := 0
	for ingredient_id: String in session.pantry.bill(dish_id):
		cost += session.pantry.cost_of(session.ingredients.get_item(ingredient_id))
	return cost

func _cook_until_done(session: TDPhase3Session) -> Dictionary:
	var result := {"code": "", "quality": 0}
	for _try in 12:
		if String(session.duty.get("prep", "")) == "" or String(session.duty.get("cook", "")) != "":
			assert_true(session.prep_dish(session.pantry_dish).ok)
			assert_eq(session.hand_prep().code, "PREPPED")
		var cooked := session.hand_cook()
		result = {"code": cooked.code, "quality": int(cooked.data.get("quality", 0))}
		if cooked.code == "COOKED":
			return result
		assert_eq(cooked.code, "ACCIDENT", cooked.message)
	return result

func _plot(session: TDPhase3Session, id: String) -> Dictionary:
	for item: Variant in session.town_map.plots:
		var plot: Dictionary = item
		if String(plot.get("id", "")) == id:
			return plot
	return {}

func _open_cell(session: TDPhase3Session, size_id: String) -> Vector2i:
	var foot := TDRestaurantSizes.footprint(size_id)
	for y in range(1, TDTownMap.SIZE - foot.y):
		for x in range(1, TDTownMap.SIZE - foot.x):
			if session.town_map.can_place(x, y, foot.x, foot.y):
				return Vector2i(x, y)
	return Vector2i(-1, -1)
