class_name TDTravelCatalog
extends RefCounted
## Presentation metadata only: stable economic IDs, no new ownership or wallet.
const IDS := ["chengdu", "tokyo", "paris"]
const ATLAS: Texture2D = preload("res://assets/town/four-cultures-v2.png")
const PROPS: Texture2D = preload("res://assets/town/four-cultures-props-v2.png")
const CIVIC := "res://assets/town/civic-buildings-v1.png"
const NEIGHBORHOODS := "res://assets/town/neighborhoods-v1.png"
const JiangnanFrontage := preload("res://src/town/jiangnan_frontage.gd")
const Landmarks := preload("res://src/town/jiangnan_landmarks.gd")
const Traders := preload("res://src/town/panorama_traders.gd")
const STREET := "res://assets/town/street-life-v1.png"
# Length of the seat board in the source sticker, excluding lamps and greenery.
const BENCH_SEAT_PIXELS := {"chengdu":137,"tokyo":152,"paris":148}

static func bench_width(town: String, art: Texture2D) -> float:
	return TDTownWorld.HERO_HEIGHT*1.17*art.get_width()/BENCH_SEAT_PIXELS[town]
const FLORA := "res://assets/town/regional-flora-v1.png"
const GREENBELT := "res://assets/town/greenbelt-flora-v1.png"
const GREENBELT_SIZES := [Vector2i(294,303),Vector2i(306,289),Vector2i(120,303),Vector2i(306,280),Vector2i(306,224),Vector2i(306,223)]
const RESTAURANTS: Dictionary = {
	"chengdu": preload("res://assets/town/restaurant-chinese-v1.png"),
	"tokyo": preload("res://assets/town/restaurant-japanese-v1.png"),
	"paris": preload("res://assets/town/restaurant-european-v1.png"),
}
const BRANCH_EXTERIORS := {
	"chengdu": preload("res://assets/town/player-branches/harbor.png"),
	"tokyo": preload("res://assets/town/player-branches/island.png"),
	"paris": preload("res://assets/town/player-branches/riverside.png"),
}
const BRANCH_CONSTRUCTION := preload("res://assets/town/player-branches/construction.png")
const REGIONS := {
 "chengdu":{"name":"臻味港", "row":0,"grass":"748655","road":"b3aa90","water":"4d8995","leaf":"47734d","caption":"石板街、青瓦巷和东岸海港。食堂与小屋都在这里。"},
 "tokyo":{"name":"和味道", "row":0,"grass":"84977a","road":"9b9da0","water":"537f9d","leaf":"d58fab","caption":"沿着湾岸码头和樱花参道漫步，路边是木造町屋和挂着暖帘的食铺。"},
 "paris":{"name":"稀味郡", "row":1,"grass":"80936e","road":"c2b7a1","water":"6b9195","leaf":"64825a","caption":"从彩石喷泉广场和露天市集出发，经过麦田风车，就能走到稀味客港。"},
}
static var _sprites: Dictionary={}
static var _atlas_image: Image
## The importer packs every sprite bottom-centred in a 320px cell, four pixels above its edge.
const CIVIC_SIZES: Array[Vector2i] = [
	Vector2i(300,278), Vector2i(300,291), Vector2i(309,270),
	Vector2i(303,281), Vector2i(305,291), Vector2i(303,253),
	Vector2i(303,289), Vector2i(303,296), Vector2i(312,269),
	Vector2i(309,295), Vector2i(298,281), Vector2i(312,248),
	Vector2i(306,289), Vector2i(294,295), Vector2i(310,279),
]
const NEIGHBORHOOD_SIZES: Array[Vector2i] = [
	Vector2i(300,255), Vector2i(275,242), Vector2i(302,260),
	Vector2i(290,247), Vector2i(281,235), Vector2i(267,223),
	Vector2i(281,275), Vector2i(291,262), Vector2i(264,248),
	Vector2i(299,256), Vector2i(283,218), Vector2i(265,143),
	Vector2i(302,245), Vector2i(285,242), Vector2i(291,190),
]
const FLORA_SIZES: Array[Vector2i] = [
	Vector2i(294,278), Vector2i(285,285), Vector2i(292,204),
	Vector2i(288,267), Vector2i(298,263), Vector2i(288,173),
	Vector2i(198,298), Vector2i(283,260), Vector2i(251,163),
	Vector2i(268,271), Vector2i(310,261), Vector2i(284,207),
	Vector2i(310,275), Vector2i(269,235), Vector2i(310,176),
]

const STREET_SIZES: Array[Vector2i] = [
	Vector2i(312,259), Vector2i(252,236), Vector2i(303,221),
	Vector2i(312,244), Vector2i(236,232), Vector2i(304,170),
	Vector2i(312,275), Vector2i(245,240), Vector2i(308,122),
	Vector2i(312,260), Vector2i(250,234), Vector2i(312,195),
	Vector2i(312,278), Vector2i(256,238), Vector2i(310,152),
]

static func info(id: String) -> Dictionary:
	return REGIONS.get(id,{}).duplicate(true)

static func sprite(town: String, column: int) -> Texture2D:
	if clampi(column,0,3)==0 and RESTAURANTS.has(town):
		return _restaurant(town)
	return _street_sprite(town, column)

static func _street_sprite(town: String, column: int) -> Texture2D:
	var index: int=int(REGIONS[town].row)*4+clampi(column,0,3)
	if not _sprites.has(index):
		var result:=AtlasTexture.new();result.atlas=ATLAS;result.filter_clip=true
		var cell := Vector2i(ATLAS.get_width() / 4, ATLAS.get_height() / 4)
		var origin := Vector2i(index % 4, index / 4) * cell
		if _atlas_image == null:
			_atlas_image = ATLAS.get_image()
			if _atlas_image.is_compressed(): _atlas_image.decompress()
		var used := _atlas_image.get_region(Rect2i(origin, cell)).get_used_rect()
		result.region = Rect2(origin + used.position, used.size)
		_sprites[index]=result
	return _sprites[index]

static func _district_sprite(town: String, sheet: String, column: int) -> AtlasTexture:
	var row := IDS.find(town)
	var key := "%s:%s:%d" % [sheet, town, column]
	if not _sprites.has(key):
		var sizes: Array[Vector2i] = NEIGHBORHOOD_SIZES
		if sheet == CIVIC: sizes = CIVIC_SIZES
		elif sheet == FLORA: sizes = FLORA_SIZES
		elif sheet == STREET: sizes = STREET_SIZES
		var size: Vector2i = sizes[row*3+column]
		var origin := Vector2i(column, row)*320 + Vector2i((320-size.x)/2,316-size.y)
		var tile := AtlasTexture.new()
		tile.atlas = load(sheet) as Texture2D
		tile.filter_clip = true
		tile.region = Rect2(origin, size)
		_sprites[key] = tile
	return _sprites[key]

static func native_frontage_feet(lot: Rect2) -> Vector2:
	return Vector2(lot.get_center().x, lot.end.y - .12)

## Both the walkable world and the atlas use the parcel's purpose to select its facade.
static func facade(town: String, plot: Dictionary, variation: int = 0, branch_skin: bool = true) -> Texture2D:
	var kind := str(plot.get("kind", ""))
	if branch_skin and plot.has("branch_id") and not plot.get("preset_storefront", false):
		if plot.get("construction", false): return BRANCH_CONSTRUCTION
		return BRANCH_EXTERIORS.get(town, BRANCH_EXTERIORS.chengdu)
	if plot.get("construction", false): return TDTownArt.sprite(12)
	if plot.get("preset_storefront", false): return TDJiangnanReferenceArt.diner_facade().art
	if kind == "player_diner" and (plot.get("id", "") == "player_diner" or plot.has("branch_id")):
		return TDEnvironmentArt.diner() if town == "chengdu" else _restaurant(town)
	if town == "chengdu":
		match str(plot.get("id","")):
			"hotel": return Landmarks.picture(Landmarks.Piece.INN)
			"commercial_street:bank": return Landmarks.picture(Landmarks.Piece.BANK)
			"landmark": return Landmarks.picture(Landmarks.Piece.PAVILION)
			"plaza": return Landmarks.picture(Landmarks.Piece.BANYAN)
			"market-small": return Traders.picture("pickle_shop")
			"market-mid": return Traders.picture("market_hall")
			"snack_street": return Traders.picture("night_shops")
	match kind:
		"competitor", "commercial_street", "snack_street":
			if absi(str(plot.get("id","")).hash()) % 2 == 0: return street_detail(town,0)
		"hotel": return _district_sprite(town, CIVIC, 0)
		"bank": return _district_sprite(town, CIVIC, 1)
		"market": return _district_sprite(town, CIVIC, 2)
		"housing", "urban_village", "rich_district", "player_cottage":
			var house := (variation + int(kind == "rich_district")) % 2
			if town == "chengdu": return JiangnanFrontage.picture(house)
			return _district_sprite(town, NEIGHBORHOODS, house)
		"plaza": return _district_sprite(town, NEIGHBORHOODS, 2)
		"harbor": return TDHarbor.texture(1) if town == "chengdu" else _street_sprite(town, 3)
		"landmark": return TDTownArt.sprite(7) if town == "chengdu" else _street_sprite(town, 2)
		"supply_factory", "factory_lot":
			return TDEnvironmentArt.factory(str(plot.get("supply",""))) if town == "chengdu" else _street_sprite(town, 1)
	if town != "chengdu": return _street_sprite(town, 0)
	var index: int = {"zoo":6, "amusement":10, "snack_street":13, "station":9}.get(kind,4)
	return TDTownArt.sprite(index)

static func street_detail(town: String, column: int) -> Texture2D:
	return _district_sprite(town,STREET,column)

static func plant(town: String, column: int) -> Texture2D:
	if column < 3: return _district_sprite(town, FLORA, column)
	var index := 5 if column==4 else IDS.find(town)
	var key := "greenbelt:%d"%index
	if not _sprites.has(key):
		var tex := AtlasTexture.new()
		tex.atlas = load(GREENBELT) as Texture2D
		tex.filter_clip = true
		var size: Vector2i = GREENBELT_SIZES[index]
		var offset := Vector2i(index%3,index/3)*320+Vector2i((320-size.x)/2,316-size.y)
		tex.region = Rect2(offset,size)
		_sprites[key] = tex
	return _sprites[key]

## Columns 0–2 are the region's canopy, secondary tree and ground cover;
## 3 is its distinctive flowering or columnar specimen; 4 is Japanese azalea.
static func plant_species(town: String, habitat: String, sample: int) -> int:
	match town:
		"chengdu": return 0 if habitat=="bank" else (3 if habitat=="avenue" or sample%3==0 else 1)
		"tokyo": return 3 if habitat!="grove" or sample%4==0 else (0 if sample%3!=0 else 1)
		"paris": return 0 if habitat=="bank" else (3 if habitat=="avenue" else 1)


	return 0

static func _restaurant(town: String) -> AtlasTexture:
	var key: String="restaurant:"+town
	if not _sprites.has(key):
		var source: Texture2D=RESTAURANTS[town]
		var image: Image=source.get_image()
		if image.is_compressed(): image.decompress()
		var used: Rect2i=image.get_used_rect()
		var result:=AtlasTexture.new();result.atlas=source;result.filter_clip=true
		result.region=Rect2(used)
		_sprites[key]=result
	return _sprites[key]

static func map_for(profile: TDGameProfile, id: String) -> TDTownMap:
	if id not in IDS: return null
	# Copy presentation state; never mutate the branch cache or home world.
	var source: TDTownMap=profile.branches.town_map(id)
	if source==null: return null
	var copy:=TDTownMap.new();copy.extent=source.extent;copy.layout_version=source.layout_version;copy.region_id=source.region_id
	copy.jiangnan_layout_revision=source.jiangnan_layout_revision
	copy.shiomi=source.shiomi
	copy.egret=source.egret
	copy.egret_version=source.egret_version
	copy._reserved_frontages=source._reserved_frontages.duplicate()
	copy.roads=source.roads.duplicate(true);copy.plots=source.plots.duplicate(true);copy.cottage=source.cottage.duplicate(true)
	copy.plots=copy.plots.filter(func(p:Dictionary)->bool:return not p.has("branch_id"))
	if id!=str(profile.commerce.state.home):
		copy.apply_commercial_occupancy(profile.commerce.expansion.presentation(id,profile.commerce.state.competitors[id],int(profile.commerce.state.day)))
	copy.plots.append_array(profile.branches.plots(id))
	return copy

static func prop(town: String, decoration: bool) -> Texture2D:
	var key: String="prop:%s:%s"%[town,decoration]
	if not _sprites.has(key):
		var source:=PROPS.get_image()
		if source.is_compressed(): source.decompress()
		var cell:=Vector2i(PROPS.get_width()/4,PROPS.get_height()/2)
		var region:=Rect2i(Vector2i(int(REGIONS[town].row)*cell.x,cell.y if decoration else 0),cell)
		var used:=source.get_region(region).get_used_rect()
		var texture:=AtlasTexture.new();texture.atlas=PROPS;texture.filter_clip=true
		texture.region=Rect2(region.position+used.position,used.size);_sprites[key]=texture
	return _sprites[key]

const SIGHT_KINDS := ["landmark","plaza","amusement","zoo","public_walk"]
const SIGHT_DESCRIPTIONS := {
	"chengdu": {
		"landmark": "临水的亭子底下常有人歇脚。潮水涨上来时，在这里能看见货船隔着石桥缓缓转弯。",
		"plaza": "临着客港的石砖广场，是等船和碰头的地方。海风一吹，卖热饼的摊子先飘来香气。",
		"amusement": "木戏台朝着一片开阔地。起锣前，来早的街坊会从家里搬来小凳，把最前一排占满。",
		"zoo": "园路从叠石和花草间绕过，沿着矮墙走一圈，能听见河水拍着石沿。",
	},
	"tokyo": {
		"landmark": "穿过樱树间的鸟居，就能看见屋檐下挂着的天妇罗木牌。每逢祭日，街坊会带来新炸的天妇罗，祈求灶火平顺、四季丰收。",
		"plaza": "浅色砂地围着椭圆形能舞台。演出前，观众顺着砂纹两侧入座，把舞台正面留给演员。",
		"office": "面向港湾的办公楼记录进出客船。渔民也会来这里问潮位，再决定几点把船解缆。",
		"watch": "值班人从望塔上能看见岛外水道。夜里，塔灯给开往和味道的船指路。",
		"onsen": "温泉沿山石露天而设，水汽沿木栏往上飘。从这里能听见瀑布落进下方的潭水。",
	},
	"paris": {
		"landmark": "钟楼高过沿岸的尖顶。河面起雾时，赶集的人靠钟声辨时，船夫也听得见。",
		"plaza": "石雕喷泉是街坊常用的碰头处。水落进石槽的声音穿过广场，周围小馆也爱把桌子摆到这里。",
		"mill": "河岸风车把谷物磨成面粉。风稳的日子，风轮转得轻快，磨坊门口堆着刚装好的面粉袋。",
	},
}

static func sight_description(plot: Dictionary, town: String) -> String:
	var descriptions: Dictionary = SIGHT_DESCRIPTIONS.get(town,{})
	return str(descriptions.get(plot.get("id",""),descriptions.get(plot.get("kind",""),"沿街的石阶和树荫把这里连到主路。早晚经过时，常能遇见出来散步的街坊。")))

static func label(plot: Dictionary, town: String) -> String:
	if plot.has("branch_id"): return str(plot.name)+(" · 施工中" if plot.get("construction",false) else "")
	if plot.has("local_name"): return str(plot.local_name)
	if plot.get("kind") == "hotel" or plot.get("kind") == "landmark": return str(plot.name)
	if town=="chengdu": return str(plot.get("name","街区"))
	var jp: bool=town=="tokyo"
	match str(plot.get("kind","")):
		"market": return "鱼市与食材街" if jp else "露天农贸市集"
		"housing","urban_village","rich_district": return "町屋住宅街" if jp else "河岸住宅街"
		"plaza","amusement": return "樱花参道" if jp else "钟楼广场"
		"bank": return "街区银行"
		"factory_lot","supply_factory": return "食材作坊"
		"competitor","commercial_street","snack_street": return "暖帘食街" if jp else "咖啡与小馆"
		_: return "街坊公共区"

static func port(id: String) -> Vector2i:
	if id=="paris": return TDEgretLayout.port()
	return TDHarbor.ARRIVAL if id=="chengdu" else TDRegionalLayout.port(id)

static func harbor_rect(id: String="chengdu") -> Rect2:
	if id == "chengdu": return Rect2(TDHarbor.lot("quay")).merge(Rect2(TDHarbor.lot("booth")))
	return Rect2(Vector2(port(id))+Vector2(-1.5,-2.5),Vector2(3,3))
