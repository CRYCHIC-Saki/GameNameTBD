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

func enter_shop(resume_saved: bool = false) -> void:
	_dispose_kitchen()
	shop_view=TDShopView.new(); shop_view.save_path=shop_save_path; shop_view.resume_saved=resume_saved
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
	if kitchen == null and cooking_kitchen == null and full_kitchen == null and shop_view == null:
		return
	_paused = not _paused
	get_tree().paused = _paused
	if kitchen != null:
		kitchen.set_paused(_paused)
	if cooking_kitchen != null:
		cooking_kitchen.set_paused(_paused)
	if full_kitchen != null:
		full_kitchen.set_paused(_paused)
	if shop_view != null: shop_view.set_paused(_paused)

func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_CLOSE_REQUEST and is_inside_tree():
		if shop_view!=null: shop_view.request_leave(func()->void:get_tree().quit())
		else: get_tree().quit()
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_inside_tree() and (kitchen != null or cooking_kitchen != null or full_kitchen != null or shop_view != null) and not _paused:
		toggle_pause()

func _dispose_kitchen() -> void:
	_paused = false
	get_tree().paused = false
	if is_instance_valid(shop_view):
		shop_view.close(); remove_child(shop_view); shop_view.queue_free()
	shop_view=null
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
	if is_instance_valid(shop_view): shop_view.close()
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
	var column := TDUI.column(_menu, 22)
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
	column.add_child(TDUI.label("WASD 走动 · E 拿取 / 交互 · 跟随节拍做菜 · Esc 暂停", 17, TDUI.MUTED))
	_settings_message = TDUI.label("占位界面 · 原型建议数值 · 人工玩法验收待完成。", 16, TDUI.MUTED)
	column.add_child(_settings_message)
	if not config.ok:
		_settings_message.text = "配置错误：" + config.message
	var exit_button := TDUI.button("退出", func() -> void: get_tree().quit())
	exit_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	column.add_child(exit_button)
