@tool
extends RefCounted
## Samples each shot at an absolute time so pausing, seeking and replay agree.
const FRAME := Rect2(0, 0, 1280, 720)
const TITLES := {
	"arrival": "到达港口", "hungry": "饥饿", "messenger": "阿铃登场",
	"soup_reflection": "汤里的倒影", "first_hearth": "招牌与炉火",
	"vito_awakening": "维托尝到第一口", "royal_letter": "公主的飞箭传书",
	"royal_domain": "至味卿展开领域",
}
const DURATIONS := {
	"soup_reflection": 5.6, "first_hearth": 6.4, "vito_awakening": 8.0,
	"royal_letter": 4.8, "royal_domain": 6.5,
}
const LEADS := {"vito_awakening":"vito_fork", "royal_letter":"restaurant_street", "royal_domain":"river_square"}
var image: Texture2D
var lead: Texture2D

static func duration_for(id: String) -> float:
	return float(DURATIONS.get(id, TDArrivalCutscene.SPANS.get(id, 0.0)))

static func load_still(id: String) -> Texture2D:
	var path := "res://assets/story/cg/%s.webp" % id
	if not ResourceLoader.exists(path, "Texture2D"): return null
	return ResourceLoader.load(path, "Texture2D") as Texture2D

func select(id: String) -> void:
	image = null
	lead = null
	if DURATIONS.has(id): image = load_still(id)
	if LEADS.has(id): lead = load_still(LEADS[id])

func paint(canvas: CanvasItem, id: String, t: float) -> void:
	if image == null: return
	match id:
		"soup_reflection":
			var push := smoothstep(0.12, 0.84, t)
			_still(canvas, image, Vector2(0.51, 0.68), lerpf(1.0, 1.23, push), Color.WHITE.lerp(Color(0.77, 0.84, 0.94), push * 0.7))
			var whisper := smoothstep(0.48, 0.56, t) * (1.0 - smoothstep(0.75, 0.83, t))
			if whisper > 0.0:
				var anchor := Vector2(787, 483)
				canvas.draw_string_outline(TDUI.font(), anchor, "好吃。", HORIZONTAL_ALIGNMENT_LEFT, -1, 27, 4, Color(0.11, 0.13, 0.16, 0.75 * whisper))
				canvas.draw_string(TDUI.font(), anchor, "好吃。", HORIZONTAL_ALIGNMENT_LEFT, -1, 27, Color(0.86, 0.90, 0.91, whisper))
		"first_hearth":
			var pan := smoothstep(0.16, 0.80, t)
			var focus := Vector2(0.19, 0.23).lerp(Vector2(0.79, 0.78), pan)
			_still(canvas, image, focus, lerpf(1.2, 1.28, pan))
		"vito_awakening":
			# Hold on the fork, cut on the intake of breath, then let his expression settle.
			if t < 0.39 and lead != null:
				_closeup(canvas, lead, Vector2(0.47, 0.77), 1.40 + 0.22 * smoothstep(0.0, 0.33, t))
			else:
				var breath := smoothstep(0.40, 0.89, t)
				_closeup(canvas, image, Vector2(0.54, 0.38), 1.50 - 0.36 * breath)
		"royal_letter":
			var push := smoothstep(0.22, 0.83, t)
			var focus := Vector2(0.55, 0.50)
			var impact := 1.0 - smoothstep(0.18, 0.25, t)
			if t > 0.18: focus.x += sin((t - 0.18) * 145.0) * impact * 0.022
			var cut := smoothstep(0.147, 0.189, t) if lead != null else 1.0
			if cut < 1.0: _still(canvas, lead, Vector2(0.51, 0.54), 1.015)
			if cut > 0.0: _still(canvas, image, focus, lerpf(1.04, 1.47, push), Color(1, 1, 1, cut))
			if t < 0.18:
				var dash := smoothstep(0.04, 0.18, t)
				var tip := Vector2(-140, 497).lerp(Vector2(704, 360), dash)
				canvas.draw_line(tip - Vector2(135, -22), tip, Color(0.85, 0.91, 0.98, sin(dash * PI)), 2.8, true)
		"royal_domain":
			_domain(canvas, image, lead, t)
	# A brief exposure ramp at the cuts bridges these frames back into dialogue.
	var shade := (1.0 - smoothstep(0.0, 0.055, t)) * 0.70 + smoothstep(0.94, 1.0, t) * 0.66
	canvas.draw_rect(FRAME, Color(0.025, 0.022, 0.04, shade))

static func _domain(canvas: CanvasItem, domain: Texture2D, square: Texture2D, t: float) -> void:
	var source := Vector2(0.71, 0.55)
	var center := FRAME.size * source
	var spread := smoothstep(0.14, 0.76, t)
	var zoom := lerpf(1.06, 1.0, spread)
	if spread >= 1.0 or square == null:
		_still(canvas, domain, source, zoom)
		return
	_still(canvas, square, source, 1.015, Color.WHITE.lerp(Color(0.75, 0.72, 0.84), spread))
	if spread <= 0.0001: return
	# A textured iris replaces the town square from the princess's feet outwards.
	var radius := 1050.0 * spread
	var circle := PackedVector2Array()
	for i in 96: circle.append(center + Vector2.from_angle(TAU * i / 96.0) * radius)
	var frame := PackedVector2Array([FRAME.position, Vector2(FRAME.end.x, 0), FRAME.end, Vector2(0, FRAME.end.y)])
	var mask := Geometry2D.intersect_polygons(frame, circle)
	var sample := _region(domain, source, zoom)
	for polygon: PackedVector2Array in mask:
		var uv := PackedVector2Array()
		for point in polygon: uv.append((sample.position + point / FRAME.size * sample.size) / domain.get_size())
		canvas.draw_polygon(polygon, PackedColorArray([Color.WHITE]), uv, domain)
	var rim := Color(0.96, 0.82, 0.50, sin(PI * spread) * 0.76)
	canvas.draw_arc(center, radius, 0, TAU, 128, Color(rim, rim.a * 0.25), 7.0, true)
	canvas.draw_arc(center, radius, 0, TAU, 128, rim, 1.8, true)

static func _region(texture: Texture2D, focus: Vector2, zoom: float) -> Rect2:
	var source := texture.get_size()
	var filled := maxf(FRAME.size.x / source.x, FRAME.size.y / source.y)
	var visible_size := FRAME.size / (filled * zoom)
	var origin := (source - visible_size) * focus
	return Rect2(origin, visible_size)

static func _still(canvas: CanvasItem, texture: Texture2D, focus: Vector2, zoom: float, tint: Color = Color.WHITE) -> void:
	canvas.draw_texture_rect_region(texture, FRAME, _region(texture, focus, zoom), tint)

static func _closeup(canvas: CanvasItem, texture: Texture2D, target: Vector2, zoom: float) -> void:
	var size := texture.get_size()
	var crop := _region(texture, Vector2.ZERO, zoom)
	crop.position = (size * target - crop.size * 0.5).clamp(Vector2.ZERO, size - crop.size)
	canvas.draw_texture_rect_region(texture, FRAME, crop)
