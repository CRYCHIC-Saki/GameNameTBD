class_name TDFurnitureModel
extends RefCounted
## Shared read-only presentation for catalog, installed pieces and the placement ghost.
const DINING_PARTS: Texture2D=preload("res://assets/redraw-v1/dining-parts.png")
static var _dining_parts: Dictionary={}

const ACCENTS := "res://assets/interiors/shared-accents-v1.png"
const LOUNGE := "res://assets/interiors/lounge-furniture-v1.png"
const ACCENT_REGIONS := [Rect2(29,45,271,243),Rect2(338,45,275,243),Rect2(74,326,183,288),Rect2(370,326,179,290)]
const LOUNGE_REGIONS := {"booth":Rect2(101,5,236,216),"sofa":Rect2(540,28,251,184),"child_seat":Rect2(136,233,160,207),"storefront":Rect2(491,265,343,134)}
static var _props: Dictionary = {}

static func _prop_texture(path: String, region: Rect2) -> AtlasTexture:
	# Each atlas has a separate namespace; its authored trim anchors the feet.
	if not _props.has(path): _props[path] = {}
	var tiles: Dictionary = _props[path]
	if not tiles.has(region):
		var tile := AtlasTexture.new()
		tile.atlas = TDRegionalInterior.source(path)
		tile.region = region
		tile.filter_clip = true
		tiles[region] = tile
	return tiles[region]

static func accent_texture(kind: String, rotation: int) -> AtlasTexture:
	var index := (0 if kind == "screen" else 2) + (1 if rotation in [90, 180] else 0)
	return _prop_texture(ACCENTS, ACCENT_REGIONS[index])

static func _draw_fitted(canvas: CanvasItem, sprite: AtlasTexture, bounds_rect: Rect2, flip: bool, tint: Color) -> void:
	var fit := minf(bounds_rect.size.x / sprite.get_width(), -bounds_rect.position.y / sprite.get_height())
	var size := sprite.get_size() * fit
	var target := Rect2(Vector2(-size.x*.5, -size.y),size)
	if flip: target.size.x = -target.size.x
	canvas.draw_texture_rect(sprite, target, false, tint)


static func dining_part(index: int) -> AtlasTexture:
	if not _dining_parts.has(index):
		var source:=DINING_PARTS.get_image()
		if source.is_compressed(): source.decompress()
		var cell:=Vector2i(source.get_width()/2,source.get_height())
		var origin:=Vector2i(index*cell.x,0)
		var used:=TDStoryArt._walk_bounds(source.get_region(Rect2i(origin,cell)))
		var texture:=AtlasTexture.new();texture.atlas=DINING_PARTS
		texture.region=Rect2(origin+used.position,used.size);texture.filter_clip=true
		_dining_parts[index]=texture
	return _dining_parts[index]

static func table_texture(item: Dictionary) -> AtlasTexture:
	var theme := TDRegionalInterior.piece_style(item)
	return TDRegionalInterior.sprite(theme, 0) if TDRegionalInterior.regional(theme) else dining_part(0)

static func stool_texture(item: Dictionary) -> AtlasTexture:
	var theme := TDRegionalInterior.piece_style(item)
	return TDRegionalInterior.sprite(theme, 1) if TDRegionalInterior.regional(theme) else dining_part(1)

static func dining_table_rect(item: Dictionary) -> Rect2:
	var rect:=bounds(item)
	return Rect2(-rect.size.x*.45,rect.position.y*.82,rect.size.x*.90,-rect.position.y*.81)

static func dining_stool_rect(item: Dictionary, side: float) -> Rect2:
	var rect:=bounds(item)
	# Match the stool in the occupied assembly, so sitting does not resize it.
	var size:=Vector2(rect.size.x*.31,-rect.position.y*.33)
	return Rect2(Vector2(side*rect.size.x*.32,5)-Vector2(size.x*.5,size.y),size)

static func bounds(item: Dictionary) -> Rect2:
	var w: float=(float(item.w)+float(item.h))*48.0*.9
	var height: float=70.0
	match str(item.kind):
		"screen","kiosk","storefront": height=110.0
		"stool","waiting_seat": height=45.0
		"child_seat": height=65.0
		"dining_table": height=w*.78
		"welcome_desk","cashier","order_counter": height=w*.9
	return Rect2(-w*.5,-height,w,height+14)

static func center(item: Dictionary) -> Vector2:
	return TDRestaurantIsoView.project(float(item.x)+float(item.w)*.5,float(item.y)+float(item.h)*.5)

static func dining_feet(item: Dictionary) -> Vector2:
	# Independent front stool ground anchor, shared by approach and seated display.
	var rect:=bounds(item)
	var side: float=1.0 if int(item.get("rotation",0)) in [90,270] else -1.0
	return center(item)+Vector2(side*rect.size.x*.32,5) if str(item.kind) == "dining_table" else center(item)+Vector2(0,4)

static func dining_cushion(item: Dictionary) -> Vector2:
	var side: float=1.0 if int(item.get("rotation",0)) in [90,270] else -1.0
	if str(item.kind) == "dining_table":
		var stool:=dining_stool_rect(item,side)
		return center(item)+stool.position+stool.size*Vector2(.5,.26)
	return center(item)+Vector2(0,-27)

static func dining_pose_rect(item: Dictionary, texture: Texture2D, hip: Vector2) -> Rect2:
	# Keep authored chibi proportions; short legs need not reach the floor.
	var height: float=83.52
	var size:=texture.get_size()*height/texture.get_height()
	if int(item.get("rotation",0)) in [90,270]: hip.x=1.0-hip.x
	return Rect2(dining_cushion(item)-hip*size,size)

static func occupied_pose_rect(item: Dictionary, texture: Texture2D, foot: Vector2) -> Rect2:
	var size:=texture.get_size()*108.0/texture.get_height()
	if int(item.get("rotation",0)) in [90,270]: foot.x=1.0-foot.x
	return Rect2(dining_feet(item)-foot*size,size)

static func uses_occupied_pose(item: Dictionary) -> bool:
	return str(item.get("kind","")) == "dining_table" and not TDRegionalInterior.regional(TDRegionalInterior.piece_style(item))

static func dining_occlusion(item: Dictionary, lower_body: Rect2) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array]=[]
	if str(item.kind) != "dining_table": return result
	# The table-only sprite has true transparent gaps between its legs.
	# The independently placed stools must never be repainted over the diner.
	var rect:=dining_table_rect(item)
	var points:=PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)])
	var clip:=PackedVector2Array([lower_body.position,Vector2(lower_body.end.x,lower_body.position.y),lower_body.end,Vector2(lower_body.position.x,lower_body.end.y)])
	result.append_array(Geometry2D.intersect_polygons(points,clip))
	return result

static func draw_dining_foreground(canvas: CanvasItem, item: Dictionary, lower_body: Rect2) -> void:
	var rect:=dining_table_rect(item)
	var flipped: bool=int(item.get("rotation",0)) in [90,270]
	var tile:=table_texture(item)
	for points: PackedVector2Array in dining_occlusion(item,lower_body):
		var uv:=PackedVector2Array()
		for point: Vector2 in points:
			var local: Vector2=(point-rect.position)/rect.size
			if flipped: local.x=1.0-local.x
			# Polygon UVs address the whole backing atlas; AtlasTexture.draw_rect's
			# region transform is not applied by CanvasItem.draw_polygon.
			uv.append((tile.region.position+local*tile.region.size)/tile.atlas.get_size())
		canvas.draw_polygon(points,PackedColorArray([Color.WHITE]),uv,tile.atlas)

static func draw_model(canvas: CanvasItem, item: Dictionary, tint: Color=Color.WHITE, occupied: bool=false) -> void:
	var rect:=bounds(item)
	var kind:=str(item.kind)
	var rotation:=int(item.get("rotation",0))
	var style:=str(item.get("style_id","chinese_low")).split("_")
	var palette:=TDRestaurantArt.swatch(style[0],style[1])
	var corners:=PackedVector2Array([Vector2(0,-10),Vector2(rect.size.x*.5,0),Vector2(0,14),Vector2(-rect.size.x*.5,0)])
	canvas.draw_colored_polygon(corners,Color(0,0,0,.16)*tint)
	if TDRestaurantLayout.shared_accent(kind):
		_draw_fitted(canvas, accent_texture(kind, rotation), rect, rotation in [90,270], tint)
		return
	if kind == "storefront":
		# A wall-mounted plaque follows the wall plane. Its six-cell frontage
		# describes the fixture's reservation, not the width of a billboard.
		var along := Vector2(1, .5) if item.w >= item.h else Vector2(-1, .5)
		var center_on_wall := Vector2(0, -40)
		var half_span := along * 51.0
		var half_rise := Vector2(0, -19)
		var points := PackedVector2Array([center_on_wall-half_span+half_rise,center_on_wall+half_span+half_rise,center_on_wall+half_span-half_rise,center_on_wall-half_span-half_rise])
		var sprite := _prop_texture(LOUNGE,LOUNGE_REGIONS.storefront)
		var r := sprite.region
		var uv := PackedVector2Array([r.position,Vector2(r.end.x,r.position.y),r.end,Vector2(r.position.x,r.end.y)])
		for i: int in uv.size(): uv[i] /= sprite.atlas.get_size()
		canvas.draw_polygon(points,PackedColorArray([tint]),uv,sprite.atlas)
		return
	if LOUNGE_REGIONS.has(kind):
		var sprite := _prop_texture(LOUNGE,LOUNGE_REGIONS[kind])
		var finish := Color.WHITE.lerp(Color(palette.cloth), .20) if TDRegionalInterior.regional(style[0]) else Color.WHITE
		_draw_fitted(canvas, sprite, rect, rotation in [90,270], tint*finish)
		return
	if kind == "dining_table":
		var table:=dining_table_rect(item)
		if rotation in [90,270]: table.size.x=-table.size.x
		canvas.draw_texture_rect(table_texture(item),table,false,tint)
		for side: float in [-1.0,1.0]:
			if occupied and side==(1.0 if rotation in [90,270] else -1.0): continue
			canvas.draw_texture_rect(stool_texture(item),dining_stool_rect(item,side),false,tint)
		return
	if kind in ["welcome_desk","cashier","order_counter"]:
		var texture: Texture2D=TDRegionalInterior.sprite(style[0],2) if TDRegionalInterior.regional(style[0]) else TDEnvironmentArt.sprite(1)
		var target:=Rect2(rect.position,Vector2(rect.size.x,-rect.position.y))
		# Godot flips a negative-width texture inside the same destination bounds.
		# Moving x as well would displace the model by a whole furniture width.
		if rotation in [90,270]: target.size.x=-target.size.x
		canvas.draw_texture_rect(texture,target,false,tint)
		return
	if kind in ["stool", "waiting_seat"]:
		var texture := stool_texture(item)
		var size := texture.get_size() * 43.0 / texture.get_height()
		canvas.draw_texture_rect(texture, Rect2(Vector2(-size.x*.5, 5-size.y), size), false, tint)
		return

static func hit(item: Dictionary, point: Vector2) -> bool:
	return bounds(item).has_point(point-center(item))
