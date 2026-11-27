class_name TDStoryEvents
extends RefCounted
## Authored event definitions are content; only completion counts belong to a profile.
const PATH := "res://content/story/events.json"
const ROOT := "res://content/story/vn/scenario/"
const PEOPLE := {"aling":"阿铃", "chen":"老陈"}
const PLACES := {"restaurant":"主店餐厅", "kitchen":"主店厨房", "cottage":"小屋", "town:chengdu":"臻味港", "town:tokyo":"和味道", "town:paris":"稀味郡"}
const MILESTONES := {"intro":"港口介绍完成", "soup":"老陈介绍完成", "after_taste":"尝汤剧情完成", "awaken":"进入食堂教学完成", "trial_served":"首次番茄炒蛋送到阿铃", "verdict":"阿铃试吃评价完成", "business_opened":"首次开门营业", "day_settled":"首次营业日结", "home_unlocked":"小屋已解锁", "chapter_finished":"第一章完成"}
const CUISINES := {"cn":"中式", "eu":"欧洲", "jp":"日本"}
const TOWNS := {"chengdu":"臻味港", "tokyo":"和味道", "paris":"稀味郡"}
var definitions: Array = []
var error: String = ""
var counts: Dictionary = {}
var pending: Array[String] = []
var observed: Dictionary = {}
var active: Dictionary = {}
var serial: int = 0

func _init(path: String = PATH) -> void:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	error = validate_catalog(raw)
	if error.is_empty(): definitions = raw.events.duplicate(true)

static func valid_id(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length() > 80: return false
	for letter: String in value:
		if not letter in "abcdefghijklmnopqrstuvwxyz0123456789_-": return false
	return true

static func validate_catalog(raw: Variant, check_files: bool = true) -> String:
	if not raw is Dictionary or raw.get("schema_version") != 1 or not raw.get("events") is Array: return "剧情触发配置版本或格式无效。"
	var ids := {}; var scripts := {}
	for row: Variant in raw.events:
		if not row is Dictionary or not valid_id(row.get("id")) or ids.has(row.id): return "剧情触发ID无效或重复。"
		if not row.get("title") is String or row.title.strip_edges().is_empty() or row.title.length() > 80: return "请填写演出名称（80字以内）。"
		if not row.get("enabled") is bool or not row.get("repeat") is bool: return "启用或重复设置无效。"
		var target: Variant = row.get("target")
		var choices: Dictionary = {"person":PEOPLE,"place":PLACES,"milestone":MILESTONES}.get(row.get("type"),{})
		if not target is String or not choices.has(target): return "请选择有效的触发对象。"
		if not row.get("requires") is String or not row.get("milestone_required") is String: return "前置条件无效。"
		if row.milestone_required != "" and not MILESTONES.has(row.milestone_required): return "前置任务节点不存在。"
		var path: Variant = row.get("script_path")
		if not path is String or not path.begins_with(ROOT) or not path.ends_with(".txt") or path.contains("..") or path == ROOT+"intro/script.txt" or scripts.has(path): return "每段新演出只可登记一次；不能覆盖港口开篇。"
		if check_files and row.enabled and not FileAccess.file_exists(path) and not ResourceLoader.exists(path+".res"): return "找不到演出剧本："+path
		var effect: Variant = row.get("effect")
		if not effect is Dictionary or effect.get("kind") not in ["none","cuisine","route"] or not effect.get("target") is String: return "完成效果无效。"
		if effect.kind == "cuisine" and not CUISINES.has(effect.target): return "菜系不存在。"
		if effect.kind == "route" and not TOWNS.has(effect.target): return "商路不存在。"
		if effect.kind == "none" and effect.target != "": return "无完成效果时不应填写目标。"
		ids[row.id] = row; scripts[path] = true
	for id: String in ids:
		var seen := {}; var cursor: String = id
		while cursor != "":
			if not ids.has(cursor): return "前置演出不存在。"
			if seen.has(cursor): return "演出前置条件形成循环。"
			seen[cursor] = true; cursor = ids[cursor].requires
	return ""

static func validate_progress(raw: Variant) -> bool:
	if not raw is Dictionary or raw.get("schema_version") != 1 or not raw.get("counts") is Dictionary: return false
	for id: Variant in raw.counts:
		if not valid_id(id) or not TDServiceCatalog.integer(raw.counts[id],1,1000000): return false
	return true

func snapshot() -> Dictionary:
	return {"schema_version":1,"counts":counts.duplicate(true)}

func restore(raw: Dictionary = {"schema_version":1,"counts":{}}) -> void:
	counts = {}
	for id: String in raw.counts: counts[id] = int(raw.counts[id])
	cancel(); pending.clear(); observed.clear()

static func validate_authored_source(source: String) -> String:
	for line: String in source.split("\n"):
		var command := line.strip_edges().get_slice(" ",0)
		if command in ["@td_name","@goto_chapter","@ending","@return","@call"]: return "新触发演出不能更改主角姓名或跳到其他章节。"
	return ""

func definition(id: String) -> Dictionary:
	for row: Dictionary in definitions:
		if row.id == id: return row.duplicate(true)
	return {}

func eligible(row: Dictionary, milestones: Dictionary) -> bool:
	return row.enabled and (row.repeat or not counts.has(row.id)) and (row.requires == "" or counts.has(row.requires)) and (row.milestone_required == "" or milestones.get(row.milestone_required,false))

func notify(kind: String, target: String, milestones: Dictionary) -> void:
	if not error.is_empty(): return
	for row: Dictionary in definitions:
		if row.type == kind and row.target == target and eligible(row,milestones) and row.id not in pending and active.get("id") != row.id: pending.append(row.id)

func observe(milestones: Dictionary) -> void:
	# Dependencies can become ready after a milestone; edge is per event, not only node.
	for row: Dictionary in definitions:
		if row.type != "milestone": continue
		var ready: bool = milestones.get(row.target,false) and eligible(row,milestones)
		if ready and not observed.get(row.id,false): notify("milestone",row.target,milestones)
		observed[row.id] = ready

func begin_next(milestones: Dictionary, place: String, boundary: bool) -> Dictionary:
	if not active.is_empty(): return {}
	for id: String in pending.duplicate():
		var row := definition(id)
		if row.is_empty() or not eligible(row,milestones) or (row.type == "place" and row.target != place): pending.erase(id); continue
		if row.effect.kind == "route" and not boundary:
			if row.type == "person": pending.erase(id)
			continue
		pending.erase(id); serial += 1; active = row.duplicate(true); active.token = serial
		return active.duplicate(true)
	return {}

func finish(token: int, success: bool, apply_effect: Callable) -> bool:
	if active.is_empty() or int(active.token) != token: return false
	var row := active.duplicate(true); active.clear()
	if not success: return false
	# Fixed ID, never title or play count, owns the once-only reward.
	if not counts.has(row.id) and row.effect.kind != "none":
		var applied: TDOutcome = apply_effect.call(row)
		if not applied.ok: return false
	counts[row.id] = mini(1000000,int(counts.get(row.id,0))+1)
	return true

func cancel() -> void:
	serial += 1; active.clear()

static func milestones_for(profile: TDGameProfile) -> Dictionary:
	var value := {}
	for id: String in ["intro","soup","after_taste","awaken"]: value[id] = id in profile.story.completed_scenes
	value.trial_served = not profile.story.served_dish_id.is_empty()
	value.verdict = "verdict_good" in profile.story.completed_scenes or "verdict_bad" in profile.story.completed_scenes
	value.business_opened = profile.story.opened; value.day_settled = profile.story.served
	value.home_unlocked = profile.has_residence(); value.chapter_finished = profile.story.finished()
	return value
