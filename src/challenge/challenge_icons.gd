extends RefCounted
## Compact symbols shared by the battlefield sidebar and its circular controls.

const Action := TDChallengeBattle.Action
const VITO_ART := preload("res://assets/characters/mainline-20261126/vito/calm.png")
const HEAD_ART := {
	"hero": [preload("res://assets/characters/mainline-20261126/hero/calm.png"), Rect2(900, 325, 700, 700)],
	"aling": [preload("res://assets/characters/mainline-20261126/aling/calm.png"), Rect2(1015, 130, 690, 690)],
	"chen": [preload("res://assets/characters/mainline-20261126/chen/calm.png"), Rect2(868, 264, 705, 705)],
	"vito": [VITO_ART, Rect2(883, 250, 620, 620)],
	"hina": [preload("res://assets/characters/mainline-20261126/hina/calm.png"), Rect2(1010, 155, 675, 675)],
	"luoe": [preload("res://assets/characters/mainline-20261126/luo/calm.png"), Rect2(948, 228, 692, 692)],
	"crowd": [preload("res://assets/characters/crowd/crowd-original-neutral.png"), Rect2(543, 24, 1040, 1040)],
}
static var _headshots: Dictionary = {}
static var _guarded_luoe: ImageTexture

static func headshot(character: String) -> AtlasTexture:
	var id := "crowd" if character.begins_with("crowd_") else character
	if not HEAD_ART.has(id): return null
	if not _headshots.has(id):
		var source: Array = HEAD_ART[id]
		var image := AtlasTexture.new()
		image.atlas = source[0]
		image.region = source[1]
		image.filter_clip = true
		_headshots[id] = image
	return _headshots[id]

static func guarded_luoe_headshot() -> Texture2D:
	if _guarded_luoe == null:
		var portrait := headshot("luoe")
		var source := portrait.atlas.get_image()
		if source.is_compressed(): source.decompress()
		var image := source.get_region(Rect2i(portrait.region))
		image.convert(Image.FORMAT_RGBA8)
		image.clear_mipmaps()
		var pixels := image.get_data()
		for i: int in range(0, pixels.size(), 4):
			var luminance := (pixels[i] * 3 + pixels[i + 1] * 6 + pixels[i + 2]) / 10.0
			var tint := roundi(105.0 + luminance * (150.0 / 255.0))
			pixels[i] = tint
			pixels[i + 1] = tint
			pixels[i + 2] = tint
		image.set_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8, pixels)
		image.generate_mipmaps()
		_guarded_luoe = ImageTexture.create_from_image(image)
	return _guarded_luoe

static func layout_diamond(area: Vector2, line: CommandButton, square: CommandButton,
		slot_f: CommandButton, slot_g: CommandButton) -> void:
	var diameter := floorf(minf(84, area.x * .37))
	var step := roundf(diameter * .76)
	var center := (area - Vector2.ONE * diameter) * .5
	var buttons := [slot_g, square, slot_f, line]
	for i: int in buttons.size():
		buttons[i].size = Vector2.ONE * diameter
		buttons[i].position = (center + Vector2(TDChallengeBattle.DIRECTIONS[i]) * step).round()

class Badge extends Control:
	var tint := Color("#e7b778")

	func _draw() -> void:
		var at := size * .5
		draw_colored_polygon(PackedVector2Array([at + Vector2(0,-11), at + Vector2(9,0),
			at + Vector2(0,11), at + Vector2(-9,0)]), tint.darkened(.32))
		draw_colored_polygon(PackedVector2Array([at + Vector2(2,-8), at + Vector2(-4,1),
			at + Vector2(0,1), at + Vector2(-2,8), at + Vector2(5,-2), at + Vector2(1,-2)]), tint.lightened(.25))

class EnergyIcon extends Control:
	func _draw() -> void:
		draw_crystal(self, size * .5, 10.0)

	static func draw_crystal(canvas: CanvasItem, center: Vector2, radius: float) -> void:
		canvas.draw_colored_polygon(PackedVector2Array([center + Vector2.UP * radius,
			center + Vector2.RIGHT * radius * .7, center + Vector2.DOWN * radius,
			center + Vector2.LEFT * radius * .7]), Color("#64daad"))
		canvas.draw_line(center + Vector2.UP * radius * .65, center + Vector2.LEFT * radius * .42,
			Color("#fff0d2"), 2.0, true)

class Portrait extends Control:
	var face: Texture2D
	var tint := Color.WHITE

	func _ready() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

	func _draw() -> void:
		var frame := Rect2(Vector2.ZERO, size)
		draw_rect(frame, tint.darkened(.60))
		draw_rect(frame.grow(-2), Color("#171e25"))
		if face != null:
			draw_texture_rect(face, frame.grow(-3), false)
		else:
			var center := frame.get_center()
			draw_circle(center + Vector2(0,-8), 8, tint.darkened(.26), true, -1, true)
			draw_circle(center + Vector2(0,17), 12, tint.darkened(.44), true, -1, true)
			draw_rect(Rect2(3,size.y-12,size.x-6,9), Color("#171e25"))
		draw_line(Vector2(3,size.y-1), size-Vector2(3,1), tint, 2)

class CommandButton extends Button:
	const SLATE := Color("#242c35")
	const PALETTE := [Color.WHITE, Color("#eed09a"), Color("#eaa485"), Color("#88daca"), Color("#d7b0ef")]
	const SKILL_COLORS := {"beam":Color("#88daca"), "delay":Color("#d7b0ef"), "heal":Color("#a9e6a6"), "tomato":Color("#f4a27d"), "shield":Color("#8ac8f1")}
	const GLOW_PERIOD := 1.05
	var action := Action.LINE
	var key_hint := ""
	var skill_id := ""
	var energy_cost: int:
		get: return int(TDChallengeBattle.Skills.DEFINITIONS.get(skill_id, {}).get("energy_cost", 0))
	var warehouse_slot := false
	var warehouse_equipped := false
	var ready_to_cast := false:
		set(value):
			if value == ready_to_cast: return
			ready_to_cast = value
			_update_glow()
			queue_redraw()
	var aimed := false
	var _glow_phase := 0.0

	func _ready() -> void:
		var empty := StyleBoxEmpty.new()
		for state: String in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
			add_theme_stylebox_override(state, empty)
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)
		button_down.connect(queue_redraw)
		button_up.connect(queue_redraw)
		visibility_changed.connect(_update_glow)
		_update_glow()

	func _update_glow() -> void:
		var active := ready_to_cast and is_visible_in_tree()
		if active == is_processing(): return
		_glow_phase = 0.0
		set_process(active)

	func _process(delta: float) -> void:
		_glow_phase = fposmod(_glow_phase + delta * TAU / GLOW_PERIOD, TAU)
		queue_redraw()

	func _has_point(point: Vector2) -> bool:
		return point.distance_to(size * .5) <= size.x * .5

	func _draw() -> void:
		var center := size * .5
		var radius := center.x - 3.0
		if radius < 4: return
		var slot := action in [Action.SLOT_1, Action.SLOT_2]
		var tint: Color = SKILL_COLORS.get(skill_id, Color("#b6b9bd")) if slot else PALETTE[action]
		var highlighted := not disabled and (aimed or is_hovered())
		var rim := tint if highlighted else tint.darkened(.54 if disabled else .24)
		var pulse := 0.0
		var surface := SLATE.lightened(.15) if highlighted else SLATE
		if warehouse_slot:
			surface = Color("#191a20") if highlighted else Color("#101115")
			if skill_id.is_empty(): rim = Color("#615449")
		if ready_to_cast:
			pulse = .5 + .5 * cos(_glow_phase)
			var halo := Color.from_hsv(tint.h, minf(1, tint.s * 1.45), tint.v)
			draw_circle(center, radius+6, Color(halo, .07 + .25 * pulse), false, 9, true)
			draw_circle(center, radius+3, Color(halo, .16 + .58 * pulse), false, 4, true)
			rim = tint.lerp(Color.WHITE, .25 + .55 * pulse)
			surface = surface.lerp(tint, .08 + .23 * pulse)
		draw_circle(center + Vector2(0,2), radius+2, Color("#11161d"), true, -1, true)
		draw_circle(center, radius, surface, true, -1, true)
		draw_circle(center, radius, rim, false, 1.5, true)
		if warehouse_slot and skill_id.is_empty(): return
		if warehouse_equipped:
			draw_circle(center + Vector2(.60, -.60) * radius, 3, Color("#efc87f"), true, -1, true)
		var ink := tint.darkened(.23 if disabled else .0)
		if ready_to_cast: ink = tint.lerp(Color.WHITE, .32 + .44 * pulse)
		var glyph_size := size.x * .35
		var glyph_offset := .5 if key_hint.is_empty() else .65
		draw_set_transform(center - Vector2(glyph_size * .5, glyph_size * glyph_offset), 0, Vector2.ONE * glyph_size / 24.0)
		_draw_glyph(ink)
		draw_set_transform_matrix(Transform2D.IDENTITY)
		if not key_hint.is_empty():
			var text_size := clampi(roundi(size.x * .19), 12, 16)
			draw_string(TDUI.font(), Vector2(0, center.y + radius * .66), key_hint,
				HORIZONTAL_ALIGNMENT_CENTER, size.x, text_size, ink.lightened(.32))
		if energy_cost > 0:
			var badge := Rect2(Vector2(minf(center.x + radius * .30, size.x - 31), center.y + radius * .27), Vector2(31, 19))
			draw_rect(badge, Color("#173d39"))
			draw_rect(badge, Color("#88daca"), false)
			var crystal := badge.position + Vector2(7, 9)
			draw_colored_polygon(PackedVector2Array([crystal + Vector2(0, -4), crystal + Vector2(3, 0),
				crystal + Vector2(0, 4), crystal + Vector2(-3, 0)]), Color("#88daca"))
			draw_string(TDUI.font(), badge.position + Vector2(12, 14), str(energy_cost),
				HORIZONTAL_ALIGNMENT_CENTER, 17, 12, Color("#eefff6"))

	func _draw_glyph(ink: Color) -> void:
		match action:
			Action.LINE:
				draw_colored_polygon(PackedVector2Array([Vector2(2,10), Vector2(14,10), Vector2(14,4),
					Vector2(23,12), Vector2(14,20), Vector2(14,14), Vector2(2,14)]), ink)
			Action.SQUARE:
				draw_rect(Rect2(4,4,16,16), ink, false, 2)
				for corner: Vector2 in [Vector2(2,2),Vector2(18,2),Vector2(2,18),Vector2(18,18)]:
					draw_rect(Rect2(corner, Vector2(4,4)), ink)
				draw_rect(Rect2(10,10,4,4), ink)
			Action.SLOT_1, Action.SLOT_2:
				_draw_skill(ink)

	func _draw_skill(ink: Color) -> void:
		match skill_id:
			"beam":
				draw_line(Vector2(1,5), Vector2(16,5), ink, 2, true)
				draw_line(Vector2(1,19), Vector2(16,19), ink, 2, true)
				draw_line(Vector2(1,12), Vector2(23,12), ink, 3, true)
				draw_polyline(PackedVector2Array([Vector2(17,7), Vector2(23,12),Vector2(17,17)]), ink, 2, true)
			"delay":
				draw_circle(Vector2(12,12), 9, ink, false, 2, true)
				draw_polyline(PackedVector2Array([Vector2(12,6), Vector2(12,12), Vector2(17,12)]), ink, 2, true)
			"heal":
				draw_rect(Rect2(9,2,6,20), ink)
				draw_rect(Rect2(2,9,20,6), ink)
			"tomato":
				draw_circle(Vector2(12,14), 8, ink, false, 2.5, true)
				draw_polyline(PackedVector2Array([Vector2(6,4), Vector2(12,8), Vector2(12,2), Vector2(12,8), Vector2(18,4)]), ink, 2, true)
			"shield":
				draw_polyline(PackedVector2Array([Vector2(12,2), Vector2(21,6), Vector2(20,15), Vector2(12,22), Vector2(4,15), Vector2(3,6), Vector2(12,2)]), ink, 2.5, true)
				draw_line(Vector2(12,7), Vector2(12,16), ink, 2, true)
			_:
				draw_arc(Vector2(12,10), 5, PI, TAU, 20, ink, 2.5, true)
				draw_rect(Rect2(5,10,14,11), ink)
				draw_circle(Vector2(12,15), 1.6, SLATE, true, -1, true)
