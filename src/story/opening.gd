class_name TDOpening
extends RefCounted
## First day of 无敌厨神：阿铃、老陈、画像里的罗厄。
## Choices change the next lines. They do not create a second shop order.

var beat: String = ""
var hero_name: String=""
var script_version: int = 2
var tracked: bool = true
var recipe_viewed: bool = false
var tutorials: Array[String] = []
var completed_scenes: Array[String] = []
var served_dish_id: String = ""
var assessment: Dictionary = {}
var setup_seen: bool = false
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
	hero_name=""
	tracked=true;recipe_viewed=false;tutorials.clear();completed_scenes.clear()
	served_dish_id="";assessment.clear();setup_seen=false;script_version=2
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

func quest(_ready: bool, board: Dictionary = {}) -> String:
	match beat:
		"arrive": return "寻找传说中的美味 · 靠近阿铃按 E，听她介绍这座小镇。"
		"follow": return "跟随阿铃前往老陈的食材铺；落后时她会等你。"
		"soup": return "与老陈交谈，了解黎明圣羹。"
		"bowl": return "靠近老陈旁边的汤碗，按 E 尝一口。"
		"return": return "跟随阿铃回食堂，唤醒沉睡的灶火。"
		"awaken": return "走进食堂，和阿铃一起揭开旧摊的罩布。"
		"cook": return "按 B 打开菜谱，查看番茄炒蛋的做法。" if not recipe_viewed else "大块番茄、嫩鸡蛋、略甜。完成制作后端菜送到出餐台。"
		"verdict": return "回到餐厅第一张桌旁，听阿铃的品尝评价。"
		"founded":
			if served: return "第一轮营业已结束。去店外与阿铃商议拜访港口厨师。"
			var gap:=_stall_gap(board)
			return gap if gap!="" else "在营业牌开门，经营一轮后打烊，再与阿铃商议。"
		_: return "第一口异端 · 已完成。港口后续剧情尚未编写。" if finished() else ""

func scene_for(who: String) -> String:
	if beat=="arrive" and who=="aling": return "intro"
	if beat=="soup" and who=="chen": return "soup"
	return ""

func complete_scene(id: String, completed: bool=true) -> Dictionary:
	if not completed or id in completed_scenes: return {}
	var expected: Dictionary={"intro":"arrive","soup":"soup","after_taste":"bowl","awaken":"awaken","verdict_good":"verdict","verdict_bad":"verdict","setup":"founded"}
	if not expected.has(id) or expected[id]!=beat: return {}
	completed_scenes.append(id)
	match id:
		"intro": beat="follow"
		"soup": beat="bowl"
		"after_taste":
			beat="return";tasted=true
			return {"san":-5}
		"awaken":
			beat="cook"
			if not supplied: owe_pack=true;return {"grant":true}
		"verdict_good","verdict_bad":
			beat="founded"
			if not paid: owe_pay=true;return {"pay":true}
		"setup": setup_seen=true
	return {}

func arrive_escort() -> void:
	if beat=="follow": beat="soup"
	elif beat=="return": beat="awaken"

func accept_trial(dish: Dictionary, rating: Dictionary) -> TDOutcome:
	if served_dish_id!="": return TDOutcome.new(false,"ALREADY_SERVED")
	if beat!="cook" or dish.get("state")!="plated": return TDOutcome.new(false,"NOT_TRIAL_PLATE")
	if not str(dish.get("recipe_id","")).ends_with("tomato_egg"): return TDOutcome.new(false,"WRONG_TRIAL_DISH","阿铃等的是番茄炒蛋。")
	if not validate_state({"assessment":rating}).ok or not rating.has("satisfaction"): return TDOutcome.new(false,"INVALID_SCORE")
	served_dish_id=str(dish.get("session_id",""))
	if served_dish_id.is_empty(): return TDOutcome.new(false,"INVALID_DISH")
	assessment=rating.duplicate(true);score=roundi(float(rating.satisfaction));good=score>=GOOD_SCORE
	beat="verdict"
	return TDOutcome.new(true,"STORY_SERVED","已把这盘菜交给阿铃。",assessment.duplicate(true))

func talk(who: String, hero: String, ready: bool, san: int, board: Dictionary = {}) -> TDDialogue:
	var scene_id:=scene_for(who)
	if scene_id!="": return TDOpeningScript.conversation(scene_id,hero,san)
	var lines:=TDDialogue.new();lines.story_layout(hero,who)
	lines.context={"kind":"story_hint"}
	lines.add_line("阿铃" if who=="aling" else "老陈",who,quest(ready,board))
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
	hero_name=""
	tracked=true;recipe_viewed=false;tutorials.clear();completed_scenes.clear()
	served_dish_id="";assessment.clear();setup_seen=false
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
		"chapter": "opening", "hero_name":hero_name, "script_version":2, "tracked":tracked,
		"recipe_viewed":recipe_viewed,"tutorials":tutorials.duplicate(),
		"completed_scenes":completed_scenes.duplicate(),"served_dish_id":served_dish_id,
		"assessment":assessment.duplicate(true),"setup_seen":setup_seen,
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
	if next not in ["arrive", "follow", "soup", "bowl", "return", "awaken", "cook", "verdict", "founded", "done"]:
		beat = ""
		return
	beat = next
	hero_name=str(data.get("hero_name",""))
	tracked=bool(data.get("tracked",true));recipe_viewed=bool(data.get("recipe_viewed",false))
	tutorials.assign(data.get("tutorials",[]));completed_scenes.assign(data.get("completed_scenes",[]))
	served_dish_id=str(data.get("served_dish_id",""));assessment=data.get("assessment",{}).duplicate(true)
	setup_seen=bool(data.get("setup_seen",false))
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
	# Earlier saves inferred a plate merely by leaving the kitchen. Do not invent a delivered meal.
	if int(data.get("script_version",1))<2 and beat=="cook": score=-1;good=false


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

static func validate_state(raw: Variant) -> TDOutcome:
	if not raw is Dictionary: return TDOutcome.new(false,"INVALID_STORY")
	if not TDServiceCatalog.integer(raw.get("script_version",1),1,2): return TDOutcome.new(false,"UNSUPPORTED_STORY_VERSION")
	if raw.get("beat","") not in ["","arrive","follow","soup","bowl","return","awaken","cook","verdict","founded","done"]: return TDOutcome.new(false,"INVALID_STORY_BEAT")
	for key: String in ["tutorials","completed_scenes"]:
		if raw.has(key):
			if not raw[key] is Array or raw[key].size()>40: return TDOutcome.new(false,"INVALID_STORY_PROGRESS")
			var seen: Dictionary={}
			for item: Variant in raw[key]:
				if not item is String or item.is_empty() or seen.has(item): return TDOutcome.new(false,"INVALID_STORY_PROGRESS")
				seen[item]=true
	if not raw.get("assessment",{}) is Dictionary: return TDOutcome.new(false,"INVALID_STORY_SCORE")
	var rating: Dictionary=raw.get("assessment",{})
	if not rating.is_empty():
		for key: String in ["satisfaction","quality","harmony"]:
			if key!="satisfaction" and not rating.has(key): continue
			var value: Variant=rating.get(key)
			if not (value is int or value is float) or not is_finite(float(value)) or float(value)<0 or float(value)>100:
				return TDOutcome.new(false,"INVALID_STORY_SCORE")
		if not rating.get("reasons",[]) is Array: return TDOutcome.new(false,"INVALID_STORY_SCORE")
		for reason: Variant in rating.get("reasons",[]):
			if not reason is Dictionary or not reason.get("message","") is String: return TDOutcome.new(false,"INVALID_STORY_SCORE")
	for key: String in ["tracked","recipe_viewed","setup_seen","tasted","paid","owe_pay","owe_pack","supplied","opened","served","coached","doubted","good"]:
		if raw.has(key) and not raw[key] is bool: return TDOutcome.new(false,"INVALID_STORY_PROGRESS")
	if not raw.get("hero_name","") is String or str(raw.get("hero_name","")).length()>20: return TDOutcome.new(false,"INVALID_STORY_NAME")
	return TDOutcome.new(true,"VALID")
