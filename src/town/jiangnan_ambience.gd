extends Node2D
## Every effect uses the same game minute as the town tint. The host draws the
## floor pass beneath people and gives the facade pass its owner's sort depth.

const FEATURES := ["courtyard_shadow","banyan", "tea", "puppet", "street_lamp", "eave_lantern", "chess", "audience", "hawthorn", "well", "bench", "stools", "reeds", "cloth_sign", "forge", "lantern_rope"]
const ROPE_LAMPS := [Vector2(.15,.27),Vector2(.32,.35),Vector2(.50,.40),Vector2(.66,.35),Vector2(.82,.27)]
const SPARROW_OFFSETS: Array[Vector2] = [Vector2(-24,-2), Vector2(10,8), Vector2(39,-5)]
static var _falloff: GradientTexture2D
static var _shadow_masks: Dictionary = {}
var _shadow: Texture2D
var _banner: Texture2D
var feature: String
var facade: Rect2
var bounds: Rect2
var minute: float = -1.0
var phase: float
var lamps: float
var sun: float
var daylight_tint: Color
var light_at: Vector2
var kettle_at: Vector2
var steamer_at: Vector2
var screen: Rect2
var birds_at: Vector2

func configure(item: Dictionary) -> void:
	feature = item.jiangnan_feature
	facade = item.rect
	if feature == "cloth_sign":
		_banner = item.art
	elif feature != "eave_lantern":
		_shadow = _shadow_mask(item.art, feature == "banyan")
	position = Vector2(facade.get_center().x, float(item.get("sort_y", facade.end.y)) + .1)
	var light_uv := Vector2(.5, .5) if feature == "eave_lantern" else Vector2(.5, .28)
	light_at = facade.position + facade.size * Vector2(item.get("light_uv", light_uv))
	kettle_at = facade.position + facade.size * Vector2(item.get("kettle_uv", Vector2(.72, .57)))
	steamer_at = facade.position + facade.size * Vector2(item.get("steamer_uv", Vector2(.34, .73)))
	var silk: Rect2 = item.get("screen_uv", Rect2(.25, .30, .5, .33))
	screen = Rect2(facade.position + facade.size * silk.position, facade.size * silk.size)
	birds_at = item.get("birds_at", Vector2(facade.get_center().x + facade.size.x * .30, facade.end.y + 33))
	bounds = facade.expand(position + Vector2.DOWN * 8).grow(100)
	if _shadow != null:
		bounds = bounds.expand(facade.end + facade.size.y * Vector2(.58, .49))
	if feature == "banyan":
		bounds = bounds.merge(Rect2(birds_at - Vector2(35, 20), Vector2(82, 42)))
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if _banner != null else CanvasItem.TEXTURE_FILTER_LINEAR
	hide()

func sample(view_rect: Rect2, game_minute: float, daylight: Dictionary) -> void:
	visible = bounds.intersects(view_rect)
	if not visible or is_equal_approx(minute, game_minute): return
	minute = game_minute
	phase = (minute - TDWorldDayClock.START_MINUTE) / TDWorldDayClock.MINUTES_PER_SECOND
	lamps = daylight.lamps
	daylight_tint = daylight.tint
	sun = (1.0 - lamps) * lerpf(.66, 1.0, smoothstep(480.0, 600.0, minute))
	queue_redraw()

func draw_ground(canvas: Node2D) -> void:
	if not visible or minute < 0: return
	if _shadow != null: _cast_shadow(canvas)
	if feature == "banyan" and sun > .025:
		_sparrows(canvas)
	elif feature in ["street_lamp", "eave_lantern"] and lamps > .01:
		var pool := Vector2(light_at.x + 4, position.y + 7)
		_soft(canvas, pool, Vector2(104, 40), _warm(Color("ffaf65"), .26 * lamps))
	elif feature == "lantern_rope" and lamps > .01:
		for uv: Vector2 in ROPE_LAMPS:
			var pool := Vector2(facade.position.x+facade.size.x*uv.x,facade.end.y+5)
			_soft(canvas,pool,Vector2(95,37),_warm(Color("ffae52"),.16*lamps))

func _draw() -> void:
	if minute < 0: return
	match feature:
		"cloth_sign":
			_draw_banner()
		"tea":
			_steam(kettle_at - position, 31, .0)
			_steam(steamer_at - position, 24, 1.7)
		"puppet":
			_shadow_play()
		"forge":
			var fire := facade.position-position+facade.size*Vector2(.595,.69)
			var pulse := .51+.13*sin(phase*4.2)+.11*sin(phase*6.7)
			_soft(self,fire,Vector2(37,27),_warm(Color("ff8c34"),pulse))
			for spark: int in 5:
				var t := fposmod(phase*.62+spark*.21,1.0)
				var at := fire+Vector2(sin(t*3.0+spark)*t*11.0,-21.0*t)
				draw_rect(Rect2(at,Vector2(1.6,2.1)),_warm(Color("ffbb5b"),sin(t*PI)*.90))
		"lantern_rope":
			if lamps > .01:
				for uv: Vector2 in ROPE_LAMPS:
					var at := facade.position-position+facade.size*uv
					_soft(self,at,Vector2(67,60),_warm(Color("ff8c43"),.47*lamps))
					_soft(self,at,Vector2(19,22),_warm(Color("ffd574"),.71*lamps))
		"street_lamp", "eave_lantern":
			if lamps > .01:
				var at := light_at - position
				_soft(self, at, Vector2(83, 75), _warm(Color("ff8b40"), .44 * lamps))
				_soft(self, at, Vector2(32, 32), _warm(Color("ffb25e"), .68 * lamps))
				_soft(self, at, Vector2(11, 13), _warm(Color("ffdb9c"), .86 * lamps))

func _banner_offset(height_fraction: float) -> float:
	# Both suspension loops and the full wooden rod are in the upper fifth.
	var free := clampf((height_fraction - .20) / .80, 0, 1)
	var breeze := phase * 1.54 + facade.position.x * .012
	return facade.size.x * free * free * (.081 * sin(breeze - free * .78) + .022 * sin(breeze * .57 + free))

func _draw_banner() -> void:
	var top := 0.0
	var art_size := _banner.get_size()
	for bottom: float in [.20, .40, .60, .80, 1.0]:
		var offset := _banner_offset(top)
		var height := (bottom - top) * facade.size.y
		var skew := (_banner_offset(bottom) - offset) / height
		var corner := facade.position - position + Vector2(offset, top * facade.size.y)
		draw_set_transform_matrix(Transform2D(Vector2.RIGHT, Vector2(skew,1), corner))
		draw_texture_rect_region(_banner, Rect2(0,0,facade.size.x,height),
				Rect2(0,top * art_size.y,art_size.x,(bottom - top) * art_size.y))
		top = bottom
	draw_set_transform_matrix(Transform2D.IDENTITY)

func _warm(color: Color, alpha: float) -> Color:
	# Lamps stay orange even after the shared outdoor twilight tint is applied.
	return Color(color.r / daylight_tint.r, color.g / daylight_tint.g, color.b / daylight_tint.b, alpha)

static func _soft(canvas: CanvasItem, center: Vector2, size: Vector2, color: Color) -> void:
	if _falloff == null:
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0, .25, .54, .80, 1])
		gradient.colors = PackedColorArray([Color.WHITE, Color(1,1,1,.87), Color(1,1,1,.48), Color(1,1,1,.13), Color(1,1,1,0)])
		_falloff = GradientTexture2D.new()
		_falloff.width = 64
		_falloff.height = 64
		_falloff.fill = GradientTexture2D.FILL_RADIAL
		_falloff.fill_from = Vector2(.5, .5)
		_falloff.fill_to = Vector2(1, .5)
		_falloff.gradient = gradient
	canvas.draw_texture_rect(_falloff, Rect2(center - size * .5, size), false, color)

static func _shadow_mask(art: Texture2D, leafy: bool) -> Texture2D:
	if _shadow_masks.has(art): return _shadow_masks[art]
	# Keep the gaps between legs, wheel spokes, branches and aerial roots.
	# Downsampling the illustrated alpha once softens the jagged silhouette.
	var mask := art.get_image()
	if mask.is_compressed(): mask.decompress()
	mask.convert(Image.FORMAT_RGBA8)
	var longest := maxi(mask.get_width(), mask.get_height())
	var scale_factor := minf(1.0, (156.0 if leafy else 94.0) / longest)
	mask.resize(maxi(1, roundi(mask.get_width() * scale_factor)), maxi(1, roundi(mask.get_height() * scale_factor)), Image.INTERPOLATE_BILINEAR)
	for y: int in mask.get_height():
		for x: int in mask.get_width():
			var pigment := mask.get_pixel(x, y)
			var opacity := pigment.a
			if leafy and pigment.g > pigment.b * 1.33 and pigment.g > pigment.r * .88:
				# Sunlit patches in the painted foliage form irregular openings.
				# These expose the real flagstones underneath at their own colour.
				opacity *= 1.0 - .86 * smoothstep(.39, .75, pigment.get_luminance())
			mask.set_pixel(x, y, Color(1, 1, 1, opacity))
	var result := ImageTexture.create_from_image(mask)
	_shadow_masks[art] = result
	return result

func _cast_shadow(canvas: Node2D) -> void:
	var feet := Vector2(facade.get_center().x, facade.end.y)
	var size := facade.size
	var base_width := size.x * (.64 if feature == "banyan" else .86)
	_soft(canvas, feet + Vector2(2, 1), Vector2(base_width, maxf(7, size.y * .10)), Color(.18,.16,.13,.51))
	if sun <= .025: return
	var spread := 1.0 + .40 * clampf(absf(minute - 780) / 300.0, 0, 1)
	var direction := Vector2(.32, .25) * spread
	var opacity := .36
	if feature == "banyan":
		direction = Vector2(.40 + sin(phase * .63) * .012, .33 + cos(phase * .44) * .006) * spread
		opacity = .50
	# The vertical axis folds down and right. Its origin remains at the
	# object's feet, including when taller branches move together in the wind.
	canvas.draw_set_transform_matrix(Transform2D(Vector2.RIGHT, -direction, feet))
	canvas.draw_texture_rect(_shadow, Rect2(Vector2(-size.x * .5, -size.y), size), false, Color(.22,.25,.24,opacity * sun))
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)

func _sparrows(canvas: Node2D) -> void:
	for i: int in SPARROW_OFFSETS.size():
		var t := phase + i * 2.27
		var from := birds_at + SPARROW_OFFSETS[i]
		var hop := maxf(0, sin(t * .92) - .80) * 5
		var feet := from + Vector2(sin(t * .92) * 4, -sin(hop * PI) * 4)
		var peck := pow(maxf(0, sin(t * 4.3)), 3.0) * float(sin(t * .92) < .65)
		var face := -1.0 if i == 1 else 1.0
		var alpha := smoothstep(.05, .42, sun)
		if alpha <= 0: return
		_soft(canvas, Vector2(feet.x, from.y + 1), Vector2(16, 5), Color(.22,.18,.12,.36 * alpha))
		canvas.draw_set_transform(feet, 0, Vector2(face, 1))
		var ink := Color("514333")
		ink.a = alpha
		canvas.draw_line(Vector2(-2,-3), Vector2(-3,0), ink, 1.2, true)
		canvas.draw_line(Vector2(2,-3), Vector2(3,0), ink, 1.2, true)
		canvas.draw_colored_polygon(PackedVector2Array([Vector2(-2,-6),Vector2(-10,-9),Vector2(-8,-5),Vector2(-2,-3)]), ink)
		_soft(canvas, Vector2(-.4,-5), Vector2(12,8), Color(.42,.31,.23,alpha))
		canvas.draw_colored_polygon(PackedVector2Array([Vector2(-6,-6),Vector2(1,-8),Vector2(3,-5),Vector2(-4,-4)]), Color(.49,.36,.26,alpha))
		var head := Vector2(3 + peck * 3, -8 + peck * 5)
		canvas.draw_circle(head, 2.9, Color(.48,.33,.22,alpha), true, -1, true)
		canvas.draw_circle(head + Vector2(1,.7), 1.65, Color(.88,.80,.66,alpha), true, -1, true)
		canvas.draw_circle(head + Vector2(1.4,-.6), .75, ink)
		canvas.draw_line(head + Vector2(2,0), head + Vector2(5,1 + peck), ink, 1.25, true)
		canvas.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

func _steam(source_at: Vector2, rise: float, offset: float) -> void:
	for thread_index: int in 3:
		var age := fposmod(phase * .42 + offset + thread_index / 3.0, 1.0)
		var path := PackedVector2Array()
		for i: int in 8:
			var v := i / 7.0
			var lift := age * rise + v * (4 + age * 11)
			var curl := sin(age * 5 + v * 3.6 + offset) * (1 + age * 3) + age * 4
			path.append(source_at + Vector2(curl, -lift))
		var alpha := sin(age * PI) * .68
		draw_polyline(path, Color(.89,.88,.80,alpha * .24), 4.5, true)
		draw_polyline(path, Color(1,.98,.90,alpha), 1.5, true)

func _shadow_play() -> void:
	# Articulated silhouettes fit inside the cloth, with visible bamboo rods.
	var cloth := Rect2(screen.position - position, screen.size)
	var silk := Color("e6c791").lerp(_warm(Color("f1cc94"), 1), .42 * lamps)
	draw_rect(cloth.grow(1.6), Color("684832"))
	draw_rect(cloth, silk)
	_soft(self, cloth.get_center(), cloth.size, Color(1, .94, .75, .44))
	for y: int in range(3, floori(cloth.size.y) - 1, 4):
		var thread := cloth.position + Vector2(0, y)
		draw_line(thread, thread + Vector2(cloth.size.x, 0), Color(.53,.36,.20,.10), 1)
	draw_line(cloth.position, cloth.position + Vector2(cloth.size.x, 0), Color("bf9863"), 1.5, true)
	draw_line(cloth.end - Vector2(cloth.size.x, 0), cloth.end, Color("996f44"), 1.6, true)
	var scale_factor := minf(screen.size.x / 57.0, screen.size.y / 31.0)
	for i: int in 2:
		var beat := phase * 1.32 + i * 2.6
		var feet := screen.position - position + screen.size * Vector2(.30 + i * .40, .90)
		feet += Vector2(sin(beat * .6) * scale_factor, -maxf(0,sin(beat)) * scale_factor)
		draw_set_transform(feet, sin(beat * .65) * .045, Vector2(scale_factor * (1 if i == 0 else -1), scale_factor))
		var ink := Color("4a2923")
		var costume := Color("913d2e") if i == 0 else Color("405753")
		draw_line(Vector2(-2, -10), Vector2(-4, 1), Color("896443"), 1, true)
		draw_colored_polygon(PackedVector2Array([Vector2(-3,-15),Vector2(3,-13),Vector2(4,-8),Vector2(6,-3),Vector2(-6,-3),Vector2(-3,-8)]), ink)
		draw_colored_polygon(PackedVector2Array([Vector2(-2,-13),Vector2(2,-12),Vector2(3,-8),Vector2(-3,-5)]), costume)
		draw_line(Vector2(-2,-4),Vector2(-3,0),ink,2,true)
		draw_line(Vector2(2,-4),Vector2(4,-1),ink,2,true)
		draw_colored_polygon(PackedVector2Array([Vector2(-3,-19),Vector2(2,-20),Vector2(4,-18),Vector2(6,-17),Vector2(3,-16),Vector2(2,-14),Vector2(-2,-14)]),ink)
		if i == 0:
			draw_colored_polygon(PackedVector2Array([Vector2(-4,-19),Vector2(-5,-24),Vector2(-1,-22),Vector2(1,-25),Vector2(3,-22),Vector2(5,-21),Vector2(2,-19)]),ink)
		else:
			draw_colored_polygon(PackedVector2Array([Vector2(-7,-19),Vector2(-5,-21),Vector2(-2,-22),Vector2(1,-24),Vector2(4,-20),Vector2(6,-19)]),ink)
		var elbow := Vector2(4,-10) + Vector2(2,sin(beat)*2)
		var hand := elbow + Vector2(3 + cos(beat), -3 - sin(beat)*3)
		draw_line(Vector2(1,-13),elbow,costume,3.3,true)
		draw_line(elbow,hand,ink,2,true)
		draw_line(hand,Vector2(10,1),Color("886a49"),.85,true)
		draw_circle(Vector2(-.2,-10),.8,Color("c7995d"))
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
