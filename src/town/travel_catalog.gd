class_name TDTravelCatalog
extends RefCounted
## Presentation metadata only: stable economic IDs, no new ownership or wallet.
const IDS := ["chengdu", "tokyo", "paris", "bangkok", "mexico_city"]
const PORT := Vector2i(69,33)
const ATLAS: Texture2D = preload("res://assets/town/four-cultures-v1.png")
const PROPS: Texture2D = preload("res://assets/town/four-cultures-props-v1.png")
const REGIONS := {
 "chengdu":{"name":"河口镇 · 中式", "row":0,"grass":"748655","road":"b3aa90","water":"4d8995","leaf":"47734d","caption":"石板街、青瓦巷和东岸海港。食堂与小屋都在这里。"},
 "tokyo":{"name":"潮见町 · 日本", "row":0,"grass":"84977a","road":"9b9da0","water":"537f9d","leaf":"d58fab","caption":"以东京湾沿岸为灵感：湾岸码头、木造町屋、暖帘食铺与樱花参道。"},
 "paris":{"name":"白鹭河镇 · 欧洲", "row":1,"grass":"80936e","road":"c2b7a1","water":"6b9195","leaf":"64825a","caption":"以巴黎河岸为灵感：石灰岩街屋、石桥、咖啡露台与市集广场。河港经航道连接外海。"},
 "bangkok":{"name":"莲湾镇 · 东南亚", "row":2,"grass":"65835b","road":"b79e7a","water":"5c8e86","leaf":"3d7652","caption":"以曼谷水巷为灵感：湿润河网、木桩高脚屋、长尾船市集与寺院庭园。"},
 "mexico_city":{"name":"日轮镇 · 墨西哥", "row":3,"grass":"b0a37c","road":"cfb68b","water":"648e9d","leaf":"748650","caption":"以墨西哥高原城镇为灵感：赭土山坡、彩色灰泥宅院、钟楼与市集。港站包含通往海港的接驳。"}
}
static var _sprites: Dictionary={}

static func info(id: String) -> Dictionary:
	return REGIONS.get(id,{}).duplicate(true)

static func sprite(town: String, column: int) -> Texture2D:
	var index: int=int(REGIONS[town].row)*4+clampi(column,0,3)
	if not _sprites.has(index):
		var result:=AtlasTexture.new();result.atlas=ATLAS;result.filter_clip=true
		result.region=Rect2((index%4)*ATLAS.get_width()/4,(index/4)*ATLAS.get_height()/4,ATLAS.get_width()/4,ATLAS.get_height()/4)
		_sprites[index]=result
	return _sprites[index]

static func map_for(profile: TDGameProfile, id: String) -> TDTownMap:
	if id not in IDS: return null
	# Copy presentation state; never mutate the branch cache or home world.
	var source: TDTownMap=profile.branches.town_map(id)
	if source==null: return null
	var copy:=TDTownMap.new();copy.extent=source.extent;copy.layout_version=source.layout_version;copy.region_id=source.region_id
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
		var region:=Rect2i(int(REGIONS[town].row)*384,512 if decoration else 0,384,512)
		var used:=source.get_region(region).get_used_rect()
		var texture:=AtlasTexture.new();texture.atlas=PROPS;texture.filter_clip=true
		texture.region=Rect2(region.position+used.position,used.size);_sprites[key]=texture
	return _sprites[key]

static func label(plot: Dictionary, town: String) -> String:
	if plot.has("branch_id"): return str(plot.name)
	if town=="chengdu": return str(plot.get("name","街区"))
	var jp: bool=town=="tokyo";var eu: bool=town=="paris";var sea: bool=town=="bangkok"
	match str(plot.get("kind","")):
		"market": return "鱼市与食材街" if jp else ("露天农贸市集" if eu else ("水上市集" if sea else "中央市集"))
		"housing","urban_village","rich_district": return "町屋住宅街" if jp else ("河岸住宅街" if eu else ("水巷人家" if sea else "彩色宅院"))
		"plaza","amusement": return "樱花参道" if jp else ("钟楼广场" if eu else ("寺院庭园" if sea else "钟楼文化广场"))
		"bank": return "街区银行"
		"factory_lot","supply_factory": return "食材作坊"
		"competitor","commercial_street","snack_street": return "暖帘食街" if jp else ("咖啡与小馆" if eu else ("河畔食铺" if sea else "玉米香食街"))
		_: return "街坊公共区"

static func port(id: String) -> Vector2i:
	return PORT if id=="chengdu" else TDRegionalLayout.port(id)

static func harbor_rect(id: String="chengdu") -> Rect2:
	return Rect2(Vector2(port(id))+Vector2(-1.5,-2.5),Vector2(3,3))
