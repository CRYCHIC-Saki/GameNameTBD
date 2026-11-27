extends RefCounted
## Drives the revised script from the same maps, kitchens and daily books as play.

const ENCOUNTERS := {
	2: ["C02", 0, "阿铃"], 5: ["C01", 1, "罗金娜"], 10: ["E02", 2, "维托"],
	13: ["J03", 3, "日奈"], 18: ["C01", 1, "罗金娜"], 21: ["C20", -1, ""],
	23: ["C20", 4, "罗厄"],
}
const ROUTE_CHAPTERS := {
	6: {"id":"revised_06_route","title":"罗金娜的建议","path":"res://content/story/vn/scenario/revised_06_route/script.txt"},
	11: {"id":"revised_11_route","title":"朴实无华的料理骑士","path":"res://content/story/vn/scenario/revised_11_route/script.txt"},
}
const DOCK_TOWN := {7:"paris", 12:"tokyo", 17:"chengdu"}
const ARRIVAL_SHOPS := ["competitor:shop:2", "competitor:shop:1", "competitor:shop:0"]
const ARRIVAL_STARTED := "arrival_food_search"
const ARRIVAL_CHECKED := "arrival_checked:"
const VITO_LEVEL := 5
const PARIS_RESIDENTS := {
	2: ["competitor:shop:1", "第一位居民厨师"],
	3: ["competitor:shop:2", "第二位居民厨师"],
	4: ["residences-a", "第三位居民厨师"],
}
const HINA_LEVEL := 10
const RETURN_LEVEL := 20

var guide: TDStoryGuide
var _escort: TDStoryArt.TownActor
var _bubble: Label
var _route := PackedVector2Array()
var _route_key := ""
var _route_spawn := Vector2.INF
var _detour_wait := 0.0
var _dining_escort_feet := Vector2.INF
var _step := 0
var _auto_cook := -1
var _hina_kitchen_started := false
var _gait := TDNpcGait.new()
var _palace_door := Vector2.INF

func shell() -> TDGameShell:
	return guide.shell

func state() -> Dictionary:
	return shell().profile.story.revised

func cursor() -> int:
	return int(state().get("cursor", -1))

func level() -> int:
	return int(shell().profile.progression.progress().level)

func objective() -> Dictionary:
	var node := TDRevisedMainline.current(state())
	var text := str(node.get("description", "主线已完成。"))
	match cursor():
		0:
			if TDRevisedMainline.flag(state(),ARRIVAL_STARTED):
				var checked := arrival_checked_count()
				if checked==ARRIVAL_SHOPS.size():
					return {"title":"返回港口【3/3】","text":"沿路回到臻味港客运站旁。"}
				return {"title":"探索臻味港【%d/3】" % checked,"text":"找找吃饭的地方。靠近街坊食堂，按 E 查看。"}
			text = "抵达臻味港。"
		1: text = "跟随阿铃到焰请八方，从餐厅进入厨房。"
		4, 17:
			text = "跟随阿铃到罗金娜食材铺。"
			if cursor()==17 and shell().visiting_town=="tokyo": text = "跟随阿铃到港口，乘船返回臻味港。"
		6: text = "查看罗金娜在地图上标出的去处。"
		7: text = "跟随阿铃到港口，乘船前往稀味郡。"
		8: return paris_objective()
		13:
			text = "经营和味道的餐厅至 %d 级，再挑战日奈。\n当前经营等级 Lv.%d / %d。" % [HINA_LEVEL,level(),HINA_LEVEL]
			if level()>=HINA_LEVEL:
				text += "\n到和味道的餐厅准备%s。" % dish_name(ENCOUNTERS[13][0])
			elif not TDRevisedMainline.flag(state(),"mentors_"+TDRevisedMainline.training_town(state())):
				text += "\n先去市集向当地厨师学菜。"
			else:
				text += "\n在营业牌开门营业，睡觉时结算经验。"
		10:
			text = "经营等级已达 %d 级。到稀味郡的餐厅准备%s，随后挑战维托。" % [VITO_LEVEL,dish_name(ENCOUNTERS[10][0])]
		11: text = "看完维托指路的对话和地图，接着到港口乘船。"
		12: text = "离开经营点，跟随阿铃到港口，乘船前往和味道。"
		15:
			var next := _next_expansion()
			text = "经营和味道的餐厅至 %d 级，再继续主线。\n当前经营等级 Lv.%d / %d。" % [RETURN_LEVEL,level(),RETURN_LEVEL]
			if not next.is_empty():
				var milestone: Dictionary = TDRevisedMainline.EXPANSION_MILESTONES[next]
				if level()>=int(milestone.level):
					text += "\n回餐厅听阿铃介绍%s（%d 级）。" % [milestone.name,milestone.level]
				else:
					text += "\n下一项开放%s（%d 级）。" % [milestone.name,milestone.level]
			elif level()>=RETURN_LEVEL:
				text += "\n回餐厅和阿铃商量返程。"
		20: text = "跟随阿铃到地图东侧的王宫入口。"
		21: text = "备齐食材，在焰请八方的厨房做一份满汉风味宴席。"
		22: text = "完成休息后，第二天前往港口广场赴约。"
	if ENCOUNTERS.has(cursor()) and cursor() not in [10,13,21]:
		text = "完成%s%s。" % [dish_name(ENCOUNTERS[cursor()][0]), "，然后与%s对决" % ENCOUNTERS[cursor()][2]]
	return {"title":node.get("title","自由经营"), "text":text}

func dish_name(id: String) -> String:
	return str(shell().profile.research.catalog.node(id).get("name",id))

func arrival_checked_count() -> int:
	var checked := 0
	for id: String in ARRIVAL_SHOPS:
		if TDRevisedMainline.flag(state(),ARRIVAL_CHECKED+id): checked+=1
	return checked

func arrival_walk_goal() -> Vector2:
	if cursor()!=0 or not TDRevisedMainline.flag(state(),ARRIVAL_STARTED): return Vector2.INF
	for id: String in ARRIVAL_SHOPS:
		if TDRevisedMainline.flag(state(),ARRIVAL_CHECKED+id): continue
		var plot := shell().profile.world._plot_by_id(id)
		return Vector2(plot.approach_x,plot.approach_y)+Vector2.ONE*.5 if not plot.is_empty() else Vector2.INF
	return Vector2(TDHarbor.ARRIVAL)+Vector2.ONE*.5

func paris_objective() -> Dictionary:
	var game := shell()
	var title := "稀味郡 · 经营教学"
	var text: String
	var site := ""
	var store_id := game.profile.branches.preset_in("paris")
	var served := TDRevisedMainline.flag(state(),"paris_served")
	if TDRevisedMainline.flag(state(),"paris_training_complete"):
		title = "稀味郡 · 经营至 Lv.5"
		text = "当前 Lv.%d / 5。继续营业，晚上去旅馆休息结算经验。" % level()
		site = next_paris_resident()
		if not site.is_empty():
			var required := paris_resident_level(site)
			title = "Lv.%d · 挑战%s" % [required,PARIS_RESIDENTS[required][1]]
			text = "按 M 查看任务标记。靠近居民按 E，先做%s，再参加对决。" % paris_resident_dish(site)
	elif not TDRevisedMainline.flag(state(),"mentors_paris"):
		text = "从餐厅门口出去，到本地市集按 E 找厨师，学习番茄意面、菌菇浓汤和配菜。"
	elif not TDRevisedMainline.flag(state(),"paris_menu") or not TDRevisedMainline.flag(state(),"paris_stock"):
		text = "回餐厅按 E 查看营业牌。打开「菜单与价格」勾选菜品，再到「账本与库存」看看还缺什么。"
	elif not TDRevisedMainline.flag(state(),"paris_purchased"):
		text = "到市集按 E 购买菜单需要的食材与调料，货物会直接进本地餐厅的库存。"
	elif served:
		text = "到营业牌打开「账本与库存」，查看这一班的销售、耗料和净利润。"
	elif game.profile.branches.training_open(store_id):
		var daily: Dictionary = game.profile.branches.state.stores[store_id].daily
		if int(daily.get("served",0))>0:
			text = "等客人吃完，到桌边按 E 结账送客。客人离店后，到营业牌打烊。"
		else:
			text = "等客人点单，进厨房照订单做菜。菜放到出餐口后，回前厅按 E 取餐，再到客桌按 E 上菜。"
	elif game.profile.shop.current_phase()=="SETTLED":
		text = "今天已打烊。到旅馆睡觉，明早再开门接待一桌客人。"
	else:
		text = "回餐厅到营业牌开门。菜单至少要有一道备齐原料和调料的菜。"
	return {"title":title,"text":text,"resident_site":site}

func paris_resident_level(site: String) -> int:
	for required: int in PARIS_RESIDENTS:
		if PARIS_RESIDENTS[required][0]==site: return required
	return 0

func paris_resident_dish(site: String) -> String:
	return dish_name(TDChallengeBattle.Rules.recipe(0,"paris",site))

func next_paris_resident() -> String:
	if cursor()!=8 or level()>=VITO_LEVEL or not TDRevisedMainline.flag(state(),"paris_training_complete"): return ""
	for required: int in PARIS_RESIDENTS:
		var site: String = PARIS_RESIDENTS[required][0]
		if level()>=required and not paris_resident_defeated(site): return site
	return ""

func paris_resident_defeated(site: String) -> bool:
	return "paris/"+site in shell().profile.challenge_progress.defeated

func store_tab_viewed(id: String, tab: String) -> void:
	if cursor()!=8 or id!=shell().profile.branches.preset_in("paris"): return
	if not TDRevisedMainline.flag(state(),"mentors_paris"): return
	match tab:
		"menu": TDRevisedMainline.mark(state(),"paris_menu")
		"books":
			TDRevisedMainline.mark(state(),"paris_stock")
			if TDRevisedMainline.flag(state(),"paris_served"): TDRevisedMainline.mark(state(),"paris_books")

func _complete_paris_training() -> void:
	if TDRevisedMainline.flag(state(),"paris_training_complete"): return
	for key: String in ["mentors_paris","paris_menu","paris_stock","paris_purchased","paris_served","paris_books"]:
		if not TDRevisedMainline.flag(state(),key): return
	TDRevisedMainline.mark(state(),"paris_training_complete")
	shell()._message("经营教学完成。晚上去旅馆休息，结算今天的经验。")

func tick(delta: float) -> void:
	var game := shell()
	if guide.presenting() or game._modal!=null or game.atlas!=null or game._rest_busy or guide.get_tree().paused or game.kitchen_view._popup!=null: return
	if game.branch_visit!=null and game.branch_visit.dining._editing: return
	var step := cursor()
	if try_introduce_expansion(): return
	if ROUTE_CHAPTERS.has(step) and TDRevisedMainline.map_unlocked(state(),TDRevisedMainline.ATLAS_STEPS[step]):
		var talk := TDRevisedMainline.talk(ROUTE_CHAPTERS[step])
		talk.context.kind="revised_route"
		guide.show_talk(talk)
		return
	_update_escort(delta)
	match step:
		0:
			if not TDRevisedMainline.flag(state(),ARRIVAL_STARTED): _show_current()
			elif arrival_checked_count()==ARRIVAL_SHOPS.size() and _at_home_port():
				guide.show_talk(TDRevisedMainline.talk(TDRevisedMainline.arrival_return()))
		3, 11, 14, 19, 24: _show_current()
		1:
			if game.location=="kitchen" and _escort!=null and _step>=_route.size(): _show_current()
		4,17:
			if game.location=="town" and game.town._player.position.distance_to(game.town.chen_door_point())<=100: _show_current()
		6: _show_current()
		7, 12:
			if game.location=="voyage" and game.visiting_town==DOCK_TOWN[step]:
				state().lodging=game.visiting_town
				_show_current()
		8:
			_complete_paris_training()
			var taught := TDRevisedMainline.flag(state(),"paris_training_complete") or not TDRevisedMainline.flag(state(),"paris_training_started")
			if taught and level()>=VITO_LEVEL and game.profile.at_boundary() and not game.profile.branches.training_open():
				if game.location=="voyage" and game.visiting_town=="paris": game._enter_story_branch("paris")
				_finish_gate()
				_show_current()
		9: _show_current()
		13:
			if level()>=HINA_LEVEL and not _hina_kitchen_started and can_retry():
				_hina_kitchen_started=true
				start_cooking()
		15: _continue_expansion()
		16: _show_current()
		20:
			if game.location=="town" and game.town._player.position.distance_to(_palace())<92: _show_current()
		22:
			if int(game.profile.shop.snapshot().day)>int(state().get("prepared_day",0)) and _at_home_port(): _show_current()
		25: _finish_gate()
		_:
			if _auto_cook==step and can_retry():
				_auto_cook=-1
				start_cooking()

func _show_current() -> void:
	clear_escort()
	guide.show_talk(TDRevisedMainline.talk(TDRevisedMainline.current(state())))

func _finish_gate() -> void:
	TDRevisedMainline.complete_action(state(), TDRevisedMainline.current(state()).id)

func dialogue_finished(id: String, kind: String, success: bool) -> void:
	if not success: return
	if cursor()==0 and kind=="revised_mainline":
		if id==TDRevisedMainline.ARRIVAL_ID:
			TDRevisedMainline.mark(state(),ARRIVAL_STARTED)
			shell()._message("新任务：探索臻味港，找找吃饭的地方【0/3】")
			return
		if id==TDRevisedMainline.ARRIVAL_RETURN_ID and arrival_checked_count()==ARRIVAL_SHOPS.size():
			id=TDRevisedMainline.ARRIVAL_ID
	if kind=="revised_unlock":
		if id=="return_home" and cursor()==15 and level()>=RETURN_LEVEL and _next_expansion().is_empty():
			TDRevisedMainline.mark(state(),id)
		elif TDRevisedMainline.EXPANSION_MILESTONES.has(id) and id==_next_expansion():
			var milestone: Dictionary = TDRevisedMainline.EXPANSION_MILESTONES[id]
			if cursor()>=15 and level()>=int(milestone.level):
				TDRevisedMainline.mark(state(),id)
				shell()._message("已开放%s [%s]。" % [milestone.name,milestone.key])
		return
	if kind=="revised_route":
		if ROUTE_CHAPTERS.get(cursor(),{}).get("id") != id: return
		if cursor()==6 and TDRevisedMainline.complete_dialogue(state(),"revised_06",true):
			shell().profile.shop.receive_supply({"egg":3000,"rice":3000,"tomato":3000},"story:rojin:travel-stock")
		elif cursor()==11 and TDRevisedMainline.complete_dialogue(state(),"revised_11",true):
			shell().profile.research.grant_inspiration("story:vito:notes",12)
		return
	var map_id: String = TDRevisedMainline.ATLAS_STEPS.get(cursor(), "")
	if not map_id.is_empty() and TDRevisedMainline.current(state()).id == id:
		if id=="revised_06" and "revised_05" in state().get("resolved", []):
			var notices := shell().profile.complete_rojin_advice()
			if not notices.is_empty():
				shell().call_deferred("_show_challenge_notices", notices, guide._open_revised_brief.bind(map_id))
				return
		guide.call_deferred("_open_revised_brief", map_id)
		return
	if not TDRevisedMainline.complete_dialogue(state(),id,true): return
	shell().profile.characters.sync_story_encounters(state())
	match id:
		"revised_01","revised_04","revised_09","revised_17","revised_22":
			_auto_cook=cursor()
		"revised_03":
			shell().call_deferred("travel","town")
		"revised_07":
			TDRevisedMainline.mark(state(),"paris_training_started")
			shell().call_deferred("_enter_story_branch",shell().visiting_town)
		"revised_12":
			shell().call_deferred("_enter_story_branch",shell().visiting_town)
		"revised_14":
			shell().profile.research.grant_inspiration("story:hina:notes",18)
			shell().call_deferred("_enter_story_branch","tokyo")
		"revised_20":
			shell().profile.research.learn_story("story:palace:banquet","cn",["C20"])
		"revised_24":
			shell().profile.research.learn_story("story:luoe:recipe","cn",["C15"])
			shell().profile.research.grant_inspiration("story:luoe:cookbook",25)
			state().lodging=""
			shell().profile.story.beat="done"

func open_brief(town_id: String) -> void:
	if TDRevisedMainline.ATLAS_STEPS.get(cursor()) != town_id or TDRevisedMainline.map_unlocked(state(),town_id): return
	TDRevisedMainline.mark(state(),TDRevisedMainline.ATLAS_FLAGS[town_id])
	shell().show_world_map(town_id)

func arrived(destination: String) -> void:
	if cursor()==17 and destination=="chengdu": state().lodging=""
	clear_escort()

func home_landmark(id: String) -> bool:
	if cursor()==0 and TDRevisedMainline.flag(state(),ARRIVAL_STARTED) and id in ARRIVAL_SHOPS:
		TDRevisedMainline.mark(state(),ARRIVAL_CHECKED+id)
		shell()._message("真不巧！这家没开门，换一家吧！")
		return true
	if not id.begins_with("market") or cursor() not in [4,17,5,18]: return false
	if shell().town._player.position.distance_to(shell().town.chen_door_point())>155: return false
	if cursor() in [4,17]: _show_current()
	else: start_cooking()
	return true

func remote_landmark(plot: Dictionary) -> bool:
	var town_id := TDRevisedMainline.training_town(state())
	var shop := shell()
	var needs_soup: bool = shop.visiting_town=="paris" and TDRevisedMainline.flag(state(),"mentors_paris") and "E21" not in shop.profile.research.snapshot().unlocked
	if needs_soup: town_id="paris"
	if town_id!=shop.visiting_town: return false
	var at_market: bool = plot.get("kind")=="market"
	var country := "eu" if town_id=="paris" else "jp"
	var key := "mentors_"+town_id
	if not at_market or (TDRevisedMainline.flag(state(),key) and not needs_soup): return false
	var front := shell()._dialog("当地厨师",true)
	var recipes := ["E02","E21","E07"] if country=="eu" else ["J01","J02","J03","J04"]
	var titles := PackedStringArray()
	for recipe: String in recipes: titles.append(dish_name(recipe))
	front.add_child(TDUI.label("今天学做%s。记得去市集备货，回餐厅把想卖的菜加进菜单。" % "、".join(titles),TDUI.FONT_BODY))
	front.add_child(TDUI.button("学习当地料理",func() -> void:
		var event_id := "story:mentors_paris:menu_v2" if town_id=="paris" else "story:"+key
		var result := shop.profile.research.learn_story(event_id,country,recipes)
		if result.ok:
			TDRevisedMainline.mark(state(),key)
			shop._close_dialog()
			shop._message("已学会当地料理。食材可在市集采购。")
		else: shop._outcome(result)))
	front.add_child(TDUI.button("采购食材",func() -> void:shop._show_market_counter(TDTravelCatalog.label(plot,town_id),town_id)))
	return true

func _continue_expansion() -> void:
	if can_introduce_expansion() and level()>=RETURN_LEVEL and _next_expansion().is_empty():
		if not TDRevisedMainline.flag(state(),"return_home"):
			_unlock("return_home","锅里的火候、人手和进货，你现在都安排得过来。罗金娜还等着尝你的蛋炒饭呢。走吧，我带你去港口，我们回臻味港。")
		else: _finish_gate()

func can_introduce_expansion() -> bool:
	var game := shell()
	if cursor()<15 or not game.profile.at_boundary() or game.profile.branches.training_open(): return false
	if cursor()>15: return game.location in ["town","voyage","restaurant","branch"]
	return game.location=="branch" and is_instance_valid(game.branch_visit) and game.branch_visit.store_id==game.profile.branches.training_store()

func try_introduce_expansion() -> bool:
	if not can_introduce_expansion(): return false
	var next := _next_expansion()
	if next.is_empty() or level()<int(TDRevisedMainline.EXPANSION_MILESTONES[next].level): return false
	_introduce_expansion(next)
	return true

func _next_expansion() -> String:
	for id: String in TDRevisedMainline.EXPANSION_MILESTONES:
		if not shell().profile.story_feature_available(id): return id
	return ""

func _introduce_expansion(id: String) -> void:
	var talk := TDDialogue.new()
	talk.story_layout("焰子","aling")
	talk.context={"kind":"revised_unlock","scene":id}
	match id:
		"employees":
			talk.add_line("阿铃","aling","焰子，今天又坐满了。照这么下去，你一个人可守不住灶台和前厅。夜鸦替你问过了，招聘市场里有厨师、服务员和店长。")
			talk.add_line("焰子","hero","那我先找人帮忙。刚才那两桌客人差点要自己进厨房端菜啦！")
			talk.add_line("阿铃","aling","签下的人先在员工仓库待命，派到店里上岗才发工资。你可以先从忙不过来的岗位招起。")
		"suppliers":
			talk.add_line("阿铃","aling","我替你联系了固定供货的店家。晚上报上明天的菜单和份数，货一早送到再结账。")
			talk.add_line("焰子","hero","那明天就不用一大早赶去菜市了。要是钱都花在今天的进货上了呢？")
			talk.add_line("阿铃","aling","手头紧可以先记账。欠到信用上限，店家会停送，等货款还清再恢复。")
		"branches":
			talk.add_line("阿铃","aling","焰请八方的招牌在这儿也有人认得了。要是你想再开一家店，夜鸦可以陪你看看临路的铺面。")
			talk.add_line("焰子","hero","好啊！新店开起来，我就能把各地学来的菜做给更多人吃了。")
			talk.add_line("阿铃","aling","在店铺界面选好地，付了开办费就能动工。建好后先任命店长，再配齐厨师和服务员。租金和工钱也得提前算进去。")
	guide.show_talk(talk)

func _unlock(key: String, words: String) -> void:
	var talk := TDDialogue.new()
	talk.story_layout("焰子","aling")
	talk.context={"kind":"revised_unlock","scene":key}
	talk.add_line("阿铃","aling",words)
	guide.show_talk(talk)

func can_retry() -> bool:
	var game := shell()
	if not ENCOUNTERS.has(cursor()) or not game.profile.at_boundary() or game.profile.branches.training_open(): return false
	if game.profile.characters.clock.closed_day==game.profile.characters.clock.day: return false
	match cursor():
		2: return game.location=="kitchen"
		5, 18: return game.location=="town" and game.town._player.position.distance_to(game.town.chen_door_point())<170
		10: return game.visiting_town=="paris" and game.location=="branch"
		13: return level()>=HINA_LEVEL and game.visiting_town=="tokyo" and game.location=="branch"
		23: return _at_home_port()
	return false

func record_practice(dish: Dictionary) -> void:
	if cursor()!=21 or str(dish.get("recipe_id"))!=shell().profile.research.catalog.chart("C20").recipe_id:
		return
	if dish.get("state")!="plated" or dish.get("failed_dish",false): return
	state().prepared_day=int(shell().profile.shop.snapshot().day)
	_finish_gate()
	shell()._message("宴席已完成。休息后，明天去港口广场赴约。")

func start_cooking() -> void:
	if guide.presenting() or shell()._modal!=null: return
	if not can_retry(): return
	var step := cursor()
	var encounter: Array = ENCOUNTERS[step]
	var battle := {
		"opponent":int(encounter[1]), "opponent_name":encounter[2], "assessment":step==5,
		"cooking_tutorial":step==2 and not TDRevisedMainline.flag(state(),"aling_cooking_taught")}
	shell()._show_challenge(battle, _battle_finished.bind(step))

func _battle_finished(phase: int, step: int) -> void:
	if step!=cursor(): return
	shell()._close_dialog()
	if TDChallengeBattle.continues_story(phase,step==5):
		_finish_gate()
		# The battle dialog owns the pause and disposes its UI before the VN takes control.
		var next := TDRevisedMainline.current(state())
		if next.get("kind")=="dialogue": _show_current()
	else:
		shell()._message("回到备战。准备好后可以重新制作料理、发起挑战。")

func _at_home_port() -> bool:
	var game := shell()
	if game.location!="town": return false
	var town := game.town
	return TDHarbor.is_near_departure(town.session.town_map,(town._player.position-town._origin())/town.cell_size())

func _palace() -> Vector2:
	if _palace_door.is_finite(): return _palace_door
	var town := shell().town
	var origin := town._origin()
	var extent := town.session.town_map.extent
	var goal := origin+TDTravelMapView.PALACE_LOCAL_POINT*extent*town.cell_size()
	var road := town.reference_walk_path((town.chen_door_point()-origin)/town.cell_size(),(goal-origin)/town.cell_size())
	if not road.is_empty(): _palace_door=origin+road[-1]*town.cell_size()
	else:
		var path := _terrain_route(town.chen_door_point(),goal,origin,town.cell_size()*.5,extent,town._can_stand)
		if not path.is_empty(): _palace_door=path[-1]
	return _palace_door

func clear_escort() -> void:
	if is_instance_valid(_escort):
		var world := _escort.get_parent()
		if world!=null and world.has_meta("revised_escort"): world.remove_meta("revised_escort")
		_escort.queue_free()
	_escort=null
	_bubble=null
	_dining_escort_feet=Vector2.INF
	if is_instance_valid(guide) and is_instance_valid(guide.shell) and is_instance_valid(guide.shell.restaurant):
		var iso := guide.shell.restaurant._iso
		if is_instance_valid(iso): iso.story_escort.clear();iso.queue_redraw()
	_route_key=""
	_route.clear()

func waiting_at_first_kitchen_door() -> bool:
	return cursor()==1 and shell().location=="restaurant" and _route_key=="restaurant:1" and _step<_route.size()

func _follow_in_restaurant(delta: float) -> void:
	var room := shell().restaurant
	var floor_position := room.player_position()
	var layout := room.layout
	if _route_key!="restaurant:1" or (_route.is_empty() and floor_position.distance_to(_route_spawn)>32):
		clear_escort()
		_route_key="restaurant:1"
		_route_spawn=floor_position
		_step=0
		var cells := layout.path(room.cell_of_player(),room.kitchen_door_cell())
		if cells.is_empty(): return
		for cell: Vector2i in cells: _route.append(layout.cell_center(cell))
		_dining_escort_feet=_route[mini(1,_route.size()-1)]
		_step=mini(2,_route.size())
		_gait.reset(_dining_screen(_dining_escort_feet,layout.cell_px))
	if _route.is_empty(): return
	var standing_at := _dining_screen(_dining_escort_feet,layout.cell_px)
	var player_at := _dining_screen(floor_position,layout.cell_px)
	var waiting := _step<_route.size() and standing_at.distance_to(player_at)>178.0
	if not waiting and _step<_route.size():
		var floor_scale := Vector2(TDRestaurantIsoView.HALF_W,TDRestaurantIsoView.HALF_H).length()/float(layout.cell_px)
		_dining_escort_feet=_dining_escort_feet.move_toward(_route[_step],room._player.walk_speed/floor_scale*minf(delta,.05))
		if _dining_escort_feet.is_equal_approx(_route[_step]): _step+=1
	var stopped := waiting or _step>=_route.size()
	_gait.sample(_dining_screen(_dining_escort_feet,layout.cell_px),false,stopped)
	var caption := "快跟上来" if waiting else ("后厨" if _step>=_route.size() else "阿铃")
	room._iso.story_escort={"point":_dining_escort_feet,"caption":caption,"frame":_gait.frame,
		"facing":TDStoryArt.four_way_facing(player_at-standing_at) if stopped else _gait.facing}
	room._iso.queue_redraw()

func _dining_screen(point: Vector2, cell_px: int) -> Vector2:
	return TDRestaurantIsoView.project(point.x/float(cell_px),point.y/float(cell_px))

func _follow_into_kitchen(delta: float) -> void:
	var world := shell().kitchen_view.kitchen.world
	if _route_key!="kitchen:1":
		clear_escort()
		_route_key="kitchen:1"
		_step=0
		_escort=TDStoryArt.TownActor.new()
		world.add_child(_escort)
		_escort.configure("aling",world._player.sprite_height)
		_escort.position=TDKitchenWorld.DOOR_POS+Vector2(-58,-60)
		_escort.z_index=2
		_route=world.staff_route(_escort.position,Vector2(568,535))
		_gait.reset(_escort.position,Vector2i.UP)
	if _step>=_route.size(): return
	var next := _route[_step]
	_escort.position=_escort.position.move_toward(next,TDKitchenPlayer.WALK_SPEED*minf(delta,.05))
	_gait.sample(_escort.position)
	_escort.pose(_gait.facing,_gait.frame)
	if _escort.position.is_equal_approx(next): _step+=1

func _update_escort(delta: float) -> void:
	var game := shell()
	var step := cursor()
	if step==1 and game.location=="restaurant":
		_follow_in_restaurant(delta)
		return
	if step==1 and game.location=="kitchen":
		_follow_into_kitchen(delta)
		return
	var remote := game.location=="voyage"
	var target := Vector2.INF
	if game.location=="town":
		var town := game.town
		match step:
			1: target=town._origin()+(Vector2(town._diner_door())+Vector2.ONE*.5)*town.cell_size()
			4,17: target=town.chen_door_point()
			7: target=town._origin()+(Vector2(TDHarbor.ARRIVAL)+Vector2.ONE*.5)*town.cell_size()
			20: target=_palace()
	elif remote and ((step==12 and game.visiting_town=="paris") or (step==17 and game.visiting_town=="tokyo")):
		target=(Vector2(TDTravelCatalog.port(game.visiting_town))+Vector2.ONE*.5)*game.visiting.cell_size
	if not target.is_finite() or game.profile.residence.stage=="following":
		clear_escort()
		return
	var player := game.visiting.player.position if remote else game.town._player.position
	var key := "%s:%d" % [game.visiting_town,step]
	if _route_key!=key or not is_instance_valid(_escort) or (not _escort.visible and player.distance_to(_route_spawn)>32):
		_make_route(key,player,target,remote)
	if not is_instance_valid(_escort) or not _escort.visible: return
	var gap := _escort.position.distance_to(player)
	_bubble.visible=gap>210 and _step<_route.size()
	if _bubble.visible or _step>=_route.size():
		_gait.sample(_escort.position,false,true)
		_escort.pose(TDStoryArt.four_way_facing(player-_escort.position))
		return
	var next := _route[_step]
	var distance := _escort.position.distance_to(next)
	if distance<=.01:
		_step+=1
		return
	var candidate := _escort.position.move_toward(next,TDKitchenPlayer.WALK_SPEED*minf(delta,.05))
	var clear_step: Callable = game.visiting.npc_step_clear if remote else game.town.npc_step_clear
	_detour_wait=maxf(0.0,_detour_wait-delta)
	if clear_step.call(_escort.position,candidate,_escort):
		_escort.position=candidate
	elif _step==_route.size()-1 and distance<=56.0:
		_step+=1
	elif _detour_wait<=0.0:
		_detour_wait=.4
		_detour_escort(clear_step)
	_gait.sample(_escort.position)
	_escort.pose(_gait.facing,_gait.frame)

func _detour_escort(clear_step: Callable) -> void:
	var start := _escort.position
	var forward := start.direction_to(_route[_step])
	var side := forward.orthogonal()
	for index: int in range(_step,mini(_route.size(),_step+9)):
		var rejoin := _route[index]
		if clear_step.call(start,rejoin,_escort):
			_step=index
			return
		for width: float in [34.0,-34.0,56.0,-56.0,76.0,-76.0]:
			for lead: float in [0.0,24.0,-18.0]:
				var waypoint := start+side*width+forward*lead
				if not clear_step.call(start,waypoint,_escort) or not clear_step.call(waypoint,rejoin,_escort): continue
				var route := PackedVector2Array([waypoint])
				route.append_array(_route.slice(index))
				_route=route
				_step=0
				return
	if _step==_route.size()-1:
		var goal := _route[_step]
		for offset: Vector2 in [-forward*40.0,side*40.0,-side*40.0]:
			var stop := goal+offset
			if clear_step.call(start,stop,_escort):
				_route[_step]=stop
				return

func _make_route(key: String, player: Vector2, target: Vector2, remote: bool) -> void:
	clear_escort()
	_route_key=key
	_route_spawn=player
	_step=0
	_detour_wait=0.0
	var game := shell()
	var world: Node2D = game.visiting if remote else game.town
	var can_stand: Callable = game.visiting._npc_can_stand if remote else game.town._npc_can_stand
	_escort=TDStoryArt.TownActor.new()
	world.add_child(_escort)
	var heading := (target-player).normalized()
	var can_spawn := func(feet: Vector2) -> bool:
		if not can_stand.call(feet): return false
		if not TDInteractionRange.ground_segment_clear(player,feet,can_stand): return false
		return game.visiting._other_people_clear(feet,feet,_escort) if remote else game.town._other_people_clear(feet,feet,"aling",_escort)
	_escort.place("aling",TDTownWorld.OUTDOOR_PERSON_HEIGHT,player,can_spawn,heading)
	_gait.reset(_escort.position)
	if not _escort.visible: return
	world.set_meta("revised_escort",_escort)
	_bubble=TDUI.label("快跟上来",24,Color("fff2c5"))
	_bubble.position=Vector2(-70,-_escort.display_height-35)/_escort.scale
	_bubble.scale=Vector2.ONE/_escort.scale
	_bubble.hide()
	_escort.add_child(_bubble)
	if not remote:
		var town := game.town
		var origin := town._origin()
		for point: Vector2 in town.reference_walk_path((_escort.position-origin)/town.cell_size(),(target-origin)/town.cell_size()):
			_route.append(origin+point*town.cell_size())
		if _route.is_empty():
			_route=_terrain_route(_escort.position,target,origin,town.cell_size()*.5,town.session.town_map.extent,can_stand)
		return
	_route=_terrain_route(_escort.position,target,Vector2.ZERO,game.visiting.cell_size*.5,game.visiting.map.extent,can_stand)

func _terrain_route(from: Vector2, target: Vector2, origin: Vector2, spacing: float, extent: int,
		can_stand: Callable) -> PackedVector2Array:
	var center := func(cell: Vector2i) -> Vector2:
		return origin+(Vector2(cell)+Vector2.ONE*.5)*spacing
	var checked := {}
	var walkable := func(cell: Vector2i) -> bool:
		if not checked.has(cell): checked[cell]=can_stand.call(center.call(cell))
		return checked[cell]
	var first := Vector2i(((from-origin)/spacing).floor())
	var start := first
	var connected := false
	for offset: Vector2i in [Vector2i.ZERO,Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT,
			Vector2i(-1,-1),Vector2i(1,-1),Vector2i(-1,1),Vector2i(1,1)]:
		start=first+offset
		if walkable.call(start) and TDInteractionRange.ground_segment_clear(from,center.call(start),can_stand):
			connected=true
			break
	if not connected: return PackedVector2Array()
	var goal := Vector2i(((target-origin)/spacing).floor())
	var side := extent*2+8
	var step_clear := func(current: Vector2i, next: Vector2i) -> bool:
		return TDInteractionRange.ground_segment_clear(center.call(current),center.call(next),can_stand)
	var grid := TDQuestPath.find(start,goal,Rect2i(0,0,side,side),walkable,side*side,step_clear)
	var points := PackedVector2Array()
	for cell: Vector2i in grid: points.append(center.call(cell))
	return points
