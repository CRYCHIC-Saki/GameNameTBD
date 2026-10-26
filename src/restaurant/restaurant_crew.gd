class_name TDRestaurantCrew
extends RefCounted
## Restaurant hiring experiment. Cooks work the kitchen; waiters carry plates.
## The same buff does not stack. This roster is not the town NPC payroll.

const MAX_PER_ROLE := 2
const MAX_LEVEL := 5
const ORDERS_PER_LEVEL := 4
const PACE_CAP := 0.25
const NUDGE_CAP := 0.2
const TIP_CAP := 0.25
const ROSTER: Array[Dictionary] = [
	{"id": "cook-he", "role": "cook", "name": "阿禾", "wage_yuan": 23, "buff": "", "blurb": "在后厨做菜。"},
	{"id": "cook-zhou", "role": "cook", "name": "老周", "wage_yuan": 28, "buff": "faster_service", "blurb": "出餐更快。"},
	{"id": "cook-man", "role": "cook", "name": "小满", "wage_yuan": 26, "buff": "secondary", "blurb": "出锅后修正口味、香味、口感和温度。"},
	{"id": "waiter-ning", "role": "waiter", "name": "阿宁", "wage_yuan": 29, "buff": "", "blurb": "在店里端菜。"},
	{"id": "waiter-tao", "role": "waiter", "name": "小桃", "wage_yuan": 32, "buff": "tip", "blurb": "端菜时增加小费。"},
]

var hired: Array[String] = []
var progress: Dictionary = {}

func roster() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for item: Dictionary in ROSTER:
		var row := item.duplicate()
		row["hired"] = hired.has(String(item["id"]))
		row["wage_cents"] = int(item["wage_yuan"]) * 100
		row["level"] = level_of(String(item["id"]))
		row["xp"] = xp_of(String(item["id"]))
		row["blurb"] = describe(String(item["id"]))
		rows.append(row)
	return rows

func person(id: String) -> Dictionary:
	for item: Dictionary in ROSTER:
		if String(item["id"]) == id:
			return item
	return {}

func can_hire(id: String) -> TDOutcome:
	var who := person(id)
	if who.is_empty():
		return TDOutcome.new(false, "MISSING", "没有这个应聘者。")
	if hired.has(id):
		return TDOutcome.new(false, "ALREADY", "%s已经在店里。" % String(who["name"]))
	if _count(String(who["role"])) >= MAX_PER_ROLE:
		return TDOutcome.new(false, "FULL", "%s最多%d人。" % [_role_name(String(who["role"])), MAX_PER_ROLE])
	return TDOutcome.new(true, "READY", "")

func hire(id: String) -> TDOutcome:
	var check := can_hire(id)
	if not check.ok:
		return check
	hired.append(id)
	var who := person(id)
	if not progress.has(id):
		progress[id] = 0
	return TDOutcome.new(true, "HIRED", "%s入职，目前%d级。今日日薪%d元。同一加成不叠加。" % [String(who["name"]), level_of(id), int(who["wage_yuan"])])

func dismiss(id: String) -> TDOutcome:
	if not hired.has(id):
		return TDOutcome.new(false, "MISSING", "这个人没在店里。")
	hired.erase(id)
	return TDOutcome.new(true, "DISMISSED", "%s已辞退，日薪不退。" % String(person(id)["name"]))

func cooks() -> Array[Dictionary]:
	return _role("cook")

func waiters() -> Array[Dictionary]:
	return _role("waiter")

func level_of(id: String) -> int:
	return clampi(1 + xp_of(id) / ORDERS_PER_LEVEL, 1, MAX_LEVEL)

func xp_of(id: String) -> int:
	return int(progress.get(id, 0))

func describe(id: String) -> String:
	var level := level_of(id)
	var growth := "满级" if level >= MAX_LEVEL else "经验 %d/%d" % [xp_of(id) % ORDERS_PER_LEVEL, ORDERS_PER_LEVEL]
	return "%d级 · %s · %s" % [level, growth, _skill_line(String(person(id).get("buff", "")), level)]

func record_served_order() -> Array[String]:
	var notes: Array[String] = []
	var cap := (MAX_LEVEL - 1) * ORDERS_PER_LEVEL
	for id: String in hired:
		var before := level_of(id)
		progress[id] = mini(cap, xp_of(id) + 1)
		var after := level_of(id)
		if after > before:
			notes.append("%s升到%d级" % [String(person(id).get("name", id)), after])
	return notes

func cook_pace() -> float:
	return 1.0 + PACE_CAP * _ratio("faster_service")

func tip_scale() -> float:
	return 1.0 + TIP_CAP * _ratio("tip")

func duty_line() -> String:
	if hired.is_empty():
		return ""
	var parts: Array[String] = []
	for id: String in hired:
		var who := person(id)
		parts.append("%s（%s）" % [String(who["name"]), describe(id)])
	return "在岗：" + "、".join(parts)

func apply_dish(dish: Dictionary, customer: Dictionary) -> Dictionary:
	if not _has_buff("secondary") or not customer.get("requirements") is Array:
		return dish
	var copy := dish.duplicate(true)
	if not copy.get("dish_attributes") is Dictionary:
		return copy
	for requirement: Variant in customer["requirements"]:
		if requirement is Dictionary:
			_nudge(copy, requirement)
	return copy

func export_ids() -> Array:
	var rows: Array = []
	for id: String in hired:
		rows.append(id)
	return rows

func export_state() -> Array:
	var rows: Array = []
	var listed := {}
	for id: String in hired:
		rows.append({"id": id, "xp": xp_of(id)})
		listed[id] = true
	for key: Variant in progress.keys():
		var id := String(key)
		if listed.has(id) or person(id).is_empty() or xp_of(id) <= 0:
			continue
		rows.append({"id": id, "xp": xp_of(id), "hired": false})
	return rows

func restore(value: Variant) -> TDOutcome:
	if not value is Array:
		return TDOutcome.new(false, "INVALID_CREW", "雇员记录无效。")
	var next: Array[String] = []
	var next_xp := {}
	var seen := {}
	for item: Variant in value:
		var id := ""
		var xp := 0
		var on_duty := true
		if item is String:
			id = String(item)
		elif item is Dictionary:
			var record: Dictionary = item
			id = String(record.get("id", ""))
			if record.has("xp"):
				# JSON reads whole numbers back as floats. Boundary saves must still load.
				if not TDServiceCatalog.integer(record["xp"], 0, (MAX_LEVEL - 1) * ORDERS_PER_LEVEL):
					return TDOutcome.new(false, "INVALID_CREW", "雇员经验无效。")
				xp = int(record["xp"])
			if record.has("hired"):
				if not record["hired"] is bool:
					return TDOutcome.new(false, "INVALID_CREW", "雇员在岗记录无效。")
				on_duty = bool(record["hired"])
		else:
			return TDOutcome.new(false, "INVALID_CREW", "雇员记录里有不认识的人。")
		if person(id).is_empty() or seen.has(id):
			return TDOutcome.new(false, "INVALID_CREW", "雇员记录里有不认识的人。")
		seen[id] = true
		next_xp[id] = xp
		if not on_duty:
			continue
		next.append(id)
		if _count_in(next, String(person(id)["role"])) > MAX_PER_ROLE:
			return TDOutcome.new(false, "INVALID_CREW", "同一类雇员超过上限。")
	hired = next
	progress = next_xp
	return TDOutcome.new(true, "CREW_RESTORED")

func _nudge(dish: Dictionary, requirement: Dictionary) -> void:
	var attributes: Dictionary = dish["dish_attributes"]
	var target := _target(requirement)
	if is_nan(target):
		return
	var kind := String(requirement.get("kind", ""))
	match kind:
		"flavor":
			var taste := int(requirement.get("taste", -1))
			var slot := int(requirement.get("slot", -1))
			if not attributes.get("flavor") is Array or taste < 0 or slot < 0:
				return
			var rows: Array = attributes["flavor"]
			if taste >= rows.size() or not rows[taste] is Array or slot >= (rows[taste] as Array).size():
				return
			var line: Array = rows[taste]
			line[slot] = _toward(float(line[slot]), target, 0.0, 100.0, _pull("secondary"))
			rows[taste] = line
		"aroma":
			var tag := String(requirement.get("tag", ""))
			if tag.is_empty() or not attributes.get("aroma") is Dictionary or not (attributes["aroma"] as Dictionary).has(tag):
				return
			attributes["aroma"][tag] = _toward(float(attributes["aroma"][tag]), target, 0.0, 100.0, _pull("secondary"))
		"texture":
			var axis := String(requirement.get("axis", ""))
			if axis not in ["A", "B", "C"] or not attributes.get("texture") is Dictionary:
				return
			if not (attributes["texture"] as Dictionary).has(axis):
				return
			attributes["texture"][axis] = _toward(float(attributes["texture"][axis]), target, -1.0, 1.0, _pull("secondary"))
		"temperature":
			if not attributes.has("temperature_c"):
				return
			attributes["temperature_c"] = _toward(float(attributes["temperature_c"]), target, 0.0, 120.0, _pull("secondary"))

func _number(value: Variant) -> bool:
	return value is int or value is float

func _target(requirement: Dictionary) -> float:
	var has_min := _number(requirement.get("min"))
	var has_max := _number(requirement.get("max"))
	if has_min and has_max:
		return (float(requirement["min"]) + float(requirement["max"])) * 0.5
	if has_min:
		return float(requirement["min"])
	if has_max:
		return float(requirement["max"])
	return NAN

func _toward(current: float, target: float, low: float, high: float, pull: float) -> float:
	return clampf(current + (target - current) * pull, low, high)

func _pull(buff: String) -> float:
	return NUDGE_CAP * _ratio(buff)

func _ratio(buff: String) -> float:
	return float(_best_level(buff)) / float(MAX_LEVEL)

func _best_level(buff: String) -> int:
	var best := 0
	for id: String in hired:
		if String(person(id).get("buff", "")) != buff:
			continue
		best = maxi(best, level_of(id))
	return best

func _skill_line(buff: String, level: int) -> String:
	var ratio := float(level) / float(MAX_LEVEL)
	match buff:
		"faster_service":
			return "新订单可等待时间 +%d%%" % roundi(PACE_CAP * ratio * 100.0)
		"secondary":
			return "口味、香味、口感、温度向客人要求拉近 %d%%" % roundi(NUDGE_CAP * ratio * 100.0)
		"tip":
			return "小费 +%d%%" % roundi(TIP_CAP * ratio * 100.0)
		_:
			return "没有额外手艺"

func _has_buff(buff: String) -> bool:
	for id: String in hired:
		if String(person(id).get("buff", "")) == buff:
			return true
	return false

func _role(role: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for id: String in hired:
		var who := person(id).duplicate()
		who["level"] = level_of(id)
		who["xp"] = xp_of(id)
		if String(who.get("role", "")) == role:
			rows.append(who)
	return rows

func _count(role: String) -> int:
	return _count_in(hired, role)

func _count_in(ids: Array[String], role: String) -> int:
	var count := 0
	for id: String in ids:
		if String(person(id).get("role", "")) == role:
			count += 1
	return count

func _role_name(role: String) -> String:
	return "厨师" if role == "cook" else "服务员"
