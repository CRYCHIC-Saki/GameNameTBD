class_name TDCookingBoard
extends Control

## Code-drawn placeholder; no claim to final art direction.
var values: Dictionary = {}
var beat_fraction: float = 0.0
var active_kind: String = ""
var beat_times: Array = []
var elapsed_sec: float = 0.0

func _ready() -> void:
	custom_minimum_size = Vector2(400, 115)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var area := Rect2(Vector2.ZERO, size)
	draw_style_box(_panel(Color("#294842")), area)
	var center := Vector2(size.x * 0.50, 55)
	draw_circle(center, 48, Color("#152a2b"))
	draw_arc(center, 49, 0, TAU, 48, Color("#83a299"), 3)
	draw_line(center + Vector2(49, 0), center + Vector2(100, 12), Color("#83a299"), 10)
	var ingredients: Dictionary = values.get("ingredients", {})
	if ingredients.has("egg"):
		for offset: Vector2 in [Vector2(-25, 12), Vector2(8, 28), Vector2(28, -14)]:
			draw_circle(center + offset * 0.7, 15, Color("#efcf72"))
	if ingredients.has("tomato"):
		var fine: float = float(ingredients["tomato"].get("fine", 0.0))
		var count: int = 12 if fine > 0.5 else 4
		for index: int in count:
			var point := center + Vector2(cos(index * 2.4), sin(index * 2.4)) * (14.0 + index % 3 * 8.0)
			draw_rect(Rect2(point - Vector2.ONE * 7, Vector2.ONE * (10 if fine > 0.5 else 22)), Color("#dd7051"))
	if active_kind == "cut":
		var target_x: float = 55.0
		draw_line(Vector2(target_x, 75), Vector2(target_x, 110), Color("#edb76a"), 4)
		for beat: float in beat_times:
			var x: float = target_x + (beat - elapsed_sec) * 180.0
			if x >= 8.0 and x <= size.x - 8.0:
				draw_circle(Vector2(x, 94), 9.0, Color("#f1eed5"))
	if active_kind == "heat":
		draw_arc(center, 52, 0.2, PI - 0.2, 30, Color("#ec9c54"), 5)

func _panel(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(12)
	return style
