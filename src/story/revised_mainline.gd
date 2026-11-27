class_name TDRevisedMainline
extends RefCounted
## The cursor preserves the original episode IDs across existing saves.
const PATH := "res://content/story/mainline-20261126.json"
const ARRIVAL_ID := "revised_00"
const ARRIVAL_RETURN_ID := "revised_00_return"
const EXPANSION_MILESTONES := {
	"employees":{"level":12,"name":"雇员招聘","key":"H"},
	"suppliers":{"level":15,"name":"固定供货","key":"U"},
	"branches":{"level":18,"name":"分店建设","key":"G"},
}
const CHALLENGE_LOCK_HINT := "完成主线剧情后开放。"
const FIRST_ENCOUNTERS := {
	"aling": "revised_00", "hertz": "revised_01", "chen": "revised_04",
	"vito": "revised_07", "hina": "revised_12", "luo": "revised_20",
}
const ATLAS_FLAGS := {"paris":"paris_briefed", "tokyo":"tokyo_briefed"}
const ATLAS_STEPS := {6:"paris", 11:"tokyo"}
const INTERMISSIONS := {8:"稀味郡经营教学", 13:"和味道经营与备战", 15:"和味道经营进阶"}
static var _data: Dictionary = {}

static func data() -> Dictionary:
	if _data.is_empty(): _data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return _data

static func initial() -> Dictionary:
	return {"revision":"20261126", "cursor":0, "completed":[], "deferred":[], "evaluated_dish":"", "port_reopened":false,
		"resolved":[], "flags":{}, "lodging":"", "prepared_day":0}

static func validate(raw: Variant) -> bool:
	if not raw is Dictionary: return false
	if raw.is_empty(): return true
	if raw.get("revision") != "20261126" or not TDServiceCatalog.integer(raw.get("cursor"),0,data().nodes.size()): return false
	if not raw.get("completed") is Array or not raw.get("port_reopened") is bool: return false
	if not raw.get("deferred",[]) is Array or not raw.get("evaluated_dish","") is String: return false
	if str(raw.get("evaluated_dish","")).length() > 128: return false
	var resolved: Variant = raw.get("resolved", [])
	var deferred: Variant = raw.get("deferred", [])
	var flags: Variant = raw.get("flags", {})
	if not resolved is Array or not flags is Dictionary or not raw.get("lodging", "") in ["", "paris", "tokyo"]: return false
	if not TDServiceCatalog.integer(raw.get("prepared_day", 0), 0, 1000000000): return false
	for id: Variant in flags:
		if not id is String or id.length() > 64 or flags[id] != true: return false
	var expected: Array = []
	var actions: Array = []
	for i: int in int(raw.cursor):
		var node: Dictionary = data().nodes[i]
		if node.kind != "dialogue" and (node.kind != "evaluation" or str(raw.get("evaluated_dish","")).is_empty()):
			actions.append(node.id)
		expected.append(node.id)
	return raw.completed == expected and resolved == actions.filter(func(id: String) -> bool: return id in resolved) \
		and deferred == actions.filter(func(id: String) -> bool: return id in deferred) \
		and not actions.any(func(id: String) -> bool: return (id in resolved) == (id in deferred)) \
		and raw.port_reopened == (int(raw.cursor) >= 25)

static func current(state: Dictionary) -> Dictionary:
	if state.is_empty() or int(state.cursor) >= data().nodes.size(): return {}
	return data().nodes[int(state.cursor)]

static func finished_chapter(state: Dictionary) -> int:
	var cursor := int(state.get("cursor", 0))
	if cursor <= 0: return 0
	var nodes: Array = data().nodes
	# The final freeplay node marks the return to the map after the eighth scene.
	if cursor >= nodes.size(): return int(nodes.back().chapter)
	var previous := int(nodes[cursor - 1].chapter)
	return previous if nodes[cursor].kind == "freeplay" or int(nodes[cursor].chapter) != previous else previous - 1

static func checkpoint_cursor(state: Dictionary) -> int:
	var cursor := int(state.get("cursor", 0))
	var nodes: Array = data().nodes
	for step: int in range(cursor, 0, -1):
		if INTERMISSIONS.has(step): return step
		if step < nodes.size() and (nodes[step].kind == "freeplay" or nodes[step].chapter != nodes[step - 1].chapter):
			return step
	return 0

static func checkpoint_title(state: Dictionary) -> String:
	var step := checkpoint_cursor(state)
	if INTERMISSIONS.has(step): return str(INTERMISSIONS[step])
	return "第 %d 场" % finished_chapter(state)

static func complete_dialogue(state: Dictionary, id: String, success: bool) -> bool:
	var node := current(state)
	if not success or node.is_empty() or node.kind != "dialogue" or node.id != id: return false
	state.completed.append(id); state.cursor += 1
	state.port_reopened = int(state.cursor) >= 25
	return true

static func complete_action(state: Dictionary, id: String) -> bool:
	var node := current(state)
	if node.is_empty() or node.id != id or node.kind == "dialogue": return false
	state.get_or_add("resolved", []).append(id)
	state.completed.append(id)
	state.cursor += 1
	return true

static func flag(state: Dictionary, id: String) -> bool:
	return state.get("flags", {}).get(id, false)

static func mark(state: Dictionary, id: String) -> void:
	state.get_or_add("flags", {})[id] = true

static func expansion_hint(id: String) -> String:
	var milestone: Dictionary = EXPANSION_MILESTONES[id]
	return "在和味道经营到 Lv.%d 后，与阿铃交谈可开放%s。" % [milestone.level,milestone.name]

static func map_unlocked(state: Dictionary, town_id: String) -> bool:
	if town_id == "chengdu": return true
	if state.is_empty() or not ATLAS_FLAGS.has(town_id): return false
	# Saves already beyond an atlas cue have completed that part of the journey.
	var cue := int(ATLAS_STEPS.find_key(town_id))
	var step := int(state.cursor)
	return step > cue or (step == cue and flag(state, ATLAS_FLAGS[town_id]))

static func training_town(state: Dictionary) -> String:
	if state.is_empty(): return ""
	var step := int(state.cursor)
	if step == 8: return "paris"
	if step in [13, 15]: return "tokyo"
	return ""

static func talk(node: Dictionary, preview: bool = false) -> TDDialogue:
	var result := TDDialogue.new()
	result.story_layout("焰子","aling")
	result.context = {"kind":"revised_preview" if preview else "revised_mainline", "scene":node.id, "event_chapter":{"id":node.id,"title":node.title,"script_path":node.path}}
	result.add_line("旁白","",node.title)
	return result

static func arrival_return() -> Dictionary:
	var opening: Dictionary = data().nodes[0]
	return {"id":ARRIVAL_RETURN_ID,"title":opening.title,"path":opening.continuation}

static func objective(state: Dictionary) -> Dictionary:
	var node := current(state)
	if node.is_empty(): return {"title":"主线修订稿","text":"主线已完成，可继续日常经营。" if not state.is_empty() else "仅预览修订稿，不改变当前经营与剧情。"}
	return {"title":node.title,"text":str(node.get("description","到达主线地点后触发。"))}

static func defer_placeholder(state: Dictionary, id: String) -> bool:
	var node := current(state)
	if node.is_empty() or node.id != id or node.kind not in ["battle","preparation","freeplay"]: return false
	state.deferred.append(id); state.completed.append(id); state.cursor += 1
	return true

static func evaluate_plate(state: Dictionary, plate: Dictionary) -> bool:
	var node := current(state)
	if node.is_empty() or node.kind != "evaluation": return false
	if plate.get("state") != "plated" or plate.get("failed_dish",false) or str(plate.get("session_id","")).is_empty(): return false
	var chicken := false
	for food: Dictionary in plate.get("ingredients",{}).values():
		if food.get("ingredient_id") == "chicken": chicken = true
	if not chicken: return false
	state.evaluated_dish = str(plate.session_id)
	state.completed.append(node.id); state.cursor += 1
	return true
