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

static func role_name(role: String) -> String:
	return {"manager":"店长","cook":"厨师","waiter":"服务员"}.get(role,"全部岗位")

class ProductButton extends Button:
	var product_id: String=""
	var caption: String=""
	var detail: String=""
	func _draw() -> void:
		TDIngredientIcon.draw_on(self,product_id,Rect2(10,15,40,40),disabled)
		var font:=get_theme_font("font")
		draw_string(font,Vector2(60,30),caption,HORIZONTAL_ALIGNMENT_LEFT,size.x-68,TDUI.FONT_BODY,TDManagementPanels.PAPER if not disabled else TDManagementPanels.MUTED)
		draw_string(font,Vector2(60,54),detail,HORIZONTAL_ALIGNMENT_LEFT,size.x-68,TDUI.FONT_CAPTION,TDManagementPanels.MUTED)

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
		for store: Dictionary in profile.branches.state.stores.values(): rows.append({"id":str(store.id),"name":str(store.name)})
		return rows

class RelationshipPanel extends BasePanel:
	var visible_ids: Array[String]=[]
	func configure(value: TDGameProfile) -> void:
		super.configure(value);refresh()
	func refresh() -> void:
		clear();visible_ids.clear()
		add_child(TDManagementPanels.text("镇上相识",TDUI.FONT_TITLE,TDManagementPanels.GOLD))
		add_child(TDManagementPanels.text("记住每一位相识的街坊。聊天和一餐好饭，都能让彼此更亲近。",TDUI.FONT_BODY,TDManagementPanels.MUTED))
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
			details.add_child(TDManagementPanels.text("好感 %d / 100"%affection,TDUI.FONT_BODY,Color("764019")))
			var meter:=ProgressBar.new();meter.max_value=100;meter.value=affection;meter.show_percentage=false;meter.custom_minimum_size.y=12;details.add_child(meter)
			details.add_child(TDManagementPanels.text(" · ".join(definition.traits),TDUI.FONT_CAPTION,TDManagementPanels.MUTED))
			box.add_child(TDManagementPanels.text(public_biography(str(definition.biography)),TDUI.FONT_BODY))
		if visible_ids.is_empty():
			add_child(TDManagementPanels.text("这里还没有记录。到小镇走走，向遇见的人打声招呼吧。",TDUI.FONT_SECTION,TDManagementPanels.MUTED))
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
				towns.add_item(str(profile.commerce.config.towns.get(id,{}).get("name",id)));towns.set_item_metadata(towns.item_count-1,id)
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
		var portrait:=TextureRect.new();portrait.texture=TDDinerArt.portrait(TDDinerArt.appearance(str(row.id)));portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;portrait.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;portrait.custom_minimum_size=Vector2(64,72);heading.add_child(portrait)
		var name_box:=VBoxContainer.new();name_box.size_flags_horizontal=Control.SIZE_EXPAND_FILL;heading.add_child(name_box)
		name_box.add_child(TDManagementPanels.text(str(row.name),TDUI.FONT_SECTION))
		name_box.add_child(TDManagementPanels.text("★".repeat(int(row.stars))+" · "+TDManagementPanels.role_name(str(row.role)),TDUI.FONT_BODY,TDManagementPanels.GOLD))
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
				choice.add_item("仓库待命" if str(stores[index].id).is_empty() else str(stores[index].name));choice.set_item_metadata(index,str(stores[index].id))
				if str(stores[index].id)==str(row.assigned): choice.select(index)
			choice.item_selected.connect(func(index:int)->void:assign_employee(str(row.id),str(choice.get_item_metadata(index))))
		if total==0: _employee_grid.add_child(TDManagementPanels.text("这个分类下还没有员工，先到招聘市场签约吧。",TDUI.FONT_BODY,TDManagementPanels.MUTED))
	func assign_employee(id: String, store: String) -> void:
		var result:=employees().assign(id,store)
		if warehouse: refresh_roster()
		report(result)
	func change_page(delta: int) -> void:
		page+=delta;refresh_roster()

class SupplyLineCard extends VBoxContainer:
	var line_id: String
	var reordered: Callable
	func _get_drag_data(_position: Vector2) -> Variant:
		var preview:=TDManagementPanels.text("调整产线优先级",TDUI.FONT_BODY);set_drag_preview(preview)
		return {"supplier_line":line_id}
	func _can_drop_data(_position: Vector2, data: Variant) -> bool:
		return data is Dictionary and data.has("supplier_line") and data.supplier_line!=line_id
	func _drop_data(_position: Vector2, data: Variant) -> void:
		if reordered.is_valid(): reordered.call(str(data.supplier_line),line_id)

class SupplierPanel extends BasePanel:
	const TOWNS: Array[String]=["chengdu","tokyo","paris","bangkok","mexico_city"]
	const GROUPS: Dictionary={"seasoning":"调料","vegetable":"蔬菜","meat":"肉类","fruit":"水果"}
	var selected_town: String="chengdu"
	var selected_store: String="player_diner"
	var selected_group: String=""
	var selected_item: String=""
	var quantity: int=4
	var _products: Array=[]
	var _goods: GridContainer
	var _order_info: Label
	var _queue: VBoxContainer
	var _quantity: SpinBox
	var _order_button: Button
	var _refresh_elapsed: float=0.0
	var _order_busy: bool=false
	var _line_labels: Dictionary={}
	var _budget_label: Label
	var _capacity_label: Label
	var _picker_open: bool=false
	func suppliers() -> TDSupplierNetwork:
		return profile.suppliers
	func configure(value: TDGameProfile) -> void:
		if profile!=null and profile.research.changed.is_connected(_research_changed): profile.research.changed.disconnect(_research_changed)
		super.configure(value);add_theme_constant_override("separation",8);refresh()
		profile.research.changed.connect(_research_changed)
	func _exit_tree() -> void:
		if profile!=null and profile.research.changed.is_connected(_research_changed): profile.research.changed.disconnect(_research_changed)
	func _research_changed() -> void:
		if is_inside_tree(): refresh()
	func _process(delta: float) -> void:
		_refresh_elapsed+=delta
		if _refresh_elapsed>=.5 and _queue!=null:
			_refresh_elapsed=0;refresh_queue()
	func town_name(id: String) -> String:
		return str(profile.commerce.config.towns.get(id,{}).get("name",id))
	func refresh() -> void:
		clear();_queue=null;_line_labels.clear()
		add_child(TDManagementPanels.text("仅展示本地产原料 · 调料随菜系开放 · 共享调料开放任一对应菜系即可",TDUI.FONT_CAPTION,TDManagementPanels.MUTED))
		var towns:=HBoxContainer.new();add_child(towns)
		for id: String in TOWNS:
			var tab:=TDUI.button(town_name(id),select_town.bind(id));tab.toggle_mode=true;tab.button_pressed=id==selected_town;tab.size_flags_horizontal=Control.SIZE_EXPAND_FILL;towns.add_child(tab)
		var header:=HBoxContainer.new();add_child(header)
		_capacity_label=TDManagementPanels.text("",TDUI.FONT_BODY,TDManagementPanels.GOLD);header.add_child(_capacity_label)
		var level: int=int(suppliers().state.levels[selected_town])
		var expand:=TDUI.button("扩充产能 · %.2f金币"%(float(suppliers().config.upgrade_base_cents)*level/100),upgrade);expand.disabled=level>=3 or not profile.at_boundary();header.add_child(expand)
		status_line()
		var destination:=HBoxContainer.new();destination.add_child(TDManagementPanels.text("收货店铺 / 预算",TDUI.FONT_BODY));add_child(destination)
		var choose:=OptionButton.new();choose.custom_minimum_size=Vector2(300,40);destination.add_child(choose)
		for store: Dictionary in store_rows():
			if str(store.id).is_empty(): continue
			choose.add_item(str(store.name));choose.set_item_metadata(choose.item_count-1,str(store.id))
			if str(store.id)==selected_store: choose.select(choose.item_count-1)
		choose.item_selected.connect(func(index:int)->void:selected_store=str(choose.get_item_metadata(index));selected_item="";refresh())
		build_automation(suppliers().state)
		add_child(TDManagementPanels.text("产线优先级（拖动卡片空白处，或点 ↑ ↓；上方优先）",TDUI.FONT_BODY,TDManagementPanels.GOLD))
		var rows:=suppliers().line_rows(selected_town)
		for row: Dictionary in rows: build_line(row)
		if rows.is_empty(): add_child(TDManagementPanels.text("还没有持续产线。添加原料、目标库存和收货店即可开始。",TDUI.FONT_BODY,TDManagementPanels.MUTED))
		add_child(TDUI.button("收起新增产线" if _picker_open else "＋ 新增产线",func()->void:_picker_open=not _picker_open;refresh()))
		_products=suppliers().catalogue(selected_town,selected_store)
		var picker:=VBoxContainer.new();picker.visible=_picker_open;add_child(picker)
		var filters:=HBoxContainer.new();picker.add_child(filters)
		for group: String in ["","vegetable","meat","fruit","seasoning"]:
			filters.add_child(TDUI.button("全部" if group.is_empty() else GROUPS[group],select_group.bind(group)))
		_goods=GridContainer.new();_goods.columns=3;picker.add_child(_goods)
		_order_info=TDManagementPanels.text("",TDUI.FONT_BODY);picker.add_child(_order_info)
		var controls:=HBoxContainer.new();picker.add_child(controls)
		controls.add_child(TDManagementPanels.text("目标库存（包）",TDUI.FONT_BODY));_quantity=SpinBox.new();_quantity.min_value=1;_quantity.max_value=100;_quantity.step=1;_quantity.value=quantity;controls.add_child(_quantity)
		_quantity.value_changed.connect(func(value:float)->void:quantity=int(value);refresh_quote())
		_order_button=TDUI.button("启用产线",place_order);controls.add_child(_order_button)
		refresh_goods();refresh_quote()
		add_child(TDManagementPanels.text("在制 / 在途",TDUI.FONT_SECTION,TDManagementPanels.GOLD))
		_queue=VBoxContainer.new();add_child(_queue);refresh_queue()
	func build_line(row: Dictionary) -> void:
		var box:=TDManagementPanels.card(self)
		var card:=SupplyLineCard.new();card.line_id=row.id;card.reordered=reorder;card.mouse_filter=Control.MOUSE_FILTER_STOP;box.add_child(card)
		var head:=HBoxContainer.new();card.add_child(head)
		var icon:=ProductButton.new();icon.product_id=row.item_id;icon.caption=suppliers().item_name(row.item_id);icon.detail="→ "+_store_name(row.store_id);icon.custom_minimum_size=Vector2(270,68);icon.mouse_filter=Control.MOUSE_FILTER_IGNORE;head.add_child(icon)
		var status:=TDManagementPanels.text("",TDUI.FONT_CAPTION,TDManagementPanels.GOLD);head.add_child(status);_line_labels[row.id]=status
		head.add_child(TDUI.button("↑",shift.bind(row.id,-1)));head.add_child(TDUI.button("↓",shift.bind(row.id,1)))
		head.add_child(TDUI.button("删除",func()->void:var result:=suppliers().remove_line(row.id);refresh();report(result)))
		var actions:=HBoxContainer.new();card.add_child(actions)
		actions.add_child(TDManagementPanels.text("产能",TDUI.FONT_CAPTION))
		actions.add_child(TDUI.button("−",edit_line.bind(row.id,int(row.target_units),maxi(1,int(row.slots)-1),bool(row.enabled))))
		actions.add_child(TDManagementPanels.text("▣ ".repeat(int(row.slots)),TDUI.FONT_BODY,TDManagementPanels.GOLD))
		actions.add_child(TDUI.button("＋",edit_line.bind(row.id,int(row.target_units),mini(suppliers().capacity(row.town_id),int(row.slots)+1),bool(row.enabled))))
		actions.add_child(TDManagementPanels.text("目标（包）",TDUI.FONT_CAPTION))
		var pack: int=int(profile.shop.stock_info(row.item_id).pack_units)
		var target:=SpinBox.new();target.min_value=.01;target.max_value=100000.0/pack;target.step=.1;target.value=float(row.target_units)/pack;target.custom_minimum_size.x=120;actions.add_child(target)
		actions.add_child(TDUI.button("应用",func()->void:edit_line(row.id,roundi(target.value*pack),int(row.slots),bool(row.enabled))))
		actions.add_child(TDUI.button("停用" if row.enabled else "启用",edit_line.bind(row.id,int(row.target_units),int(row.slots),not row.enabled)))
	func edit_line(id: String,target: int,slots: int,enabled: bool) -> void:
		var result:=suppliers().configure_line(id,target,slots,enabled);refresh();report(result)
	func shift(id: String,offset: int) -> void:
		# Visible priorities belong to this supplier; cross-town rows do not matter.
		var rows:=suppliers().line_rows(selected_town);var index: int=-1
		for i: int in rows.size():
			if rows[i].id==id: index=i
		if index<0 or index+offset<0 or index+offset>=rows.size(): return
		reorder(id,rows[index+offset].id)
	func reorder(id: String,target_id: String) -> void:
		var rows: Array=suppliers().state.lines;var from_index: int=-1;var to_index: int=-1
		for i: int in rows.size():
			if rows[i].id==id: from_index=i
			if rows[i].id==target_id: to_index=i
		if from_index>=0 and to_index>=0: suppliers().move_line(id,to_index-from_index);refresh()
	func select_town(id: String) -> void:
		selected_town=id;selected_item="";refresh()
	func select_group(group: String) -> void:
		selected_group=group;refresh()
	func refresh_goods() -> void:
		for child: Node in _goods.get_children(): _goods.remove_child(child);child.queue_free()
		for item: Dictionary in _products:
			if not selected_group.is_empty() and item.group!=selected_group: continue
			var button:=ProductButton.new();button.product_id=item.id;button.caption=item.name;button.detail="%.2f金币/%s · 源镇%.1f包"%[float(item.price_cents)/100,item.unit,float(item.stock)/int(item.pack_units)]
			button.tooltip_text="供货地区："+str(item.region_label)
			if profile.shop.stock_info(item.id).condiment: button.tooltip_text+="\n开放任一菜系可购："+TDMaterialCatalog.cuisine_text(item.id)
			button.custom_minimum_size=Vector2(245,68);button.pressed.connect(select_item.bind(str(item.id)));button.toggle_mode=true;button.button_pressed=item.id==selected_item;_goods.add_child(button)
	func select_item(id: String) -> void:
		selected_item=id;refresh_goods();refresh_quote()
	func cart() -> Dictionary:
		for item: Dictionary in _products:
			if item.id==selected_item: return {selected_item:quantity*int(item.pack_units)}
		return {}
	func refresh_quote() -> void:
		if _order_button==null: return
		_order_button.disabled=_order_busy or cart().is_empty()
		_order_info.text="选择原料；目标计入现货、在制和在途，不会一次扣完目标货款。"
		for item: Dictionary in _products:
			if item.id!=selected_item: continue
			var rate: float=3600.0/float(suppliers().config.base_seconds[item.group])/pow(float(suppliers().config.level_time_factor),int(suppliers().state.levels[selected_town])-1)
			_order_info.text="%s → %s · 单产能 %.1f%s/游戏小时 · 运输 %.0f 游戏分钟\n按每批实际市价扣款；目标足够、缺钱或缺货会等待。"%[item.name,_store_name(selected_store),rate,item.unit,suppliers().distance(selected_town,suppliers()._store_town(selected_store))*float(suppliers().config.continuous.transport_minutes_per_distance)]
	func _store_name(id: String) -> String:
		for store: Dictionary in store_rows():
			if store.id==id: return str(store.name)
		return id
	func place_order() -> void:
		if _order_busy or cart().is_empty(): return
		_order_busy=true
		var result:=suppliers().create_line(selected_town,selected_store,selected_item,int(cart()[selected_item]))
		if result.ok: _picker_open=false
		refresh();report(result);call_deferred("_release_order")
	func _release_order() -> void:
		_order_busy=false;refresh_quote()
	func upgrade() -> void:
		if _order_busy: return
		_order_busy=true
		var result:=suppliers().upgrade(selected_town,"supplier-upgrade:%s:%d"%[profile.slot_id,Time.get_ticks_usec()]);refresh();report(result);call_deferred("_release_order")
	func build_automation(state: Dictionary) -> void:
		var setting: Dictionary=state.automation.get(selected_store,{"budget_cents":int(suppliers().config.continuous.default_budget_cents)})
		var box:=TDManagementPanels.card(self);var controls:=HBoxContainer.new();box.add_child(controls)
		var toggle:=CheckButton.new();toggle.text="按菜单托管产线";toggle.button_pressed=bool(setting.get("enabled",false));controls.add_child(toggle)
		controls.add_child(TDManagementPanels.text("每日上限",TDUI.FONT_CAPTION));var budget:=SpinBox.new();budget.min_value=0;budget.max_value=100000;budget.value=float(setting.budget_cents)/100;budget.suffix="金币";budget.custom_minimum_size.x=160;controls.add_child(budget)
		controls.add_child(TDUI.button("应用预算",func()->void:
			var result:=suppliers().set_automation(selected_store,toggle.button_pressed,roundi(budget.value*100))
			if result.ok: suppliers().automate()
			refresh();report(result)))
		_budget_label=TDManagementPanels.text("",TDUI.FONT_CAPTION,TDManagementPanels.MUTED);box.add_child(_budget_label)
		var hint:=TDManagementPanels.text("手动行也受预算限制 · 睡眠计入次日预算 · 已付货继续送达",TDUI.FONT_CAPTION,TDManagementPanels.MUTED)
		hint.tooltip_text="托管不修改手动行。分店还受店铺采购预算限制。停用或删除不会取消已付款批次。修改后请主动保存。";box.add_child(hint)
	func refresh_queue() -> void:
		var state:=suppliers().state
		_capacity_label.text="%s · %d级 · %d共享产能"%[town_name(selected_town),int(state.levels[selected_town]),suppliers().capacity(selected_town)]
		var setting: Dictionary=state.automation.get(selected_store,{})
		var spent: int=int(setting.get("spent_cents",0)) if int(setting.get("spent_day",0))==int(profile.shop.snapshot().day) else 0
		_budget_label.text="今日已用 %.2f / %.2f 金币 · 关闭托管后，手动产线仍按设置运行"%[float(spent)/100,float(setting.get("budget_cents",suppliers().config.continuous.default_budget_cents))/100]
		for row: Dictionary in suppliers().line_rows(selected_town):
			if _line_labels.has(row.id):
				var pack: float=float(profile.shop.stock_info(row.item_id).pack_units)
				_line_labels[row.id].text="%s · %d%%\n现货 %.1f + 待收 %.1f / 目标 %.1f包\n满配 %.1f%s/游戏小时"%[row.status,roundi(float(row.progress)*100),float(row.have)/pack,float(row.pending)/pack,float(row.target_units)/pack,float(row.per_hour),profile.shop.stock_info(row.item_id).unit]
		for child: Node in _queue.get_children(): _queue.remove_child(child);child.queue_free()
		var shown: int=0
		for order: Dictionary in state.orders:
			if order.store_id!=selected_store: continue
			for job: Dictionary in order.jobs:
				if job.delivered: continue
				shown+=1
				var status: String
				if not order.has("line_id"): status="旧单 · 剩余 "+time_text(float(job.seconds)-float(job.elapsed))+"（活动时间）"
				elif float(job.elapsed)<float(job.seconds): status="生产 %d%%"%roundi(float(job.elapsed)/float(job.seconds)*100)
				else: status="运输剩余 %.1f 游戏分钟"%(float(job.transit_minutes)-float(job.transit_elapsed))
				_queue.add_child(TDManagementPanels.text("%s %.2f%s · %s → %s · %s"%[suppliers().item_name(job.item_id),float(job.units)/1000,profile.shop.stock_info(job.item_id).unit,town_name(order.town_id),_store_name(order.store_id),status],TDUI.FONT_CAPTION))
		if shown==0: _queue.add_child(TDManagementPanels.text("暂无待收货批次。",TDUI.FONT_CAPTION,TDManagementPanels.MUTED))
	static func time_text(seconds: float) -> String:
		if seconds>=3600: return "%.1f 小时"%(seconds/3600)
		if seconds>=60: return "%.1f 分钟"%(seconds/60)
		return "%d 秒"%ceili(seconds)
