@tool
class_name TDVNLayout
extends RefCounted
## Shared editor/runtime geometry. td:x:y:scale = centre X / bottom Y / uniform size.
const DESIGN := Vector2(1280,800)
const BASE_HEIGHT := 605.0

static func parse(token: String) -> Dictionary:
	if not token.begins_with("td:"): return {}
	var parts := token.split(":")
	if parts.size() != 4: return {}
	for value: String in parts.slice(1):
		if not value.is_valid_float() or not is_finite(float(value)): return {}
	var x := float(parts[1]); var y := float(parts[2]); var scale_value := float(parts[3])
	if x < 0 or x > 1 or y < 0 or y > 1 or scale_value < .25 or scale_value > 1.25: return {}
	return {"x":x,"y":y,"scale":scale_value}

static func encode(x: float, y: float, scale_value: float = 1.0) -> String:
	return "td:%.6f:%.6f:%.6f" % [clampf(x,0,1),clampf(y,0,1),clampf(scale_value,.25,1.25)]

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
	return Rect2(result.position * viewport_size / DESIGN,result.size * viewport_size / DESIGN)

static func fit(texture: Texture2D, bounds: Rect2) -> Rect2:
	var factor := minf(bounds.size.x/texture.get_width(),bounds.size.y/texture.get_height())
	var size_value := texture.get_size()*factor
	return Rect2(bounds.position+(bounds.size-size_value)*.5,size_value)
