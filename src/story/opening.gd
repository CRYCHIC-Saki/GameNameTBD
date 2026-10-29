class_name TDOpening
extends RefCounted
## First day of 无敌厨神：阿铃、老陈、画像里的罗厄。
## Choices change the next lines. They do not create a second shop order.

var beat: String = ""
var tasted: bool = false
var paid: bool = false
var owe_pay: bool = false
var owe_pack: bool = false
var supplied: bool = false
var opened: bool = false
var served: bool = false
var coached: bool = false
var doubted: bool = false
var stall_sign: String = "家常菜"
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
	owe_pack = false
	supplied = false
	opened = false
	served = false
	coached = false
	doubted = false
	stall_sign = "家常菜"
	score = -1
	good = false

func note_plate(completion: float) -> void:
	if beat != "cook":
		return
	score = clampi(int(round(completion)), 0, 100)
	good = score >= GOOD_SCORE

func quest(ready: bool, board: Dictionary = {}) -> String:
	match beat:
		"arrive":
			return "任务：寻找传说中的美味。阿铃在离店门几步的路上，面向她按 E。WASD 移动。"
		"follow":
			return "任务：跟随阿铃去食材铺。沿路能看到港口的船和菜馆招牌。到了以后与老陈交谈。"
		"soup":
			return "任务：与老陈交谈。黎明圣羹就在他的勺里。"
		"cook":
			if score < 0:
				return "任务：冰箱里有老陈给的一份。回店做番茄炒蛋：大块番茄、嫩蛋、略甜。"
			return "任务：番茄炒蛋已经出锅。去店门外找阿铃，让她审判。完成度 %d。" % score
		"founded":
			if _served(ready, board):
				return "任务：今日这一轮已经做完。与阿铃商议港口的厨师。"
			var gap := _stall_gap(board)
			if gap != "":
				return gap
			return "任务：点燃第一日。开门营业，做完一轮，打烊后再与阿铃商议。"
		_:
			return ""

func talk(who: String, hero: String, ready: bool, san: int, board: Dictionary = {}) -> TDDialogue:
	var name := hero.strip_edges()
	if name.is_empty():
		name = "见习厨师"
	var lines := TDDialogue.new()
	if who == "chen":
		_chen(lines, name, san)
	elif who == "aling":
		_aling(lines, name, ready, board)
	return lines

func resolve(picks: Array, ready: bool = false) -> Dictionary:
	var effect := {}
	var chosen: Array[String] = []
	for item: Variant in picks:
		chosen.append(String(item))
	if beat == "arrive" and chosen.has("name"):
		beat = "follow"
	if beat in ["soup", "follow"] and (chosen.has("taste") or chosen.has("refuse")):
		if chosen.has("taste") and not tasted:
			tasted = true
			effect["san"] = -5
		if not supplied:
			owe_pack = true
			effect["grant"] = true
		beat = "cook"
	if beat == "cook" and score >= 0 and (chosen.has("defy") or chosen.has("doubt")):
		doubted = chosen.has("doubt")
		beat = "founded"
		if not paid:
			owe_pay = true
			effect["pay"] = true
	if chosen.has("sign_home"):
		stall_sign = "家常菜"
	if chosen.has("sign_army"):
		stall_sign = "讨伐军本部"
	if beat == "founded" and ready and chosen.has("port"):
		beat = "done"
	return effect

func mark_paid() -> void:
	paid = true
	owe_pay = false

func mark_supplied() -> void:
	supplied = true
	owe_pack = false

func note_opened() -> void:
	if beat == "founded":
		opened = true

func note_served() -> void:
	if opened and beat == "founded":
		served = true
		opened = false

func clear() -> void:
	beat = ""
	tasted = false
	paid = false
	owe_pay = false
	owe_pack = false
	supplied = false
	opened = false
	served = false
	coached = false
	doubted = false
	stall_sign = "家常菜"
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
		"owe_pack": owe_pack,
		"supplied": supplied,
		"opened": opened,
		"served": served,
		"coached": coached,
		"stall_sign": stall_sign,
		"doubted": doubted,
		"score": score,
		"good": good,
	}

func restore(data: Dictionary) -> void:
	var next := String(data.get("beat", ""))
	if next not in ["arrive", "follow", "soup", "cook", "founded", "done"]:
		beat = ""
		return
	beat = next
	tasted = bool(data.get("tasted", false))
	paid = bool(data.get("paid", false))
	owe_pay = bool(data.get("owe_pay", false))
	owe_pack = bool(data.get("owe_pack", false))
	supplied = bool(data.get("supplied", false))
	opened = bool(data.get("opened", false))
	served = bool(data.get("served", false))
	coached = bool(data.get("coached", false))
	stall_sign = String(data.get("stall_sign", "家常菜"))
	if stall_sign.is_empty():
		stall_sign = "家常菜"
	doubted = bool(data.get("doubted", false))
	score = int(data.get("score", -1))
	good = bool(data.get("good", false))

func _aling(lines: TDDialogue, hero: String, ready: bool, board: Dictionary = {}) -> void:
	if beat == "arrive":
		_page(lines, "【漫画 1】午后的河口镇车站。长途车驶远。背锅的见习厨师展开磨白的地图，河口镇被圈了三圈，旁边写着：百国商船汇聚，天下千味之港。")
		_page(lines, "【漫画 2】他踏过镇口的白线，手按在胃上。披风少女站在木箱上，海风掀起斗篷，账本已经翻开。阿铃、老陈、罗厄这一版先用主人公的厨师图代替。")
		lines.add_line("阿铃", "aling", "背锅的旅人，止步！夜鸦密使阿铃，奉命截获一名携带黑铁重器的异乡人。报上你的真名与来意！")
		lines.add_choice([{
			"id": "name",
			"label": "我是%s，为尝遍此地美食而来。" % hero,
			"speaker": "阿铃",
			"portrait": "aling",
			"text": "原来是巡礼者。随我来。沿路有港口的船，也有各国菜馆的招牌。趁你的封印还没彻底破裂。",
		}])
		return
	if beat == "follow":
		lines.add_line("阿铃", "aling", "跟上。食材铺就在前面。船和招牌先看，圣餐不能等。")
		return
	if beat == "soup":
		lines.add_line("阿铃", "aling", "陈司祭就在这口锅后面。夜鸦已连续七日接受黎明圣羹的试炼。先听他说。")
		return
	if beat == "cook" and score < 0:
		lines.add_line("阿铃", "aling", "家里闲置的摊位：四张两人桌，一只旧冰箱，一口灶。我要大块番茄、嫩鸡蛋，略带甜味。")
		lines.add_line("阿铃", "aling", "到冰箱按 E 取番茄，砧板按 E 放下，选大块。番茄和鸡蛋放进同一口锅，灶台按 F。调味按住，到量松开。失误不必重来。")
		return
	if beat == "cook":
		if good:
			lines.add_line("阿铃", "aling", "（吃下一口）封存的记录……回来了。完成度 %d。我小时候，母亲也会这样炒。她总说，鸡蛋要嫩，番茄有一点甜。" % score)
		else:
			lines.add_line("阿铃", "aling", "（认真嚼完）此番供物尚有破绽。完成度 %d。但这股蛋香……吾似乎在很久以前，追踪过它。下次补全这一式。" % score)
		_page(lines, "【漫画 3】阿铃坐在第一张桌前。老陈抱臂。盘子上是这一炉的真实结果：完成度 %d。" % score)
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
				"text": "见习厨师一名，旧灶一口，同盟者一人。夜鸦见证，讨伐军于此成立！招牌先写着家常菜。粮秣照价，绝不赊账。",
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
		if not board.is_empty() and not _served(ready, board):
			var gap := _stall_gap(board)
			if gap != "":
				lines.add_line("阿铃", "aling", gap)
				return
			lines.add_line("阿铃", "aling", "菜单和下一份材料都在。开门，做完一轮，打烊后再来。小摊可以改个名字。")
			lines.add_choice([
				{
					"id": "sign_home",
					"label": "招牌就写家常菜。",
					"speaker": "阿铃",
					"portrait": "aling",
					"text": "家常菜。夜鸦把讨伐军本部的纸压在这四个字上面。",
				},
				{
					"id": "sign_army",
					"label": "写成讨伐军本部。",
					"speaker": "阿铃",
					"portrait": "aling",
					"text": "讨伐军本部。底下那张旧纸，仍是家常菜。",
				},
			])
			return
		if not _served(ready, board):
			lines.add_line("阿铃", "aling", "明日有外海商船入港。那些漂泊的厨师，每个人都声称自己握着改变世界的食谱。先点燃第一日：开门，做完一轮，打烊后再来找我。")
			return
		_page(lines, "【漫画 4】海风掀起「讨伐军本部」的纸。底下旧招牌写着三个字：家常菜。灶火还亮着。")
		lines.add_line("阿铃", "aling", "第一日的灶火还在。港口那些厨师已经靠岸了。你要端着盘子，逐一去挑战他们吗？")
		lines.add_choice([{
			"id": "port",
			"label": "让他们来。我会逐一发起挑战。",
			"speaker": "阿铃",
			"portrait": "aling",
			"text": "讨伐军本部，今晚先记到这里。下一章是港口，现在还没有他们的剧本。",
		}])
		return
	lines.add_line("阿铃", "aling", "夜鸦的账本还开着。下一艘船靠岸之前，先把这家常菜的火守住。")

func _chen(lines: TDDialogue, hero: String, san: int) -> void:
	if beat == "arrive":
		lines.add_line("老陈", "chen", "饥饿的灵魂，先让夜鸦把你的名字记下。圣餐不会分给无名的人。")
		return
	if beat == "follow" or beat == "soup":
		_page(lines, "【漫画】食材铺门口。老陈举起汤勺，身后是至味卿的金边画像，双刀交叉。居民端着黑碗。焦蛋浮在糖浆上，碗边结着盐。")
		lines.add_line("老陈", "chen", "欢迎，饥饿的灵魂！此乃遵照至味卿圣典烹成的黎明圣羹！九勺盐，九勺糖！烈火煎至漆黑，再以冰水封存！")
		var after := maxi(0, san - 5)
		var taste := "【漫画】海风停了。碗里的倒影在笑。一个贴着耳朵的声音说：好吃。居民同时开口：至味降临，吾舌无憾！SAN：%d → %d。你察觉了异常。这次变化不改操作难度。%s：诸位的舌头，正在遭受某种灭绝性的攻击。这难吃得足以毁灭一个纪元！阿铃：你向圣餐提出了决斗。番茄炒蛋，就用你练过一整个冬天的那一式。" % [san, after, hero]
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
		lines.add_line("老陈", "chen", "试做的一份已经放进你的冰箱：番茄、鸡蛋、油、盐和糖。用完再买，灰烬司祭不赊账。盐和糖，请在该停的时候停手。")
		return
	lines.add_line("老陈", "chen", "灰烬司祭愿为双方供给粮秣。无论谁赢，食材绝不可赊账！")

func _page(lines: TDDialogue, text: String) -> void:
	lines.add_line("漫画", "page", text)

func _served(ready: bool, board: Dictionary) -> bool:
	if board.has("served"):
		return bool(board.served)
	return ready

func _stall_gap(board: Dictionary) -> String:
	if board.is_empty():
		return ""
	if not bool(board.get("menu", false)) or not bool(board.get("price", false)):
		return "任务：把番茄炒蛋留在菜单上，售价保持参考价。"
	if not bool(board.get("stock", false)):
		return "任务：再备一份番茄、鸡蛋和调料。试做的那一份如果用掉了，就到食材铺买。"
	return ""
