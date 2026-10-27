extends GutTest

func report(profit: int = 3000, pop: float = 0, aware: float = 0, day: int = 1, count: int = 1) -> Dictionary:
	var rows: Array=[]
	for i: int in count:
		rows.append({"store_id":"store-%d"%i,"scale_milli":1000,"profit_cents":profit,"popularity_before":50.0,"popularity_after":50.0+pop,"awareness_before":35.0,"awareness_after":35.0+aware})
	return {"day":day,"stores":rows}

func test_profit_and_shop_net_growth_have_independent_nonnegative_contributions() -> void:
	var rules:=TDLevelProgression.new()
	var result:=rules.evaluate(report(3000,2,3))
	assert_true(result.ok);assert_eq(result.data.profit_xp,35);assert_eq(result.data.popularity_xp,6);assert_eq(result.data.awareness_xp,9);assert_eq(result.data.mapped_xp,50)
	assert_eq(rules.evaluate(report(-3000,-2,-3)).data.mapped_xp,0)
	assert_eq(rules.evaluate(report(-3000,2,-3)).data.mapped_xp,6)
	assert_eq(rules.evaluate(report(0)).data.mapped_xp,0)
	assert_eq(rules.evaluate(report(9000)).data.profit_xp,52)
	assert_eq(rules.snapshot().total_xp,0,"Preview is read only")

func test_portfolio_scale_does_not_multiply_daily_xp_and_losses_offset_profit() -> void:
	var rules:=TDLevelProgression.new()
	for count: int in [1,10,1000]: assert_eq(rules.evaluate(report(3000,2,3,1,count)).data.mapped_xp,50)
	var mixed:=report(3000,0,0,1,2);mixed.stores[1].profit_cents=-3000
	assert_eq(rules.evaluate(mixed).data.profit_xp,0,"Take positive only after netting whole portfolio")
	mixed=report(3000,2,3);mixed.stores[0].scale_milli=2000
	assert_eq(rules.evaluate(mixed).data.profit_xp,23)

func test_extreme_income_and_full_metrics_remain_bounded() -> void:
	var rules:=TDLevelProgression.new()
	var input:=report(1000000000000)
	for key: String in ["popularity_before","popularity_after","awareness_before","awareness_after"]: input.stores[0][key]=100.0
	var result:=rules.evaluate(input)
	assert_true(result.ok);assert_gt(result.data.profit_xp,0);assert_lt(result.data.profit_xp,71)
	assert_eq(result.data.popularity_xp,0);assert_eq(result.data.awareness_xp,0)
	assert_lte(rules.evaluate(report(1000000000000,50,65)).data.mapped_xp,100)
	var earlier:=0
	for profit: int in [0,100,1000,3000,9000,100000,1000000000000]:
		var xp:int=rules.evaluate(report(profit)).data.profit_xp
		assert_gte(xp,earlier);earlier=xp

func test_daily_cursor_duplicate_conflict_and_xp_never_decrease() -> void:
	var rules:=TDLevelProgression.new()
	assert_true(rules.settle(report()).ok)
	var saved:=rules.snapshot()
	assert_eq(rules.settle(report()).code,"ALREADY_APPLIED");assert_eq(rules.snapshot(),saved)
	assert_eq(rules.settle(report(9000)).code,"DAY_CONFLICT")
	assert_eq(rules.settle(report(0,0,0,3)).code,"INVALID_LEVEL_DAY")
	assert_true(rules.settle(report(-100,0,0,2)).ok)
	assert_eq(rules.snapshot().total_xp,35)
	assert_false(rules.settle(report()).ok)
	assert_eq(rules.required_xp(1),60);assert_eq(rules.required_xp(2),84);assert_eq(rules.threshold(3),144)

func test_metrics_use_full_day_net_and_saved_baseline_not_menu_or_recipe_fame() -> void:
	var rules:=TDLevelProgression.new()
	rules.start(1,{"store-0":{"popularity":50.0,"awareness":35.0}})
	var bad:=report();bad.stores[0].popularity_before=0
	assert_eq(rules.settle(bad).code,"LEVEL_BASELINE_CONFLICT")
	var input:=report();input.recipe_fame=1000000;input.cash_balance=99999999
	assert_eq(rules.settle(input).data.xp,35)
	var snap:=rules.snapshot();snap.baselines["store-0"].popularity=0
	assert_eq(rules.snapshot().baselines["store-0"].popularity,50.0)

func test_crossing_multiple_levels_caps_and_builds_once_only_reward_events() -> void:
	var config:=TDLevelProgression.new().config.duplicate(true)
	config.max_level=5;config.curve={"base_xp":1,"linear_xp":0,"quadratic_xp":0}
	var rules:=TDLevelProgression.new(config)
	var result:=rules.settle(report())
	assert_true(result.ok);assert_eq(result.data.xp,4);assert_eq(result.data.rewards.size(),4)
	assert_eq(rules.progress().level,5);assert_true(rules.progress().at_cap)
	assert_eq(rules.snapshot().rewards.map(func(row:Dictionary)->int:return row.inspiration),[2,2,2,5])
	assert_eq(rules.pending_events().size(),4)
	assert_eq(rules.settle(report(3000,0,0,2)).data.xp,0)
	assert_eq(rules.snapshot().rewards.size(),4)

func test_hook_entitlements_and_outbox_ack_survive_roundtrip() -> void:
	var config:=TDLevelProgression.new().config.duplicate(true)
	config.curve={"base_xp":1,"linear_xp":0,"quadratic_xp":0}
	for kind: String in ["feature","furniture","story","event"]: config.hooks.append({"id":"test-"+kind,"level":2,"kind":kind,"target_id":"TEST_ONLY."+kind})
	var rules:=TDLevelProgression.new(config);rules.settle(report(100))
	assert_true(rules.has_entitlement("feature","TEST_ONLY.feature"));assert_true(rules.has_entitlement("furniture","TEST_ONLY.furniture"))
	assert_false(rules.has_entitlement("feature","unconfigured"))
	assert_eq(rules.pending_events().size(),6)
	assert_true(rules.acknowledge("level:v1:2:reached").ok)
	assert_eq(rules.acknowledge("level:v1:2:reached").code,"ALREADY_APPLIED")
	var copy:=TDLevelProgression.new(config)
	var loaded:=copy.restore(JSON.parse_string(JSON.stringify(rules.snapshot())))
	assert_true(loaded.ok,loaded.code);assert_eq(copy.pending_events().size(),5)
	assert_eq(copy.acknowledge("not-real").code,"UNKNOWN_LEVEL_EVENT")

func test_corrupt_config_reports_and_unknown_save_versions_fail_without_mutation() -> void:
	var rules:=TDLevelProgression.new();var before:=rules.snapshot()
	for field: String in ["profit_cents","scale_milli","awareness_after"]:
		var invalid:=report();invalid.stores[0][field]="wrong"
		assert_false(rules.settle(invalid).ok)
	var duplicate:=report();duplicate.stores.append(duplicate.stores[0].duplicate(true));assert_false(rules.settle(duplicate).ok)
	var empty:=report();empty.stores=[];assert_false(rules.settle(empty).ok)
	var nan_report:=report();nan_report.stores[0].popularity_after=NAN;assert_false(rules.settle(nan_report).ok)
	var bad:=before.duplicate(true);bad.schema_version=99;assert_eq(rules.restore(bad).code,"UNSUPPORTED_LEVEL_VERSION")
	bad=before.duplicate(true);bad.total_xp=-1;assert_false(rules.restore(bad).ok)
	bad=before.duplicate(true);bad.level=2;assert_false(rules.restore(bad).ok)
	assert_eq(rules.snapshot(),before)
	var config:=rules.config.duplicate(true);config.daily.profit_reference_cents=0
	assert_false(TDLevelProgression.new(config).error.ok)

func test_old_save_baseline_starts_next_day_without_retrospective_rewards() -> void:
	var rules:=TDLevelProgression.new();rules.start(101,{"store-0":{"popularity":50.0,"awareness":35.0}},true)
	assert_eq(rules.snapshot().last_day,100);assert_eq(rules.progress().level,1);assert_eq(rules.progress().total_xp,0)
	assert_true(rules.validate_save(rules.snapshot()).ok)
	assert_false(rules.settle(report(3000,0,0,100)).ok)
	assert_true(rules.settle(report(3000,0,0,101)).ok);assert_eq(rules.progress().total_xp,35)

func test_long_run_history_bounded_and_independent_sessions_deterministic() -> void:
	var a:=TDLevelProgression.new();var b:=TDLevelProgression.new();var untouched:=TDLevelProgression.new()
	for day: int in range(1,101):
		assert_true(a.settle(report(3000,0,0,day)).ok)
		assert_true(b.settle(report(3000,0,0,day)).ok)
	assert_eq(a.snapshot(),b.snapshot());assert_eq(a.snapshot().recent.size(),28)
	assert_eq(a.progress().total_xp,3500);assert_eq(untouched.progress().total_xp,0)
	var restored:=TDLevelProgression.new()
	var result:=restored.restore(JSON.parse_string(JSON.stringify(a.snapshot())))
	assert_true(result.ok,result.code);assert_eq(restored.progress(),a.progress())
