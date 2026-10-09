class_name TDDevelopmentKitchen
extends Control

signal back_requested
signal pause_requested
signal restart_requested
signal result_displayed(result: TDOutcome)

var catalog: TDCatalog
var clock: TDClock
var random_source: RefCounted
var scorer: TDCustomerScorer
var session_id: String
var generation: int
var show_debug: bool = false
var session: TDCookingSession
var probe: TDHoldProbe
var automatic_time: bool = true

var _input_sequence: int = 0
var _closed: bool = false
var _result_count: int = 0
var _last_result: Dictionary = {}
var _template: TDTemplate
var _status: Label
var _metrics: Label
var _result_label: Label
var _progress: ProgressBar
var _debug: RichTextLabel
var _start_button: Button
var _hold_button: Button
var _paused: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	if catalog == null or clock == null or random_source == null or scorer == null:
		_status.text = "入口未装配依赖，无法开始。"
		_start_button.disabled = true
		return
	_template = catalog.get_template(str(catalog.ids()[0]))
	session = TDCookingSession.new(session_id, generation, _template)
	session.result_ready.connect(_on_result)
	_render()

func start_operation() -> TDOutcome:
	if _closed or _paused or session == null:
		return TDOutcome.new(false, "UNAVAILABLE")
	var request := TDRequest.new(session_id, generation, "hold-1", "probe_hold", 0)
	var outcome := session.begin(request)
	if outcome.ok:
		probe = TDHoldProbe.new(request, _template, clock, random_source)
		_hold_button.disabled = false
		_start_button.disabled = true
	_render()
	return outcome

func _process(delta: float) -> void:
	if automatic_time:
		advance_time(delta)

func advance_time(delta: float) -> void:
	if _closed or clock == null:
		return
	if not clock.advance(delta):
		return
	if not _paused and probe != null:
		var frame := probe.advance()
		if frame != null:
			var outcome := session.accept(frame)
			if not outcome.ok:
				_result_label.text = "操作被拒绝：" + outcome.code
				print(JSON.stringify({"event": "operation_rejected", "code": outcome.code}))
	_render()

func _input(event: InputEvent) -> void:
	if _closed:
		return
	if event.is_action_pressed("pause") and not event.is_echo():
		pause_requested.emit()
		get_viewport().set_input_as_handled()
		return
	if _paused:
		return
	if event.is_action_pressed("restart_probe") and not event.is_echo():
		restart_requested.emit()
		get_viewport().set_input_as_handled()
		return
	if event.is_action("probe_hold") and not event.is_echo():
		route_strength(event.get_action_strength("probe_hold"))
		get_viewport().set_input_as_handled()

func route_strength(strength: float) -> TDOutcome:
	if _closed or _paused or probe == null:
		return TDOutcome.new(false, "UNAVAILABLE")
	_input_sequence += 1
	return probe.input(TDInput.new(session_id, generation, "hold-1", _input_sequence, clock.qte_sec, strength))

func set_paused(value: bool) -> void:
	_paused = value
	clock.paused = value
	if probe != null:
		probe.release_input()
	_start_button.disabled = value or session.snapshot().to_dict()["state"] != "ready"
	_hold_button.disabled = value or probe == null or session.snapshot().to_dict()["state"] != "running"
	_render()

func close() -> void:
	if _closed:
		return
	_closed = true
	if probe != null:
		probe.cancel()
	if session != null:
		if session.result_ready.is_connected(_on_result):
			session.result_ready.disconnect(_on_result)
		session.cancel()
	set_process(false)
	set_process_input(false)
	clock.paused = false

func result_count() -> int:
	return _result_count

func last_result() -> Dictionary:
	return _last_result.duplicate(true)

func _exit_tree() -> void:
	close()

func _on_result(result: TDOutcome) -> void:
	if _closed:
		return
	_result_count += 1
	_last_result = result.to_dict()
	var scoring := scorer.evaluate(session.snapshot().to_dict(), {})
	_last_result["scoring"] = scoring.to_dict()
	_hold_button.disabled = true
	_result_label.text = "操作完成，可以重新开始。" if result.code == "COMPLETED" else "本次等待超时，可以重新开始。"
	_result_label.text += "\n菜品评分尚未实现，本样例只记录真实输入与处理量。"
	print(JSON.stringify({"event": "operation_result", "session_id": session_id, "code": result.code}))
	result_displayed.emit(result)

func _render() -> void:
	if session == null:
		return
	var values := session.snapshot().to_dict()
	var state: String = values["state"]
	var names := {"ready": "准备就绪", "running": "正在操作", "completed": "已完成", "timed_out": "已超时", "cancelled": "已取消"}
	_status.text = "已暂停 · 再按 Esc 恢复" if _paused else str(names.get(state, state))
	var target: float = probe.target_sec if probe != null else 0.0
	_metrics.text = "已按住 %.2f 秒  /  目标 %.2f 秒     处理量 %.2f 单位\n游戏时间 %.2f 秒     操作时间 %.2f 秒" % [values["held_sec"], target, values["work_units"], clock.game_sec, values["elapsed_sec"]]
	_progress.value = clampf(float(values["held_sec"]) / target * 100.0, 0.0, 100.0) if target > 0 else 0
	_debug.visible = show_debug
	if show_debug:
		_debug.text = JSON.stringify({"snapshot": values, "result": _last_result}, "  ")

func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	add_child(margin)
	var column := TDUI.column(margin, 12)
	var nav := HBoxContainer.new()
	column.add_child(nav)
	nav.add_child(TDUI.button("← 返回主界面", func() -> void: back_requested.emit()))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav.add_child(spacer)
	nav.add_child(TDUI.button("暂停 / 恢复  Esc", func() -> void: pause_requested.emit()))
	column.add_child(TDUI.label("开发厨房", 34))
	column.add_child(TDUI.label("连续输入样例 · 开发专用", 18, TDUI.ORANGE))
	column.add_child(TDUI.label("点击开始，然后长按空格或下方按钮。松开会停止处理；6 秒内达到目标即可完成。", 18, TDUI.MUTED))
	_status = TDUI.label("正在准备", 24)
	column.add_child(_status)
	_progress = ProgressBar.new()
	_progress.custom_minimum_size.y = 28
	column.add_child(_progress)
	_metrics = TDUI.label("", 19)
	column.add_child(_metrics)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 14)
	column.add_child(actions)
	_start_button = TDUI.button("开始样例", start_operation)
	actions.add_child(_start_button)
	_hold_button = TDUI.button("按住进行处理  Space", func() -> void: pass)
	_hold_button.disabled = true
	_hold_button.button_down.connect(func() -> void: route_strength(1.0))
	_hold_button.button_up.connect(func() -> void: route_strength(0.0))
	actions.add_child(_hold_button)
	actions.add_child(TDUI.button("重新开始  R", func() -> void: restart_requested.emit()))
	_result_label = TDUI.label("此样例验证输入与模块协作，不代表完整做菜玩法。", 18, TDUI.MUTED)
	column.add_child(_result_label)
	_debug = RichTextLabel.new()
	_debug.custom_minimum_size.y = 160
	_debug.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_debug.selection_enabled = true
	_debug.add_theme_font_size_override("normal_font_size", 14)
	column.add_child(_debug)
