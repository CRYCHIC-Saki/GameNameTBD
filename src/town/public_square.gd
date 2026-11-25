extends RefCounted
## The town square and its adjoining civic frontage share a single pedestrian court.
const INLAYS := "res://assets/town/plaza-inlays-v1.png"
const JIANGNAN_COURT := "res://assets/town/jiangnan-court-v1.png"
const PALETTES := {
	"chengdu":["948a78","e3d6af","6c7c79"],
	"tokyo":["998f86","ddcdbc","716a76"],
	"paris":["c3ae91","f0e0be","89796b"],
}
static var _inlays := {}
static var _stone := {}

static func bounds(map: TDTownMap) -> Rect2i:
	if map.layout_version!=2: return Rect2i()
	var plot := map._by_id("plaza")
	if plot.is_empty() or plot.kind!="plaza": return Rect2i()
	var court := Rect2i(plot.x,plot.y,plot.w,plot.h)
	var landmark := map._by_id("landmark")
	if landmark.get("x",-1)==court.end.x and landmark.y==court.position.y and landmark.h==court.size.y:
		court.size.x+=int(landmark.w)
	return court

static func mark(surfaces: Dictionary, court: Rect2i) -> void:
	for y: int in range(court.position.y,court.end.y):
		for x: int in range(court.position.x,court.end.x):
			var at := Vector2i(x,y)
			if surfaces.get(at) in ["grass","lawn"]: surfaces[at]="civic_paving"

static func meeting_point(court: Rect2i) -> Vector2:
	return Vector2(court.position)+Vector2(court.size)*Vector2(.52,.75)

## Locate a public street opposite each side. Continue the flagstones across
## the border and grass verge, up to the curb, keeping neighbouring lots clear.
static func entrances(map: TDTownMap, court: Rect2i) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	if not court.has_area(): return result
	for side: Vector2i in [Vector2i.DOWN,Vector2i.UP,Vector2i.LEFT,Vector2i.RIGHT]:
		var horizontal := side.y!=0
		var length := court.size.x if horizontal else court.size.y
		var best := INF
		var selected := {}
		for i: int in range(1,length-1):
			var edge := court.position+Vector2i(i,0) if horizontal else court.position+Vector2i(0,i)
			if side==Vector2i.DOWN: edge.y=court.end.y-1
			if side==Vector2i.RIGHT: edge.x=court.end.x-1
			for depth: int in range(1,4):
				var at := edge+side*depth
				var terrain := map.terrain_at(at)
				if terrain.terrain_type!="plain" or not terrain.walkable: break
				if map.is_road(at.x,at.y):
					var score := 2*depth+absf(i+.5-length*.5)
					if score<best:
						best=score
						selected={"edge":edge,"side":side,"depth":depth}
					break
				if not map.plot_at(at.x,at.y).is_empty(): break
		if not selected.is_empty(): result.append(selected)
	return result

static func _flagstones(town: String) -> Image:
	if _stone.has(town): return _stone[town]
	var tile := TDTownScenery.surface_texture(1,town).get_image().duplicate() as Image
	var palette: Array = PALETTES[town]
	var ground := Color(palette[0])
	# Broad, staggered flagstones with tool marks from the local stone illustration.
	for y: int in tile.get_height():
		var course := y/15
		for x: int in tile.get_width():
			var u := (x+course%2*15)%30
			var v := y%15
			var grain := tile.get_pixel(x,y).get_luminance()
			var cut := ground.lerp(Color(palette[1]),clampf(grain*.52+float((x+course%2*15)/30%3)*.037,0,1))
			if u==0 or v==0: cut=cut.darkened(.18)
			elif u==1 or v==1: cut=cut.lightened(.095)
			tile.set_pixel(x,y,cut)
	_stone[town]=tile
	return tile

static func paint(image: Image, map: TDTownMap, surfaces: Dictionary, town: String, size: int) -> void:
	var court := bounds(map)
	if not court.has_area(): return
	var area := Rect2i(court.position*size,court.size*size)
	var field := Image.create(area.size.x,area.size.y,false,Image.FORMAT_RGBA8)
	if town=="chengdu":
		field=_jiangnan_field(area)
	else:
		var base := _flagstones(town)
		for y: int in range(0,area.size.y,base.get_height()):
			for x: int in range(0,area.size.x,base.get_width()):
				var left := area.size-Vector2i(x,y)
				field.blit_rect(base,Rect2i(Vector2i.ZERO,left.min(base.get_size())),Vector2i(x,y))
		var palette: Array = PALETTES[town]
		_inlay(field,court,town,size,Color(palette[2]),Color(palette[1]))
	for y: int in court.size.y:
		for x: int in court.size.x:
			var at := court.position+Vector2i(x,y)
			if surfaces.get(at)!="civic_paving": continue
			image.blit_rect(field,Rect2i(Vector2i(x,y)*size,Vector2i.ONE*size),at*size)
	# Jiangnan's four gates follow the same curved street centre lines as
	# its storefronts; paint them after the adjoining ground is in place.
	if town=="chengdu": return
	for gate: Dictionary in entrances(map,court):
		var side: Vector2i = gate.side
		var edge: Vector2i = gate.edge
		var tangent := Vector2i(absi(side.y),absi(side.x))
		var mouth := edge*size+Vector2i.ONE*(size/2)+side*(size/2)
		var inside := mouth-side*15
		var outside := mouth+side*((int(gate.depth)-1)*size)
		var half := tangent*(size/2-2)
		var area_min := inside.min(outside)-half
		var area_max := inside.max(outside)+half
		TDTownScenery.paint(image,Rect2i(area_min,area_max-area_min),1,town)

static func _inlay(field: Image, court: Rect2i, town: String, size: int, trim: Color, light: Color) -> void:
	for inset: int in [3,6,13]:
		var frame := Rect2i(Vector2i.ZERO,field.get_size()).grow(-inset)
		var width := 3 if inset==6 else 1
		var tint := trim if inset==6 else light
		field.fill_rect(Rect2i(frame.position,Vector2i(frame.size.x,width)),tint)
		field.fill_rect(Rect2i(frame.position,Vector2i(width,frame.size.y)),tint)
		field.fill_rect(Rect2i(frame.position.x,frame.end.y-width,frame.size.x,width),tint)
		field.fill_rect(Rect2i(frame.end.x-width,frame.position.y,width,frame.size.y),tint)
	var diameter := roundi(minf(court.size.x*.46,court.size.y*.37)*size)
	var key := town+str(diameter)
	if not _inlays.has(key):
		var atlas: Texture2D = load(INLAYS)
		var motif := atlas.get_image().get_region(Rect2i(TDTravelCatalog.IDS.find(town)*128,0,128,128))
		motif.resize(diameter,diameter,Image.INTERPOLATE_BILINEAR)
		_inlays[key]=motif
	var badge: Image = _inlays[key]
	var center := Vector2i((meeting_point(court)-Vector2(court.position))*size)
	field.blend_rect(badge,Rect2i(Vector2i.ZERO,badge.get_size()),center-badge.get_size()/2)

## The verge meets the grass at the same world coordinates as the street bed.
## Work on the cached ground, never on the walk mask or shared art.
static func _jiangnan_field(area: Rect2i) -> Image:
	var art: Texture2D = load(JIANGNAN_COURT)
	var field := art.get_image().duplicate() as Image
	if field.is_compressed(): field.decompress()
	field.convert(Image.FORMAT_RGBA8)
	if field.get_size()!=area.size: field.resize(area.size.x,area.size.y,Image.INTERPOLATE_NEAREST)
	var lawn := TDTownScenery.surface_texture(0,"chengdu").get_image()
	var sz := field.get_size()
	for y: int in sz.y:
		for x: int in sz.x:
			var edge := mini(mini(x,sz.x-x-1),mini(y,sz.y-y-1))
			if edge>=14: continue
			var lichen := sin(x*.047+y*.081)+sin(y*.074-x*.025)
			var fringe := clampf(3.0+4.0*lichen+2.0*sin(x*.11+y*.16),0,14)
			if edge<fringe:
				var p := area.position+Vector2i(x,y)
				var grass := lawn.get_pixel(p.x%lawn.get_width(),p.y%lawn.get_height())
				field.set_pixel(x,y,grass if edge<fringe-2 else field.get_pixel(x,y).lerp(grass,.56))
	return field
