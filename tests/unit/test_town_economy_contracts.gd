extends GutTest

func customer_data() -> Dictionary:
	var tastes: Dictionary = {}
	for taste: String in TDEconomicCustomer.TASTES: tastes[taste] = [20.0, 40.0, 30.0, 10.0]
	return {"schema_version":1, "id":"resident:test:17", "home_town_id":"guangzhou", "origin_id":"residential", "group_id":"local", "budget_cents":2000, "hard_budget_cents":2500, "taste":tastes, "familiarity":{"chinese":0.8}, "declared_requirements":[{"id":"sweet_front", "label":"前味甜度", "kind":"flavor", "taste":1, "slot":0, "min":20.0, "max":40.0, "weight":1.0, "scale":40.0}]}

func cell_data() -> Dictionary:
	return {"schema_version":1, "id":"guangzhou:1:2", "town_id":"guangzhou", "x":1, "y":2, "zone_id":"residential", "parcel_id":"plot.home", "land_value_cents":10000, "rent_quote_cents_per_day":10, "visibility":0.4, "attractiveness":0.6, "reachable":true, "travel_minutes":{"residential":3.0}}

func test_customer_and_nested_preferences_are_independent() -> void:
	var template := customer_data()
	var a := TDEconomicCustomer.new(template)
	var b := TDEconomicCustomer.new(template)
	assert_true(a.error.ok)
	template.taste.sweet[0] = 99.0
	var snapshot := a.snapshot()
	snapshot.familiarity.chinese = 0.0
	snapshot.declared_requirements[0].weight = 0.0
	assert_eq(a.snapshot().taste.sweet[0], 20.0)
	assert_eq(b.snapshot().taste.sweet[0], 20.0)
	assert_eq(a.snapshot().familiarity.chinese, 0.8)
	assert_eq(a.snapshot().declared_requirements[0].weight, 1.0)
	assert_eq(a.budget_cents, 2000)

func test_same_surface_different_cells_keep_separate_quotes() -> void:
	var template := cell_data()
	var a := TDEconomicCell.new(template)
	template.x = 2
	template.id = "guangzhou:2:2"
	template.rent_quote_cents_per_day = 30
	var b := TDEconomicCell.new(template)
	assert_true(a.error.ok)
	assert_true(b.error.ok)
	assert_ne(a.id, b.id)
	assert_eq(a.snapshot().rent_quote_cents_per_day, 10)
	assert_eq(b.snapshot().rent_quote_cents_per_day, 30)
	var snapshot := a.snapshot()
	snapshot.travel_minutes.residential = 1000.0
	assert_eq(a.snapshot().travel_minutes.residential, 3.0)

func test_contracts_reject_negative_money_missing_identity_and_nonfinite_values() -> void:
	var person := customer_data()
	person.budget_cents = -1
	assert_false(TDEconomicCustomer.validate(person).ok)
	person = customer_data()
	person.id = ""
	assert_false(TDEconomicCustomer.validate(person).ok)
	person = customer_data()
	person.household_id = 17
	assert_eq(TDEconomicCustomer.validate(person).code,"INVALID_HOUSEHOLD_ID")
	person = customer_data()
	person.taste.umami[1] = NAN
	assert_false(TDEconomicCustomer.validate(person).ok)
	person = customer_data()
	person.declared_requirements[0].kind = "invented"
	assert_false(TDEconomicCustomer.validate(person).ok)
	person = customer_data()
	person.declared_requirements.append(person.declared_requirements[0].duplicate(true))
	assert_eq(TDEconomicCustomer.validate(person).code, "DUPLICATE_REQUIREMENT")
	var cell := cell_data()
	cell.visibility = INF
	assert_false(TDEconomicCell.validate(cell).ok)
	cell = cell_data()
	cell.x = 2
	assert_eq(TDEconomicCell.validate(cell).code, "CELL_ID_MISMATCH")

func test_outside_intent_has_no_fake_dish_and_cannot_mutate_its_source() -> void:
	var raw := {"schema_version":1, "opportunity_id":"guangzhou:d1:s0:n17", "customer_id":"resident:test:17", "town_id":"guangzhou", "origin_id":"residential", "group_id":"local", "store_id":"outside", "recipe_id":"", "day":1, "slot":0, "quoted_cents":0, "travel_minutes":0.0, "expected_wait_minutes":0.0, "patience_seconds":0.0, "reasons":["在家吃"]}
	var intent := TDMealIntent.new(raw)
	assert_true(intent.error.ok)
	raw.reasons[0] = "changed"
	assert_eq(intent.snapshot().reasons, ["在家吃"])
	raw.recipe_id = "service.tomato_egg"
	assert_eq(TDMealIntent.validate(raw).code, "INVALID_INTENT_RECIPE")
