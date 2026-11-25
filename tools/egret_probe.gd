extends SceneTree
## Exercise the same native scene through travel, cartography and commercial property.
var failures := 0
var checks := 0

func verify(ok: bool, label: String) -> void:
	checks+=1
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures+=1

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var output := "res://artifacts/west-port/game"
	var legacy_slot := ""
	var current_slot := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
		if arg.begins_with("--legacy-slot="): legacy_slot=arg.trim_prefix("--legacy-slot=")
		if arg.begins_with("--current-slot="): current_slot=arg.trim_prefix("--current-slot=")
	DirAccess.make_dir_recursive_absolute(output)
	var p:=TDGameProfile.new()
	verify(p.error.ok,"new game profile: "+p.error.code+" "+p.error.message)
	if not p.error.ok:
		p.close()
		quit(1)
		return
	var view:=SubViewport.new()
	view.world_2d=World2D.new()
	view.size=TDEgretLayout.SIZE
	view.disable_3d=true
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var world:=TDTravelWorld.new()
	world.town_id="paris"
	world.map=TDTravelCatalog.map_for(p,"paris")
	verify_land_use(world.map)
	if not current_slot.is_empty(): verify_existing_leases(current_slot,output)
	view.add_child(world)
	var start:=world.player.position
	verify(world.nearby().get("kind")=="harbor" and world._can_stand(start),"arrival on passenger deck")
	if legacy_slot.is_empty():
		await walk_to_fountain(world,output)
	else:
		# The full route runs after loading the previous executable's save below.
		Input.action_press("world_left")
		for i: int in 14: await physics_frame
		Input.action_release("world_left")
	verify(start.distance_to(world.player.position)>20,"actual movement from passenger arrival")
	for entry: Dictionary in world._buildings:
		if entry.plot.id=="harbor":
			world.player.position=Vector2(entry.base.get_center().x,entry.base.end.y+11)
			verify(world.nearby().get("id")=="harbor" and world._can_stand(world.player.position),"walkable ticket office counter")
			continue
		var base: Rect2=entry.base
		world.player.position=Vector2(base.get_center().x,base.end.y+11)
		verify(not world._can_stand(base.get_center()),str(entry.plot.id)+" solid footprint")
		verify(world._can_stand(world.player.position) and world.nearby().get("id")==entry.plot.id,str(entry.plot.id)+" walkable interaction")
	for px: Vector2 in [Vector2(1157,601),Vector2(810,408),Vector2(1539,419),Vector2(171,542),Vector2(694,984),Vector2(1464,1033),Vector2(2177,1030),Vector2(2020,830),Vector2(140,100),Vector2(235,800)]:
		verify(world._can_stand(TDEgretLayout.world_point(px)),"walkable surface "+str(px))
	for px: Vector2 in [Vector2(52,623),Vector2(452,754),Vector2(646,981),Vector2(108,422),Vector2(210,652),Vector2(118,523),Vector2(88,1060)]:
		verify(not world._can_stand(TDEgretLayout.world_point(px)),"blocked surface "+str(px))
	await walk_new_ground(world)
	await verify_marked_streets(world)
	var invalid_quay: TDOutcome=p.branches.quote("paris",[6,25,3,3],"cn")
	verify(not invalid_quay.ok,"public west quay cannot be bought as a branch site")
	var atlas:=TDTravelMapView.new()
	atlas.maps={"paris":world.map}
	view.add_child(atlas)
	verify(atlas._textures.paris is ViewportTexture and atlas.get_child(0).get_child(0).scene_file_path==world._island.scene_file_path,"atlas uses visitable scene")
	var arrival_on_chart: Vector2=atlas.ORIGINS.paris+start/world.cell_size/73.0*atlas.TOWN_SIZE
	verify(atlas._port_point("paris").is_equal_approx(arrival_on_chart),"chart ferry pin at actual boarding position")
	atlas.queue_free()
	var panel := TDBranchPanel.new()
	view.add_child(panel)
	panel.configure(p)
	panel.begin_site()
	panel.map_view.choose_town("paris")
	panel.map_view.picked.emit([55,45,8,6])
	verify(panel.selected_town=="paris" and panel.map_view.valid and not panel.site_button.disabled,"branch selection on west quay survey")
	for lawn: Array in [[27,22,5,4],[28,26,5,4],[55,23,5,4]]:
		panel.map_view.picked.emit(lawn)
		verify(panel.map_view.valid and not panel.site_button.disabled,"branch selector accepts cleared lawn "+str(lawn))
		var center := Rect2i(lawn[0],lawn[1],lawn[2],lawn[3]).get_center()
		var district: String = world.map.terrain_at(center).district_id
		verify(panel.quote_label.text.contains(TDEgretLayout.DISTRICT_NAMES[district]),"site quote shows surveyed district "+district)
	var matched_scene := false
	for child: Node in panel.map_view.get_children():
		if child is SubViewport and child.get_child_count()>0 and child.get_child(0).scene_file_path==world._island.scene_file_path:
			matched_scene=true
	verify(matched_scene,"site selection renders the walking scene")
	panel.queue_free()
	var site:=TDRegionMigration.find_site(world.map,[18,31,3,3])
	verify(site.size()==4,"free roadside branch site")
	for rect: Array in [[27,22,5,4],[28,26,5,4],[55,23,5,4],[18,38,4,3],[24,36,5,4],[43,46,5,4],[55,45,8,6],[39,47,8,6]]:
		verify(p.branches.quote("paris",rect,"cn").ok,"branch quote on open lawn "+str(rect))
	verify(p.branches.quote("paris",[44,38,5,4],"cn").code=="PROTECTED_LAND","inn rear wall excludes its former lawn overlay")
	verify(world.map.commercial_parcels().size()==6,"six distinct historical property titles")
	world.set_process(false)
	world._layer.visible=false

	world.player.hide()
	world.player.position=TDEgretLayout.world_point(Vector2(429,595))
	world.set_day_minute(720)
	if DisplayServer.get_name()!="headless":
		for shot: Array in [["egret-overview",Vector2(TDEgretLayout.SIZE)*.5,TDEgretLayout.PITCH/world.cell_size],["egret-square",Vector2(1160,505),1.15],["egret-harbor",Vector2(249,491),1.55]]:
			world.camera.zoom=Vector2.ONE*float(shot[2])
			world.camera.position=TDEgretLayout.world_point(shot[1])
			world.camera.reset_smoothing()
			await process_frame
			await RenderingServer.frame_post_draw
			verify(view.get_texture().get_image().save_png(output.path_join(str(shot[0])+".png"))==OK,"render "+str(shot[0]))
		world.player.position=TDEgretLayout.world_point(Vector2(855,378))
		verify(world._can_stand(world.player.position),"walkable spot beside the two-seat bench")
		world.player.show()
		world.camera.zoom=Vector2.ONE*1.5
		world.camera.position=TDEgretLayout.world_point(Vector2(450,294))
		world.camera.reset_smoothing()
		await route_photo(world,output,"egret-west-street")
	world.close()
	view.queue_free()
	p.close()
	await process_frame
	await process_frame
	if not legacy_slot.is_empty():
		await verify_old_slot(legacy_slot,output)
	print("%d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify_land_use(map: TDTownMap) -> void:
	var geo := TDEconomicGeography.new()
	geo.configure("paris",map.plots,{},2)
	for row: Array in [
		[Vector2i(5,36),"pier","river_quays","harbor"], [Vector2i(11,36),"quay","river_quays","harbor"],
		[Vector2i(14,37),"lawn","river_quays","harbor"], [Vector2i(1,44),"sea","river_quays","water"],
		[Vector2i(10,25),"lawn","workers_quarter","housing"], [Vector2i(42,25),"lawn","workers_quarter","supply_factory"],
		[Vector2i(22,29),"lawn","civic_square","bank"], [Vector2i(18,31),"lawn","civic_square","civic_square"],
		[Vector2i(22,31),"stone","civic_square","road"], [Vector2i(37,38),"square","civic_square","plaza"],
		[Vector2i(46,32),"stone","civic_square","market"], [Vector2i(17,42),"wheat","market_gardens","farmland"],
		[Vector2i(22,52),"earth","market_gardens","road"], [Vector2i(48,43),"lawn","inn_quarter","hotel"],
		[Vector2i(66,35),"lawn","commercial_street","competitor"], [Vector2i(66,27),"lawn","garden_quarter","landmark"],
		[Vector2i(52,47),"lawn","garden_quarter","garden_quarter"],
		[Vector2i(52,54),"outside","off_map","off_map"], [Vector2i(52,18),"outside","off_map","off_map"],
	]:
		var value := geo.cell(row[0])
		verify([value.surface_type,value.district_id,value.zone_id]==row.slice(1),"cell uses visible ground and venue "+str(row[0]))
	var all_valid := true
	var same_ground := true
	for y: int in map.extent:
		for x: int in map.extent:
			var at := Vector2i(x,y)
			var cell := geo.cell(at)
			all_valid = all_valid and TDEconomicCell.validate(cell).ok
			same_ground = same_ground and cell.buildable == map.branch_ground_available(at)
	verify(all_valid,"all 5329 cell snapshots pass economic validation")
	verify(same_ground,"economic buildability matches the live selection grid on all 5329 cells")
	verify(map.is_road(18,31) and not map.branch_ground_available(Vector2i(18,31)),"grass verge preserves legal street frontage")
	verify(is_equal_approx(geo.cell(Vector2i(43,31)).travel_minutes.market,2.0),"market delivery starts at actual door")
	verify(is_equal_approx(geo.cell(Vector2i(5,36)).travel_minutes.station,2.0),"passenger travel starts at west landing")
	verify(geo.cell(Vector2i(9,26)).travel_minutes.residential < 3.0,"northwest homes contribute residential traffic")
	verify(geo.cell(Vector2i(9,26)).travel_minutes.station > 2.0+14*.3,"passenger route detours around obstructions")
	var occupied := map.plots.duplicate(true)
	occupied.push_front({"id":"test-tenant","kind":"competitor","economic_parcel_id":"test-tenant","x":56,"y":23,"w":3,"h":3})
	geo.configure("paris",occupied,{},2)
	var tenant := geo.cell(Vector2i(57,24))
	verify(tenant.parcel_id=="test-tenant" and tenant.zone_id=="competitor" and tenant.district_id=="garden_quarter" and not tenant.buildable,"occupied frontage keeps both tenant and native survey")

func verify_existing_leases(path: String, output: String) -> void:
	var directory := output.path_join("current-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(directory)
	var slots := TDProfileStore.new(directory,TDGameProfile.validate_save)
	if DirAccess.copy_absolute(path,slots.path_for("slot-01")) != OK:
		verify(false,"copy previous package's current save")
		return
	var checked := slots.load_slot("slot-01")
	verify(checked.ok,"read signed current save through slot store: "+checked.code)
	if not checked.ok: return
	var original := checked.data
	var restored := TDGameProfile.new()
	var loaded := restored.restore(original)
	verify(loaded.ok and not restored.region_migrated_on_load,"current save reopens without relocation")
	if loaded.ok:
		var after := restored.snapshot()
		verify(original.branches.stores.size()==2 and TDLevelProgression.same_value(original.branches,after.branches),"previous package's two paid leases and inventories stay intact")
		verify(TDLevelProgression.same_value(original.economy.expansion.parcels.paris,after.economy.expansion.parcels.paris),"all six existing commercial titles keep their contracts")
	restored.close()

func key_event(key: Key, down: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = down
	return event

func steer(direction: Vector2) -> void:
	var keys := {KEY_A:direction.x < -.35, KEY_D:direction.x > .35,
		KEY_W:direction.y < -.35, KEY_S:direction.y > .35}
	for key: Key in keys:
		if Input.is_physical_key_pressed(key) != keys[key]:
			Input.parse_input_event(key_event(key,keys[key]))
	Input.flush_buffered_events()

func walk_new_ground(world: TDTravelWorld) -> void:
	world.player.position=TDEgretLayout.world_point(Vector2(330,390))
	steer(Vector2.DOWN)
	for i in 30: await physics_frame
	steer(Vector2.ZERO)
	var along:=world._island.to_local(world.player.position)
	verify(along.y>445 and world._can_stand(world.player.position),"walk along the west stone promenade")
	steer(Vector2.LEFT)
	for i in 35: await physics_frame
	steer(Vector2.ZERO)
	var edge:=world._island.to_local(world.player.position)
	verify(edge.x<along.x-8 and world._can_stand(world.player.position) and not world._can_stand(world.player.position+Vector2.LEFT*8),"west wall stops the player at the water")
	var farm_quay: Array[Vector2]=[Vector2(359,647),Vector2(345,667),Vector2(329,688),
		Vector2(306,703),Vector2(284,714),Vector2(261,729),Vector2(260,740),
		Vector2(252,755),Vector2(236,772),Vector2(205,790)]
	world.player.position=TDEgretLayout.world_point(farm_quay[0])
	verify(await follow_route(world,farm_quay.slice(1)),"walk the widened verge around the wheat field")
	var field_corner:=TDEgretLayout.terrain(Vector2i(11,40))
	verify(field_corner.surface_type=="quay" and field_corner.walkable and not field_corner.buildable,"new field-side paving shares the public quay survey")
	world.player.position=TDEgretLayout.world_point(Vector2(1464,1023))
	steer(Vector2.RIGHT)
	for i in 32: await physics_frame
	steer(Vector2.ZERO)
	verify(world._island.to_local(world.player.position).x>1525 and world._can_stand(world.player.position),"walk across the former southern bay")

func route_photo(world: TDTravelWorld, output: String, name_of_shot: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	var frame := world.get_viewport().get_texture().get_image()
	verify(frame.save_png(output.path_join(name_of_shot+".png"))==OK,"render "+name_of_shot)

func verify_marked_streets(world: TDTravelWorld) -> void:
	for y in [503,519,536,550]:
		var clear := true
		for x in range(300,343):
			clear=clear and world._can_stand(TDEgretLayout.world_point(Vector2(x,y)))
		verify(clear,"flush timber-to-stone crossing at "+str(y))
	var church: Array[Vector2] = [Vector2(2017,317),Vector2(1983,355),Vector2(1972,400),
		Vector2(1969,453),Vector2(1966,516),Vector2(1963,569)]
	var market: Array[Vector2] = [Vector2(1570,264),Vector2(1544,293),Vector2(1533,327),Vector2(1535,359)]
	var bank_side: Array[Vector2] = [Vector2(458,235),Vector2(473,265),Vector2(491,287),
		Vector2(490,319),Vector2(477,345),Vector2(461,372)]
	for lane: Array[Vector2] in [church,market,bank_side]:
		world.player.position=TDEgretLayout.world_point(lane[0])
		var wide := true
		for i in range(1,lane.size()):
			for j in range(17):
				var point:=lane[i-1].lerp(lane[i],float(j)/16)
				for offset in [-12,0,12]:
					wide=wide and world._can_stand(TDEgretLayout.world_point(point+Vector2(offset,0)))
		verify(wide,"continuous clear street width at "+str(lane[0]))
		verify(await follow_route(world,lane.slice(1)),"walk through marked street from "+str(lane[0]))
	world.player.position=TDEgretLayout.world_point(Vector2(700,426))
	var bank_entry: Array[Vector2] = [Vector2(695,408),Vector2(695,374)]
	verify(await follow_route(world,bank_entry) and world.nearby().get("id")=="commercial_street:bank",
		"walk from the street to the relocated bank entrance")

func walk_to_fountain(world: TDTravelWorld, output: String) -> void:
	var checkpoints: Array[Vector2] = [Vector2(235,542),Vector2(305,542),Vector2(332,532),
		Vector2(346,492),Vector2(354,447),Vector2(387,437),Vector2(428,433),Vector2(480,447),Vector2(527,447),
		Vector2(573,447),Vector2(625,444),Vector2(679,443),Vector2(765,411),Vector2(878,407),
		Vector2(961,416),Vector2(1018,449),Vector2(1073,479),Vector2(1097,533),Vector2(1097,548),Vector2(1127,548),Vector2(1157,544)]
	var start := world._island.to_local(world.player.position)
	verify(start.distance_to(Vector2(170.5,542.5))<1 and world.nearby().get("id")=="harbor","route begins at west passenger landing")
	await route_photo(world,output,"walk-departure")
	if not await follow_route(world,checkpoints): return
	verify(world.nearby().get("id")=="plaza","reached fountain interaction on foot")
	await route_photo(world,output,"walk-fountain")
	var received: Array = []
	world.landmark_requested.connect(func(plot: Dictionary)->void: received.append(plot.id),CONNECT_ONE_SHOT)
	for down: bool in [true,false]:
		world.get_viewport().push_input(key_event(KEY_E,down),true)
	verify(received==["plaza"],"E at fountain triggers plaza exactly once")

func follow_route(world: TDTravelWorld, checkpoints: Array[Vector2]) -> bool:
	for target: Vector2 in checkpoints:
		var origin := world._island.to_local(world.player.position)
		var heading := origin.direction_to(target)
		var foot := origin
		var budget := ceili(origin.distance_to(target)*2)+30
		while foot.distance_to(target)>1.8 and budget>0:
			var ahead := clampf((foot-origin).dot(heading)+7,0,origin.distance_to(target))
			steer(foot.direction_to(origin+heading*ahead))
			await physics_frame
			foot=world._island.to_local(world.player.position)
			budget-=1
		print("WALK target=",target," foot=",foot)
		if foot.distance_to(target)>1.8 or not world._can_stand(world.player.position):
			steer(Vector2.ZERO)
			verify(false,"unreachable walking checkpoint "+str(target))
			return false
	steer(Vector2.ZERO)
	return true

func verify_old_slot(fixture: String, output: String) -> void:
	var shell := TDGameShell.new()
	var folder := output.path_join("migration-%d"%Time.get_ticks_usec())
	shell.profile_root=folder.path_join("profiles")
	shell.preferences_path=folder.path_join("settings.json")
	shell.automatic_time=false
	root.add_child(shell)
	await exercise_old_slot(shell,fixture,output)
	shell.go_title()
	shell.queue_free()
	await process_frame
	await process_frame

func exercise_old_slot(shell: TDGameShell, fixture: String, output: String) -> void:
	var path := shell.slots.path_for("slot-01")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var copied := DirAccess.copy_absolute(fixture,path)
	verify(copied==OK,"copied old slot into isolated profile directory")
	if copied!=OK: return
	var original := FileAccess.get_sha256(fixture)
	var old := shell.slots.load_slot("slot-01")
	verify(old.ok and int(old.data.get("region_layout_version",0)) in [3,4,5,6,7,8,9,10],"valid historical slot: "+old.code+" "+old.message)
	if not old.ok: return
	var loaded := shell.load_game("slot-01")
	verify(loaded.ok,"load and migrate through game menu: "+loaded.code+" "+loaded.message)
	if not loaded.ok: return
	var current := shell.slots.load_slot("slot-01")
	verify(current.ok and current.data.get("region_layout_version")==11 and shell.profile.region_migrated_on_load,"west quay migration committed on disk")
	if not current.ok: return
	var backup := path+(".before-egret-v11.bak" if old.data.region_layout_version>=4 else ".before-egret-v4.bak")
	if shell.profile.regions_settled_on_load: backup=path+".before-three-towns.bak"
	verify(FileAccess.get_sha256(backup)==original,"pre-migration backup equals original save bytes")
	for field: String in ["money_cents","ledger","seen"]:
		verify(TDLevelProgression.same_value(current.data.shop[field],old.data.shop[field]),"preserved shop "+field)
	var before: Dictionary=old.data.economy.expansion.parcels.paris
	var after: Dictionary=current.data.economy.expansion.parcels.paris
	var map:=shell.profile.branches.town_map("paris")
	verify(map.egret and before.size()==6 and after.size()==6,"six historical properties on native map")
	for title: Dictionary in map.commercial_parcels():
		var id: String=title.id
		var prior: Dictionary=before.get(id,{}).duplicate(true)
		for field: String in TDRegionMigration.GEOMETRY: prior[field]=title[field]
		verify(TDLevelProgression.same_value(after.get(id),prior),"preserved ownership and value at surveyed frontage "+id)
	verify(old.data.branches.stores.size()==2 and current.data.branches.stores.size()==2,"both paid stores still registered")
	var occupied: Array[Rect2i]=[]
	for id: String in old.data.branches.stores:
		var prior: Dictionary=old.data.branches.stores[id].duplicate(true)
		var now: Dictionary=current.data.branches.stores.get(id,{})
		if now.is_empty():
			verify(false,"missing paid store "+id)
			continue
		var rect:=Rect2i(now.rect[0],now.rect[1],now.rect[2],now.rect[3])
		verify(now.rect.slice(2)==prior.rect.slice(2),"preserved original dimensions "+id)
		var clear:=map.branch_touches_road(rect)
		for y: int in range(rect.position.y,rect.end.y):
			for x: int in range(rect.position.x,rect.end.x):
				clear=clear and map.branch_ground_available(Vector2i(x,y))
		for other: Rect2i in occupied: clear=clear and not rect.intersects(other)
		occupied.append(rect)
		verify(clear,"valid separate roadside ground "+id)
		print("MIGRATION ",id," ",prior.rect," -> ",now.rect)
		for field: String in ["rect","place","site_survey"]: prior[field]=now.get(field)
		verify(now==prior and now.inventory.get("tomato")==5,"contract, inventory, costs and books preserved "+id)
	var migrated_hash:=FileAccess.get_sha256(path)
	shell.go_title()
	loaded=shell.load_game("slot-01")
	verify(loaded.ok and not shell.profile.region_migrated_on_load,"reopen migrated slot without a second migration")
	if not loaded.ok: return
	verify(FileAccess.get_sha256(path)==migrated_hash and FileAccess.get_sha256(backup)==original,"second load leaves slot and backup byte-identical")
	shell.travel("town")
	shell.town.spawn_at_harbor()
	var arrival:=shell.voyage("paris")
	verify(arrival.ok and shell.visiting!=null,"board passenger ferry with migrated profile: "+arrival.code)
	if arrival.ok: await walk_to_fountain(shell.visiting,output)
