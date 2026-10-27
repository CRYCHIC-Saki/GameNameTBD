extends GutTest

func test_cottage_uses_only_unowned_housing_preserves_roads_and_survives_rebuild() -> void:
	var world:=TDPhase3Session.new();assert_true(world.load_default().ok);assert_true(world.build_home("chinese").ok)
	var map:=world.town_map;var roads:=map.roads.duplicate(true);var parcels:=map.commercial_parcels().duplicate(true)
	var protected:Dictionary={}
	for plot:Dictionary in map.plots:
		if plot.kind!="housing": protected[plot.id]=plot.duplicate(true)
	var chosen:=map.choose_cottage();assert_false(chosen.is_empty());assert_eq(map.choose_cottage(),chosen)
	for y:int in range(chosen.y,chosen.y+2):
		for x:int in range(chosen.x,chosen.x+2): assert_eq(map.plot_at(x,y).kind,"housing")
	assert_true(map.install_cottage(chosen).ok)
	assert_eq(map.roads,roads);assert_eq(map.commercial_parcels(),parcels)
	for plot:Dictionary in map.plots:
		if protected.has(plot.id): assert_eq(plot,protected[plot.id])
	assert_eq(map.plot_at(chosen.x,chosen.y).id,"player_cottage")
	world._rebuild_map()
	assert_eq(map.plot_at(chosen.x,chosen.y).id,"player_cottage");assert_eq(map.cottage,chosen)
	var bad:=chosen.duplicate(true);bad.x=20;bad.y=20
	assert_false(map.install_cottage(bad).ok);assert_eq(map.cottage,chosen)
	bad=chosen.duplicate(true);bad.approach_x=0;bad.approach_y=0
	assert_false(map.validate_cottage(bad).ok)
	bad=chosen.duplicate(true);bad.walkable=true
	assert_eq(map.install_cottage(bad).code,"INVALID_COTTAGE");assert_eq(map.cottage,chosen)
