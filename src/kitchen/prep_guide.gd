class_name TDPrepGuide
extends RefCounted
## The recipe tree and the cutting board share this reading of existing charts.
## It does not change unlock scores, inspiration, or how a cut is judged.

static var _ready: bool = false
static var _by_id: Dictionary = {}
static var _by_name: Dictionary = {}
static var _recipes: Dictionary = {}
static var _cooking: Dictionary = {}
static var _rules: Dictionary = {}

const STEPS := {
	"preheat": "预热",
	"cut": "切配",
	"stir": "翻炒",
	"heat": "控温",
	"season": "调味",
	"plate": "出锅",
	"boil": "煮",
	"steam": "蒸",
	"stew": "炖",
}

static func ensure() -> void:
	if _ready:
		return
	_ready = true
	_rules = TDFoodStock.load_rules()
	var service := TDServiceCatalog.new()
	if not service.load_file().ok:
		return
	TDResearchRuntime.install(service)
	_cooking = service.cooking.data()
	for food: Dictionary in _cooking.ingredients:
		_by_id[String(food.id)] = food
		_by_name[String(food.name)] = food
	for recipe: Dictionary in _cooking.recipes:
		_recipes[String(recipe.id)] = recipe

static func food(id: String) -> Dictionary:
	ensure()
	return (_by_id.get(id, {}) as Dictionary).duplicate(true)

static func handling(food: Dictionary, recipe: Dictionary = {}) -> String:
	if food.is_empty():
		return ""
	var id := String(food.get("id", ""))
	var parts: PackedStringArray = []
	var label := _sheet_label(recipe, id)
	if label != "":
		parts.append("按谱「%s」。" % label)
	var requirement := _requirement(recipe, id)
	var fine := _fine_text(requirement)
	if fine != "":
		parts.append(fine)
	if not requirement.is_empty() and float(requirement.get("min_heat_dose", 0.0)) > 0.0:
		parts.append("还要真正上过火。")
	if label == "":
		parts.append(_category_text(food))
	return "".join(parts)

static func unlock_text(status: String, starter: bool) -> String:
	if status == "UNLOCKED" and starter:
		return "解锁：开局就会。不用花灵感，食材铺按这道菜的主料供货。"
	if status == "UNLOCKED":
		return "解锁：研习成绩到了 80。学会以后，它的主料才在食材铺出现。"
	if status == "STORY_LOCKED":
		return "解锁：这一菜系要等剧情推荐。树上看得见，现在不能研习，也不会因此开卖新主料。"
	if status == "PREREQUISITES":
		return "解锁：先掌握金线连着的全部前置。差一道都不算。"
	if status == "CHART_PENDING":
		return "解锁：前置够了，但这道菜还没有研习谱面。点开会被拒绝，也不扣灵感。"
	if status == "POINTS_SHORT":
		return "解锁：前置和谱面都齐，灵感不够。营业里每道菜每天第一次 80 分可以得 1 点灵感。"
	if status == "RESEARCHABLE":
		return "解锁：资格已经买下。再进真实厨房打到 80 分就掌握，这次不另扣灵感。"
	if status == "AVAILABLE":
		return "解锁：花灵感进真实厨房。80 分掌握，失败立刻免费重试。学会后主料进货单才开放。"
	return "解锁：" + status

static func obtain_text(food: Dictionary, status: String) -> String:
	var id := String(food.get("id", ""))
	if bool(_rules.get(id, {}).get("condiment", false)) or String(food.get("category", "")) == "seasoning":
		return "食材铺一直卖，不跟菜谱解锁。"
	if status == "UNLOCKED":
		return "这道菜已经掌握，作为主料可以买。库里原有的也不会被清掉。"
	return "要等这道菜掌握之后，食材铺才把它当主料卖。"

static func recipe_lines(session: TDResearchSession, id: String) -> PackedStringArray:
	var lines: PackedStringArray = []
	var node := session.catalog.node(id)
	if node.is_empty():
		return lines
	var status := session.status(id)
	var starter: bool = id in session.catalog.data.unlock_rules.initial_unlocked_ids
	lines.append(unlock_text(status, starter))
	var recipe := _kitchen_recipe(session.catalog, id)
	var steps := _step_text(recipe)
	if steps != "":
		lines.append(steps)
	for item: Dictionary in _foods_for(session.catalog, node, recipe):
		lines.append("%s：%s%s" % [String(item.name), handling(item, recipe), obtain_text(item, status)])
	if lines.size() == 1:
		lines.append("食材线索仍是：%s。它们还没对上厨房里的原料编号。" % String(node.ingredients))
	return lines

static func handling_for_id(id: String, recipe_id: String = "") -> String:
	var found := food(id)
	if found.is_empty():
		return ""
	ensure()
	var recipe: Dictionary = _recipes.get(recipe_id, {})
	return "%s：%s" % [String(found.name), handling(found, recipe)]

static func _kitchen_recipe(catalog: TDResearchCatalog, id: String) -> Dictionary:
	ensure()
	var mapped := catalog.runtime_id(id)
	var chart := catalog.chart(id)
	for key: String in [String(chart.get("recipe_id", "")), mapped, "study." + mapped]:
		if key != "" and _recipes.has(key):
			return _recipes[key]
	return {}

static func _foods_for(catalog: TDResearchCatalog, node: Dictionary, recipe: Dictionary) -> Array:
	ensure()
	var found: Array = []
	var seen: Dictionary = {}
	for raw: Variant in recipe.get("required_ingredients", []):
		if raw is Dictionary:
			_add(found, seen, String(raw.get("id", "")))
	var chart := catalog.chart(String(node.id))
	if not chart.is_empty():
		for raw: Variant in chart.primary:
			_add(found, seen, String(raw))
	for part: String in String(node.ingredients).split("、"):
		var name := part.strip_edges()
		if _by_name.has(name):
			_add(found, seen, String((_by_name[name] as Dictionary).id))
	return found

static func _add(found: Array, seen: Dictionary, id: String) -> void:
	if id.is_empty() or seen.has(id) or not _by_id.has(id):
		return
	seen[id] = true
	found.append(_by_id[id])

static func _sheet_label(recipe: Dictionary, id: String) -> String:
	var sheet_id := String(recipe.get("preparation_sheets", {}).get(id, ""))
	if sheet_id == "":
		return ""
	var sheets: Dictionary = _cooking.get("pc_operations", {}).get("document_sheets", {})
	var sheet: Dictionary = sheets.get(sheet_id, {})
	var label := String(sheet.get("groups", {}).get("cut", {}).get("label", ""))
	if label == "":
		label = String(sheet.get("dish", ""))
	return label

static func _requirement(recipe: Dictionary, id: String) -> Dictionary:
	for raw: Variant in recipe.get("required_ingredients", []):
		if raw is Dictionary and String(raw.get("id", "")) == id:
			return raw
	return {}

static func _fine_text(requirement: Dictionary) -> String:
	if requirement.is_empty() or not _cooking.has("cut_shapes"):
		return ""
	var low := float(requirement.get("min_fine", 0.0))
	var high := float(requirement.get("max_fine", 1.0))
	if low <= 0.0 and high >= 1.0:
		return ""
	var names: PackedStringArray = []
	for shape: String in ["slice", "chunk", "strip", "dice"]:
		var entry: Dictionary = _cooking.cut_shapes.get(shape, {})
		if entry.is_empty():
			continue
		var fine := float(entry.get("fine", -1.0))
		if fine + 0.0001 >= low and fine - 0.0001 <= high:
			names.append(String(entry.name))
	if names.is_empty():
		return "细碎度要落在这道菜自己的范围内。"
	return "谱面接受%s。" % "、".join(names)

static func _category_text(food: Dictionary) -> String:
	var category := String(food.get("category", ""))
	var name := String(food.get("name", ""))
	if name in ["水", "清水", "高汤", "清汤"] or category == "liquid":
		return "不用切。它负责煮和蒸，按谱加入。"
	if bool(_rules.get(String(food.get("id", "")), {}).get("condiment", false)) or category == "seasoning":
		return "不切。调味时按住，到目标用量松开；加多了会盖住主味。"
	if category == "protein":
		return "整份下锅。热锅快炒或蒸，见嫩就停，切碎会老。"
	if category == "meat":
		return "先切条或块再煸。两刀同向是条，中途转向是块；不要煮到中心发干。"
	if category in ["seafood", "fish"]:
		return "少翻。到刚熟的窗口就出锅，久煮会柴。"
	if category == "nuts":
		return "最后撒上，保持脆，不要跟主料一起炒老。"
	if category in ["grain", "noodle", "dough", "starch"]:
		return "不拿来切。下锅煮到刚好。"
	return "上砧板。家常用大块，要入味用条，爆香才切丁。两刀同向是条，中途转向是块，三刀起是丁。"

static func _step_text(recipe: Dictionary) -> String:
	var source: Array = recipe.get("required_steps", [])
	if source.is_empty():
		source = recipe.get("recommended_steps", [])
	var names: PackedStringArray = []
	for step: Variant in source:
		var label := String(STEPS.get(String(step), ""))
		if label != "" and label not in names:
			names.append(label)
	if names.is_empty():
		return ""
	return "工序按谱推进，不能自选下一道：%s。" % "、".join(names)
