class_name TDEnvironmentArt
extends RefCounted
## Read-only generated atlases. No mutable image state is shared with a game session.
const TOWN := preload("res://assets/town/town-sprites-v3.png")
const PROPS := preload("res://assets/town/diner-props-v2.png")
const RESIDENTIAL := preload("res://assets/town/residential-houses-v2.png")
const RESIDENTIAL_REGIONS: Array[Rect2i]=[Rect2i(0,0,660,540),Rect2i(660,0,594,540),Rect2i(0,540,662,714),Rect2i(662,540,592,714)]
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
			Rect2(0,0,384,326),Rect2(384,0,312,326),Rect2(696,0,304,326),Rect2(1000,0,254,326),
			Rect2(0,326,384,304),Rect2(384,326,370,304),Rect2(754,326,246,304),Rect2(1000,326,254,304),
			Rect2(0,630,384,306),Rect2(384,630,312,306),Rect2(696,630,344,306),Rect2(1040,630,214,306),
			Rect2(0,936,384,318),Rect2(384,936,358,318),Rect2(742,936,258,318),Rect2(1000,936,254,318)]
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
	var used:=source.get_region(Rect2i(origin,size)).get_used_rect()
	var tile:=AtlasTexture.new();tile.atlas=RESIDENTIAL;tile.filter_clip=true
	tile.region=Rect2(used.position+origin,used.size)
	_cache[key]=tile
	return tile

static func draw_residential(canvas: CanvasItem,index: int,rect: Rect2) -> void:
	var texture:=residential(index)
	var width: float=minf(rect.size.x,rect.size.y*texture.get_width()/texture.get_height())
	var height: float=width*texture.get_height()/texture.get_width()
	var feet:=Vector2(rect.get_center().x,rect.end.y)
	canvas.draw_texture_rect(texture,Rect2(feet-Vector2(width*.5,height),Vector2(width,height)),false)
