class_name TDSupplierNetwork
extends RefCounted
## External suppliers reserve finite world-market stock at payment. The target
## store alone owns delivered inventory; production never creates a second ledger.
const SOURCE := "res://content/suppliers.json"
const TOWNS := ["chengdu","paris","tokyo","bangkok","mexico_city"]
const STATE_KEYS := ["schema_version","serial","levels","legacy_lines","orders","automation","legacy_migrated"]
const ORDER_KEYS := ["id","token","town_id","store_id","day","total_cents","jobs"]
const JOB_KEYS := ["id","item_id","units","cost_cents","seconds","elapsed","delivered"]
const AUTO_KEYS := ["enabled","budget_cents","spent_day","spent_cents"]
const LINE_KEYS := ["id","town_id","store_id","item_id","target_units","slots","enabled","managed"]
const LINE_STATE_KEYS := ["lines","line_serial"]
var config: Dictionary = {}
var state: Dictionary = {"schema_version":2,"serial":0,"levels":{},"legacy_lines":{},"orders":[],"automation":{},"legacy_migrated":false,"lines":[],"line_serial":0}
var _statuses: Dictionary = {}
var error := TDOutcome.new(true)
var _owner: WeakRef
var _names: Dictionary = {}

func _init() -> void:
	var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
	error=validate_config(raw)
	if error.ok: config=raw
	for town: String in TOWNS: state.levels[town]=1; state.legacy_lines[town]=0

func attach(profile: TDGameProfile) -> void:
	_owner=weakref(profile)
	_names.clear()
	# The composed cooking catalogue includes base ingredients and overrides.
	# service.config.ingredients contains only additions, not the full catalogue.
	for row: Dictionary in profile.service.cooking.data().ingredients: _names[row.id]=str(row.name)

func owner_profile() -> TDGameProfile:
	return _owner.get_ref() as TDGameProfile if _owner!=null else null

static func _keys(raw: Dictionary, expected: Array) -> bool:
	if raw.size()!=expected.size(): return false
	for key: Variant in raw:
		if key not in expected: return false
	return true

static func validate_config(raw: Variant) -> TDOutcome:
	if not raw is Dictionary or raw.get("schema_version")!=1: return TDOutcome.new(false,"SUPPLIER_CONFIG_VERSION")
	if not _keys(raw,["schema_version","parameter_status","note","distance_unit","distance_price_rate","distance_time_rate","upgrade_base_cents","max_level","level_time_factor","max_order_units","max_pending_orders","automation_target_portions","base_seconds","common_items","towns","continuous"]): return TDOutcome.new(false,"SUPPLIER_CONFIG_FIELDS")
	if not raw.continuous is Dictionary or not _keys(raw.continuous,["default_budget_cents","transport_minutes_per_distance","max_lines"]): return TDOutcome.new(false,"SUPPLIER_CONFIG_CONTINUOUS")
	if not TDServiceCatalog.integer(raw.continuous.default_budget_cents,0,10000000) or not TDServiceCatalog.integer(raw.continuous.max_lines,1,500) or not TDEconomicCustomer.finite_range(raw.continuous.transport_minutes_per_distance,1,1440): return TDOutcome.new(false,"SUPPLIER_CONFIG_CONTINUOUS")
	if not raw.parameter_status is String or not raw.note is String: return TDOutcome.new(false,"SUPPLIER_CONFIG_METADATA")
	for key: String in ["upgrade_base_cents","max_order_units","max_pending_orders","automation_target_portions"]:
		if not TDServiceCatalog.integer(raw.get(key),1,100000): return TDOutcome.new(false,"SUPPLIER_CONFIG_NUMBER",key)
	if raw.max_level!=3 or not TDEconomicCustomer.finite_range(raw.distance_unit,1,10000) or not TDEconomicCustomer.finite_range(raw.level_time_factor,.1,1): return TDOutcome.new(false,"SUPPLIER_CONFIG_SCALE")
	for key: String in ["distance_price_rate","distance_time_rate"]:
		if not TDEconomicCustomer.finite_range(raw[key],0,10): return TDOutcome.new(false,"SUPPLIER_CONFIG_DISTANCE")
	if not raw.base_seconds is Dictionary or not _keys(raw.base_seconds,["vegetable","fruit","seasoning","meat"]): return TDOutcome.new(false,"SUPPLIER_CONFIG_GROUP")
	for seconds: Variant in raw.base_seconds.values():
		if not TDEconomicCustomer.finite_range(seconds,1,86400): return TDOutcome.new(false,"SUPPLIER_CONFIG_SECONDS")
	if not raw.common_items is Array or raw.common_items.is_empty() or not raw.towns is Dictionary or not _keys(raw.towns,TOWNS): return TDOutcome.new(false,"SUPPLIER_CONFIG_TOWNS")
	var common: Dictionary={}
	for id: Variant in raw.common_items:
		if not id is String or id.is_empty() or common.has(id): return TDOutcome.new(false,"SUPPLIER_CONFIG_ITEM")
		common[id]=true
	for town: String in TOWNS:
		var row: Variant=raw.towns[town]
		if not row is Dictionary or not _keys(row,["name","position","local_items"]) or not row.name is String or row.name.is_empty() or not row.position is Array or row.position.size()!=2 or not row.local_items is Array: return TDOutcome.new(false,"SUPPLIER_CONFIG_TOWN")
		for value: Variant in row.position:
			if not TDEconomicCustomer.finite_range(value,-10000,10000): return TDOutcome.new(false,"SUPPLIER_CONFIG_POSITION")
		var seen:=common.duplicate()
		for id: Variant in row.local_items:
			if not id is String or id.is_empty() or seen.has(id): return TDOutcome.new(false,"SUPPLIER_CONFIG_ITEM")
			seen[id]=true
	return TDOutcome.new(true,"VALID")

func snapshot() -> Dictionary:
	return state.duplicate(true)

func _store_town(store_id: String) -> String:
	var p:=owner_profile()
	if p==null: return ""
	if store_id=="player_diner": return str(p.commerce.state.home)
	return str(p.branches.state.stores.get(store_id,{}).get("town_id",""))

func distance(source: String, destination: String) -> float:
	if source not in TOWNS or destination not in TOWNS: return -1.0
	var a: Array=config.towns[source].position; var b: Array=config.towns[destination].position
	return Vector2(float(a[0]),float(a[1])).distance_to(Vector2(float(b[0]),float(b[1])))/float(config.distance_unit)

func _supplies(town: String, item: String) -> bool:
	return town in TOWNS and TDMaterialCatalog.supplies(town,item)

func capacity(town: String) -> int:
	return maxi(int(state.levels.get(town,1)),int(state.legacy_lines.get(town,0)))

func _production_duration(rows: Array, town: String) -> float:
	var lines: Array[float]=[]
	for index: int in capacity(town): lines.append(0.0)
	for row: Dictionary in rows:
		var remaining: int=int(row.units)
		while remaining>0:
			var chosen: int=0
			for index: int in lines.size():
				if lines[index]<lines[chosen]: chosen=index
			var units: int=mini(1000,remaining)
			lines[chosen]+=float(row.production_seconds)*float(units)/float(row.units)
			remaining-=units
	return float(lines.max())

func _name(id: String) -> String:
	return item_name(id)

func item_name(id: String) -> String:
	return str(_names.get(id,id))

func catalogue(town: String, store_id: String="player_diner") -> Array[Dictionary]:
	var result: Array[Dictionary]=[]; var p:=owner_profile(); var destination:=_store_town(store_id)
	if not error.ok or p==null or town not in TOWNS or destination not in TOWNS: return result
	var market: Dictionary=p.commerce.state.markets[town]
	for id: String in p.shop.purchase_ids():
		if not _supplies(town,id): continue
		var info:=p.shop.stock_info(id); var span:=distance(town,destination)
		var price: int=maxi(1,ceili(float(market.price[id])*(1.0+span*float(config.distance_price_rate))))
		var seconds: float=float(config.base_seconds[info.group])*pow(float(config.level_time_factor),int(state.levels[town])-1)*(1.0+span*float(config.distance_time_rate))
		result.append({"id":id,"name":_name(id),"group":str(info.group),"unit":str(info.unit),"pack_units":int(info.pack_units),"stock":int(market.stock[id]),"price_cents":price,"production_seconds":seconds,"regions":info.supply_regions,"region_label":info.region_label})
	return result

func quote(town: String, store_id: String, cart: Dictionary) -> TDOutcome:
	var p:=owner_profile()
	if p==null or not error.ok: return TDOutcome.new(false,"SUPPLIER_NOT_ATTACHED")
	if town not in TOWNS or _store_town(store_id) not in TOWNS: return TDOutcome.new(false,"UNKNOWN_SUPPLY_TARGET")
	if cart.is_empty(): return TDOutcome.new(false,"EMPTY_CART","请选择需要生产的食材。")
	var lookup: Dictionary={}
	for row: Dictionary in catalogue(town,store_id): lookup[row.id]=row
	var rows: Array=[]; var total: int=0
	for id: Variant in cart:
		if not id is String or not lookup.has(id): return TDOutcome.new(false,"ITEM_NOT_AVAILABLE","本镇不供此原料，或菜谱／调料所属菜系尚未开放。")
		if not TDServiceCatalog.integer(cart[id],1,int(config.max_order_units)): return TDOutcome.new(false,"INVALID_QUANTITY","单种原料每次最多生产8份。")
		var item: Dictionary=lookup[id]; var units: int=int(cart[id])
		if units>int(item.stock): return TDOutcome.new(false,"MARKET_SHORTAGE","现有原料不足，整笔订单未提交。")
		var cost: int=maxi(1,TDShopSession.amount_cost(units,int(item.price_cents)))
		var seconds: float=float(item.production_seconds)*float(units)/1000.0
		rows.append({"id":id,"units":units,"unit_price_cents":int(item.price_cents),"cost_cents":cost,"production_seconds":seconds})
		total+=cost
	return TDOutcome.new(true,"QUOTED","生产时间按真实活动秒计算，不含前单排队。",{"town_id":town,"store_id":store_id,"rows":rows,"total_cents":total,"distance":distance(town,_store_town(store_id)),"production_seconds":_production_duration(rows,town)})

func order(town: String, store_id: String, cart: Dictionary, token: String) -> TDOutcome:
	var p:=owner_profile()
	if p==null: return TDOutcome.new(false,"SUPPLIER_NOT_ATTACHED")
	if not p._alive: return TDOutcome.new(false,"STALE_PROFILE")
	if token.is_empty() or p.shop.snapshot().seen.has(token): return TDOutcome.new(false,"DUPLICATE")
	if not p.at_boundary(): return TDOutcome.new(false,"NOT_AT_BOUNDARY","请在开门前或日结后安排生产。")
	if store_id!="player_diner" and not p.branches.funded(store_id): return TDOutcome.new(false,"UNPAID_SITE","请先确认店铺付款。")
	if state.orders.filter(func(row: Dictionary)->bool:return not _finished(row)).size()>=int(config.max_pending_orders): return TDOutcome.new(false,"SUPPLIER_QUEUE_FULL")
	var offered:=quote(town,store_id,cart)
	if not offered.ok: return offered
	var paid:=p.shop.branch_adjustment(-int(offered.data.total_cents),token,"供应商生产："+str(config.towns[town].name),store_id)
	if not paid.ok: return paid
	# branch_transfer intentionally has no implicit sector movement in Shop.
	p.commerce.society.state.sectors.market+=int(offered.data.total_cents)
	if store_id!="player_diner": p.branches.note_supply_purchase(store_id,int(offered.data.total_cents))
	state.serial+=1
	var identity: String="supplier-order:%d"%int(state.serial)
	var jobs: Array=[]
	for row: Dictionary in offered.data.rows:
		var remaining: int=int(row.units); var cost_left: int=int(row.cost_cents)
		while remaining>0:
			var portion: int=mini(1000,remaining)
			var cost: int=cost_left if remaining==portion else roundi(float(cost_left)*float(portion)/float(remaining))
			jobs.append({"id":identity+":%d"%jobs.size(),"item_id":str(row.id),"units":portion,"cost_cents":cost,"seconds":float(row.production_seconds)*float(portion)/float(row.units),"elapsed":0.0,"delivered":false})
			remaining-=portion; cost_left-=cost
		var market: Dictionary=p.commerce.state.markets[town]
		market.stock[row.id]-=int(row.units)
		# Daily market statistics are sparse after advance_day; stock is the full ledger.
		market.sold[row.id]=int(market.sold.get(row.id,0))+int(row.units)
		market.requested[row.id]=int(market.requested.get(row.id,0))+int(row.units)
	state.orders.append({"id":identity,"token":token,"town_id":town,"store_id":store_id,"day":int(p.shop.snapshot().day),"total_cents":int(offered.data.total_cents),"jobs":jobs})
	_prune_history()
	return TDOutcome.new(true,"SUPPLIER_ORDERED","已付款并加入生产队列。",{"order_id":identity,"total_cents":int(offered.data.total_cents)})

func _finished(order_row: Dictionary) -> bool:
	return order_row.jobs.all(func(job: Dictionary)->bool:return bool(job.delivered))

func _prune_history() -> void:
	# Shop's persisted transaction tokens keep idempotency after visual history ages out.
	var completed: int=state.orders.filter(func(row: Dictionary)->bool:return _finished(row)).size()
	if completed<=30: return
	var kept: Array=[]
	for row: Dictionary in state.orders:
		if completed>30 and _finished(row): completed-=1
		else: kept.append(row)
	state.orders=kept

func advance(seconds: float) -> void:
	var p:=owner_profile()
	if not is_finite(seconds) or seconds<0 or p==null or not p._alive: return
	for town: String in TOWNS:
		var remaining: float=seconds
		while remaining>0.000001:
			var active: Array=[]
			for row: Dictionary in state.orders:
				if row.town_id!=town or row.has("line_id"): continue
				for job: Dictionary in row.jobs:
					if float(job.elapsed)<float(job.seconds) and active.size()<capacity(town): active.append(job)
			if active.is_empty(): break
			var step: float=remaining
			for job: Dictionary in active: step=minf(step,float(job.seconds)-float(job.elapsed))
			if step<=0: break
			for job: Dictionary in active: job.elapsed=minf(float(job.seconds),float(job.elapsed)+step)
			remaining-=step
	_deliver_ready()

func _deliver_ready() -> void:
	var p:=owner_profile()
	if p==null or not p._alive: return
	for row: Dictionary in state.orders:
		for job: Dictionary in row.jobs:
			if row.has("line_id") and float(job.transit_elapsed)<float(job.transit_minutes): continue
			if bool(job.delivered) or float(job.elapsed)<float(job.seconds): continue
			var token: String="supply-arrival:"+str(job.id)
			var receipt: TDOutcome
			if row.store_id=="player_diner":
				receipt=p.shop.receive_supply({str(job.item_id):int(job.units)},token,int(job.cost_cents),row.has("line_id"))
			else:
				receipt=p.branches.receive_supply(str(row.store_id),{str(job.item_id):int(job.units)},{str(job.item_id):int(job.cost_cents)},token)
			if receipt.ok or receipt.code=="DUPLICATE": job.delivered=true
	_prune_history()

func upgrade(town: String, token: String) -> TDOutcome:
	var p:=owner_profile()
	if p==null: return TDOutcome.new(false,"SUPPLIER_NOT_ATTACHED")
	if not p._alive: return TDOutcome.new(false,"STALE_PROFILE")
	if token.is_empty() or p.shop.snapshot().seen.has(token): return TDOutcome.new(false,"DUPLICATE")
	if not p.at_boundary(): return TDOutcome.new(false,"NOT_AT_BOUNDARY")
	if town not in TOWNS: return TDOutcome.new(false,"UNKNOWN_SUPPLIER")
	var level: int=int(state.levels[town])
	if level>=int(config.max_level): return TDOutcome.new(false,"MAX_LEVEL")
	var cents: int=int(config.upgrade_base_cents)*level
	var paid:=p.shop.branch_adjustment(-cents,token,"供应商产线升级","supplier-network")
	if not paid.ok: return paid
	p.commerce.society.state.sectors.services+=cents
	state.levels[town]=level+1
	return TDOutcome.new(true,"SUPPLIER_UPGRADED","产线增加，之后的新订单生产时间缩短。",{"level":level+1,"cost_cents":cents})

func set_automation(store_id: String, enabled: bool, budget_cents: int) -> TDOutcome:
	var p:=owner_profile()
	if p==null: return TDOutcome.new(false,"SUPPLIER_NOT_ATTACHED")
	if not p._alive: return TDOutcome.new(false,"STALE_PROFILE")
	if _store_town(store_id) not in TOWNS: return TDOutcome.new(false,"UNKNOWN_SUPPLY_TARGET")
	if budget_cents<0 or budget_cents>10000000: return TDOutcome.new(false,"INVALID_SUPPLY_BUDGET")
	var previous: Dictionary=state.automation.get(store_id,{"spent_day":0,"spent_cents":0})
	state.automation[store_id]={"enabled":enabled,"budget_cents":budget_cents,"spent_day":int(previous.spent_day),"spent_cents":int(previous.spent_cents)}
	if not enabled:
		for line: Dictionary in state.lines:
			if line.store_id==store_id and line.managed: line.enabled=false
	return TDOutcome.new(true,"SUPPLY_AUTOMATION_UPDATED")

func _desired(store_id: String) -> Dictionary:
	var p:=owner_profile(); var needed: Dictionary={}; var menu: Array=[]
	if store_id=="player_diner":
		var data:=p.shop.snapshot()
		for id: String in data.menu:
			if not data.menu[id].enabled: continue
			var family: String=p.shop.family_id(id)
			if p.service.offer(family).is_empty(): continue
			menu.append({"ingredients":p.service.material_needs(p.service.cooking,family)})
	else: menu=p.branches.state.stores[store_id].menu
	# The configured total target is distributed across enabled dishes, not multiplied per dish.
	var portions: int=maxi(1,ceili(float(config.automation_target_portions)/maxi(1,menu.size())))
	for entry: Dictionary in menu:
		for id: String in entry.ingredients: needed[id]=int(needed.get(id,0))+int(entry.ingredients[id])*portions
	return needed

func in_transit(store_id: String, item_id: String) -> int:
	var units: int=0
	for row: Dictionary in state.orders:
		if row.store_id!=store_id: continue
		for job: Dictionary in row.jobs:
			if not job.delivered and job.item_id==item_id: units+=int(job.units)
	if store_id=="player_diner": units+=_legacy_pending_units(item_id)
	return units

func _legacy_pending_units(item_id: String) -> int:
	var p:=owner_profile()
	if p==null or not p.service.config.costs.has(item_id): return 0
	# These are views of the old owners, not migrated deliveries. Old factory qty
	# is the remaining number of portions; completed portions move into supply.stock.
	var units: int=maxi(0,int(p.world.supply.stock.get(item_id,0)))*1000
	for raw_jobs: Variant in p.world.factory_jobs.values():
		var jobs: Array=raw_jobs if raw_jobs is Array else ([raw_jobs] if raw_jobs is Dictionary else [])
		for job: Variant in jobs:
			if job is Dictionary and job.get("item_id")==item_id and TDServiceCatalog.integer(job.get("qty"),1,1000000000): units+=int(job.qty)*1000
	for shipment: Dictionary in p.world.supply.incoming:
		if shipment.get("item_id")==item_id: units+=maxi(0,int(shipment.get("amount",0)))*1000
	# Legacy world-commerce shipments have only one receiving kitchen: the main
	# store. Their rows already use internal units; never multiply those by 1000.
	for shipment: Dictionary in p.commerce.state.shipments:
		if not shipment.delivered and shipment.rows.has(item_id): units+=int(shipment.rows[item_id].units)
	return units

func automate() -> void:
	var p:=owner_profile()
	if p==null or not p._alive: return
	# Automation edits only its own rows. Manual lines are never overwritten.
	for line: Dictionary in state.lines:
		if line.managed: line.enabled=false
	for store_id: String in state.automation:
		if not state.automation[store_id].enabled or _store_town(store_id) not in TOWNS: continue
		if store_id!="player_diner" and not p.branches.funded(store_id): continue
		for item: String in _desired(store_id):
			var found: Dictionary={};var manual: bool=false
			for line: Dictionary in state.lines:
				if line.store_id==store_id and line.item_id==item:
					if not line.managed: manual=true
					else: found=line
			if manual: continue
			var target: int=mini(100000,int(_desired(store_id)[item]))
			if found.is_empty():
				var best: Dictionary={};var town_id: String=""
				for town: String in TOWNS:
					for offer: Dictionary in catalogue(town,store_id):
						if offer.id==item and (best.is_empty() or int(offer.price_cents)<int(best.price_cents)): best=offer;town_id=town
				if not town_id.is_empty(): create_line(town_id,store_id,item,target,1,true)
			else: found.target_units=target;found.enabled=true
	advance_game_minutes(0)

func _line(id: String) -> Dictionary:
	for line: Dictionary in state.lines:
		if line.id==id: return line
	return {}

func create_line(town: String, store_id: String, item: String, target: int, slots: int=1, managed: bool=false) -> TDOutcome:
	var p:=owner_profile()
	if p==null or not p._alive: return TDOutcome.new(false,"STALE_PROFILE")
	if store_id!="player_diner" and not p.branches.funded(store_id): return TDOutcome.new(false,"UNPAID_SITE")
	if state.lines.size()>=int(config.continuous.max_lines): return TDOutcome.new(false,"LINE_LIMIT")
	if not TDServiceCatalog.integer(target,1,100000) or slots<1 or slots>capacity(town): return TDOutcome.new(false,"INVALID_LINE")
	if not catalogue(town,store_id).any(func(row:Dictionary)->bool:return row.id==item): return TDOutcome.new(false,"ITEM_NOT_AVAILABLE","本镇不供此原料，或菜谱／调料所属菜系尚未开放。")
	for line: Dictionary in state.lines:
		if line.town_id==town and line.store_id==store_id and line.item_id==item: return TDOutcome.new(false,"DUPLICATE_LINE","已有同源同店同原料产线，请调整现有产线。")
	state.line_serial+=1
	var id: String="supply-line:%d"%int(state.line_serial)
	state.lines.append({"id":id,"town_id":town,"store_id":store_id,"item_id":item,"target_units":target,"slots":slots,"enabled":true,"managed":managed})
	if not state.automation.has(store_id): set_automation(store_id,false,int(config.continuous.default_budget_cents))
	return TDOutcome.new(true,"LINE_CREATED","产线已启用，将按每日预算逐批采购。",{"line_id":id})

func configure_line(id: String, target: int, slots: int, enabled: bool) -> TDOutcome:
	var p:=owner_profile();var line:=_line(id)
	if p==null or not p._alive: return TDOutcome.new(false,"STALE_PROFILE")
	if line.is_empty() or target<1 or target>100000 or slots<1 or slots>capacity(str(line.get("town_id",""))): return TDOutcome.new(false,"INVALID_LINE")
	line.target_units=target;line.slots=slots;line.enabled=enabled;line.managed=false
	return TDOutcome.new(true,"LINE_UPDATED","配置已更新；已付款批次继续完成。")

func move_line(id: String, offset: int) -> TDOutcome:
	var p:=owner_profile();var line:=_line(id)
	if p==null or not p._alive: return TDOutcome.new(false,"STALE_PROFILE")
	if line.is_empty(): return TDOutcome.new(false,"UNKNOWN_LINE")
	var index: int=state.lines.find(line);state.lines.remove_at(index)
	state.lines.insert(clampi(index+offset,0,state.lines.size()),line)
	return TDOutcome.new(true,"LINE_MOVED")

func remove_line(id: String) -> TDOutcome:
	var p:=owner_profile();var line:=_line(id)
	if p==null or not p._alive: return TDOutcome.new(false,"STALE_PROFILE")
	if line.is_empty(): return TDOutcome.new(false,"UNKNOWN_LINE")
	state.lines.erase(line)
	return TDOutcome.new(true,"LINE_REMOVED","已撤销持续计划，已付款批次仍会送到原店。")

func _live_job(line_id: String) -> Dictionary:
	for order_row: Dictionary in state.orders:
		if order_row.get("line_id","")!=line_id: continue
		for job: Dictionary in order_row.jobs:
			if float(job.elapsed)<float(job.seconds): return job
	return {}

func _on_hand(store_id: String, item: String) -> int:
	var p:=owner_profile()
	return int(p.shop.snapshot().inventory.get(item,0)) if store_id=="player_diner" else int(p.branches.state.stores.get(store_id,{}).get("inventory",{}).get(item,0))

func _start_batch(line: Dictionary) -> String:
	var p:=owner_profile()
	if not line.enabled: return "已停用"
	if line.store_id!="player_diner" and not p.branches.funded(line.store_id): return "店铺未付款"
	var deficit: int=int(line.target_units)-_on_hand(line.store_id,line.item_id)-in_transit(line.store_id,line.item_id)
	if deficit<=0: return "库存目标已满足"
	if p.shop.stock_info(line.item_id).condiment and not p.shop.purchasable(line.item_id): return "等待调料菜系开放"
	if state.orders.filter(func(row:Dictionary)->bool:return not _finished(row)).size()>=int(config.max_pending_orders): return "运输队列已满"
	var units: int=mini(1000,deficit)
	var offered:=quote(line.town_id,line.store_id,{str(line.item_id):units})
	if not offered.ok: return "源镇缺货" if offered.code=="MARKET_SHORTAGE" else "原料尚不可供货"
	var cost: int=int(offered.data.total_cents)
	var day: int=int(p.shop.snapshot().day)
	var setting: Dictionary=state.automation[line.store_id]
	if int(setting.spent_day)!=day: setting.spent_day=day;setting.spent_cents=0
	var limit: int=int(setting.budget_cents)-int(setting.spent_cents)
	if line.store_id!="player_diner":
		var store: Dictionary=p.branches.state.stores[line.store_id]
		limit=mini(limit,int(store.budget_cents)-(int(store.daily.get("purchase_cents",0)) if int(store.day)==day else 0))
	if cost>limit: return "每日预算不足"
	if cost>int(p.shop.snapshot().money_cents): return "现金不足"
	var id: String="supplier-order:%d"%(int(state.serial)+1)
	var token: String="line-batch:"+id
	var paid:=p.shop.branch_adjustment(-cost,token,"持续供货："+item_name(line.item_id),line.store_id)
	if not paid.ok: return paid.code
	p.commerce.society.state.sectors.market+=cost
	if line.store_id!="player_diner": p.branches.note_supply_purchase(line.store_id,cost)
	setting.spent_cents+=cost
	var market: Dictionary=p.commerce.state.markets[line.town_id]
	market.stock[line.item_id]-=units
	market.sold[line.item_id]=int(market.sold.get(line.item_id,0))+units
	market.requested[line.item_id]=int(market.requested.get(line.item_id,0))+units
	var group: String=p.shop.stock_info(line.item_id).group
	var duration: float=float(config.base_seconds[group])*pow(float(config.level_time_factor),int(state.levels[line.town_id])-1)*units/1000.0
	var travel: float=distance(line.town_id,_store_town(line.store_id))*float(config.continuous.transport_minutes_per_distance)
	state.serial+=1
	state.orders.append({"id":id,"token":token,"town_id":line.town_id,"store_id":line.store_id,"day":day,"total_cents":cost,"line_id":line.id,"jobs":[{"id":id+":0","item_id":line.item_id,"units":units,"cost_cents":cost,"seconds":duration,"elapsed":0.0,"delivered":false,"transit_minutes":travel,"transit_elapsed":0.0}]})
	return "生产中"

func _allocation() -> Array:
	var active: Array=[];_statuses.clear()
	for town: String in TOWNS:
		var free: int=capacity(town)
		# Paid legacy queues keep their existing capacity entitlement.
		for order_row: Dictionary in state.orders:
			if order_row.town_id!=town or order_row.has("line_id"): continue
			for job: Dictionary in order_row.jobs:
				if float(job.elapsed)<float(job.seconds): free=maxi(0,free-1)
		# Deleted plans retain paid work; it is drained before new plans.
		for order_row: Dictionary in state.orders:
			if order_row.town_id!=town or not order_row.has("line_id") or not _line(order_row.line_id).is_empty(): continue
			for job: Dictionary in order_row.jobs:
				if float(job.elapsed)<float(job.seconds) and free>0: active.append({"job":job,"slots":1});free-=1
		for line: Dictionary in state.lines:
			if line.town_id!=town: continue
			var job:=_live_job(line.id)
			if free<=0: _statuses[line.id]="等待产能";continue
			if job.is_empty():
				_statuses[line.id]=_start_batch(line)
				job=_live_job(line.id)
			if job.is_empty(): continue
			var count: int=mini(free,int(line.slots));free-=count
			active.append({"job":job,"slots":count})
			_statuses[line.id]="生产中 · %d产能"%count
	return active

func advance_active_time(seconds: float, game_minutes: float) -> void:
	# Split at legacy completions so a long frame cannot lend new lines capacity
	# for time when the original real-second job was still occupying it.
	if not is_finite(seconds) or seconds<0 or not is_finite(game_minutes) or game_minutes<0: return
	if seconds<=0: advance_game_minutes(game_minutes);return
	var remaining: float=seconds
	while remaining>0.0000001:
		var step: float=remaining
		for row: Dictionary in state.orders:
			if row.has("line_id"): continue
			for job: Dictionary in row.jobs:
				if float(job.elapsed)<float(job.seconds): step=minf(step,float(job.seconds)-float(job.elapsed))
		advance_game_minutes(step*game_minutes/seconds)
		advance(step)
		remaining=maxf(0,remaining-step)
	advance_game_minutes(0)

func advance_game_minutes(minutes: float) -> void:
	var p:=owner_profile()
	if p==null or not p._alive or not is_finite(minutes) or minutes<0: return
	var remaining: float=minutes
	_deliver_ready()
	var active:=_allocation()
	while remaining>0.0000001:
		var travel: Array=[];var step: float=remaining
		for entry: Dictionary in active: step=minf(step,(float(entry.job.seconds)-float(entry.job.elapsed))/(60.0*int(entry.slots)))
		for order_row: Dictionary in state.orders:
			if not order_row.has("line_id"): continue
			for job: Dictionary in order_row.jobs:
				if not job.delivered and float(job.elapsed)>=float(job.seconds) and float(job.transit_elapsed)<float(job.transit_minutes):
					travel.append(job);step=minf(step,float(job.transit_minutes)-float(job.transit_elapsed))
		if active.is_empty() and travel.is_empty(): break
		for entry: Dictionary in active: entry.job.elapsed=minf(float(entry.job.seconds),float(entry.job.elapsed)+step*60.0*int(entry.slots))
		for job: Dictionary in travel: job.transit_elapsed=minf(float(job.transit_minutes),float(job.transit_elapsed)+step)
		remaining=maxf(0,remaining-step)
		_deliver_ready();active=_allocation()

func line_rows(town: String="") -> Array[Dictionary]:
	var rows: Array[Dictionary]=[]
	for line: Dictionary in state.lines:
		if not town.is_empty() and line.town_id!=town: continue
		var row: Dictionary=line.duplicate(true);var job:=_live_job(line.id)
		row.status=_statuses.get(line.id,"待调度" if line.enabled else "已停用")
		row.have=_on_hand(line.store_id,line.item_id);row.pending=in_transit(line.store_id,line.item_id)
		row.progress=0.0 if job.is_empty() else float(job.elapsed)/float(job.seconds)
		row.per_hour=3600.0/(float(config.base_seconds[owner_profile().shop.stock_info(line.item_id).group])*pow(float(config.level_time_factor),int(state.levels[line.town_id])-1))*int(line.slots)
		rows.append(row)
	return rows

func migrate_legacy(world: TDPhase3Session) -> void:
	var p:=owner_profile()
	if p==null or not p._alive: return
	if state.legacy_migrated: return
	# Existing paid queues, stock and their basis stay with the old factory owner.
	# Keep all purchased parallel lines, even when their combined capacity exceeds
	# the new supplier's ordinary three-level cap. Queues themselves stay legacy-owned.
	for key: String in world.factory_built:
		if not world.factory_built[key]: continue
		var town: String=key.get_slice(":",0)
		if town in TOWNS:
			var level: int=clampi(int(world.factory_level.get(key,1)),1,int(config.max_level))
			state.levels[town]=maxi(int(state.levels[town]),level)
			state.legacy_lines[town]+=level
	state.legacy_migrated=true

func validate_save(raw: Variant, stores: Dictionary={}, day: int=-1, allowed_items: Array=[]) -> TDOutcome:
	if not raw is Dictionary or (raw.get("schema_version")!=1 and raw.get("schema_version")!=2): return TDOutcome.new(false,"SUPPLIER_SAVE_VERSION")
	var modern: bool=int(raw.schema_version)==2
	if not _keys(raw,STATE_KEYS+(LINE_STATE_KEYS if modern else [])) or not TDServiceCatalog.integer(raw.serial,0,100000000) or not raw.levels is Dictionary or not _keys(raw.levels,TOWNS) or not raw.legacy_lines is Dictionary or not _keys(raw.legacy_lines,TOWNS) or not raw.orders is Array or raw.orders.size()>130 or not raw.automation is Dictionary or not raw.legacy_migrated is bool: return TDOutcome.new(false,"SUPPLIER_SAVE_FIELDS")
	for level: Variant in raw.levels.values():
		if not TDServiceCatalog.integer(level,1,3): return TDOutcome.new(false,"SUPPLIER_SAVE_LEVEL")
	for lines: Variant in raw.legacy_lines.values():
		if not TDServiceCatalog.integer(lines,0,1000) or (not raw.legacy_migrated and int(lines)>0): return TDOutcome.new(false,"SUPPLIER_SAVE_LEGACY_LINES")
	var p:=owner_profile()
	if p!=null and stores.is_empty(): stores=p.branches.state.stores
	if p!=null and day<0: day=int(p.shop.snapshot().day)
	if p!=null and allowed_items.is_empty(): allowed_items=p.commerce.costs.keys()
	if modern:
		if not TDServiceCatalog.integer(raw.line_serial,0,100000000) or not raw.lines is Array or raw.lines.size()>int(config.continuous.max_lines): return TDOutcome.new(false,"SUPPLIER_SAVE_LINES")
		var ids: Dictionary={};var destinations: Dictionary={}
		for line: Variant in raw.lines:
			if not line is Dictionary or not _keys(line,LINE_KEYS) or not line.id is String or not line.id.begins_with("supply-line:") or ids.has(line.id): return TDOutcome.new(false,"SUPPLIER_SAVE_LINE")
			var serial_text: String=str(line.id).trim_prefix("supply-line:")
			if not serial_text.is_valid_int() or int(serial_text)<1 or int(serial_text)>int(raw.line_serial) or str(int(serial_text))!=serial_text: return TDOutcome.new(false,"SUPPLIER_SAVE_LINE")
			if line.town_id not in TOWNS or not line.store_id is String or (line.store_id!="player_diner" and not stores.has(line.store_id)) or not raw.automation.has(line.store_id) or not line.item_id is String or TDMaterialCatalog.item(str(line.item_id)).is_empty() or (not allowed_items.is_empty() and line.item_id not in allowed_items): return TDOutcome.new(false,"SUPPLIER_SAVE_LINE_TARGET")
			if not TDServiceCatalog.integer(line.target_units,1,100000) or not TDServiceCatalog.integer(line.slots,1,maxi(int(raw.levels[line.town_id]),int(raw.legacy_lines[line.town_id]))) or not line.enabled is bool or not line.managed is bool: return TDOutcome.new(false,"SUPPLIER_SAVE_LINE_CONFIG")
			var key: String=line.town_id+":"+line.store_id+":"+line.item_id
			if destinations.has(key): return TDOutcome.new(false,"SUPPLIER_SAVE_LINE_DUPLICATE")
			ids[line.id]=true;destinations[key]=true
	var seen_ids: Dictionary={}; var seen_tokens: Dictionary={}; var seen_jobs: Dictionary={}; var active_lines: Dictionary={}
	for row: Variant in raw.orders:
		if not row is Dictionary or not _keys(row,ORDER_KEYS+(["line_id"] if modern and row.has("line_id") else [])) or not row.id is String or not row.id.begins_with("supplier-order:") or not row.token is String or row.token.is_empty() or seen_ids.has(row.id) or seen_tokens.has(row.token) or row.town_id not in TOWNS: return TDOutcome.new(false,"SUPPLIER_SAVE_ORDER")
		var serial_text: String=str(row.id).trim_prefix("supplier-order:")
		if not serial_text.is_valid_int() or int(serial_text)<1 or int(serial_text)>int(raw.serial) or str(int(serial_text))!=serial_text: return TDOutcome.new(false,"SUPPLIER_SAVE_SERIAL")
		if row.store_id!="player_diner" and not stores.has(row.store_id): return TDOutcome.new(false,"SUPPLIER_SAVE_TARGET")
		if not TDServiceCatalog.integer(row.day,1,1000000) or (day>=0 and int(row.day)>day) or not TDServiceCatalog.integer(row.total_cents,0,100000000) or not row.jobs is Array or row.jobs.is_empty() or row.jobs.size()>208: return TDOutcome.new(false,"SUPPLIER_SAVE_ORDER_DATA")
		seen_ids[row.id]=true; seen_tokens[row.token]=true
		var total: int=0
		for index: int in row.jobs.size():
			var job: Variant=row.jobs[index]
			if not job is Dictionary or not _keys(job,JOB_KEYS+(["transit_minutes","transit_elapsed"] if row.has("line_id") else [])) or job.id!=row.id+":%d"%index or seen_jobs.has(job.id) or not job.item_id is String or TDMaterialCatalog.item(str(job.item_id)).is_empty() or (not allowed_items.is_empty() and job.item_id not in allowed_items): return TDOutcome.new(false,"SUPPLIER_SAVE_JOB")
			if not TDServiceCatalog.integer(job.units,1,1000) or not TDServiceCatalog.integer(job.cost_cents,0,100000000) or not TDEconomicCustomer.finite_range(job.seconds,.000001,10000000) or not TDEconomicCustomer.finite_range(job.elapsed,0,float(job.seconds)) or not job.delivered is bool or (job.delivered and float(job.elapsed)!=float(job.seconds)): return TDOutcome.new(false,"SUPPLIER_SAVE_PROGRESS")
			if row.has("line_id"):
				if not row.line_id is String or not row.line_id.begins_with("supply-line:") or not str(row.line_id).trim_prefix("supply-line:").is_valid_int() or int(str(row.line_id).trim_prefix("supply-line:"))<1 or int(str(row.line_id).trim_prefix("supply-line:"))>int(raw.line_serial): return TDOutcome.new(false,"SUPPLIER_SAVE_LINE_REFERENCE")
				for line: Dictionary in raw.lines:
					if line.id==row.line_id and (line.town_id!=row.town_id or line.store_id!=row.store_id or line.item_id!=job.item_id): return TDOutcome.new(false,"SUPPLIER_SAVE_LINE_REFERENCE")
				if float(job.elapsed)<float(job.seconds):
					if active_lines.has(row.line_id): return TDOutcome.new(false,"SUPPLIER_SAVE_DOUBLE_PRODUCTION")
					active_lines[row.line_id]=true
				if row.jobs.size()!=1 or not TDEconomicCustomer.finite_range(job.transit_minutes,0,100000) or not TDEconomicCustomer.finite_range(job.transit_elapsed,0,float(job.transit_minutes)) or (float(job.transit_elapsed)>0 and float(job.elapsed)<float(job.seconds)) or (job.delivered and float(job.transit_elapsed)!=float(job.transit_minutes)): return TDOutcome.new(false,"SUPPLIER_SAVE_TRANSPORT")
			seen_jobs[job.id]=true; total+=int(job.cost_cents)
		if total!=int(row.total_cents): return TDOutcome.new(false,"SUPPLIER_SAVE_COST")
	for store_id: Variant in raw.automation:
		if not store_id is String or (store_id!="player_diner" and not stores.has(store_id)): return TDOutcome.new(false,"SUPPLIER_SAVE_AUTOMATION_TARGET")
		var setting: Variant=raw.automation[store_id]
		if not setting is Dictionary or not _keys(setting,AUTO_KEYS) or not setting.enabled is bool or not TDServiceCatalog.integer(setting.budget_cents,0,10000000) or not TDServiceCatalog.integer(setting.spent_day,0,1000000) or (day>=0 and int(setting.spent_day)>day) or not TDServiceCatalog.integer(setting.spent_cents,0,10000000): return TDOutcome.new(false,"SUPPLIER_SAVE_AUTOMATION")
	return TDOutcome.new(true,"VALID")

func restore(raw: Variant) -> TDOutcome:
	var p:=owner_profile()
	if p!=null and not p._alive: return TDOutcome.new(false,"STALE_PROFILE")
	var checked:=validate_save(raw)
	if not checked.ok: return checked
	state=raw.duplicate(true)
	if int(state.schema_version)==1: state.schema_version=2;state.lines=[];state.line_serial=0
	_statuses.clear()
	return TDOutcome.new(true,"SUPPLIER_RESTORED")
