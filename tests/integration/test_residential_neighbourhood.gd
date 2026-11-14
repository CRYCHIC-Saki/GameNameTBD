extends GutTest
const DRIVER=preload("res://tools/test_support/kitchen_input.gd")

func test_housing_groups_survive_reversed_plot_order_and_cover_each_free_cell_once() -> void:
	var profile:=TDGameProfile.new();var map:=profile.world.town_map
	var original:=map.plots.duplicate(true);var before: Dictionary=profile.snapshot()
	var groups:=TDTownArt.housing_groups(map)
	assert_true(groups.any(func(g:Dictionary)->bool:return int(g["size"])==3),"A complete 3x3 block must be homes, not nine planters")
	map.plots.reverse();assert_eq(TDTownArt.housing_groups(map),groups,"Same geometry, different dictionary order")
	map.plots=original
	var seen: Dictionary={}
	var cottage:=Rect2i(TDTownArt.facade_plot(map,map.cottage,1.0))
	for g: Dictionary in groups:
		for y: int in int(g["size"]):
			for x: int in int(g["size"]):
				var at: Vector2i=g.at+Vector2i(x,y)
				assert_false(seen.has(at));assert_false(cottage.has_point(at));seen[at]=true
	var expected:=map._home_cells()
	for y: int in cottage.size.y:
		for x: int in cottage.size.x: expected.erase(cottage.position+Vector2i(x,y))
	assert_eq(seen.size(),expected.size());assert_eq(profile.snapshot(),before)
	groups[0]["size"]=99;assert_ne(TDTownArt.housing_groups(map)[0]["size"],99,"Read-only query result")
	profile.close()

func test_residential_art_cannot_change_parcels_population_or_origin_distances() -> void:
	var profile:=TDGameProfile.new();var map:=profile.world.town_map
	var before: Dictionary=profile.snapshot()
	var geography:=TDEconomicGeography.new();geography.configure("chengdu",map.plots,{},2)
	var distances: Dictionary=geography.cell(Vector2i(14,40)).travel_minutes
	var town:=TDTownWorld.new();town.session=profile.world;town.player_mode=true;add_child_autofree(town)
	await get_tree().process_frame;await get_tree().process_frame
	for index: int in 4:
		var tile:=TDEnvironmentArt.residential(index)
		assert_gt(tile.region.size.x,300.0);assert_gt(tile.region.size.y,200.0)
		assert_true(Rect2(Vector2.ZERO,TDEnvironmentArt.RESIDENTIAL.get_size()).encloses(tile.region))
		assert_same(TDEnvironmentArt.residential(index),tile)
	assert_eq(profile.snapshot(),before)
	geography.configure("chengdu",map.plots,{},2)
	assert_eq(geography.cell(Vector2i(14,40)).travel_minutes,distances)
	profile.close()

func test_later_building_is_excluded_from_house_grouping() -> void:
	var profile:=TDGameProfile.new();var map:=profile.world.town_map
	var groups:=TDTownArt.housing_groups(map);var at: Vector2i=groups[0].at
	map.plots.push_front({"id":"test-owned-parcel","kind":"competitor","x":at.x,"y":at.y,"w":1,"h":1})
	for group: Dictionary in TDTownArt.housing_groups(map):
		assert_false(Rect2i(group.at,Vector2i.ONE*int(group["size"])).has_point(at))
	profile.close()

func test_actual_neighbourhood_notice_and_player_cottage_keep_separate_actions() -> void:
	var app:TDApplication=load("res://src/app/main.tscn").instantiate()
	app.settings_path="res://artifacts/residential/slots-%d/settings.json"%Time.get_ticks_usec()
	add_child_autofree(app);var shell:=app.game_shell;shell.automatic_time=false
	assert_true(shell.create_game("slot-01").ok);shell.guide.dialogue.finish_now();shell.profile.story.beat="done";shell.town.sync_characters(0)
	await get_tree().process_frame
	shell.profile.residence.stage="door";assert_true(shell.profile.unlock_residence().ok)
	var before: Dictionary=shell.profile.snapshot()
	var driver:=DRIVER.new();driver.viewport=get_tree().root
	for id: String in ["urban_village","rich_district"]:
		var plot: Dictionary=shell.profile.world.town_map.plots.filter(func(p:Dictionary)->bool:return str(p.id)==id)[0]
		var near:=Vector2(float(plot.x)+float(plot.w)*.5,float(plot.y+plot.h)+.5)
		assert_true(shell.profile.world.town_map.is_walkable(int(near.x),int(near.y)))
		shell.town._player.position=shell.town._origin()+near*shell.town.CELL
		assert_eq(str(shell.town.facing_plot().get("id","")),id)
		driver.tap(KEY_E);assert_not_null(shell._modal_box)
		if shell._modal_box==null: continue
		var labels: String=""
		for label: Label in shell._modal_box.find_children("*","Label",true,false): labels+=label.text
		assert_true(labels.contains("居民区"));assert_false(labels.contains("地块参考总价"))
		assert_eq(shell.profile.snapshot(),before);shell._close_dialog()
	shell.town.spawn_at_plot("player_cottage");driver.tap(KEY_E);assert_eq(shell.location,"cottage")
	assert_true(shell.save_game().ok);shell.go_title();assert_true(shell.load_game("slot-01").ok)
	assert_eq(shell.location,"cottage")
	var restored: Dictionary=shell.profile.world.town_map.cottage
	assert_eq(str(restored.id),str(before.residence.plot.id))
	for field: String in ["x","y","w","h","approach_x","approach_y"]:
		assert_eq(int(restored[field]),int(before.residence.plot[field]),"Saved grid coordinate "+field)
	shell.go_title();await get_tree().process_frame
