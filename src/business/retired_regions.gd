extends RefCounted
## Converts the five-region profile on a copy before normal slot validation.
const TOWNS := ["bangkok", "mexico_city"]
const CUISINES := ["sea", "lat"]
static var removed_materials: Array = TDMaterialCatalog.retired_ids()
const REFUND_TOKEN := "migration:three-towns:refund"

static func needed(raw: Variant) -> bool:
	if not raw is Dictionary or raw.get("region_content_version", 0) != 0:
		return false
	var economy: Variant = raw.get("economy", {})
	var shop: Variant = raw.get("shop", {})
	var research: Variant = raw.get("research", {})
	if not economy is Dictionary or not shop is Dictionary or not research is Dictionary:
		return false
	var markets: Variant = economy.get("markets", {})
	var menu: Variant = shop.get("menu", {})
	var cuisines: Variant = research.get("cuisines", [])
	return (markets is Dictionary and (markets.has("bangkok") or markets.has("mexico_city"))) or (menu is Dictionary and menu.has("study.s01")) or (cuisines is Array and ("sea" in cuisines or "lat" in cuisines))

static func _erase(values: Variant, ids: Array) -> void:
	if values is Dictionary or values is Array:
		for id: Variant in ids:
			values.erase(id)

static func _fields(data: Dictionary, fields: Array, ids: Array) -> void:
	for field: String in fields:
		_erase(data.get(field), ids)

static func _payment(receipts: Dictionary, token: String, kind: String, total: int, store: String = "") -> bool:
	var row: Dictionary = receipts.get(token, {})
	return total > 0 and row.get("kind") == kind and int(row.get("cents", 0)) == -total and (store.is_empty() or row.get("extra", {}).get("store_id") == store)

static func convert(original: Dictionary) -> TDOutcome:
	var data := original.duplicate(true)
	var shop: Variant = data.get("shop")
	if not shop is Dictionary or not shop.get("ledger") is Array or not shop.get("seen") is Dictionary or not data.get("world") is Dictionary:
		return TDOutcome.new(false, "INVALID_REGION_MIGRATION")
	var dishes: Array = []
	for prefix: String in ["S", "L"]:
		for i in range(1, 21):
			var atlas := "%s%02d" % [prefix, i]
			dishes.append_array([atlas, "study." + atlas.to_lower(), "cuisine_" + atlas.to_lower()])
	for entry: Variant in shop.get("custom", []):
		if entry is Dictionary and (entry.get("plan",{}).get("recipe_id") in dishes or _uses_material(entry.get("plan",{}))):
			dishes.append(entry.id)
	if shop.has("custom"): shop.custom = shop.custom.filter(func(row: Dictionary)->bool: return row.id not in dishes)
	if shop.has("cold_foods"): shop.cold_foods = shop.cold_foods.filter(func(row: Dictionary)->bool: return row.get("ingredient_id") not in removed_materials)
	var receipts := {}
	for transaction: Variant in shop.ledger:
		if not transaction is Dictionary or not transaction.get("reference") is String:
			return TDOutcome.new(false, "INVALID_REGION_RECEIPT")
		receipts[transaction.reference] = transaction
		_erase(transaction.get("inventory_delta"), removed_materials)
		var extra: Dictionary = transaction.get("extra",{})
		_erase(extra.get("waste"), removed_materials)
		if extra.has("cold_foods"):
			extra.cold_foods = extra.cold_foods.filter(func(row: Dictionary)->bool: return row.get("ingredient_id") not in removed_materials)
	var refund := 0
	var claimed := {}
	var closed: Array = []
	var branches: Dictionary = data.get("branches", {})
	var stores: Dictionary = branches.get("stores", {})
	if int(branches.get("schema_version",1)) >= 2:
		var payments := TDPlayerBranches.validate_payments(branches, shop)
		if not payments.ok: return payments
	for id: String in stores.keys():
		var store: Dictionary = stores[id]
		if store.get("town_id") in TOWNS or store.get("cuisine_id") in CUISINES:
			var paid: Dictionary = store.get("construction", {})
			var token: String = paid.get("token", "")
			# Older paid contracts predate the construction record; their ledger identifies the site.
			if paid.is_empty():
				for key: String in receipts:
					if receipts[key].get("extra", {}).get("store_id") == id and receipts[key].extra.get("label") == "分店开办":
						token = key
						break
			if token.is_empty() and paid.is_empty() and id=="player-branch:1" and branches.get("legacy",{}).get("branch_open",false):
				for key: String in receipts:
					if TDPlayerBranches._legacy_payment(receipts[key]):
						token = key
						paid = {"kind":"legacy_paid", "paid_cents":-int(receipts[key].cents)}
						break
			if paid.get("kind","") == "legacy_paid":
				if claimed.has(token) or not TDPlayerBranches._legacy_payment(receipts.get(token,{})) or not shop.seen.has(token): return TDOutcome.new(false,"INVALID_BRANCH_PAYMENT")
				claimed[token] = true
				refund -= int(receipts[token].cents)
			elif paid.get("kind", "") == "paid" or (paid.is_empty() and not token.is_empty()):
				var amount: int = paid.get("paid_cents", store.get("opening_cents", 0))
				if claimed.has(token) or not _payment(receipts,token,"branch_transfer",amount,id) or receipts[token].extra.get("label") != "分店开办":
					return TDOutcome.new(false, "INVALID_BRANCH_PAYMENT")
				claimed[token] = true
				refund += amount
			closed.append(id)
			stores.erase(id)
		else:
			_fields(store, ["inventory","lots","basis"], removed_materials)
			store.menu = store.menu.filter(func(row: Dictionary) -> bool: return row.id not in dishes)
	var suppliers: Dictionary = data.get("suppliers", {})
	_fields(suppliers, ["levels","legacy_lines"], TOWNS)
	_erase(suppliers.get("automation"), closed)
	if suppliers.has("lines"):
		suppliers.lines = suppliers.lines.filter(func(row: Dictionary) -> bool: return row.town_id not in TOWNS and row.store_id not in closed and row.item_id not in removed_materials)
	if suppliers.has("orders"):
		var remaining := []
		for order: Dictionary in suppliers.orders:
			if order.town_id not in TOWNS and order.store_id not in closed and not order.jobs.any(func(job: Dictionary) -> bool: return job.item_id in removed_materials):
				remaining.append(order)
				continue
			var total := 0
			var pending := 0
			for job: Dictionary in order.jobs:
				var cost: int = job.get("cost_cents", -1)
				if cost < 0 or not job.get("delivered") is bool:
					return TDOutcome.new(false, "INVALID_SUPPLIER_JOB")
				var arrival := "supply-arrival:" + str(job.id)
				var destination: Dictionary = original.get("branches",{}).get("stores",{}).get(order.store_id,{})
				var delivered: bool = (shop.seen if order.store_id == "player_diner" else destination.get("supply_seen",{})).has(arrival)
				if delivered != job.delivered: return TDOutcome.new(false,"INCONSISTENT_SUPPLY_RECEIPT")
				total += cost
				if not delivered: pending += cost
			if claimed.has(order.token) or total != int(order.total_cents) or not _payment(receipts,order.token,"branch_transfer",total,order.store_id):
				return TDOutcome.new(false, "INVALID_SUPPLIER_PAYMENT")
			claimed[order.token] = true
			refund += pending
		suppliers.orders = remaining
	var old_map: Dictionary = data.get("region_migration",{})
	_trim_geography(old_map.get("branches",{}))
	_trim_geography(old_map.get("cells",{}))
	var economy: Dictionary = data.get("economy", {})
	if economy.has("shipments"):
		var remaining := []
		for shipment: Dictionary in economy.shipments:
			if shipment.source not in TOWNS and shipment.destination not in TOWNS and not shipment.get("rows", {}).keys().any(func(k: String)->bool: return k in removed_materials):
				remaining.append(shipment)
				continue
			if not shipment.delivered:
				if shop.seen.has("arrival:"+str(shipment.id)): return TDOutcome.new(false,"INCONSISTENT_SHIPMENT_RECEIPT")
				if claimed.has(shipment.id) or not _payment(receipts,shipment.id,"world_adjustment",shipment.total_cents) or not str(receipts[shipment.id].get("extra",{}).get("label","")).begins_with("跨镇采购"):
					return TDOutcome.new(false, "INVALID_SHIPMENT_PAYMENT")
				claimed[shipment.id] = true
				refund += int(shipment.total_cents)
		economy.shipments = remaining
	var factory_result := _settle_factory_jobs(data.world, economy, receipts, claimed)
	if not factory_result.ok: return factory_result
	refund += int(factory_result.data.cents)
	_trim_economy(economy, refund)
	_trim_employees(data.get("employees", {}), closed)
	for store: Dictionary in stores.values():
		if _retired_employee(store.get("manager_id","")): store.manager_id = ""
	if data.get("main_management_auto",false):
		var roster := TDEmployeeRoster.new()
		roster.state = data.employees
		data.main_management_auto = not roster.manager_for("player_diner").is_empty()
	if data.world.get("branch_open",false) and (data.world.get("branch_town") in TOWNS or data.world.get("branch_culture") in ["southeast_asian","latin_american"]):
		for token: String in receipts:
			if not claimed.has(token) and TDPlayerBranches._legacy_payment(receipts[token]) and shop.seen.has(token):
				refund -= int(receipts[token].cents)
				if economy.has("society"): economy.society.external_net_cents -= int(receipts[token].cents)
				break
		data.world.branch_open = false
		data.world.branch_town = ""
		data.world.branch_culture = ""
	_fields(data.world, ["home_skill","branch_skill"], dishes)
	_fields(data.world, ["branch_stock"], removed_materials)
	if data.world.get("pantry") is Dictionary and data.world.pantry.get("lots") is Array:
		data.world.pantry.lots = data.world.pantry.lots.filter(func(row: Dictionary)->bool: return row.get("ingredient_id") not in removed_materials)
	if data.world.has("supply"):
		_erase(data.world.supply.get("stock"), removed_materials)

	if data.world.get("town_id") in TOWNS: data.world.town_id = data.world.get("home_town_id","chengdu")
	var archive: Dictionary = branches.get("legacy",{}).get("unverified_archive",{})
	_erase(archive,closed)
	_fields(shop, ["inventory","inventory_lots"], removed_materials)
	_fields(shop, ["unlocked","menu","fame","mastery","mastery_dishes"], dishes)
	if shop.has("orders"):
		shop.orders = shop.orders.filter(func(row: Dictionary) -> bool: return row.get("recipe_id") not in dishes)
	var study: Dictionary = data.get("research", {})
	_fields(study, ["unlocked","licensed","grandfathered","legacy_ids","best"], dishes)
	_erase(study.get("cuisines"), CUISINES)
	for id: String in study.get("events", {}).keys():
		var event: Dictionary = study.events[id]
		if event.get("cuisine") in CUISINES or event.get("recipe") in dishes: study.events.erase(id)
	_fields(data.world, ["prices","home_chef_recipes","branch_chef_recipes","branch_menu"], dishes)
	_erase(data.get("progression",{}).get("baselines"),closed)
	_trim_layout(data.get("layout",{}))
	if refund > 0:
		if shop.seen.has(REFUND_TOKEN) or int(shop.serial) != shop.ledger.size(): return TDOutcome.new(false, "INVALID_REGION_REFUND")
		shop.serial += 1
		shop.ledger.append({"id":"%s:txn-%d" % [shop.run_id,shop.serial], "kind":"world_adjustment", "reference":REFUND_TOKEN, "day":shop.day, "cents":refund, "inventory_delta":{}, "extra":{"label":"撤区结清 · 开办费与未交付货款"}})
		shop.seen[REFUND_TOKEN] = true
		shop.money_cents += refund
		if economy.has("cost_cursor"): economy.cost_cursor += 1
		data.world.money = int(shop.money_cents) / 100
	data.region_content_version = 1
	return TDOutcome.new(true, "REGIONS_SETTLED", "", data)

# Old factory lines store the original charge and the number of portions still in production.
static func _settle_factory_jobs(world: Dictionary, economy: Dictionary, receipts: Dictionary, claimed: Dictionary) -> TDOutcome:
	var refund := 0
	var jobs: Dictionary = world.get("factory_jobs", {})
	for key: String in jobs.keys():
		var retired_factory: bool = key.get_slice(":",0) in TOWNS
		var entry: Variant = jobs[key]
		var lines: Array = entry if entry is Array else [entry]
		var kept: Array = []
		for job: Dictionary in lines:
			if not retired_factory and job.get("item_id") not in removed_materials:
				kept.append(job)
				continue
			var total := int(job.get("cost",0)) * 100
			var units := int(job.get("qty",0))
			var original_units := units
			if float(job.get("unit_hours",0)) > 0:
				original_units = roundi(float(job.get("total_hours",0)) / float(job.unit_hours))
			if units < 1 or original_units < units or total < 0: return TDOutcome.new(false,"INVALID_FACTORY_JOB")
			if total == 0: continue
			var token := ""
			for reference: String in receipts:
				if claimed.has(reference): continue
				if _payment(receipts,reference,"world_adjustment",total) and receipts[reference].get("extra",{}).get("label") == "工厂生产":
					token = reference
					break
			if token.is_empty(): return TDOutcome.new(false,"INVALID_FACTORY_PAYMENT")
			claimed[token] = true
			var cents := roundi(float(total) * units / original_units)
			refund += cents
			var basis: Dictionary = economy.get("factory_costs",{}).get(job.item_id,{})
			if not basis.is_empty():
				basis.units = maxi(0,int(basis.units)-units*1000)
				basis.value_cents = maxi(0,int(basis.value_cents)-cents)
		if kept.is_empty(): jobs.erase(key)
		elif kept.size()!=lines.size(): jobs[key] = kept
	for field: String in ["factory_built","factory_level"]:
		for key: String in world.get(field,{}).keys():
			if key.get_slice(":",0) in TOWNS: world[field].erase(key)
	return TDOutcome.new(true,"FACTORY_SETTLED","",{"cents":refund})

static func _trim_geography(rows: Dictionary) -> void:
	for id: String in rows.keys():
		if rows[id] is Dictionary and rows[id].get("town_id") in TOWNS: rows.erase(id)

static func _trim_economy(economy: Dictionary, refund: int) -> void:
	_trim_geography(economy.get("cells", {}))
	_erase(economy.get("day_stats",{}).get("remote_opportunities"), TOWNS)
	var withdrawn := 0
	for town: String in TOWNS:
		for firm: Dictionary in economy.get("competitors", {}).get(town, []):
			withdrawn += int(firm.cash_cents)
	_fields(economy, ["markets","competitors","routes"], TOWNS)
	for key: String in economy.get("route_events", {}).keys():
		if economy.route_events[key] in TOWNS: economy.route_events.erase(key)
	for market: Dictionary in economy.get("markets", {}).values():
		for values: Variant in market.values(): _erase(values, removed_materials)
	for firms: Array in economy.get("competitors", {}).values():
		for firm: Dictionary in firms:
			_fields(firm, ["inventory","cost_basis"], removed_materials)
	_fields(economy, ["cost_stock","factory_costs"], removed_materials)
	var expansion: Dictionary = economy.get("expansion", {})
	_fields(expansion, ["parcels","last_review"], TOWNS)
	if expansion.has("events"): expansion.events = expansion.events.filter(func(event: Dictionary)->bool: return event.get("town_id") not in TOWNS)
	var society: Dictionary = economy.get("society", {})
	if society.is_empty(): return
	for town: String in TOWNS:
		withdrawn += int(society.public.get(town, 0))
		society.public.erase(town)
	var gone := {}
	for id: String in society.households.keys():
		if society.households[id].town_id in TOWNS:
			withdrawn += int(society.households[id].cash_cents)
			society.households.erase(id)
			gone[id] = true
	for token: String in society.holds.keys():
		if gone.has(society.holds[token].family_id): society.holds.erase(token)
	var bank: Dictionary = society.bank
	for owner: String in bank.accounts.keys():
		if not owner.split(":").has("bangkok") and not owner.split(":").has("mexico_city"): continue
		var account: Dictionary = bank.accounts[owner]
		bank.equity_cents += int(account.deposit_cents) - int(account.principal_cents) - int(account.interest_cents)
		bank.accounts.erase(owner)
	bank.journal = bank.journal.filter(func(row: Dictionary)->bool: return bank.accounts.has(row.owner))
	society.external_net_cents += refund - withdrawn

static func _trim_employees(employees: Dictionary, closed: Array) -> void:
	var removed: Array = []
	for id: String in employees.get("owned", {}).keys():
		if _retired_employee(id):
			removed.append(id)
		elif employees.owned[id].get("assigned") in closed: employees.owned[id].assigned = ""
	_fields(employees, ["owned","contracts"], removed)
	for duty: Dictionary in employees.get("duties", {}).values():
		for id: String in duty.keys():
			if id in removed or duty[id].get("store_id") in closed: duty.erase(id)

static func _retired_employee(id: String) -> bool:
	return id.begins_with("staff.lat.") or id.begins_with("staff.sea.")

static func _uses_material(value: Variant) -> bool:
	if value is Array:
		for item: Variant in value:
			if _uses_material(item): return true
	if value is Dictionary:
		if value.get("ingredient_id") in removed_materials: return true
		for part: Variant in value.values():
			if _uses_material(part): return true
	return false

static func _trim_layout(layout: Dictionary) -> void:
	if layout.get("culture") in ["thai","mexican"]: layout.culture = "chinese"
	for line: Array in layout.get("finish_ids", []):
		for x: int in line.size():
			if line[x] in ["floor_thai","floor_mexican","wall_thai","wall_mexican"]:
				line[x] = str(line[x]).get_slice("_",0) + "_chinese"
	for piece: Dictionary in layout.get("pieces", []):
		var style: String = piece.get("style_id","")
		if style.get_slice("_",0) in ["thai","mexican"]: piece.style_id = "chinese_" + style.get_slice("_",1)
		for key: String in ["kind","finish_id"]:
			var value: String = piece.get(key,"")
			if value in ["floor_thai","floor_mexican","wall_thai","wall_mexican"]: piece[key] = value.get_slice("_",0) + "_chinese"
