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
var kitchen_checkpoint: Callable
var _alive: bool = true
var error := TDOutcome.new(true)
var commerce: TDWorldEconomy
var branches := TDPlayerBranches.new()
var employees := TDEmployeeRoster.new()
var suppliers := TDSupplierNetwork.new()
var progression := TDLevelProgression.new()
var progression_error := TDOutcome.new(true)
var residence:Dictionary={}
var map_migration: Dictionary={}
var map_migrated_on_load: bool=false
var region_migrated_on_load: bool=false
var region_layout_version: int=2
var region_migration: Dictionary={}
var story := TDOpening.new()
var characters := TDCharacterRoster.new()
var main_management_auto: bool=false

func _init() -> void:
	if not characters.error.ok: error=characters.error;return
	error=service.load_file()
	if not error.ok: return
	error=TDResearchRuntime.install(service)
	if not error.ok: return
	var definitions:=TDResearchCatalog.new()
	error=definitions.load_file()
	if not error.ok: return
	research=TDResearchSession.new(definitions)
	world.map_version=2
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
	shop.material_recipe_unlocks=research.snapshot().unlocked.duplicate()
	shop.material_cuisine_unlocks=research.snapshot().cuisines.duplicate()
	commerce=TDWorldEconomy.new(service.config.costs,world.home_town_id if not world.home_town_id.is_empty() else world.town_id,int(shop.snapshot().seed))
	if not commerce.error.ok: error=commerce.error;return
	if not branches.error.ok: error=branches.error;return
	branches.managed=true
	employees.attach(self);suppliers.attach(self)
	if not employees.error.ok: error=employees.error;return
	if not suppliers.error.ok: error=suppliers.error;return
	employees.sync_main_crew()
	branches.attach(self)
	_wire_commerce()
	if not error.ok: return
	if not progression.error.ok: error=progression.error;return
	initialize_progression()
	shop.day_settled.connect(_on_day_settled)
	shop.day_opened.connect(_on_business_opened)
	shop.day_settled.connect(_on_business_settled)
	error=initialize_residence()

func _on_business_opened() -> void:
	employees.record_duties(int(shop.snapshot().day))
	story.note_opened()

func _on_business_settled(_day: int) -> void:
	story.note_served()

func initialize_residence() -> TDOutcome:
	var plot:=world.town_map.choose_cottage()
	if plot.is_empty(): return TDOutcome.new(false,"NO_COTTAGE_LOCATION")
	var installed:=world.town_map.install_cottage(plot)
	if not installed.ok: return installed
	residence={"schema_version":2,"anchor":"harbor_arrival","plot":plot,"stage":"locked","reason":""}
	return installed

func has_residence() -> bool:
	return residence.get("stage","")=="unlocked"

func invite_home(reason: String) -> TDOutcome:
	if has_residence(): return TDOutcome.new(true,"HOME_ALREADY_UNLOCKED")
	if residence.stage!="locked": return TDOutcome.new(true,"HOME_ALREADY_PENDING")
	if shop.snapshot().phase!="SETTLED" or reason not in ["first_day","late"]: return TDOutcome.new(false,"HOME_NOT_READY")
	if reason=="first_day" and not story.served: return TDOutcome.new(false,"BUSINESS_NOT_COMPLETED")
	residence.stage="invited";residence.reason=reason
	return TDOutcome.new(true,"HOME_INVITED")

func unlock_residence() -> TDOutcome:
	if has_residence(): return TDOutcome.new(true,"HOME_ALREADY_UNLOCKED")
	if residence.stage!="door": return TDOutcome.new(false,"HOME_STORY_INCOMPLETE")
	residence.stage="unlocked";residence.anchor="cottage_bed"
	if story.beat=="founded" and story.served: story.beat="done"
	return TDOutcome.new(true,"HOME_UNLOCKED")

func initialize_progression(migrated: bool = false) -> void:
	var day := int(shop.snapshot().day)+(1 if shop.snapshot().phase=="SETTLED" else 0)
	progression.start(day,{"player_diner":{"popularity":float(shop.snapshot().popularity),"awareness":float(commerce.state.awareness)*100.0}},migrated)

func level_daily_report() -> TDOutcome:
	# One portfolio report per day; transfers and opening capital are not profit.
	if not _alive or shop.snapshot().phase!="SETTLED": return TDOutcome.new(false,"NOT_SETTLED")
	var day := int(shop.snapshot().day)
	var book: Dictionary=shop.day_summary().economy
	if book.is_empty() or int(book.day)!=day: return TDOutcome.new(false,"MISSING_LEVEL_BUSINESS_BOOK")
	var before: Dictionary=progression.snapshot().baselines.get("player_diner",{})
	if before.is_empty(): return TDOutcome.new(false,"MISSING_LEVEL_BASELINE")
	return TDOutcome.new(true,"LEVEL_REPORT","",{"day":day,"stores":[{"store_id":"player_diner","scale_milli":1000,"profit_cents":int(book.profit_cents),"popularity_before":float(before.popularity),"popularity_after":float(shop.snapshot().popularity),"awareness_before":float(before.awareness),"awareness_after":float(commerce.state.awareness)*100.0}]+branches.level_rows(day)})

func _on_day_settled(_day: int) -> void:
	characters.observe_orders(shop.snapshot().orders)
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
	return progression.acknowledge(event_id)

func _wire_commerce() -> void:
	shop.commerce=commerce
	shop.before_open=prepare_management
	shop.before_settlement=_accrue_main_payroll
	branches.attach(self)
	commerce.player_branches=branches
	commerce.character_candidate=_meal_candidate
	shop.day_minute_reader=func()->float:return characters.clock.minute
	shop.kitchen_gate=characters.kitchen_available
	world.factory_products_provider=_factory_products;world.factory_item_provider=_factory_item
	commerce.attach_cash_baseline(int(shop.snapshot().money_cents))
	for town_id: String in commerce.config.active_towns:
		var map:=world.town_map if town_id==commerce.state.home else TDTownMap.new()
		if town_id!=commerce.state.home:
			map.layout_version=world.map_version
			var generated:=map.build_economic_layout(world.catalog,TDTownMap.seed_of(town_id),region_layout_version)
			if not generated.ok: error=generated;return
		var configured:=commerce.configure_parcels(town_id,map.plots,map.commercial_parcels(),world.map_version)
		if not configured.ok: error=configured;return
	sync_commercial_map()
	commerce.attach_map(world.town_map.plots,world.map_version)
	for id: String in research.catalog.nodes:
		var runtime:=research.catalog.runtime_id(id)
		var recipe:=world.catalog.kitchen_recipe_id(runtime)
		if not recipe.is_empty(): shop.recipe_cultures[recipe]={"cn":"chinese","eu":"continental","jp":"japanese","sea":"southeast_asian","lat":"latin_american"}.get(research.catalog.node(id).cuisine_id,research.catalog.node(id).cuisine_id)

func _legacy_staff(old_layout: Dictionary) -> Dictionary:
	var result: Dictionary=world.staff.duplicate(true)
	for role: String in ["greeter","cashier"]:
		if bool(old_layout.get("staff",{}).get(role,false)): result[role]=true
	return result

func prepare_management() -> void:
	if not _alive or not at_boundary(): return
	suppliers.advance(0)
	receive_supplies()
	_automate_main()
	branches.automate()
	suppliers.automate()
	employees.record_duties(int(shop.snapshot().day))
	employees.sync_main_crew()

func main_menu_rows() -> Array:
	var rows: Array=[];var data:=shop.snapshot()
	for id: String in data.menu:
		if not shop.is_unlocked(shop.family_id(id)): continue
		var row:=shop.offer(id)
		if row.is_empty(): continue
		row.name=shop.recipe_name(id);row.enabled=bool(data.menu[id].enabled);row.price_cents=int(data.menu[id].price_cents)
		rows.append(row)
	rows.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return str(a.id)<str(b.id))
	return rows

func set_main_management(value: bool) -> TDOutcome:
	if not _alive or not at_boundary(): return TDOutcome.new(false,"NOT_AT_BOUNDARY","筹备或日结后才能调整托管。")
	if value and employees.manager_for("player_diner").is_empty(): return TDOutcome.new(false,"MANAGER_REQUIRED","请先从员工仓库为主店派驻店长。")
	main_management_auto=value
	if value: _automate_main()
	return TDOutcome.new(true,"AUTOMATION_UPDATED","主店经营托管已开启，店长将在筹备时安排人员和菜单。" if value else "主店经营托管已关闭，当前人员和菜单保留。")

func _automate_main() -> void:
	if not _alive or not main_management_auto or shop.snapshot().phase!="PREPARE" or employees.manager_for("player_diner").is_empty(): return
	var choices:=main_menu_rows()
	choices.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return int(a.reference_cents)<int(b.reference_cents) if int(a.reference_cents)!=int(b.reference_cents) else str(a.id)<str(b.id))
	var menu: Array=[]
	for dish: Dictionary in choices.slice(0,3):
		var recipe:=shop.profile_for({"recipe_id":dish.id})
		var needs:=service.material_needs(recipe,shop.family_id(dish.id));var cost: int=0
		for item: String in needs:
			cost+=TDShopSession.amount_cost(int(needs[item]),int(commerce.state.markets[commerce.state.home].price.get(item,0)))
		menu.append({"id":dish.id,"price_cents":clampi(maxi(int(dish.reference_cents),roundi(cost*1.8)),1,1000000)})
	if menu.is_empty(): return
	var updated:=shop.configure_menu(menu)
	if updated.ok: employees.auto_assign("player_diner")

func _accrue_main_payroll() -> void:
	employees.record_duties(int(shop.snapshot().day))
	var payroll: Dictionary=employees.payroll_for("player_diner",int(shop.snapshot().day))
	# Legacy hiring paid these named workers in advance. Keep the paid wage in the
	# existing ledger and accrue only the balance, including after save migration.
	var prepaid: Dictionary={}
	for event: Dictionary in shop.snapshot().ledger:
		if event.kind=="settlement": prepaid.clear()
		elif event.kind=="wage" and int(event.cents)<0:
			prepaid[str(event.reference)]=int(prepaid.get(str(event.reference),0))-int(event.cents)
	var credit: int=0
	for worker: Dictionary in payroll.workers:
		var paid: int=0
		for token: String in prepaid:
			if token.begins_with("crew:%s:"%worker.employee_id): paid+=int(prepaid[token])
		credit+=mini(int(worker.cents),paid)
	shop.accrue_wage(maxi(0,int(payroll.total_cents)-credit),shop.day_namespace()+"employee-payroll")

func _meal_candidate(raw: Dictionary, templates: Array, family_count: int) -> Dictionary:
	return characters.candidate(raw,templates,family_count,commerce.event_minute)

func _factory_products(group: String) -> Array:
	var rows: Array=[]
	for id: String in shop.purchase_ids():
		if shop.stock_info(id).group==group and TDMaterialCatalog.supplies(world.town_id,id): rows.append({"id":id,"hours":1.0 if group=="meat" else .5})
	return rows

func _factory_item(id: String) -> Dictionary:
	if not service.config.costs.has(id): return {}
	for food: Dictionary in service.cooking.data().ingredients:
		if food.id==id: return {"id":id,"name":food.name,"cost":maxi(1,ceili(float(service.config.costs[id])/100)),"unit":shop.stock_info(id).unit}
	return {}

func sync_commercial_map() -> TDOutcome:
	var result := world.town_map.apply_commercial_occupancy(commerce.expansion.presentation(commerce.state.home,commerce.state.competitors[commerce.state.home],int(commerce.state.day)))
	world.town_map.plots=world.town_map.plots.filter(func(p:Dictionary)->bool:return not p.has("branch_id"))
	world.town_map.plots.append_array(branches.plots(str(commerce.state.home)))
	return result

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
	shop.material_recipe_unlocks=research.snapshot().unlocked.duplicate()
	shop.material_cuisine_unlocks=research.snapshot().cuisines.duplicate()
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
	var data:={"schema_version":9,"kind":"town-diner-profile","slot_id":slot_id,"title":title,"updated_at":updated_at,"revision":revision,"imported_legacy":imported_legacy,"shop":business,"research":progress,"world":state,"layout":layout.to_dict(),"economy":commerce.snapshot(),"branches":branches.snapshot(),"employees":employees.snapshot(),"suppliers":suppliers.snapshot(),"progression":progression.snapshot(),"residence":residence.duplicate(true),"characters":characters.snapshot(),"map_migration":map_migration.duplicate(true)}
	data.main_management_auto=main_management_auto
	data.region_layout_version=region_layout_version;data.region_migration=region_migration.duplicate(true)
	var chapter:=story.export_state()
	if not chapter.is_empty(): data.story=chapter
	return data

func save(candidate: Dictionary = {}) -> TDOutcome:
	if not _alive: return TDOutcome.new(false,"STALE_PROFILE")
	if not at_boundary(): return TDOutcome.new(false,"NOT_AT_BOUNDARY","营业中不能存档，请打烊后保存。")
	if kitchen_checkpoint.is_valid():
		var ready: TDOutcome=kitchen_checkpoint.call()
		if not ready.ok: return ready
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
	# Research commits to this live profile, not to disk. A purchase/calibration
	# must not silently checkpoint unrelated furniture, money or quest progress.
	var checked:=research.validate_save(candidate)
	if not checked.ok: return checked
	return TDOutcome.new(true,"BUFFERED_UNTIL_EXPLICIT_SAVE")

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

func close_branch_books() -> TDOutcome:
	if world == null or not world.branch_open:
		return TDOutcome.new(true, "NO_BRANCH")
	var played := int(shop.snapshot().day)
	if world.branch_settled.has(str(played)):
		return TDOutcome.new(true, "ALREADY", "分店今天已经结过。")
	var previous_day := world.day
	world.money = int(shop.snapshot().money_cents) / 100
	world.day = played
	var before := world.money
	var report := world.settle_branch()
	world.day = previous_day
	if not bool(report.get("ok", false)):
		return TDOutcome.new(false, str(report.get("code", "BRANCH")), str(report.get("events", "")))
	var delta := (world.money - before) * 100
	if delta != 0:
		var recorded := shop.world_adjustment(delta, "branch-day:%s:%d" % [shop.snapshot().run_id, played], "分店日结")
		if not recorded.ok:
			return recorded
	world.money = int(shop.snapshot().money_cents) / 100
	return TDOutcome.new(true, "BRANCH", str(report.get("events", "")))

func next_day() -> TDOutcome:
	if kitchen_checkpoint.is_valid():
		var ready: TDOutcome=kitchen_checkpoint.call()
		if not ready.ok: return ready
	var settled := settle_progression()
	if not settled.ok: return settled
	var previous:=commerce.snapshot()
	var moved:=commerce.advance_day(int(shop.snapshot().day))
	if not moved.ok: return moved
	var books := close_branch_books()
	if not books.ok:
		commerce.restore(previous)
		return books
	var overnight: float=1440.0+TDWorldDayClock.START_MINUTE-characters.clock.minute
	var result:=shop.next_day(int(shop.snapshot().day))
	if result.ok:
		world.day=int(shop.snapshot().day);world.day_phase="morning";world.free_spent=0.0
		branches.advance_day()
		characters.next_day(world.day)
		# Night deliveries are booked on the new morning after expiry/day rollover.
		# Only game-time lines advance; prepaid legacy real-second queues do not.
		suppliers.automate()
		suppliers.advance_game_minutes(overnight)
		world.pantry.spoil(world.day);world.supply.collect(world.day)
		receive_supplies()
		prepare_management()
		sync_commercial_map();world.map_revision+=1
	else: commerce.restore(previous)
	return result

func order_remote(id: String, town_id: String = "", units: int = 1000, request_id: String = "") -> TDOutcome:
	if not service.config.costs.has(id): return TDOutcome.new(false,"UNSUPPORTED_MATERIAL")
	if not shop.market_sells(id): return TDOutcome.new(false,"INGREDIENT_LOCKED","原料不可购买；特色调料需先开放对应菜系。")
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
	return commerce.open_route(town_id,event_id)

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
	map_migrated_on_load=int(data.world.get("map_version",1))<2
	if map_migrated_on_load:
		var migrated:=TDMapMigration.convert(data)
		if not migrated.ok: return migrated
		data=migrated.data
		checked=validate_save(data)
		if not checked.ok: return checked
	region_migrated_on_load=int(data.get("region_layout_version",1))<2
	if region_migrated_on_load:
		var converted:=TDRegionMigration.convert(data)
		if not converted.ok: return converted
		data=converted.data
		checked=validate_save(data)
		if not checked.ok: return checked
	main_management_auto=bool(data.get("main_management_auto",false))
	region_layout_version=2;region_migration=data.get("region_migration",{}).duplicate(true)
	map_migration=data.get("map_migration",{}).duplicate(true)
	# Validation completes before any live object is changed.
	world.town_map.cottage={};residence={}
	install_legacy(service,data.shop.menu.keys())
	shop.restore(data.shop);research.restore(data.research)
	TDWorldSnapshot.restore(world,data.world)
	branches.state=data.get("branches",{"schema_version":1,"serial":0,"stores":{},"legacy":{}}).duplicate(true)
	if int(data.schema_version)>=2:
		commerce=TDWorldEconomy.new(service.config.costs,str(data.economy.home),int(data.shop.seed),int(data.shop.day))
		commerce.restore(data.economy)
	else:
		# Explicit v1 -> v2 in-memory migration. Never charge past days or rewrite on read.
		initialize_legacy_commerce()
	_wire_commerce()
	if not error.ok: return error
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
	if data.has("story") and data.story is Dictionary: story.restore(data.story)
	else: story.clear()
	# Older slots already owned their cottage. Never remove a previously saved entitlement.
	if int(data.schema_version)<7:
		residence.merge({"schema_version":2,"anchor":"cottage_bed","stage":"unlocked","reason":"legacy"},true)
	if int(data.schema_version)>=5: characters.restore(data.characters,int(data.shop.day))
	else: characters.migrate(int(data.shop.day),data.shop.phase=="SETTLED")
	world.scaled_interior=false
	_sync_recipes()
	if int(data.schema_version)<8 and world.branch_open:
		branches.migrate_legacy()
		sync_commercial_map()
		if not residence.is_empty(): world.town_map.install_cottage(residence.plot)
	employees=TDEmployeeRoster.new();suppliers=TDSupplierNetwork.new()
	employees.attach(self);suppliers.attach(self);branches.managed=true
	if int(data.schema_version)>=9:
		checked=employees.restore(data.employees)
		if not checked.ok: return checked
		checked=suppliers.restore(data.suppliers)
		if not checked.ok: return checked
	else:
		checked=employees.migrate_legacy(data.layout.get("crew",[]),branches.snapshot(),_legacy_staff(data.layout))
		if not checked.ok: return checked
		for store: Dictionary in branches.state.stores.values():
			store.manager_id=str(employees.manager_for(str(store.id)).get("id",""))
			store.management_auto=false
		suppliers.migrate_legacy(world)
	branches.migrate_construction()
	sync_commercial_map()
	employees.sync_main_crew()
	if int(data.schema_version)<9:
		if story.started(): characters.mark_met("aling")
		if story.started() and story.beat not in ["arrive","follow"]: characters.mark_met("chen")
	for plot: Dictionary in world.town_map.plots: plot.enabled=bool(data.world.zone_enabled.get(plot.id,plot.get("enabled",true)))
	return TDOutcome.new(true,"MAP_MIGRATED" if map_migrated_on_load or region_migrated_on_load else "RESTORED","小镇已更新布局，经营进度已保留。" if map_migrated_on_load or region_migrated_on_load else "")

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
	if not raw is Dictionary or not TDServiceCatalog.integer(raw.get("schema_version"),1,9) or raw.get("kind")!="town-diner-profile": return TDOutcome.new(false,"UNSUPPORTED_VERSION")
	if raw.has("main_management_auto") and not raw.main_management_auto is bool: return TDOutcome.new(false,"INVALID_MAIN_MANAGEMENT")
	if not TDServiceCatalog.integer(raw.get("region_layout_version",1),1,2): return TDOutcome.new(false,"UNKNOWN_REGION_VERSION")
	var regions:=TDRegionMigration.validate_archive(raw.get("region_migration",{}))
	if not regions.ok: return regions
	if raw.has("story"):
		var chapter:=TDOpening.validate_state(raw.story)
		if not chapter.ok: return chapter
	if int(raw.schema_version)>=6 and int(raw.get("world",{}).get("map_version",0))!=2: return TDOutcome.new(false,"INVALID_MAP_VERSION")
	if raw.has("map_migration") and not raw.map_migration is Dictionary: return TDOutcome.new(false,"INVALID_MAP_ARCHIVE")
	var archive: Dictionary=raw.get("map_migration",{})
	if not archive.is_empty():
		if archive.get("from")!=1 or archive.get("to")!=2 or not archive.get("old_residence") is Dictionary or not archive.get("old_branch") is Array or archive.old_branch.size()!=2 or not archive.get("archived_cell_overrides") is Dictionary:
			return TDOutcome.new(false,"INVALID_MAP_ARCHIVE")
		for value: Variant in archive.old_branch:
			if not TDServiceCatalog.integer(value,0,73): return TDOutcome.new(false,"INVALID_MAP_ARCHIVE")
		for value: Variant in archive.archived_cell_overrides.values():
			if not TDEconomicCell.validate(value).ok: return TDOutcome.new(false,"INVALID_MAP_ARCHIVE")
	if int(raw.schema_version)>=7:
		var home: Variant=raw.get("residence")
		if not home is Dictionary or home.get("schema_version")!=2 or not home.get("plot") is Dictionary or home.get("stage") not in ["locked","invited","following","door","unlocked"] or home.get("reason") not in ["","first_day","late","legacy"]: return TDOutcome.new(false,"INVALID_RESIDENCE")
		if home.get("anchor")!=("cottage_bed" if home.stage=="unlocked" else "harbor_arrival"): return TDOutcome.new(false,"INVALID_RESIDENCE_ANCHOR")
	elif int(raw.schema_version)>=4:
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
	if int(raw.schema_version)>=5:
		var people:=TDCharacterRoster.new()
		if not people.error.ok: return people.error
		checked=people.validate_save(raw.get("characters"),int(raw.shop.day))
		if not checked.ok: return checked
		if int(raw.characters.clock.closed_day)==int(raw.shop.day) and raw.shop.phase!="SETTLED": return TDOutcome.new(false,"INCONSISTENT_NIGHT_CLOSURE")
	var definitions:=TDResearchCatalog.new();checked=definitions.load_file()
	if not checked.ok: return checked
	checked=TDResearchSession.new(definitions).validate_save(raw.research)
	if not checked.ok: return checked
	checked=TDWorldSnapshot.validate(raw.world)
	if not checked.ok: return checked
	if int(raw.world.day)!=int(raw.shop.day) or int(raw.world.money)!=int(raw.shop.money_cents)/100: return TDOutcome.new(false,"INCONSISTENT_PROFILE")
	var manager_ids: Array=[""]
	if int(raw.schema_version)>=9:
		if not raw.get("economy") is Dictionary or not raw.economy.get("home") is String: return TDOutcome.new(false,"MISSING_ECONOMY")
		if not raw.get("branches") is Dictionary or not raw.branches.get("stores") is Dictionary: return TDOutcome.new(false,"INVALID_BRANCH_STATE")
		for store: Variant in raw.branches.stores.values():
			if not store is Dictionary or not store.get("town_id") is String or not store.get("supply_seen",{}) is Dictionary: return TDOutcome.new(false,"INVALID_BRANCH_STATE")
		var roster:=TDEmployeeRoster.new()
		checked=roster.validate_save(raw.get("employees"),raw.branches.stores.keys(),int(raw.shop.day))
		if not checked.ok: return checked
		roster.state=raw.employees.duplicate(true)
		for row: Dictionary in roster.roster_rows():
			if row.role=="manager" and row.owned: manager_ids.append(row.id)
		var supply:=TDSupplierNetwork.new()
		var stores: Dictionary=raw.branches.stores.duplicate(true)
		stores["player_diner"]={"town_id":raw.economy.home}
		checked=supply.validate_save(raw.get("suppliers"),stores,int(raw.shop.day),content.config.costs.keys())
		if not checked.ok: return checked
		var receipts: Dictionary={}
		for event: Dictionary in raw.shop.ledger: receipts[str(event.reference)]=event
		for order_row: Dictionary in raw.suppliers.orders:
			var payment: Dictionary=receipts.get(str(order_row.token),{})
			if payment.get("kind","")!="branch_transfer" or payment.get("extra",{}).get("store_id","")!=order_row.store_id or int(payment.get("cents",0))!=-int(order_row.total_cents) or int(payment.get("day",0))!=int(order_row.day): return TDOutcome.new(false,"INVALID_SUPPLIER_PAYMENT")
			if not raw.shop.seen.has(order_row.token): return TDOutcome.new(false,"UNPAID_SUPPLIER_ORDER")
			for job: Dictionary in order_row.jobs:
				var token: String="supply-arrival:"+str(job.id)
				var seen: Dictionary=raw.shop.seen if order_row.store_id=="player_diner" else raw.branches.stores[order_row.store_id].get("supply_seen",{})
				if bool(job.delivered)!=seen.has(token): return TDOutcome.new(false,"INCONSISTENT_SUPPLY_RECEIPT")
		for employee_token: String in raw.employees.seen:
			if not raw.shop.seen.has(employee_token): return TDOutcome.new(false,"UNPAID_EMPLOYEE_RECRUITMENT")
			var payment: Dictionary=receipts.get(employee_token,{})
			if payment.get("kind","")!="branch_transfer" or payment.get("extra",{}).get("store_id","")!="employee-roster" or int(payment.get("cents",0))>=0: return TDOutcome.new(false,"INVALID_EMPLOYEE_PAYMENT")
		for contract: Dictionary in raw.employees.get("contracts",{}).values():
			var payment: Dictionary=receipts.get(contract.token,{})
			if int(payment.get("cents",0))!=-int(contract.fee_cents) or int(payment.get("day",0))!=int(contract.day): return TDOutcome.new(false,"INVALID_EMPLOYEE_CONTRACT_PAYMENT")

	if int(raw.schema_version)>=8:
		var branch_rules := TDPlayerBranches.new()
		if not branch_rules.error.ok: return branch_rules.error
		checked=branch_rules.validate_save(raw.get("branches"),int(raw.shop.day),content,raw.shop.unlocked,manager_ids,int(raw.schema_version)>=9)
		if not checked.ok: return checked
		checked=TDPlayerBranches.validate_payments(raw.branches,raw.shop)
		if not checked.ok: return checked
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
	var loaded:=world_data.catalog.load_file()
	if not loaded.ok: return loaded
	world_data.import_phase4(raw.world)
	loaded=_validate_residence(world_data,raw)
	if not loaded.ok: return loaded
	if int(raw.schema_version)>=4:
		loaded=world_data.town_map.install_cottage(raw.residence.plot)
		if not loaded.ok: return loaded
	var branch_maps: Dictionary={}
	for branch: Dictionary in raw.get("branches",{}).get("stores",{}).values():
		if branch.get("construction",{}).get("kind","")=="unverified": continue # Archived references do not reserve land.
		var town_id: String=branch.town_id
		if not branch_maps.has(town_id):
			var map := world_data.town_map if town_id==economy.home else TDTownMap.new()
			if town_id!=economy.home:
				map.layout_version=2
				var generated:=map.build_economic_layout(world_data.catalog,TDTownMap.seed_of(town_id),int(raw.get("region_layout_version",1)))
				if not generated.ok: return generated
			branch_maps[town_id]=map
		var map: TDTownMap=branch_maps[town_id]
		var r: Array=branch.rect
		for y: int in range(int(r[1]),int(r[1]+r[3])):
			for x: int in range(int(r[0]),int(r[0]+r[2])):
				if map.is_road(x,y) or not map.terrain_at(Vector2i(x,y)).buildable or not map.plot_at(x,y).is_empty(): return TDOutcome.new(false,"PROTECTED_BRANCH_GEOMETRY")
		if not map._touches_road(int(r[0]),int(r[1]),int(r[2]),int(r[3])): return TDOutcome.new(false,"BRANCH_NOT_ROADSIDE")
		map.plots.append({"id":branch.id,"kind":"player_diner","x":r[0],"y":r[1],"w":r[2],"h":r[3]})
	for town: String in economy.expansion.parcels:
		var definitions: Dictionary={}
		if town==economy.home:
			for parcel: Dictionary in world_data.town_map.commercial_parcels(): definitions[parcel.id]=parcel
		else:
			var remote: Variant=TDTownMap.economic_parcels(world_data.catalog,TDTownMap.seed_of(town),int(raw.world.get("map_version",1)),int(raw.get("region_layout_version",1)))
			if remote is TDOutcome: return remote
			definitions=remote
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
	if shop!=null:
		shop.before_open=Callable();shop.before_settlement=Callable()
		shop.cooking_reward=Callable()
		shop.kitchen_gate=Callable()
		shop.day_minute_reader=Callable()
	if commerce!=null: commerce.character_candidate=Callable()
	if shop!=null and shop.day_settled.is_connected(_on_day_settled): shop.day_settled.disconnect(_on_day_settled)
	if shop!=null and shop.day_opened.is_connected(_on_business_opened): shop.day_opened.disconnect(_on_business_opened)
	if shop!=null and shop.day_settled.is_connected(_on_business_settled): shop.day_settled.disconnect(_on_business_settled)
