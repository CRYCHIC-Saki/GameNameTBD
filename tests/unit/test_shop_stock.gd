extends GutTest

func _shop() -> TDShopSession:
	var catalog:=TDServiceCatalog.new()
	assert_true(catalog.load_file().ok)
	assert_true(TDResearchRuntime.install(catalog).ok)
	return TDShopSession.new(catalog,"stock-test",42,["service.tomato_egg","study.egg_fried_rice"])

func test_purchase_gate_tracks_unlocks_and_all_condiments() -> void:
	var shop:=_shop()
	assert_true(shop.purchasable("tomato"));assert_true(shop.purchasable("rice"))
	assert_false(shop.purchasable("chicken"));assert_true(shop.purchasable("bean_paste"))
	var before:=shop.snapshot()
	assert_eq(shop.buy({"chicken":1000,"tomato":1000},"blocked").code,"INGREDIENT_LOCKED")
	assert_eq(shop.snapshot(),before)
	assert_true(shop.grant_recipe("service.kungpao").ok)
	assert_true(shop.buy({"chicken":1000,"peanut":1000},"allowed").ok)

func test_batches_use_earliest_expiry_and_reconcile() -> void:
	var lots:=TDFoodStock.migrate({"tomato":0},1,{})
	TDFoodStock.add(lots,"tomato",700,2,9);TDFoodStock.add(lots,"tomato",500,1,9)
	TDFoodStock.take(lots,"tomato",600)
	assert_eq(lots.tomato,[{"units":600,"stored_on":2,"expires_on":11}])
	assert_true(TDFoodStock.valid(lots,{"tomato":600},2))
	assert_false(TDFoodStock.valid(lots,{"tomato":601},2))
	assert_eq(TDFoodStock.expired(lots,10),{})
	assert_eq(TDFoodStock.expired(lots,11),{"tomato":600})

func test_expiry_runs_once_at_day_boundary_and_survives_save() -> void:
	var shop:=_shop()
	shop.stock_rules.tomato.shelf_days=1
	assert_true(shop.buy({"tomato":2000,"salt":1000},"fresh").ok)
	assert_true(shop.open_day().ok);assert_true(shop.close_early().ok)
	assert_true(shop.next_day(1).ok)
	assert_eq(shop.available("tomato"),0);assert_eq(shop.available("salt"),1000)
	var state:=shop.snapshot()
	assert_true(shop.validate_save(state).ok)
	assert_false(shop.next_day(1).ok);assert_eq(shop.snapshot(),state)
	var other:=_shop();assert_true(other.restore(state).ok);assert_eq(other.snapshot(),state)

func test_old_batchless_save_migrates_without_changing_balance() -> void:
	var shop:=_shop();assert_true(shop.buy({"tomato":1500},"old").ok)
	var old:=shop.snapshot()
	for key: String in ["stock_version","inventory_lots","mastery_version","mastery","mastery_dishes"]: old.erase(key)
	var restored:=_shop();assert_true(restored.restore(old).ok)
	assert_eq(restored.available("tomato"),1500)
	assert_eq(restored.snapshot().money_cents,old.money_cents)
	assert_eq(restored.stock_info("tomato").expires_on,10)
	var broken:=restored.snapshot();broken.inventory_lots.tomato[0].units=1
	assert_eq(restored.restore(broken).code,"INVALID_STOCK_BATCHES")

func test_mastery_uses_actual_performance_threshold_and_idempotence() -> void:
	var shop:=_shop();assert_true(shop.open_day().ok)
	var dish: Dictionary={"session_id":shop.day_namespace()+"pan","recipe_id":"service.tomato_egg","dish_id":"a","state":"plated","missing_required":[],"performance_score":79.99}
	assert_eq(shop.observe_mastery(dish).code,"MASTERY_BELOW_TARGET")
	for i: int in 4:
		dish.dish_id="dish-%d"%i;dish.performance_score=100.0
		assert_eq(shop.observe_mastery(dish).code,"MASTERY_GAINED")
		assert_eq(shop.observe_mastery(dish).code,"MASTERY_ALREADY_RECORDED")
		assert_eq(shop.mastery("service.tomato_egg").automatic_available,i==3)
	assert_eq(shop.mastery("service.tomato_egg").points,400.0)
	dish.dish_id="automatic";dish.production_mode="automatic"
	assert_false(shop.observe_mastery(dish).ok)
	assert_eq(shop.mastery("service.tomato_egg").points,400.0)
	assert_true(shop.close_early().ok)
	var restored:=_shop();assert_true(restored.restore(shop.snapshot()).ok)
	assert_eq(restored.mastery("service.tomato_egg").points,400.0)
	assert_eq(_shop().mastery("service.tomato_egg").points,0.0)
	var edge:=_shop();edge.open_day();dish.production_mode="manual";dish.session_id=edge.day_namespace()+"edge"
	for i: int in 4:
		dish.dish_id="edge-%d"%i;dish.performance_score=99.0 if i==3 else 100.0
		assert_true(edge.observe_mastery(dish).ok)
	assert_eq(edge.mastery("service.tomato_egg").points,399.0)
	assert_false(edge.mastery("service.tomato_egg").automatic_available)
