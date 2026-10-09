extends GutTest
var catalog: TDCookingCatalog
var serial: int = 0

func before_each() -> void:
	catalog = TDCookingCatalog.new(); assert_true(catalog.load_file("res://content/cooking_system.json").ok)
	serial = 0

func make(id: String) -> TDCookingSession:
	return TDCookingSession.new(id,0,catalog.for_recipe("tomato_egg"),{"pc_controls":true})

func begin(session: TDCookingSession, kind: String, args: Dictionary = {}) -> TDOutcome:
	serial += 1
	var state: Dictionary = session.snapshot().to_dict()
	var request := TDRequest.new(state.session_id,0,"test-%d"%serial,kind,int(state.revision),args); request.schema_version=3
	return session.begin(request)

func completed(session: TDCookingSession, identity: String, kind: String, metrics: Dictionary = {}) -> TDOutcome:
	var state: Dictionary = session.snapshot().to_dict()
	var values: Dictionary = {"schema_version":3,"session_id":state.session_id,"generation":0,"operation_id":identity,"kind":kind,"status":"completed","quality":1.0,"elapsed_sec":2.0}
	values.merge(metrics,true)
	return session.complete_operation(TDOutcome.new(true,"COMPLETED","",values))

func test_cut_count_direction_shape_and_zero_hit_are_real_model_outputs() -> void:
	var session := make("cut")
	var id: String = begin(session,"add",{"ingredient_id":"tomato"}).data.instance_id
	begin(session,"cut",{"instance_id":id,"beats":2})
	assert_true(completed(session,"test-2","cut",{"cut_directions":[0,1],"quality":.8}).ok)
	var item: Dictionary = session.snapshot().to_dict().ingredients[id]
	assert_eq(item.shape,"chunk"); assert_eq(float(item.fine),.25)
	var other := make("miss")
	var other_id: String = begin(other,"add",{"ingredient_id":"tomato"}).data.instance_id
	begin(other,"cut",{"instance_id":other_id,"beats":2})
	assert_true(completed(other,"test-4","cut",{"cut_directions":[],"quality":0.0}).ok)
	assert_eq(other.snapshot().to_dict().ingredients[other_id].shape,"whole")
	assert_eq(float(other.snapshot().to_dict().ingredients[other_id].fine),0.0)

func test_transfer_keeps_identity_cut_quality_and_detaches_all_arrays() -> void:
	var template: Dictionary = catalog.data()
	var source := make("source"); var destination := make("pot")
	var id: String = begin(source,"add",{"ingredient_id":"tomato"}).data.instance_id
	begin(source,"cut",{"instance_id":id,"beats":2}); completed(source,"test-2","cut",{"cut_directions":[0,1]})
	var prepared: Dictionary = source.snapshot().to_dict().ingredients[id]
	assert_true(source.transfer_to(destination,id,"transfer-1").ok)
	var state: Dictionary = destination.snapshot().to_dict()
	assert_eq(state.ingredients[id].id,id); assert_eq(state.ingredients[id].flavor,prepared.flavor)
	assert_eq(state.steps.size(),1); assert_eq(float(state.steps[0].quality),1.0)
	assert_true(source.snapshot().to_dict().ingredients.is_empty())
	assert_eq(source.transfer_to(destination,id,"transfer-1").code,"ALREADY_TRANSFERRED")
	assert_eq(state,destination.snapshot().to_dict())
	state.ingredients[id].flavor[0][0]=99
	assert_ne(state.ingredients[id].flavor,destination.snapshot().to_dict().ingredients[id].flavor)
	assert_eq(template,catalog.data())

func test_busy_pot_rejects_transfer_without_losing_either_side() -> void:
	var source := make("source"); var target := make("target")
	var id: String = begin(source,"add",{"ingredient_id":"tomato"}).data.instance_id
	begin(target,"add",{"ingredient_id":"egg"}); begin(target,"heat")
	var a: Dictionary = source.snapshot().to_dict(); var b: Dictionary = target.snapshot().to_dict()
	assert_eq(source.transfer_to(target,id,"move").code,"BUSY")
	assert_eq(source.snapshot().to_dict(),a); assert_eq(target.snapshot().to_dict(),b)

func test_parallel_heat_and_stir_finish_independently_once() -> void:
	var session := make("parallel")
	begin(session,"add",{"ingredient_id":"egg"})
	assert_true(begin(session,"heat").ok)
	assert_true(begin(session,"stir").ok)
	assert_eq(begin(session,"plate").code,"BUSY")
	assert_true(completed(session,"test-3","stir").ok)
	assert_eq(session.snapshot().to_dict().state,"operating")
	assert_true(completed(session,"test-2","heat",{"heat_dose":1.0}).ok)
	var before: Dictionary = session.snapshot().to_dict()
	assert_eq(before.steps.size(),2)
	assert_eq(completed(session,"test-2","heat",{"heat_dose":1.0}).code,"ALREADY_FINISHED")
	assert_eq(before,session.snapshot().to_dict())

func test_cancel_parallel_rejects_both_old_completions() -> void:
	var session := make("cancel")
	begin(session,"add",{"ingredient_id":"egg"}); begin(session,"heat"); begin(session,"stir")
	assert_true(session.cancel_operation().ok)
	assert_eq(completed(session,"test-2","heat").code,"CANCELLED")
	assert_eq(completed(session,"test-3","stir").code,"CANCELLED")
	assert_eq(session.snapshot().to_dict().steps.size(),0)

func test_actual_season_materials_and_order_change_flavor_and_no_input_adds_nothing() -> void:
	var session := make("spice")
	begin(session,"add",{"ingredient_id":"egg"}); begin(session,"season",{"ingredient_id":"salt","amount":.1})
	assert_true(completed(session,"test-2","season",{"actual_actions":[{"action":"spice:sugar","beat_index":0},{"action":"spice:salt","beat_index":1}],"quality":0.0}).ok)
	var items: Array = session.snapshot().to_dict().ingredients.values()
	assert_eq(items.size(),3); assert_eq(items[1].ingredient_id,"sugar"); assert_eq(items[2].ingredient_id,"salt")
	var other := make("empty")
	begin(other,"add",{"ingredient_id":"egg"}); begin(other,"season",{"ingredient_id":"salt","amount":.1})
	assert_true(completed(other,"test-4","season",{"actual_actions":[],"quality":0.0}).ok)
	assert_eq(other.snapshot().to_dict().ingredients.size(),1)

func test_handling_full_hands_board_occupancy_and_failure_keep_ownership() -> void:
	var handling := TDKitchenHandling.new(catalog)
	assert_true(handling.pick("tomato").ok)
	assert_eq(handling.pick("egg").code,"HANDS_FULL")
	assert_true(handling.put_board().ok)
	assert_true(handling.pick("egg").ok)
	assert_eq(handling.put_board().code,"BOARD_OCCUPIED")
	assert_eq(handling.take_board().code,"HANDS_FULL")
	var pot := make("pot")
	assert_true(handling.put_pot(pot).ok)
	assert_true(handling.take_board().ok)
	assert_true(handling.put_pot(pot).ok)
	assert_eq(pot.snapshot().to_dict().ingredients.size(),2)
	assert_true(handling.display().hand.is_empty())

func test_pc_bad_config_and_beat_sheet_are_rejected_before_play() -> void:
	var bad: Dictionary = catalog.data()
	bad.pc_operations.modules.stir.sequence=["unknown"]
	assert_false(TDCookingCatalog.new().load_data(bad).ok)
	bad=catalog.data(); bad.pc_operations.modules.heat.drag_strength=-1
	assert_false(TDCookingCatalog.new().load_data(bad).ok)
	bad=catalog.data(); bad.pc_operations.sheets.stir_fry.events[0].beat=-1
	assert_false(TDCookingCatalog.new().load_data(bad).ok)

func test_pc_cut_and_actual_season_plan_roundtrips_without_scores() -> void:
	var source := make("portable"); var destination := make("pot")
	var id: String = begin(source,"add",{"ingredient_id":"tomato"}).data.instance_id
	begin(source,"cut",{"instance_id":id,"beats":2}); completed(source,"test-2","cut",{"cut_directions":[0,1]})
	source.transfer_to(destination,id,"move")
	begin(destination,"season",{"ingredient_id":"salt","amount":.1})
	completed(destination,"test-3","season",{"actual_actions":[{"action":"spice:sugar","beat_index":0},{"action":"spice:salt","beat_index":1},{"action":"spice:oil","beat_index":2}]})
	var plan: Dictionary = destination.snapshot().to_dict().custom_plan
	assert_eq(plan.schema_version,2)
	var library := TDRecipeLibrary.new("res://artifacts/test-storage/pc-plan-unit.json",catalog.data())
	assert_true(library.validate_plan(plan).ok)
	var roundtrip: Dictionary = JSON.parse_string(JSON.stringify(plan))
	assert_true(library.validate_plan(roundtrip).ok)
	assert_eq(plan.operations.back().parameters.sequence,["sugar","salt","oil"])
	assert_false(JSON.stringify(plan).contains("quality"))
