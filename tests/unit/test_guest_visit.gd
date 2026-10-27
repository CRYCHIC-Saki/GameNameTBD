extends GutTest

func test_visit_phases_follow_the_shop_order() -> void:
	assert_eq(TDGuestVisit.phase_of("WAITING", false, 0.0), "approach")
	assert_eq(TDGuestVisit.phase_of("COOKING", true, 0.0), "wait_serve")
	assert_eq(TDGuestVisit.phase_of("SERVED", true, 0.0), "eat")
	assert_eq(TDGuestVisit.phase_of("SERVED", true, 6.0), "pay")
	assert_eq(TDGuestVisit.phase_of("SERVED", true, 8.2), "leave")
	assert_eq(TDGuestVisit.phase_of("TIMED_OUT", false, 0.0), "leave")
	assert_eq(TDGuestVisit.phase_of("REJECTED_STOCK", true, 0.0), "leave")
	assert_eq(TDGuestVisit.phase_of("CANCELLED", true, 3.0), "leave")
	var eating := TDGuestVisit.caption("蛋炒饭", "SERVED", "eat", 0, 88.0, 1300, 0)
	assert_true(eating.contains("88"))
	var refunded := TDGuestVisit.caption("蛋炒饭", "SERVED", "pay", 0, 20.0, 0, 1200)
	assert_true(refunded.contains("退款"))
	var text := TDGuestVisit.inspect_text("蛋炒饭", "街坊", "SERVED", "pay", 0, 1200, 90.0, 1500, 0, PackedStringArray(["比较后去本店"]), 30.0, "")
	assert_true(text.contains("已经记入账本") or text.contains("净收"))
	assert_true(text.contains("不改这一单"))
	var waiting := TDGuestVisit.inspect_text("蛋炒饭", "街坊", "WAITING", "wait_serve", 40, 1200, -1.0, 0, 0, PackedStringArray(), 30.0, "")
	assert_true(waiting.contains("送达后才记账"))

func test_comparison_note_and_interior_shift_are_stable() -> void:
	var note := TDEconomicDemand.comparison_note([
		{"store_id": "player", "probability": 0.5, "recipe_id": "a"},
		{"store_id": "npc", "probability": 0.25, "recipe_id": "b"},
		{"store_id": "outside", "probability": 0.25, "recipe_id": ""},
	], {"store_id": "player"})
	assert_eq(note, "比较后去本店：本店50%，竞品合计25%，在家25%")
	var economy := TDWorldEconomy.new({"tomato": 200}, "chengdu", 101)
	assert_true(economy.error.ok)
	var group: Dictionary = economy.config.groups[0]
	var menu := [{"id": "service.tomato_egg", "family_id": "service.tomato_egg", "price_cents": 1300, "reference_cents": 1300, "food": 0.7, "familiarity": 0.7, "available": true, "taste": {"sweet": 0.5}, "culture": "chinese"}]
	var plain: float = float(economy.player_store(menu, 0, group).decor_match)
	economy.interior_effect = 30.0
	assert_almost_eq(float(economy.player_store(menu, 0, group).decor_match), plain, 0.0001)
	economy.interior_effect = 110.0
	assert_almost_eq(float(economy.player_store(menu, 0, group).decor_match), plain + 0.25, 0.0001)
	economy.interior_effect = 0.0
	assert_almost_eq(float(economy.player_store(menu, 0, group).decor_match), plain - 0.25, 0.0001)
	economy.interior_effect = -1.0
	assert_almost_eq(float(economy.player_store(menu, 0, group).decor_match), plain, 0.0001)
	var before := _player_chance(TDEconomicDemand.choices(group, [economy.player_store(menu, 0, group)], economy.config.outside_utility, economy.config.menu_tau))
	economy.interior_effect = 110.0
	var after := _player_chance(TDEconomicDemand.choices(group, [economy.player_store(menu, 0, group)], economy.config.outside_utility, economy.config.menu_tau))
	assert_gt(after, before)
	var template: Array = [{"requirements": []}]
	var first := economy.arrivals(0, menu, 0, 3, template, 240)
	if not first.is_empty():
		var reasons: Array = first[0].intent.reasons
		assert_eq(reasons[0], "预算范围内")
		assert_true(str(reasons.back()).begins_with("比较后去"))
		assert_true(TDMealIntent.validate(first[0].intent).ok)

func _player_chance(rows: Array) -> float:
	var total := 0.0
	for item: Variant in rows:
		var row: Dictionary = item
		if str(row.store_id) == "player":
			total += float(row.probability)
	return total
