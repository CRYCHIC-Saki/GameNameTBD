class_name TDRegionalInterior
extends RefCounted
## Read-only visual themes. Economic cuisine IDs and saved player layouts keep their meaning.
const STYLES := {"cn":"chinese", "eu":"french", "jp":"japanese"}
const DECOR_STYLES: Array[String] = ["chinese","french","japanese"]
const STYLE_NAMES := {"chinese":"中式","french":"欧陆","japanese":"日式"}
const FLOOR_NAMES := {"chinese":"中式石砖","french":"欧陆棋盘砖","japanese":"日式木地板"}
const WALL_NAMES := {"chinese":"中式木格墙","french":"欧陆护墙板","japanese":"日式木格纸墙"}
const ALIASES := {"continental":"french"}
const ROWS := {"french":0, "japanese":1}
const BACKGROUNDS := "res://assets/interiors/regional-kitchens-v1.png"
const DINING := "res://assets/interiors/regional-dining-v1.png"
const PROPS := "res://assets/interiors/regional-props-v1.png"
const FLOOR_TILES := "res://assets/interiors/floor-finishes-v1.png"
const WALL_TILES := "res://assets/interiors/wall-finishes-v1.png"
const FLOOR_INDEX := {"floor_chinese":0,"floor_french":1,"floor_japanese":2,"wood":5,"tile":6,"stone":7,"carpet":8}
const WALL_INDEX := {"wall_chinese":0,"wall_french":1,"wall_japanese":2,"paper":5,"stripe":6,"floral":7,"brick":8}
const WALLS := {"chinese":"efdfbb", "french":"e9e1ca", "japanese":"eee3c9"}
const WOODS := {"chinese":"785035", "french":"667354", "japanese":"b58b59"}
static var _textures: Dictionary = {}
static var _sprites: Dictionary = {}

static func style(value: String) -> String:
	return str(STYLES.get(value, ALIASES.get(value, value)))

static func piece_style(item: Dictionary) -> String:
	return str(item.get("style_id", "chinese_low")).get_slice("_", 0)

static func regional(value: String) -> bool:
	return ROWS.has(style(value))

static func finish_style(id: String) -> String:
	if not id.begins_with("floor_") and not id.begins_with("wall_"): return ""
	var value := id.get_slice("_",1)
	return value if id in ["floor_"+value,"wall_"+value] and value in DECOR_STYLES else ""

static func surface_style(id: String, fallback: String) -> String:
	var value := finish_style(id)
	return value if not value.is_empty() else fallback

static func finish_name(id: String) -> String:
	var value := finish_style(id)
	if value.is_empty(): return id
	return str((FLOOR_NAMES if id.begins_with("floor_") else WALL_NAMES)[value])

# Sample inside each swatch's gutter so adjacent materials never bleed under zoom.
static var _finish_uvs: Dictionary = {}

static func _uv(index: int, section: Vector2i, repeat_span: int) -> PackedVector2Array:
	var key := Vector3i(index, section.x + section.y * repeat_span, repeat_span)
	if not _finish_uvs.has(key):
		var edge := 1.0 / 288.0
		var span := 1.0 / 3.0 - 2.0 * edge
		var start := Vector2(index % 3, index / 3) / 3.0 + Vector2.ONE * edge + Vector2(section) * span / repeat_span
		var step := span / repeat_span
		_finish_uvs[key] = PackedVector2Array([start, start+Vector2(step,0), start+Vector2(step,step), start+Vector2(0,step)])
	return _finish_uvs[key]

static func draw_floor(canvas: CanvasItem, id: String, pts: PackedVector2Array, cell: Vector2i) -> void:
	var index: int = FLOOR_INDEX.get(id, -1)
	if index < 0: return
	var repeat_span := 2
	var tint := Color.WHITE
	match id:
		"floor_french":
			tint = Color("929891") if (cell.x + cell.y) % 2 == 0 else Color.WHITE
	var section := Vector2i(posmod(cell.x,repeat_span),posmod(cell.y,repeat_span))
	canvas.draw_polygon(pts,PackedColorArray([tint]),_uv(index,section,repeat_span),source(FLOOR_TILES))

static func draw_wall(canvas: CanvasItem, id: String, start: Vector2, finish: Vector2, up: Vector2, index: int, lit: bool) -> void:
	var tile: int = WALL_INDEX.get(id,-1)
	if tile < 0: return
	var points := PackedVector2Array([start+up,finish+up,finish,start])
	var tint := Color.WHITE if lit else Color("c4b6a7")
	canvas.draw_polygon(points,PackedColorArray([tint]),_uv(tile,Vector2i.ZERO,1),source(WALL_TILES))
	var wood := Color(WOODS.get(finish_style(id),"806249")) * tint
	canvas.draw_line(start,finish,wood.darkened(.22),3)
	canvas.draw_line(start+up,finish+up,wood,3)
	if id == "wall_chinese" and index % 3 == 0:
		canvas.draw_line(start,start+up,wood,3)
		canvas.draw_line(start+up*.69,finish+up*.69,wood.lightened(.15),2)

static func draw_finish_sample(canvas: CanvasItem, id: String, bounds: Rect2) -> void:
	if WALL_INDEX.has(id):
		draw_wall(canvas,id,Vector2(bounds.position.x,bounds.end.y),bounds.end,Vector2(0,-bounds.size.y),0,true)
	elif FLOOR_INDEX.has(id):
		var size := bounds.size / Vector2(3,2)
		for y: int in 2:
			for x: int in 3:
				var at := bounds.position + Vector2(x,y)*size
				var pts := PackedVector2Array([at,at+Vector2(size.x,0),at+size,at+Vector2(0,size.y)])
				draw_floor(canvas,id,pts,Vector2i(x,y))

static func source(path: String) -> Texture2D:
	if not _textures.has(path): _textures[path] = load(path) as Texture2D
	return _textures[path]

static func sprite(value: String, column: int, kitchen: bool = false) -> AtlasTexture:
	var theme := style(value)
	if not ROWS.has(theme): return null
	var key := "%s:%d:%s" % [theme, column, kitchen]
	if _sprites.has(key): return _sprites[key]
	var texture := source(PROPS if kitchen else DINING)
	var row: int = ROWS[theme]
	# Authored gutters are not an exact uniform grid: keep neighbouring cabinets
	# out of the stool region (otherwise a thin cabinet leg appears beside it).
	var xs := PackedInt32Array([0,314,627,941,1254] if kitchen else [0,380,680,1086])
	var ys := PackedInt32Array([0,326,640,955,1254] if kitchen else [0,380,732,1094,1448])
	var bounds := Rect2i(xs[column],ys[row],xs[column+1]-xs[column],ys[row+1]-ys[row])
	var pixels := texture.get_image()
	if pixels.is_compressed(): pixels.decompress()
	# Trim only the selected sprite; original atlases remain unmodified.
	var used := TDStoryArt._walk_bounds(pixels.get_region(bounds))
	var tile := AtlasTexture.new()
	tile.atlas = texture; tile.region = Rect2(bounds.position + used.position, used.size); tile.filter_clip = true
	_sprites[key] = tile
	return tile

static func kitchen_regions(cuisine: String) -> Array[Rect2]:
	if not regional(cuisine): return []
	var row: int = ROWS[style(cuisine)]
	var size := source(BACKGROUNDS).get_size() / 2.0
	var origin := Vector2(row % 2, row / 2) * size
	# Map the authored countertop edge to the unchanged y=280 collider.
	# Stretch wall/cabinet and floor separately, retaining the existing doorway.
	var split := 220.0 if row < 2 else 224.0
	return [Rect2(origin, Vector2(size.x, split)), Rect2(origin + Vector2(0, split), Vector2(size.x, size.y - split))]

static func draw_kitchen(canvas: CanvasItem, cuisine: String) -> void:
	var regions := kitchen_regions(cuisine)
	if regions.is_empty(): return
	var texture := source(BACKGROUNDS)
	canvas.draw_texture_rect_region(texture, Rect2(0, 0, 1280, 280), regions[0])
	canvas.draw_texture_rect_region(texture, Rect2(0, 280, 1280, 520), regions[1])

static func draw_prop(canvas: CanvasItem, cuisine: String, kind: String, feet: Vector2) -> bool:
	var column: int = {"fridge":0, "board":1, "serve":2, "trash":3}.get(kind, -1)
	if column < 0 or not regional(cuisine): return false
	var texture := sprite(cuisine, column, true)
	var height: float = 236.0 if kind == "fridge" else (92.0 if kind == "trash" else 145.0)
	var size := texture.get_size() * height / texture.get_height()
	canvas.draw_texture_rect(texture, Rect2(feet - Vector2(size.x * .5, size.y), size), false)
	return true

static func floor_color(culture: String, cell: Vector2i) -> Color:
	var odd := (cell.x + cell.y) % 2 != 0
	match style(culture):
		"french": return Color("d9cfb4" if odd else "747569")
		"japanese": return Color("c9af7d" if cell.y % 2 == 0 else "c3a572")
	return Color("bd9b72" if not odd else "c6a57d")
