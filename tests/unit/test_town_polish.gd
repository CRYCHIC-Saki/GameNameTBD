extends GutTest

func test_roaming_covers_a_neighbourhood_and_idle_stops_stay_clear() -> void:
	var profile:=TDGameProfile.new();var people:=profile.characters
	people.sync_map(profile.world.town_map)
	var points: Array[Vector2i]=[]
	for i: int in 120:
		people.advance(.5)
		points.append(people.runtime.aling.cell)
		if people.runtime.aling.route.is_empty():
			for plot: Dictionary in profile.world.town_map.plots:
				if TDInteractionRange.facility(plot):
					assert_gt(TDInteractionRange.distance(Vector2(people.runtime.aling.cell)+Vector2(.5,.5),TDInteractionRange.plot_bounds(plot)),1.5,"NPC cannot idle at a facility edge")
	var diameter: float=0
	for a: Vector2i in points:
		for b: Vector2i in points: diameter=maxf(diameter,Vector2(a).distance_to(Vector2(b)))
	assert_gt(diameter,4.0,"Roam across several tiles, not one neighbour")
	profile.close()

func test_standing_holds_and_schedule_boundaries_ignore_frame_partition() -> void:
	var profile:=TDGameProfile.new();var large:=profile.characters;large.sync_map(profile.world.town_map)
	var small:=TDCharacterRoster.new();small.sync_map(profile.world.town_map)
	large.advance(0);var chen: Vector2i=large.runtime.chen.cell
	large.advance(60);assert_eq(large.runtime.chen.cell,chen,"Stall owner stands, rather than oscillating")
	large.advance(420,[],540)
	for i: int in 480: small.advance(1,[],480+i)
	for id: String in ["aling","chen"]:
		assert_eq(large.runtime[id].cell,small.runtime[id].cell,id)
		assert_eq(large.runtime[id].route,small.runtime[id].route,id)
		assert_almost_eq(float(large.runtime[id].wait),float(small.runtime[id].wait),.0001)
		assert_almost_eq(float(large.runtime[id].dwell),float(small.runtime[id].dwell),.0001)
	var before:=small.visible_people();small.hold("aling",true);small.hold("chen",true);small.advance(60)
	assert_eq(small.visible_people(),before,"Dialogue holds positions and interpolation")
	profile.close()

func test_activity_validation_and_real_order_gate() -> void:
	var raw: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(TDCharacterRoster.SOURCE))
	for bad: Dictionary in [{"activity":"teleport"},{"radius_tiles":-1},{"rest_sec":0}]:
		var broken:=raw.duplicate(true);broken.characters[0].schedule[0].merge(bad,true)
		assert_false(TDCharacterRoster.validate_config(broken).ok)
	var profile:=TDGameProfile.new();var people:=profile.characters;people.sync_map(profile.world.town_map)
	var original:=people.definition("aling");var records:=people.records.duplicate(true)
	people.advance(60)
	assert_eq(people.records,records,"Wandering is presentation, not extra visits or household accounting")
	var order: Dictionary={"id":"real-visit","status":"WAITING","economic_intent":{"day":1},"economic_profile":{"id":"character:aling"}}
	people.advance(.1,[order]);assert_eq(people.runtime.aling.phase,"to_diner")
	people.advance(90,[order]);assert_true(people.can_enter("aling","real-visit"))
	assert_false(people.visible_people().any(func(p:Dictionary)->bool:return p.id=="aling"))
	people.finish_visit("aling","wrong-id");assert_eq(people.runtime.aling.phase,"dining")
	people.finish_visit("aling","real-visit");people.advance(30)
	assert_eq(people.runtime.aling.phase,"town");assert_eq(people.definition("aling"),original)
	profile.close()

func test_mealtime_without_an_order_does_not_send_residents_to_the_door() -> void:
	var profile:=TDGameProfile.new();var people:=profile.characters
	people.clock.minute=760;people.sync_map(profile.world.town_map);people.advance(60)
	for id: String in ["aling","chen"]:
		assert_ne(people.schedule(id).zone,"player_diner")
		assert_eq(people.runtime[id].phase,"town")
		assert_eq(people.runtime[id].order_id,"")
	profile.close()
