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
var cottage:TDCottageWorld
var music:TDGameMusic
var _rest_busy:bool=false
var _quitting:bool=false
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
	music=TDGameMusic.new();add_child(music)
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
	if _quitting: return
	if music!=null:
		var cooking:bool=kitchen_view!=null and kitchen_view.kitchen.music_audible()
		if atlas!=null and atlas.trial!=null and atlas.trial.lesson!=null: cooking=atlas.trial.lesson.kitchen.music_audible()
		music.select_context("silent" if cooking else ("service" if profile!=null and not profile.at_boundary() else "casual"),get_tree().paused)
	if profile==null: return
	if restaurant!=null and restaurant.layout!=null and profile.commerce!=null and profile.world!=null and profile.world.catalog!=null:
		profile.commerce.interior_effect=float(TDEconomyMath.decor_of(restaurant.layout.pieces(),profile.world.catalog.wildcards).effect)
	# Factory work follows the same paused active-game clock in every room.
	if automatic_time and atlas==null and not get_tree().paused: profile.world.tick_factories(_delta)
	var state:=profile.shop.snapshot()
	_hud.text="%s  ·  第 %d 天    ¥ %.2f    %s"%[profile.title,state.day,float(state.money_cents)/100.0,{"PREPARE":"筹备中","OPEN":"营业中","DRAINING":"等待最后的客人","SETTLED":"今日已打烊"}.get(state.phase,state.phase)]
	_hud.text+="    Lv.%d"%int(profile.progression.progress().level)
	if Time.get_ticks_msec()<_toast_until: _hud.text+= "  ·  "+_toast
	_hud_layer.visible=location!="kitchen" and atlas==null
	if town!=null: town.shop_open=state.phase in ["OPEN","DRAINING"]
	if restaurant!=null and town!=null:
		restaurant.caller_name=TDTownCaller.NAME
		if restaurant.caller_left:
			restaurant.caller_left=false
			town.finish_call()
		restaurant.caller_inside=town.caller_phase()=="dining"
	if state.phase!=_last_phase:
		_last_phase=state.phase
		profile.world.day=int(state.day)
		profile.world.day_phase="morning" if state.phase=="PREPARE" else ("evening" if state.phase=="SETTLED" else "service")
		if state.phase=="SETTLED":
			var result:=save_game()
			if not result.ok: _message("自动保存失败："+result.code)
			elif not profile.progression.snapshot().recent.is_empty():
				var growth: Dictionary=profile.progression.snapshot().recent.back()
				if int(growth.day)==int(state.day) and not growth.rewards.is_empty():
					if _modal==null and atlas==null: show_levels()
					else: _message("经营等级提升至 Lv.%d，灵感已到账，可在账本查看奖励。"%int(growth.level_after))

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree(): return
	if _entry_busy or _quitting:
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
	if cottage!=null:
		cottage.player.set_controls_enabled(value and location=="cottage")
		cottage.set_process_unhandled_input(value and location=="cottage")
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
	_activate(next,true)
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

func _activate(next: TDGameProfile,first_entry:bool=false) -> void:
	_close_dialog();_dispose_game();profile=next;_generation+=1
	_title_screen.hide();_last_phase=str(profile.shop.snapshot().phase)
	town=TDTownWorld.new();town.player_mode=true;town.session=profile.world
	town.transaction_sink=profile.world_transaction;town.external_factory_clock=true
	town.balance_reader=func()->int:return int(profile.shop.snapshot().money_cents)
	town.commercial_refresh=profile.sync_commercial_map
	town.restaurant_requested.connect(func()->void:travel("restaurant"));town.place_requested.connect(_place);town.pause_requested.connect(show_pause);add_child(town)
	restaurant=TDRestaurantWorld.new();restaurant.player_mode=true;restaurant.floor_service=true;restaurant.session=profile.world;restaurant.layout=profile.layout;restaurant.business=profile.shop
	restaurant.object_requested.connect(_object);restaurant.pause_requested.connect(show_pause);add_child(restaurant)
	cottage=TDCottageWorld.new();cottage.object_requested.connect(_object);add_child(cottage)
	kitchen_view=TDShopView.new();kitchen_view.embedded=true;kitchen_view.shop=profile.shop;kitchen_view.day_san=profile.world.san;kitchen_view.boundary_save=save_game
	kitchen_view.save_path=profile_root.path_join(profile.slot_id+"-runtime")
	kitchen_view.back_requested.connect(func()->void:travel("restaurant"));kitchen_view.pause_requested.connect(show_pause);add_child(kitchen_view)
	kitchen_view.kitchen.auto_advance=automatic_time
	travel("town" if first_entry else "cottage",not first_entry)

func travel(destination: String,at_bed:bool=false) -> TDOutcome:
	if profile==null or destination not in ["town","restaurant","kitchen","cottage"]: return TDOutcome.new(false,"INVALID_DESTINATION")
	if destination in ["town","cottage"] and not profile.can_leave_shop(): return _outcome(TDOutcome.new(false,"SHOP_OPEN","营业中不能离店，请先处理订单并打烊。"))
	if _modal!=null: _close_dialog()
	var previous_location:=location
	location=destination
	town.set_presented(destination=="town")
	cottage.set_presented(destination=="cottage",at_bed)
	restaurant.set_floor_cover(destination!="restaurant")
	kitchen_view.visible=destination=="kitchen"
	kitchen_view.kitchen.world.set_controls_enabled(destination=="kitchen")
	if destination=="town": town.spawn_at_plot("player_cottage" if previous_location=="cottage" else "player_diner")
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
		"hire": show_crew()
		"recipes": open_atlas()

func _place(kind: String, id: String) -> void:
	if kind=="cottage": travel("cottage")
	elif kind in ["commercial_street","bank"]: show_bank()
	elif kind=="competitor": show_competitor(id)
	elif kind=="market":
		profile.world.select_market(id);show_market()
	elif kind=="supply_factory":
		if town!=null:
			var plot:Dictionary=profile.world._plot_by_id(id)
			if not plot.is_empty():
				town._open_factory_panel(plot)
				return
		show_supplier()
	else:
		var box:=_dialog("街坊告示")
		var plot:Dictionary=profile.world._plot_by_id(id)
		if not plot.is_empty():
			profile.commerce.attach_map(profile.world.town_map.plots)
			var site:=profile.commerce.geography.cell(Vector2i(int(plot.x),int(plot.y)))
			var quote:=profile.commerce.geography.parcel_quote(id)
			box.add_child(TDUI.label("地块参考总价 ¥%.2f · 日租报价 ¥%.2f\n可见度 %.0f%% · 区位吸引力 %.0f%%\n报价不是当前租约；自有主店免现金房租。"%[float(quote.land_value_cents)/100,float(quote.rent_quote_cents_per_day)/100,100*float(site.visibility),100*float(site.attractiveness)],18))
		box.add_child(TDUI.label("这里是"+str(profile.world._plot_by_id(id).get("name","小镇街区"))+"。",22))
		if kind in ["factory_lot","supply_factory","diner_lot"]:
			box.add_child(TDUI.label("地块管理",20))
			if kind=="factory_lot": box.add_child(TDUI.button("建设原料厂",func()->void:_outcome(profile.world.build_factory(id))))
		elif not TDSanRules.recovery(kind).is_empty():
			var offer:=TDSanRules.recovery(kind)
			box.add_child(TDUI.label("歇歇脚 · %.0f小时 · %d元 · 精神恢复%d"%[offer.hours,offer.cost,offer.san],18))
			box.add_child(TDUI.button("在这里逛一逛",func()->void:_outcome(profile.world_transaction(profile.world.visit_zone.bind(kind),"visit:"+kind))))
		else: box.add_child(TDUI.label("走访街区，回店经营。",18,TDUI.MUTED))
		var pool:=int(plot.get("pool",0));var shift:=int(plot.get("budget_shift",0))
		if pool!=0 or shift!=0:
			box.add_child(TDUI.label("这个功能区计入客流：人数 %+d，预算 %+d。客人进店时仍会和竞品比较装修、价格和等待。"%[pool,shift],18))

func show_market() -> void:
	if not profile.can_leave_shop(): _outcome(TDOutcome.new(false,"SHOP_OPEN","营业中不能采购。"));return
	var box:=_dialog("街口菜摊 · 现货采购")
	if profile.shop.snapshot().phase=="SETTLED":
		box.add_child(TDUI.label("今天已经打烊。回店休息后，明早再来挑新鲜食材。",20));return
	var forecast:=profile.shop.visitor_forecast()
	box.add_child(TDUI.label("今日预计 %d—%d 位客人 · 买好食材后回店挂牌营业"%[forecast.min_visitors,forecast.max_visitors],20,TDUI.ORANGE))
	for id: String in profile.shop.spoiled_today():
		box.add_child(TDUI.label("今日过期：%s %.2f%s，已清理。"%[_ingredient_name(id),float(profile.shop.spoiled_today()[id])/1000,profile.shop.stock_info(id).unit],17,TDUI.ORANGE))
	for id: String in profile.shop.purchase_ids():
		var row:=HBoxContainer.new();box.add_child(row)
		row.add_child(TDIngredientIcon.make(id))
		var market:Dictionary=profile.commerce.state.markets[profile.commerce.state.home]
		var info:=profile.shop.stock_info(id)
		var caption:=TDUI.label(_market_caption(id),18)
		caption.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(caption)
		var amount:=SpinBox.new();amount.min_value=1;amount.max_value=30;amount.step=1;amount.value=1;row.add_child(amount)
		row.add_child(TDUI.button("购买",func()->void:
			var result:=profile.buy({id:int(amount.value)*1000});_outcome(result)
			if result.ok: caption.text=_market_caption(id)))
		row.tooltip_text="按%s购买，入库起保质%d天；冰箱显示余量和剩余天数。"%[info.unit,info.shelf_days]
	box.add_child(TDUI.button("资金困难 · 申请应急补助",func()->void:_outcome(profile.shop.claim_grant())))
	box.add_child(TDUI.button("查看跨镇商路与预订",show_supplier))

func _market_caption(id: String) -> String:
	var info:=profile.shop.stock_info(id)
	var market:Dictionary=profile.commerce.state.markets[profile.commerce.state.home]
	return "%s · 家中 %.2f%s · ¥%.2f/%s · 保质%d天"%[_ingredient_name(id),float(profile.shop.available(id))/1000,info.unit,float(market.price[id])/100,info.unit,info.shelf_days]

func show_supplier() -> void:
	if not profile.at_boundary(): return
	var box:=_dialog("跨镇商路 · 原料预订")
	box.add_child(TDUI.label("货款与运费下单时固定；有库存和运力限制，到货后进入厨房。",20,TDUI.ORANGE))
	for route: Dictionary in profile.commerce.routes():
		if route.town_id==profile.commerce.state.home: continue
		var title:=_town_name(route.town_id)
		if not route.open:
			box.add_child(TDUI.label("🔒 "+title+" · 等待商路推荐",18,TDUI.MUTED));continue
		box.add_child(TDUI.button("%s · %d天送达 · 运费¥%.2f/份"%[title,route.lead_days,float(route.freight_cents_per_portion)/100],func()->void:show_remote_market(route.town_id)))
	for order: Dictionary in profile.commerce.state.shipments:
		if not order.delivered: box.add_child(TDUI.label("来自%s · %.1f份 · 第%d天送到"%[_town_name(order.source),float(order.units)/1000,order.arrival_day],17,TDUI.MUTED))
	box.add_child(TDUI.button("领取已到货物",func()->void:_outcome(profile.receive_supplies())))

func _town_name(id: String) -> String:
	if profile.commerce.config.towns.has(id): return str(profile.commerce.config.towns[id].name)
	var town_data:Dictionary=profile.world.catalog.town(id)
	return str(town_data.get("nickname",id))

func show_remote_market(town_id: String) -> void:
	if town_id not in profile.commerce.state.routes: _outcome(TDOutcome.new(false,"ROUTE_LOCKED","尚未收到这条商路的推荐。"));return
	var box:=_dialog(_town_name(town_id)+" · 当日报价")
	var market:Dictionary=profile.commerce.state.markets[town_id]
	for id: String in profile.shop.purchase_ids():
		var row:=HBoxContainer.new();box.add_child(row)
		row.add_child(TDIngredientIcon.make(id))
		var info:=profile.shop.stock_info(id)
		var label:=TDUI.label("%s · 现货%.1f%s · 含运费¥%.2f/%s"%[_ingredient_name(id),float(market.stock[id])/1000,info.unit,float(int(market.price[id])+profile.commerce.freight(town_id))/100,info.unit],18)
		label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(label)
		var amount:=SpinBox.new();amount.min_value=1;amount.max_value=16;amount.value=1;row.add_child(amount)
		var token: String="remote-ui:%s:%d:%s"%[profile.shop.snapshot().run_id,profile.shop.snapshot().serial+1,id]
		var buy_button:=TDUI.button("预订",func()->void:
			var outcome:=profile.order_remote(id,town_id,int(amount.value)*1000,token)
			_outcome(outcome)
			if outcome.ok: show_remote_market(town_id))
		row.add_child(buy_button)
	box.add_child(TDUI.button("返回商路",show_supplier))

func _ingredient_name(id: String) -> String:
	for food: Dictionary in profile.service.cooking.data().ingredients:
		if food.id==id: return str(food.name)
	return id

func show_menu() -> void:
	profile.commerce.attach_map(profile.world.town_map.plots)
	var state:=profile.shop.snapshot()
	var box:=_dialog("今日菜单 · 营业牌")
	if state.phase in ["OPEN","DRAINING"]:
		box.add_child(TDUI.label("正在营业。打烊后可出门采购、研究菜谱和布置餐厅。",20))
		box.add_child(TDUI.button("提前打烊",func()->void:_outcome(profile.shop.close_early());_close_dialog()))
		return
	if state.phase=="SETTLED":
		box.add_child(TDUI.button("查看今日账本",show_ledger))
		box.add_child(TDUI.button("分店",show_branch))
		return
	box.add_child(TDUI.button("分店",show_branch))
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
	var demand:=TDUI.label("",18,TDUI.ORANGE);box.add_child(demand)
	var forecast_update:=func()->void:
		var estimated:=profile.shop.visitor_forecast()
		demand.text="备足材料时预计 %d—%d 位客人；预算、路程、排队和竞争会影响实际到店。"%[estimated.min_visitors,estimated.max_visitors]
		if estimated.has("excluded_budget_share") and float(estimated.excluded_budget_share)>0:
			demand.text+="\n目前没有约%.0f%%客群买得起的菜，可试着加入较低价菜品。"%(100*float(estimated.excluded_budget_share))
	forecast_update.call()
	for price_control: SpinBox in box.find_children("*","SpinBox",true,false): price_control.value_changed.connect(func(_v:float)->void:forecast_update.call())
	for check_control: CheckBox in box.find_children("*","CheckBox",true,false): check_control.toggled.connect(func(_v:bool)->void:forecast_update.call())
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
	var growth := profile.progression.progress()
	box.add_child(TDUI.button("经营等级 Lv.%d · 查看等级奖励"%int(growth.level),show_levels))
	box.add_child(TDUI.button("分店",show_branch))
	var state:=profile.shop.snapshot()
	if state.phase=="SETTLED": kitchen_view._summary_page(box,profile.shop.day_summary())
	else: box.add_child(TDUI.label("第%d天 · 余额 ¥%.2f · 人气%d"%[state.day,float(state.money_cents)/100.0,state.popularity],21))
	var economy:Dictionary=profile.commerce.state
	box.add_child(TDUI.label("未付费用 ¥%.2f · 店铺认知 %.0f%% · 品牌信任 %.0f%%"%[float(economy.debt_cents)/100,float(economy.awareness)*100,float(economy.brand)*100],19,TDUI.ORANGE))
	if not economy.books.is_empty():
		var report:Dictionary=economy.books.back()
		box.add_child(TDUI.label("第%d天：耗料成本 ¥%.2f · 水电 ¥%.2f · 房租 ¥%.2f\n经营利润 ¥%.2f（采购是现金换库存，不再次扣利润）\n全镇用餐机会%d · 考虑本店%d · 接待%d · 完成%d · 离开%d"%[report.day,float(report.consumed_cost_cents)/100,float(report.utilities_cents)/100,float(report.rent_cents)/100,float(report.profit_cents)/100,report.funnel.opportunities,report.funnel.considered,report.funnel.admitted,report.funnel.completed,report.funnel.abandoned],18))
	for group:Dictionary in profile.commerce.config.groups:
		box.add_child(TDUI.label("%s：味道%.0f / 服务%.0f / 划算%.0f"%[group.name,100*profile.commerce.reputation(group.id,"food"),100*profile.commerce.reputation(group.id,"service"),100*profile.commerce.reputation(group.id,"value")],17,TDUI.MUTED))
	for item: Dictionary in state.ledger.slice(maxi(0,state.ledger.size()-16)):
		box.add_child(TDUI.label("第%d天 · %s · %+.2f元"%[item.day,_ledger_name(item.kind),float(item.cents)/100.0],16,TDUI.MUTED))
	if profile.at_boundary(): box.add_child(TDUI.button("保存当前进度",func()->void:_outcome(save_game())))
	var account:=profile.commerce.society.bank.account("player")
	box.add_child(TDUI.label("钱庄存款 ¥%.2f · 贷款本金 ¥%.2f · 未付利息 ¥%.2f\n借还本金和存取款不计入经营利润。商业街钱庄可办理。"%[float(account.deposit_cents)/100,float(account.principal_cents)/100,float(account.interest_cents)/100],18))
	if not economy.books.is_empty():
		var last: Dictionary=economy.books.back()
		box.add_child(TDUI.label("利润税 ¥%.2f · 本日利息 ¥%.2f · 税前利润 ¥%.2f"%[float(last.get("tax_cents",0))/100,float(last.get("interest_cents",0))/100,float(last.get("profit_before_tax_cents",last.profit_cents))/100],18))
	var society: Dictionary=profile.commerce.society.state
	if not society.daily.is_empty(): box.add_child(TDUI.label("五镇家庭：工资 ¥%.2f · 外食 ¥%.2f · 基本生活 ¥%.2f\n未满足基本生活支出 ¥%.2f（没有暗中补款）"%[float(society.daily.wages_cents)/100,float(society.daily.dining_cents)/100,float(society.daily.necessities_cents)/100,float(society.daily.unmet_needs_cents)/100],17,TDUI.MUTED))
	box.add_child(TDUI.label("本镇公共账户 ¥%.2f · 工资税与利润税收入分别记账"%(float(society.public[economy.home])/100),17,TDUI.MUTED))

func show_levels() -> void:
	if profile==null: return
	var box := _dialog("经营等级 · 升级奖励")
	var view := TDLevelRewardsView.new()
	box.add_child(view);view.setup(profile.progression,int(profile.research.snapshot().points))
	if not profile.at_boundary(): box.add_child(TDUI.label("查阅期间营业继续；按 Esc 返回。",16,TDUI.MUTED))

func show_bank() -> void:
	if profile==null or not profile.at_boundary(): return
	var target:=profile
	var box:=_dialog("商业街钱庄")
	var bank:=profile.commerce.society.bank
	var account:=bank.account("player")
	box.add_child(TDUI.label("手头 ¥%.2f · 存款 ¥%.2f\n贷款本金 ¥%.2f · 应付利息 ¥%.2f"%[float(profile.shop.snapshot().money_cents)/100,float(account.deposit_cents)/100,float(account.principal_cents)/100,float(account.interest_cents)/100],22))
	box.add_child(TDUI.label("授信上限 ¥%.2f · 借款日息 %.2f%% · 存款日息最高 %.2f%%\n期限%d天；到期日结尽力偿还，逾期停新增贷款，仍可继续经营。"%[float(bank.config.loan_limit_cents)/100,float(bank.config.loan_daily_bps)/100,float(bank.config.deposit_daily_bps)/100,bank.config.term_days],18,TDUI.MUTED))
	if int(account.principal_cents)>0: box.add_child(TDUI.label("到期：第%d天%s"%[account.due_day," · 已逾期" if int(profile.shop.snapshot().day)>int(account.due_day) else ""],19,TDUI.ORANGE))
	var amount:=SpinBox.new();amount.min_value=.01;amount.max_value=10000;amount.step=.01;amount.value=100;amount.prefix="¥ ";amount.name="BankAmount";box.add_child(amount)
	for action: String in ["deposit","withdraw","borrow","repay"]:
		var labels: Dictionary={"deposit":"存入","withdraw":"取出","borrow":"借款","repay":"还款（先息后本）"}
		var token: String="bank:%s:%d:%s"%[profile.shop.snapshot().run_id,int(profile.shop.snapshot().serial)+1,action]
		box.add_child(TDUI.button(labels[action],func()->void:
			if profile!=target or not target._alive: return
			var result:=target.bank_action(action,roundi(amount.value*100),token)
			_outcome(result)
			if result.ok: show_bank()))
	box.add_child(TDUI.label("存取借还只在筹备或日结办理，随当前存档保存。利率是游戏内可调参数。",16,TDUI.MUTED))

func show_competitor(parcel_id: String) -> void:
	var box:=_dialog("街坊餐馆 · 经营告示")
	var economy:=profile.commerce
	var firms: Array=economy.state.competitors[economy.state.home]
	var selected:=firms.filter(func(f:Dictionary)->bool:return f.parcel_id==parcel_id)
	if selected.is_empty(): selected=firms
	for firm: Dictionary in selected:
		box.add_child(TDUI.label("%s · %s\n售价 ¥%.2f · 今日接待%d/%d · 在岗%d人\n最近经营利润 ¥%.2f · 现金 ¥%.2f"%[firm.name,"第%d天开业"%int(firm.open_day) if firm.status=="construction" else "营业中",float(firm.price_cents)/100,firm.served,firm.capacity,economy.society.staff(firm.id).size(),float(firm.last_profit_cents)/100,float(firm.cash_cents)/100],19))
	box.add_child(TDUI.label("商业街可交易商铺剩余%d处。竞争者按盈利、人员和资金决定投资，不增加全镇用餐机会。"%economy.expansion.candidates(economy.state.home).size(),17,TDUI.MUTED))
	var decor:=TDEconomyMath.decor_of(profile.layout.pieces(),profile.world.catalog.wildcards)
	box.add_child(TDUI.label("每个用餐机会只选择一次：比较本店菜单、这些竞品和在家吃饭。预算、菜价、路程、等待、品牌和装修一起决定。\n你的装修效果 %.0f（统一 %.0f，高端 %.0f）。到店后的改价不改已经生成的订单。"%[float(decor.effect),float(decor.unity),float(decor.luxury)],18))
	var stats:Dictionary=economy.state.day_stats
	if int(stats.get("opportunities",0))>0:
		box.add_child(TDUI.label("今日用餐机会 %d · 选本店 %d · 选竞品 %d · 在家或没买成 %d"%[int(stats.opportunities),int(stats.considered),int(stats.competitor),int(stats.outside)],18,TDUI.ORANGE))
	for event: Dictionary in economy.expansion.state.events:
		if event.town_id==economy.state.home: box.add_child(TDUI.label("第%d天买地建店 · 支出 ¥%.2f · 第%d天开业"%[event.day,float(event.cost_cents)/100,event.open_day],16,TDUI.MUTED))

func _ledger_name(id: String) -> String:
	return {"purchase":"采购","consumption":"食材消耗","prepayment":"菜款","tip":"小费","refund_cancel":"取消退款","refund_served":"退菜退款","settlement":"日结","emergency_grant":"应急补助","world_adjustment":"小镇支出 / 收入","supply_delivery":"预订原料到货","operating_payment":"水电税费 / 偿还欠费","bank_transfer":"钱庄存取 / 借还","wage":"雇员工资"}.get(id,id)

func show_crew() -> void:
	var crew := profile.layout.crew
	var box := _dialog("招工处")
	box.add_child(TDUI.label("厨师在后厨做菜，服务员在店里端菜。每类最多两人，同一种加成不叠加，按在岗者里较高的等级计算。完成一单，在岗的人各得1点经验，每4点升1级，最高5级。入职数值较低，升级后才提高。辞退后经验还在。日薪当场扣除，打烊后才能办理。",18,TDUI.MUTED))
	box.add_child(TDUI.label("迎宾、传菜和收银是店里的另外三个岗位。没雇的时候，进门、端菜和送客要你亲自做。雇了就由他们做。工资从同一本现金账扣，不重复收客人的钱。",18,TDUI.MUTED))
	if not crew.duty_line().is_empty():
		box.add_child(TDUI.label(crew.duty_line(),20,TDUI.ORANGE))
	for person: Dictionary in crew.roster():
		var row := HBoxContainer.new()
		box.add_child(row)
		var caption := TDUI.label("%s · %s · 日薪%d元\n%s" % [person.name, "厨师" if person.role=="cook" else "服务员", int(person.wage_yuan), person.blurb], 18)
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(caption)
		var person_id := String(person.id)
		if bool(person.hired):
			row.add_child(TDUI.button("辞退", _dismiss_crew.bind(person_id)))
		else:
			var button := TDUI.button("雇佣", _hire_crew.bind(person_id))
			button.disabled = not profile.at_boundary()
			row.add_child(button)
	for role: String in ["greeter", "cashier", "runner"]:
		var floor := HBoxContainer.new()
		box.add_child(floor)
		var title := str(TDPhase3Session.ROLE_TITLE.get(role, role))
		var wage := profile.world.catalog.wage_of(role)
		var hired := profile.world.staff_on(role)
		var caption := TDUI.label("%s · 日薪%d元\n%s" % [title, wage, "已经在岗" if hired else "没雇时要你亲自做这一岗"], 18)
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		floor.add_child(caption)
		var role_id := role
		if hired:
			var dismiss := TDUI.button("辞退", _dismiss_floor.bind(role_id))
			dismiss.disabled = not profile.at_boundary()
			floor.add_child(dismiss)
		else:
			var hire := TDUI.button("雇佣", _hire_floor.bind(role_id))
			hire.disabled = not profile.at_boundary()
			floor.add_child(hire)

func _hire_crew(id: String) -> void:
	if profile == null or not profile.at_boundary():
		_outcome(TDOutcome.new(false, "SHOP_OPEN", "打烊后才能雇人。"))
		return
	var check := profile.layout.crew.can_hire(id)
	if not check.ok:
		_outcome(check)
		return
	var wage := int(profile.layout.crew.person(id).wage_yuan) * 100
	var paid := profile.shop.pay_wage(wage, "crew:%s:%d" % [id, int(profile.shop.snapshot().day)])
	if not paid.ok:
		_outcome(paid)
		show_crew()
		return
	var hired := profile.layout.crew.hire(id)
	var saved := save_game()
	_outcome(hired if saved.ok else saved)
	show_crew()

func _dismiss_crew(id: String) -> void:
	if profile == null or not profile.at_boundary():
		_outcome(TDOutcome.new(false, "SHOP_OPEN", "打烊后才能辞退。"))
		return
	var result := profile.layout.crew.dismiss(id)
	var saved := save_game()
	_outcome(result if saved.ok else saved)
	show_crew()

func _hire_floor(role: String) -> void:
	if profile == null or not profile.at_boundary():
		_outcome(TDOutcome.new(false, "SHOP_OPEN", "打烊后才能雇人。"))
		return
	var title := str(TDPhase3Session.ROLE_TITLE.get(role, role))
	var result := profile.world_transaction(func() -> TDOutcome: return profile.world.employ(role), "雇" + title)
	if result.ok and role in ["greeter", "cashier"]:
		profile.layout.set_staff(role, true)
	if result.ok:
		var saved := save_game()
		if not saved.ok:
			result = saved
	_outcome(result)
	show_crew()

func _dismiss_floor(role: String) -> void:
	if profile == null or not profile.at_boundary():
		_outcome(TDOutcome.new(false, "SHOP_OPEN", "打烊后才能辞退。"))
		return
	var title := str(TDPhase3Session.ROLE_TITLE.get(role, role))
	var result := profile.world_transaction(func() -> TDOutcome: return profile.world.dismiss(role), "辞退" + title)
	if result.ok and role in ["greeter", "cashier"]:
		profile.layout.set_staff(role, false)
	if result.ok:
		var saved := save_game()
		if not saved.ok:
			result = saved
	_outcome(result)
	show_crew()

func show_branch() -> void:
	if profile == null:
		return
	var box := _dialog("分店")
	var world := profile.world
	box.add_child(TDUI.label("同时只开一家，开在别的小镇，主店这张地图不动。钱和已会的菜谱共用，菜单、员工和原料分开。划地 %d 元。打烊结算时，有店长、会做菜单的主厨和原料，才有营业额；维护费照扣。这笔钱进同一本现金账，不另算经营等级。" % TDPhase3Session.CLAIM_FEE, 18, TDUI.MUTED))
	if not profile.at_boundary():
		box.add_child(TDUI.label("打烊后才能划地、雇人和进货。", 20))
		return
	if not world.branch_open:
		for town: Dictionary in world.catalog.playable_towns():
			if str(town.get("id", "")) == world.home_town_id:
				continue
			var town_id := str(town.get("id", ""))
			var title := "%s · %s" % [str(town.get("real", town_id)), str(town.get("nickname", ""))]
			box.add_child(TDUI.button("在%s开小店" % title, _open_branch.bind(town_id)))
		return
	var place := world.catalog.town(world.branch_town)
	box.add_child(TDUI.label("分店在%s。地图 %d×%d。" % [str(place.get("real", world.branch_town)), world.branch_w, world.branch_h], 20))
	for entry: Dictionary in world.branch_menu:
		var snap: Dictionary = entry.get("snapshot", {})
		box.add_child(TDUI.label("菜单 · %s · %d元" % [str(snap.get("name", entry.get("dish_id", ""))), int(entry.get("price", 0))], 18))
		var dish_id := str(entry.get("dish_id", ""))
		box.add_child(TDUI.button("教会主厨做" + str(snap.get("name", dish_id)), _teach_branch.bind(dish_id)))
	if not world.branch_menu.is_empty():
		var lead_entry: Dictionary = world.branch_menu[0]
		var lead: Dictionary = lead_entry.get("snapshot", {})
		box.add_child(TDUI.button("进一份原料 · %d元" % maxi(1, int(lead.get("ingredient_cost", 1))), _stock_branch))
	for role: String in TDPhase3Session.ROLES:
		var hired := bool(world.branch_staff.get(role, false))
		var role_id := role
		var row := HBoxContainer.new()
		box.add_child(row)
		row.add_child(TDUI.label("%s · 日薪%d元 · %s" % [str(TDPhase3Session.ROLE_TITLE.get(role, role)), world.catalog.wage_of(role), "在岗" if hired else "空缺"], 18))
		if hired:
			row.add_child(TDUI.button("辞退", _dismiss_branch.bind(role_id)))
		else:
			row.add_child(TDUI.button("雇佣", _hire_branch.bind(role_id)))
	if profile.shop.snapshot().phase == "SETTLED" and not world.branch_settled.has(str(profile.shop.snapshot().day)):
		box.add_child(TDUI.button("结算今天的分店", _settle_branch_now))
	box.add_child(TDUI.button("关掉分店", _close_branch_ui))

func _open_branch(town_id: String) -> void:
	var result := profile.world_transaction(func() -> TDOutcome: return profile.world.open_branch_in_town(town_id), "开分店")
	if result.ok:
		if profile.residence.get("plot") is Dictionary:
			profile.world.town_map.install_cottage(profile.residence.plot)
		profile.sync_commercial_map()
		profile.world.map_revision += 1
		var saved := save_game()
		if not saved.ok:
			result = saved
	_outcome(result)
	show_branch()

func _hire_branch(role: String) -> void:
	var title := str(TDPhase3Session.ROLE_TITLE.get(role, role))
	var result := profile.world_transaction(func() -> TDOutcome: return profile.world.employ(role, "branch"), "分店" + title)
	_keep_branch(result)

func _dismiss_branch(role: String) -> void:
	var title := str(TDPhase3Session.ROLE_TITLE.get(role, role))
	var result := profile.world_transaction(func() -> TDOutcome: return profile.world.dismiss(role, "branch"), "分店辞退" + title)
	_keep_branch(result)

func _teach_branch(dish_id: String) -> void:
	var result := profile.world_transaction(func() -> TDOutcome: return profile.world.teach_chef("branch", dish_id), "分店主厨")
	_keep_branch(result)

func _stock_branch() -> void:
	var result := profile.world_transaction(func() -> TDOutcome: return profile.world.buy_branch_portion(), "分店进货")
	_keep_branch(result)

func _settle_branch_now() -> void:
	var result := profile.close_branch_books()
	_keep_branch(result)

func _close_branch_ui() -> void:
	var result := profile.world_transaction(func() -> TDOutcome: return profile.world.close_branch(), "关掉分店")
	_keep_branch(result)

func _keep_branch(result: TDOutcome) -> void:
	if result.ok:
		var saved := save_game()
		if not saved.ok:
			result = saved
	_outcome(result)
	show_branch()

func show_rest() -> void:
	if profile==null or location!="cottage": return
	var box:=_dialog("小屋 · 床")
	if profile.shop.snapshot().phase!="SETTLED":
		box.add_child(TDUI.label("完成营业并打烊后，可以休息到下一天。读档会回到床边。",20))
		if profile.at_boundary(): box.add_child(TDUI.button("保存进度",func()->void:_outcome(save_game())))
		return
	box.add_child(TDUI.label("今日进度将保存，明早可以去集市重新备货。",20))
	var owner:=profile;var day:=int(profile.shop.snapshot().day)
	box.add_child(TDUI.button("休息到明天",func()->void:
		if _rest_busy or profile!=owner or int(owner.shop.snapshot().day)!=day or owner.shop.snapshot().phase!="SETTLED": return
		_rest_busy=true
		var saved:=save_game()
		if not saved.ok: _rest_busy=false;_outcome(saved);return
		var result:=profile.next_day()
		if result.ok:
			kitchen_view._make_kitchen();kitchen_view.kitchen.auto_advance=automatic_time;kitchen_view.refresh(true)
			var morning_save:=save_game()
			_rest_busy=false
			if not morning_save.ok:
				show_pause();_message("已进入次日，但保存失败："+morning_save.code+"。请重试保存；上次日结存档仍保留。");return
			_close_dialog();travel("cottage",true)
		else: _rest_busy=false;_outcome(result)))

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
	if _quitting: return
	if profile==null: _finish_quit();return
	var box:=_dialog("退出游戏",true)
	box.add_child(TDUI.label("营业中退出将回到最近边界存档。筹备或日结阶段会先保存。",20))
	box.add_child(TDUI.button("确认退出",func()->void:
		if profile.at_boundary():
			var result:=save_game()
			if not result.ok: _outcome(result);return
		_finish_quit()))

func _finish_quit() -> void:
	if _quitting: return
	_quitting=true
	_close_dialog();_dispose_game()
	if music!=null: music.shutdown()
	# Let the audio server retire stopped playback before the engine is destroyed.
	await get_tree().create_timer(.15,true,false,true).timeout
	get_tree().quit()

func go_title() -> void:
	_close_dialog();_dispose_game();location="title";_hud.text="";_build_title()

func _dispose_game() -> void:
	close_atlas();_pause(false)
	for scene: Node in [town,restaurant,kitchen_view,cottage]:
		if is_instance_valid(scene): scene.close();remove_child(scene);scene.queue_free()
	town=null;restaurant=null;kitchen_view=null;cottage=null;_rest_busy=false
	if profile!=null: profile.close();profile=null
	_generation+=1

func open_atlas() -> void:
	if profile==null or atlas!=null: return
	_prior_pause=get_tree().paused;_pause(true)
	for scene: Node in [town,restaurant,kitchen_view,cottage]: _freeze_branch(scene)
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
	if old_shop.ok: next.initialize_legacy_commerce()
	next.initialize_progression(true)
	var home_result:=next.initialize_residence()
	if not home_result.ok: next.close();return _outcome(home_result)
	next._sync_recipes();next.persistence=slots.save_slot
	var result:=next.save()
	if result.ok: _activate(next)
	else: next.close();_outcome(result)
	return result

func _outcome(result: TDOutcome) -> TDOutcome:
	_message(result.message if not result.message.is_empty() else ({"SAVED":"进度已保存。","PURCHASED":"已购入，食材已放入厨房库存。","OPENED":"开门营业！","BANK_RECORDED":"已办理，金额记入当前存档的钱庄账户。","INSUFFICIENT_FUNDS":"手头现金不足，本次没有扣款。","INSUFFICIENT_DEPOSIT":"存款余额不足。","CREDIT_LIMIT":"超过当前贷款额度。","BANK_LIQUIDITY":"钱庄当前可用资金不足，请减少金额或之后再来。","EXCEEDS_LOAN":"还款金额超过本金和应付利息之和。","DUPLICATE":"这笔操作已经办理，不会重复扣款。","INVALID_BANK_REQUEST":"请输入有效金额。"}.get(result.code,result.code)))
	return result

func _exit_tree() -> void:
	if atlas!=null: atlas.close()
	if kitchen_view!=null: kitchen_view.close()
	if profile!=null: profile.close()
	if is_inside_tree(): get_tree().paused=false
