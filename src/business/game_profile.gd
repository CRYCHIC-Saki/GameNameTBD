class_name TDGameProfile
extends RefCounted
## One profile owns one business ledger, research graph and persistent world.
var slot_id: String = ""
var title: String = "小镇食堂"
var updated_at: int = 0
var revision: int = 0
var imported_legacy: bool = false
var service := TDServiceCatalog.new()
var shop: TDShopSession
var world := TDPhase3Session.new()
var research: TDResearchSession
var layout: TDRestaurantLayout
var persistence: Callable
var _alive: bool = true
var error := TDOutcome.new(true)
var commerce: TDWorldEconomy
var progression := TDLevelProgression.new()
var progression_error := TDOutcome.new(true)
var residence:Dictionary={}

func _init() -> void:
	error=service.load_file()
	if not error.ok: return
	error=TDResearchRuntime.install(service)
	if not error.ok: return
	var definitions:=TDResearchCatalog.new()
	error=definitions.load_file()
	if not error.ok: return
	research=TDResearchSession.new(definitions)
	error=world.load_default()
	if not error.ok: return
	world.attach_research(research)
	shop=TDShopSession.new(service,"",101,world.research_service_ids())
	shop.cooking_reward=_reward_cooking
	world.factory_products_provider=_factory_products
	world.factory_item_provider=_factory_item
	world.build_home("chinese")
	world.scaled_interior=false # The supplied persistent layout has priority.
	var furniture:=TDRestaurantCatalog.new()
	error=furniture.load_file()
	if not error.ok: return
	var grid:=world.interior_grid()
	layout=TDRestaurantLayout.make_sized(furniture,grid.x,grid.y,"chinese")
	if layout==null: error=TDOutcome.new(false,"INVALID_LAYOUT");return
	error=layout.furnish_player_home()
	if not error.ok: return
	shop.crew=layout.crew
	research.save_sink=_research_candidate
	research.changed.connect(_sync_recipes)
	commerce=TDWorldEconomy.new(service.config.costs,world.home_town_id if not world.home_town_id.is_empty() else world.town_id,int(shop.snapshot().seed))
	if not commerce.error.ok: error=commerce.error;return
	_wire_commerce()
	if not progression.error.ok: error=progression.error;return
	initialize_progression()
	shop.day_settled.connect(_on_day_settled)
	error=initialize_residence()

func initialize_residence() -> TDOutcome:
	var plot:=world.town_map.choose_cottage()
	if plot.is_empty(): return TDOutcome.new(false,"NO_COTTAGE_LOCATION")
	var installed:=world.town_map.install_cottage(plot)
	if not installed.ok: return installed
	residence={"schema_version":1,"anchor":"cottage_bed","plot":plot}
	return installed

func initialize_progression(migrated: bool = false) -> void:
	var day := int(shop.snapshot().day)+(1 if shop.snapshot().phase=="SETTLED" else 0)
	progression.start(day,{"player_diner":{"popularity":float(shop.snapshot().popularity),"awareness":float(commerce.state.awareness)*100.0}},migrated)

func level_daily_report() -> TDOutcome:
	# Formal player branches will supply the full same-day portfolio here. NPC firms and
	# the old independent world branch ledger are deliberately not player income.
	if not _alive or shop.snapshot().phase!="SETTLED": return TDOutcome.new(false,"NOT_SETTLED")
	var day := int(shop.snapshot().day)
	var book: Dictionary=shop.day_summary().economy
	if book.is_empty() or int(book.day)!=day: return TDOutcome.new(false,"MISSING_LEVEL_BUSINESS_BOOK")
	var before: Dictionary=progression.snapshot().baselines.get("player_diner",{})
	if before.is_empty(): return TDOutcome.new(false,"MISSING_LEVEL_BASELINE")
	return TDOutcome.new(true,"LEVEL_REPORT","",{"day":day,"stores":[{"store_id":"player_diner","scale_milli":1000,"profit_cents":int(book.profit_cents),"popularity_before":float(before.popularity),"popularity_after":float(shop.snapshot().popularity),"awareness_before":float(before.awareness),"awareness_after":float(commerce.state.awareness)*100.0}]})

func _on_day_settled(_day: int) -> void:
	progression_error=settle_progression()

func settle_progression() -> TDOutcome:
	if not _alive: return TDOutcome.new(false,"STALE_PROFILE")
	if shop.snapshot().phase!="SETTLED": return TDOutcome.new(true,"NOT_DUE")
	if int(progression.snapshot().last_day)==int(shop.snapshot().day): return TDOutcome.new(true,"ALREADY_APPLIED")
	if not research._active.is_empty(): return TDOutcome.new(false,"RESEARCH_BUSY")
	var report := level_daily_report()
	if not report.ok: return report
	var staged := TDLevelProgression.new(progression.config)
	var restored := staged.restore(progression.snapshot())
	if not restored.ok: return restored
	var result := staged.settle(report.data)
	if not result.ok: return result
	# Stage rewards through the existing rule, without the live save_sink. Both domains
	# enter the same profile package; a scene refresh never invokes the reward rule.
	var staged_research := TDResearchSession.new(research.catalog)
	restored=staged_research.restore(research.snapshot())
	if not restored.ok: return restored
	for reward: Dictionary in result.data.rewards:
		var granted := staged_research.grant_inspiration(str(reward.grant_id),int(reward.inspiration))
		if not granted.ok: return granted
	var checked := progression.validate_save(staged.snapshot())
	if not checked.ok: return checked
	progression.restore(staged.snapshot())
	research.restore(staged_research.snapshot())
	progression_error=TDOutcome.new(true)
	return result

func pending_level_events() -> Array:
	return progression.pending_events() if _alive else []

func acknowledge_level_event(event_id: String) -> TDOutcome:
	if not _alive or not at_boundary(): return TDOutcome.new(false,"NOT_AT_BOUNDARY")
	var before := progression.snapshot()
	var result := progression.acknowledge(event_id)
	if not result.ok or result.code=="ALREADY_APPLIED": return result
	var saved := save()
	if not saved.ok: progression.restore(before);return saved
	return result

func _wire_commerce() -> void:
	shop.commerce=commerce
	world.factory_products_provider=_factory_products;world.factory_item_provider=_factory_item
	commerce.attach_cash_baseline(int(shop.snapshot().money_cents))
	for town_id: String in commerce.config.active_towns:
		var map:=world.town_map if town_id==commerce.state.home else TDTownMap.new()
		if town_id!=commerce.state.home:
			var generated:=map.build_economic_layout(world.catalog,TDTownMap.seed_of(town_id))
			if not generated.ok: error=generated;return
		commerce.configure_parcels(town_id,map.plots,map.commercial_parcels())
	sync_commercial_map()
	commerce.attach_map(world.town_map.plots)
	for id: String in research.catalog.nodes:
		var runtime:=research.catalog.runtime_id(id)
		var recipe:=world.catalog.kitchen_recipe_id(runtime)
		if not recipe.is_empty(): shop.recipe_cultures[recipe]={"cn":"chinese","eu":"continental","jp":"japanese","sea":"southeast_asian","lat":"latin_american"}.get(research.catalog.node(id).cuisine_id,research.catalog.node(id).cuisine_id)

func _factory_products(group: String) -> Array:
	var rows: Array=[]
	for id: String in shop.purchase_ids():
		if shop.stock_info(id).group==group: rows.append({"id":id,"hours":1.0 if group=="meat" else .5})
	return rows

func _factory_item(id: String) -> Dictionary:
	if not service.config.costs.has(id): return {}
	for food: Dictionary in service.cooking.data().ingredients:
		if food.id==id: return {"id":id,"name":food.name,"cost":maxi(1,ceili(float(service.config.costs[id])/100)),"unit":shop.stock_info(id).unit}
	return {}

func sync_commercial_map() -> TDOutcome:
	return world.town_map.apply_commercial_occupancy(commerce.expansion.presentation(commerce.state.home,commerce.state.competitors[commerce.state.home],int(commerce.state.day)))

func bank_action(action: String, cents: int, token: String) -> TDOutcome:
	if not _alive or not at_boundary(): return TDOutcome.new(false,"NOT_AT_BOUNDARY")
	var before:=commerce.snapshot()
	var result:=commerce.society.bank.transact("player",action,cents,int(shop.snapshot().money_cents),int(shop.snapshot().day),token)
	if not result.ok: return result
	var moved:=shop.bank_adjustment(int(result.data.cash_delta_cents),token,action)
	if not moved.ok: commerce.restore(before);return moved
	return result

func at_boundary() -> bool:
	return shop!=null and shop.snapshot().phase in ["PREPARE","SETTLED"]

func can_leave_shop() -> bool:
	return at_boundary()

func _reward_cooking(day: int, id: String, score: float) -> void:
	var runtime:=world.catalog.dish_id_for_kitchen(id)
	if not runtime.is_empty(): research.record_cooking(day,runtime,score)

func _sync_recipes() -> void:
	if not _alive: return
	install_legacy(service,world.research_service_ids())
	for id: String in world.research_service_ids():
		if not shop.is_unlocked(id): shop.grant_recipe(id)

func snapshot(candidate: Dictionary = {}) -> Dictionary:
	var progress:=research.snapshot() if candidate.is_empty() else candidate.duplicate(true)
	var business:=shop.snapshot()
	# Candidate research is committed before its changed signal. Include new recipes atomically.
	for node_id: String in progress.unlocked:
		var runtime:=research.catalog.runtime_id(node_id)
		var id:=world.catalog.kitchen_recipe_id(runtime)
		if id.is_empty() or service.offer(id).is_empty() or id in business.unlocked: continue
		business.unlocked.append(id)
		business.menu[id]={"enabled":true,"price_cents":int(service.offer(id).reference_cents)}
		business.fame[id]=0
	var state:=TDWorldSnapshot.capture(world)
	state.day=int(business.day);state.money=int(business.money_cents)/100
	state.day_phase="evening" if business.phase=="SETTLED" else "morning"
	progress.world_time={"day":int(business.day),"phase":state.day_phase,"spent":state.free_spent}
	return {"schema_version":4,"kind":"town-diner-profile","slot_id":slot_id,"title":title,"updated_at":updated_at,"revision":revision,"imported_legacy":imported_legacy,"shop":business,"research":progress,"world":state,"layout":layout.to_dict(),"economy":commerce.snapshot(),"progression":progression.snapshot(),"residence":residence.duplicate(true)}

func save(candidate: Dictionary = {}) -> TDOutcome:
	if not _alive: return TDOutcome.new(false,"STALE_PROFILE")
	if not at_boundary(): return TDOutcome.new(false,"NOT_AT_BOUNDARY","营业中不能存档，请打烊后保存。")
	if not persistence.is_valid(): return TDOutcome.new(false,"NO_STORAGE")
	# Research's candidate callback must never recurse into another live reward commit.
	if not candidate.is_empty() and shop.snapshot().phase=="SETTLED" and int(progression.snapshot().last_day)!=int(shop.snapshot().day): return TDOutcome.new(false,"PROGRESSION_PENDING")
	if candidate.is_empty():
		var settled := settle_progression()
		if not settled.ok: return settled
	var data:=snapshot(candidate)
	data.updated_at=int(Time.get_unix_time_from_system()*1000000.0);data.revision=revision+1
	var result: TDOutcome=persistence.call(slot_id,data)
	if result.ok: updated_at=data.updated_at;revision=data.revision
	return result

func _research_candidate(candidate: Dictionary) -> TDOutcome:
	if not _alive: return TDOutcome.new(false,"STALE_PROFILE")
	if not at_boundary(): return TDOutcome.new(true,"BUFFERED_UNTIL_DAY_BOUNDARY")
	return save(candidate)

func buy(cart: Dictionary) -> TDOutcome:
	if not can_leave_shop(): return TDOutcome.new(false,"SHOP_OPEN","营业中不能外出采购。")
	if shop.snapshot().phase!="PREPARE": return TDOutcome.new(false,"NOT_PREPARING")
	var quote:=commerce.quote(commerce.state.home,cart)
	if not quote.ok: return quote
	var token: String="market:%s:%d"%[shop.snapshot().run_id,int(shop.snapshot().serial)+1]
	var prices: Dictionary={}
	for item: String in quote.data.rows: prices[item]=int(quote.data.rows[item].price_cents)
	var before:=shop.snapshot();var economy_before:=commerce.snapshot()
	var result:=shop.buy(cart,token,prices)
	if not result.ok: return result
	var committed:=commerce.commit_quote(quote.data,token)
	if not committed.ok: shop.restore(before);commerce.restore(economy_before);return committed
	commerce.mark_delivered(token)
	return result

func next_day() -> TDOutcome:
	var settled := settle_progression()
	if not settled.ok: return settled
	var previous:=commerce.snapshot()
	var moved:=commerce.advance_day(int(shop.snapshot().day))
	if not moved.ok: return moved
	var result:=shop.next_day(int(shop.snapshot().day))
	if result.ok:
		world.day=int(shop.snapshot().day);world.day_phase="morning";world.free_spent=0.0
		world.pantry.spoil(world.day);world.supply.collect(world.day)
		receive_supplies()
		sync_commercial_map();world.map_revision+=1
	else: commerce.restore(previous)
	return result

func order_remote(id: String, town_id: String = "", units: int = 1000, request_id: String = "") -> TDOutcome:
	if not service.config.costs.has(id): return TDOutcome.new(false,"UNSUPPORTED_MATERIAL")
	if not shop.purchasable(id): return TDOutcome.new(false,"INGREDIENT_LOCKED","该原料尚未用于已解锁菜谱。")
	if not at_boundary() or shop.snapshot().phase!="PREPARE": return TDOutcome.new(false,"NOT_PREPARING")
	if town_id.is_empty():
		if commerce.state.routes.size()<2: return TDOutcome.new(false,"NO_REMOTE_ROUTE","目前只有本地商路，等待剧情推荐后再预订。")
		town_id=commerce.state.routes[1]
	var token:=request_id if not request_id.is_empty() else "remote:%s:%d"%[shop.snapshot().run_id,int(shop.snapshot().serial)+1]
	if shop.snapshot().seen.has(token): return TDOutcome.new(false,"DUPLICATE")
	var quote:=commerce.quote(town_id,{id:units})
	if not quote.ok: return quote
	var before:=shop.snapshot();var economy_before:=commerce.snapshot()
	var paid:=shop.world_adjustment(-int(quote.data.total_cents),token,"跨镇采购（含运费）")
	if not paid.ok: return paid
	var committed:=commerce.commit_quote(quote.data,token)
	if not committed.ok: shop.restore(before);commerce.restore(economy_before);return committed
	receive_supplies()
	return TDOutcome.new(true,"ORDERED","已付款，预计第%d天送到。"%int(quote.data.arrival_day),quote.data)

func receive_supplies() -> TDOutcome:
	if not at_boundary(): return TDOutcome.new(false,"NOT_AT_BOUNDARY")
	for shipment: Dictionary in commerce.due_shipments():
		var goods: Dictionary={}
		for id: String in shipment.rows: goods[id]=int(shipment.rows[id].units)
		var delivered:=shop.receive_supply(goods,"arrival:"+str(shipment.id),int(shipment.total_cents))
		if not delivered.ok and delivered.code!="DUPLICATE": return delivered
		commerce.mark_delivered(shipment.id)
	var units:Dictionary={}
	for id: String in world.supply.stock:
		if service.config.costs.has(id) and int(world.supply.stock[id])>0: units[id]=int(world.supply.stock[id])*1000
	if units.is_empty(): return TDOutcome.new(true,"NO_DELIVERY")
	var factory_value: int=0
	var reductions: Dictionary={}
	for id: String in units:
		var basis: Dictionary=commerce.state.factory_costs.get(id,{"units":0,"value_cents":0})
		var covered:=mini(int(units[id]),int(basis.units))
		var value:=int(basis.value_cents) if covered==int(basis.units) else roundi(float(basis.value_cents)*covered/maxi(1,int(basis.units)))
		factory_value+=value;reductions[id]={"units":covered,"value_cents":value}
	var result:=shop.receive_supply(units,"supply:%s:%d"%[shop.snapshot().run_id,int(shop.snapshot().serial)+1],factory_value)
	if result.ok:
		for id: String in units:
			world.supply.stock[id]=0
			if commerce.state.factory_costs.has(id):
				commerce.state.factory_costs[id].units-=int(reductions[id].units)
				commerce.state.factory_costs[id].value_cents-=int(reductions[id].value_cents)
	return result

func recommend_route(town_id: String, event_id: String) -> TDOutcome:
	if not _alive or not at_boundary(): return TDOutcome.new(false,"NOT_AT_BOUNDARY")
	var before:=commerce.snapshot()
	var result:=commerce.open_route(town_id,event_id)
	if not result.ok: return result
	if persistence.is_valid():
		var saved:=save()
		if not saved.ok: commerce.restore(before);return saved
	return result

func world_transaction(action: Callable, label: String) -> TDOutcome:
	if not _alive or not at_boundary(): return TDOutcome.new(false,"NOT_AT_BOUNDARY")
	var previous:=TDWorldSnapshot.capture(world)
	var whole_yuan:int=int(shop.snapshot().money_cents)/100
	world.money=whole_yuan
	var result: TDOutcome=action.call()
	if not result.ok:
		_restore_world_transaction(previous)
		return result
	var delta:int=(world.money-whole_yuan)*100
	if delta!=0:
		var recorded:=shop.world_adjustment(delta,"world:%s:%d"%[shop.snapshot().run_id,int(shop.snapshot().serial)+1],label)
		if not recorded.ok: _restore_world_transaction(previous);return recorded
	if delta<0 and label=="工厂生产":
		for key: String in world.factory_jobs:
			var old_value: Variant=previous.get("factory_jobs",{}).get(key,[])
			# Earlier factory saves used one Dictionary instead of a list of production lines.
			var old: Array=old_value if old_value is Array else ([old_value] if old_value is Dictionary and not old_value.is_empty() else [])
			for job: Dictionary in world.factory_jobs[key]:
				if old.any(func(j:Dictionary)->bool:return int(j.line)==int(job.line)) or not service.config.costs.has(job.item_id): continue
				var basis: Dictionary=commerce.state.factory_costs.get(job.item_id,{"units":0,"value_cents":0})
				basis.units+=int(job.qty)*1000;basis.value_cents+=int(job.cost)*100
				commerce.state.factory_costs[job.item_id]=basis
	world.money=int(shop.snapshot().money_cents)/100
	return result

func _restore_world_transaction(previous: Dictionary) -> void:
	TDWorldSnapshot.restore(world,previous)
	sync_commercial_map()
	for plot: Dictionary in world.town_map.plots: plot.enabled=bool(previous.zone_enabled.get(plot.id,plot.enabled))

func restore(data: Dictionary) -> TDOutcome:
	var checked:=validate_save(data)
	if not checked.ok: return checked
	# Validation completes before any live object is changed.
	world.town_map.cottage={};residence={}
	install_legacy(service,data.shop.menu.keys())
	shop.restore(data.shop);research.restore(data.research)
	TDWorldSnapshot.restore(world,data.world)
	if int(data.schema_version)>=2:
		commerce=TDWorldEconomy.new(service.config.costs,str(data.economy.home),int(data.shop.seed),int(data.shop.day))
		commerce.restore(data.economy)
	else:
		# Explicit v1 -> v2 in-memory migration. Never charge past days or rewrite on read.
		initialize_legacy_commerce()
	_wire_commerce()
	if int(data.schema_version)>=3: progression.restore(data.progression)
	else: initialize_progression(true)
	if int(data.schema_version)>=4:
		residence=data.residence.duplicate(true);world.town_map.install_cottage(residence.plot)
	else:
		var installed:=initialize_residence()
		if not installed.ok: return installed
	for plot: Dictionary in world.town_map.plots: plot.enabled=bool(data.world.zone_enabled.get(plot.id,plot.enabled))
	var furniture:=TDRestaurantCatalog.new();furniture.load_file()
	layout=TDRestaurantLayout.import_dict(data.layout,furniture)
	if layout!=null: shop.crew=layout.crew
	slot_id=data.slot_id;title=data.title;updated_at=int(data.updated_at);revision=int(data.revision);imported_legacy=data.imported_legacy
	world.scaled_interior=false
	_sync_recipes()
	return TDOutcome.new(true,"RESTORED")

func initialize_legacy_commerce() -> void:
	var business:=shop.snapshot()
	world.day=int(business.day)
	world.day_phase="evening" if business.phase=="SETTLED" else "morning"
	commerce=TDWorldEconomy.new(service.config.costs,world.home_town_id if not world.home_town_id.is_empty() else world.town_id,int(business.seed),int(business.day))
	commerce.sync_costs(business.ledger);commerce.state.cost_consumed=0
	if business.phase=="SETTLED":
		commerce.state.last_settled_day=int(business.day)
		commerce.society.state.last_day=int(business.day);commerce.society.bank.state.last_day=int(business.day)
	_wire_commerce()

static func validate_save(raw: Variant) -> TDOutcome:
	if not raw is Dictionary or not TDServiceCatalog.integer(raw.get("schema_version"),1,4) or raw.get("kind")!="town-diner-profile": return TDOutcome.new(false,"UNSUPPORTED_VERSION")
	if int(raw.schema_version)>=4:
		if not raw.get("residence") is Dictionary or raw.residence.get("schema_version")!=1 or raw.residence.get("anchor")!="cottage_bed" or not raw.residence.get("plot") is Dictionary: return TDOutcome.new(false,"INVALID_RESIDENCE")
	if not raw.get("slot_id") is String or not raw.slot_id in ["slot-01","slot-02","slot-03","slot-04","slot-05","slot-06"]: return TDOutcome.new(false,"INVALID_SLOT")
	if not raw.get("title") is String or raw.title.strip_edges().is_empty() or raw.title.length()>40 or not raw.get("imported_legacy") is bool: return TDOutcome.new(false,"INVALID_PROFILE")
	if not TDServiceCatalog.integer(raw.get("revision"),0,1000000000) or not TDServiceCatalog.integer(raw.get("updated_at"),0,9007199254740991): return TDOutcome.new(false,"INVALID_PROFILE")
	for field: String in ["shop","research","world","layout"]:
		if not raw.get(field) is Dictionary: return TDOutcome.new(false,"INVALID_PROFILE",field)
	var content:=TDServiceCatalog.new();var checked:=content.load_file()
	if not checked.ok: return checked
	checked=TDResearchRuntime.install(content)
	if not checked.ok: return checked
	if raw.shop.get("menu") is Dictionary: install_legacy(content,raw.shop.menu.keys())
	var business:=TDShopSession.new(content)
	checked=business.validate_save(raw.shop)
	if not checked.ok: return checked
	var definitions:=TDResearchCatalog.new();checked=definitions.load_file()
	if not checked.ok: return checked
	checked=TDResearchSession.new(definitions).validate_save(raw.research)
	if not checked.ok: return checked
	checked=TDWorldSnapshot.validate(raw.world)
	if not checked.ok: return checked
	if int(raw.world.day)!=int(raw.shop.day) or int(raw.world.money)!=int(raw.shop.money_cents)/100: return TDOutcome.new(false,"INCONSISTENT_PROFILE")
	var furniture:=TDRestaurantCatalog.new();checked=furniture.load_file()
	if not checked.ok: return checked
	if TDRestaurantLayout.import_dict(raw.layout,furniture)==null: return TDOutcome.new(false,"INVALID_LAYOUT",TDRestaurantLayout.import_code)
	if int(raw.schema_version)>=2:
		if not raw.get("economy") is Dictionary: return TDOutcome.new(false,"MISSING_ECONOMY")
		var economy:=TDWorldEconomy.new(content.config.costs)
		checked=economy.validate_save(raw.economy)
		if not checked.ok: return checked
		if int(raw.economy.schema_version)==2:
			checked=_validate_social_links(raw)
			if not checked.ok: return checked
		if int(raw.economy.day)!=int(raw.shop.day) or int(raw.economy.cost_cursor)!=raw.shop.ledger.size(): return TDOutcome.new(false,"INCONSISTENT_ECONOMY")
		if raw.shop.phase=="SETTLED" and int(raw.economy.last_settled_day)!=int(raw.shop.day): return TDOutcome.new(false,"INCONSISTENT_ECONOMY")
	if int(raw.schema_version)<2 or int(raw.economy.schema_version)!=2:
		var world_data:=TDPhase3Session.new();checked=world_data.load_default()
		if not checked.ok: return checked
		checked=TDWorldSnapshot.restore(world_data,raw.world)
		if not checked.ok: return checked
		checked=_validate_residence(world_data,raw)
		if not checked.ok: return checked
	if int(raw.schema_version)>=3:
		var levels := TDLevelProgression.new()
		if not levels.error.ok: return levels.error
		checked=levels.validate_save(raw.get("progression"))
		if not checked.ok: return checked
		var cursor := int(raw.shop.day)-(0 if raw.shop.phase=="SETTLED" else 1)
		if int(raw.progression.last_day)!=cursor or not raw.progression.baselines.has("player_diner"): return TDOutcome.new(false,"INCONSISTENT_LEVEL_DAY")
		for reward: Dictionary in raw.progression.rewards:
			if not TDLevelProgression.same_value(raw.research.events.get(reward.grant_id),{"kind":"inspiration","amount":int(reward.inspiration)}): return TDOutcome.new(false,"INCONSISTENT_LEVEL_REWARD")
		for event_id: String in raw.research.events:
			if event_id.begins_with("level:v1:") and event_id.ends_with(":inspiration") and not raw.progression.rewards.any(func(reward:Dictionary)->bool:return reward.grant_id==event_id): return TDOutcome.new(false,"INCONSISTENT_LEVEL_REWARD")
	return TDOutcome.new(true,"VALID")

static func _validate_social_links(raw: Dictionary) -> TDOutcome:
	var economy: Dictionary=raw.economy
	for order: Dictionary in raw.shop.orders:
		if not order.has("economic_profile") or not order.economic_profile.has("household_id"): continue # Historical settled orders stay read-only.
		var family: String=order.economic_profile.household_id
		var token: String=order.economic_intent.opportunity_id
		var hold: Dictionary=economy.society.holds.get(token,{})
		if not economy.society.households.has(family) or hold.is_empty() or hold.family_id!=family or int(hold.cents)!=int(order.price_cents): return TDOutcome.new(false,"INCONSISTENT_HOUSEHOLD_ORDER")
		if int(hold.paid_cents)!=int(order.prepaid_cents)+int(order.tip_cents) or int(hold.refunded_cents)!=int(order.refunded_cents): return TDOutcome.new(false,"INCONSISTENT_CONSUMER_PAYMENT")
	# Rebuild only geometry from the authoritative building snapshot. A valid financial record
	# cannot relocate a commercial unit into housing or a player/factory lot on load.
	var world_data:=TDPhase3Session.new()
	var loaded:=world_data.load_default()
	if not loaded.ok: return loaded
	loaded=TDWorldSnapshot.restore(world_data,raw.world)
	if not loaded.ok: return loaded
	loaded=_validate_residence(world_data,raw)
	if not loaded.ok: return loaded
	for town: String in economy.expansion.parcels:
		var map:=world_data.town_map if town==economy.home else TDTownMap.new()
		if town!=economy.home:
			var generated:=map.build_economic_layout(world_data.catalog,TDTownMap.seed_of(town))
			if not generated.ok: return generated
		var definitions: Dictionary={}
		for parcel: Dictionary in map.commercial_parcels(): definitions[parcel.id]=parcel
		for id: String in economy.expansion.parcels[town]:
			if not definitions.has(id): return TDOutcome.new(false,"PROTECTED_OR_UNKNOWN_PARCEL")
			var p: Dictionary=economy.expansion.parcels[town][id]
			for field: String in ["x","y","w","h","approach_x","approach_y","parent_id","tradable","capacity","initial_store_index"]:
				if not p.has(field) or p[field]!=definitions[id][field]: return TDOutcome.new(false,"INVALID_PROPERTY_GEOMETRY",id+":"+field)
	return TDOutcome.new(true,"VALID_SOCIAL_LINKS")

static func _validate_residence(world_data:TDPhase3Session,raw:Dictionary) -> TDOutcome:
	if int(raw.schema_version)>=4: return world_data.town_map.validate_cottage(raw.residence.plot)
	if world_data.town_map.choose_cottage().is_empty(): return TDOutcome.new(false,"NO_COTTAGE_LOCATION")
	return TDOutcome.new(true,"VALID")

static func install_legacy(content: TDServiceCatalog, needed: Array) -> void:
	# Definitions are not unlocks. This preserves legitimate older phase3 recipe IDs.
	var missing: Array=needed.filter(func(id:Variant)->bool:return id is String and id.begins_with("phase3.") and content.offer(id).is_empty())
	if missing.is_empty(): return
	var catalog:=TDTownCatalog.new()
	if catalog.load_file().ok:
		TDKitchenLink.install(content,catalog.dish_list().filter(func(d:Dictionary)->bool:return "phase3."+str(d.id) in missing))

func close() -> void:
	_alive=false
	if research!=null:
		if not research._active.is_empty(): research.cancel(str(research._active.token))
		if research.changed.is_connected(_sync_recipes): research.changed.disconnect(_sync_recipes)
		if research.changed.is_connected(world._sync_research): research.changed.disconnect(world._sync_research)
		# Keep the rejecting sink on stale references instead of silently accepting writes.
	persistence=Callable()
	if shop!=null: shop.cooking_reward=Callable()
	if shop!=null and shop.day_settled.is_connected(_on_day_settled): shop.day_settled.disconnect(_on_day_settled)
