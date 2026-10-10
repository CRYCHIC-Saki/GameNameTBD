extends GutTest
var data: Dictionary
var clock: TDClock
var q: TDCookingQTE
var sequence: int

func before_each() -> void:
	data=JSON.parse_string(FileAccess.get_file_as_string("res://content/cooking_system.json"))
	clock=TDClock.new(); sequence=0

func make_cut() -> void:
	var config: Dictionary=data.pc_operations.modules.cut.duplicate(true)
	config.merge({"document_rules":true,"beats":3,"cut_actions":["primary","rotate_right","primary"],"beat_times_sec":[2.0,3.0,4.0]},true)
	var request:=TDRequest.new("notes",0,"cut","cut",0); request.schema_version=3
	q=TDCookingQTE.new(request,config,clock,TDBusinessRandom.new(1)); assert_true(q.start().ok)

func at(time: float, action: String) -> TDOutcome:
	clock.advance(time-clock.qte_sec); sequence+=1
	var result:=q.input(sequence,time,action,true)
	sequence+=1; q.input(sequence,time,action,false)
	return result

func test_cut_chart_counts_only_knives_and_requires_rotation_on_its_beat() -> void:
	make_cut()
	at(2,"primary"); at(3,"rotate_right"); at(4,"primary")
	clock.advance(.11)
	var result:=q.finish()
	assert_eq(result.data.cut_directions,[0,1])
	assert_eq(float(result.data.quality),1.0)
	assert_eq(int(result.data.get("cut_hits",-1)),2)

func test_wrong_or_offbeat_rotation_cannot_silently_change_food_direction() -> void:
	make_cut()
	at(1,"rotate_right")
	assert_eq(int(q.update().data.cut_direction),0)
	at(2,"primary"); at(3,"rotate_left"); at(4,"primary")
	clock.advance(.11)
	var result:=q.finish()
	assert_eq(result.data.cut_directions,[0])
	assert_eq(result.data.judgements,["perfect","miss","miss"])

func test_note_feedback_has_signed_timing_and_does_not_repeat_on_reads() -> void:
	make_cut(); var result:=at(1.95,"primary")
	var event: Dictionary=result.data.get("last_judgement",{})
	assert_eq(event.get("grade"),"perfect")
	assert_almost_eq(float(event.get("error_sec",99)),-.05,.000001)
	assert_eq(q.update().data.get("last_judgement",{}),event)
	clock.advance(1.2); var missed: Dictionary=q.update().data.get("last_judgement",{})
	assert_eq(missed.get("grade"),"miss"); assert_eq(missed.get("reason"),"MISSED_NOTE")
	assert_gt(int(missed.get("serial",0)),int(event.get("serial",0)))

func make_charge() -> void:
	var config: Dictionary=data.pc_operations.modules.plate.duplicate(true)
	config.merge({"document_rules":true,"charge_preview_sec":2.0,"start_grace_sec":2.0,"target_min_sec":1.9,"target_max_sec":2.1,"perfect_center_sec":2.0,"perfect_sec":.05,"timeout_sec":6.3},true)
	var request:=TDRequest.new("hold",0,"plate","plate",0); request.schema_version=3
	q=TDCookingQTE.new(request,config,clock,TDBusinessRandom.new(1)); assert_true(q.start().ok)

func test_charge_has_preview_and_late_legal_start_gets_full_hold_time() -> void:
	make_charge()
	assert_eq(q.input(1,0,"primary",true).code,"PREVIEW")
	clock.advance(3.5); q.input(2,3.5,"primary",true)
	clock.advance(1.5)
	assert_false(bool(q.update().data.ready_to_finish))
	assert_almost_eq(float(q.update().data.held_sec),1.5,.000001)
	clock.advance(.5); q.input(3,5.5,"primary",false)
	assert_eq(float(q.finish().data.quality),1.0)

func test_no_start_times_out_and_pause_release_does_not_finish_charge() -> void:
	make_charge(); clock.advance(4.01)
	assert_true(bool(q.update().data.ready_to_finish))
	assert_eq(float(q.finish().data.quality),0.0)
	clock=TDClock.new(); make_charge(); clock.advance(2); q.input(1,2,"primary",true)
	clock.advance(1); q.release_input(); clock.paused=true; clock.advance(30)
	assert_false(bool(q.update().data.ready_to_finish))
	clock.paused=false; q.input(2,3,"primary",true); clock.advance(1); q.input(3,4,"primary",false)
	assert_eq(float(q.finish().data.quality),1.0)

func test_chart_rejects_hidden_heat_span_over_seasoning_mouse_track() -> void:
	var chart: Dictionary={"id":"conflict","bpm":120,"groups":{"heat":{"operation":"heat","parameters":{}},"season":{"operation":"season","parameters":{"mode":"precise"}}},"beats":[]}
	for n: int in range(1,10):
		var spice: String=["salt","sugar","oil"][n-4] if n in [4,5,6] else ""
		chart.beats.append({"t":n,"lanes":{"mouse":{"group":"season" if not spice.is_empty() else "heat","op":"season" if not spice.is_empty() else "heat","input":"spice:"+spice if not spice.is_empty() else "Mouse","form":"tap" if not spice.is_empty() else "hold"}}})
	assert_eq(TDBeatSheet.new().configure(chart,data.operations).code,"CONTENDED_MOUSE_TRACK")

func test_perfect_good_inclusive_boundaries_and_repeat_inputs() -> void:
	for pair: Array in [[-.05,"perfect"],[.05,"perfect"],[-.1,"good"],[.1,"good"],[.1001,"miss"]]:
		clock=TDClock.new(); sequence=0; make_cut()
		at(2+float(pair[0]),"primary")
		assert_eq(q.update().data.judgements[0],pair[1])
	clock=TDClock.new(); make_cut(); clock.advance(2)
	var hit:=q.input(1,2,"primary",true)
	assert_eq(q.input(2,2,"primary",true).code,"HELD_INPUT")
	assert_eq(q.update().data.last_judgement,hit.data.last_judgement)
	assert_eq(int(q.update().data.cut_hits),1)

func test_thermal_suspension_excludes_time_without_awarding_free_quality() -> void:
	var config: Dictionary=data.pc_operations.modules.heat.duplicate(true)
	config.document_rules=true; config.duration_sec=2.0
	var request:=TDRequest.new("heat",0,"thermal","heat",0); request.schema_version=3
	q=TDCookingQTE.new(request,config,clock,TDBusinessRandom.new(1)); q.start()
	q.set_control_suspended(true)
	var before: float=q.update().data.power
	assert_eq(q.input(1,0,"drag",true,.9).code,"CONTROL_SUSPENDED")
	clock.advance(2)
	var result:=q.finish()
	assert_eq(float(result.data.power),before)
	assert_eq(float(result.data.assessed_sec),0.0)
	assert_eq(float(result.data.quality),0.0)
	assert_almost_eq(float(result.data.heat_dose),before*2,.000001)

func test_preparation_is_recipe_bound_and_invalid_reference_rejected() -> void:
	var catalog:=TDCookingCatalog.new(); assert_true(catalog.load_data(data,"chart").ok)
	assert_eq(catalog.for_recipe("tomato_egg").recipe.preparation_sheets.tomato,"prepare")
	assert_eq(catalog.for_recipe("test.cold_salad").recipe.preparation_sheets.cucumber,"prepare_strips")
	var a:=TDBeatSheet.new(); var b:=TDBeatSheet.new()
	a.configure(data.pc_operations.document_sheets.prepare,data.operations)
	b.configure(data.pc_operations.document_sheets.prepare_strips,data.operations)
	assert_eq(a.snapshot().events[0].settings.cut_actions,["primary","rotate_right","primary"])
	assert_eq(b.snapshot().events[0].settings.cut_actions,["primary","primary"])
	var changed: Dictionary=catalog.for_recipe("tomato_egg"); changed.recipe.preparation_sheets.tomato="missing"
	assert_eq(catalog.for_recipe("tomato_egg").recipe.preparation_sheets.tomato,"prepare")
	data.recipes[0].preparation_sheets.tomato="missing"
	assert_false(TDCookingCatalog.new().load_data(data,"bad reference").ok)

func test_late_start_long_frame_matches_partitioned_clock_and_cancel_is_final() -> void:
	var outcomes: Array=[]
	for partition: bool in [false,true]:
		clock=TDClock.new(); make_charge(); clock.advance(3.8); q.input(1,3.8,"primary",true)
		if partition:
			for i: int in 20: clock.advance(.1); q.update()
		else: clock.advance(2)
		q.input(2,clock.qte_sec,"primary",false); outcomes.append(q.finish().data.quality)
	assert_eq(outcomes,[1.0,1.0])
	clock=TDClock.new(); make_cut(); q.cancel()
	assert_eq(q.input(1,0,"primary",true).code,"CANCELLED")

func test_new_chart_fields_reject_wrong_types_and_unknown_recipe() -> void:
	for value: Variant in [[],"slow",-1,50]:
		var chart: Dictionary=data.pc_operations.document_sheets.prepare.duplicate(true)
		chart.preview_beats=value
		assert_false(TDBeatSheet.new().configure(chart,data.operations).ok)
	data.pc_operations.document_rules.preparation_recipes.tomato="missing"
	assert_false(TDCookingCatalog.new().load_data(data,"unknown recipe").ok)
