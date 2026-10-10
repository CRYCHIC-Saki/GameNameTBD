class_name TDShopView
extends Control
signal back_requested
signal pause_requested
const KITCHEN := preload("res://src/kitchen/full_kitchen.tscn")
var save_path: String = "user://shop-v1.json"
var resume_saved: bool = false
var service := TDServiceCatalog.new()
var shop: TDShopSession
var store: TDShopStore
var kitchen: TDFullKitchen
var lane_orders: Array[String] = ["",""]
var selected_order: String = ""
var hand_order: String = ""
var board_order: String = ""
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

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS; theme=TDUI.theme(); set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for state: String in ["normal","hover","pressed","focus"]:
		var style:=theme.get_stylebox(state,"Button") as StyleBoxFlat
		style.content_margin_left=10; style.content_margin_right=10; style.content_margin_top=8; style.content_margin_bottom=8
	var background:=ColorRect.new(); background.color=Color("17251f"); background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); background.mouse_filter=Control.MOUSE_FILTER_IGNORE; add_child(background)
	var loaded:=service.load_file()
	if not loaded.ok: add_child(TDUI.label("营业配置错误："+loaded.message)); return
	shop=TDShopSession.new(service); store=TDShopStore.new(save_path,shop)
	if resume_saved:
		var saved:=store.load_game()
		if saved.ok: last_result=shop.restore(saved.data)
		else: last_result=saved; _load_blocked=true
	else: _new_needs_confirmation=store.load_game().code!="NOT_FOUND"
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
	kitchen=KITCHEN.instantiate() as TDFullKitchen; kitchen.catalog=catalog; kitchen.scorer=shop.scorer
	kitchen.library_path=save_path+".unused-library" # No player recipe write bypasses the business save.
	kitchen.station_handler=_station
	kitchen.time_boundary=shop.next_boundary
	kitchen.station_names={"kitchen.supply.tomato":"蔬菜架 · 取料","kitchen.supply.egg":"配料架 · 取料","kitchen.supply.beef":"肉类架 · 取料"}
	kitchen.z_index=2
	kitchen.back_requested.connect(request_back); kitchen.pause_requested.connect(func()->void:pause_requested.emit())
	kitchen.time_advanced.connect(_on_time); kitchen.dish_delivered.connect(_on_dish)
	_holder.add_child(kitchen); kitchen.world.scale=Vector2(.71875,.71875)
	kitchen.world.get_node("Background").z_index=-1
	kitchen.world.set_return_visible(false)
	lane_orders=["",""]; selected_order=""; hand_order=""; board_order=""

func refresh(force: bool = false) -> void:
	if shop==null or _closed: return
	var state: Dictionary=shop.snapshot()
	var fame: int=0
	for id: String in state.menu:
		if state.menu[id].enabled: fame+=int(state.fame.get(id,0))
	_title.text="小镇食堂  ·  第 %d 天     ¥ %.2f     人气 %d   店名气 %d" % [state.day,float(state.money_cents)/100.0,state.popularity,fame]
	var boundary: bool=state.phase in ["PREPARE","SETTLED"]
	_open_button.disabled=state.phase!="PREPARE" or _load_blocked
	_save_button.disabled=not boundary or _load_blocked
	_next_button.disabled=state.phase!="SETTLED" or _load_blocked
	_page.visible=boundary; _holder.visible=not boundary
	if _last_phase!=state.phase or (force and boundary):
		_last_phase=state.phase; _planning_page(state)
	var side_key: String=JSON.stringify([state.orders.map(func(o:Dictionary)->Array:return [o.id,o.status]),state.phase,int(state.elapsed_sec),selected_order,state.money_cents])
	if force or side_key!=_side_key: _side_key=side_key; _orders_panel(state)

func _empty(node: Node) -> void:
	for child: Node in node.get_children(): node.remove_child(child); child.queue_free()

func _planning_page(state: Dictionary) -> void:
	_empty(_page)
	var scroll:=ScrollContainer.new(); scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; _page.add_child(scroll)
	var column:=VBoxContainer.new(); column.size_flags_horizontal=Control.SIZE_EXPAND_FILL; column.add_theme_constant_override("separation",12); scroll.add_child(column)
	column.add_child(TDUI.label("菜单与备货" if state.phase=="PREPARE" else "今日打烊 · 看反馈，准备下一天",25,TDUI.ORANGE))
	column.add_child(TDUI.label("上架菜品会被顾客点单。补齐一份包括主料和预留调料，未用调料会返还可用库存。",15,TDUI.MUTED))
	if state.phase=="PREPARE":
		for id: String in state.menu:
			var row:=HBoxContainer.new(); column.add_child(row)
			var check:=CheckBox.new(); check.text=shop.recipe_name(id); check.custom_minimum_size.x=215; check.button_pressed=state.menu[id].enabled; row.add_child(check)
			var price:=SpinBox.new(); price.min_value=.01; price.max_value=10000; price.step=.5; price.value=float(state.menu[id].price_cents)/100; price.prefix="¥ "; price.custom_minimum_size.x=125; row.add_child(price)
			check.toggled.connect(func(v:bool)->void:_show(shop.set_menu(id,v,roundi(price.value*100))))
			price.value_changed.connect(func(v:float)->void:_show(shop.set_menu(id,check.button_pressed,roundi(v*100))))
			var reference:=TDUI.label("参考 %.2f" % (float(shop.offer(id).reference_cents)/100),15,TDUI.MUTED)
			reference.custom_minimum_size.x=105; reference.autowrap_mode=TextServer.AUTOWRAP_OFF; row.add_child(reference)
			row.add_child(TDUI.button("补齐 ¥%.2f" % (float(shop.kit_cost(id,true))/100),func()->void:buy_kit(id)))
			row.add_child(TDUI.button("再备1份",func()->void:buy_kit(id,false)))
		column.add_child(TDUI.button("资金困难 · 申请应急补助",func()->void:_show(shop.claim_grant());refresh(true)))
	else:
		var purchased: int=0; var received: int=0; var refunded: int=0
		for event: Dictionary in state.ledger:
			if int(event.day)!=int(state.day): continue
			if event.kind=="purchase": purchased-=int(event.cents)
			elif event.kind in ["prepayment","tip"]: received+=int(event.cents)
			elif event.kind in ["refund_cancel","refund_served"]: refunded-=int(event.cents)
		column.add_child(TDUI.label("采购 ¥%.2f  ·  收款 ¥%.2f  ·  退款 ¥%.2f  ·  净收支 %+.2f" % [float(purchased)/100,float(received)/100,float(refunded)/100,float(received-refunded-purchased)/100],19,TDUI.ORANGE))
		for item: Dictionary in state.orders:
			var text: String=shop.recipe_name(item.recipe_id)+" · "+_status_name(item.status)
			if not item.score.is_empty(): text+=" · %.1f分 · 实收¥%.2f" % [item.score.satisfaction,float(item.prepaid_cents+item.tip_cents-item.refunded_cents)/100]
			column.add_child(TDUI.label(text,18))
			if not item.score.is_empty():
				for reason: Dictionary in item.score.reasons.slice(0,3): column.add_child(TDUI.label("  "+_feedback_text(str(reason.message)),14,TDUI.MUTED))
				column.add_child(TDUI.button("退还此单款项",func()->void:_show(shop.refund(item.id));refresh(true)))
				var row:=HBoxContainer.new(); column.add_child(row)
				var name_input:=LineEdit.new(); name_input.placeholder_text="为这份做法命名"; name_input.custom_minimum_size.x=250; row.add_child(name_input)
				row.add_child(TDUI.button("保存食材与工序方案",func()->void:save_order_plan(item.id,name_input.text)))
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

func _orders_panel(state: Dictionary) -> void:
	_empty(_sidebar)
	_sidebar.add_child(TDUI.label("接待与订单",24,TDUI.ORANGE))
	var clock_text: String="筹备不计时" if state.phase=="PREPARE" else ("今日已结算" if state.phase=="SETTLED" else ("停止接客 · 完成剩余订单" if state.phase=="DRAINING" else "营业剩余 %d 秒" % maxi(0,int(service.config.settings.day_sec)-int(state.elapsed_sec))))
	_sidebar.add_child(TDUI.label(clock_text,17))
	if _new_needs_confirmation: _sidebar.add_child(TDUI.label("新店尚未覆盖旧档；首次保存前会确认。",15,TDUI.ORANGE))
	for item: Dictionary in state.orders:
		if item.status not in ["WAITING","COOKING"]: continue
		var panel:=PanelContainer.new(); _sidebar.add_child(panel)
		var column:=VBoxContainer.new(); column.add_theme_constant_override("separation",5); panel.add_child(column)
		column.add_child(TDUI.label(("▶ " if selected_order==item.id else "")+shop.recipe_name(item.recipe_id),20,TDUI.ORANGE))
		column.add_child(TDUI.label("%s · ¥%.2f" % [item.customer.name,float(item.price_cents)/100],15))
		for requirement: Dictionary in item.customer.requirements: column.add_child(TDUI.label("· "+str(requirement.label),14,TDUI.MUTED))
		var patience:=ProgressBar.new(); patience.max_value=float(service.config.settings.patience_sec); patience.value=maxf(0,float(item.deadline_sec)-float(state.elapsed_sec)); patience.show_percentage=false; patience.custom_minimum_size.y=13; column.add_child(patience)
		column.add_child(TDUI.label("耐心 %d 秒 · %s" % [ceili(patience.value),_status_name(item.status)],15))
		var row:=HBoxContainer.new(); column.add_child(row)
		if item.status=="WAITING":
			for lane: int in 2: row.add_child(TDUI.button("左锅备菜" if lane==0 else "右锅备菜",func()->void:begin_order(item.id,lane)))
		else:
			row.add_child(TDUI.button("选中此单",func()->void:selected_order=item.id;_show(TDOutcome.new(true,"SELECTED","已选中；去食材架取料。"));refresh(true)))
		row.add_child(TDUI.button("取消",func()->void:cancel_order(item.id)))
		column.add_child(TDUI.button("这道菜售罄",func()->void:_show(shop.sold_out(item.recipe_id));refresh(true)))
	var done: Array=state.orders.filter(func(o:Dictionary)->bool:return o.status not in ["WAITING","COOKING"])
	if not done.is_empty():
		var last: Dictionary=done.back()
		_sidebar.add_child(TDUI.label("最近一单 · "+_status_name(last.status),18,TDUI.ORANGE))
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

func begin_order(id: String, lane: int) -> TDOutcome:
	if get_tree().paused: return TDOutcome.new(false,"PAUSED")
	var result:=shop.begin_order(id,lane)
	if result.ok:
		lane_orders[lane]=id; selected_order=id
		kitchen.lanes[lane].session_namespace=id
		kitchen.lanes[lane].customer_override=[result.data.customer.duplicate(true)]
		kitchen.lanes[lane].new_session(str(result.data.recipe_id))
		result.message="订单已预留整份食材 · 到料架取料，再按菜谱备菜。"
	_show(result); refresh(true); return result

func _station(id: String) -> void:
	if get_tree().paused: return
	if shop.snapshot().phase not in ["OPEN","DRAINING"]: _station_done(TDOutcome.new(false,"NOT_OPEN")); return
	var item: Dictionary=shop.order(selected_order)
	if id=="kitchen.serve": _serve(); return
	if id.begins_with("kitchen.supply."):
		if item.get("status")!="COOKING": _station_done(TDOutcome.new(false,"SELECT_ORDER","先在右侧选择订单和灶台。")); return
		_show_pantry(); return
	if id=="kitchen.board":
		var result: TDOutcome
		if kitchen.handling.hand==null and kitchen.handling.board!=null:
			if kitchen.prep.qte!=null or (kitchen.prep.sheet!=null and kitchen.prep.sheet.running): kitchen.open_station_view(id); return
			result=kitchen.handling.take_board()
			if result.ok: hand_order=board_order; board_order=""
		else:
			result=kitchen.handling.put_board()
			if result.ok:
				board_order=hand_order; hand_order=""; kitchen.prep.bind_preparation(kitchen.handling.board)
				kitchen.prep.customer_override=[shop.order(board_order).customer]
				result=kitchen.prep.start_preparation()
				if result.ok: kitchen.open_station_view(id); return
		_station_done(result); return
	var index: int=1 if id in ["kitchen.stove.right","kitchen.steamer"] else 0
	var lane: TDCookingLane=kitchen.lanes[index]
	var bound: Dictionary=shop.order(lane_orders[index])
	if bound.get("status")!="COOKING": _station_done(TDOutcome.new(false,"SELECT_ORDER","先为这口锅选择订单。")); return
	if id=="kitchen.steamer": _station_done(TDOutcome.new(false,"WRONG_STATION","当前菜单使用炒锅，请到右灶台。")); return
	if kitchen.handling.hand_kind=="ingredient":
		if hand_order!=bound.id: _station_done(TDOutcome.new(false,"WRONG_ORDER","这份食材属于另一口锅的订单。")); return
		var food: Dictionary=kitchen.handling.hand.snapshot().to_dict().ingredients.values()[0]
		var recipe: Dictionary=kitchen.catalog.for_recipe(bound.recipe_id).recipe
		if recipe.get("preparation_sheets",{}).has(food.ingredient_id) and food.history.is_empty(): _station_done(TDOutcome.new(false,"PREPARE_FIRST","先到砧板按菜谱备菜。")); return
		var moved:=kitchen.handling.put_pot(lane.session)
		if moved.ok: hand_order=""
		_station_done(moved); return
	if kitchen.handling.hand!=null: _station_done(TDOutcome.new(false,"HANDS_FULL")); return
	if lane.snapshot().state=="plated": _station_done(kitchen.handling.take_dish(lane.session)); return
	if lane.qte!=null or lane.thermal_qte!=null or (lane.sheet!=null and lane.sheet.running): kitchen.open_station_view(id); return
	var food_ids: Array=lane.snapshot().ingredients.values().map(func(x:Dictionary)->String:return x.ingredient_id)
	for ingredient: String in shop.offer(bound.recipe_id).primary:
		if ingredient not in food_ids: _station_done(TDOutcome.new(false,"MISSING_PREPARATION","先将全部主料搬入锅中。")); return
	lane.document_rules=true; lane.dual=true
	var result:=lane.start_sheet(str(kitchen.catalog.for_recipe(bound.recipe_id).recipe.guided_profile))
	if result.ok: kitchen.open_station_view(id)
	else: _station_done(result)

func _show_pantry() -> void:
	var column:=_dialog("食材架 · "+shop.recipe_name(shop.order(selected_order).recipe_id))
	var item: Dictionary=shop.order(selected_order)
	for id: String in shop.offer(item.recipe_id).primary:
		var remaining: int=int(item.reserved.get(id,0))-int(item.used.get(id,0))
		var button:=TDUI.button("拿取 "+str(_ingredient(id).name)+" · 可取 %.1f份" % (float(remaining)/1000),func()->void:pick_ingredient(id);_close_popup())
		button.disabled=remaining<1000 or kitchen.handling.hand!=null; column.add_child(button)
	column.add_child(TDUI.label("调料已随订单预留，在调味谱中实际使用时消耗。",16,TDUI.MUTED))
	column.add_child(TDUI.button("返回厨房",_close_popup))

func pick_ingredient(id: String) -> TDOutcome:
	if get_tree().paused: return TDOutcome.new(false,"PAUSED")
	var item: Dictionary=shop.order(selected_order)
	if item.get("status")!="COOKING" or id not in shop.offer(item.recipe_id).primary or int(item.reserved.get(id,0))-int(item.used.get(id,0))<1000: return TDOutcome.new(false,"NO_RESERVED_STOCK")
	var result:=kitchen.handling.pick(id,item.recipe_id)
	if result.ok: hand_order=item.id; _sync_usage()
	_station_done(result); return result

func _sync_usage() -> void:
	for index: int in 2:
		var id: String=lane_orders[index]
		if shop.order(id).get("status")!="COOKING": continue
		var sessions: Array=[kitchen.lanes[index].session]
		if hand_order==id and kitchen.handling.hand!=null and kitchen.handling.hand_kind=="ingredient": sessions.append(kitchen.handling.hand)
		if board_order==id and kitchen.handling.board!=null: sessions.append(kitchen.handling.board)
		var totals: Dictionary={}; var seen: Dictionary={}
		for session: TDCookingSession in sessions:
			var snap: Dictionary=session.snapshot().to_dict()
			if seen.has(snap.session_id): continue
			seen[snap.session_id]=true
			for ingredient: Dictionary in snap.consumed_ingredients: totals[ingredient.ingredient_id]=int(totals.get(ingredient.ingredient_id,0))+roundi(float(ingredient.amount)*1000.0)
		var consumed:=shop.consume_total(id,totals)
		if not consumed.ok: _show(consumed)

func _serve() -> void:
	if kitchen.handling.hand_kind!="dish": _station_done(TDOutcome.new(false,"NO_DISH","先端起成品再出餐。")); return
	for index: int in 2:
		if kitchen.handling.hand!=kitchen.lanes[index].session: continue
		var id: String=lane_orders[index]
		_sync_usage()
		var result:=shop.can_deliver(id,kitchen.lanes[index].snapshot())
		if not result.ok: _station_done(result); return
		result=kitchen.lanes[index].perform("deliver")
		if result.ok:
			kitchen.handling.clear_dish(); kitchen.close_bench(); lane_orders[index]=""
			var order_result: Dictionary=shop.order(id)
			_message.text="已送达 %s · %.1f分。日结可查看详细评价或保存这份做法。" % [shop.recipe_name(order_result.recipe_id),order_result.score.satisfaction]
		if not result.ok: _station_done(result)
		else: kitchen.world.set_controls_enabled(true); kitchen.refresh_world()
		refresh(true); return

func _on_dish(dish: Dictionary) -> void:
	for index: int in 2:
		if kitchen.lanes[index].snapshot().session_id==dish.session_id:
			_show(shop.deliver(lane_orders[index],dish)); return

func _on_time(seconds: float) -> void:
	if _closed or shop==null: return
	_sync_usage(); shop.advance(seconds,get_tree().paused); _cleanup_terminal(); refresh()

func cancel_order(id: String) -> void:
	if get_tree().paused: return
	_sync_usage(); _show(shop.cancel_order(id)); _cleanup_terminal(); refresh(true)

func _cleanup_terminal() -> void:
	for index: int in 2:
		var id: String=lane_orders[index]
		if id.is_empty() or shop.order(id).get("status")=="COOKING": continue
		if hand_order==id:
			if kitchen.handling.hand!=null: kitchen.handling.hand.cancel()
			kitchen.handling.hand=null; kitchen.handling.hand_kind=""; hand_order=""
		if board_order==id:
			kitchen.prep.cancel_operation(); kitchen.handling.board=null; board_order=""
		if kitchen.handling.hand==kitchen.lanes[index].session: kitchen.handling.clear_dish()
		kitchen.lanes[index].new_session("service.tomato_egg"); lane_orders[index]=""
		kitchen.close_bench()

func _station_done(result: TDOutcome) -> void:
	_show(result); kitchen.world.set_controls_enabled(true); kitchen.refresh_world()

func _show(result: TDOutcome) -> void:
	last_result=result
	if _message==null: return
	var names: Dictionary={"SAVED":"进度已保存，可退出后继续。","PURCHASED":"采购完成，账本已记录。","RESERVED":"已预留食材。","OPENED":"开门迎客！选择订单，再去食材架取料。","INSUFFICIENT_STOCK":"缺少整份食材，未扣料、未收款。可售罄或取消。","INSUFFICIENT_FUNDS":"资金不足，采购未发生。","HANDS_FULL":"先放下手上的食材或成品。","GRANT_NOT_NEEDED":"当前仍买得起至少一份备货，无需补助。","GRANT_UNAVAILABLE":"补助仅次日起资金不足时可领，每日一次。","GRANTED":"应急补助已到账，账本单独列出。","PLAN_SAVED":"方案已保存；下一天可上架并重新打谱制作。","DUPLICATE":"此操作已处理，不会重复结算。","NEXT_DAY":"新的一天，从菜单与备货开始。"}
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
		lines.append("第%d天 · %s  %+.2f元  %s%s" % [event.day,{"purchase":"采购","prepayment":"预收","consumption":"耗料","tip":"小费","refund_cancel":"取消/超时退还","refund_served":"客诉退款","settlement":"日结","emergency_grant":"应急补助"}.get(event.kind,event.kind),float(event.cents)/100," / ".join(stock),"  已用料损耗："+" / ".join(wasted) if not wasted.is_empty() else ""])
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
	return {"WAITING":"等候","COOKING":"制作中","SERVED":"已送达","CANCELLED":"已取消","TIMED_OUT":"等太久离开"}.get(value,value)
