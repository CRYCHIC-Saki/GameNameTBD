class_name TDGameShell
extends Control
## Presentation and dependency assembly. Economy remains in the existing shop model.
signal debug_entry_requested(entry: String)
const TITLE_ART := preload("res://assets/town/title-town-v1.png")
var profile_root: String="user://profiles"
var preferences_path: String="user://player-settings.json"
var legacy_shop_path: String="user://shop-v1.json"
var legacy_research_path: String="user://research-v1.json"
var profile: TDGameProfile
var slots: TDProfileStore
var preferences: TDPlayerPreferences
var town: TDTownWorld
var restaurant: TDRestaurantWorld
var kitchen_view: TDShopView
var atlas: TDRecipeAtlas
var location: String="title"
var debug_enabled: bool=false
var automatic_time: bool=true
var _title_screen: Control
var _hud: Label
var _hud_layer: CanvasLayer
var _modal: CanvasLayer
var _modal_box: VBoxContainer
var _notice: Label
var _console: LineEdit
var _console_output: Label
var _atlas_layer: CanvasLayer
var _frozen: Array=[]
var _prior_pause: bool=false
var _last_phase: String=""
var _generation: int=0
var _preferences_status: Label
var _toast: String=""
var _toast_until: int=0
var _title_notice: Label
var _entry_busy: bool=false

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	theme=TDUI.theme()
	# Crisp wooden panels fit the pixel scene; text remains native and readable.
	for state: String in ["normal","hover","pressed","focus"]:
		var style:=theme.get_stylebox(state,"Button") as StyleBoxFlat
		style.set_corner_radius_all(2);style.set_border_width_all(2)
		style.bg_color=Color("65523c") if state=="hover" else Color("3b4235")
		style.border_color=Color("c8a56a") if state=="hover" else Color("8e815d")
	var panel_style:=StyleBoxFlat.new();panel_style.bg_color=Color("242d26");panel_style.border_color=Color("b79b68");panel_style.set_border_width_all(3)
	theme.set_stylebox("panel","PanelContainer",panel_style)
	slots=TDProfileStore.new(profile_root,TDGameProfile.validate_save)
	preferences=TDPlayerPreferences.new(preferences_path)
	preferences.apply()
	_build_title()
	_hud_layer=CanvasLayer.new();_hud_layer.layer=20;add_child(_hud_layer)
	_hud_layer.visible=false
	var hud_back:=ColorRect.new();hud_back.color=Color(.07,.12,.10,.9);hud_back.size=Vector2(1280,54);hud_back.mouse_filter=Control.MOUSE_FILTER_IGNORE;_hud_layer.add_child(hud_back)
	_hud=TDUI.label("",19,Color("f5d79d"));_hud.position=Vector2(24,14);_hud.size=Vector2(1200,34);_hud.mouse_filter=Control.MOUSE_FILTER_IGNORE;_hud_layer.add_child(_hud)

func _build_title() -> void:
	if is_instance_valid(_hud_layer): _hud_layer.visible=false
	if is_instance_valid(_title_screen): _title_screen.queue_free()
	_title_screen=Control.new();_title_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(_title_screen)
	var art:=TextureRect.new();art.texture=TITLE_ART;art.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;art.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED;art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);art.mouse_filter=Control.MOUSE_FILTER_IGNORE;_title_screen.add_child(art)
	var shade:=ColorRect.new();shade.color=Color(.08,.12,.12,.65);shade.position=Vector2(40,60);shade.size=Vector2(360,670);shade.mouse_filter=Control.MOUSE_FILTER_IGNORE;_title_screen.add_child(shade)
	var column:=VBoxContainer.new();column.position=Vector2(76,108);column.size=Vector2(288,560);column.add_theme_constant_override("separation",18);_title_screen.add_child(column)
	column.add_child(TDUI.label("小 镇 食 堂",48,Color("f5dfb6")))
	column.add_child(TDUI.label("一餐烟火，一日小镇",18,Color("d7c5a0")))
	var space:=Control.new();space.custom_minimum_size.y=28;column.add_child(space)
	column.add_child(TDUI.button("开始游戏",start_game))
	var resume:=TDUI.button("继续游戏",continue_game);resume.disabled=slots.latest().is_empty();column.add_child(resume)
	column.add_child(TDUI.button("载入存档",func()->void:show_slots(false)))
	column.add_child(TDUI.button("设置",show_settings))
	column.add_child(TDUI.button("退出游戏",request_quit))
	column.add_child(TDUI.label("WASD 移动  ·  E 交互",15,Color("b7c6b8")))
	_title_notice=TDUI.label("",20,Color("f5dfb6"));_title_notice.position=Vector2(440,660);_title_notice.size=Vector2(780,100)
	_title_notice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_title_screen.add_child(_title_notice)

func _process(_delta: float) -> void:
	if profile==null: return
	var state:=profile.shop.snapshot()
	_hud.text="%s  ·  第 %d 天    ¥ %.2f    %s"%[profile.title,state.day,float(state.money_cents)/100.0,{"PREPARE":"筹备中","OPEN":"营业中","DRAINING":"等待最后的客人","SETTLED":"今日已打烊"}.get(state.phase,state.phase)]
	if Time.get_ticks_msec()<_toast_until: _hud.text+= "  ·  "+_toast
	_hud_layer.visible=location!="kitchen" and atlas==null
	if state.phase!=_last_phase:
		_last_phase=state.phase
		profile.world.day=int(state.day)
		profile.world.day_phase="morning" if state.phase=="PREPARE" else ("evening" if state.phase=="SETTLED" else "service")
		if state.phase=="SETTLED":
			var result:=save_game()
			if not result.ok: _message("自动保存失败："+result.code)

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree(): return
	if _entry_busy:
		get_viewport().set_input_as_handled();return
	if event.is_action_pressed("debug_console") and not event.is_echo():
		show_console();get_viewport().set_input_as_handled();return
	# Esc closes a modal even while its text field owns keyboard focus.
	if event.is_action_pressed("pause") and not event.is_echo() and _modal!=null:
		_close_dialog();get_viewport().set_input_as_handled();return
	var focus:=get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit: return
	if event.is_action_pressed("recipe_book") and not event.is_echo() and profile!=null and _modal==null:
		if atlas!=null: close_atlas()
		elif _modal==null: open_atlas()
		get_viewport().set_input_as_handled()
	if event.is_action_pressed("pause") and not event.is_echo():
		if _modal!=null: _close_dialog()
		elif atlas!=null:
			if atlas.trial==null: close_atlas()
			else: atlas.set_paused(not get_tree().paused);get_tree().paused=not get_tree().paused
		elif profile!=null: show_pause()
		get_viewport().set_input_as_handled()

func _dialog(title: String, freeze: bool=false) -> VBoxContainer:
	_close_dialog()
	_prior_pause=get_tree().paused
	if freeze: _pause(true)
	_lock_controls(false)
	_modal=CanvasLayer.new();_modal.layer=800;add_child(_modal)
	var scrim:=ColorRect.new();scrim.color=Color(0.02,0.04,0.03,.72);scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);_modal.add_child(scrim)
	var panel:=PanelContainer.new();panel.position=Vector2(210,74);panel.size=Vector2(860,650);panel.theme=theme;_modal.add_child(panel)
	var margin:=MarginContainer.new()
	for side:String in ["left","right","top","bottom"]:
		margin.add_theme_constant_override("margin_"+side,24)
	panel.add_child(margin)
	var scroll:=ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;margin.add_child(scroll)
	_modal_box=VBoxContainer.new();_modal_box.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_modal_box.add_theme_constant_override("separation",14);scroll.add_child(_modal_box)
	var top:=HBoxContainer.new();_modal_box.add_child(top)
	var heading:=TDUI.label(title,30,TDUI.ORANGE);heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL;top.add_child(heading)
	top.add_child(TDUI.button("返回",_close_dialog))
	_notice=TDUI.label("",17,Color("edc280"));_modal_box.add_child(_notice)
	return _modal_box

func _message(text: String) -> void:
	if is_instance_valid(_notice): _notice.text=text
	elif is_instance_valid(_title_notice) and _title_screen.visible: _title_notice.text=text
	else: _toast=text;_toast_until=Time.get_ticks_msec()+4000

func _close_dialog() -> void:
	if is_instance_valid(_modal):
		remove_child(_modal);_modal.queue_free();_modal=null
		_pause(_prior_pause)
	_console=null;_console_output=null;_notice=null
	_lock_controls(true)

func _lock_controls(value: bool) -> void:
	if town!=null:
		town._player.set_controls_enabled(value and location=="town")
		town.set_process_unhandled_input(value and location=="town")
	if restaurant!=null:
		restaurant._player.set_controls_enabled(value and location=="restaurant" and not restaurant._editing)
		restaurant.set_process_unhandled_input(value and location=="restaurant")
		restaurant.set_process_input(value and location=="restaurant")
	if kitchen_view!=null and kitchen_view.kitchen!=null:
		kitchen_view.kitchen.world.set_controls_enabled(value and location=="kitchen" and not kitchen_view.kitchen.stage.visible)
		kitchen_view.kitchen.set_process_input(value and location=="kitchen")

func _pause(value: bool) -> void:
	get_tree().paused=value
	if kitchen_view!=null: kitchen_view.set_paused(value)
	if atlas!=null: atlas.set_paused(value)

func show_slots(new_game: bool) -> void:
	if _entry_busy: return
	var box:=_dialog("开始一段新生活" if new_game else "载入存档",true)
	var name_input: LineEdit
	if new_game:
		name_input=LineEdit.new();name_input.placeholder_text="给这家食堂起个名字";name_input.text="小镇食堂";name_input.max_length=40;box.add_child(name_input)
	else: box.add_child(TDUI.button("新建存档",func()->void:show_slots(true)))
	for row: Dictionary in slots.slots():
		var line:=HBoxContainer.new();box.add_child(line)
		var label:=TDUI.label("%d · "%[int(row.slot_id.trim_prefix("slot-"))]+("空存档" if row.empty else ("%s · 第%d天 · ¥%.2f · 已学%d道菜"%[row.title,row.day,float(row.money_cents)/100.0,row.unlocked] if row.ok else "存档不可读取："+str(row.code))),18)
		label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;line.add_child(label)
		var id:String=row.slot_id
		if new_game and row.empty: line.add_child(TDUI.button("从这里开始",func()->void:_enter_game(create_game.bind(id,name_input.text),"正在创建新生活……")))
		elif not new_game and row.ok: line.add_child(TDUI.button("载入",func()->void:_enter_game(load_game.bind(id),"正在载入存档……")))
		elif not row.ok and not row.empty and row.code!="UNSUPPORTED_VERSION":
			if row.get("backup_available",false): line.add_child(TDUI.button("恢复备份",func()->void:_recover_slot(id,false)))
			if row.get("temporary_available",false): line.add_child(TDUI.button("恢复完整临时档",func()->void:_recover_slot(id,true)))
	if new_game: box.add_child(TDUI.button("导入旧进度（原文件保留）",func()->void:_enter_game(import_legacy,"正在导入旧进度……")))
	box.add_child(TDUI.label("每个存档独立保存经营、菜谱、餐厅与小镇。营业期间不保存做菜现场。",16,TDUI.MUTED))

func start_game() -> void:
	if _entry_busy: return
	var id:=slots.latest()
	if not id.is_empty():
		_enter_game(load_game.bind(id),"正在载入最近的存档……");return
	for row: Dictionary in slots.slots():
		if row.empty:
			_enter_game(create_game.bind(String(row.slot_id),"小镇食堂"),"正在创建新生活……");return
	_outcome(TDOutcome.new(false,"NO_EMPTY_SLOT","没有可载入的存档或空位，请通过“载入存档”检查并恢复已有存档。"))

func _enter_game(action: Callable, progress: String) -> void:
	if _entry_busy: return
	_entry_busy=true;_message(progress)
	# Give progress one complete render frame before synchronous content validation.
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree(): return
	var result: TDOutcome=action.call()
	_entry_busy=false
	if not result.ok: _message("无法进入游戏（%s）：%s"%[result.code,result.message if not result.message.is_empty() else "请检查存档或游戏文件。"])

func create_game(id: String, name_value: String="小镇食堂") -> TDOutcome:
	if slots.load_slot(id).code!="NOT_FOUND": return _outcome(TDOutcome.new(false,"SLOT_OCCUPIED","这个存档位已有内容，请选择空位。"))
	var next:=TDGameProfile.new()
	if not next.error.ok:
		next.close()
		return _outcome(next.error)
	next.slot_id=id;next.title=name_value.strip_edges() if not name_value.strip_edges().is_empty() else "小镇食堂";next.persistence=slots.save_slot
	var result:=next.save()
	if not result.ok: next.close();return _outcome(result)
	_activate(next)
	return result

func load_game(id: String) -> TDOutcome:
	var saved:=slots.load_slot(id)
	if not saved.ok: return _outcome(saved)
	var next:=TDGameProfile.new()
	if not next.error.ok: next.close();return _outcome(next.error)
	var result:=next.restore(saved.data)
	if not result.ok: next.close();return _outcome(result)
	next.persistence=slots.save_slot
	_activate(next)
	return result

func continue_game() -> void:
	if _entry_busy: return
	var id:=slots.latest()
	if not id.is_empty(): _enter_game(load_game.bind(id),"正在载入最近的存档……")

func _recover_slot(id: String, temporary: bool) -> void:
	var result:=slots.recover_slot(id,temporary)
	if result.ok: load_game(id)
	else: _outcome(result)

func _activate(next: TDGameProfile) -> void:
	_close_dialog();_dispose_game();profile=next;_generation+=1
	_title_screen.hide();_last_phase=str(profile.shop.snapshot().phase)
	town=TDTownWorld.new();town.player_mode=true;town.session=profile.world
	town.restaurant_requested.connect(func()->void:travel("restaurant"));town.place_requested.connect(_place);town.pause_requested.connect(show_pause);add_child(town)
	restaurant=TDRestaurantWorld.new();restaurant.player_mode=true;restaurant.session=profile.world;restaurant.layout=profile.layout;restaurant.business=profile.shop
	restaurant.object_requested.connect(_object);restaurant.pause_requested.connect(show_pause);add_child(restaurant)
	kitchen_view=TDShopView.new();kitchen_view.embedded=true;kitchen_view.shop=profile.shop;kitchen_view.day_san=profile.world.san;kitchen_view.boundary_save=save_game
	kitchen_view.save_path=profile_root.path_join(profile.slot_id+"-runtime")
	kitchen_view.back_requested.connect(func()->void:travel("restaurant"));kitchen_view.pause_requested.connect(show_pause);add_child(kitchen_view)
	kitchen_view.kitchen.auto_advance=automatic_time
	travel("town")

func travel(destination: String) -> TDOutcome:
	if profile==null or destination not in ["town","restaurant","kitchen"]: return TDOutcome.new(false,"INVALID_DESTINATION")
	if destination=="town" and not profile.can_leave_shop(): return _outcome(TDOutcome.new(false,"SHOP_OPEN","营业中不能离店采购，请先处理订单并打烊。"))
	if _modal!=null: _close_dialog()
	var previous_location:=location
	location=destination
	town.set_presented(destination=="town")
	restaurant.set_floor_cover(destination!="restaurant")
	kitchen_view.visible=destination=="kitchen"
	kitchen_view.kitchen.world.set_controls_enabled(destination=="kitchen")
	if destination=="town": town.spawn_at_home()
	if destination=="restaurant":
		var entry:=restaurant.layout.entrance()+Vector2i.DOWN*2
		if previous_location=="kitchen": entry=Vector2i(restaurant.layout.columns-2,restaurant.layout.rows-2)
		if not restaurant.layout.is_walkable(entry.x,entry.y): entry=restaurant.layout.entrance()
		restaurant.teleport_player(entry)
	_lock_controls(true)
	return TDOutcome.new(true,"ARRIVED")

func _object(action: String) -> void:
	match action:
		"town","kitchen": travel(action)
		"menu": show_menu()
		"ledger": show_ledger()
		"decorate":
			if not profile.at_boundary(): _outcome(TDOutcome.new(false,"SHOP_OPEN","打烊后才能布置餐厅。"));return
			restaurant._toggle_edit()
		"rest": show_rest()
		"recipes": open_atlas()

func _place(kind: String, id: String) -> void:
	if kind=="market":
		profile.world.select_market(id);show_market()
	elif kind=="supply_factory": show_supplier()
	else:
		var box:=_dialog("街坊告示")
		box.add_child(TDUI.label("这里是"+str(profile.world._plot_by_id(id).get("name","小镇街区"))+"。",22))
		if kind in ["factory_lot","supply_factory","diner_lot"]:
			box.add_child(TDUI.label("地块管理",20))
			if kind=="factory_lot": box.add_child(TDUI.button("建设原料厂",func()->void:_outcome(profile.world.build_factory(id))))
		elif not TDSanRules.recovery(kind).is_empty():
			var offer:=TDSanRules.recovery(kind)
			box.add_child(TDUI.label("歇歇脚 · %.0f小时 · %d元 · 精神恢复%d"%[offer.hours,offer.cost,offer.san],18))
			box.add_child(TDUI.button("在这里逛一逛",func()->void:_outcome(profile.world_transaction(profile.world.visit_zone.bind(kind),"visit:"+kind))))
		else: box.add_child(TDUI.label("走访街区，回店经营。",18,TDUI.MUTED))

func show_market() -> void:
	if not profile.can_leave_shop(): _outcome(TDOutcome.new(false,"SHOP_OPEN","营业中不能采购。"));return
	var box:=_dialog("街口菜摊 · 现货采购")
	if profile.shop.snapshot().phase=="SETTLED":
		box.add_child(TDUI.label("今天已经打烊。回店休息后，明早再来挑新鲜食材。",20));return
	var forecast:=profile.shop.visitor_forecast()
	box.add_child(TDUI.label("今日预计 %d—%d 位客人 · 买好食材后回店挂牌营业"%[forecast.min_visitors,forecast.max_visitors],20,TDUI.ORANGE))
	for id: String in profile.service.config.costs:
		var row:=HBoxContainer.new();box.add_child(row)
		var caption:=TDUI.label("%s · 库存 %.2f份 · ¥%.2f/份"%[_ingredient_name(id),float(profile.shop.available(id))/1000.0,float(profile.service.config.costs[id])/100.0],18)
		caption.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(caption)
		var amount:=SpinBox.new();amount.min_value=1;amount.max_value=30;amount.step=1;amount.value=1;row.add_child(amount)
		row.add_child(TDUI.button("购买",func()->void:
			var result:=profile.buy({id:int(amount.value)*1000});_outcome(result)
			if result.ok: caption.text="%s · 库存 %.2f份"%[_ingredient_name(id),float(profile.shop.available(id))/1000.0]))
	box.add_child(TDUI.button("资金困难 · 申请应急补助",func()->void:_outcome(profile.shop.claim_grant())))

func show_supplier() -> void:
	if not profile.at_boundary(): return
	var box:=_dialog("原料供货处")
	box.add_child(TDUI.label("预订货物通常次日送到。即时现货请到菜摊购买。",20,TDUI.ORANGE))
	for item: Dictionary in profile.world.catalog.supply_items:
		if not profile.service.config.costs.has(item.id): continue
		var row:=HBoxContainer.new();box.add_child(row)
		var caption:=TDUI.label("%s · ¥%d / 份"%[item.name,item.cost],18);caption.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(caption)
		row.add_child(TDUI.button("预订一份",func()->void:_outcome(profile.order_remote(item.id))))
	for order: Dictionary in profile.world.supply.incoming:
		box.add_child(TDUI.label("%s ×%d · 第%d天送到"%[_ingredient_name(order.item_id),order.amount,order.arrive],17,TDUI.MUTED))
	box.add_child(TDUI.button("领取已到货物",func()->void:_outcome(profile.receive_supplies())))

func _ingredient_name(id: String) -> String:
	for food: Dictionary in profile.service.cooking.data().ingredients:
		if food.id==id: return str(food.name)
	return id

func show_menu() -> void:
	var state:=profile.shop.snapshot()
	var box:=_dialog("今日菜单 · 营业牌")
	if state.phase in ["OPEN","DRAINING"]:
		box.add_child(TDUI.label("正在营业。打烊后可出门采购、研究菜谱和布置餐厅。",20))
		box.add_child(TDUI.button("提前打烊",func()->void:_outcome(profile.shop.close_early());_close_dialog()))
		return
	if state.phase=="SETTLED": box.add_child(TDUI.button("查看今日账本",show_ledger));return
	for id: String in state.menu:
		if not profile.shop.is_unlocked(profile.shop.family_id(id)): continue
		var row:=HBoxContainer.new();box.add_child(row)
		var enabled:=CheckBox.new();enabled.text=profile.shop.recipe_name(id);enabled.button_pressed=state.menu[id].enabled;enabled.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(enabled)
		var price:=SpinBox.new();price.min_value=.01;price.max_value=10000;price.step=.5;price.value=float(state.menu[id].price_cents)/100;price.prefix="¥ ";price.custom_minimum_size=Vector2(150,52);row.add_child(price)
		enabled.toggled.connect(func(value:bool)->void:_outcome(profile.shop.set_menu(id,value,roundi(price.value*100))))
		price.value_changed.connect(func(value:float)->void:_outcome(profile.shop.set_menu(id,enabled.button_pressed,roundi(value*100))))
		var stock:=TDUI.label("有料" if profile.shop.menu_available(id) else "缺料 / 售罄",17,TDUI.MUTED)
		stock.custom_minimum_size.x=125;stock.autowrap_mode=TextServer.AUTOWRAP_OFF;row.add_child(stock)
	box.add_child(TDUI.label("确认菜单和价格后开门。缺料菜自动停售，营业期间不能离店补货。",17,TDUI.MUTED))
	box.add_child(TDUI.button("确认菜单，开门营业",start_day))

func start_day() -> TDOutcome:
	var saved:=save_game()
	if not saved.ok: return _outcome(saved)
	var result:=profile.shop.open_day()
	if result.ok:
		kitchen_view._make_kitchen();kitchen_view.kitchen.auto_advance=automatic_time;kitchen_view.refresh(true)
		profile.world.day_phase="service"
		_close_dialog();_lock_controls(true)
	return _outcome(result)

func show_ledger() -> void:
	var box:=_dialog("食堂账本")
	var state:=profile.shop.snapshot()
	if state.phase=="SETTLED": kitchen_view._summary_page(box,profile.shop.day_summary())
	else: box.add_child(TDUI.label("第%d天 · 余额 ¥%.2f · 人气%d"%[state.day,float(state.money_cents)/100.0,state.popularity],21))
	for item: Dictionary in state.ledger.slice(maxi(0,state.ledger.size()-16)):
		box.add_child(TDUI.label("第%d天 · %s · %+.2f元"%[item.day,_ledger_name(item.kind),float(item.cents)/100.0],16,TDUI.MUTED))
	if profile.at_boundary(): box.add_child(TDUI.button("保存当前进度",func()->void:_outcome(save_game())))

func _ledger_name(id: String) -> String:
	return {"purchase":"采购","consumption":"食材消耗","prepayment":"菜款","tip":"小费","refund_cancel":"取消退款","refund_served":"退菜退款","settlement":"日结","emergency_grant":"应急补助","world_adjustment":"小镇支出 / 收入","supply_delivery":"预订原料到货"}.get(id,id)

func show_rest() -> void:
	var box:=_dialog("收工休息")
	if profile.shop.snapshot().phase!="SETTLED":
		box.add_child(TDUI.label("完成营业并打烊后，在这里休息到下一天。",20))
		return
	box.add_child(TDUI.label("今日进度将保存，明早可以去集市重新备货。",20))
	box.add_child(TDUI.button("休息到明天",func()->void:
		var saved:=save_game()
		if not saved.ok: _outcome(saved);return
		var result:=profile.next_day()
		if result.ok:
			kitchen_view._make_kitchen();kitchen_view.kitchen.auto_advance=automatic_time;kitchen_view.refresh(true)
			var morning_save:=save_game()
			if not morning_save.ok:
				show_pause();_message("已进入次日，但保存失败："+morning_save.code+"。请重试保存；上次日结存档仍保留。");return
			_close_dialog();travel("restaurant")
		else: _outcome(result)))

func save_game() -> TDOutcome:
	if profile==null: return TDOutcome.new(false,"NO_PROFILE")
	if restaurant!=null: profile.layout=restaurant.layout
	return profile.save()

func show_pause() -> void:
	if profile==null: return
	var box:=_dialog("暂停",true)
	box.add_child(TDUI.button("继续游戏",_close_dialog))
	var save:=TDUI.button("保存进度",func()->void:_outcome(save_game()));save.disabled=not profile.at_boundary();box.add_child(save)
	box.add_child(TDUI.button("设置",show_settings))
	box.add_child(TDUI.button("返回主菜单",request_title))
	box.add_child(TDUI.label("营业中退出将回到最近的筹备 / 日结存档。",16,TDUI.MUTED))

func show_settings() -> void:
	var box:=_dialog("设置",true)
	box.add_child(TDUI.label("主音量",20))
	var volume:=HSlider.new();volume.min_value=0;volume.max_value=1;volume.step=.05;volume.value=preferences.values.volume;volume.custom_minimum_size=Vector2(600,35);box.add_child(volume)
	var fullscreen:=CheckBox.new();fullscreen.text="全屏显示";fullscreen.button_pressed=preferences.values.fullscreen;box.add_child(fullscreen)
	box.add_child(TDUI.button("应用并保存",func()->void:_outcome(preferences.change(volume.value,fullscreen.button_pressed))))
	if profile!=null:
		box.add_child(TDUI.label("研习输入校准（毫秒）",20))
		var offset:=SpinBox.new();offset.min_value=-200;offset.max_value=200;offset.step=5;offset.value=profile.research.snapshot().input_offset_sec*1000;box.add_child(offset)
		box.add_child(TDUI.button("保存校准",func()->void:_outcome(profile.research.calibrate(offset.value/1000.0))))
	box.add_child(TDUI.label("WASD 移动 · E 交互 / 放取 · F 开灶 · Q 取锅料 · B 菜谱 · Esc 暂停",17,TDUI.MUTED))

func request_title() -> void:
	if profile==null: return
	if profile.at_boundary():
		var result:=save_game()
		if not result.ok: _outcome(result);return
		go_title();return
	var box:=_dialog("离开本次营业？",true)
	box.add_child(TDUI.label("未保存的订单、做菜和营业奖励会一同回退到最近边界存档。",20))
	box.add_child(TDUI.button("确认返回主菜单",go_title))

func request_quit() -> void:
	if profile==null: get_tree().quit();return
	var box:=_dialog("退出游戏",true)
	box.add_child(TDUI.label("营业中退出将回到最近边界存档。筹备或日结阶段会先保存。",20))
	box.add_child(TDUI.button("确认退出",func()->void:
		if profile.at_boundary():
			var result:=save_game()
			if not result.ok: _outcome(result);return
		get_tree().quit()))

func go_title() -> void:
	_close_dialog();_dispose_game();location="title";_hud.text="";_build_title()

func _dispose_game() -> void:
	close_atlas();_pause(false)
	for scene: Node in [town,restaurant,kitchen_view]:
		if is_instance_valid(scene): scene.close();remove_child(scene);scene.queue_free()
	town=null;restaurant=null;kitchen_view=null
	if profile!=null: profile.close();profile=null
	_generation+=1

func open_atlas() -> void:
	if profile==null or atlas!=null: return
	_prior_pause=get_tree().paused;_pause(true)
	for scene: Node in [town,restaurant,kitchen_view]: _freeze_branch(scene)
	get_tree().paused=false
	_atlas_layer=CanvasLayer.new();_atlas_layer.layer=600;add_child(_atlas_layer)
	atlas=TDRecipeAtlas.new();atlas.session=profile.research
	var identity:int=_generation
	atlas.begin_handler=func(id:String)->TDOutcome:
		if identity!=_generation: return TDOutcome.new(false,"STALE_PROFILE")
		if not profile.at_boundary(): return TDOutcome.new(false,"SHOP_OPEN","营业中只能查看，打烊后可研习。")
		return profile.research.begin(id,{"day":int(profile.shop.snapshot().day),"phase":"morning" if profile.shop.snapshot().phase=="PREPARE" else "evening","spent":profile.world.free_spent},24)
	atlas.back_requested.connect(close_atlas);atlas.pause_requested.connect(func()->void:get_tree().paused=not get_tree().paused;atlas.set_paused(get_tree().paused))
	_atlas_layer.add_child(atlas)

func _freeze_branch(node: Node) -> void:
	if not is_instance_valid(node): return
	_frozen.append({"node":node,"mode":node.process_mode});node.process_mode=Node.PROCESS_MODE_DISABLED
	for child: Node in node.get_children(): _freeze_branch(child)

func close_atlas() -> void:
	if atlas==null: return
	atlas.close();_atlas_layer.remove_child(atlas);atlas.queue_free();atlas=null
	remove_child(_atlas_layer);_atlas_layer.queue_free();_atlas_layer=null
	for entry: Dictionary in _frozen:
		if is_instance_valid(entry.node): entry.node.process_mode=entry.mode
	_frozen.clear();_pause(_prior_pause);_lock_controls(true)
	if kitchen_view!=null: kitchen_view.refresh(true)

func show_console() -> void:
	if atlas!=null: return
	var box:=_dialog("控制台",true)
	_console_output=TDUI.label("输入 debug 进入调试模式。" if not debug_enabled else "调试模式已开启。输入 help 查看命令。",18);box.add_child(_console_output)
	_console=LineEdit.new();_console.placeholder_text="输入命令";box.add_child(_console)
	_console.text_submitted.connect(func(command:String)->void:
		var result:=execute_command(command)
		if is_instance_valid(_console_output): _console_output.text=result
		if is_instance_valid(_console): _console.clear())
	_console.grab_focus()

func execute_command(command: String) -> String:
	var words:=command.strip_edges().split(" ",false)
	if words.is_empty(): return ""
	if command.strip_edges()=="debug": debug_enabled=true;return "调试模式已开启。help 查看命令。"
	if not debug_enabled: return "请先输入 debug。"
	if words[0]=="help": return "status 查看状态；san 0..100 修改SAN；tools 查看旧调试入口；debug_off 关闭调试"
	if words[0]=="debug_off": debug_enabled=false;return "调试模式已关闭。"
	if words[0]=="status": return "无活动存档" if profile==null else "%s · %s · 第%d天 · %s"%[profile.slot_id,location,profile.shop.snapshot().day,profile.shop.snapshot().phase]
	if words[0]=="san" and words.size()==2 and words[1].is_valid_int() and profile!=null:
		var value:=int(words[1])
		if value<0 or value>100: return "SAN范围为0至100。"
		profile.world.san=value;kitchen_view.day_san=value
		for lane: TDCookingLane in kitchen_view.kitchen.lanes+[kitchen_view.kitchen.prep]: lane.day_san=value
		return "SAN = %d（后续工序生效）"%value
	if words[0]=="tools":
		show_debug_tools();return "已打开调试工具。"
	return "未知命令，输入 help。"

func show_debug_tools() -> void:
	if not debug_enabled: return
	var box:=_dialog("调试工具 · 独立试验入口",true)
	box.add_child(TDUI.label("这些旧原型用于复现和检查，与当前存档分开。",18))
	for entry: String in ["厨房","营业","小镇","餐厅"]:
		box.add_child(TDUI.button(entry,func()->void:
			# Leave the real slot at a defined boundary; debug prototypes never own it.
			if profile!=null and not profile.at_boundary():
				_message("请先打烊再进入独立调试入口。");return
			if profile!=null:
				var saved:=save_game()
				if not saved.ok: _outcome(saved);return
			go_title();debug_entry_requested.emit(entry)))

func import_legacy() -> TDOutcome:
	var empty: String=""
	for row: Dictionary in slots.slots():
		if row.ok and slots.load_slot(row.slot_id).data.imported_legacy: return _outcome(TDOutcome.new(false,"ALREADY_IMPORTED","旧进度已导入一个存档位。"))
		if row.empty and empty.is_empty(): empty=row.slot_id
	if empty.is_empty(): return _outcome(TDOutcome.new(false,"NO_EMPTY_SLOT"))
	var next:=TDGameProfile.new()
	if not next.error.ok: next.close();return _outcome(next.error)
	next.slot_id=empty;next.title="旧食堂进度";next.imported_legacy=true
	TDGameProfile.install_legacy(next.service,next.world.catalog.dish_list().map(func(d:Dictionary)->String:return "phase3."+str(d.id)))
	var old_shop:=TDShopStore.new(legacy_shop_path,next.shop).load_game()
	var old_research:=TDResearchStore.new(legacy_research_path,next.research.validate_save).load_game()
	if not old_shop.ok and old_shop.code!="NOT_FOUND": next.close();return _outcome(old_shop)
	if not old_research.ok and old_research.code!="NOT_FOUND": next.close();return _outcome(old_research)
	if not old_shop.ok and not old_research.ok: next.close();return _outcome(TDOutcome.new(false,"NOT_FOUND","没有可导入的旧营业 / 研习存档。"))
	next.research.save_sink=Callable()
	if old_shop.ok: next.shop.restore(old_shop.data)
	if old_research.ok: next.research.restore(old_research.data)
	if old_shop.ok:
		var inherited:Array=[]
		for id: String in next.shop.snapshot().unlocked:
			var runtime:=next.world.catalog.dish_id_for_kitchen(id)
			if not runtime.is_empty(): inherited.append(runtime)
		next.research.inherit_legacy(inherited)
	next.research.save_sink=next._research_candidate
	next._sync_recipes();next.persistence=slots.save_slot
	var result:=next.save()
	if result.ok: _activate(next)
	else: next.close();_outcome(result)
	return result

func _outcome(result: TDOutcome) -> TDOutcome:
	_message(result.message if not result.message.is_empty() else ({"SAVED":"进度已保存。","PURCHASED":"已购入，食材已放入厨房库存。","OPENED":"开门营业！"}.get(result.code,result.code)))
	return result

func _exit_tree() -> void:
	if atlas!=null: atlas.close()
	if kitchen_view!=null: kitchen_view.close()
	if profile!=null: profile.close()
	if is_inside_tree(): get_tree().paused=false
