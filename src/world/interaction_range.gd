class_name TDInteractionRange
extends RefCounted
## Pure geometry shared by physical interactables; no input or state ownership.
const NPC_SPACING := 28.0
const RESIDENTIAL_KINDS := ["housing", "urban_village", "rich_district"]

static func ground_segment_clear(from: Vector2, to: Vector2, can_stand: Callable, step: float = 4.0) -> bool:
	var samples := maxi(1,ceili(from.distance_to(to)/step))
	for index: int in range(1,samples+1):
		if not can_stand.call(from.lerp(to,float(index)/samples)): return false
	return true
static func closest(point: Vector2, bounds: Rect2) -> Vector2:
	return Vector2(clampf(point.x,bounds.position.x,bounds.end.x),clampf(point.y,bounds.position.y,bounds.end.y))

static func distance(point: Vector2, bounds: Rect2) -> float:
	return point.distance_to(closest(point,bounds))

static func plot_bounds(plot: Dictionary, cell: float = 1.0, origin: Vector2 = Vector2.ZERO) -> Rect2:
	return Rect2(origin+Vector2(plot.x,plot.y)*cell,Vector2(plot.w,plot.h)*cell)

static func facility(plot: Dictionary) -> bool:
	var kind := str(plot.get("kind", ""))
	return not kind.is_empty() and kind != "diner_lot" and kind not in RESIDENTIAL_KINDS \
		and not plot.get("economic_courtyard", false)

static func npc_clear(from: Vector2, to: Vector2, feet: Vector2, spacing: float) -> bool:
	var radius_squared := spacing * spacing
	var start := from.distance_squared_to(feet)
	# A walking NPC can enter the player's space. Allow the player to step out.
	if start < radius_squared:
		return (to-from).dot(from-feet)>=0 and to.distance_squared_to(feet)>start
	return Geometry2D.get_closest_point_to_segment(feet,from,to).distance_squared_to(feet) >= radius_squared

static func faces(from: Vector2, facing: Vector2i, target: Vector2, reach: float) -> bool:
	var offset := target-from
	return offset.length_squared() <= reach*reach and (offset.is_zero_approx() or offset.normalized().dot(Vector2(facing).normalized()) >= .35)
