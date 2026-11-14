class_name TDEnvironmentArt
extends RefCounted
## Read-only generated atlases. No mutable image state is shared with a game session.
const TOWN := preload("res://assets/town/town-sprites-v4.png")
const PROPS := preload("res://assets/redraw-v1/diner-props.png")
const RESIDENTIAL := preload("res://assets/town/residential-houses-v3.png")
const FACTORIES := preload("res://assets/town/supply-factories-v2.png")
const DINER := preload("res://assets/town/restaurant-chinese-v1.png")
const RESIDENTIAL_REGIONS: Array[Rect2i]=[Rect2i(0,0,632,536),Rect2i(632,0,658,536),Rect2i(0,536,652,683),Rect2i(652,536,638,683)]
static var _cache: Dictionary={}

static func sprite(index: int, town: bool = false) -> AtlasTexture:
	var key: String="%s:%d"%[town,index]
	if _cache.has(key): return _cache[key]
	var atlas: Texture2D=TOWN if town else PROPS
	var tile:=AtlasTexture.new();tile.atlas=atlas
	var side: float=atlas.get_width()/4.0
	tile.region=Rect2(Vector2(index%4,index/4)*side,Vector2.ONE*side)
	if town:
		# Generated objects are not uniformly spaced; explicit regions avoid neighbours.
		var regions: Array[Rect2]=[
			Rect2(0,0,361,329),Rect2(361,0,309,329),Rect2(670,0,309,329),Rect2(979,0,298,329),
			Rect2(0,329,357,293),Rect2(357,329,382,293),Rect2(739,329,229,293),Rect2(968,329,309,293),
			Rect2(0,622,361,309),Rect2(361,622,310,309),Rect2(671,622,345,309),Rect2(1016,622,261,309),
			Rect2(0,931,348,300),Rect2(348,931,364,300),Rect2(712,931,251,300),Rect2(963,931,314,300)]
		tile.region=regions[index]
		var source:=TOWN.get_image()
		if source.is_compressed(): source.decompress()
		var used:=source.get_region(Rect2i(tile.region)).get_used_rect()
		tile.region=Rect2(tile.region.position+Vector2(used.position),used.size)
	tile.filter_clip=true
	_cache[key]=tile
	return tile

static func draw_prop(canvas: CanvasItem, index: int, feet: Vector2, width: float, town: bool = false) -> void:
	var texture:=sprite(index,town)
	var height: float=width*texture.get_height()/texture.get_width()
	canvas.draw_texture_rect(texture,Rect2(feet-Vector2(width*.5,height*.97),Vector2(width,height)),false)

static func residential(index: int) -> AtlasTexture:
	var key: String="residential:%d"%index
	if _cache.has(key): return _cache[key]
	var source:=RESIDENTIAL.get_image()
	if source.is_compressed(): source.decompress()
	var size: Vector2i=RESIDENTIAL_REGIONS[index].size
	var origin: Vector2i=RESIDENTIAL_REGIONS[index].position
	# Keep each quadrant separate; trim transparent margins only in the read-only atlas region.
	var crop:=source.get_region(Rect2i(origin,size))
	# Almost transparent generation residue must not count as courtyard margins.
	var minimum:=crop.get_size();var maximum:=Vector2i(-1,-1)
	for y: int in crop.get_height():
		for x: int in crop.get_width():
			if crop.get_pixel(x,y).a<.15: continue
			minimum=minimum.min(Vector2i(x,y));maximum=maximum.max(Vector2i(x,y))
	var used:=Rect2i(minimum,maximum-minimum+Vector2i.ONE)
	var tile:=AtlasTexture.new();tile.atlas=RESIDENTIAL;tile.filter_clip=true
	tile.region=Rect2(used.position+origin,used.size)
	_cache[key]=tile
	return tile

static func factory(supply: String) -> AtlasTexture:
	var index: int={"seasoning":0,"vegetable":1,"meat":2,"fruit":3}.get(supply,0)
	var key: String="factory:%d"%index
	if _cache.has(key): return _cache[key]
	var source:=FACTORIES.get_image()
	if source.is_compressed(): source.decompress()
	var half:=Vector2i(source.get_width()/2,source.get_height()/2)
	var origin:=Vector2i((index%2)*half.x,(index/2)*half.y)
	var used:=source.get_region(Rect2i(origin,half)).get_used_rect()
	var tile:=AtlasTexture.new();tile.atlas=FACTORIES;tile.filter_clip=true
	tile.region=Rect2(used.position+origin,used.size)
	_cache[key]=tile
	return tile

static func diner() -> AtlasTexture:
	var key := "diner"
	if _cache.has(key): return _cache[key]
	var source := DINER.get_image()
	if source.is_compressed(): source.decompress()
	var used := source.get_used_rect()
	var tile := AtlasTexture.new()
	tile.atlas = DINER
	tile.filter_clip = true
	tile.region = Rect2(used)
	_cache[key] = tile
	return tile

static func draw_diner(canvas: CanvasItem, feet: Vector2, width: float) -> void:
	var texture := diner()
	var height: float = width * texture.get_height() / texture.get_width()
	canvas.draw_texture_rect(texture, Rect2(feet - Vector2(width * 0.5, height * 0.97), Vector2(width, height)), false)

static func draw_factory(canvas: CanvasItem,supply: String,feet: Vector2,width: float,unfinished: bool) -> void:
	var texture:=factory(supply)
	var height: float=width*texture.get_height()/texture.get_width()
	var tint:=Color(0.82,0.84,0.86) if unfinished else Color.WHITE
	canvas.draw_texture_rect(texture,Rect2(feet-Vector2(width*.5,height*.97),Vector2(width,height)),false,tint)

static func fit_in_plot(texture: Texture2D,rect: Rect2,_label_space: float=0.0) -> Rect2:
	# Use the complete vacant area. Keep the facade bottom against the street,
	# rather than shrinking it to reserve a caption strip or centring it vertically.
	var area:=rect.grow(-4.0)
	var size:=texture.get_size()*minf(area.size.x/texture.get_width(),area.size.y/texture.get_height())
	return Rect2(Vector2(area.get_center().x-size.x*.5,area.end.y-size.y),size)

static func draw_residential(canvas: CanvasItem,index: int,rect: Rect2,_display_scale: float=1.0) -> void:
	var texture:=residential(index)
	canvas.draw_texture_rect(texture,fit_in_plot(texture,rect),false)
