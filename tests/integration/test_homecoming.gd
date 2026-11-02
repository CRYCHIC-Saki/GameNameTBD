extends GutTest
const DRIVER=preload("res://tools/test_support/kitchen_input.gd")
var app: TDApplication
var shell: TDGameShell

func before_each() -> void:
	app=load("res://src/app/main.tscn").instantiate()
	app.settings_path="res://artifacts/homecoming/tests/%d/settings.json"%Time.get_ticks_usec()
	add_child_autofree(app);shell=app.game_shell;shell.automatic_time=false
	assert_true(shell.create_game("slot-01").ok);shell.guide.dialogue.finish_now()
	await get_tree().process_frame

func after_each() -> void:
	get_tree().paused=false;shell.go_title();await get_tree().process_frame

func complete_talk() -> void:
	assert_true(shell.guide.presenting())
	shell.guide.dialogue.talk.skip();shell.guide.dialogue._emit_if_finished()

func follow_home() -> void:
	var town:=shell.town
	town._tick_escort(.01)
	var start:=town.escort_position()
	town._player.position=start+Vector2(500,0);town._tick_escort(5)
	assert_eq(town.escort_position(),start);assert_true(town._escort_waiting)
	for step: int in 400:
		if shell.profile.residence.stage!="following": break
		town._player.position=town.escort_position();town._tick_escort(.5)
	assert_eq(shell.profile.residence.stage,"door","Real road route reaches cottage")

func interact_at_home() -> void:
	shell.town.spawn_at_plot("player_cottage");shell.town._process(0)
	var input:=DRIVER.new();input.viewport=get_tree().root;input.kitchen=shell.kitchen_view.kitchen
	input.tap(KEY_E)

func test_new_save_keeps_progress_at_harbor_then_story_unlock_saves_at_bed() -> void:
	assert_false(shell.profile.has_residence());assert_eq(shell.travel("cottage").code,"HOME_LOCKED")
	shell.profile.story.beat="founded";shell.profile.story.setup_seen=true;shell.profile.story.hero_name="赤焰"
	assert_true(shell.profile.buy({"egg":1000}).ok);assert_true(shell.save_game().ok)
	var money:int=shell.profile.shop.snapshot().money_cents
	shell.go_title();assert_true(shell.load_game("slot-01").ok)
	assert_eq(shell.location,"town");assert_false(shell.guide.presenting())
	assert_eq(shell.town._player_cell(),TDHarbor.ARRIVAL)
	assert_eq(shell.profile.story.hero_name,"赤焰");assert_eq(shell.profile.shop.snapshot().money_cents,money)
	# Both actions are synchronous: no frame polling is needed to remember opening.
	shell.profile.shop.open_day();shell.profile.shop.close_early()
	assert_true(shell.profile.story.served)
	shell.guide._process(0);assert_eq(shell.profile.residence.stage,"invited")
	shell.guide.dialogue.finish_now();assert_false(shell.profile.has_residence(),"Cancelling invitation cannot grant keys")
	shell.guide.begin_homecoming();complete_talk();assert_eq(shell.profile.residence.stage,"following")
	follow_home();interact_at_home();complete_talk()
	assert_true(shell.profile.has_residence());assert_eq(shell.location,"cottage")
	assert_eq(shell.profile.story.beat,"done");assert_eq(shell.profile.unlock_residence().code,"HOME_ALREADY_UNLOCKED")
	shell.go_title();assert_true(shell.load_game("slot-01").ok)
	assert_eq(shell.location,"cottage");assert_eq(shell.cottage.target(),"rest")

func test_two_am_before_business_unlocks_home_without_erasing_tutorial() -> void:
	shell.profile.story.beat="cook";shell.profile.story.recipe_viewed=true
	shell.profile.characters.clock.minute=1560
	assert_eq(shell.finish_night().code,"NIGHT_CLOSED")
	assert_eq(shell.profile.residence.reason,"late");assert_eq(shell.profile.story.beat,"cook")
	assert_eq(shell.finish_night().code,"NIGHT_ALREADY_CLOSED")
	complete_talk();follow_home();interact_at_home();complete_talk()
	assert_eq(shell.profile.story.beat,"cook");assert_true(shell.profile.story.recipe_viewed)
	assert_eq(shell.location,"cottage");assert_true(shell.profile.next_day().ok)
	assert_eq(shell.profile.characters.clock.minute,480.0)
	assert_eq(shell.profile.story.beat,"cook");assert_true(shell.travel("kitchen").ok)

func test_pending_route_restores_harbor_and_legacy_home_is_not_taken_away() -> void:
	shell.profile.story.beat="founded";shell.profile.story.setup_seen=true
	shell.profile.shop.open_day();shell.profile.shop.close_early()
	shell.profile.invite_home("first_day");shell.profile.residence.stage="following"
	assert_true(shell.save_game().ok)
	shell.go_title();assert_true(shell.load_game("slot-01").ok)
	assert_eq(shell.town._player_cell(),TDHarbor.ARRIVAL);assert_eq(shell.profile.residence.stage,"following")
	follow_home()
	var old:=shell.profile.snapshot();old.schema_version=6
	old.residence={"schema_version":1,"anchor":"cottage_bed","plot":old.residence.plot.duplicate(true)}
	var restored:=TDGameProfile.new();assert_true(restored.restore(old).ok);assert_true(restored.has_residence())
	assert_eq(restored.snapshot().schema_version,7);restored.close()
	var bad:=shell.profile.snapshot();bad.residence.anchor="cottage_bed"
	assert_eq(TDGameProfile.validate_save(bad).code,"INVALID_RESIDENCE_ANCHOR")
