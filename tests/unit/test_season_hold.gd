extends GutTest

func config() -> Dictionary:
	return {"kind":"sequence","cabinet":true,"on_beat":true,"document_rules":true,"sequence":["spice:salt"],"allowed_actions":["spice:salt","spice:sugar"],"timeout_sec":3.0,"lead_in_sec":1.0,"interval_sec":1.0,"perfect_sec":.05,"good_sec":.1,"beat_times_sec":[1.0],"hold_durations_sec":[.5],"pour_rate_per_sec":.2}

func controller(clock: TDClock, settings: Dictionary = {}) -> TDCookingQTE:
	var request:=TDRequest.new("hold",1,"season-1","season",0)
	request.schema_version=3
	var value: Dictionary=config(); value.merge(settings,true)
	var qte:=TDCookingQTE.new(request,value,clock,TDBusinessRandom.new(1))
	assert_true(qte.start().ok)
	return qte

func test_actual_hold_quantity_and_inclusive_duration_windows() -> void:
	for seconds: float in [.2,.45,.5,.55,.6,.600001]:
		var clock:=TDClock.new(); var qte:=controller(clock)
		clock.advance(1); qte.input(1,clock.qte_sec,"spice:salt",true)
		clock.advance(seconds); qte.input(2,clock.qte_sec,"spice:salt",false)
		var result:=qte.finish()
		assert_true(result.ok)
		assert_almost_eq(float(result.data.actual_actions[0].amount),roundi(seconds*200)/1000.0,.000001)
		var expected: String="perfect" if seconds in [.45,.5,.55] else ("good" if seconds==.6 else "miss")
		assert_eq(result.data.last_judgement.grade,expected)

func test_duplicate_wrong_material_and_release_do_not_double_pour() -> void:
	var clock:=TDClock.new(); var qte:=controller(clock)
	clock.advance(1); qte.input(1,clock.qte_sec,"spice:sugar",true)
	assert_eq(qte.input(1,clock.qte_sec,"spice:sugar",true).code,"STALE_INPUT")
	assert_eq(qte.input(2,clock.qte_sec,"spice:sugar",true).code,"HELD_INPUT")
	clock.advance(.5); qte.input(3,clock.qte_sec,"spice:sugar",false)
	var result:=qte.finish()
	assert_eq(result.data.actual_actions.size(),1)
	assert_eq(result.data.actual_actions[0].action,"spice:sugar")
	assert_almost_eq(float(result.data.actual_actions[0].amount),.1,.000001)
	assert_eq(result.data.last_judgement.grade,"miss")
	assert_false(qte.input(4,clock.qte_sec,"spice:sugar",false).ok)

func test_pause_requires_repress_and_does_not_add_pause_time() -> void:
	var clock:=TDClock.new(); var qte:=controller(clock)
	clock.advance(1); qte.input(1,clock.qte_sec,"spice:salt",true)
	clock.advance(.2); qte.release_input(); clock.paused=true; clock.advance(10); qte.update()
	assert_almost_eq(float(qte.update().data.note_held_sec),.2,.000001)
	clock.paused=false
	assert_eq(qte.input(2,clock.qte_sec,"spice:salt",true).code,"HOLD_RESUMED")
	clock.advance(.3); qte.input(3,clock.qte_sec,"spice:salt",false)
	assert_almost_eq(float(qte.finish().data.actual_actions[0].amount),.1,.000001)

func test_long_frame_auto_stops_and_cancel_rejects_old_callback() -> void:
	var results: Array=[]
	for slices: int in [1,100]:
		var clock:=TDClock.new(); var qte:=controller(clock)
		clock.advance(1); qte.input(1,clock.qte_sec,"spice:salt",true)
		for index: int in slices: clock.advance(10.0/slices); qte.update()
		results.append(qte.finish().data.actual_actions)
	assert_eq(results[0],results[1])
	assert_almost_eq(float(results[0][0].amount),.17,.000001)
	var clock:=TDClock.new(); var qte:=controller(clock)
	clock.advance(1); qte.input(1,clock.qte_sec,"spice:salt",true); qte.cancel()
	clock.advance(2); assert_false(qte.finish().ok); assert_eq(qte.input(2,clock.qte_sec,"spice:salt",false).code,"CANCELLED")

func test_invalid_overlapping_and_nonfinite_hold_configuration_rejected() -> void:
	for update: Dictionary in [{"hold_durations_sec":[NAN]},{"pour_rate_per_sec":0},{"hold_durations_sec":[]},{"hold_durations_sec":[4.0,1.0],"sequence":["spice:salt","spice:sugar"],"beat_times_sec":[1.0,2.0]}]:
		var request:=TDRequest.new("hold",1,"x","season",0); request.schema_version=3
		var data: Dictionary=config(); data.merge(update,true)
		var qte:=TDCookingQTE.new(request,data,TDClock.new(),TDBusinessRandom.new(1))
		assert_false(qte.start().ok)

func test_actual_amount_changes_real_flavor_and_plan_is_read_only() -> void:
	var catalog:=TDServiceCatalog.new(); assert_true(catalog.load_file().ok)
	var samples: Array=[]
	for seconds: float in [.2,.3]:
		var session:=TDCookingSession.new("hold",1,catalog.cooking.for_recipe("service.tomato_egg"),{"pc_controls":true,"document_rules":true})
		var request:=TDRequest.new("hold",1,"add","add",0,{"ingredient_id":"tomato","amount":1}); request.schema_version=3
		assert_true(session.begin(request).ok)
		request=TDRequest.new("hold",1,"season-1","season",session.snapshot().to_dict().revision,{"ingredient_id":"salt","amount":.1,"mode":"precise"}); request.schema_version=3
		assert_true(session.begin(request).ok)
		var clock:=TDClock.new(); var qte:=controller(clock)
		clock.advance(1); qte.input(1,clock.qte_sec,"spice:salt",true); clock.advance(seconds); qte.input(2,clock.qte_sec,"spice:salt",false)
		var result:=qte.finish(); assert_true(session.complete_operation(result).ok)
		var snapshot: Dictionary=session.snapshot().to_dict(); samples.append(snapshot)
		assert_eq(snapshot.custom_plan.schema_version,3)
		assert_true(TDRecipeLibrary.new("",catalog.cooking.data()).validate_plan(snapshot.custom_plan).ok)
		assert_true(TDRecipeLibrary.new("",catalog.cooking.data()).validate_plan(JSON.parse_string(JSON.stringify(snapshot.custom_plan))).ok)
		assert_eq(session.complete_operation(result).code,"ALREADY_FINISHED")
		assert_eq(session.snapshot().to_dict(),snapshot)
	assert_gt(float(samples[1].dish_attributes.flavor[4][1]),float(samples[0].dish_attributes.flavor[4][1]))
