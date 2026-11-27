extends GutTest
var app: TDApplication
var shell: TDGameShell

func before_each() -> void:
	app=load("res://src/app/main.tscn").instantiate()
	app.settings_path="res://artifacts/travel/tests/%d/settings.json"%Time.get_ticks_usec()
	add_child_autofree(app);shell=app.game_shell;shell.automatic_time=false
	await wait_process_frames(1)
	assert_true(shell.create_game("slot-01","航线测试",false).ok)
	shell.guide.dialogue.finish_now();shell.profile.story.beat="done"
	shell.travel("town");shell.town.spawn_at_harbor()

func after_each() -> void:
	for action: String in ["world_left","world_right","world_up","world_down","world_sprint"]: Input.action_release(action)
	get_tree().paused=false;shell._close_dialog();shell._dispose_game()
	await wait_process_frames(2)

func test_public_benches_seat_two_people_at_town_scale() -> void:
	# Width of load-bearing seat, measured on each unscaled atlas illustration.
	var seat_pixels := {"chengdu":137,"tokyo":152,"paris":148}
	for id: String in TDTravelCatalog.IDS:
		if id == "chengdu":
			var benches := shell.town._facades.filter(func(entry: Dictionary) -> bool:
				return str(entry.get("reference_id", "")).begins_with("food-street-benches"))
			assert_eq(benches.size(), 2, "Both reference seating groups are in the walking scene")
			for entry: Dictionary in benches:
				assert_gt((entry.rect as Rect2).size.x, shell.town._player.sprite_height)
			continue
		var tex := TDTravelCatalog.street_detail(id,2)
		var widths: Array[float] = []
		shell.town.spawn_at_harbor()
		assert_true(shell.voyage(id).ok)
		if shell.visiting.map.egret:
			var bench := shell.visiting._island.get_node("TownHallBench") as Sprite2D
			var seat: Rect2 = bench.get_meta("base")
			assert_between(seat.size.x*shell.visiting._island.scale.x,105.0,115.0,"two-person bank bench")
			assert_false(shell.visiting._can_stand(shell.visiting._island.to_global(bench.position+seat.get_center())))
			assert_true(shell.voyage("chengdu").ok)
			continue
		if shell.visiting.map.shiomi:
			for node: Node in shell.visiting._island.get_children():
				var bench:=node as Sprite2D
				if bench!=null and bench.get_meta("art","")=="bench":
					var size: Vector2=(bench.global_transform*bench.get_rect()).size
					assert_between(size.x,80.0,105.0,"two-person stage bench")
					widths.append(size.x)
			assert_eq(widths.size(),4)
			assert_true(shell.voyage("chengdu").ok)
			continue
		for child: Node in shell.visiting.get_children():
			if child is Sprite2D and child.texture==tex: widths.append(child.scale.x*tex.get_width())
		shell.visiting.player.position=(Vector2(TDTravelCatalog.port(id))+Vector2.ONE*.5)*shell.visiting.cell_size
		assert_true(shell.voyage("chengdu").ok)
		assert_gt(widths.size(),0,id+" has a placed street bench")
		for w: float in widths:
			var seat: float = w*seat_pixels[id]/tex.get_width()
			assert_between(seat,76.0,96.0,id+" usable seat in world pixels")

func test_named_venues_are_visible_and_reachable_in_all_five_towns() -> void:
	for town: String in TDTravelCatalog.IDS:
		var home := town=="chengdu"
		if not home:
			shell.town.spawn_at_harbor()
			assert_true(shell.voyage(town).ok)
		var map := shell.town.session.town_map if home else shell.visiting.map
		var origin := shell.town._origin() if home else Vector2.ZERO
		var existing := shell.town._facades if home else shell.visiting._buildings
		if home:
			var landmarks := existing.map(func(e: Dictionary) -> String: return str(e.get("reference_id", "")))
			for fixture: String in ["waterfront-show-stage", "east-tea-dock", "river-pier-stall", "market-blue-fish-stall", "forge"]:
				assert_has(landmarks, fixture)
			for id: String in ["hotel", "market-small", "market-mid", "commercial_street:bank", "player_diner"]:
				var plot := map._by_id(id)
				var front := origin + (Vector2(plot.approach_x, plot.approach_y) + Vector2.ONE * .5) * shell.town.cell_size()
				assert_true(shell.town._can_stand(front), id + " approach")
			continue
		if not home:
			var ports := existing.filter(func(e:Dictionary)->bool: return e.plot.kind=="harbor")
			assert_eq(ports.size(),1,town+" has a berth")
			if not ports.is_empty():
				var berth: Rect2 = ports[0].rect
				var blocked_deck := false
				for y: int in range(floori(berth.position.y/shell.visiting.cell_size),ceili(berth.end.y/shell.visiting.cell_size)):
					for x: int in range(floori(berth.position.x/shell.visiting.cell_size),ceili(berth.end.x/shell.visiting.cell_size)):
						if map.terrain_at(Vector2i(x,y)).surface_type=="bridge": blocked_deck=true
				assert_false(blocked_deck,town+" boat and ticket counter stand clear of the crossing")
		if map.shiomi or map.egret:
			var venues := ["plaza","market-neighborhood","market-main","hotel","landmark","commercial_street:bank"]
			venues.append_array(["mill","workshops"] if map.egret else ["watch"])
			for id: String in venues:
				var entry: Dictionary=existing.filter(func(e:Dictionary)->bool:return e.plot.id==id)[0]
				var base:Rect2=entry.base
				assert_false(shell.visiting._can_stand(base.get_center()),id+" solid")
				shell.visiting.player.position=Vector2(base.get_center().x,base.end.y+12)
				assert_true(shell.visiting._can_stand(shell.visiting.player.position),id+" front")
				assert_eq(shell.visiting.nearby().get("id"),id)
			shell.visiting.player.position=(Vector2(TDTravelCatalog.port(town))+Vector2.ONE*.5)*shell.visiting.cell_size
			assert_true(shell.voyage("chengdu").ok)
			continue
		for id: String in TDTownArt.StreetPlaces.VENUES[town]:
			var plot := map._by_id(id)
			var venue := TDTownArt.StreetPlaces.venue(town,plot,TDTownWorld.CELL,origin)
			var rect: Rect2 = venue.rect
			assert_true(TDInteractionRange.plot_bounds(plot,TDTownWorld.CELL,origin).encloses(rect),venue.place_name)
			var found := false
			if home:
				for e: Dictionary in existing:
					if e.art==venue.art and e.rect==rect: found=true
			else:
				for child: Node in shell.visiting.get_children():
					if child is Sprite2D and child.texture==venue.art and (child.transform*child.get_rect()).is_equal_approx(rect): found=true
			assert_true(found,str(venue.place_name)+" shares its location with the atlas")
			for e: Dictionary in existing:
				if e.has("plot"): assert_false(rect.intersects(e.rect),str(venue.place_name)+" obscures "+str(e.plot.id))
			var front := Vector2(rect.get_center().x,rect.end.y+17)
			assert_true(shell.town._can_stand(front) if home else shell.visiting._can_stand(front),str(venue.place_name)+" approach")
			var wall: Rect2=venue.bases[0]
			assert_false(shell.town._can_stand(wall.get_center()) if home else shell.visiting._can_stand(wall.get_center()),"building wall")
		var blockers: Array[Rect2]=[]
		for e: Dictionary in existing:
			if e.has("plot"): blockers.append(e.rect)
		var props := TDTownArt.StreetPlaces.verges(town,map,TDTownWorld.CELL,origin,blockers)
		var clusters := {}
		for item: Dictionary in props:
			if item.has("street_cluster"): clusters[item.street_cluster]=true
			var foot: Rect2=item.bases[0]
			var at:=Vector2i(((foot.get_center()-origin)/TDTownWorld.CELL).floor())
			assert_false(map.is_road(at.x,at.y),town+" public street remains clear")
		assert_gte(clusters.size(),10,town+" distributes groups throughout the town")
		if not home:
			shell.visiting.player.position=(Vector2(TDTravelCatalog.port(town))+Vector2.ONE*.5)*shell.visiting.cell_size
			assert_true(shell.voyage("chengdu").ok)

func test_town_squares_have_an_open_meeting_floor() -> void:
	for id: String in TDTravelCatalog.IDS:
		var home := id=="chengdu"
		if not home:
			shell.town.spawn_at_harbor()
			assert_true(shell.voyage(id).ok)
		var map := shell.town.session.town_map if home else shell.visiting.map
		var court := TDTownScenery.PublicSquare.bounds(map)
		var center := TDTownScenery.PublicSquare.meeting_point(court)
		var origin := shell.town._origin() if home else Vector2.ZERO
		if home:
			center = Vector2(380,534)/TDPlannedTown.REFERENCE_PIXELS_PER_CELL
			for offset: Vector2 in [Vector2.ZERO,Vector2.LEFT*.4,Vector2.RIGHT*.4,Vector2.UP*.2,Vector2.DOWN*.2]:
				assert_true(shell.town._can_stand(origin + (center + offset) * shell.town.cell_size()), "Open flagstones south of the banyan")
			continue
		if map.egret:
			for px: Vector2 in [Vector2(1157,578),Vector2(1115,578),Vector2(1199,578),Vector2(1157,552),Vector2(1157,601)]:
				var point := TDEgretLayout.world_point(px)
				var at := Vector2i((point/shell.visiting.cell_size).floor())
				assert_eq(map.terrain_at(at).surface_type,"square","mosaic at the fountain")
				assert_true(shell.visiting._can_stand(point),"open meeting floor south of the basin")
			assert_true(shell.voyage("chengdu").ok)
			continue
		if map.shiomi:
			var floor_layer:=shell.visiting._island.get_node("WhiteCourts") as TileMapLayer
			for px: int in range(375,551,25):
				var point:=TDShiomiLayout.world_point(Vector2(px,644))
				assert_true(shell.visiting._can_stand(point))
				assert_gte(floor_layer.get_cell_source_id(floor_layer.local_to_map(floor_layer.to_local(point))),0)
			assert_true(shell.voyage("chengdu").ok)
			continue
		var floor := TDTownScenery.smooth_surfaces(map)
		assert_gte(court.get_area(),28,id+" civic assembly space")
		assert_gt(TDTownScenery.PublicSquare.entrances(map,court).size(),0,id+" a paved entry connects to a real street")
		for offset: Vector2 in [Vector2.ZERO,Vector2.LEFT*.55,Vector2.RIGHT*.55,Vector2.UP*.4,Vector2.DOWN*.4]:
			var at := center+offset
			var expected_surfaces := ["stone","civic_paving"] if home else ["civic_paving"]
			assert_has(expected_surfaces,floor[Vector2i(at.floor())],id+" paved meeting floor")
			var feet := origin+at*TDTownWorld.CELL
			assert_true(shell.town._can_stand(feet) if home else shell.visiting._can_stand(feet),id+" unobstructed position "+str(at))
		if not home:
			shell.visiting.player.position=(Vector2(TDTravelCatalog.port(id))+Vector2.ONE*.5)*shell.visiting.cell_size
			assert_true(shell.voyage("chengdu").ok)

func test_street_buildings_keep_human_scale_including_narrow_residential_frontages() -> void:
	for id: String in TDTravelCatalog.IDS:
		var home := id=="chengdu"
		if not home:
			shell.town.spawn_at_harbor()
			assert_true(shell.voyage(id).ok)
		var entries := shell.town._facades if home else shell.visiting._buildings
		var player := shell.town._player if home else shell.visiting.player
		if home:
			assert_true(shell.town._can_stand(shell.town._origin()+(Vector2(TDHarbor.ARRIVAL)+Vector2.ONE*.5)*shell.town.cell_size()),"arrival stays open")
			var homes := 0
			for part: Dictionary in entries:
				var name := str(part.get("reference_id", ""))
				if name.begins_with("west-") or name.begins_with("east-"):
					if name.contains("house") or name.contains("homes"): homes += 1
				assert_almost_eq(part.rect.size.aspect(), (part.art as Texture2D).get_size().aspect(), .005)
			assert_gte(homes, 8, "Both banks include their authored residential buildings")
			continue
		var visit:=shell.visiting
		assert_eq(player.sprite_height,shell.town._player.sprite_height)
		assert_eq(visit.camera.zoom,shell.town._camera.zoom)
		var reference_height: Dictionary={}
		for facade: Dictionary in shell.town._facades:
			reference_height[facade.get("reference_id","")]=(facade.rect as Rect2).size.y
		var venues := {"commercial_street:bank":"bank","hotel":"inn",
			"residences-a":"west-inn-lane-house","residences-b":"west-square-edge-house"}
		for plot_id: String in venues:
			var matches:=visit._buildings.filter(func(row: Dictionary)->bool: return row.plot.id==plot_id)
			assert_eq(matches.size(),1,id+" "+plot_id)
			if matches.size()!=1: continue
			var rect: Rect2=matches[0].rect
			var wall: Rect2=matches[0].base
			var expected: float=reference_height[venues[plot_id]]
			assert_almost_eq(rect.size.y/expected,1.0,.13,id+" "+plot_id+" relative to Jiangnan")
			assert_true(rect.encloses(wall) and not visit._can_stand(wall.get_center()))
			player.position=Vector2(wall.get_center().x,wall.end.y+visit.FOOT_RADIUS+2)
			assert_true(visit._can_stand(player.position))
			if plot_id.begins_with("residences-"):
				assert_ne(visit.nearby().get("id"),plot_id)
			else:
				assert_eq(visit.nearby().get("id"),plot_id)
		player.position=(Vector2(TDTravelCatalog.port(id))+Vector2.ONE*.5)*visit.cell_size
		shell.show_world_map()
		var maps:=shell._modal_box.find_children("*","Control",true,false)
		var found:=false
		for panel: Control in maps:
			if panel is TDTravelMapView:
				assert_true(panel.marker.is_equal_approx(Vector2(TDTravelCatalog.port(id))+Vector2.ONE*.5),"map marker at the arrival cell center")
				found=true
		assert_true(found,"atlas marker is measured in town cells")
		shell._close_dialog()
		assert_true(shell.voyage("chengdu").ok)

func test_regional_residential_streets_have_walkable_gates_and_solid_rails() -> void:
	for id: String in TDRegionalLayout.IDS:
		if id == "chengdu": continue # Its reference housing has hand-authored collision bases.
		if id != "chengdu":
			shell.town.spawn_at_harbor()
			assert_true(shell.voyage(id).ok)
		var home := id=="chengdu"
		var map: TDTownMap = shell.town.session.town_map if home else shell.visiting.map
		var origin := shell.town._origin() if home else Vector2.ZERO
		var feet := shell.town._player if home else shell.visiting.player
		if map.shiomi or map.egret:
			var fences:=0
			for node: Node in shell.visiting._island.get_children():
				if node.get_meta("art","")!="fence": continue
				var sprite:=node as Sprite2D
				var base:Rect2=sprite.get_meta("base")
				var point:=shell.visiting._island.to_global(sprite.position+base.get_center())
				assert_false(shell.visiting._can_stand(point),"authored fence footing")
				fences+=1
			assert_gt(fences,4)
			var gate := TDEgretLayout.world_point(Vector2(694,984)) if map.egret else TDShiomiLayout.world_point(Vector2(199,702))
			assert_true(shell.visiting._can_stand(gate),"neighborhood gate")
			assert_true(shell.voyage("chengdu").ok)
			continue
		var yards := 0
		for p: Dictionary in map.plots:
			if not TDTownArt.Yard.has_yard(p): continue
			var entries := shell.town._facades if home else shell.visiting._buildings
			var rendered := entries.filter(func(e: Dictionary)->bool: return e.get("plot",{}).get("id","")==p.id)
			assert_eq(rendered.size(),1,id+":"+p.id+" actual facade")
			if rendered.is_empty(): continue
			var house: Rect2 = rendered[0].rect
			var court := TDTownArt.Yard.enclosure(p,TDTownWorld.CELL,origin,house)
			assert_true(court.encloses(house.grow(7)), "%s %s roof %s inside rails %s" % [id,p.id,house,court])
			var fence := TDTownArt.Yard.sections(id,p,TDTownWorld.CELL,origin,house)
			assert_has(["rich_district","urban_village"],str(p.kind),id+" protects public lots")
			yards+=1
			var center := Vector2(house.get_center().x,court.end.y)
			assert_eq(map.terrain_at(Vector2i((center-origin)/TDTownWorld.CELL)).surface_type,"lawn",id+":"+p.id)
			feet.position = center+Vector2(0,24)
			var inside := Vector2(center.x,house.end.y+12)
			assert_true(shell.town._feet_on_road(inside) if home else shell.visiting._confine(inside),id+":"+p.id+" can walk through front opening")
			var base: Rect2=fence.front().bases.front()
			assert_false(shell.town._can_stand(base.get_center()) if home else shell.visiting._can_stand(base.get_center()),id+" fence has contact")
			var door := origin+(Vector2(p.approach_x,p.approach_y)+Vector2.ONE*.5)*TDTownWorld.CELL
			var neighbours := entries.filter(func(e: Dictionary)->bool:
				return (e.has("plot") or e.get("housing_block",false)) and e.get("plot",{}).get("id","")!=p.id and court.grow(50).intersects(e.rect))
			for segment: Dictionary in fence:
				var solid: Rect2 = segment.bases.front()
				for neighbour: Dictionary in neighbours:
					assert_false(segment.rect.intersects(neighbour.rect),"%s %s fence crosses %s" % [id,p.id,neighbour.get("plot",{}).get("id","housing")])
				assert_false(solid.grow(9.0).has_point(door),id+" door clearance")
				assert_false(map.is_road(floori((solid.get_center().x-origin.x)/TDTownWorld.CELL),floori((solid.get_center().y-origin.y)/TDTownWorld.CELL)),id+" public road stays clear")
		assert_gt(yards,0,id+" has a residential enclosure")
		if not home:
			feet.position=(Vector2(TDTravelCatalog.port(id))+Vector2.ONE*.5)*shell.visiting.cell_size
			assert_true(shell.voyage("chengdu").ok)

func test_four_towns_round_trip_does_not_mutate_home_or_unlocks() -> void:
	var before:=shell.profile.snapshot()
	for id: String in ["tokyo","paris"]:
		assert_true(shell.voyage(id).ok,id)
		assert_eq(shell.location,"voyage");assert_eq(shell.visiting.town_id,id)
		assert_eq(shell.visiting.nearby().get("kind"),"harbor")
		assert_eq(shell.voyage(id).code,"INVALID_DESTINATION")
		var map:=shell.visiting.map
		assert_true(map.is_walkable(TDTravelCatalog.port(id).x,TDTravelCatalog.port(id).y));assert_false(map.is_walkable(0,0))
		assert_gt(shell.visiting._buildings.size(),6)
		assert_eq(shell.profile.snapshot(),before)
	assert_true(shell.voyage("chengdu").ok)
	assert_null(shell.visiting);assert_eq(shell.location,"town")
	assert_eq(shell.town._player_cell(),TDHarbor.ARRIVAL)
	assert_true(shell.town._can_stand(shell.town._player.position),"east-quay berth remains clear on returning home")
	assert_eq(shell.profile.snapshot(),before)

func test_map_key_pause_return_and_no_remote_teleport_from_map() -> void:
	assert_true(shell.voyage("tokyo").ok)
	var key:=InputEventAction.new();key.action="world_map";key.pressed=true
	shell._input(key)
	assert_true(shell._map_open);assert_true(get_tree().paused);assert_false(shell.visiting.player.controls_enabled)
	var before:=shell.visiting.player.position
	shell._input(key)
	assert_false(shell._map_open);assert_false(get_tree().paused);assert_true(shell.visiting.player.controls_enabled)
	assert_eq(shell.visiting.player.position,before)
	shell.visiting.player.position=Vector2(20.5,20.5)*shell.visiting.cell_size
	assert_eq(shell.voyage("paris").code,"NOT_AT_PORT")
	assert_eq(shell.visiting_town,"tokyo")

func test_unknown_destination_and_protected_water_and_paused_clock() -> void:
	var before:=shell.profile.snapshot()
	assert_false(shell.voyage("bad-town").ok);assert_eq(shell.profile.snapshot(),before)
	assert_false(shell.voyage("mexico_city").ok)
	assert_true(shell.voyage("tokyo").ok)
	var safe:=shell.visiting.player.position
	assert_false(shell.visiting._confine(Vector2(.5,.5)*TDTownWorld.CELL))
	shell.show_world_map();var minute:=shell.profile.characters.clock.minute
	shell.advance_world_time(30);assert_eq(shell.profile.characters.clock.minute,minute)
	shell._close_dialog()

func test_saved_branch_footprints_are_same_on_travel_map() -> void:
	var home: TDTownMap=shell.profile.world.town_map
	var copy:=TDTravelCatalog.map_for(shell.profile,"chengdu")
	assert_eq(copy.roads,home.roads);assert_eq(copy.plots,home.plots)
	copy.plots.clear();assert_false(home.plots.is_empty())
	var tex:=TDTravelCatalog.sprite("paris",0) as AtlasTexture
	assert_eq(tex.atlas.resource_path,"res://assets/town/restaurant-european-v1.png")
	assert_eq(tex.margin,Rect2(),"Facade no longer uses collision padding as sprite art")
	var house:=TDTravelCatalog.sprite("paris",1) as AtlasTexture
	assert_true(Rect2(384,256,384,256).encloses(house.region),"Trimming stays in the appropriate sheet cell")
	assert_lt(house.region.size.x,384.0,"Transparent edges are removed before scaling")

func test_facade_ownership_and_civic_landmarks_across_all_five_towns() -> void:
	for town: String in TDTravelCatalog.IDS:
		var map := TDTravelCatalog.map_for(shell.profile,town)
		var branch := {"id":"branch", "kind":"player_diner", "branch_id":"branch"}
		var brand := TDTravelCatalog.facade(town, branch)
		assert_eq(brand, TDTravelCatalog.BRANCH_EXTERIORS[town])
		branch.construction = true
		assert_eq(TDTravelCatalog.facade(town, branch), TDTravelCatalog.BRANCH_CONSTRUCTION)
		var civic := {}
		for parcel: Dictionary in map.plots:
			var kind := str(parcel.kind)
			var art := TDTravelCatalog.facade(town,parcel) as AtlasTexture
			if kind != "player_diner": assert_ne(art.atlas,brand,town + ":" + kind)
			if kind in ["hotel","bank","market","plaza","landmark","urban_village"]:
				civic[kind] = str(art.atlas.resource_path) + str(art.region)
		assert_eq(civic.size(),6,town)
		assert_eq(TDTravelCatalog.facade(town,{"kind":"hotel"}).atlas.resource_path,TDTravelCatalog.CIVIC)
		assert_eq(TDTravelCatalog.facade(town,{"kind":"plaza"}).atlas.resource_path,TDTravelCatalog.NEIGHBORHOODS)
		for kind: String in civic:
			assert_eq(civic.values().count(civic[kind]),1,town + ":" + kind)

func test_shiomi_counter_opens_from_the_shop_door_and_sells_local_unlocked_ingredients() -> void:
	assert_true(shell.voyage("tokyo").ok)
	var world:=shell.visiting
	var fronts:=world._buildings.filter(func(entry:Dictionary)->bool:return entry.plot.id=="market-neighborhood")
	assert_eq(fronts.size(),1)
	if fronts.is_empty(): return
	var base: Rect2=fronts[0].base
	world.player.position=Vector2(base.get_center().x,base.end.y+12)
	assert_true(world._can_stand(world.player.position))
	assert_eq(TDTravelCatalog.label(world.nearby(),"tokyo"),"町内食材铺")
	var interact:=InputEventAction.new();interact.action="world_interact";interact.pressed=true
	world._unhandled_input(interact)
	assert_not_null(shell._modal_box)
	if shell._modal_box==null: return
	assert_false(shell._modal_box.find_children("*","TDIngredientIcon",true,false).any(
		func(icon: TDIngredientIcon) -> bool: return icon.item_id == "udon"))
	shell._close_dialog()
	assert_true(shell.profile.research.learn_story("story:local_market_test","jp",["J03"]).ok)
	world._unhandled_input(interact)
	var tabs:=shell._modal_box.find_children("*","TabBar",true,false)
	assert_eq(tabs.size(),1)
	if tabs.is_empty(): return
	var rows: Dictionary={}
	for icon: TDIngredientIcon in shell._modal_box.find_children("*","TDIngredientIcon",true,false):
		rows[icon.item_id]=icon.get_parent()
	assert_eq(rows.size(),shell.profile.shop.local_market_ids("tokyo").size())
	assert_does_not_have(rows,"tortilla")
	for id: String in ["udon","salt"]:
		assert_has(rows,id)
		if not rows.has(id): return
		(tabs[0] as TabBar).current_tab=0 if id=="udon" else 1
		assert_true((rows[id] as Control).is_visible_in_tree(),id)
		var before:=shell.profile.shop.available(id)
		var button: Button=rows[id].find_children("*","Button",true,false).back()
		assert_eq(button.text,"购买")
		button.pressed.emit()
		assert_eq(shell.profile.shop.available(id),before+1000)

func test_service_can_leave_but_procurement_policy_stays_separate() -> void:
	assert_true(shell.kitchen_view.buy_kit("service.tomato_egg").ok)
	assert_true(shell.profile.shop.open_day().ok)
	assert_true(shell.travel("restaurant").ok);assert_true(shell.travel("town").ok)
	shell.town.spawn_at_harbor();assert_true(shell.voyage("tokyo").ok)
	assert_false(shell.profile.can_leave_shop()) # existing purchase boundary, not travel permission
	assert_true(shell.kitchen_view.staff_status().contains("缺厨师"))

func test_night_brings_the_player_to_local_lodging_and_rejects_stale_travel() -> void:
	assert_true(shell.voyage("paris").ok)
	shell.advance_world_time(TDWorldDayClock.END_MINUTE-shell.profile.characters.clock.minute)
	assert_not_null(shell.visiting)
	assert_eq(shell.location,"voyage")
	assert_eq(shell.visiting_town,"paris")
	assert_eq(shell.visiting.nearby().kind,"hotel")
	assert_eq(shell.profile.characters.clock.closed_day,shell.profile.characters.clock.day)
	assert_eq(shell.voyage("tokyo").code,"NIGHT_CLOSED")

func test_player_pot_and_missing_cook_are_never_taken_over() -> void:
	var view:=shell.kitchen_view
	assert_true(view.buy_kit("service.tomato_egg").ok)
	assert_true(shell.profile.shop.open_day().ok)
	var lane: TDCookingLane=view.kitchen.lanes[0]
	assert_true(lane.perform("add",{"ingredient_id":"tomato","amount":1.0}).ok)
	var before:=lane.snapshot();view.staff_away=true;view.tick_staff()
	assert_eq(lane.snapshot(),before)
	shell.profile.employees.state.owned["cook-he"]={"id":"cook-he","copies":1,"xp":0,"assigned":""}
	assert_eq(shell.profile.employees.assign("cook-he","player_diner").code,"NOT_AT_BOUNDARY")
	# Staffing fixture for the takeover boundary; player reassignment during OPEN remains forbidden.
	shell.profile.employees.state.owned["cook-he"].assigned="player_diner"
	shell.profile.employees.sync_main_crew()
	view.tick_staff();assert_eq(lane.snapshot(),before)
	shell._pause(true);view.tick_staff();assert_eq(lane.snapshot(),before);shell._pause(false)

func test_employee_cook_uses_real_qte_stock_and_does_not_grant_mastery() -> void:
	# Real standalone shop + front room, with deterministic default arrival clock.
	var catalog:=TDServiceCatalog.new();assert_true(catalog.load_file().ok)
	var shop:=TDShopSession.new(catalog,"staff-travel",59)
	var room:=TDRestaurantWorld.new();room.player_mode=true;room.floor_service=true;room.business=shop
	add_child(room);room.bind_dining_clock()
	var view:=TDShopView.new();view.service=catalog;view.shop=shop;view.embedded=true
	view.save_path="res://artifacts/travel/staff-%d.json"%Time.get_ticks_usec();add_child(view);view.kitchen.auto_advance=false
	shop.crew=room.layout.crew;assert_true(shop.crew.hire("cook-he").ok)
	assert_true(shop.buy(shop.offer("service.tomato_egg").stock,"staff-stock").ok)
	for id: String in shop.snapshot().menu: shop.set_menu(id,id=="service.tomato_egg",1200)
	assert_true(shop.open_day().ok);view.staff_away=true
	var before: int=shop.available("tomato")
	for n: int in 1500: view.kitchen.advance(.1)
	var served: Array=shop.snapshot().orders.filter(func(o:Dictionary)->bool:return o.status=="SERVED")
	assert_gt(served.size(),0,"employee real dish reaches original delivery")
	assert_lt(shop.available("tomato"),before)
	assert_eq(shop.mastery("service.tomato_egg").points,0.0)
	var after: int=int(shop.snapshot().money_cents)
	for n: int in 10: view.tick_staff()
	assert_eq(shop.snapshot().money_cents,after)
	view.close();room.close();view.queue_free();room.queue_free();await wait_process_frames(2)

func held(action: String, frames: int, sprint: bool=false) -> Vector2:
	var before:=shell.visiting.player.position
	Input.action_press(action)
	if sprint: Input.action_press("world_sprint")
	for i: int in frames: await get_tree().physics_frame
	Input.action_release(action);Input.action_release("world_sprint")
	await get_tree().physics_frame
	return shell.visiting.player.position-before

func test_actual_physics_movement_sprint_collision_pause_and_reentry_all_towns() -> void:
	for id: String in TDRegionalLayout.IDS:
		assert_true(shell.voyage(id).ok,id)
		var view:=shell.visiting;var start:=view.player.position
		assert_true(view._confine(start),id+" arrival collision-free")
		var walk:=await held("world_left",10)
		assert_gt(walk.dot(Vector2.LEFT),12.0,id+" actual held movement from arrival")
		view.player.position=start
		var sprint:=await held("world_left",10,true)
		assert_gt(sprint.length(),walk.length()*1.3,id+" Shift movement")
		if view.map.egret:
			view.player.position=start
			var to_water:=await held("world_left",70,true)
			assert_lt(to_water.x,0.0,id+" walks along the passenger deck")
			assert_true(view._can_stand(view.player.position))
			assert_false(view._can_stand(view.player.position+Vector2.LEFT*6),id+" sprint stops at the water")
		# Hold against a real rendered building base: stop outside it, no acceleration.
		var bank: Dictionary=view._buildings.filter(func(part:Dictionary)->bool:return part.plot.id=="commercial_street:bank").front()
		var wall: Rect2=bank.base
		var facade: Rect2=bank.rect
		assert_true(facade.encloses(wall),id+" rendered footprint stays within the actual facade")
		view.player.position=Vector2(wall.get_center().x,wall.end.y+25)
		await held("world_up",30)
		if view.map.egret or view.map.shiomi:
			# Transparent foundation margins and steps make the service box deeper than the stone.
			assert_true(view._can_stand(view.player.position),id+" feet stop on clear ground")
			assert_false(view._can_stand(view.player.position+Vector2.UP*6),id+" further motion enters the painted foundation")
			assert_gt(view.player.position.y,wall.get_center().y,id+" player stays in front of the building")
		else:
			assert_gte(view.player.position.y,wall.end.y+8.5,id+" building collision")
		assert_lt(view.player.position.y,wall.end.y+25,id+" approached wall")
		shell.show_world_map();var frozen:=view.player.position
		Input.action_press("world_down")
		await wait_process_frames(5)
		assert_eq(view.player.position,frozen,id+" frozen under map")
		Input.action_release("world_down");shell._close_dialog()
		view.player.position=start
		assert_gt((await held("world_left",6)).length(),10.0,id+" controls restored")
		view.player.position=start
	assert_true(shell.voyage("chengdu").ok)
	assert_true(shell.voyage("tokyo").ok)
	assert_gt((await held("world_left",8)).length(),15.0,"reentry has a live input callback")

func test_world_map_five_towns_wheel_anchor_drag_and_limits() -> void:
	var unlaid := TDTravelMapView.new()
	unlaid.zoom_at(Vector2.ZERO,1.5)
	assert_true(unlaid.pan.is_finite(),"按 M 后布局完成前滚动也不会丢失地图中心")
	unlaid.free()
	shell.show_world_map()
	var view: TDTravelMapView
	for child: Node in shell._modal_box.get_children():
		if child is TDTravelMapView: view=child
	assert_not_null(view)
	await wait_process_frames(2)
	assert_eq(view.maps.size(),3)
	var cursor:=view.size*.5;var anchor:=view.screen_to_world(cursor)
	var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_WHEEL_UP;event.pressed=true;event.position=cursor
	view._gui_input(event)
	assert_gt(view.zoom,1.0)
	assert_lt(view.screen_to_world(cursor).distance_to(anchor),.001,"cursor anchored zoom")
	var press:=InputEventMouseButton.new();press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true;view._gui_input(press)
	var motion:=InputEventMouseMotion.new();motion.relative=Vector2(40,20);motion.position=cursor;view._gui_input(motion)
	assert_eq(view.pan,Vector2(40,20))
	press.pressed=false;view._gui_input(press)
	for i: int in 20: view.zoom_at(cursor,1.5)
	assert_eq(view.zoom,5.0)
	view.reset_view();assert_eq(view.zoom,1.0);assert_eq(view.pan,Vector2.ZERO)
	assert_eq(shell.visiting_town,"chengdu","atlas never teleports")
	assert_eq(view.focused_town(),"")
	for id: String in TDTravelCatalog.IDS:
		view.focus_town(id)
		assert_eq(view.focused_town(),id,"Live local map is separate from world illustration")
	view.reset_view()
	assert_eq(view.focused_town(),"")

func test_regional_migration_keeps_old_bytes_until_the_next_checkpoint() -> void:
	var p:=shell.profile
	# This fixture predates the supplied regional storefronts and their surveyed lots.
	p.branches.state.stores.clear()
	p.branches.state.serial=0
	p.region_layout_version=1
	for id: String in TDRegionalLayout.IDS: p.commerce.expansion.state.parcels.erase(id)
	p._wire_commerce()
	assert_true(shell.profile.save().ok)
	var path:=shell.slots.path_for("slot-01");var bytes:=FileAccess.get_file_as_bytes(path)
	shell.slots.interrupt_at="after_temp"
	assert_true(shell.load_game("slot-01").ok)
	assert_true(shell.profile.region_migrated_on_load)
	assert_eq(FileAccess.get_file_as_bytes(path),bytes,"Loading the migrated profile never rewrites the original")
	assert_eq(shell.profile.branches.state.stores.size(),2,"new storefronts are added after migration")
	shell.slots.interrupt_at=""
	shell.guide.dialogue.finish_now()
	shell._sleep("chengdu",0)
	var daily := shell.slots.load_slot("slot-01",TDProfileStore.DAILY)
	assert_true(daily.ok,daily.code)
	assert_eq(int(daily.data.region_layout_version),TDEgretLayout.CURRENT_VERSION)
	assert_eq(FileAccess.get_file_as_bytes(path),bytes)
	assert_true(shell.load_game("slot-01").ok)
	assert_false(shell.profile.region_migrated_on_load)
