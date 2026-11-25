class_name TDPlannedTown
extends RefCounted
## Static terrain and authored plan, separate from ownership and market state.
const SOURCE := "res://content/towns/chinese_layout.json"
const REFERENCE_GEOGRAPHY := "res://content/towns/jiangnan_reference_geography.json"
const REFERENCE_FOOTPRINTS := "res://content/towns/jiangnan_map_footprints.json"
const REFERENCE_SIZE := Vector2(1670, 941)
const REFERENCE_PIXELS_PER_CELL := REFERENCE_SIZE.x / 73.0
static var _definition: Dictionary={}
static var _district_cells: Dictionary={}
static var _road_cells: Dictionary={}
static var _forests: Dictionary={}
static var _quays: Dictionary={}
static var _decks: Dictionary={}
static var _ocean: Dictionary={}
static var _terminal := Rect2i()
const ROAD_HALF_WIDTH := .57
static var _estuary_cells: Dictionary={}
static var _landing := Rect2i()
static var _reference_loaded := false
static var _reference_polygons: Dictionary = {}
static var _reference_road_segments: Array[Dictionary] = []
static var _reference_buildability: Dictionary = {}
static var _reference_bases: Array[Rect2] = []
static var _reference_bases_ready := false
static var _survey: Dictionary = {}
const SURVEY_SURFACES := {"g":"lawn","r":"stone","p":"square","f":"woodland","a":"sand",
	"b":"bridge","q":"quay","s":"sea","w":"water"}

const DISTRICT_SURFACES := ["lane", "lawn", "square", "quay", "earth"]

static func approved(map: TDTownMap) -> bool:
	return map.layout_version==2 and map.region_id.is_empty() and map.jiangnan_layout_revision==2

static func coast_height() -> int:
	if _definition.is_empty(): definition()
	return int(_definition.coast_height)

## Pixel coordinates are a survey of the approved art. The existing whole-cell
## plan remains the historical cadastral record for old saves and migrations.
static func _prepare_reference_geography() -> void:
	if _reference_loaded: return
	_reference_loaded = true
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(REFERENCE_GEOGRAPHY))
	if not raw is Dictionary or raw.get("schema_version") != 1:
		push_error("Invalid Jiangnan reference geography")
		return
	var size: Variant = raw.get("reference_size")
	if not size is Array or size.size() != 2 or size[0] != REFERENCE_SIZE.x or size[1] != REFERENCE_SIZE.y:
		push_error("Invalid Jiangnan reference dimensions")
		return
	for layer: String in ["land", "woods", "public_decks", "public_ground"]:
		if not raw.get(layer) is Dictionary or raw[layer].is_empty():
			push_error("Invalid Jiangnan reference geography layer: " + layer)
			_reference_polygons.clear()
			return
		var outlines: Array[Dictionary] = []
		for identity: String in raw[layer]:
			var pixels := _reference_outline(raw[layer][identity], 3)
			if pixels.is_empty():
				push_error("Invalid Jiangnan polygon: " + identity)
				_reference_polygons.clear()
				return
			outlines.append({"points": pixels, "bounds": _bounds_of(pixels)})
		_reference_polygons[layer] = outlines
	var road_rows: Variant = raw.get("road_centerlines")
	if not road_rows is Array or road_rows.is_empty():
		push_error("Missing Jiangnan road centerlines")
		_reference_polygons.clear()
		return
	for row: Variant in road_rows:
		if not row is Dictionary:
			push_error("Invalid Jiangnan road centerline")
			_reference_polygons.clear()
			_reference_road_segments.clear()
			return
		var pixels := _reference_outline(row.get("points"), 2)
		var radius := float(row.get("radius", 0))
		if pixels.is_empty() or not _valid_number(radius, 1, 40):
			push_error("Invalid Jiangnan road centerline")
			_reference_polygons.clear()
			_reference_road_segments.clear()
			return
		for index: int in range(1, pixels.size()):
			var start := pixels[index - 1]
			var end := pixels[index]
			_reference_road_segments.append({
				"start": start, "end": end, "radius": radius,
				"bounds": Rect2(start, Vector2.ZERO).expand(end).grow(radius)
			})

static func _reference_outline(raw: Variant, minimum: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	if not raw is Array or raw.size() < minimum: return points
	for pair: Variant in raw:
		if not pair is Array or pair.size() != 2 or not _valid_number(pair[0], 0, REFERENCE_SIZE.x) or not _valid_number(pair[1], 0, REFERENCE_SIZE.y):
			return PackedVector2Array()
		points.append(Vector2(pair[0], pair[1]))
	return points

static func _bounds_of(points: PackedVector2Array) -> Rect2:
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point: Vector2 in points: bounds = bounds.expand(point)
	return bounds

static func _reference_contains(pixel: Vector2, layer: String) -> bool:
	for shape: Dictionary in _reference_polygons.get(layer, []):
		if shape.bounds.has_point(pixel) and Geometry2D.is_point_in_polygon(pixel, shape.points):
			return true
	return false

static func reference_walkable_at_cell_position(at: Vector2) -> bool:
	_prepare_reference_geography()
	var pixel := at * REFERENCE_PIXELS_PER_CELL
	if not Rect2(Vector2.ZERO, REFERENCE_SIZE).has_point(pixel): return false
	return _reference_contains(pixel, "public_decks") or (
		_reference_contains(pixel, "land") and not _reference_contains(pixel, "woods")
	)

static func _prepare_reference_bases() -> bool:
	if _reference_bases_ready: return not _reference_bases.is_empty()
	_reference_bases_ready = true
	var metadata: Variant = JSON.parse_string(FileAccess.get_file_as_string(REFERENCE_FOOTPRINTS))
	if not metadata is Dictionary or not metadata.get("parts") is Array:
		push_error("Missing Jiangnan reference footprints")
		return false
	var survey: Dictionary = metadata.get("survey", {})
	if survey.get("version", 0) != 1 or survey.get("surfaces", []).size() != 73 or survey.get("flags", []).size() != 73:
		push_error("Missing Jiangnan parcel survey")
		return false
	for y: int in 73:
		if len(survey.surfaces[y]) != 73 or len(survey.flags[y]) != 73:
			push_error("Invalid Jiangnan parcel row")
			return false
	_survey = survey
	for part: Variant in metadata.parts:
		if not part is Dictionary or not part.get("bases") is Array:
			push_error("Invalid Jiangnan reference footprints")
			_reference_bases.clear()
			return false
		for base: Variant in part.bases:
			if not base is Array or base.size() != 4 or not base.all(
				func(value: Variant) -> bool: return _valid_number(value, 0, REFERENCE_SIZE.x)
			):
				push_error("Invalid Jiangnan reference footprint")
				_reference_bases.clear()
				return false
			var bounds := Rect2(float(base[0]), float(base[1]), float(base[2]), float(base[3]))
			if not bounds.has_area() or not Rect2(Vector2.ZERO, REFERENCE_SIZE).encloses(bounds):
				push_error("Jiangnan reference footprint out of bounds")
				_reference_bases.clear()
				return false
			_reference_bases.append(bounds)
	return not _reference_bases.is_empty()

## New construction must respect the surveyed shore and visible public spaces.
## Existing contracts continue to use the whole-cell layout that issued them.
static func reference_buildable_cell(at: Vector2i, issued := false) -> bool:
	_prepare_reference_geography()
	if not _prepare_reference_bases(): return false
	var flags := _survey_flags(at)
	if not (flags & 1) or (not issued and (flags & 8)): return false
	if _reference_buildability.has(at): return _reference_buildability[at]
	var box := Rect2(Vector2(at) * REFERENCE_PIXELS_PER_CELL, Vector2.ONE * REFERENCE_PIXELS_PER_CELL)
	var corners := PackedVector2Array([box.position, Vector2(box.end.x, box.position.y), box.end, Vector2(box.position.x, box.end.y)])
	var on_land := false
	for land: Dictionary in _reference_polygons.get("land", []):
		if land.bounds.encloses(box) and Geometry2D.clip_polygons(corners, land.points).is_empty():
			on_land = true
			break
	var available := on_land and not _overlaps_reference_public_space(box, corners)
	_reference_buildability[at] = available
	return available

static func _survey_flags(at: Vector2i) -> int:
	if not Rect2i(0,0,73,73).has_point(at) or _survey.is_empty(): return 0
	return int(_survey.flags[at.y][at.x])

static func reference_street_in_cell(at: Vector2i) -> bool:
	return _prepare_reference_bases() and (_survey_flags(at) & 2) != 0

static func reference_anchors() -> Dictionary:
	if not _prepare_reference_bases(): return {}
	return _survey.anchors.duplicate(true)

static func reference_terrain(at: Vector2i) -> Dictionary:
	_prepare_public_access()
	var surface := "sea"
	if _prepare_reference_bases() and Rect2i(0,0,73,73).has_point(at):
		surface = SURVEY_SURFACES.get(_survey.surfaces[at.y][at.x], "sea")
	var wet := surface in ["sea","water","bridge"]
	var wooded := surface == "woodland"
	var district: String = str(_district_cells.get(at,{}).get("id","outskirts"))
	if wet: district = "harbor"
	elif surface == "quay": district = "east_quays"
	return {"terrain_type":"water" if wet else ("hill" if wooded else "plain"),
		"surface_type":surface, "elevation":0 if wet else (2 if wooded else 1), "district_id":district,
		"walkable":surface not in ["sea","water","woodland"] and (_survey_flags(at) & 4) == 0,
		"buildable":surface == "lawn" and reference_buildable_cell(at)}

static func _overlaps_reference_public_space(box: Rect2, corners: PackedVector2Array) -> bool:
	for bounds: Rect2 in _reference_bases:
		if box.intersects(bounds): return true
	for layer: String in ["woods", "public_decks", "public_ground"]:
		for shape: Dictionary in _reference_polygons.get(layer, []):
			if box.intersects(shape.bounds) and not Geometry2D.intersect_polygons(corners, shape.points).is_empty():
				return true
	for segment: Dictionary in _reference_road_segments:
		if not box.intersects(segment.bounds): continue
		if box.has_point(segment.start) or box.has_point(segment.end): return true
		for index: int in corners.size():
			var nearest := Geometry2D.get_closest_points_between_segments(
				corners[index], corners[(index + 1) % corners.size()], segment.start, segment.end
			)
			if nearest[0].distance_to(nearest[1]) < segment.radius: return true
	return false

## Route the guide along the same visible streets and bridge decks the player
## uses. The scene supplies its own foot and current building collision check.
static func reference_escort_path(start: Vector2, goal: Vector2, can_stand: Callable, lanes: AStar2D) -> PackedVector2Array:
	if not can_stand.call(start) or not can_stand.call(goal): return PackedVector2Array()
	if start.distance_to(goal) <= 1.0 and _reference_segment_clear(start, goal, can_stand):
		return PackedVector2Array([start, goal])
	var streets := lanes.get_point_ids()
	var from_id := _attach_reference_escort_stop(lanes, streets, start, can_stand)
	var to_id := _attach_reference_escort_stop(lanes, streets, goal, can_stand)
	var result := lanes.get_point_path(from_id, to_id)
	lanes.remove_point(from_id)
	lanes.remove_point(to_id)
	return result

static func reference_road_graph(can_stand: Callable) -> AStar2D:
	_prepare_reference_geography()
	var lanes := AStar2D.new()
	var ids: Dictionary = {}
	for segment: Dictionary in _reference_road_segments:
		var a: Vector2 = segment.start / REFERENCE_PIXELS_PER_CELL
		var b: Vector2 = segment.end / REFERENCE_PIXELS_PER_CELL
		var samples := maxi(1, ceili(a.distance_to(b) / .26))
		var previous := -1
		for index: int in range(samples + 1):
			var position := a.lerp(b, float(index) / samples)
			var key := Vector2i((position * REFERENCE_PIXELS_PER_CELL * 10).round())
			if not ids.has(key):
				if not can_stand.call(position):
					ids[key] = -1
				else:
					ids[key] = lanes.get_available_point_id()
					lanes.add_point(ids[key], position)
			var current: int = ids[key]
			if previous >= 0 and current >= 0 and previous != current and _reference_segment_clear(
				lanes.get_point_position(previous), lanes.get_point_position(current), can_stand
			):
				lanes.connect_points(previous, current)
			previous = current
	return lanes

static func _attach_reference_escort_stop(lanes: AStar2D, streets: PackedInt64Array, at: Vector2, can_stand: Callable) -> int:
	var identity := lanes.get_available_point_id()
	lanes.add_point(identity, at)
	var nearby: Array[Dictionary] = []
	for id: int in streets:
		var distance := at.distance_squared_to(lanes.get_point_position(id))
		if distance <= 25.0:
			nearby.append({"id": id, "distance": distance})
	nearby.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.distance < b.distance)
	var exits := 0
	for item: Dictionary in nearby:
		if not _reference_segment_clear(at, lanes.get_point_position(item.id), can_stand): continue
		lanes.connect_points(identity, item.id)
		exits += 1
		if exits == 5: break
	return identity

static func _reference_segment_clear(a: Vector2, b: Vector2, can_stand: Callable) -> bool:
	var checks := maxi(1, ceili(a.distance_to(b) / .08))
	for index: int in range(1, checks + 1):
		if not can_stand.call(a.lerp(b, float(index) / checks)): return false
	return true

static func valid_districts(value: Variant) -> bool:
	if not value is Array or value.is_empty(): return false
	var ids := {}
	for row: Variant in value:
		if not row is Dictionary or not row.get("id") is String or row.id.is_empty() or ids.has(row.id): return false
		if row.get("surface") not in DISTRICT_SURFACES or not row.get("outline") is Array or row.outline.size()<3: return false
		ids[row.id] = true
		for point: Variant in row.outline:
			if not point is Array or point.size()!=2: return false
			for n: Variant in point:
				if not TDServiceCatalog.integer(n, 0, 73): return false
	return true

## First polygon wins where a quay or neighborhood meets a larger hinterland.
## Rasterized once per region, so rendering and per-cell quotes sample the same plan.
static func district_cells(rows: Array) -> Dictionary:
	var cells := {}
	for row: Dictionary in rows:
		var points := PackedVector2Array()
		for p: Array in row.outline: points.append(Vector2(p[0],p[1]))
		var bounds := Rect2(points[0],Vector2.ZERO)
		for p: Vector2 in points: bounds=bounds.expand(p)
		for y: int in range(floori(bounds.position.y),ceili(bounds.end.y)):
			for x: int in range(floori(bounds.position.x),ceili(bounds.end.x)):
				var at := Vector2i(x,y)
				if not cells.has(at) and Geometry2D.is_point_in_polygon(Vector2(at)+Vector2.ONE*.5,points):
					cells[at]=row
	return cells

static func definition() -> Dictionary:
	if _definition.is_empty():
		var value: Variant=JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
		var checked := validate(value)
		if checked.ok: _definition=value
		else: push_error("Invalid town layout: "+checked.code)
	return _definition.duplicate(true)

static func _rect(value: Array) -> Rect2i:
	return Rect2i(int(value[0]),int(value[1]),int(value[2]),int(value[3]))

static func pavilion_landing() -> Rect2i:
	if not _landing.has_area():
		_landing = _rect(definition().panorama.pavilion_landing)
	return _landing

## Translate the authored map labels to live parcel coordinates. Call when
## the town is built, then reuse the result while drawing or moving the camera.
static func panorama_zones(map: TDTownMap) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if map.layout_version != 2 or not map.region_id.is_empty(): return result
	if _definition.is_empty(): definition()
	for zone: Dictionary in _definition.panorama.zones:
		var anchor := map._by_id(zone.anchor)
		if anchor.is_empty(): continue
		var at := Vector2(float(anchor.x)+zone.offset[0],float(anchor.y)+zone.offset[1])
		result.append({"id":zone.id,"label":zone.label,"anchor":zone.anchor,"at":at})
	return result

static func validate(raw: Variant) -> TDOutcome:
	if not raw is Dictionary or raw.get("schema_version") != 2 or raw.get("size") != 73:
		return TDOutcome.new(false,"INVALID_LAYOUT_VERSION")
	if not raw.get("survey_commercial_sites") is Array or not raw.get("commercial_parcels") is Array or raw.survey_commercial_sites.size() < raw.commercial_parcels.size():
		return TDOutcome.new(false,"INVALID_COMMERCIAL_SURVEY")
	for site: Variant in raw.survey_commercial_sites:
		if not site is Array or site.size()!=4 or not site.all(func(n: Variant) -> bool: return TDServiceCatalog.integer(n,0,72)):
			return TDOutcome.new(false,"INVALID_COMMERCIAL_SURVEY")
	if not valid_districts(raw.get("districts")): return TDOutcome.new(false,"INVALID_DISTRICTS")
	if not valid_waterworks(raw): return TDOutcome.new(false,"INVALID_WATERWORKS")
	if raw.bridge_spans.size()!=2: return TDOutcome.new(false,"INVALID_JIANGNAN_BRIDGES")
	if not TDServiceCatalog.integer(raw.get("coast_height"),32,73): return TDOutcome.new(false,"INVALID_COAST")
	for field: String in ["roads","plots","factory_origins","housing_blocks","quays"]:
		if not raw.get(field) is Array or raw[field].is_empty(): return TDOutcome.new(false,"INVALID_LAYOUT_LIST",field)
	for path: Variant in raw.roads:
		if not _valid_points(path,2): return TDOutcome.new(false,"INVALID_ROAD_PATH")
	for field: String in ["water","forests"]:
		if not raw.get(field) is Array or raw[field].is_empty(): return TDOutcome.new(false,"INVALID_LAYOUT_POLYGON",field)
		for outline: Variant in raw[field]:
			if not _valid_points(outline,3): return TDOutcome.new(false,"INVALID_LAYOUT_POLYGON",field)
	if not _valid_points(raw.get("headland"),3): return TDOutcome.new(false,"INVALID_LANDMARK_SHORE")
	if not raw.get("courts") is Array: return TDOutcome.new(false,"INVALID_COURTS")
	for court: Variant in raw.courts:
		if not court is Dictionary or court.get("kind")!="stone" or not _valid_points(court.get("outline"),3):
			return TDOutcome.new(false,"INVALID_COURTS")
	var harbor: Variant = raw.get("harbor")
	if not harbor is Dictionary or not _valid_points([harbor.get("arrival"),harbor.get("guide")],2):
		return TDOutcome.new(false,"INVALID_HARBOR")
	for field: String in ["booth","quay","deck"]:
		if not _valid_rect(harbor.get(field)): return TDOutcome.new(false,"INVALID_HARBOR")
	var ids: Dictionary={}
	var rectangles: Array=raw.quays+raw.housing_blocks
	for plot: Variant in raw.plots:
		if not plot is Dictionary or not plot.get("id") is String or ids.has(plot.id) or not plot.get("kind") is String or not plot.get("name") is String:
			return TDOutcome.new(false,"INVALID_LAYOUT_PLOT")
		if plot.has("door") and not _valid_points([plot.door],1): return TDOutcome.new(false,"INVALID_APPROACH")
		if plot.has("facade"):
			var pose: Variant = plot.facade
			if not pose is Array or pose.size()!=3 or not _valid_points([pose.slice(0,2)],1):
				return TDOutcome.new(false,"INVALID_FACADE")
			if not _valid_number(pose[2],.5,20): return TDOutcome.new(false,"INVALID_FACADE")
		ids[plot.id]=true
		rectangles.append(plot.get("rect"))
	for r: Variant in rectangles:
		if not r is Array or r.size()!=4: return TDOutcome.new(false,"INVALID_LAYOUT_RECT")
		for number: Variant in r:
			if not TDServiceCatalog.integer(number,0,73): return TDOutcome.new(false,"INVALID_LAYOUT_RECT")
		if r[2]<1 or r[3]<1 or r[0]+r[2]>73 or r[1]+r[3]>73: return TDOutcome.new(false,"INVALID_LAYOUT_BOUNDS")
	if raw.factory_origins.size()!=8: return TDOutcome.new(false,"INVALID_FACTORY_COUNT")
	for at: Variant in raw.factory_origins:
		if not at is Array or at.size()!=2 or not TDServiceCatalog.integer(at[0],0,71) or not TDServiceCatalog.integer(at[1],0,71): return TDOutcome.new(false,"INVALID_FACTORY_POSITION")
	if not _valid_panorama(raw.get("panorama"),ids): return TDOutcome.new(false,"INVALID_PANORAMA")
	return TDOutcome.new(true,"VALID_LAYOUT")

static func _valid_panorama(value: Variant, plot_ids: Dictionary) -> bool:
	if not value is Dictionary: return false
	for key: String in ["home_front","pavilion_landing"]:
		if not _valid_rect(value.get(key)): return false
	if not value.get("zones") is Array or value.zones.size()!=8 or not value.get("sites") is Array: return false
	var ids := {}
	for zone: Variant in value.zones:
		if not zone is Dictionary or not zone.get("id") is String or ids.has(zone.id) or not zone.get("label") is String or zone.label.is_empty(): return false
		if not plot_ids.has(zone.get("anchor")) or not zone.get("offset") is Array or zone.offset.size()!=2: return false
		for axis: Variant in zone.offset:
			if not TDServiceCatalog.integer(axis,-72,72): return false
		ids[zone.id] = true
	for site: Variant in value.sites:
		if not site is Dictionary or not site.get("id") is String or ids.has(site.id) or not _valid_rect(site.get("rect")): return false
		if site.get("surface") not in ["soil","mud","gravel","turf","old_stone"] or not site.get("side") is Array or site.side.size()!=2: return false
		if not TDServiceCatalog.integer(site.side[0],-1,1) or not TDServiceCatalog.integer(site.side[1],-1,1) or absi(int(site.side[0]))+absi(int(site.side[1]))!=1: return false
		if site.has("allow_plot") and not plot_ids.has(site.allow_plot): return false
		ids[site.id] = true
	return true

static func _valid_rect(value: Variant) -> bool:
	if not value is Array or value.size()!=4: return false
	for axis: Variant in value:
		if not TDServiceCatalog.integer(axis,0,73): return false
	var box := _rect(value)
	return box.has_area() and box.end.x<=73 and box.end.y<=73

static func _valid_number(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is float or value is int) and float(value)>=minimum and float(value)<=maximum

static func _valid_points(value: Variant, count: int) -> bool:
	if not value is Array or value.size()<count: return false
	for point: Variant in value:
		if not point is Array or point.size()!=2: return false
		if not _valid_number(point[0],0,73) or not _valid_number(point[1],0,73): return false
	return true

static func valid_waterworks(plan: Dictionary) -> bool:
	if not _valid_points(plan.get("estuary"),3): return false
	if not plan.get("bridge_spans") is Array or plan.bridge_spans.is_empty(): return false
	for span: Variant in plan.bridge_spans:
		if not _valid_rect(span) or span[2]<=span[3]: return false
	return true

static func bridge_cells(plan: Dictionary) -> Dictionary:
	var cells := {}
	for span: Array in plan.bridge_spans:
		for y: int in range(int(span[1]),int(span[1]+span[3])):
			for x: int in range(int(span[0]),int(span[0]+span[2])):
				cells[Vector2i(x,y)]=true
	return cells

static func is_road(at: Vector2i) -> bool:
	_prepare_public_access()
	return _road_cells.has(at)

## Footpaths, the coastline and the economic map are surveyed from the same plan.
static func _prepare_public_access() -> void:
	if not _road_cells.is_empty(): return
	var plan := definition()
	_decks = bridge_cells(plan)
	var wet_polygons: Array = []
	for outline: Array in plan.water: wet_polygons.append({"outline":outline})
	_estuary_cells = district_cells(wet_polygons)
	var headland := district_cells([{"outline":plan.headland}])
	for at: Vector2i in headland: _estuary_cells.erase(at)
	_ocean = district_cells([{"outline":plan.estuary}])
	_terminal = _rect(plan.harbor.booth)
	var woodland: Array = []
	for outline: Array in plan.forests: woodland.append({"outline":outline})
	_forests = district_cells(woodland)
	_district_cells = district_cells(plan.districts)
	for bounds: Array in plan.quays:
		var rect := _rect(bounds)
		for y: int in range(rect.position.y,rect.end.y):
			for x: int in range(rect.position.x,rect.end.x):
				_quays[Vector2i(x,y)] = true
	var court_cells := district_cells(plan.courts)
	for path: Array in plan.roads:
		for i: int in range(1,path.size()):
			var a := Vector2(path[i-1][0],path[i-1][1])
			var b := Vector2(path[i][0],path[i][1])
			var box := Rect2(a,Vector2.ZERO).expand(b).grow(1.2)
			for y: int in range(floori(box.position.y),ceili(box.end.y)):
				for x: int in range(floori(box.position.x),ceili(box.end.x)):
					var at := Vector2i(x,y)
					var center := Vector2(at)+Vector2.ONE*.5
					if center.distance_to(Geometry2D.get_closest_point_to_segment(center,a,b))<=.86:
						_register_road(at)
	for at: Vector2i in court_cells: _register_road(at)
	for at: Vector2i in _quays: _register_road(at)
	for at: Vector2i in _decks: _register_road(at)

static func _register_road(at: Vector2i) -> void:
	if at.x<0 or at.y<0 or at.x>=73 or at.y>=73: return
	if not _estuary_cells.has(at) or _decks.has(at) or _quays.has(at):
		_road_cells[at] = true

static func terrain(at: Vector2i, road: bool) -> Dictionary:
	_prepare_public_access()
	if _quays.has(at) or pavilion_landing().has_point(at):
		return {"terrain_type":"plain","elevation":1,"surface_type":"quay","district_id":"east_quays",
			"buildable":false,"walkable":true}
	if _estuary_cells.has(at):
		var surface := "bridge" if _decks.has(at) else ("sea" if _ocean.has(at) else "water")
		return {"terrain_type":"water","elevation":0,"surface_type":surface,"district_id":"harbor",
			"buildable":false,"walkable":surface=="bridge"}
	var wooded := _forests.has(at)
	var surface := "stone" if road else ("woodland" if wooded else "lawn")
	var zone: Dictionary = _district_cells.get(at,{})
	return {"terrain_type":"hill" if wooded and not road else "plain","elevation":2 if wooded else 1,
		"surface_type":surface,"district_id":str(zone.get("id","outskirts")),
		"buildable":not road and not wooded and not _terminal.has_point(at),"walkable":road or not wooded}

static func populate(map: TDTownMap, catalog: TDTownCatalog, place_diner: bool, reserve: Dictionary, built: Array, span: Vector2i, venue: String) -> void:
	var data:=definition()
	_prepare_public_access()
	map.extent=int(data.size);map.plots=[];map.roads=_road_cells.duplicate();map.housing_names=[]
	var used: Dictionary={}
	for raw: Dictionary in data.plots:
		var r: Array=raw.rect
		var extra:=raw.duplicate(true)
		if raw.kind=="market": extra.unlocks=TDTownMap.MARKET_TIERS[int(raw.tier)-1].unlocks.duplicate()
		map._commit(raw.kind,raw.name,int(r[0]),int(r[1]),int(r[2]),int(r[3]),used,extra)
		var plot: Dictionary=map.plots.back()
		if plot.id == "commercial_street": plot.economic_courtyard = true
		if raw.has("facade"): plot.facade_anchor = raw.facade.duplicate()
		if raw.has("door"):
			plot.approach_x = int(raw.door[0])
			plot.approach_y = int(raw.door[1])
			continue
		var bounds:=Rect2i(int(r[0]),int(r[1]),int(r[2]),int(r[3]))
		if not bounds.grow(1).has_point(Vector2i(plot.approach_x,plot.approach_y)):
			# A doorstep set back from the public street still uses its own
			# front path, not the historical (20,20) default used by legacy maps.
			var front:=Vector2i(bounds.get_center().x,bounds.end.y)
			var nearest:=Vector2i(plot.approach_x,plot.approach_y)
			for cell: Vector2i in map.roads:
				if cell.distance_squared_to(front)<nearest.distance_squared_to(front): nearest=cell
			plot.approach_x=nearest.x;plot.approach_y=nearest.y
	for index: int in data.factory_origins.size():
		var p: Array=data.factory_origins[index];var supply:=TDTownMap.supply_of_slot(index+1)
		map._commit("factory_lot",TDTownMap.supply_name(supply,false),int(p[0]),int(p[1]),2,2,used,{"id":"factory-%d"%(index+1),"slot":index+1,"supply":supply})
	map._mark_built_factories(built)
	for r: Array in data.housing_blocks:
		for y: int in range(int(r[1]),int(r[1]+r[3])):
			for x: int in range(int(r[0]),int(r[0]+r[2])):
				map._commit("housing","青瓦人家",x,y,1,1,used,{"id":"house-%d-%d"%[x,y]})
	if place_diner:
		if span==Vector2i.ZERO: span=Vector2i(6,9)
		map._place_home_diner(span,used,venue if venue!="" else "chinese",_rect(data.panorama.home_front))
		if not map.plots.is_empty() and map.plots.back().id=="player_diner":
			var diner: Dictionary = map.plots.back()
			diner.facade_anchor = [30.35,21.35,7.0]
			diner.approach_x = 30
			diner.approach_y = 21
	if not reserve.is_empty():
		var at:=Vector2i(int(reserve.x),int(reserve.y))
		if map.can_place(at.x,at.y,int(reserve.w),int(reserve.h)):
			map._commit("player_diner","分店",at.x,at.y,int(reserve.w),int(reserve.h),used,{"id":"branch_diner","size":str(reserve.size)})
	map._copy_catalog(catalog)
	# Authored names stay readable; economic zone IDs remain the historical stable IDs.
	for raw: Dictionary in data.plots:
		for plot: Dictionary in map.plots:
			if plot.id==raw.id: plot.name=raw.name
	if not map.cottage.is_empty(): map.install_cottage(map.cottage)

static func branch_site(map: TDTownMap, width: int, height: int) -> Vector2i:
	for y: int in range(3,int(_definition.coast_height)-height):
		for x: int in range(2,map.extent-width):
			if map.can_place(x,y,width,height) and map._touches_road(x,y,width,height):
				return Vector2i(x,y)
	return Vector2i(-1,-1)
