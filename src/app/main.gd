class_name TDApplication
extends Control

const KITCHEN_SCENE := preload("res://src/kitchen/development_kitchen.tscn")
const COOKING_SCENE := preload("res://src/kitchen/cooking_kitchen.tscn")
const FULL_SCENE := preload("res://src/kitchen/full_kitchen.tscn")

@export var initial_kitchen: bool = false
@export var initial_cooking: bool = false
@export var initial_full: bool = false
var full_kitchen: TDFullKitchen
var shop_view: TDShopView
var restaurant: TDRestaurantWorld
var town: TDTownWorld
var phase3: TDPhase3Session
var research: TDResearchSession
var research_store: TDResearchStore
var atlas: TDRecipeAtlas
var _atlas_layer: CanvasLayer
var _research_underlay: Array = []
var _research_was_paused: bool = false
var research_save_path: String = ""
var floor_kitchen: TDFloorKitchen
var _observing_floor: bool = false
var shop_save_path: String = "user://shop-v1.json"
var full_catalog := TDCookingCatalog.new()
var settings_path: String = "user://settings.json"
var kitchen: TDDevelopmentKitchen
var cooking_kitchen: TDCookingKitchen
var recipe_catalog := TDRecipeCatalog.new()
var generation: int = 0
var catalog := TDCatalog.new()
var scorer := TDCustomerScorer.new()
var _store: TDSettingsStore
var _menu: Control
var _settings_message: Label
var _show_debug: bool = false
var _paused: bool = false

func _ready() -> void:
	get_tree().auto_accept_quit=false
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_unhandled_input(true)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = TDUI.theme()
	_store = TDSettingsStore.new(settings_path)
	var loaded := _store.load_settings()
	if loaded.ok:
		_show_debug = loaded.data["show_debug"]
	var config := catalog.load_file("res://content/dev_samples.json")
	var recipe_loaded := recipe_catalog.load_file("res://content/cooking_prototype.json")
	var full_loaded := full_catalog.load_file("res://content/cooking_system.json")
	_build_menu(config)
	if not recipe_loaded.ok:
		_settings_message.text = "原型配置错误：" + recipe_loaded.message
	if not loaded.ok and loaded.code != "NOT_FOUND":
		_settings_message.text = "设置读取失败：" + loaded.code + "。保留原文件，使用本次默认值。"
	if initial_full and full_loaded.ok:
		enter_full_kitchen()
	elif initial_kitchen and config.ok:
		enter_kitchen()
	elif initial_cooking and recipe_loaded.ok:
		enter_cooking()

func enter_kitchen() -> void:
	if catalog.ids().is_empty():
		return
	_dispose_kitchen()
	generation += 1
	kitchen = KITCHEN_SCENE.instantiate() as TDDevelopmentKitchen
	kitchen.catalog = catalog
	kitchen.clock = TDClock.new()
	kitchen.random_source = TDBusinessRandom.new(101 + generation)
	kitchen.scorer = scorer
	kitchen.session_id = "session-%d" % generation
	kitchen.generation = generation
	kitchen.show_debug = _show_debug
	kitchen.back_requested.connect(return_to_menu)
	kitchen.pause_requested.connect(toggle_pause)
	kitchen.restart_requested.connect(enter_kitchen)
	_menu.hide()
	add_child(kitchen)

func return_to_menu() -> void:
	_dispose_kitchen()
	_menu.show()

func enter_restaurant(path: String = "") -> void:
	_dispose_kitchen()
	restaurant = TDRestaurantWorld.new()
	restaurant.save_path = path
	var phase3_session := _phase3()
	phase3_session.scaled_interior = true
	restaurant.session = phase3_session
	restaurant.back_requested.connect(return_to_menu)
	restaurant.pause_requested.connect(toggle_pause)
	restaurant.kitchen_requested.connect(_enter_floor_kitchen)
	_menu.hide()
	add_child(restaurant)

func enter_town() -> void:
	_dispose_kitchen()
	town = TDTownWorld.new()
	town.session = _phase3()
	town.back_requested.connect(return_to_menu)
	town.pause_requested.connect(toggle_pause)
	town.restaurant_requested.connect(func() -> void: enter_restaurant(""))
	_menu.hide()
	add_child(town)

func _phase3() -> TDPhase3Session:
	if phase3 == null:
		phase3 = TDPhase3Session.new()
		phase3.load_default()
		if _ensure_research():
			phase3.attach_research(research)
			_apply_study_time()
	return phase3

func _ensure_research() -> bool:
	if research!=null: return true
	var definitions:=TDResearchCatalog.new()
	var checked:=definitions.load_file()
	if not checked.ok:
		_settings_message.text="菜谱资料无法读取："+checked.code
		return false
	research=TDResearchSession.new(definitions)
	var path:String=research_save_path
	if path.is_empty():
		path=shop_save_path+".research" if shop_save_path!="user://shop-v1.json" else (settings_path+".research" if settings_path!="user://settings.json" else "user://research-v1.json")
	research_store=TDResearchStore.new(path,research.validate_save)
	var saved:=research_store.load_game()
	if saved.ok: research.restore(saved.data)
	elif saved.code!="NOT_FOUND": research.load_error=saved.code
	research.save_sink=research_store.save_game
	research.attempt_completed.connect(func(_result:Dictionary)->void:_apply_study_time())
	return true

func enter_research() -> void:
	if atlas!=null: return
	if not _ensure_research(): return
	_phase3()
	_research_was_paused=_paused
	_set_underlay_paused(true)
	for node:Node in [_menu,kitchen,cooking_kitchen,full_kitchen,shop_view,restaurant,town,floor_kitchen]:
		if is_instance_valid(node): _suspend_research_underlay(node)
	_paused=false;get_tree().paused=false
	_atlas_layer=CanvasLayer.new();_atlas_layer.layer=500;add_child(_atlas_layer)
	atlas=TDRecipeAtlas.new();atlas.session=research
	atlas.begin_handler=_begin_study;atlas.recovery_handler=_recover_research
	atlas.back_requested.connect(close_research);atlas.pause_requested.connect(toggle_pause)
	_atlas_layer.add_child(atlas)

func _suspend_research_underlay(node:Node) -> void:
	_research_underlay.append({"node":node,"mode":node.process_mode})
	node.process_mode=Node.PROCESS_MODE_DISABLED
	for child:Node in node.get_children(): _suspend_research_underlay(child)

func _set_underlay_paused(value:bool) -> void:
	for node:Node in [kitchen,cooking_kitchen,full_kitchen,shop_view,floor_kitchen]:
		if is_instance_valid(node): node.set_paused(value)

func close_research() -> void:
	if atlas==null: return
	atlas.close();_atlas_layer.remove_child(atlas);atlas.queue_free();atlas=null
	remove_child(_atlas_layer);_atlas_layer.queue_free();_atlas_layer=null
	for entry:Dictionary in _research_underlay:
		if is_instance_valid(entry.node): entry.node.process_mode=entry.mode
	_research_underlay.clear()
	_paused=_research_was_paused;get_tree().paused=_paused;_set_underlay_paused(_paused)
	if shop_view!=null and shop_view.shop.snapshot().phase in ["PREPARE","SETTLED"]:
		shop_view.sync_research_recipes(_phase3().research_service_ids())

func _input(event:InputEvent) -> void:
	if event.is_action_pressed("recipe_book") and not event.is_echo():
		var focus:=get_viewport().gui_get_focus_owner()
		if focus is LineEdit or focus is TextEdit: return
		if atlas==null: enter_research()
		else: close_research()
		get_viewport().set_input_as_handled()
	elif atlas!=null and atlas.trial==null and event.is_action_pressed("pause") and not event.is_echo():
		toggle_pause();get_viewport().set_input_as_handled()

func _begin_study(id:String) -> TDOutcome:
	if shop_view!=null and shop_view.shop.snapshot().phase in ["OPEN","DRAINING"]: return TDOutcome.new(false,"SHOP_OPEN","营业中只能查看菜谱，请打烊后研习。")
	var world:=_phase3()
	return research.begin(id,{"day":world.day,"phase":world.day_phase,"spent":world.free_spent},world.free_hours()-world.free_spent)

func _apply_study_time() -> void:
	if phase3==null or research==null: return
	var time:Dictionary=research.snapshot().world_time
	if int(time.day)<phase3.day: return
	phase3.day=int(time.day);phase3.day_phase=time.phase;phase3.free_spent=float(time.spent)

func _recover_research(temporary:bool) -> TDOutcome:
	var result:=research_store.recover(temporary)
	if result.ok:
		result=research.restore(result.data)
		if result.ok: _apply_study_time()
	return result

func _inherit_shop_recipes(ids:Array) -> void:
	var world:=_phase3();var names:Array=[]
	for id:String in ids:
		var runtime:=world.catalog.dish_id_for_kitchen(id)
		if not runtime.is_empty(): names.append(runtime)
	var result:=research.inherit_legacy(names)
	if not result.ok: _settings_message.text="旧菜谱继承未保存："+result.code

func _reward_shop_cooking(day:int,recipe_id:String,score:float) -> void:
	var world:=_phase3();var id:=world.catalog.dish_id_for_kitchen(recipe_id)
	if not id.is_empty(): research.record_cooking(day,id,score)

func enter_shop(resume_saved: bool = false) -> void:
	_dispose_kitchen()
	shop_view=TDShopView.new(); shop_view.save_path=shop_save_path; shop_view.resume_saved=resume_saved; shop_view.day_san=float(_phase3().san)
	shop_view.learned_dishes=_phase3().learned_kitchen_dishes()
	shop_view.recipe_unlocks=_phase3().research_service_ids()
	shop_view.cooking_reward=_reward_shop_cooking;shop_view.legacy_loaded=_inherit_shop_recipes
	shop_view.back_requested.connect(return_to_menu); shop_view.pause_requested.connect(toggle_pause)
	_menu.hide(); add_child(shop_view)

func enter_full_kitchen() -> void:
	_dispose_kitchen()
	if full_catalog.data().is_empty(): return
	full_kitchen = FULL_SCENE.instantiate() as TDFullKitchen
	full_kitchen.catalog = full_catalog
	full_kitchen.scorer = scorer
	full_kitchen.back_requested.connect(return_to_menu)
	full_kitchen.pause_requested.connect(toggle_pause)
	_menu.hide()
	add_child(full_kitchen)

func enter_cooking() -> void:
	var chosen_customer: int = 0
	var offset_sec: float = 0.0
	if is_instance_valid(cooking_kitchen):
		chosen_customer = cooking_kitchen.customer_index
		offset_sec = cooking_kitchen.input_offset_sec
	_dispose_kitchen()
	var recipe_data := recipe_catalog.data()
	if recipe_data.is_empty():
		return
	generation += 1
	cooking_kitchen = COOKING_SCENE.instantiate() as TDCookingKitchen
	cooking_kitchen.config = recipe_data
	cooking_kitchen.clock = TDClock.new()
	cooking_kitchen.scorer = scorer
	cooking_kitchen.session_id = "cook-%d" % generation
	cooking_kitchen.generation = generation
	cooking_kitchen.customer_index = chosen_customer
	cooking_kitchen.input_offset_sec = offset_sec
	cooking_kitchen.back_requested.connect(return_to_menu)
	cooking_kitchen.pause_requested.connect(toggle_pause)
	cooking_kitchen.restart_requested.connect(enter_cooking)
	_menu.hide()
	add_child(cooking_kitchen)

func toggle_pause() -> void:
	if kitchen == null and cooking_kitchen == null and full_kitchen == null and shop_view == null and restaurant == null and town == null and atlas == null:
		return
	_paused = not _paused
	get_tree().paused = _paused
	if atlas!=null:
		atlas.set_paused(_paused)
		return
	if kitchen != null:
		kitchen.set_paused(_paused)
	if cooking_kitchen != null:
		cooking_kitchen.set_paused(_paused)
	if full_kitchen != null:
		full_kitchen.set_paused(_paused)
	if shop_view != null: shop_view.set_paused(_paused)
	if floor_kitchen != null: floor_kitchen.set_paused(_paused)

func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_CLOSE_REQUEST and is_inside_tree():
		close_research() # Reveal the existing unsaved-business confirmation above its own scene.
		if shop_view!=null: shop_view.request_leave(func()->void:get_tree().quit())
		else: get_tree().quit()
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_inside_tree() and (kitchen != null or cooking_kitchen != null or full_kitchen != null or shop_view != null or restaurant != null or town != null or atlas != null) and not _paused:
		toggle_pause()

func _unhandled_input(event: InputEvent) -> void:
	if atlas!=null: return
	if not event.is_action_pressed("floor_look") or event.is_echo():
		return
	if not _floor_link_active():
		return
	_toggle_floor_look()
	get_viewport().set_input_as_handled()

func _enter_floor_kitchen() -> void:
	if restaurant == null:
		return
	_observing_floor = false
	restaurant.set_observe(false)
	_ensure_floor_kitchen()
	restaurant.set_floor_cover(true)
	floor_kitchen.open_for(restaurant)

func _return_to_restaurant() -> void:
	_observing_floor = false
	if restaurant != null:
		restaurant.set_observe(false)
	if floor_kitchen != null:
		floor_kitchen.set_active(false)
	if restaurant != null:
		restaurant.set_floor_cover(false)
		if restaurant.layout != null:
			restaurant.teleport_player(restaurant.layout.entrance())

func _toggle_floor_look() -> void:
	if not _floor_link_active():
		return
	_observing_floor = not _observing_floor
	if _observing_floor:
		floor_kitchen.set_active(false)
		restaurant.set_floor_cover(false)
		restaurant.set_observe(true)
		return
	restaurant.set_observe(false)
	restaurant.set_floor_cover(true)
	floor_kitchen.set_active(true)

func _floor_link_active() -> bool:
	return restaurant != null and floor_kitchen != null and (floor_kitchen.visible or _observing_floor)

func _ensure_floor_kitchen() -> void:
	if floor_kitchen != null:
		return
	floor_kitchen = TDFloorKitchen.new()
	floor_kitchen.session = _phase3()
	floor_kitchen.restaurant_requested.connect(_return_to_restaurant)
	floor_kitchen.look_requested.connect(_toggle_floor_look)
	floor_kitchen.pause_requested.connect(toggle_pause)
	add_child(floor_kitchen)

func _dispose_kitchen() -> void:
	close_research()
	_paused = false
	_observing_floor = false
	get_tree().paused = false
	if is_instance_valid(floor_kitchen):
		floor_kitchen.close()
		remove_child(floor_kitchen)
		floor_kitchen.queue_free()
	floor_kitchen = null
	if is_instance_valid(shop_view):
		shop_view.close(); remove_child(shop_view); shop_view.queue_free()
	shop_view=null
	if is_instance_valid(restaurant):
		restaurant.close()
		remove_child(restaurant)
		restaurant.queue_free()
	restaurant = null
	if is_instance_valid(town):
		town.close()
		remove_child(town)
		town.queue_free()
	town = null
	if is_instance_valid(full_kitchen):
		full_kitchen.close()
		remove_child(full_kitchen)
		full_kitchen.queue_free()
	full_kitchen = null
	if is_instance_valid(kitchen):
		kitchen.close()
		remove_child(kitchen)
		kitchen.queue_free()
	kitchen = null
	if is_instance_valid(cooking_kitchen):
		cooking_kitchen.close()
		remove_child(cooking_kitchen)
		cooking_kitchen.queue_free()
	cooking_kitchen = null

func _exit_tree() -> void:
	if is_instance_valid(atlas): atlas.close()
	if is_instance_valid(shop_view): shop_view.close()
	if is_instance_valid(restaurant): restaurant.close()
	if is_instance_valid(town): town.close()
	if is_instance_valid(full_kitchen):
		full_kitchen.close()
	if is_instance_valid(kitchen):
		kitchen.close()
	if is_instance_valid(cooking_kitchen):
		cooking_kitchen.close()
	if is_inside_tree():
		get_tree().paused = false

func _save_debug(value: bool) -> void:
	_show_debug = value
	var result := _store.save_settings({"show_debug": value})
	_settings_message.text = "设置已保存。" if result.ok else "设置保存失败：" + result.code + "；原文件未被静默覆盖。"

func _build_menu(config: TDOutcome) -> void:
	_menu = MarginContainer.new()
	_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		_menu.add_theme_constant_override("margin_" + side, 64)
	add_child(_menu)
	var column := TDUI.column(_menu, 14)
	column.add_child(TDUI.label("TOWN DINER   /   SINGLE STORE", 17, TDUI.ORANGE))
	column.add_child(TDUI.label("小镇食堂", 62))
	column.add_child(TDUI.label("从一间小店，开始我们的故事。", 26))
	column.add_child(TDUI.label("备好食材，写下今日菜单，迎接第一位客人。\n按菜谱打谱做菜，用每天的反馈经营这间小店。", 20, TDUI.MUTED))
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 20
	column.add_child(spacer)
	var start := TDUI.button("新开一间店   →", func()->void:enter_shop(false))
	start.custom_minimum_size = Vector2(360, 60)
	start.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	start.disabled = full_catalog.data().is_empty()
	column.add_child(start)
	column.add_child(TDUI.button("继续经营",func()->void:enter_shop(true)))
	column.add_child(TDUI.button("菜谱研习",enter_research))
	column.add_child(TDUI.button("布置餐厅", func() -> void: enter_restaurant("")))
	column.add_child(TDUI.button("走进小镇", func() -> void: enter_town()))
	column.add_child(TDUI.label("WASD 走动 · E 拿取 / 交互 · B 菜谱研习 · Esc 暂停", 17, TDUI.MUTED))
	_settings_message = TDUI.label("占位界面 · 原型建议数值 · 人工玩法验收待完成。", 16, TDUI.MUTED)
	column.add_child(_settings_message)
	if not config.ok:
		_settings_message.text = "配置错误：" + config.message
	var exit_button := TDUI.button("退出", func() -> void: get_tree().quit())
	exit_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	column.add_child(exit_button)
