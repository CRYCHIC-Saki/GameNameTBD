extends GutTest

func test_roles_cap_pace_and_tip_without_stacking() -> void:
	var crew := TDRestaurantCrew.new()
	assert_eq(crew.hire("cook-zhou").code, "HIRED")
	assert_eq(crew.hire("cook-zhou").code, "ALREADY")
	assert_eq(crew.level_of("cook-zhou"), 1)
	assert_almost_eq(crew.cook_pace(), 1.05, 0.001)
	assert_eq(crew.hire("cook-he").code, "HIRED")
	assert_eq(crew.hire("cook-man").code, "FULL")
	assert_almost_eq(crew.cook_pace(), 1.05, 0.001)
	assert_almost_eq(crew.tip_scale(), 1.0, 0.001)
	assert_eq(crew.hire("waiter-tao").code, "HIRED")
	assert_almost_eq(crew.tip_scale(), 1.05, 0.001)
	assert_eq(crew.record_served_order().size(), 0)
	assert_eq(crew.record_served_order().size(), 0)
	assert_eq(crew.record_served_order().size(), 0)
	var promoted := crew.record_served_order()
	assert_true(promoted.has("老周升到2级"))
	assert_true(promoted.has("小桃升到2级"))
	assert_eq(crew.level_of("cook-he"), 2)
	assert_almost_eq(crew.cook_pace(), 1.10, 0.001)
	assert_almost_eq(crew.tip_scale(), 1.10, 0.001)
	for _step in 12:
		crew.record_served_order()
	assert_eq(crew.level_of("cook-zhou"), 5)
	assert_eq(crew.xp_of("cook-zhou"), 16)
	assert_almost_eq(crew.cook_pace(), 1.25, 0.001)
	assert_almost_eq(crew.tip_scale(), 1.25, 0.001)
	assert_eq(crew.record_served_order().size(), 0)
	assert_eq(crew.dismiss("cook-zhou").code, "DISMISSED")
	assert_almost_eq(crew.cook_pace(), 1.0, 0.001)
	assert_eq(crew.hire("cook-zhou").code, "HIRED")
	assert_eq(crew.level_of("cook-zhou"), 5)
	assert_almost_eq(crew.cook_pace(), 1.25, 0.001)

func test_secondary_buff_moves_requested_attributes_and_keeps_the_original() -> void:
	var crew := TDRestaurantCrew.new()
	assert_true(crew.hire("cook-man").ok)
	var dish := {
		"dish_attributes": {
			"flavor": [[0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [20, 0, 0, 0]],
			"aroma": {"fresh": 10},
			"texture": {"A": 0.0, "B": 0.0, "C": 0.0},
			"temperature_c": 40.0,
		},
	}
	var customer := {"requirements": [
		{"kind": "flavor", "taste": 6, "slot": 0, "min": 80, "max": 100},
		{"kind": "aroma", "tag": "fresh", "min": 50, "max": 50},
		{"kind": "texture", "axis": "A", "min": 0.4, "max": 0.4},
		{"kind": "temperature", "min": 60, "max": 60},
	]}
	var adjusted: Dictionary = crew.apply_dish(dish, customer)
	assert_almost_eq(float(adjusted.dish_attributes.flavor[6][0]), 22.8, 0.01)
	assert_almost_eq(float(adjusted.dish_attributes.aroma.fresh), 11.6, 0.01)
	assert_almost_eq(float(adjusted.dish_attributes.texture.A), 0.016, 0.001)
	assert_almost_eq(float(adjusted.dish_attributes.temperature_c), 40.8, 0.01)
	assert_eq(dish.dish_attributes.flavor[6][0], 20)
	for _step in 16:
		crew.record_served_order()
	var mastered: Dictionary = crew.apply_dish(dish, customer)
	assert_almost_eq(float(mastered.dish_attributes.flavor[6][0]), 34.0, 0.01)
	assert_almost_eq(float(mastered.dish_attributes.aroma.fresh), 18.0, 0.01)
	assert_almost_eq(float(mastered.dish_attributes.texture.A), 0.08, 0.001)
	assert_almost_eq(float(mastered.dish_attributes.temperature_c), 44.0, 0.01)

func test_layout_roundtrip_and_wage_ledger() -> void:
	var catalog := TDRestaurantCatalog.new()
	assert_true(catalog.load_file().ok)
	var layout := catalog.default_layout()
	assert_false(layout.to_dict().has("crew"))
	assert_eq(layout.crew.hire("waiter-ning").code, "HIRED")
	for _step in 4:
		layout.crew.record_served_order()
	var saved := layout.to_dict()
	var loaded := TDRestaurantLayout.import_dict(saved, catalog)
	assert_not_null(loaded)
	assert_eq(loaded.crew.export_ids(), ["waiter-ning"])
	assert_eq(loaded.crew.level_of("waiter-ning"), 2)
	assert_eq(loaded.crew.xp_of("waiter-ning"), 4)
	var parser := JSON.new()
	assert_eq(parser.parse(JSON.stringify(saved)), OK)
	var from_json := TDRestaurantLayout.import_dict(parser.data, catalog)
	assert_not_null(from_json)
	assert_eq(from_json.crew.xp_of("waiter-ning"), 4)
	var fractional: Dictionary = (parser.data as Dictionary).duplicate(true)
	fractional["crew"] = [{"id": "waiter-ning", "xp": 4.5}]
	assert_null(TDRestaurantLayout.import_dict(fractional, catalog))
	var legacy: Dictionary = saved.duplicate(true)
	legacy["crew"] = ["waiter-ning"]
	var plain := TDRestaurantLayout.import_dict(legacy, catalog)
	assert_not_null(plain)
	assert_eq(plain.crew.level_of("waiter-ning"), 1)
	saved["crew"] = ["missing-person"]
	assert_null(TDRestaurantLayout.import_dict(saved, catalog))
	saved["crew"] = [{"id": "waiter-ning", "xp": 17}]
	assert_null(TDRestaurantLayout.import_dict(saved, catalog))
	var service := TDServiceCatalog.new()
	assert_true(service.load_file().ok)
	var shop := TDShopSession.new(service, "crew-test", 7, ["service.tomato_egg"])
	shop.crew = loaded.crew
	assert_almost_eq(shop.guest_patience(180.0), 180.0, 0.01)
	shop.crew.hire("cook-zhou")
	assert_almost_eq(shop.guest_patience(180.0), 189.0, 0.01)
	var before := int(shop.snapshot().money_cents)
	assert_eq(shop.pay_wage(2900, "crew:waiter-ning:1").code, "PAID")
	assert_eq(int(shop.snapshot().money_cents), before - 2900)
	assert_true(shop.validate_save(shop.snapshot()).ok)
	assert_eq(shop.pay_wage(int(shop.snapshot().money_cents) + 1, "too-much").code, "BROKE")

func test_hired_cook_finishes_the_order_and_the_faster_cook_is_sooner() -> void:
	var service := TDServiceCatalog.new()
	assert_true(service.load_file().ok)
	var plain := _open_crewed_shop(service, "crew-plain", "cook-he")
	var paced := _open_crewed_shop(service, "crew-paced", "cook-zhou")
	var tipped := _open_crewed_shop(service, "crew-tipped", "cook-zhou")
	assert_true(tipped.crew.hire("waiter-tao").ok)
	var plain_id := str(plain.active_orders()[0].id)
	var paced_id := str(paced.active_orders()[0].id)
	var tipped_id := str(tipped.active_orders()[0].id)
	assert_eq(plain.order(plain_id).status, "WAITING")
	plain.advance(0.05)
	paced.advance(0.05)
	tipped.advance(0.05)
	assert_eq(plain.order(plain_id).status, "COOKING")
	assert_eq(plain.crew_work("cook-he"), "做菜")
	var soon := paced.crew.cook_seconds("cook-zhou")
	assert_lt(soon, TDRestaurantCrew.COOK_SEC)
	plain.advance(soon)
	paced.advance(soon)
	tipped.advance(soon)
	assert_eq(plain.order(plain_id).status, "COOKING", plain.take_crew_note())
	assert_eq(paced.order(paced_id).status, "SERVED", paced.take_crew_note())
	assert_eq(tipped.order(tipped_id).status, "SERVED", tipped.take_crew_note())
	assert_lt(paced.available("tomato"), 1000)
	assert_gt(float(paced.order(paced_id).score.satisfaction), 60.0)
	assert_gt(int(tipped.order(tipped_id).tip_cents), int(paced.order(paced_id).tip_cents))
	plain.advance(TDRestaurantCrew.COOK_SEC)
	var done := plain.take_crew_note()
	assert_eq(plain.order(plain_id).status, "SERVED", done)
	assert_false(done.is_empty())

func _open_crewed_shop(service: TDServiceCatalog, run_id: String, cook_id: String) -> TDShopSession:
	var shop := TDShopSession.new(service, run_id, 11)
	var crew := TDRestaurantCrew.new()
	assert_true(crew.hire(cook_id).ok)
	shop.crew = crew
	assert_true(shop.buy(shop.offer("service.tomato_egg").stock, "buy").ok)
	assert_true(shop.open_day().ok)
	shop.advance(1.0)
	assert_eq(shop.active_orders().size(), 1)
	return shop
