class_name TDBranchKitchenSession
extends TDShopSession
## A live branch kitchen uses the existing cooking/order rules. Inventory/lots
## are references to its Branches record; cash still belongs to the main ledger.
var network: TDPlayerBranches
var store_id: String
var cleanup: Callable
var _paid_tip: int=0

func _init(content: TDServiceCatalog, branches: TDPlayerBranches, identity: String) -> void:
	super(content,identity)
	network=branches;store_id=identity
	crew=TDRestaurantCrew.new()
	sync_store()

func sync_store() -> void:
	var p:=network.owner_profile()
	if p==null or not p._alive: return
	var store: Dictionary=network.state.stores[store_id]
	var day: int=int(p.shop._s.day)
	if int(_s.day)!=day:
		table_service.clear_on_restore()
		_s.day=day;_s.orders=[];_s.elapsed_sec=0.0;_s.ledger=[];_s.seen={}
	var staffed: bool = p.shop._s.phase=="OPEN" and not store.paused and p.employees.ready_for(store_id)
	_s.phase="OPEN" if (staffed or network.training_open(store_id)) and not store.daily.get("settled",false) else "PREPARE"
	_s.money_cents=int(p.shop._s.money_cents);_s.popularity=roundi(store.popularity)
	for id: String in catalog.config.costs:
		if not store.inventory.has(id):
			store.inventory[id]=0;store.basis[id]={"units":0,"value_cents":0};store.lots[id]=[]
	_s.inventory=store.inventory;_s.inventory_lots=store.lots
	if not store.has("kitchen_state"): store.kitchen_state={"version":1,"serial":0,"cold_foods":[]}
	_s.serial=int(store.kitchen_state.serial);_s.cold_foods=store.kitchen_state.cold_foods
	_s.order_serial=int(store.kitchen_state.get("order_serial",0))
	_s.mastery=p.shop._s.mastery;_s.mastery_dishes=p.shop._s.mastery_dishes
	_s.unlocked=p.shop._s.unlocked.duplicate();recipe_cultures=p.shop.recipe_cultures.duplicate()
	cuisine_id=store.cuisine_id;research_controlled=p.shop.research_controlled;cooking_reward=p.shop.cooking_reward
	for id: String in _s.menu: _s.menu[id].enabled=false
	for row: Dictionary in store.menu: _s.menu[row.id]={"enabled":true,"price_cents":int(row.price_cents)}
	crew.use_external(p.employees.assigned(store_id).filter(func(person:Dictionary)->bool:return person.role in ["cook","waiter"]),p.employees._record_growth)

func enqueue(recipe_id: String, family: String) -> bool:
	sync_store()
	if _s.phase!="OPEN" or pending_orders().size()>=6 or not can_make_order(recipe_id): return false
	var store: Dictionary=network.state.stores[store_id]
	_s.order_serial+=1
	store.kitchen_state.order_serial=int(_s.order_serial)
	var id:=day_namespace()+"o%d"%int(_s.order_serial)
	var price: int=int(_s.menu[recipe_id].price_cents)
	var hold:=network.owner_profile().commerce.society.reserve(family,price,id)
	if not hold.ok: return false
	var templates:=catalog.cooking.customer_definitions()
	var economy:=network.owner_profile().commerce
	var group_id: String=str(economy.society.state.households[family].group_id)
	var groups: Array=economy.config.groups.filter(func(g:Dictionary)->bool:return g.id==group_id)
	var customer: Dictionary=templates[int(groups[0].customer_template)%templates.size() if not groups.is_empty() else 0]
	customer.id=family;customer.name=str(groups[0].name) if not groups.is_empty() else "食客"
	customer.requirements=customer.get("requirements",[]).filter(func(r:Dictionary)->bool:return str(r.get("ingredient_id","")).is_empty())
	if not menu_available(recipe_id,customer) and menu_available(recipe_id):
		customer.requirements=customer.requirements.filter(func(r:Dictionary)->bool:return r.get("kind")!="flavor")
	if not menu_available(recipe_id,customer):
		economy.society.release(id)
		return false
	_s.orders.append(_prepare_arrival({"id":id,"recipe_id":recipe_id,"family_id":recipe_id,"branch_family":family,"branch_hold":id,"status":"WAITING","price_cents":price,"reference_cents":int(offer(recipe_id).reference_cents),"customer":customer,"arrival_sec":float(_s.elapsed_sec),"deadline_sec":float(_s.elapsed_sec)+maxf(240,float(catalog.config.settings.get("patience_sec",240))),"lane":-1,"reserved":{},"used":{},"prepaid_cents":0,"refunded_cents":0,"tip_cents":0,"dish_id":"","score":{},"plan":{}}))
	store.daily.reason="现场营业：落座点单，送到桌上才计收入"
	return true

func can_make_order(id: String) -> bool:
	if catalog.cooking.recipe_cuisine(id)!=cuisine_id: return false
	if not _s.menu.has(id) or not _s.menu[id].enabled: return false
	var needs:=catalog.material_needs(catalog.cooking,id)
	for item: String in needs:
		var held: int=0
		for order_row: Dictionary in pending_orders(): held+=int(catalog.material_needs(catalog.cooking,order_row.recipe_id).get(item,0))
		if available(item)-held<int(needs[item]): return false
	return true

func advance(seconds: float, paused: bool=false) -> TDOutcome:
	if not is_finite(seconds) or seconds<0: return TDOutcome.new(false,"INVALID_TIME")
	if paused: return TDOutcome.new(true,"IDLE")
	sync_store()
	_tick_dining(0)
	var remaining:=seconds
	while remaining>0:
		var span:=next_boundary(remaining)
		_s.elapsed_sec+=span
		for row: Dictionary in pending_orders():
			if float(row.deadline_sec)<=float(_s.elapsed_sec): cancel_order(row.id,"TIMED_OUT")
		_tick_dining(span)
		remaining=maxf(0.0,remaining-span)
	return TDOutcome.new(true,"ADVANCED")

func next_boundary(maximum: float) -> float:
	var span:=maximum
	for row: Dictionary in pending_orders(): span=minf(span,maxf(.000001,float(row.deadline_sec)-float(_s.elapsed_sec)))
	if dining_boundary.is_valid(): span=minf(span,float(dining_boundary.call(span)))
	return span

func _complete_delivery(id: String, dish: Dictionary) -> TDOutcome:
	var row:=order(id)
	var plated: Dictionary=dish if crew==null else crew.apply_dish(dish,row.get("customer",{}))
	var check:=can_deliver(id,plated)
	if not check.ok: return check
	var society:=network.owner_profile().commerce.society
	_paid_tip=0
	if not dish.get("failed_dish",false):
		var tip:=roundi(float(row.price_cents)*maxf(0,float(check.data.satisfaction)-80)/200.0*crew.tip_scale())
		var paid:=society.pay(row.branch_hold,tip)
		if not paid.ok: return paid
		_paid_tip=int(paid.data.tip_cents)
	else: society.release(row.branch_hold)
	var result:=super._complete_delivery(id,dish)
	if result.ok:
		var store: Dictionary=network.state.stores[store_id]
		network.record_completed(store.daily, clampf(float(result.data.score.satisfaction) / 100.0, 0.0, 1.0))
		network._pay_debt(store)
		_s.money_cents=int(network.owner_profile().shop._s.money_cents)
	return result

func cancel_order(id: String, reason: String="CANCELLED") -> TDOutcome:
	var row:=order(id)
	var result:=super.cancel_order(id,reason)
	if result.ok and row.has("branch_hold"):
		network.owner_profile().commerce.society.release(row.branch_hold)
	return result

func _apply_popularity(_delta: int, item: Dictionary) -> void:
	item.popularity_delta = 0

func refund(id: String) -> TDOutcome:
	if network.state.stores[store_id].daily.get("settled", false):
		return TDOutcome.new(false, "NOT_OPEN")
	return super.refund(id)

func material_cost_basis() -> Dictionary:
	return network.state.stores[store_id].basis

func _record(kind: String, cents: int, inventory_delta: Dictionary, reference: String, extra: Dictionary={}) -> void:
	var p:=network.owner_profile();var store: Dictionary=network.state.stores[store_id]
	_s.serial+=1;store.kitchen_state.serial=int(_s.serial)
	if kind=="tip":
		cents=_paid_tip
		var index:=_order_index(reference)
		if index>=0: _s.orders[index].tip_cents=cents
	if kind=="refund_served": p.commerce.society.refund(str(order(reference).get("branch_hold","")),-cents)
	if cents!=0:
		var paid:=network._cash(cents,"branch:kitchen:%s:%d:%d"%[store_id,_s.day,_s.serial],"分店现场 · "+kind,store_id)
		assert(paid.ok)
		if kind in ["prepayment","tip","refund_served"]: store.daily.sales_cents+=cents
		if kind == "prepayment": store.daily.paid_orders = int(store.daily.get("paid_orders", 0)) + 1
		elif kind == "refund_served": store.daily.paid_orders = maxi(0, int(store.daily.get("paid_orders", 0)) - 1)
	for id: String in inventory_delta:
		var units: int=int(inventory_delta[id])
		if units<0: store.daily.consumed_cents+=network._take(store,id,-units)
		elif units>0:
			store.inventory[id]=int(store.inventory.get(id,0))+units
			if not store.basis.has(id): store.basis[id]={"units":0,"value_cents":0}
			store.basis[id].units+=units
			TDFoodStock.record_add(store.lots,id,units,int(_s.day),int(stock_rules.get(id,{}).get("shelf_days",3)),extra)
			if kind=="stock_return":
				var value := int(extra.inventory_cost_cents)
				store.basis[id].value_cents+=value
				store.daily.consumed_cents=maxi(0,int(store.daily.consumed_cents)-value)
	_s.money_cents=int(p.shop._s.money_cents)
	_s.ledger.append({"id":"%s:txn-%d"%[store_id,_s.serial],"day":int(_s.day),"kind":kind,"cents":cents,"inventory_delta":inventory_delta.duplicate(true),"reference":reference,"extra":extra.duplicate(true)})

func settle_day() -> TDOutcome:
	# Branches settles its rent/payroll/tax exactly once; this kitchen has no second day ledger.
	_s.phase="SETTLED"
	return TDOutcome.new(true,"SETTLED")

func finish_service() -> TDOutcome:
	if cleanup.is_valid():
		var cleaned: TDOutcome=cleanup.call()
		if not cleaned.ok: return cleaned
	table_service.clear_for_night()
	for row: Dictionary in pending_orders(): cancel_order(row.id,"TIMED_OUT")
	_s.phase="SETTLED"
	return TDOutcome.new(true,"SETTLED")
