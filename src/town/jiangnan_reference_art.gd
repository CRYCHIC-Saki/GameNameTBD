class_name TDJiangnanReferenceArt
extends RefCounted
## The editor scene supplies both reusable sprites and individual ground cells.
const SIZE := TDPlannedTown.REFERENCE_SIZE
const MAP_PATH := "res://src/town/jiangnan_map.tscn"
const CELL_SIZE := 90
const WORLD_SIZE := SIZE * (73.0 * CELL_SIZE / SIZE.x)
static var _map: PackedScene
static var _parts: Array[Dictionary] = []

static func make_scene() -> Node2D:
	if _map == null: _map = load(MAP_PATH)
	return _map.instantiate() as Node2D

static func _parts_from_scene() -> Array[Dictionary]:
	if not _parts.is_empty(): return _parts
	var scene := make_scene()
	for child: Node in scene.get_node("Props").get_children():
		if not child is Sprite2D or not child.has_meta("scenic_id"): continue
		var sprite := child as Sprite2D
		var walking: Array[Rect2] = []
		for bounds: Rect2 in sprite.get_meta("walking_feet", []):
			var contact := sprite.transform * bounds
			walking.append(TDEnvironmentArt.wall_clearance(contact) if sprite.get_meta("enclosed",false) else contact)
		var bases: Array[Rect2] = []
		for bounds: Rect2 in sprite.get_meta("footprints", []):
			bases.append(sprite.transform * bounds)
		_parts.append({"id": sprite.get_meta("scenic_id"), "art": sprite.texture,
			"rect": sprite.transform * sprite.get_rect(), "bases": bases, "walking": walking, "foot": sprite.position.y,
			"service": sprite.get_meta("service", ""), "layer": sprite.get_meta("scenic_layer"),
			"below_player": sprite.z_index < 0})
	scene.free()
	return _parts

static func world_scale(map: TDTownMap, cell: float) -> float:
	return map.extent * cell / SIZE.x

static func _place(bounds: Rect2, origin: Vector2, scale_factor: float) -> Rect2:
	return Rect2(origin + bounds.position * scale_factor, bounds.size * scale_factor)

static func make_overview() -> SubViewport:
	var view := SubViewport.new()
	view.disable_3d = true
	view.transparent_bg = true
	view.size = Vector2i(730, 412)
	view.render_target_update_mode = SubViewport.UPDATE_ONCE
	var scene := make_scene()
	scene.scale = Vector2.ONE * (view.size.x / WORLD_SIZE.x)
	view.add_child(scene)
	return view

static func terrain_walkable(scene: Node2D, at: Vector2) -> bool:
	if not Rect2(Vector2.ZERO, WORLD_SIZE).has_point(at): return false
	for name: String in ["Wharf", "BridgeDeck"]:
		if _contains_tile(scene.get_node(name) as TileMapLayer, at): return true
	return not _contains_tile(scene.get_node("Woodlands") as TileMapLayer, at) \
		and _contains_tile(scene.get_node("Land") as TileMapLayer, at)

static func _contains_tile(layer: TileMapLayer, at: Vector2) -> bool:
	var point := layer.transform.affine_inverse() * at
	var cell := layer.local_to_map(point)
	var data := layer.get_cell_tile_data(cell)
	if data == null: return false
	var mask := int(data.get_custom_data("corner_mask"))
	if mask == 15: return true
	var size := Vector2(layer.tile_set.tile_size)
	var in_cell := (point - layer.map_to_local(cell)) / size + Vector2.ONE * .5
	# Samples exactly on a texel seam belong to its upper/left neighbour.
	# A small bias removes float error from the 2.5x layer transform.
	var pixel := Vector2i((in_cell*size-Vector2.ONE*.0005).floor().clamp(Vector2.ZERO,size-Vector2.ONE))
	in_cell = (Vector2(pixel)+Vector2.ONE*.5)/size
	var edge := .49+float((pixel.y*31+pixel.x*17)%7-3)*.013
	var top := lerpf(float((mask & 1) != 0), float((mask & 2) != 0), in_cell.x)
	var bottom := lerpf(float((mask & 8) != 0), float((mask & 4) != 0), in_cell.x)
	return lerpf(top, bottom, in_cell.y) >= edge

static func facades(map: TDTownMap, cell: float, origin: Vector2) -> Array[Dictionary]:
	var scale_factor := map.extent * cell / WORLD_SIZE.x
	var output: Array[Dictionary] = []
	for part: Dictionary in _parts_from_scene():
		var bounds := _place(part.rect, origin, scale_factor)
		var bases: Array[Rect2] = []
		for base: Rect2 in part.bases:
			bases.append(_place(base, origin, scale_factor))
		var plot := map._by_id(part.service) if not String(part.service).is_empty() else {}
		if part.service == "diner_lot" and not map._by_id("player_diner").is_empty():
			plot = map._by_id("player_diner")
		if part.service == "harbor.hekou": plot = TDHarbor.facility(map)
		var walking: Array[Rect2] = []
		for contact: Rect2 in part.walking:
			walking.append(_place(contact,origin,scale_factor))
		var sort_y := origin.y + float(part.foot) * scale_factor
		if part.below_player: sort_y = origin.y - 1.0
		output.append({"art": part.art, "rect": bounds, "bases": bases, "walking": bases if walking.is_empty() else walking, "sort_y": sort_y,
			"plot": plot, "reference_id": part.id, "reference_layer": part.layer})
	return output
