extends RefCounted
## Art anchored to the river and buildings of the Jiangnan home map.
const FRONTAGE := "res://assets/town/jiangnan-frontage-v1.png"
const EAVES := "res://assets/town/jiangnan-eaves-v1.png"
const RIVERBANK := "res://assets/town/jiangnan-riverbank-v1.png"
enum Piece { COTTAGE, GALLERY, BOAT, STEPS, LANTERN, CLOTH_SIGN, INDIGO_LAUNDRY, LINEN_LAUNDRY,
	WASHER, STONE_EDGE, SEDGE_EDGE, REEDS, EAST_STONE, EAST_SEDGE }
const FEATURES := ["", "", "wupeng_boat", "wash_steps", "eave_lantern", "cloth_sign", "laundry", "laundry",
	"washer", "stone_bank", "sedge_bank", "reeds_bank", "stone_bank", "sedge_bank"]
## The first two frames retain the doorstep and collision dimensions of the previous houses.
const REGIONS := [
	Rect2i(10,61,300,255), Rect2i(342,74,275,242), Rect2i(9,496,302,140), Rect2i(329,498,302,138),
	Rect2i(61,16,198,300), Rect2i(361,16,237,300), Rect2i(9,433,302,203), Rect2i(329,450,302,186),
	Rect2i(26,16,267,300), Rect2i(404,16,151,300), Rect2i(85,336,149,300), Rect2i(339,336,282,300),
	Rect2i(84,656,151,300), Rect2i(405,656,149,300),
]
static var _pieces: Dictionary = {}

static func picture(piece: int) -> AtlasTexture:
	if not _pieces.has(piece):
		var texture := AtlasTexture.new()
		var path := FRONTAGE if piece < Piece.LANTERN else EAVES
		if piece >= Piece.WASHER: path = RIVERBANK
		texture.atlas = load(path) as Texture2D
		texture.filter_clip = true
		texture.region = REGIONS[piece]
		_pieces[piece] = texture
	return _pieces[piece]

## One hook per street frontage, inside the painted wall. Its sort position is
## the house's footing so the wall can carry a sign without gaining a collider.
static func hanging(piece: int, facade: Rect2, anchor: Vector2, width: float) -> Dictionary:
	var art := picture(piece)
	var size := Vector2(width, width / art.get_size().aspect())
	var hook := facade.position + facade.size * anchor
	var item := {"art":art, "rect":Rect2(hook-Vector2(size.x*.5,0),size), "bases":[],
		"sort_y":facade.end.y+.25, "jiangnan_feature":FEATURES[piece]}
	if piece == Piece.LANTERN: item.light_uv = Vector2(.64,.54)
	return item

static func shop_hanging(plot: Dictionary, facade: Rect2) -> Dictionary:
	if plot.get("construction",false): return {}
	var piece: int
	var hook: Vector2
	match str(plot.get("kind","")):
		"hotel", "competitor":
			piece = Piece.LANTERN
			hook = Vector2(.17,.42)
		"market", "commercial_street", "snack_street":
			piece = Piece.CLOTH_SIGN
			hook = Vector2(.14,.39)
		"rich_district":
			return hanging(Piece.LINEN_LAUNDRY,facade,Vector2(.37,.46),facade.size.x*.28)
		_: return {}
	var width := 24.0 if piece == Piece.LANTERN else 28.0
	return hanging(piece,facade,hook,minf(width,facade.size.x*.18))

## West-bank steps enter the actual water, alongside a boat at two of the
## landings. Skip a placement if later geography makes it a bridge or a parcel.
static func river_life(map: TDTownMap, cell: float, origin: Vector2) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if map.layout_version != 2 or not map.region_id.is_empty(): return result
	for row: int in [11,20,38,59]:
		var bank := Vector2i(52,row)
		if not map.terrain_at(bank).walkable or not map.plot_at(bank.x,bank.y).is_empty(): continue
		for piece: int in [Piece.STEPS,Piece.BOAT]:
			if piece == Piece.BOAT and row not in [20,38]: continue
			var art := picture(piece)
			var width := 1.16 if piece == Piece.STEPS else 1.72
			var size := Vector2(width,width/art.get_size().aspect())
			var anchor := Vector2(53.0,row+.47)
			if piece == Piece.BOAT: anchor += Vector2(.83,.79)
			var rect := Rect2(anchor-Vector2(0,size.y*.5),size)
			var clear := true
			for y: int in range(floori(rect.position.y),ceili(rect.end.y)):
				for x: int in range(floori(rect.position.x),ceili(rect.end.x)):
					if map.terrain_at(Vector2i(x,y)).surface_type != "water" or not map.plot_at(x,y).is_empty():
						clear = false
			if clear:
				var entry := {"art":art,"rect":Rect2(origin+rect.position*cell,rect.size*cell),
					"bases":[],"jiangnan_feature":FEATURES[piece]}
				result.append(entry)
				if piece == Piece.STEPS:
					# Reserve the path to the landing and the air above a standing visitor.
					entry.walk_in = Rect2(origin+Vector2(50.8,row-.66)*cell,Vector2(3.4,1.82)*cell)
					if row == 20:
						_bank_prop(result,Piece.WASHER,Vector2(53.23,row+.41),.68,cell,origin)
						result.back().sort_y = entry.rect.end.y+.20
					_dress_landing(result,map,row,cell,origin)
	return result

static func _bank_prop(result: Array[Dictionary],piece: int,feet: Vector2,height: float,cell: float,origin: Vector2) -> void:
	var art := picture(piece)
	var size := Vector2(height*art.get_size().aspect(),height)*cell
	result.append({"art":art,"rect":Rect2(origin+feet*cell-Vector2(size.x*.5,size.y),size),
		"bases":[],"jiangnan_feature":FEATURES[piece]})

static func _dress_landing(result: Array[Dictionary],map: TDTownMap,row: int,cell: float,origin: Vector2) -> void:
	# Broken stretches of stone and sedge follow each real bank. Step back
	# before a bridge, a road or a developed lot, including future leases.
	for west: bool in [true,false]:
		var land := 52 if west else 56
		var water := 53 if west else 55
		var boundary := 53.0 if west else 56.0
		var inward := -1.0 if west else 1.0
		for bed: Array in [[-1.65,1.53,false],[-.17,1.46,true],[1.89,1.00,false],[3.28,1.32,true]]:
			var y := row+float(bed[0])
			if not west: y += .38 if bed[0]<0 else -.16
			var height := float(bed[1])
			var clear := true
			for grid_y: int in range(floori(y-height),ceili(y)):
				if map.terrain_at(Vector2i(water,grid_y)).surface_type != "water" or not map.terrain_at(Vector2i(land,grid_y)).walkable:
					clear = false
				if map.is_road(land,grid_y) or not map.plot_at(land,grid_y).is_empty(): clear = false
			if not clear: continue
			var piece := Piece.STONE_EDGE if west else Piece.EAST_STONE
			if not bed[2]: piece = Piece.SEDGE_EDGE if west else Piece.EAST_SEDGE
			_bank_prop(result,piece,Vector2(boundary+inward*.035,y),height,cell,origin)
		# A small tuft helps tie the steps to the turf at their southern end.
		if west:
			_bank_prop(result,Piece.REEDS,Vector2(boundary-.02,row+.98),.53,cell,origin)
