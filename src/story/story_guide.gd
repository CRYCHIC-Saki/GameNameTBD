class_name TDStoryGuide
extends Control
## Shell-owned chapter presentation. Opening owns progress; Shop owns money/materials.
var shell: TDGameShell
var dialogue: TDDialogueView
var _layer: CanvasLayer
var _trail: TDQuestTrail
var _card: PanelContainer
var _title: Label
var _hint: Label
var _pending_tutorial: String=""
var _route_key: String=""
var _route: Array[Vector2i]=[]
var _reference_route := PackedVector2Array()
var _pulse: float=0
var _scene_key: String=""
var _cut_count: int=0
var _bark_until: float=0
var _bark: Label
var _bark_portrait: TextureRect
var _reply_at: float=-1
var _previous_modules: Dictionary={}
var _bark_key: String=""
var _closed: bool=false
var _bark_seen: Dictionary={}
var _first_arrival: bool=false
var _event_place: String=""

func reserved_bottom() -> float:
	return _card.get_global_rect().end.y if _card!=null and _card.is_visible_in_tree() else 0.0

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS;mouse_filter=Control.MOUSE_FILTER_IGNORE
	_layer=CanvasLayer.new();_layer.layer=50;add_child(_layer)
	_trail=TDQuestTrail.new();_layer.add_child(_trail)
	_card=PanelContainer.new();_card.position=Vector2(26,118);_card.size=Vector2(372,0)
	_card.mouse_filter=Control.MOUSE_FILTER_IGNORE;_card.theme=TDUI.theme();_layer.add_child(_card)
	var box:=VBoxContainer.new();box.mouse_filter=Control.MOUSE_FILTER_IGNORE;_card.add_child(box)
	_title=TDUI.label("第一口异端",TDUI.FONT_BODY,TDUI.ORANGE);box.add_child(_title)
	_hint=TDUI.label("",TDUI.FONT_BODY);_hint.custom_minimum_size.x=348;_hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;box.add_child(_hint)
	_bark_portrait=TextureRect.new();_bark_portrait.position=Vector2(1025,350);_bark_portrait.size=Vector2(150,170)
	_bark_portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;_bark_portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_bark_portrait.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;_bark_portrait.mouse_filter=Control.MOUSE_FILTER_IGNORE;_layer.add_child(_bark_portrait)
	_bark=TDUI.label("",TDUI.FONT_BODY,Color("ffe4a0"));_bark.position=Vector2(955,530);_bark.size=Vector2(300,120);_bark.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_bark.mouse_filter=Control.MOUSE_FILTER_IGNORE;_layer.add_child(_bark)
	dialogue=TDDialogueView.new();_layer.add_child(dialogue);dialogue.closed.connect(_on_dialogue_closed)
	dialogue.hero_named.connect(func(value:String)->void:
		if shell.profile!=null and dialogue.talk!=null and dialogue.talk.context.get("kind")=="story": shell.profile.story.hero_name=value)
	shell.town.story_requested.connect(request_person)
	shell.town.authored_interaction = request_authored_person
	shell.restaurant.authored_interaction = request_authored_person
	shell.kitchen_view.story_delivery=shell.profile.shop.table_service.place_trial
	shell.profile.shop.table_service.trial_check=check_trial_delivery
	shell.profile.shop.table_service.trial_received=serve_trial
	shell.kitchen_view.story_cooking_check=check_trial_cooking
	shell.profile.shop.practice_supply_policy=practice_supplies
	shell.kitchen_view.kitchen.tutorial_gate=tutorial_gate

func presenting() -> bool:
	return dialogue!=null and dialogue.visible

func begin_arrival() -> void:
	# Called synchronously before the first new-slot frame can be drawn.
	_first_arrival=true
	shell.town.hide();shell.town._status_panel.hide();shell._hud_layer.hide()
	present("intro")

func _process(delta: float) -> void:
	if shell==null or shell.profile==null: return
	observe_authored()
	var story:=shell.profile.story
	if presenting() and dialogue.talk!=null and dialogue.talk.display_kind=="line": shell.profile.characters.mark_met(dialogue.talk.portrait_id)
	if shell.atlas!=null and shell.atlas.selected_id=="C02" and story.waiting_cook(): story.recipe_viewed=true
	var hidden:=shell.location=="voyage" or presenting() or shell._modal!=null or shell.atlas!=null or shell.kitchen_view._popup!=null or not story.started()
	var pending_home: bool=not shell.profile.has_residence() and shell.profile.residence.stage!="locked"
	_card.visible=not hidden and (not story.finished() or pending_home)
	_trail.visible=not hidden and story.tracked and (not story.finished() or pending_home)
	if not get_tree().paused and not presenting(): _pulse+=delta
	var now:=objective()
	_hint.text=str(now.get("text",""));_title.text="主线 · "+str(now.get("title","第一口异端"))
	_card.reset_size()
	if shell.location=="kitchen" and shell.kitchen_view.kitchen.stage.visible: _card.hide();_trail.hide()
	if _trail.visible: update_route(now)
	_bark.visible=not hidden and shell.location=="kitchen" and _pulse<_bark_until
	_bark_portrait.visible=_bark.visible
	if not hidden and shell.location=="kitchen": cooking_barks()
	if hidden or get_tree().paused:
		if shell.location=="voyage" or not story.started(): play_authored()
		return
	if not shell.profile.has_residence():
		if story.served and shell.profile.shop.snapshot().phase=="SETTLED": shell.profile.invite_home("first_day")
		if shell.profile.residence.stage=="invited" and shell.location=="town": begin_homecoming();return
		if shell.profile.residence.stage in ["following","door"]: return
	if story.beat=="awaken" and shell.location=="restaurant": present("awaken")
	elif story.beat=="verdict" and shell.location=="restaurant": present("verdict_good" if story.good else "verdict_bad")
	elif story.beat=="founded" and not story.setup_seen and shell.location=="restaurant": present("setup")
	else: play_authored()

func request_person(who: String) -> void:
	if presenting() or shell._modal!=null: return
	if request_authored_person(who): return
	if who=="aling" and not shell.profile.has_residence():
		if shell.profile.residence.stage=="locked": shell.profile.invite_home("first_day")
		if shell.profile.residence.stage=="invited": begin_homecoming();return
		if shell.profile.residence.stage=="door": present_home("home_door");return
	var story:=shell.profile.story
	if who=="bowl" and story.beat=="bowl":
		var box:=shell._dialog("老陈屋内 · 黎明圣羹",true)
		box.add_child(TDUI.label("浓黑汤面上浮着焦蛋，碗边结着盐。",TDUI.FONT_SECTION))
		box.add_child(TDUI.button("尝一口",func()->void:shell._close_dialog();present("after_taste")))
		return
	if story.beat=="founded" and story.served and who=="aling":
		var talk:=TDDialogue.new();talk.story_layout(shell.profile.title,"aling");talk.context={"kind":"story","scene":"end_day"}
		talk.add_line("阿铃","aling","第一日的灶火没有熄灭。夜鸦记下了：下一站，港口。","happy")
		talk.add_line("提示","","第一章已完成。港口厨师的后续剧情尚未开放。","calm","","ui")
		show_talk(talk);return
	var id:=story.scene_for(who)
	if id!="": present(id)
	else: show_talk(story.talk(who,shell.profile.title,shell.town.chapter_ready,shell.profile.world.san,shell.town.story_board))

func present(id: String) -> void:
	if _closed or presenting(): return
	var talk:=TDOpeningScript.conversation(id,hero_name(),shell.profile.world.san)
	if id=="intro": talk.context.request_name=shell.profile.story.hero_name.is_empty()
	show_talk(talk)

func hero_name() -> String:
	return shell.profile.story.hero_name if not shell.profile.story.hero_name.is_empty() else "？？？"

func begin_homecoming() -> void:
	if shell.profile.residence.stage!="invited" or presenting(): return
	present_home("home_late" if shell.profile.residence.reason=="late" else "home_invite")

func present_home(scene: String) -> void:
	if presenting(): return
	show_talk(TDOpeningScript.home_conversation(scene,hero_name()))

func show_talk(talk: TDDialogue) -> void:
	_scene_key=str(talk.context.get("scene",""));dialogue.present(talk)
	shell.town.external_story_frozen=true;shell.restaurant.story_frozen=true
	shell.kitchen_view.set_paused(true);shell._lock_controls(false)

func _on_dialogue_closed(_text: String, _picks: Array) -> void:
	var story:=shell.profile.story
	var home_finished: bool=false
	if dialogue.last_context.get("kind") == "authored_event":
		var committed := shell.profile.story_events.finish(int(dialogue.last_context.get("event_token",-1)),dialogue.last_completed,_apply_event_effect)
		if dialogue.last_completed and not committed: shell._message("演出的完成效果未能应用，未记录完成；可重新触发后再试。")
	elif _scene_key in ["home_invite","home_late","home_door"]:
		if dialogue.last_completed:
			if _scene_key=="home_door": home_finished=shell.profile.unlock_residence().ok
			elif shell.profile.residence.stage=="invited": shell.profile.residence.stage="following"
	elif _scene_key=="end_day" and dialogue.last_completed and story.beat=="founded" and story.served:
		story.beat="done"
	else: shell._apply_story(story.complete_scene(_scene_key,dialogue.last_completed))
	_scene_key="";shell.town.external_story_frozen=false;shell.restaurant.story_frozen=false
	if _first_arrival:
		_first_arrival=false;shell.town.set_presented(true)
		shell.town.sync_characters(0);shell.town._follow_camera()
	shell.kitchen_view.set_paused(get_tree().paused);shell._lock_controls(true)
	if home_finished:
		shell.travel("cottage",true)
		shell._message("小屋已解锁。靠近床按 E 保存或休息；退出不会自动保存，未完成的教学会随存档保留。")

func show_journal() -> void:
	if presenting() or shell.atlas!=null or shell._modal!=null: return
	var story:=shell.profile.story
	var box:=shell._dialog("任务 · 第一口异端",true)
	box.add_child(TDUI.label("主线  ·  "+("已完成" if story.finished() else "进行中"),TDUI.FONT_SECTION,TDUI.ORANGE))
	var now:=objective();box.add_child(TDUI.label(str(now.get("text","")),TDUI.FONT_SECTION))
	var stages: Array=[{"ids":["arrive","follow"],"text":"寻找传说中的美味 · 跟随阿铃"},{"ids":["soup","bowl"],"text":"众口称颂的圣餐 · 尝一口汤"},{"ids":["return","awaken","cook"],"text":"唤醒灶火 · 为阿铃做番茄炒蛋"},{"ids":["verdict"],"text":"第一位异端 · 听取真实评价"},{"ids":["founded"],"text":"点燃第一日 · 菜单、备货、开门与打烊"}]
	var reached: bool=false
	for entry: Dictionary in stages:
		var active: bool=story.beat in entry.ids
		if active: reached=true
		box.add_child(TDUI.label(("◆ " if active else ("○ " if reached else "✓ "))+str(entry.text),TDUI.FONT_BODY,TDUI.ORANGE if active else TDUI.MUTED))
	box.add_child(TDUI.button("停止追踪 [T]" if story.tracked else "追踪任务 [T]",func()->void:story.tracked=not story.tracked;shell._close_dialog()))
	box.add_child(TDUI.button("操作教学手册",show_manual))
	if story.finished(): box.add_child(TDUI.button("第一章回顾（不改变进度或奖励）",show_replay))
	for event: Dictionary in shell.profile.story_events.definitions:
		if shell.profile.story_events.counts.has(event.id): box.add_child(TDUI.label("✓ "+str(event.title),TDUI.FONT_BODY,TDUI.MUTED))
		elif shell.profile.story_events.eligible(event,TDStoryEvents.milestones_for(shell.profile)):
			var label: String = {"person":"交谈：","place":"前往：","milestone":"等待节点："}[event.type]
			var names: Dictionary = {"person":TDStoryEvents.PEOPLE,"place":TDStoryEvents.PLACES,"milestone":TDStoryEvents.MILESTONES}[event.type]
			box.add_child(TDUI.label(str(event.title)+" · "+label+str(names[event.target]),TDUI.FONT_BODY))
			if event.type=="milestone" and TDStoryEvents.milestones_for(shell.profile).get(event.target,false):
				box.add_child(TDUI.button("观看演出",func()->void:
					shell._close_dialog();shell.profile.story_events.notify("milestone",event.target,TDStoryEvents.milestones_for(shell.profile));play_authored()))

func objective() -> Dictionary:
	var story:=shell.profile.story
	if not shell.profile.has_residence():
		var stage: String=shell.profile.residence.stage
		if stage!="locked":
			return {"title":"夜鸦的落脚密令","room":"town","target":"cottage" if stage=="door" else ("escort" if stage=="following" else "aling"),"text":{"invited":"到店外找阿铃","following":"跟随阿铃前往小屋","door":"E 接过钥匙"}[stage]}
	var result: Dictionary={"title":"第一口异端","text":story.quest(shell.town.chapter_ready,shell.town.story_board),"room":"town","target":"aling"}
	match story.beat:
		"arrive": result.text="与阿铃交谈"
		"follow","return": result.target="escort";result.text="跟随阿铃"
		"soup": result.target="bowl";result.text="到老陈家门前交谈"
		"bowl": result.target="bowl";result.text="E 进屋尝汤"
		"awaken","verdict": result.room="restaurant";result.target="table"
		"cook":
			result.title="唤醒灶火";result.room="kitchen";result.target="kitchen.fridge"
			var plate:=shell.profile.shop.table_service.for_order(TDTableService.TRIAL_ORDER)
			if not plate.is_empty():
				result.room="restaurant";result.target="trial" if plate.carrier=="player" else "pass"
				result.text="E 给阿铃上菜" if plate.carrier=="player" else "回餐厅出餐口取菜"
				return result
			var kitchen:=shell.kitchen_view.kitchen
			var handling:=kitchen.handling
			if handling.hand_kind=="dish":
				var issue:=trial_plate_problem(handling.hand.snapshot().to_dict())
				result.text="E 放到出餐口" if issue.ok else issue.message
				result.target="kitchen.serve" if issue.ok else "kitchen.trash";return result
			for lane: TDCookingLane in kitchen.lanes:
				if lane.snapshot().state=="plated":
					var issue:=trial_plate_problem(lane.snapshot())
					result.text="E 端起番茄炒蛋" if issue.ok else "菜没做成，端到垃圾桶后重新取料。"
					result.target="kitchen.stove.left" if lane.lane_index==0 else "kitchen.stove.right";return result
			if not story.recipe_viewed: result.text="B 查看番茄炒蛋的做法";return result
			var pot:=0
			for lane: TDCookingLane in kitchen.lanes:
				if not lane.snapshot().ingredients.is_empty(): pot=lane.lane_index;break
			var pot_id: String="kitchen.stove.left" if pot==0 else "kitchen.stove.right"
			if handling.hand_kind=="ingredient":
				var food: Dictionary=handling.hand.snapshot().to_dict().ingredients.values()[0]
				if food.ingredient_id=="tomato" and food.shape=="whole": result.text="在砧板把番茄切成大块";result.target="kitchen.board"
				else: result.text="E 放入同一口锅";result.target=pot_id
			elif handling.board!=null:
				result.text="切好后 E 取走";result.target="kitchen.board"
			else:
				var foods: Array=kitchen.lanes[pot].snapshot().ingredients.values().map(func(x:Dictionary)->String:return x.ingredient_id)
				if "tomato" in foods and "egg" in foods: result.text="F 开火";result.target=pot_id
				else: result.text="从冰箱取"+("鸡蛋" if "tomato" in foods else "番茄")
		"founded":
			result.title="点燃第一日"
			if story.served and shell.profile.has_residence(): result.text="今日灶火已收。去店外与阿铃谈谈明日的打算。"
			if not story.served:
				result.room="restaurant";result.target="menu"
				if not shell.town.story_board.get("stock",false) and shell.profile.at_boundary(): result.room="town";result.target="market"
	return result

func trial_customer() -> Dictionary:
	var requirements: Array=[]
	for item: Dictionary in shell.profile.service.cooking.data().customers[0].requirements:
		if item.id in ["sweet_front","chunk","tender"]: requirements.append(item.duplicate(true))
	return {"id":"story.aling.trial","name":"阿铃","requirements":requirements}

func practice_supplies() -> Dictionary:
	return {"tomato":1000,"egg":1000} if not _closed and shell.profile!=null and shell.profile.story.waiting_cook() else {}

func check_trial_cooking(dish: Dictionary, method: String) -> TDOutcome:
	if not shell.profile.story.waiting_cook(): return TDOutcome.new(true,"NOT_TRIAL_COOKING")
	var ids: Array=[];var extras: Array[String]=[]
	for food: Dictionary in dish.get("ingredients",{}).values():
		ids.append(food.ingredient_id)
		if shell.profile.service.is_primary(food.ingredient_id) and food.ingredient_id not in ["tomato","egg"]: extras.append(str(food.name))
	if not extras.is_empty(): return TDOutcome.new(false,"TRIAL_EXTRA_MATERIAL","阿铃这次要番茄炒蛋。请先按 Q 取出多放的"+"、".join(extras)+"，放回冰箱。")
	var missing: Array[String]=[]
	if "tomato" not in ids: missing.append("番茄")
	if "egg" not in ids: missing.append("鸡蛋")
	if not missing.is_empty(): return TDOutcome.new(false,"TRIAL_MISSING_MATERIAL","锅里还缺"+"和".join(missing)+"。去冰箱领取，按 E 放进同一口炒锅，再按 F 开火。")
	if method!="stir": return TDOutcome.new(false,"TRIAL_WRONG_METHOD","番茄炒蛋要用炒锅，不能蒸。按 Q 取回食材，放进左侧炒锅后按 F。")
	return TDOutcome.new(true,"TRIAL_READY")

func trial_plate_problem(dish: Dictionary) -> TDOutcome:
	if dish.get("recipe_id","") in TDOpening.TRIAL_RECIPES and not dish.get("failed_dish",false): return TDOutcome.new(true,"TRIAL_PLATE")
	var method: String=str(dish.get("recipe",{}).get("cooking_method","steam" if str(dish.get("recipe_id","")).ends_with("steam") else "stir"))
	var issue:=check_trial_cooking(dish,method)
	var cause: String="这盘是失败的菜品。"
	if issue.code=="TRIAL_MISSING_MATERIAL": cause="这盘缺少番茄或鸡蛋，未识别为番茄炒蛋。"
	elif issue.code=="TRIAL_EXTRA_MATERIAL": cause="多放了其他主料，这盘不是番茄炒蛋。"
	elif issue.code=="TRIAL_WRONG_METHOD": cause="这盘用了蒸制，番茄炒蛋需要用炒锅。"
	elif not dish.get("failed_dish",false): cause="这盘是其他菜，阿铃这次想尝番茄炒蛋。"
	return TDOutcome.new(false,"WRONG_TRIAL_DISH",cause+"先到垃圾桶按 E 放下，再从冰箱领取教程食材重试。")

func check_trial_delivery(dish: Dictionary) -> TDOutcome:
	if shell.profile.story.beat!="cook": return TDOutcome.new(false,"NOT_STORY_DELIVERY")
	return trial_plate_problem(dish)

func serve_trial(dish: Dictionary) -> TDOutcome:
	var story:=shell.profile.story
	if story.beat!="cook": return TDOutcome.new(false,"NOT_STORY_DELIVERY")
	var issue:=trial_plate_problem(dish)
	if not issue.ok: return issue
	var rated:=TDCustomerScorer.new().evaluate(dish,trial_customer())
	if not rated.ok: return rated
	var accepted:=story.accept_trial(dish,rated.data)
	if accepted.ok: call_deferred("show_trial_feedback")
	return accepted

func show_trial_feedback() -> void:
	if _closed or shell.profile==null: return
	var rating: Dictionary=shell.profile.story.assessment
	var box:=shell._dialog("阿铃 · 本次试做",true)
	box.add_child(TDUI.label("%.1f 分"%float(rating.satisfaction),42,TDUI.ORANGE))
	box.add_child(TDUI.label("大块番茄 · 嫩鸡蛋 · 略带甜味",TDUI.FONT_SECTION))
	box.add_child(TDUI.label("完成度 %.1f / 搭配度 %.1f"%[rating.quality,rating.harmony],TDUI.FONT_BODY))
	for reason: Dictionary in rating.reasons: box.add_child(TDUI.label("• "+str(reason.message),TDUI.FONT_BODY))
	if rating.reasons.is_empty(): box.add_child(TDUI.label("这次做法符合阿铃的期待。",TDUI.FONT_BODY))
	box.add_child(TDUI.button("回餐厅听听她怎么说",func()->void:shell._close_dialog();shell.travel("restaurant")))

const LESSONS: Dictionary={
	"M1":["切配 · 按谱落刀","空格：落刀    A / D：转食材","等符号到判定线时按对应键。转向也是谱面的一拍；切型已由你选的大块决定。"],
	"M2":["热锅点火","空格：点火","观察移动游标，进入绿色区时按一次空格。先看一轮轨迹，别连按。"],
	"M3":["翻炒搅拌","左锅 W A S D    右锅 ↑ ← ↓ →    空格收势","跟随箭头逐拍输入；最后按空格收势。按错仍可继续下一拍。"],
	"M4":["翻炒时控温","鼠标靠近温度条，按住左键加强吸引","让游标保持在目标区内，同时用键盘翻炒。M6 调味时控温会自动托管，不抢鼠标。"],
	"M5":["蒸煮控温","鼠标靠近目标温区，按住左键调节","观察温度变化，留在标记范围；不需要按鼓点连击。"],
	"M6":["顺序调味","鼠标按住亮起的调料，到目标量松开","开始标记告诉你何时按下，进度到目标线松开。越久加得越多；灰色调料已耗尽。"],
	"M7":["出锅","按住空格 → 进入绿色区时松开","这一关判定松开的时机。等起手提示后按住，观察充能游标；不要只点一下。"]}

func tutorial_gate() -> bool:
	if shell.profile==null or shell.location!="kitchen" or not shell.profile.story.waiting_cook(): return true
	if _pending_tutorial!="":
		if shell._modal==null and not get_tree().paused and not shell.kitchen_view.kitchen.shared_clock.paused: _pending_tutorial=""
		else: return false
	for lane: TDCookingLane in shell.kitchen_view.kitchen.lanes+[shell.kitchen_view.kitchen.prep]:
		for progress: Dictionary in [lane.progress if lane.qte!=null else {},lane.thermal_progress if lane.thermal_qte!=null else {}]:
			var module:=str(progress.get("pc_module",""))
			if module in LESSONS and module not in shell.profile.story.tutorials:
				_pending_tutorial=module;shell.kitchen_view.set_paused(true);call_deferred("show_lesson",module);return false
	return true

func show_lesson(module: String) -> void:
	if _closed or shell.profile==null or module!=_pending_tutorial: return
	var row: Array=LESSONS[module];var box:=shell._dialog(str(row[0]),true)
	box.add_child(TDUI.label("首次操作教学 · 时间已暂停",TDUI.FONT_BODY,TDUI.MUTED))
	box.add_child(TDUI.label(str(row[1]),TDUI.FONT_DISPLAY,TDUI.ORANGE));box.add_child(TDUI.label(str(row[2]),TDUI.FONT_SECTION))
	box.add_child(TDUI.label("阿铃：命运尚未宣判。失误不用重来，盯住下一拍！",TDUI.FONT_BODY))
	box.add_child(TDUI.button("明白了，开始操作",func()->void:
		if module not in shell.profile.story.tutorials: shell.profile.story.tutorials.append(module)
		_pending_tutorial="";shell._close_dialog()))

func cooking_barks() -> void:
	if not shell.profile.story.waiting_cook(): return
	if _reply_at>=0 and _pulse>=_reply_at:
		_reply_at=-1;say_bark("aling","calm","命运尚未宣判。继续，盯住下一拍！",2.5)
	for lane: TDCookingLane in shell.kitchen_view.kitchen.lanes+[shell.kitchen_view.kitchen.prep]:
		var module:=str(lane.progress.get("pc_module",""))
		if lane.thermal_qte!=null and not _bark_seen.has("heat"):
			_bark_seen.heat=true;say_bark("aling","calm","别让赤焰冲出标记，鸡蛋承受不了你的野心！",3)
		if module=="M3" and _previous_modules.get(lane.lane_index,"")=="M6" and not _bark_seen.has("season"):
			_bark_seen.season=true;say_bark("chen","surprised","竟然在第九勺之前停手……你果然踏上了禁忌之路！",3)
		if module!="": _previous_modules[lane.lane_index]=module
		var feedback: Dictionary=lane.judgement_feedback
		var key:=str(lane.lane_index)+str(feedback.get("shown_at_sec",""))+str(feedback.get("grade",""))
		if feedback.is_empty() or key==_bark_key: continue
		if str(feedback.get("grade","")).to_lower().contains("miss"):
			_bark_key=key
			if _pulse>=_bark_until:
				say_bark("hero","sad","这一击……偏离了命运。",1.5);_reply_at=_pulse+1.5
		elif lane==shell.kitchen_view.kitchen.prep and _cut_count==0:
			_cut_count=1;_bark_key=key;say_bark("hero","happy","赤焰流 · 断界！",1.6)

func say_bark(who: String, mood: String, line: String, seconds: float) -> void:
	_bark_portrait.texture=TDStoryArt.portrait(who,mood)
	_bark.text={"hero":hero_name(),"aling":"阿铃","chen":"老陈"}.get(who,who)+"："+line
	_bark_until=_pulse+seconds

func update_route(goal: Dictionary) -> void:
	var room:=shell.location;var destination:=str(goal.get("room","town"));var target:=str(goal.get("target","aling"))
	var start:=Vector2i.ZERO;var end:=Vector2i.ZERO;var bounds:=Rect2i();var can_walk: Callable;var project: Callable
	if room=="town":
		var town:=shell.town;start=town._player_cell();var point:=Vector2.ZERO
		if town._uses_reference_escort():
			_update_reference_town_route(town, destination, target)
			return
		if destination!="town":
			var plot:=town.session._plot_by_id("player_diner");point=Vector2(plot.x,plot.y)+Vector2(plot.w,plot.h)*.5
		elif target=="cottage": point=Vector2(shell.profile.residence.plot.approach_x,shell.profile.residence.plot.approach_y)
		elif target=="escort": point=(town.escort_position()-town._origin())/town.cell_size()
		elif target=="bowl": point=(town.bowl_point()-town._origin())/town.cell_size()
		elif target=="market":
			var plot:=town._plot_of_kind("market");point=Vector2(plot.x,plot.y)+Vector2(plot.w,plot.h)*.5
		else:
			for person: Dictionary in town._story_people():
				if person.id==target: point=Vector2(person.get("position",Vector2(person.cell)))
		end=Vector2i(point);bounds=Rect2i(0,0,town.session.town_map.extent,town.session.town_map.extent)
		can_walk=func(cell:Vector2i)->bool:return town.session.town_map.is_road(cell.x,cell.y)
		project=func(cell:Vector2i)->Vector2:return town.get_global_transform_with_canvas()*(town._origin()+(Vector2(cell)+Vector2(.5,.5))*town.cell_size())
	elif room=="restaurant":
		var restaurant:=shell.restaurant;start=restaurant.cell_of_player()
		var action:=target if destination=="restaurant" else ("kitchen" if destination=="kitchen" else "town")
		if action=="table": action="kitchen"
		for item: Dictionary in restaurant.interaction_points():
			if item.action==action: end=Vector2i(item.cell)
		if action=="pass": end=restaurant.service_window_cell()
		if action=="trial":
			for guest: TDRestaurantGuest in restaurant.guest_nodes():
				if guest.ticket_id==TDTableService.TRIAL_ORDER: end=restaurant._beside_seat(guest.seat_id)
		bounds=Rect2i(0,0,restaurant.layout.columns,restaurant.layout.rows)
		can_walk=func(cell:Vector2i)->bool:return restaurant.layout.is_walkable(cell.x,cell.y)
		project=func(cell:Vector2i)->Vector2:return restaurant._iso.get_global_transform_with_canvas()*restaurant._iso.project(cell.x+.5,cell.y+.5)
	elif room in ["kitchen","cottage"]:
		var world: Node2D=shell.kitchen_view.kitchen.world if room=="kitchen" else shell.cottage
		var player: TDKitchenPlayer=shell.kitchen_view.kitchen.world._player if room=="kitchen" else shell.cottage.player
		var point:=Vector2(640,700) if room=="kitchen" else TDCottageWorld.DOOR
		if room=="kitchen" and destination=="kitchen":
			for station: Dictionary in shell.kitchen_view.kitchen.world.stations():
				if station.id==target: point=station.position
		start=Vector2i(player.position/16);end=Vector2i(point/16);bounds=Rect2i(0,0,80,50)
		can_walk=func(cell:Vector2i)->bool:
			var at: Vector2=(Vector2(cell)+Vector2(.5,.5))*16
			if not Rect2(38,292,1204,432).has_point(at) and room=="kitchen": return false
			if room=="cottage" and not TDCottageWorld.ROOM.grow(-12).has_point(at): return false
			var query:=PhysicsShapeQueryParameters2D.new();var shape:=CircleShape2D.new();shape.radius=12
			query.shape=shape;query.transform=Transform2D(0,world.to_global(at));query.collision_mask=player.collision_mask
			return world.get_world_2d().direct_space_state.intersect_shape(query,1).is_empty()
		project=func(cell:Vector2i)->Vector2:return world.get_global_transform_with_canvas()*((Vector2(cell)+Vector2(.5,.5))*16)
	else: _trail.points=[];return
	var key:=room+str(end)+str(shell.profile.world.map_revision)+str(shell.profile.layout.to_dict().hash())
	if key!=_route_key or not _route.has(start):
		_route_key=key;_route=TDQuestPath.find(start,end,bounds,can_walk)
	var points:=PackedVector2Array()
	for cell: Vector2i in _route.slice(maxi(0,_route.find(start))): points.append(project.call(cell))
	_trail.points=points;_trail.phase=_pulse;_trail.queue_redraw()

func _update_reference_town_route(town: TDTownWorld, destination: String, target: String) -> void:
	var origin := town._origin()
	var start := (town._player.position - origin) / town.cell_size()
	var goal := Vector2(town._diner_door()) + Vector2.ONE * .5
	if destination == "town":
		match target:
			"cottage":
				goal = Vector2(shell.profile.residence.plot.approach_x, shell.profile.residence.plot.approach_y) + Vector2.ONE * .5
			"escort":
				goal = (town.escort_position() - origin) / town.cell_size()
			"bowl":
				goal = (town.bowl_point() - origin) / town.cell_size()
			"market":
				var market := town._plot_of_kind("market")
				goal = Vector2(market.approach_x, market.approach_y) + Vector2.ONE * .5
			_:
				for person: Dictionary in town._story_people():
					if person.id == target:
						goal = Vector2(person.get("position", Vector2(person.cell))) + Vector2.ONE * .5
	var key := "reference" + str(Vector2i(start.floor())) + str(Vector2i(goal.floor())) + str(shell.profile.world.map_revision)
	if key != _route_key:
		_route_key = key
		_reference_route = town.reference_walk_path(start, goal)
	var points := PackedVector2Array()
	var project := town.get_global_transform_with_canvas()
	for at: Vector2 in _reference_route:
		points.append(project * (origin + at * town.cell_size()))
	_trail.points = points
	_trail.phase = _pulse
	_trail.queue_redraw()

func close() -> void:
	_closed=true;_pending_tutorial=""
	if shell!=null and shell.profile!=null: shell.profile.story_events.cancel(); shell.profile.story_events.pending.clear()
	if shell!=null and shell.town!=null: shell.town.authored_interaction=Callable()
	if shell!=null and shell.restaurant!=null: shell.restaurant.authored_interaction=Callable()
	if dialogue!=null: dialogue.dismiss()
	if shell!=null and shell.town!=null: shell.town.external_story_frozen=false
	if shell!=null and shell.profile!=null:
		shell.profile.shop.practice_supply_policy=Callable()
		shell.profile.shop.table_service.trial_check=Callable()
		shell.profile.shop.table_service.trial_received=Callable()
	if shell!=null and shell.kitchen_view!=null: shell.kitchen_view.story_cooking_check=Callable()
	set_process(false)

func authored_place() -> String:
	return "town:"+str(shell.visiting_town) if shell.location in ["town","voyage"] else shell.location

func observe_authored() -> void:
	var events := shell.profile.story_events
	if events.definitions.is_empty(): return
	var milestones := TDStoryEvents.milestones_for(shell.profile)
	events.observe(milestones)
	var place := authored_place()
	if place != _event_place:
		_event_place = place; events.notify("place",place,milestones)

func authored_safe() -> bool:
	if _closed or presenting() or shell.profile == null or get_tree().paused: return false
	if shell._modal != null or shell.atlas != null or shell._night_closing or shell.kitchen_view._popup != null: return false
	if shell.town.story_dialogue_open() or shell.kitchen_view.kitchen.stage.visible or _pending_tutorial != "": return false
	if shell.restaurant._talk_open() or shell.restaurant._editing: return false
	var story := shell.profile.story
	if shell.location=="restaurant" and (story.beat in ["awaken","verdict"] or (story.beat=="founded" and not story.setup_seen)): return false
	if not shell.profile.has_residence() and shell.profile.residence.stage != "locked": return false
	return true

func request_authored_person(who: String) -> bool:
	if not authored_safe(): return false
	var story := shell.profile.story
	# Existing mandatory conversation and escort/homecoming always take priority.
	if story.scene_for(who) != "" or story.beat in ["follow","return"]: return false
	if who == "aling" and not shell.profile.has_residence() and story.served: return false
	shell.profile.story_events.notify("person",who,TDStoryEvents.milestones_for(shell.profile))
	return play_authored()

func play_authored() -> bool:
	if not authored_safe(): return false
	if shell.profile.story_events.pending.is_empty(): return false
	var event := shell.profile.story_events.begin_next(TDStoryEvents.milestones_for(shell.profile),authored_place(),shell.profile.at_boundary())
	if event.is_empty(): return false
	var script := VNEngineScenarioLoader.load_script(event.script_path,null)
	var issue := TDStoryEvents.validate_authored_source(FileAccess.get_file_as_string(event.script_path)) if FileAccess.file_exists(event.script_path) else ""
	if script==null or script.has_errors() or not issue.is_empty():
		shell.profile.story_events.cancel();shell._message("这段演出未通过检查，请在剧情编辑器中修复后重试。");return false
	var talk := TDDialogue.new(); talk.story_layout(hero_name(),"")
	talk.context = {"kind":"authored_event","scene":"authored:"+str(event.id),"event_chapter":event,"event_token":event.token}
	show_talk(talk)
	return true

func _apply_event_effect(event: Dictionary) -> TDOutcome:
	var token: String = "authored:"+str(event.id)
	match event.effect.kind:
		"cuisine": return shell.profile.research.recommend_cuisine(token,event.effect.target)
		"route": return shell.profile.recommend_route(event.effect.target,token)
	return TDOutcome.new(true)

func show_manual() -> void:
	var box:=shell._dialog("操作教学手册",true)
	for module: String in LESSONS:
		var row: Array=LESSONS[module]
		box.add_child(TDUI.label(str(row[0])+" · "+str(row[1]),TDUI.FONT_SECTION,TDUI.ORANGE))
		box.add_child(TDUI.label(str(row[2]),TDUI.FONT_BODY))

func show_replay() -> void:
	var box:=shell._dialog("第一章回顾",true)
	for pair: Array in [["intro","赤焰之手，空腹降临"],["soup","众口称颂的圣餐"],["after_taste","第一口异端"],["awaken","唤醒灶火"],["verdict_good","第一位异端 · 好评"],["verdict_bad","第一位异端 · 有失误"],["setup","点燃第一日"]]:
		var id:=str(pair[0])
		box.add_child(TDUI.button(str(pair[1]),func()->void:
			shell._close_dialog()
			var talk:=TDOpeningScript.conversation(id,hero_name(),shell.profile.world.san)
			talk.context={"kind":"story_replay","scene":id};show_talk(talk)))
