class_name TDLegacyJiangnanLayout
extends RefCounted
## Static terrain and authored plan, separate from ownership and market state.
const SOURCE := "res://content/towns/chinese_layout_legacy.json"
static var _definition: Dictionary={}
static var _district_cells: Dictionary={}
static var _road_cells: Dictionary={}
static var _grass_walkways: Dictionary={}
static var _inlet_cells: Dictionary={}
static var _estuary_cells: Dictionary={}
static var _landing := Rect2i()

const DISTRICT_SURFACES := ["lane", "lawn", "square", "quay", "earth"]

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
	if not valid_districts(raw.get("districts")): return TDOutcome.new(false,"INVALID_DISTRICTS")
	if not valid_waterworks(raw): return TDOutcome.new(false,"INVALID_WATERWORKS")
	var inlet: Variant=raw.get("garden_inlet")
	if not inlet is Dictionary or not inlet.get("origin") is Array or inlet.origin.size()!=2 or inlet.get("id")!="lotus_inlet":
		return TDOutcome.new(false,"INVALID_INLET")
	if not inlet.get("rows") is Array or inlet.rows.is_empty(): return TDOutcome.new(false,"INVALID_INLET")
	for n: Variant in inlet.origin:
		if not TDServiceCatalog.integer(n,0,72): return TDOutcome.new(false,"INVALID_INLET")
	if inlet.origin[1]+inlet.rows.size()>73: return TDOutcome.new(false,"INVALID_INLET")
	for row: Variant in inlet.rows:
		if not row is String or row.is_empty() or row.length()+inlet.origin[0]>73: return TDOutcome.new(false,"INVALID_INLET")
		for symbol: String in row:
			if not "~=.g ".contains(symbol): return TDOutcome.new(false,"INVALID_INLET")
	for field: String in ["roads","plots","factory_origins","housing_blocks"]:
		if not raw.get(field) is Array or raw[field].is_empty(): return TDOutcome.new(false,"INVALID_LAYOUT_LIST",field)
	var ids: Dictionary={}
	if not raw.get("grass_walkways",[]) is Array: return TDOutcome.new(false,"INVALID_LAYOUT_LIST","grass_walkways")
	var rectangles: Array=raw.roads+raw.get("grass_walkways",[])+raw.housing_blocks
	for plot: Variant in raw.plots:
		if not plot is Dictionary or not plot.get("id") is String or ids.has(plot.id) or not plot.get("kind") is String or not plot.get("name") is String:
			return TDOutcome.new(false,"INVALID_LAYOUT_PLOT")
		ids[plot.id]=true;rectangles.append(plot.get("rect"))
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

static func valid_waterworks(plan: Dictionary) -> bool:
	if not plan.get("estuary") is Array or plan.estuary.size()<3: return false
	for p: Variant in plan.estuary:
		if not p is Array or p.size()!=2: return false
		for n: Variant in p:
			if not TDServiceCatalog.integer(n,0,73): return false
	if not plan.get("bridge_spans") is Array or plan.bridge_spans.is_empty(): return false
	for span: Variant in plan.bridge_spans:
		if not span is Array or span.size()!=4: return false
		for n: Variant in span:
			if not TDServiceCatalog.integer(n,1,71): return false
		if span[2]<=span[3] or span[0]+span[2]>=73 or span[1]+span[3]>=73: return false
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

## Both streets and grass approaches carry foot traffic and reserve public land.
static func _prepare_public_access() -> void:
	if not _road_cells.is_empty(): return
	var plan := definition()
	var decks := bridge_cells(plan)
	_estuary_cells = district_cells([{"outline":plan.estuary}])
	for group: String in ["roads","grass_walkways"]:
		for r: Array in plan.get(group,[]):
			for y: int in range(int(r[1]),int(r[1]+r[3])):
				for x: int in range(int(r[0]),int(r[0]+r[2])):
					var cell := Vector2i(x,y)
					if x>=53 and x<=55 and not decks.has(cell): continue
					_road_cells[cell] = true
					if group=="grass_walkways": _grass_walkways[cell] = true

static func terrain(at: Vector2i, road: bool) -> Dictionary:
	# Eastern border was non-buildable hills. A fixed public sea pier uses those
	# cells only; no authored property, factory, road, or valid old building moves.
	if at.x>=71:
		var pier: bool=at.x<73 and at.y>=33 and at.y<=35
		return {"terrain_type":"water","elevation":0,"surface_type":"bridge" if pier else "water","district_id":"harbor","buildable":false,"walkable":pier}
	_prepare_public_access()
	var river: bool=(at.x>=53 and at.x<=55) or _estuary_cells.has(at)
	if river and pavilion_landing().has_point(at):
		return {"terrain_type":"water","elevation":0,"surface_type":"water","district_id":"pavilion_landing","buildable":false,"walkable":true}
	if _inlet_cells.is_empty():
		var inlet: Dictionary=definition().garden_inlet
		var corner:=Vector2i(inlet.origin[0],inlet.origin[1])
		var symbols: Dictionary={"~":"water","=":"bridge",".":"quay","g":"grass"}
		for y: int in inlet.rows.size():
			var row: String=inlet.rows[y]
			for x: int in row.length():
				if symbols.has(row[x]): _inlet_cells[corner+Vector2i(x,y)]=symbols[row[x]]
	if _inlet_cells.has(at):
		var cover: String=_inlet_cells[at]
		var wet:=cover in ["bridge","water"]
		return {"terrain_type":"water" if wet else "plain","elevation":0 if wet else 1,"surface_type":cover,"district_id":"lotus_inlet","buildable":false,"walkable":cover!="water"}
	var hill: bool=at.y<5 or at.y>=72 or at.x<2 or at.x>=71
	var type: String="water" if river else ("hill" if hill else "plain")
	if _district_cells.is_empty(): _district_cells=district_cells(definition().districts)
	var zone: Dictionary=_district_cells.get(at,{})
	var surface := str(zone.get("surface","grass"))
	if hill: surface="woodland"
	if river: surface="water"
	if road:
		_prepare_public_access()
		surface="bridge" if river else ("lawn" if _grass_walkways.has(at) else "stone")
	return {"terrain_type":type,"elevation":2 if hill else (0 if river else 1),"surface_type":surface,"district_id":str(zone.get("id","outskirts")),"buildable":not hill and not river and not road,"walkable":road or (not hill and not river)}

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
	for plot: Dictionary in map.plots:
		plot.jiangnan_layout_revision=1

static func branch_site(map: TDTownMap, width: int, height: int) -> Vector2i:
	# A generous western development parcel, away from the river and workshops.
	for y: int in range(48,map.extent-height):
		for x: int in range(6,19-width+1):
			if map.can_place(x,y,width,height) and map._touches_road(x,y,width,height): return Vector2i(x,y)
	return Vector2i(-1,-1)
