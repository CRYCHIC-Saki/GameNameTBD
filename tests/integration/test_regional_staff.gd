extends GutTest

var profile: TDGameProfile

func before_each() -> void:
	profile=TDGameProfile.new()
	assert_true(profile.shop.world_adjustment(300000,"staff-funds","fixture").ok)

func after_each() -> void:
	profile.close()

func hire(town: String, role: String) -> Dictionary:
	var roster:=profile.employees
	var offer: Dictionary=roster.market_rows(town,role)[0]
	var result:=roster.sign_employee(offer.id,"hire-"+str(offer.id),offer.offer_key)
	assert_true(result.ok,result.code)
	return roster.employee_info(offer.id)

func test_cross_town_assignment_uses_restaurant_cuisine_and_auto_leaves_foreign_staff_idle() -> void:
	var roster:=profile.employees
	var store:="player-branch:1"
	profile.branches.state.stores[store]={"name":"江南日料","id":store,"town_id":"chengdu","cuisine_id":"jp","start_day":1,"construction":{"kind":"paid"}}
	var cook:=hire("tokyo","cook")
	var server:=hire("tokyo","waiter")
	var manager:=hire("paris","manager")
	var western_server:=hire("paris","waiter")
	var snapshot:=roster.snapshot()
	assert_eq(roster.assign(cook.id,roster.HOME).code,"CUISINE_MISMATCH")
	assert_eq(roster.assign(western_server.id,store).code,"CUISINE_MISMATCH")
	assert_eq(roster.snapshot(),snapshot)
	assert_true(roster.assign(manager.id,store).ok)
	assert_true(roster.auto_assign(store).ok)
	assert_eq(roster.employee_info(cook.id).assigned,store)
	assert_eq(roster.employee_info(server.id).assigned,store)
	assert_eq(roster.employee_info(western_server.id).assigned,"")
	assert_true(roster.ready_for(store))
	assert_eq(roster.auto_assign(roster.HOME).code,"STAFF_SHORTAGE")
	var interior:=TDBranchInterior.new()
	interior.profile=profile
	interior.store_id=store
	interior.layout=TDRestaurantLayout.make_sized(profile.layout._catalog,16,16,"jp")
	interior.dining=TDRestaurantWorld.new()
	interior.dining.player_mode=true
	interior.dining.layout=interior.layout
	interior.add_child(interior.dining)
	interior.iso=TDRestaurantIsoView.new()
	interior.add_child(interior.iso)
	interior.refresh_staff()
	var servers:=interior.iso.crew_people.filter(func(row: Dictionary)->bool: return row.role=="waiter")
	assert_eq(servers.size(),1)
	assert_eq(servers[0].actor_id,server.id)
	assert_eq(servers[0].cuisine_id,"jp")
	assert_eq(servers[0].appearance_variant,server.appearance_variant)
	assert_eq(interior.iso.crew_people.size(),1,"Managers have portraits only")
	interior.free()

func test_load_returns_mismatched_recruit_and_preserves_earned_wage_and_legacy_origin() -> void:
	var roster:=profile.employees
	var server:=hire("paris","waiter")
	roster.state.owned[server.id].assigned=roster.HOME
	roster.record_duties(1)
	var payroll:=roster.payroll_for(roster.HOME,1)
	var saved:=roster.snapshot()
	var branch:="player-branch:1"
	profile.branches.state.stores[branch]={"name":"日料","id":branch,"cuisine_id":"jp","start_day":1,"construction":{"kind":"paid"}}
	saved.owned["cook-he"]={"id":"cook-he","copies":1,"xp":2,"assigned":branch}
	var restored:=roster.restore(saved)
	assert_true(restored.ok,restored.code)
	assert_eq(roster.employee_info(server.id).assigned,"")
	assert_eq(roster.employee_info(server.id).town,"paris")
	assert_eq(roster.payroll_for(roster.HOME,1),payroll)
	assert_eq(roster.employee_info("cook-he").town,"tokyo")
	assert_eq(roster.employee_info("cook-he").assigned,branch)
	assert_true(roster.assign("cook-he","").ok)
	assert_true(roster.restore(roster.snapshot()).ok)
	assert_eq(roster.employee_info("cook-he").cuisine_id,"jp")

func test_all_dishes_honor_chef_specialty_and_cards_use_personal_art() -> void:
	var panel:=TDManagementPanels.EmployeePanel.new()
	add_child_autofree(panel)
	panel.configure(profile)
	var faces: Array=[]
	var bodies: Array=[]
	for town: String in TDEmployeeRoster.REGION_CUISINES:
		var cuisine: String=TDEmployeeRoster.REGION_CUISINES[town]
		for role: String in ["cook","waiter","manager"]:
			var offer: Dictionary=profile.employees.market_rows(town,role)[0]
			assert_eq(offer.gender,"female")
			assert_eq(offer.town,town)
			if role!="manager": assert_eq(offer.cuisine_id,cuisine)
			var card:=panel.person_card(offer)
			var portrait: TextureRect=card.find_children("*","TextureRect",true,false)[0]
			assert_eq(portrait.texture,TDEmployeeArt.portrait(cuisine,role,offer.appearance_variant))
			assert_false(portrait.texture.region in faces)
			faces.append(portrait.texture.region)
			if role=="manager":
				assert_null(TDEmployeeArt.sprite(cuisine,role,Vector2i.DOWN,-1,offer.appearance_variant))
				continue
			var idle:=TDEmployeeArt.sprite(cuisine,role,Vector2i.DOWN,-1,offer.appearance_variant)
			assert_false(idle.region in bodies)
			bodies.append(idle.region)
			assert_ne(idle,TDEmployeeArt.sprite(cuisine,role,Vector2i.DOWN,0,offer.appearance_variant))
			assert_ne(idle,TDEmployeeArt.sprite(cuisine,role,Vector2i.UP,-1,offer.appearance_variant))
			if role=="cook":
				for recipe: String in profile.service.cooking.recipe_ids():
					var actual: String=profile.service.cooking.recipe_data(recipe).get("cuisine_id","cn")
					assert_eq(profile.shop.cook_can_prepare(offer,recipe),actual==cuisine,recipe)
				var actor:=TDKitchenStaffActor.new()
				add_child_autofree(actor)
				actor.present({"point":Vector2.ZERO,"name":offer.name,"cuisine_id":cuisine,"appearance_variant":offer.appearance_variant,"facing":Vector2i.DOWN,"frame":-1,"phase":"idle","elapsed":0.0,"action":"待命","carried":""})
				assert_eq(actor.body.texture,idle)
	assert_eq(faces.size(),9)
	assert_eq(bodies.size(),6)

func test_every_town_and_role_uses_three_distinct_recruit_appearances() -> void:
	var roster:=profile.employees
	var groups: Dictionary={}
	var faces: Dictionary={}
	var bodies: Dictionary={}
	for definition: Dictionary in roster.config.fixed_employees:
		var row:=roster.employee_info(definition.id)
		var region: String=roster.REGION_CUISINES[row.town]
		var group: String=region+"-"+str(row.role)
		if not groups.has(group): groups[group]={}
		groups[group][row.appearance_variant]=true
		var face:=TDEmployeeArt.portrait(region,row.role,row.appearance_variant)
		assert_true(Rect2(Vector2.ZERO,face.atlas.get_size()).encloses(face.region))
		faces[face.region]=true
		if row.role!="manager":
			var walking:=TDEmployeeArt.sprite(region,row.role,Vector2i.UP,2,row.appearance_variant)
			assert_true(Rect2(Vector2.ZERO,walking.atlas.get_size()).encloses(walking.region))
			bodies[walking.region]=true
	assert_eq(groups.size(),9)
	for used: Dictionary in groups.values(): assert_eq(used.size(),3)
	assert_eq(faces.size(),27)
	assert_eq(bodies.size(),18)

func test_legacy_manager_keeps_hometown_and_appearance_on_transfer_and_reload() -> void:
	var roster:=profile.employees
	var store:="player-branch:1"
	profile.branches.state.stores[store]={"id":store,"name":"潮见欧陆餐馆","town_id":"tokyo","cuisine_id":"eu","start_day":1,"construction":{"kind":"paid"}}
	var raw:=roster.snapshot()
	raw.owned["manager.host"]={"id":"manager.host","copies":1,"xp":1,"assigned":store}
	assert_true(roster.restore(raw).ok)
	var before:=roster.employee_info("manager.host")
	assert_eq(before.town,"tokyo")
	assert_true(roster.assign(before.id,roster.HOME).ok)
	assert_true(roster.restore(roster.snapshot()).ok)
	var after:=roster.employee_info(before.id)
	assert_eq(after.town,before.town)
	assert_eq(after.name,before.name)
	assert_eq(after.appearance_variant,before.appearance_variant)
	assert_eq(after.assigned,roster.HOME)

func test_chef_breathes_at_fixed_feet_and_uses_stationary_pose_while_cutting() -> void:
	var actor := TDKitchenStaffActor.new()
	add_child_autofree(actor)
	var pose := {"point":Vector2(246,334),"name":"测试厨师","facing":Vector2i.LEFT,
		"frame":-1,"phase":"idle","elapsed":0.0,"carried":"","action":"待命","visual_seconds":0.0}
	actor.present(pose)
	var initial_scale := actor.body.scale
	var neutral := actor.body.texture
	var feet := Vector2(TDEmployeeArt.CELL_PX * 0.5,TDEmployeeArt.FOOT_Y)
	assert_gt(actor.body.texture.get_height()*initial_scale.y,100.0)
	assert_eq(actor.body.to_global(actor.body.offset+feet),pose.point)
	pose.visual_seconds=1.6
	actor.present(pose)
	assert_gt(actor.body.scale.y,initial_scale.y)
	assert_eq(actor.body.scale.x,initial_scale.x)
	assert_eq(actor.body.texture,neutral)
	assert_eq(actor.body.to_global(actor.body.offset+feet),pose.point)
	pose.phase="to_board"
	pose.frame=0
	actor.present(pose)
	assert_ne(actor.body.texture,neutral)
	assert_eq(actor.body.scale,initial_scale)
	pose.phase="cut"
	pose.elapsed=0.15
	actor.present(pose)
	assert_eq(actor.body.texture,TDEmployeeArt.sprite("cn","cook",Vector2i.UP,-1))
	assert_ne(actor.body.rotation,0.0)
	assert_eq(actor.body.to_global(actor.body.offset+feet),pose.point)

func test_wall_waiter_breath_uses_dining_clock_and_preserves_feet_and_spot() -> void:
	var room := TDRestaurantWorld.new()
	room.player_mode=true
	room.floor_service=true
	room.business=profile.shop
	add_child_autofree(room)
	room.bind_dining_clock()
	assert_true(room.layout.crew.hire("waiter-ning").ok)
	var first: Dictionary=room._crew_points(0)[0]
	assert_true(first.at_wall)
	room.advance_dining(1.6)
	var breathing: Dictionary=room._crew_points(0)[0]
	assert_eq(breathing.point,first.point)
	assert_ne(breathing.idle_lift,first.idle_lift)
	room.story_frozen=true
	room.advance_dining(1.6)
	assert_eq(room._crew_points(0)[0].idle_lift,breathing.idle_lift)
	room.close()
