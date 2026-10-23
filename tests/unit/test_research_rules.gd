extends GutTest
const DRIVER=preload("res://tools/test_support/research_input.gd")

func make() -> TDResearchSession:
	var c:=TDResearchCatalog.new();var result:=c.load_file();assert_true(result.ok,result.code)
	return TDResearchSession.new(c)

func start(s:TDResearchSession,id:String) -> TDOutcome:
	var begun:=s.begin(id);assert_true(begun.ok,begun.code)
	if begun.ok: add_child(s.controller)
	return begun

func perform(s:TDResearchSession,id:String) -> TDOutcome:
	var begun:=start(s,id);assert_true(DRIVER.play(s,begun.data.token))
	return s.finish(begun.data.token)

func after_each() -> void:
	for child:Node in get_children():
		if child is TDResearchLesson and not child.is_queued_for_deletion(): child.dispose()

func test_catalog_100_nodes_references_cycles_and_real_kitchen_charts() -> void:
	var s:=make();assert_eq(s.catalog.nodes.size(),100)
	var bad:=s.catalog.data.duplicate(true);bad.recipes[0].prerequisites=["C05"]
	assert_eq(TDResearchCatalog.new().load_data(bad).code,"CYCLIC_ATLAS")
	bad=s.catalog.data.duplicate(true);bad.recipes[0].prerequisites=["NO"]
	assert_false(TDResearchCatalog.new().load_data(bad).ok)
	for change:Dictionary in [{"recipe_id":"missing"},{"primary":["egg","egg"]},{"kind":"sequence"}]:
		bad=s.catalog.data.duplicate(true);bad.charts.C03.merge(change,true)
		assert_false(TDResearchCatalog.new().load_data(bad).ok)

func test_two_starters_pending_chart_locked_and_insufficient_points_no_spend() -> void:
	var s:=make();assert_eq(s.snapshot().unlocked,["C01","C02"])
	var before:=s.snapshot()
	for pair:Array in [["E01","STORY_LOCKED"],["C05","CHART_PENDING"],["C20","PREREQUISITES"]]:
		assert_eq(s.begin(pair[0]).code,pair[1]);assert_eq(s.snapshot(),before)
	var empty:=s.snapshot();empty.points=0;assert_true(s.restore(empty).ok)
	assert_eq(s.begin("C03").code,"POINTS_SHORT");assert_eq(s.snapshot().points,0)

func test_real_kitchen_missed_inputs_fail_license_retry_cancel_and_steam_pass() -> void:
	var s:=make();var begun:=start(s,"C04");assert_eq(s.snapshot().points,2)
	assert_eq(s.begin("C03").code,"BUSY");s.advance(200)
	var failed:=s.finish(begun.data.token);assert_eq(failed.code,"LOW_SCORE");assert_lt(failed.data.score,80.0)
	assert_eq(s.snapshot().study_hours,0)
	var retry:=s.begin("C04");assert_eq(retry.data.cost,0);s.cancel(retry.data.token)
	assert_eq(s.input(retry.data.token,"primary",true).code,"STALE_ATTEMPT")
	var passed:=perform(s,"C04");assert_eq(passed.code,"UNLOCKED");assert_almost_eq(passed.data.score,100.0,.01)
	assert_eq(passed.data.modules.keys(),["M6","M3","M7"])
	assert_eq(s.snapshot().points,2);assert_eq(s.finish(passed.data.token).code,"STALE_ATTEMPT")

func test_boil_uses_real_continuous_temperature_and_score_read_only() -> void:
	var s:=make();var passed:=perform(s,"C03");assert_eq(passed.code,"UNLOCKED")
	assert_true(passed.data.modules.has("M5"));assert_true(passed.data.modules.has("M2"));assert_true(passed.data.modules.has("M7"))
	assert_gte(passed.data.score,80.0);var before:=s.snapshot()
	passed.data.score=0;s.progress().quality=0;assert_eq(s.snapshot(),before)

func test_same_lesson_host_supports_real_cut_stir_without_parallel_qte() -> void:
	var s:=make();var raw:=s.catalog.data.duplicate(true)
	raw.charts.C03.recipe_id="service.tomato_egg";raw.charts.C03.primary=["tomato","egg"]
	var catalog:=TDResearchCatalog.new();assert_true(catalog.load_data(raw).ok)
	s=TDResearchSession.new(catalog);var passed:=perform(s,"C03")
	assert_eq(passed.code,"UNLOCKED");assert_true(passed.data.modules.has("M1"));assert_true(passed.data.modules.has("M4"));assert_true(passed.data.modules.has("M6"))
	assert_eq(passed.data.steps[0].operation,"cut")

func test_completed_save_failure_retry_commits_only_once() -> void:
	var s:=make();var begun:=start(s,"C04");assert_true(DRIVER.play(s,begun.data.token));var before:=s.snapshot()
	s.save_sink=func(_value:Dictionary)->TDOutcome:return TDOutcome.new(false,"WRITE_FAILED")
	assert_eq(s.finish(begun.data.token).code,"WRITE_FAILED");assert_eq(s.snapshot(),before)
	s.save_sink=Callable();assert_eq(s.finish(begun.data.token).code,"UNLOCKED");assert_eq(s.snapshot().study_hours,0)
	assert_eq(s.finish(begun.data.token).code,"STALE_ATTEMPT")

func test_pause_long_frame_cancel_and_separate_sessions_do_not_pollute_templates() -> void:
	var a:=make();var b:=make();var begun:=start(a,"C04");var template:=a.catalog.data.duplicate(true)
	a.advance(1);a.set_paused(true);a.advance(50);assert_eq(a.clock.qte_sec,1.0)
	assert_eq(a.input(begun.data.token,"primary",true).code,"PAUSED")
	a.set_paused(false);a.advance(200);assert_eq(a.finish(begun.data.token).code,"LOW_SCORE")
	assert_eq(b.snapshot().points,3);assert_eq(a.catalog.data,template)
	assert_eq(a.advance(-1).code,"NO_ATTEMPT")
	var old:=start(a,"C04");a.advance(.1);a.cancel(old.data.token)
	var fresh:=start(a,"C04");assert_ne(fresh.data.token,old.data.token)
	assert_eq(a.input(old.data.token,"primary",true).code,"STALE_ATTEMPT");a.cancel(fresh.data.token)

func test_story_and_inspiration_idempotency_and_unlock_validation() -> void:
	var s:=make();assert_true(s.recommend_cuisine("story.europe","eu").ok)
	assert_false(s.has("E01"));assert_eq(s.status("E01"),"CHART_PENDING")
	assert_eq(s.recommend_cuisine("story.europe","eu").code,"ALREADY_APPLIED")
	assert_eq(s.recommend_cuisine("story.europe","jp").code,"EVENT_CONFLICT")
	assert_false(s.recommend_cuisine("x","unknown").ok)
	s.record_cooking(1,"tomato_egg",80);s.record_cooking(1,"tomato_egg",100);assert_eq(s.snapshot().points,4)
	var bad:=s.snapshot();bad.unlocked.append("C03");assert_eq(s.restore(bad).code,"INVALID_UNLOCK")
	bad=s.snapshot();bad.licensed.append("C03");bad.best.C03=100;bad.unlocked.append("C03");bad.study_hours=1
	assert_eq(s.restore(bad).code,"INVALID_COUNTER")

func test_storage_failure_atomic_legacy_and_phase_limits() -> void:
	var s:=make();var before:=s.snapshot()
	s.save_sink=func(_data:Dictionary)->TDOutcome:return TDOutcome.new(false,"DISK_FULL")
	assert_eq(s.begin("C03").code,"DISK_FULL");assert_eq(s.snapshot(),before)
	s.save_sink=Callable();assert_true(s.inherit_legacy(["mapodoufu"]).ok)
	assert_true(s.has("C14"));assert_false(s.has("C09"));assert_true(s.validate_save(s.snapshot()).ok)
	var raw:=s.snapshot();raw.points=-1;assert_false(s.restore(raw).ok)
	raw=s.snapshot();raw.schema_version=99;assert_eq(s.restore(raw).code,"UNSUPPORTED_VERSION")
	assert_eq(s.begin("C03",{"day":1,"phase":"service","spent":0},4).code,"SHOP_OPEN")
	var begun:=s.begin("C03",{"day":1,"phase":"morning","spent":0},0)
	assert_true(begun.ok);s.cancel(begun.data.get("token",""))

func test_exhausted_legacy_progress_can_retry_today_without_time_or_repeat_cost() -> void:
	var s:=make();var raw:=s.snapshot()
	raw.points=2;raw.licensed=["C04"];raw.best={"C04":0.0}
	raw.attempt_serial=4;raw.completed_attempts=4;raw.study_hours=4
	raw.world_time={"day":3,"phase":"evening","spent":4.0}
	assert_true(s.restore(raw).ok)
	for attempt:int in 3:
		var begun:=s.begin("C04",raw.world_time,0)
		assert_true(begun.ok,begun.code)
		if not begun.ok: return
		add_child(s.controller);s.advance(200)
		assert_eq(s.finish(begun.data.token).code,"LOW_SCORE")
		assert_eq(s.finish(begun.data.token).code,"STALE_ATTEMPT")
		assert_eq(s.snapshot().world_time,raw.world_time)
		assert_eq(s.snapshot().study_hours,4);assert_eq(s.snapshot().points,2)
	var begun:=s.begin("C04",raw.world_time,0);assert_true(begun.ok)
	add_child(s.controller);assert_true(DRIVER.play(s,begun.data.token))
	assert_eq(s.finish(begun.data.token).code,"UNLOCKED")
	assert_eq(s.snapshot().world_time,raw.world_time);assert_eq(s.snapshot().study_hours,4)
	assert_eq(s.snapshot().completed_attempts,8)
	var restored:=make();assert_true(restored.restore(JSON.parse_string(JSON.stringify(s.snapshot()))).ok)
	assert_true(restored.has("C04"));assert_eq(float(restored.snapshot().world_time.spent),4.0)
	var invalid:=s.snapshot();invalid.study_hours=9;assert_eq(s.restore(invalid).code,"INVALID_COUNTER")

func test_real_save_interruption_recovery_and_future_version_preservation() -> void:
	var s:=make();var dir:="res://artifacts/test-storage/research-%d"%Time.get_ticks_usec();DirAccess.make_dir_recursive_absolute(dir)
	var store:=TDResearchStore.new(dir+"/progress.json",s.validate_save);s.save_sink=store.save_game
	assert_true(s.grant_inspiration("first",1).ok);var bytes:=FileAccess.get_file_as_bytes(store.path)
	store.interrupt_at="partial_write";assert_eq(s.grant_inspiration("second",1).code,"INTERRUPTED")
	assert_eq(FileAccess.get_file_as_bytes(store.path),bytes);assert_eq(s.snapshot().points,4)
	store.interrupt_at="after_backup";assert_eq(s.grant_inspiration("second",1).code,"INTERRUPTED")
	assert_eq(store.load_game().code,"INTERRUPTED_SAVE");assert_true(store.recover(true).ok)
	var fresh:=make();assert_true(fresh.restore(store.load_game().data).ok);assert_eq(fresh.snapshot().points,5)
	var f:=FileAccess.open(store.path,FileAccess.WRITE);f.store_string('{"schema_version":99}');f.close()
	bytes=FileAccess.get_file_as_bytes(store.path);assert_eq(store.save_game(fresh.snapshot()).code,"UNSUPPORTED_VERSION")
	assert_eq(store.recover().code,"UNSUPPORTED_VERSION");assert_eq(FileAccess.get_file_as_bytes(store.path),bytes)
