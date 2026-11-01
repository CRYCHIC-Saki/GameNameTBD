class_name TDTownScenery
extends RefCounted
## Presentation-only terrain cache. Its hash never consumes the simulation RNG.
const SCALE: int=24
const MATERIALS=preload("res://assets/town/ground-materials-v4.png")
static var _key: String=""
static var _ground: ImageTexture
static var _trees: Array[Vector2]=[]
static var _swatches: Array[Image]=[]
static var _dressing_key: String=""
static var _dressing: Array[Dictionary]=[]

static func paint(image: Image,rect: Rect2i,index: int) -> void:
	if _swatches.is_empty():
		var source:=MATERIALS.get_image()
		if source.is_compressed(): source.decompress()
		source.convert(Image.FORMAT_RGBA8)
		var side: int=source.get_width()/2
		for i: int in 4:
			var tile:=source.get_region(Rect2i((i%2)*side,(i/2)*side,side,side))
			tile.resize(120,120,Image.INTERPOLATE_NEAREST);_swatches.append(tile)
	var y: int=rect.position.y
	while y<rect.end.y:
		var height: int=mini(120-y%120,rect.end.y-y);var x: int=rect.position.x
		while x<rect.end.x:
			var width: int=mini(120-x%120,rect.end.x-x)
			image.blit_rect(_swatches[index],Rect2i(x%120,y%120,width,height),Vector2i(x,y));x+=width
		y+=height

static func noise(x: int,y: int,salt: int=0) -> int:
	return absi((x*73856093)^(y*19349663)^(salt*83492791))

static func ground(map: TDTownMap) -> ImageTexture:
	var key: String="%d:%d:%d:%d"%[map.layout_version,map.extent,map.roads.hash(),map.plots.hash()]
	if _ground!=null and key==_key: return _ground
	var image:=Image.create(map.extent*SCALE,map.extent*SCALE,false,Image.FORMAT_RGBA8)
	var surfaces: Dictionary={}
	for y: int in map.extent:
		for x: int in map.extent: surfaces[Vector2i(x,y)]=str(map.terrain_at(Vector2i(x,y)).surface_type)
	_trees.clear()
	for y: int in map.extent:
		for x: int in map.extent:
			var at:=Vector2i(x,y);var origin:=at*SCALE;var surface: String=surfaces[at]
			paint(image,Rect2i(origin,Vector2i.ONE*SCALE),3 if surface=="water" else (1 if surface=="stone" else 0))
			if surface=="bridge":
				image.fill_rect(Rect2i(origin,Vector2i.ONE*SCALE),Color("927357"))
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
