extends GutTest

# Produced by the five-region game using the real construction, supply and shipping APIs.
const BEFORE := "res://tests/fixtures/five-region-profile.json.gz"

func old_slot() -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes(BEFORE).decompress_dynamic(2000000, FileAccess.COMPRESSION_GZIP)
	return JSON.parse_string(bytes.get_string_from_utf8())

func test_old_three_town_slot_removes_retired_menu_without_changing_accounts() -> void:
	var profile := TDGameProfile.new()
	profile.slot_id = "slot-01"
	assert_true(profile.shop.world_adjustment(300000,"fixture-funding","test").ok)
	var opened := profile.branches.open_store("chengdu",[32,11,3,4],"cn","","legacy-branch")
	assert_true(opened.ok,opened.code)
	if not opened.ok:
		profile.close()
		return
	var branch_id: String = opened.data.store_id
	var original := profile.snapshot()
	var shop: Dictionary = original.shop
	for id: String in TDRetiredRecipes.SERVICE_IDS:
		shop.menu[id] = {"enabled":true,"price_cents":1200}
		shop.unlocked.append(id)
		shop.fame[id] = 35
		shop.mastery[id] = 400.0
	original.research.legacy_ids.append_array(TDRetiredRecipes.WORLD_IDS)
	original.world.pantry_dish = "qiguoji"
	original.branches.stores[branch_id].menu = [{"id":"service.qiguoji","name":"汽锅鸡","price_cents":1200,"reference_cents":2000,"ingredients":{"mushroom":1000}}]
	original.branches.stores[branch_id].paused = false
	original.menu_supply.plans["player_diner"] = {"service.qiguoji":10,"service.tomato_egg":4}
	original.menu_supply.plans[branch_id] = {"service.qiguoji":5}
	original.menu_supply.portions["player_diner"] = {"service.pepper_pork":3}
	var restored := profile.restore(original)
	assert_true(restored.ok,restored.code)
	if restored.ok:
		var current := profile.snapshot()
		for id: String in TDRetiredRecipes.SERVICE_IDS:
			assert_does_not_have(current.shop.menu,id)
			assert_does_not_have(current.shop.unlocked,id)
			assert_does_not_have(current.shop.fame,id)
			assert_does_not_have(current.shop.mastery,id)
		assert_has(original.shop.menu,"service.qiguoji")
		assert_eq(current.shop.inventory,shop.inventory)
		assert_eq(current.shop.ledger,shop.ledger)
		assert_eq(current.shop.money_cents,shop.money_cents)
		assert_eq(current.research.legacy_ids,[])
		assert_eq(current.world.pantry_dish,"mapodoufu")
		assert_eq(current.branches.stores[branch_id].menu,[])
		assert_true(current.branches.stores[branch_id].paused)
		assert_eq(current.branches.stores[branch_id].construction,original.branches.stores[branch_id].construction)
		assert_does_not_have(current.menu_supply.plans,branch_id)
		assert_eq(current.menu_supply.plans["player_diner"],{"service.tomato_egg":4})
		assert_eq(current.menu_supply.portions,{})
		assert_true(profile.restore(current).ok)
		assert_true(profile.branches.configure_store(branch_id,[{"id":"service.tomato_egg","price_cents":1800}],10000).ok)
	profile.close()

func test_three_towns_share_travel_recruitment_supply_and_research() -> void:
	var profile := TDGameProfile.new()
	assert_true(profile.error.ok,profile.error.code)
	assert_eq(TDTravelCatalog.IDS, ["chengdu","tokyo","paris"])
	for town: String in TDTravelCatalog.IDS:
		assert_has(profile.commerce.state.markets,town)
		assert_has(profile.suppliers.config.towns,town)
		assert_false(profile.employees.market_rows(town,"manager").is_empty())
	assert_eq(profile.commerce.state.markets.size(),3)
	assert_eq(profile.research.catalog.nodes.size(),61)
	for town: String in ["bangkok","mexico_city"]:
		assert_false(profile.commerce.open_route(town,"retired:"+town).ok)
		assert_false(profile.suppliers.quote(town,"player_diner",{"salt":1000}).ok)
		assert_true(profile.employees.market_rows(town,"manager").is_empty())
	profile.close()

func test_real_slot_refund_is_itemised_by_actual_unfulfilled_cost_and_paid_once() -> void:
	var profile := TDGameProfile.new()
	var original := old_slot()
	var cumin := profile.world.pantry.store(profile.world.ingredients.get_item("cumin"),"dry_store",1)
	profile.world.pantry.store({"id":"laksa_paste","name":"叻沙酱","category":"spice"},"dry_store",1)
	original.world.pantry=profile.snapshot().world.pantry
	var before := original.duplicate(true)
	var result := profile.restore(original)
	assert_true(result.ok,result.code)
	assert_eq(original,before)
	if result.ok:
		var saved := profile.snapshot()
		assert_eq(saved.world.pantry.lots,[cumin],"The Chinese pantry keeps its spice when the retired-region lots are cleared")
		assert_eq(int(saved.shop.money_cents),int(original.shop.money_cents)+28100+56+111)
		assert_eq(saved.shop.ledger.size(),original.shop.ledger.size()+1)
		assert_true(saved.branches.stores.is_empty())
		assert_true(saved.economy.shipments.is_empty())
		assert_true(saved.suppliers.orders.is_empty())
		assert_eq(saved.research.cuisines,["cn"])
		assert_eq(saved.shop.inventory.egg,original.shop.inventory.egg)
		assert_eq(saved.economy.society.bank,original.economy.society.bank)
		assert_true(TDGameProfile.validate_save(saved).ok)
		assert_true(profile.restore(saved).ok)
		assert_false(profile.regions_settled_on_load)
		assert_eq(profile.shop.snapshot().money_cents,saved.shop.money_cents)
	profile.close()

func test_delivered_part_of_mixed_order_and_unfunded_site_receive_no_refund() -> void:
	var raw := old_slot()
	var order: Dictionary = raw.suppliers.orders[0]
	var first: Dictionary = order.jobs[0]
	first.cost_cents=36
	var delivered := first.duplicate(true)
	delivered.id=order.id+":1"
	delivered.cost_cents=20
	delivered.elapsed=delivered.seconds
	delivered.delivered=true
	order.jobs.append(delivered)
	raw.shop.seen["supply-arrival:"+delivered.id]=true
	var place: Dictionary = raw.branches.stores.values()[0]
	place.construction={"schema_version":1,"kind":"unverified","paid_day":0,"ready_day":2,"paid_cents":0,"token":""}
	var result := TDGameProfile.RetiredRegions.convert(raw)
	assert_true(result.ok,result.code)
	if result.ok:
		assert_eq(int(result.data.shop.money_cents)-int(raw.shop.money_cents),36+111)

func test_invalid_payment_or_duplicate_claim_cannot_be_migrated() -> void:
	var raw := old_slot()
	raw.suppliers.orders.append(raw.suppliers.orders[0].duplicate(true))
	assert_false(TDGameProfile.validate_save(raw).ok)
	raw = old_slot()
	raw.economy.shipments[0].total_cents += 1
	assert_false(TDGameProfile.validate_save(raw).ok)

func test_load_menu_backs_up_original_and_three_passenger_ports_work() -> void:
	var app: TDApplication = load("res://src/app/main.tscn").instantiate()
	app.settings_path = "res://artifacts/three-town-slots/%d/settings.json" % Time.get_ticks_usec()
	add_child_autofree(app)
	await wait_process_frames(1)
	var shell := app.game_shell
	shell.automatic_time = false
	var store := shell.slots
	assert_true(store.save_slot("slot-01",old_slot()).ok)
	var source := store.path_for("slot-01")
	var original := FileAccess.get_file_as_bytes(source)
	assert_eq(store.latest(),"slot-01")
	var result := shell.load_game("slot-01")
	assert_true(result.ok,result.code)
	if result.ok:
		assert_eq(FileAccess.get_file_as_bytes(source+".before-three-towns.bak"),original)
		var reopened := shell.load_game("slot-01")
		assert_true(reopened.ok,reopened.code)
		assert_eq(int(shell.profile.shop.snapshot().money_cents),330000)
		shell.guide.dialogue.finish_now()
		shell.profile.story.beat="done"
		shell.travel("town")
		shell.town.spawn_at_harbor()
		assert_false(shell.voyage("bangkok").ok)
		assert_false(shell.voyage("mexico_city").ok)
		for town: String in ["tokyo","paris","chengdu"]:
			var sailing := shell.voyage(town)
			assert_true(sailing.ok,sailing.code)
			assert_eq(shell.visiting_town,town)
		var map := TDTravelMapView.new()
		map.configure(shell.profile)
		assert_eq(map.maps.size(),3)
		assert_eq(map.maps.keys(),TDTravelCatalog.IDS)
		map.free()
	shell._close_dialog()
	shell._dispose_game()
	await wait_process_frames(2)

func test_old_factory_refunds_only_remaining_portions() -> void:
	var raw := old_slot()
	raw.world.factory_jobs["chengdu:factory"]=[{"item_id":"fishsauce","qty":1,"cost":12,"unit_hours":1,"total_hours":3}]
	var shop: Dictionary = raw.shop
	shop.serial += 1
	shop.money_cents -= 1200
	shop.seen["factory-old"]=true
	shop.ledger.append({"id":"%s:txn-%d"%[shop.run_id,shop.serial],"reference":"factory-old","cents":-1200,"kind":"world_adjustment","day":1,"extra":{"label":"工厂生产"},"inventory_delta":{}})
	raw.economy.cost_cursor += 1
	var result := TDGameProfile.RetiredRegions.convert(raw)
	assert_true(result.ok,result.code)
	if result.ok:
		assert_eq(int(result.data.shop.money_cents)-int(shop.money_cents),28267+400)
		assert_true(result.data.world.factory_jobs.is_empty())
