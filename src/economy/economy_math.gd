class_name TDEconomyMath
extends RefCounted

## Phase 3 formulas from doc/agent_prompts/经济系统草稿.md.
## 装修效果把统一度百分数换成 0–1，避免 0–100 相乘冲出评价量纲。ASSUMPTION。
## 展示用评价夹到 0–100；选店用的竞争优势保留未夹取的前评价，否则开局全是负数时无法比较。

const STAR_EDGES := [40.0, 60.0, 80.0, 90.0]

static func reference_price(ingredient_cost: float, labor_factor: float, value_offset: float) -> float:
	return ingredient_cost * labor_factor + value_offset

static func budget_from_unit(unit: float) -> int:
	var u := clampf(unit, 0.0, 1.0)
	var low := 15.0
	var mode := 50.0
	var high := 130.0
	var span := high - low
	var left := (mode - low) / span
	var value := low
	if u <= left:
		value = low + sqrt(u * span * (mode - low))
	else:
		value = high - sqrt((1.0 - u) * span * (high - mode))
	return maxi(15, int(round(value)))

static func decor_of(pieces: Array, wildcards: Array) -> Dictionary:
	var counts := {}
	for item: Variant in pieces:
		var style := _style(item)
		if wildcards.has(style["culture"]):
			continue
		counts[style["culture"]] = int(counts.get(style["culture"], 0)) + 1
	var majority := ""
	var best := -1
	for key: Variant in counts.keys():
		var amount := int(counts[key])
		if amount > best:
			best = amount
			majority = String(key)
	var unity := 0.0
	var luxury_sum := 0.0
	var count := 0
	for item: Variant in pieces:
		count += 1
		var style := _style(item)
		var culture := String(style["culture"])
		if wildcards.has(culture):
			unity += 10.0
		elif majority == "" or culture == majority:
			unity += 14.0
		else:
			unity -= 3.0
		if String(style["tier"]) == "high":
			unity += 2.0
			luxury_sum += 85.0
		else:
			luxury_sum += 30.0
	if count == 0:
		return {"unity": 0.0, "luxury": 0.0, "effect": 0.0, "majority": ""}
	unity = clampf(unity, 0.0, 100.0)
	var luxury := luxury_sum / float(count)
	return {
		"unity": unity,
		"luxury": luxury,
		"effect": unity / 100.0 * luxury,
		"majority": majority,
	}

static func expectations(budget: int) -> Dictionary:
	return {
		"decor": clampf(float(budget) * 0.85, 0.0, 100.0),
		"quality": clampf(28.0 + float(budget) * 0.64, 1.0, 100.0),
		"reputation": clampf(0.25 + float(budget) / 180.0, 0.0, 1.0),
	}

static func type_preference(dish_culture: String, preferences: Array) -> float:
	return 1.0 if preferences.has(dish_culture) else 0.3

static func style_preference(majority: String, wildcards: Array, preferences: Array) -> float:
	if majority == "" or wildcards.has(majority) or preferences.has(majority):
		return 1.0
	return 0.42

static func pre_dish(budget: float, price: float, reference: float, type_pref: float) -> float:
	if reference <= 0.0 or price <= 0.0:
		return 0.0
	var price_ratio := price / reference
	var gap := budget - reference
	if absf(gap) < 0.000001:
		if absf(price - reference) < 0.000001:
			return 100.0 / price_ratio * type_pref
		return 0.0
	return (budget - price) / gap * 100.0 / price_ratio * type_pref

static func pre_decor(effect: float, expectation: float, style_pref: float) -> float:
	return (effect - expectation) * style_pref

static func reputation_score(good_count: int, bad_count: int) -> float:
	return 100.0 * float(good_count) - 5000.0 * float(bad_count)

static func pre_brand(reputation: float, brand_good_count: int, reputation_pref: float) -> float:
	return reputation * (1.0 + 0.01 * float(brand_good_count)) * reputation_pref

static func advantage(dish_pre: float, decor_pre: float, brand_pre: float) -> float:
	return dish_pre + decor_pre + brand_pre

static func dish_review(dish_pre: float, quality: float, quality_expect: float) -> float:
	if quality_expect <= 0.0:
		return 0.0
	return dish_pre * (quality / quality_expect)

static func overall_raw(decor_pre: float, brand_pre: float, reviewed_dish: float) -> float:
	return (decor_pre + brand_pre + reviewed_dish) / 3.0

static func brand_review(overall_value: float, brand_pre: float) -> float:
	return (overall_value + brand_pre) / 2.0

static func decor_review(overall_value: float, decor_pre: float) -> float:
	return (overall_value + decor_pre) / 2.0

static func present(value: float) -> float:
	return clampf(value, 0.0, 100.0)

static func stars(presented: float) -> int:
	var score := present(presented)
	if score < STAR_EDGES[0]:
		return 1
	if score < STAR_EDGES[1]:
		return 2
	if score < STAR_EDGES[2]:
		return 3
	if score < STAR_EDGES[3]:
		return 4
	return 5

static func is_good(presented: float) -> bool:
	return present(presented) >= 80.0

static func is_bad(presented: float) -> bool:
	return present(presented) < 40.0

static func preference_roll_count(budget: int, foreign_scale: float, first: float, second: float, third: float) -> int:
	var extra := 0
	var scale := maxf(foreign_scale, 0.0)
	if budget >= 45 and first < minf(0.98, (float(budget) - 25.0) / 55.0) * scale:
		extra += 1
	if budget >= 75 and second < minf(0.98, (float(budget) - 50.0) / 40.0) * scale:
		extra += 1
	if budget >= 105 and third < 0.9 * scale:
		extra += 1
	return extra

static func pool_plan(base: int, zones: Array, housing_enabled: int, housing_cap: int) -> Dictionary:
	var bonus := 0
	var shift := 0
	var scale_sum := 0.0
	var scale_count := 0
	var rows: Array = []
	for item: Variant in zones:
		var zone: Dictionary = item
		var enabled := bool(zone.get("enabled", true))
		var pool := int(zone.get("pool", 0))
		var zone_shift := int(zone.get("budget_shift", 0))
		var scale := float(zone.get("foreign_scale", 1.0))
		if enabled:
			bonus += pool
			shift += zone_shift
			scale_sum += scale
			scale_count += 1
		rows.append({
			"id": String(zone.get("id", "")),
			"name": String(zone.get("name", "")),
			"enabled": enabled,
			"pool": pool,
			"budget_shift": zone_shift,
			"foreign_scale": scale,
		})
	var houses := mini(maxi(housing_enabled, 0), housing_cap)
	bonus += houses
	var foreign := 1.0 if scale_count == 0 else scale_sum / float(scale_count)
	return {
		"count": maxi(0, base + bonus),
		"budget_shift": shift,
		"foreign_scale": foreign,
		"housing": houses,
		"rows": rows,
	}

static func evaluate_offer(budget: float, price: float, reference: float, type_pref: float, effect: float, decor_expect: float, style_pref: float, good_count: int, bad_count: int, reputation_pref: float) -> Dictionary:
	var dish_pre := pre_dish(budget, price, reference, type_pref)
	var decor_pre := pre_decor(effect, decor_expect, style_pref)
	var reputation := reputation_score(good_count, bad_count)
	var brand_pre := pre_brand(reputation, good_count, reputation_pref)
	return {
		"pre_dish": dish_pre,
		"pre_decor": decor_pre,
		"pre_brand": brand_pre,
		"advantage": advantage(dish_pre, decor_pre, brand_pre),
		"reputation": reputation,
	}

static func evaluate_meal(offer: Dictionary, quality: float, quality_expect: float) -> Dictionary:
	var reviewed := dish_review(float(offer["pre_dish"]), quality, quality_expect)
	var raw := overall_raw(float(offer["pre_decor"]), float(offer["pre_brand"]), reviewed)
	var shown := present(raw)
	var brand := present(brand_review(raw, float(offer["pre_brand"])))
	var decor := present(decor_review(raw, float(offer["pre_decor"])))
	return {
		"dish_review": reviewed,
		"overall_raw": raw,
		"overall": shown,
		"brand_review": brand,
		"decor_review": decor,
		"stars": stars(shown),
		"good": is_good(shown),
		"bad": is_bad(shown),
	}

static func _style(item: Variant) -> Dictionary:
	var piece: Dictionary = item
	var parts := String(piece.get("style_id", "plain_low")).split("_")
	var culture := parts[0] if not parts.is_empty() else "plain"
	var tier := parts[1] if parts.size() > 1 else "low"
	return {"culture": culture, "tier": tier}
