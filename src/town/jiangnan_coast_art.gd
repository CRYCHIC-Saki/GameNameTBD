extends RefCounted
## The approved coast is surveyed in world cells. Rendering and gameplay share
## its polygons and street centerlines, with smaller pixels at the edges.
const Paving := preload("res://src/town/jiangnan_paving.gd")
const District := preload("res://src/town/jiangnan_district_terrain.gd")
const SPRITES := "res://assets/town/jiangnan-river-sprites-v1.png"
const SIZES := [Vector2i(238,102),Vector2i(251,83),Vector2i(145,61),Vector2i(208,175),Vector2i(198,187),Vector2i(200,162)]
const GRASS_SHADE := Color(.89,1.08,.93)
const ROCK := Color("9d9a78")
const SAND := Color("c3ad76")
const SURF := Color("98d0bb")
static var _materials: Dictionary = {}
static var _sprites: Dictionary = {}

static func picture(id: int) -> AtlasTexture:
	if not _sprites.has(id):
		var art := AtlasTexture.new()
		var frame: Vector2i = SIZES[id]
		art.atlas = load(SPRITES)
		art.region = Rect2i(Vector2i(id%3,id/3)*320+Vector2i((320-frame.x)/2,316-frame.y),frame)
		art.filter_clip = true
		_sprites[id] = art
	return _sprites[id]

static func _material(id: int) -> Image:
	if _materials.has(id): return _materials[id]
	var source := TDTownScenery.surface_texture(id).get_image()
	if id==1:
		source = Paving.stone_swatch()
		source.resize(134,134,Image.INTERPOLATE_NEAREST)
	elif id==0:
		for y: int in source.get_height():
			for x: int in source.get_width():
				var c := source.get_pixel(x,y)*GRASS_SHADE
				source.set_pixel(x,y,c)
	_materials[id] = source
	return source

static func _tile(image: Image, rect: Rect2i, material: Image) -> void:
	var period := material.get_size()
	var y := rect.position.y
	while y<rect.end.y:
		var height := mini(period.y-y%period.y,rect.end.y-y)
		var x := rect.position.x
		while x<rect.end.x:
			var width := mini(period.x-x%period.x,rect.end.x-x)
			var crop := Rect2i(x%period.x,y%period.y,width,height)
			image.blit_rect(material,crop,Vector2i(x,y))
			x+=width
		y+=height

static func _polygon(image: Image, outline: Array, size: int, paint_row: Callable) -> void:
	var points := PackedVector2Array()
	var bounds := Rect2()
	for raw: Array in outline:
		var point := Vector2(raw[0],raw[1])*size
		if points.is_empty(): bounds = Rect2(point,Vector2.ZERO)
		bounds = bounds.expand(point)
		points.append(point)
	for y: int in range(maxi(0,floori(bounds.position.y)),mini(image.get_height(),ceili(bounds.end.y))):
		var scan := y+.5
		var intersections := PackedFloat32Array()
		for i: int in points.size():
			var a := points[i]
			var b := points[(i+1)%points.size()]
			if (a.y>scan)==(b.y>scan): continue
			intersections.append(lerpf(a.x,b.x,(scan-a.y)/(b.y-a.y)))
		intersections.sort()
		for i: int in range(0,intersections.size()-1,2):
			var first := clampi(roundi(intersections[i]),0,image.get_width())
			var last := clampi(roundi(intersections[i+1]),0,image.get_width())
			if last>first: paint_row.call(Rect2i(first,y,last-first,1))

static func _stroke(image: Image, outline: Array, size: int, width: float, material: Image, pigment: Color = Color.WHITE) -> void:
	for i: int in range(1,outline.size()):
		var a := Vector2(outline[i-1][0],outline[i-1][1])*size
		var b := Vector2(outline[i][0],outline[i][1])*size
		var length := a.distance_to(b)
		if length<.01: continue
		var center := Rect2(a,Vector2.ZERO).expand(b).grow(width+2.0)
		var period := material.get_size() if material!=null else Vector2i.ONE
		for y: int in range(maxi(0,floori(center.position.y)),mini(image.get_height(),ceili(center.end.y))):
			for x: int in range(maxi(0,floori(center.position.x)),mini(image.get_width(),ceili(center.end.x))):
				var pos := Vector2(x+.5,y+.5)
				var round_edge := Geometry2D.get_closest_point_to_segment(pos,a,b)
				var tooth := float(TDTownScenery.noise(x/2,y/2,11)%5-2)*.35
				if pos.distance_squared_to(round_edge)>pow(maxf(.6,width+tooth),2): continue
				var ink := pigment if material==null else material.get_pixel(x%period.x,y%period.y)
				image.set_pixel(x,y,ink)

static func build(map: TDTownMap, size: int, miniature: bool=false) -> Image:
	var survey := TDPlannedTown.definition()
	var height := int(survey.coast_height) if miniature else map.extent
	var image := Image.create_empty(map.extent*size,height*size,false,Image.FORMAT_RGBA8)
	var stone := _material(1)
	var water := _material(3)
	var grass := _material(0)
	var bounds := Rect2i(Vector2i.ZERO,image.get_size())
	_tile(image,bounds,grass)
	for forest: Array in survey.forests:
		_polygon(image,forest,size,func(row: Rect2i)->void:
			for x: int in range(row.position.x,row.end.x):
				var tint := image.get_pixel(x,row.position.y).darkened(.24)
				image.set_pixel(x,row.position.y,tint))
	for court: Dictionary in survey.courts:
		_polygon(image,court.outline,size,func(row: Rect2i)->void: _tile(image,row,stone))
	for path: Array in survey.roads:
		_stroke(image,path,size,TDPlannedTown.ROAD_HALF_WIDTH*size,stone)
	for outline: Array in survey.water:
		_shore(image,outline,size)
		_polygon(image,outline,size,func(row: Rect2i)->void: _tile(image,row,water))
	_shore(image,survey.headland,size)
	_polygon(image,survey.headland,size,func(row: Rect2i)->void: _tile(image,row,grass))
	if not miniature:
		var sea_y := mini(image.get_height(),29*size)
		var coast := _sea_cells(sea_y,size,image.get_size())
		_draw_sea(image,coast,size)
	for bounds_raw: Array in survey.quays:
		var box := Rect2i(int(bounds_raw[0])*size,int(bounds_raw[1])*size,int(bounds_raw[2])*size,int(bounds_raw[3])*size)
		_tile(image,box.intersection(bounds),stone)
	for raw: Array in survey.bridge_spans:
		var deck := Rect2i(raw[0],raw[1],raw[2],raw[3])
		if miniature:
			var landing_y := float(deck.position.y)+.70
			_stroke(image,[[deck.position.x,landing_y],[deck.end.x,landing_y]],size,.50*size,stone)
	if not miniature:
		District.paint_approved_market(image,map,size)
	return image

static func _shore(image: Image, outline: Array, size: int) -> void:
	var bankline: Array = outline.duplicate()
	bankline.append(outline[0])
	_stroke(image,bankline,size,size*.36,null,ROCK)
	_stroke(image,bankline,size,size*.23,null,SAND)
	_stroke(image,bankline,size,size*.08,null,SURF)

static func _sea_cells(start: int,size: int,extent: Vector2i) -> Dictionary:
	# The two water polygons are resolved once per map, including a broad open sea.
	var shelves := {}
	for y: int in range(start/size,extent.y/size):
		for x: int in range(extent.x/size):
			var at := Vector2i(x,y)
			if TDPlannedTown.terrain(at,false).surface_type=="sea":
				shelves[at] = true
	return shelves

static func _draw_sea(image: Image, sea: Dictionary, size: int) -> void:
	for at: Vector2i in sea:
		var reef := not sea.has(at+Vector2i.UP) or not sea.has(at+Vector2i.LEFT)
		# Use the original texture at the coastline. The outer open sea takes
		# a darker blue and long rows of sparse breaking waves.
		if reef: continue
		var seed := TDTownScenery.noise(at.x,at.y,38)
		var accent := Color("206f89").lightened(float(seed%5)*.012)
		var tile := Rect2i(at*size,Vector2i.ONE*size)
		var y := tile.position.y
		var x := tile.position.x
		# Preserve actual pixel water marks rather than replacing them with a solid color.
		for row: int in range(y,tile.end.y,2):
			for column: int in range(x,tile.end.x,2):
				var base := image.get_pixel(column,row)
				var color := base.lerp(accent,.32)
				image.fill_rect(Rect2i(column,row,2,2),color)
		if seed%3!=0: continue
		for i: int in range(3,size-2):
			var height := tile.position.y+size*.40+sin((tile.position.x+i)*.095)*2.0
			var p := Vector2i(tile.position.x+i,int(height))
			image.set_pixelv(p, image.get_pixelv(p).lerp(SURF,.56))
