extends CanvasLayer

signal morning
signal finished

const PAPER := Color("#f8ead3")
const MUTED := Color("#c5b49e")
const GOLD := Color("#ffc96c")
const FADE := 0.38

var _black: ColorRect
var _message: CenterContainer
var _summary: CenterContainer
var _values: Array[Label] = []
var _level: Label
var _bar: ProgressBar
var _bar_text: Label
var _promotion: Label
var _continue: Button
var _ready_to_leave := false

func present(report: Dictionary, progression: TDLevelProgression) -> void:
	layer = 1000
	process_mode = Node.PROCESS_MODE_ALWAYS
	_black = ColorRect.new()
	_black.color = Color.BLACK
	_black.modulate.a = 0.0
	add_child(_black)
	_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_message = _center()
	_message.add_child(_line("你睡下了，等候明天的到来。", 30, PAPER))
	_make_summary(int(report.day))
	var start_xp := int(report.xp_before)
	var end_xp := int(report.xp_after)
	var level := progression.level_for(start_xp)
	_show_xp(start_xp, level, progression)

	var fade := create_tween()
	fade.tween_property(_black, "modulate:a", 1.0, FADE)
	fade.tween_property(_message, "modulate:a", 1.0, FADE)
	fade.tween_interval(1.0)
	fade.tween_property(_message, "modulate:a", 0.0, FADE)
	fade.tween_callback(_message.hide)
	fade.tween_property(_summary, "modulate:a", 1.0, FADE)
	await fade.finished

	var gains: Array[float] = [
		float(report.profit_cents) / 100.0,
		float(report.popularity_delta),
		float(report.awareness_delta),
		float(report.xp_after) - float(report.xp_before),
	]
	var tally := create_tween()
	for row: int in range(3):
		tally.tween_method(_show_gain.bind(row), 0.0, gains[row], 0.40).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await tally.finished

	var target_level := progression.level_for(end_xp)
	while level < target_level:
		var threshold := progression.threshold(level + 1)
		await _animate_xp(start_xp, threshold, int(report.xp_before), level, progression, gains[3])
		level += 1
		start_xp = threshold
		_show_xp(start_xp, level, progression)
		await _announce_level(level)
	await _animate_xp(start_xp, end_xp, int(report.xp_before), level, progression, gains[3])
	_ready_to_leave = true
	_continue.show()
	_continue.grab_focus()

func _center() -> CenterContainer:
	var panel := CenterContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.modulate.a = 0.0
	_black.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return panel

func _make_summary(day: int) -> void:
	_summary = _center()
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 410
	column.add_theme_constant_override("separation", 11)
	_summary.add_child(column)
	var heading := _line("第 %d 天结算" % day, 30, PAPER)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(heading)
	for entry: Array in [
		["¥", "净收入", GOLD],
		["♥", "人气增长", Color("#ff9894")],
		["★", "名气增长", Color("#f9ce7a")],
		["↑", "经验增长", Color("#a9db9a")],
	]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		column.add_child(row)
		var icon := _line(entry[0], 24, entry[2])
		icon.custom_minimum_size.x = 30
		icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(icon)
		var caption := _line(entry[1], 22, PAPER)
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(caption)
		var amount := _line("", 23, entry[2])
		amount.custom_minimum_size.x = 150
		amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(amount)
		_values.append(amount)
		_show_gain(0.0, _values.size() - 1)

	var progress_header := HBoxContainer.new()
	column.add_child(progress_header)
	_level = _line("", 18, PAPER)
	_level.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress_header.add_child(_level)
	_bar_text = _line("", 18, MUTED)
	progress_header.add_child(_bar_text)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size.y = 15
	_bar.add_theme_stylebox_override("background", _track(Color("#332a24")))
	_bar.add_theme_stylebox_override("fill", _track(GOLD))
	column.add_child(_bar)
	_promotion = _line(" ", 24, GOLD)
	_promotion.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_promotion)
	_promotion.modulate.a = 0.0
	var footer := CenterContainer.new()
	footer.custom_minimum_size.y = 44
	column.add_child(footer)
	_continue = TDUI.button("迎接新的一天", continue_morning)
	_continue.custom_minimum_size.x = 220
	_continue.focus_mode = Control.FOCUS_ALL
	_continue.theme = TDUI.theme()
	footer.add_child(_continue)
	_continue.hide()

func _line(words: String, size: int, color: Color) -> Label:
	var label := TDUI.label(words, size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	return label

func _track(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(5)
	return style

func _show_gain(value: float, row: int) -> void:
	match row:
		0: _values[row].text = "%s¥%.2f" % ["−" if value < 0 else "+", absf(value)]
		1: _values[row].text = "%+.2f" % value
		2: _values[row].text = "%+.2f%%" % value
		3: _values[row].text = "+%d XP" % roundi(value)

func _show_xp(total: float, level: int, progression: TDLevelProgression) -> void:
	var needed := 0 if level >= int(progression.config.max_level) else progression.required_xp(level)
	var current := clampf(total - progression.threshold(level), 0.0, float(needed))
	_level.text = "Lv. %d" % level
	_bar.max_value = maxi(1, needed)
	_bar.value = current if needed > 0 else 1.0
	_bar_text.text = "%d / %d XP" % [roundi(current), needed] if needed > 0 else "已达最高等级"

func _animate_xp(from_xp: int, to_xp: int, initial: int, level: int, progression: TDLevelProgression, gain: float) -> void:
	if from_xp == to_xp: return
	var duration := clampf(.25 + 1.05 * float(to_xp - from_xp) / maxf(gain, 1.0), .28, 1.3)
	var motion := create_tween()
	motion.tween_method(func(total: float) -> void:
		_show_gain(total - initial, 3)
		_show_xp(total, level, progression)
	, float(from_xp), float(to_xp), duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await motion.finished

func _announce_level(level: int) -> void:
	_promotion.text = "升级！ Lv. %d" % level
	_promotion.pivot_offset = _promotion.size / 2.0
	_promotion.scale = Vector2.ONE * .86
	var pulse := create_tween().set_parallel(true)
	pulse.tween_property(_promotion, "modulate:a", 1.0, .17)
	pulse.tween_property(_promotion, "scale", Vector2.ONE, .24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pulse.chain().tween_interval(.48)
	pulse.chain().tween_property(_promotion, "modulate:a", 0.0, .24)
	await pulse.finished

func continue_morning() -> void:
	if not _ready_to_leave: return
	_ready_to_leave = false
	_continue.disabled = true
	var fade := create_tween()
	fade.tween_property(_summary, "modulate:a", 0.0, FADE)
	fade.tween_callback(morning.emit)
	fade.tween_property(_black, "modulate:a", 0.0, FADE)
	await fade.finished
	finished.emit()
	queue_free()
