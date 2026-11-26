@tool
class_name TDVNLayout
extends RefCounted
## Shared editor/runtime geometry. td:x:y:scale = centre X / bottom Y / uniform size.
const DESIGN := Vector2(1280,800)
const BASE_HEIGHT := 605.0
const MIN_SCALE := 0.25
const MAX_SCALE := 5.0
# Offscreen staging is intentional; keep a finite guard against corrupt geometry.
const MIN_POSITION := -10.0
const MAX_POSITION := 11.0

const HALF_BODY_SCALE := 2.15
# Face anchors in the untouched original square canvases. Expressions share one anchor.
const FACE_FOCUS := {"hero":Vector2(.49,.26), "aling":Vector2(.50,.19), "chen":Vector2(.44,.23), "luo":Vector2(.51,.30), "vito":Vector2(.46,.235), "hertz":Vector2(.54,.19), "hina":Vector2(.50,.23)}

static func half_body(side: String, actor: String = "") -> String:
	var focus: Vector2 = FACE_FOCUS.get(actor, FACE_FOCUS.hero)
	var width := 760.0 * .64 * HALF_BODY_SCALE
	var height := BASE_HEIGHT * HALF_BODY_SCALE
	var x := float({"left":.26, "right":.74}.get(side,.5)) - (focus.x-.5)*width/DESIGN.x
	var image_top := 270.0-focus.y*width
	return encode(x,(image_top+(height+width)*.5)/DESIGN.y,HALF_BODY_SCALE)

static func parse(token: String) -> Dictionary:
	if not token.begins_with("td:"): return {}
	var parts := token.split(":")
	if parts.size() != 4: return {}
	for value: String in parts.slice(1):
		if not value.is_valid_float() or not is_finite(float(value)): return {}
	var x := float(parts[1]); var y := float(parts[2]); var scale_value := float(parts[3])
	if x < MIN_POSITION or x > MAX_POSITION or y < MIN_POSITION or y > MAX_POSITION or scale_value < MIN_SCALE or scale_value > MAX_SCALE: return {}
	return {"x":x,"y":y,"scale":scale_value}

static func encode(x: float, y: float, scale_value: float = 1.0) -> String:
	if not is_finite(x) or not is_finite(y) or not is_finite(scale_value): return ""
	return "td:%.6f:%.6f:%.6f" % [clampf(x,MIN_POSITION,MAX_POSITION),clampf(y,MIN_POSITION,MAX_POSITION),clampf(scale_value,MIN_SCALE,MAX_SCALE)]

static func rect(token: String, cast_scale: float = .64, viewport_size: Vector2 = DESIGN) -> Rect2:
	var layout := parse(token)
	var x := float({"far_left":.1,"left":.25,"center":.5,"right":.75,"far_right":.9}.get(token,.5))
	if token.is_valid_float(): x = float(token)
	var bottom := 685.0
	var factor := 1.0
	if not layout.is_empty():
		x = layout.x; bottom = layout.y * DESIGN.y; factor = layout.scale
	var size_value := Vector2(760.0 * cast_scale, BASE_HEIGHT) * factor
	var result := Rect2(Vector2(x*DESIGN.x - size_value.x/2,bottom-size_value.y),size_value)
	# Uniform viewport scaling prevents wide windows enlarging faces until heads clip.
	var screen_scale := minf(viewport_size.x/DESIGN.x,viewport_size.y/DESIGN.y)
	var rendered_size := result.size * screen_scale
	return Rect2(Vector2(x*viewport_size.x-rendered_size.x*.5,bottom/DESIGN.y*viewport_size.y-rendered_size.y),rendered_size)

static func fit(texture: Texture2D, bounds: Rect2) -> Rect2:
	var factor := minf(bounds.size.x/texture.get_width(),bounds.size.y/texture.get_height())
	var size_value := texture.get_size()*factor
	return Rect2(bounds.position+(bounds.size-size_value)*.5,size_value)
