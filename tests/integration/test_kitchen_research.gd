extends GutTest
const APP=preload("res://src/app/main.tscn")
var app:TDApplication
var layer:CanvasLayer
var path:String

func before_each() -> void:
	DirAccess.make_dir_recursive_absolute("res://artifacts/test-storage")
	path="res://artifacts/test-storage/research-scene-%d.json"%Time.get_ticks_usec()
	layer=CanvasLayer.new();layer.layer=135;add_child_autofree(layer)
	app=APP.instantiate();app.research_save_path=path;app.settings_path=path+".settings";app.shop_save_path=path+".shop";layer.add_child(app)
	await get_tree().process_frame

func after_each() -> void:
	get_tree().paused=false;app.return_to_menu();await get_tree().process_frame

func key(code:Key,down:bool) -> void:
	var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=down;get_tree().root.push_input(event,true)

func play_chart() -> void:
	app.atlas.trial.automated_clock=true
	assert_true(load("res://tools/test_support/research_input.gd").play(app.research,app.atlas.trial.token,get_tree().root))
	await get_tree().process_frame;await get_tree().process_frame

func test_real_entry_tree_input_unlock_persist_and_kitchen_menu() -> void:
	app.enter_research();await get_tree().process_frame
	assert_eq(app.atlas.canvas.positions.size(),20);assert_eq(app.research.snapshot().unlocked,["C01","C02"])
	app.atlas.select_recipe("C03");app.atlas.start_selected();await get_tree().process_frame
	assert_not_null(app.atlas.trial);await play_chart()
	assert_true(app.research.has("C03"));assert_gte(float(app.research.snapshot().best.C03),80.0)
	assert_eq(app.phase3.free_spent,0.0);assert_eq(app.research.snapshot().study_hours,0)
	app.atlas.trial._continue.pressed.emit();await get_tree().process_frame
	assert_null(app.atlas.trial);app.enter_shop();await get_tree().process_frame
	assert_true(app.shop_view.shop.is_unlocked("study.yangchun_noodles"));assert_true(app.shop_view.shop.is_unlocked("study.egg_fried_rice"))
	assert_false(app.shop_view.shop.is_unlocked("service.gongbaojiding"))
	assert_true(app.shop_view.service.cooking.for_recipe("study.yangchun_noodles").recipe.required_steps.has("boil"))
	assert_true(app.shop_view.service.cooking.for_recipe("study.steamed_egg").recipe.required_steps.has("steam"))
	var stored:=app.research_store.load_game();assert_true(stored.ok);assert_eq(stored.data.unlocked,["C01","C02","C03"])
	app.return_to_menu();app.queue_free();await get_tree().process_frame
	app=APP.instantiate();app.research_save_path=path;app.settings_path=path+".settings";app.shop_save_path=path+".shop";layer.add_child(app);app.enter_research()
	assert_true(app.research.has("C03"));assert_eq(app.phase3.free_spent,0.0)

func test_cancel_pause_two_distinct_charts_no_old_results_or_signals() -> void:
	app.enter_research();app.atlas.select_recipe("C04");app.atlas.start_selected();await get_tree().process_frame
	app.atlas.trial.automated_clock=true;var token:String=app.atlas.trial.token
	app.toggle_pause();app.research.advance(30);assert_lt(app.research.clock.qte_sec,.2)
	app.toggle_pause();app.atlas.trial._cancel_button.pressed.emit();await get_tree().process_frame
	assert_null(app.atlas.trial);assert_eq(app.research.snapshot().points,2)
	app.atlas.start_selected();await get_tree().process_frame;assert_ne(app.atlas.trial.token,token)
	assert_eq(app.research.finish(token).code,"STALE_ATTEMPT");await play_chart();assert_true(app.research.has("C04"))
	assert_eq(app.research.snapshot().points,2);assert_eq(app.research.snapshot().study_hours,0)
	app.return_to_menu();await get_tree().process_frame;app.enter_research()
	assert_eq(app.research.get_signal_connection_list("changed").size(),2)

func test_story_interface_does_not_gift_recipe_or_charge_for_pending_chart() -> void:
	app.enter_research();app.atlas.switch_cuisine("eu");await get_tree().process_frame
	assert_eq(app.atlas.active_cuisine,"cn");assert_true(app.atlas._tabs.eu.disabled);assert_not_null(app.atlas._tabs.eu.icon)
	app.atlas.select_recipe("E20");assert_eq(app.atlas.selected_id,"C02");assert_false(app.atlas.canvas.positions.has("E20"))
	assert_true(app.research.recommend_cuisine("story.test.europe","eu").ok)
	app.atlas.switch_cuisine("eu");assert_eq(app.atlas.active_cuisine,"eu");assert_false(app.atlas._tabs.eu.disabled)
	assert_eq(app.research.status("E01"),"CHART_PENDING");assert_false(app.research.has("E01"));assert_eq(app.research.snapshot().points,3)
	app.atlas.set_zoom(1.3);app.atlas.select_recipe("E20");app.atlas.reveal_selection();assert_gt(app.atlas._tree_scroll.scroll_vertical,0)

func test_runtime_data_valid_legacy_save_preserved_and_no_perfect_bypass() -> void:
	var service:=TDServiceCatalog.new();assert_true(service.load_file().ok)
	var legacy:=TDShopSession.new(service,"historical");var old:=legacy.snapshot()
	app.enter_shop();var view:=app.shop_view
	assert_true(view.shop.validate_save(old).ok);assert_true(view.shop.restore(old).ok)
	assert_eq(view.shop.snapshot().money_cents,old.money_cents);assert_eq(view.shop.available("rice"),0)
	app._inherit_shop_recipes(old.unlocked);assert_true(app.research.has("C14"));assert_false(app.research.has("C13"))
	view.shop.open_day();var fake:Dictionary={"recipe_id":"service.qiguoji","session_id":view.shop.day_namespace()+"probe","state":"plated"}
	assert_eq(view.shop.observe_finished(fake).code,"RESEARCH_REQUIRED")

func test_bad_progress_is_visible_and_cannot_be_silently_replaced() -> void:
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string("broken");file.close()
	app.enter_research();app.atlas.select_recipe("C03");app.atlas.start_selected()
	assert_null(app.atlas.trial);assert_eq(app.research.load_error,"INVALID_JSON");assert_eq(FileAccess.get_file_as_string(path),"broken")
	assert_true(app.atlas._notice.text.contains("读取失败"))

func test_tree_selection_highlights_exact_prerequisites_without_granting_mastery() -> void:
	app.enter_research()
	assert_eq(app.research.catalog.node("C09").prerequisites,["C06"])
	assert_eq(app.research.catalog.node("C10").prerequisites,["C07"])
	for id:String in ["C09","C10"]:
		app.atlas.select_recipe(id)
		assert_false(app.atlas.canvas.edge_active("C06",id))
		assert_false(app.atlas.canvas.edge_active("C07",id))
	assert_true(app.atlas.canvas.edge_selected("C07","C10"))
	assert_false(app.atlas.canvas.edge_selected("C06","C09"))
	assert_false(app.atlas.canvas.edge_selected("C06","C10"))
	app.atlas.select_recipe("C11")
	assert_true(app.atlas.canvas.edge_selected("C06","C11"))
	assert_true(app.atlas.canvas.edge_selected("C08","C11"))
	assert_false(app.atlas.canvas.edge_selected("C07","C10"))
	assert_false(app.research.has("C11"))
	app.research.inherit_legacy(["gongbaojiding"])
	assert_false(app.atlas.canvas.edge_active("C06","C09"),"historical child does not invent an unlocked parent")

func test_all_cuisine_edges_avoid_cards_and_labels_and_scale_with_input() -> void:
	app.enter_research();var canvas:=app.atlas.canvas
	var source:=app.research.catalog.data.duplicate(true)
	for cuisine:String in ["cn","eu","jp","sea","lat"]:
		if cuisine!="cn": app.research.recommend_cuisine("test.layout."+cuisine,cuisine)
		app.atlas.switch_cuisine(cuisine)
		var collisions:Array[String]=[]
		for child:String in canvas.positions:
			for parent:String in app.research.catalog.node(child).prerequisites:
				var path:=canvas.edge_path(parent,child)
				assert_gte(path.size(),2)
				for segment:int in range(1,path.size()):
					var count:int=maxi(1,ceili(path[segment-1].distance_to(path[segment])/3.0))
					for sample:int in count+1:
						var point:Vector2=path[segment-1].lerp(path[segment],float(sample)/count)
						for card:String in canvas.positions:
							if canvas.card_bounds(card).has_point(point): collisions.append(parent+":"+child+" through "+card)
		assert_eq(collisions,[],cuisine+" routes must stay out of all node/label rectangles")
	assert_eq(app.research.catalog.data,source)
	app.atlas.switch_cuisine("cn");app.atlas.set_zoom(.8)
	var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true
	event.position=canvas.positions.C09*canvas.zoom;canvas._gui_input(event)
	assert_eq(app.atlas.selected_id,"C09");assert_true(canvas.edge_selected("C06","C09"))

func test_failed_result_retries_immediately_with_exhausted_time_and_no_old_callback() -> void:
	app.enter_research();app.phase3.free_spent=app.phase3.free_hours()
	var spent:float=app.phase3.free_spent;var day:int=app.phase3.day
	app.atlas.select_recipe("C04");app.atlas.start_selected();assert_not_null(app.atlas.trial)
	for repeat:int in 2:
		var previous:=app.atlas.trial;previous.automated_clock=true
		app.research.advance(200);await get_tree().process_frame
		assert_eq(previous._result.code,"LOW_SCORE");assert_true(previous._retry_attempt.visible)
		assert_eq(app.phase3.free_spent,spent);assert_eq(app.phase3.day,day)
		previous._retry_attempt.pressed.emit()
		assert_not_same(app.atlas.trial,previous);assert_ne(app.atlas.trial.token,previous.token)
		var fresh:String=app.atlas.trial.token;previous._retry();previous._return_result()
		assert_eq(app.atlas.trial.token,fresh);assert_eq(app.research.input(previous.token,"primary",true).code,"STALE_ATTEMPT")
		await get_tree().process_frame
	await play_chart();assert_true(app.research.has("C04"))
	assert_eq(app.phase3.free_spent,spent);assert_eq(app.phase3.day,day)
	assert_eq(app.research.snapshot().points,2);assert_eq(app.research.snapshot().completed_attempts,3)
	assert_false(app.atlas.trial._retry_attempt.visible)
	var stored:=app.research_store.load_game();assert_true(stored.ok)
	assert_eq(float(stored.data.world_time.spent),spent);assert_eq(int(stored.data.completed_attempts),3)

func test_B_overlay_preserves_operating_kitchen_and_queue_without_input_leak() -> void:
	app.enter_shop();var view:=app.shop_view;var kitchen:=view.kitchen;kitchen.auto_advance=false
	view.buy_kit("service.tomato_egg");view.open_day();kitchen=view.kitchen;kitchen.auto_advance=false;kitchen.advance(1)
	var lane:=kitchen.lanes[0];lane.perform("add",{"ingredient_id":"tomato","amount":1})
	lane.perform("add",{"ingredient_id":"egg","amount":1});lane.start_sheet("service.tomato_egg");kitchen.open_station_view("kitchen.stove.left");kitchen.advance(3)
	var dish:=lane.snapshot();var before:=view.shop.snapshot();var elapsed:float=kitchen.shared_clock.qte_sec
	for repeat:int in 3:
		key(KEY_B,true);key(KEY_B,false);assert_not_null(app.atlas)
		assert_eq(app._begin_study("C03").code,"SHOP_OPEN")
		key(KEY_SPACE,true);key(KEY_SPACE,false);key(KEY_E,true);key(KEY_E,false)
		await get_tree().process_frame
		assert_eq(lane.snapshot(),dish);assert_eq(view.shop.snapshot(),before)
		key(KEY_B,true);key(KEY_B,false);await get_tree().process_frame
		assert_null(app.atlas);assert_same(app.shop_view,view);assert_same(view.kitchen,kitchen)
		assert_eq(kitchen.shared_clock.qte_sec,elapsed);assert_eq(lane.snapshot(),dish)
	assert_eq(app.research.snapshot().points,3)
	app.toggle_pause();key(KEY_B,true);key(KEY_B,false);key(KEY_B,true);key(KEY_B,false)
	assert_true(get_tree().paused);assert_true(kitchen.shared_clock.paused)

func test_in_game_unlock_refreshes_same_preparation_menu_and_new_cuisine_gate() -> void:
	app.enter_shop();var view:=app.shop_view;var money:int=view.shop.snapshot().money_cents
	key(KEY_B,true);key(KEY_B,false);assert_not_null(app.atlas)
	app.atlas.select_recipe("C04");app.atlas.start_selected();await play_chart()
	assert_true(app.research.has("C04"));key(KEY_B,true);key(KEY_B,false);await get_tree().process_frame
	assert_same(app.shop_view,view);assert_true(view.shop.is_unlocked("study.steamed_egg"));assert_eq(view.shop.snapshot().money_cents,money)

func test_book_from_town_is_a_screen_overlay_and_typing_B_is_not_a_shortcut() -> void:
	app.enter_town();var world:=app.town;key(KEY_B,true);key(KEY_B,false)
	assert_not_null(app.atlas);assert_eq(app.atlas.get_parent(),app._atlas_layer)
	var search:LineEdit=app.atlas._shell.find_children("*","LineEdit",true,false)[0];search.grab_focus()
	key(KEY_B,true);key(KEY_B,false);assert_not_null(app.atlas)
	search.release_focus();key(KEY_B,true);key(KEY_B,false);assert_same(app.town,world);assert_null(app.atlas)

func test_focus_pause_blocks_start_until_resume_without_spending() -> void:
	app.enter_research();app.atlas.select_recipe("C03")
	app.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	var before:=app.research.snapshot();app.atlas.start_selected()
	assert_null(app.atlas.trial);assert_eq(app.research.snapshot(),before)
	assert_true(app.atlas._notice.text.contains("暂停"))
	key(KEY_ESCAPE,true);key(KEY_ESCAPE,false);app.atlas.start_selected()
	assert_not_null(app.atlas.trial);assert_false(app.research.clock.paused)

func test_window_close_reveals_existing_unsaved_shop_confirmation() -> void:
	app.enter_shop();var view:=app.shop_view;app.enter_research()
	app.notification(NOTIFICATION_WM_CLOSE_REQUEST)
	assert_null(app.atlas);assert_same(app.shop_view,view)
	var dialogs:=view.find_children("*","ConfirmationDialog",true,false)
	assert_eq(dialogs.size(),1)
	assert_true(dialogs[0].visible);assert_true(dialogs[0].can_process())
	dialogs[0].hide();dialogs[0].canceled.emit()
