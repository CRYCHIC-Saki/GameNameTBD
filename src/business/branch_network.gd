class_name TDPlayerBranches
extends RefCounted
## Slot-owned branch rules. Cash goes through Shop; customers/markets through WorldEconomy.
const SOURCE := "res://content/branches.json"
const CULTURES := {"cn":"chinese","eu":"continental","jp":"japanese","sea":"southeast_asian","lat":"latin_american"}
const TITLES := {"cn":"中餐馆","eu":"欧陆餐馆","jp":"日料馆","sea":"东南亚餐馆","lat":"拉美餐馆"}
var config: Dictionary = {}
var state: Dictionary = {"schema_version":1,"serial":0,"stores":{},"legacy":{}}
var error := TDOutcome.new(true)
var _owner: WeakRef
var _maps: Dictionary = {}
var _stock_rules := TDFoodStock.load_rules()

func _init() -> void:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
	error = validate_config(raw)
	if error.ok: config = raw

static func validate_config(raw: Variant) -> TDOutcome:
	if not raw is Dictionary or raw.get("schema_version") != 1: return TDOutcome.new(false,"BRANCH_CONFIG_VERSION")
	for key: String in ["min_side","max_side","max_area","opening_base_cents","opening_cell_cents","crew_base_cents","crew_cell_cents","default_budget_cents","target_portions","cook_seconds"]:
		if not TDServiceCatalog.integer(raw.get(key),1,1000000): return TDOutcome.new(false,"BRANCH_CONFIG_NUMBER",key)
	if raw.min_side>raw.max_side or raw.max_side>24 or raw.target_portions>100: return TDOutcome.new(false,"BRANCH_CONFIG_RANGE")
	if not raw.get("managers") is Array or raw.managers.size()!=3: return TDOutcome.new(false,"BRANCH_CONFIG_MANAGERS")
	var ids: Dictionary = {}; var stars: Dictionary = {}
	for m: Variant in raw.managers:
		if not m is Dictionary or not m.get("id") is String or m.id.is_empty() or ids.has(m.id) or not m.get("name") is String or not m.get("special") is String: return TDOutcome.new(false,"BRANCH_CONFIG_MANAGER")
		if not TDServiceCatalog.integer(m.get("stars"),1,3) or stars.has(m.stars) or not TDServiceCatalog.integer(m.get("wage_cents"),1,100000): return TDOutcome.new(false,"BRANCH_CONFIG_STARS")
		for key: String in ["attraction","operations","quality","economy"]:
			if not TDServiceCatalog.integer(m.get(key),0,100): return TDOutcome.new(false,"BRANCH_CONFIG_STAT")
		for key: String in ["service_bonus","quality_bonus","utility_discount"]:
			if not TDEconomicCustomer.finite_range(m.get(key),0,0.5): return TDOutcome.new(false,"BRANCH_CONFIG_BONUS")
		ids[m.id]=true; stars[m.stars]=true
	return TDOutcome.new(true,"VALID")

func attach(owner: TDGameProfile) -> void:
	_owner = weakref(owner)
	_maps.clear()

func owner_profile() -> TDGameProfile:
	return _owner.get_ref() as TDGameProfile if _owner != null else null

func snapshot() -> Dictionary:
	return state.duplicate(true)

func manager(id: String) -> Dictionary:
	for row: Dictionary in config.managers:
		if row.id==id: return row.duplicate(true)
	return {}

func town_map(town: String) -> TDTownMap:
	var p := owner_profile()
	if town==p.commerce.state.home: return p.world.town_map
	if not _maps.has(town):
		var map := TDTownMap.new(); map.layout_version=2
		if not map.build_economic_layout(p.world.catalog,TDTownMap.seed_of(town),p.region_layout_version).ok: return null
		map.apply_commercial_occupancy(p.commerce.expansion.presentation(town,p.commerce.state.competitors[town],int(p.commerce.state.day)))
		_maps[town]=map
	return _maps[town]

func recipes(cuisine: String) -> Array:
	var p := owner_profile(); var rows: Array = []
	for id: String in p.shop.snapshot().unlocked:
		if p.shop.recipe_cultures.get(id,"chinese") != CULTURES.get(cuisine,""): continue
		var offer := p.service.offer(id)
		if offer.is_empty(): continue
		var needs := p.service.material_needs(p.service.cooking,id)
		if needs.is_empty(): continue
		rows.append({"id":id,"name":p.shop.recipe_name(id),"price_cents":int(offer.reference_cents),"reference_cents":int(offer.reference_cents),"ingredients":needs})
	return rows

func _rectangle(raw: Variant) -> Rect2i:
	if not raw is Array or raw.size()!=4: return Rect2i()
	for n: Variant in raw:
		if not TDServiceCatalog.integer(n,0,73): return Rect2i()
	return Rect2i(int(raw[0]),int(raw[1]),int(raw[2]),int(raw[3]))

func quote(town: String, raw: Array, cuisine: String, manager_id: String="") -> TDOutcome:
	var p := owner_profile()
	if not p._alive or not p.at_boundary(): return TDOutcome.new(false,"NOT_AT_BOUNDARY","请先结束当天营业。")
	if town not in p.commerce.config.active_towns: return TDOutcome.new(false,"TOWN_LOCKED","这座小镇尚未开放选址。")
	if cuisine not in p.research.snapshot().cuisines or recipes(cuisine).is_empty(): return TDOutcome.new(false,"CUISINE_LOCKED","需要至少掌握一道该菜系的可制作菜谱。")
	var rect := _rectangle(raw)
	if rect.size.x<int(config.min_side) or rect.size.y<int(config.min_side) or rect.size.x>int(config.max_side) or rect.size.y>int(config.max_side) or rect.get_area()>int(config.max_area): return TDOutcome.new(false,"INVALID_AREA","每边3–12格，总面积最多108格。")
	var map := town_map(town)
	if map==null or rect.end.x>map.extent or rect.end.y>map.extent: return TDOutcome.new(false,"OUT_OF_MAP")
	for other: Dictionary in state.stores.values():
		if other.town_id==town and _rectangle(other.rect).intersects(rect): return TDOutcome.new(false,"OCCUPIED","这里已经有一家分店。")
	for y: int in range(rect.position.y,rect.end.y):
		for x: int in range(rect.position.x,rect.end.x):
			if map.is_road(x,y) or not map.terrain_at(Vector2i(x,y)).buildable or not map.plot_at(x,y).is_empty(): return TDOutcome.new(false,"PROTECTED_LAND","选区含道路、住宅、建筑或不可建设地形。")
	if not map._touches_road(rect.position.x,rect.position.y,rect.size.x,rect.size.y): return TDOutcome.new(false,"NO_ROAD","至少一侧需要紧邻道路。")
	var geo := TDEconomicGeography.new(); geo.configure(town,map.plots,p.commerce.state.cells,2)
	var rent: int=0
	for y: int in range(rect.position.y,rect.end.y):
		for x: int in range(rect.position.x,rect.end.x): rent+=int(geo.cell(Vector2i(x,y)).rent_quote_cents_per_day)
	var cell := geo.cell(rect.get_center())
	var m := manager(manager_id)
	if manager_id!="" and m.is_empty(): return TDOutcome.new(false,"MANAGER_REQUIRED")
	var ops: int=int(m.get("operations",40))
	return TDOutcome.new(true,"QUOTED","",{"town_id":town,"rect":raw.duplicate(),"cuisine_id":cuisine,"manager_id":manager_id,"opening_cents":int(config.opening_base_cents)+rect.get_area()*int(config.opening_cell_cents),"rent_cents":rent,"crew_cents":int(config.crew_base_cents)+rect.get_area()*int(config.crew_cell_cents),"manager_cents":int(m.get("wage_cents",0)),"capacity":maxi(6,roundi(rect.get_area()*(0.5+ops/100.0))),"place":cell})

func open_store(town: String, rect: Array, cuisine: String, manager_id: String, token: String) -> TDOutcome:
	var p := owner_profile()
	if token.is_empty() or p.shop.snapshot().seen.has(token): return TDOutcome.new(false,"DUPLICATE")
	if manager(manager_id).is_empty(): return TDOutcome.new(false,"MANAGER_REQUIRED","请选择店长。")
	var checked := quote(town,rect,cuisine,manager_id)
	if not checked.ok: return checked
	var q := checked.data
	var id := "player-branch:%d"%(int(state.serial)+1)
	var paid := _cash(-int(q.opening_cents),token,"分店开办",id)
	if not paid.ok: return paid
	p.commerce.society.state.sectors.services+=int(q.opening_cents)
	state.serial+=1
	var menu: Array=[recipes(cuisine)[0].duplicate(true)]
	var day: int=int(p.shop.snapshot().day)
	state.stores[id]={"id":id,"name":"%s · %d号店"%[TITLES[cuisine],state.serial],"town_id":town,"cuisine_id":cuisine,"rect":rect.duplicate(),"manager_id":manager_id,"rent_cents":int(q.rent_cents),"crew_cents":int(q.crew_cents),"capacity":int(q.capacity),"opening_cents":int(q.opening_cents),"start_day":day+1,"menu":menu,"budget_cents":int(config.default_budget_cents),"inventory":{},"lots":{},"basis":{},"debt":{},"day":day,"daily":{},"books":[],"awareness":0.35,"popularity":50.0,"place":q.place.duplicate(true),"paused":false}
	p.sync_commercial_map(); p.world.map_revision+=1
	return TDOutcome.new(true,"BRANCH_OPENED","分店已筹建，明日起由店长带队营业。请记得主动保存。",{"store_id":id})

func configure_store(id: String, menu: Array, budget: int, paused: bool=false) -> TDOutcome:
	var p := owner_profile()
	if not p._alive or not p.at_boundary(): return TDOutcome.new(false,"NOT_AT_BOUNDARY")
	if not state.stores.has(id): return TDOutcome.new(false,"UNKNOWN_BRANCH")
	if not TDServiceCatalog.integer(budget,0,10000000) or menu.is_empty() or menu.size()>20: return TDOutcome.new(false,"INVALID_BRANCH_MENU")
	var store: Dictionary=state.stores[id]; var available: Dictionary={}; var chosen: Array=[]
	for dish: Dictionary in recipes(store.cuisine_id): available[dish.id]=dish
	var seen: Dictionary={}
	for row: Variant in menu:
		if not row is Dictionary or not available.has(row.get("id")) or seen.has(row.id) or not TDServiceCatalog.integer(row.get("price_cents"),1,1000000): return TDOutcome.new(false,"INVALID_BRANCH_RECIPE","只能上架已掌握的本菜系菜谱，价格必须有效。")
		var dish: Dictionary=available[row.id].duplicate(true); dish.price_cents=int(row.price_cents); chosen.append(dish); seen[row.id]=true
	store.menu=chosen; store.budget_cents=budget; store.paused=paused
	return TDOutcome.new(true,"BRANCH_CONFIGURED","分店菜单和预算已更新。")

func _cash(cents: int, token: String, label: String, id: String) -> TDOutcome:
	var p := owner_profile()
	if p==null or not p._alive: return TDOutcome.new(false,"STALE_PROFILE")
	return p.shop.branch_adjustment(cents,token,label,id)

func _day(store: Dictionary, day: int) -> void:
	if int(store.day)==day and not store.daily.is_empty(): return
	store.day=day
	store.daily={"day":day,"prepared":false,"settled":false,"sales_cents":0,"purchase_cents":0,"consumed_cents":0,"spoilage_cents":0,"served":0,"rent_cents":0,"utilities_cents":0,"manager_cents":0,"crew_cents":0,"tax_cents":0,"paid_cents":0,"profit_cents":0,"reason":"","popularity_before":float(store.popularity),"awareness_before":float(store.awareness)}
	for item: String in TDFoodStock.expired(store.lots,day):
		var units: int=int(TDFoodStock.expired(store.lots,day)[item])
		store.daily.spoilage_cents+=_take(store,item,units)

func advance_day() -> void:
	_maps.clear()
	for store: Dictionary in state.stores.values(): _day(store,int(owner_profile().shop.snapshot().day))

func prepare() -> void:
	var p := owner_profile()
	if p==null or not p._alive: return
	var day: int=int(p.commerce.state.day)
	for store: Dictionary in state.stores.values():
		_day(store,day)
		if store.daily.prepared or day<int(store.start_day): continue
		store.daily.prepared=true
		_pay_debt(store)
		if store.paused: store.daily.reason="暂停营业（仍承担房租）"; continue
		if not store.debt.is_empty(): store.daily.reason="有欠费，暂停补货，现有原料可继续经营"; continue
		var market: Dictionary=p.commerce.state.markets[store.town_id]
		var remaining: int=mini(int(store.budget_cents),int(p.shop.snapshot().money_cents))
		# Atomic baskets, round robin across dishes. Retained stock counts toward target.
		for n: int in mini(int(config.target_portions),int(store.capacity)):
			var dish: Dictionary=store.menu[n%store.menu.size()]
			var target: int=1+n/store.menu.size()
			var cart: Dictionary={}; var cost: int=0; var sufficient: bool=true
			for item: String in dish.ingredients:
				var needed: int=maxi(0,target*int(dish.ingredients[item])-int(store.inventory.get(item,0)))
				if needed<=0: continue
				cart[item]=needed
				cost+=TDShopSession.amount_cost(needed,int(market.price[item]))
				if needed>int(market.stock[item]): sufficient=false
			if cart.is_empty(): continue
			if not sufficient: store.daily.reason="市场部分原料缺货"; continue
			if cost>remaining: store.daily.reason="采购预算或现金不足"; continue
			var token: String="branch:purchase:%s:%d:%d"%[store.id,day,n]
			if not _cash(-cost,token,"分店采购",store.id).ok: continue
			p.commerce.society.state.sectors.market+=cost
			for item: String in cart:
				var units: int=int(cart[item]); var value: int=TDShopSession.amount_cost(units,int(market.price[item]))
				market.stock[item]-=units; market.requested[item]=int(market.requested.get(item,0))+units; market.sold[item]=int(market.sold.get(item,0))+units
				store.inventory[item]=int(store.inventory.get(item,0))+units
				TDFoodStock.add(store.lots,item,units,day,int(_stock_rules.get(item,{}).get("shelf_days",3)))
				var basis: Dictionary=store.basis.get(item,{"units":0,"value_cents":0}); basis.units+=units; basis.value_cents+=value; store.basis[item]=basis
			remaining-=cost; store.daily.purchase_cents+=cost

func _enough(store: Dictionary, dish: Dictionary) -> bool:
	for item: String in dish.ingredients:
		if int(store.inventory.get(item,0))<int(dish.ingredients[item]): return false
	return not dish.ingredients.is_empty()

func candidates(town: String, group: Dictionary) -> Array:
	var rows: Array=[]
	if owner_profile()==null or not owner_profile()._alive: return rows
	var day: int=int(owner_profile().commerce.state.day)
	for store: Dictionary in state.stores.values():
		if store.town_id!=town or store.paused or day<int(store.start_day): continue
		var m := manager(store.manager_id); var menu: Array=[]
		for dish: Dictionary in store.menu:
			menu.append({"id":dish.id,"family_id":dish.id,"price_cents":int(dish.price_cents),"reference_cents":int(dish.reference_cents),"available":_enough(store,dish),"food":clampf(.55+float(m.quality)*.003+float(m.quality_bonus),0,1),"familiarity":.75 if CULTURES[store.cuisine_id]==str(owner_profile().commerce.config.towns[town].culture) else .4,"taste":{}})
		var served: int=int(store.daily.get("served",0)) if int(store.day)==day else 0
		rows.append({"id":store.id,"open":served<int(store.capacity),"visibility":clampf(float(store.place.visibility)+float(m.attraction)*.002,0,1),"awareness":float(store.awareness),"brand":float(store.popularity)/100,"service":.5+float(m.operations)*.003+float(m.service_bonus),"travel_minutes":float(store.place.travel_minutes.residential),"wait_minutes":served/maxf(1,float(m.operations))*.4,"decor_match":float(store.place.attractiveness),"menu":menu})
	return rows

func sell(id: String, recipe_id: String, family: String) -> bool:
	if owner_profile()==null or not owner_profile()._alive: return false
	if not state.stores.has(id): return false
	var p := owner_profile(); var store: Dictionary=state.stores[id]; var day: int=int(p.commerce.state.day)
	if day<int(store.start_day) or store.paused or bool(store.daily.get("settled",false)) or int(store.daily.get("served",0))>=int(store.capacity): return false
	var found: Array=store.menu.filter(func(d:Dictionary)->bool:return d.id==recipe_id)
	if found.is_empty() or not _enough(store,found[0]): return false
	var dish: Dictionary=found[0]; var price: int=int(dish.price_cents)
	if p.commerce.society.available(family)<price: return false
	var serial: int=int(store.daily.served)
	if not _cash(price,"branch:sale:%s:%d:%d"%[id,day,serial],"分店销售",id).ok: return false
	p.commerce.society.spend(family,price)
	var material_cost: int=0
	for item: String in dish.ingredients: material_cost+=_take(store,item,int(dish.ingredients[item]))
	# Lower waste means fewer real ingredient units consumed after a successful meal.
	var m := manager(store.manager_id)
	var waste: bool=p.commerce.unit("branch:waste:%s:%d:%d"%[id,day,serial])<.12*(1.0-float(m.economy)/100.0)
	if waste:
		for item: String in dish.ingredients:
			var extra: int=mini(int(store.inventory.get(item,0)),ceili(int(dish.ingredients[item])*.05))
			if extra>0: material_cost+=_take(store,item,extra)
	store.daily.consumed_cents+=material_cost; store.daily.served+=1; store.daily.sales_cents+=price
	_pay_debt(store)
	return true

func _take(store: Dictionary, item: String, units: int) -> int:
	var basis: Dictionary=store.basis[item]
	var value: int=int(basis.value_cents) if units==int(basis.units) else roundi(float(basis.value_cents)*units/maxi(1,int(basis.units)))
	basis.units-=units; basis.value_cents-=value; store.inventory[item]-=units
	TDFoodStock.take(store.lots,item,units)
	return value

func _pay_debt(store: Dictionary) -> void:
	var p := owner_profile()
	for key: String in store.debt.keys():
		var due: Dictionary=store.debt[key]; var amount: int=mini(int(due.remaining_cents),int(p.shop.snapshot().money_cents))
		if amount<=0: break
		var token: String="branch:pay:%s:%s:%d"%[store.id,key,int(due.remaining_cents)]
		if not _cash(-amount,token,"分店"+str(due.label),store.id).ok: break
		if due.category=="tax": p.commerce.society.state.public[store.town_id]+=amount
		else: p.commerce.society.state.sectors.services+=amount
		due.remaining_cents-=amount; store.daily.paid_cents+=amount
		if int(due.remaining_cents)==0: store.debt.erase(key)

func settle() -> void:
	if owner_profile()==null or not owner_profile()._alive: return
	prepare()
	var p := owner_profile(); var day: int=int(p.commerce.state.day)
	for store: Dictionary in state.stores.values():
		if day<int(store.start_day) or store.daily.settled: continue
		var d: Dictionary=store.daily; var m := manager(store.manager_id)
		d.rent_cents=int(store.rent_cents)
		d.manager_cents=int(m.wage_cents)
		if not store.paused:
			d.crew_cents=int(store.crew_cents)
			d.utilities_cents=roundi((float(p.commerce.config.fees.opening_cents)+int(d.served)*(float(p.commerce.config.fees.guest_cents)+float(config.cook_seconds)*float(p.commerce.config.fees.cooking_second_cents)))*(1.0-float(m.utility_discount)))
		var before_tax: int=int(d.sales_cents)-int(d.consumed_cents)-int(d.spoilage_cents)-int(d.manager_cents)-int(d.crew_cents)-int(d.utilities_cents)-int(d.rent_cents)
		d.tax_cents=roundi(maxi(0,before_tax)*float(p.commerce.config.society.profit_tax_bps)/10000.0); d.profit_cents=before_tax-int(d.tax_cents)
		for kind: String in ["manager","crew","utilities","rent","tax"]:
			var amount: int=int(d[kind+"_cents"])
			if amount>0: store.debt["%d:%s"%[day,kind]]={"remaining_cents":amount,"category":kind,"label":{"manager":"店长工资","crew":"班组工资","utilities":"水电","rent":"房租","tax":"利润税"}[kind]}
		_pay_debt(store)
		store.awareness=clampf(float(store.awareness)*.995+int(d.served)*.003,0,1)
		store.popularity=clampf(lerpf(float(store.popularity),55+float(m.quality)*.35,minf(.3,int(d.served)*.02)),0,100)
		d.settled=true; d.debt_cents=debt_total(store); d.popularity_after=float(store.popularity); d.awareness_after=float(store.awareness)
		store.books.append(d.duplicate(true))
		while store.books.size()>28: store.books.pop_front()

static func debt_total(store: Dictionary) -> int:
	var total: int=0
	for entry: Dictionary in store.debt.values(): total+=int(entry.remaining_cents)
	return total

func plots(town: String) -> Array:
	var result: Array=[]
	for store: Dictionary in state.stores.values():
		if store.town_id!=town: continue
		var r := _rectangle(store.rect)
		result.append({"id":store.id,"kind":"player_diner","name":store.name,"x":r.position.x,"y":r.position.y,"w":r.size.x,"h":r.size.y,"enabled":true,"walkable":false,"pool":0,"budget_shift":0,"foreign_scale":1.0,"size":"small","branch_id":store.id,"approach_x":r.position.x,"approach_y":r.end.y,"venue":CULTURES[store.cuisine_id]})
	return result

func level_rows(day: int) -> Array:
	var rows: Array=[]
	for store: Dictionary in state.stores.values():
		if store.books.is_empty() or int(store.books.back().day)!=day: continue
		var d: Dictionary=store.books.back()
		rows.append({"store_id":store.id,"scale_milli":maxi(1000,roundi(int(store.capacity)*1000.0/12.0)),"profit_cents":int(d.profit_cents),"popularity_before":float(d.popularity_before),"popularity_after":float(d.popularity_after),"awareness_before":float(d.awareness_before)*100,"awareness_after":float(d.awareness_after)*100})
	return rows

func validate_save(raw: Variant, day: int, service: TDServiceCatalog, unlocked: Array) -> TDOutcome:
	if not raw is Dictionary or raw.get("schema_version")!=1 or not TDServiceCatalog.integer(raw.get("serial"),0,1000000) or not raw.get("stores") is Dictionary or raw.stores.size()>1000 or not raw.get("legacy") is Dictionary: return TDOutcome.new(false,"INVALID_BRANCH_VERSION")
	for id: Variant in raw.stores:
		var s: Variant=raw.stores[id]
		if not id is String or not s is Dictionary or s.get("id")!=id or not id.begins_with("player-branch:") or not s.get("name") is String or s.name.length()>100: return TDOutcome.new(false,"INVALID_BRANCH_ID")
		var suffix: String=str(id).trim_prefix("player-branch:")
		if not suffix.is_valid_int() or int(suffix)<1 or int(suffix)>int(raw.serial) or str(int(suffix))!=suffix: return TDOutcome.new(false,"INVALID_BRANCH_SERIAL")
		if s.get("town_id") not in TDHarbor.TOWNS or not CULTURES.has(s.get("cuisine_id")) or manager(str(s.get("manager_id",""))).is_empty() or not s.get("paused") is bool: return TDOutcome.new(false,"INVALID_BRANCH_TYPE")
		var rect := _rectangle(s.get("rect"))
		if rect.size.x<1 or rect.size.y<1 or rect.end.x>73 or rect.end.y>73: return TDOutcome.new(false,"INVALID_BRANCH_RECT")
		if not (id=="player-branch:1" and bool(raw.legacy.get("branch_open",false))) and (rect.size.x<int(config.min_side) or rect.size.y<int(config.min_side) or rect.size.x>int(config.max_side) or rect.size.y>int(config.max_side) or rect.get_area()>int(config.max_area)): return TDOutcome.new(false,"INVALID_BRANCH_AREA")
		for key: String in ["rent_cents","crew_cents","capacity","opening_cents","budget_cents"]:
			if not TDServiceCatalog.integer(s.get(key),0,100000000): return TDOutcome.new(false,"INVALID_BRANCH_NUMBER",key)
		if int(s.capacity)<1 or not TDServiceCatalog.integer(s.get("day"),1,day) or not TDServiceCatalog.integer(s.get("start_day"),1,day+1): return TDOutcome.new(false,"INVALID_BRANCH_DAY")
		for key: String in ["inventory","lots","basis","debt","daily","place"]:
			if not s.get(key) is Dictionary: return TDOutcome.new(false,"INVALID_BRANCH_FIELD",key)
		if not TDEconomicCell.validate(s.place).ok or s.place.town_id!=s.town_id: return TDOutcome.new(false,"INVALID_BRANCH_PLACE")
		if not TDEconomicCustomer.finite_range(s.get("awareness"),0,1) or not TDEconomicCustomer.finite_range(s.get("popularity"),0,100): return TDOutcome.new(false,"INVALID_BRANCH_REPUTATION")
		if not s.get("menu") is Array or s.menu.is_empty() or s.menu.size()>20 or not s.get("books") is Array or s.books.size()>28: return TDOutcome.new(false,"INVALID_BRANCH_MENU")
		var ids: Dictionary={}
		for d: Variant in s.menu:
			if not d is Dictionary or not d.get("id") is String or d.id not in unlocked or ids.has(d.id) or service.offer(d.id).is_empty() or not d.get("name") is String: return TDOutcome.new(false,"INVALID_BRANCH_RECIPE")
			if not TDServiceCatalog.integer(d.get("price_cents"),1,1000000) or not TDServiceCatalog.integer(d.get("reference_cents"),1,1000000) or not d.get("ingredients") is Dictionary: return TDOutcome.new(false,"INVALID_BRANCH_PRICE")
			if not TDLevelProgression.same_value(d.ingredients,service.material_needs(service.cooking,d.id)): return TDOutcome.new(false,"INVALID_BRANCH_INGREDIENTS")
			ids[d.id]=true
		for item: Variant in s.inventory:
			if not service.config.costs.has(item) or not TDServiceCatalog.integer(s.inventory[item],0,1000000) or not s.basis.get(item) is Dictionary: return TDOutcome.new(false,"INVALID_BRANCH_STOCK")
			var b: Dictionary=s.basis[item]
			if b.get("units")!=s.inventory[item] or not TDServiceCatalog.integer(b.get("value_cents"),0,100000000): return TDOutcome.new(false,"INVALID_BRANCH_BASIS")
		if not TDFoodStock.valid(s.lots,s.inventory,day): return TDOutcome.new(false,"INVALID_BRANCH_LOTS")
		for key: Variant in s.debt:
			var d: Variant=s.debt[key]
			if not key is String or not d is Dictionary or not TDServiceCatalog.integer(d.get("remaining_cents"),1,100000000) or d.get("category") not in ["manager","crew","utilities","rent","tax"] or not d.get("label") is String: return TDOutcome.new(false,"INVALID_BRANCH_DEBT")
		var reports: Array=s.books.duplicate()
		if not s.daily.is_empty(): reports.append(s.daily)
		var previous: int=0
		for index: int in reports.size():
			var d: Variant=reports[index]
			if not d is Dictionary or not TDServiceCatalog.integer(d.get("day"),1,day) or not d.get("prepared") is bool or not d.get("settled") is bool or not d.get("reason") is String: return TDOutcome.new(false,"INVALID_BRANCH_BOOK")
			if index<s.books.size():
				if int(d.day)<=previous or not d.settled: return TDOutcome.new(false,"INVALID_BRANCH_BOOK_ORDER")
				previous=int(d.day)
			for key: String in ["sales_cents","purchase_cents","consumed_cents","spoilage_cents","served","rent_cents","utilities_cents","manager_cents","crew_cents","tax_cents","paid_cents"]:
				if not TDServiceCatalog.integer(d.get(key),0,100000000): return TDOutcome.new(false,"INVALID_BRANCH_BOOK_NUMBER",key)
			if not TDServiceCatalog.integer(d.get("profit_cents"),-100000000,100000000): return TDOutcome.new(false,"INVALID_BRANCH_PROFIT")
			for key: String in ["popularity_before","awareness_before"]:
				if not TDEconomicCustomer.finite_range(d.get(key),0,100 if key.begins_with("popularity") else 1): return TDOutcome.new(false,"INVALID_BRANCH_BOOK_REPUTATION")
			if d.settled:
				for key: String in ["popularity_after","awareness_after"]:
					if not TDEconomicCustomer.finite_range(d.get(key),0,100 if key.begins_with("popularity") else 1): return TDOutcome.new(false,"INVALID_BRANCH_BOOK_REPUTATION")
	return TDOutcome.new(true,"VALID_BRANCHES")

func migrate_legacy() -> void:
	var p := owner_profile(); var w := p.world
	if not w.branch_open or not state.stores.is_empty(): return
	var old := TDWorldSnapshot.capture(w)
	for key: String in old:
		if key.begins_with("branch_"): state.legacy[key]=old[key]
	w.branch_open=false; w._rebuild_map()
	if not p.residence.is_empty(): w.town_map.install_cottage(p.residence.plot)
	var town: String=str(old.branch_town) if old.branch_town in p.commerce.config.active_towns else str(p.commerce.state.home)
	var cuisine: String="cn"
	for key: String in CULTURES:
		if CULTURES[key]==old.branch_culture and not recipes(key).is_empty(): cuisine=key
	var map := town_map(town); var r: Array=[int(old.branch_x),int(old.branch_y),int(old.branch_w),int(old.branch_h)]
	var valid := func(at: Array)->bool:
		var rect := _rectangle(at)
		if rect.size.x<1 or rect.size.y<1 or rect.end.x>73 or rect.end.y>73: return false
		for y: int in range(rect.position.y,rect.end.y):
			for x: int in range(rect.position.x,rect.end.x):
				if map.is_road(x,y) or not map.terrain_at(Vector2i(x,y)).buildable or not map.plot_at(x,y).is_empty(): return false
		return map._touches_road(rect.position.x,rect.position.y,rect.size.x,rect.size.y)
	if not valid.call(r):
		r=[]
		for y: int in range(5,68):
			for x: int in range(2,68):
				var candidate: Array=[x,y,3,4]
				if valid.call(candidate): r=candidate; break
			if not r.is_empty(): break
	if r.is_empty():
		# Full legacy payload remains in the slot; no fees, stock or money discarded.
		state.legacy["migration_notice"]="旧分店未找到安全地块，原数据完整保留，需重新选址。"
		return
	var geo := TDEconomicGeography.new(); geo.configure(town,map.plots,p.commerce.state.cells,2)
	var rent: int=0
	for y: int in range(int(r[1]),int(r[1]+r[3])):
		for x: int in range(int(r[0]),int(r[0]+r[2])): rent+=int(geo.cell(Vector2i(x,y)).rent_quote_cents_per_day)
	state.serial=1
	var day: int=int(p.shop.snapshot().day)
	var menu: Array=[]
	var available := recipes(cuisine)
	for old_dish: Dictionary in old.branch_menu:
		var runtime: String=w.catalog.kitchen_recipe_id(str(old_dish.dish_id))
		for dish: Dictionary in available:
			if dish.id==runtime:
				var entry := dish.duplicate(true); entry.price_cents=maxi(1,int(old_dish.price)*100); menu.append(entry)
	if menu.is_empty(): menu=[available[0].duplicate(true)]
	var s: Dictionary={"id":"player-branch:1","name":"原分店 · "+str(TITLES[cuisine]),"town_id":town,"cuisine_id":cuisine,"rect":r,"manager_id":"manager.steady","rent_cents":rent,"crew_cents":int(config.crew_base_cents)+int(r[2])*int(r[3])*int(config.crew_cell_cents),"capacity":maxi(6,int(r[2])*int(r[3])),"opening_cents":0,"start_day":day+1,"menu":menu,"budget_cents":int(config.default_budget_cents),"inventory":{},"lots":{},"basis":{},"debt":{},"day":day,"daily":{},"books":[],"awareness":0.35,"popularity":50.0,"place":geo.cell(Vector2i(int(r[0]+r[2]/2),int(r[1]+r[3]/2))),"paused":false}
	var retained: Dictionary={}
	for item: String in old.branch_stock:
		var units: int=int(old.branch_stock[item])*1000
		if not p.service.config.costs.has(item): retained[item]=old.branch_stock[item]; continue
		s.inventory[item]=units; s.basis[item]={"units":units,"value_cents":TDShopSession.amount_cost(units,int(p.service.config.costs[item]))}
		s.lots[item]=[]
		if units>0: TDFoodStock.add(s.lots,item,units,day,int(_stock_rules.get(item,{}).get("shelf_days",3)))
	state.stores[s.id]=s
	state.legacy["unmapped_stock"]=retained
	state.legacy["migration_notice"]="旧分店已升级为店长托管，原位置可用时保留，不重收开办费，明日起按新规则营业。旧员工/历史账与未映射原料完整归档。"
