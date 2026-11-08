class_name TDFurnitureModel
extends RefCounted
## Shared read-only presentation for catalog, installed pieces and the placement ghost.
const DINING_PARTS: Texture2D=preload("res://assets/town/dining-table-stool-separated-v1.png")
static var _dining_parts: Dictionary={}

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
		"dining_table","hotpot_table": height=w*.78
		"welcome_desk","cashier","order_counter": height=w*.9
	return Rect2(-w*.5,-height,w,height+14)

static func center(item: Dictionary) -> Vector2:
	return TDRestaurantIsoView.project(float(item.x)+float(item.w)*.5,float(item.y)+float(item.h)*.5)

static func dining_feet(item: Dictionary) -> Vector2:
	# Independent front stool ground anchor, shared by approach and seated display.
	var rect:=bounds(item)
	var side: float=1.0 if int(item.get("rotation",0)) in [90,270] else -1.0
	return center(item)+Vector2(side*rect.size.x*.32,5) if str(item.kind) in ["dining_table","hotpot_table"] else center(item)+Vector2(0,4)

static func dining_cushion(item: Dictionary) -> Vector2:
	var side: float=1.0 if int(item.get("rotation",0)) in [90,270] else -1.0
	if str(item.kind) in ["dining_table","hotpot_table"]:
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
	return str(item.get("kind","")) in ["dining_table","hotpot_table"]

static func dining_occlusion(item: Dictionary, lower_body: Rect2) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array]=[]
	if str(item.kind) not in ["dining_table","hotpot_table"]: return result
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
	var tile:=dining_part(0)
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
	var wood:=Color(palette.wood)*tint
	var cloth:=Color(palette.cloth)*tint
	var trim:=Color(palette.accent)*tint
	var corners:=PackedVector2Array([Vector2(0,-10),Vector2(rect.size.x*.5,0),Vector2(0,14),Vector2(-rect.size.x*.5,0)])
	canvas.draw_colored_polygon(corners,Color(0,0,0,.16)*tint)
	if kind in ["dining_table","hotpot_table"]:
		var table:=dining_table_rect(item)
		if rotation in [90,270]: table.size.x=-table.size.x
		canvas.draw_texture_rect(dining_part(0),table,false,tint)
		for side: float in [-1.0,1.0]:
			if occupied and side==(1.0 if rotation in [90,270] else -1.0): continue
			canvas.draw_texture_rect(dining_part(1),dining_stool_rect(item,side),false,tint)
		if kind=="hotpot_table":
			canvas.draw_circle(Vector2(0,rect.position.y*.55),12,Color("343d3b")*tint)
			canvas.draw_arc(Vector2(0,rect.position.y*.55),9,0,TAU,16,Color("df7151")*tint,3)
		return
	if kind in ["welcome_desk","cashier","order_counter"]:
		var texture:=TDEnvironmentArt.sprite(1)
		var target:=Rect2(rect.position,Vector2(rect.size.x,-rect.position.y))
		# Godot flips a negative-width texture inside the same destination bounds.
		# Moving x as well would displace the model by a whole furniture width.
		if rotation in [90,270]: target.size.x=-target.size.x
		canvas.draw_texture_rect(texture,target,false,tint)
		return
	# Raised furniture remains pixel-aligned; rotation flips its front/back details.
	var left:=rotation in [90,180]
	var width:=rect.size.x*.72
	var top:=rect.position.y+8
	if kind in ["screen","storefront"]:
		canvas.draw_rect(Rect2(-width*.5,top,width,-top),wood)
		canvas.draw_rect(Rect2(-width*.5+6,top+6,width-12,-top-15),Color("e4cc93")*tint)
		for x in range(3):
			var px:float=-width*.5+width*(x+1)/4
			canvas.draw_line(Vector2(px,top+6),Vector2(px,-10),wood,3)
		canvas.draw_line(Vector2(-width*.5,top+22),Vector2(width*.5,top+22),wood,3)
		canvas.draw_line(Vector2(-width*.5,top+48),Vector2(width*.5,top+48),wood,3)
		canvas.draw_rect(Rect2(-width*.5-4,-3,15,8),wood)
		canvas.draw_rect(Rect2(width*.5-11,-3,15,8),wood)
	elif kind=="kiosk":
		canvas.draw_rect(Rect2(-24,-20,48,24),wood)
		canvas.draw_rect(Rect2(-9,-70,18,55),wood)
		canvas.draw_rect(Rect2(-30,top,60,52),wood)
		canvas.draw_rect(Rect2(-24,top+6,48,38),Color("68aa9a")*tint if not left else wood.lightened(.12))
		if not left:
			for y in range(3): canvas.draw_line(Vector2(-16,top+14+y*10),Vector2(12,top+14+y*10),Color("f6e9c6")*tint,3)
	else:
		var tall: bool=kind in ["booth","sofa","child_seat"]
		if tall:
			canvas.draw_rect(Rect2(-width*.5,top,width,-top-20),wood)
			canvas.draw_rect(Rect2(-width*.5+5,top+6,width-10,-top-32),cloth)
		canvas.draw_rect(Rect2(-width*.5,-29,width,18),wood)
		canvas.draw_rect(Rect2(-width*.5+3,-29,width-6,8),cloth if tall else trim)
		for side: int in [-1,1]:
			canvas.draw_rect(Rect2(side*(width*.5-7)-3,-11,6,18),wood)
		if tall and left: canvas.draw_rect(Rect2(-width*.5,-35,width,23),wood)
	canvas.draw_line(Vector2(rect.position.x*.7,top),Vector2(-rect.position.x*.7,top),trim,3)

static func hit(item: Dictionary, point: Vector2) -> bool:
	return bounds(item).has_point(point-center(item))
