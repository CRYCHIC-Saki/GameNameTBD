class_name TDTownMap
extends RefCounted

const SIZE := 41
const CENTER := 20
const FACTORY_SLOTS := 8
const FACTORY_CELL := 2
const SUPPLY_KINDS: Array[String] = ["seasoning", "vegetable", "meat", "fruit"]
const FACTORY_QTY_MIN := 1
const FACTORY_QTY_MAX := 8
const FACTORY_LEVEL_MAX := 3
const FACTORY_PRODUCTS := {
	"seasoning": [
		{"id": "salt", "hours": 0.5}, {"id": "peanut_oil", "hours": 0.5}, {"id": "sugar", "hours": 0.5},
		{"id": "soy_sauce", "hours": 0.5}, {"id": "shanxi_vinegar", "hours": 0.5}, {"id": "star_anise", "hours": 0.5},
		{"id": "cinnamon", "hours": 0.5}, {"id": "peppercorn", "hours": 0.5},
	],
	"vegetable": [
		{"id": "tomato", "hours": 0.5}, {"id": "potato", "hours": 0.5}, {"id": "cabbage", "hours": 0.5},
	],
	"meat": [
		{"id": "pork", "hours": 1.0}, {"id": "beef", "hours": 1.0}, {"id": "mutton", "hours": 1.0},
		{"id": "fish", "hours": 1.0}, {"id": "egg", "hours": 1.0}, {"id": "milk", "hours": 1.0}, {"id": "offal", "hours": 1.0},
	],
	"fruit": [
		{"id": "watermelon", "hours": 0.5}, {"id": "lemon", "hours": 0.5},
	],
}
const DINER_LOT_SPAN := Vector2i(12, 18)
const LONG_KINDS: Array[String] = ["plaza", "amusement", "snack_street", "commercial_street"]
const MARKET_TIERS: Array = [
	{"id": "market-small", "name": "街口菜摊", "tier": 1, "w": 2, "h": 2, "unlocks": ["tomato", "egg", "scallion", "oil", "salt"]},
	{"id": "market-mid", "name": "社区菜市", "tier": 2, "w": 4, "h": 3, "unlocks": ["tomato", "egg", "scallion", "oil", "salt", "noodles", "tofu", "pork", "chili", "flour"]},
	{"id": "market-large", "name": "城南大市", "tier": 3, "w": 6, "h": 4, "unlocks": []},
]

var plots: Array = []
var housing_names: Array[String] = []
var roads: Dictionary = {}
var cottage: Dictionary={}

static func supply_of_slot(slot: int) -> String:
	if slot <= 0:
		return SUPPLY_KINDS[0]
	return SUPPLY_KINDS[(slot - 1) % SUPPLY_KINDS.size()]

static func supply_color(supply: String, built: bool) -> Color:
	var color := Color("#888888")
	match supply:
		"seasoning":
			color = Color("#d4a017")
		"vegetable":
			color = Color("#3f8f45")
		"meat":
			color = Color("#c45b4a")
		"fruit":
			color = Color("#e07a3d")
	if not built:
		color = color.darkened(0.35)
	return color

static func supply_name(supply: String, built: bool) -> String:
	match supply:
		"seasoning":
			return "调料厂" if built else "调料厂空地"
		"vegetable":
			return "蔬菜厂" if built else "蔬菜厂空地"
		"meat":
			return "肉类厂" if built else "肉类厂空地"
		"fruit":
			return "水果厂" if built else "水果厂空地"
		_:
			return "原料厂" if built else "原料厂空地"

static func supply_goods(supply: String) -> String:
	match supply:
		"seasoning":
			return "盐、花生油、白糖、生抽、山西醋，以及八角、肉桂、花椒"
		"vegetable":
			return "西红柿、土豆、白菜等蔬菜"
		"meat":
			return "猪羊牛肉、鱼、鸡蛋、牛奶、内脏"
		"fruit":
			return "西瓜、柠檬等水果"
		_:
			return ""

static func time_scale(level: int) -> float:
	var steps := clampi(level, 1, FACTORY_LEVEL_MAX) - 1
	var scale := 1.0
	for _step in steps:
		scale *= 0.75
	return scale

static func products_of(supply: String) -> Array:
	var rows: Variant = FACTORY_PRODUCTS.get(supply, [])
	if rows is Array:
		return (rows as Array).duplicate(true)
	return []

static func product_of(supply: String, item_id: String) -> Dictionary:
	for item: Variant in products_of(supply):
		var row: Dictionary = item
		if String(row.get("id", "")) == item_id:
			return row
	return {}

static func seed_of(town_id: String) -> int:
	var value := 20261012
	for index in town_id.length():
		value = (value * 33 + town_id.unicode_at(index)) % 1000003
	return value

func build(catalog: TDTownCatalog, seed_value: int, _home_size: String = "small", place_diner: bool = false, reserve: Dictionary = {}, built_factories: Array = [], diner_span: Vector2i = Vector2i.ZERO, home_venue: String = "") -> void:
	var rng := TDBusinessRandom.new(seed_value)
	_grow_roads(rng)
	plots = []
	housing_names = []
	var used := {}
	_place_diner_lot(used, rng)
	_place_factory_lots(used, rng)
	if place_diner:
		var span := diner_span
		if span.x <= 0 or span.y <= 0:
			var lot_now := diner_lot()
			span = Vector2i(maxi(1, int(lot_now.get("w", 2)) / 2), maxi(1, int(lot_now.get("h", 2)) / 2))
		_place_home_diner(span, used, home_venue if home_venue != "" else "chinese")
	_mark_built_factories(built_factories)
	if not reserve.is_empty():
		var reserved_width := int(reserve.get("w", 0))
		var reserved_height := int(reserve.get("h", 0))
		var reserved_origin := Vector2i(int(reserve.get("x", -1)), int(reserve.get("y", -1)))
		if _fits(reserved_origin, reserved_width, reserved_height, used):
			_commit("player_diner", String(reserve.get("name", "分店")), reserved_origin.x, reserved_origin.y, reserved_width, reserved_height, used, {"id": "branch_diner", "size": String(reserve.get("size", "small"))})
	var pending: Array[String] = []
	for id: String in TDTownCatalog.ZONE_IDS:
		if id == "player_diner" or id == "market" or id == "diner_lot":
			continue
		pending.append(id)
	pending.sort_custom(func(a: String, b: String) -> bool:
		var left := _span(catalog, a)
		var right := _span(catalog, b)
		return left.x * left.y > right.x * right.y
	)
	for id: String in pending:
		var zone := catalog_zone(catalog, id)
		var span := _span(catalog, id)
		_place(id, String(zone.get("name", id)), span.x, span.y, used, rng, {})
	for tier: Variant in MARKET_TIERS:
		var row: Dictionary = tier
		_place("market", String(row["name"]), int(row["w"]), int(row["h"]), used, rng, row)
	var serial := 1
	for y in SIZE:
		for x in SIZE:
			if is_road(x, y) or used.has(Vector2i(x, y)):
				continue
			var name := _house_name(rng, serial)
			serial += 1
			housing_names.append(name)
			var house := {
				"id": "house-%d" % serial,
				"name": name,
				"kind": "housing",
				"x": x,
				"y": y,
				"w": 1,
				"h": 1,
				"enabled": true,
				"walkable": false,
				"pool": 1,
				"budget_shift": 0,
				"foreign_scale": 1.0,
			}
			var door := _approach(x, y, 1, 1)
			house["approach_x"] = door.x
			house["approach_y"] = door.y
			plots.append(house)
	_copy_catalog(catalog)
	if not cottage.is_empty(): install_cottage(cottage)

func choose_cottage() -> Dictionary:
	var connected:=_connected_roads()
	var available:=_home_cells()
	var goal:=Vector2(CENTER,CENTER)
	for plot:Dictionary in plots:
		if plot.id=="player_diner": goal=Vector2(plot.x+plot.w*.5,plot.y+plot.h*.5)
	var best:Dictionary={};var score:float=INF
	for y:int in SIZE-1:
		for x:int in SIZE-1:
			var at:=Vector2i(x,y)
			if not _empty_home_square(at,available): continue
			var door:=_approach(x,y,2,2)
			if not connected.has(door) or not _adjacent_home(at,door): continue
			var distance:=Vector2(at).distance_squared_to(goal)
			if distance<score:
				score=distance;best={"id":"player_cottage","x":x,"y":y,"w":2,"h":2,"approach_x":door.x,"approach_y":door.y}
	return best

func _connected_roads() -> Dictionary:
	var queue:Array[Vector2i]=[Vector2i(CENTER,CENTER)];var found:Dictionary={queue[0]:true};var cursor:int=0
	while cursor<queue.size():
		var at:=queue[cursor];cursor+=1
		for direction:Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var next:=at+direction
			if is_road(next.x,next.y) and not found.has(next): found[next]=true;queue.append(next)
	return found

func _home_cells() -> Dictionary:
	var available:Dictionary={}
	for plot:Dictionary in plots:
		if plot.kind=="housing": available[Vector2i(plot.x,plot.y)]=true
	for plot:Dictionary in plots:
		if plot.kind=="housing" or plot.id=="player_cottage": continue
		for y:int in range(int(plot.y),int(plot.y+plot.h)):
			for x:int in range(int(plot.x),int(plot.x+plot.w)): available.erase(Vector2i(x,y))
	return available

func _empty_home_square(at:Vector2i,available:Dictionary={}) -> bool:
	if available.is_empty(): available=_home_cells()
	for dy:int in 2:
		for dx:int in 2:
			var x:=at.x+dx;var y:=at.y+dy
			if is_road(x,y): return false
			if not available.has(Vector2i(x,y)): return false
	return true

func _adjacent_home(at:Vector2i,door:Vector2i) -> bool:
	return ((door.x==at.x-1 or door.x==at.x+2) and door.y>=at.y and door.y<at.y+2) or ((door.y==at.y-1 or door.y==at.y+2) and door.x>=at.x and door.x<at.x+2)

func validate_cottage(raw:Variant) -> TDOutcome:
	if not raw is Dictionary or raw.get("id")!="player_cottage" or raw.get("w")!=2 or raw.get("h")!=2: return TDOutcome.new(false,"INVALID_COTTAGE")
	for key:Variant in raw:
		if key not in ["id","x","y","w","h","approach_x","approach_y"]: return TDOutcome.new(false,"INVALID_COTTAGE")
	for key:String in ["x","y","approach_x","approach_y"]:
		if not TDServiceCatalog.integer(raw.get(key),0,SIZE-1): return TDOutcome.new(false,"INVALID_COTTAGE")
	var at:=Vector2i(raw.x,raw.y);var door:=Vector2i(raw.approach_x,raw.approach_y)
	if not _empty_home_square(at) or not _adjacent_home(at,door) or not _connected_roads().has(door): return TDOutcome.new(false,"PROTECTED_COTTAGE_LOCATION")
	return TDOutcome.new(true,"VALID")

func install_cottage(value:Dictionary) -> TDOutcome:
	var checked:=validate_cottage(value)
	if not checked.ok: return checked
	cottage=value.duplicate(true)
	var plot:=value.duplicate(true)
	plot.merge({"kind":"player_cottage","name":"小屋","enabled":true,"walkable":false,"pool":0,"budget_shift":0,"foreign_scale":1.0})
	plots=plots.filter(func(p:Dictionary)->bool:return p.id!="player_cottage")
	plots.push_front(plot)
	return TDOutcome.new(true,"COTTAGE_READY")

func _copy_catalog(catalog: TDTownCatalog) -> void:
	for index in plots.size():
		var plot: Dictionary = plots[index]
		var kind := String(plot["kind"])
		if kind == "housing" or kind == "market":
			continue
		var zone := catalog_zone(catalog, kind)
		plot["pool"] = int(zone.get("pool", 0))
		plot["budget_shift"] = int(zone.get("budget_shift", 0))
		plot["foreign_scale"] = float(zone.get("foreign_scale", 1.0))
		if String(plot["id"]) == kind and String(plot.get("venue", "")) == "":
			plot["name"] = String(zone.get("name", plot["name"]))
		plots[index] = plot

func is_road(x: int, y: int) -> bool:
	return roads.has(Vector2i(x, y))

func build_economic_layout(catalog: TDTownCatalog, seed_value: int) -> TDOutcome:
	# Remote economic regions have no owned player geometry. Reject generated layouts
	# whose commercial frontage is disconnected, instead of selling unreachable land.
	for attempt: int in 32:
		build(catalog,seed_value+attempt*7919)
		var pending: Array[Vector2i]=[Vector2i(CENTER,CENTER)]
		var reached: Dictionary={pending[0]:true}
		var cursor: int=0
		while cursor<pending.size():
			var at:=pending[cursor];cursor+=1
			for direction: Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
				var next:=at+direction
				if not reached.has(next) and is_road(next.x,next.y): reached[next]=true;pending.append(next)
		var valid: bool=true
		for plot: Dictionary in plots:
			if str(plot.id) not in ["competitor","commercial_street"]: continue
			if not _touches(Vector2i(plot.x,plot.y),int(plot.w),int(plot.h)) or not reached.has(Vector2i(plot.approach_x,plot.approach_y)): valid=false
		if valid: return TDOutcome.new(true,"CONNECTED_ECONOMIC_LAYOUT")
	return TDOutcome.new(false,"NO_CONNECTED_ECONOMIC_LAYOUT")

func commercial_parcels() -> Array:
	# Carve shop units only inside already designated commercial property.
	# Housing, diner/factory lots, roads and the player's existing branch are never candidates.
	var result: Array=[]
	for plot: Dictionary in plots:
		if plot.has("economic_parcel_id") or str(plot.id) not in ["competitor","commercial_street"]: continue
		var initial: bool=str(plot.id)=="competitor"
		var vertical: bool=not initial and int(plot.h)>int(plot.w)
		var width: int=1 if initial else 2
		var height: int=1 if initial else 2
		var parent_door:=_approach(int(plot.x),int(plot.y),int(plot.w),int(plot.h))
		var horizontal_front: bool=parent_door.y<int(plot.y) or parent_door.y>=int(plot.y+plot.h)
		for index: int in 3:
			var x:=int(plot.x)+1+(0 if vertical else index*(width+1))
			var y:=int(plot.y)+1+(index*(height+1) if vertical else 0)
			if initial:
				x=int(plot.x)+(index if horizontal_front else 1)
				y=int(plot.y)+(1 if horizontal_front else index)
			if x+width>int(plot.x+plot.w) or y+height>int(plot.y+plot.h): continue
			var at:=Vector2i(x,y)
			var door:=_approach(at.x,at.y,width,height)
			if initial:
				door=at+Vector2i(0,-1 if parent_door.y<int(plot.y) else 1) if horizontal_front else at+Vector2i(-1 if parent_door.x<int(plot.x) else 1,0)
			else: door=at+(Vector2i(-1,0) if vertical else Vector2i(0,-1))
			result.append({"id":"%s:shop:%d"%[plot.id,index],"parent_id":str(plot.id),"x":at.x,"y":at.y,"w":width,"h":height,"approach_x":door.x,"approach_y":door.y,"tradable":not initial,"initial_store_index":index if initial else -1,"capacity":12})
	return result

func apply_commercial_occupancy(ownership: Dictionary) -> TDOutcome:
	var candidates:=commercial_parcels()
	var approved: Dictionary={}
	for parcel: Dictionary in candidates: approved[parcel.id]=parcel
	for id: String in ownership:
		if not approved.has(id) or not ownership[id] is Dictionary or not ownership[id].get("owner_id") is String or not ownership[id].get("store_id") is String: return TDOutcome.new(false,"PROTECTED_OR_UNKNOWN_PARCEL")
	# Validate the complete set before replacing the presentation. Property authority stays in the save.
	plots=plots.filter(func(p:Dictionary)->bool:return not p.has("economic_parcel_id"))
	for parent: Dictionary in plots:
		if str(parent.id) in ["competitor","commercial_street"]: parent.economic_courtyard=true
	for id: String in ownership:
		var record: Dictionary=ownership[id]
		if str(record.owner_id).is_empty(): continue
		var value: Dictionary=approved[id].duplicate(true)
		value.merge({"id":id,"economic_parcel_id":id,"economic_owner":record.owner_id,"economic_store":record.store_id,"kind":"competitor","name":str(record.get("name","街坊餐馆")),"enabled":true,"walkable":false,"pool":0,"budget_shift":0,"foreign_scale":1.0,"construction":bool(record.get("construction",false))},true)
		plots.push_front(value)
	plots=plots.filter(func(p:Dictionary)->bool:return not p.has("economic_service_id"))
	for parent: Dictionary in plots.duplicate():
		if str(parent.id)!="commercial_street" or maxi(int(parent.w),int(parent.h))<11 or mini(int(parent.w),int(parent.h))<2: continue
		var vertical: bool=int(parent.h)>int(parent.w)
		var at:=Vector2i(int(parent.x)+(1 if vertical else 9),int(parent.y)+(9 if vertical else 1))
		var door:=at+(Vector2i(-1,0) if vertical else Vector2i(0,-1))
		plots.push_front({"id":"commercial_street:bank","economic_service_id":"bank","kind":"bank","name":"街坊钱庄","x":at.x,"y":at.y,"w":2 if vertical else 1,"h":1 if vertical else 2,"approach_x":door.x,"approach_y":door.y,"enabled":true,"walkable":false,"pool":0,"budget_shift":0,"foreign_scale":1.0})
	return TDOutcome.new(true,"COMMERCIAL_MAP_UPDATED")

func is_walkable(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= SIZE or y >= SIZE:
		return false
	if is_road(x, y):
		return true
	var plot:=plot_at(x,y)
	return String(plot.get("id", "")) == "player_diner" or bool(plot.get("economic_courtyard",false))

func plot_at(x: int, y: int) -> Dictionary:
	var lot := {}
	for item: Variant in plots:
		var plot: Dictionary = item
		var width := int(plot.get("w", 1))
		var height := int(plot.get("h", 1))
		if x < int(plot["x"]) or y < int(plot["y"]) or x >= int(plot["x"]) + width or y >= int(plot["y"]) + height:
			continue
		var kind := String(plot.get("kind", ""))
		if kind == "diner_lot" or kind == "factory_lot":
			if lot.is_empty():
				lot = plot
			continue
		return plot.duplicate(true)
	if not lot.is_empty():
		return lot.duplicate(true)
	return {}

func can_place(x: int, y: int, width: int, height: int) -> bool:
	if width <= 0 or height <= 0 or x < 0 or y < 0 or x + width > SIZE or y + height > SIZE:
		return false
	for cy in height:
		for cx in width:
			if is_road(x + cx, y + cy):
				return false
			var plot := plot_at(x + cx, y + cy)
			if plot.is_empty():
				continue
			if String(plot.get("kind", "")) != "housing":
				return false
	return true

func covers_road(plot: Dictionary) -> bool:
	for y in int(plot.get("h", 1)):
		for x in int(plot.get("w", 1)):
			if is_road(int(plot["x"]) + x, int(plot["y"]) + y):
				return true
	return false

func arm_length(direction: Vector2i) -> int:
	var length := 0
	var cursor := Vector2i(CENTER, CENTER) + direction
	while is_road(cursor.x, cursor.y):
		length += 1
		cursor += direction
	return length

func set_enabled(id: String, enabled: bool) -> void:
	for index in plots.size():
		var plot: Dictionary = plots[index]
		var kind := String(plot["kind"])
		if kind == "player_diner" or kind == "plaza" or kind == "diner_lot" or kind == "factory_lot" or kind == "supply_factory":
			continue
		if String(plot["id"]) == id or kind == id:
			plot["enabled"] = enabled
			plots[index] = plot

func set_housing_enabled(enabled: bool) -> void:
	for index in plots.size():
		var plot: Dictionary = plots[index]
		if String(plot["kind"]) == "housing":
			plot["enabled"] = enabled
			plots[index] = plot

func housing_enabled() -> int:
	var count := 0
	for item: Variant in plots:
		var plot: Dictionary = item
		if String(plot["kind"]) == "housing" and bool(plot["enabled"]):
			count += 1
	return count

func zone_rows(catalog: TDTownCatalog) -> Array:
	var rows: Array = []
	for id: String in TDTownCatalog.ZONE_IDS:
		var zone := catalog_zone(catalog, id)
		var plot := _by_kind(id)
		zone["enabled"] = bool(plot.get("enabled", true))
		rows.append(zone)
	return rows

func market(id: String) -> Dictionary:
	for item: Variant in plots:
		var plot: Dictionary = item
		if String(plot["id"]) == id and String(plot["kind"]) == "market":
			return plot.duplicate(true)
	return {}

func markets() -> Array:
	var rows: Array = []
	for item: Variant in plots:
		var plot: Dictionary = item
		if String(plot["kind"]) == "market":
			rows.append(plot.duplicate(true))
	return rows

func distance_to(id: String) -> int:
	var plot := _by_id(id)
	if plot.is_empty():
		return 0
	return absi(int(plot["approach_x"]) - CENTER) + absi(int(plot["approach_y"]) - CENTER)

func attraction_bonus() -> int:
	var total := 0
	for kind: String in ["amusement", "landmark"]:
		var plot := _by_kind(kind)
		if plot.is_empty() or not bool(plot.get("enabled", true)):
			continue
		var distance := absi(int(plot["approach_x"]) - CENTER) + absi(int(plot["approach_y"]) - CENTER)
		total += TDSanRules.near_bonus(distance)
	return total

func _by_kind(kind: String) -> Dictionary:
	for item: Variant in plots:
		var plot: Dictionary = item
		if String(plot["kind"]) == kind:
			return plot
	return {}

func _by_id(id: String) -> Dictionary:
	for item: Variant in plots:
		var plot: Dictionary = item
		if String(plot["id"]) == id:
			return plot
	return {}

func catalog_zone(catalog: TDTownCatalog, id: String) -> Dictionary:
	for item: Variant in catalog.zones:
		var zone: Dictionary = item
		if String(zone["id"]) == id:
			return zone.duplicate(true)
	return {"id": id, "name": id, "pool": 0, "budget_shift": 0, "foreign_scale": 1.0}

func _plot(kind: String, title: String, x: int, y: int, catalog: TDTownCatalog) -> Dictionary:
	var zone := catalog_zone(catalog, kind)
	return {
		"id": kind,
		"name": title,
		"kind": kind,
		"x": x,
		"y": y,
		"w": maxi(1, int(zone.get("w", 1))),
		"h": maxi(1, int(zone.get("h", 1))),
		"enabled": true,
		"walkable": false,
		"pool": int(zone.get("pool", 0)),
		"budget_shift": int(zone.get("budget_shift", 0)),
		"foreign_scale": float(zone.get("foreign_scale", 1.0)),
		"approach_x": x,
		"approach_y": y,
		"tier": 0,
		"unlocks": [],
	}

func _span(catalog: TDTownCatalog, id: String) -> Vector2i:
	var zone := catalog_zone(catalog, id)
	var width := maxi(1, int(zone.get("w", 1)))
	var height := maxi(1, int(zone.get("h", 1)))
	if id in LONG_KINDS and maxi(width, height) < 10:
		width = 10
		height = maxi(height, 4)
	return Vector2i(width, height)

func _claim(used: Dictionary, plot: Dictionary) -> void:
	for y in int(plot.get("h", 1)):
		for x in int(plot.get("w", 1)):
			used[Vector2i(int(plot["x"]) + x, int(plot["y"]) + y)] = true

func _grow_roads(rng: TDBusinessRandom) -> void:
	roads = {}
	roads[Vector2i(CENTER, CENTER)] = true
	var directions: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
	for direction: Vector2i in directions:
		var length := 8 + int(rng.unit() * 8.0)
		var cursor := Vector2i(CENTER, CENTER)
		for _step in length:
			cursor += direction
			if not _inside(cursor):
				break
			roads[cursor] = true
	var arms: Array = []
	for key: Variant in roads.keys():
		var cell: Vector2i = key
		if cell.x == CENTER or cell.y == CENTER:
			if cell != Vector2i(CENTER, CENTER):
				arms.append(cell)
	for _branch in 6:
		if arms.is_empty():
			break
		var origin: Vector2i = arms[int(rng.unit() * float(arms.size())) % arms.size()]
		var side := Vector2i(0, 1 if rng.unit() < 0.5 else -1) if origin.y == CENTER else Vector2i(1 if rng.unit() < 0.5 else -1, 0)
		var length := 3 + int(rng.unit() * 5.0)
		var cursor := origin
		for _step in length:
			cursor += side
			if not _inside(cursor):
				break
			roads[cursor] = true

func diner_lot() -> Dictionary:
	return _by_kind("diner_lot")

func factory_lots() -> Array:
	var rows: Array = []
	for item: Variant in plots:
		var plot: Dictionary = item
		var kind := String(plot.get("kind", ""))
		if kind == "factory_lot" or kind == "supply_factory":
			rows.append(plot.duplicate(true))
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("id", "")) < String(b.get("id", ""))
	)
	return rows

func _place_diner_lot(used: Dictionary, rng: TDBusinessRandom) -> void:
	var orientations: Array[Vector2i] = [DINER_LOT_SPAN, Vector2i(DINER_LOT_SPAN.y, DINER_LOT_SPAN.x)]
	for orient: Vector2i in orientations:
		var spot := _against_cross(orient.x, orient.y, used)
		if spot.x >= 0:
			_commit("diner_lot", "餐厅建设区", spot.x, spot.y, orient.x, orient.y, used, {"id": "diner_lot"})
			return
	for orient: Vector2i in orientations:
		_place("diner_lot", "餐厅建设区", orient.x, orient.y, used, rng, {"id": "diner_lot"})
		if not diner_lot().is_empty():
			return

func _place_factory_lots(used: Dictionary, rng: TDBusinessRandom) -> void:
	var cell := FACTORY_CELL
	var grids: Array[Vector2i] = [Vector2i(4, 2), Vector2i(2, 4)]
	for grid: Vector2i in grids:
		var width := grid.x * cell
		var height := grid.y * cell
		var origin := _against_cross(width, height, used)
		if origin.x < 0:
			continue
		var serial := 1
		for row in grid.y:
			for column in grid.x:
				if serial > FACTORY_SLOTS:
					break
				var x := origin.x + column * cell
				var y := origin.y + row * cell
				var supply := supply_of_slot(serial)
				_commit("factory_lot", supply_name(supply, false), x, y, cell, cell, used, {"id": "factory-%d" % serial, "slot": serial, "supply": supply})
				serial += 1
		return
	for serial in range(1, FACTORY_SLOTS + 1):
		var supply := supply_of_slot(serial)
		_place("factory_lot", supply_name(supply, false), cell, cell, used, rng, {"id": "factory-%d" % serial, "slot": serial, "supply": supply})

func _against_cross(width: int, height: int, used: Dictionary) -> Vector2i:
	var origins: Array[Vector2i] = [
		Vector2i(CENTER - width, CENTER - height),
		Vector2i(CENTER + 1, CENTER - height),
		Vector2i(CENTER - width, CENTER + 1),
		Vector2i(CENTER + 1, CENTER + 1),
	]
	for origin: Vector2i in origins:
		if _fits(origin, width, height, used) and _touches_road(origin.x, origin.y, width, height):
			return origin
	for origin: Vector2i in origins:
		var away := Vector2i(-1 if origin.x < CENTER else 1, -1 if origin.y < CENTER else 1)
		for step in 10:
			var shifted := origin + away * step
			if _fits(shifted, width, height, used) and _touches_road(shifted.x, shifted.y, width, height):
				return shifted
	return _lot_spot(width, height, used, true)

func _mark_built_factories(built_factories: Array) -> void:
	var built := {}
	for item: Variant in built_factories:
		built[String(item)] = true
	for index in plots.size():
		var plot: Dictionary = plots[index]
		if String(plot.get("kind", "")) != "factory_lot":
			continue
		var id := String(plot.get("id", ""))
		if not built.has(id):
			continue
		plot["kind"] = "supply_factory"
		plot["name"] = supply_name(String(plot.get("supply", "")), true)
		plots[index] = plot

func mark_factory_built(plot_id: String) -> bool:
	for index in plots.size():
		var plot: Dictionary = plots[index]
		if String(plot.get("id", "")) != plot_id or String(plot.get("kind", "")) != "factory_lot":
			continue
		plot["kind"] = "supply_factory"
		plot["name"] = supply_name(String(plot.get("supply", "")), true)
		plots[index] = plot
		return true
	return false

func _place_home_diner(span: Vector2i, used: Dictionary, venue: String) -> void:
	var lot := diner_lot()
	if lot.is_empty():
		return
	var width := span.x
	var height := span.y
	if width > int(lot["w"]) or height > int(lot["h"]):
		if height <= int(lot["w"]) and width <= int(lot["h"]):
			var swapped := width
			width = height
			height = swapped
		else:
			return
	var spot := _corner_near_center(lot, width, height)
	var title := "西餐厅" if venue == "western" else "中餐厅"
	_commit_overlap("player_diner", title, spot.x, spot.y, width, height, used, {"id": "player_diner", "size": "quarter", "venue": venue})

func _corner_near_center(lot: Dictionary, width: int, height: int) -> Vector2i:
	var base_x := int(lot["x"])
	var base_y := int(lot["y"])
	var best := Vector2i(base_x, base_y)
	var best_distance := 9999
	for ox: int in [0, maxi(0, int(lot["w"]) - width)]:
		for oy: int in [0, maxi(0, int(lot["h"]) - height)]:
			var origin := Vector2i(base_x + ox, base_y + oy)
			var distance := absi(origin.x + (width >> 1) - CENTER) + absi(origin.y + (height >> 1) - CENTER)
			if distance < best_distance:
				best_distance = distance
				best = origin
	return best

func _lot_spot(width: int, height: int, used: Dictionary, prefer_hub: bool) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_distance := 9999
	if width <= 0 or height <= 0:
		return best
	for y in range(0, SIZE - height + 1):
		for x in range(0, SIZE - width + 1):
			if not _fits(Vector2i(x, y), width, height, used):
				continue
			if not _touches_road(x, y, width, height):
				continue
			if prefer_hub and not _near_hub(x, y, width, height, 8):
				continue
			var distance := absi(x + (width >> 1) - CENTER) + absi(y + (height >> 1) - CENTER)
			if prefer_hub:
				if distance < best_distance:
					best_distance = distance
					best = Vector2i(x, y)
			else:
				if distance > best_distance or best.x < 0:
					best_distance = distance
					best = Vector2i(x, y)
	if best.x >= 0 or not prefer_hub:
		return best
	best_distance = 9999
	for y in range(0, SIZE - height + 1):
		for x in range(0, SIZE - width + 1):
			if not _fits(Vector2i(x, y), width, height, used):
				continue
			if not _touches_road(x, y, width, height):
				continue
			var distance := absi(x + (width >> 1) - CENTER) + absi(y + (height >> 1) - CENTER)
			if distance < best_distance:
				best_distance = distance
				best = Vector2i(x, y)
	return best

func _touches_road(x: int, y: int, width: int, height: int) -> bool:
	for cy in height:
		for cx in width:
			for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var neighbor := Vector2i(x + cx, y + cy) + step
				if is_road(neighbor.x, neighbor.y):
					return true
	return false

func _near_hub(x: int, y: int, width: int, height: int, limit: int) -> bool:
	var distance := absi(x + (width >> 1) - CENTER) + absi(y + (height >> 1) - CENTER)
	return distance <= limit

func _commit_overlap(kind: String, title: String, x: int, y: int, width: int, height: int, used: Dictionary, extra: Dictionary) -> void:
	var plot := {
		"id": String(extra.get("id", kind)),
		"name": title,
		"kind": kind,
		"x": x,
		"y": y,
		"w": width,
		"h": height,
		"enabled": true,
		"walkable": false,
		"pool": 0,
		"budget_shift": 0,
		"foreign_scale": 1.0,
		"tier": int(extra.get("tier", 0)),
		"unlocks": (extra.get("unlocks", []) as Array).duplicate(),
		"size": String(extra.get("size", "")),
		"slot": int(extra.get("slot", 0)),
		"venue": String(extra.get("venue", "")),
	}
	var door := _approach(x, y, width, height)
	plot["approach_x"] = door.x
	plot["approach_y"] = door.y
	_claim(used, plot)
	plots.append(plot)

func _place(kind: String, title: String, width: int, height: int, used: Dictionary, rng: TDBusinessRandom, extra: Dictionary) -> void:
	var roads_list := _road_cells()
	if roads_list.is_empty():
		return
	var start := int(rng.unit() * float(roads_list.size())) % roads_list.size()
	var directions: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
	var orientations: Array[Vector2i] = [Vector2i(width, height), Vector2i(height, width)]
	for step in roads_list.size():
		var road: Vector2i = roads_list[(start + step) % roads_list.size()]
		for normal: Vector2i in directions:
			for orient: Vector2i in orientations:
				if _try_place(kind, title, road, normal, orient.x, orient.y, used, extra):
					return
	for y in range(1, SIZE - height):
		for x in range(1, SIZE - width):
			if _fits(Vector2i(x, y), width, height, used):
				_commit(kind, title, x, y, width, height, used, extra)
				_connect(Vector2i(x, y), width, height)
				return

func _try_place(kind: String, title: String, road: Vector2i, normal: Vector2i, width: int, height: int, used: Dictionary, extra: Dictionary) -> bool:
	var touch := road + normal
	var slides := maxi(width, height)
	for slide in slides:
		var origin := touch
		if normal.x != 0:
			var left := touch.x if normal.x > 0 else touch.x - (width - 1)
			origin = Vector2i(left, road.y - slide)
		else:
			var top := touch.y if normal.y > 0 else touch.y - (height - 1)
			origin = Vector2i(road.x - slide, top)
		if _fits(origin, width, height, used):
			_commit(kind, title, origin.x, origin.y, width, height, used, extra)
			return true
	return false

func _fits(origin: Vector2i, width: int, height: int, used: Dictionary) -> bool:
	if origin.x < 0 or origin.y < 0 or origin.x + width > SIZE or origin.y + height > SIZE:
		return false
	for y in height:
		for x in width:
			var cell := Vector2i(origin.x + x, origin.y + y)
			if used.has(cell) or is_road(cell.x, cell.y):
				return false
	return true

func _commit(kind: String, title: String, x: int, y: int, width: int, height: int, used: Dictionary, extra: Dictionary) -> void:
	var plot := {
		"id": String(extra.get("id", kind)),
		"name": title,
		"kind": kind,
		"x": x,
		"y": y,
		"w": width,
		"h": height,
		"enabled": true,
		"walkable": false,
		"pool": 0,
		"budget_shift": 0,
		"foreign_scale": 1.0,
		"tier": int(extra.get("tier", 0)),
		"unlocks": (extra.get("unlocks", []) as Array).duplicate(),
		"size": String(extra.get("size", "")),
		"slot": int(extra.get("slot", 0)),
		"supply": String(extra.get("supply", "")),
	}
	if extra.is_empty():
		plot["id"] = kind
	var door := _approach(x, y, width, height)
	plot["approach_x"] = door.x
	plot["approach_y"] = door.y
	_claim(used, plot)
	plots.append(plot)

func _connect(origin: Vector2i, width: int, height: int) -> void:
	var door := _approach(origin.x, origin.y, width, height)
	if door == Vector2i(CENTER, CENTER) and not _touches(origin, width, height):
		var target := Vector2i(origin.x, CENTER)
		var cursor := Vector2i(CENTER, CENTER)
		while cursor != target:
			cursor.x += 1 if target.x > cursor.x else -1
			roads[cursor] = true
		cursor = target
		var goal_y := origin.y if origin.y > 0 else origin.y + height - 1
		while cursor.y != goal_y:
			cursor.y += 1 if goal_y > cursor.y else -1
			if cursor.x >= origin.x and cursor.x < origin.x + width and cursor.y >= origin.y and cursor.y < origin.y + height:
				break
			roads[cursor] = true

func _touches(origin: Vector2i, width: int, height: int) -> bool:
	for y in height:
		for x in width:
			for direction: Vector2i in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
				var cell := origin + Vector2i(x, y) + direction
				if is_road(cell.x, cell.y):
					return true
	return false

func _approach(x: int, y: int, width: int, height: int) -> Vector2i:
	var best := Vector2i(CENTER, CENTER)
	var best_distance := 9999
	var found := false
	for yy in height:
		for xx in width:
			for direction: Vector2i in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
				var cell := Vector2i(x + xx, y + yy) + direction
				if not is_road(cell.x, cell.y):
					continue
				var distance := absi(cell.x - CENTER) + absi(cell.y - CENTER)
				if not found or distance < best_distance:
					best = cell
					best_distance = distance
					found = true
	return best

func _road_cells() -> Array:
	var cells: Array = []
	for key: Variant in roads.keys():
		cells.append(key)
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x)
	)
	return cells

func _inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < SIZE and cell.y < SIZE

func _house_name(rng: TDBusinessRandom, serial: int) -> String:
	var faces := ["青瓦", "白墙", "红门", "木窗", "窄巷", "天台"]
	return "%s住户%d" % [faces[int(rng.unit() * float(faces.size())) % faces.size()], serial]
