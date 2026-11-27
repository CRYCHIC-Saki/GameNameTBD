class_name TDManagementPanels
extends RefCounted
## Domain state is supplied by the profile. Panels never save or own a wallet.

const PAPER:=Color("30251b")
const MUTED:=Color("65503a")
const GOLD:=Color("764019")

static func theme() -> Theme:
	return TDUI.theme()

static func text(value: String, font_size: int=TDUI.FONT_BODY, color: Color=PAPER) -> Label:
	var label:=TDUI.label(value,font_size,color);label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	return label

static func card(parent: Node, accent: Color=GOLD) -> VBoxContainer:
	var panel:=PanelContainer.new();panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL;parent.add_child(panel)
	var style:=TDUI.wood(TDUI.Surface.CARD,14)
	panel.add_theme_stylebox_override("panel",style)
	var box:=VBoxContainer.new();box.add_theme_constant_override("separation",8);panel.add_child(box)
	return box

static func employee_portrait(row: Dictionary, size_px: Vector2) -> TextureRect:
	var portrait:=TextureRect.new()
	portrait.texture=TDEmployeeArt.portrait(TDEmployeeRoster.REGION_CUISINES[row.town],row.role,row.appearance_variant)
	portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.custom_minimum_size=size_px
	portrait.mouse_filter=Control.MOUSE_FILTER_IGNORE
	return portrait

static func role_name(role: String) -> String:
	return {"manager":"店长","cook":"厨师","waiter":"服务员"}.get(role,"全部岗位")



class BasePanel extends VBoxContainer:
	signal changed
	signal notice(message: String)
	var profile: TDGameProfile
	var _status: Label
	func configure(value: TDGameProfile) -> void:
		profile=value;theme=TDManagementPanels.theme();add_theme_constant_override("separation",14)
	func clear() -> void:
		for child: Node in get_children(): remove_child(child);child.queue_free()
		_status=null
	func status_line() -> void:
		_status=TDManagementPanels.text("",TDUI.FONT_BODY,TDManagementPanels.GOLD);_status.visible=false;add_child(_status)
	func report(result: TDOutcome) -> void:
		var message: String=result.message if not result.message.is_empty() else str({"INSUFFICIENT_FUNDS":"金币不足。","SHOP_OPEN":"请在营业结束后调整人员。","STALE_PROFILE":"这份存档已关闭，请重新打开界面。","POOL_EMPTY":"这个招募池中的员工都已达到三星。","NOT_OWNED":"请先招募这位员工。"}.get(result.code,result.code))
		if _status!=null: _status.text=message;_status.visible=not message.is_empty()
		notice.emit(message)
		if result.ok: changed.emit()
	func store_rows() -> Array[Dictionary]:
		var rows: Array[Dictionary]=[{"id":"","name":"待岗"},{"id":"player_diner","name":"主店 · "+profile.title}]
		for store: Dictionary in profile.branches.state.stores.values():
			if profile.branches.can_support_store(str(store.id)):
				rows.append({"id":str(store.id),"name":str(store.name)})
		return rows

class RelationshipPanel extends BasePanel:
	var visible_ids: Array[String]=[]
	func configure(value: TDGameProfile) -> void:
		super.configure(value);refresh()
	func refresh() -> void:
		clear();visible_ids.clear()
		add_child(TDManagementPanels.text("镇上相识",TDUI.FONT_TITLE,TDManagementPanels.GOLD))
		add_child(TDManagementPanels.text("在剧情中结识的居民会出现在这里。每天完成一次闲聊可提升好感。",TDUI.FONT_BODY,TDManagementPanels.MUTED))
		var grid:=GridContainer.new();grid.columns=2;grid.add_theme_constant_override("h_separation",14);grid.add_theme_constant_override("v_separation",14);add_child(grid)
		for id: String in profile.characters.definitions:
			var relation:=profile.characters.relationship(id)
			if not bool(relation.get("flags",{}).get("met",false)): continue
			visible_ids.append(id)
			var definition:=profile.characters.definition(id)
			var box:=TDManagementPanels.card(grid,Color("c29c99"));box.custom_minimum_size.x=330
			var row:=HBoxContainer.new();row.add_theme_constant_override("separation",14);box.add_child(row)
			var portrait:=TextureRect.new();portrait.texture=TDStoryArt.portrait(str(definition.portrait))
			portrait.custom_minimum_size=Vector2(98,142);portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			portrait.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;row.add_child(portrait)
			var details:=VBoxContainer.new();details.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(details)
			details.add_child(TDManagementPanels.text(str(definition.name),TDUI.FONT_SECTION))
			var affection: int=int(relation.affection)
			var stage: String = {"stranger":"初识","friend":"熟悉","close":"亲近"}[profile.characters.tier(id)]
			details.add_child(TDManagementPanels.text("%s · 好感 %d / 100" % [stage,affection],TDUI.FONT_BODY,Color("764019")))
			var meter:=ProgressBar.new();meter.max_value=100;meter.value=affection;meter.show_percentage=false;meter.custom_minimum_size.y=12;details.add_child(meter)
			details.add_child(TDManagementPanels.text(" · ".join(definition.traits),TDUI.FONT_CAPTION,TDManagementPanels.MUTED))
			box.add_child(TDManagementPanels.text(public_biography(str(definition.biography)),TDUI.FONT_BODY))
		if visible_ids.is_empty():
			add_child(TDManagementPanels.text("跟随主线结识居民后，这里会显示他们的资料。",TDUI.FONT_SECTION,TDManagementPanels.MUTED))
	static func public_biography(value: String) -> String:
		# Current authored biographies append production notes after the first sentence.
		return value.split("。",false)[0]+"。" if value.contains("。") else value

class EmployeePanel extends BasePanel:
	const PAGE_SIZE: int=20
	var role_filter: String="cook"
	var town: String="chengdu"
	var warehouse: bool=false
	var duty_filter: String="all"
	var page: int=0
	var market_candidates: Array=[]
	var _page_label: Label
	var _previous: Button
	var _next: Button
	var _busy: bool=false
	var _sign_buttons: Dictionary={}
	var _tabs: Dictionary={}
	var _employee_grid: GridContainer
	func employees() -> TDEmployeeRoster:
		return profile.employees
	func configure(value: TDGameProfile) -> void:
		super.configure(value);refresh()
	func refresh() -> void:
		clear();_sign_buttons.clear();_tabs.clear()
		var tabs:=HBoxContainer.new();add_child(tabs)
		for mode: String in ["market","warehouse"]:
			var button:=TDUI.button("招聘市场" if mode=="market" else "员工仓库",select_tab.bind(mode));button.toggle_mode=true;button.button_pressed=warehouse==(mode=="warehouse");tabs.add_child(button);_tabs[mode]=button
		add_child(TDManagementPanels.text("签约入库 → 选择店铺上任；仓库待命不计薪。当天已上岗的工资仍需结算。",TDUI.FONT_BODY,TDManagementPanels.MUTED))
		if not profile.at_boundary(): add_child(TDManagementPanels.text("营业中仅查阅，打烊后可签约和调整岗位。",TDUI.FONT_BODY,TDManagementPanels.GOLD))
		var filters:=HBoxContainer.new();filters.add_theme_constant_override("separation",8);add_child(filters)
		if not warehouse:
			var towns:=OptionButton.new();towns.custom_minimum_size=Vector2(150,42);filters.add_child(towns)
			for id: String in employees().config.recruitment.towns:
				towns.add_item(str(TDTravelCatalog.REGIONS[id].name));towns.set_item_metadata(towns.item_count-1,id)
				if id==town: towns.select(towns.item_count-1)
			towns.item_selected.connect(func(index:int)->void:town=str(towns.get_item_metadata(index));refresh())
		for role: String in (["","manager","cook","waiter"] if warehouse else ["manager","cook","waiter"]):
			var button:=TDUI.button(TDManagementPanels.role_name(role),select_role.bind(role));button.toggle_mode=true;button.button_pressed=role_filter==role;filters.add_child(button)
		status_line()
		if warehouse:
			var heading:=HBoxContainer.new();add_child(heading)
			var duty:=OptionButton.new();heading.add_child(duty)
			for item: Array in [["all","全部任职"],["idle","仓库待命"],["assigned","已派驻"]]:
				duty.add_item(item[1]);duty.set_item_metadata(duty.item_count-1,item[0])
				if item[0]==duty_filter: duty.select(duty.item_count-1)
			duty.item_selected.connect(func(index:int)->void:duty_filter=str(duty.get_item_metadata(index));page=0;refresh_roster())
			_previous=TDUI.button("上一页",change_page.bind(-1));heading.add_child(_previous)
			_page_label=TDManagementPanels.text("",TDUI.FONT_CAPTION,TDManagementPanels.MUTED);heading.add_child(_page_label)
			_next=TDUI.button("下一页",change_page.bind(1));heading.add_child(_next)
		else:
			add_child(TDManagementPanels.text("候选名额：★ 5 人 · ★★ 2 人 · ★★★ 1 人。每 3 天分批轮换，签约后不再出现。",TDUI.FONT_CAPTION,TDManagementPanels.MUTED))
		_employee_grid=GridContainer.new();_employee_grid.columns=2;_employee_grid.add_theme_constant_override("h_separation",12);_employee_grid.add_theme_constant_override("v_separation",12);add_child(_employee_grid)
		if warehouse: refresh_roster()
		else: refresh_market()
	func select_tab(mode: String) -> void:
		warehouse=mode=="warehouse";page=0
		if not warehouse and role_filter.is_empty(): role_filter="cook"
		refresh()
	func select_role(value: String) -> void:
		role_filter=value;page=0;refresh()
	func person_card(row: Dictionary) -> VBoxContainer:
		var box:=TDManagementPanels.card(_employee_grid,Color("a7bd9c") if warehouse else TDManagementPanels.GOLD);box.custom_minimum_size.x=330
		var heading:=HBoxContainer.new();box.add_child(heading)
		heading.add_child(TDManagementPanels.employee_portrait(row,Vector2(64,72)))
		var name_box:=VBoxContainer.new();name_box.size_flags_horizontal=Control.SIZE_EXPAND_FILL;heading.add_child(name_box)
		name_box.add_child(TDManagementPanels.text(str(row.name),TDUI.FONT_SECTION))
		name_box.add_child(TDManagementPanels.text("★".repeat(int(row.stars))+" · "+TDManagementPanels.role_name(str(row.role)),TDUI.FONT_BODY,TDManagementPanels.GOLD))
		var hometown:=str(TDTravelCatalog.REGIONS[row.town].name).get_slice(" · ",0)
		var eligibility: String="各菜系均可任职" if row.role=="manager" else TDPlayerBranches.TITLES[row.cuisine_id]
		name_box.add_child(TDManagementPanels.text("%s · %s"%[hometown,eligibility],TDUI.FONT_CAPTION))
		box.add_child(TDManagementPanels.text(str(row.description),TDUI.FONT_CAPTION,TDManagementPanels.MUTED))
		box.add_child(TDManagementPanels.text("招徕 %d   运营 %d   品质 %d   节用 %d"%[int(row.attraction),int(row.operations),int(row.quality),int(row.economy)],TDUI.FONT_CAPTION,TDManagementPanels.GOLD))
		if row.role=="manager" and int(row.stars)>=2:
			box.add_child(TDManagementPanels.text("服务 +%.0f%% · 品质 +%.0f%% · 水电减免 %.0f%%"%[100*float(row.service_bonus),100*float(row.quality_bonus),100*float(row.utility_discount)],TDUI.FONT_CAPTION,TDManagementPanels.MUTED))
		box.add_child(TDManagementPanels.text("任职日薪 %.2f 金币 · 待命免费"%(float(row.wage_cents)/100),TDUI.FONT_CAPTION))
		return box
	func refresh_market() -> void:
		market_candidates=employees().market_rows(town,role_filter)
		for row: Dictionary in market_candidates:
			var box:=person_card(row)
			box.add_child(TDManagementPanels.text("本批有效至第 %d 天结束"%int(row.last_day),TDUI.FONT_CAPTION,TDManagementPanels.MUTED))
			var button:=TDUI.button("签约入库 · %.2f 金币"%(float(row.sign_fee_cents)/100),sign_candidate.bind(str(row.id),str(row.offer_key)))
			button.disabled=_busy or not profile.at_boundary() or int(profile.shop.snapshot().money_cents)<int(row.sign_fee_cents);box.add_child(button);_sign_buttons[row.id]=button
		if market_candidates.is_empty(): _employee_grid.add_child(TDManagementPanels.text("这个岗位暂无未签约的候选人，可查看其他小镇或岗位。",TDUI.FONT_BODY,TDManagementPanels.MUTED))
	func sign_candidate(id: String, offer_key: String) -> void:
		if _busy: return
		_busy=true
		var result:=employees().sign_employee(id,"recruit-ui:%s:%d"%[profile.slot_id,Time.get_ticks_usec()],offer_key)
		refresh();report(result);call_deferred("_release_sign")
	func _release_sign() -> void:
		await get_tree().create_timer(0.4,true,false,true).timeout
		if not is_inside_tree(): return
		_busy=false
		for id: String in _sign_buttons:
			_sign_buttons[id].disabled=not profile.at_boundary() or int(profile.shop.snapshot().money_cents)<int(employees().employee_info(id).sign_fee_cents)
	func refresh_roster() -> void:
		for child: Node in _employee_grid.get_children(): _employee_grid.remove_child(child);child.queue_free()
		var all: Array=employees().roster_rows(role_filter)
		if duty_filter!="all": all=all.filter(func(row:Dictionary)->bool:return str(row.assigned).is_empty()==(duty_filter=="idle"))
		var total: int=all.size();var pages: int=maxi(1,ceili(float(total)/PAGE_SIZE));page=clampi(page,0,pages-1)
		_page_label.text="%d 人 · %d / %d 页"%[total,page+1,pages];_previous.disabled=page==0;_next.disabled=page>=pages-1
		var stores:=store_rows()
		for row: Dictionary in all.slice(page*PAGE_SIZE,(page+1)*PAGE_SIZE):
			var box:=person_card(row)
			box.add_child(TDManagementPanels.text("任职："+str(row.store_name),TDUI.FONT_CAPTION))
			var choice:=OptionButton.new();choice.custom_minimum_size.y=40;choice.disabled=not profile.at_boundary();choice.size_flags_horizontal=Control.SIZE_EXPAND_FILL;box.add_child(choice)
			for index: int in stores.size():
				if not employees().fits_store(row,str(stores[index].id)): continue
				choice.add_item("仓库待命" if str(stores[index].id).is_empty() else str(stores[index].name));choice.set_item_metadata(choice.item_count-1,str(stores[index].id))
				if str(stores[index].id)==str(row.assigned): choice.select(choice.item_count-1)
			choice.item_selected.connect(func(index:int)->void:assign_employee(str(row.id),str(choice.get_item_metadata(index))))
		if total==0: _employee_grid.add_child(TDManagementPanels.text("这个分类下还没有员工，先到招聘市场签约吧。",TDUI.FONT_BODY,TDManagementPanels.MUTED))
	func assign_employee(id: String, store: String) -> void:
		var result:=employees().assign(id,store)
		if warehouse: refresh_roster()
		report(result)
	func change_page(delta: int) -> void:
		page+=delta;refresh_roster()

class SupplierPanel extends BasePanel:
	var selected_store := "player_diner"
	var inputs := {}
	var toggle: CheckBox
	var pay: Button
	var confirm: Button

	func configure(value: TDGameProfile) -> void:
		super.configure(value)
		refresh()

	func refresh() -> void:
		clear()
		inputs.clear()
		var contract := profile.menu_supply
		var account := contract.state
		var unlocked := profile.story_feature_available("suppliers")
		var header := TDManagementPanels.card(self)
		toggle=CheckBox.new()
		toggle.text="启用菜单供货" if unlocked else "供货随主线开放"
		toggle.disabled=not unlocked
		toggle.button_pressed=account.enabled
		header.add_child(toggle)
		toggle.toggled.connect(func(value:bool)->void: finish(contract.set_enabled(value)))
		var last := "暂无" if int(account.invoice_day)==0 else "第 %d 天 · %.2f 金币"%[account.invoice_day,float(account.last_invoice)/100]
		header.add_child(TDManagementPanels.text("上一笔货款　"+last))
		header.add_child(TDManagementPanels.text("信用额度　%.2f 金币　　　当前欠款　%.2f 金币"%[contract.credit()/100.0,float(account.debt)/100]))
		if account.suspended: header.add_child(TDManagementPanels.text("已停供 · 还清全部欠款后恢复次晨配送",TDUI.FONT_BODY,TDUI.ORANGE))
		pay=TDUI.button("用现有金币偿还货款",func()->void: finish(contract.repay()))
		pay.disabled=int(account.debt)==0 or int(profile.shop.snapshot().money_cents)<=0
		header.add_child(pay)
		if not unlocked or not account.enabled:
			status_line()
			return
		var body:=TDManagementPanels.card(self)
		var picker:=OptionButton.new()
		var eligible := contract.store_ids()
		for row: Dictionary in store_rows():
			if row.id not in eligible: continue
			picker.add_item(row.name)
			picker.set_item_metadata(picker.item_count-1,row.id)
			if row.id==selected_store: picker.select(picker.item_count-1)
		picker.item_selected.connect(func(index:int)->void: selected_store=str(picker.get_item_metadata(index));refresh())
		body.add_child(picker)
		var rows:=contract.dishes(selected_store)
		var counts:=contract.quantities(selected_store,rows)
		var editable:=contract.evening()
		var day:=int(profile.shop.snapshot().day)+1
		body.add_child(TDManagementPanels.text("第 %d 天 · %s"%[day,"已预订菜单" if account.plans.has(selected_store) else "沿用当前菜单"],TDUI.FONT_SECTION))
		body.add_child(TDManagementPanels.text("18:00 或打烊后可改。沿用上次份数，新菜默认 %d 份。填 0 可撤下该菜。"%contract.DEFAULT_PORTIONS,TDUI.FONT_CAPTION))
		for dish: Dictionary in rows:
			var line:=HBoxContainer.new()
			body.add_child(line)
			var name_label:=TDManagementPanels.text(str(dish.name))
			name_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			line.add_child(name_label)
			var amount:=SpinBox.new()
			amount.min_value=0
			amount.max_value=contract.MAX_PORTIONS
			amount.step=1
			amount.suffix="份"
			amount.value=int(counts.get(dish.id,0))
			amount.editable=editable
			line.add_child(amount)
			inputs[dish.id]=amount
		confirm=TDUI.button("确认明日菜单",save_plan)
		confirm.disabled=not editable
		body.add_child(confirm)
		status_line()

	func save_plan() -> void:
		var counts: Dictionary={}
		for id: String in inputs:
			var amount: SpinBox=inputs[id]
			if amount.get_line_edit().has_focus(): amount.apply()
			if amount.value>0: counts[id]=int(amount.value)
		finish(profile.menu_supply.book(selected_store,counts))

	func finish(result: TDOutcome) -> void:
		if result.ok: refresh()
		report(result)
