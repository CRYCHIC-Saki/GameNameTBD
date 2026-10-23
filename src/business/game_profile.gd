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
	research.save_sink=_research_candidate
	research.changed.connect(_sync_recipes)

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
	return {"schema_version":1,"kind":"town-diner-profile","slot_id":slot_id,"title":title,"updated_at":updated_at,"revision":revision,"imported_legacy":imported_legacy,"shop":business,"research":progress,"world":state,"layout":layout.to_dict()}

func save(candidate: Dictionary = {}) -> TDOutcome:
	if not _alive: return TDOutcome.new(false,"STALE_PROFILE")
	if not at_boundary(): return TDOutcome.new(false,"NOT_AT_BOUNDARY","营业中不能存档，请打烊后保存。")
	if not persistence.is_valid(): return TDOutcome.new(false,"NO_STORAGE")
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
	return shop.buy(cart,"market:%s:%d"%[shop.snapshot().run_id,int(shop.snapshot().serial)+1])

func next_day() -> TDOutcome:
	var result:=shop.next_day(int(shop.snapshot().day))
	if result.ok:
		world.day=int(shop.snapshot().day);world.day_phase="morning";world.free_spent=0.0
		world.pantry.spoil(world.day);world.supply.collect(world.day)
		receive_supplies()
	return result

func order_remote(id: String) -> TDOutcome:
	if not service.config.costs.has(id): return TDOutcome.new(false,"UNSUPPORTED_MATERIAL")
	var result:=world_transaction(world.order_supply.bind(id),"supply:"+id)
	if result.ok: receive_supplies()
	return result

func receive_supplies() -> TDOutcome:
	if not at_boundary(): return TDOutcome.new(false,"NOT_AT_BOUNDARY")
	var units:Dictionary={}
	for id: String in world.supply.stock:
		if service.config.costs.has(id) and int(world.supply.stock[id])>0: units[id]=int(world.supply.stock[id])*1000
	if units.is_empty(): return TDOutcome.new(true,"NO_DELIVERY")
	var result:=shop.receive_supply(units,"supply:%s:%d"%[shop.snapshot().run_id,int(shop.snapshot().serial)+1])
	if result.ok:
		for id: String in units: world.supply.stock[id]=0
	return result

func world_transaction(action: Callable, label: String) -> TDOutcome:
	if not _alive or not at_boundary(): return TDOutcome.new(false,"NOT_AT_BOUNDARY")
	var previous:=TDWorldSnapshot.capture(world)
	var whole_yuan:int=int(shop.snapshot().money_cents)/100
	world.money=whole_yuan
	var result: TDOutcome=action.call()
	if not result.ok:
		TDWorldSnapshot.restore(world,previous)
		return result
	var delta:int=(world.money-whole_yuan)*100
	if delta!=0:
		var recorded:=shop.world_adjustment(delta,"world:%s:%d"%[shop.snapshot().run_id,int(shop.snapshot().serial)+1],label)
		if not recorded.ok: TDWorldSnapshot.restore(world,previous);return recorded
	return result

func restore(data: Dictionary) -> TDOutcome:
	var checked:=validate_save(data)
	if not checked.ok: return checked
	# Validation completes before any live object is changed.
	install_legacy(service,data.shop.menu.keys())
	shop.restore(data.shop);research.restore(data.research)
	TDWorldSnapshot.restore(world,data.world)
	var furniture:=TDRestaurantCatalog.new();furniture.load_file()
	layout=TDRestaurantLayout.import_dict(data.layout,furniture)
	slot_id=data.slot_id;title=data.title;updated_at=int(data.updated_at);revision=int(data.revision);imported_legacy=data.imported_legacy
	world.scaled_interior=false
	_sync_recipes()
	return TDOutcome.new(true,"RESTORED")

static func validate_save(raw: Variant) -> TDOutcome:
	if not raw is Dictionary or raw.get("schema_version")!=1 or raw.get("kind")!="town-diner-profile": return TDOutcome.new(false,"UNSUPPORTED_VERSION")
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
