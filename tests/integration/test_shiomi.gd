extends GutTest

var profile: TDGameProfile

func before_each() -> void:
	profile=TDGameProfile.new()
	profile.slot_id="slot-01"
	assert_true(profile.error.ok,profile.error.code)

func after_each() -> void:
	profile.close()

func test_ingredient_shop_uses_regional_stock_without_booking_freight() -> void:
	var economy:=profile.commerce
	var shop:=profile.shop
	var shelf:=shop.market_ids("tokyo")
	assert_has(shelf,"udon")
	assert_has(shelf,"egg")
	assert_has(shelf,"salt")
	assert_does_not_have(shelf,"tortilla")
	assert_does_not_have(shelf,"miso")
	var cash:=int(shop.snapshot().money_cents)
	var held:=shop.available("egg")
	var stock: int=economy.state.markets.tokyo.stock.egg
	for invalid: Dictionary in [{"egg":1000,"miso":1000},{"egg":1000,"tortilla":1000}]:
		assert_false(profile.buy(invalid,"tokyo").ok)
	assert_eq(int(shop.snapshot().money_cents),cash)
	assert_eq(shop.available("egg"),held)
	assert_eq(int(economy.state.markets.tokyo.stock.egg),stock)
	assert_true(profile.research.recommend_cuisine("shiomi-shop-jp","jp").ok)
	assert_has(shop.market_ids("tokyo"),"miso")
	assert_does_not_have(economy.state.routes,"tokyo")
	var cart:={"miso":1000,"egg":1000}
	assert_false(economy.quote("tokyo",cart).ok)
	var home_stock: Dictionary=economy.state.markets.chengdu.stock.duplicate()
	var miso_stock: int=economy.state.markets.tokyo.stock.miso
	var held_miso:=shop.available("miso")
	var price: Dictionary=economy.state.markets.tokyo.price
	var shipments: Array=economy.state.shipments.duplicate(true)
	assert_true(profile.buy(cart,"tokyo").ok)
	assert_eq(int(shop.snapshot().money_cents),cash-int(price.egg)-int(price.miso))
	assert_eq(shop.available("egg"),held+1000)
	assert_eq(shop.available("miso"),held_miso+1000)
	assert_gt(shop.stock_info("miso").remaining_days,0)
	assert_eq(int(economy.state.markets.tokyo.stock.egg),stock-1000)
	assert_eq(int(economy.state.markets.tokyo.stock.miso),miso_stock-1000)
	assert_eq(economy.state.markets.chengdu.stock,home_stock)
	assert_eq(economy.state.shipments,shipments)
	assert_false(economy.quote("tokyo",cart).ok)
	economy.state.markets.tokyo.stock.miso=0
	cash=int(shop.snapshot().money_cents)
	assert_eq(profile.buy(cart,"tokyo").code,"MARKET_SOLD_OUT")
	assert_eq(int(shop.snapshot().money_cents),cash)
	assert_eq(shop.available("egg"),held+1000)

func test_arrival_on_real_wharf_and_blocked_sea() -> void:
	var world:=TDTravelWorld.new()
	world.map=TDTravelCatalog.map_for(profile,"tokyo")
	add_child_autofree(world)
	assert_true(world.map.shiomi)
	assert_eq(world.nearby().get("kind"),"harbor")
	assert_true(world._can_stand(world.player.position))
	assert_true(world._confine(world.player.position+Vector2(-33,0)))
	assert_false(world._can_stand(TDShiomiLayout.world_point(Vector2(1220,699))))
	assert_false(world._can_stand(TDShiomiLayout.world_point(Vector2(780,488))))
	assert_true(world._can_stand(TDShiomiLayout.world_point(Vector2(790,543))))
	var obj: Node2D=world._island
	assert_gt(obj.get_node("Streets").get_used_cells().size(),1000)
	assert_gt(obj.get_node("Meadows").get_used_cells().size(),1000)
	assert_gt(obj.get_node("Wharf").get_used_cells().size(),100)
	assert_gt(obj.get_node("QuayStone").get_used_cells().size(),700)
	var weather=obj.get_node("Weather")
	world.set_day_minute(720)
	assert_eq(weather.daylight,0.0)
	var a: float=weather.wheel.rotation
	world.set_day_minute(1190)
	assert_ne(weather.wheel.rotation,a)
	assert_eq(weather.daylight,1.0)
	assert_gt(weather.lamps.size(),5)
	assert_gt(weather.trees.size(),4)
	assert_not_null(weather.bath)

func test_visible_arch_is_the_only_walkable_river_crossing() -> void:
	var world:=TDTravelWorld.new()
	world.map=TDTravelCatalog.map_for(profile,"tokyo")
	add_child_autofree(world)
	for at: Vector2 in [Vector2(1228,235),Vector2(1237,231),Vector2(1253,222),
			Vector2(1273,218),Vector2(1295,224),Vector2(1313,233),Vector2(1320,235)]:
		assert_true(world._can_stand(TDShiomiLayout.world_point(at)),str(at))
	for at: Vector2 in [Vector2(1271,208),Vector2(1274,230),Vector2(1274,244),Vector2(1272,256)]:
		assert_false(world._can_stand(TDShiomiLayout.world_point(at)),str(at))
	for at: Vector2i in [Vector2i(1217,257),Vector2i(1227,235),Vector2i(1320,235),Vector2i(1338,230)]:
		assert_shiomi_surface(world._island,"Streets",at)
		assert_true(world._can_stand(TDShiomiLayout.world_point(at)),str(at))
	for at: Vector2i in [Vector2i(1288,150),Vector2i(1252,202)]:
		assert_shiomi_surface(world._island,"Watercourse",at)
		assert_false(world._can_stand(TDShiomiLayout.world_point(at)),str(at))
	assert_true(world._can_stand(TDShiomiLayout.world_point(Vector2(255,178))))
	assert_true(world._can_stand(TDShiomiLayout.world_point(Vector2(255,292))))
	assert_false(world._can_stand(TDShiomiLayout.world_point(Vector2(274,808))))


func test_water_works_and_dry_riverbed_match_the_survey() -> void:
	var world:=TDTravelWorld.new()
	world.map=TDTravelCatalog.map_for(profile,"tokyo")
	add_child_autofree(world)
	var scene:=world._island
	for at: Vector2i in [Vector2i(1290,116),Vector2i(1273,255),Vector2i(1498,394),
			Vector2i(1268,268),Vector2i(1244,278),Vector2i(1222,291),
			Vector2i(130,815),Vector2i(153,825),Vector2i(174,807),Vector2i(178,803),Vector2i(200,840),Vector2i(214,926)]:
		assert_shiomi_surface(scene,"Watercourse",at)
		assert_false(world._can_stand(TDShiomiLayout.world_point(at)),str(at))
	for at: Vector2i in [Vector2i(209,742),Vector2i(192,768)]:
		assert_shiomi_surface(scene,"Meadows",at)
	for at: Vector2i in [Vector2i(1244,290),Vector2i(1208,313)]:
		assert_shiomi_surface(scene,"DryRiverbed",at)
		assert_true(world._can_stand(TDShiomiLayout.world_point(at)),str(at))
	for name_of_layer: String in ["MountainSpring","MillHeadwater","BeachBluffs","RakedSand","TidalOutfalls","BridgeWaterShadow"]:
		assert_false(scene.get_node(name_of_layer).get_used_cells().is_empty(),name_of_layer)
	assert_shiomi_surface(scene,"DryRiverbed",Vector2i(1208,313))
	assert_eq(world.map.terrain_at(Vector2i(58,30)).surface_type,"gravel")
	assert_true(world.map.branch_ground_available(Vector2i(58,30)))
	var offer:=profile.branches.quote("tokyo",[58,30,3,3],"cn")
	assert_true(offer.ok,offer.code)

func test_buildings_use_jiangnan_character_scale() -> void:
	var shiomi:=TDShiomiArt.instance()
	add_child_autofree(shiomi)
	var jiangnan:=TDJiangnanReferenceArt.make_scene()
	add_child_autofree(jiangnan)
	for names: Array in [["Bank004","bank"],["Inn010","inn"]]:
		var japanese:=shiomi.get_node(names[0]) as Sprite2D
		var chinese:=jiangnan.get_node("Props/"+names[1]) as Sprite2D
		var height:=japanese.get_rect().size.y*japanese.global_scale.y
		var reference:=chinese.get_rect().size.y*chinese.global_scale.y
		assert_almost_eq(height/reference,1.0,.13,names[0])
	assert_true(shiomi.get_node("Bank004").get_meta("grass_footing",false))
	var white_court:=shiomi.get_node("WhiteCourts") as TileMapLayer
	for footing: Vector2i in [Vector2i(450,610),Vector2i(795,795)]:
		assert_shiomi_surface(shiomi,"WhiteCourts",footing)
		var tile:=Vector2i((Vector2(footing)/6.0).floor())
		assert_eq(white_court.get_cell_source_id(tile),0,str(footing))
		assert_true(white_court.get_cell_atlas_coords(tile).x in range(56,64),"raked surface at "+str(footing))
	for at: Vector2i in [Vector2i(450,580),Vector2i(669,790),Vector2i(920,804)]:
		assert_shiomi_surface(shiomi,"Meadows",at)


func test_stone_quay_connects_to_pier_over_the_sea() -> void:
	var world:=TDTravelWorld.new()
	world.map=TDTravelCatalog.map_for(profile,"tokyo")
	add_child_autofree(world)
	for at: Vector2i in [Vector2i(1180,575),Vector2i(1332,577),Vector2i(1408,562)]:
		assert_shiomi_surface(world._island,"QuayStone",at)
		assert_true(world._can_stand(TDShiomiLayout.world_point(at)),str(at))
	for at: Vector2i in [Vector2i(1332,612),Vector2i(1180,611),Vector2i(1455,641),Vector2i(1332,652)]:
		assert_shiomi_surface(world._island,"Wharf",at)
		assert_true(world._can_stand(TDShiomiLayout.world_point(at)),str(at))
	for at: Vector2i in [Vector2i(1180,641),Vector2i(1200,660),Vector2i(1332,681)]:
		assert_shiomi_surface(world._island,"Sea",at)
		assert_false(world._can_stand(TDShiomiLayout.world_point(at)),str(at))
	for at: Vector2i in [Vector2i(1145,568),Vector2i(1447,634),Vector2i(1334,528)]:
		assert_false(world._can_stand(TDShiomiLayout.world_point(at)),"solid dock cargo at "+str(at))


func test_relocated_frontages_follow_real_ground() -> void:
	var world:=TDTravelWorld.new()
	world.map=TDTravelCatalog.map_for(profile,"tokyo")
	add_child_autofree(world)
	var scene:=world._island
	for node: Node in scene.get_children():
		var prop:=node as Sprite2D
		if prop==null or not prop.has_meta("base"): continue
		var id:=str(prop.get_meta("plot_id",""))
		var coastal:=id in ["market-main","harbor"]
		var moved_fence: bool=prop.get_meta("art","")=="fence" and is_equal_approx(prop.position.y,675.0)
		if not coastal and not moved_fence and id not in ["market-neighborhood","competitor:shop:0","competitor:shop:1","residences-b"]: continue
		var contact: Rect2=prop.get_meta("base")
		var center:=prop.position+contact.get_center()
		for offset: float in [-.44,0.,.44]:
			var point:=Vector2i(center+Vector2(contact.size.x*offset,0))
			assert_shiomi_surface(scene,"QuayStone" if coastal else "Meadows",point)
		if coastal: assert_false(prop.has_meta("grass_footing"))
	var road_foot:=Vector2i(220,699)
	assert_shiomi_surface(scene,"Streets",road_foot)
	assert_true(world._can_stand(TDShiomiLayout.world_point(road_foot)),"the former fence position is now clear")


func assert_shiomi_surface(scene: Node2D, layer_name: String, at: Vector2i) -> void:
	var layer:=scene.get_node(layer_name) as TileMapLayer
	var cell:=Vector2i((Vector2(at)/6.0).floor())
	assert_gte(layer.get_cell_source_id(cell),0,"%s at %s"%[layer_name,at])

func test_residential_bends_beach_and_bath_court() -> void:
	var scene:=TDShiomiArt.instance()
	add_child_autofree(scene)
	for at: Vector2i in [Vector2i(198,484),Vector2i(548,297),Vector2i(1207,277)]:
		assert_shiomi_surface(scene,"Streets",at)
	for at: Vector2i in [Vector2i(229,484),Vector2i(548,279)]:
		assert_shiomi_surface(scene,"Meadows",at)
	for at: Vector2i in [Vector2i(1320,848),Vector2i(1270,873),Vector2i(1200,885),Vector2i(1150,910)]:
		assert_shiomi_surface(scene,"ShellBeach",at)
		assert_true(TDShiomiArt.can_stand(scene,TDShiomiLayout.world_point(at)))
	assert_shiomi_surface(scene,"Escarpments",Vector2i(1280,852))
	assert_false(TDShiomiArt.can_stand(scene,TDShiomiLayout.world_point(Vector2(1280,852))))
	assert_false(TDShiomiArt.can_stand(scene,TDShiomiLayout.world_point(Vector2(1320,910))))
	var hotel:=scene.get_node("Inn010") as Sprite2D
	var bath:=scene.get_node("Bath011") as Sprite2D
	var gap: float=(bath.transform*bath.get_rect()).position.x-(hotel.transform*hotel.get_rect()).end.x
	assert_between(gap,0.0,10.0,"bath court is beside the right wing")
	for child in scene.get_children():
		if not child is Sprite2D or not child.visible or child.get_meta("art","")!="reef": continue
		assert_shiomi_surface(scene,"Sea",Vector2i(child.position-Vector2(0,4)))

func test_beach_cliff_shows_only_the_seaward_front_and_preserves_the_descent() -> void:
	var scene:=TDShiomiArt.instance()
	add_child_autofree(scene)
	var bluff:=scene.get_node("BeachBluffs") as TileMapLayer
	# The back drop is a protected turf edge; only the foreground edge shows rock.
	var back:=Vector2i(1149,765)
	var front:=Vector2i(1149,884)
	for foot: Vector2i in [back,front,Vector2i(1122,896),Vector2i(1178,872),Vector2i(1320,826)]:
		assert_shiomi_surface(scene,"Escarpments",foot)
		assert_false(TDShiomiArt.can_stand(scene,TDShiomiLayout.world_point(foot)))
	assert_eq(bluff.get_cell_source_id(bluff.local_to_map(Vector2(back))),-1)
	assert_gte(bluff.get_cell_source_id(bluff.local_to_map(Vector2(front))),0)
	for y: int in range(849,895,3):
		assert_true(TDShiomiArt.can_stand(scene,TDShiomiLayout.world_point(Vector2(1212,y))),"beach access at "+str(y))

func test_free_survey_is_shared_by_quotes_and_terrain() -> void:
	var map:=profile.branches.town_map("tokyo")
	for at: Vector2i in [Vector2i(65,34),Vector2i(11,35),Vector2i(31,45)]:
		assert_eq(map.branch_ground_available(at),map.terrain_at(at).buildable and map.plot_at(at.x,at.y).is_empty() and not map.frontage_reserved(at))
	assert_false(map.branch_ground_available(Vector2i(63,42)),"port")
	assert_false(map.branch_ground_available(Vector2i(8,17)),"sea")
	assert_false(map.branch_ground_available(Vector2i(28,22)),"ridge")
	var candidates: Array[Rect2i]=[]
	for y: int in range(20,55):
		for x: int in range(10,68):
			var rect:=Rect2i(x,y,3,3)
			if not map.branch_touches_road(rect): continue
			var clear:=true
			for dx: int in 3:
				for dy: int in 3:
					if not map.branch_ground_available(rect.position+Vector2i(dx,dy)): clear=false
			if not clear: continue
			if candidates.any(func(r:Rect2i)->bool: return r.grow(3).intersects(rect)): continue
			candidates.append(rect)
	assert_gte(candidates.size(),5,"separate neighborhoods allow free siting")
	for r: Rect2i in candidates.slice(0,5):
		var offer:=profile.branches.quote("tokyo",[r.position.x,r.position.y,3,3],"cn")
		assert_true(offer.ok,offer.code)
	var raw:=profile.snapshot()
	var checked:=TDGameProfile.validate_save(raw)
	assert_true(checked.ok,checked.code+" "+checked.message)

func test_shiomi_economic_terrain_follows_the_landed_map() -> void:
	var map:=profile.branches.town_map("tokyo")
	var geo:=TDEconomicGeography.new()
	geo.configure("tokyo",map.plots,{},2)
	for pair: Array in [[Vector2i(63,42),"pier"],[Vector2i(67,40),"quay"],[Vector2i(61,26),"bridge"],[Vector2i(58,30),"gravel"],[Vector2i(18,48),"paddy"],[Vector2i(58,54),"sand"]]:
		var cell:=geo.cell(pair[0])
		assert_eq(cell.surface_type,pair[1])
		assert_true(TDEconomicCell.validate(cell).ok)
	assert_lt(geo.cell(Vector2i(67,40)).travel_minutes.station,geo.cell(Vector2i(24,44)).travel_minutes.station)
	assert_lt(geo.cell(Vector2i(61,26)).travel_minutes.station,1000.,"bridge connected to port")
	assert_eq(geo.cell(Vector2i(24,44)).district_id,"noh_square")
	assert_eq(geo.cell(Vector2i(18,48)).district_id,"mill_fields")
	for p: Vector2i in [Vector2i(8,17),Vector2i(18,48),Vector2i(61,52)]:
		var cell:=geo.cell(p)
		assert_false(cell.reachable)
		assert_eq(cell.rent_quote_cents_per_day,0)
		assert_eq(cell.land_value_cents,0)

func test_older_shiomi_lease_stays_valid_beside_newly_surveyed_rock() -> void:
	var map:=profile.branches.town_map("tokyo")
	var rect: Array=[56,24,3,3]
	for y: int in range(24,27):
		for x: int in range(56,59):
			assert_true(map.branch_ground_available(Vector2i(x,y),true))
	assert_eq(profile.branches.quote("tokyo",rect,"cn").code,"PROTECTED_LAND")
	assert_true(profile.shop.world_adjustment(500000,"fixture","地籍验证").ok)
	var opened:=profile.branches.open_store("tokyo",[58,30,3,3],"cn","","shore-lease")
	assert_true(opened.ok,opened.code)
	if not opened.ok: return
	var raw:=profile.snapshot()
	var store: Dictionary=raw.branches.stores.values()[0]
	store.erase("site_survey")
	store.rect=rect.duplicate()
	var next:=TDGameProfile.new()
	var loaded:=next.restore(raw)
	assert_true(loaded.ok,loaded.code)
	if loaded.ok:
		var after: Dictionary=next.branches.state.stores[store.id]
		assert_eq(after.rect,rect)
		assert_eq(after.rent_cents,store.rent_cents)
		assert_eq(after.books,store.books)
	next.close()

func test_finish_layers_do_not_take_land_or_introduce_collision() -> void:
	var scene:=TDShiomiArt.instance()
	add_child_autofree(scene)
	for name_of_layer: String in ["MeadowUndergrowth","RoadVerge","WaterfallPools","TideAndMillBanks","BankPlanting","LandingTimbers","ContactInk","WallGrasses"]:
		var layer:=scene.get_node(name_of_layer) as TileMapLayer
		assert_not_null(layer,name_of_layer)
		assert_false(layer.get_used_cells().is_empty(),name_of_layer)
		assert_eq(layer.tile_set.get_physics_layers_count(),0,name_of_layer)
		assert_false(name_of_layer in TDShiomiArt.WALK_LAYERS)
	assert_true(scene.get_node("WallGrasses").y_sort_enabled)
	assert_true(scene.get_node("Weather/FoamAndBirds") is Node2D)
	for name_of_prop: String in ["DockTubs1334","DockCargo1446"]:
		var prop:=scene.get_node(name_of_prop)
		assert_false(prop.has_meta("base"))
		assert_false(prop.has_meta("plot_id"))

func test_paid_previous_island_store_moves_once_and_keeps_its_books() -> void:
	profile.region_layout_version=2
	# Recreate each town's titles in the legacy layout before taking the old save.
	for id: String in TDRegionalLayout.IDS:
		profile.commerce.expansion.state.parcels.erase(id)
	profile.branches._maps.clear()
	profile._wire_commerce()
	assert_true(profile.shop.world_adjustment(500000,"fixture","测试资金").ok)
	var previous:=profile.branches.town_map("tokyo")
	assert_false(previous.shiomi)
	var rect:=TDRegionMigration.find_site(previous,[13,20,3,3])
	assert_eq(rect.size(),4)
	var paid:=profile.branches.open_store("tokyo",rect,"cn","","shiomi-migration")
	assert_true(paid.ok,paid.code)
	if not paid.ok: return
	var old:=profile.snapshot()
	var next:=TDGameProfile.new()
	var result:=next.restore(old)
	assert_true(result.ok,result.code+" "+result.message)
	if result.ok:
		assert_true(next.region_migrated_on_load)
		var saved:=next.snapshot()
		assert_eq(saved.shop,old.shop)
		var map:=next.branches.town_map("tokyo")
		var identities: Dictionary={}
		for plot: Dictionary in map.plots:
			assert_false(identities.has(plot.id),str(plot.id))
			identities[plot.id]=true
		for id: String in old.branches.stores:
			var before: Dictionary=old.branches.stores[id]
			var after: Dictionary=saved.branches.stores[id]
			assert_eq(after.rect.slice(2),before.rect.slice(2))
			for field: String in before:
				if field not in ["place","rect"]: assert_eq(after[field],before[field],field)
		var again:=TDGameProfile.new()
		assert_true(again.restore(saved).ok)
		assert_false(again.region_migrated_on_load)
		assert_eq(again.snapshot(),saved)
		again.close()
	next.close()
