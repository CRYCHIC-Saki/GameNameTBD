extends RefCounted
## Jiangnan street dressing: map coordinates are in the existing 73-cell plan.
const Terrain := preload("res://src/town/jiangnan_district_terrain.gd")
const Places := preload("res://src/town/street_places.gd")
const Frontage := preload("res://src/town/jiangnan_frontage.gd")
const Traders := preload("res://src/town/panorama_traders.gd")
const Landmarks := preload("res://src/town/jiangnan_landmarks.gd")
const Produce := preload("res://assets/town/jiangnan-produce-cc0.png")
const COAST_SHEET := "res://assets/town/jiangnan-waterfront-v1.png"
const COAST_REGIONS := {
	"festival_market": Rect2i(30,200,451,174),
	"festival_stage": Rect2i(563,115,414,316),
	"tea_deck": Rect2i(1098,117,399,311),
	"landing_kiosk": Rect2i(76,614,357,323),
	"goods_cart": Rect2i(607,619,340,328),
}
const WOOD := Color("563c30")
const LIT_WOOD := Color("b38152")
const BLACK := Color("392e27")
const HIGHLIGHT := Color("dcc290")
static var _handmade: Dictionary = {}

static func enabled(map: TDTownMap) -> bool:
	return map.layout_version == 2 and map.region_id.is_empty()

static func fixtures(map: TDTownMap, cell: float, origin: Vector2, entries: Array[Dictionary]) -> void:
	if not enabled(map): return
	var sites := Terrain.sites(map)
	var solid: Array[Rect2] = []
	for entry: Dictionary in entries:
		solid.append_array(entry.bases)
		if entry.has("walk_in"): solid.append(entry.walk_in)
	var inn := map._by_id("hotel")
	var court := Vector2(inn.x,inn.y)
	_put(map,cell,origin,entries,solid,sites,"entry_gate",Landmarks.picture(Landmarks.Piece.GATE),court+Vector2(.70,11.2),5.2,0.0,true)
	_put(map,cell,origin,entries,solid,sites,"stable",Landmarks.picture(Landmarks.Piece.STABLE),court+Vector2(9.3,5.8),4.05,.18,true)
	_put(map,cell,origin,entries,solid,sites,"inn_crates",_sprite("crate"),court+Vector2(10.42,6.25),.78,0.0,true)
	_put(map,cell,origin,entries,solid,sites,"stable_rail",Landmarks.picture(Landmarks.Piece.BAMBOO_RAIL),court+Vector2(8.82,6.42),1.65,.10,true)
	var square := map._by_id("plaza")
	var plaza := Vector2(square.x,square.y)
	_put(map,cell,origin,entries,solid,sites,"story_table",Landmarks.picture(Landmarks.Piece.STORYTELLER),plaza+Vector2(9.3,7.1),1.35,.12,true)
	_put(map,cell,origin,entries,solid,sites,"goods_cart",_coast_piece("goods_cart"),plaza+Vector2(.75,6.25),1.35,.12,true)
	_pickle_lane(map,cell,origin,entries,solid,sites)
	var bank := map._by_id("commercial_street:bank")
	if not bank.is_empty():
		var base := Vector2(bank.x,bank.y)
		# The lions, enclosing wall and black gate share the bank facade's perspective.
		_pick_spot(map,cell,origin,entries,solid,sites,"bank_carriage",Landmarks.picture(Landmarks.Piece.CARRIAGE),[base+Vector2(4.82,3.5),base+Vector2(4.9,3.82)],1.65,.15)
		_put(map,cell,origin,entries,solid,sites,"bank_crocks",Traders.picture("clay_crock"),base+Vector2(2.80,3.27),.32)
		_pick_spot(map,cell,origin,entries,solid,sites,"courtyard_wall",Landmarks.picture(Landmarks.Piece.GARDEN_WALL),[base+Vector2(-.50,2.42),base+Vector2(.49,1.48),base+Vector2(1.16,.54)],2.07,.09)
		_pick_spot(map,cell,origin,entries,solid,sites,"bank_bamboo",Landmarks.picture(Landmarks.Piece.BAMBOO),[base+Vector2(2.58,.64),base+Vector2(2.73,1.38)],1.68,.10)
	var diner := map._by_id("player_diner")
	if not diner.is_empty():
		var lower := Vector2(diner.x,diner.y+diner.h)
		for dx: float in [.32,float(diner.w)-.32]:
			_pick_spot(map,cell,origin,entries,solid,sites,"peony",Landmarks.picture(Landmarks.Piece.PEONY),[lower+Vector2(dx,-.12),lower+Vector2(dx,-.48)],.88,.09)
	_wet_market(map,cell,origin,entries,solid,sites)
	_snack_lane(map,cell,origin,entries,solid,sites)
	_river_pavilion(map,cell,origin,entries,solid,sites)
	_workshops(map,cell,origin,entries,solid,sites)
	_waterfront(map,cell,origin,entries,solid,sites)

static func _river_pavilion(map: TDTownMap, cell: float, origin: Vector2, entries: Array[Dictionary],
		solid: Array[Rect2], sites: Array[Dictionary]) -> void:
	var hall := map._by_id("landmark")
	if hall.is_empty(): return
	var bank := Vector2(hall.x,hall.y)
	_pick_spot(map,cell,origin,entries,solid,sites,"willow",TDTravelCatalog.plant("chengdu",0),[bank+Vector2(-.8,.82),bank+Vector2(3.1,4.82)],2.90,.12,true)
	_pick_spot(map,cell,origin,entries,solid,sites,"peach",Landmarks.picture(Landmarks.Piece.PEACH),[bank+Vector2(-1.9,2.6),bank+Vector2(-.9,1.4)],2.55,.10,true)
	# The painted boards (rows 64..184) span the walkable water cell;
	# the remaining width extends onto the dry shore and the piles into water.
	var landing := Rect2(TDPlannedTown.pavilion_landing())
	var tackle := Landmarks.picture(Landmarks.Piece.LANDING)
	if landing.has_area():
		var ratio := cell*landing.size.y/120.0
		var deck := Rect2(origin+landing.position*cell-Vector2(4,64)*ratio,tackle.get_size()*ratio)
		entries.append({"art":tackle,"rect":deck,"bases":[],"sort_y":origin.y+landing.position.y*cell-1,"district_fixture":"pavilion_deck"})
	_float_piece(map,cell,origin,entries,"lotus",_sprite("lotus"),bank+Vector2(4.4,.0),1.05)

static func _pickle_lane(map: TDTownMap, cell: float, origin: Vector2, entries: Array[Dictionary],
		solid: Array[Rect2], sites: Array[Dictionary]) -> void:
	var plot := map._by_id("market-small")
	if plot.is_empty(): return
	var base := Vector2(plot.x,plot.y)
	# Small rows are tucked beside the shop. Chen's door and public grass
	# approach stay clear across the whole five-cell story frontage.
	for row: int in range(3):
		for col: int in range(7):
			var foot := base+Vector2(-1.69+col*.204+(row%2)*.062,1.33+row*.29+((row+3*col)%4)*.014)
			_put(map,cell,origin,entries,solid,sites,"pickling_crocks",Traders.picture("red_crock" if (row+col)%4==0 else "clay_crock"),foot,.25)
	for row: int in range(2):
		for col: int in range(6):
			var foot := base+Vector2(2.36+col*.23,1.41+row*.29)
			_put(map,cell,origin,entries,solid,sites,"pickling_crocks",Traders.picture("red_crock" if (row+col)%3==0 else "clay_crock"),foot,.26)
	_put(map,cell,origin,entries,solid,sites,"chen_annex",Frontage.picture(Frontage.Piece.GALLERY),base+Vector2(3.17,.55),1.78,.14)
	_put(map,cell,origin,entries,solid,sites,"chen_awning",Traders.picture("patched_awning"),base+Vector2(3.00,1.43),1.75)
	_put(map,cell,origin,entries,solid,sites,"crock_cluster",Traders.picture("crock_cluster"),base+Vector2(-1.03,1.11),.74)
	_put(map,cell,origin,entries,solid,sites,"chen_well",Places._square_piece(4),base+Vector2(7.45,4.53),.57)

static func _wet_market(map: TDTownMap, cell: float, origin: Vector2, entries: Array[Dictionary],
		solid: Array[Rect2], sites: Array[Dictionary]) -> void:
	var plot := map._by_id("market-mid")
	if plot.is_empty(): return
	var base := Vector2(plot.x,plot.y)
	# Separate counters leave an aisle that reaches the wet market's entrance.
	_trader(map,cell,origin,entries,solid,sites,base,"fish_stall",[Vector2(1.95,4.40),Vector2(2.25,3.57)],2.95,.18,true)
	_trader(map,cell,origin,entries,solid,sites,base,"meat_stall",[Vector2(3.55,2.73),Vector2(2.85,2.60)],2.60,.18,true)
	_trader(map,cell,origin,entries,solid,sites,base,"produce_stall",[Vector2(7.95,4.20),Vector2(7.75,3.55)],2.95,.16,true)
	_pick_spot(map,cell,origin,entries,solid,sites,"market_cc0_produce",_sprite("produce"),[base+Vector2(6.57,2.62),base+Vector2(8.57,5.14)],1.12,.12,true)

static func _snack_lane(map: TDTownMap, cell: float, origin: Vector2, entries: Array[Dictionary],
		solid: Array[Rect2], sites: Array[Dictionary]) -> void:
	var plot := map._by_id("snack_street")
	if plot.is_empty(): return
	var base := Vector2(plot.x,plot.y)
	_trader(map,cell,origin,entries,solid,sites,base,"old_cart",[Vector2(.93,4.9),Vector2(1.25,5.12)],1.48,.16,true)
	_trader(map,cell,origin,entries,solid,sites,base,"steam_cart",[Vector2(3.10,4.64),Vector2(2.85,4.70)],1.62,.17,true)
	_trader(map,cell,origin,entries,solid,sites,base,"snack_table",[Vector2(4.62,4.88),Vector2(4.30,4.97)],1.13,.16,true)
	_trader(map,cell,origin,entries,solid,sites,base,"snack_table",[Vector2(7.80,4.88),Vector2(7.46,4.96)],1.13,.16,true)

static func _workshops(map: TDTownMap, cell: float, origin: Vector2, entries: Array[Dictionary],
		solid: Array[Rect2], sites: Array[Dictionary]) -> void:
	var plot := map._by_id("competitor")
	if plot.is_empty(): return
	var base := Vector2(plot.x,plot.y)
	# Atlas and town use the same front door for the named dye shop.
	var dye := Places.venue("chengdu",plot,cell,origin)
	if not dye.is_empty():
		dye.district_fixture="dye_house"
		entries.append(dye)
		solid.append_array(dye.bases)
	_trader(map,cell,origin,entries,solid,sites,base,"forge",[Vector2(3.75,4.28),Vector2(3.62,4.45)],4.38,.16,true)
	_trader(map,cell,origin,entries,solid,sites,base,"tofu_house",[Vector2(15.15,4.22),Vector2(16.02,4.32)],3.62,.15,true)
	_put(map,cell,origin,entries,solid,sites,"millstones",Traders.picture("stone_mill"),base+Vector2(16.25,4.78),.85,0.0,true)
	_put(map,cell,origin,entries,solid,sites,"indigo_rack",_sprite("dye"),base+Vector2(8.48,4.35),1.35,.12,true)

static func _waterfront(map: TDTownMap, cell: float, origin: Vector2, entries: Array[Dictionary],
		solid: Array[Rect2], sites: Array[Dictionary]) -> void:
	var plaza := map._by_id("waterfront_market")
	if plaza.is_empty(): return
	var start := Vector2(plaza.x,plaza.y)
	_put(map,cell,origin,entries,solid,sites,"festival_market",_coast_piece("festival_market"),start+Vector2(6.7,3.25),7.5,.17,true)
	_put(map,cell,origin,entries,solid,sites,"festival_stage",_coast_piece("festival_stage"),start+Vector2(15.15,3.28),5.4,.17,true)
	_put(map,cell,origin,entries,solid,sites,"riverside_kiosk",_coast_piece("landing_kiosk"),start+Vector2(22.2,3.1),3.5,.18,true)
	_put(map,cell,origin,entries,solid,sites,"east_teahouse",_coast_piece("tea_deck"),Vector2(48.8,22.0),4.55,.18,true)
	_put(map,cell,origin,entries,solid,sites,"east_small_landing",_coast_piece("landing_kiosk"),Vector2(44.9,24.9),3.60,.18,true)
	_float_piece(map,cell,origin,entries,"waterfront_boat",Frontage.picture(Frontage.Piece.BOAT),start+Vector2(8.35,7.85),3.25)
	_float_piece(map,cell,origin,entries,"waterfront_boat",Frontage.picture(Frontage.Piece.BOAT),start+Vector2(24.3,7.05),3.35)
	_float_piece(map,cell,origin,entries,"east_small_ferry",Frontage.picture(Frontage.Piece.BOAT),Vector2(46.0,28.60),3.2)

static func _coast_piece(id: String) -> Texture2D:
	if not _handmade.has(id):
		var texture := AtlasTexture.new()
		texture.atlas = load(COAST_SHEET)
		texture.region = COAST_REGIONS[id]
		texture.filter_clip = true
		_handmade[id] = texture
	return _handmade[id]

static func _trader(map: TDTownMap, cell: float, origin: Vector2, entries: Array[Dictionary], solid: Array[Rect2],
		sites: Array[Dictionary], base: Vector2, id: String, offsets: Array, width: float, depth: float, road_ok := false) -> void:
	var spots: Array[Vector2] = []
	for offset: Vector2 in offsets: spots.append(base+offset)
	_pick_spot(map,cell,origin,entries,solid,sites,id,Traders.picture(id),spots,width,depth,road_ok)

static func _pick_spot(map: TDTownMap, cell: float, origin: Vector2, entries: Array[Dictionary], solid: Array[Rect2],
		sites: Array[Dictionary], id: String, tex: Texture2D, candidates: Array[Vector2], width: float, depth: float, road_ok := false) -> void:
	for point: Vector2 in candidates:
		var count := entries.size()
		_put(map,cell,origin,entries,solid,sites,id,tex,point,width,depth,road_ok)
		if entries.size()>count: return

static func _put(map: TDTownMap, cell: float, origin: Vector2, entries: Array[Dictionary], solid: Array[Rect2],
		sites: Array[Dictionary], id: String, tex: Texture2D, at: Vector2, wide: float, depth: float = 0.0, road_ok := false) -> void:
	var width := wide*cell
	var feet := origin+at*cell
	var rect := TDEnvironmentArt.facade_rect(tex,feet,width,width/tex.get_size().aspect())
	var bases: Array[Rect2] = []
	if depth>.015: bases = TDEnvironmentArt.facade_bases(rect,depth)
	if id=="entry_gate":
		for x: float in [.09,.79]:
			bases.append(Rect2(rect.position+rect.size*Vector2(x,.91),rect.size*Vector2(.13,.08)))
	var sample := Rect2(feet-Vector2(width*.36,cell*.1),Vector2(width*.72,cell*.1))
	if not bases.is_empty(): sample = bases[0]
	for p: Vector2 in [sample.position+Vector2.ONE,sample.end-Vector2.ONE,sample.get_center()]:
		var grid := Vector2i(((p-origin)/cell).floor())
		if not map.terrain_at(grid).walkable or (map.is_road(grid.x,grid.y) and not road_ok): return
		var lot := map.plot_at(grid.x,grid.y)
		if lot.get("construction",false) or lot.has("branch_id"): return
	if solid.any(func(b: Rect2)->bool: return b.grow(2).intersects(sample)): return
	for site: Dictionary in sites:
		var block: Rect2i = site.rect
		if Rect2(origin+Vector2(block.position)*cell,Vector2(block.size)*cell).intersects(sample): return
	var entry := {"art":tex,"rect":rect,"bases":bases,"district_fixture":id}
	if id in ["willow","peach","shade_tree","stable","entry_gate","bank_carriage","story_table","stone_bench","courtyard_wall","inn_screen","inn_bamboo","bank_bamboo"]:
		entry.jiangnan_feature = "courtyard_shadow"
	elif id=="steam_cart":
		entry.jiangnan_feature = "tea"
		entry.steamer_uv = Vector2(.30,.60)
		entry.kettle_uv = Vector2(.68,.60)
	elif id=="festival_stage":
		entry.jiangnan_feature = "lantern_rope"
	elif id=="lantern_rope" or id=="forge":
		entry.jiangnan_feature = id
	elif id=="old_cart":
		entry.jiangnan_feature = "tea"
		entry.steamer_uv = Vector2(.49,.51)
		entry.kettle_uv = Vector2(.53,.51)
	elif id=="night_lamp":
		entry.jiangnan_feature = "street_lamp"
		entry.light_uv = Vector2(.74,.34)
	entries.append(entry)
	solid.append_array(bases)

static func _float_piece(map: TDTownMap, cell: float, origin: Vector2, entries: Array[Dictionary],
		id: String, tex: Texture2D, at: Vector2, width: float) -> void:
	var size := Vector2(width,width/tex.get_size().aspect())
	var rect := Rect2(at-Vector2(size.x*.5,size.y),size)
	for point: Vector2 in [rect.position+.02*Vector2.ONE,rect.end-.02*Vector2.ONE,rect.get_center()]:
		var terrain := map.terrain_at(Vector2i(point.floor()))
		if terrain.terrain_type != "water" or terrain.walkable: return
	entries.append({"art":tex,"rect":Rect2(origin+rect.position*cell,rect.size*cell),"bases":[],"district_fixture":id})

static func _fill(im: Image, x: int, y: int, w: int, h: int, color: Color) -> void:
	im.fill_rect(Rect2i(x,y,w,h),color)

static func _oval(im: Image, center: Vector2i, size: Vector2i, color: Color) -> void:
	for y: int in range(center.y-size.y,center.y+size.y+1):
		for x: int in range(center.x-size.x,center.x+size.x+1):
			if not Rect2i(Vector2i.ZERO,im.get_size()).has_point(Vector2i(x,y)): continue
			var t := Vector2(Vector2i(x,y)-center)/Vector2(size)
			if t.length_squared() <= 1.0: im.set_pixel(x,y,color)

static func _produce_baskets() -> Image:
	var im := Traders.picture("produce_baskets").get_image()
	var src := Produce.get_image()
	for spec: Array in [[Rect2i(1,0,28,29),Vector2i(37,21)],[Rect2i(65,0,26,31),Vector2i(14,47)],[Rect2i(96,32,31,31),Vector2i(68,55)]]:
		var piece := src.get_region(spec[0])
		piece.resize(14,13,Image.INTERPOLATE_NEAREST)
		im.blend_rect(piece,Rect2i(Vector2i.ZERO,piece.get_size()),spec[1])
	return im

static func _sprite(id: String) -> Texture2D:
	if _handmade.has(id): return _handmade[id]
	var im := Image.create_empty(80,65,false,Image.FORMAT_RGBA8)
	match id:
		"produce":
			im = _produce_baskets()
		"crate":
			_fill(im,10,23,54,30,BLACK)
			_fill(im,13,23,48,27,WOOD)
			for y: int in [24,32,41]:
				_fill(im,15,y,44,5,LIT_WOOD)
				_fill(im,17,y+1,40,1,HIGHLIGHT.darkened(.22))
			_fill(im,13,22,5,29,LIT_WOOD.darkened(.30))
			_fill(im,57,22,5,29,LIT_WOOD.darkened(.30))
		"dye":
			for x: int in [7,69]: _fill(im,x,9,3,55,LIT_WOOD)
			_fill(im,5,12,71,2,WOOD)
			for x: int in [14,32,51]:
				_fill(im,x,14,14,35,Color("465d74"))
				for y: int in range(18,49,5):
					_fill(im,x+3,y,8,1,Color("c1b29a"))
					_fill(im,x+6,y-1,2,3,Color("e6dbbe"))
		"lotus":
			for p: Vector2i in [Vector2i(18,28),Vector2i(39,36),Vector2i(61,25)]:
				_oval(im,p,Vector2i(14,7),Color("576339"))
				_oval(im,p-Vector2i(1,1),Vector2i(12,5),Color("8e963f"))
			_oval(im,Vector2i(39,29),Vector2i(4,4),Color("d8a69d"))
	var used := im.get_used_rect()
	if used.has_area(): im = im.get_region(used)
	var tex := ImageTexture.create_from_image(im)
	_handmade[id] = tex
	return tex

static func draw_street_marks(canvas: Node2D, entries: Array[Dictionary], origin: Vector2, cell: float, minute: float) -> void:
	var visible := canvas.get_global_transform_with_canvas().affine_inverse()*canvas.get_viewport_rect()
	var lamps: float = TDDaylight.sample(minute).lamps
	for entry: Dictionary in entries:
		var rect: Rect2 = entry.rect
		if not rect.intersects(visible): continue
		if entry.get("district_fixture","") in ["old_cart","steam_cart"] and lamps>0:
			for offset: float in [.20,.52,.80]:
				TDDaylight.glow(canvas,rect.position+rect.size*Vector2(offset,.49),lamps*.66,31)

static func add_inn_banner(sprite: Sprite2D) -> void:
	# Attach the lettering to the cream wine flag painted on the left eave.
	var flag := Node2D.new()
	var size := sprite.texture.get_size()
	flag.position = size*Vector2(-.435,-.415)
	flag.scale = Vector2.ONE/sprite.scale
	flag.draw.connect(func() -> void:
		for i: int in 2:
			flag.draw_string(TDUI.font(),Vector2(-5,i*12),"南埠"[i],HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("69372a")))
	sprite.add_child(flag)
