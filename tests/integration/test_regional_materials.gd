extends GutTest
var kitchen: TDFullKitchen
var p: TDGameProfile
var layer: CanvasLayer
func before_each() -> void:
	p=TDGameProfile.new();p.slot_id="slot-01";assert_true(p.error.ok,p.error.code)
	layer=CanvasLayer.new();layer.layer=130;get_tree().root.add_child(layer)
	kitchen=TDFullKitchen.new();kitchen.catalog=p.service.cooking;kitchen.scorer=TDCustomerScorer.new()
	kitchen.auto_advance=false;kitchen.library_path="res://artifacts/regional-materials/test-library-%d.json"%Time.get_ticks_usec()
	layer.add_child(kitchen);await wait_process_frames(2)
func after_each() -> void:
	get_tree().paused=false
	if kitchen!=null: kitchen.close()
	if layer!=null: layer.queue_free()
	if p!=null: p.close()
	await wait_process_frames(2)
func mouse(at: Vector2,down: bool) -> void:
	var motion:=InputEventMouseMotion.new();motion.position=at;motion.global_position=at;get_tree().root.push_input(motion,true)
	var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.position=at;event.global_position=at;event.pressed=down;get_tree().root.push_input(event,true)

func test_supplier_panel_refreshes_on_cuisine_event_and_disconnects_on_close() -> void:
	var before: int=p.research.changed.get_connections().size()
	var panel:=TDManagementPanels.SupplierPanel.new();layer.add_child(panel);panel.configure(p)
	panel.select_town("tokyo");panel.select_group("seasoning")
	assert_false(panel._products.any(func(row:Dictionary)->bool:return row.id=="miso"))
	assert_eq(p.research.changed.get_connections().size(),before+1)
	assert_true(p.research.recommend_cuisine("panel-jp","jp").ok)
	assert_true(panel._products.any(func(row:Dictionary)->bool:return row.id=="miso"))
	var ids: Array=[]
	for child: Node in panel._goods.get_children(): ids.append(child.product_id)
	assert_has(ids,"miso");assert_has(ids,"salt");assert_does_not_have(ids,"fishsauce")
	panel.configure(p);assert_eq(p.research.changed.get_connections().size(),before+1)
	panel.queue_free();await wait_process_frames(2)
	assert_eq(p.research.changed.get_connections().size(),before)
	assert_true(p.research.recommend_cuisine("after-close-sea","sea").ok)
func season(index: int,cuisine: String,id: String,units: int=200) -> TDCookingLane:
	# Explicit boundary fixture: clone an existing recipe's M6, not a newly playable dish.
	assert_true(p.research.recommend_cuisine("material-test-"+cuisine,cuisine).ok)
	var data:=p.service.cooking.data()
	for recipe: Dictionary in data.recipes:
		if recipe.id=="service.tomato_egg": recipe["cuisine_id"]=cuisine
	var catalog:=TDCookingCatalog.new();var loaded:=catalog.load_data(data,"D069 M6 boundary fixture");assert_true(loaded.ok,loaded.message)
	var lane: TDCookingLane=kitchen.lanes[index];lane.catalog=catalog;lane.session_namespace=p.shop.day_namespace()+"material-test";lane.new_session("service.tomato_egg")
	assert_true(p.shop.buy({id:units,"tomato":1000},"spice-%d"%index).ok)
	lane.session.set_material_sink(p.shop.consume_materials,p.shop.available)
	var added:=lane.perform("add",{"ingredient_id":"tomato","amount":1});assert_true(added.ok,added.code)
	lane._scheduled_settings={"kind":"sequence","pc_module":"M6","cabinet":true,"on_beat":true,"sequence":["spice:"+id],"timeout_sec":3.0,"lead_in_sec":1.0,"interval_sec":1.0,"beat_times_sec":[1.0],"hold_durations_sec":[.5],"pour_rate_per_sec":.2}
	var started:=lane.perform("season",{"ingredient_id":id,"amount":.1,"mode":"precise"});assert_true(started.ok,started.code)
	lane._scheduled_settings={}
	return lane

func test_real_cabinet_click_hold_deducts_foreign_material_and_updates_dish() -> void:
	var lane:=season(0,"jp","miso")
	if lane.qte==null: return
	kitchen.stage.lanes=[lane];kitchen.stage.show();await wait_process_frames(2)
	assert_has(lane.spice_choices(),"miso");assert_does_not_have(lane.spice_choices(),"fishsauce")
	assert_eq(kitchen.stage.spice_rect(0,"fishsauce"),Rect2())
	var initial_umami: float=lane.snapshot().dish_attributes.flavor[5][1]
	lane.advance(1)
	mouse(kitchen.stage.spice_rect(0,"miso").get_center(),true)
	assert_true(lane.qte.update().data.hold_pressed,"real mouse reached real M6")
	lane.advance(.5);mouse(Vector2(5,5),false)
	assert_eq(p.shop.available("miso"),100)
	lane.advance(3)
	var dish:=lane.snapshot()
	assert_gt(float(dish.dish_attributes.flavor[5][1]),initial_umami,"miso changes actual flavor")
	var foods: Array=dish.ingredients.values().filter(func(row:Dictionary)->bool:return row.ingredient_id=="miso")
	assert_eq(foods.size(),1)
	if not foods.is_empty(): assert_almost_eq(float(foods[0].amount),.1,.000001)
	assert_eq(p.shop.available("miso"),100,"completion does not deduct twice")
	assert_false(TDGuidedCookingView.spice_name("miso").is_empty())

func test_dual_cabinets_empty_disable_pause_and_cancel_do_not_mix_state() -> void:
	var left:=season(0,"jp","miso",30);var right:=season(1,"sea","fishsauce",200)
	if left.qte==null or right.qte==null: return
	kitchen.stage.lanes=[left,right];kitchen.stage.show();await wait_process_frames(2)
	assert_has(left.spice_choices(),"miso");assert_has(right.spice_choices(),"fishsauce")
	assert_false(kitchen.stage.spice_rect(0,"miso").intersects(kitchen.stage.spice_rect(1,"fishsauce")))
	left.advance(1);right.advance(1);mouse(kitchen.stage.spice_rect(0,"miso").get_center(),true)
	left.advance(.2);mouse(Vector2(5,5),false)
	assert_eq(p.shop.available("miso"),0);assert_eq(p.shop.available("fishsauce"),200)
	mouse(kitchen.stage.spice_rect(0,"miso").get_center(),true)
	assert_true("已用完" in kitchen.stage.feedback)
	mouse(kitchen.stage.spice_rect(1,"fishsauce").get_center(),true);right.advance(.1)
	assert_eq(p.shop.available("fishsauce"),180)
	right.set_paused(true);right.advance(10);assert_eq(p.shop.available("fishsauce"),180)
	right.set_paused(false);right.cancel_operation();mouse(Vector2(5,5),false)
	assert_eq(p.shop.available("fishsauce"),180)
	var old:=right.session;right.new_session("service.tomato_egg")
	assert_ne(right.session,old);assert_eq(p.shop.available("fishsauce"),180)

func test_foreign_customer_requests_stay_on_their_cuisine_cabinet() -> void:
	var data:=p.service.cooking.data()
	for recipe: Dictionary in data.recipes:
		if recipe.id=="service.tomato_egg": recipe["cuisine_id"]="jp"
	assert_true(p.service.cooking.load_data(data,"test foreign preference").ok)
	var customized:=p.service.request_profile("service.tomato_egg",{"requirements":[{"kind":"flavor","taste":5,"min":40,"weight":1}]})
	assert_not_null(customized)
	if customized==null: return
	var recipe: Dictionary=customized.for_recipe("service.tomato_egg").recipe
	var chart: Dictionary=customized.data().pc_operations.document_sheets[recipe.guided_profile]
	var spices: Array=[]
	for beat: Dictionary in chart.beats:
		for note: Dictionary in beat.lanes.values():
			if str(note.get("input","")).begins_with("spice:"): spices.append(str(note.input).trim_prefix("spice:"))
	assert_has(spices,"japanese_soy");assert_does_not_have(spices,"soy_sauce")
