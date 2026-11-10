extends GutTest
var profiles: Array[TDGameProfile]=[]

func test_installed_catalog_reloads_and_still_rejects_invalid_costs() -> void:
	var original:=TDServiceCatalog.new();assert_true(original.load_file().ok)
	var before: Dictionary=original.config.duplicate(true)
	var restored:=TDServiceCatalog.new()
	var result:=restored.load_data(before)
	assert_true(result.ok,result.code)
	assert_eq(restored.config,before)
	assert_eq(restored.cooking.data(),original.cooking.data())
	for id: String in ["tomato","miso","unknown-material"]:
		var invalid: Dictionary=before.duplicate(true)
		invalid.costs[id]=0 if id!="unknown-material" else 100
		assert_eq(TDServiceCatalog.new().load_data(invalid).code,"INVALID_COST",id)
	assert_eq(original.config,before,"Reload and failed validation must not mutate the source")

func profile() -> TDGameProfile:
	var p:=TDGameProfile.new();profiles.append(p);p.slot_id="slot-01"
	assert_true(p.error.ok,p.error.code)
	p.shop.world_adjustment(300000,"materials-fixture","test funds")
	return p
func after_each() -> void:
	for p: TDGameProfile in profiles: p.close()
	profiles.clear()

func test_every_atlas_recipe_has_explicit_foods_regions_stock_and_preserved_identity() -> void:
	var data:=TDMaterialCatalog.data();assert_true(TDMaterialCatalog.validate(data).ok)
	var atlas: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/research/recipe_atlas.json"))
	var manifest: Dictionary={}
	for row: Dictionary in data.recipes: manifest[row.id]=row
	assert_eq(manifest.size(),100);assert_eq(data.items.size(),148)
	for recipe: Dictionary in atlas.recipes:
		assert_has(manifest,recipe.id)
		assert_eq(manifest[recipe.id].cuisine_id,recipe.cuisine_id)
		assert_false(str(manifest[recipe.id].source_text).is_empty())
		for id: String in manifest[recipe.id].ingredients+manifest[recipe.id].seasonings:
			assert_has(data.items,id);assert_false(data.items[id].supply_regions.is_empty())
	assert_eq(TDMaterialCatalog.name_for("rice"),"熟米饭")
	assert_eq(TDMaterialCatalog.name_for("raw_rice"),"生大米")
	assert_eq(TDMaterialCatalog.name_for("wine"),"料酒")
	assert_eq(TDMaterialCatalog.name_for("pepper"),"花椒")
	for id: String in ["steam","charcoal","sour_sweet"]: assert_false(data.items.has(id))
	var copy:=TDMaterialCatalog.item("miso");copy.supply_regions.clear();copy.definition.base_tastes[0]=999
	assert_eq(TDMaterialCatalog.item("miso").supply_regions,["tokyo"])
	assert_ne(float(TDMaterialCatalog.definition("miso").base_tastes[0]),999.0)

func test_registry_rejects_duplicates_unknown_regions_references_and_bad_stock() -> void:
	for mutation: int in 10:
		var data:=TDMaterialCatalog.data()
		match mutation:
			0: data.revision=99
			1: data.items.salt.supply_regions=["moon"]
			2: data.items.salt.supply_regions=["tokyo","tokyo"]
			3: data.recipes.append(data.recipes[0].duplicate(true))
			4: data.recipes[0].seasonings.append("not_food")
			5: data.items.salt.stock.shelf_days=-1
			6: data.items.miso.unlock_cuisines=[]
			7: data.items.miso.unlock_cuisines=["moon"]
			8: data.items.miso.unlock_cuisines=["jp","jp"]
			9: data.items.miso.unlock_cuisines=["eu"]
		assert_false(TDMaterialCatalog.validate(data).ok)

func test_supplier_regions_apply_to_catalogue_quote_and_new_lines_atomically() -> void:
	var p:=profile();var n:=p.suppliers
	assert_true(p.research.recommend_cuisine("materials-jp","jp").ok)
	assert_true(p.research.recommend_cuisine("materials-sea","sea").ok)
	for town: String in TDSupplierNetwork.TOWNS:
		var rows:=n.catalogue(town)
		assert_true(rows.any(func(row:Dictionary)->bool:return row.id=="salt"))
		for row: Dictionary in rows: assert_true(TDMaterialCatalog.supplies(town,row.id))
	assert_true(n.catalogue("tokyo").any(func(row:Dictionary)->bool:return row.id=="miso"))
	assert_false(n.catalogue("chengdu").any(func(row:Dictionary)->bool:return row.id=="miso"))
	assert_true(n.quote("bangkok","player_diner",{"fishsauce":1000}).ok)
	var before:=p.snapshot()
	assert_false(n.order("chengdu","player_diner",{"salt":1000,"fishsauce":1000},"wrong-origin").ok)
	assert_false(n.create_line("chengdu","player_diner","miso",1000).ok)
	assert_eq(p.snapshot(),before)
	assert_true(n.create_line("tokyo","player_diner","miso",1000).ok)
	n.advance_game_minutes(300)
	assert_eq(p.shop.available("miso"),1000)
	assert_eq(p.shop.available("fishsauce"),0)
	assert_eq(int(p.commerce.cash_audit(int(p.shop.snapshot().money_cents)).difference_cents),0)

func test_locked_primary_materials_follow_recipe_unlocks_not_seasoning_access() -> void:
	var p:=profile()
	assert_eq(p.shop.material_recipe_unlocks,["C01","C02"])
	assert_false(p.shop.purchasable("udon"));assert_false(p.shop.purchasable("miso"))
	assert_true(p.research.recommend_cuisine("materials-jp","jp").ok)
	assert_true(p.shop.purchasable("miso"));assert_false(p.shop.purchasable("udon"))
	# Future unlocked-node projection fixture; J03 does not yet have a playable chart.
	p.shop.material_recipe_unlocks.append("J03")
	assert_true(p.shop.purchasable("udon"))
	assert_true(p.suppliers.catalogue("tokyo").any(func(row:Dictionary)->bool:return row.id=="udon"))
	assert_false(p.suppliers.catalogue("chengdu").any(func(row:Dictionary)->bool:return row.id=="udon"))
	assert_false(p.world.factory_products("seasoning").any(func(row:Dictionary)->bool:return row.id=="miso"))

func test_old_paid_out_of_region_jobs_are_kept_but_new_orders_are_rejected() -> void:
	var p:=profile();var n:=p.suppliers
	assert_true(n.order("chengdu","player_diner",{"bean_paste":1000},"old-paid").ok)
	var old:=p.snapshot()
	# Pre-D069 allowed bean paste from Tokyo. Its paid amount/time remain authoritative.
	old.suppliers.orders[0].town_id="tokyo"
	var restored:=profile();var result:=restored.restore(old);assert_true(result.ok,result.code)
	var money: int=int(restored.shop.snapshot().money_cents)
	restored.suppliers.advance(100000)
	assert_eq(restored.shop.available("bean_paste"),1000)
	assert_eq(int(restored.shop.snapshot().money_cents),money)
	assert_false(restored.suppliers.order("tokyo","player_diner",{"bean_paste":1000},"new-denied").ok)
	var done:=restored.snapshot();restored.suppliers.advance(100000);assert_eq(restored.snapshot(),done)

func test_old_profile_extends_only_new_materials_and_saves_roundtrip_in_isolated_slot() -> void:
	var p:=profile();assert_true(p.buy({"tomato":1000}).ok)
	var old:=p.snapshot();old.shop.erase("material_version");old.economy.erase("material_version")
	for id: String in p.service.config.material_cost_ids:
		old.shop.inventory.erase(id);old.shop.inventory_lots.erase(id)
		for town: String in old.economy.markets:
			for field: String in ["stock","price","premium","opening"]: old.economy.markets[town][field].erase(id)
	var loaded:=profile();var result:=loaded.restore(JSON.parse_string(JSON.stringify(old)));assert_true(result.ok,result.code)
	if not result.ok: return
	assert_eq(loaded.shop.available("miso"),0);assert_eq(loaded.shop.available("tomato"),1000)
	assert_eq(int(loaded.shop.snapshot().money_cents),int(p.shop.snapshot().money_cents))
	for town: String in old.economy.markets:
		assert_eq(int(loaded.commerce.state.markets[town].stock.tomato),int(old.economy.markets[town].stock.tomato))
		assert_eq(int(loaded.commerce.state.markets[town].price.tomato),int(old.economy.markets[town].price.tomato))
		assert_has(loaded.commerce.state.markets[town].stock,"miso")
	var store:=TDProfileStore.new("res://artifacts/regional-materials/slots/%d"%Time.get_ticks_usec(),TDGameProfile.validate_save)
	assert_true(loaded.research.recommend_cuisine("saved-jp","jp").ok)
	loaded.persistence=store.save_slot;assert_true(loaded.save().ok)
	var saved:=store.load_slot("slot-01");assert_true(saved.ok,saved.code)
	var final_profile:=profile();var final_result:=final_profile.restore(saved.data);assert_true(final_result.ok,final_result.code)
	assert_eq(final_profile.shop.snapshot(),loaded.shop.snapshot())
	assert_true(final_profile.shop.purchasable("miso"));assert_false(final_profile.shop.purchasable("fishsauce"))
	assert_eq(JSON.parse_string(JSON.stringify(final_profile.commerce.snapshot())),JSON.parse_string(JSON.stringify(loaded.commerce.snapshot())))
	var bad:=loaded.snapshot();bad.shop.material_version=99;assert_false(TDGameProfile.validate_save(bad).ok)
	bad=loaded.snapshot();bad.economy.material_version=99;assert_false(TDGameProfile.validate_save(bad).ok)
	bad=loaded.snapshot();bad.shop.inventory.erase("miso");bad.shop.inventory_lots.erase("miso");assert_false(TDGameProfile.validate_save(bad).ok)

func test_cuisine_cabinets_cover_required_spices_and_preferences_use_local_shelf() -> void:
	var jp:=TDMaterialCatalog.palette("jp",["spice:ginger"])
	assert_has(jp,"ginger");assert_has(jp,"miso");assert_does_not_have(jp,"wine")
	var sea:=TDMaterialCatalog.palette("sea",["spice:massaman"])
	assert_has(sea,"massaman");assert_has(sea,"fishsauce");assert_ne(sea,jp)
	assert_eq(jp.count("ginger"),1)
	for cuisine: String in ["eu","jp","sea","lat"]:
		for taste: int in 7:
			var id:=TDMaterialCatalog.preference_spice(cuisine,taste,"wine")
			if not id.is_empty(): assert_has(TDMaterialCatalog.palette(cuisine),id)
	assert_eq(TDMaterialCatalog.preference_spice("cn",0,"vinegar"),"vinegar")

func test_every_material_is_in_runtime_catalogue_with_stock_metadata_and_no_test_scope() -> void:
	var p:=profile();var cooking:=p.service.cooking.data();var definitions: Dictionary={}
	for row: Dictionary in cooking.ingredients: definitions[row.id]=row
	for id: String in TDMaterialCatalog.data().items:
		assert_has(p.service.config.costs,id);assert_has(definitions,id)
		assert_ne(definitions[id].scope,"TEST_ONLY")
		assert_has(p.shop.stock_rules,id);assert_gt(int(p.shop.stock_info(id).shelf_days),0)
		if p.shop.stock_info(id).condiment: assert_eq(definitions[id].category,"seasoning")
	assert_eq(p.service.config.offers.size(),9,"Materials do not pretend to add 100 playable recipes.")

func test_runtime_cuisine_and_optional_palette_reject_bad_metadata() -> void:
	var service:=TDServiceCatalog.new();assert_true(service.load_file().ok)
	for invalid: Dictionary in [{"cuisine_id":"moon"},{"seasoning_palette":["tomato"]},{"seasoning_palette":["salt","salt"]}]:
		var data:=service.cooking.data()
		data.recipes[0].merge(invalid,true)
		var tested:=TDCookingCatalog.new();assert_false(tested.load_data(data,"bad recipe metadata").ok)

func test_locked_condiments_reject_every_purchase_entry_without_side_effects() -> void:
	var p:=profile()
	assert_true(TDMaterialCatalog.supplies("chengdu","blackpepper"),"Supply geography does not imply cuisine permission")
	for id: String in ["miso","fishsauce","blackpepper","mole"]:
		assert_false(p.shop.purchasable(id));assert_false(p.shop.market_sells(id))
		assert_does_not_have(p.shop.purchase_ids(),id);assert_does_not_have(p.shop.market_ids(),id)
	for id: String in ["salt","sugar","starch","bean_paste"]:
		assert_true(p.shop.purchasable(id));assert_true(p.shop.market_sells(id))
	var before:=p.snapshot()
	assert_false(p.shop.buy({"tomato":1000,"miso":1000},"locked-direct").ok)
	assert_false(p.buy({"salt":1000,"blackpepper":1000}).ok)
	assert_false(p.order_remote("miso","tokyo",1000,"locked-remote").ok)
	assert_false(p.suppliers.order("tokyo","player_diner",{"salt":1000,"miso":1000},"locked-supplier").ok)
	assert_false(p.suppliers.create_line("tokyo","player_diner","miso",1000).ok)
	assert_false(p.world.factory_products("seasoning").any(func(row:Dictionary)->bool:return row.id=="blackpepper"))
	assert_eq(p.snapshot(),before)
	assert_true(p.shop.market_sells("udon"),"D069 street market noncondiments unchanged")

func test_cuisine_unlock_updates_shared_spices_immediately_without_unlocking_recipes() -> void:
	var p:=profile();var original: Array=p.research.snapshot().unlocked.duplicate()
	assert_false(p.shop.purchasable("coconut_milk"))
	assert_true(p.research.recommend_cuisine("story-sea","sea").ok)
	assert_true(p.shop.purchasable("coconut_milk"));assert_true(p.shop.purchasable("fishsauce"))
	assert_false(p.shop.purchasable("mole"));assert_false(p.shop.purchasable("miso"))
	assert_true(p.research.recommend_cuisine("story-jp","jp").ok)
	assert_true(p.shop.purchasable("miso"));assert_false(p.shop.purchasable("udon"))
	assert_true(p.suppliers.quote("tokyo","player_diner",{"miso":1000}).ok)
	assert_false(p.suppliers.quote("chengdu","player_diner",{"miso":1000}).ok)
	assert_eq(p.research.snapshot().unlocked,original)
	var other:=profile();assert_false(other.shop.purchasable("miso"),"Profiles do not share permissions")
	assert_true(other.restore(p.snapshot()).ok);assert_true(other.shop.purchasable("miso"))

func test_prepaid_locked_cuisine_stock_and_lines_survive_without_new_purchases() -> void:
	var p:=profile();var old_research:=p.research.snapshot()
	assert_true(p.research.recommend_cuisine("legacy-setup-jp","jp").ok)
	assert_true(p.shop.buy({"miso":200},"legacy-owned").ok)
	assert_true(p.suppliers.order("tokyo","player_diner",{"miso":1000},"legacy-paid").ok)
	assert_true(p.suppliers.create_line("tokyo","player_diner","miso",3000).ok)
	var old:=p.snapshot();old.research=old_research
	# Pre-D070 purchases had no cuisine gate. This valid legacy snapshot must remain loadable.
	var restored:=profile();var loaded:=restored.restore(old);assert_true(loaded.ok,loaded.code)
	var cents: int=int(restored.shop.snapshot().money_cents)
	assert_false(restored.shop.purchasable("miso"))
	assert_true(restored.shop.consume_materials(restored.shop.day_namespace()+"owned-use",{"miso":50}).ok)
	restored.suppliers.advance(100000);restored.suppliers.advance_game_minutes(600)
	assert_eq(restored.shop.available("miso"),1150)
	assert_eq(int(restored.shop.snapshot().money_cents),cents)
	assert_eq(restored.suppliers.state.orders.size(),1,"No new unpaid batch from the old line")
	var saved:=restored.snapshot();assert_true(TDGameProfile.validate_save(saved).ok)
	var reloaded:=profile();assert_true(reloaded.restore(saved).ok)
	assert_false(reloaded.shop.purchasable("miso"));assert_eq(reloaded.shop.available("miso"),1150)
