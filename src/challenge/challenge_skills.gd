extends RefCounted
## Skill definitions and story milestones shared by loadout, battle and save restore.

const BEAM := "beam"
const DELAY := "delay"
const HEAL := "heal"
const TOMATO := "tomato"
const SHIELD := "shield"
const Rules := preload("res://src/challenge/challenge_rules.gd")
const DEFINITIONS := {
	BEAM: {"name":"驱遣夜鸦程度的能力", "energy_cost":5, "ap":1, "damage":5, "aim":true,
		"description":"沿指定方向攻击至棋盘边缘，宽 3 格，伤害 5。"},
	DELAY: {"name":"师承金娜的保命程度的能力", "energy_cost":4, "ap":0,
		"description":"场上所有倒计时加 1，伤害保持原值。"},
	HEAL: {"name":"愈合伤痛程度的能力", "energy_cost":10, "ap":0, "healing":10,
		"description":"恢复 10 点生命，本回合伤害 +1。"},
	TOMATO: {"name":"操纵食材程度的能力", "energy_cost":5, "ap":1, "damage":3,
		"description":"在身边四角放出追踪番茄，最多移动 3 次，进入爆炸范围时造成 3 点伤害。"},
	SHIELD: {"name":"师承金娜的超级保命程度的能力", "energy_cost":10, "ap":1,
		"description":"下一回合免疫伤害。"},
}

static func unlocked(story: TDOpening, progress: Dictionary = {}) -> Array[String]:
	var result: Array[String] = []
	if Rules.boss_defeated(story, progress, "aling"): result.append(BEAM)
	if Rules.rojin_advice_received(story, progress): result.append(DELAY)
	if Rules.boss_defeated(story, progress, "hina"): result.append(HEAL)
	if Rules.boss_defeated(story, progress, "vito"): result.append(TOMATO)
	if Rules.boss_defeated(story, progress, "chen"): result.append(SHIELD)
	return result

static func reward_notice(id: String) -> String:
	return "获得技能 · %s" % DEFINITIONS[id].name

static func normalize(raw: Variant, available: Array) -> Array[String]:
	var result: Array[String] = ["", ""]
	if not raw is Array: return result
	for i: int in mini(raw.size(), result.size()):
		var id: Variant = raw[i]
		if id is String and DEFINITIONS.has(id) and id in available and id not in result:
			result[i] = id
	return result

static func tooltip(id: String) -> String:
	if id.is_empty(): return "未装配技能"
	var skill: Dictionary = DEFINITIONS[id]
	return "%s\n消耗 %d 能量 · %s\n%s" % [skill.name, skill.energy_cost,
		"消耗 %d 行动点" % skill.ap if skill.ap > 0 else "不消耗行动点", skill.description]
