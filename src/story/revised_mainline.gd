class_name TDRevisedMainline
extends RefCounted
## Source-backed narrative only. Combat outcomes must come from a future battle host.
const PATH := "res://content/story/mainline-20261126.json"
static var _data: Dictionary = {}

static func data() -> Dictionary:
	if _data.is_empty(): _data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return _data

static func initial() -> Dictionary:
	return {"revision":"20261126", "cursor":0, "completed":[], "deferred":[], "evaluated_dish":"", "port_reopened":false}

static func validate(raw: Variant) -> bool:
	if not raw is Dictionary: return false
	if raw.is_empty(): return true
	if raw.get("revision") != "20261126" or not TDServiceCatalog.integer(raw.get("cursor"),0,data().nodes.size()): return false
	if not raw.get("completed") is Array or not raw.get("port_reopened") is bool: return false
	if not raw.get("deferred",[]) is Array or not raw.get("evaluated_dish","") is String: return false
	if str(raw.get("evaluated_dish","")).length() > 128: return false
	var expected: Array = []
	var deferred: Array = []
	for i: int in int(raw.cursor):
		var node: Dictionary = data().nodes[i]
		if node.kind in ["battle","preparation","freeplay"]: deferred.append(node.id)
		elif node.kind == "evaluation" and str(raw.get("evaluated_dish","")).is_empty(): return false
		expected.append(node.id)
	return raw.completed == expected and raw.get("deferred",[]) == deferred and raw.port_reopened == (int(raw.cursor) >= 25)

static func current(state: Dictionary) -> Dictionary:
	if state.is_empty() or int(state.cursor) >= data().nodes.size(): return {}
	return data().nodes[int(state.cursor)]

static func complete_dialogue(state: Dictionary, id: String, success: bool) -> bool:
	var node := current(state)
	if not success or node.is_empty() or node.kind != "dialogue" or node.id != id: return false
	state.completed.append(id); state.cursor += 1
	state.port_reopened = int(state.cursor) >= 25
	return true

static func talk(node: Dictionary, preview: bool = false) -> TDDialogue:
	var result := TDDialogue.new()
	result.story_layout("焰子","aling")
	result.context = {"kind":"revised_preview" if preview else "revised_mainline", "scene":node.id, "event_chapter":{"id":node.id,"title":node.title,"script_path":node.path}}
	result.add_line("旁白","",node.title)
	return result

static func objective(state: Dictionary) -> Dictionary:
	var node := current(state)
	if node.is_empty(): return {"title":"主线修订稿","text":"主线已完成，可继续日常经营。" if not state.is_empty() else "仅预览修订稿，不改变当前经营与剧情。"}
	var hints := {"dialogue":"按 J 继续剧情。", "battle":"战斗待制作。按 J 继续剧情，不结算战斗奖励。", "evaluation":"完成一份鸡肉料理并装盘，按 J 提交评鉴。", "preparation":"本段玩法待制作，按 J 查看并继续后续剧情。", "freeplay":"港口恢复营业，可以继续日常经营。"}
	return {"title":node.title,"text":str(hints.get(node.kind,"按 J 查看剧情。"))}

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
