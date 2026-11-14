class_name TDTownScenery
extends RefCounted
## Presentation-only terrain cache. Its hash never consumes the simulation RNG.
const SCALE: int=24
const MATERIALS=preload("res://assets/town/map-surfaces-v2.png")
const SURFACE_ROWS: Dictionary={"chengdu":0,"tokyo":1,"paris":2,"bangkok":3,"mexico_city":4}
static var _key: String=""
static var _ground: ImageTexture
static var _trees: Array[Vector2]=[]
static var _swatches: Array[Image]=[]
static var _surface_textures: Dictionary={}
static var _dressing_key: String=""
static var _dressing: Array[Dictionary]=[]

static func _prepare_swatches() -> void:
	if _swatches.is_empty():
		var source:=MATERIALS.get_image()
		if source.is_compressed(): source.decompress()
		source.convert(Image.FORMAT_RGBA8)
		for i: int in 20:
			var start:=Vector2i(roundi((i%4)*source.get_width()/4.0),roundi((i/4)*source.get_height()/5.0))
			var end:=Vector2i(roundi((i%4+1)*source.get_width()/4.0),roundi((i/4+1)*source.get_height()/5.0))
			var tile:=source.get_region(Rect2i(start,end-start).grow(-2))
			tile.resize(120,120,Image.INTERPOLATE_NEAREST)
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
			var at:=Vector2i(x,y);surfaces[at]=str(map.terrain_at(at).surface_type)
	# Short authored entrance aprons used to be wider than their shop, producing
	# rectangular pavement ears. Fit those aprons to the frontage, keeping trunks.
	if map.layout_version==2 and map.region_id.is_empty():
		var authored: Array=TDPlannedTown.definition().roads
		for raw: Array in authored:
			var apron:=Rect2i(int(raw[0]),int(raw[1]),int(raw[2]),int(raw[3]))
			if apron.size.x>6 or apron.size.y>3: continue
			for p: Dictionary in map.plots:
				if not p.has("approach_x") or int(p.y+p.h)!=apron.position.y: continue
				if not apron.has_point(Vector2i(int(p.approach_x),int(p.approach_y))): continue
				for y: int in range(apron.position.y,apron.end.y):
					for x: int in range(apron.position.x,apron.end.x):
						var at:=Vector2i(x,y)
						if x>=int(p.x) and x<int(p.x+p.w) or protected.has(at): continue
						var trunk: bool=false
						for other: Array in authored:
							if other==raw: continue
							if Rect2i(int(other[0]),int(other[1]),int(other[2]),int(other[3])).has_point(at): trunk=true;break
						if not trunk: surfaces[at]="grass"
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
		for at: Vector2i in remove: surfaces[at]="grass"
	# Close narrow grass notches between three road sides, outside buildings.
	for pass_index: int in 4:
		var fill: Array[Vector2i]=[]
		for at: Vector2i in surfaces:
			if surfaces[at]!="grass" or map.layout_version!=2 or not map.plot_at(at.x,at.y).is_empty(): continue
			var count: int=0
			for d: Vector2i in directions:
				if road_surface(surfaces.get(at+d,"")): count+=1
			if count>=3: fill.append(at)
		if fill.is_empty(): break
		for at: Vector2i in fill: surfaces[at]="stone"
	return surfaces

static func paint_cell(image: Image,at: Vector2i,surfaces: Dictionary,town: String="chengdu") -> void:
	var surface: String=surfaces.get(at,"water")
	var origin:=at*SCALE
	paint(image,Rect2i(origin,Vector2i.ONE*SCALE),3 if surface=="water" else (1 if road_surface(surface) else (2 if surface=="sand" else 0)),town)
	if surface!="stone": return
	# Autotile convex road corners to round caps; the UV stays world-aligned.
	var grass: Image=_swatches[int(SURFACE_ROWS.get(town,0))*4]
	var radius: int=12
	for corner: Vector2i in [Vector2i(-1,-1),Vector2i(1,-1),Vector2i(-1,1),Vector2i(1,1)]:
		var horizontal: String=surfaces.get(at+Vector2i(corner.x,0),"water")
		var vertical: String=surfaces.get(at+Vector2i(0,corner.y),"water")
		if horizontal not in ["grass","woodland"] or vertical not in ["grass","woodland"]: continue
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
	var swatch: Image=_swatches[int(SURFACE_ROWS.get(town,0))*4+clampi(index,0,3)]
	var y: int=rect.position.y
	while y<rect.end.y:
		var height: int=mini(120-y%120,rect.end.y-y);var x: int=rect.position.x
		while x<rect.end.x:
			var width: int=mini(120-x%120,rect.end.x-x)
			image.blit_rect(swatch,Rect2i(x%120,y%120,width,height),Vector2i(x,y));x+=width
		y+=height

static func noise(x: int,y: int,salt: int=0) -> int:
	return absi((x*73856093)^(y*19349663)^(salt*83492791))

static func ground(map: TDTownMap) -> ImageTexture:
	var key: String="%d:%d:%d:%d"%[map.layout_version,map.extent,map.roads.hash(),map.plots.hash()]
	if _ground!=null and key==_key: return _ground
	var image:=Image.create(map.extent*SCALE,map.extent*SCALE,false,Image.FORMAT_RGBA8)
	var surfaces: Dictionary=smooth_surfaces(map)
	_trees.clear()
	for y: int in map.extent:
		for x: int in map.extent:
			var at:=Vector2i(x,y);var origin:=at*SCALE;var surface: String=surfaces[at]
			paint_cell(image,at,surfaces)
			if surface=="bridge":
				image.fill_rect(Rect2i(origin,Vector2i.ONE*SCALE),Color("a7784d"))
				for n: int in range(0,SCALE,4):
					image.fill_rect(Rect2i(origin+Vector2i(0,n),Vector2i(SCALE,1)),Color("624f42"))
					image.fill_rect(Rect2i(origin+Vector2i(2,n+1),Vector2i(18,1)),Color("bb9870"))
			if surface=="woodland" and x%3==0 and y%3==1: _trees.append(Vector2(x+.5,y+1.0))
	# A parcel is an ownership boundary, not a rectangular dirt foundation.
	# Building art already includes its steps/courtyard; keep the terrain continuous.
	_ground=ImageTexture.create_from_image(image);_key=key
	return _ground

static func draw_wilds(canvas: CanvasItem,origin: Vector2,cell: float) -> void:
	for at: Vector2 in _trees:
		TDEnvironmentArt.draw_prop(canvas,3 if noise(int(at.x),int(at.y))%2==0 else 6,origin+at*cell,cell*2.7,true)

static func dressing(map: TDTownMap) -> Array[Dictionary]:
	var key: String="%d:%d:%d"%[map.layout_version,map.roads.hash(),map.plots.hash()]
	if _dressing_key==key: return _dressing
	_dressing_key=key;_dressing=[]
	if map.layout_version!=2: return _dressing
	var candidates: Array[Vector2]=[Vector2(29.5,19.5),Vector2(32,20),Vector2(8,28),Vector2(8,34),Vector2(8,40),Vector2(16,28),Vector2(11,30)]
	for y: int in range(10,70,4):
		for x: int in range(7,70,5):
			if noise(x,y)%3!=0: candidates.append(Vector2(x+.5+(y%3),y+.5))
	for at: Vector2 in candidates:
		var safe: bool=true
		for p: Dictionary in map.plots:
			if p.kind=="diner_lot" or p.get("economic_courtyard",false): continue
			if TDInteractionRange.plot_bounds(p).grow(1.5).has_point(at): safe=false;break
		if not safe: continue
		for y: int in range(int(at.y)-1,int(at.y)+2):
			for x: int in range(int(at.x)-1,int(at.x)+2):
				if map.is_road(x,y) or not map.terrain_at(Vector2i(x,y)).walkable: safe=false
		if not safe: continue
		var index: int=[3,6,14][noise(int(at.x),int(at.y))%3]
		var width: float=2.8 if index==3 else (2.1 if index==6 else 1.4)
		var bounds:=Rect2(at-Vector2(width*.27,.4),Vector2(width*.54,.65))
		for plot: Dictionary in map.plots:
			if TDInteractionRange.facility(plot) and TDInteractionRange.plot_bounds(plot).grow(1.1).intersects(bounds): safe=false;break
		if not safe: continue
		if _dressing.any(func(p:Dictionary)->bool:return p.bounds.grow(.7).intersects(bounds)): continue
		_dressing.append({"feet":at,"index":index,"width":width,"bounds":bounds})
	_dressing.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return a.feet.y<b.feet.y)
	return _dressing

static func draw_dressing(canvas: CanvasItem,map: TDTownMap,origin: Vector2,cell: float) -> void:
	for p: Dictionary in dressing(map):
		var feet: Vector2=origin+p.feet*cell
		shadow(canvas,feet,p.width*cell)
		TDEnvironmentArt.draw_prop(canvas,p.index,feet,p.width*cell,true)

static func shadow(canvas: CanvasItem,feet: Vector2,width: float) -> void:
	# Stepped contact shadow: no smooth vector oval against the pixel silhouettes.
	for row: int in 5:
		var inset: float=absf(float(row)-2.0)*width*.04
		canvas.draw_rect(Rect2(feet+Vector2(-width*.43+inset,-10+row*3),Vector2(width*.86-inset*2,3)),Color(.20,.24,.16,.10))

static func fence(canvas: CanvasItem,rect: Rect2) -> void:
	var ink:=Color("68634f");var wood:=Color("a79972")
	for x: float in [rect.position.x+4,rect.end.x-8]:
		canvas.draw_rect(Rect2(x,rect.position.y+5,4,rect.size.y-12),ink)
		for y: int in range(int(rect.position.y)+8,int(rect.end.y)-16,24):
			canvas.draw_rect(Rect2(x-3,y-12,10,18),ink);canvas.draw_rect(Rect2(x-1,y-12,6,14),wood)
	canvas.draw_rect(Rect2(rect.position+Vector2(4,4),Vector2(rect.size.x-12,6)),ink)
	canvas.draw_rect(Rect2(rect.position+Vector2(4,2),Vector2(rect.size.x-12,3)),wood)

static func pots(canvas: CanvasItem,rect: Rect2) -> void:
	if rect.size.x<130: return
	for x: float in [rect.position.x+22,rect.end.x-24]:
		var feet:=Vector2(x,rect.end.y-12)
		shadow(canvas,feet,44);TDEnvironmentArt.draw_prop(canvas,14,feet,42,true)
