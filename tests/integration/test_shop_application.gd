extends GutTest
const APP:=preload("res://src/app/main.tscn")
var app: TDApplication
var view: TDShopView
var kitchen: TDFullKitchen
var layer: CanvasLayer
var sent: Dictionary
var save_path: String
var season_duration_scale: float = 1.0
var release_outside: bool = false

class MenuRandom extends RefCounted:
	var count: int=0
	func unit() -> float:
		count+=1
		return 0.0 if count==1 else .99

func before_each() -> void:
	season_duration_scale=1.0; release_outside=false
	DirAccess.make_dir_recursive_absolute("res://artifacts/test-storage")
	layer=CanvasLayer.new(); layer.layer=131; autofree(layer); get_tree().root.add_child(layer)
	app=APP.instantiate() as TDApplication; app.settings_path="res://artifacts/test-storage/phase2-settings.json"
	save_path="res://artifacts/test-storage/service-%d.json" % Time.get_ticks_usec(); app.shop_save_path=save_path
	layer.add_child(app)
	# Historical five-recipe save fixture; new-player research is covered separately.
	var world:=app._phase3()
	app.research.inherit_legacy(world.catalog.dish_list().filter(func(d:Dictionary)->bool:return d.get("starter",false)).map(func(d:Dictionary)->String:return d.id))
	app.enter_shop(); view=app.shop_view; kitchen=view.kitchen; kitchen.auto_advance=false; sent={}
	for recipe_id:String in view.shop.snapshot().menu:
		view.shop.set_menu(recipe_id,recipe_id=="service.tomato_egg",int(view.shop.offer(recipe_id).reference_cents))
	await get_tree().process_frame

func after_each() -> void:
	get_tree().paused=false; app.return_to_menu(); await get_tree().process_frame; await get_tree().process_frame

func key(code: Key,pressed: bool=true) -> void:
	var e:=InputEventKey.new(); e.keycode=code; e.physical_keycode=code; e.pressed=pressed; get_tree().root.push_input(e,true)
func tap(code: Key) -> void: key(code); key(code,false)
func station(id: String, button: Key=KEY_E) -> void:
	for entry: Dictionary in kitchen.world.stations():
		if entry.id==id: (kitchen.world.get_node("Player") as TDKitchenPlayer).position=entry.position+Vector2(0,40); (kitchen.world.get_node("Player") as TDKitchenPlayer).face(Vector2.UP); tap(button); return
func click(at: Vector2) -> void:
	var motion:=InputEventMouseMotion.new(); motion.position=at; motion.global_position=at; get_tree().root.push_input(motion,true)
	for down: bool in [true,false]:
		var e:=InputEventMouseButton.new(); e.position=at; e.global_position=at; e.button_index=MOUSE_BUTTON_LEFT; e.pressed=down; get_tree().root.push_input(e,true)
func hold_mouse(at: Vector2,pressed: bool) -> void:
	var event:=InputEventMouseButton.new(); event.position=at; event.global_position=at; event.button_index=MOUSE_BUTTON_LEFT; event.pressed=pressed; get_tree().root.push_input(event,true)

func play(seconds: float, input_enabled: bool=true) -> void:
	for frame: int in int(seconds/.025):
		kitchen.advance(.025)
		if not input_enabled or not kitchen.stage.visible: continue
		for lane: TDCookingLane in kitchen.stage.lanes.duplicate():
			if lane.qte==null: continue
			var p: Dictionary=lane.progress.duplicate(true)
			var token: String=str(p.operation_id)
			var kind: String=p.qte_kind
			if p.get("free_seasoning",false):
				var done: int=p.actual_actions.size()
				if int(p.hold_index)>=0 and float(p.note_held_sec)+.000001>=.5+float(done)*.25:
					hold_mouse(kitchen.stage.spice_rect(lane.lane_index,str(p.hold_action).trim_prefix("spice:")).get_center(),false)
				elif int(p.hold_index)<0 and done<2 and float(p.elapsed_sec)>.5+done*2:
					hold_mouse(kitchen.stage.spice_rect(lane.lane_index,"sugar" if done==0 else "salt").get_center(),true)
				continue
			if p.has("hold_durations_sec") and int(p.hold_index)>=0 and float(p.note_held_sec)+.000001>=float(p.hold_durations_sec[int(p.hold_index)])*season_duration_scale:
				hold_mouse(Vector2(1270,20) if release_outside else kitchen.stage.spice_rect(lane.lane_index,str(p.hold_action).trim_prefix("spice:")).get_center(),false)
			if kind in ["rhythm","sequence"]:
				for index: int in p.beat_times_sec.size():
					var marker: String=token+":"+str(index)
					if sent.has(marker) or float(p.elapsed_sec)+.000001<float(p.beat_times_sec[index]): continue
					sent[marker]=true
					var action: String=str(p.cut_actions[index]) if kind=="rhythm" and not p.get("cut_actions",[]).is_empty() else ("primary" if kind=="rhythm" else str(p.sequence[index]))
					if action.begins_with("spice:"):
						var r: Rect2=kitchen.stage.spice_rect(lane.lane_index,action.trim_prefix("spice:"));
						if p.has("hold_durations_sec"): hold_mouse(r.get_center(),true)
						else: click(r.get_center())
					else:
						var codes: Dictionary={"primary":KEY_SPACE,"rotate_left":KEY_A,"rotate_right":KEY_D,"up":KEY_W,"left":KEY_A,"down":KEY_S,"right":KEY_D} if lane.lane_index!=1 else {"primary":KEY_SPACE,"up":KEY_UP,"left":KEY_LEFT,"down":KEY_DOWN,"right":KEY_RIGHT}
						tap(codes[action])
			elif kind=="window" and not sent.has(token) and float(p.elapsed_sec)+.000001>=float(p.target_sec): sent[token]=true; tap(KEY_SPACE)
			elif kind=="charge":
				if not sent.has(token) and float(p.get("preview_remaining_sec",0))<=.000001: sent[token]=true; key(KEY_SPACE)
				elif float(p.held_sec)+.000001>=(float(p.target_min_sec)+float(p.target_max_sec))*.5: key(KEY_SPACE,false)


func prepare_order(recipe_id: String) -> String:
	for id: String in view.shop.snapshot().menu: view.shop.set_menu(id,id==recipe_id,int(view.shop.offer(id).reference_cents))
	assert_true(view.buy_kit(recipe_id).ok)
	view.open_day(); kitchen=view.kitchen; kitchen.auto_advance=false; sent={}
	for lane: TDCookingLane in kitchen.lanes+[kitchen.prep]: lane.beat_offset_sec=0
	kitchen.advance(1)
	var id: String=view.shop.active_orders()[0].id
	assert_eq(view.shop.order(id).status,"WAITING")
	return id

func choose_requested_cut(ingredient: String, order: Dictionary) -> void:
	var recipe: Dictionary=kitchen.catalog.for_recipe(view.shop.family_id(order.recipe_id)).recipe
	var sheet: String=str(recipe.preparation_sheets.get(ingredient,"prepare"))
	var shape: String={"prepare":"chunk","service.slice":"slice","service.strips":"strip","service.dice":"dice","service.small":"dice"}.get(sheet,"chunk")
	for request: Dictionary in order.customer.requirements:
		if request.get("kind")=="fine" and request.get("ingredient_id")==ingredient and float(request.get("min",0))>=.6: shape="dice"
	assert_true(view.choose_cut(shape).ok)

func cook_order(id: String) -> void:
	var recipe_id: String=view.shop.order(id).recipe_id
	var target:String="kitchen.steamer" if kitchen.catalog.for_recipe(recipe_id).recipe.get("cooking_method")=="steam" else "kitchen.stove.left"
	var lane_index:int=1 if target=="kitchen.steamer" else 0
	for ingredient: String in view.shop.offer(recipe_id).primary:
		station("kitchen.fridge"); assert_true(view.pick_ingredient(ingredient).ok); view._close_popup()
		if kitchen.catalog.for_recipe(recipe_id).recipe.preparation_sheets.has(ingredient):
			station("kitchen.board"); choose_requested_cut(ingredient,view.shop.order(id)); assert_true(kitchen.stage.visible); play(12); station("kitchen.board")
		station(target)
	station(target,KEY_F); assert_true(kitchen.stage.visible); play(70)
	assert_eq(kitchen.lanes[lane_index].snapshot().state,"plated")
	station(target); station("kitchen.serve")
	assert_eq(view.shop.order(id).status,"SERVED")
	assert_true(view.shop.order(id).score.has("satisfaction"))
	assert_eq(kitchen.handling.hand_kind,"")

func test_real_tomato_egg_inventory_cooking_and_customer_delivery() -> void:
	var id: String=prepare_order("service.tomato_egg")
	cook_order(id)
	var before: Dictionary=view.shop.snapshot()
	station("kitchen.serve"); assert_eq(view.shop.snapshot(),before)

func mastered_fixture(recipe_id: String) -> void:
	# Explicit precondition: historical four 100-point handmade dishes, not QTE evidence.
	for i: int in 4:
		assert_true(view.shop.observe_mastery({"session_id":view.shop.day_namespace()+"history","recipe_id":recipe_id,"dish_id":"history-%d"%i,"state":"plated","missing_required":[],"performance_score":100.0}).ok)

func load_raw_pot(index: int) -> void:
	for ingredient: String in ["tomato","egg"]:
		assert_true(view.pick_ingredient(ingredient).ok)
		station("kitchen.stove.left" if index==0 else "kitchen.stove.right")

func test_automatic_real_workflow_pause_delivery_and_no_mastery_farming() -> void:
	var id:=prepare_order("service.tomato_egg");mastered_fixture("service.tomato_egg")
	load_raw_pot(0)
	var before: Dictionary=view.shop.snapshot().inventory
	assert_true(view.start_automatic(0).ok)
	assert_ne(kitchen.lanes[0].snapshot().state,"plated")
	assert_eq(view.start_automatic(0).code,"BUSY")
	kitchen.advance(3);app.toggle_pause();var paused:=kitchen.lanes[0].snapshot()
	kitchen.advance(100);assert_eq(kitchen.lanes[0].snapshot(),paused);app.toggle_pause()
	play(100,false)
	var dish:=kitchen.lanes[0].snapshot()
	assert_eq(dish.state,"plated",str(kitchen.lanes[0].last_result.code));assert_false(dish.failed_dish)
	assert_eq(dish.production_mode,"automatic");assert_lte(float(dish.performance_score),85.00001)
	assert_eq(view.shop.mastery("service.tomato_egg").points,400.0)
	assert_lt(view.shop.available("oil"),int(before.oil));assert_lt(view.shop.available("salt"),int(before.salt))
	station("kitchen.stove.left");station("kitchen.serve");assert_eq(view.shop.order(id).status,"SERVED")

func test_automatic_two_real_pots_keep_state_and_consumption_independent() -> void:
	view.buy_kit("service.tomato_egg");view.buy_kit("service.tomato_egg",false)
	view.open_day();kitchen=view.kitchen;kitchen.auto_advance=false;mastered_fixture("service.tomato_egg")
	for lane: TDCookingLane in kitchen.lanes: lane.beat_offset_sec=0
	load_raw_pot(0);load_raw_pot(1)
	assert_true(view.start_automatic(0).ok);assert_true(view.start_automatic(1).ok)
	play(100,false)
	assert_eq(kitchen.lanes[0].snapshot().state,"plated");assert_eq(kitchen.lanes[1].snapshot().state,"plated")
	assert_ne(kitchen.lanes[0].snapshot().session_id,kitchen.lanes[1].snapshot().session_id)
	assert_eq(view.shop.mastery("service.tomato_egg").points,400.0)
	for amount: int in view.shop.snapshot().inventory.values(): assert_gte(amount,0)

func test_fridge_shows_only_owned_categories_and_preserves_return_expiry() -> void:
	view.buy_kit("service.tomato_egg");view.open_day();kitchen=view.kitchen;kitchen.auto_advance=false
	assert_eq(view.pantry_entries("fruit"),[])
	assert_false(view.pantry_entries("meat").any(func(e:Dictionary)->bool:return e.ingredient_id=="beef"))
	var expiry: int=view.shop.stock_info("tomato").expires_on
	assert_true(view.pick_ingredient("tomato").ok);station("kitchen.board");view.choose_cut("chunk");play(12)
	station("kitchen.board");assert_true(view.return_ingredient().ok)
	var foods: Array=view.pantry_entries("vegetable")
	assert_eq(foods.size(),1);assert_eq(int(foods[0].expires_on),expiry)
	station("kitchen.fridge");assert_eq(view._popup.find_children("*","TabContainer",true,false).size(),1)

func test_automatic_missing_stock_rejects_atomically() -> void:
	prepare_order("service.tomato_egg");mastered_fixture("service.tomato_egg");load_raw_pot(0)
	assert_true(view.shop.consume_materials(view.shop.day_namespace()+"waste-oil",{"oil":view.shop.available("oil")}).ok)
	var before:=kitchen.lanes[0].snapshot();var stock:=view.shop.snapshot()
	assert_eq(view.start_automatic(0).code,"INSUFFICIENT_STOCK")
	assert_eq(kitchen.lanes[0].snapshot(),before);assert_eq(view.shop.snapshot(),stock)

func test_automatic_cancel_clears_schedule_without_refunding_used_material() -> void:
	prepare_order("service.tomato_egg");mastered_fixture("service.tomato_egg");load_raw_pot(0)
	assert_true(view.start_automatic(0).ok);kitchen.advance(3)
	kitchen.lanes[0].cancel_operation();var left: Dictionary=view.shop.snapshot().inventory
	play(60,false);assert_eq(view.shop.snapshot().inventory,left)
	assert_null(kitchen.lanes[0].qte);assert_true(kitchen.lanes[0].sheet==null or not kitchen.lanes[0].sheet.running)
	assert_eq(view.shop.mastery("service.tomato_egg").points,400.0)

func test_research_starters_and_unlocked_examples_use_real_cooking_and_delivery() -> void:
	for id:String in ["C03","C04"]:
		var begun:=app._begin_study(id);assert_true(begun.ok)
		app.add_child(app.research.controller)
		assert_true(load("res://tools/test_support/research_input.gd").play(app.research,begun.data.token))
		assert_true(app.research.finish(begun.data.token).ok)
	for id:String in ["study.egg_fried_rice","study.yangchun_noodles","study.steamed_egg"]:
		app.return_to_menu();await get_tree().process_frame;app.shop_save_path=save_path+"."+id;app.enter_shop();view=app.shop_view;kitchen=view.kitchen;kitchen.auto_advance=false
		assert_true(view.shop.is_unlocked(id));var order_id:=prepare_order(id);cook_order(order_id)
		assert_false(view.shop.order(order_id).score.is_empty());assert_false(kitchen.lanes[0 if id!="study.steamed_egg" else 1].snapshot().failed_dish)

func test_real_beef_noodles_inventory_cooking_and_customer_delivery() -> void:
	var id: String=prepare_order("service.beef_noodles")
	cook_order(id)
	var before: Dictionary=view.shop.snapshot()
	station("kitchen.serve"); assert_eq(view.shop.snapshot(),before)

func test_real_mapo_tofu_inventory_cooking_and_customer_delivery() -> void:
	var id: String=prepare_order("service.mapo_tofu")
	cook_order(id)
	var before: Dictionary=view.shop.snapshot()
	station("kitchen.serve"); assert_eq(view.shop.snapshot(),before)

func test_real_kungpao_inventory_cooking_and_customer_delivery() -> void:
	var id: String=prepare_order("service.kungpao")
	cook_order(id)
	var before: Dictionary=view.shop.snapshot()
	station("kitchen.serve"); assert_eq(view.shop.snapshot(),before)

func test_real_pepper_pork_inventory_cooking_and_customer_delivery() -> void:
	var id: String=prepare_order("service.pepper_pork")
	cook_order(id)
	var before: Dictionary=view.shop.snapshot()
	station("kitchen.serve"); assert_eq(view.shop.snapshot(),before)

func test_real_three_days_save_restart_and_custom_menu() -> void:
	var custom_id: String=""
	for day: int in range(1,4):
		var id: String=prepare_order("service.tomato_egg" if custom_id.is_empty() else custom_id)
		cook_order(id)
		if day>1:
			assert_eq(view.shop.order(id).used.get("vinegar"),200)
			assert_eq(view.shop.order(id).used.get("sugar",0),200 if view.shop.order(id).customer.id=="sweet" else 0)
			assert_true(view.shop.order(id).customer.requirements.any(func(r:Dictionary)->bool:return r.get("ingredient_id")=="tomato"))
		view.shop.close_early()
		for remaining: Dictionary in view.shop.active_orders(): view.cancel_order(remaining.id)
		kitchen.advance(.01); assert_eq(view.shop.snapshot().phase,"SETTLED")
		var summary_titles: int=0
		for label: Label in view._page.find_children("*","Label",true,false):
			if "收益总结" in label.text: summary_titles+=1
		assert_gt(summary_titles,0)
		if day==1:
			var saved:=view.save_order_plan(id,"小店招牌炒蛋")
			assert_true(saved.ok,saved.code+" "+saved.message)
			if saved.ok: custom_id=saved.data.id
			if saved.ok:
				var reordered: Dictionary=saved.data.duplicate(true)
				reordered.plan.operations.push_front(reordered.plan.operations.pop_back())
				assert_eq(view.service.compile_plan(reordered).code,"PLAN_ORDER_UNSUPPORTED")
				var changed: Dictionary=saved.data.duplicate(true)
				for ingredient: Dictionary in changed.plan.ingredients:
					if ingredient.ingredient_id=="sugar": ingredient.ingredient_id="vinegar"
				for operation: Dictionary in changed.plan.operations:
					if operation.parameters.has("sequence"): operation.parameters.sequence[1]="vinegar"
				var compiled:=view.service.compile_plan(changed)
				assert_true(compiled.ok)
				assert_true(JSON.stringify(compiled.data.sheets).contains("spice:vinegar"))
				var renamed:=view.shop.save_plan("换醋招牌炒蛋",changed.plan,custom_id)
				assert_true(renamed.ok); assert_eq(renamed.data.id,custom_id); assert_eq(renamed.data.version,2)
				assert_false(JSON.stringify(renamed.data.plan).contains("satisfaction"))
		var boundary:=view.save_boundary()
		assert_true(boundary.ok,boundary.code+" "+boundary.message)
		if not boundary.ok: return
		var previous: Dictionary=view.shop.snapshot()
		app.return_to_menu(); await get_tree().process_frame; app.enter_shop(true); view=app.shop_view; kitchen=view.kitchen; kitchen.auto_advance=false
		assert_eq(JSON.parse_string(JSON.stringify(view.shop.snapshot())),JSON.parse_string(JSON.stringify(previous)))
		view.next_day(); assert_eq(view.shop.snapshot().day,day+1)

func test_pause_cancel_and_late_input_dont_consume_a_new_order() -> void:
	var id: String=prepare_order("service.tomato_egg")
	view.pick_ingredient("tomato"); station("kitchen.board"); view.choose_cut("chunk"); kitchen.advance(1)
	var old: TDCookingQTE=kitchen.prep.qte
	var before: Dictionary=view.shop.snapshot(); app.toggle_pause(); kitchen.advance(300); tap(KEY_SPACE)
	assert_eq(view.shop.snapshot(),before); app.toggle_pause()
	view.cancel_order(id); assert_eq(view.shop.order(id).status,"CANCELLED")
	assert_not_null(kitchen.handling.board)
	assert_true(kitchen.prep.sheet.running)
	assert_true(old==kitchen.prep.qte)
	assert_eq(view.shop.available("tomato"),0)

func test_ingredients_are_not_bound_to_a_customer_or_pot() -> void:
	view.buy_kit("service.tomato_egg"); view.buy_kit("service.tomato_egg",false)
	view.open_day(); kitchen=view.kitchen; kitchen.auto_advance=false; kitchen.advance(1)
	var first: String=view.shop.active_orders()[0].id
	view.pick_ingredient("tomato"); station("kitchen.board"); view.choose_cut("chunk"); play(12)
	kitchen.advance(70)
	assert_eq(view.shop.active_orders().size(),2)
	station("kitchen.board"); station("kitchen.stove.right")
	assert_eq(kitchen.lanes[1].snapshot().ingredients.size(),1)
	assert_eq(kitchen.lanes[0].snapshot().ingredients.size(),0)
	assert_eq(view.shop.order(first).status,"WAITING")
	assert_eq(view._sidebar.find_children("*","Button",true,false).size(),0)

func test_real_gui_purchase_and_open_buttons_start_business() -> void:
	await get_tree().process_frame
	var forecast_shown: bool=false
	for label: Label in view._page.find_children("*","Label",true,false):
		if label.text=="第 1 天 · 预计到店 6—10 位客人": forecast_shown=true
	assert_true(forecast_shown,"采购前显示当天预计访客范围")
	var buy: Button
	for button: Button in view._page.find_children("*","Button",true,false):
		if button.text.begins_with("补齐"): buy=button; break
	assert_not_null(buy)
	click(buy.get_global_rect().get_center()); await get_tree().process_frame
	assert_eq(view.shop.available("tomato"),1000)
	click(view._open_button.get_global_rect().get_center()); await get_tree().process_frame
	kitchen=view.kitchen; kitchen.auto_advance=false
	assert_eq(view.shop.snapshot().phase,"OPEN")
	assert_true(FileAccess.file_exists(save_path))

func test_long_frame_expires_order_before_later_cooking_consumption() -> void:
	var id: String=prepare_order("service.tomato_egg")
	view.pick_ingredient("tomato"); station("kitchen.board"); view.choose_cut("chunk"); play(12)
	station("kitchen.board"); station("kitchen.stove.left")
	view.pick_ingredient("egg"); station("kitchen.stove.left")
	kitchen.advance(240.0-float(view.shop.snapshot().elapsed_sec))
	station("kitchen.stove.left",KEY_F); assert_true(kitchen.stage.visible)
	kitchen.advance(60)
	assert_eq(view.shop.order(id).status,"TIMED_OUT")
	assert_eq(kitchen.lanes[0].snapshot().state,"plated")
	assert_gt(kitchen.lanes[0].snapshot().ingredients.size(),2)
	assert_null(kitchen.lanes[0].qte)

func test_window_close_warns_and_cancel_preserves_live_order() -> void:
	var id: String=prepare_order("service.tomato_egg")
	assert_false(get_tree().auto_accept_quit)
	app._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	var dialogs: Array[Node]=view.find_children("*","ConfirmationDialog",false,false)
	assert_eq(dialogs.size(),1)
	assert_true((dialogs[0] as ConfirmationDialog).dialog_text.contains("当前订单和做菜进度会丢失"))
	(dialogs[0] as ConfirmationDialog).canceled.emit()
	await get_tree().process_frame
	assert_eq(view.shop.order(id).status,"WAITING")
	assert_eq(view.store.load_game().data.phase,"PREPARE")

func test_real_mouse_hold_release_outside_changes_usage_and_recipe_amounts() -> void:
	season_duration_scale=.4; release_outside=true
	var id: String=prepare_order("service.tomato_egg")
	cook_order(id)
	var item: Dictionary=view.shop.order(id)
	assert_eq(item.used.get("salt"),40)
	assert_eq(item.used.get("sugar"),80)
	assert_eq(item.used.get("oil"),140)
	assert_eq(item.plan.schema_version,3)
	var season: Dictionary={}
	for step: Dictionary in item.plan.operations:
		if step.parameters.has("sequence"): season=step.parameters
	assert_eq(season.amounts,[.04,.08,.04])
	view.shop.close_early(); kitchen.advance(.01)
	var saved:=view.save_order_plan(id,"少盐短按炒蛋")
	assert_true(saved.ok,saved.code)
	if not saved.ok: return
	var edited: Dictionary=saved.data.duplicate(true)
	for ingredient: Dictionary in edited.plan.ingredients:
		if ingredient.local_id in season.local_ids: ingredient.amount=.17
	for step: Dictionary in edited.plan.operations:
		if step.parameters.has("sequence"): step.parameters.amounts=[.17,.17,.17]
	var compiled:=view.service.compile_plan(edited)
	assert_true(compiled.ok,compiled.code)
	if not compiled.ok: return
	var chart:=TDBeatSheet.new()
	assert_true(chart.configure(compiled.data.sheets[edited.id],kitchen.catalog.data().operations).ok)
	var event: Dictionary=chart.snapshot().events.filter(func(x:Dictionary)->bool:return x.operation=="season" and x.parameters.get("mode")=="precise")[0]
	assert_eq(event.settings.hold_durations_sec,[.85,.85,.85])

func test_same_family_two_customers_really_play_different_cut_and_season_charts() -> void:
	view.buy_kit("service.tomato_egg"); view.buy_kit("service.tomato_egg",false)
	view.open_day(); kitchen=view.kitchen; kitchen.auto_advance=false
	for lane: TDCookingLane in kitchen.lanes+[kitchen.prep]: lane.beat_offset_sec=0
	kitchen.advance(81)
	var first: String=view.shop.active_orders()[0].id; var second: String=view.shop.active_orders()[1].id
	cook_order(first)
	var large: Dictionary=view.shop.order(first)
	assert_eq(large.used.sugar,200)
	assert_eq(large.plan.operations.filter(func(s:Dictionary)->bool:return s.operation=="cut")[0].parameters.shape,"chunk")
	cook_order(second)
	var small: Dictionary=view.shop.order(second)
	assert_eq(small.used.soy_sauce,150)
	var cut: Dictionary=small.plan.operations.filter(func(s:Dictionary)->bool:return s.operation=="cut")[0]
	assert_eq(cut.parameters.shape,"dice"); assert_eq(cut.parameters.beats,8)
	assert_eq(large.plan.recipe_id,small.plan.recipe_id)
	assert_eq(view._sidebar.find_children("*","Button",true,false).size(),0)

func test_second_different_dish_can_be_served_before_first_customer() -> void:
	view.buy_kit("service.tomato_egg"); view.buy_kit("service.pepper_pork")
	view.shop.set_menu("service.pepper_pork",true,2600)
	view.open_day(); kitchen=view.kitchen; kitchen.auto_advance=false; view.shop._rng=MenuRandom.new()
	for lane: TDCookingLane in kitchen.lanes+[kitchen.prep]: lane.beat_offset_sec=0
	kitchen.advance(81)
	var first: Dictionary=view.shop.active_orders()[0]; var second: Dictionary=view.shop.active_orders()[1]
	assert_eq(first.recipe_id,"service.tomato_egg"); assert_eq(second.recipe_id,"service.pepper_pork")
	cook_order(second.id)
	assert_eq(view.shop.order(first.id).status,"WAITING")
	assert_eq(view.shop.order(second.id).status,"SERVED")

func test_one_fridge_all_materials_and_only_one_held_item() -> void:
	view.buy_kit("service.tomato_egg"); view.buy_kit("service.beef_noodles")
	view.open_day(); kitchen=view.kitchen; kitchen.auto_advance=false; kitchen.advance(1)
	assert_eq(kitchen.world.stations().filter(func(s:Dictionary)->bool:return s.get("kind")=="fridge").size(),1)
	assert_eq(kitchen.world.stations().filter(func(s:Dictionary)->bool:return s.get("kind")=="supply").size(),0)
	station("kitchen.fridge"); await get_tree().process_frame
	var material_buttons: int=0
	for button: Button in view._popup.find_children("*","Button",true,false):
		if button.text.contains("\n余 "): material_buttons+=1
	assert_eq(material_buttons,view.shop.snapshot().inventory.values().filter(func(n:int)->bool:return n>0).size())
	assert_true(view.pick_ingredient("beef").ok,"非当前订单的食材也可取")
	view._close_popup()
	var state: Dictionary=view.shop.snapshot()
	assert_eq(view.pick_ingredient("tomato").code,"HANDS_FULL")
	assert_eq(view.shop.snapshot(),state)
	assert_eq(view.shop.available("beef"),0)
	assert_eq(view.shop.active_orders()[0].status,"WAITING")

func test_can_take_last_material_before_any_customer_arrives() -> void:
	view.buy_kit("service.tomato_egg"); view.open_day(); kitchen=view.kitchen; kitchen.auto_advance=false
	assert_eq(view.shop.active_orders().size(),0)
	assert_true(view.pick_ingredient("tomato").ok)
	assert_eq(view.shop.available("tomato"),0)

	kitchen.advance(1)
	assert_eq(view.shop.active_orders().size(),1,"手里最后一份原料仍可供给来客")
	assert_eq(view.shop.active_orders()[0].status,"WAITING")

func test_three_visible_orders_list_materials_without_action_buttons() -> void:
	for i: int in 3: view.buy_kit("service.tomato_egg",false)
	view.open_day(); kitchen=view.kitchen; kitchen.auto_advance=false; kitchen.advance(100)
	assert_eq(view.shop.active_orders().size(),3)
	var material_cards: int=0
	for label: Label in view._sidebar.find_children("*","Label",true,false):
		if label.text=="材料：番茄 ＋ 鸡蛋": material_cards+=1
	assert_eq(material_cards,3)
	assert_eq(view._sidebar.find_children("*","Button",true,false).size(),0)
	assert_gt(float(view.shop.active_orders()[0].deadline_sec),float(view.shop.snapshot().elapsed_sec))

func test_no_order_beef_cut_choice_return_retrieve_and_cold_boundary_reload() -> void:
	view.buy_kit("service.beef_noodles")
	view.open_day(); kitchen=view.kitchen; kitchen.auto_advance=false
	assert_true(view.pick_ingredient("beef").ok)
	station("kitchen.board"); await get_tree().process_frame
	assert_false(kitchen.stage.visible)
	var choice: Button
	for button: Button in view._popup.find_children("*","Button",true,false):
		if button.text=="小丁": choice=button
	assert_not_null(choice); click(choice.get_global_rect().get_center())
	play(12); station("kitchen.board")
	var before: Dictionary=kitchen.handling.hand.snapshot().to_dict().ingredients.values()[0].duplicate(true)
	assert_eq(before.shape,"dice"); assert_eq(before.fine,.75)
	assert_true(view.return_ingredient().ok)
	assert_null(kitchen.handling.hand); assert_eq(view.shop.snapshot().cold_foods.size(),1)
	assert_eq(view.shop.available("beef"),0)
	assert_true(view.pick_stored(before.id).ok)
	assert_eq(kitchen.handling.hand.snapshot().to_dict().ingredients.values()[0].flavor,before.flavor)
	station("kitchen.stove.left")
	assert_eq(kitchen.lanes[0].snapshot().ingredients.size(),1)
	assert_true(view.take_pot_ingredient(0,before.id).ok)
	assert_eq(kitchen.handling.hand.snapshot().to_dict().ingredients.values()[0].shape,"dice")
	assert_true(kitchen.lanes[0].snapshot().ingredients.is_empty())
	assert_true(view.return_ingredient().ok)
	view.shop.close_early(); kitchen.advance(.01)
	assert_eq(view.shop.snapshot().phase,"SETTLED")
	assert_true(view.save_boundary().ok)
	app.return_to_menu(); await get_tree().process_frame; app.enter_shop(true); view=app.shop_view; kitchen=view.kitchen; kitchen.auto_advance=false
	assert_eq(view.shop.snapshot().cold_foods.size(),1)
	view.next_day(); view.open_day(); kitchen=view.kitchen; kitchen.auto_advance=false
	assert_true(view.pick_stored(before.id).ok)
	var after: Dictionary=kitchen.handling.hand.snapshot().to_dict().ingredients.values()[0]
	assert_eq(after.id,before.id); assert_eq(after.flavor,before.flavor); assert_eq(after.history,before.history)
	assert_eq(view.shop.available("beef"),0)

func test_any_nonempty_pot_runs_unknown_full_chain_and_trash_clears_it() -> void:
	view.buy_kit("service.tomato_egg"); view.buy_kit("service.beef_noodles")
	view.open_day(); kitchen=view.kitchen; kitchen.auto_advance=false
	view.pick_ingredient("beef"); station("kitchen.stove.left")
	station("kitchen.stove.left")
	assert_false(kitchen.stage.visible,"E仅取放，F才开锅")
	station("kitchen.stove.left",KEY_F)
	assert_true(kitchen.stage.visible); assert_eq(kitchen.lanes[0].base_recipe_id,"kitchen.unknown_stir")
	play(85)
	var dish: Dictionary=kitchen.lanes[0].snapshot()
	assert_eq(dish.state,"plated"); assert_true(dish.failed_dish); assert_eq(dish.recipe_name,"失败的菜品")
	for kind: String in ["preheat","stir","heat","season","starch","plate"]:
		assert_true(dish.steps.any(func(s:Dictionary)->bool:return s.operation==kind),kind)
	var season: Array=dish.custom_plan.operations.filter(func(s:Dictionary)->bool:return s.parameters.has("amounts"))
	assert_eq(season.size(),1)
	if not season.is_empty(): assert_eq(season[0].parameters.amounts,[.1,.15])
	station("kitchen.stove.left"); assert_eq(kitchen.handling.hand_kind,"dish")
	station("kitchen.trash")
	assert_null(kitchen.handling.hand); assert_true(kitchen.lanes[0].snapshot().ingredients.is_empty())
	assert_eq(view.shop.available("beef"),0)
	station("kitchen.trash"); view._close_popup(); assert_eq(view.shop.available("beef"),0)

func test_failed_dish_serves_first_customer_once_and_lowers_popularity() -> void:
	for i: int in 3: view.buy_kit("service.tomato_egg",false)
	view.buy_kit("service.beef_noodles")
	view.open_day(); kitchen=view.kitchen; kitchen.auto_advance=false; kitchen.advance(50)
	var first: String=view.shop.active_orders()[0].id
	view.pick_ingredient("beef"); station("kitchen.steamer"); station("kitchen.steamer",KEY_F)
	play(45)
	assert_true(kitchen.lanes[1].snapshot().failed_dish); assert_eq(kitchen.lanes[1].snapshot().state,"plated")
	station("kitchen.steamer"); var popularity: int=view.shop.snapshot().popularity
	station("kitchen.serve")
	assert_eq(view.shop.order(first).status,"SERVED")
	assert_eq(view.shop.order(first).score.satisfaction,0.0)
	assert_eq(view.shop.snapshot().popularity,popularity-4)
	assert_true(view.shop.order(first).plan.is_empty())
	var after: Dictionary=view.shop.snapshot(); station("kitchen.serve"); assert_eq(view.shop.snapshot(),after)

func test_actual_perfect_steam_requires_research_but_historical_unlock_survives_restart() -> void:
	# Historical stock / paid supply still allows cooking a locked recipe after D037.
	assert_true(view.shop.receive_supply(view.shop.offer("service.qiguoji").stock,"historical-steam").ok)
	view.open_day(); kitchen=view.kitchen; kitchen.auto_advance=false
	assert_false(view.shop.is_unlocked("service.qiguoji"))
	for food: String in ["chicken","mushroom"]: assert_true(view.pick_ingredient(food).ok); station("kitchen.steamer")
	station("kitchen.steamer",KEY_F); assert_true(kitchen.stage.visible)
	play(40)
	var dish: Dictionary=kitchen.lanes[1].snapshot()
	assert_eq(dish.state,"plated"); assert_false(dish.failed_dish); assert_true(dish.missing_required.is_empty())
	for step: Dictionary in dish.steps: assert_eq(step.grade,"Perfect",step.operation)
	assert_false(view.shop.is_unlocked("service.qiguoji")) # D030: Perfect no longer bypasses research.
	assert_true(app.research.inherit_legacy(["qiguoji"]).ok) # A legitimate historical unlock remains compatible.
	assert_eq(view.shop.observe_finished(dish).code,"RESEARCH_REQUIRED")
	view.shop.close_early(); kitchen.advance(.01)
	var plan:=view.shop.save_plan("第一份汽锅鸡做法",dish.custom_plan)
	assert_true(plan.ok,plan.code)
	assert_true(view.save_boundary().ok)
	app.return_to_menu(); await get_tree().process_frame; app.enter_shop(true); view=app.shop_view; kitchen=view.kitchen; kitchen.auto_advance=false
	assert_true(view.shop.is_unlocked("service.qiguoji")); view.next_day()
	assert_true(view.shop.set_menu("service.qiguoji",true,2200).ok)

func test_missed_steam_and_cooking_started_retrieval_are_rejected() -> void:
	# Historical stock / paid supply still allows cooking a locked recipe after D037.
	assert_true(view.shop.receive_supply(view.shop.offer("service.qiguoji").stock,"historical-steam").ok); view.open_day(); kitchen=view.kitchen; kitchen.auto_advance=false
	for food: String in ["chicken","mushroom"]: view.pick_ingredient(food); station("kitchen.steamer")
	station("kitchen.steamer",KEY_F); kitchen.advance(3)
	var id: String=kitchen.lanes[1].snapshot().ingredients.keys()[0]
	assert_eq(view.take_pot_ingredient(1,id).code,"COOKING_STARTED")
	play(40,false)
	assert_eq(kitchen.lanes[1].snapshot().state,"plated")
	assert_false(view.shop.is_unlocked("service.qiguoji"))
