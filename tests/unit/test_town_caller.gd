extends GutTest

func test_caller_walks_to_the_diner_and_goes_home_after_eating() -> void:
	var caller := TDTownCaller.new()
	caller.boot(Vector2i(0, 0), Vector2i(0, 0))
	var road := func(x: int, y: int) -> bool: return y == 0 and x >= 0 and x <= 6
	caller.tick(road, Vector2i(6, 0), false)
	assert_eq(caller.phase, "wander")
	assert_eq(caller.cell, Vector2i(0, 0))
	assert_true(caller.line().contains("开门"))
	for _step in 8:
		caller.tick(road, Vector2i(6, 0), true)
	assert_eq(caller.phase, "dining")
	caller.tick(road, Vector2i(6, 0), true)
	assert_eq(caller.phase, "dining")
	caller.meal_done = true
	caller.tick(road, Vector2i(6, 0), true)
	assert_eq(caller.phase, "home")
	assert_true(caller.ate)
	assert_true(caller.line().contains("吃好了"))
	for _step in 8:
		caller.tick(road, Vector2i(6, 0), false)
	assert_eq(caller.phase, "wander")
	assert_eq(caller.cell, Vector2i(0, 0))
	assert_true(caller.line().contains("已经吃过"))

func test_the_town_shows_her_and_she_enters_when_the_shop_opens() -> void:
	var session := TDPhase3Session.new()
	assert_true(session.load_default().ok)
	assert_true(session.build_venue("chinese").ok)
	var town := TDTownWorld.new()
	town.player_mode = true
	town.session = session
	add_child_autofree(town)
	await get_tree().process_frame
	assert_eq(town.caller_phase(), "wander")
	town.shop_open = true
	for _step in 80:
		town._tick_caller(0.5)
	assert_eq(town.caller_phase(), "dining")
	town.finish_call()
	assert_eq(town.caller_phase(), "home")
	assert_true(town._caller.line().contains("吃好了"))

func test_talking_opens_the_portrait_box_and_leaves_her_route_alone() -> void:
	var session := TDPhase3Session.new()
	assert_true(session.load_default().ok)
	var town := TDTownWorld.new()
	town.player_mode = true
	town.session = session
	add_child_autofree(town)
	await get_tree().process_frame
	var phase := town.caller_phase()
	town._open_talk(town._caller.conversation())
	assert_true(town._talk_open())
	assert_gt(town._talk_view.dim_alpha(), 0.5)
	assert_false(town._player.controls_enabled)
	town._talk_view._on_skip()
	assert_true(town._talk_view.talk.choices_open)
	(town._talk_view.get_node("Box/Choices").get_child(0) as Button).pressed.emit()
	town._talk_view._on_skip()
	assert_false(town._talk_open())
	assert_eq(town.caller_phase(), phase)
	assert_true(town._player.controls_enabled)
