extends GutTest
var clock: TDClock
var qte: TDCookingQTE
var data: Dictionary
var sequence: int

func before_each() -> void:
	data = JSON.parse_string(FileAccess.get_file_as_string("res://content/cooking_system.json"))
	clock = TDClock.new(); sequence = 0

func create(kind: String) -> void:
	var request := TDRequest.new("pc-test", 0, kind, kind, 0); request.schema_version = 3
	qte = TDCookingQTE.new(request, data.pc_operations.modules[kind], clock, TDBusinessRandom.new(55))
	assert_true(qte.start().ok)

func press(action: String, down: bool = true, value: float = 1.0) -> TDOutcome:
	sequence += 1
	return qte.input(sequence, clock.qte_sec, action, down, value)

func test_cut_directions_and_hits_are_independent_of_grade() -> void:
	create("cut")
	clock.advance(1); press("primary"); press("primary", false)
	press("rotate_right"); press("rotate_right", false)
	clock.advance(.57); press("primary"); press("primary", false)
	clock.advance(.04)
	var result := qte.finish()
	assert_true(result.ok)
	assert_eq(result.data.cut_directions, [0, 1])
	assert_eq(result.data.perfect, 1); assert_eq(result.data.good, 1)
	assert_almost_eq(float(result.data.quality), .8, .000001)

func test_mashing_commands_without_beats_cannot_complete_perfect() -> void:
	create("stir")
	for action: String in ["up", "left", "down", "right", "primary"]:
		press(action); press(action, false)
	clock.advance(4)
	var result := qte.finish()
	assert_true(result.ok); assert_eq(float(result.data.quality), 0.0)

func test_commands_end_with_space_and_one_bad_step_is_good() -> void:
	create("stir")
	for action: String in ["up", "right", "down", "right", "primary"]:
		clock.advance(.5); press(action); press(action, false)
	var result := qte.finish()
	assert_true(result.ok); assert_almost_eq(float(result.data.quality), .6, .000001)
	assert_eq(result.data.actual_actions.back().action, "primary")

func test_cabinet_records_actual_wrong_material_and_zero_quality() -> void:
	create("season")
	for action: String in ["spice:sugar", "spice:salt", "spice:oil"]:
		clock.advance(.5); press(action); press(action, false)
	var result := qte.finish()
	assert_eq(float(result.data.quality), 0.0)
	assert_eq(result.data.actual_actions[0].action, "spice:sugar")

func test_window_and_hold_use_document_mapping() -> void:
	create("preheat"); clock.advance(2); press("primary")
	var ignition := qte.finish()
	assert_eq(ignition.data.grade, "perfect")
	assert_almost_eq(float(ignition.data.cursor), .5, .000001)
	clock = TDClock.new(); create("plate")
	press("primary"); clock.advance(1); press("primary", false)
	assert_eq(qte.finish().data.grade, "perfect")

func test_attraction_moves_cursor_instead_of_teleporting() -> void:
	create("heat")
	press("drag", true, .9)
	assert_almost_eq(float(qte.update().data.power), .25, .000001)
	clock.advance(.1)
	var value: float = qte.update().data.power
	assert_gt(value, .25); assert_lt(value, .9)

func test_attraction_fixed_timeline_is_frame_partition_independent() -> void:
	create("heat"); press("drag", true, .52); clock.advance(16)
	var first := qte.finish()
	clock = TDClock.new(); create("heat"); press("drag", true, .52)
	for index: int in 160: clock.advance(.1); qte.update()
	var second := qte.finish()
	assert_almost_eq(float(first.data.heat_dose), float(second.data.heat_dose), .0000001)
	assert_almost_eq(float(first.data.inside_sec), float(second.data.inside_sec), .0000001)

func test_pause_releases_attraction_without_scoring_release() -> void:
	create("heat"); press("drag", true, .5); qte.release_input()
	assert_eq(float(qte.update().data.attraction), 0.0)
	clock.paused = true; clock.advance(10)
	assert_eq(clock.qte_sec, 0.0)

func test_beat_sheet_keeps_rest_and_parallel_events_and_rejects_collision() -> void:
	var sheet := TDBeatSheet.new()
	assert_true(sheet.configure(data.pc_operations.sheets.stir_fry, data.operations).ok)
	assert_true(sheet.start(2).ok)
	assert_eq(sheet.due(1).size(), 0); assert_eq(sheet.due(2).size(), 1)
	assert_eq(sheet.due(2).size(), 0)
	assert_eq(sheet.due(5).size(), 1)
	assert_eq(sheet.due(7).size(), 2)
	var invalid: Dictionary = data.pc_operations.sheets.stir_fry.duplicate(true)
	invalid.events.insert(1, invalid.events[0].duplicate(true))
	assert_false(sheet.configure(invalid, data.operations).ok)
