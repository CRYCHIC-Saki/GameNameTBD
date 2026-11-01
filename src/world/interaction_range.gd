class_name TDInteractionRange
extends RefCounted
## Pure geometry shared by physical interactables; no input or state ownership.
static func closest(point: Vector2, bounds: Rect2) -> Vector2:
	return Vector2(clampf(point.x,bounds.position.x,bounds.end.x),clampf(point.y,bounds.position.y,bounds.end.y))

static func distance(point: Vector2, bounds: Rect2) -> float:
	return point.distance_to(closest(point,bounds))

static func plot_bounds(plot: Dictionary, cell: float = 1.0, origin: Vector2 = Vector2.ZERO) -> Rect2:
	return Rect2(origin+Vector2(plot.x,plot.y)*cell,Vector2(plot.w,plot.h)*cell)

static func facility(plot: Dictionary) -> bool:
	return not plot.get("economic_courtyard",false) and plot.kind not in ["housing","diner_lot"]
