class_name TDBusinessExpansion
extends RefCounted
## Purchases refer to building-supplied commercial parcels. No geometry is invented here.
var config: Dictionary = {}
var state: Dictionary = {}

func _init(settings: Dictionary = {}) -> void:
	config=settings.duplicate(true)
	state={"schema_version":1,"parcels":{},"serial":0,"last_review":{},"events":[]}

func register(town: String, parcels: Array, geography: TDEconomicGeography, firms: Array) -> TDOutcome:
	if state.parcels.has(town): return TDOutcome.new(true,"ALREADY_REGISTERED")
	var proposed: Dictionary={}
	for parcel: Dictionary in parcels:
		if proposed.has(parcel.id) or not parcel.get("tradable") is bool or int(parcel.w)<=0 or int(parcel.h)<=0: return TDOutcome.new(false,"INVALID_COMMERCIAL_PARCEL")
		var value:=parcel.duplicate(true)
		var price: int=0
		for x: int in range(int(parcel.x),int(parcel.x+parcel.w)):
			for y: int in range(int(parcel.y),int(parcel.y+parcel.h)): price+=int(geography.cell(Vector2i(x,y)).land_value_cents)
		value.land_cents=price;value.version=1;value.owner_id="";value.store_id=""
		var index: int=int(parcel.initial_store_index)
		if index>=0 and index<firms.size():
			value.owner_id=firms[index].owner_id;value.store_id=firms[index].id
			firms[index].parcel_id=parcel.id
			firms[index].travel_minutes=float(geography.cell(Vector2i(parcel.x,parcel.y)).travel_minutes.residential)
		proposed[parcel.id]=value
	state.parcels[town]=proposed
	return TDOutcome.new(true,"PARCELS_REGISTERED")

func candidates(town: String) -> Array:
	return state.parcels.get(town,{}).values().filter(func(p:Dictionary)->bool:return p.tradable and p.owner_id.is_empty())

func buy(town: String, parcel_id: String, expected_version: int, firm: Dictionary, all_firms: Array, society: TDCommunitySociety, day: int) -> TDOutcome:
	var parcel: Dictionary=state.parcels.get(town,{}).get(parcel_id,{})
	if parcel.is_empty() or not parcel.tradable or not parcel.owner_id.is_empty(): return TDOutcome.new(false,"PROTECTED_OR_OWNED_PARCEL")
	if int(parcel.version)!=expected_version: return TDOutcome.new(false,"STALE_PARCEL")
	if all_firms.filter(func(f:Dictionary)->bool:return f.owner_id==firm.owner_id).size()>=int(config.max_stores_per_owner): return TDOutcome.new(false,"EXPANSION_LIMIT")
	var total:=int(parcel.land_cents)+int(config.construction_cents)
	var earnings: int=0
	for row: Dictionary in firm.history: earnings+=mini(int(row.get("profit_cents",0)),int(row.get("cash_flow_cents",row.get("profit_cents",0))))
	if int(firm.profitable_reviews)<int(config.profitable_reviews) or firm.history.size()<int(config.review_days) or earnings/int(config.review_days)*int(config.horizon_days)/2<=total: return TDOutcome.new(false,"NO_EXPECTED_PAYBACK")
	var reserve:=int(config.working_cash_days)*(int(society.config.npc.daily_fixed_cents)+int(society.config.society.npc_wage_cents)+int(society.config.npc.target_portions)*500)
	if int(firm.cash_cents)<total+reserve or int(firm.debt_cents)>0: return TDOutcome.new(false,"EXPANSION_FUNDS")
	var id: String="npc-store:%s:branch:%d"%[town,int(state.serial)+1]
	var hired:=society.hire(id,town,int(config.staff_per_store),int(society.config.society.npc_wage_cents))
	if not hired.ok: return hired
	var next: Dictionary=firm.duplicate(true)
	next.merge({"id":id,"name":"%s分店"%str(firm.get("name","街坊餐馆")),"parcel_id":parcel_id,"cash_cents":reserve,"debt_cents":0,"inventory":{},"cost_basis":{},"history":[],"served":0,"last_served":0,"receipts_cents":0,"purchase_cents":0,"paid_fixed_cents":0,"consumed_cents":0,"wage_expense_cents":0,"tax_cents":0,"tax_due_cents":0,"open_day":day+int(config.construction_days),"capacity":mini(int(parcel.capacity),int(config.store_capacity)),"profitable_reviews":0,"last_profit_cents":0,"status":"construction","travel_minutes":float(firm.travel_minutes)+2.0},true)
	firm.cash_cents-=total+reserve
	society.state.sectors.land+=int(parcel.land_cents);society.state.sectors.construction+=int(config.construction_cents)
	parcel.owner_id=firm.owner_id;parcel.store_id=id;parcel.version+=1
	all_firms.append(next);state.serial+=1
	var event: Dictionary={"day":day,"town_id":town,"store_id":id,"owner_id":firm.owner_id,"parcel_id":parcel_id,"type":"construction","cost_cents":total,"open_day":next.open_day}
	state.events.append(event)
	while state.events.size()>32: state.events.pop_front()
	return TDOutcome.new(true,"NPC_CONSTRUCTION_STARTED","",event.duplicate(true))

func review(town: String, firms: Array, society: TDCommunitySociety, day: int) -> void:
	if day%int(config.review_days)!=0 or int(state.last_review.get(town,0))>=day: return
	state.last_review[town]=day
	# One investment at most per town and week. Stable rotating order avoids first-owner monopoly.
	var original:=firms.duplicate()
	var ordered: Array=[]
	for offset: int in original.size(): ordered.append(original[(offset+day/int(config.review_days))%original.size()])
	for firm: Dictionary in ordered:
		if firm.status!="open" or firm.history.size()<int(config.review_days): continue
		var profit: int=0
		for row: Dictionary in firm.history: profit+=mini(int(row.get("profit_cents",0)),int(row.get("cash_flow_cents",row.get("profit_cents",0))))
		firm.profitable_reviews=int(firm.profitable_reviews)+1 if profit>0 else 0
		if int(firm.profitable_reviews)<int(config.profitable_reviews): continue
		var lots:=candidates(town)
		if lots.is_empty(): continue
		lots.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return int(a.land_cents)<int(b.land_cents))
		var lot: Dictionary=lots[0]
		# New outlets share demand; use half observed cash earnings, not a new population grant.
		var forecast: int=profit/int(config.review_days)*int(config.horizon_days)/2
		if forecast<=int(lot.land_cents)+int(config.construction_cents): continue
		var bought:=buy(town,str(lot.id),int(lot.version),firm,firms,society,day)
		if bought.ok: break

func presentation(town: String, firms: Array, day: int) -> Dictionary:
	var result: Dictionary={}
	for parcel: Dictionary in state.parcels.get(town,{}).values():
		if parcel.owner_id.is_empty(): continue
		var match_firms:=firms.filter(func(f:Dictionary)->bool:return f.id==parcel.store_id)
		if match_firms.is_empty(): continue
		var firm: Dictionary=match_firms[0]
		result[parcel.id]={"owner_id":parcel.owner_id,"store_id":parcel.store_id,"name":str(firm.name)+( " · 施工" if int(firm.open_day)>day else ""),"construction":int(firm.open_day)>day}
	return result

func validate(raw: Variant, towns: Array, competitors: Dictionary) -> TDOutcome:
	if not raw is Dictionary or raw.get("schema_version")!=1 or not raw.get("parcels") is Dictionary or not raw.get("last_review") is Dictionary or not raw.get("events") is Array or raw.events.size()>32 or not TDServiceCatalog.integer(raw.get("serial"),0,1000000): return TDOutcome.new(false,"INVALID_EXPANSION")
	var occupied: Dictionary={}
	for town: Variant in raw.last_review:
		if town not in towns or not TDServiceCatalog.integer(raw.last_review[town],0,1000000000): return TDOutcome.new(false,"INVALID_EXPANSION_REVIEW")
	for event: Variant in raw.events:
		if not event is Dictionary or event.get("town_id") not in towns or event.get("type")!="construction" or not event.get("store_id") is String or not event.get("owner_id") is String or not event.get("parcel_id") is String: return TDOutcome.new(false,"INVALID_EXPANSION_EVENT")
		for field: String in ["day","cost_cents","open_day"]:
			if not TDServiceCatalog.integer(event.get(field),0,1000000000): return TDOutcome.new(false,"INVALID_EXPANSION_EVENT")
	for town: Variant in raw.parcels:
		if town not in towns or not raw.parcels[town] is Dictionary or raw.parcels[town].size()>6: return TDOutcome.new(false,"INVALID_PARCELS")
		for id: Variant in raw.parcels[town]:
			var p: Variant=raw.parcels[town][id]
			if not p is Dictionary or p.get("id")!=id or p.get("parent_id") not in ["competitor","commercial_street"] or not p.get("tradable") is bool or not p.get("owner_id") is String or not p.get("store_id") is String: return TDOutcome.new(false,"INVALID_PARCEL")
			for field: String in ["x","y","w","h","capacity","version","land_cents"]:
				if not TDServiceCatalog.integer(p.get(field),0,100000000): return TDOutcome.new(false,"INVALID_PARCEL",field)
			if int(p.w)<1 or int(p.h)<1 or int(p.x+p.w)>41 or int(p.y+p.h)>41: return TDOutcome.new(false,"INVALID_PARCEL_GEOMETRY")
			if not p.owner_id.is_empty():
				if occupied.has(p.store_id): return TDOutcome.new(false,"DUPLICATE_PROPERTY")
				var stores: Array=competitors[town].filter(func(f:Dictionary)->bool:return f.id==p.store_id and f.owner_id==p.owner_id and f.parcel_id==id)
				if stores.size()!=1: return TDOutcome.new(false,"INVALID_PROPERTY_OWNER")
				occupied[p.store_id]=true
	return TDOutcome.new(true,"VALID_EXPANSION")
