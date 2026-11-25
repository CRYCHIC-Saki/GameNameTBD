extends RefCounted
## Trimmed, foot-anchored pictures used by both the walking map and the atlas.
const ATLAS := "res://assets/town/jiangnan-landmarks-v1.png"
enum Piece { INN, STABLE, GATE, BANK, PAVILION, CARRIAGE, BANYAN, BENCH, STORYTELLER, PEONY, PIER, PEACH, LANDING, BAMBOO_RAIL, GARDEN_WALL, BAMBOO, SHORE_ROCKS, FOUNDATION, CHICKENS }
const SIZES := [
	Vector2i(274,240), Vector2i(158,113), Vector2i(214,204), Vector2i(263,195),
	Vector2i(153,190), Vector2i(138,82), Vector2i(296,281), Vector2i(149,84),
	Vector2i(59,77), Vector2i(87,61), Vector2i(170,136), Vector2i(158,154), Vector2i(170,232),
	Vector2i(132,60), Vector2i(183,98), Vector2i(192,162), Vector2i(141,113), Vector2i(92,35), Vector2i(67,32)]
static var _pictures := {}

static func picture(piece: Piece) -> Texture2D:
	if not _pictures.has(piece):
		var size: Vector2i = SIZES[piece]
		var tex := AtlasTexture.new()
		tex.atlas = load(ATLAS)
		tex.region = Rect2i(Vector2i(piece%4,piece/4)*320+Vector2i((320-size.x)/2,316-size.y),size)
		tex.filter_clip = true
		_pictures[piece] = tex
	return _pictures[piece]
