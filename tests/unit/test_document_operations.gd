extends GutTest
var data: Dictionary
func before_each() -> void:
	data=JSON.parse_string(FileAccess.get_file_as_string("res://content/cooking_system.json"))

func test_beat_cells_compile_to_exact_timestamps_including_rest_and_parallel() -> void:
	var sheet:=TDBeatSheet.new()
	assert_true(sheet.configure(data.pc_operations.document_sheets.tomato_egg,data.operations).ok)
	var events: Array=sheet.snapshot().events
	var cut:=TDBeatSheet.new(); cut.configure(data.pc_operations.document_sheets.prepare,data.operations)
	assert_eq(cut.snapshot().events[0].settings.beat_times_sec,[2.0,3.0,4.0])
	var stages: Array=[]
	for event: Dictionary in events:
		stages.append(event.group)
		if event.group=="stir-a":
			assert_eq(float(event.beat),26.0)
			assert_eq(event.settings.sequence,["up","left","down","right","primary"])
			assert_eq(event.settings.beat_times_sec,[2.0,3.0,4.0,5.0,6.0])
		if event.group=="heat": assert_eq(float(event.settings.duration_sec),19.0)
	assert_eq(stages,["ignite","oil","load","stir-a","heat","stir-b","stir-c","season","starch","plate"])

func test_invalid_tracks_unknown_groups_and_overlaps_rejected_before_play() -> void:
	for error: String in ["track","missing","overlap"]:
		var d: Dictionary=data.pc_operations.document_sheets.prepare.duplicate(true)
		if error=="track": d.beats[4].lanes.mouse=d.beats[4].lanes.hand; d.beats[4].lanes.erase("hand")
		elif error=="missing": d.beats[4].lanes.hand.group="absent"
		else: d.beats[2].t=d.beats[1].t
		assert_false(TDBeatSheet.new().configure(d,data.operations).ok,error)

func test_hold_center_edges_and_outside_match_drawn_interval() -> void:
	for duration: float in [.95,1.0,1.05,.9,1.1,.899,1.101]:
		var settings: Dictionary=data.pc_operations.modules.plate.duplicate(true)
		settings.merge({"document_rules":true,"target_min_sec":.9,"target_max_sec":1.1,"perfect_center_sec":1.0,"perfect_sec":.05},true)
		var clock:=TDClock.new(); var request:=TDRequest.new("hold",0,"hold","plate",0); request.schema_version=3
		var q:=TDCookingQTE.new(request,settings,clock,TDBusinessRandom.new(1)); q.start()
		q.input(1,0,"primary",true); clock.advance(duration); q.input(2,duration,"primary",false)
		var expected: float=1.0 if duration>=.95 and duration<=1.05 else (.6 if duration>=.9 and duration<=1.1 else 0.0)
		assert_eq(float(q.finish().data.quality),expected,str(duration))

func test_configured_rest_does_not_create_a_chop_target() -> void:
	var sheet:=TDBeatSheet.new(); sheet.configure(data.pc_operations.document_sheets.prepare,data.operations)
	var config: Dictionary=data.pc_operations.modules.cut.duplicate(true); config.merge(sheet.snapshot().events[0].settings,true)
	var clock:=TDClock.new(); var request:=TDRequest.new("cut",0,"cut","cut",0); request.schema_version=3
	var q:=TDCookingQTE.new(request,config,clock,TDBusinessRandom.new(1)); q.start()
	clock.advance(2.5)
	assert_eq(q.input(1,2.5,"primary",true).code,"OUTSIDE_WINDOW")
	assert_eq(q.update().data.cut_directions,[])

func test_module_average_does_not_multiply_weight_for_many_stir_segments() -> void:
	var catalog:=TDCookingCatalog.new(); assert_true(catalog.load_data(data,"test").ok)
	var model:=TDCookingModel.new("weights",0,catalog.for_recipe("tomato_egg"),{"pc_controls":true,"document_rules":true})
	# Explicit rule-boundary fixture; no scene or UI is mocked by this unit test.
	model._steps=[{"operation":"preheat","parameters":{},"quality":1.0,"module":"M2"},{"operation":"stir","parameters":{},"quality":.6,"module":"M3"},{"operation":"season","parameters":{"mode":"common"},"quality":.6,"module":"M3"},{"operation":"starch","parameters":{},"quality":.6,"module":"M3"},{"operation":"season","parameters":{},"quality":0.0,"module":"M6"}]
	var groups: Dictionary=model.module_scores()
	assert_almost_eq(float(groups.M3.quality),.6,.0000001)
	assert_eq(float(groups.M3.weight),.25)
	assert_eq(float(groups.M6.weight),.2)
	assert_eq(model._module("season",{"mode":"common"}),"M3")
	assert_eq(model._module("starch",{}),"M3")

func test_first_beat_ignition_has_a_real_count_in_and_valid_controller() -> void:
	var d: Dictionary={"id":"first","bpm":120,"groups":{"ignite":{"operation":"preheat","parameters":{}}},"beats":[{"t":1,"lanes":{"hand":{"group":"ignite","op":"preheat","input":"primary","form":"tap"}}}]}
	var sheet:=TDBeatSheet.new(); assert_true(sheet.configure(d,data.operations).ok)
	var state: Dictionary=sheet.snapshot(); assert_eq(float(state.pre_roll_beats),4.0)
	var event: Dictionary=state.events[0]
	assert_eq(float(event.beat),0.0); assert_eq(float(event.settings.target_sec),2.0)
	var config: Dictionary=data.pc_operations.modules.preheat.duplicate(true); config.merge(event.settings,true)
	var clock:=TDClock.new(); var request:=TDRequest.new("ignition",0,"first","preheat",0); request.schema_version=3
	var q:=TDCookingQTE.new(request,config,clock,TDBusinessRandom.new(1)); assert_true(q.start().ok)
	clock.advance(2); q.input(1,2,"primary",true); assert_eq(float(q.finish().data.quality),1.0)

func test_adjacent_command_groups_preserve_input_beats_without_forcing_rest() -> void:
	var d: Dictionary={"id":"adjacent","bpm":120,"groups":{"first":{"operation":"stir","parameters":{}},"next":{"operation":"stir","parameters":{}}},"beats":[]}
	var commands: Array=["up","left","primary","down","right","primary"]
	for index: int in commands.size():
		var group: String="first" if index<3 else "next"
		d.beats.append({"t":index+2,"lanes":{"hand":{"group":group,"op":"stir","input":commands[index],"form":"tap"}}})
	var sheet:=TDBeatSheet.new(); assert_true(sheet.configure(d,data.operations).ok)
	var events: Array=sheet.snapshot().events
	assert_eq(events.size(),2)
	# Expected absolute input times are hand-calculated at 120 BPM.
	for index: int in events.size():
		var actual: Array=[]
		for time: float in events[index].settings.beat_times_sec: actual.append(float(events[index].beat)*.5+time)
		var expected: Array=[.5,1.0,1.5] if index==0 else [2.0,2.5,3.0]
		for step: int in actual.size(): assert_almost_eq(float(actual[step]),float(expected[step]),.000001)
	assert_gt(float(events[1].beat)*.5,1.6)
	assert_lt(float(events[1].beat)*.5,2.0)

func test_material_reference_and_hold_gaps_rejected_before_runtime() -> void:
	var d: Dictionary=data.duplicate(true)
	for row: Dictionary in d.pc_operations.document_sheets.tomato_egg.beats:
		if row.t==75: row.lanes.mouse.input="spice:missing"
	assert_false(TDCookingCatalog.new().load_data(d,"missing cabinet material").ok)
	d=data.pc_operations.document_sheets.steam.duplicate(true)
	for row: Dictionary in d.beats:
		if row.t==21: row.lanes={}; row.rest=true
	assert_eq(TDBeatSheet.new().configure(d,data.operations).code,"INVALID_HOLD")

func test_season_holds_wait_one_extra_beat_between_pours() -> void:
	var spices: Array=["spice:salt","spice:sugar","spice:oil"]
	var beats: Array=[]
	for index: int in spices.size():
		beats.append({"t":5+index*2,"lanes":{"mouse":{"group":"season","op":"season","input":spices[index],"form":"hold","hold_beats":1}}})
	var sheet: Dictionary={"id":"season-gap","bpm":120,"preview_beats":1,"charge_start_grace_beats":4,"groups":{"season":{"operation":"season","parameters":{"mode":"precise"}}},"beats":beats}
	var compiled:=TDBeatSheet.new()
	var outcome:=compiled.configure(sheet,data.operations)
	assert_true(outcome.ok,outcome.code)
	var event: Dictionary=compiled.snapshot().events[0]
	assert_eq(event.settings.hold_durations_sec,[.5,.5,.5])
	var times: Array=event.settings.beat_times_sec
	assert_almost_eq(float(times[1])-float(times[0]),1.5,.000001)
	assert_almost_eq(float(times[2])-float(times[1]),1.5,.000001)
	var service:=TDServiceCatalog.new()
	var loaded:=service.load_file()
	assert_true(loaded.ok,loaded.code+" "+loaded.message)
	if not loaded.ok: return
	for id: String in service.cooking.data().pc_operations.document_sheets:
		var chart: Dictionary=service.cooking.data().pc_operations.document_sheets[id]
		if not chart.has("beats"): continue
		var played:=TDBeatSheet.new()
		var ready:=played.configure(chart,service.cooking.data().operations)
		assert_true(ready.ok,id+" "+ready.code)

func test_thermal_ratio_boundary_uses_document_grade_weights_once() -> void:
	var config: Dictionary=data.pc_operations.modules.heat.duplicate(true); config.document_rules=true
	var request:=TDRequest.new("thermal",0,"ratio","heat",0); request.schema_version=3
	var q:=TDCookingQTE.new(request,config,TDClock.new(),TDBusinessRandom.new(1)); q.start()
	for pair: Array in [[.499,0.0],[.5,.6],[.8,.6],[.801,1.0]]:
		q._inside_sec=float(pair[0])*float(config.duration_sec)
		assert_eq(q._current_quality(),float(pair[1]),str(pair[0]))
