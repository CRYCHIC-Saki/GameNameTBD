class_name TDDebugCommands
extends RefCounted
## Explicit debug adapter. Never owns a Profile or writes a save file directly.
const HELP: Dictionary={
	"help":"help [命令]：分类帮助；Tab 补全，↑↓历史，Esc 返回。",
	"debug":"debug / debug off（或 debug_off）：启用/关闭调试修改。",
	"status":"status：当前槽、场景、钟表、现金、SAN、灵感、订单与员工。",
	"check":"check：只读校验完整存档和世界资金账，不保存。",
	"money":"money add <金币>：增加或减少现金，单次最多±1000000金币、两位小数；例 money add 10000。走账本，增加资金先偿还旧欠费。",
	"items":"items [ID或名称片段]：查食材ID、单位与当前库存。",
	"give":"give <食材ID或完整名称> <份数> [店铺ID]：免费调试补料，单次0.001–1000标准份、最多三位小数；默认主店，例 give tomato 10。调料同样按标准份计，不是购买包装数。",
	"stock":"stock [店铺ID] [关键词]：查库存；main为主店，分店ID用shop list查询。",
	"inspiration":"inspiration add <1..10000>：增加灵感；不制造经营等级或研习分数。",
	"recipes":"recipes [ID或名称片段]：查菜谱ID、掌握状态与运行时映射。",
	"recipe":"recipe unlock <菜谱ID或完整名称>：调试掌握该菜及前置、开放所属菜系。明确记录调试来源，不伪造挑战分数。例 recipe unlock C03。",
	"cuisine":"cuisine open <cn|eu|jp|sea|lat>：开放菜系，菜谱仍独立掌握。",
	"san":"san <0..100>：设置SAN，后续工序生效。",
	"time":"time / time set <HH:MM>：查看/设置08:00–次日01:59钟表（跨午夜用00:30或24:30）。仅筹备/日结，不推进订单、生产或日期。",
	"employee":"employee market <镇ID> <manager|cook|waiter>；employee owned [关键词]；employee hire <ID或完整姓名>（当前候选，真实付签约费）；employee assign <ID或姓名> <main|分店ID|idle>。",
	"shop":"shop list [关键词] / shop info <ID> / shop auto <ID> <on|off>：主店用main，任免沿员工仓库；不自动开店。",
	"orders":"orders [关键词]：只读查看当前订单、顾客、菜品、状态与耐心。",
	"supply":"supply [关键词]：查看五镇供应商生产任务。调整供货请用 open suppliers。",
	"quest":"quest：当前剧情节点和目标；quest track on/off：切换任务追踪，不跳过任务或发奖。",
	"open":"open <employees|shops|suppliers|recipes|quests|map|relationships>：打开现有管理界面。",
	"goto":"goto <town|restaurant|kitchen|cottage|harbor>：到主镇对应场景；不解锁小屋，不带着食物跨场景。",
	"save":"save：主动保存当前槽；仍要求合法时点、厨房整理完毕。其他命令不自动保存。",
	"tools":"tools：旧独立试验入口，不使用当前存档。",
	"clear":"clear：清空控制台输出；不修改游戏或已记命令历史。"
}
const OPEN: Dictionary={"employees":"employees","shops":"branches","suppliers":"suppliers","recipes":"recipes","quests":"quests","map":"map","relationships":"relationships"}

static func tokenize(raw: String) -> TDOutcome:
	if raw.length()>512: return TDOutcome.new(false,"COMMAND_TOO_LONG","命令最多512字符。")
	var words: PackedStringArray=[];var word: String="";var quote: String="";var started: bool=false
	for ch: String in raw:
		if not quote.is_empty():
			if ch==quote: quote=""
			else: word+=ch
			started=true
		elif ch in ["\"","'"]: quote=ch;started=true
		elif ch in [" ","\t","\r","\n"]:
			if started: words.append(word);word="";started=false
		else: word+=ch;started=true
	if not quote.is_empty(): return TDOutcome.new(false,"UNCLOSED_QUOTE","引号没有闭合。")
	if started: words.append(word)
	return TDOutcome.new(true,"TOKENS","",{"words":words})

static func scaled(text: String, digits: int, minimum: int, maximum: int) -> TDOutcome:
	var pattern:=RegEx.new();pattern.compile("^[+-]?[0-9]{1,9}(\\.[0-9]{1,%d})?$"%digits)
	if pattern.search(text)==null: return TDOutcome.new(false,"INVALID_NUMBER","请输入普通十进制数字，最多%d位小数。"%digits)
	var negative:=text.begins_with("-");var parts:=text.trim_prefix("-").trim_prefix("+").split(".")
	var factor: int=100 if digits==2 else 1000
	var value: int=int(parts[0])*factor
	if parts.size()==2: value+=int(parts[1].rpad(digits,"0"))
	if negative: value=-value
	if value<minimum or value>maximum: return TDOutcome.new(false,"OUT_OF_RANGE","数值超出范围。")
	return TDOutcome.new(true,"NUMBER","",{"value":value})

static func outcome(result: TDOutcome) -> String:
	return ("成功 · " if result.ok else "失败 · ")+result.code+(" · "+result.message if not result.message.is_empty() else "")

static func token(p: TDGameProfile, kind: String) -> String:
	return "debug:%s:%s:%d:%d"%[kind,p.shop.snapshot().run_id,int(p.shop.snapshot().serial)+1,Time.get_ticks_usec()]

static func store_id(p: TDGameProfile, raw: String) -> String:
	if raw in ["main","主店","player_diner"]: return "player_diner"
	return raw if p.branches.state.stores.has(raw) else ""

static func resolve(rows: Array, value: String) -> String:
	for row: Dictionary in rows:
		if str(row.id).to_lower()==value.to_lower(): return str(row.id)
	var matches: Array=rows.filter(func(row:Dictionary)->bool:return str(row.get("name",""))==value)
	return str(matches[0].id) if matches.size()==1 else ""

static func select_rows(rows: Array, filter: String) -> Array:
	return rows.filter(func(row:Dictionary)->bool:return filter.is_empty() or (str(row.id)+" "+str(row.get("name",""))).to_lower().contains(filter.to_lower()))

static func limited(lines: Array[String]) -> String:
	var shown: Array[String]=lines.slice(0,40)
	if lines.size()>40: shown.append("共%d项，仅显示前40项；请加关键词缩小范围。"%lines.size())
	return "\n".join(shown) if not shown.is_empty() else "没有符合条件的记录。"

static func food_rows(p: TDGameProfile) -> Array:
	var rows: Array=[]
	for id: String in p.service.config.costs:
		var row:=p._factory_item(id);row.id=id;rows.append(row)
	rows.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return str(a.id)<str(b.id))
	return rows

static func blocked(shell: TDGameShell, boundary: bool=true) -> String:
	if shell.profile==null or not shell.profile._alive: return "没有活动存档，请先开始或载入游戏。"
	if (shell.guide!=null and shell.guide.presenting()) or (shell.town!=null and shell.town.story_dialogue_open()) or (shell.restaurant!=null and shell.restaurant._talk_open()): return "当前正在对话或演出，请结束后再修改。"
	if shell.atlas!=null or (shell.kitchen_view!=null and shell.kitchen_view.kitchen.stage.visible): return "正在研习或进行QTE，请结束后再修改。"
	if shell.kitchen_view!=null:
		for lane: TDCookingLane in shell.kitchen_view.kitchen.lanes+[shell.kitchen_view.kitchen.prep]:
			if lane.qte!=null or lane.thermal_qte!=null or (lane.sheet!=null and lane.sheet.running): return "正在进行QTE或后台烹饪，请结束后再修改。"
	if boundary and not shell.profile.at_boundary(): return "仅在筹备或日结后可修改；营业中可以查询。"
	return ""

static func help_text(topic: String="") -> String:
	if not topic.is_empty(): return str(HELP.get(topic,"未知帮助主题；输入 help 查看分类。"))
	return "输入 debug 启用。调试只改当前槽内存，主动 save 才保存。\n查询：status · check · items · stock · recipes · orders · supply · quest\n资源：money · give · inspiration · san\n经营：employee · shop · cuisine · recipe\n场景：time · goto · open · tools\n控制：help <命令> · clear · debug off · save\n快捷键：↑↓历史 · Tab补全 · Esc关闭。例：money add 10000；give tomato 10"

static func execute(shell: TDGameShell, raw: String) -> String:
	var parsed:=tokenize(raw)
	if not parsed.ok: return outcome(parsed)
	var w: PackedStringArray=parsed.data.words
	if w.is_empty(): return ""
	w[0]=w[0].to_lower();var cmd: String=w[0]
	if cmd=="help" and w.size()<=2: return help_text(w[1].to_lower() if w.size()==2 else "")
	if (cmd=="debug" and w.size()==1): shell.debug_enabled=true;return "调试模式已开启。help 查看命令；修改只在当前槽内存中生效。"
	if (cmd=="debug_off" and w.size()==1) or (cmd=="debug" and w.size()==2 and w[1]=="off"): shell.debug_enabled=false;return "调试模式已关闭。已发生的修改不会自动撤销，也未自动保存。"
	if not shell.debug_enabled: return "请先输入 debug。"
	if not HELP.has(cmd): return "未知命令“%s”，输入 help 或按 Tab 查看命令。"%cmd
	if cmd=="clear" and w.size()==1: shell._console_lines.clear();return "输出已清空。"
	if cmd=="tools" and w.size()==1:
		var reason:=blocked(shell,false)
		if shell.profile!=null and not reason.is_empty(): return reason
		shell.show_debug_tools();return "已打开独立调试工具。"
	var p: TDGameProfile=shell.profile
	if p==null or not p._alive: return "没有活动存档，请先开始或载入游戏。"
	var s:=p.shop.snapshot()
	if cmd=="status" and w.size()==1:
		return "%s · %s · 第%d天 %s · %s\n现金 %.2f 金币 · 人气%d · 店名气%.0f · SAN%d · 灵感%d\n店铺%d家 · 员工%d人 · 待单%d · 当前修改须主动保存"%[p.slot_id,shell.location,s.day,p.characters.clock.label(),s.phase,float(s.money_cents)/100,s.popularity,float(p.commerce.state.awareness)*100,p.world.san,p.research.snapshot().points,p.branches.paid_ids().size()+1,p.employees.roster_count(),p.shop.pending_orders().size()]
	if cmd=="check" and w.size()==1:
		var result:=TDGameProfile.validate_save(p.snapshot());var audit:=p.commerce.cash_audit(int(s.money_cents))
		return outcome(result)+"\n世界资金差额 %d 分 · 银行账差额 %d 分（均应为0）"%[int(audit.difference_cents),int(audit.bank_difference_cents)]
	if cmd=="items" and w.size()<=2:
		var lines: Array[String]=[]
		for row: Dictionary in select_rows(food_rows(p),w[1] if w.size()==2 else ""):
			lines.append("%s · %s · 库存 %.3f %s · 1=标准份（1000内部单位）"%[row.id,row.get("name",row.id),float(s.inventory.get(row.id,0))/1000,row.get("unit","份")])
		return limited(lines)
	if cmd=="stock" and w.size()<=3:
		var id:=store_id(p,w[1] if w.size()>=2 else "main")
		if id.is_empty(): return "未知店铺；用 shop list 查询ID。"
		var stock: Dictionary=s.inventory if id=="player_diner" else p.branches.state.stores[id].inventory
		var lines: Array[String]=[]
		for item: String in stock:
			if int(stock[item])>0: lines.append("%s · %s · %.3f"%[item,p._factory_item(item).get("name",item),float(stock[item])/1000])
		if w.size()==3: lines=lines.filter(func(line:String)->bool:return line.to_lower().contains(w[2].to_lower()))
		return id+"\n"+limited(lines)
	if cmd=="recipes" and w.size()<=2:
		var lines: Array[String]=[]
		for row: Dictionary in select_rows(p.research.catalog.nodes.values(),w[1] if w.size()==2 else ""):
			lines.append("%s · %s · %s · %s"%[row.id,row.name,p.research.status(row.id)+(" [调试授予]" if p.research.snapshot().events.has("debug:recipe:"+str(row.id)) else ""),p.research.catalog.runtime_id(row.id)])
		return limited(lines)
	if cmd=="time" and w.size()==1: return "第%d天 %s（%d分钟）"%[p.characters.clock.day,p.characters.clock.label(),floori(p.characters.clock.minute)]
	if cmd=="orders" and w.size()<=2:
		var lines: Array[String]=[]
		for row: Dictionary in s.orders: lines.append("%s · %s · %s · %s · 耐心 %s"%[row.id,row.get("customer_id",row.get("customer",{}).get("name","客人")),p.shop.recipe_name(str(row.recipe_id)),row.status,str(maxf(0.0,float(row.deadline_sec)-float(s.elapsed_sec)))])
		if w.size()==2: lines=lines.filter(func(line:String)->bool:return line.to_lower().contains(w[1].to_lower()))
		return limited(lines)
	if cmd=="supply" and w.size()<=2:
		var lines: Array[String]=[]
		for order: Dictionary in p.suppliers.snapshot().orders:
			for job: Dictionary in order.jobs:
				lines.append("%s · %s → %s · %s %.3f份 · %s"%[order.id,order.town_id,order.store_id,job.item_id,float(job.units)/1000,"已收货" if job.delivered else "剩余 %.1f 秒"%maxf(0.0,float(job.seconds)-float(job.elapsed))])
		if w.size()==2: lines=lines.filter(func(line:String)->bool:return line.to_lower().contains(w[1].to_lower()))
		return limited(lines)
	if cmd=="quest" and w.size()==1:
		return "剧情节点：%s · 追踪：%s\n%s"%[p.story.beat,str(p.story.tracked),JSON.stringify(shell.guide.objective() if shell.guide!=null else {},"  ")]
	if cmd=="employee" and w.size()>=2:
		if w[1]=="owned" and w.size()<=3:
			var lines: Array[String]=[]
			for row: Dictionary in select_rows(p.employees.roster_rows(),w[2] if w.size()==3 else ""): lines.append("%s · %s · %s %d星 · %s · 日薪%.2f"%[row.id,row.name,row.role,row.stars,row.assigned if not str(row.assigned).is_empty() else "idle",float(row.wage_cents)/100])
			return limited(lines)
		if w[1]=="market" and w.size()==4:
			if w[2] not in TDTravelCatalog.IDS or w[3] not in ["manager","cook","waiter"]: return "镇ID：chengdu/paris/tokyo/bangkok/mexico_city；岗位：manager/cook/waiter。"
			var lines: Array[String]=[]
			for row: Dictionary in p.employees.market_rows(w[2],w[3]): lines.append("%s · %s · %d星 · 签约%.2f · 日薪%.2f"%[row.id,row.name,row.stars,float(row.sign_fee_cents)/100,float(row.wage_cents)/100])
			return limited(lines)
	if cmd=="shop" and w.size()>=2:
		if w[1]=="list" and w.size() in [2,3]:
			var lines: Array[String]=["main / player_diner · "+p.title+" · 主店"]
			for id: String in p.branches.state.stores: lines.append("%s · %s · %s · %s"%[id,p.branches.state.stores[id].name,p.branches.state.stores[id].town_id,p.branches.status_text(id)])
			if w.size()==3: lines=lines.filter(func(line:String)->bool:return line.to_lower().contains(w[2].to_lower()))
			return limited(lines)
		if w[1]=="info" and w.size()==3:
			var id:=store_id(p,w[2])
			if id.is_empty(): return "未知店铺；用 shop list 查询。"
			return JSON.stringify({"id":id,"manager":p.employees.manager_for(id),"staff":p.employees.assigned(id),"management_auto":p.main_management_auto if id=="player_diner" else p.branches.state.stores[id].management_auto,"menu":s.menu if id=="player_diner" else p.branches.state.stores[id].menu,"supply":p.suppliers.state.automation.get(id,{})},"  ")
	var reason:=blocked(shell,cmd not in ["open","quest","san"])
	if not reason.is_empty(): return reason
	if cmd=="money" and w.size()==3 and w[1]=="add":
		var n:=scaled(w[2],2,-100000000,100000000)
		if not n.ok: return outcome(n)
		if int(n.data.value)==0: return "金额为0，未修改。"
		var result:=p.shop.world_adjustment(int(n.data.value),token(p,"money"),"控制台调试资金")
		return outcome(result)+" · 当前现金 %.2f 金币"%(float(p.shop.snapshot().money_cents)/100)
	if cmd=="give" and w.size() in [3,4]:
		var item:=resolve(food_rows(p),w[1]);var id:=store_id(p,w[3] if w.size()==4 else "main");var n:=scaled(w[2],3,1,1000000)
		if item.is_empty(): return "未知或歧义食材；用 items 查询ID。"
		if id.is_empty(): return "未知店铺；用 shop list 查询ID。"
		if not n.ok: return outcome(n)
		var result:=p.shop.receive_supply({item:int(n.data.value)},token(p,"give")) if id=="player_diner" else p.branches.receive_supply(id,{item:int(n.data.value)},{item:0},token(p,"give"))
		return outcome(result)+" · %s → %s · %.3f标准份"%[item,id,float(n.data.value)/1000]
	if cmd=="inspiration" and w.size()==3 and w[1]=="add":
		if not w[2].is_valid_int() or w[2].length()>6: return "灵感应为1至10000的整数。"
		return outcome(p.research.grant_inspiration(token(p,"inspiration"),int(w[2])))
	if cmd=="cuisine" and w.size()==3 and w[1]=="open": return outcome(p.research.recommend_cuisine(token(p,"cuisine"),w[2]))
	if cmd=="recipe" and w.size()==3 and w[1]=="unlock":
		var id:=resolve(p.research.catalog.nodes.values(),w[2])
		if id.is_empty(): return "未知或歧义菜谱；用 recipes 查询ID。"
		return outcome(p.research.debug_unlock(id))
	if cmd=="san" and w.size()==2:
		if not w[1].is_valid_int() or w[1].length()>3 or int(w[1])<0 or int(w[1])>100: return "SAN范围为0至100。"
		var value:=int(w[1]);p.world.san=value;shell.kitchen_view.day_san=value
		for lane: TDCookingLane in shell.kitchen_view.kitchen.lanes+[shell.kitchen_view.kitchen.prep]: lane.day_san=value
		return "SAN = %d（后续工序生效）"%value
	if cmd=="time" and w.size()==3 and w[1]=="set":
		var pattern:=RegEx.new();pattern.compile("^[0-2]?[0-9]:[0-5][0-9]$")
		if pattern.search(w[2])==null: return "时间格式 HH:MM，例如18:00。"
		var parts:=w[2].split(":");var hour:=int(parts[0]);var minute: int=hour*60+int(parts[1])
		if hour<2: minute+=1440
		if minute<480 or minute>=1560 or p.characters.clock.closed_day==p.characters.clock.day: return "只能设置08:00至次日01:59；02:00后须正常休息。"
		p.characters.clock.minute=float(minute)
		if shell.town!=null: shell.town.sync_characters(0,p.shop.snapshot().orders,float(minute))
		return "钟表已设为 "+p.characters.clock.label()+"；订单/生产/日期未快进，未保存。"
	if cmd=="employee" and w.size()>=2:
		if w[1]=="hire" and w.size()==3:
			var candidates: Array=[]
			for town: String in TDTravelCatalog.IDS:
				for role: String in ["manager","cook","waiter"]: candidates.append_array(p.employees.market_rows(town,role))
			var id:=resolve(candidates,w[2])
			if id.is_empty(): return "不是当前候选或已签约；employee market 查询当前ID。"
			var row: Dictionary=candidates.filter(func(x:Dictionary)->bool:return x.id==id)[0]
			return outcome(p.employees.sign_employee(id,token(p,"hire"),row.offer_key))
		if w[1]=="assign" and w.size()==4:
			var id:=resolve(p.employees.roster_rows(),w[2]);var store:=store_id(p,w[3])
			if id.is_empty(): return "员工不在仓库或姓名有歧义。"
			if w[3]!="idle" and store.is_empty(): return "未知店铺。"
			return outcome(p.employees.assign(id,"" if w[3]=="idle" else store))
	if cmd=="shop" and w.size()==4 and w[1]=="auto" and w[3] in ["on","off"]:
		var id:=store_id(p,w[2])
		if id.is_empty(): return "未知店铺。"
		return outcome(p.set_main_management(w[3]=="on") if id=="player_diner" else p.branches.set_management(id,w[3]=="on"))
	if cmd=="quest" and w.size()==3 and w[1]=="track" and w[2] in ["on","off"]:
		p.story.tracked=w[2]=="on";return "任务追踪 "+w[2]
	if cmd=="open" and w.size()==2 and OPEN.has(w[1]): shell._open_management(OPEN[w[1]]);return "已打开 "+w[1]
	if cmd=="goto" and w.size()==2 and w[1] in ["town","restaurant","kitchen","cottage","harbor"]:
		if w[1]=="cottage" and not p.has_residence(): return "小屋尚未解锁。"
		if not shell.kitchen_view.checkpoint_ready().ok: return "请先整理手中及工位食物。"
		var result:=shell.travel("town" if w[1]=="harbor" else w[1])
		if result.ok and w[1]=="harbor": shell.town.spawn_at_harbor()
		if result.ok: shell._close_dialog()
		return outcome(result)
	if cmd=="save" and w.size()==1: return outcome(shell.save_game())
	return "用法："+str(HELP[cmd])

static func complete(raw: String, p: TDGameProfile) -> PackedStringArray:
	var suggestions: Array[String]=[]
	for key: String in HELP: suggestions.append(key)
	suggestions.append_array(["debug off","money add ","inspiration add ","cuisine open ","time set ","employee market ","employee owned","employee hire ","employee assign ","shop list","shop info ","shop auto ","quest track on","quest track off"])
	for key: String in OPEN: suggestions.append("open "+key)
	for id: String in ["cn","eu","jp","sea","lat"]: suggestions.append("cuisine open "+id)
	for id: String in ["town","restaurant","kitchen","cottage","harbor"]: suggestions.append("goto "+id)
	for town: String in TDTravelCatalog.IDS:
		for role: String in ["manager","cook","waiter"]: suggestions.append("employee market %s %s"%[town,role])
	if p!=null and p._alive:
		for row: Dictionary in food_rows(p): suggestions.append("give "+str(row.id)+" ")
		for id: String in p.research.catalog.nodes: suggestions.append("recipe unlock "+id)
		for id: String in ["main"]+p.branches.state.stores.keys():
			suggestions.append("stock "+id);suggestions.append("shop info "+id);suggestions.append("shop auto "+id+" on");suggestions.append("shop auto "+id+" off")
		for row: Dictionary in p.employees.roster_rows(): suggestions.append("employee assign "+str(row.id)+" ")
		if raw.to_lower().begins_with("employee hire "):
			for town: String in TDTravelCatalog.IDS:
				for role: String in ["manager","cook","waiter"]:
					for row: Dictionary in p.employees.market_rows(town,role): suggestions.append("employee hire "+str(row.id))
	var found: PackedStringArray=[]
	for choice: String in suggestions:
		if choice.to_lower().begins_with(raw.to_lower()) and choice!=raw and choice not in found: found.append(choice)
	found.sort();return found
