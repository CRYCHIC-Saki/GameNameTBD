class_name TDWorldSnapshot
extends RefCounted
## Durable world fields only. Live service guests and QTE objects are never serialized.
const EXTRA := ["san", "open_hour", "close_hour", "day_phase", "selected_market", "free_spent", "good_count", "bad_count", "prices", "pantry_device", "pantry_category", "pantry_index", "pantry_dish", "_supply_cursor"]
static var _validation_template: Dictionary={}
static var _validation_catalog: TDTownCatalog

static func capture(world: TDPhase3Session) -> Dictionary:
	var data := world.export_phase4()
	data.schema_version = 1
	for field: String in EXTRA:
		var value: Variant = world.get(field)
		data[field] = value.duplicate(true) if value is Dictionary or value is Array else value
	data.supply = world.supply.duplicate_state()
	data.pantry = {"lots":world.pantry.lots.duplicate(true),"serial":world.pantry._serial}
	data.random = {"seed":str(world.rng._generator.seed),"state":str(world.rng._generator.state)}
	data.zone_enabled = {}
	for plot: Dictionary in world.town_map.plots: data.zone_enabled[plot.id] = plot.enabled
	return data

static func validate(raw: Variant) -> TDOutcome:
	if not raw is Dictionary or raw.get("schema_version") != 1: return TDOutcome.new(false,"UNSUPPORTED_WORLD_VERSION")
	if _validation_template.is_empty():
		var defaults := TDPhase3Session.new()
		if not defaults.load_default().ok: return TDOutcome.new(false,"WORLD_CONTENT")
		_validation_template=capture(defaults)
		_validation_catalog=defaults.catalog
	var expected := _validation_template
	for field: String in expected:
		if not raw.has(field): return TDOutcome.new(false,"INVALID_WORLD",field)
		var value: Variant = raw[field]
		if expected[field] is int:
			if not TDServiceCatalog.integer(value,0,1000000000): return TDOutcome.new(false,"INVALID_WORLD",field)
		elif expected[field] is float:
			if not (value is int or value is float) or not is_finite(float(value)) or float(value)<0: return TDOutcome.new(false,"INVALID_WORLD",field)
		elif typeof(value)!=typeof(expected[field]): return TDOutcome.new(false,"INVALID_WORLD",field)
	if _validation_catalog.town(raw.town_id).is_empty() or _validation_catalog.town(raw.home_town_id).is_empty(): return TDOutcome.new(false,"UNKNOWN_TOWN")
	if raw.day<1 or raw.san>100 or raw.open_hour>24 or raw.close_hour>24 or raw.free_spent>24 or raw.day_phase not in ["morning","evening"]: return TDOutcome.new(false,"INVALID_WORLD_CLOCK")
	if raw.home_size not in ["small","medium","large","huge","quarter"] or raw.home_w>41 or raw.home_h>41: return TDOutcome.new(false,"INVALID_WORLD_SIZE")
	if raw.home_built and (raw.home_venue not in ["chinese","western"] or raw.home_w<1 or raw.home_h<1): return TDOutcome.new(false,"INVALID_WORLD_HOME")
	if raw.branch_open and (_validation_catalog.town(raw.branch_town).is_empty() or raw.branch_w<1 or raw.branch_h<1 or raw.branch_x+raw.branch_w>41 or raw.branch_y+raw.branch_h>41): return TDOutcome.new(false,"INVALID_WORLD_BRANCH")
	for flag: Variant in raw.factory_built.values():
		if not flag is bool: return TDOutcome.new(false,"INVALID_WORLD_FACTORY")
	for field: String in ["prices","branch_stock","wage_paid","branch_wage_paid","home_skill","branch_skill"]:
		for amount: Variant in raw[field].values():
			if not TDServiceCatalog.integer(amount,0,1000000000): return TDOutcome.new(false,"INVALID_WORLD_VALUE",field)
	for field: String in ["branch_menu","branch_chef_recipes","home_chef_recipes"]:
		for id: Variant in raw[field]:
			if not id is String: return TDOutcome.new(false,"INVALID_WORLD_RECIPE")
	if not raw.random.get("state") is String or not raw.random.state.is_valid_int() or not raw.random.get("seed") is String or not raw.random.seed.is_valid_int(): return TDOutcome.new(false,"INVALID_WORLD_RNG")
	if not raw.supply.get("stock") is Dictionary or not raw.supply.get("incoming") is Array or not raw.supply.get("pipeline") is bool or not raw.supply.get("nearby_market") is bool: return TDOutcome.new(false,"INVALID_SUPPLY")
	for amount: Variant in raw.supply.stock.values():
		if not TDServiceCatalog.integer(amount,0,1000000000): return TDOutcome.new(false,"INVALID_SUPPLY")
	for order: Variant in raw.supply.incoming:
		if not order is Dictionary or not order.get("item_id") is String or not TDServiceCatalog.integer(order.get("amount"),1,1000000) or not TDServiceCatalog.integer(order.get("arrive"),1,1000000000) or not TDServiceCatalog.integer(order.get("ordered_on"),1,1000000000): return TDOutcome.new(false,"INVALID_SUPPLY")
	if not raw.pantry.get("lots") is Array or not TDServiceCatalog.integer(raw.pantry.get("serial"),1,1000000000): return TDOutcome.new(false,"INVALID_PANTRY")
	for lot: Variant in raw.pantry.lots:
		if not lot is Dictionary or not lot.get("id") is String or not lot.get("ingredient_id") is String or not lot.get("device_id") is String or not TDServiceCatalog.integer(lot.get("expires_on"),1,1000000000): return TDOutcome.new(false,"INVALID_PANTRY")
	for flag: Variant in raw.zone_enabled.values():
		if not flag is bool: return TDOutcome.new(false,"INVALID_ZONE")
	for field: String in ["staff","branch_staff"]:
		for role: String in TDPhase3Session.ROLES:
			if not raw[field].get(role) is bool: return TDOutcome.new(false,"INVALID_WORLD_STAFF")
	return TDOutcome.new(true,"VALID")

static func restore(world: TDPhase3Session, data: Dictionary) -> TDOutcome:
	var checked := validate(data)
	if not checked.ok: return checked
	world.import_phase4(data)
	for field: String in EXTRA:
		var previous: Variant = world.get(field)
		var value: Variant = data[field]
		if previous is int: world.set(field,int(value))
		elif previous is float: world.set(field,float(value))
		else: world.set(field,value.duplicate(true) if value is Dictionary or value is Array else value)
	world.supply.stock=data.supply.stock.duplicate(true);world.supply.incoming=data.supply.incoming.duplicate(true)
	world.supply.pipeline=data.supply.pipeline;world.supply.nearby_market=data.supply.nearby_market
	world.pantry.lots=data.pantry.lots.duplicate(true);world.pantry._serial=int(data.pantry.serial)
	for plot: Dictionary in world.town_map.plots: plot.enabled=bool(data.zone_enabled.get(plot.id,plot.enabled))
	world.refresh_pool()
	world.rng._generator.seed=int(data.random.seed);world.rng._generator.state=int(data.random.state)
	return TDOutcome.new(true,"RESTORED")
