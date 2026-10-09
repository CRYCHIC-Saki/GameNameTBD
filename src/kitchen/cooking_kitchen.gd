class_name TDCookingKitchen
extends Control

signal back_requested
signal pause_requested
signal restart_requested
signal dish_delivered(result: TDOutcome)
signal operation_applied(result: TDOutcome)

var config: Dictionary
var clock: TDClock
var scorer: TDCustomerScorer
var session_id: String
var generation: int
var session: TDCookingSession
var automatic_time: bool = true
var audio_enabled: bool = true
var customer_index: int = 0
var input_offset_sec: float = 0.0
var _qte: RefCounted
var _active_kind: String = ""
var _qte_end_sec: float = 0.0
var _operation_counter: int = 0
var _sequence: int = 0
var _accepted: bool = false
var _closed: bool = false
var _paused: bool = false
var _last_tick: int = 0
var _feedback: Dictionary = {}
var _qte_status: Dictionary = {}
var _audio: TDBeatAudio
var _board: TDCookingBoard
var _order: Label
var _status: Label
var _attributes: RichTextLabel
var _history: RichTextLabel
var _feedback_label: RichTextLabel
var _customer_choice: OptionButton
var _shape: OptionButton
var _power: HSlider
var _offset: SpinBox
var _progress: ProgressBar
var _action_buttons: Array[Button] = []
var _accept_button: Button
var _cancel_button: Button
var _tap_button: Button
var _pause_button: Button
var _ui_guard: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	session = TDCookingSession.new(session_id, generation, config)
	_audio = TDBeatAudio.new()
	add_child(_audio)
	_build_ui()
	_last_tick = Time.get_ticks_usec()
	_render()

func accept_order() -> TDOutcome:
	if _accepted or _closed or _paused:
		return TDOutcome.new(false, "UNAVAILABLE")
	_accepted = true
	_status.text = "订单已接。推荐：番茄＋鸡蛋 → 切番茄 → 调味 → 加热 → 出锅交付。可自由调整。"
	_render()
	return TDOutcome.new(true, "ORDER_ACCEPTED")

func perform(kind: String, parameters: Dictionary = {}) -> TDOutcome:
	_sync_time()
	if not _accepted or _closed or _paused:
		return TDOutcome.new(false, "UNAVAILABLE")
	_operation_counter += 1
	var request := TDRequest.new(session_id, generation, "op-%d" % _operation_counter, kind, int(session.snapshot().to_dict()["revision"]))
	request.schema_version = 2
	request.parameters = parameters.duplicate(true)
	var outcome := session.begin(request)
	if not outcome.ok:
		_status.text = _failure_message(outcome)
		return outcome
	if kind in ["cut", "heat"]:
		_active_kind = kind
		_sequence = 0
		var qte_config: Dictionary = config["qte"][kind].duplicate(true)
		if kind == "cut":
			_shape.select(0 if parameters["shape"] == "chunk" else 1)
			qte_config["input_offset_sec"] = input_offset_sec
			if audio_enabled:
				_audio.prepare(qte_config)
				qte_config["lead_in_sec"] = float(qte_config["lead_in_sec"]) + _audio.begin()
			_qte = TDRhythmQTE.new(request, qte_config, clock)
		else:
			_qte = TDHeatQTE.new(request, qte_config, clock)
			_ui_guard = true
			_power.value = float(qte_config.get("initial_power", 0.5))
			_ui_guard = false
		var started: TDOutcome = _qte.start()
		if not started.ok:
			session.cancel_operation()
			_dispose_qte()
			_status.text = started.code
			return started
		_qte_status = started.data.duplicate(true)
		_qte_end_sec = clock.qte_sec + float(qte_config.get("duration_sec", 6.0))
		if kind == "cut":
			# Keep the inclusive last Good edge open to an input at that timestamp.
			_qte_end_sec = clock.qte_sec + float(qte_config["lead_in_sec"]) + (int(qte_config["beats"]) - 1) * float(qte_config["interval_sec"]) + float(qte_config["good_sec"]) + input_offset_sec + 0.0000001
		_status.text = "圆点抵达左侧金线、听到拍点时按空格；节奏只影响品质。" if kind == "cut" else "拖动火力，保持在标示的稳定区。空格按住为猛火，松开回到基准火力。"
	else:
		operation_applied.emit(outcome)
		_status.text = "已执行：" + _operation_name(kind)
	if kind == "plate":
		_deliver()
	_render()
	return outcome

func route_input(value: float) -> TDOutcome:
	_sync_time()
	if _closed or _paused or _qte == null:
		return TDOutcome.new(false, "UNAVAILABLE")
	_sequence += 1
	var outcome: TDOutcome = _qte.input(_sequence, clock.qte_sec, value)
	if _active_kind == "heat":
		_ui_guard = true
		_power.value = value
		_ui_guard = false
	return outcome

func advance_time(delta_sec: float) -> void:
	if _closed or not is_finite(delta_sec) or delta_sec < 0.0:
		return
	if _paused:
		clock.advance(delta_sec)
		_render()
		return
	var remaining: float = delta_sec
	if _qte != null and clock.qte_sec + remaining >= _qte_end_sec:
		var until_finish: float = maxf(0.0, _qte_end_sec - clock.qte_sec)
		_advance_slice(until_finish)
		remaining = maxf(0.0, remaining - until_finish)
	if remaining > 0.0 or delta_sec == 0.0:
		_advance_slice(remaining)
	_render()

func _advance_slice(delta_sec: float) -> void:
	clock.advance(delta_sec)
	session.advance_time(delta_sec)
	if _qte == null:
		return
	var update: TDOutcome = _qte.update()
	_qte_status = update.data.duplicate(true)
	if bool(update.data.get("ready_to_finish", false)) and clock.qte_sec >= _qte_end_sec:
		var result: TDOutcome = _qte.finish()
		if result.ok:
			var applied := session.complete_operation(result)
			_status.text = "%s结束：品质 %.0f%%。可以继续加工或出锅。" % [_operation_name(_active_kind), float(result.data.get("quality", 0.0)) * 100.0] if applied.ok else "效果拒绝：" + applied.code
			operation_applied.emit(applied)
			_dispose_qte()

func cancel_operation() -> TDOutcome:
	if _closed or _paused:
		return TDOutcome.new(false, "UNAVAILABLE")
	var outcome := session.cancel_operation()
	_dispose_qte()
	_status.text = "已取消本次操作，未提交的工序效果不应用。"
	_render()
	return outcome

func set_paused(value: bool) -> void:
	_sync_time()
	_paused = value
	clock.paused = value
	_audio.stream_paused = value
	if _qte != null:
		_qte.release_input()
		if _active_kind == "heat":
			_ui_guard = true
			_power.value = float(_qte.update().data.get("power", 0.5))
			_ui_guard = false
	_last_tick = Time.get_ticks_usec()
	_render()

func close() -> void:
	if _closed:
		return
	_closed = true
	_dispose_qte()
	if session != null:
		session.cancel()
	if clock != null:
		clock.paused = false
	set_process(false)
	set_process_input(false)

func last_feedback() -> Dictionary:
	return _feedback.duplicate(true)

func _exit_tree() -> void:
	close()

func _dispose_qte() -> void:
	if _qte != null:
		_qte.cancel()
	_qte = null
	_active_kind = ""
	if is_instance_valid(_audio):
		_audio.stop()

func _process(_delta: float) -> void:
	_sync_time()

func _sync_time() -> void:
	if automatic_time and _last_tick > 0 and not _closed:
		var now: int = Time.get_ticks_usec()
		var elapsed: float = float(now - _last_tick) / 1000000.0
		_last_tick = now
		advance_time(elapsed)

func _input(event: InputEvent) -> void:
	if _closed or event.is_echo():
		return
	if event.is_action_pressed("pause"):
		pause_requested.emit()
		get_viewport().set_input_as_handled()
		return
	if _paused:
		return
	if event.is_action_pressed("restart_probe"):
		restart_requested.emit()
		get_viewport().set_input_as_handled()
	elif event.is_action("cook_action"):
		var strength: float = event.get_action_strength("cook_action")
		if _active_kind == "heat":
			strength = 1.0 if strength > 0.0 else float(config["qte"]["heat"].get("initial_power", 0.5))
		route_input(strength)
		get_viewport().set_input_as_handled()

func _deliver() -> void:
	var customer: Dictionary = config["customers"][customer_index]
	var scored := scorer.evaluate(session.snapshot().to_dict(), customer)
	_feedback = scored.to_dict()
	if not scored.ok:
		_feedback_label.text = "评分失败：" + scored.code + " " + scored.message
		return
	var data: Dictionary = scored.data
	var text: String = "%s的反馈\n满意度 %.1f / 100\n基础 Q %.1f · H %.1f · 需求偏差 %.1f\n\n" % [customer["name"], data["satisfaction"], data["quality"], data["harmony"], data["deviation"]]
	for reason: Dictionary in data.get("reasons", []):
		text += "• " + str(reason.get("message", reason.get("label", reason.get("code", "")))) + "\n"
	if data.get("reasons", []).is_empty():
		text += "这次做法满足了已声明的要求。\n"
	text += "\n下一次可调整切型、糖盐或火力。R 重试同一订单。\n数值均为原型建议，未设星级与奖励。"
	_feedback_label.text = text
	_status.text = "已交付。根据右侧反馈调整下一次做法；本次没有经济惩罚。"
	dish_delivered.emit(scored)

func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)
	var root_column := TDUI.column(margin, 10)
	var header := HBoxContainer.new()
	root_column.add_child(header)
	var title := TDUI.label("番茄炒蛋 / 试作厨房", 29)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(TDUI.button("返回", func() -> void: back_requested.emit()))
	_pause_button = TDUI.button("暂停 Esc", func() -> void: pause_requested.emit())
	header.add_child(_pause_button)
	header.add_child(TDUI.button("重试 R", func() -> void: restart_requested.emit()))
	root_column.add_child(TDUI.label("PHASE 1 · 图形/音效均为占位 · 自由工序 · 建议数值 · 无经济惩罚", 15, TDUI.ORANGE))
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 18)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_column.add_child(columns)
	var left := TDUI.column(columns, 10)
	left.custom_minimum_size.x = 245
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 0.8
	left.add_child(TDUI.label("01  接单与备料", 21, TDUI.ORANGE))
	_customer_choice = OptionButton.new()
	for customer: Dictionary in config["customers"]:
		_customer_choice.add_item(str(customer["name"]))
	_customer_choice.select(customer_index)
	_customer_choice.item_selected.connect(func(index: int) -> void: customer_index = index; _render())
	left.add_child(_customer_choice)
	_order = TDUI.label("", 17)
	left.add_child(_order)
	_accept_button = TDUI.button("接下这单", accept_order)
	left.add_child(_accept_button)
	_add_action(left, "放入番茄", "add", {"ingredient_id": "tomato"})
	_add_action(left, "放入鸡蛋", "add", {"ingredient_id": "egg"})
	_shape = OptionButton.new()
	_shape.add_item("番茄切型：大块")
	_shape.add_item("番茄切型：小丁")
	left.add_child(_shape)
	var cut_button := TDUI.button("切番茄 · 节奏", func() -> void: perform("cut", {"ingredient_id": "tomato", "shape": "chunk" if _shape.selected == 0 else "dice"}))
	left.add_child(cut_button)
	_action_buttons.append(cut_button)
	var seasoning := HBoxContainer.new()
	left.add_child(seasoning)
	_add_action(seasoning, "加糖 +1", "season", {"ingredient_id": "sugar", "amount": 1})
	_add_action(seasoning, "加盐 +1", "season", {"ingredient_id": "salt", "amount": 1})
	left.add_child(TDUI.label("必需：番茄、鸡蛋、切番茄、加热。漏项也能交付，反馈会指出原因。", 15, TDUI.MUTED))
	var center := TDUI.column(columns, 8)
	center.custom_minimum_size.x = 410
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_stretch_ratio = 1.25
	center.add_child(TDUI.label("02  操作与属性", 21, TDUI.ORANGE))
	_board = TDCookingBoard.new()
	center.add_child(_board)
	_progress = ProgressBar.new()
	_progress.max_value = 1.0
	_progress.custom_minimum_size.y = 22
	center.add_child(_progress)
	_tap_button = TDUI.button("落刀 / 空格（按拍点）", func() -> void: pass)
	_tap_button.button_down.connect(func() -> void: route_input(1.0))
	_tap_button.button_up.connect(func() -> void: route_input(0.0))
	center.add_child(_tap_button)
	var heat_row := HBoxContainer.new()
	center.add_child(heat_row)
	_add_action(heat_row, "加热 · 控火", "heat")
	_add_action(heat_row, "出锅并交付", "plate")
	center.add_child(TDUI.label("火力 0–100%% · 稳定区 %.0f–%.0f%%" % [float(config["qte"]["heat"]["target_power_min"]) * 100.0, float(config["qte"]["heat"]["target_power_max"]) * 100.0], 16))
	_power = HSlider.new()
	_power.min_value = 0.0
	_power.max_value = 1.0
	_power.step = 0.01
	_power.value = 0.5
	_power.value_changed.connect(func(value: float) -> void:
		if not _ui_guard and _active_kind == "heat": route_input(value))
	center.add_child(_power)
	_cancel_button = TDUI.button("取消", cancel_operation)
	heat_row.add_child(_cancel_button)
	_attributes = _text_box(center, 115)
	var calibration := HBoxContainer.new()
	left.add_child(calibration)
	var calibration_label := TDUI.label("输入补偿 ms", 15)
	calibration_label.custom_minimum_size.x = 110
	calibration.add_child(calibration_label)
	_offset = SpinBox.new()
	_offset.custom_minimum_size.x = 115
	_offset.min_value = -250
	_offset.max_value = 250
	_offset.step = 5
	_offset.value = input_offset_sec * 1000.0
	_offset.value_changed.connect(func(value: float) -> void: input_offset_sec = value / 1000.0)
	calibration.add_child(_offset)
	left.add_child(TDUI.label("若总是慢于听到的拍点，可调正值。设备同步待试玩校准。", 13, TDUI.MUTED))
	var right := TDUI.column(columns, 10)
	right.custom_minimum_size.x = 285
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 1.0
	right.add_child(TDUI.label("03  工序变化与反馈", 21, TDUI.ORANGE))
	_history = _text_box(right, 240)
	_feedback_label = _text_box(right, 250)
	_feedback_label.text = "交付后显示评分与主要原因。\n\n选择不同客人，比较同一做法是否合适。\n\n未声明的要求不会额外扣需求分。"
	_status = TDUI.label("先选客人并接单，再决定做法。", 17, TDUI.ORANGE)
	_status.custom_minimum_size.y = 46
	root_column.add_child(_status)

func _add_action(parent: Node, text: String, kind: String, parameters: Dictionary = {}) -> void:
	var button := TDUI.button(text, func() -> void: perform(kind, parameters))
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(button)
	_action_buttons.append(button)

func _text_box(parent: Node, height: float) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.custom_minimum_size.y = height
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("normal_font_size", 16)
	parent.add_child(label)
	return label

func _render() -> void:
	if session == null or _order == null:
		return
	var state := session.snapshot().to_dict()
	var terminal: bool = str(state.get("state", "")) in ["plated", "cancelled"]
	var busy: bool = _qte != null
	for button: Button in _action_buttons:
		button.disabled = not _accepted or busy or terminal or _paused
	_accept_button.disabled = _accepted or _paused
	_customer_choice.disabled = _accepted or _paused
	_shape.disabled = busy or terminal or _paused
	_offset.editable = not busy and not _paused
	_power.editable = _active_kind == "heat" and not _paused
	_cancel_button.disabled = not busy or _paused
	_tap_button.disabled = _active_kind != "cut" or _paused
	_pause_button.text = "恢复 Esc" if _paused else "暂停 Esc"
	_order.text = str(config["customers"][customer_index]["description"])
	_board.values = state
	_board.active_kind = _active_kind
	_board.beat_times = _qte_status.get("beat_times_sec", [])
	_board.elapsed_sec = float(_qte_status.get("elapsed_sec", 0.0))
	_board.beat_fraction = float(_qte_status.get("elapsed_sec", 0.0)) / float(config["qte"]["cut"].get("interval_sec", 0.5))
	_board.queue_redraw()
	_progress.value = float(_qte_status.get("progress", 0.0))
	var attrs: Dictionary = state.get("dish_attributes", {})
	_attributes.text = _describe_attributes(attrs, state.get("ingredients", {}))
	if _paused:
		_attributes.text = "【已暂停：游戏、QTE、音轨冻结】\n" + _attributes.text
	elif _active_kind == "cut":
		_attributes.text = "Perfect %d / Good %d / Miss %d\n" % [_qte_status.get("perfect", 0), _qte_status.get("good", 0), _qte_status.get("miss", 0)] + _attributes.text
	var history_text: String = "工序记录（顺序生效）\n"
	for entry: Dictionary in state.get("history", []):
		history_text += _history_line(entry)
	if _history.text != history_text:
		_history.text = history_text

func _describe_attributes(attrs: Dictionary, ingredients: Dictionary) -> String:
	if attrs.is_empty():
		return "尚无菜品属性"
	var text: String = "温度 %.1f℃ · Q %.1f · H %.1f\n" % [attrs.get("temperature_c", 0.0), attrs.get("completion", 0.0), attrs.get("harmony", 0.0)]
	var aromas: Array[String] = []
	for tag: String in attrs.get("aroma", {}):
		aromas.append("%s %.0f" % [str({"tomato": "番茄香", "egg": "蛋香", "caramel": "焦糖香"}.get(tag, tag)), attrs["aroma"][tag]])
	text += "香气 " + ("、".join(aromas) if not aromas.is_empty() else "尚无") + "\n"
	var texture: Dictionary = attrs.get("texture", {})
	text += "口感 嫩 %.2f / 脆 %.2f / 粘 %.2f\n" % [texture.get("A", 0), texture.get("B", 0), texture.get("C", 0)]
	for id: String in ingredients:
		if ingredients[id].get("category") == "seasoning":
			text += "%s %.0f份  " % [ingredients[id].get("name", id), ingredients[id].get("amount", 0)]
		else:
			text += "%s %s / 细碎度 %.2f  " % [ingredients[id].get("name", id), {"whole": "未切", "chunk": "大块", "dice": "小丁"}.get(ingredients[id].get("shape", "whole"), "未切"), ingredients[id].get("fine", 0.0)]
	text += "\n口味：前 / 主 / 余 / 回\n"
	var names: Array[String] = ["酸", "甜", "苦", "辣", "咸", "鲜", "麻"]
	var flavor: Array = attrs.get("flavor", [])
	for index: int in mini(flavor.size(), 7):
		text += names[index] + " " + JSON.stringify(flavor[index]) + "\n"
	return text

func _history_line(entry: Dictionary) -> String:
	var before: Dictionary = entry.get("before", {})
	var after: Dictionary = entry.get("after", {})
	if before.has("dish_attributes"): before = before["dish_attributes"]
	if after.has("dish_attributes"): after = after["dish_attributes"]
	var parameters: Dictionary = entry.get("parameters", {})
	var detail: String = str({"tomato": "番茄", "egg": "鸡蛋", "sugar": "白糖", "salt": "盐"}.get(parameters.get("ingredient_id", ""), ""))
	if parameters.has("shape"):
		detail += "·" + ("大块" if parameters["shape"] == "chunk" else "小丁")
	var text: String = "%s %s\n温度 %.1f→%.1f  Q %.1f→%.1f  H %.1f→%.1f\n" % [_operation_name(str(entry.get("operation", ""))), detail, before.get("temperature_c", 0), after.get("temperature_c", 0), before.get("completion", 0), after.get("completion", 0), before.get("harmony", 0), after.get("harmony", 0)]
	for key: String in ["aroma", "texture"]:
		if before.get(key, {}) != after.get(key, {}):
			text += ("香气 " if key == "aroma" else "口感 ") + JSON.stringify(before.get(key, {})) + " → " + JSON.stringify(after.get(key, {})) + "\n"
	var old_flavor: Array = before.get("flavor", [])
	var new_flavor: Array = after.get("flavor", [])
	var tastes: Array[String] = ["酸", "甜", "苦", "辣", "咸", "鲜", "麻"]
	for index: int in mini(old_flavor.size(), new_flavor.size()):
		if old_flavor[index] != new_flavor[index]:
			text += tastes[index] + " " + JSON.stringify(old_flavor[index]) + " → " + JSON.stringify(new_flavor[index]) + "\n"
	return text + str(entry.get("message", "")) + "\n\n"

func _operation_name(kind: String) -> String:
	return str({"add": "加入食材", "cut": "切番茄", "season": "调味", "heat": "加热", "plate": "出锅交付"}.get(kind, kind))

func _failure_message(outcome: TDOutcome) -> String:
	var messages: Dictionary = {"NO_TARGET": "先放入要处理的食材。", "ALREADY_PRESENT": "本份菜里已有这种食材。", "AMOUNT_LIMIT": "调料已达到本原型单菜允许的上限。", "BUSY": "先完成或取消当前工序。", "ALREADY_FINISHED": "这份菜已交付，请重试开始新的一份。", "COARSER_CUT": "小丁不能切回大块，请重试或继续加工。", "CANCELLED": "本次会话已结束，请重试。"}
	return str(messages.get(outcome.code, outcome.message if not outcome.message.is_empty() else "此操作当前不可用。"))
