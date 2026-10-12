class_name TDSanRules
extends RefCounted
## Phase 3 day rules. Window scale follows the attached outline formula.
## Visual decoys do not use the business random source.

const WAKE_HOUR := 6
const DARK_SCORE := 80.0
const DARK_SAN := 30.0
const DARK_CHANCE := 0.45
const DARK_ORDER_CHANCE := 0.03
const SUPPER_ORDER_CHANCE := 0.08

static func clamp_san(value: float) -> int:
	return clampi(int(round(value)), 0, 100)

static func window_scale(san: float) -> float:
	return 0.6 + 0.4 * clampf(san, 0.0, 100.0) / 100.0

static func vignette_alpha(san: float) -> float:
	return (100.0 - clampf(san, 0.0, 100.0)) / 100.0 * 0.62

static func shows_fake(san: float, note_index: int, seconds_until: float, beat_sec: float) -> bool:
	if san >= DARK_SAN or seconds_until <= beat_sec * 2.0:
		return false
	var span := (DARK_SAN - clampf(san, 0.0, DARK_SAN)) / DARK_SAN
	var roll := float(posmod(note_index * 37 + 11, 100)) / 100.0
	return roll < span * 0.85

static func dark_triggered(san: float, quality: float, unit: float) -> bool:
	return san < DARK_SAN and quality >= DARK_SCORE and unit < DARK_CHANCE

static func dark_order_chance(meal: String) -> float:
	if meal == "supper":
		return SUPPER_ORDER_CHANCE
	return DARK_ORDER_CHANCE

static func stock_minutes(distance: int, selected: bool) -> int:
	if not selected:
		return 60
	return 30 + maxi(0, distance) * 5

static func clean_minutes(cleaner: bool) -> int:
	return 0 if cleaner else 30

static func tidy_minutes(cleaner: bool, cashier: bool) -> int:
	var hands := (1 if cleaner else 0) + (1 if cashier else 0)
	return int(round(60.0 * (1.0 - 0.25 * float(hands))))

static func hour_points(hours: float, sign: int) -> int:
	return sign * int(round(maxf(0.0, hours) * 2.0))

static func overlaps(open_hour: int, close_hour: int, start: int, end: int) -> bool:
	return open_hour < end and close_hour > start

static func meals(open_hour: int, close_hour: int) -> Array:
	var rows: Array = []
	if overlaps(open_hour, close_hour, 6, 9):
		rows.append({"id": "breakfast", "name": "早餐", "guests": 2, "shift": -6})
	if overlaps(open_hour, close_hour, 11, 13):
		rows.append({"id": "lunch", "name": "午餐", "guests": 4, "shift": 0})
	if overlaps(open_hour, close_hour, 17, 20):
		rows.append({"id": "dinner", "name": "晚餐", "guests": 5, "shift": 8})
	if overlaps(open_hour, close_hour, 21, 22):
		rows.append({"id": "supper", "name": "夜宵", "guests": 1, "shift": 2})
	return rows

static func meal_guests(open_hour: int, close_hour: int) -> int:
	var total := 0
	for item: Variant in meals(open_hour, close_hour):
		total += int((item as Dictionary)["guests"])
	if total == 0:
		return -4
	return total

static func near_bonus(distance: int) -> int:
	return maxi(0, 10 - maxi(0, distance) / 2)

static func recovery(kind: String) -> Dictionary:
	var table := {
		"plaza": {"hours": 1.0, "cost": 4, "san": 4},
		"amusement": {"hours": 2.0, "cost": 18, "san": 10},
		"landmark": {"hours": 1.0, "cost": 8, "san": 6},
		"snack_street": {"hours": 1.0, "cost": 6, "san": 3},
		"commercial_street": {"hours": 1.0, "cost": 12, "san": 5},
		"zoo": {"hours": 2.0, "cost": 10, "san": 8},
		"urban_village": {"hours": 1.0, "cost": 2, "san": 2},
		"rich_district": {"hours": 1.0, "cost": 20, "san": 8},
	}
	if not table.has(kind):
		return {}
	return (table[kind] as Dictionary).duplicate(true)

static func day_plan(open_hour: int, close_hour: int, distance: int, selected: bool, cleaner: bool, cashier: bool) -> Dictionary:
	var stock := stock_minutes(distance, selected)
	var clean := clean_minutes(cleaner)
	var service := maxi(0, close_hour - open_hour) * 60
	var tidy := tidy_minutes(cleaner, cashier)
	var prep := float(stock + clean) / 60.0
	var tidy_hours := float(tidy) / 60.0
	var morning := maxf(0.0, float(open_hour) - prep - float(WAKE_HOUR))
	var evening := maxf(0.0, 24.0 - (float(close_hour) + tidy_hours))
	return {
		"stock_minutes": stock,
		"clean_minutes": clean,
		"service_minutes": service,
		"tidy_minutes": tidy,
		"work_hours": float(stock + clean + service + tidy) / 60.0,
		"morning_free_hours": morning,
		"evening_free_hours": evening,
		"meals": meals(open_hour, close_hour),
		"meal_guests": meal_guests(open_hour, close_hour),
	}
