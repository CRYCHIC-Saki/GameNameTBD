extends GutTest
const DRIVER=preload("res://tools/test_support/kitchen_input.gd")
var store: TDProfileStore
var profiles: Array[TDGameProfile]=[]

func before_each() -> void:
	store=TDProfileStore.new("res://artifacts/level-tests/%d-%d"%[Time.get_ticks_usec(),randi()],TDGameProfile.validate_save)

func after_each() -> void:
	for profile: TDGameProfile in profiles: profile.close()
	profiles.clear();get_tree().paused=false
	await get_tree().process_frame;await get_tree().process_frame

func create_profile(id: String="slot-01") -> TDGameProfile:
	var profile:=TDGameProfile.new();profiles.append(profile)
	assert_true(profile.error.ok,profile.error.code)
	profile.slot_id=id;profile.persistence=store.save_slot
	return profile

func finish_day(profile: TDGameProfile) -> void:
	# Real finite-demand day with no prepared meals. It loses money but can gain shop
	# awareness. This fixture does not fake cooking scores or arbitrary XP awards.
	assert_true(profile.shop.open_day().ok)
	assert_true(profile.shop.advance(360).ok)
	for order: Dictionary in profile.shop.active_orders(): profile.shop.cancel_order(order.id)
	profile.shop.advance(1000)
	assert_eq(profile.shop.snapshot().phase,"SETTLED")
	assert_true(profile.progression_error.ok,profile.progression_error.code)

func reach_level_two(profile: TDGameProfile) -> void:
	for day: int in range(1,9):
		finish_day(profile)
		if profile.progression.progress().level>=2: return
		assert_true(profile.next_day().ok)
	fail_test("Actual awareness growth did not reach level two within eight days")

func test_real_profit_and_store_metrics_exclude_bank_cash_menu_and_recipe_fame() -> void:
	var profile:=create_profile()
	assert_true(profile.bank_action("borrow",10000,"test-level-borrow").ok)
	var before:=profile.progression.snapshot()
	profile.shop.set_menu("service.tomato_egg",false,1000)
	profile.shop.set_menu("service.tomato_egg",true,1000)
	profile.shop._s.fame["service.tomato_egg"]=999999 # Regression fixture: excluded old metric.
	assert_true(profile.save().ok);assert_eq(profile.progression.snapshot(),before)
	finish_day(profile)
	var report:=profile.level_daily_report()
	assert_true(report.ok);assert_eq(report.data.stores.size(),1)
	assert_eq(report.data.stores[0].profit_cents,profile.shop.day_summary().economy.profit_cents)
	assert_lt(report.data.stores[0].profit_cents,0)
	var growth:Dictionary=profile.progression.snapshot().recent.back()
	assert_eq(growth.profit_xp,0);assert_eq(growth.store_count,1);assert_eq(growth.scale_milli,1000)
	assert_gt(growth.awareness_xp,0);assert_eq(growth.popularity_xp,0)

func test_multi_day_level_reward_and_six_slot_package_are_idempotent() -> void:
	var profile:=create_profile();var other:=create_profile("slot-02")
	var initial_points:=int(profile.research.snapshot().points)
	reach_level_two(profile)
	assert_eq(profile.progression.progress().level,2)
	assert_eq(int(profile.research.snapshot().points),initial_points+2)
	assert_eq(other.progression.progress().level,1);assert_eq(int(other.research.snapshot().points),initial_points)
	var levels:=profile.progression.snapshot();var research:=profile.research.snapshot()
	assert_false(profile.shop.settle_day().ok)
	assert_eq(profile.settle_progression().code,"ALREADY_APPLIED")
	assert_true(profile.save().ok);assert_true(profile.save().ok)
	assert_eq(profile.progression.snapshot(),levels);assert_eq(profile.research.snapshot(),research)
	var loaded:=store.load_slot("slot-01");assert_true(loaded.ok,loaded.code)
	assert_eq(int(loaded.data.schema_version),4)
	var restored:=create_profile("slot-03");assert_true(restored.restore(loaded.data).ok)
	assert_eq(restored.progression.progress(),profile.progression.progress())
	# The profile deliberately aligns research.world_time with the saved business day.
	assert_true(TDLevelProgression.same_value(restored.research.snapshot(),profile.snapshot().research))
	for key: String in research:
		if key!="world_time": assert_true(TDLevelProgression.same_value(restored.research.snapshot()[key],research[key]),key)
	assert_eq(restored.settle_progression().code,"ALREADY_APPLIED")
	assert_true(restored.next_day().ok);assert_true(restored.save().ok)
	assert_eq(restored.progression.progress().total_xp,profile.progression.progress().total_xp)

func test_interrupted_upgrade_write_preserves_complete_old_package_and_retry_once() -> void:
	var profile:=create_profile()
	assert_true(profile.save().ok)
	var old:Dictionary={}
	for day: int in range(1,9):
		old=store.load_slot("slot-01").data
		finish_day(profile)
		if profile.progression.progress().level==2: break
		assert_true(profile.save().ok);assert_true(profile.next_day().ok);assert_true(profile.save().ok)
	assert_eq(profile.progression.progress().level,2)
	var current:=profile.snapshot()
	store.interrupt_at="partial_write"
	assert_false(profile.save().ok)
	var preserved:=store.load_slot("slot-01");assert_true(preserved.ok)
	assert_eq(preserved.data.progression,old.progression);assert_eq(preserved.data.research,old.research)
	store.interrupt_at=""
	assert_true(profile.save().ok)
	var loaded:=store.load_slot("slot-01");assert_true(loaded.ok)
	assert_eq(int(loaded.data.progression.level),2)
	assert_eq(int(loaded.data.research.events["level:v1:2:inspiration"].amount),2)
	assert_eq(loaded.data.research.events["level:v1:2:inspiration"].kind,"inspiration")
	assert_eq(loaded.data.progression,JSON.parse_string(JSON.stringify(current.progression)))
	var restored:=create_profile("slot-02");assert_true(restored.restore(loaded.data).ok)
	assert_true(restored.save().ok);assert_true(TDLevelProgression.same_value(restored.research.snapshot(),current.research))
	# Existing backup/temporary-file recovery also preserves both domains together.
	store.interrupt_at="after_backup";assert_false(profile.save().ok)
	assert_eq(store.load_slot("slot-01").code,"INTERRUPTED_SAVE")
	store.interrupt_at="";assert_true(store.recover_slot("slot-01").ok)
	assert_eq(int(store.load_slot("slot-01").data.progression.level),2)

func test_legacy_profiles_migrate_without_backfill_and_invalid_new_data_do_not_mutate() -> void:
	var profile:=create_profile();finish_day(profile)
	for version: int in [1,2]:
		var old:=profile.snapshot();old.schema_version=version;old.erase("progression")
		if version==1: old.erase("economy")
		var migrated:=create_profile("slot-02")
		var result:=migrated.restore(old);assert_true(result.ok,result.code)
		assert_eq(migrated.progression.progress().total_xp,0)
		assert_eq(migrated.progression.snapshot().last_day,1)
		assert_true(migrated.progression.progress().migrated)
		assert_true(migrated.save().ok)
		assert_eq(migrated.progression.progress().total_xp,0)
		assert_true(migrated.next_day().ok);finish_day(migrated)
		assert_gt(migrated.progression.progress().total_xp,0)
	var snapshot:=profile.snapshot()
	for kind: String in ["missing","version","cursor","reward"]:
		var bad:=snapshot.duplicate(true)
		match kind:
			"missing": bad.erase("progression")
			"version": bad.progression.schema_version=99
			"cursor": bad.progression.last_day=500
			"reward": bad.research.events["level:v1:2:inspiration"]={"kind":"inspiration","amount":2}
		assert_false(profile.restore(bad).ok)
		assert_eq(profile.snapshot(),snapshot)

func test_pending_events_survive_retry_ack_and_stale_profile_calls() -> void:
	var profile:=create_profile();reach_level_two(profile);assert_true(profile.save().ok)
	var pending:=profile.pending_level_events();assert_eq(pending.size(),1)
	var event_id:String=pending[0].event_id
	store.interrupt_at="partial_write"
	assert_false(profile.acknowledge_level_event(event_id).ok)
	assert_eq(profile.pending_level_events().size(),1)
	store.interrupt_at="";assert_true(profile.acknowledge_level_event(event_id).ok)
	assert_eq(profile.acknowledge_level_event(event_id).code,"ALREADY_APPLIED")
	var restored:=create_profile("slot-02");assert_true(restored.restore(store.load_slot("slot-01").data).ok)
	assert_true(restored.pending_level_events().is_empty())
	profile.close();assert_eq(profile.settle_progression().code,"STALE_PROFILE")
	assert_false(profile.acknowledge_level_event(event_id).ok)

func test_real_main_ledger_reward_page_is_readonly_and_returns_controls() -> void:
	var layer:=CanvasLayer.new();layer.layer=140;add_child_autofree(layer)
	var app:TDApplication=load("res://src/app/main.tscn").instantiate()
	app.settings_path=store.root.path_join("scene/settings.json");layer.add_child(app)
	var shell:=app.game_shell;shell.automatic_time=false
	assert_true(shell.create_game("slot-01").ok);shell.travel("restaurant")
	var driver:=DRIVER.new();driver.viewport=get_tree().root
	var point:Dictionary=shell.restaurant.interaction_points().filter(func(item:Dictionary)->bool:return item.action=="ledger")[0]
	shell.restaurant.teleport_player(Vector2i(point.cell));driver.tap(KEY_E)
	await get_tree().process_frame
	var buttons:=shell._modal_box.find_children("*","Button",true,false).filter(func(node:Button)->bool:return node.text.begins_with("经营等级"))
	assert_eq(buttons.size(),1);buttons[0].pressed.emit()
	var view:TDLevelRewardsView=shell._modal_box.find_child("LevelRewardsView",true,false)
	assert_not_null(view);assert_eq(view.find_child("LevelReward2",true,false).get_child_count(),3)
	assert_eq(view.find_child("LevelExperienceBar",true,false).value,0.0)
	var before:=shell.profile.snapshot()
	for i: int in 3: shell.show_levels();shell._close_dialog()
	assert_eq(shell.profile.snapshot(),before)
	assert_true(shell.restaurant.is_processing_input())
	assert_true(shell.start_day().ok);shell.show_levels()
	assert_false(get_tree().paused,"Looking at levels does not stop business time")
	driver.tap(KEY_ESCAPE);assert_null(shell._modal)
	shell.go_title()

func test_real_daily_transition_displays_upgrade_and_reloads_same_reward() -> void:
	var layer:=CanvasLayer.new();layer.layer=140;add_child_autofree(layer)
	var app:TDApplication=load("res://src/app/main.tscn").instantiate()
	app.settings_path=store.root.path_join("upgrade/settings.json");layer.add_child(app)
	var shell:=app.game_shell;shell.automatic_time=false
	assert_true(shell.create_game("slot-01").ok)
	for day: int in range(1,9):
		# Use formal day transition; the shell sees OPEN before SETTLED.
		assert_true(shell.start_day().ok);shell._process(0)
		shell.profile.shop.advance(360)
		for order:Dictionary in shell.profile.shop.active_orders(): shell.profile.shop.cancel_order(order.id)
		shell.profile.shop.advance(1000);shell._process(0)
		if shell.profile.progression.progress().level==2: break
		assert_true(shell.profile.next_day().ok);shell._process(0)
	assert_eq(shell.profile.progression.progress().level,2)
	assert_not_null(shell._modal_box.find_child("LevelRewardsView",true,false))
	var points:=int(shell.profile.research.snapshot().points)
	shell.go_title();assert_true(shell.load_game("slot-01").ok)
	assert_eq(shell.profile.progression.progress().level,2)
	assert_eq(int(shell.profile.research.snapshot().points),points)
	shell.show_levels();shell._close_dialog();assert_eq(int(shell.profile.research.snapshot().points),points)
	shell.go_title()
