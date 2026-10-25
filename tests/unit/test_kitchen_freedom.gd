extends GutTest

var catalog: TDServiceCatalog
var serial: int=0

func before_each() -> void:
	catalog=TDServiceCatalog.new(); assert_true(catalog.load_file().ok)

func session(id: String="test") -> TDCookingSession:
	return TDCookingSession.new(id,1,catalog.cooking.for_recipe("service.tomato_egg"),{"pc_controls":true,"document_rules":true})

func add_food(target: TDCookingSession, id: String) -> String:
	serial+=1
	var d: Dictionary=target.snapshot().to_dict()
	var request:=TDRequest.new(d.session_id,1,"add-%d"%serial,"add",d.revision,{"ingredient_id":id,"amount":1.0}); request.schema_version=3
	var result:=target.begin(request); assert_true(result.ok,result.code)
	return str(result.data.instance_id)

func test_move_one_item_out_of_multi_ingredient_pot_is_atomic_and_unique() -> void:
	var pot:=session("pot"); var hand:=session("hand")
	var beef: String=add_food(pot,"beef"); var tomato: String=add_food(pot,"tomato")
	var original: Dictionary=pot.snapshot().to_dict().ingredients[beef].duplicate(true)
	assert_true(pot.transfer_to(hand,beef,"take-beef").ok)
	assert_eq(pot.snapshot().to_dict().ingredients.keys(),[tomato])
	assert_eq(hand.snapshot().to_dict().ingredients[beef].flavor,original.flavor)
	assert_eq(hand.snapshot().to_dict().ingredients[beef].id,beef)
	assert_eq(pot.transfer_to(hand,beef,"take-beef").code,"ALREADY_TRANSFERRED")
	assert_true(hand.transfer_to(pot,beef,"put-back").ok)
	assert_eq(pot.snapshot().to_dict().consumed_ingredients.size(),2)
	assert_eq(pot.snapshot().to_dict().custom_plan.ingredients.size(),2)
	assert_false(pot.transfer_to(session("other"),"missing","bad").ok)
	assert_eq(pot.snapshot().to_dict().ingredients.size(),2)

func test_storage_replays_actual_cut_data_without_trusting_arbitrary_attributes() -> void:
	# Boundary fixture describes actual successful directions; live cutting is in scene tests.
	var raw: Dictionary={"schema_version":1,"id":"food-original","ingredient_id":"beef","amount":1.0,"cuts":[{"directions":[0,1],"quality":1.0,"elapsed_sec":6.0,"operation_id":"cut-original"}]}
	var a:=session("a"); assert_true(a.restore_portable(raw).ok)
	var state: Dictionary=a.snapshot().to_dict()
	assert_eq(state.ingredients[raw.id].shape,"chunk")
	assert_almost_eq(float(state.ingredients[raw.id].fine),.25,.000001)
	var saved:=a.portable_data(); assert_true(saved.ok)
	var b:=session("b"); assert_true(b.restore_portable(JSON.parse_string(JSON.stringify(saved.data))).ok)
	for field: String in state.ingredients[raw.id]: assert_eq(b.snapshot().to_dict().ingredients[raw.id][field],state.ingredients[raw.id][field],field)
	assert_eq(b.snapshot().to_dict().steps,state.steps)
	assert_false(b.restore_portable(saved.data).ok)
	for edit: Dictionary in [{"amount":-1},{"amount":NAN},{"ingredient_id":"ghost"},{"cuts":[{"directions":[9],"quality":1,"elapsed_sec":0,"operation_id":"x"}]},{"schema_version":99}]:
		var bad: Dictionary=raw.duplicate(true); bad.merge(edit,true)
		var candidate:=session("bad"); assert_false(candidate.restore_portable(bad).ok)
		assert_true(candidate.snapshot().to_dict().ingredients.is_empty())

func test_started_operation_cannot_return_ingredients() -> void:
	var pot:=session("pot"); var id: String=add_food(pot,"beef")
	var request:=TDRequest.new("pot",1,"heat","preheat",pot.snapshot().to_dict().revision,{}); request.schema_version=3
	assert_true(pot.begin(request).ok)
	assert_false(pot.transfer_to(session(),id,"take").ok)
	assert_false(pot.portable_data().ok)

func test_returned_cut_food_preserves_exposure_reaction_and_does_not_react_twice() -> void:
	var raw: Dictionary={"schema_version":1,"id":"exposed-food","ingredient_id":"tomato","amount":1.0,"cuts":[{"directions":[0,1],"quality":1.0,"elapsed_sec":6.0,"operation_id":"cut"}]}
	var source:=session("source"); assert_true(source.restore_portable(raw).ok)
	source.advance_time(20)
	var original: Dictionary=source.snapshot().to_dict()
	assert_true("cut_oxidation" in original.ingredients[raw.id].reactions)
	var portable:=source.portable_data(); assert_true(portable.ok)
	var saved: Dictionary=JSON.parse_string(JSON.stringify(portable.data)); var before: Dictionary=saved.duplicate(true)
	var restored:=session("restored"); assert_true(restored.restore_portable(saved).ok); assert_eq(saved,before)
	var attributes: Dictionary=restored.snapshot().to_dict().dish_attributes
	for field: String in original.dish_attributes:
		if field=="flavor":
			for taste: int in 7:
				for slot: int in 4: assert_almost_eq(float(attributes.flavor[taste][slot]),float(original.dish_attributes.flavor[taste][slot]),.00000001,"JSON round-trip taste %d/%d"%[taste,slot])
		else: assert_eq(attributes[field],original.dish_attributes[field],field)
	assert_eq(restored.snapshot().to_dict().ingredients[raw.id].exposure_sec,20.0)
	var flavor: Array=restored.snapshot().to_dict().ingredients[raw.id].flavor.duplicate(true)
	restored.advance_time(5)
	assert_eq(restored.snapshot().to_dict().ingredients[raw.id].flavor,flavor)
	assert_eq(restored.snapshot().to_dict().ingredients[raw.id].reactions,["cut_oxidation"])
	var invalid: Dictionary=saved.duplicate(true); invalid.processing_state.flavor[0][0]=NAN
	assert_false(session("invalid").restore_portable(invalid).ok)

func test_locked_recipe_method_and_corrupt_progress_are_explicit() -> void:
	var shop:=TDShopSession.new(catalog,"unit")
	assert_eq(shop.snapshot().unlocked.size(),5)
	assert_false(shop.is_unlocked("service.qiguoji"))
	assert_eq(shop.set_menu("service.qiguoji",true,2200).code,"RECIPE_NOT_UNLOCKED")
	assert_eq(shop.context_for_ingredients(["chicken","mushroom"],true,"steam").recipe_id,"service.qiguoji")
	assert_true(shop.context_for_ingredients(["chicken","mushroom"],true,"stir").is_empty())
	assert_true(shop.context_for_ingredients(["beef"],true,"stir").is_empty())
	for field: String in ["cold_foods","unlocked"]:
		var invalid: Dictionary=shop.snapshot(); invalid[field]="bad"; assert_false(shop.validate_save(invalid).ok)
	var future: Dictionary=shop.snapshot(); future.progress_version=999; assert_eq(shop.validate_save(future).code,"UNSUPPORTED_VERSION")
	var duplicate: Dictionary=shop.snapshot(); duplicate.unlocked.append(duplicate.unlocked[0]); assert_false(shop.validate_save(duplicate).ok)

func test_old_boundary_migrates_five_unlocked_without_touching_old_input() -> void:
	var shop:=TDShopSession.new(catalog,"legacy")
	var old: Dictionary=shop.snapshot()
	for key: String in ["progress_version","cold_foods","unlocked","stock_version","inventory_lots","mastery_version","mastery","mastery_dishes"]: old.erase(key)
	old.inventory.erase("mushroom"); old.menu.erase("service.qiguoji"); old.fame.erase("service.qiguoji")
	var before: Dictionary=old.duplicate(true)
	assert_true(shop.restore(old).ok)
	assert_eq(old,before); assert_eq(shop.snapshot().unlocked.size(),5)
	assert_eq(shop.available("mushroom"),0); assert_false(shop.snapshot().menu["service.qiguoji"].enabled)

func test_processed_food_normalized_twice_remains_valid() -> void:
	var shop:=TDShopSession.new(catalog,"cold-run")
	var raw: Dictionary={"schema_version":1,"id":"cold-run:d1:food","ingredient_id":"beef","amount":1.0,"cuts":[{"directions":[0,1,0],"quality":1.0,"elapsed_sec":6.0,"operation_id":"cut"}]}
	var model:=session(); model.restore_portable(raw)
	shop.open_day(); assert_true(shop.store_food(model.portable_data().data).ok); shop.close_early()
	var decoded: Dictionary=JSON.parse_string(JSON.stringify(shop.snapshot()))
	assert_true(shop.validate_save(decoded).ok)
	var normalized: Dictionary=TDShopSession.normalize_save(decoded)
	assert_true(shop.validate_save(normalized).ok)
	assert_true(shop.restore(normalized).ok)
	assert_eq(shop.snapshot().cold_foods.size(),1)

func test_free_seasoning_uses_actual_time_pause_and_no_fake_perfect() -> void:
	var request:=TDRequest.new("free",1,"season","season",0); request.schema_version=3
	var config: Dictionary=catalog.cooking.data().pc_operations.modules.season.duplicate(true)
	config.merge({"free_seasoning":true,"free_duration_sec":8.0,"pour_rate_per_sec":.2,"sequence":["spice:salt"],"on_beat":true,"document_rules":true,"beat_times_sec":[1.0]},true)
	var clock:=TDClock.new(); var qte:=TDCookingQTE.new(request,config,clock,TDBusinessRandom.new(1)); assert_true(qte.start().ok)
	clock.advance(.3); assert_true(qte.input(1,clock.qte_sec,"spice:sugar",true).ok)
	clock.advance(.5); qte.input(2,clock.qte_sec,"spice:sugar",false)
	assert_almost_eq(float(qte.update().data.actual_actions[0].amount),.1,.000001)
	qte.input(3,clock.qte_sec,"spice:salt",true); clock.advance(.2); qte.release_input()
	clock.paused=true; clock.advance(20); qte.update(); clock.paused=false
	assert_false(qte.update().data.hold_pressed)
	qte.input(4,clock.qte_sec,"spice:salt",true); clock.advance(.3); qte.input(5,clock.qte_sec,"spice:salt",false)
	clock.advance(10); var result:=qte.finish(); assert_true(result.ok)
	assert_eq(result.data.actual_actions.size(),2); assert_almost_eq(float(result.data.actual_actions[1].amount),.1,.000001)
	assert_eq(result.data.quality,0.0); assert_false(qte.input(6,clock.qte_sec,"spice:salt",false).ok)

func test_season_prompt_follows_actual_acceptance_not_mouse_click_visual() -> void:
	var p: Dictionary={"sequence_index":0,"sequence":["spice:sugar"],"beat_times_sec":[2.0],"elapsed_sec":0.0,"hold_index":-1,"good_sec":.1}
	assert_eq(TDGuidedCookingView.season_prompt(p).phase,"waiting")
	p.elapsed_sec=2.0; assert_eq(TDGuidedCookingView.season_prompt(p).phase,"press")
	p.hold_index=0; p.hold_action="spice:sugar"; p.hold_pressed=true; p.hold_durations_sec=[1.0]; p.note_held_sec=.2
	assert_eq(TDGuidedCookingView.season_prompt(p).phase,"holding")
	p.note_held_sec=1.0; assert_eq(TDGuidedCookingView.season_prompt(p).phase,"release")
	p.note_held_sec=1.2; assert_eq(TDGuidedCookingView.season_prompt(p).phase,"late")
	p.hold_pressed=false; assert_true(TDGuidedCookingView.season_prompt(p).title.contains("重新按住"))
