class_name TDCookingLane
extends VBoxContainer
## One playable lane owns one session, one clock and separately seeded QTE/business RNGs.
signal dish_delivered(dish: Dictionary)
var catalog: TDCookingCatalog
var _content: Dictionary = {}
var library: TDRecipeLibrary
var scorer: TDCustomerScorer
var lane_index: int = 0
var session: TDCookingSession
var clock := TDClock.new()
var qte: TDCookingQTE
var progress: Dictionary = {}
var last_result: TDOutcome
var input_offset_sec: float = 0.0
var day_san: float = -1.0
var story_coach: bool = false
var dual: bool = false
var generation: int = 0
var base_recipe_id: String = "tomato_egg"
var session_namespace: String = ""
var customer_override: Array = []
var custom_entry: Dictionary = {}
var _operation_counter: int = 0
var _sequence: int = 0
var _qte_random: TDBusinessRandom
var _operation: String = ""
var _local_instances: Dictionary = {}
var _pending_plan_local_id: String = ""
var _test_enabled: bool = false
var _recipes: OptionButton
var _ingredients: OptionButton
var _targets: OptionButton
var _shapes: OptionButton
var _operations: OptionButton
var _batch: OptionButton
var _amount: SpinBox
var _san: SpinBox
var _title: Label
var _summary: Label
var _hint: Label
var _status: Label
var _feedback: RichTextLabel
var _details: RichTextLabel
var _view: Control
var _plate: TDPlatingView
var _heat: HSlider
var _primary: Button
var _direction_row: HBoxContainer
var _audio := TDBeatAudio.new()
var _plan_steps: OptionButton
var _saved: OptionButton
var _recipe_name: LineEdit
var _closed: bool = false
var pc_controls: bool = false
var station_role: String = "stove"
var shared_clock: TDClock
var beat_offset_sec: float = 0.0
var assist_windows: bool = false
var assist_temperature: bool = false
var thermal_qte: TDCookingQTE
var thermal_progress: Dictionary = {}
var sheet: TDBeatSheet
var temperature_view: TDTemperatureView
var _pc_toolbar: HFlowContainer
var _cabinet: HBoxContainer
var _cut_beats: SpinBox
var _pc_buttons: Dictionary = {}
var _pending_plan_local_ids: Array = []
var restart_allowed: Callable
var _pc_amount: SpinBox
var document_rules: bool = false
var stage_label: String = ""
var _scheduled_settings: Dictionary = {}
var active_sheet_id: String = ""
var _customer_feedback: Array=[]
var judgement_feedback: Dictionary = {}
var _feedback_token: String = ""
var automatic: bool = false
var _automatic_preparation: Array = []
var _automatic_target: String = ""

func start_automatic() -> TDOutcome:
	if qte!=null or thermal_qte!=null or (sheet!=null and sheet.running) or not session.is_cold(): return TDOutcome.new(false,"BUSY")
	var dish:=snapshot()
	if dish.get("failed_dish",false) or dish.ingredients.is_empty(): return TDOutcome.new(false,"UNKNOWN_RECIPE")
	automatic=true;session.set_production_mode("automatic");_automatic_preparation=[]
	var recipe: Dictionary=catalog.for_recipe(base_recipe_id).recipe
	for food: Dictionary in dish.ingredients.values():
		if food.history.any(func(h:Dictionary)->bool:return h.get("operation")=="cut"): continue
		var chart: String=str(recipe.get("preparation_sheets",{}).get(food.ingredient_id,""))
		if not chart.is_empty(): _automatic_preparation.append({"target":food.id,"sheet":chart})
	return _next_automatic_sheet()

func _next_automatic_sheet() -> TDOutcome:
	_automatic_target=""
	if not _automatic_preparation.is_empty():
		var entry: Dictionary=_automatic_preparation.pop_front();_automatic_target=entry.target
		return start_sheet(entry.sheet)
	return start_sheet(str(catalog.for_recipe(base_recipe_id).recipe.guided_profile))

func _ready() -> void:
	_content = catalog.data()
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 5)
	add_child(_audio)
	_build()
	if pc_controls: _build_pc()
	refresh_recipes()
	new_session(base_recipe_id)
	refresh_library()

func new_session(recipe_id: String, entry: Dictionary = {}) -> void:
	automatic=false;_automatic_preparation.clear();_automatic_target=""
	_content = catalog.data()
	if restart_allowed.is_valid() and not restart_allowed.call():
		_status.text = "先把手上的成品送到出餐台，再重新做。"
		return
	if session != null: session.cancel()
	if qte != null: qte.cancel()
	if thermal_qte != null: thermal_qte.cancel()
	thermal_qte = null; thermal_progress = {}
	if sheet != null: sheet.cancel()
	sheet = null; judgement_feedback.clear(); _feedback_token = ""; stage_label = ""
	qte = null
	_audio.stop()
	_plate.cancel_drag()
	generation += 1
	base_recipe_id = recipe_id
	custom_entry = entry.duplicate(true)
	_local_instances.clear()
	_pending_plan_local_id = ""
	_pending_plan_local_ids.clear()
	clock = TDClock.new()
	if shared_clock != null:
		clock.qte_sec = shared_clock.qte_sec; clock.game_sec = shared_clock.game_sec
	clock.paused = get_tree().paused
	_qte_random = TDBusinessRandom.new(700 + lane_index)
	var options: Dictionary = {"san": _san.value, "random_source": TDBusinessRandom.new(12345 + lane_index), "pc_controls":pc_controls, "document_rules":document_rules}
	if not entry.is_empty():
		var required: Array = []
		var amounts: Dictionary = {}
		var steps: Array = []
		for item: Dictionary in entry.plan.ingredients:
			amounts[item.ingredient_id] = float(amounts.get(item.ingredient_id, 0)) + float(item.amount)
		for identity: String in amounts:
			required.append({"id": identity, "min_amount": amounts[identity], "min_fine": 0, "max_fine": 1})
		for step: Dictionary in entry.plan.operations:
			if _content.operations.has(step.operation) and step.operation != "plate" and step.operation not in steps: steps.append(step.operation)
		options.custom_recipe = {"id": entry.id, "name": entry.name, "version": entry.version, "required_ingredients": required, "required_steps": steps, "allowed_ingredients": amounts.keys(), "variant_ids": []}
	var identity: String = "lane-%d-%d" % [lane_index,generation]
	if not session_namespace.is_empty(): identity=session_namespace+":"+identity
	session = TDCookingSession.new(identity, generation, catalog.for_recipe(recipe_id), options)
	session.result_ready.connect(_on_session_result)
	_operation_counter = 0
	_sequence = 0
	progress = {}
	_customer_feedback.clear()
	_feedback.text = "先备料，再自由选择工序。客人要求见下方；缺项可以交付，但会明确扣分。"
	_status.text = "新的一份菜，SAN %.0f。参数均为原型建议。" % _san.value
	_plan_steps.clear()
	if not entry.is_empty():
		for step: Dictionary in entry.plan.operations:
			_plan_steps.add_item("%d. %s %s" % [_plan_steps.item_count + 1, step.operation, JSON.stringify(step.parameters)])
	_refresh_targets()
	refresh()

func perform(kind: String, args: Dictionary = {}) -> TDOutcome:
	if _closed or clock.paused: return TDOutcome.new(false, "PAUSED_OR_CLOSED")
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus != null: focus.release_focus()
	var state: Dictionary = snapshot()
	_operation_counter += 1
	var request := TDRequest.new(state.session_id, generation, "%s:op-%d" % [state.session_id, _operation_counter], kind, int(state.revision), args)
	request.schema_version = 3
	var result: TDOutcome = session.begin(request)
	last_result = result
	if result.ok and result.code == "STARTED":
		for index: int in _operations.item_count:
			if _operations.get_item_metadata(index) == kind: _operations.select(index)
		if not pc_controls or kind not in ["heat", "boil"]: _operation = kind
		if not pc_controls: _sequence = 0
		var settings: Dictionary = result.data.qte_config.duplicate(true)
		settings.input_offset_sec = input_offset_sec
		if pc_controls:
			if _scheduled_settings.is_empty(): settings = _align_pc(settings)
			else: settings.merge(_scheduled_settings,true)
			if document_rules:
				var assistance: Dictionary=_content.pc_operations.document_rules.get("assistance",{})
				for key: String in ["perfect_sec","good_sec","good_quality","aggregate_score","smooth_maintain","automatic_quality"]:
					if assistance.has(key): settings[key]=assistance[key]
			_apply_day_san(settings)
			settings.document_rules = document_rules
			if document_rules and dual and settings.kind == "maintain":
				var delta: float = -.16 if lane_index == 0 else .2
				settings.target_min = clampf(float(settings.target_min)+delta,0,1)
				settings.target_max = clampf(float(settings.target_max)+delta,0,1)
		if settings.kind == "rhythm" and not pc_controls:
			_audio.prepare(settings)
			settings.lead_in_sec = float(settings.lead_in_sec) + _audio.begin()
		var controller := TDCookingQTE.new(request, settings, clock, _qte_random)
		if automatic: controller.enable_automatic()
		if kind=="season" and (settings.has("hold_durations_sec") or settings.get("free_seasoning",false)):
			controller.material_pour=session.pour_material
			controller.material_available=session.material_units
		var started := controller.start()
		if not started.ok:
			session.cancel_operation()
			if qte != null: qte.cancel()
			if thermal_qte != null: thermal_qte.cancel()
			qte = null; thermal_qte = null
			result = started
		else:
			if pc_controls and kind in ["heat", "boil"]:
				thermal_qte = controller; thermal_progress = started.data
			else:
				qte = controller; progress = started.data
			if settings.kind == "maintain": _heat.set_value_no_signal(float(settings.initial_value) * 100)
		_status.text = "正在%s" % _content.operations[kind].name
	elif not result.ok:
		_status.text = "不能执行：" + _explain_error(result)
	else:
		_status.text = "已完成：" + {"add":"投料", "merge":"合碗入锅", "container":"更换容器", "rework":"回锅", "deliver":"交付试吃", "discard":"放弃这份菜"}.get(kind, kind)
	_refresh_targets()
	refresh()
	return result

func advance(delta: float) -> void:
	if _closed or not is_finite(delta) or delta < 0 or clock.paused: return
	if pc_controls:
		_advance_pc(delta)
		return
	var remaining: float = delta
	if qte != null:
		var current := qte.update()
		var until_end: float = float(current.data.remaining_sec)
		var active: float = minf(remaining, until_end)
		clock.advance(active)
		session.advance_time(active)
		remaining -= active
		progress = qte.update().data
		# Let input at the exact inclusive end arrive before an automatic timeout.
		if bool(progress.ready_to_finish) and (until_end == 0 or remaining > .00000001): _finish()
	if remaining > 0:
		clock.advance(remaining)
		session.advance_time(remaining)
	refresh()

func input_action(action: String, pressed: bool, value: float = 1.0, operation_token: String = "") -> TDOutcome:
	if pc_controls and action in ["adjust", "drag", "hover"] and thermal_qte != null:
		_sequence += 1
		var result := thermal_qte.input(_sequence, clock.qte_sec, action, pressed, value)
		thermal_progress = result.data
		refresh()
		return result
	if qte == null: return TDOutcome.new(false, "NO_OPERATION")
	if not operation_token.is_empty() and operation_token != str(progress.operation_id): return TDOutcome.new(false, "STALE_OPERATION")
	_sequence += 1
	var result := qte.input(_sequence, clock.qte_sec, action, pressed, value)
	progress = result.data
	_capture_feedback(progress)
	_view.call("pulse_input", action, pressed)
	if result.ok and bool(progress.ready_to_finish): _finish()
	refresh()
	return result

func _finish() -> void:
	if qte == null: return
	var result := qte.finish()
	if not result.ok: return
	progress = result.data
	_capture_feedback(progress)
	last_result = session.complete_operation(result)
	if last_result.ok and not _pending_plan_local_ids.is_empty():
		var used: Array = snapshot().consumed_ingredients
		var imported: Array = used.slice(used.size()-_pending_plan_local_ids.size())
		for index: int in imported.size(): _local_instances[_pending_plan_local_ids[index]] = imported[index].instance_id
	_pending_plan_local_ids.clear()
	if last_result.ok and last_result.data.has("instance_id") and not _pending_plan_local_id.is_empty():
		_local_instances[_pending_plan_local_id] = last_result.data.instance_id
	_pending_plan_local_id = ""
	_status.text = "%s · %s · 表现 %.0f%%（%s）" % [_content.operations[_operation].name, result.data.grade, float(result.data.quality) * 100, result.data.reason]
	if story_coach and str(result.data.get("grade", "")).to_lower().contains("miss"):
		_status.text += "\n这一击偏离了命运。命运尚未宣判。继续，盯住下一拍。"
	if not last_result.ok:
		session.cancel_operation(str(result.data.operation_id))
		_status.text = "本次工序未应用：" + _explain_error(last_result)
		judgement_feedback={"grade":"Miss","action":"","message":last_result.message if not last_result.message.is_empty() else _status.text,"shown_at_sec":clock.qte_sec,"at_sec":clock.qte_sec}
	qte = null
	if not pc_controls: _audio.stop()
	_refresh_targets()

func cancel_operation() -> void:
	automatic=false;_automatic_preparation.clear();_automatic_target=""
	if qte != null: qte.cancel()
	if thermal_qte != null: thermal_qte.cancel()
	thermal_qte = null
	if sheet != null: sheet.cancel()
	qte = null
	session.cancel_operation()
	_pending_plan_local_id = ""
	_audio.stop()
	progress = {}
	judgement_feedback.clear(); _feedback_token = ""
	_status.text = "已取消本次操作，已完成的历史不会撤销。"
	refresh()

func set_paused(value: bool) -> void:
	if value:
		if qte != null: qte.release_input()
		if thermal_qte != null: thermal_qte.release_input()
		_plate.cancel_drag()
	clock.paused = value
	_audio.stream_paused = value
	refresh()

func close() -> void:
	_closed = true
	_audio.stop()
	if qte != null: qte.cancel()
	if thermal_qte != null: thermal_qte.cancel()
	thermal_qte = null
	if sheet != null: sheet.cancel()
	if session != null: session.cancel()
	qte = null

func snapshot() -> Dictionary:
	return session.snapshot().to_dict() if session != null else {}

func customer_feedback() -> Array:
	return _customer_feedback.duplicate(true)

func _on_session_result(result: TDOutcome) -> void:
	if result.data.get("session_id") != snapshot().session_id: return
	if result.code == "DELIVERED":
		dish_delivered.emit(result.data.duplicate(true))
		_customer_feedback.clear()
		var lines: Array[String] = []
		for customer: Dictionary in customer_profiles():
			var rating := scorer.evaluate(result.data, customer)
			if not rating.ok:
				lines.append("评分失败：" + rating.code + " " + rating.message)
				continue
			var display: Dictionary=rating.data.duplicate(true); display.customer_name=customer.name; _customer_feedback.append(display)
			lines.append("%s：%.1f 分 / %d 星\nQ %.1f · H %.1f · 需求偏差 %.1f" % [customer.name, rating.data.satisfaction, rating.data.stars, rating.data.quality, rating.data.harmony, rating.data.deviation])
			for reason: Dictionary in rating.data.reasons: lines.append("• " + _explain_reason(str(reason.message)))
			lines.append("")
		_feedback.text = "\n".join(lines)

func refresh() -> void:
	if session == null or (document_rules and pc_controls): return
	var dish: Dictionary = snapshot()
	var attrs: Dictionary = dish.dish_attributes
	_title.text = ("左灶" if lane_index == 0 else "右灶") + " · " + dish.recipe_name + (" [自建]" if dish.is_custom else "")
	var state_name: String = {"preparing":"备料中", "operating":"操作中", "plated":"已出锅", "delivered":"已交付", "discarded":"已报废", "cancelled":"已放弃"}.get(dish.state, dish.state)
	_summary.text = "%s  |  %.1f℃  完成度 %.1f  搭配 %.1f  |  SAN %.0f" % [state_name, attrs.temperature_c, attrs.completion, attrs.harmony, dish.san_context.current]
	_plate.visible = dish.state in ["plated", "delivered", "discarded"]
	_view.visible = not _plate.visible
	_plate.show_dish(dish)
	_view.call("set_progress", _operation, progress)
	_heat.visible = qte != null and progress.get("qte_kind") == "maintain"
	_primary.visible = qte != null and progress.get("qte_kind") in ["charge", "rhythm", "window"]
	_direction_row.visible = qte != null and progress.get("qte_kind") == "sequence"
	var key: String = "W" if lane_index == 0 else "↑"
	if not dual: key = "空格"
	_primary.text = "按住 / 按下 " + key
	var kind: String = progress.get("qte_kind", "")
	if _plate.visible:
		_hint.text = "拖动食物摆盘；盘内不改分，盘外松手整份报废。交付前可回锅。"
	elif qte == null:
		_hint.text = "自由工序：备料 → 选目标 → 选工序。所有操作都保留实际历史。"
	else:
		match kind:
			"charge": _hint.text = "按住%s蓄力，在绿色区间松开；不是等待结束。" % key
			"rhythm": _hint.text = "听节拍，音符到判定线按%s；错拍/多按会扣表现。" % key
			"window": _hint.text = "标记进入绿色区间时按%s一次。" % key
			"maintain": _hint.text = "拖动火力条抵抗波动，让实际火力留在绿区；左右键每按±5%。"
			"sequence": _hint.text = "按亮起顺序操作：" + ("W A S D" if lane_index == 0 else "↑ ← ↓ →")
	if not dish.get("fermentations", []).is_empty():
		var pending: Dictionary = dish.fermentations[0]
		_hint.text += " 发酵中，尚需 %.1f 秒。" % float(pending.remaining_sec)
	var description: Array[String] = []
	for customer: Dictionary in _content.customers:
		description.append(customer.name + "：")
		for requirement: Dictionary in customer.requirements: description.append("  " + str(requirement.label))
	description.append("\n材料：")
	for item: Dictionary in dish.ingredients.values(): description.append("%s %.2f份 · %s · %s 细碎%.2f · %.1f℃" % [item.name, item.amount, item.batch_id, item.shape, item.fine, item.temperature_c])
	description.append("\n主味 " + str(attrs.dominant) + " / 复合 " + str(attrs.compound))
	description.append("口味 [前/主/余/回]：\n" + JSON.stringify(attrs.flavor))
	description.append("口感 " + JSON.stringify(attrs.texture) + "\n香味 " + JSON.stringify(attrs.aroma))
	description.append("缺项 " + str(dish.missing_required) + "\n反应/供料/产出事件：" + JSON.stringify(dish.events))
	for step: Dictionary in dish.history:
		description.append("%s: %.1f→%.1f℃ / Q %.1f→%.1f / H %.1f→%.1f\n味 %s → %s\n口感 %s → %s\n香气 %s → %s" % [step.operation, step.before.temperature_c, step.after.temperature_c, step.before.completion, step.after.completion, step.before.harmony, step.after.harmony, JSON.stringify(step.before.flavor), JSON.stringify(step.after.flavor), JSON.stringify(step.before.texture), JSON.stringify(step.after.texture), JSON.stringify(step.before.aroma), JSON.stringify(step.after.aroma)])
	_details.text = "\n".join(description)
	if pc_controls: _refresh_pc(dish)

func _refresh_targets() -> void:
	var selected: String = _selected(_targets)
	_targets.clear()
	if session == null: return
	for identity: String in snapshot().ingredients:
		var item: Dictionary = snapshot().ingredients[identity]
		_targets.add_item("%s · %s · 第%d份" % [item.name, "主锅" if item.batch_id == "main" else "备料碗", _targets.item_count + 1])
		_targets.set_item_metadata(_targets.item_count - 1, identity)
		if identity == selected: _targets.select(_targets.item_count - 1)

func _explain_reason(message: String) -> String:
	for item: Dictionary in _content.ingredients:
		message = message.replace("ingredient:" + item.id, item.name + "（份量或加工不足）")
	for id: String in _content.operations:
		message = message.replace("step:" + id, _content.operations[id].name)
	return message

func _explain_error(result: TDOutcome) -> String:
	if not result.message.is_empty(): return result.message
	return {"BUSY":"先完成或取消正在进行的工序。", "ALREADY_FINISHED":"这份菜已结束，请重新接单。", "NO_TARGET":"先向目标锅或备料碗投放食材。", "INVALID_TARGET":"请选择可用于这道工序的食材。", "INVALID_SHAPE":"此食材不能采用该切型。", "AMOUNT_LIMIT":"该食材已达到本次厨房供料上限。", "INVALID_BATCH":"没有可合并的备料碗，请先分批投料。", "PLATING_IN_PROGRESS":"请先完成拖动摆盘，再交付。", "INVALID_AMOUNT":"请检查食材份量。", "PAUSED_OR_CLOSED":"请先恢复游戏。"}.get(result.code, "请求未生效（" + result.code + "）")

func _selected(box: OptionButton) -> String:
	return str(box.get_item_metadata(box.selected)) if box.selected >= 0 else ""

func refresh_recipes() -> void:
	_recipes.clear()
	for identity: String in catalog.recipe_ids(_test_enabled):
		_recipes.add_item(catalog.for_recipe(identity).recipe.name)
		_recipes.set_item_metadata(_recipes.item_count - 1, identity)
	_ingredients.clear()
	for item: Dictionary in _content.ingredients:
		if _test_enabled or item.scope != "TEST_ONLY":
			_ingredients.add_item(item.name)
			_ingredients.set_item_metadata(_ingredients.item_count - 1, item.id)

func _run_selected() -> void:
	var kind: String = _selected(_operations)
	var args: Dictionary = {}
	if kind == "cut": args = {"instance_id": _selected(_targets), "shape": _selected(_shapes)}
	elif kind == "season": args = {"ingredient_id": _selected(_ingredients), "amount": _amount.value, "batch_id": _selected(_batch)}
	elif kind != "plate": args = {"batch_id": _selected(_batch)}
	perform(kind, args)

func refresh_library() -> void:
	_saved.clear()
	var loaded := library.load_library()
	if not loaded.ok:
		_status.text = "配方库读取失败，保留原文件：" + loaded.code
		return
	for entry: Dictionary in loaded.data.entries:
		if _test_enabled or entry.scope != "TEST_ONLY":
			_saved.add_item(entry.name + " v%d" % entry.version + (" [TEST_ONLY]" if entry.scope == "TEST_ONLY" else ""))
			_saved.set_item_metadata(_saved.item_count - 1, entry)

func save_current(new_version: bool = false) -> TDOutcome:
	var plan: Dictionary = snapshot().custom_plan
	plan.recipe_id = base_recipe_id
	var result := library.save_plan(_recipe_name.text, plan, str(custom_entry.get("id", "")) if new_version else "")
	if result.ok: custom_entry = result.data.duplicate(true)
	_status.text = "已保存方案；重做仍需重新操作。" if result.ok else "保存失败：" + result.code
	refresh_library()
	return result

func _run_plan_step() -> void:
	if custom_entry.is_empty() or _plan_steps.selected < 0: return
	var step: Dictionary = custom_entry.plan.operations[_plan_steps.selected]
	if pc_controls and step.operation in ["add","cut"]:
		_status.text = "按方案到料箱取料，在菜板备好再搬到锅里；不能从方案界面隔空投料或切菜。"
		return
	var args: Dictionary = step.parameters.duplicate(true)
	var local_id: String = str(args.get("local_id", ""))
	args.erase("local_id")
	var local_ids: Array = args.get("local_ids",[]).duplicate()
	args.erase("local_ids")
	if step.operation == "cut":
		var target: String = str(args.get("target_local_id", ""))
		args.erase("target_local_id")
		var chosen: String = str(_local_instances.get(target, ""))
		if chosen.is_empty() and pc_controls:
			for identity: String in snapshot().ingredients:
				if snapshot().ingredients[identity].local_id == target: chosen = identity
		if chosen.is_empty() and target.is_empty():
			for identity: String in snapshot().ingredients:
				var item: Dictionary = snapshot().ingredients[identity]
				if item.ingredient_id == args.ingredient_id and item.batch_id == args.get("batch_id", "main"):
					chosen = identity
					break
		args.erase("ingredient_id")
		args.instance_id = chosen
	var result := perform(step.operation, args)
	if result.ok:
		if result.data.has("instance_id") and not local_id.is_empty(): _local_instances[local_id] = result.data.instance_id
		elif result.code == "STARTED": _pending_plan_local_id = local_id
		if result.code == "STARTED": _pending_plan_local_ids = local_ids
		_plan_steps.select(mini(_plan_steps.selected + 1, _plan_steps.item_count - 1))

func _build() -> void:
	_title = TDUI.label("", 22, TDUI.ORANGE)
	add_child(_title)
	var row := _row(self)
	_recipes = OptionButton.new(); _recipes.fit_to_longest_item = false; _recipes.clip_text = true
	_recipes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_recipes)
	row.add_child(TDUI.button("接单 / 重做", func() -> void: new_session(_selected(_recipes))))
	_san = SpinBox.new()
	_san.min_value = 0; _san.max_value = 100; _san.value = 100; _san.prefix = "SAN "
	_san.custom_minimum_size.x = 104
	row.add_child(_san)
	row = _row(self)
	_ingredients = OptionButton.new(); _ingredients.fit_to_longest_item = false; _ingredients.clip_text = true; _ingredients.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(_ingredients)
	_amount = SpinBox.new(); _amount.min_value = .01; _amount.max_value = 10; _amount.step = .1; _amount.value = 1; _amount.suffix = "份"; row.add_child(_amount)
	_batch = OptionButton.new()
	for identity: String in ["main", "side"]:
		_batch.add_item("主锅" if identity == "main" else "备料碗"); _batch.set_item_metadata(_batch.item_count - 1, identity)
	row.add_child(_batch)
	row.add_child(TDUI.button("投料", func() -> void: perform("add", {"ingredient_id": _selected(_ingredients), "amount": _amount.value, "batch_id": _selected(_batch)})))
	row = _row(self)
	_targets = OptionButton.new(); _targets.fit_to_longest_item = false; _targets.size_flags_horizontal = Control.SIZE_EXPAND_FILL; _targets.clip_text = true; row.add_child(_targets)
	_shapes = OptionButton.new()
	for identity: String in _content.cut_shapes:
		_shapes.add_item(str(_content.cut_shapes[identity].get("name", identity))); _shapes.set_item_metadata(_shapes.item_count - 1, identity)
	row.add_child(_shapes)
	row.add_child(TDUI.button("合碗入锅", func() -> void: perform("merge", {"source_batch": "side", "target_batch": "main"})))
	row = _row(self)
	_operations = OptionButton.new(); _operations.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for identity: String in _content.operations:
		var op: Dictionary = _content.operations[identity]
		_operations.add_item(op.name); _operations.set_item_metadata(_operations.item_count - 1, identity)
	row.add_child(_operations)
	row.add_child(TDUI.button("开始工序", _run_selected))
	row.add_child(TDUI.button("取消", cancel_operation))
	_view = load("res://src/qte/cooking_action_view.gd").new() as Control
	add_child(_view)
	_plate = TDPlatingView.new(); add_child(_plate)
	_plate.moved.connect(func(id: String, point: Vector2, drop: bool) -> void:
		var result := session.move_plating(id, point, drop)
		if not result.ok or result.code == "DISCARDED": _status.text = result.code + "：盘外松手，该份已报废。"
		refresh())
	_hint = TDUI.label("", 15, TDUI.MUTED); _hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; add_child(_hint)
	_primary = Button.new(); _primary.focus_mode = Control.FOCUS_NONE
	_primary.button_down.connect(func() -> void: input_action("primary", true))
	_primary.button_up.connect(func() -> void: input_action("primary", false))
	add_child(_primary)
	_heat = HSlider.new(); _heat.min_value = 0; _heat.max_value = 100; _heat.value = 50; _heat.step = .1
	_heat.value_changed.connect(func(value: float) -> void: input_action("adjust", true, value / 100))
	add_child(_heat)
	_direction_row = _row(self)
	for direction: String in ["up", "left", "down", "right"]:
		var d: String = direction
		_direction_row.add_child(TDUI.button({"up":"↑", "left":"←", "down":"↓", "right":"→"}[d], func() -> void:
			input_action(d, true); input_action(d, false)))
	_status = TDUI.label("", 15, TDUI.ORANGE); _status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; add_child(_status)
	_summary = TDUI.label("", 14); add_child(_summary)
	row = _row(self)
	row.add_child(TDUI.button("交付试吃", func() -> void: perform("deliver")))
	row.add_child(TDUI.button("回锅", func() -> void: perform("rework")))
	row.add_child(TDUI.button("保温", func() -> void: perform("container", {"kind": "insulated"})))
	row.add_child(TDUI.button("普通盘", func() -> void: perform("container", {"kind": "normal"})))
	row.add_child(TDUI.button("放弃", func() -> void: perform("discard")))
	var tabs := TabContainer.new(); tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL; tabs.custom_minimum_size.y = 160; add_child(tabs)
	_feedback = RichTextLabel.new(); _feedback.name = "试吃反馈"; tabs.add_child(_feedback)
	_details = RichTextLabel.new(); _details.name = "要求与工序变化"; tabs.add_child(_details)
	var library_tab := VBoxContainer.new(); library_tab.name = "自建食谱"; tabs.add_child(library_tab)
	row = _row(library_tab)
	_recipe_name = LineEdit.new(); _recipe_name.placeholder_text = "为本次方案命名"; _recipe_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(_recipe_name)
	row.add_child(TDUI.button("新建保存", func() -> void: save_current(false)))
	row.add_child(TDUI.button("另存新版本", func() -> void: save_current(true)))
	row = _row(library_tab)
	_saved = OptionButton.new(); _saved.fit_to_longest_item = false; _saved.clip_text = true; _saved.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(_saved)
	row.add_child(TDUI.button("刷新", refresh_library))
	row.add_child(TDUI.button("选用并重做", func() -> void:
		if _saved.selected >= 0:
			var entry: Dictionary = _saved.get_item_metadata(_saved.selected)
			new_session(entry.plan.recipe_id, entry)))
	row = _row(library_tab)
	_plan_steps = OptionButton.new(); _plan_steps.fit_to_longest_item = false; _plan_steps.clip_text = true; _plan_steps.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(_plan_steps)
	row.add_child(TDUI.button("按方案执行此步", _run_plan_step))
	library_tab.add_child(TDUI.label("只保存方案；可自由修改用料/工序后另存版本。成绩必须重新操作获得。", 14, TDUI.MUTED))
	var test_toggle := CheckButton.new(); test_toggle.text = "显示 TEST_ONLY 机制测试食谱 / 食材"; test_toggle.add_theme_font_size_override("font_size", 14)
	test_toggle.toggled.connect(func(value: bool) -> void: _test_enabled = value; refresh_recipes(); refresh_library())
	add_child(test_toggle)

func _row(parent: Node) -> HBoxContainer:
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 5); parent.add_child(row); return row

func bind_preparation(value: TDCookingSession) -> void:
	if qte != null: qte.cancel()
	if sheet != null: sheet.cancel()
	sheet = null; judgement_feedback.clear(); _feedback_token = ""
	qte = null
	if session != null and session != value:
		if session.result_ready.is_connected(_on_session_result): session.result_ready.disconnect(_on_session_result)
	session = value
	generation = int(snapshot().generation)
	base_recipe_id = str(snapshot().recipe_id)
	if not session.result_ready.is_connected(_on_session_result): session.result_ready.connect(_on_session_result)
	progress = {}; _operation_counter = 0; _sequence = 0
	if shared_clock != null:
		clock.qte_sec = shared_clock.qte_sec; clock.game_sec = shared_clock.game_sec
	_refresh_targets(); refresh()

func start_preparation() -> TDOutcome:
	var dish: Dictionary = snapshot()
	if dish.ingredients.is_empty(): return TDOutcome.new(false,"NO_INGREDIENT")
	var recipe: Dictionary = catalog.for_recipe(str(dish.recipe_id)).get("recipe",{})
	var ingredient: String = str(dish.ingredients.values()[0].ingredient_id)
	var id: String = str(recipe.get("preparation_sheets",{}).get(ingredient,""))
	if id.is_empty(): return TDOutcome.new(false,"NO_PREPARATION_CHART","这份菜谱未配置该食材的备菜谱。")
	return start_sheet(id)

func use_recipe_profile(value: TDCookingCatalog, identity: String, customer: Dictionary = {}) -> TDOutcome:
	var changed := session.select_recipe(value.for_recipe(identity))
	if not changed.ok: return changed
	catalog = value; _content = value.data(); base_recipe_id = identity
	customer_override = [customer.duplicate(true)] if not customer.is_empty() else []
	return changed

func feedback_remaining() -> float:
	return maxf(0,float(judgement_feedback.get("shown_at_sec",-10)) + float(_content.pc_operations.document_rules.get("feedback_sec",.9)) - clock.qte_sec)

var feedback_audible: bool=true

func _capture_feedback(data: Dictionary) -> void:
	if not document_rules: return
	var event: Dictionary = data.get("last_judgement",{})
	if event.is_empty(): return
	var token: String = str(data.get("operation_id",""))+":"+str(event.serial)
	if token == _feedback_token: return
	_feedback_token = token
	judgement_feedback = event.duplicate(true)
	judgement_feedback.operation_id = data.operation_id
	judgement_feedback.shown_at_sec = float(event.at_sec)
	if feedback_remaining() > 0 and feedback_audible and not automatic: _audio.play_feedback(str(event.grade))

func next_boundary_sec() -> float:
	var boundary: float = sheet.next_in(clock.qte_sec) if sheet != null else INF
	if automatic and not _automatic_target.is_empty() and qte==null and thermal_qte==null:
		var recovery: float=float(snapshot().recovery_sec)
		if recovery>0: boundary=minf(boundary,recovery)
	for controller: TDCookingQTE in [qte,thermal_qte]:
		if controller != null: boundary = minf(boundary,float(controller.update().data.remaining_sec))
	return boundary

func _align_pc(settings: Dictionary) -> Dictionary:
	var interval: float = 60.0 / float(_content.pc_operations.bpm)
	if settings.has("interval_sec"): settings.interval_sec = interval
	if settings.has("lead_in_sec"):
		var at: float = ceil((clock.qte_sec - beat_offset_sec + .25) / interval) * interval + beat_offset_sec
		settings.lead_in_sec = maxf(.25, at - clock.qte_sec)
	if settings.kind == "window":
		var at: float = ceil((clock.qte_sec - beat_offset_sec + .5) / (4 * interval)) * (4 * interval) + beat_offset_sec
		settings.target_sec = maxf(.5, at - clock.qte_sec)
		settings.timeout_sec = settings.target_sec + .3
		settings.sweep_period_sec = settings.target_sec * 4
	if settings.kind == "maintain" and dual:
		var offsets: Array = _content.pc_operations.get("dual_target_offsets",[-.15,.2])
		settings.target_min = clampf(float(settings.target_min)+float(offsets[mini(lane_index,1)]),0,1)
		settings.target_max = clampf(float(settings.target_max)+float(offsets[mini(lane_index,1)]),0,1)
	if assist_windows:
		for field: String in ["perfect_sec", "good_sec", "good_margin_sec"]:
			if settings.has(field): settings[field] = float(settings[field]) * 1.5
	return settings

func _apply_day_san(settings: Dictionary) -> void:
	if day_san < 0.0:
		return
	var scale := TDSanRules.window_scale(day_san)
	for field: String in ["perfect_sec", "good_sec", "good_margin_sec"]:
		if settings.has(field):
			settings[field] = float(settings[field]) * scale

func start_sheet(id: String) -> TDOutcome:
	if qte != null or thermal_qte != null: return TDOutcome.new(false, "BUSY")
	var configured: Dictionary = _content.pc_operations.document_sheets if document_rules else _content.pc_operations.sheets
	if not configured.has(id): return TDOutcome.new(false, "UNKNOWN_SHEET")
	sheet = TDBeatSheet.new()
	var check := sheet.configure(configured[id], _content.operations,_content.pc_operations.document_rules.get("assistance",{}) if document_rules else {})
	if not check.ok: return check
	active_sheet_id = id
	var bar: float = 240.0 / float(configured[id].bpm)
	var origin: float = ceil((clock.qte_sec - beat_offset_sec + .5) / bar) * bar + beat_offset_sec
	_status.text = "下个强拍开始 · 留白可以休息，控温仍会继续"
	return sheet.start(origin)

func _advance_pc(delta: float) -> void:
	var remaining: float = delta
	var iterations: int = 0
	while remaining > .000000001 or iterations == 0:
		iterations += 1
		if iterations > 512:
			push_error("PC operation scheduler exceeded bounded event count")
			break
		if automatic and not _automatic_target.is_empty() and qte==null and thermal_qte==null and sheet!=null and not sheet.running and float(snapshot().recovery_sec)<=.000001:
			_next_automatic_sheet()
		if sheet != null:
			for event: Dictionary in sheet.due(clock.qte_sec):
				_scheduled_settings = event.get("settings",{}).duplicate(true)
				var args: Dictionary = event.parameters.duplicate(true)
				if document_rules and event.operation == "cut":
					if snapshot().ingredients.is_empty(): sheet.cancel(); break
					args.instance_id = _automatic_target if not _automatic_target.is_empty() else snapshot().ingredients.keys()[0]; args.beats = _scheduled_settings.beats
				if event.operation not in ["heat","boil"] or qte==null: stage_label = event.get("label","")
				var result := perform(event.operation, args)
				_scheduled_settings.clear()
				if not result.ok:
					sheet.cancel(); _status.text = "节拍表已停止：" + _explain_error(result)
		if assist_temperature and thermal_qte != null:
			_sequence += 1
			thermal_qte.input(_sequence, clock.qte_sec, "drag", true, (float(thermal_progress.target_min) + float(thermal_progress.target_max)) * .5)
		var span: float = remaining
		if automatic and not _automatic_target.is_empty() and qte==null and thermal_qte==null and float(snapshot().recovery_sec)>0: span=minf(span,float(snapshot().recovery_sec))
		if sheet != null: span = minf(span, sheet.next_in(clock.qte_sec))
		for controller: TDCookingQTE in [qte, thermal_qte]:
			if controller != null: span = minf(span, float(controller.update().data.remaining_sec))
		clock.advance(span); session.advance_time(span); remaining -= span
		if qte != null:
			progress = qte.update().data
			_capture_feedback(progress)
			if bool(progress.ready_to_finish) and (remaining > .000000001 or span == 0): _finish()
		if thermal_qte != null:
			thermal_progress = thermal_qte.update().data
			if bool(thermal_progress.ready_to_finish) and (remaining > .000000001 or span == 0):
				var result := thermal_qte.finish()
				thermal_progress = result.data
				_capture_feedback(thermal_progress)
				last_result = session.complete_operation(result)
				_status.text = "控温完成 · 稳定 %.0f%% · %s" % [float(result.data.quality) * 100, result.data.grade]
				thermal_qte = null
		if remaining <= .000000001: break
	refresh()

func _build_pc() -> void:
	# Keep the original developer widgets as compatibility harnesses, but the
	# playable station flow has no remote ingredient injection buttons.
	for child: Node in get_children():
		if child is HBoxContainer: child.hide()
	_san.hide()
	_pc_toolbar = HFlowContainer.new(); add_child(_pc_toolbar); move_child(_pc_toolbar, 2)
	var recipe_row := HBoxContainer.new(); add_child(recipe_row); move_child(recipe_row,2)
	_recipes.reparent(recipe_row)
	recipe_row.add_child(TDUI.button("选择菜谱 / 重做",func() -> void: new_session(_selected(_recipes))))
	_pc_buttons.recipes = recipe_row
	_cut_beats = SpinBox.new(); _cut_beats.min_value = 1; _cut_beats.max_value = 12; _cut_beats.value = 2; _cut_beats.prefix = "计划 "; _cut_beats.suffix = " 刀"; _pc_toolbar.add_child(_cut_beats)
	_cut_beats.custom_minimum_size.x = 145
	_pc_amount = SpinBox.new(); _pc_amount.min_value=.01; _pc_amount.max_value=1; _pc_amount.step=.01; _pc_amount.value=.1; _pc_amount.suffix="份/调料"; _pc_toolbar.add_child(_pc_amount)
	_pc_amount.custom_minimum_size.x = 160
	for definition: Array in [["cut","开始切菜"],["preheat","点火"],["stir","翻炒"],["heat","炒制控温"],["boil","炖煮控温"],["season","顺序调味"],["oil","下油"],["starch","勾芡"],["ferment","发酵搅拌"],["steam","上笼蒸制"],["plate","长按出锅"]]:
		var kind: String = definition[0]
		var button := TDUI.button(definition[1], func() -> void: _pc_perform(kind))
		_pc_buttons[kind] = button; _pc_toolbar.add_child(button)
	_pc_toolbar.add_child(TDUI.button("取消本次", cancel_operation))
	_pc_buttons.sheet = TDUI.button("跟随炒菜节拍表", func() -> void: start_sheet("stir_fry")); _pc_toolbar.add_child(_pc_buttons.sheet)
	_pc_buttons.steam_sheet = TDUI.button("跟随蒸菜节拍表", func() -> void: start_sheet("steam")); _pc_toolbar.add_child(_pc_buttons.steam_sheet)
	_pc_buttons.rework = TDUI.button("回锅", func() -> void: perform("rework")); _pc_toolbar.add_child(_pc_buttons.rework)
	temperature_view = TDTemperatureView.new(); add_child(temperature_view); move_child(temperature_view, get_children().find(_view) + 1)
	_cabinet = HBoxContainer.new(); add_child(_cabinet); move_child(_cabinet, get_children().find(_hint) + 1)
	for id: String in ["salt", "sugar", "oil", "starch"]:
		var action: String = "spice:" + id
		var button := TDUI.button({"salt":"盐","sugar":"糖","oil":"油","starch":"淀粉"}[id], func() -> void:
			input_action(action, true); input_action(action, false))
		button.name = "Spice_" + id; button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_cabinet.add_child(button)
	_direction_row.add_child(TDUI.button("空格 · 收势", func() -> void: input_action("primary", true); input_action("primary", false)))
	(_details.get_parent() as TabContainer).custom_minimum_size.y=110

func _pc_perform(kind: String) -> void:
	var args: Dictionary = {}
	if kind == "cut":
		if snapshot().ingredients.is_empty(): return
		args = {"instance_id":snapshot().ingredients.keys()[0],"beats":int(_cut_beats.value)}
	elif kind in ["season", "oil"]: args = {"ingredient_id":"oil" if kind == "oil" else "salt","amount":_pc_amount.value,"mode":"common" if kind == "oil" else "precise"}
	perform("season" if kind == "oil" else kind, args)

func _refresh_pc(dish: Dictionary) -> void:
	if _pc_toolbar == null: return
	_title.text = ("菜板" if station_role == "board" else ("蒸笼" if station_role == "steamer" else ("左灶" if lane_index == 0 else "右灶"))) + " · " + dish.recipe_name
	for kind: String in _pc_buttons:
		if station_role == "board": _pc_buttons[kind].visible = kind == "cut"
		elif station_role == "steamer": _pc_buttons[kind].visible = kind in ["season","steam","steam_sheet","plate","rework","recipes"]
		else: _pc_buttons[kind].visible = kind not in ["cut","steam","steam_sheet"]
	_cut_beats.visible = station_role == "board"
	_pc_amount.visible = station_role != "board"
	_heat.hide()
	temperature_view.visible = thermal_qte != null
	temperature_view.show_progress(thermal_progress)
	_cabinet.visible = qte != null and progress.get("pc_module") == "M6"
	_direction_row.visible = qte != null and progress.get("qte_kind") == "sequence" and not _cabinet.visible
	if qte != null:
		match str(progress.get("pc_module", "")):
			"M1": _hint.text = "空格落刀 · A/D转向：%s · 成功%d刀（两刀同向=条，转向=块，三刀起=丁）" % [["横切","竖切","斜切"][int(progress.get("cut_direction",0))],int(progress.get("hits",0))]
			"M2": _hint.text = "空格点火 · 游标到中央绿区时按一下，金色强拍帮助预判"
			"M3": _hint.text = "每拍一个指令，最后空格收势 · " + ("W A S D" if lane_index != 1 else "↑ ← ↓ →")
			"M6": _hint.text = "每拍点击一个调料：盐 → 糖 → 油；点错材料会实际改变味道"
			"M7": _hint.text = "长按空格，进度到绿区中心后松开；早松欠火，晚松过火"
	elif thermal_qte != null:
		_hint.text = "鼠标靠近温度条产生弱吸引，按住增强；可以同时开始翻炒或调味。"
	else:
		_hint.text = "在功能位选择操作；返回厨房继续搬运食材。" if dish.state != "plated" else "可拖动摆盘；返回厨房后在灶台按 E 端起，送到出餐台。"
	_primary.text = "长按空格 → 绿区松开" if progress.get("qte_kind") == "charge" else "空格 · 卡拍操作"
	var lines: Array[String] = ["食材处理状态："]
	for item: Dictionary in dish.ingredients.values():
		lines.append("%s · %s · 细碎 %d/8 · %.1f℃" % [item.name,{"whole":"完整","slice":"片","strip":"条","chunk":"块","dice":"丁"}.get(item.shape,item.shape),roundi(float(item.fine)*8),item.temperature_c])
		var note := TDPrepGuide.handling_for_id(String(item.get("ingredient_id", "")), String(dish.get("recipe_id", base_recipe_id)))
		if note != "":
			lines.append("  " + note)
	lines.append("\n客人明确要求：")
	for customer: Dictionary in _content.customers:
		lines.append(customer.name)
		for requirement: Dictionary in customer.requirements: lines.append("  " + str(requirement.label))
	lines.append("\n工序前后：")
	for step: Dictionary in dish.history:
		lines.append("%s · 温度 %.1f→%.1f℃ / 完成度 %.1f→%.1f / 搭配 %.1f→%.1f" % [_content.operations.get(step.operation,{}).get("name","入锅"),step.before.temperature_c,step.after.temperature_c,step.before.completion,step.after.completion,step.before.harmony,step.after.harmony])
	_details.text = "\n".join(lines)
	var tabs: TabContainer = _details.get_parent() as TabContainer
	tabs.set_tab_hidden(2,station_role == "board")

func customer_profiles() -> Array:
	return customer_override.duplicate(true) if not customer_override.is_empty() else _content.customers.duplicate(true)
