extends RefCounted
## Dimensions are in map cells. Only protected residential plots receive fences.
const WOOD := {"chengdu":"a77b50","tokyo":"835e48","paris":"bdab87"}
static var _textures: Dictionary = {}

static func is_residential(kind: String) -> bool:
	return kind in ["housing","player_cottage","urban_village","rich_district"]

## Mark courtyards and their free verge on the cached drawing surface. Street,
## shore and neighbouring parcel ownership come from the original geography.
static func apply_lawns(surfaces: Dictionary, plots: Array) -> void:
	var occupied: Dictionary = {}
	var homes: Array[Rect2i] = []
	for p: Dictionary in plots:
		var lot := Rect2i(p.x,p.y,p.w,p.h)
		if is_residential(p.kind):
			homes.append(lot)
		else:
			for y: int in range(lot.position.y,lot.end.y):
				for x: int in range(lot.position.x,lot.end.x):
					occupied[Vector2i(x,y)] = true
	for lot: Rect2i in homes:
		var verge := lot.grow(1)
		for y: int in range(verge.position.y,verge.end.y):
			for x: int in range(verge.position.x,verge.end.x):
				var at := Vector2i(x,y)
				if not occupied.has(at) and surfaces.get(at,"") in ["grass","lane","lawn","square","quay","earth"]:
					surfaces[at] = "lawn"

static func facade_lot(lot: Rect2, cell: float, fenced: bool) -> Rect2:
	var side := .64 if fenced else .2
	var front := .70 if fenced else .55
	return lot.grow_individual(-side*cell,0,-side*cell,-front*cell)

static func has_yard(p: Dictionary) -> bool:
	return not p.get("construction",false) and ((p.kind=="rich_district" and p.w>=4 and p.h>=4) or (p.kind=="urban_village" and p.w>=5 and p.h>=5))

## Fence centre lines in world pixels. Measure the rendered roof as well as the
## garden; the parcel edge remains the limit beside public roads.
static func enclosure(p: Dictionary, cell: float, origin: Vector2, house: Rect2) -> Rect2:
	var limit := TDInteractionRange.plot_bounds(p,cell,origin).grow(-cell*.10)
	var side := clampf(house.size.x*.15,24.0,44.0)
	var garden := house.grow_individual(side,26.0,side,60.0)
	limit.end.y -= cell*.04
	return limit.intersection(garden)

static func sections(town: String, p: Dictionary, cell: float, origin: Vector2, house: Rect2) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not has_yard(p): return result
	var court := enclosure(p,cell,origin,house)
	var first := court.position
	var last := court.end
	var door_x := house.get_center().x
	var entrance := origin+Vector2(p.approach_x+.5,p.approach_y+.5)*cell
	_run(result,town,first,Vector2(last.x,first.y),entrance)
	for x: float in [first.x,last.x]:
		_run(result,town,Vector2(x,first.y),Vector2(x,last.y),entrance)
	_run(result,town,Vector2(first.x,last.y),Vector2(door_x-48,last.y),entrance)
	_run(result,town,Vector2(door_x+48,last.y),last,entrance)
	return result

static func _run(output: Array[Dictionary],town: String,a: Vector2,b: Vector2,entrance: Vector2) -> void:
	var repeats := ceili(a.distance_to(b)/56.0)
	var unit := 2.4
	for index: int in repeats:
		var first := a.lerp(b,float(index)/repeats)
		var last := a.lerp(b,float(index+1)/repeats)
		if entrance.distance_to(Geometry2D.get_closest_point_to_segment(entrance,first,last))<36.0: continue
		var rect := Rect2(first-Vector2(2,15)*unit,last-first+Vector2(5,16)*unit)
		var base := Rect2(first-Vector2(2,1)*unit,last-first+Vector2(4,2)*unit)
		output.append({"art":_texture(town,a.y==b.y),"rect":rect,"bases":[base]})

static func _texture(town: String, across: bool) -> Texture2D:
	var key := town + ("-rail" if across else "-side")
	if _textures.has(key): return _textures[key]
	var panel := Image.create(29 if across else 5,16 if across else 40,false,Image.FORMAT_RGBA8)
	var wood := Color(WOOD[town])
	var edge := wood.darkened(.40)
	var light := wood.lightened(.27)
	if across:
		for x: int in range(4,25):
			var rise := 12-(x-4)/3
			panel.fill_rect(Rect2i(x,rise,1,3),edge)
			panel.set_pixel(x,rise,wood)
		for y: int in [4,10]:
			panel.fill_rect(Rect2i(1,y,27,4),edge)
			panel.fill_rect(Rect2i(1,y,26,1),light)
			panel.fill_rect(Rect2i(1,y+1,26,2),wood)
			panel.set_pixel(9 if y==4 else 17,y+2,wood.darkened(.15))
	else:
		panel.fill_rect(Rect2i(0,4,4,34),edge)
		panel.fill_rect(Rect2i(0,4,1,31),light)
		panel.fill_rect(Rect2i(1,4,2,31),wood)
	for tip: Vector2i in [Vector2i.ZERO,Vector2i(24,0) if across else Vector2i(0,24)]:
		panel.fill_rect(Rect2i(tip+Vector2i(0,2),Vector2i(5,13)),edge)
		panel.fill_rect(Rect2i(tip+Vector2i(1,2),Vector2i(3,12)),wood)
		panel.fill_rect(Rect2i(tip+Vector2i(1,3),Vector2i(1,10)),light)
		panel.fill_rect(Rect2i(tip+Vector2i(1,0),Vector2i(3,2)),light)
		panel.fill_rect(Rect2i(tip+Vector2i(0,2),Vector2i(5,1)),wood.lightened(.12))
		panel.set_pixelv(tip+Vector2i(2,6),edge)
		panel.set_pixelv(tip+Vector2i(3,10),wood.darkened(.19))
	_textures[key]=ImageTexture.create_from_image(panel)
	return _textures[key]

static func paint_steps(image: Image, map: TDTownMap, scale: int, town: String) -> void:
	# Stepping stones sit flush with the lawn and lead through the actual front gap.
	var stone := Color("b8b5a0")
	for p: Dictionary in map.plots:
		if not has_yard(p): continue
		for n: int in 4:
			var at := Vector2(p.x+p.w*.5,p.y+p.h-.56+n*.25)
			if map.terrain_at(Vector2i(at)).surface_type!="lawn": continue
			var pixel := Vector2i(at*scale) + Vector2i(1 if n%2==0 else -1,0)
			image.fill_rect(Rect2i(pixel-Vector2i(6,2),Vector2i(13,5)),stone.darkened(.24))
			image.fill_rect(Rect2i(pixel-Vector2i(7,1),Vector2i(15,3)),stone)
			image.fill_rect(Rect2i(pixel-Vector2i(5,2),Vector2i(10,1)),stone.lightened(.18))
