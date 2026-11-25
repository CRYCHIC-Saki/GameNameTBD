extends GutTest

# Produced by the five-region game using the real construction, supply and shipping APIs.
const BEFORE := "res://tests/fixtures/five-region-profile.json.gz"

func old_slot() -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes(BEFORE).decompress_dynamic(2000000, FileAccess.COMPRESSION_GZIP)
	return JSON.parse_string(bytes.get_string_from_utf8())

func test_three_towns_share_travel_recruitment_supply_and_research() -> void:
	var profile := TDGameProfile.new()
	assert_true(profile.error.ok,profile.error.code)
	assert_eq(TDTravelCatalog.IDS, ["chengdu","tokyo","paris"])
	for town: String in TDTravelCatalog.IDS:
		assert_has(profile.commerce.state.markets,town)
		assert_has(profile.suppliers.config.towns,town)
		assert_false(profile.employees.market_rows(town,"manager").is_empty())
	assert_eq(profile.commerce.state.markets.size(),3)
	assert_eq(profile.research.catalog.nodes.size(),60)
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
