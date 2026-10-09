class_name TDTemperatureView
extends Control
## Read-only temperature/beat HUD. Mouse is routed once by the kitchen root.
var progress: Dictionary = {}
var beat_sec: float = 0.0
var bpm: float = 120.0
var beat_only: bool = false

func _init() -> void:
	custom_minimum_size = Vector2(300, 70)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func show_progress(value: Dictionary) -> void:
	progress = value.duplicate(true); queue_redraw()

func bar_rect() -> Rect2:
	return Rect2(global_position + Vector2(12, 24), Vector2(maxf(1, size.x - 24), 24))

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("172d29"))
	var width: float = maxf(1, size.x - 24)
	if beat_only:
		var beat: float = maxf(0, beat_sec) * bpm / 60.0
		for index: int in 5:
			var x: float = 12 + width * index / 4.0
			draw_line(Vector2(x, 20), Vector2(x, 48), TDUI.ORANGE if index % 4 == 0 else TDUI.MUTED, 3 if index % 4 == 0 else 1)
		var x: float = 12 + fposmod(beat, 4) / 4 * width
		draw_circle(Vector2(x, 34), 7, TDUI.ORANGE if fposmod(beat, 4) < .15 else Color.WHITE)
		draw_string(get_theme_default_font(), Vector2(14, 65), "共用节拍  %d BPM  ·  金色为强拍" % int(bpm), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, TDUI.MUTED)
		return
	var low: float = progress.get("target_min", .4); var high: float = progress.get("target_max", .65)
	draw_rect(Rect2(12, 24, width, 24), Color("314842"))
	draw_rect(Rect2(12 + low * width, 24, (high - low) * width, 24), Color("408461"))
	var power: float = progress.get("power", .5)
	draw_circle(Vector2(12 + power * width, 36), 8, TDUI.ORANGE)
	var remaining: float = progress.get("remaining_sec", 0)
	var ratio: float = float(progress.get("inside_sec", 0)) / maxf(.0001, float(progress.get("elapsed_sec", 0)))
	draw_string(get_theme_default_font(), Vector2(14, 18), "鼠标靠近吸引 · 按住更强 · 留在绿区", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
	draw_string(get_theme_default_font(), Vector2(14, 66), "稳定 %.0f%%   剩余 %.1fs" % [ratio * 100, remaining], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, TDUI.MUTED)
