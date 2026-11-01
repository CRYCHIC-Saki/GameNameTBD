class_name TDPlannedTown
extends RefCounted
## Static terrain and authored plan, separate from ownership and market state.
const SOURCE := "res://content/towns/chinese_layout.json"
static var _definition: Dictionary={}

static func definition() -> Dictionary:
	if _definition.is_empty():
		var value: Variant=JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
		var checked := validate(value)
		if checked.ok: _definition=value
		else: push_error("Invalid town layout: "+checked.code)
	return _definition.duplicate(true)

static func validate(raw: Variant) -> TDOutcome:
	if not raw is Dictionary or raw.get("schema_version") != 2 or raw.get("size") != 73:
		return TDOutcome.new(false,"INVALID_LAYOUT_VERSION")
	for field: String in ["roads","plots","factory_origins","housing_blocks"]:
		if not raw.get(field) is Array or raw[field].is_empty(): return TDOutcome.new(false,"INVALID_LAYOUT_LIST",field)
	var ids: Dictionary={}
	var rectangles: Array=raw.roads.duplicate(true)+raw.housing_blocks.duplicate(true)
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
	return TDOutcome.new(true,"VALID_LAYOUT")

static func is_road(at: Vector2i) -> bool:
	for r: Array in definition().roads:
		if Rect2i(int(r[0]),int(r[1]),int(r[2]),int(r[3])).has_point(at): return true
	return false

static func terrain(at: Vector2i, road: bool) -> Dictionary:
	# Eastern border was non-buildable hills. A fixed public sea pier uses those
	# cells only; no authored property, factory, road, or valid old building moves.
	if at.x>=71:
		var pier: bool=at.x<73 and at.y>=33 and at.y<=35
		return {"terrain_type":"water","elevation":0,"surface_type":"bridge" if pier else "water","buildable":false,"walkable":pier}
	var river: bool=at.x>=53 and at.x<=55
	var hill: bool=at.y<5 or at.y>=72 or at.x<2 or at.x>=71
	var type: String="water" if river else ("hill" if hill else "plain")
	return {"terrain_type":type,"elevation":2 if hill else (0 if river else 1),"surface_type":"bridge" if river and road else ("stone" if road else ("water" if river else ("woodland" if hill else "grass"))),"buildable":not hill and not river and not road,"walkable":road or (not hill and not river)}

static func populate(map: TDTownMap, catalog: TDTownCatalog, place_diner: bool, reserve: Dictionary, built: Array, span: Vector2i, venue: String) -> void:
	var data:=definition()
	map.extent=int(data.size);map.plots=[];map.roads={};map.housing_names=[]
	var used: Dictionary={}
	for road: Array in data.roads:
		for y: int in range(int(road[1]),int(road[1]+road[3])):
			for x: int in range(int(road[0]),int(road[0]+road[2])): map.roads[Vector2i(x,y)]=true
	for raw: Dictionary in data.plots:
		var r: Array=raw.rect
		var extra:=raw.duplicate(true)
		if raw.kind=="market": extra.unlocks=TDTownMap.MARKET_TIERS[int(raw.tier)-1].unlocks.duplicate()
		map._commit(raw.kind,raw.name,int(r[0]),int(r[1]),int(r[2]),int(r[3]),used,extra)
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
		map._place_home_diner(span,used,venue if venue!="" else "chinese")
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
	# A generous western development parcel, away from the river and workshops.
	for y: int in range(48,map.extent-height):
		for x: int in range(6,19-width+1):
			if map.can_place(x,y,width,height) and map._touches_road(x,y,width,height): return Vector2i(x,y)
	return Vector2i(-1,-1)
