class_name TDRetiredRecipes
extends RefCounted
## Strip retired recipes from a save before validating against the current catalogue.
const SERVICE_IDS := ["service.beef_noodles", "service.pepper_pork", "service.qiguoji"]
const WORLD_IDS := ["ganchaoniuhe", "lajiaochaorou", "qiguoji"]

static func has_shop_entries(shop: Variant) -> bool:
	if not shop is Dictionary or not shop.get("menu") is Dictionary:
		return false
	return SERVICE_IDS.any(func(id: String) -> bool: return shop.menu.has(id))

static func shop_copy(shop: Dictionary) -> Dictionary:
	var copy := shop.duplicate(true)
	_clean_shop(copy)
	return copy

static func profile_copy(profile: Dictionary) -> Dictionary:
	if not has_shop_entries(profile.get("shop")):
		return profile
	var copy := profile.duplicate(true)
	var removed := _clean_shop(copy.shop)
	var research: Dictionary = copy.research
	var world: Dictionary = copy.world
	_erase(research.get("legacy_ids"), WORLD_IDS)
	_erase(research.get("legacy_ids"), SERVICE_IDS)
	for field: String in ["prices", "home_skill", "branch_skill"]:
		_erase(world.get(field), WORLD_IDS)
	for field: String in ["home_chef_recipes", "branch_chef_recipes", "branch_menu"]:
		if world.get(field) is Array:
			world[field] = world[field].filter(func(row: Variant) -> bool:
				return (row.get("dish_id") if row is Dictionary else row) not in WORLD_IDS)
	if world.get("pantry_dish") in WORLD_IDS:
		world.pantry_dish = "mapodoufu"

	var branches: Variant = copy.get("branches")
	var stores: Variant = branches.get("stores") if branches is Dictionary else null
	if stores is Dictionary:
		for store: Variant in stores.values():
			if not store is Dictionary or not store.get("menu") is Array:
				continue
			var original_size: int = store.menu.size()
			store.menu = _without_rows(store.menu, "id", removed)
			if original_size > 0 and store.menu.is_empty():
				store.paused = true
	var supply: Variant = copy.get("menu_supply")
	if supply is Dictionary:
		for field: String in ["plans", "portions"]:
			if not supply.get(field) is Dictionary:
				continue
			for store_id: Variant in supply[field].keys():
				var counts: Variant = supply[field][store_id]
				if not counts is Dictionary or counts.is_empty():
					continue
				_erase(counts, removed)
				if counts.is_empty():
					supply[field].erase(store_id)
	return copy

static func _clean_shop(shop: Dictionary) -> Array:
	var removed := SERVICE_IDS.duplicate()
	if shop.get("custom") is Array:
		for entry: Variant in shop.custom:
			if entry is Dictionary and entry.get("id") is String and entry.get("plan") is Dictionary and entry.plan.get("recipe_id") in SERVICE_IDS:
				removed.append(entry.id)
		shop.custom = _without_rows(shop.custom, "id", removed)
	for field: String in ["menu", "unlocked", "fame", "mastery"]:
		_erase(shop.get(field), removed)
	if shop.get("orders") is Array:
		shop.orders = shop.orders.filter(func(row: Variant) -> bool:
			if not row is Dictionary or row.get("recipe_id") not in removed:
				return true
			return row.get("status") not in ["SERVED", "CANCELLED", "TIMED_OUT", "REJECTED_STOCK"])
	return removed

static func _without_rows(rows: Array, field: String, ids: Array) -> Array:
	return rows.filter(func(row: Variant) -> bool: return not row is Dictionary or row.get(field) not in ids)

static func _erase(values: Variant, ids: Array) -> void:
	if values is Array or values is Dictionary:
		for id: String in ids:
			values.erase(id)
