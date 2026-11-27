extends Control

const FONT_SIZE := 24
const SIDE_GUTTER := 33.0
const INSET := 12.0
const HUD_BOTTOM := 86.0
const INK := Color("#fff4dd")
const CHEVRON := [Vector2(-4, -7), Vector2(2, -7), Vector2(8, 0),
	Vector2(2, 7), Vector2(-4, 7), Vector2(2, 0)]

var _font: Font
var _title := ""
var _title_width := 0.0
var _facade := Rect2()
var _world_anchor := Vector2.ZERO

func _ready() -> void:
	name = "BuildingNameplate"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = TDUI.font()
	hide()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.015, 0.012, 0.013, 0.57))
	_draw_chevron(19.0, 1.0)
	_draw_chevron(size.x - 19.0, -1.0)
	var baseline := (size.y - _font.get_height(FONT_SIZE)) * 0.5 + _font.get_ascent(FONT_SIZE)
	draw_string(_font, Vector2(SIDE_GUTTER, baseline), _title, HORIZONTAL_ALIGNMENT_CENTER,
		size.x - 2.0 * SIDE_GUTTER, FONT_SIZE, INK)

func _draw_chevron(x: float, direction: float) -> void:
	var center := Vector2(x, size.y * 0.5)
	var points := PackedVector2Array()
	for point: Vector2 in CHEVRON:
		points.append(center + Vector2(point.x * direction, point.y))
	draw_colored_polygon(points, Color("#f5d9a1"))

func track(world: CanvasItem, bounds: Rect2, title: String) -> void:
	var viewport := world.get_viewport_rect().grow(-INSET)
	if title.is_empty() or not bounds.has_area():
		hide()
		return
	var projection := world.get_global_transform_with_canvas()
	var on_screen := projection * bounds
	if _title != title:
		_title = title
		_title_width = ceilf(_font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x)
		queue_redraw()
	var final_size := Vector2(minf(_title_width + 2.0 * SIDE_GUTTER, viewport.size.x), _font.get_height(FONT_SIZE) + 10.0)
	if size != final_size:
		size = final_size
		queue_redraw()
	if not visible or _facade != bounds:
		if not on_screen.intersects(viewport):
			hide()
			return
		_facade = bounds
		# Pick a position once per visit. Keep it attached to the same roof or
		# upper facade as the camera scrolls, even when the edges are cropped.
		var top := on_screen.position.y - size.y - 8.0
		if top < HUD_BOTTOM:
			top = clampf(HUD_BOTTOM, on_screen.position.y + 8.0, maxf(on_screen.position.y + 8.0, on_screen.end.y - size.y))
		var center_x := on_screen.get_center().x
		if center_x < viewport.position.x or center_x > viewport.end.x:
			center_x = on_screen.intersection(viewport).get_center().x
		_world_anchor = projection.affine_inverse() * Vector2(center_x, top)
	var projected := projection * _world_anchor
	position = (projected - Vector2(size.x * 0.5, 0.0)).round()
	show()
