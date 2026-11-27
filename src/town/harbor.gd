class_name TDHarbor
extends RefCounted
## Jiangnan's public seacoast landing. Terrain, doors and arrival use the authored plan.
## Passenger travel is independent from cargo procurement routes.
const ID := "harbor.hekou"
const ANCHOR := "harbor.hekou.arrival"
const TOWNS := ["chengdu","paris","tokyo"]
const JiangnanFrontage := preload("res://src/town/jiangnan_frontage.gd")
const ART_PATH := "res://assets/town/harbor-estuary-v1.png"
const SPRITES: Array[Rect2i] = [
	Rect2i(735,251,542,417),
	Rect2i(49,303,605,366),
	Rect2i(1476,259,146,306),
	Rect2i(1446,568,199,108)
]
static var _textures: Dictionary={}
static var _geometry: Dictionary = {}
static var _quay_art: ImageTexture
static var ARRIVAL: Vector2i:
	get: return cell("arrival")
static var GUIDE_STOP: Vector2i:
	get: return cell("guide")

static func _layout() -> Dictionary:
	if _geometry.is_empty():
		_geometry = TDPlannedTown.definition().harbor
	return _geometry

static func cell(key: String) -> Vector2i:
	var point: Array = _layout()[key]
	return Vector2i(int(point[0]), int(point[1]))

static func lot(key: String) -> Rect2i:
	var rect: Array = _layout()[key]
	return Rect2i(int(rect[0]), int(rect[1]), int(rect[2]), int(rect[3]))

static func facility(map: TDTownMap) -> Dictionary:
	if map.layout_version != 2 or not map.region_id.is_empty(): return {}
	var booth := lot("booth")
	return {"id":ID, "kind":"harbor", "name":"臻味港客运站",
		"x":booth.position.x, "y":booth.position.y, "w":booth.size.x, "h":booth.size.y,
		"approach_x":ARRIVAL.x, "approach_y":ARRIVAL.y, "enabled":true}

static func is_near_departure(map: TDTownMap, feet: Vector2) -> bool:
	if facility(map).is_empty(): return false
	return TDInteractionRange.distance(feet, Rect2(lot("booth"))) <= .65 \
		or feet.distance_to(Vector2(ARRIVAL) + Vector2.ONE * .5) <= .8

static func departure_request(destination: String, home: String, unlocked: Array, arrivals: Dictionary, shop_open: bool=false) -> TDOutcome:
	if destination not in TOWNS or home not in TOWNS or destination==home: return TDOutcome.new(false,"INVALID_DESTINATION")
	if shop_open: return TDOutcome.new(false,"SHOP_OPEN","请先结束营业再出发。")
	if destination not in unlocked: return TDOutcome.new(false,"PASSENGER_ROUTE_LOCKED","等待新的航线消息。")
	if not arrivals.get(destination) is String or str(arrivals.get(destination,"")).is_empty():
		return TDOutcome.new(false,"DESTINATION_NOT_READY","目的地暂未通航。")
	return TDOutcome.new(true,"DEPARTURE_REQUEST","",{"schema_version":1,"origin_port_id":ID,"origin_town_id":home,"return_anchor_id":ANCHOR,"destination_town_id":destination,"arrival_anchor_id":str(arrivals[destination])})

static func texture(index: int) -> Texture2D:
	if not _textures.has(index):
		var atlas := AtlasTexture.new()
		atlas.atlas = load(ART_PATH) as Texture2D
		atlas.region = Rect2(SPRITES[index])
		atlas.filter_clip = true
		_textures[index] = atlas
	return _textures[index]

static func fit(art: Texture2D, box: Rect2) -> Rect2:
	var dimensions:=art.get_size()*minf(box.size.x/art.get_width(),box.size.y/art.get_height())
	return Rect2(box.position+Vector2((box.size.x-dimensions.x)*.5,box.size.y-dimensions.y),dimensions)

static func booth_rect(origin: Vector2, tile: float) -> Rect2:
	var booth := Rect2(lot("booth"))
	var feet := Vector2(booth.get_center().x, booth.end.y - .08)
	return TDEnvironmentArt.facade_rect(texture(1), origin + feet * tile, 7.6 * tile, 4.5 * tile)

static func _platform() -> ImageTexture:
	if _quay_art != null: return _quay_art
	# Irregular slate joints are baked once, outside the per-frame draw.
	var size := lot("quay").size * 24
	var image := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	var stone := Color("a4a396")
	image.fill(Color("716e64"))
	for row: int in ceili(size.y / 9.0):
		for column: int in range(-1, ceili(size.x / 19.0)):
			var x := maxi(0, column * 19 + row % 2 * 9)
			var y := row * 9
			var right := mini(size.x, (column + 1) * 19 + row % 2 * 9 - 1)
			if right <= x: continue
			var slab := Rect2i(x, y, right - x, mini(8, size.y - y))
			var color := stone.lightened(float(posmod(column * 13 + row * 7, 9)) * .018)
			image.fill_rect(slab, color)
			image.fill_rect(Rect2i(slab.position, Vector2i(slab.size.x, 1)), color.lightened(.11))
	# The timber landing occupies the open lower half, with a continuous masonry perimeter.
	var land := Rect2i(Vector2i(12, size.y / 2), Vector2i(size.x - 24, size.y / 2 - 9))
	image.fill_rect(land.grow(2), Color("726b58"))
	image.fill_rect(land, Color("b99265"))
	for x: int in range(land.position.x, land.end.x, 6):
		var base := Color("a57a52").lightened(float(posmod(x * 13, 11)) * .013)
		image.fill_rect(Rect2i(x, land.position.y, mini(5, land.end.x - x), land.size.y), base)
		image.fill_rect(Rect2i(x, land.position.y, 1, land.size.y), base.lightened(.16))
	_quay_art = ImageTexture.create_from_image(image)
	return _quay_art

static func draw(canvas: CanvasItem, map: TDTownMap, origin: Vector2, tile: float) -> void:
	if facility(map).is_empty(): return
	var quay := Rect2(lot("quay"))
	var platform := Rect2(origin + quay.position * tile, quay.size * tile)
	canvas.draw_texture_rect(_platform(), platform, false)
	_draw_retaining_wall(canvas, platform, tile)
	var deck := Rect2(lot("deck"))
	var dock := Rect2(origin + deck.position * tile, deck.size * tile)
	canvas.draw_rect(dock, Color("856446"))
	for x: int in range(0, int(dock.size.x), 11):
		canvas.draw_line(dock.position + Vector2(x, 0), dock.position + Vector2(x, dock.size.y), Color("c49869"), 3)
	canvas.draw_rect(Rect2(dock.position, Vector2(dock.size.x, 7)), Color("63452f"))
	canvas.draw_rect(Rect2(dock.position + Vector2(0,dock.size.y - 5), Vector2(dock.size.x, 10)), Color("63452f"))
	for fraction: float in [.2,.78]:
		var middle := dock.position + Vector2(dock.size.x * fraction, 0)
		for step: int in 5:
			var tread := Rect2(middle + Vector2(-.62 * tile, 7.0 * step - 10), Vector2(1.24 * tile, 7))
			canvas.draw_rect(tread, Color("977850").lightened(.04 * step))
			canvas.draw_rect(Rect2(tread.position, Vector2(tread.size.x, 2)), Color("cab088"))
	for fraction: float in [.015,.12,.3,.46,.64,.85,.985]:
		var foot := dock.position + Vector2(dock.size.x*fraction, dock.size.y)
		_draw_post(canvas, foot, tile)
	var berth := JiangnanFrontage.picture(JiangnanFrontage.Piece.BOAT)
	var mooring := origin + Vector2(quay.position.x + 4.0, quay.end.y + .6) * tile
	canvas.draw_texture_rect(berth, fit(berth,Rect2(mooring, Vector2(3.5,1.9)*tile)), false)
	var ship := texture(0)
	var waterline := origin + (quay.end + Vector2(-7.4, .6)) * tile
	canvas.draw_texture_rect(ship,fit(ship,Rect2(waterline,Vector2(7.8,5.7)*tile)),false)

static func _draw_retaining_wall(canvas: CanvasItem, platform: Rect2, tile: float) -> void:
	# The masonry profile bevels out into the deeper part of the harbor.
	var a := Vector2(platform.position.x, platform.end.y)
	var b := platform.end
	var cut := tile * .44
	var depth := tile * .53
	canvas.draw_colored_polygon(PackedVector2Array([a,b,b + Vector2(0,depth * .34),
		b + Vector2(-cut,depth),a + Vector2(cut,depth),a + Vector2(0,depth * .34)]), Color("655e53"))
	for course: int in 3:
		var inset := cut * float(course) / 3.0 + 2
		var row_y := depth * float(course) / 3.0
		for x: int in range(0, int(platform.size.x - 2 * inset), 44):
			var span := minf(42, platform.size.x - 2 * inset - x)
			var facing := Rect2(a + Vector2(inset + x, row_y + 1), Vector2(span, depth / 3.0 - 2))
			var tint := Color("948b7a").darkened(float(course) * .12)
			canvas.draw_rect(facing, tint)
			canvas.draw_rect(Rect2(facing.position, Vector2(facing.size.x, 3)), tint.lightened(.16))

static func _draw_post(canvas: CanvasItem, foot: Vector2, tile: float) -> void:
	var cap := foot + Vector2(-4, -tile * .30)
	canvas.draw_rect(Rect2(cap, Vector2(12,tile*.43)), Color("523a28"))
	canvas.draw_rect(Rect2(cap + Vector2(2,0), Vector2(8,tile*.40)), Color("976b47"))
	canvas.draw_rect(Rect2(cap, Vector2(12,5)), Color("e0b37b"))
	canvas.draw_rect(Rect2(cap + Vector2(-1,12), Vector2(14,4)), Color("d4b47b"))

static func decorations(origin: Vector2, tile: float) -> Array[Dictionary]:
	var quay := Rect2(lot("quay"))
	var beacon := texture(2)
	var footing := origin + Vector2(quay.end.x - .8, quay.end.y - .65) * tile
	var beacon_rect := TDEnvironmentArt.facade_rect(beacon, footing, 1.1 * tile, 2.55 * tile)
	var hampers := texture(3)
	var cargo_feet := origin + Vector2(quay.position.x + 2.1, quay.position.y + 1.8) * tile
	var cargo_rect := TDEnvironmentArt.facade_rect(hampers, cargo_feet, 1.7 * tile, tile)
	return [
		{"art":beacon, "rect":beacon_rect, "bases":TDEnvironmentArt.facade_bases(beacon_rect,.20)},
		{"art":hampers, "rect":cargo_rect, "bases":TDEnvironmentArt.facade_bases(cargo_rect,.42)}
	]
