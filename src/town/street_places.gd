extends RefCounted
## Public architecture and removable street furniture use the existing town map.
const ATLAS := "res://assets/town/cultural-venues-v1.png"
const STALLS := "res://assets/town/market-stalls-v1.png"
const SQUARE_ART := "res://assets/town/jiangnan-square-v1.png"
const Landmarks := preload("res://src/town/jiangnan_landmarks.gd")
const Traders := preload("res://src/town/panorama_traders.gd")
const SQUARE_SIZES := [
	Vector2i(220,207),Vector2i(104,78),Vector2i(112,111),Vector2i(126,126),
	Vector2i(62,57),Vector2i(100,94),Vector2i(150,87),Vector2i(52,71),
	Vector2i(102,47),Vector2i(64,38),Vector2i(32,77),Vector2i(46,27)]
const SIZES := [Vector2i(306,276),Vector2i(306,296),Vector2i(306,293),Vector2i(306,303),Vector2i(279,303),Vector2i(306,248)]
const STALL_SIZES := [Vector2i(306,264),Vector2i(306,237),Vector2i(306,251),Vector2i(306,265),Vector2i(306,249),Vector2i(306,247)]
# Feet measured in cells from the NW corner of an established public block.
const VENUES := {
	"chengdu":{"plaza":["河口水戏台",0,Vector2(13.60,6.10),3.85],"competitor":["蓝印染坊",5,Vector2(11.0,4.35),3.95]},
	"tokyo":{"residences-a":["浜町能舞台",1,Vector2(1.50,2.95),2.28]},
	"paris":{"hotel":["白鹭冬园",2,Vector2(1.5,3.05),2.42]},
}
static var _sprites: Dictionary = {}

static func _square_piece(index: int) -> Texture2D:
	var key := 12+index
	if not _sprites.has(key):
		var texture := AtlasTexture.new()
		texture.atlas = load(SQUARE_ART)
		texture.filter_clip = true
		var size: Vector2i = SQUARE_SIZES[index]
		var corner := Vector2i(index%4,index/4)*240+Vector2i((240-size.x)/2,236-size.y)
		texture.region = Rect2i(corner,size)
		_sprites[key] = texture
	return _sprites[key]

## Coordinates are measured from the public square's northwest corner.
## Leave the southern gathering area and entrances open between the groups.
static func jiangnan_square(_map: TDTownMap, plot: Dictionary, cell: float, origin: Vector2) -> Array[Dictionary]:
	var start := origin+Vector2(plot.x,plot.y)*cell
	var result: Array[Dictionary] = []
	var stage := venue("chengdu",plot,cell,origin)
	stage.jiangnan_feature = "puppet"
	stage.screen_uv = Rect2(.35,.51,.32,.20)
	result.append(stage)
	var stage_rect: Rect2 = stage.rect
	var steps := Rect2(Vector2(stage_rect.get_center().x-stage_rect.size.x*.32,stage_rect.end.y-6),
			Vector2(stage_rect.size.x*.64,15))
	result.append({"art":_square_piece(8),"rect":steps,"bases":[],"sort_y":stage_rect.end.y-.1})
	for spec: Array in [
		["banyan",0,Vector2(8.0,5.50),7.15],
		["tea",3,Vector2(2.65,3.65),2.15],
		["hawthorn",2,Vector2(2.25,6.08),2.38],
		["stools",11,Vector2(5.70,5.37),1.32],
		["stools",11,Vector2(6.65,6.14),1.28],
		["stools",11,Vector2(9.52,5.88),1.25],
		["stools",11,Vector2(10.53,5.03),1.05]]:
		var id: String = spec[0]
		var texture := Landmarks.picture(Landmarks.Piece.BANYAN) if id=="banyan" else _square_piece(spec[1])
		var feet := start+Vector2(spec[2])*cell
		var width: float = spec[3]*cell
		var height := width/texture.get_size().aspect()
		var rect := Rect2(feet-Vector2(width*.5,height),Vector2(width,height))
		var entry := {"art":texture,"rect":rect,"bases":TDEnvironmentArt.facade_bases(rect,.20),"jiangnan_feature":id}
		match id:
			"banyan":
				entry.bases = [Rect2(feet-Vector2(width*.11,height*.10),Vector2(width*.22,height*.10))]
				entry.plot=plot
				entry.label_at=Vector2.INF
				entry.birds_at=start+Vector2(8.60,7.10)*cell
			"tea":
				entry.kettle_uv = Vector2(.72,.50)
				entry.steamer_uv = Vector2(.33,.51)
		result.append(entry)
	return result

static func _picture(index: int, stall: bool=false) -> Texture2D:
	var key := index+6 if stall else index
	if not _sprites.has(key):
		var tex := AtlasTexture.new()
		var size: Vector2i = STALL_SIZES[index] if stall else SIZES[index]
		tex.atlas = load(STALLS if stall else ATLAS) as Texture2D
		tex.filter_clip = true
		tex.region = Rect2(Vector2i(index%3,index/3)*320+Vector2i((320-size.x)/2,316-size.y),size)
		_sprites[key] = tex
	return _sprites[key]

static func venue(town: String, plot: Dictionary, cell: float, origin: Vector2) -> Dictionary:
	var record: Array = VENUES.get(town,{}).get(plot.get("id",""),[])
	if record.is_empty() or plot.get("construction",false): return {}
	var art := Traders.picture("dye_house") if town=="chengdu" and plot.id=="competitor" else _picture(record[1])
	var offset: Vector2 = record[2]
	var feet := origin+(Vector2(plot.x,plot.y)+offset)*cell
	var rect := TDEnvironmentArt.facade_rect(art,feet,float(plot.w)*cell-16,TDTownWorld.HERO_HEIGHT*float(record[3]))
	return {"place_name":record[0],"art":art,"rect":rect,"bases":TDEnvironmentArt.facade_bases(rect,.15)}

## Dress the grass shoulder in pairs along public routes. A new lease, building
## or access path suppresses its local props at the next map rebuild.
static func verges(town: String, map: TDTownMap, cell: float, origin: Vector2, blocked: Array[Rect2]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if map.layout_version!=2: return result
	var used := blocked.duplicate()
	var occupied := {}
	for p: Dictionary in map.plots:
		var lot := Rect2i(p.x,p.y,p.w,p.h).grow(1)
		for y: int in range(lot.position.y,lot.end.y):
			for x: int in range(lot.position.x,lot.end.x):
				occupied[Vector2i(x,y)] = true
		if p.has("approach_x"): occupied[Vector2i(p.approach_x,p.approach_y)] = true
	# The arcade's trading parcels occupy the first four rows. Its public
	# forecourt has room for a short line of stalls well away from their doors.
	var arcade := map._by_id("commercial_street")
	if not arcade.is_empty() and arcade.get("economic_courtyard",false) and arcade.h>=7:
		var lineup := [_picture(TDTravelCatalog.IDS.find(town),true),TDTravelCatalog.street_detail(town,1),_picture(5,true),TDTravelCatalog.street_detail(town,2)]
		for i: int in lineup.size():
			var column: float = [2.55,6.05,9.00,13.4][i]
			var feet_cell := Vector2(arcade.x+column,arcade.y+arcade.h-(1.25 if i%2==0 else .48))
			var art: Texture2D = lineup[i]
			var width := TDTravelCatalog.bench_width(town,art) if i==3 else cell*2.7
			var rect := TDEnvironmentArt.facade_rect(art,origin+feet_cell*cell,width,cell*2.35)
			var lot := TDInteractionRange.plot_bounds(arcade,cell,origin)
			if not lot.encloses(rect) or used.any(func(r:Rect2)->bool: return rect.intersects(r.grow(10))): continue
			var base := TDEnvironmentArt.facade_bases(rect,.14)[0]
			var inside := true
			for corner: Vector2 in [base.position,base.end,base.get_center()]:
				var at := Vector2i(((corner-origin)/cell).floor())
				if map.is_road(at.x,at.y) or map.terrain_at(at).terrain_type!="plain": inside=false;break
			if not inside: continue
			result.append({"art":art,"rect":rect,"bases":[base],"arcade":true})
			used.append(rect)
	var harbor := TDTravelCatalog.harbor_rect(town).grow(2)
	var clusters: Array[Vector2i] = []
	var salt := TDTravelCatalog.IDS.find(town)*37+7
	for y: int in range(2,map.extent-2):
		for x: int in range(2,map.extent-2):
			var at := Vector2i(x,y)
			var seed := TDTownScenery.noise(x,y,salt)
			if seed%4!=0 or occupied.has(at) or harbor.has_point(Vector2(at)) or map.is_road(x,y): continue
			var terrain := map.terrain_at(at)
			if terrain.terrain_type!="plain" or not terrain.walkable: continue
			var tangent := Vector2i.ZERO
			for side: Vector2i in [Vector2i.UP,Vector2i.LEFT,Vector2i.DOWN,Vector2i.RIGHT]:
				var roadside := at+side
				if map.is_road(roadside.x,roadside.y) and map.terrain_at(roadside).surface_type=="stone":
					tangent = Vector2i(-side.y,side.x)
					break
			if tangent==Vector2i.ZERO: continue
			if clusters.any(func(p:Vector2i)->bool: return at.distance_squared_to(p)<30): continue
			var market := str(terrain.district_id) in ["old_market","east_quays","south_gate","shopping_street","fish_wharf","civic_square","river_quays","floating_market","trade_street","zocalo","trading_post"]
			var texture := _picture(TDTravelCatalog.IDS.find(town) if seed%5!=0 else 5,true) if market and seed%3!=0 else TDTravelCatalog.plant(town,TDTravelCatalog.plant_species(town,"avenue",seed))
			var width := 172.0 if market else 106.0+float(seed%3)*14
			var companion := at+tangent
			var added := false
			for pos: Vector2i in [at,companion]:
				if occupied.has(pos) or map.is_road(pos.x,pos.y) or map.terrain_at(pos).terrain_type!="plain": continue
				var art := texture if pos==at else TDTravelCatalog.plant(town,4 if town=="tokyo" else 2)
				var feet := origin+(Vector2(pos)+Vector2(.52,.67))*cell
				var rect := TDEnvironmentArt.facade_rect(art,feet,width if pos==at else 46.0,140.0)
				if used.any(func(other:Rect2)->bool: return rect.intersects(other.grow(5))): continue
				var base := TDEnvironmentArt.facade_bases(rect,.12)[0]
				var clear := true
				for corner: Vector2 in [base.position,base.end,Vector2(base.end.x,base.position.y),Vector2(base.position.x,base.end.y)]:
					var foot_cell := Vector2i(((corner-origin)/cell).floor())
					if map.is_road(foot_cell.x,foot_cell.y) or occupied.has(foot_cell) or map.terrain_at(foot_cell).terrain_type!="plain": clear=false;break
				if not clear: continue
				result.append({"art":art,"rect":rect,"bases":[base],"street_cluster":at})
				used.append(rect)
				added = true
			if added: clusters.append(at)
	return result
