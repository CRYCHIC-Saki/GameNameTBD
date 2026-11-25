class_name TDTownScenery
extends RefCounted
## Presentation-only terrain cache. Its hash never consumes the simulation RNG.
const SCALE: int=TDTownWorld.CELL/2
const MATERIALS=preload("res://assets/town/map-surfaces-v2.png")
const Yard := preload("res://src/town/residential_yard.gd")
const RiverBridge := preload("res://src/town/river_bridge_art.gd")
const PublicSquare := preload("res://src/town/public_square.gd")
const JiangnanPaving := preload("res://src/town/jiangnan_paving.gd")
const JiangnanDistrictTerrain := preload("res://src/town/jiangnan_district_terrain.gd")
const SURFACE_COLUMNS := {"grass":0,"lawn":0,"woodland":0,"stone":1,"water":3,"bridge":3}
const SURFACE_ROWS: Dictionary={"chengdu":0,"tokyo":1,"paris":2}
static var _key: String=""
static var _ground: ImageTexture
static var _trees: Array[Vector2]=[]
static var _swatches: Array[Image]=[]
static var _surface_textures: Dictionary={}
static var _plant_plans: Dictionary={}

static func _prepare_swatches() -> void:
	if not _swatches.is_empty(): return
	var source := MATERIALS.get_image()
	if source.is_compressed(): source.decompress()
	source.convert(Image.FORMAT_RGBA8)
	for i: int in 20:
		var start:=Vector2i(roundi((i%4)*source.get_width()/4.0),roundi((i/4)*source.get_height()/5.0))
		var end:=Vector2i(roundi((i%4+1)*source.get_width()/4.0),roundi((i/4+1)*source.get_height()/5.0))
		var tile := source.get_region(Rect2i(start,end-start).grow(-2))
		tile.resize(120,120,Image.INTERPOLATE_NEAREST)
		if i==1: tile=JiangnanPaving.stone_swatch()
		_match_edges(tile)
		_swatches.append(tile)

static func _match_edges(tile: Image) -> void:
	# Pair opposite edge bands once, on a private runtime copy. This enforces
	# exact horizontal AND vertical continuity even after atlas cropping/resizing.
	var band: int=6
	for x: int in band:
		var weight: float=.5*(1.0-smoothstep(0.0,float(band-1),float(x)))
		for y: int in tile.get_height():
			var a:=tile.get_pixel(x,y);var b:=tile.get_pixel(tile.get_width()-1-x,y)
			tile.set_pixel(x,y,a.lerp(b,weight));tile.set_pixel(tile.get_width()-1-x,y,b.lerp(a,weight))
			if x==0:
				var shared:=a.lerp(b,.5)
				tile.set_pixel(x,y,shared);tile.set_pixel(tile.get_width()-1-x,y,shared)
	for y: int in band:
		var weight: float=.5*(1.0-smoothstep(0.0,float(band-1),float(y)))
		for x: int in tile.get_width():
			var a:=tile.get_pixel(x,y);var b:=tile.get_pixel(x,tile.get_height()-1-y)
			tile.set_pixel(x,y,a.lerp(b,weight));tile.set_pixel(x,tile.get_height()-1-y,b.lerp(a,weight))
			if y==0:
				var shared:=a.lerp(b,.5)
				tile.set_pixel(x,y,shared);tile.set_pixel(x,tile.get_height()-1-y,shared)

static func road_surface(surface: String) -> bool:
	return surface in ["stone","bridge"]

static func smooth_surfaces(map: TDTownMap,extra_columns: int=0) -> Dictionary:
	var surfaces: Dictionary={};var protected: Dictionary={}
	for p: Dictionary in map.plots:
		if p.has("approach_x"): protected[Vector2i(int(p.approach_x),int(p.approach_y))]=true
	if not map.cottage.is_empty(): protected[Vector2i(int(map.cottage.approach_x),int(map.cottage.approach_y))]=true
	var directions: Array[Vector2i]=[Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]
	for y: int in map.extent:
		for x: int in range(map.extent+extra_columns):
			var at:=Vector2i(x,y)
			var cover: String = map.terrain_at(at).surface_type
			# Land-use districts still inform land values. Only a physical street
			# gets paving; the other dry parcels use the town's grass.
			surfaces[at] = cover if SURFACE_COLUMNS.has(cover) else "grass"
	# Authored streets, including door aprons, must agree with the world map.
	if map.layout_version == 2:
		Yard.apply_lawns(surfaces,map.plots)
		PublicSquare.mark(surfaces,PublicSquare.bounds(map))
		return surfaces
	# Discard decorative one-cell road tails, never door approaches or bridges.
	# Only the presentation copy changes; geography and saved property stay intact.
	for pass_index: int in 4:
		var remove: Array[Vector2i]=[]
		for at: Vector2i in surfaces:
			if surfaces[at]!="stone" or protected.has(at): continue
			var count: int=0
			for d: Vector2i in directions:
				if road_surface(surfaces.get(at+d,"")): count+=1
			if count<=1: remove.append(at)
		if remove.is_empty(): break
		for at: Vector2i in remove:
			surfaces[at]=surfaces.get(at+Vector2i.UP,"grass")
			if road_surface(surfaces[at]) or surfaces[at]=="water": surfaces[at]="grass"
	return surfaces

static func paint_cell(image: Image,at: Vector2i,surfaces: Dictionary,town: String="chengdu") -> void:
	var surface: String=surfaces.get(at,"water")
	var origin:=at*SCALE
	var column: int = SURFACE_COLUMNS.get(surface,0)
	paint(image,Rect2i(origin,Vector2i.ONE*SCALE),column,town)
	if surface == "water":
		for d: Vector2i in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:
			var bank: String = surfaces.get(at+d,"water")
			if bank in ["water", "bridge"]: continue
			var start := origin + Vector2i(maxi(d.x,0),maxi(d.y,0))*(SCALE-2)
			var strip := Vector2i(SCALE,2) if d.x==0 else Vector2i(2,SCALE)
			image.fill_rect(Rect2i(start,strip),Color("617c72"))
	if surface!="stone": return
	if town=="chengdu":
		JiangnanPaving.finish_cell(image,at,surfaces,_swatches[0],SCALE)
		return
	# Autotile convex road corners to round caps; the UV stays world-aligned.
	var radius: int=12
	for corner: Vector2i in [Vector2i(-1,-1),Vector2i(1,-1),Vector2i(-1,1),Vector2i(1,1)]:
		var horizontal: String=surfaces.get(at+Vector2i(corner.x,0),"water")
		var vertical: String=surfaces.get(at+Vector2i(0,corner.y),"water")
		if horizontal not in ["grass","woodland","lawn"] or vertical not in ["grass","woodland","lawn"]: continue
		var row := int(SURFACE_ROWS[town])
		var grass := _swatches[row*4]
		for y: int in radius:
			for x: int in radius:
				var distance: float=Vector2(radius-x-.5,radius-y-.5).length()
				var mix_value: float=clampf(distance-float(radius)+.5,0.0,1.0)
				if mix_value<=0: continue
				var pixel:=origin+Vector2i(x if corner.x<0 else SCALE-1-x,y if corner.y<0 else SCALE-1-y)
				image.set_pixelv(pixel,image.get_pixelv(pixel).lerp(grass.get_pixel(pixel.x%120,pixel.y%120),mix_value))

static func surface_texture(index: int,town: String="chengdu") -> Texture2D:
	_prepare_swatches()
	var key: int=int(SURFACE_ROWS.get(town,0))*4+clampi(index,0,3)
	if not _surface_textures.has(key): _surface_textures[key]=ImageTexture.create_from_image(_swatches[key])
	return _surface_textures[key]

static func paint(image: Image,rect: Rect2i,index: int,town: String="chengdu") -> void:
	_prepare_swatches()
	var swatch := _swatches[int(SURFACE_ROWS.get(town,0))*4+index]
	var period := swatch.get_width()
	var y: int=rect.position.y
	while y<rect.end.y:
		var height: int=mini(period-y%period,rect.end.y-y);var x: int=rect.position.x
		while x<rect.end.x:
			var width: int=mini(period-x%period,rect.end.x-x)
			image.blit_rect(swatch,Rect2i(x%period,y%period,width,height),Vector2i(x,y));x+=width
		y+=height

static func noise(x: int,y: int,salt: int=0) -> int:
	return absi((x*73856093)^(y*19349663)^(salt*83492791))

## One deterministic candidate per patch, with a broken canopy and clearings.
## Pure presentation sampling, independent of the market and kitchen RNG.
static func planting_at(patch: Vector2i, salt: int) -> Vector2:
	var x := noise(patch.x,patch.y,salt) % 199
	var y := noise(patch.y,patch.x,salt+17) % 199
	return Vector2(patch * 3) + Vector2(.48 + float(x)/103.0, .58 + float(y)/109.0)

static func wooded_patch(at: Vector2, surface: String, salt: int) -> bool:
	if surface not in ["woodland", "earth", "grass"]: return false
	var density := sin(at.x*.19 + salt) + cos(at.y*.23 - at.x*.08) + sin((at.x + at.y)*.12)
	var threshold := -1.1 if surface == "woodland" else (.3 if surface == "earth" else .75)
	return density > threshold

static func ground(map: TDTownMap) -> ImageTexture:
	var key: String="%d:%d:%d:%d"%[map.layout_version,map.extent,map.roads.hash(),map.plots.hash()]
	if _ground!=null and key==_key: return _ground
	if TDPlannedTown.approved(map):
		_trees.clear()
		var coast: Script = load("res://src/town/jiangnan_coast_art.gd")
		_ground=ImageTexture.create_from_image(coast.build(map,SCALE))
		_key=key
		return _ground
	var image:=Image.create(map.extent*SCALE,map.extent*SCALE,false,Image.FORMAT_RGBA8)
	var surfaces: Dictionary=smooth_surfaces(map)
	_trees.clear()
	for y: int in map.extent:
		for x: int in map.extent:
			var at:=Vector2i(x,y)
			paint_cell(image,at,surfaces)
	if map.layout_version==2 and map.region_id.is_empty():
		JiangnanDistrictTerrain.Pedestrian.paint_streets(image,map,SCALE)
	RiverBridge.paint(image,surfaces,"chengdu",SCALE)
	PublicSquare.paint(image,map,surfaces,"chengdu",SCALE)
	Yard.paint_steps(image,map,SCALE,"chengdu")
	JiangnanDistrictTerrain.paint(image,map,SCALE)
	for y: int in ceili(map.extent/3.0):
		for x: int in ceili(map.extent/3.0):
			var point := planting_at(Vector2i(x,y),3)
			if surfaces.get(Vector2i(point)) == "woodland" and wooded_patch(point,"woodland",3): _trees.append(point)
	# A parcel is an ownership boundary, not a rectangular dirt foundation.
	# Building art already includes its steps/courtyard; keep the terrain continuous.
	_ground=ImageTexture.create_from_image(image);_key=key
	return _ground

static func draw_wilds(canvas: CanvasItem,origin: Vector2,cell: float) -> void:
	for at: Vector2 in _trees:
		var sample := noise(int(at.x),int(at.y))
		_draw_plant(canvas,0 if sample%3!=0 else 1,origin+at*cell,cell*(2.1+.11*(sample%9)))

static func dressing(map: TDTownMap) -> Array[Dictionary]:
	var plants: Array[Dictionary]=[]
	if map.layout_version!=2: return plants
	var town := "chengdu" if map.region_id.is_empty() else map.region_id
	var approved := TDPlannedTown.approved(map)
	var key := Vector2i(map.roads.hash(),map.plots.hash())
	if _plant_plans.has(town) and _plant_plans[town].key==key: return _plant_plans[town].plants
	var reserved := {}
	for plot: Dictionary in map.plots:
		var lot := Rect2i(plot.x,plot.y,plot.w,plot.h).grow(1 if approved else 2)
		for y: int in range(lot.position.y,lot.end.y):
			for x: int in range(lot.position.x,lot.end.x):
				reserved[Vector2i(x,y)] = true
		if plot.has("approach_x"): reserved[Vector2i(plot.approach_x,plot.approach_y)] = true
	JiangnanDistrictTerrain.reserve_planting(reserved,map)
	var shore := {}
	var soil := {}
	var port := TDTravelCatalog.harbor_rect(town).grow(2.0)
	for y: int in map.extent:
		for x: int in map.extent:
			var p := Vector2i(x,y)
			var terrain := map.terrain_at(p)
			if terrain.terrain_type=="water":
				if terrain.surface_type in ["water","sea"]: shore[p]=true
			elif not map.is_road(x,y) and terrain.walkable and not reserved.has(p) and not port.has_point(Vector2(p)):
				soil[p]=true
	var salt := TDTravelCatalog.IDS.find(town)*13+17
	var taken := {}
	for p: Vector2i in soil:
		var side := _adjacent_side(p,shore)
		var habitat := "bank"
		if side==Vector2i.ZERO:
			side = _adjacent_side(p,map.roads)
			habitat = "avenue" if side!=Vector2i.ZERO else "grove"
		var sample := noise(p.x,p.y,salt)
		var tangent := Vector2i(-side.y,side.x)
		if habitat=="grove":
			# Small irregular groves, separated by open lawns.
			var interval := 8 if approved else 5
			if posmod(p.y+salt,interval)!=0 or posmod(p.x+noise(0,p.y,salt),interval)!=0 or sample%5==1: continue
			tangent = Vector2i.RIGHT if sample%3!=0 else Vector2i.DOWN
		else:
			# Repeat street trees along one kerb. Riparian beds have shorter intervals.
			var along := p.x if side.y!=0 else p.y
			var cross := p.y if side.y!=0 else p.x
			var spacing := 6 if approved and habitat=="avenue" else (4 if habitat=="avenue" else 3)
			if posmod(along+cross+salt,spacing)!=0: continue
		if taken.has(p): continue
		var dominant := TDTravelCatalog.plant_species(town,habitat,sample)
		var width := (1.85 if habitat=="avenue" else 2.10)*(.90+.035*(sample%7))
		if town=="paris" and dominant==3: width*=.55

		_add_plant(plants,taken,p,dominant,width,habitat)
		# Echo the canopy with low planting, following the same bank or kerb.
		var understory := 4 if town=="tokyo" else 2
		for step: int in [1,-1]:
			var neighbor := p+tangent*step
			if not soil.has(neighbor) or taken.has(neighbor) or (step<0 and sample%3!=0): continue
			if habitat!="grove" and not (shore if habitat=="bank" else map.roads).has(neighbor+side): continue
			var shrub := understory

			_add_plant(plants,taken,neighbor,shrub,.64+.065*(sample%4),habitat)
	if approved:
		for y: int in TDPlannedTown.coast_height():
			for x: int in map.extent:
				var at := Vector2i(x,y)
				var seed := noise(x,y,71)
				if seed%10>4 or taken.has(at) or reserved.has(at): continue
				var terrain := map.terrain_at(at)
				if terrain.terrain_type=="hill":
					_add_plant(plants,taken,at,1 if seed%4 else 2,2.0+.15*(seed%7),"woodland")
	plants.sort_custom(func(a:Dictionary,b:Dictionary)->bool: return a.feet.y<b.feet.y)
	_plant_plans[town]={"key":key,"plants":plants}
	return plants

static func _adjacent_side(at: Vector2i, feature: Dictionary) -> Vector2i:
	for side: Vector2i in [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]:
		if feature.has(at+side): return side
	return Vector2i.ZERO

static func _add_plant(plants: Array[Dictionary],taken: Dictionary,at: Vector2i,index: int,width: float,habitat: String) -> void:
	var seed := noise(at.x,at.y,31)
	var feet := Vector2(at)+Vector2(.42+.026*(seed%8),.57+.025*((seed/7)%8))
	var bounds := Rect2(feet-Vector2(width*.10,.13),Vector2(width*.20,.14))
	plants.append({"feet":feet,"index":index,"width":width,"bounds":bounds,"habitat":habitat})
	taken[at]=true

static func _draw_plant(canvas: CanvasItem, index: int, feet: Vector2, width: float) -> void:
	var tex := TDTravelCatalog.plant("chengdu",index)
	var size := tex.get_size() * (width / tex.get_width())
	canvas.draw_texture_rect(tex,Rect2(feet-Vector2(size.x*.5,size.y),size),false)

static func shadow(canvas: CanvasItem,feet: Vector2,width: float) -> void:
	# Stepped contact shadow: no smooth vector oval against the pixel silhouettes.
	for row: int in 5:
		var inset: float=absf(float(row)-2.0)*width*.04
		canvas.draw_rect(Rect2(feet+Vector2(-width*.43+inset,-10+row*3),Vector2(width*.86-inset*2,3)),Color(.20,.24,.16,.10))

static func pots(canvas: CanvasItem,rect: Rect2) -> void:
	if rect.size.x<130: return
	for x: float in [rect.position.x+22,rect.end.x-24]:
		var feet:=Vector2(x,rect.end.y-12)
		shadow(canvas,feet,44);TDEnvironmentArt.draw_prop(canvas,14,feet,42,true)
