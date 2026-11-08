class_name TDRegionalLayout
extends RefCounted
## Shared geography for exploration, property validation and economic distances.
const SOURCE := "res://content/towns/regions.json"
const IDS := ["tokyo","paris","bangkok","mexico_city"]
const SIZE := 73
static var _data: Dictionary = {}
static var _cache: Dictionary = {}

static func definition(id: String) -> Dictionary:
	if _data.is_empty():
		var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
		var checked:=validate(raw)
		if not checked.ok: push_error(checked.code+": "+checked.message);return {}
		_data=raw
	return _data.towns.get(id,{}).duplicate(true)

static func validate(raw: Variant) -> TDOutcome:
	if not raw is Dictionary or raw.get("schema_version")!=2 or raw.get("size")!=SIZE or not raw.get("towns") is Dictionary: return TDOutcome.new(false,"REGION_SCHEMA")
	if raw.towns.size()!=IDS.size(): return TDOutcome.new(false,"REGION_COUNT")
	for id: String in IDS:
		var d: Variant=raw.towns.get(id)
		if not d is Dictionary: return TDOutcome.new(false,"REGION_MISSING",id)
		for key: String in ["land","rivers","hills","roads","plots","port"]:
			if not d.get(key) is Array: return TDOutcome.new(false,"REGION_FIELD",id+":"+key)
		if d.port.size()!=2 or d.land.size()<3 or d.roads.is_empty(): return TDOutcome.new(false,"REGION_GEOMETRY",id)
		var points: Array=d.land.duplicate()+[d.port]
		for line: Variant in d.rivers+d.roads:
			if not line is Array or line.size()<2: return TDOutcome.new(false,"REGION_LINE",id)
			points.append_array(line)
		for point: Variant in points:
			if not point is Array or point.size()!=2: return TDOutcome.new(false,"REGION_POINT",id)
			for n: Variant in point:
				if not TDServiceCatalog.integer(n,-2,75): return TDOutcome.new(false,"REGION_POINT",id)
		var used: Dictionary={};var keys: Dictionary={}
		for plot: Variant in d.plots:
			if not plot is Array or plot.size()!=6 or not plot[0] is String or not plot[1] is String or keys.has(plot[0]): return TDOutcome.new(false,"REGION_PLOT",id)
			keys[plot[0]]=true
			for n: Variant in plot.slice(2):
				if not TDServiceCatalog.integer(n,1,71): return TDOutcome.new(false,"REGION_RECT",id)
			var r:=Rect2i(int(plot[2]),int(plot[3]),int(plot[4]),int(plot[5]))
			if r.end.x>=SIZE or r.end.y>=SIZE: return TDOutcome.new(false,"REGION_BOUNDS",id)
			for y: int in range(r.position.y,r.end.y):
				for x: int in range(r.position.x,r.end.x):
					var at:=Vector2i(x,y)
					if used.has(at): return TDOutcome.new(false,"REGION_OVERLAP",id+":"+str(plot[0]))
					used[at]=true
		for key: String in ["competitor","commercial_street"]:
			if not keys.has(key): return TDOutcome.new(false,"REGION_COMMERCIAL",id)
		for hill: Variant in d.hills:
			if not hill is Array or hill.size()!=4: return TDOutcome.new(false,"REGION_HILL",id)
			for n: Variant in hill:
				if not TDServiceCatalog.integer(n,0,73): return TDOutcome.new(false,"REGION_HILL",id)
	return TDOutcome.new(true,"VALID_REGIONS")

static func port(id: String) -> Vector2i:
	var p: Array=definition(id).port
	return Vector2i(p[0],p[1])

static func _point(p: Array) -> Vector2:
	return Vector2(p[0],p[1])

static func _inside(at: Vector2i) -> bool:
	return at.x>0 and at.y>0 and at.x<SIZE-1 and at.y<SIZE-1

static func _prepare(id: String) -> void:
	if _cache.has(id): return
	var d:=definition(id)
	if d.is_empty(): return
	var polygon:=PackedVector2Array()
	for p: Array in d.land: polygon.append(_point(p))
	var ground: Dictionary={};var solids: Dictionary={}
	for p: Array in d.plots:
		for y: int in range(int(p[3]),int(p[3]+p[5])):
			for x: int in range(int(p[2]),int(p[2]+p[4])): solids[Vector2i(x,y)]=true
	for y: int in SIZE:
		for x: int in SIZE:
			var at:=Vector2i(x,y);var center:=Vector2(at)+Vector2.ONE*.5
			var type: String="plain" if Geometry2D.is_point_in_polygon(center,polygon) else "sea"
			for line: Array in d.rivers:
				for i: int in range(1,line.size()):
					if center.distance_to(Geometry2D.get_closest_point_to_segment(center,_point(line[i-1]),_point(line[i])))<1.25: type="water"
			for h: Array in d.hills:
				var r:=Rect2(float(h[0]),float(h[1]),float(h[2]),float(h[3]))
				if r.has_point(center) and ((center-r.get_center())/(r.size*.5)).length_squared()<1.0 and type=="plain": type="hill"
			if not _inside(at) and type=="plain": type="hill"
			ground[at]=type
	var grid:=AStarGrid2D.new();grid.region=Rect2i(0,0,SIZE,SIZE);grid.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_NEVER;grid.update()
	for at: Vector2i in ground:
		grid.set_point_solid(at,solids.has(at) or ground[at] in ["sea","hill"] or not _inside(at))
		if ground[at]=="water": grid.set_point_weight_scale(at,3.0)
	var roads: Dictionary={}
	for line: Array in d.roads:
		for i: int in range(1,line.size()):
			var a:=Vector2i(_point(line[i-1]));var b:=Vector2i(_point(line[i]))
			var path:=grid.get_id_path(a,b)
			for at: Vector2i in path:
				for dy: int in range(-1,2):
					for dx: int in range(-1,2):
						var cell:=at+Vector2i(dx,dy)
						if grid.is_in_boundsv(cell) and not grid.is_point_solid(cell): roads[cell]=true
	# Small front paths join each authored block; no road cuts through property.
	for p: Array in d.plots:
		var door:=Vector2i(int(p[2])+int(p[4])/2,int(p[3]+p[5]))
		var nearest:=Vector2i(-1,-1);var distance: float=INF
		for at: Vector2i in roads:
			if Vector2(at).distance_squared_to(door)<distance: nearest=at;distance=Vector2(at).distance_squared_to(door)
		if nearest.x>=0 and not grid.is_point_solid(door):
			for at: Vector2i in grid.get_id_path(door,nearest): roads[at]=true
	_cache[id]={"ground":ground,"roads":roads}

static func roads(id: String) -> Dictionary:
	_prepare(id)
	return _cache[id].roads.duplicate()

static func terrain(id: String, at: Vector2i) -> Dictionary:
	_prepare(id)
	var type: String=_cache[id].ground.get(at,"sea")
	var road: bool=_cache[id].roads.has(at)
	var water: bool=type in ["sea","water"]
	var shore: bool=false
	if type=="plain" and not road:
		for offset: Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			if _cache[id].ground.get(at+offset,"")=="sea": shore=true
	return {"terrain_type":"water" if water else type,"elevation":0 if water else (3 if type=="hill" else 1),"surface_type":"bridge" if water and road else ("stone" if road else ("water" if water else ("woodland" if type=="hill" else ("sand" if shore else "grass")))),"walkable":road or type=="plain","buildable":type=="plain" and not road and not shore}

static func populate(map: TDTownMap, catalog: TDTownCatalog, id: String) -> TDOutcome:
	map.region_id=id;map.layout_version=2;map.extent=SIZE;map.plots=[];map.roads=roads(id)
	var used: Dictionary={}
	for p: Array in definition(id).plots:
		for y: int in range(int(p[3]),int(p[3]+p[5])):
			for x: int in range(int(p[2]),int(p[2]+p[4])):
				if terrain(id,Vector2i(x,y)).terrain_type!="plain": return TDOutcome.new(false,"REGION_PROPERTY_TERRAIN",id+":"+str(p[0])+":"+str(Vector2i(x,y)))
		map._commit(p[1],p[0],int(p[2]),int(p[3]),int(p[4]),int(p[5]),used,{"id":p[0]})
	map._copy_catalog(catalog)
	for p: Dictionary in map.plots: p.region_layout_version=2
	if not map.roads.has(port(id)): return TDOutcome.new(false,"REGION_PORT_DISCONNECTED",id)
	return TDOutcome.new(true,"REGION_READY")
