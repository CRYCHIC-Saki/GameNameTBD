class_name TDFoodStock
extends RefCounted
## Batch metadata complements the Shop inventory ledger; it is not another wallet.
const PATH := "res://content/markets/kitchen_stock.json"

static func load_rules() -> Dictionary:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not raw is Dictionary or raw.get("schema_version") != 1 or not raw.get("items") is Dictionary: return {}
	for id: Variant in raw.items:
		var item: Variant = raw.items[id]
		if not id is String or not item is Dictionary or item.get("group") not in ["seasoning","vegetable","meat","fruit"]: return {}
		if not TDServiceCatalog.integer(item.get("shelf_days"),1,1000) or not TDServiceCatalog.integer(item.get("pack_units"),1,100000): return {}
		if item.get("unit") not in ["份","瓶","袋"] or not item.get("condiment") is bool: return {}
	return raw.items.duplicate(true)

static func migrate(inventory: Dictionary, day: int, rules: Dictionary) -> Dictionary:
	var lots: Dictionary = {}
	for id: String in inventory:
		lots[id] = []
		if int(inventory[id]) > 0: add(lots,id,int(inventory[id]),day,int(rules.get(id,{}).get("shelf_days",3)))
	return lots

static func add(lots: Dictionary, id: String, units: int, day: int, life: int) -> void:
	if not lots.has(id): lots[id] = []
	for lot: Dictionary in lots[id]:
		if int(lot.stored_on)==day and int(lot.expires_on)==day+life:
			lot.units=int(lot.units)+units
			return
	lots[id].append({"units":units,"stored_on":day,"expires_on":day+life})
	lots[id].sort_custom(func(a:Dictionary,b:Dictionary)->bool:return int(a.expires_on)<int(b.expires_on))

static func first_expiry(lots: Dictionary, id: String) -> int:
	return int(lots[id][0].expires_on) if lots.has(id) and not lots[id].is_empty() else 0

static func take(lots: Dictionary, id: String, units: int) -> void:
	var remaining: int = units
	for lot: Dictionary in lots.get(id,[]):
		var used: int = mini(int(lot.units),remaining)
		lot.units=int(lot.units)-used; remaining-=used
		if remaining==0: break
	lots[id]=lots.get(id,[]).filter(func(lot:Dictionary)->bool:return int(lot.units)>0)

static func expired(lots: Dictionary, day: int) -> Dictionary:
	var result: Dictionary = {}
	for id: String in lots:
		for lot: Dictionary in lots[id]:
			if int(lot.expires_on)<=day: result[id]=int(result.get(id,0))+int(lot.units)
	return result

static func valid(lots: Variant, inventory: Dictionary, day: int) -> bool:
	if not lots is Dictionary or lots.size()!=inventory.size(): return false
	for id: String in inventory:
		if not lots.get(id) is Array or lots[id].size()>1000: return false
		var total: int=0; var previous: int=0
		for lot: Variant in lots[id]:
			if not lot is Dictionary or not TDServiceCatalog.integer(lot.get("units"),1,1000000): return false
			if not TDServiceCatalog.integer(lot.get("stored_on"),1,day) or not TDServiceCatalog.integer(lot.get("expires_on"),day+1,day+1000): return false
			if int(lot.expires_on)<=int(lot.stored_on) or int(lot.expires_on)<previous: return false
			previous=int(lot.expires_on);total+=int(lot.units)
		if total!=int(inventory[id]): return false
	return true
