class_name TDIngredientIcon
extends Control
var item_id: String = ""

static func make(id: String, side: int = 36) -> TDIngredientIcon:
	var icon:=TDIngredientIcon.new();icon.item_id=id
	icon.custom_minimum_size=Vector2(side,side);icon.mouse_filter=Control.MOUSE_FILTER_IGNORE
	icon.size_flags_vertical=Control.SIZE_SHRINK_CENTER;icon.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
	return icon

func _draw() -> void:
	draw_on(self, item_id, Rect2(Vector2.ZERO, size))

static func draw_on(canvas: CanvasItem, item_id: String, rect: Rect2, muted: bool = false) -> void:
	if rect.size.x < 4.0 or rect.size.y < 4.0:
		return
	if muted:
		_bottle(canvas,rect,Color("71766d"),Color("494f49"),Color("9b9d93"));return
	match item_id:
		"salt":
			_salt(canvas, rect)
		"peanut_oil", "oil":
			_bottle(canvas, rect, Color(0.93, 0.72, 0.22), Color(0.45, 0.28, 0.08), Color(0.98, 0.86, 0.45))
		"sugar":
			_sugar(canvas, rect)
		"soy_sauce":
			_bottle(canvas, rect, Color(0.16, 0.08, 0.06), Color(0.08, 0.05, 0.04), Color(0.72, 0.16, 0.14))
		"shanxi_vinegar", "vinegar", "wine":
			_bottle(canvas, rect, Color(0.42, 0.22, 0.1), Color(0.72, 0.55, 0.18), Color(0.12, 0.08, 0.06))
		"star_anise":
			_star(canvas, rect, Color(0.45, 0.24, 0.12), 8)
		"cinnamon":
			_cinnamon(canvas, rect)
		"peppercorn", "pepper":
			_peppercorn(canvas, rect)
		"tomato":
			_tomato(canvas, rect)
		"potato":
			_potato(canvas, rect)
		"cabbage":
			_cabbage(canvas, rect)
		"pork":
			_chop(canvas, rect, Color(0.95, 0.64, 0.62), 0.18)
		"beef":
			_steak(canvas, rect)
		"mutton":
			_chop(canvas, rect, Color(0.62, 0.22, 0.24), 0.34)
		"fish":
			_fish(canvas, rect)
		"egg":
			_egg(canvas, rect)
		"milk":
			_milk(canvas, rect)
		"offal":
			_offal(canvas, rect)
		"watermelon":
			_watermelon(canvas, rect)
		"lemon":
			_lemon(canvas, rect)
		"chicken":
			_chop(canvas,rect,Color("e5ba82"),.24)
		"chili":
			canvas.draw_colored_polygon(PackedVector2Array([_at(rect,.25,.2),_at(rect,.7,.3),_at(rect,.58,.65),_at(rect,.25,.9),_at(rect,.4,.55)]),Color("cf543c"))
			canvas.draw_line(_at(rect,.45,.25),_at(rect,.6,.1),Color("6e9c52"),4)
		"mushroom":
			canvas.draw_rect(Rect2(_at(rect,.43,.4),rect.size*Vector2(.18,.42)),Color("f0d8ac"))
			_ellipse(canvas,rect,.5,.36,.34,.21,Color("a36d43"))
		"rice", "noodles":
			_ellipse(canvas,rect,.5,.64,.35,.2,Color("648e80"))
			for i: int in 5:
				canvas.draw_line(_at(rect,.25+i*.1,.42),_at(rect,.29+i*.1,.6 if item_id=="noodles" else .49),Color("eddbab"),4)
		"tofu":
			canvas.draw_rect(Rect2(_at(rect,.2,.3),rect.size*Vector2(.6,.45)),Color("e9dab6"))
			canvas.draw_line(_at(rect,.5,.3),_at(rect,.5,.75),Color("a6987b"),2)
		"bean_paste":
			_bottle(canvas,rect,Color("9b4533"),Color("6f3d27"),Color("e5ba72"))
		"starch":
			canvas.draw_rect(Rect2(_at(rect,.24,.2),rect.size*Vector2(.52,.63)),Color("dacda8"))
			canvas.draw_rect(Rect2(_at(rect,.28,.38),rect.size*Vector2(.44,.15)),Color("759a85"))
		"scallion":
			for i: int in 3: canvas.draw_line(_at(rect,.3+i*.13,.78),_at(rect,.22+i*.18,.17),Color("73a45a"),4)
		"garlic":
			for i: int in 3: _ellipse(canvas,rect,.35+i*.15,.57,.13,.23,Color("e1cfaa"))
		"ginger", "peanut":
			for i: int in 3: _ellipse(canvas,rect,.3+i*.19,.5+float(i%2)*.17,.15,.18,Color("ba8c4e") if item_id=="ginger" else Color("b17c55"))
		_:
			_ellipse(canvas, rect, 0.5, 0.5, 0.28, 0.28, Color(0.75, 0.82, 0.9))

static func _at(rect: Rect2, x: float, y: float) -> Vector2:
	return rect.position + Vector2(rect.size.x * x, rect.size.y * y)

static func _ellipse(canvas: CanvasItem, rect: Rect2, cx: float, cy: float, rx: float, ry: float, color: Color) -> void:
	var points := PackedVector2Array()
	var center := _at(rect, cx, cy)
	var scale := Vector2(rect.size.x * rx, rect.size.y * ry)
	for step in 18:
		var angle := TAU * float(step) / 18.0
		points.append(center + Vector2(cos(angle) * scale.x, sin(angle) * scale.y))
	canvas.draw_colored_polygon(points, color)

static func _salt(canvas: CanvasItem, rect: Rect2) -> void:
	var body := Color(0.96, 0.97, 0.99)
	canvas.draw_rect(Rect2(_at(rect, 0.3, 0.36), Vector2(rect.size.x * 0.4, rect.size.y * 0.46)), body)
	_ellipse(canvas, rect, 0.5, 0.36, 0.2, 0.1, body)
	canvas.draw_rect(Rect2(_at(rect, 0.34, 0.18), Vector2(rect.size.x * 0.32, rect.size.y * 0.12)), Color(0.55, 0.6, 0.66))
	for hole in 3:
		canvas.draw_circle(_at(rect, 0.4 + float(hole) * 0.1, 0.46), rect.size.x * 0.025, Color(0.35, 0.4, 0.48))

static func _bottle(canvas: CanvasItem, rect: Rect2, glass: Color, cap: Color, band: Color) -> void:
	_ellipse(canvas, rect, 0.5, 0.64, 0.22, 0.24, glass)
	canvas.draw_rect(Rect2(_at(rect, 0.42, 0.28), Vector2(rect.size.x * 0.16, rect.size.y * 0.22)), glass)
	canvas.draw_rect(Rect2(_at(rect, 0.4, 0.16), Vector2(rect.size.x * 0.2, rect.size.y * 0.12)), cap)
	canvas.draw_rect(Rect2(_at(rect, 0.32, 0.56), Vector2(rect.size.x * 0.36, rect.size.y * 0.1)), band)

static func _sugar(canvas: CanvasItem, rect: Rect2) -> void:
	var pale := Color(0.98, 0.98, 0.96)
	var shade := Color(0.86, 0.88, 0.9)
	_diamond(canvas, rect, 0.38, 0.58, 0.14, 0.16, shade)
	_diamond(canvas, rect, 0.62, 0.6, 0.14, 0.16, pale)
	_diamond(canvas, rect, 0.5, 0.38, 0.15, 0.16, Color.WHITE)

static func _diamond(canvas: CanvasItem, rect: Rect2, cx: float, cy: float, rx: float, ry: float, color: Color) -> void:
	canvas.draw_colored_polygon(PackedVector2Array([
		_at(rect, cx, cy - ry), _at(rect, cx + rx, cy), _at(rect, cx, cy + ry), _at(rect, cx - rx, cy),
	]), color)

static func _star(canvas: CanvasItem, rect: Rect2, color: Color, points: int) -> void:
	var poly := PackedVector2Array()
	var center := _at(rect, 0.5, 0.52)
	for step in points * 2:
		var radius := 0.4 if step % 2 == 0 else 0.18
		var angle := -PI * 0.5 + TAU * float(step) / float(points * 2)
		poly.append(center + Vector2(cos(angle) * rect.size.x * radius, sin(angle) * rect.size.y * radius))
	canvas.draw_colored_polygon(poly, color)
	canvas.draw_circle(center, rect.size.x * 0.06, color.darkened(0.35))

static func _cinnamon(canvas: CanvasItem, rect: Rect2) -> void:
	var bark := Color(0.62, 0.38, 0.18)
	canvas.draw_line(_at(rect, 0.22, 0.72), _at(rect, 0.7, 0.28), bark, maxf(3.0, rect.size.x * 0.12))
	canvas.draw_line(_at(rect, 0.34, 0.78), _at(rect, 0.82, 0.36), Color(0.78, 0.52, 0.26), maxf(3.0, rect.size.x * 0.1))

static func _peppercorn(canvas: CanvasItem, rect: Rect2) -> void:
	var spots: Array[Vector2] = [Vector2(0.38, 0.42), Vector2(0.58, 0.38), Vector2(0.48, 0.58), Vector2(0.68, 0.56), Vector2(0.32, 0.64)]
	var tones: Array[Color] = [Color(0.38, 0.14, 0.12), Color(0.52, 0.18, 0.14), Color(0.28, 0.1, 0.08), Color(0.62, 0.28, 0.16), Color(0.44, 0.16, 0.12)]
	for index in spots.size():
		var spot: Vector2 = spots[index]
		canvas.draw_circle(_at(rect, spot.x, spot.y), rect.size.x * 0.11, tones[index])

static func _tomato(canvas: CanvasItem, rect: Rect2) -> void:
	_ellipse(canvas, rect, 0.5, 0.58, 0.3, 0.28, Color(0.84, 0.18, 0.16))
	_ellipse(canvas, rect, 0.4, 0.48, 0.06, 0.04, Color(1, 0.45, 0.38, 0.7))
	_star(canvas, Rect2(rect.position + Vector2(rect.size.x * 0.28, rect.size.y * 0.02), rect.size * 0.44), Color(0.28, 0.62, 0.28), 5)

static func _potato(canvas: CanvasItem, rect: Rect2) -> void:
	_ellipse(canvas, rect, 0.5, 0.54, 0.32, 0.24, Color(0.78, 0.58, 0.3))
	for eye: Vector2 in [Vector2(0.38, 0.48), Vector2(0.58, 0.6), Vector2(0.48, 0.4)]:
		canvas.draw_circle(_at(rect, eye.x, eye.y), rect.size.x * 0.03, Color(0.35, 0.22, 0.1))

static func _cabbage(canvas: CanvasItem, rect: Rect2) -> void:
	_ellipse(canvas, rect, 0.5, 0.54, 0.32, 0.3, Color(0.55, 0.75, 0.38))
	_ellipse(canvas, rect, 0.5, 0.54, 0.2, 0.18, Color(0.74, 0.88, 0.5))
	_ellipse(canvas, rect, 0.5, 0.54, 0.08, 0.08, Color(0.9, 0.95, 0.7))

static func _chop(canvas: CanvasItem, rect: Rect2, meat: Color, bone: float) -> void:
	_ellipse(canvas, rect, 0.42, 0.58, 0.24, 0.22, meat)
	canvas.draw_line(_at(rect, 0.55, 0.48), _at(rect, 0.55 + bone, 0.48 - bone), Color(0.94, 0.92, 0.86), maxf(3.0, rect.size.x * 0.1))
	canvas.draw_circle(_at(rect, 0.58 + bone, 0.45 - bone), rect.size.x * 0.07, Color(0.96, 0.94, 0.88))
	canvas.draw_line(_at(rect, 0.3, 0.52), _at(rect, 0.52, 0.66), Color(0.98, 0.9, 0.88, 0.8), maxf(2.0, rect.size.x * 0.06))

static func _steak(canvas: CanvasItem, rect: Rect2) -> void:
	_ellipse(canvas, rect, 0.5, 0.54, 0.34, 0.22, Color(0.55, 0.14, 0.14))
	canvas.draw_line(_at(rect, 0.28, 0.48), _at(rect, 0.7, 0.58), Color(0.92, 0.78, 0.74), maxf(2.0, rect.size.x * 0.05))
	canvas.draw_line(_at(rect, 0.32, 0.62), _at(rect, 0.66, 0.5), Color(0.95, 0.86, 0.82), maxf(2.0, rect.size.x * 0.04))

static func _fish(canvas: CanvasItem, rect: Rect2) -> void:
	_ellipse(canvas, rect, 0.52, 0.54, 0.26, 0.16, Color(0.38, 0.68, 0.74))
	canvas.draw_colored_polygon(PackedVector2Array([
		_at(rect, 0.28, 0.54), _at(rect, 0.1, 0.32), _at(rect, 0.1, 0.76),
	]), Color(0.3, 0.56, 0.64))
	canvas.draw_circle(_at(rect, 0.68, 0.48), rect.size.x * 0.035, Color(0.08, 0.12, 0.16))

static func _egg(canvas: CanvasItem, rect: Rect2) -> void:
	_ellipse(canvas, rect, 0.5, 0.56, 0.22, 0.3, Color(0.96, 0.93, 0.84))
	_ellipse(canvas, rect, 0.42, 0.46, 0.06, 0.08, Color(1, 1, 1, 0.7))

static func _milk(canvas: CanvasItem, rect: Rect2) -> void:
	canvas.draw_rect(Rect2(_at(rect, 0.28, 0.34), Vector2(rect.size.x * 0.44, rect.size.y * 0.5)), Color(0.96, 0.97, 0.98))
	canvas.draw_colored_polygon(PackedVector2Array([
		_at(rect, 0.28, 0.34), _at(rect, 0.72, 0.34), _at(rect, 0.6, 0.16), _at(rect, 0.4, 0.16),
	]), Color(0.28, 0.55, 0.86))
	canvas.draw_rect(Rect2(_at(rect, 0.28, 0.52), Vector2(rect.size.x * 0.44, rect.size.y * 0.1)), Color(0.28, 0.55, 0.86))

static func _offal(canvas: CanvasItem, rect: Rect2) -> void:
	_ellipse(canvas, rect, 0.42, 0.52, 0.2, 0.24, Color(0.58, 0.14, 0.2))
	_ellipse(canvas, rect, 0.6, 0.56, 0.18, 0.2, Color(0.48, 0.1, 0.16))
	canvas.draw_line(_at(rect, 0.4, 0.4), _at(rect, 0.58, 0.66), Color(0.32, 0.06, 0.1), maxf(2.0, rect.size.x * 0.05))

static func _watermelon(canvas: CanvasItem, rect: Rect2) -> void:
	var wedge := PackedVector2Array()
	var origin := _at(rect, 0.5, 0.78)
	wedge.append(origin)
	for step in 11:
		var angle := PI + PI * float(step) / 10.0
		wedge.append(origin + Vector2(cos(angle) * rect.size.x * 0.4, sin(angle) * rect.size.y * 0.46))
	canvas.draw_colored_polygon(wedge, Color(0.22, 0.55, 0.28))
	var flesh := PackedVector2Array()
	flesh.append(origin)
	for step in 11:
		var angle := PI + PI * float(step) / 10.0
		flesh.append(origin + Vector2(cos(angle) * rect.size.x * 0.3, sin(angle) * rect.size.y * 0.34))
	canvas.draw_colored_polygon(flesh, Color(0.86, 0.24, 0.28))
	for seed: Vector2 in [Vector2(0.4, 0.48), Vector2(0.58, 0.52), Vector2(0.48, 0.62)]:
		canvas.draw_circle(_at(rect, seed.x, seed.y), rect.size.x * 0.025, Color(0.1, 0.08, 0.08))

static func _lemon(canvas: CanvasItem, rect: Rect2) -> void:
	_ellipse(canvas, rect, 0.5, 0.58, 0.28, 0.24, Color(0.96, 0.84, 0.2))
	_ellipse(canvas, rect, 0.5, 0.32, 0.06, 0.08, Color(0.32, 0.62, 0.24))
	canvas.draw_circle(_at(rect, 0.42, 0.52), rect.size.x * 0.03, Color(1, 0.95, 0.55, 0.8))
