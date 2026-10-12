class_name TDBranchSim
extends RefCounted

static func guest_count(town_culture: String, dish_culture: String, price: int, reference: float, prep_on: bool) -> int:
	var count := 4
	if town_culture != "" and town_culture == dish_culture:
		count += 3
	elif dish_culture != "" and dish_culture != "plain":
		count -= 2
	elif dish_culture == "plain":
		count += 1
	if reference > 0.0 and float(price) > reference * 1.25:
		count -= 2
	if prep_on:
		count += 1
	return clampi(count, 0, 8)

static func cook_quality(dish_proficiency: int) -> int:
	return clampi(70 + int((dish_proficiency - 50) / 5.0), 40, 96)

static func quality_shift(mood: int, drive: String, care: String, wage: int, recommended: int) -> int:
	var shift := int((clampi(mood, 0, 100) - 50) / 10.0)
	if drive == "diligent":
		shift += 4
	elif drive == "lazy":
		shift -= 4
	if care == "careful":
		shift += 3
	elif care == "careless":
		shift -= 6
	if recommended > 0 and wage > recommended:
		shift += mini(8, wage - recommended)
	elif recommended > 0 and wage < recommended:
		shift -= mini(8, recommended - wage)
	return shift

static func service_quality(base: int, mood: int, drive: String, care: String, wage: int, recommended: int) -> int:
	return clampi(base + quality_shift(mood, drive, care, wage, recommended), 40, 96)

static func mood_delta(wage: int, recommended: int, drive: String) -> int:
	var delta := 1
	if recommended > 0 and wage > recommended:
		delta = mini(8, wage - recommended)
	elif recommended > 0 and wage < recommended:
		delta = -mini(12, recommended - wage)
	if drive == "diligent":
		delta += 2
	elif drive == "lazy":
		delta -= 3
	return delta

static func drive_name(drive: String) -> String:
	if drive == "diligent":
		return "勤奋"
	if drive == "lazy":
		return "懒惰"
	return "平常"

static func care_name(care: String) -> String:
	if care == "careful":
		return "认真"
	if care == "careless":
		return "马虎"
	return "平常"

static func accident_chance(role_proficiency: int, care: String = "", drive: String = "", mood: int = 50) -> float:
	var chance := 0.15 - float(role_proficiency) / 1000.0
	if care == "careless":
		chance += 0.08
	elif care == "careful":
		chance -= 0.04
	if drive == "lazy":
		chance += 0.04
	elif drive == "diligent":
		chance -= 0.03
	if mood < 40:
		chance += 0.05
	return clampf(chance, 0.02, 0.45)
