extends RefCounted
## Fixed supplier for the brand. Plans, invoices and credit belong to one save slot.
const HOME := "player_diner"
const UNLOCK_LEVEL := 3
const DEFAULT_PORTIONS := 5
const MAX_PORTIONS := 99
const BASE_CREDIT := 15000
const CREDIT_PER_LEVEL := 5000
var owner: WeakRef
var state := {"version":1,"enabled":false,"debt":0,"suspended":false,"last_invoice":0,
	"invoice_day":0,"processed_day":0,"menu_day":0,"plans":{},"portions":{},"repayments":0,"store_debts":{}}

func _init(profile: TDGameProfile) -> void:
	owner = weakref(profile)

func level() -> int:
	var p: TDGameProfile = owner.get_ref()
	return int(p.progression.progress().level)

func credit() -> int:
	return 0 if level() < UNLOCK_LEVEL else BASE_CREDIT + (level() - UNLOCK_LEVEL) * CREDIT_PER_LEVEL

func set_enabled(value: bool) -> TDOutcome:
	var p: TDGameProfile = owner.get_ref()
	if p == null or not p._alive: return TDOutcome.new(false,"STALE_PROFILE")
	if value and level() < UNLOCK_LEVEL: return TDOutcome.new(false,"SUPPLY_LOCKED","品牌达到%d级后解锁。"%UNLOCK_LEVEL)
	state.enabled = value
	return TDOutcome.new(true,"SUPPLY_SWITCH","已开启次晨配送。" if value else "已关闭次晨配送。")

func evening() -> bool:
	var p: TDGameProfile = owner.get_ref()
	return p.shop.snapshot().phase == "SETTLED" or p.characters.clock.minute >= 18*60

func store_ids() -> Array:
	var p: TDGameProfile = owner.get_ref()
	var ids: Array = [HOME]
	var day := p.world.day
	for id: String in p.branches.state.stores:
		if p.branches.funded(id) and int(p.branches.state.stores[id].start_day)<=day: ids.append(id)
	return ids

func dishes(store: String) -> Array:
	var p: TDGameProfile = owner.get_ref()
	if store == HOME: return p.main_menu_rows()
	var branch: Dictionary = p.branches.state.stores.get(store,{})
	if branch.is_empty(): return []
	var rows := p.branches.recipes(branch.cuisine_id)
	var active := {}
	for dish: Dictionary in branch.menu: active[dish.id] = dish.price_cents
	for row: Dictionary in rows:
		row.enabled = active.has(row.id)
		row.price_cents = active.get(row.id,row.price_cents)
	return rows

func quantities(store: String, rows: Array) -> Dictionary:
	if state.plans.has(store): return state.plans[store].duplicate()
	var counts := {}
	for row: Dictionary in rows:
		if row.enabled: counts[row.id] = state.portions.get(store,{}).get(row.id,DEFAULT_PORTIONS)
	return counts

func ingredients(store: String, counts: Dictionary, rows: Array) -> Dictionary:
	var p: TDGameProfile = owner.get_ref()
	var needs := {}
	for row: Dictionary in rows:
		if not counts.has(row.id): continue
		var recipe: Dictionary
		if store == HOME:
			recipe = p.service.material_needs(p.shop.profile_for({"recipe_id":row.id}),p.shop.family_id(row.id))
		else: recipe = row.ingredients
		for item: String in recipe:
			needs[item] = int(needs.get(item,0)) + int(recipe[item])*int(counts[row.id])
	return needs

func book(store: String, counts: Dictionary) -> TDOutcome:
	var p: TDGameProfile = owner.get_ref()
	if p == null or not p._alive: return TDOutcome.new(false,"STALE_PROFILE")
	if not state.enabled or level() < UNLOCK_LEVEL: return TDOutcome.new(false,"SUPPLY_DISABLED","请先开启供应商。")
	if not evening(): return TDOutcome.new(false,"SUPPLY_NOT_EVENING","18:00 后或打烊后可预订明日菜单。")
	if store not in store_ids(): return TDOutcome.new(false,"UNKNOWN_SUPPLY_TARGET")
	var rows := dishes(store)
	if counts.is_empty(): return TDOutcome.new(false,"EMPTY_MENU","至少为一道菜填写份数。")
	if store != HOME and counts.size()>20: return TDOutcome.new(false,"INVALID_MENU","分店最多可选20道菜。")
	var ids := rows.map(func(row: Dictionary)->String: return row.id)
	for id: Variant in counts:
		if id not in ids or not TDServiceCatalog.integer(counts[id],1,MAX_PORTIONS): return TDOutcome.new(false,"INVALID_MENU","请选择已掌握的菜品并输入有效份数。")
	for units: int in ingredients(store,counts,rows).values():
		if units>1000000: return TDOutcome.new(false,"STOCK_CAPACITY","此菜单所需原料超出单店库存容量，请减少份数。")
	state.plans[store] = counts.duplicate()
	return TDOutcome.new(true,"MENU_BOOKED","明日菜单已记录，货到结算。")

func holds_menu(store: String) -> bool:
	var p: TDGameProfile = owner.get_ref()
	return state.enabled and int(state.menu_day)==p.world.day and state.portions.has(store)

func _unit_price(p: TDGameProfile, destination: String, item: String) -> int:
	var best := 0
	for town: String in TDSupplierNetwork.TOWNS:
		if not TDMaterialCatalog.supplies(town,item): continue
		var distance := p.suppliers.distance(town,destination)
		var price := maxi(1,ceili(float(p.commerce.state.markets[town].price[item])*(1.0+distance*float(p.suppliers.config.distance_price_rate))))
		if town==destination: return price
		if best==0 or price<best: best=price
	return best

func _shipment(p: TDGameProfile, store: String, needs: Dictionary, inventory: Dictionary, day: int) -> int:
	var destination: String = p.commerce.state.home if store==HOME else p.branches.state.stores[store].town_id
	var invoice := 0
	for item: String in needs:
		var stock := int(inventory.get(item,0))
		var missing := mini(1000000,int(needs[item]))-stock
		if missing<=0: continue
		var unit_price := _unit_price(p,destination,item)
		if unit_price<=0: continue
		var pack := maxi(1,int(p.shop.stock_info(item).pack_units))
		var units := mini(1000000-stock,ceili(float(missing)/pack)*pack)
		var cost := maxi(1,TDShopSession.amount_cost(units,unit_price))
		var token := "menu-supply:%d:%s:%s"%[day,store,item]
		var delivered := p.shop.receive_supply({item:units},token,cost) if store==HOME else p.branches.receive_supply(store,{item:units},{item:cost},token)
		if delivered.ok: invoice+=cost
	return invoice

func morning() -> void:
	var p: TDGameProfile = owner.get_ref()
	var business := p.shop.snapshot()
	var day := int(business.day)
	if business.phase!="PREPARE" or day<=int(state.processed_day): return
	state.processed_day = day
	if not state.enabled or level()<UNLOCK_LEVEL:
		state.plans.clear()
		return
	state.menu_day = day
	var next_portions := {}
	var invoice := 0
	for store: String in store_ids():
		var branch: Dictionary = p.branches.state.stores.get(store,{})
		if branch.get("paused",false) and not state.plans.has(store): continue
		var rows := dishes(store)
		var counts := quantities(store,rows)
		if counts.is_empty(): continue
		if state.plans.has(store):
			var chosen := []
			for row: Dictionary in rows:
				if counts.has(row.id): chosen.append({"id":row.id,"price_cents":row.price_cents})
			var menu := p.shop.configure_menu(chosen) if store==HOME else p.branches.configure_store(store,chosen,branch.budget_cents,branch.paused)
			if not menu.ok: continue
		next_portions[store] = counts
		if state.suspended or branch.get("paused",false): continue
		var needs := ingredients(store,counts,rows)
		var cost := _shipment(p,store,needs,business.inventory if store==HOME else branch.inventory,day)
		if cost>0:
			invoice += cost
			var paid := _pay(p,store,cost,"menu-invoice:%d:%s"%[day,store],"次晨供货")
			if cost>paid:
				state.store_debts[store] = int(state.store_debts.get(store,0))+cost-paid
				state.debt = int(state.debt)+cost-paid
	state.portions = next_portions
	state.plans.clear()
	if invoice<=0: return
	state.last_invoice = invoice
	state.invoice_day = day
	state.suspended = int(state.debt)>=credit()

func _pay(p: TDGameProfile, store: String, amount: int, token: String, label: String) -> int:
	var available := mini(amount,maxi(0,int(p.shop.snapshot().money_cents)))
	var paid := 0
	while paid<available:
		var part := mini(100000000,available-paid)
		if not p.shop.branch_adjustment(-part,"%s:%d"%[token,paid],label,store).ok: break
		p.commerce.society.state.sectors.market += part
		if store!=HOME: p.branches.note_supply_purchase(store,part)
		paid += part
	return paid

func repay() -> TDOutcome:
	var p: TDGameProfile = owner.get_ref()
	if p == null or not p._alive: return TDOutcome.new(false,"STALE_PROFILE")
	if int(state.debt)<=0: return TDOutcome.new(false,"NO_DEBT","没有待还货款。")
	var paid := 0
	for store: String in state.store_debts.keys():
		var owed := int(state.store_debts[store])
		var part := _pay(p,store,owed,"menu-repay:%d:%s"%[state.repayments,store],"偿还供应商欠款")
		paid += part
		if part==owed: state.store_debts.erase(store)
		else:
			state.store_debts[store] = owed-part
			break
	if paid<=0: return TDOutcome.new(false,"INSUFFICIENT_FUNDS","当前没有可用于还款的金币。")
	state.repayments = int(state.repayments)+1
	state.debt = int(state.debt)-paid
	if int(state.debt)==0: state.suspended=false
	return TDOutcome.new(true,"SUPPLY_REPAID","已偿还 %.2f 金币。"%(paid/100.0))

static func valid(raw: Variant, stores: Dictionary, menu: Dictionary, day: int) -> bool:
	if not raw is Dictionary or raw.get("version")!=1 or not raw.get("enabled") is bool or not raw.get("suspended") is bool: return false
	for key: String in ["last_invoice","debt","repayments"]:
		if not TDServiceCatalog.integer(raw.get(key),0,9007199254740991): return false
	if raw.suspended and int(raw.debt)==0: return false
	if not raw.get("store_debts") is Dictionary: return false
	var debt_sum := 0
	for store: Variant in raw.store_debts:
		if not stores.has(store) or not TDServiceCatalog.integer(raw.store_debts[store],1,9007199254740991): return false
		debt_sum+=int(raw.store_debts[store])
	if debt_sum!=int(raw.debt): return false
	if not TDServiceCatalog.integer(raw.get("processed_day"),0,day) or not TDServiceCatalog.integer(raw.get("invoice_day"),0,int(raw.processed_day)): return false
	if not TDServiceCatalog.integer(raw.get("menu_day"),0,int(raw.processed_day)): return false
	for key: String in ["plans","portions"]:
		if not raw.get(key) is Dictionary: return false
		for store: Variant in raw[key]:
			if not stores.has(store): return false
			var counts: Variant=raw[key][store]
			if not counts is Dictionary or counts.is_empty() or (store!=HOME and counts.size()>20): return false
			for dish: Variant in counts:
				if not menu.has(dish) or not TDServiceCatalog.integer(counts[dish],1,MAX_PORTIONS): return false
	return true
