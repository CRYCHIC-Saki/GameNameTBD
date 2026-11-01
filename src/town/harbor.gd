class_name TDHarbor
extends RefCounted
## Public seacoast landmark; eastern reserved border, outside existing property.
## Passenger travel is independent from cargo procurement routes.
const ID := "harbor.hekou"
const ANCHOR := "harbor.hekou.arrival"
const ARRIVAL := Vector2i(69,34)
const GUIDE_STOP := Vector2i(67,34)
const TOWNS := ["chengdu","paris","tokyo","bangkok","mexico_city"]
const ART: Texture2D=preload("res://assets/town/harbor-v1.png")
static var _textures: Dictionary={}

static func facility(map: TDTownMap) -> Dictionary:
	if map.layout_version!=2: return {}
	return {"id":ID,"kind":"harbor","name":"河口港 · 海港客运","x":70,"y":32,"w":1,"h":1,"enabled":true}

static func departure_request(destination: String, home: String, unlocked: Array, arrivals: Dictionary, shop_open: bool=false) -> TDOutcome:
	if destination not in TOWNS or home not in TOWNS or destination==home: return TDOutcome.new(false,"INVALID_DESTINATION")
	if shop_open: return TDOutcome.new(false,"SHOP_OPEN","请先结束营业再出发。")
	if destination not in unlocked: return TDOutcome.new(false,"PASSENGER_ROUTE_LOCKED","等待新的航线消息。")
	if not arrivals.get(destination) is String or str(arrivals.get(destination,"")).is_empty():
		return TDOutcome.new(false,"DESTINATION_NOT_READY","目的地暂未通航。")
	return TDOutcome.new(true,"DEPARTURE_REQUEST","",{"schema_version":1,"origin_port_id":ID,"origin_town_id":home,"return_anchor_id":ANCHOR,"destination_town_id":destination,"arrival_anchor_id":str(arrivals[destination])})

static func texture(index: int) -> Texture2D:
	if not _textures.has(index):
		var atlas:=AtlasTexture.new();atlas.atlas=ART;atlas.filter_clip=true
		atlas.region=Rect2(245,5,400,870) if index==0 else Rect2(920,278,840,545)
		_textures[index]=atlas
	return _textures[index]

static func fit(art: Texture2D, box: Rect2) -> Rect2:
	var dimensions:=art.get_size()*minf(box.size.x/art.get_width(),box.size.y/art.get_height())
	return Rect2(box.position+Vector2((box.size.x-dimensions.x)*.5,box.size.y-dimensions.y),dimensions)

static func draw(canvas: CanvasItem,map: TDTownMap,origin: Vector2,cell: float) -> void:
	if facility(map).is_empty(): return
	# Wide open water continues beyond the playable map; it is never buildable.
	canvas.draw_rect(Rect2(origin+Vector2(71,0)*cell,Vector2(27,map.extent)*cell),Color("4d8995"))
	for y: int in range(0,map.extent*int(cell),28):
		for x: int in range(0,27*int(cell),97):
			var offset:=Vector2(x+(y%53),y)
			canvas.draw_line(origin+Vector2(71*cell,0)+offset,origin+Vector2(71*cell,0)+offset+Vector2(23+(y%17),0),Color("71a6ad"),2)
	# Stone seawall, with a gap at the walkable public pier.
	for y: int in map.extent:
		if y in [33,34,35]: continue
		var rim:=Rect2(origin+Vector2(70.85,y)*cell,Vector2(.25,1)*cell)
		canvas.draw_rect(rim,Color("9ca693"));canvas.draw_rect(rim.grow(-2),Color("bdbea5"),false,2)
	var dock:=Rect2(origin+Vector2(70,33)*cell,Vector2(3,3)*cell)
	canvas.draw_rect(dock,Color("82684c"))
	for row: int in range(0,int(dock.size.y),8): canvas.draw_line(dock.position+Vector2(0,row),dock.position+Vector2(dock.size.x,row),Color("b0946a"),2)
	for y: int in [33,35]:
		for x: int in range(70,74):
			canvas.draw_rect(Rect2(origin+Vector2(x,y+.05)*cell,Vector2(7,14)),Color("564c40"))
	var ship:=texture(0)
	canvas.draw_texture_rect(ship,fit(ship,Rect2(origin+Vector2(73,29)*cell,Vector2(3.1,6.7)*cell)),false)
	canvas.draw_texture_rect(ship,fit(ship,Rect2(origin+Vector2(80,20)*cell,Vector2(2.4,5.3)*cell)),false)
	var booth:=texture(1)
	canvas.draw_texture_rect(booth,fit(booth,Rect2(origin+Vector2(68.8,29.5)*cell,Vector2(2.5,3.5)*cell)),false)
	var sign:=Rect2(origin+Vector2(68,28.6)*cell,Vector2(5,0.7)*cell)
	canvas.draw_rect(sign,Color("253c36"))
	canvas.draw_string(ThemeDB.fallback_font,sign.position+Vector2(10,24),"河口港 · 海港客运",HORIZONTAL_ALIGNMENT_CENTER,sign.size.x-20,20,Color("f7dfad"))
