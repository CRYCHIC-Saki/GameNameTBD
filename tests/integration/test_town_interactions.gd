extends GutTest

var profile: TDGameProfile

func before_each() -> void:
	profile=TDGameProfile.new()
	profile.slot_id="slot-01"
	assert_true(profile.error.ok,profile.error.code)

func after_each() -> void:
	profile.close()

func test_walkable_towns_keep_nameplates_on_real_facades_and_ignore_housing() -> void:
	var town := TDTownWorld.new()
	town.player_mode = true
	town.management_menus = true
	town.session = profile.world
	add_child_autofree(town)
	watch_signals(town)
	for plot: Dictionary in profile.world.town_map.plots:
		if plot.kind not in TDInteractionRange.RESIDENTIAL_KINDS: continue
		assert_false(TDInteractionRange.facility(plot), plot.id)
	var ferry_homes := profile.world.town_map._by_id("ferry-homes")
	assert_false(ferry_homes.is_empty())
	assert_false(town._interactable_facades.has("ferry-homes"))
	town.spawn_at_plot("ferry-homes")
	var interact := InputEventAction.new()
	interact.action = "world_interact"
	interact.pressed = true
	town._unhandled_input(interact)
	assert_signal_not_emitted(town, "place_requested")
	assert_null(town._status_panel)
	town.spawn_at_plot("hotel")
	var plate := town._building_nameplate
	town._update_building_nameplate()
	assert_true(plate.visible)
	assert_eq(plate._facade, town._interactable_facades.hotel.rect)
	var before := plate.position
	var original_anchor := plate._world_anchor
	var view_offset := Vector2(72, 44)
	town._camera.offset += view_offset
	town._camera.force_update_scroll()
	town._update_building_nameplate()
	assert_eq(plate._world_anchor, original_anchor)
	assert_eq(plate.position, before - view_offset)
	town.spawn_at_plot("ferry-homes")
	town._update_building_nameplate()
	assert_false(plate.visible)
	town.close()
	for region: String in ["tokyo", "paris"]:
		var visit := TDTravelWorld.new()
		visit.town_id = region
		visit.map = TDTravelCatalog.map_for(profile, region)
		add_child_autofree(visit)
		assert_eq(visit._layer.get_child_count(), 1, region + " has no bottom banner")
		for front: Dictionary in visit._buildings:
			var plot: Dictionary = front.plot
			if plot.get("kind") not in TDInteractionRange.RESIDENTIAL_KINDS: continue
			var base: Rect2 = front.base
			assert_ne(visit._target_at(base.get_center() + Vector2(0, base.size.y * .5 + 12)).get("id"), plot.id)
		var access := visit.landmark_access("landmark", "landmark")
		assert_true(access.is_finite())
		if access.is_finite():
			visit.player.position = access
			visit.camera.position = access
			visit.camera.force_update_scroll()
			visit._process(0)
			assert_true(visit._building_nameplate.visible)
			assert_eq(visit._target.id, "landmark")
		visit.close()

func test_market_lists_and_validates_the_same_local_unlocked_foods() -> void:
	assert_true(profile.shop.local_market_sells("egg","chengdu"))
	var locked: String=""
	var imports: String=""
	for id: String in profile.shop.market_ids("chengdu"):
		if not profile.shop.local_market_sells(id,"chengdu"):
			locked=id
			break
	for id: String in profile.shop.purchase_ids():
		if not TDMaterialCatalog.supplies("chengdu",id):
			imports=id
			break
	assert_ne(locked,"","a local but locked food exists")
	assert_eq(profile.buy({locked:1000}).code,"INGREDIENT_LOCKED")
	if not imports.is_empty(): assert_eq(profile.buy({imports:1000}).code,"INGREDIENT_LOCKED")
	var stock := int(profile.commerce.state.markets.chengdu.stock.egg)
	assert_true(profile.buy({"egg":1000}).ok)
	assert_eq(int(profile.commerce.state.markets.chengdu.stock.egg),stock-1000)
	var lessons := {"chengdu":["C01","C02","C15","C20"],"paris":["E02","E03","E06"],"tokyo":["J01","J02","J03","J04"]}
	for town: String in lessons:
		var cuisine: String = {"paris":"eu","tokyo":"jp","chengdu":"cn"}[town]
		assert_true(profile.research.learn_story("story:test:"+town,cuisine,lessons[town]).ok)
		for recipe: Dictionary in TDMaterialCatalog.recipes():
			if recipe.id not in lessons[town]: continue
			for material: String in recipe.ingredients+recipe.seasonings:
				assert_true(profile.shop.local_market_sells(material,town),town+" "+recipe.id+" "+material)

func test_all_six_relationships_follow_story_and_same_day_chat_is_idempotent() -> void:
	var state := TDRevisedMainline.initial()
	var roster := profile.characters
	var old_save := roster.snapshot()
	for id: String in TDRevisedMainline.FIRST_ENCOUNTERS:
		if id not in TDCharacterRoster.ORIGINAL_RESIDENTS: old_save.records.erase(id)
	assert_true(roster.restore(old_save,1).ok)
	roster.sync_story_encounters(state)
	for id: String in TDRevisedMainline.FIRST_ENCOUNTERS:
		assert_false(roster.can_chat(id))
	for step: int in 21:
		var node: Dictionary=TDRevisedMainline.data().nodes[step]
		state.completed.append(node.id)
		roster.sync_story_encounters(state)
		for id: String in TDRevisedMainline.FIRST_ENCOUNTERS:
			assert_eq(roster.can_chat(id),TDRevisedMainline.FIRST_ENCOUNTERS[id] in state.completed,id)
	for id: String in TDRevisedMainline.FIRST_ENCOUNTERS:
		var initial := roster.conversation(id)
		initial.begin()
		assert_false(initial.body.is_empty(),id)
		assert_eq(roster.complete_chat(initial.context,false,["chat"]).code,"CHAT_CANCELLED")
		assert_eq(roster.complete_chat(initial.context,true,["chat"]).code,"RELATIONSHIP_CHANGED")
		assert_eq(roster.complete_chat(initial.context,true,["chat"]).code,"CHAT_ALREADY_COUNTED")
		roster.records[id].affection=65
		var close := roster.conversation(id)
		close.begin()
		assert_ne(initial.body,close.body,id)
		assert_not_null(TDStoryArt.portrait(id))

func test_old_daily_books_migrate_to_new_curve_and_unlock_rewards_once() -> void:
	var old_config := profile.progression.config.duplicate(true)
	old_config.rules_version=1
	old_config.daily=TDLevelProgression.LEGACY_DAILY.duplicate()
	profile.progression=TDLevelProgression.new(old_config)
	profile.initialize_progression()
	assert_true(profile.shop.open_day().ok)
	assert_true(profile.shop.advance(360).ok)
	assert_true(profile.shop.close_for_night().ok)
	assert_true(profile.settle_progression().ok)
	var legacy := profile.snapshot()
	var xp := int(legacy.progression.total_xp)
	assert_gt(xp,0)
	assert_true(TDGameProfile.validate_save(legacy).ok)
	var restored := TDGameProfile.new()
	var result := restored.restore(legacy)
	assert_true(result.ok,result.code)
	assert_eq(int(restored.progression.snapshot().rules_version),2)
	assert_eq(int(restored.progression.progress().total_xp),xp)
	assert_eq(restored.progression.threshold(20),570)
	assert_lt(restored.progression.threshold(20),restored.progression.threshold(20,1))
	assert_eq(restored.progression.decoration_unlocked("screen"),xp>=12)
	assert_true(restored.progression.decoration_unlocked("floor_japanese"))
	var migrated := restored.snapshot()
	assert_true(TDGameProfile.validate_save(migrated).ok)
	var reloaded := TDGameProfile.new()
	assert_true(reloaded.restore(migrated).ok)
	assert_eq(reloaded.research.snapshot().events,restored.research.snapshot().events)
	restored.close()
	reloaded.close()

func test_inspiration_and_counter_rules() -> void:
	var points := int(profile.research.snapshot().points)
	assert_true(profile.research.record_cooking(1,"test-cooking",75).ok)
	assert_eq(profile.research.record_cooking(1,"test-cooking",90).code,"ALREADY_APPLIED")
	assert_eq(int(profile.research.snapshot().points),points+2)
	assert_false(profile.layout.piece_by_kind("cashier").is_empty())
	assert_true(profile.layout.piece_by_kind("welcome_desk").is_empty())
	assert_eq(profile.layout.place("order_counter",5,2,0).code,"COUNTER_LIMIT")
	assert_false(TDInteractionRange.npc_clear(Vector2(-40,0),Vector2(40,0),Vector2.ZERO,28))
	assert_true(TDInteractionRange.npc_clear(Vector2(4,0),Vector2(10,0),Vector2.ZERO,28))

func test_paid_hotel_and_cottage_sleep_work_during_preparation_and_reload() -> void:
	var app: TDApplication = load("res://src/app/main.tscn").instantiate()
	app.settings_path = "res://artifacts/town-interactions-20261126/tests/%d/settings.json" % Time.get_ticks_usec()
	add_child_autofree(app)
	var shell := app.game_shell
	shell.automatic_time=false
	profile.slot_id="slot-01"
	profile.persistence=shell.slots.save_slot
	shell._activate(profile)
	var before := int(profile.shop._s.money_cents)
	shell.town.spawn_at_plot("hotel")
	assert_eq(shell.town.facing_plot().get("kind"),"hotel")
	shell.town._interact()
	assert_not_null(shell._modal_box)
	for button: Button in shell._modal_box.find_children("*","Button",true,false):
		if button.text.begins_with("支付"): button.pressed.emit(); break
	assert_eq(int(profile.shop._s.day),2)
	assert_eq(int(profile.shop._s.money_cents),before-600)
	assert_eq(profile.rest_town,"chengdu")
	assert_eq(shell.town.facing_plot().get("kind"),"hotel")
	assert_eq(int(profile.progression.progress().total_xp),0)
	assert_true(shell.slots.load_slot("slot-01").ok)
	profile.residence.stage="unlocked"
	assert_true(shell.travel("cottage").ok)
	shell.show_rest()
	for button: Button in shell._modal_box.find_children("*","Button",true,false):
		if button.text=="休息到明天": button.pressed.emit(); break
	assert_eq(int(profile.shop._s.day),3)
	assert_eq(profile.rest_town,"")
	assert_eq(shell.location,"cottage")
	assert_true(shell.slots.load_slot("slot-01").ok)
	shell.go_title()
	await get_tree().process_frame

func test_remote_story_hotels_and_landmark_dialogue_use_real_interaction() -> void:
	var app: TDApplication = load("res://src/app/main.tscn").instantiate()
	app.settings_path = "res://artifacts/town-interactions-20261126/tests/%d/settings.json" % Time.get_ticks_usec()
	add_child_autofree(app)
	var shell := app.game_shell
	shell.automatic_time=false
	profile.persistence=shell.slots.save_slot
	profile.story.begin()
	profile.story.beat="done"
	profile.branches.install_completed_storefronts()
	shell._activate(profile)
	for row: Array in [["paris",8,"vito"],["tokyo",13,"hina"]]:
		var place: String = row[0]
		var state := TDRevisedMainline.initial()
		for step: int in int(row[1]):
			var node: Dictionary = TDRevisedMainline.data().nodes[step]
			if node.kind=="dialogue": TDRevisedMainline.complete_dialogue(state,node.id,true)
			else: TDRevisedMainline.complete_action(state,node.id)
		state.lodging=place
		profile.story.revised=state
		profile.characters.sync_story_encounters(state)
		assert_true(shell._arrive(place).ok)
		var visit := shell.visiting
		var actor := visit._town_actor
		assert_true(actor.visible)
		var feet := actor.position
		var edge := Vector2.INF
		for direction: Vector2 in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
			var near := feet+direction*46.0
			if visit._can_stand(near): edge=near;break
		assert_true(edge.is_finite())
		if edge.is_finite():
			visit.player.position=edge
			visit.player.face(feet-edge)
			assert_false(visit._confine(feet))
			var press := InputEventAction.new()
			press.action="world_interact";press.pressed=true
			visit._unhandled_input(press)
			assert_eq(shell.guide.dialogue.talk.context.get("character_id"),row[2])
			shell.guide.dialogue.talk.skip()
			shell.guide.dialogue._choose("chat")
			shell.guide.dialogue.talk.skip()
			shell.guide.dialogue._emit_if_finished()
			assert_eq(int(profile.characters.relationship(row[2]).affection),5)
		var sight := visit.landmark_access("landmark","landmark")
		assert_true(sight.is_finite())
		if sight.is_finite():
			visit.player.position=sight
			shell._travel_landmark(visit.nearby())
			assert_eq(shell.guide.dialogue.talk.context.kind,"landmark")
			assert_gt(shell.guide.dialogue.talk.body.length(),15)
			assert_true(shell.guide.dialogue._panel.visible)
			assert_false(shell.guide.dialogue._portrait.visible)
			assert_false(shell.guide.dialogue._right_portrait.visible)
			shell.guide.dialogue.talk.skip()
			shell.guide.dialogue._emit_if_finished()
		shell._arrive_at_lodging(place)
		assert_eq(shell._hotel_fee(place),0)
		var training_open := place=="paris"
		if training_open:
			assert_true(profile.research.learn_story("story:test-training","eu",["E02"]).ok)
			TDRevisedMainline.mark(state,"mentors_paris")
			shell._enter_story_branch(place)
			var site := profile.branches.training_store()
			var recipe: String = profile.research.catalog.chart("E02").recipe_id
			var matching := profile.branches.recipes("eu").filter(func(item: Dictionary) -> bool: return item.id==recipe)
			var menu: Dictionary = matching[0]
			assert_true(profile.branches.configure_store(site,[{"id":recipe,"price_cents":menu.reference_cents}],0).ok)
			assert_true(profile.buy(menu.ingredients,place).ok)
			assert_true(profile.branches.open_training(site).ok)
			var group: String = profile.commerce.config.groups[0].id
			assert_true(profile.branches.sell(site,recipe,profile.commerce.society.identity(place,group,0)))
			assert_eq(shell.branch_visit.kitchen_session.pending_orders().size(),1)
			shell._arrive_at_lodging(place)
		var before := int(profile.shop._s.money_cents)
		var day := int(profile.shop._s.day)
		shell._travel_landmark(shell.visiting.nearby())
		for button: Button in shell._modal_box.find_children("*","Button",true,false):
			if button.text=="休息到明天": button.pressed.emit();break
		assert_eq(int(profile.shop._s.day),day+1)
		if not training_open: assert_eq(int(profile.shop._s.money_cents),before)
		assert_false(profile.branches.training_open())
		assert_false(profile.shop._s.ledger.any(func(item: Dictionary) -> bool: return str(item.reference).begins_with("hotel:")))
		assert_true(shell.slots.load_slot("slot-01").ok)
		assert_eq(shell.visiting_town,place)
	shell.go_title()
	await get_tree().process_frame

func test_main_town_cast_can_be_reached_with_map_interaction() -> void:
	var app: TDApplication = load("res://src/app/main.tscn").instantiate()
	app.settings_path = "res://artifacts/town-interactions-20261126/tests/%d/settings.json" % Time.get_ticks_usec()
	add_child_autofree(app)
	var shell := app.game_shell
	shell.automatic_time=false
	profile.story.begin()
	profile.story.beat="done"
	var state := TDRevisedMainline.initial()
	for step: int in 21:
		var node: Dictionary=TDRevisedMainline.data().nodes[step]
		if node.kind=="dialogue": TDRevisedMainline.complete_dialogue(state,node.id,true)
		else: TDRevisedMainline.complete_action(state,node.id)
	profile.story.revised=state
	profile.characters.sync_story_encounters(state)
	shell._activate(profile)
	shell.guide.set_process(false)
	var town := shell.town
	town._process(0.0)
	var residents := {}
	for item: Dictionary in town._story_people(): residents[item.id]=town._person_feet(item)
	if is_instance_valid(town._hertz) and town._hertz.visible: residents.hertz=town._hertz.position
	if is_instance_valid(town._luo) and town._luo.visible: residents.luo=town._luo.position
	for id: String in ["aling","chen"]:
		var actor: TDStoryArt.TownActor = town._resident_sprites.get(id)
		assert_not_null(actor,id+" uses the same depth-sorted world layer as buildings")
		if actor!=null:
			assert_true(actor.get_parent().y_sort_enabled)
			assert_eq(actor.position,residents.get(id,Vector2.INF))
	for id: String in ["aling","chen","hertz","luo"]:
		assert_true(residents.has(id),id+" appears where players can find them")
		if not residents.has(id): continue
		var feet: Vector2 = residents[id]
		var interacted := false
		for direction: Vector2 in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
			var near := feet+direction*46.0
			if not town._can_stand(near): continue
			town._player.position=near
			town._player.face(feet-near)
			if town._story_faced()!=id: continue
			assert_false(town._player_step_clear(feet),id+" blocks the player")
			town._interact()
			assert_true(shell.guide.presenting(),id)
			if shell.guide.presenting():
				assert_eq(shell.guide.dialogue.talk.context.get("character_id"),id)
				shell.guide.dialogue.finish_now()
			interacted=true
			break
		assert_true(interacted,id+" is reachable by E")
	shell.go_title()
	await get_tree().process_frame
