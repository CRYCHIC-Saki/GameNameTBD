class_name TDDinerArt
extends RefCounted
## Two diner identities, three clothing palettes; presentation never draws economic RNG.
const ATLAS: Texture2D=preload("res://assets/characters/diners/diners-four-directions-v1.png")
const SEATED: Texture2D=preload("res://assets/characters/diners/diners-seated-v1.png")
const ISO_SEATED: Texture2D=preload("res://assets/characters/diners/diners-isometric-seated-v2.png")
const OCCUPIED: Texture2D=preload("res://assets/characters/diners/diners-occupied-seat-v4.png")
const VARIANTS: int=6
const CLOTH_HUES: Array[float]=[0.48,0.08,0.96]
static var _sprites: Dictionary={}
static var _portraits: Dictionary={}
static var _source: Image
static var _seated_source: Image
static var _iso_source: Image
static var _occupied_source: Image

static func occupied_sprite(variant: int, character_id: String="") -> Texture2D:
	variant=posmod(variant,VARIANTS)
	var index: int=2 if character_id=="aling" else (3 if character_id=="chen" else variant%2)
	var key: String="occupied:%d:%d"%[index,0 if character_id!="" else variant/2]
	if _sprites.has(key): return _sprites[key]
	if _occupied_source==null:
		_occupied_source=OCCUPIED.get_image()
		if _occupied_source.is_compressed(): _occupied_source.decompress()
	# Explicit row split: the generated atlas is not an even square grid.
	var top: int=0 if index<2 else 600
	var width: int=_occupied_source.get_width()/2
	var height: int=600 if index<2 else _occupied_source.get_height()-600
	var pose:=_occupied_source.get_region(Rect2i(index%2*width,top,width,height))
	pose=pose.get_region(TDStoryArt._walk_bounds(pose))
	if character_id=="":
		for y: int in pose.get_height():
			for x: int in pose.get_width(): pose.set_pixel(x,y,cloth_color(pose.get_pixel(x,y),variant/2))
	_sprites[key]=ImageTexture.create_from_image(pose)
	return _sprites[key]

static func occupied_base(variant: int, character_id: String="") -> Vector2:
	# Bottom of the nearest wooden leg in the complete, alpha-trimmed assembly.
	if character_id=="aling": return Vector2(.428,1)
	if character_id=="chen": return Vector2(.425,1)
	return Vector2(.426 if variant%2==0 else .412,1)

static func dining_sprite(variant: int, character_id: String="") -> Texture2D:
	variant=posmod(variant,VARIANTS)
	var cell_index: int=2 if character_id=="aling" else (3 if character_id=="chen" else variant%2)
	var key: String="iso:%d:%d"%[cell_index,0 if character_id!="" else variant/2]
	if _sprites.has(key): return _sprites[key]
	if _iso_source==null:
		_iso_source=ISO_SEATED.get_image()
		if _iso_source.is_compressed(): _iso_source.decompress()
	var cell:=Vector2i(_iso_source.get_width()/2,_iso_source.get_height()/2)
	var pose:=_iso_source.get_region(Rect2i(Vector2i(cell_index%2,cell_index/2)*cell,cell))
	pose=pose.get_region(TDStoryArt._walk_bounds(pose))
	if character_id=="":
		for y: int in pose.get_height():
			for x: int in pose.get_width(): pose.set_pixel(x,y,cloth_color(pose.get_pixel(x,y),variant/2))
	var texture:=ImageTexture.create_from_image(pose)
	_sprites[key]=texture
	return texture

static func hip_ratio(variant: int, character_id: String="") -> Vector2:
	# V2 keeps the established chibi proportions and one consistent body direction.
	if character_id=="aling": return Vector2(.44,.86)
	if character_id=="chen": return Vector2(.39,.85)
	return Vector2(.43,.84) if variant%2==0 else Vector2(.43,.86)

static func appearance(identity: String) -> int:
	return posmod(identity.hash(),VARIANTS)

static func sprite(variant: int, facing: Vector2i=Vector2i.DOWN, frame: int=-1, seated: bool=false) -> Texture2D:
	variant=posmod(variant,VARIANTS)
	var step: int=1 if frame==0 else (2 if frame==2 else 0)
	var column:=TDChefArt.direction_index(facing)
	var key: String="%d:%d:%d:%s"%[variant,column,step,seated]
	if _sprites.has(key): return _sprites[key]
	if _source==null:
		_source=ATLAS.get_image()
		if _source.is_compressed(): _source.decompress()
	if seated and _seated_source==null:
		_seated_source=SEATED.get_image()
		if _seated_source.is_compressed(): _seated_source.decompress()
	var source:=_seated_source if seated else _source
	var cell:=Vector2i(source.get_width()/4,source.get_height()/(2 if seated else 6))
	var row: int=variant%2 if seated else (variant%2)*3+step
	var pose:=source.get_region(Rect2i(Vector2i(column,row)*cell,cell))
	# Ignore alpha noise in transparent generated gutters. Original atlas is read-only.
	var bounds:=TDStoryArt._walk_bounds(pose)
	pose=pose.get_region(bounds)
	for y: int in pose.get_height():
		for x: int in pose.get_width():
			var pixel:=pose.get_pixel(x,y)
			pose.set_pixel(x,y,cloth_color(pixel,variant/2))
	var texture:=ImageTexture.create_from_image(pose)
	_sprites[key]=texture
	return texture

static func cloth_color(pixel: Color, palette: int) -> Color:
	if pixel.a<.05: return Color.TRANSPARENT
	# Only the deliberately teal garment pixels change; hair, skin and shoes keep their color.
	if palette>0 and pixel.h>.40 and pixel.h<.57 and pixel.s>.20:
		return Color.from_hsv(CLOTH_HUES[clampi(palette,0,2)],pixel.s*.85,pixel.v,pixel.a)
	return pixel

static func portrait(variant: int) -> Texture2D:
	variant=posmod(variant,VARIANTS)
	if not _portraits.has(variant):
		var source:=sprite(variant)
		var view:=AtlasTexture.new();view.atlas=source
		view.region=Rect2(0,0,source.get_width(),source.get_height()*.66)
		view.filter_clip=true;_portraits[variant]=view
	return _portraits[variant]
