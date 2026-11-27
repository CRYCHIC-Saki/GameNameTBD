class_name TDEgretLayout
extends RefCounted
## Survey of the European port. Coordinates use the same projection as the walking scene.
const SIZE := Vector2i(2263,1085)
const OFFSET := Vector2(0,19)
const PITCH := 31.0
# Keep house and hero proportions as the street grid expands.
const WALK_CELL := PITCH * (40.0 / 24.0)
const CURRENT_VERSION := 12
const SCENE := preload("res://src/town/egret_map.tscn")
const SURFACES := {".":"lawn","r":"stone","q":"quay","d":"pier","g":"square","w":"wheat","t":"earth","~":"sea"}
const DISTRICTS := {"Q":"river_quays","N":"workers_quarter","C":"civic_square","F":"market_gardens",
	"G":"garden_quarter","S":"commercial_street","I":"inn_quarter"}
const DISTRICT_NAMES := {"river_quays":"西岸客港","workers_quarter":"北街住宅与工坊","civic_square":"市政广场",
	"market_gardens":"磨坊田园","garden_quarter":"花园街区","commercial_street":"东部商业街","inn_quarter":"旅馆街区"}
const LAND_USES := {"~":"water","r":"road","h":"harbor","p":"plaza","w":"farmland","a":"housing","b":"bank",
	"f":"supply_factory","i":"hotel","m":"market","u":"urban_village","c":"competitor","v":"rich_district","l":"landmark"}
static var survey: Dictionary:
	get:
		if survey.is_empty():
			survey=JSON.parse_string(FileAccess.get_file_as_string("res://content/towns/egret_survey.json"))
		return survey
# Historical surveys validate the exact geography used when an older save was written.
const HISTORICAL := {
	4: [Vector2i(1672, 942), Vector2(2, 15), 24.0],
	5: [Vector2i(2240, 1760), Vector2(1, 12), 32.0],
	6: [SIZE, OFFSET, PITCH],
	7: [SIZE, OFFSET, PITCH],
	8: [SIZE, OFFSET, PITCH],
	9: [SIZE, OFFSET, PITCH],
	10: [SIZE, OFFSET, PITCH],
	11: [SIZE, OFFSET, PITCH],
}
static var _surveys: Dictionary = {}
static var _historic_feet: Dictionary = {}
static var _feet := PackedByteArray()

static func geography(version: int) -> Dictionary:
	if not HISTORICAL.has(version): return survey
	if not _surveys.has(version):
		_surveys[version] = JSON.parse_string(FileAccess.get_file_as_string("res://content/towns/egret_survey_v%d.json" % version))
	return _surveys[version]

static func port(version: int = CURRENT_VERSION) -> Vector2i:
	var at: Array = geography(version).arrival
	return Vector2i(int(at[0]),int(at[1]))

static func world_point(pixel: Vector2) -> Vector2:
	return (OFFSET+pixel/PITCH)*WALK_CELL

static func instance() -> Node2D:
	var scene := SCENE.instantiate() as Node2D
	scene.position=world_point(Vector2.ZERO)
	scene.scale=Vector2.ONE*WALK_CELL/PITCH
	return scene

static func overview() -> SubViewport:
	var view := SubViewport.new()
	view.disable_3d=true
	view.transparent_bg=true
	view.size=Vector2i(1460,1460)
	view.render_target_update_mode=SubViewport.UPDATE_ONCE
	var scene := instance()
	var factor := view.size.x/(73.0*WALK_CELL)
	scene.position*=factor
	scene.scale*=factor
	view.add_child(scene)
	return view

static func can_stand(pixel: Vector2) -> bool:
	var at:=Vector2i(pixel.floor())
	if not Rect2i(Vector2i.ZERO,SIZE).has_point(at): return false
	if _feet.is_empty():
		_feet=Marshalls.base64_to_raw(survey.walk_bits).decompress((SIZE.x*SIZE.y+7)/8,FileAccess.COMPRESSION_DEFLATE)
	var bit:=at.y*SIZE.x+at.x
	return (_feet[bit>>3] & (1<<(bit&7)))!=0

static func terrain(at: Vector2i, version: int = CURRENT_VERSION) -> Dictionary:
	var data := geography(version)
	var inside:=Rect2i(0,0,73,73).has_point(at)
	if data.has("districts") and (not inside or data.cells[at.y][at.x]=="_"):
		return {"terrain_type":"outside","surface_type":"outside","district_id":"off_map","zone_id":"off_map",
			"elevation":0,"walkable":false,"buildable":false}
	var code: String=data.cells[at.y][at.x] if inside else "~"
	var point:=(Vector2(at)+Vector2.ONE*.5-OFFSET)*PITCH
	var walkable := false
	var district_point := point
	if HISTORICAL.has(version):
		var old: Array = HISTORICAL[version]
		var size: Vector2i = old[0]
		point=(Vector2(at)+Vector2.ONE*.5-Vector2(old[1]))*float(old[2])
		district_point=point
		if Rect2(Vector2.ZERO, Vector2(size)).has_point(point):
			if not _historic_feet.has(version):
				_historic_feet[version]=Marshalls.base64_to_raw(data.walk_bits).decompress((size.x*size.y+7)/8,FileAccess.COMPRESSION_DEFLATE)
			var bits: PackedByteArray = _historic_feet[version]
			var bit := int(point.y)*size.x+int(point.x)
			walkable=(bits[bit>>3] & (1<<(bit&7)))!=0
	else:
		walkable=can_stand(point)
	var dry:=code!="~"
	var result := {"terrain_type":"plain" if dry else "water","surface_type":SURFACES[code],
		"elevation":1 if dry else 0,"walkable":walkable,"buildable":inside and data.sites[at.y][at.x]=="."}
	if data.has("districts"):
		var district_code: String = data.districts[at.y][at.x]
		var use_code: String = data.land_use[at.y][at.x]
		result.district_id = DISTRICTS[district_code]
		result.zone_id = LAND_USES.get(use_code, result.district_id)
		return result
	# Historical layouts use the original coordinate-based district boundaries.
	if data.has("reference_frame"):
		var frame: Array = data.reference_frame
		district_point=(point-Vector2(frame[0],frame[1]))/float(frame[2])
	var gardens := (district_point.y>1050 and district_point.x<1625) if version==5 else (district_point.x<580 and district_point.y>495)
	var district:="civic_square"
	if not dry or code in ["q","d"]: district="river_quays"
	elif gardens: district="market_gardens"
	elif district_point.x>(1580 if version==5 else 1140): district="garden_quarter"
	elif district_point.y<(375 if version==5 else 245): district="workers_quarter"
	result.district_id = district
	return result

static func route_minutes(at: Vector2i) -> Dictionary:
	var result := {}
	var local := at - Vector2i(OFFSET)
	var inside := Rect2i(Vector2i.ZERO, SIZE / int(PITCH)).has_point(local)
	for origin: String in survey.routes:
		var steps := int(survey.routes[origin][local.y][local.x]) if inside else -1
		# The survey measures five walking steps per tile. The economy uses 0.3 minutes per tile.
		result[origin] = 2.0 + steps * (0.3 / 5.0) if steps >= 0 else 32.0
	return result

static func titles(version: int = CURRENT_VERSION) -> Array:
	var result: Array=[]
	for r: Array in geography(version).titles:
		var parts:=str(r[0]).split(":")
		var initial:=parts[0]=="competitor"
		result.append({"id":r[0],"parent_id":parts[0],"x":int(r[1]),"y":int(r[2]),"w":int(r[3]),"h":int(r[4]),
			"approach_x":int(r[5]),"approach_y":int(r[6]),"tradable":not initial,"initial_store_index":int(parts[2]) if initial else -1,"capacity":12})
	return result

static func populate(map: TDTownMap,catalog: TDTownCatalog, version: int = CURRENT_VERSION) -> TDOutcome:
	var data := geography(version)
	map.egret_version=version
	map.region_id="paris"
	map.egret=true
	map.extent=73
	map.layout_version=2
	map.roads.clear()
	map._reserved_frontages.clear()
	map.plots.clear()
	var used: Dictionary={}
	for y: int in map.extent:
		for x: int in map.extent:
			var road: bool = data.frontage[y][x]=="+" if data.has("frontage") else data.cells[y][x] in ["g","r","q","d"]
			if road: map.roads[Vector2i(x,y)]=true
	for r: Array in data.plots:
		map._commit(r[1],r[2],r[3],r[4],r[5],r[6],used,{"id":r[0]})
		var plot: Dictionary=map.plots.back()
		plot.local_name=r[2]
		plot.approach_x=int(r[7])
		plot.approach_y=int(r[8])
		plot.region_layout_version=version
	map._copy_catalog(catalog)
	for plot: Dictionary in map.plots: plot.name=plot.local_name
	for title: Dictionary in titles(version):
		for y: int in range(title.y,title.y+title.h):
			for x: int in range(title.x,title.x+title.w): map._reserved_frontages[Vector2i(x,y)]=true
	return TDOutcome.new(true,"EGRET_READY")
