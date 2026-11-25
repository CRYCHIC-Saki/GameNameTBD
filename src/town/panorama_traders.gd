extends RefCounted
## Hand-placed storefront and market pictures. Coordinates enclose only one
## cutout, so furniture, doors and depth sorting stay independent in the town.

const SHEET := "res://assets/town/jiangnan-traders-v1.png"
const REGIONS := {
	"pickle_shop": Rect2i(0,0,342,336),
	"fish_stall": Rect2i(346,0,194,158),
	"meat_stall": Rect2i(544,0,193,170),
	"produce_stall": Rect2i(741,0,195,160),
	"steam_cart": Rect2i(0,340,195,198),
	"snack_table": Rect2i(199,340,126,88),
	"forge": Rect2i(329,340,249,272),
	"dye_house": Rect2i(582,340,268,238),
	"tofu_house": Rect2i(0,616,242,219),
	"old_cart": Rect2i(246,616,199,177),
	"lantern_rope": Rect2i(449,616,213,184),
	"crock_cluster": Rect2i(666,616,112,86),
	"night_shops": Rect2i(0,839,500,151),
	"market_hall": Rect2i(504,839,465,141),
	"clay_crock": Rect2i(0,996,50,54),
	"red_crock": Rect2i(54,996,48,57),
	"patched_awning": Rect2i(106,996,166,134),
	"produce_baskets": Rect2i(276,996,107,92),
	"fuel_cart": Rect2i(387,996,114,82),
	"stone_mill": Rect2i(505,996,101,108),
}

static var _textures: Dictionary = {}

static func picture(id: String) -> Texture2D:
	if not _textures.has(id):
		var piece := AtlasTexture.new()
		piece.atlas = load(SHEET) as Texture2D
		piece.region = REGIONS[id]
		piece.filter_clip = true
		_textures[id] = piece
	return _textures[id]
