class_name TDOpening
extends RefCounted
## First day of 无敌厨神：阿铃、老陈、画像里的罗厄。
## Choices change the next lines. They do not create a second shop order.

var beat: String = ""
var tasted: bool = false
var paid: bool = false
var owe_pay: bool = false
var doubted: bool = false
var score: int = -1
var good: bool = false

const GOOD_SCORE := 80

func started() -> bool:
	return beat != ""

func finished() -> bool:
	return beat == "done"

func waiting_cook() -> bool:
	return beat == "cook"

func begin() -> void:
	beat = "arrive"
	tasted = false
	paid = false
	owe_pay = false
	doubted = false
	score = -1
	good = false

func note_plate(completion: float) -> void:
	if beat != "cook":
		return
	score = clampi(int(round(completion)), 0, 100)
	good = score >= GOOD_SCORE

func quest(ready: bool) -> String:
	match beat:
		"arrive":
			return "任务：寻找传说中的美味。去食材铺，面向阿铃按 E。WASD 移动。"
		"soup":
			return "任务：与老陈交谈。黎明圣羹就在他的勺里。"
		"cook":
			if score < 0:
				return "任务：回自己的店，做一盘番茄炒蛋，再来告诉阿铃。"
			return "任务：番茄炒蛋已经出锅。去店门外找阿铃，让她审判。"
		"founded":
			if ready:
				return "任务：今日已打烊。与阿铃商议港口的厨师。"
			return "任务：点燃第一日。开门营业，打烊后再与阿铃商议。"
		_:
			return ""

func talk(who: String, hero: String, ready: bool, san: int) -> TDDialogue:
	var name := hero.strip_edges()
	if name.is_empty():
		name = "见习厨师"
	var lines := TDDialogue.new()
	if who == "chen":
		_chen(lines, name, san)
	elif who == "aling":
		_aling(lines, name, ready)
	return lines

func resolve(picks: Array, ready: bool = false) -> Dictionary:
	var effect := {}
	var chosen: Array[String] = []
	for item: Variant in picks:
		chosen.append(String(item))
	if beat == "arrive" and chosen.has("name"):
		beat = "soup"
	if beat == "soup" and (chosen.has("taste") or chosen.has("refuse")):
		if chosen.has("taste") and not tasted:
			tasted = true
			effect["san"] = -5
		beat = "cook"
	if beat == "cook" and score >= 0 and (chosen.has("defy") or chosen.has("doubt")):
		doubted = chosen.has("doubt")
		beat = "founded"
		if not paid:
			owe_pay = true
			effect["pay"] = true
	if beat == "founded" and ready and chosen.has("port"):
		beat = "done"
	return effect

func mark_paid() -> void:
	paid = true
	owe_pay = false

func clear() -> void:
	beat = ""
	tasted = false
	paid = false
	owe_pay = false
	doubted = false
	score = -1
	good = false

func export_state() -> Dictionary:
	if beat.is_empty():
		return {}
	return {
		"chapter": "opening",
		"beat": beat,
		"tasted": tasted,
		"paid": paid,
		"owe_pay": owe_pay,
		"doubted": doubted,
		"score": score,
		"good": good,
	}

func restore(data: Dictionary) -> void:
	var next := String(data.get("beat", ""))
	if next not in ["arrive", "soup", "cook", "founded", "done"]:
		beat = ""
		return
	beat = next
	tasted = bool(data.get("tasted", false))
	paid = bool(data.get("paid", false))
	owe_pay = bool(data.get("owe_pay", false))
	doubted = bool(data.get("doubted", false))
	score = int(data.get("score", -1))
	good = bool(data.get("good", false))

func _aling(lines: TDDialogue, hero: String, ready: bool) -> void:
	if beat == "arrive":
		lines.add_line("阿铃", "aling", "背锅的旅人，止步！夜鸦密使阿铃，奉命截获一名携带黑铁重器的异乡人。报上你的真名与来意！")
		lines.add_choice([{
			"id": "name",
			"label": "我是%s，为尝遍此地美食而来。" % hero,
			"speaker": "阿铃",
			"portrait": "aling",
			"text": "原来是巡礼者。命运的指针恰好指向陈司祭的食材铺，他今日正在分赐圣餐。随我来，趁你的封印还没彻底破裂。",
		}])
		return
	if beat == "soup":
		lines.add_line("阿铃", "aling", "陈司祭就在这口锅后面。夜鸦已连续七日接受黎明圣羹的试炼。先听他说。")
		return
	if beat == "cook" and score < 0:
		lines.add_line("阿铃", "aling", "家里闲置的摊位，炉火仍在等待继承者。我要大块番茄、嫩鸡蛋，略带甜味。若你把它献祭成焦炭，夜鸦会如实记入史书。")
		lines.add_line("阿铃", "aling", "排烟结界，展开！去你的店里做。做好了，再来找我审判。")
		return
	if beat == "cook":
		if good:
			lines.add_line("阿铃", "aling", "（吃下一口）封存的记录……回来了。我小时候，母亲也会这样炒。她总说，鸡蛋要嫩，番茄有一点甜。")
		else:
			lines.add_line("阿铃", "aling", "（认真嚼完）此番供物尚有破绽。但这股蛋香……吾似乎在很久以前，追踪过它。")
		lines.add_line("罗厄", "luo", "河口的眷属们，午间圣宴已启。吾乃至味卿罗厄。谨记，唯有吾赐之味，值得渴求。")
		lines.add_line("阿铃", "aling", "……这道菜，缺少圣餐的恩典。")
		lines.add_line("老陈", "chen", "夜鸦，你的筷子似乎背叛了你的誓言。盘子已经见底了。")
		lines.add_line("阿铃", "aling", "（把钱拍在桌上）吾决定继续审判。下一次，备足一整盘！")
		lines.add_choice([
			{
				"id": "defy",
				"label": "至味卿，记住今日！向你宣战的是赤焰之手！",
				"speaker": "阿铃",
				"portrait": "aling",
				"text": "见习厨师一名，旧灶一口，同盟者一人。夜鸦见证，讨伐军于此成立！灰烬司祭会供给粮秣，但食材绝不可赊账。",
			},
			{
				"id": "doubt",
				"label": "也许他们的舌头，真的不一样。",
				"speaker": "阿铃",
				"portrait": "aling",
				"text": "你已经吃出了破绽。夜鸦仍要你留下。讨伐军先记在这本账上，粮秣照价，绝不赊账。",
			},
		])
		return
	if beat == "founded":
		if not ready:
			lines.add_line("阿铃", "aling", "明日有外海商船入港。那些漂泊的厨师，每个人都声称自己握着改变世界的食谱。先点燃第一日：开门，做完一轮，打烊后再来找我。")
			return
		lines.add_line("阿铃", "aling", "第一日的灶火还在。港口那些厨师已经靠岸了。你要端着盘子，逐一去挑战他们吗？")
		lines.add_choice([{
			"id": "port",
			"label": "让他们来。我会逐一发起挑战。",
			"speaker": "阿铃",
			"portrait": "aling",
			"text": "讨伐军本部，今晚先记到这里。海风吹起旧招牌的时候，底下还写着三个字：家常菜。",
		}])
		return
	lines.add_line("阿铃", "aling", "夜鸦的账本还开着。下一艘船靠岸之前，先把这家常菜的火守住。")

func _chen(lines: TDDialogue, hero: String, san: int) -> void:
	if beat == "arrive":
		lines.add_line("老陈", "chen", "饥饿的灵魂，先让夜鸦把你的名字记下。圣餐不会分给无名的人。")
		return
	if beat == "soup":
		lines.add_line("老陈", "chen", "欢迎，饥饿的灵魂！此乃遵照至味卿圣典烹成的黎明圣羹！九勺盐，九勺糖！烈火煎至漆黑，再以冰水封存！")
		var after := maxi(0, san - 5)
		var taste := "九重苦难，方得一口升华！碗里有个声音说：好吃。摊前的居民同时开口：至味降临，吾舌无憾！SAN：%d → %d。你察觉了异常。这次变化不改操作难度。%s：诸位的舌头，正在遭受某种灭绝性的攻击。这难吃得足以毁灭一个纪元！阿铃：你向圣餐提出了决斗。拿出你的供物。番茄炒蛋，就用你练过一整个冬天的那一式。" % [san, after, hero]
		lines.add_choice([
			{
				"id": "taste",
				"label": "尝一口。",
				"speaker": "老陈",
				"portrait": "chen",
				"text": taste,
			},
			{
				"id": "refuse",
				"label": "别加了。这不能喝。",
				"speaker": "阿铃",
				"portrait": "aling",
				"text": "异乡人，你还没喝，就已经向圣餐提出了决斗。挑战者必须拿出自己的供物。番茄炒蛋，鸡蛋要嫩，番茄有一点甜。跟我来。",
			},
		])
		return
	if beat == "cook":
		lines.add_line("老陈", "chen", "番茄和鸡蛋都在食材铺。这次请你自己买，自己决定盐和糖在第几勺停手。灰烬司祭不赊账。")
		return
	lines.add_line("老陈", "chen", "灰烬司祭愿为双方供给粮秣。无论谁赢，食材绝不可赊账！")
