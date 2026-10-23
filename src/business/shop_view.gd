class_name TDShopView
extends Control
signal back_requested
signal pause_requested
var embedded: bool = false
var boundary_save: Callable
const KITCHEN := preload("res://src/kitchen/full_kitchen.tscn")
var save_path: String = "user://shop-v1.json"
var resume_saved: bool = false
var service := TDServiceCatalog.new()
var shop: TDShopSession
var store: TDShopStore
var kitchen: TDFullKitchen
var day_san: float = -1.0
var last_result := TDOutcome.new(true)
var _title: Label
var _message: Label
var _holder: Control
var _sidebar: VBoxContainer
var _page: PanelContainer
var _popup: PanelContainer
var _scrim: ColorRect
var _open_button: Button
var _next_button: Button
var _save_button: Button
var _last_phase: String = ""
var _side_key: String = ""
var _closed: bool = false
var _load_blocked: bool = false
var _new_needs_confirmation: bool = false
var _serial: int = 0
var learned_dishes: Array = []
var recipe_unlocks: Array = []
var cooking_reward: Callable
var legacy_loaded: Callable

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS; theme=TDUI.theme(); set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for state: String in ["normal","hover","pressed","focus"]:
		var style:=theme.get_stylebox(state,"Button") as StyleBoxFlat
		style.content_margin_left=10; style.content_margin_right=10; style.content_margin_top=8; style.content_margin_bottom=8
	var background:=ColorRect.new(); background.color=Color("17251f"); background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); background.mouse_filter=Control.MOUSE_FILTER_IGNORE; add_child(background)
	var linked: Array=[]
	if embedded and shop!=null:
		service=shop.catalog
	else:
		var loaded:=service.load_file()
		if not loaded.ok: add_child(TDUI.label("营业配置错误："+loaded.message)); return
		linked=TDKitchenLink.install(service, learned_dishes)
		shop=TDShopSession.new(service,"",101,recipe_unlocks); shop.cooking_reward=cooking_reward; store=TDShopStore.new(save_path,shop)
	if resume_saved and not embedded:
		var saved:=store.load_game()
		if saved.ok:
			last_result=shop.restore(saved.data)
			if last_result.ok and legacy_loaded.is_valid(): legacy_loaded.call(shop.snapshot().unlocked)
		else: last_result=saved; _load_blocked=true
	elif not embedded: _new_needs_confirmation=store.load_game().code!="NOT_FOUND"
	for recipe_id: String in linked:
		if resume_saved and shop.is_unlocked(recipe_id): continue # Keep saved menu enabled/price choices.
		var granted:=shop.grant_recipe(recipe_id)
		if not granted.ok: last_result=granted
	_build_shell(); _make_kitchen(); refresh(true)
	if _load_blocked: _show_recovery()

func _build_shell() -> void:
	_title=TDUI.label("",28,TDUI.ORANGE); _title.position=Vector2(24,17); _title.size=Vector2(1190,42); add_child(_title)
	_message=TDUI.label("筹备：补货、定价，然后开门迎客。",17,TDUI.MUTED); _message.position=Vector2(24,59); _message.size=Vector2(1210,44); add_child(_message)
	var actions:=HBoxContainer.new(); actions.position=Vector2(24,104); actions.add_theme_constant_override("separation",12); add_child(actions)
	_open_button=TDUI.button("开门营业",open_day); actions.add_child(_open_button)
	_save_button=TDUI.button("保存进度",save_boundary); actions.add_child(_save_button)
	actions.add_child(TDUI.button("提前打烊",func()->void:_show(shop.close_early());refresh(true)))
	_next_button=TDUI.button("准备下一天",next_day); actions.add_child(_next_button)
	actions.add_child(TDUI.button("经营账本",_show_ledger))
	actions.add_child(TDUI.button("暂停 / 恢复",func()->void:pause_requested.emit()))
	actions.add_child(TDUI.button("返回主界面",request_back))
	if embedded: actions.hide()
	_holder=Control.new(); _holder.position=Vector2(12,174); _holder.size=Vector2(920,575); add_child(_holder)
	var scroll:=ScrollContainer.new(); scroll.position=Vector2(953,166); scroll.size=Vector2(303,610); scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; add_child(scroll)
	_sidebar=VBoxContainer.new(); _sidebar.size_flags_horizontal=Control.SIZE_EXPAND_FILL; _sidebar.add_theme_constant_override("separation",10); scroll.add_child(_sidebar)
	_page=PanelContainer.new(); _page.position=Vector2(18,166); _page.size=Vector2(913,610); add_child(_page)

func _make_kitchen() -> void:
	if kitchen!=null:
		kitchen.close(); _holder.remove_child(kitchen); kitchen.queue_free()
	var config:=service.with_plans(shop.snapshot().custom)
	var catalog:=TDCookingCatalog.new()
	if not config.ok or not catalog.load_data(config.data,"shop composition").ok:
		_load_blocked=true; _message.text="自建方案无法装配，请保留存档并检查配方。"; return
	kitchen=KITCHEN.instantiate() as TDFullKitchen; kitchen.catalog=catalog; kitchen.scorer=shop.scorer; kitchen.day_san=day_san
	kitchen.library_path=save_path+".unused-library" # No player recipe write bypasses the business save.
	kitchen.station_handler=_station
	kitchen.action_handler=_station_action
	kitchen.time_boundary=shop.next_boundary
	kitchen.single_fridge=true
	kitchen.z_index=2
	kitchen.back_requested.connect(request_back); kitchen.pause_requested.connect(func()->void:pause_requested.emit())
	kitchen.time_advanced.connect(_on_time); kitchen.dish_delivered.connect(_on_dish)
	_holder.add_child(kitchen); kitchen.world.scale=Vector2(.71875,.71875)
	kitchen.world.get_node("Background").z_index=-1
	kitchen.world.set_return_visible(false)
	if embedded:
		kitchen.world.service_door=true
		kitchen.world.dining_requested.connect(func()->void:back_requested.emit())
	kitchen.handling.session_namespace=shop.day_namespace()
	kitchen.handling.material_sink=shop.consume_materials
	for lane: TDCookingLane in kitchen.lanes:
		lane.session_namespace=shop.day_namespace().trim_suffix(":")
		lane.new_session("service.tomato_egg")
		lane.session.set_material_sink(shop.consume_materials)

func refresh(force: bool = false) -> void:
	if shop==null or _closed: return
	var state: Dictionary=shop.snapshot()
	var fame: int=0
	for id: String in state.menu:
		if state.menu[id].enabled: fame+=int(state.fame.get(id,0))
	_title.text="小镇食堂  ·  第 %d 天     ¥ %.2f     人气 %d   店名气 %d" % [state.day,float(state.money_cents)/100.0,state.popularity,fame]
	var boundary: bool=state.phase in ["PREPARE","SETTLED"]
	if embedded and _last_phase!=state.phase:
		_message.text={"PREPARE":"到集市采购，再回餐厅营业牌确认菜单与价格。","OPEN":"营业中 · 按订单备菜，做好的菜交到出餐台 · B 查看菜谱","DRAINING":"已停止接新客，请处理最后的订单。","SETTLED":"今天打烊了。回餐厅查看账本，休息后迎接新一天。"}.get(state.phase,"")
	_open_button.disabled=state.phase!="PREPARE" or _load_blocked
	_save_button.disabled=not boundary or _load_blocked
	_next_button.disabled=state.phase!="SETTLED" or _load_blocked
	_page.visible=boundary and not embedded; _holder.visible=not boundary or embedded
	if state.phase=="SETTLED" and _last_phase!="SETTLED":
		_close_popup()
		_message.text="今日结束，请看收益总结。"
	if _last_phase!=state.phase or (force and boundary):
		_last_phase=state.phase
		if not embedded: _planning_page(state)
	var side_key: String=JSON.stringify([state.orders.map(func(o:Dictionary)->Array:return [o.id,o.status]),state.phase,int(state.elapsed_sec),state.money_cents])
	if force or side_key!=_side_key: _side_key=side_key; _orders_panel(state)

func _empty(node: Node) -> void:
	for child: Node in node.get_children(): node.remove_child(child); child.queue_free()

func _planning_page(state: Dictionary) -> void:
	_empty(_page)
	var scroll:=ScrollContainer.new(); scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; _page.add_child(scroll)
	var column:=VBoxContainer.new(); column.size_flags_horizontal=Control.SIZE_EXPAND_FILL; column.add_theme_constant_override("separation",12); scroll.add_child(column)
	column.add_child(TDUI.label("菜单与备货" if state.phase=="PREPARE" else "今日收益总结",25,TDUI.ORANGE))
	column.add_child(TDUI.label("顾客自动排队；同菜优先先到的客人。备货包括主料和调料，实际拿取 / 倒入时扣除。",15,TDUI.MUTED))
	if state.phase=="PREPARE":
		var forecast: Dictionary=shop.visitor_forecast()
		column.add_child(TDUI.label("第 %d 天 · 预计到店 %d—%d 位客人" % [forecast.day,forecast.min_visitors,forecast.max_visitors],22,TDUI.ORANGE))
		column.add_child(TDUI.label("按当前人气估算，可据此分配菜单备货；售罄或提前打烊会减少实际接单数。",15,TDUI.MUTED))
		for id: String in state.menu:
			var row:=HBoxContainer.new(); column.add_child(row)
			var check:=CheckBox.new(); check.text=shop.recipe_name(id); check.custom_minimum_size.x=215; check.button_pressed=state.menu[id].enabled; check.disabled=not shop.is_unlocked(shop.family_id(id)); check.text+="（未解锁）" if check.disabled else ""; row.add_child(check)
			var price:=SpinBox.new(); price.min_value=.01; price.max_value=10000; price.step=.5; price.value=float(state.menu[id].price_cents)/100; price.prefix="¥ "; price.custom_minimum_size.x=125; row.add_child(price)
			check.toggled.connect(func(v:bool)->void:_show(shop.set_menu(id,v,roundi(price.value*100))))
			price.value_changed.connect(func(v:float)->void:_show(shop.set_menu(id,check.button_pressed,roundi(v*100))))
			var reference:=TDUI.label("参考 %.2f" % (float(shop.offer(id).reference_cents)/100),15,TDUI.MUTED)
			reference.custom_minimum_size.x=105; reference.autowrap_mode=TextServer.AUTOWRAP_OFF; row.add_child(reference)
			row.add_child(TDUI.button("补齐 ¥%.2f" % (float(shop.kit_cost(id,true))/100),func()->void:buy_kit(id)))
			row.add_child(TDUI.button("再备1份",func()->void:buy_kit(id,false)))
		column.add_child(TDUI.button("资金困难 · 申请应急补助",func()->void:_show(shop.claim_grant());refresh(true)))
	else:
		_summary_page(column, shop.day_summary())
	column.add_child(TDUI.label("库存 · 单位：标准份",20,TDUI.ORANGE))
	var stock_lines: Array[String]=[]
	for id: String in state.inventory:
		var definition: Dictionary=_ingredient(id)
		stock_lines.append("%s %.2f" % [definition.get("name",id),float(state.inventory[id])/1000.0])
	column.add_child(TDUI.label("  ·  ".join(stock_lines),16,TDUI.MUTED))
	for entry: Dictionary in state.custom:
		var row:=HBoxContainer.new(); column.add_child(row)
		var rename:=LineEdit.new(); rename.text=entry.name; rename.custom_minimum_size.x=250; row.add_child(rename)
		row.add_child(TDUI.button("改名 / 保存新版本",func()->void:_show(shop.save_plan(rename.text,entry.plan,entry.id));refresh(true)))
	column.add_child(TDUI.label("声望：本阶段未启用。菜品名气分别累计；店名气只统计当前上架菜。",15,TDUI.MUTED))

func _summary_page(column: VBoxContainer, report: Dictionary) -> void:
	var reason := "今日已结算"
	if str(report.reason) == "early":
		reason = "提前打烊"
	elif str(report.reason) == "time":
		reason = "营业时间结束"
	column.add_child(TDUI.label("第 %d 天 · %s" % [int(report.day), reason], 22, TDUI.ORANGE))
	var net_color := Color("de755d")
	if int(report.net_cents) >= 0:
		net_color = TDUI.ORANGE
	column.add_child(TDUI.label("今日净收支 %+.2f 元" % (float(report.net_cents) / 100.0), 28, net_color))
	var money_line := "备货支出 ¥%.2f    菜款 ¥%.2f    小费 ¥%.2f    退款 ¥%.2f" % [float(report.purchased_cents) / 100.0, float(report.received_cents) / 100.0, float(report.tip_cents) / 100.0, float(report.refunded_cents) / 100.0]
	if int(report.grant_cents) != 0:
		money_line += "    应急补助 ¥%.2f" % (float(report.grant_cents) / 100.0)
	column.add_child(TDUI.label(money_line, 16))
	column.add_child(TDUI.label("开门 ¥%.2f → 打烊 ¥%.2f，营业盈亏 %+.2f 元。备货算在今日净收支里，不算进开门后的营业盈亏。" % [float(report.open_money_cents) / 100.0, float(report.money_cents) / 100.0, float(report.service_cents) / 100.0], 15, TDUI.MUTED))
	var pop_color := TDUI.MUTED
	if int(report.popularity_delta) > 0:
		pop_color = Color("9fc48f")
	elif int(report.popularity_delta) < 0:
		pop_color = Color("de755d")
	column.add_child(TDUI.label("人气 %d → %d（%+d）" % [int(report.open_popularity), int(report.popularity), int(report.popularity_delta)], 22, pop_color))
	column.add_child(TDUI.label("每一单", 20, TDUI.ORANGE))
	var orders: Array = report.orders
	if orders.is_empty():
		column.add_child(TDUI.label("今天没有客人留下订单。", 16, TDUI.MUTED))
	for row: Dictionary in orders:
		var panel := PanelContainer.new()
		column.add_child(panel)
		var body := VBoxContainer.new()
		body.add_theme_constant_override("separation", 4)
		panel.add_child(body)
		body.add_child(TDUI.label("%s · %s · %s" % [str(row.customer), str(row.name), _status_name(str(row.status))], 18, TDUI.ORANGE))
		var effect := "本单 %+.2f 元（小费 ¥%.2f，退款 ¥%.2f）    人气 %+d" % [float(row.money_cents) / 100.0, float(row.tip_cents) / 100.0, float(row.refunded_cents) / 100.0, int(row.popularity_delta)]
		if int(row.fame_delta) != 0:
			effect += "    名气 %+d" % int(row.fame_delta)
		body.add_child(TDUI.label(effect, 16))
		if float(row.satisfaction) >= 0.0:
			body.add_child(TDUI.label("评价 %.1f 分 · %d 星" % [float(row.satisfaction), int(row.stars)], 16))
			var reasons: Array = row.reasons
			for note: Dictionary in reasons.slice(0, 3):
				body.add_child(TDUI.label(_feedback_text(str(note.message)), 14, TDUI.MUTED))
		if str(row.feedback) != "":
			body.add_child(TDUI.label(str(row.feedback), 15, TDUI.MUTED))
		if str(row.status) == "SERVED":
			var order_id := str(row.id)
			body.add_child(TDUI.button("退还此单款项", func() -> void: _show(shop.refund(order_id)); refresh(true)))
			var actions := HBoxContainer.new()
			body.add_child(actions)
			var name_input := LineEdit.new()
			name_input.placeholder_text = "为这份做法命名"
			name_input.custom_minimum_size.x = 250
			actions.add_child(name_input)
			var save_plan_button := TDUI.button("保存食材与工序方案", func() -> void: save_order_plan(order_id, name_input.text))
			save_plan_button.disabled = shop.order(order_id).plan.is_empty()
			actions.add_child(save_plan_button)

func _orders_panel(state: Dictionary) -> void:
	_empty(_sidebar)
	_sidebar.add_child(TDUI.label("等候订单 · %d / %d"%[shop.active_orders().size(),service.config.settings.max_orders],24,TDUI.ORANGE))
	var clock_text: String="筹备不计时" if state.phase=="PREPARE" else ("今日已结算" if state.phase=="SETTLED" else ("停止接客 · 完成剩余订单" if state.phase=="DRAINING" else "营业剩余 %d 秒" % maxi(0,int(service.config.settings.day_sec)-int(state.elapsed_sec))))
	_sidebar.add_child(TDUI.label(clock_text,17))
	_sidebar.add_child(TDUI.label("同菜先到先服务；不同菜可乱序出餐。",14,TDUI.MUTED))
	if _new_needs_confirmation: _sidebar.add_child(TDUI.label("新店尚未覆盖旧档；首次保存前会确认。",15,TDUI.ORANGE))
	for item: Dictionary in state.orders:
		if item.status not in ["WAITING","COOKING"]: continue
		var panel:=PanelContainer.new(); _sidebar.add_child(panel)
		var column:=VBoxContainer.new(); column.add_theme_constant_override("separation",5); panel.add_child(column)
		column.add_child(TDUI.label("%s · ¥%.2f"%[shop.recipe_name(item.recipe_id),float(item.price_cents)/100],19,TDUI.ORANGE))
		var materials: Array[String]=[]
		for ingredient: String in shop.offer(item.recipe_id).primary: materials.append(str(_ingredient(ingredient).name))
		column.add_child(TDUI.label("材料："+" ＋ ".join(materials),16))
		var wishes: Array[String]=[]
		for requirement: Dictionary in item.customer.requirements: wishes.append(str(requirement.label))
		column.add_child(TDUI.label("要求："+" / ".join(wishes),14,TDUI.MUTED))
		var patience:=ProgressBar.new(); patience.max_value=float(service.config.settings.patience_sec); patience.value=maxf(0,float(item.deadline_sec)-float(state.elapsed_sec)); patience.show_percentage=false; patience.custom_minimum_size.y=13; column.add_child(patience)
		column.add_child(TDUI.label("耐心 %d 秒 · %s" % [ceili(patience.value),_status_name(item.status)],15))
	var done: Array=state.orders.filter(func(o:Dictionary)->bool:return o.status not in ["WAITING","COOKING"])
	if not done.is_empty():
		var last: Dictionary=done.back()
		_sidebar.add_child(TDUI.label("最近一单 · "+_status_name(last.status),18,TDUI.ORANGE))
		if last.has("feedback"): _sidebar.add_child(TDUI.label(str(last.feedback)+" 人气小幅下降。",15,TDUI.MUTED))
		if not last.score.is_empty():
			_sidebar.add_child(TDUI.label("%.1f 分  ·  小费 ¥%.2f" % [last.score.satisfaction,float(last.tip_cents)/100],17))
			for reason: Dictionary in last.score.reasons.slice(0,3): _sidebar.add_child(TDUI.label(_feedback_text(str(reason.message)),14,TDUI.MUTED))

func _feedback_text(value: String) -> String:
	var terms: Dictionary={"M1操作品质":"备菜节奏","M2操作品质":"点火时机","M3操作品质":"翻炒与拌料","M4操作品质":"炒制火候","M5操作品质":"炖煮火候","M6操作品质":"调味节奏","M7操作品质":"出锅时机","stale_oil":"油耗味","burnt":"焦糊味"}
	for term: String in terms: value=value.replace(term,terms[term])
	return value

func _ingredient(id: String) -> Dictionary:
	for item: Dictionary in service.cooking.data().ingredients:
		if item.id==id: return item
	return {}

func buy_kit(id: String, missing_only: bool = true) -> TDOutcome:
	var cart: Dictionary={}
	for ingredient: String in shop.offer(id).stock:
		var missing: int=maxi(0,int(shop.offer(id).stock[ingredient])-(shop.available(ingredient) if missing_only else 0))
		if missing>0: cart[ingredient]=missing
	_serial+=1
	var result:=TDOutcome.new(true,"ENOUGH_STOCK","库存已足够一份。") if cart.is_empty() else shop.buy(cart,"purchase-%d-%d" % [Time.get_ticks_usec(),_serial])
	_show(result); refresh(true); return result

func save_boundary() -> TDOutcome:
	if embedded:
		return boundary_save.call() if boundary_save.is_valid() else TDOutcome.new(false,"NO_STORAGE")
	if _load_blocked: return TDOutcome.new(false,"LOAD_BLOCKED")
	if _new_needs_confirmation:
		_confirm("已有经营存档。确认新开一间店？旧档会另存备份，不再作为继续游戏的入口。",func()->void:
			var result:=store.archive_for_new_game()
			if result.ok: _new_needs_confirmation=false; save_boundary()
			else: _show(result))
		return TDOutcome.new(false,"CONFIRM_NEW_GAME")
	var result:=store.save_game(shop.snapshot()); _show(result); return result

func open_day() -> void:
	if get_tree().paused or _load_blocked: return
	var saved:=save_boundary()
	if not saved.ok: return
	_make_kitchen(); _show(shop.open_day()); refresh(true)

func next_day() -> void:
	if get_tree().paused: return
	var result:=save_boundary()
	if not result.ok: return
	_show(shop.next_day(int(shop.snapshot().day))); refresh(true)

func _apply_context(lane: TDCookingLane, context: Dictionary) -> TDOutcome:
	var profile: TDCookingCatalog=shop.profile_for(context)
	if profile==null: return TDOutcome.new(false,"INVALID_REQUEST_PROFILE")
	return lane.use_recipe_profile(profile,shop.family_id(context.recipe_id),context.get("customer",{}))

func _station(id: String) -> void:
	_station_action(id,"interact")

func _station_action(id: String, action: String) -> void:
	if get_tree().paused: return
	if shop.snapshot().phase not in ["OPEN","DRAINING"]: _station_done(TDOutcome.new(false,"NOT_OPEN")); return
	if id=="kitchen.trash": _trash(); return
	if id=="kitchen.serve": _serve(); return
	if id=="kitchen.fridge":
		if kitchen.handling.hand_kind=="ingredient": return_ingredient()
		else: _show_pantry()
		return
	if id=="kitchen.board":
		if kitchen.prep.qte!=null or (kitchen.prep.sheet!=null and kitchen.prep.sheet.running): kitchen.open_station_view(id); return
		if kitchen.handling.board!=null:
			_station_done(kitchen.handling.take_board()); return
		var result:=kitchen.handling.put_board()
		if result.ok:
			kitchen.prep.bind_preparation(kitchen.handling.board)
			_show_cut_choices(); _sync_usage()
		else: _station_done(result)
		return
	if id not in ["kitchen.stove.left","kitchen.stove.right","kitchen.steamer"]: return
	var index: int=1 if id in ["kitchen.stove.right","kitchen.steamer"] else 0
	var lane: TDCookingLane=kitchen.lanes[index]
	if action=="retrieve":
		if not lane.session.is_cold(): _station_done(TDOutcome.new(false,"COOKING_STARTED","已开始加工，只能继续制作或整锅丢弃。")); return
		_show_pot_contents(index); return
	if action!="open":
		if kitchen.handling.hand_kind=="ingredient":
			var result:=kitchen.handling.put_pot(lane.session)
			if result.ok: _recognize(lane,"steam" if id=="kitchen.steamer" else "stir",false)
			_station_done(result); return
		if lane.snapshot().state=="plated": _station_done(kitchen.handling.take_dish(lane.session)); return
		_station_done(TDOutcome.new(true,"OPEN_HINT","F 开始做菜 / 查看操作 · Q 取出食材")); return
	if lane.qte!=null or lane.thermal_qte!=null or (lane.sheet!=null and lane.sheet.running): kitchen.open_station_view(id); return
	if lane.snapshot().state=="plated": _station_done(TDOutcome.new(true,"READY","已做好，按 E 端盘。")); return
	if lane.snapshot().ingredients.is_empty(): _station_done(TDOutcome.new(false,"NO_INGREDIENT")); return
	var selected:=_recognize(lane,"steam" if id=="kitchen.steamer" else "stir",true)
	if not selected.ok: _station_done(selected); return
	lane.document_rules=true; lane.dual=true
	var result:=lane.start_sheet(str(lane.catalog.for_recipe(lane.base_recipe_id).recipe.guided_profile))
	if result.ok: kitchen.open_station_view(id)
	else: _station_done(result)

func _recognize(lane: TDCookingLane, method: String, complete: bool) -> TDOutcome:
	var ids: Array=lane.snapshot().ingredients.values().map(func(x:Dictionary)->String:return x.ingredient_id)
	var context: Dictionary=shop.context_for_ingredients(ids,complete,method)
	if not context.is_empty(): return _apply_context(lane,context)
	return lane.use_recipe_profile(service.cooking,"kitchen.unknown_"+method)

func _show_cut_choices() -> void:
	var column:=_dialog("选择切型 · 然后按谱切菜")
	column.add_child(TDUI.label("切型由你选择；顾客的要求显示在订单上，做错切型仍可以继续做菜。",18))
	var row:=HBoxContainer.new(); row.add_theme_constant_override("separation",18); column.add_child(row)
	for shape: String in service.config.preparation_choices:
		var button:=TDUI.button({"chunk":"大块","dice":"小丁","slice":"薄片","strip":"长条"}[shape],func()->void:choose_cut(shape))
		button.custom_minimum_size=Vector2(155,95); row.add_child(button)
	column.add_child(TDUI.button("先不切，返回厨房",_close_popup))

func choose_cut(shape: String) -> TDOutcome:
	if get_tree().paused: return TDOutcome.new(false,"PAUSED")
	if kitchen.handling.board==null or not service.config.preparation_choices.has(shape): return TDOutcome.new(false,"INVALID_CUT")
	kitchen.prep.catalog=service.cooking
	var selected:=kitchen.prep.use_recipe_profile(service.cooking,"service.tomato_egg")
	if not selected.ok: return selected
	var result:=kitchen.prep.start_sheet(str(service.config.preparation_choices[shape]))
	_close_popup()
	if result.ok: kitchen.open_station_view("kitchen.board")
	else: _station_done(result)
	return result

func return_ingredient() -> TDOutcome:
	if kitchen.handling.hand==null or kitchen.handling.hand_kind!="ingredient": return TDOutcome.new(false,"NO_INGREDIENT")
	var result:=kitchen.handling.hand.portable_data()
	if result.ok: result=shop.store_food(result.data)
	if result.ok: kitchen.handling.clear_ingredient()
	_station_done(result); return result

func pick_stored(id: String) -> TDOutcome:
	var food: Dictionary=shop.stored_food(id)
	if food.is_empty(): return TDOutcome.new(false,"NOT_FOUND")
	var result:=kitchen.handling.take_stored(food)
	if result.ok: result=shop.take_stored(id)
	_station_done(result); return result

func _show_pot_contents(index: int) -> void:
	var column:=_dialog("锅内材料 · 取出一份")
	for food: Dictionary in kitchen.lanes[index].snapshot().ingredients.values():
		column.add_child(TDUI.button(str(food.name)+" · "+str(food.shape),func()->void:take_pot_ingredient(index,food.id);_close_popup()))
	column.add_child(TDUI.button("返回厨房",_close_popup))

func take_pot_ingredient(index: int, id: String) -> TDOutcome:
	if get_tree().paused: return TDOutcome.new(false,"PAUSED")
	var lane: TDCookingLane=kitchen.lanes[index]
	if lane.qte!=null or lane.thermal_qte!=null or (lane.sheet!=null and lane.sheet.running): return TDOutcome.new(false,"COOKING_STARTED")
	var result:=kitchen.handling.take_ingredient(lane.session,id)
	if result.ok and lane.snapshot().ingredients.is_empty(): _reset_pot(lane)
	elif result.ok: _recognize(lane,"steam" if lane.station_role=="steamer" else "stir",false)
	_station_done(result); return result

func _reset_pot(lane: TDCookingLane) -> void:
	lane.cancel_operation(); lane.catalog=kitchen.catalog; lane.customer_override=[]; lane.new_session("service.tomato_egg"); lane.session.set_material_sink(shop.consume_materials)

func _trash() -> void:
	if kitchen.handling.hand!=null:
		if kitchen.handling.hand_kind=="dish":
			for lane: TDCookingLane in kitchen.lanes:
				if kitchen.handling.hand==lane.session: kitchen.handling.clear_dish(); _reset_pot(lane); break
		else: kitchen.handling.clear_ingredient()
		_station_done(TDOutcome.new(true,"DISCARDED","已丢弃，食材不返还。")); return
	var column:=_dialog("清理厨房 · 丢弃后不返还食材")
	if kitchen.handling.board!=null: column.add_child(TDUI.button("丢弃砧板食材",func()->void:kitchen.prep.cancel_operation();kitchen.handling.board.cancel();kitchen.handling.board=null;_close_popup();_station_done(TDOutcome.new(true,"DISCARDED"))))
	for i: int in kitchen.lanes.size():
		if not kitchen.lanes[i].snapshot().ingredients.is_empty(): column.add_child(TDUI.button("丢弃"+("左锅" if i==0 else "右锅 / 蒸笼")+"整份食物",func()->void:_reset_pot(kitchen.lanes[i]);_close_popup();_station_done(TDOutcome.new(true,"DISCARDED"))))
	column.add_child(TDUI.button("返回厨房",_close_popup))

func _show_pantry() -> void:
	var column:=_dialog("大冰箱 · 每次携带一份食材")
	column.add_child(TDUI.label("可自由取料；主料每次1份，调料每次0.1份。灶台调味会直接消耗冰箱余量。",16,TDUI.MUTED))
	var scroll:=ScrollContainer.new(); scroll.custom_minimum_size=Vector2(710,290); scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL; column.add_child(scroll)
	var grid:=GridContainer.new(); grid.columns=3; grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL; grid.add_theme_constant_override("h_separation",10); grid.add_theme_constant_override("v_separation",10); scroll.add_child(grid)
	for food: Dictionary in shop.snapshot().cold_foods:
		var held_food: Dictionary=food
		var button:=TDUI.button("冷藏 · "+str(_ingredient(food.ingredient_id).name)+("（已切配）" if not food.cuts.is_empty() else "（原料）"),func()->void:pick_stored(held_food.id);_close_popup())
		button.custom_minimum_size=Vector2(224,55); button.disabled=kitchen.handling.hand!=null; grid.add_child(button)
	for id: String in service.config.costs:
		var amount: int=1000 if service.is_primary(id) else 100
		var button:=TDUI.button("%s · 余 %.2f份" % [_ingredient(id).name,float(shop.available(id))/1000],func()->void:pick_ingredient(id);_close_popup())
		button.custom_minimum_size=Vector2(224,55); button.disabled=shop.available(id)<amount or kitchen.handling.hand!=null; grid.add_child(button)
	column.add_child(TDUI.button("返回厨房",_close_popup))

func pick_ingredient(id: String) -> TDOutcome:
	if get_tree().paused: return TDOutcome.new(false,"PAUSED")
	if shop.snapshot().phase not in ["OPEN","DRAINING"] or not service.config.costs.has(id): return TDOutcome.new(false,"NOT_OPEN")
	var context: Dictionary=shop.context_for_ingredients([id])
	var family: String=shop.family_id(context.recipe_id) if not context.is_empty() else "service.tomato_egg"
	var amount: float=1.0 if service.is_primary(id) else .1
	var result:=kitchen.handling.pick(id,family,amount)
	_station_done(result); return result

func _sync_usage() -> void:
	var snapshots: Array=[]
	var contents: Array=[]
	for lane: TDCookingLane in kitchen.lanes:
		var dish: Dictionary=lane.snapshot()
		var names: Array[String]=[]
		for food: Dictionary in dish.ingredients.values():
			if str(food.name) not in names: names.append(str(food.name))
		contents.append({"title":("左锅 · " if lane.lane_index==0 else "右锅 / 蒸笼 · ")+(str(dish.recipe_name) if not names.is_empty() else "空"),"materials":" ＋ ".join(names) if not names.is_empty() else "E 放入 · F 开始 · Q 取回"})
		if dish.state=="plated":
			var unlocked:=shop.observe_finished(dish)
			if unlocked.code=="RECIPE_UNLOCKED": _show(unlocked)
		snapshots.append({"location":"pot","dish":dish,"future_materials":service.material_needs(lane.catalog,lane.base_recipe_id,dish.steps)})
	for source: TDCookingSession in [kitchen.handling.hand,kitchen.handling.board]:
		if source!=null: snapshots.append({"location":"loose","dish":source.snapshot().to_dict()})
	shop.sync_kitchen(snapshots)
	kitchen.world.pot_contents=contents

func _serve() -> void:
	if kitchen.handling.hand_kind!="dish": _station_done(TDOutcome.new(false,"NO_DISH","先端起成品再出餐。")); return
	for index: int in 2:
		var lane: TDCookingLane=kitchen.lanes[index]
		if kitchen.handling.hand!=lane.session: continue
		_sync_usage()
		var item: Dictionary=shop.first_order_for(lane.snapshot())
		if item.is_empty(): _station_done(TDOutcome.new(false,"NO_MATCHING_ORDER","当前没有客人在等这道菜。")); return
		var result:=shop.can_deliver(item.id,lane.snapshot())
		if not result.ok: _station_done(result); return
		result=lane.perform("deliver")
		if result.ok:
			kitchen.handling.clear_dish(); kitchen.close_bench()
			lane.catalog=kitchen.catalog; lane.customer_override=[]; lane.new_session("service.tomato_egg"); lane.session.set_material_sink(shop.consume_materials)
			var served: Dictionary=shop.order(item.id)
			_message.text="已送达 %s · %.1f分。" % [shop.recipe_name(served.recipe_id),served.score.satisfaction]
		else: _station_done(result)
		kitchen.world.set_controls_enabled(true); kitchen.refresh_world(); _sync_usage(); refresh(true); return

func _on_dish(dish: Dictionary) -> void:
	var item: Dictionary=shop.first_order_for(dish)
	if not item.is_empty(): _show(shop.deliver(item.id,dish))

func _on_time(seconds: float) -> void:
	if _closed or shop==null: return
	_sync_usage(); shop.advance(seconds,get_tree().paused); _cleanup_terminal(); refresh()

func cancel_order(id: String) -> void:
	# Retained as an explicit rules/test boundary; order cards expose no buttons.
	if get_tree().paused: return
	_sync_usage(); _show(shop.cancel_order(id)); _cleanup_terminal(); refresh(true)

func _cleanup_terminal() -> void:
	# Customer departure does not destroy physical food. Only the day boundary clears it.
	if shop.snapshot().phase=="SETTLED":
		kitchen.handling.close()
		kitchen.prep.cancel_operation()
		for lane: TDCookingLane in kitchen.lanes: lane.cancel_operation()
		kitchen.close_bench()

func _station_done(result: TDOutcome) -> void:
	_show(result); _sync_usage(); kitchen.world.set_controls_enabled(true); kitchen.refresh_world(); refresh(true)

func _show(result: TDOutcome) -> void:
	last_result=result
	if _message==null: return
	var names: Dictionary={"TRANSFERRED":"食材已放入锅中。","ON_BOARD":"食材已放到砧板。","HANDS_FULL":"手里已有食材或菜品，请先放下。","NOT_OPEN":"现在尚未营业。","NO_PREPARATION_CHART":"这份食材不需要切配，可取回并直接入锅。","RECIPE_LOCKED":"这口锅已经开始加工，请使用另一口锅。","NO_INGREDIENT":"先到冰箱拿食材。","BOARD_OCCUPIED":"砧板上还有食材，请先取走。","EMPTY_BOARD":"砧板上没有食材。","SAVED":"进度已保存，可退出后继续。","PURCHASED":"采购完成，账本已记录。","RESERVED":"已预留食材。","OPENED":"开门迎客！订单自动排队，到大冰箱拿料；同菜按先到客人的要求制作。","SETTLED":"今日结束，请看收益总结。","DRAINING":"已停止迎客。剩下的客人离开后进入收益总结。","INSUFFICIENT_STOCK":"缺少整份食材，未扣料、未收款。可售罄或取消。","INSUFFICIENT_FUNDS":"资金不足，采购未发生。","GRANT_NOT_NEEDED":"当前仍买得起至少一份备货，无需补助。","GRANT_UNAVAILABLE":"补助仅次日起资金不足时可领，每日一次。","GRANTED":"应急补助已到账，账本单独列出。","PLAN_SAVED":"方案已保存；下一天可上架并重新打谱制作。","DUPLICATE":"此操作已处理，不会重复结算。","NEXT_DAY":"新的一天，从菜单与备货开始。"}
	_message.text=result.message if not result.message.is_empty() else str(names.get(result.code,("已完成：" if result.ok else "未执行：")+result.code))

func save_order_plan(id: String, title: String) -> TDOutcome:
	var item: Dictionary=shop.order(id)
	var plan: Dictionary=item.get("plan",{}).duplicate(true)
	var original: Dictionary=shop.offer(str(plan.get("recipe_id","")))
	if original.has("custom_entry"): plan.recipe_id=original.custom_entry.plan.recipe_id
	var result:=shop.save_plan(title,plan)
	_show(result); refresh(true); return result

func _dialog(title: String) -> VBoxContainer:
	_close_popup()
	_scrim=ColorRect.new(); _scrim.color=Color(0,0,0,.65); _scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); _scrim.z_index=29; add_child(_scrim)
	_popup=PanelContainer.new(); _popup.position=Vector2(210,185); _popup.size=Vector2(790,475); _popup.z_index=30
	var style:=StyleBoxFlat.new(); style.bg_color=Color("213d34"); style.border_color=TDUI.ORANGE; style.set_border_width_all(2); style.set_corner_radius_all(12); _popup.add_theme_stylebox_override("panel",style); add_child(_popup)
	kitchen.world.set_controls_enabled(false); kitchen.set_process_input(false)
	var margin:=MarginContainer.new(); for side: String in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,20)
	_popup.add_child(margin)
	var column:=VBoxContainer.new(); column.add_theme_constant_override("separation",12); margin.add_child(column); column.add_child(TDUI.label(title,25,TDUI.ORANGE)); return column

func _close_popup() -> void:
	if is_instance_valid(_popup): remove_child(_popup); _popup.queue_free()
	if is_instance_valid(_scrim): remove_child(_scrim); _scrim.queue_free()
	_popup=null
	_scrim=null
	if kitchen!=null: kitchen.world.set_controls_enabled(true); kitchen.set_process_input(true)

func _show_ledger() -> void:
	var column:=_dialog("经营账本 · 收支与实际库存变化")
	var text:=RichTextLabel.new(); text.custom_minimum_size=Vector2(730,325); text.size_flags_vertical=Control.SIZE_EXPAND_FILL; column.add_child(text)
	var state: Dictionary=shop.snapshot(); var lines: Array[String]=[]
	for event: Dictionary in state.ledger:
		var stock: Array[String]=[]
		for id: String in event.inventory_delta: stock.append("%s %+.2f份" % [_ingredient(id).name,float(event.inventory_delta[id])/1000.0])
		var wasted: Array[String]=[]
		for id: String in event.extra.get("waste",{}): wasted.append("%s %.2f份" % [_ingredient(id).name,float(event.extra.waste[id])/1000.0])
		lines.append("第%d天 · %s  %+.2f元  %s%s" % [event.day,{"purchase":"采购","prepayment":"菜款","consumption":"耗料","tip":"小费","refund_cancel":"取消/超时退还","refund_served":"客诉退款","settlement":"日结","emergency_grant":"应急补助"}.get(event.kind,event.kind),float(event.cents)/100," / ".join(stock),"  已用料损耗："+" / ".join(wasted) if not wasted.is_empty() else ""])
	text.text="\n".join(lines)
	column.add_child(TDUI.button("关闭账本",_close_popup))

func _show_recovery() -> void:
	var result:=store.load_game(); var column:=_dialog("存档未能读取 · "+result.code)
	column.add_child(TDUI.label("原文件保持不变。可以明确选择有效备份恢复；未知版本请保留文件，不能降级覆盖。",18))
	for temporary: bool in [false,true]:
		var button:=TDUI.button("恢复已校验临时文件" if temporary else "恢复上一份有效备份",func()->void:
			var recovered:=store.recover(temporary)
			if recovered.ok: shop.restore(recovered.data); _load_blocked=false; _close_popup(); _make_kitchen(); refresh(true)
			else: _show(recovered))
		button.disabled=result.code=="UNSUPPORTED_VERSION" or not result.data.get("temporary_available" if temporary else "backup_available",false); column.add_child(button)
	column.add_child(TDUI.button("返回主界面",func()->void:back_requested.emit()))

func _confirm(message: String, action: Callable) -> void:
	var dialog:=ConfirmationDialog.new(); dialog.dialog_text=message; dialog.title="确认"; dialog.ok_button_text="确认"; dialog.cancel_button_text="取消"; add_child(dialog)
	dialog.confirmed.connect(func()->void:action.call();dialog.queue_free()); dialog.canceled.connect(dialog.queue_free); dialog.popup_centered(Vector2i(570,190))

func request_back() -> void:
	if embedded: back_requested.emit();return
	request_leave(func()->void:back_requested.emit())

func request_leave(action: Callable) -> void:
	if shop.snapshot().phase in ["OPEN","DRAINING"]:
		_confirm("营业中不能保存。退出后将回到最近一次筹备/日结存档，当前订单和做菜进度会丢失。",action)
	else:
		_confirm("退出当前小店？未保存的筹备或日结修改会丢失。",action)

func set_paused(value: bool) -> void:
	if kitchen!=null: kitchen.set_paused(value)

func close() -> void:
	_closed=true
	if kitchen!=null: kitchen.close()

func _status_name(value: String) -> String:
	return {"WAITING":"等候","COOKING":"制作中","SERVED":"已送达","CANCELLED":"已取消","TIMED_OUT":"等太久离开","REJECTED_STOCK":"缺料谢客"}.get(value,value)

func sync_research_recipes(ids:Array) -> void:
	if shop==null or shop.snapshot().phase not in ["PREPARE","SETTLED"]: return
	for id:String in ids:
		if not shop.is_unlocked(id): shop.grant_recipe(id)
	refresh(true)
