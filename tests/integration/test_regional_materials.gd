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

func test_regional_supplier_catalogue_tracks_unlocked_seasonings() -> void:
	assert_false(p.suppliers.catalogue("tokyo").any(func(row:Dictionary)->bool:return row.id=="miso"))
	assert_true(p.research.recommend_cuisine("panel-jp","jp").ok)
	var ids:=p.suppliers.catalogue("tokyo").map(func(row:Dictionary)->String:return row.id)
	assert_has(ids,"miso")
	assert_has(ids,"salt")
	assert_does_not_have(ids,"oliveoil")

func test_backpack_matches_unfiltered_factory_lists_in_catalogue_order() -> void:
	var stock := {"tomato":4,"egg":3,"salt":1,"miso":2,"unknown":7,"oil":0}
	p.world.supply.stock = stock.duplicate()
	for region: String in ["chengdu","tokyo"]:
		p.world.town_id = region
		if region == "tokyo": assert_true(p.research.recommend_cuisine("pack-jp","jp").ok)
		var expected: Array = []
		for group: String in ["seasoning","vegetable","meat","fruit"]:
			for item: Dictionary in p.world.factory_products(group):
				if int(stock.get(item.id,0)) > 0:
					expected.append({"supply":group,"id":item.id,"name":p.service.cooking.ingredient_data(item.id).name,"qty":stock[item.id]})
		assert_false(expected.is_empty())
		assert_eq(p.world.factory_goods(), expected)
	p.world.supply.stock = {"salt":0}
	assert_eq(p.world.factory_goods(), [])
func season(index: int,cuisine: String,id: String,units: int=200) -> TDCookingLane:
	# Explicit boundary fixture: clone an existing recipe's M6, not a newly playable dish.
	assert_true(p.research.recommend_cuisine("material-test-"+cuisine,cuisine).ok)
	var data:=p.service.cooking.data()
	for recipe: Dictionary in data.recipes:
		if recipe.id=="service.tomato_egg": recipe["cuisine_id"]=cuisine
	var catalog:=TDCookingCatalog.new();var loaded:=catalog.load_data(data,"D069 M6 boundary fixture");assert_true(loaded.ok,loaded.message)
	var lane: TDCookingLane=kitchen.lanes[index];lane.catalog=catalog;lane.session_namespace=p.shop.day_namespace()+"material-test";lane.new_session("service.tomato_egg")
	var cart := {"tomato":1000}
	if units>0: cart[id]=units
	assert_true(p.shop.buy(cart,"spice-%d"%index).ok)
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
	assert_has(lane.spice_choices(),"miso");assert_does_not_have(lane.spice_choices(),"oliveoil")
	assert_eq(kitchen.stage.spice_rect(0,"oliveoil"),Rect2())
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

func test_single_cabinet_empty_disable_pause_and_cancel_do_not_mix_state() -> void:
	var left:=season(0,"jp","miso",30)
	if left.qte==null: return
	p.shop.receive_supply({"oliveoil":200},"oliveoil-test")
	kitchen.stage.lanes=[left];kitchen.stage.show();await wait_process_frames(2)
	assert_has(left.spice_choices(),"miso")
	assert_false(kitchen.stage.spice_rect(0,"miso").intersects(kitchen.stage.spice_rect(1,"oliveoil")))
	left.advance(1);mouse(kitchen.stage.spice_rect(0,"miso").get_center(),true)
	left.advance(.2);mouse(Vector2(5,5),false)
	assert_eq(p.shop.available("miso"),0);assert_eq(p.shop.available("oliveoil"),200)
	mouse(kitchen.stage.spice_rect(0,"miso").get_center(),true)
	assert_true("已用完" in kitchen.stage.empty_spice_notice)
	assert_gt(kitchen.stage.notice_until, kitchen.stage.beat_sec)
	left.cancel_operation(); left.new_session("service.tomato_egg")
	var right:=season(1,"eu","oliveoil",0)
	assert_has(right.spice_choices(),"oliveoil")
	kitchen.stage.lanes=[right]; right.advance(1)
	mouse(kitchen.stage.spice_rect(1,"oliveoil").get_center(),true);right.advance(.1)
	assert_eq(p.shop.available("oliveoil"),180)
	right.set_paused(true);right.advance(10);assert_eq(p.shop.available("oliveoil"),180)
	right.set_paused(false);right.cancel_operation();mouse(Vector2(5,5),false)
	assert_eq(p.shop.available("oliveoil"),180)
	var old:=right.session;right.new_session("service.tomato_egg")
	assert_ne(right.session,old);assert_eq(p.shop.available("oliveoil"),180)

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
