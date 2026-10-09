class_name TDCookingActionView
extends Control
## Presentation only: never advances a clock or changes cooking/QTE rules.
## Deliberately code-drawn placeholder pixel art; caller supplies QTE progress.

const BASE_SIZE := Vector2(380.0, 158.0)
const INK := Color("#f0ead1")
const MUTED := Color("#97afa9")
const ORANGE := Color("#f3b668")
const GREEN := Color("#8ed6a1")
const RED := Color("#e47266")
const DARK := Color("#132724")
const METAL := Color("#819d9b")
const TITLES := {"cut": "切菜", "preheat": "热锅点火", "stir": "翻炒搅拌", "heat": "炒制控温",
	"boil": "炖煮控温", "season": "顺序调味", "starch": "勾芡", "ferment": "发酵搅拌", "plate": "把握出锅"}
const HINTS := {"charge": "按住 · 进入绿区松开", "rhythm": "拍点到竖线时按下",
	"window": "光标进入目标区时按下", "maintain": "调节控制量 · 让实际火力留在绿区", "sequence": "按亮起的方向 · 按错可继续"}

var _operation := ""
var _progress: Dictionary = {}
var _font: SystemFont
var _pulse_at_sec := -10.0
var _last_action := ""
var _pressed := false
var _elapsed := 0.0
var _operation_id := ""

func _init() -> void:
	custom_minimum_size = BASE_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC"])

func set_progress(operation: String, progress: Dictionary) -> void:
	var next_elapsed := _finite(progress.get("elapsed_sec", 0.0), 0.0)
	var next_identity := str(progress.get("operation_id", ""))
	if next_identity != _operation_id or operation != _operation or next_elapsed < _elapsed:
		_pulse_at_sec = -10.0
		_pressed = false
		_last_action = ""
	_operation = operation
	_operation_id = next_identity
	_elapsed = maxf(0.0, next_elapsed)
	_progress = progress.duplicate(true)
	queue_redraw()

func pulse_input(action: String, pressed: bool) -> void:
	_last_action = action
	_pressed = pressed
	if pressed or str(_progress.get("qte_kind", "")) == "charge":
		_pulse_at_sec = _elapsed
	queue_redraw()

func presentation_state() -> Dictionary:
	# Small read-only diagnostic for integration/paused-render verification.
	return {"operation": _operation, "progress": _progress.duplicate(true), "elapsed_sec": _elapsed,
		"pulse": _pulse(), "last_action": _last_action, "pressed": _pressed}

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),DARK)
	var factor: float = minf(maxf(size.x,1)/BASE_SIZE.x,maxf(size.y,1)/BASE_SIZE.y)
	draw_set_transform(Vector2((size.x-BASE_SIZE.x*factor)*.5,0),0,Vector2.ONE*factor)
	draw_rect(Rect2(Vector2.ZERO, BASE_SIZE), DARK)
	draw_rect(Rect2(0.0, 0.0, 380.0, 94.0), Color("#1d3832"))
	draw_rect(Rect2(0.0, 91.0, 380.0, 3.0), Color("#456257"))
	_text(str(TITLES.get(_operation, "烹饪动作")), Vector2(12.0, 19.0), INK, 15)
	var kind := str(_progress.get("qte_kind", ""))
	var hint: String = str(HINTS.get(kind, "选择工序后开始"))
	if _progress.get("pc_module") == "M6": hint = "每拍点击材料柜 · 按实际材料调味"
	elif _progress.get("pc_module") == "M3" and kind == "sequence": hint = "一拍一键 · 最后一拍空格收势"
	_text(hint, Vector2(12.0, 108.0), MUTED, 12)
	_draw_action()
	match kind:
		"charge": _draw_charge()
		"rhythm": _draw_rhythm()
		"window": _draw_window()
		"maintain": _draw_maintain()
		"sequence": _draw_sequence()
	var status := str(_progress.get("status", ""))
	if status == "completed":
		var grade := str(_progress.get("grade", "miss"))
		_text(grade.to_upper(), Vector2(283.0, 19.0), GREEN if grade == "perfect" else ORANGE, 14)
	elif status == "cancelled":
		_text("已取消", Vector2(305.0, 19.0), RED, 13)

func _draw_action() -> void:
	match _operation:
		"cut": _draw_cut()
		"preheat":
			_draw_pan(Vector2(153.0, 59.0))
			var hold := _finite(_progress.get("held_sec", float(_progress.get("cursor",0)) * 1.4), 0.0)
			var target := maxf(0.1, _finite(_progress.get("target_min_sec", 1.2), 1.2))
			_draw_fire(Vector2(161.0, 85.0), clampf(hold / target, 0.0, 1.0))
			_pixel_rect(111.0, 62.0 - _pulse() * 6.0, 24.0, 6.0, ORANGE)
			_pixel_rect(132.0, 57.0 - _pulse() * 6.0, 7.0, 13.0, RED)
		"stir": _draw_stir()
		"heat", "boil":
			_draw_pan(Vector2(153.0, 58.0))
			_draw_food(Vector2(171.0, 57.0), 0.0)
			_draw_fire(Vector2(161.0, 85.0), _finite(_progress.get("power", 0.5), 0.5))
			_draw_steam(Vector2(175.0, 43.0), 3 if _operation == "boil" else 2)
			if _operation == "boil":
				for index in 3:
					_pixel_rect(164.0 + index * 22.0, 53.0 - fposmod(_elapsed * 11.0 + index * 4.0, 9.0), 5.0, 4.0, INK)
		"season", "ferment": _draw_sequence_action()
		"plate": _draw_plate()
		"starch": _draw_starch()
		"steam":
			_pixel_rect(143,47,90,34,Color("#b58d56"))
			for index: int in 3: _pixel_rect(147,51+index*10,82,3,Color("#745435"))
			_pixel_rect(140,39-_pulse()*9,96,9,Color("#d3b077"))
			_draw_steam(Vector2(161,39),3)
		_:
			_draw_pan(Vector2(153.0, 61.0))
			_draw_food(Vector2(171.0, 60.0), 0.0)

func _draw_cut() -> void:
	_pixel_rect(106.0, 61.0, 165.0, 22.0, Color("#b68050"))
	_pixel_rect(113.0, 65.0, 150.0, 3.0, Color("#dca56b"))
	for index in 4:
		_pixel_rect(132.0 + index * 18.0, 52.0 + float(index % 2) * 3.0, 13.0, 13.0, RED if index % 2 == 0 else ORANGE)
	var drop := _pulse() * 19.0
	var angle: float = [0.0,PI*.5,PI*.25][int(_progress.get("cut_direction",0))]
	var axis: Vector2 = Vector2.RIGHT.rotated(angle)
	var blade: Vector2 = Vector2(191,35+drop)
	draw_line(blade-axis*12,blade+axis*12,Color("#d1ded4"),12,false)
	draw_line(blade+axis*11,blade+axis*33,Color("#885847"),7,false)
	if _pulse() > 0.4:
		_pixel_rect(176.0, 55.0, 4.0, 3.0, ORANGE)
		_pixel_rect(216.0, 57.0, 4.0, 3.0, ORANGE)

func _draw_stir() -> void:
	var lift := _pulse() * 8.0
	_draw_pan(Vector2(143.0, 65.0 - lift))
	_draw_food(Vector2(161.0, 61.0 - lift), _pulse() * 22.0)
	var swing := sin(_elapsed * 5.0) * 7.0 + _pulse() * 10.0
	_pixel_rect(200.0 + swing, 34.0, 37.0, 6.0, Color("#b98959"))
	_pixel_rect(190.0 + swing, 37.0, 15.0, 14.0, ORANGE)
	_draw_fire(Vector2(151.0, 88.0), 0.55)

func _draw_sequence_action() -> void:
	_draw_pan(Vector2(156.0, 62.0))
	_draw_food(Vector2(174.0, 60.0), 0.0)
	var colors := [RED, ORANGE, GREEN, INK]
	var names := ["up", "left", "down", "right"]
	var index := names.find(_last_action)
	for item in 4:
		var pouring := item == index and _pulse() > 0.0
		var x := 112.0 + item * 38.0
		var y := 30.0 + (_pulse() * 6.0 if pouring else 0.0)
		_pixel_rect(x, y, 19.0, 19.0, colors[item])
		_pixel_rect(x + 2.0, y - 4.0, 15.0, 4.0, METAL)
		if pouring:
			for grain in 3:
				_pixel_rect(x + 6.0 + grain * 3.0, y + 23.0 + grain * 4.0, 3.0, 3.0, colors[item])
	if _operation == "ferment":
		var shift := sin(_elapsed * 4.0) * 7.0
		_pixel_rect(219.0 + shift, 46.0, 6.0, 25.0, ORANGE)

func _draw_plate() -> void:
	_pixel_rect(221.0, 74.0, 84.0, 7.0, METAL)
	_pixel_rect(216.0, 67.0, 94.0, 9.0, INK)
	var tilt := _pulse()
	var pan_origin := Vector2(106.0 + tilt * 12.0, 51.0 - tilt * 16.0)
	for part in 7:
		var segment_y := pan_origin.y + float(part) * tilt * 3.0
		_pixel_rect(pan_origin.x + part * 12.0, segment_y, 12.0, 5.0, METAL)
		_pixel_rect(pan_origin.x + part * 12.0, segment_y + 5.0, 12.0, 12.0, Color("#24322f"))
		_pixel_rect(pan_origin.x + part * 12.0, segment_y + 17.0, 12.0, 4.0, Color("#101b19"))
	_pixel_rect(pan_origin.x - 31.0, pan_origin.y + 5.0, 31.0, 7.0, Color("#a7764d"))
	_draw_food(Vector2(124.0 + tilt * 35.0, 47.0), 0.0)
	if tilt > 0.0:
		for index in 4:
			_pixel_rect(202.0 + float(index) * 14.0, 40.0 + float(index * index) * 2.0, 9.0, 7.0, RED if index % 2 == 0 else ORANGE)
	if str(_progress.get("status", "")) == "completed":
		_draw_food(Vector2(237.0, 59.0), 0.0)

func _draw_starch() -> void:
	_draw_pan(Vector2(154.0, 63.0))
	_draw_food(Vector2(172.0, 61.0), 0.0)
	_pixel_rect(132.0, 28.0, 34.0, 13.0, INK)
	_pixel_rect(137.0, 41.0, 24.0, 5.0, METAL)
	if _pulse() > 0.0:
		for index in 4:
			_pixel_rect(157.0 + index * 7.0, 43.0 + index * 5.0, 4.0, 7.0, INK)
	_draw_steam(Vector2(209.0, 44.0), 2)

func _draw_pan(origin: Vector2) -> void:
	_pixel_rect(origin.x - 4.0, origin.y, 88.0, 7.0, METAL)
	_pixel_rect(origin.x, origin.y + 7.0, 80.0, 12.0, Color("#24322f"))
	_pixel_rect(origin.x + 8.0, origin.y + 19.0, 65.0, 5.0, Color("#101b19"))
	_pixel_rect(origin.x + 80.0, origin.y + 4.0, 34.0, 7.0, Color("#a7764d"))

func _draw_food(origin: Vector2, lift: float) -> void:
	for index in 5:
		var jump := lift * (0.65 + 0.35 * sin(float(index) + 1.0))
		_pixel_rect(origin.x + index * 10.0, origin.y - jump + float(index % 2) * 4.0, 8.0, 6.0, RED if index % 2 == 0 else ORANGE)

func _draw_fire(origin: Vector2, power: float) -> void:
	for index in 5:
		var flicker := float(int(floor(_elapsed * 9.0)) + index) * 1.7
		var height := 4.0 + clampf(power, 0.0, 1.0) * 13.0 + sin(flicker) * 2.0
		_pixel_rect(origin.x + index * 13.0, origin.y - height, 8.0, height, RED)
		_pixel_rect(origin.x + index * 13.0 + 2.0, origin.y - height * 0.65, 4.0, height * 0.65, ORANGE)

func _draw_steam(origin: Vector2, count: int) -> void:
	for index in count:
		var rise := fposmod(_elapsed * 13.0 + index * 5.0, 19.0)
		_pixel_rect(origin.x + index * 18.0 + sin(_elapsed * 2.0 + index) * 3.0, origin.y - rise, 4.0, 7.0, MUTED)

func _draw_charge() -> void:
	var low := _finite(_progress.get("target_min_sec", 1.2), 1.2)
	var high := _finite(_progress.get("target_max_sec", 1.6), 1.6)
	var maximum := maxf(0.1, high * 1.5)
	_bar(20.0, 126.0, 245.0, low / maximum, high / maximum)
	var held := _finite(_progress.get("held_sec", 0.0), 0.0)
	_marker(20.0 + clampf(held / maximum, 0.0, 1.0) * 245.0, 122.0, INK)
	_text("%.2f 秒" % held, Vector2(282.0, 137.0), ORANGE, 14)
	_text("目标 %.1f–%.1f 秒" % [low, high], Vector2(20.0, 153.0), MUTED, 11)

func _draw_rhythm() -> void:
	_pixel_rect(20.0, 127.0, 341.0, 5.0, Color("#405e54"))
	_pixel_rect(126.0, 116.0, 4.0, 27.0, INK)
	var beats: Array = _progress.get("beat_times_sec", [])
	var judgements: Array = _progress.get("judgements", [])
	for index in beats.size():
		var x := 128.0 + (_finite(beats[index], 0.0) - _elapsed) * 82.0
		if x < 22.0 or x > 354.0:
			continue
		var judgement := str(judgements[index]) if index < judgements.size() else "pending"
		var color := ORANGE if judgement == "pending" else (RED if judgement == "miss" else GREEN)
		_pixel_rect(x - 5.0, 121.0, 11.0, 15.0, color)
	if _pulse() > 0.0:
		_pixel_rect(122.0, 119.0, 12.0, 20.0, Color(1.0, 1.0, 1.0, _pulse() * 0.5))
	_text("连击 %d  /  命中 %d" % [int(_progress.get("combo", 0)), int(_progress.get("hits", 0))], Vector2(20.0, 153.0), MUTED, 11)

func _draw_window() -> void:
	var duration := maxf(0.1, _finite(_progress.get("duration_sec", 2.5), 2.5))
	var target := _finite(_progress.get("target_sec", 1.8), 1.8)
	var good := _finite(_progress.get("good_sec", 0.14), 0.14)
	var perfect := _finite(_progress.get("perfect_sec", 0.06), 0.06)
	if _progress.get("pc_module") == "M2":
		var period: float = target * 4
		var half: float = .45 * sin(TAU * good / period)
		_bar(20,126,340,.5-half,.5+half)
		_marker(20 + float(_progress.get("cursor",.5))*340,122,INK)
		_text("冷 ←    强拍到绿区：空格点火    → 热",Vector2(20,153),MUTED,11)
		return
	_bar(20.0, 126.0, 340.0, (target - good) / duration, (target + good) / duration)
	_pixel_rect(20.0 + (target - perfect) / duration * 340.0, 126.0, perfect * 2.0 / duration * 340.0, 10.0, GREEN)
	_marker(20.0 + clampf(_elapsed / duration, 0.0, 1.0) * 340.0, 122.0, INK)
	_text("目标 %.2f 秒   Perfect ±%dms" % [target, int(round(perfect * 1000.0))], Vector2(20.0, 153.0), MUTED, 11)

func _draw_maintain() -> void:
	var low := _finite(_progress.get("target_min", 0.4), 0.4)
	var high := _finite(_progress.get("target_max", 0.7), 0.7)
	var power := _finite(_progress.get("power", 0.5), 0.5)
	var control := _finite(_progress.get("control", 0.5), 0.5)
	_bar(20.0, 126.0, 245.0, low, high)
	_marker(20.0 + clampf(power, 0.0, 1.0) * 245.0, 121.0, INK)
	_pixel_rect(20.0 + clampf(control, 0.0, 1.0) * 245.0 - 3.0, 140.0, 6.0, 4.0, ORANGE)
	_text("实际 %d%%" % int(round(power * 100.0)), Vector2(278.0, 138.0), INK, 13)
	_text("橙标：控制量    白线：扰动后的实际火力", Vector2(20.0, 155.0), MUTED, 10)

func _draw_sequence() -> void:
	var steps: Array = _progress.get("sequence", [])
	var current := int(_progress.get("sequence_index", 0))
	if current < 0: current = steps.size()
	var count := mini(steps.size(), 8)
	var start_index := clampi(current - 2, 0, maxi(0, steps.size() - count))
	for index in count:
		var step_index := start_index + index
		var center := Vector2(36.0 + index * 39.0, 132.0)
		var color := GREEN if step_index < current else (ORANGE if step_index == current else MUTED)
		if step_index == current:
			_pixel_rect(center.x - 16.0, center.y - 15.0, 32.0, 29.0, Color("#48694f"))
		var action: String = str(steps[step_index])
		if action == "primary": _text("空格",center+Vector2(-15,5),color,12)
		elif action.begins_with("spice:"): _text({"spice:salt":"盐","spice:sugar":"糖","spice:oil":"油","spice:starch":"粉"}.get(action,"?"),center+Vector2(-7,5),color,14)
		else: _draw_arrow(center, action, color)
		var beats: Array = _progress.get("beat_times_sec",[])
		if step_index < beats.size() and step_index == current:
			var to_beat: float = float(beats[step_index]) - _elapsed
			draw_arc(center,maxf(16,16+absf(to_beat)*20),0,TAU,24,ORANGE,1)
	_text("%d/%d  错键 %d" % [current, steps.size(), int(_progress.get("wrong", 0))], Vector2(20.0, 156.0), MUTED, 10)

func _draw_arrow(center: Vector2, action: String, color: Color) -> void:
	var direction := Vector2.UP
	match action:
		"left": direction = Vector2.LEFT
		"down": direction = Vector2.DOWN
		"right": direction = Vector2.RIGHT
	var side := Vector2(-direction.y, direction.x)
	var tip := center + direction * 9.0
	draw_line(center - direction * 9.0, tip, color, 4.0, false)
	draw_line(tip, center + side * 8.0, color, 4.0, false)
	draw_line(tip, center - side * 8.0, color, 4.0, false)

func _bar(x: float, y: float, width: float, low: float, high: float) -> void:
	_pixel_rect(x, y, width, 10.0, Color("#3e514b"))
	_pixel_rect(x + clampf(low, 0.0, 1.0) * width, y, maxf(0.0, high - low) * width, 10.0, Color("#497e55"))

func _marker(x: float, y: float, color: Color) -> void:
	_pixel_rect(x - 2.0, y, 4.0, 18.0, color)

func _pixel_rect(x: float, y: float, width: float, height: float, color: Color) -> void:
	draw_rect(Rect2(roundf(x), roundf(y), maxf(1.0, roundf(width)), maxf(1.0, roundf(height))), color)

func _text(value: String, position: Vector2, color: Color, font_size: int) -> void:
	draw_string(_font, position, value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)

func _pulse() -> float:
	return clampf(1.0 - maxf(0.0, _elapsed - _pulse_at_sec) / 0.18, 0.0, 1.0)

func _finite(value: Variant, fallback: float) -> float:
	return float(value) if (value is float or value is int) and is_finite(float(value)) else fallback
