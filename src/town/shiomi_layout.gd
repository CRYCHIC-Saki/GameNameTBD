class_name TDShiomiLayout
extends RefCounted
## Coordinates shared by native tiles, travel, rental surveys and the atlas.
const OFFSET := Vector2(8,17)
const PIXELS_PER_CELL := 24.0
static var data: Dictionary:
	get:
		if data.is_empty(): data=JSON.parse_string(FileAccess.get_file_as_string("res://content/towns/shiomi_survey.json"))
		return data
const SURFACES := {".":"lawn","r":"stone","g":"square","z":"raked_gravel","d":"pier","q":"quay","b":"bridge","^":"cliff","k":"rock","o":"reef","p":"paddy","v":"gravel","s":"sand","~":"sea","i":"water"}
const MAP_SIZE := Vector2i(1536,1024)
static var _foot_mask := PackedByteArray()
static var _routes: Dictionary = {}
static var _terrain_cache: Dictionary = {}
# Neighborhood centres in reference pixels. Multiple centres follow the curved
# market street and coast rather than cutting them at an arbitrary row of lots.
const NEIGHBORHOODS := {
	"shrine_ridge":[Vector2(252,211),Vector2(584,102)],
	"shiomi_machiya":[Vector2(545,285),Vector2(388,441),Vector2(222,542)],
	"noh_square":[Vector2(449,634)],
	"civic_centre":[Vector2(792,501),Vector2(946,288)],
	"spring_ravine":[Vector2(1267,205),Vector2(1211,311)],
	"fish_wharf":[Vector2(1270,492),Vector2(1405,605)],
	"mill_fields":[Vector2(203,787),Vector2(331,844)],
	"onsen_coast":[Vector2(808,785),Vector2(983,783),Vector2(1248,849)]}
const EXPANSION_SITES := [[25,24],[28,32],[38,33]]

static func world_point(point: Vector2) -> Vector2:
	return (OFFSET + point/PIXELS_PER_CELL)*TDTownWorld.CELL

static func visible_lawn(at: Vector2i) -> bool:
	return Rect2i(0,0,73,73).has_point(at) and data.visible_lawn[at.y][at.x]=="."

static func foot_clear(point: Vector2) -> bool:
	var px:=Vector2i(point.floor())
	if not Rect2i(Vector2i.ZERO,MAP_SIZE).has_point(px): return false
	if _foot_mask.is_empty():
		_foot_mask=Marshalls.base64_to_raw(data.walk_bits).decompress(MAP_SIZE.x*MAP_SIZE.y/8,FileAccess.COMPRESSION_DEFLATE)
	var index:=px.y*MAP_SIZE.x+px.x
	return (_foot_mask[index >> 3] & (1 << (index & 7))) != 0

static func route_minutes(at: Vector2i) -> Dictionary:
	if _routes.is_empty():
		for kind: String in data.travel: _routes[kind]=Marshalls.base64_to_raw(data.travel[kind])
	var values: Dictionary={}
	for kind: String in _routes:
		var cost: int=_routes[kind][at.y*73+at.x] if Rect2i(0,0,73,73).has_point(at) else 255
		values[kind]=float(cost)*.1 if cost!=255 else 1000.
	return values

static func district_at(point: Vector2) -> String:
	var nearest:=INF
	var district: String="shiomi_machiya"
	for id: String in NEIGHBORHOODS:
		for center: Vector2 in NEIGHBORHOODS[id]:
			var distance:=point.distance_squared_to(center)
			if distance<nearest:
				nearest=distance
				district=id
	return district

static func terrain(at: Vector2i) -> Dictionary:
	if _terrain_cache.has(at): return _terrain_cache[at].duplicate()
	var code := "~"
	var inside:=Rect2i(0,0,73,73).has_point(at)
	if inside: code=data.surfaces[at.y][at.x]
	var center:=(Vector2(at)+Vector2(.5,.5)-OFFSET)*PIXELS_PER_CELL
	var district:="shiomi_bay" if code in ["~","o"] else district_at(center)
	var elevation:=2
	if code in ["~","s","o"]: elevation=0
	elif code in ["d","q","p"] or district=="mill_fields": elevation=1
	elif district in ["shrine_ridge","spring_ravine"]: elevation=4 if code=="^" else 3
	var walkable: bool=code not in ["~","i","k","o","^","p"] and route_minutes(at).station<1000.
	var result: Dictionary={"terrain_type":"water" if code in ["~","i","o"] else ("hill" if code=="^" else "plain"),
		"surface_type": SURFACES[code], "district_id": district, "elevation":elevation,
		"walkable":walkable, "buildable":inside and data.sites[at.y][at.x]=="."}
	if inside: _terrain_cache[at]=result.duplicate()
	return result

static func populate(map: TDTownMap, catalog: TDTownCatalog) -> TDOutcome:
	map.region_id="tokyo"
	map.shiomi=true
	map.layout_version=2
	map.extent=73
	map.roads.clear()
	map.plots.clear()
	var used := {}
	for y: int in map.extent:
		for x: int in map.extent:
			if data.cells[y][x] in ["r","b","d","g"]: map.roads[Vector2i(x,y)]=true
	for row: Array in data.plots:
		map._commit(row[1],row[2],row[3],row[4],row[5],row[6],used,{"id":row[0]})
		var plot: Dictionary=map.plots.back()
		plot.local_name=row[2]
		plot.approach_x=row[7]
		plot.approach_y=row[8]
		plot.region_layout_version=3
	map._copy_catalog(catalog)
	for plot: Dictionary in map.plots: plot.name=plot.local_name
	for record: Dictionary in titles():
		for y: int in range(record.y,record.y+record.h):
			for x: int in range(record.x,record.x+record.w): map._reserved_frontages[Vector2i(x,y)]=true
	return TDOutcome.new(true,"SHIOMI_READY")

static func titles() -> Array:
	var records: Array=[]
	for parent: String in ["competitor","commercial_street"]:
		for i: int in 3:
			var id := "%s:shop:%d"%[parent,i]
			var xy: Array=EXPANSION_SITES[i]
			var w := 3
			var h := 3
			if parent=="competitor":
				var original: Array = data.plots.filter(func(row:Array)->bool: return row[0]==id)[0]
				xy=[int(original[3]),int(original[4])]
				w=int(original[5]);h=int(original[6])
			records.append({"id":id,"parent_id":parent,"x":int(xy[0]),"y":int(xy[1]),"w":w,"h":h,
				"approach_x":int(xy[0])+w/2,"approach_y":int(xy[1])+h,"tradable":parent=="commercial_street",
				"initial_store_index":i if parent=="competitor" else -1,"capacity":12})
	return records

static func migrate(raw: Dictionary) -> TDOutcome:
	return TDRegionMigration.migrate_native(raw,"tokyo",3)
