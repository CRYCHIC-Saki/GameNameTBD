extends GutTest
const APP:=preload("res://src/app/main.tscn")
var app: TDApplication
var view: TDShopView
var kitchen: TDFullKitchen
var layer: CanvasLayer
var sent: Dictionary
var save_path: String

func before_each() -> void:
	DirAccess.make_dir_recursive_absolute("res://artifacts/test-storage")
	layer=CanvasLayer.new(); layer.layer=131; autofree(layer); get_tree().root.add_child(layer)
	app=APP.instantiate() as TDApplication; app.settings_path="res://artifacts/test-storage/phase2-settings.json"
	save_path="res://artifacts/test-storage/service-%d.json" % Time.get_ticks_usec(); app.shop_save_path=save_path
	layer.add_child(app); app.enter_shop(); view=app.shop_view; kitchen=view.kitchen; kitchen.auto_advance=false; sent={}
	await get_tree().process_frame

func after_each() -> void:
	get_tree().paused=false; app.return_to_menu(); await get_tree().process_frame; await get_tree().process_frame

func key(code: Key,pressed: bool=true) -> void:
	var e:=InputEventKey.new(); e.keycode=code; e.physical_keycode=code; e.pressed=pressed; get_tree().root.push_input(e,true)
func tap(code: Key) -> void: key(code); key(code,false)
func station(id: String) -> void:
	for entry: Dictionary in TDKitchenWorld.STATIONS:
		if entry.id==id: (kitchen.world.get_node("Player") as TDKitchenPlayer).position=entry.position+Vector2(0,40); tap(KEY_E); return
func click(at: Vector2) -> void:
	var motion:=InputEventMouseMotion.new(); motion.position=at; motion.global_position=at; get_tree().root.push_input(motion,true)
	for down: bool in [true,false]:
		var e:=InputEventMouseButton.new(); e.position=at; e.global_position=at; e.button_index=MOUSE_BUTTON_LEFT; e.pressed=down; get_tree().root.push_input(e,true)
func play(seconds: float, input_enabled: bool=true) -> void:
	for frame: int in int(seconds/.025):
		kitchen.advance(.025)
		if not input_enabled or not kitchen.stage.visible: continue
		for lane: TDCookingLane in kitchen.stage.lanes.duplicate():
			if lane.qte==null: continue
			var p: Dictionary=lane.progress.duplicate(true)
			var token: String=str(p.operation_id)
			var kind: String=p.qte_kind
			if kind in ["rhythm","sequence"]:
				for index: int in p.beat_times_sec.size():
					var marker: String=token+":"+str(index)
					if sent.has(marker) or float(p.elapsed_sec)+.000001<float(p.beat_times_sec[index]): continue
					sent[marker]=true
					var action: String=str(p.cut_actions[index]) if kind=="rhythm" and not p.get("cut_actions",[]).is_empty() else ("primary" if kind=="rhythm" else str(p.sequence[index]))
					if action.begins_with("spice:"):
						var r: Rect2=kitchen.stage.spice_rect(lane.lane_index,action.trim_prefix("spice:")); click(r.get_center())
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
	assert_true(view.begin_order(id,0).ok)
	return id

func cook_order(id: String) -> void:
	var recipe_id: String=view.shop.order(id).recipe_id
	for ingredient: String in view.shop.offer(recipe_id).primary:
		station("kitchen.supply.tomato"); assert_true(view.pick_ingredient(ingredient).ok); view._close_popup()
		if kitchen.catalog.for_recipe(recipe_id).recipe.preparation_sheets.has(ingredient):
			station("kitchen.board"); assert_true(kitchen.stage.visible); play(12); station("kitchen.board")
		station("kitchen.stove.left")
	station("kitchen.stove.left"); assert_true(kitchen.stage.visible); play(58)
	assert_eq(kitchen.lanes[0].snapshot().state,"plated")
	station("kitchen.stove.left"); station("kitchen.serve")
	assert_eq(view.shop.order(id).status,"SERVED")
	assert_true(view.shop.order(id).score.has("satisfaction"))
	assert_eq(kitchen.handling.hand_kind,"")

func test_real_tomato_egg_inventory_cooking_and_customer_delivery() -> void:
	var id: String=prepare_order("service.tomato_egg")
	cook_order(id)
	var before: Dictionary=view.shop.snapshot()
	station("kitchen.serve"); assert_eq(view.shop.snapshot(),before)

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
			assert_eq(view.shop.order(id).used.get("vinegar"),100)
			assert_eq(view.shop.order(id).used.get("sugar",0),0)
			assert_true(view.shop.order(id).customer.requirements.any(func(r:Dictionary)->bool:return r.get("ingredient_id")=="tomato"))
		view.shop.close_early()
		for remaining: Dictionary in view.shop.active_orders(): view.cancel_order(remaining.id)
		kitchen.advance(.01); assert_eq(view.shop.snapshot().phase,"SETTLED")
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
		assert_true(view.save_boundary().ok)
		var previous: Dictionary=view.shop.snapshot()
		app.return_to_menu(); await get_tree().process_frame; app.enter_shop(true); view=app.shop_view; kitchen=view.kitchen; kitchen.auto_advance=false
		assert_eq(JSON.parse_string(JSON.stringify(view.shop.snapshot())),JSON.parse_string(JSON.stringify(previous)))
		view.next_day(); assert_eq(view.shop.snapshot().day,day+1)

func test_pause_cancel_and_late_input_dont_consume_a_new_order() -> void:
	var id: String=prepare_order("service.tomato_egg")
	view.pick_ingredient("tomato"); station("kitchen.board"); kitchen.advance(1)
	var old: TDCookingQTE=kitchen.prep.qte
	var before: Dictionary=view.shop.snapshot(); app.toggle_pause(); kitchen.advance(300); tap(KEY_SPACE)
	assert_eq(view.shop.snapshot(),before); app.toggle_pause()
	view.cancel_order(id); assert_eq(view.shop.order(id).status,"CANCELLED")
	assert_null(kitchen.handling.board); assert_null(kitchen.prep.qte)
	if old!=null: assert_false(old.input(999,99,"primary",true).ok)
	assert_eq(view.shop.order(id).used.get("tomato"),1000)

func test_two_orders_keep_physical_ingredients_and_reservations_separate() -> void:
	view.buy_kit("service.tomato_egg"); view.buy_kit("service.tomato_egg",false)
	view.open_day(); kitchen=view.kitchen; kitchen.auto_advance=false; kitchen.advance(1)
	var first: String=view.shop.active_orders()[0].id; view.begin_order(first,0)
	view.pick_ingredient("tomato"); station("kitchen.board"); play(12)
	kitchen.advance(70)
	var second: String=view.shop.active_orders()[1].id; assert_true(view.begin_order(second,1).ok)
	station("kitchen.board"); station("kitchen.stove.right")
	assert_eq(view.last_result.code,"WRONG_ORDER")
	assert_false(kitchen.lanes[1].snapshot().ingredients.has("tomato"))
	station("kitchen.stove.left")
	assert_eq(kitchen.lanes[0].snapshot().ingredients.size(),1)
	view.cancel_order(second)
	assert_eq(view.shop.order(first).status,"COOKING")
	assert_eq(kitchen.lanes[0].snapshot().ingredients.size(),1)

func test_real_gui_purchase_and_open_buttons_start_business() -> void:
	await get_tree().process_frame
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
	view.pick_ingredient("tomato"); station("kitchen.board"); play(12)
	station("kitchen.board"); station("kitchen.stove.left")
	view.pick_ingredient("egg"); station("kitchen.stove.left")
	kitchen.advance(240.0-float(view.shop.snapshot().elapsed_sec))
	station("kitchen.stove.left"); assert_true(kitchen.stage.visible)
	kitchen.advance(60)
	assert_eq(view.shop.order(id).status,"TIMED_OUT")
	assert_eq(view.shop.order(id).used,{"tomato":1000,"egg":1000})
	assert_eq(view.lane_orders[0],"")
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
	assert_eq(view.shop.order(id).status,"COOKING")
	assert_eq(view.store.load_game().data.phase,"PREPARE")
