class_name TDBranchPanel
extends VBoxContainer
signal changed
## Store navigation and intents. Existing Shop/Branches/Roster remain the authorities.
var profile: TDGameProfile
var selected_id: String=""
var selected_town: String="chengdu"
var selected_cuisine: String="cn"
var selected_manager: String=""
var selected_rect: Array=[]
var map_view: SiteMap
var quote_label: Label
var status_label: Label
var manager_box: VBoxContainer
var create_button: Button
var site_button: Button
var _site_done: bool=false
var _site_controls: Array[Control]=[]
var _serial: int=0
const HOME: String="player_diner"
var store_buttons: Dictionary={}
var current_tab: String="menu"
var tab_buttons: Dictionary={}
var menu_rows: Dictionary={}
var budget_input: SpinBox
var pause_input: CheckBox
var apply_button: Button
var back_button: Button
var _supply_enabled: CheckBox
var _supply_budget: SpinBox


func configure(value: TDGameProfile) -> void:
	profile=value; theme=TDManagementPanels.theme();add_theme_constant_override("separation",12); selected_town=str(profile.commerce.state.home)
	list_stores()

func _clear() -> void:
	for child: Node in get_children(): remove_child(child); child.queue_free()

func _notice(text: String) -> void:
	if is_instance_valid(status_label): status_label.text=text; status_label.visible=not text.is_empty()

func _is_home() -> bool:
	return selected_id==HOME

func _store_name(id: String) -> String:
	return profile.title if id==HOME else str(profile.branches.state.stores.get(id,{}).get("name","店铺已不存在"))

func _ignore_mouse(node: Node) -> void:
	if node is Control: node.mouse_filter=Control.MOUSE_FILTER_IGNORE
	for child: Node in node.get_children(): _ignore_mouse(child)

func _scroll_top() -> void:
	var outer:=get_parent()
	while outer!=null:
		if outer is ScrollContainer: outer.set_deferred("scroll_vertical",0);return
		outer=outer.get_parent()

func list_stores() -> void:
	_clear();map_view=null;store_buttons.clear();selected_id="";current_tab="menu";menu_rows.clear()
	var heading:=HBoxContainer.new();add_child(heading)
	heading.add_child(TDManagementPanels.text("我的店铺",25,TDUI.ORANGE))
	var new_button:=TDUI.button("＋ 增设店铺",begin_site);new_button.disabled=not profile.at_boundary();heading.add_child(new_button)
	add_child(TDManagementPanels.text("1 家主店 · %d 家分店    点击店铺查看菜单、价格、员工和账目。"%profile.branches.paid_ids().size(),17,TDUI.MUTED))
	status_label=TDUI.label(str(profile.branches.state.legacy.get("migration_notice","")),17,TDUI.ORANGE);status_label.visible=not status_label.text.is_empty();add_child(status_label)
	var ids: Array=profile.branches.state.stores.keys();ids.sort_custom(func(a:String,b:String)->bool:return a.naturalnocasecmp_to(b)<0);ids.push_front(HOME)
	for id: String in ids:
		var home: bool=id==HOME
		var data: Dictionary={} if home else profile.branches.state.stores[id]
		var town_id: String=str(profile.commerce.state.home) if home else str(data.town_id)
		var manager:=profile.employees.manager_for(id)
		var books: Array=profile.commerce.state.books if home else data.books
		var automatic: bool=profile.main_management_auto if home else bool(data.get("management_auto",false))
		var button:=TDUI.button("",manage.bind(id));button.custom_minimum_size.y=112;add_child(button);store_buttons[id]=button
		var margin:=MarginContainer.new();button.add_child(margin);margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for side: String in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,16)
		var line:=HBoxContainer.new();line.add_theme_constant_override("separation",18);margin.add_child(line)
		var title_box:=VBoxContainer.new();title_box.size_flags_horizontal=Control.SIZE_EXPAND_FILL;title_box.size_flags_stretch_ratio=1.2;line.add_child(title_box)
		title_box.add_child(TDManagementPanels.text(_store_name(id)+("  · 主店" if home else ("  · 分店" if profile.branches.funded(id) else "  · 待核对记录")),22,TDManagementPanels.GOLD))
		title_box.add_child(TDManagementPanels.text(str(profile.commerce.config.towns[town_id].name)+" · "+("自有店面" if home else ("待核对选址（不计店铺）" if not profile.branches.funded(id) else str(TDPlayerBranches.TITLES[data.cuisine_id]))),16,TDUI.MUTED))
		var staff_box:=VBoxContainer.new();staff_box.size_flags_horizontal=Control.SIZE_EXPAND_FILL;line.add_child(staff_box)
		staff_box.add_child(TDManagementPanels.text("店长："+("待分配" if manager.is_empty() else str(manager.name)),18))
		staff_box.add_child(TDManagementPanels.text("厨师 %d 人 · 服务员 %d 人"%[profile.employees.assigned(id,"cook").size(),profile.employees.assigned(id,"waiter").size()],16,TDUI.MUTED))
		var info:=VBoxContainer.new();info.size_flags_horizontal=Control.SIZE_EXPAND_FILL;line.add_child(info)
		var state: String={"PREPARE":"筹备中","OPEN":"营业中","DRAINING":"收尾中","SETTLED":"已日结"}.get(profile.shop.snapshot().phase,"") if home else profile.branches.status_text(id)
		info.add_child(TDManagementPanels.text(state+" · "+("经营托管" if automatic else "手动管理"),17))
		info.add_child(TDManagementPanels.text("尚无日结记录" if books.is_empty() else "上次净利润 %+.2f 金币"%(float(books.back().profit_cents)/100),16,TDUI.MUTED))
		var arrow:=TDUI.label("›",30,TDUI.ORANGE);arrow.custom_minimum_size.x=24;line.add_child(arrow);_ignore_mouse(margin)
	_scroll_top()

func begin_site() -> void:
	_clear(); selected_manager=""; selected_rect=[]; _site_done=false; _site_controls=[]
	add_child(TDUI.label("① 菜系与地块 → ② 确认付款 → ③ 等待建成 → 任命店长",22,TDUI.ORANGE))
	var selectors:=HBoxContainer.new(); add_child(selectors)
	_site_controls.append(selectors)
	var cuisine_label:=TDUI.label("餐馆类型",18);cuisine_label.autowrap_mode=TextServer.AUTOWRAP_OFF
	selectors.add_child(cuisine_label)
	var cuisines:=OptionButton.new(); cuisines.custom_minimum_size=Vector2(210,44); selectors.add_child(cuisines)
	var cuisine_ids: Array=[]
	for id: String in TDPlayerBranches.CULTURES:
		if id not in profile.research.snapshot().cuisines or profile.branches.recipes(id).is_empty(): continue
		cuisine_ids.append(id); cuisines.add_item(str(TDPlayerBranches.TITLES[id]))
	selected_cuisine=str(cuisine_ids[0]); cuisines.item_selected.connect(func(index:int)->void:selected_cuisine=str(cuisine_ids[index]); _update_quote())
	var site_help:=TDUI.label("五镇均可开店，U 打开五镇供应商。每边3–12格、最多108格，须临路且不占已有用地。",16,TDUI.MUTED)
	add_child(site_help); _site_controls.append(site_help)
	var navigation:=HBoxContainer.new(); add_child(navigation); _site_controls.append(navigation)
	map_view=SiteMap.new(); map_view.configure(profile)
	map_view.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	navigation.add_child(TDUI.button("世界全览",map_view.reset_view))
	for id: String in TDTravelCatalog.IDS:
		navigation.add_child(TDUI.button(str(TDTravelCatalog.info(id).name),map_view.choose_town.bind(id)))
	add_child(map_view)
	map_view.town_selected.connect(func(id:String)->void:selected_town=id; selected_rect=[]; selected_manager=""; _update_quote())
	map_view.picked.connect(func(rect:Array)->void:selected_rect=rect; _update_quote())
	quote_label=TDUI.label("拖出范围查看报价。",18,TDUI.ORANGE); quote_label.custom_minimum_size.y=50; add_child(quote_label)
	var footer:=HBoxContainer.new();add_child(footer)
	site_button=TDUI.button("下一步：确认施工报价",_toggle_site); site_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL; footer.add_child(site_button)
	footer.add_child(TDUI.button("取消筹建",list_stores))
	manager_box=VBoxContainer.new(); add_child(manager_box)
	status_label=TDUI.label("",17,TDUI.ORANGE); status_label.hide(); add_child(status_label)
	create_button=TDUI.button("确认支付并开始施工",confirm); create_button.disabled=true; add_child(create_button)
	selected_town=""; _update_quote()

func _update_quote() -> void:
	var result:=profile.branches.quote(selected_town,selected_rect,selected_cuisine,selected_manager)
	site_button.disabled=not result.ok
	site_button.text="返回调整位置" if _site_done else "下一步：确认施工报价"
	manager_box.visible=_site_done
	create_button.visible=_site_done
	for item: Control in _site_controls: item.visible=not _site_done
	create_button.disabled=not result.ok or not _site_done
	map_view.valid=result.ok; map_view.queue_redraw()
	for child: Node in manager_box.get_children(): manager_box.remove_child(child); child.queue_free()
	if not result.ok:
		quote_label.text="先在世界地图点选小镇，再拖出餐馆范围。" if selected_town.is_empty() else (TDTravelCatalog.info(selected_town).name+" · "+(result.message if result.message!="" else "先拖出合法矩形范围。"))
		return
	var q:=result.data
	quote_label.text=TDTravelCatalog.info(selected_town).name+" · "+"占地%d×%d格 · 开办费 ¥%.2f（一次性） · 房租 ¥%.2f/日\n厨服 ¥%.2f/日 · 容量%d人/日 · 水电按实际接待与出餐计费"%[int(selected_rect[2]),int(selected_rect[3]),float(q.opening_cents)/100,float(q.rent_cents)/100,float(q.crew_cents)/100,int(q.capacity)]
	manager_box.add_child(TDUI.label("工期 %d 个游戏日 · 第%d天建成"%[int(profile.branches.config.construction_days),int(profile.shop.snapshot().day)+int(profile.branches.config.construction_days)],22,TDUI.ORANGE))
	manager_box.add_child(TDUI.label("确认后立即支付开办费并开始施工。施工期间不能进入或营业。\n建成后可在地图靠近店铺按 E 进入餐厅和厨房巡视。\n请在店员安排中从员工仓库任命店长；配齐厨师、服务员并备好原料后才营业。",19))
	manager_box.add_child(TDUI.label("施工日不收房租、开门水电与岗位工资；房租从建成日起计算。取消不扣钱、不占地。",17,TDUI.MUTED))

func _toggle_site() -> void:
	_site_done=not _site_done; map_view.visible=not _site_done; _update_quote()
	var container:=get_parent().get_parent() as ScrollContainer
	if container!=null: container.set_deferred("scroll_vertical",0)

func confirm() -> void:
	_serial+=1
	var token: String="branch:open:%s:%d"%[profile.shop.snapshot().run_id,int(profile.shop.snapshot().serial)+1]
	var result:=profile.branches.open_store(selected_town,selected_rect,selected_cuisine,"",token)
	if result.ok: list_stores();changed.emit()
	_notice(result.message if result.message!="" else result.code)

func manage(id: String) -> void:
	if profile==null or not profile._alive: return
	if id!=HOME and not profile.branches.state.stores.has(id): list_stores();_notice("这家店已不存在。");return
	selected_id=id;current_tab="menu";_detail()

func select_tab(tab: String) -> void:
	if tab not in ["menu","staff","management","books"]: return
	current_tab=tab;_detail()

func _automatic() -> bool:
	return profile.main_management_auto if _is_home() else bool(profile.branches.state.stores[selected_id].get("management_auto",false))

func _detail() -> void:
	if profile==null or not profile._alive: return
	_clear();map_view=null;menu_rows.clear();tab_buttons.clear();budget_input=null;pause_input=null
	var heading:=HBoxContainer.new();add_child(heading)
	back_button=TDUI.button("‹ 全部店铺",list_stores);heading.add_child(back_button)
	heading.add_child(TDManagementPanels.text(_store_name(selected_id)+(" · 主店" if _is_home() else (" · 分店" if profile.branches.funded(selected_id) else " · 待核对记录")),25,TDManagementPanels.GOLD))
	var manager:=profile.employees.manager_for(selected_id)
	add_child(TDManagementPanels.text("店长："+("尚未派驻" if manager.is_empty() else str(manager.name)+"★".repeat(int(manager.stars)))+" · "+("经营托管已开启" if _automatic() else "手动管理"),17,TDUI.MUTED))
	var tabs:=HBoxContainer.new();add_child(tabs)
	for pair: Array in [["menu","菜单与价格"],["staff","店员安排"],["management","托管与供货"],["books","账本与库存"]]:
		var button:=TDUI.button(pair[1],select_tab.bind(pair[0]));button.toggle_mode=true;button.button_pressed=current_tab==pair[0];tabs.add_child(button);tab_buttons[pair[0]]=button
	status_label=TDUI.label("",17,TDUI.ORANGE);status_label.hide();add_child(status_label)
	if not _is_home():
		add_child(TDUI.label(profile.branches.status_text(selected_id),19,TDUI.ORANGE))
		if not profile.branches.funded(selected_id):
			add_child(TDUI.label("这是没有开办付款凭证的旧选址，原账目和货物记录仍在。不会出现在地图或营业。核对后可主动付款施工，不会自动补扣费用。",18))
			var old: Dictionary=profile.branches.state.stores[selected_id]
			var quote:=profile.branches.quote(old.town_id,old.rect,old.cuisine_id,"",selected_id)
			var pay:=TDUI.button("确认支付 %.2f 金币并施工"%(float(quote.data.get("opening_cents",0))/100),_fund_pending)
			pay.disabled=not quote.ok;add_child(pay)
			if not quote.ok: add_child(TDUI.label("原选址暂不能施工："+(quote.message if not quote.message.is_empty() else quote.code),17,TDUI.ORANGE))
	if not profile.at_boundary(): add_child(TDUI.label("营业中仅查阅，打烊后可调整。",17,TDUI.ORANGE))
	match current_tab:
		"menu": _menu_page()
		"staff": _staff_page()
		"management": _management_page()
		"books": _books_page()
	_scroll_top()

func _fund_pending() -> void:
	var token: String="branch:fund:%s:%d"%[profile.shop.snapshot().run_id,int(profile.shop.snapshot().serial)+1]
	var result:=profile.branches.fund_unverified(selected_id,token)
	if result.ok: _detail();changed.emit()
	_notice(result.message if not result.message.is_empty() else result.code)

func _menu_page() -> void:
	var data: Dictionary={} if _is_home() else profile.branches.state.stores[selected_id]
	var choices: Array=profile.main_menu_rows() if _is_home() else profile.branches.recipes(data.cuisine_id)
	var editable: bool=profile.at_boundary() and not _automatic()
	add_child(TDUI.label("勾选当日上架菜品，右侧填写每份售价。" if not _automatic() else "店长会在筹备时选择菜单与价格；关闭经营托管后可手动修改。",17,TDUI.MUTED))
	for dish: Dictionary in choices:
		var row:=HBoxContainer.new();row.add_theme_constant_override("separation",18);add_child(row)
		var check:=CheckBox.new();check.text=dish.name;check.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(check)
		var current: Array=[] if _is_home() else data.menu.filter(func(d:Dictionary)->bool:return d.id==dish.id)
		check.button_pressed=bool(dish.enabled) if _is_home() else not current.is_empty();check.disabled=not editable
		var reference:=TDUI.label("参考价 %.2f"%(float(dish.reference_cents)/100),16,TDUI.MUTED);reference.custom_minimum_size.x=140;row.add_child(reference)
		var price:=SpinBox.new();price.min_value=.01;price.max_value=10000;price.step=.01;price.prefix="金币 ";price.value=float(dish.price_cents if _is_home() or current.is_empty() else current[0].price_cents)/100;price.custom_minimum_size=Vector2(190,44);price.editable=editable;row.add_child(price)
		menu_rows[dish.id]={"check":check,"price":price}
	if not _is_home():
		add_child(TDUI.label("每日采购预算",18))
		budget_input=SpinBox.new();budget_input.min_value=0;budget_input.max_value=100000;budget_input.step=1;budget_input.prefix="金币 ";budget_input.value=float(data.budget_cents)/100;budget_input.editable=profile.at_boundary();add_child(budget_input)
		pause_input=CheckBox.new();pause_input.text="暂停营业（当日已发生工资及房租照常结算）";pause_input.button_pressed=data.paused;pause_input.disabled=not profile.at_boundary();add_child(pause_input)
	apply_button=TDUI.button("应用菜单与价格" if _is_home() else "应用菜单、预算与营业安排",apply_menu);apply_button.disabled=not profile.at_boundary() or (choices.is_empty()) or (_is_home() and not editable);add_child(apply_button)

func apply_menu() -> void:
	if profile==null or not profile._alive: return
	var chosen: Array=[]
	for id: String in menu_rows:
		if menu_rows[id].check.button_pressed: chosen.append({"id":id,"price_cents":roundi(menu_rows[id].price.value*100)})
	var result:=profile.shop.configure_menu(chosen) if _is_home() else profile.branches.configure_store(selected_id,chosen,roundi(budget_input.value*100),pause_input.button_pressed)
	if result.ok: changed.emit()
	_notice(result.message if not result.message.is_empty() else result.code)

func _staff_page() -> void:
	add_child(TDUI.label("从员工仓库安排人手。上岗计日薪，撤回后待命；今天已发生的工资不撤销。",17,TDUI.MUTED))
	for role: String in ["manager","cook","waiter"]:
		var box:=TDManagementPanels.card(self)
		var people:=profile.employees.assigned(selected_id,role)
		box.add_child(TDUI.label("%s · %d / %d 人"%[TDManagementPanels.role_name(role),people.size(),int(profile.employees.config.role_caps[role])],21,TDUI.ORANGE))
		for person: Dictionary in people:
			var line:=HBoxContainer.new();box.add_child(line)
			line.add_child(TDManagementPanels.text("%s %s · 日薪 %.2f"%[person.name,"★".repeat(int(person.stars)),float(person.wage_cents)/100],18))
			var remove:=TDUI.button("调回仓库",assign_employee.bind(str(person.id),""));remove.disabled=not profile.at_boundary();line.add_child(remove)
		var idle: Array=profile.employees.assigned("",role)
		if not idle.is_empty() and people.size()<int(profile.employees.config.role_caps[role]):
			var line:=HBoxContainer.new();box.add_child(line)
			var select:=OptionButton.new();select.custom_minimum_size=Vector2(350,44);select.size_flags_horizontal=Control.SIZE_EXPAND_FILL;line.add_child(select)
			for person: Dictionary in idle: select.add_item("%s %s · 日薪 %.2f"%[person.name,"★".repeat(int(person.stars)),float(person.wage_cents)/100]);select.set_item_metadata(select.item_count-1,str(person.id))
			select.disabled=not profile.at_boundary()
			var appoint:=TDUI.button("派驻本店",func()->void:
				if select.selected>=0: assign_employee(str(select.get_item_metadata(select.selected)),selected_id))
			appoint.disabled=not profile.at_boundary();line.add_child(appoint)
		elif people.is_empty(): box.add_child(TDUI.label("仓库没有待命的此类员工。按 H 前往招聘市场。",17,TDUI.MUTED))
	var missing: Array[String]=[]
	for role: String in ["manager","cook","waiter"]:
		if profile.employees.assigned(selected_id,role).is_empty(): missing.append(TDManagementPanels.role_name(role))
	add_child(TDUI.label("三岗位齐备，可由员工协作经营。" if missing.is_empty() else "待安排："+"、".join(missing)+("。主店仍可由玩家亲自工作。" if _is_home() else "。分店暂不接客。"),17,TDUI.ORANGE))

func assign_employee(id: String, target: String) -> void:
	var result:=profile.employees.assign(id,target);_detail();_notice(result.message if not result.message.is_empty() else result.code)
	if result.ok: changed.emit()

func _management_page() -> void:
	var auto:=CheckBox.new();auto.text="开启经营托管";auto.button_pressed=_automatic();auto.disabled=not profile.at_boundary();add_child(auto);auto.toggled.connect(set_management)
	add_child(TDUI.label("店长在筹备时安排闲置员工、已掌握菜单与价格。员工使用实际食材与时间完成工作。",18,TDUI.MUTED))
	if _is_home() and profile.employees.manager_for(HOME).is_empty(): add_child(TDUI.label("店长缺位，自动配置暂停。请在“店员安排”中派驻店长。" if _automatic() else "请先在“店员安排”中为主店派驻店长。",17,TDUI.ORANGE))
	if _is_home(): add_child(TDUI.label("开门和打烊仍由你决定；厨师负责做菜，服务员负责传菜与收银。",17,TDUI.MUTED))
	var supply: Dictionary=profile.suppliers.state.automation.get(selected_id,{"enabled":false,"budget_cents":0})
	var box:=TDManagementPanels.card(self)
	box.add_child(TDUI.label("供应托管",22,TDUI.ORANGE))
	_supply_enabled=CheckBox.new();_supply_enabled.text="按本店菜单自动补货";_supply_enabled.button_pressed=bool(supply.enabled);_supply_enabled.disabled=not profile.at_boundary();box.add_child(_supply_enabled)
	box.add_child(TDUI.label("独立控制本店的自动采购，遵守预算与实际余额；已付款订单继续生产。",17,TDUI.MUTED))
	_supply_budget=SpinBox.new();_supply_budget.min_value=0;_supply_budget.max_value=100000;_supply_budget.step=1;_supply_budget.prefix="每日预算 · 金币 ";_supply_budget.value=float(supply.budget_cents)/100;_supply_budget.editable=profile.at_boundary();box.add_child(_supply_budget)
	var save:=TDUI.button("应用供货设置",func()->void:
		var result:=profile.suppliers.set_automation(selected_id,_supply_enabled.button_pressed,roundi(_supply_budget.value*100))
		if result.ok: profile.suppliers.automate()
		_notice(result.message if not result.message.is_empty() else ("本店供货设置已更新。" if result.ok else result.code)))
	save.disabled=not profile.at_boundary();box.add_child(save)

func set_management(value: bool) -> void:
	var result:=profile.set_main_management(value) if _is_home() else profile.branches.set_management(selected_id,value)
	_detail();_notice(result.message if not result.message.is_empty() else result.code)
	if result.ok: changed.emit()

func _books_page() -> void:
	var data: Dictionary={} if _is_home() else profile.branches.state.stores[selected_id]
	var books: Array=profile.commerce.state.books if _is_home() else data.books
	add_child(TDUI.label("最近日账",22,TDUI.ORANGE))
	if books.is_empty(): add_child(TDUI.label("完成一天营业后，这里会记录真实收支。",18,TDUI.MUTED))
	for book: Dictionary in books.slice(maxi(0,books.size()-7)):
		var box:=TDManagementPanels.card(self)
		box.add_child(TDUI.label(main_report_text(book) if _is_home() else report_text(book),18))
	var debt: int=int(profile.commerce.state.debt_cents) if _is_home() else TDPlayerBranches.debt_total(data)
	add_child(TDUI.label("当前欠费 %.2f 金币"%(float(debt)/100),19,TDUI.ORANGE))
	add_child(TDUI.label("本店库存",22,TDUI.ORANGE))
	var stock: Dictionary=profile.shop.snapshot() if _is_home() else data
	var lots: Dictionary=stock.inventory_lots if _is_home() else stock.lots
	var lines: Array[String]=[]
	for item: String in stock.inventory:
		if int(stock.inventory[item])<=0: continue
		lines.append("%s  %.2f · 第%d天到期"%[profile._factory_item(item).get("name",item),float(stock.inventory[item])/1000,TDFoodStock.first_expiry(lots,item)])
	add_child(TDUI.label("\n".join(lines) if not lines.is_empty() else "暂无库存。按 U 指定本店进货，或开启本店供应托管。",17))

static func main_report_text(book: Dictionary) -> String:
	return "第%d天 · 净销售 %.2f · 净利润 %+.2f 金币\n耗料 %.2f / 工资 %.2f / 房租 %.2f / 水电 %.2f / 利息 %.2f / 税 %.2f"%[int(book.day),float(book.sales_net_cents)/100,float(book.profit_cents)/100,float(book.consumed_cost_cents)/100,float(book.get("wages_cents",0))/100,float(book.rent_cents)/100,float(book.utilities_cents)/100,float(book.get("interest_cents",0))/100,float(book.get("tax_cents",0))/100]

static func report_text(d: Dictionary) -> String:
	return "第%d天 · 接待%d人 · 销售 ¥%.2f · 净利润 %+.2f元\n采购 %.2f / 耗料 %.2f / 过期 %.2f / 店长 %.2f / 厨服 %.2f / 租金 %.2f / 水电 %.2f / 税 %.2f\n%s"%[int(d.day),int(d.served),float(d.sales_cents)/100,float(d.profit_cents)/100,float(d.purchase_cents)/100,float(d.consumed_cents)/100,float(d.spoilage_cents)/100,float(d.manager_cents)/100,float(d.crew_cents)/100,float(d.rent_cents)/100,float(d.utilities_cents)/100,float(d.tax_cents)/100,str(d.reason)]

class SiteMap extends TDTravelMapView:
	## Same atlas as M. Only local view state; TDPlayerBranches owns all land/cash rules.
	signal town_selected(id: String)
	signal picked(rect: Array)
	var selected_town: String=""
	var selection:=Rect2i()
	var valid: bool=false
	var _start:=Vector2i.ZERO
	var _site_drag: bool=false
	var _preview:=Rect2i()
	var _land: ImageTexture
	var _occupied: Dictionary={}

	func _init() -> void:
		minimum_view_size=Vector2(1080,350);max_zoom=12;show_player=false
		heading="分店选址 · 世界全览";controls_hint="点击小镇放大 · 滚轮缩放 · 中键拖动地图"

	func _ready() -> void:
		super._ready()
		resized.connect(_cancel_drag)
		visibility_changed.connect(_cancel_drag)

	func _notification(what: int) -> void:
		super._notification(what)
		if what==NOTIFICATION_WM_WINDOW_FOCUS_OUT: _cancel_drag()

	func _cancel_drag() -> void:
		_site_drag=false;_dragging=false;_preview=Rect2i();queue_redraw()

	func reset_view() -> void:
		_cancel_drag();selected_town="";selection=Rect2i();valid=false
		heading="分店选址 · 世界全览";controls_hint="点击小镇放大 · 滚轮缩放 · 中键拖动地图"
		super.reset_view();town_selected.emit("")

	func choose_town(id: String) -> void:
		if not maps.has(id): return
		_cancel_drag();selected_town=id;selection=Rect2i();valid=false
		zoom=5;pan=-(ORIGINS[id]+Vector2.ONE*TOWN_SIZE*.5-WORLD_SIZE*.5)*scale_factor()
		_limit_pan();_build_land()
		heading="分店选址 · "+str(TDTravelCatalog.info(id).name)
		controls_hint="左键拖出范围 · 中键拖动 / 滚轮缩放 · 浅绿可建 / 深色已占 / 蓝色水域"
		town_selected.emit(id);queue_redraw()

	func _town_at(point: Vector2) -> String:
		if not Rect2(Vector2(0,68),Vector2(size.x,size.y-104)).has_point(point): return ""
		for id: String in maps:
			if Rect2(ORIGINS[id],Vector2.ONE*TOWN_SIZE).has_point(screen_to_world(point)): return id
		return ""

	func _cell(point: Vector2) -> Vector2i:
		if selected_town.is_empty() or _town_at(point)!=selected_town: return Vector2i(-1,-1)
		return Vector2i(((screen_to_world(point)-ORIGINS[selected_town])*float(maps[selected_town].extent)/TOWN_SIZE).floor())

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
				_cancel_drag();zoom_at(event.position,1.22 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.0/1.22);accept_event()
			elif event.button_index==MOUSE_BUTTON_MIDDLE:
				_cancel_drag();_dragging=event.pressed;accept_event()
			elif event.button_index==MOUSE_BUTTON_LEFT:
				if event.pressed:
					var id:=_town_at(event.position)
					if id.is_empty(): _cancel_drag();return
					if selected_town!=id or zoom<4:
						choose_town(id);accept_event();return
					_start=_cell(event.position);_site_drag=true;_preview=Rect2i(_start,Vector2i.ONE)
				elif _site_drag:
					var cell:=_cell(event.position)
					if cell.x>=0:
						_preview_to(cell);selection=_preview;valid=false
						picked.emit([selection.position.x,selection.position.y,selection.size.x,selection.size.y])
					_cancel_drag()
				queue_redraw();accept_event()
		elif event is InputEventMouseMotion:
			if _dragging: pan+=event.relative;_limit_pan()
			if _site_drag:
				var cell:=_cell(event.position)
				if cell.x<0: _cancel_drag()
				else: _preview_to(cell)
			_hover=_town_at(event.position);queue_redraw();accept_event()

	func _preview_to(cell: Vector2i) -> void:
		var origin:=Vector2i(mini(cell.x,_start.x),mini(cell.y,_start.y))
		_preview=Rect2i(origin,Vector2i(absi(cell.x-_start.x)+1,absi(cell.y-_start.y)+1))

	func caption_text() -> String:
		if selected_town.is_empty(): return "五镇均可选址 · 开店与进口商路独立 · 道路、住房和既有建筑不可占用"
		return str(TDTravelCatalog.info(selected_town).caption)

	func _build_land() -> void:
		var map: TDTownMap=maps[selected_town]
		var image:=Image.create(map.extent*6,map.extent*6,false,Image.FORMAT_RGBA8)
		_occupied.clear()
		for plot: Dictionary in map.plots:
			for y: int in range(int(plot.y),int(plot.y+plot.h)):
				for x: int in range(int(plot.x),int(plot.x+plot.w)): _occupied[Vector2i(x,y)]=true
		for y: int in map.extent:
			for x: int in map.extent:
				var at:=Vector2i(x,y);var terrain:=map.terrain_at(at)
				var color:=Color("93b28b") if terrain.buildable else Color("4d755b")
				if terrain.terrain_type=="water": color=Color("327e95")
				elif _occupied.has(at): color=Color("635a4c")
				elif map.is_road(x,y): color=Color("cec2a3")
				elif terrain.surface_type=="sand": color=Color("bcb384")
				image.fill_rect(Rect2i(x*6,y*6,6,6),color)
				image.fill_rect(Rect2i(x*6,y*6+5,6,1),color.darkened(.13))
				image.fill_rect(Rect2i(x*6+5,y*6,1,6),color.darkened(.13))
		_land=ImageTexture.create_from_image(image)

	func _draw_land_overlay() -> void:
		if selected_town.is_empty() or _land==null or zoom<4: return
		var origin: Vector2=ORIGINS[selected_town]
		var area:=Rect2(world_to_screen(origin),Vector2.ONE*TOWN_SIZE*scale_factor())
		draw_texture_rect(_land,area,false)
		# Actual footprints remain visible; illustrative building roofs never hide selectable cells.
		var map: TDTownMap=maps[selected_town]
		var unit: float=TOWN_SIZE/float(map.extent)*scale_factor()
		for plot: Dictionary in map.plots:
			var rect:=Rect2(cell_to_screen(selected_town,Vector2(plot.x,plot.y)),Vector2(plot.w,plot.h)*unit)
			if not Rect2(Vector2.ZERO,size).intersects(rect): continue
			var color:=Color("e8b85d") if plot.has("branch_id") else Color("9b8971")
			draw_rect(rect,color,false,2)
			if rect.size.x>35: _text(rect.position+Vector2(3,15),TDTravelCatalog.label(plot,selected_town),12,color)
		var chosen: Rect2i=_preview if _site_drag else selection
		if chosen.has_area():
			var rect:=Rect2(cell_to_screen(selected_town,Vector2(chosen.position)),Vector2(chosen.size)*unit)
			var color:=Color("f5d58a") if _site_drag else (Color("b6ff9f") if valid else Color("ff7a60"))
			draw_rect(rect,Color(color,.3));draw_rect(rect,color,false,2)
			_text(rect.position+Vector2(0,-6),"%d × %d格"%[chosen.size.x,chosen.size.y],16,color)
