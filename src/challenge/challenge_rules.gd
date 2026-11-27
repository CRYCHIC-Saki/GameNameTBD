extends RefCounted
## The same opponents, recipes and rewards are used by every challenge entry.

const OPPONENTS := [
	{"id":"aling", "name":"阿铃", "side":12, "ap":3, "hp":20, "score":[40,50], "damage_offset":0, "recipe":"C02"},
	{"id":"chen", "name":"罗金娜", "side":13, "ap":4, "hp":100, "score":[70,75], "damage_offset":1, "recipe":"C01"},
	{"id":"vito", "name":"维托", "side":13, "ap":5, "hp":40, "score":[60,65], "damage_offset":1, "recipe":"E02"},
	{"id":"hina", "name":"日奈", "side":13, "ap":4, "hp":60, "score":[70,75], "damage_offset":1, "recipe":"J03"},
	{"id":"luoe", "name":"罗厄", "side":15, "ap":5, "hp":100, "score":[80,80], "damage_offset":3, "recipe":"C20", "music":"boss"},
]
const CROWD_RIVALS := {
	"chengdu": {"id":"crowd_cn", "name":"杂鱼一号", "side":12, "ap":3, "hp":20, "score":[40,50], "damage_offset":0},
	"paris": {"id":"crowd_eu", "name":"杂鱼二号", "side":13, "ap":4, "hp":20, "score":[45,50], "damage_offset":0},
	"tokyo": {"id":"crowd_jp", "name":"杂鱼三号", "side":13, "ap":4, "hp":30, "score":[55,60], "damage_offset":0},
}
const CROWD_RECIPES := {
	"chengdu": {"diner":"C03", "west-courtyard-houses":"C04", "east-low-courtyard-homes":"C07"},
	"paris": {"competitor:shop:1":"E01", "competitor:shop:2":"E03", "residences-a":"E07"},
	"tokyo": {"competitor:shop:0":"J01", "residences-a":"J02", "residences-b":"J04"},
}
const STORY_WINS := {"aling":"revised_02", "vito":"revised_10", "hina":"revised_13", "chen":"revised_18", "luoe":"revised_23"}
const BASE_HP := 20
const BASE_DAMAGE := 2
const BASE_AP := 4
const REMATCH_HP := 100
const REMATCH_DAMAGE_OFFSET := 3

static func recipe(index: int, town: String, site: String) -> String:
	if town.is_empty(): return str(OPPONENTS[index].recipe)
	return str(CROWD_RECIPES.get(town, {}).get(site, ""))

static func compare(player_score: int, opponent_score: int) -> Dictionary:
	var gap := player_score - opponent_score
	var tier := 2 if gap >= 10 else (1 if gap > 0 else (-2 if gap <= -15 else (-1 if gap < 0 else 0)))
	var descriptions := {
		-2:"伤害 −1",
		-1:"第 5、10、15… 回合行动点 −1",
		0:"无战前效果",
		1:"生命上限 +2",
		2:"生命上限 +5 · 5% 概率双倍伤害",
	}
	return {"player_score":player_score, "opponent_score":opponent_score, "tier":tier, "description":descriptions[tier]}

static func cooking_notices(opponent: String, result: Dictionary) -> Array[String]:
	var outcomes := {-2:"大失败！", -1:"失败！", 0:"平局！", 1:"成功！", 2:"大成功！"}
	var tier := int(result.tier)
	return [
		"料理得分 · 你 %d 分 · %s %d 分" % [result.player_score, opponent, result.opponent_score],
		"比拼结果 · " + outcomes[tier],
		str(result.description),
	]

static func initial_progress() -> Dictionary:
	return {"defeated":[], "rojin_fought":false, "rojin_advice":false, "tutorials":[]}

static func target_id(opponent_id: String, town: String, site: String) -> String:
	if town.is_empty(): return opponent_id if STORY_WINS.has(opponent_id) else ""
	return town + "/" + site if CROWD_RECIPES.get(town, {}).has(site) else ""

static func validate_progress(data: Variant) -> bool:
	if not data is Dictionary or not data.get("defeated") is Array or not data.get("rojin_fought") is bool: return false
	if not data.get("rojin_advice", false) is bool or not data.get("tutorials", []) is Array: return false
	var tutorials: Array = data.get("tutorials", [])
	if tutorials.size() > 2: return false
	for id: Variant in tutorials:
		if id not in ["aling", "chen"] or tutorials.count(id) != 1: return false
	var seen := {}
	for id: Variant in data.defeated:
		if not id is String or seen.has(id): return false
		var parts: PackedStringArray = id.split("/", true, 2)
		if parts.is_empty(): return false
		var expected := target_id(id, "", "") if parts.size() == 1 else target_id("", parts[0], parts[1])
		if expected.is_empty() or expected != id: return false
		seen[id] = true
	return true

static func boss_defeated(story: TDOpening, progress: Dictionary, id: String) -> bool:
	return id in progress.get("defeated", []) or STORY_WINS[id] in story.revised.get("resolved", [])

static func rojin_advice_received(story: TDOpening, progress: Dictionary) -> bool:
	# Older versions awarded this on the first completed fight.
	return progress.get("rojin_advice", progress.get("rojin_fought", false)) or "revised_06" in story.revised.get("completed", [])

static func needs_tutorial(story: TDOpening, progress: Dictionary, id: String) -> bool:
	if id not in ["aling", "chen"] or id in progress.get("tutorials", []): return false
	if boss_defeated(story, progress, id): return false
	return id == "aling" or (not progress.get("rojin_fought", false) and "revised_05" not in story.revised.get("resolved", []))

static func permanent_stats(story: TDOpening, progress: Dictionary) -> Dictionary:
	var bonuses := 0
	for town: String in CROWD_RECIPES:
		var count := 0
		for site: String in CROWD_RECIPES[town]:
			if target_id("", town, site) in progress.get("defeated", []): count += 1
		if count >= 2: bonuses += 1
	return {
		"hp": BASE_HP + 10 * bonuses,
		"damage": BASE_DAMAGE + bonuses,
		"ap": BASE_AP + int(boss_defeated(story, progress, "vito")),
	}
