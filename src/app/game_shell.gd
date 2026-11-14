class_name TDGameShell
extends Control
## Presentation and dependency assembly. Economy remains in the existing shop model.
signal debug_entry_requested(entry: String)
const TITLE_ART := preload("res://assets/redraw-v1/title.png")
var profile_root: String="user://profiles"
var preferences_path: String="user://player-settings.json"
var legacy_shop_path: String="user://shop-v1.json"
var legacy_research_path: String="user://research-v1.json"
var guide: TDStoryGuide
var profile: TDGameProfile
var slots: TDProfileStore
var preferences: TDPlayerPreferences
var town: TDTownWorld
var branch_visit: TDBranchInterior
var _branch_return: Vector2=Vector2.ZERO
var visiting: TDTravelWorld
var visiting_town: String="chengdu"
var _map_open: bool=false
var restaurant: TDRestaurantWorld
var cottage:TDCottageWorld
var music:TDGameMusic
var _rest_busy:bool=false
var _quitting:bool=false
var _story_pay_note: String = ""
var kitchen_view: TDShopView
var atlas: TDRecipeAtlas
var location: String="title"
var debug_enabled: bool=false
var automatic_time: bool=true
var _title_screen: Control
var _hud: TDGameHUD
var _management_action: String=""
var _hud_layer: CanvasLayer
var _modal: CanvasLayer
var _modal_box: VBoxContainer
var _notice: Label
var _console: LineEdit
var _console_output: RichTextLabel
var _console_lines: PackedStringArray=[]
var _command_history: PackedStringArray=[]
var _history_cursor: int=0
var _history_draft: String=""
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
var _night_closing: bool=false
var _story_frozen: bool=false

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	theme=TDUI.theme()
	slots=TDProfileStore.new(profile_root,TDGameProfile.validate_save)
	preferences=TDPlayerPreferences.new(preferences_path)
	preferences.apply()
	music=TDGameMusic.new();add_child(music)
	_build_title()
	_hud_layer=CanvasLayer.new();_hud_layer.layer=20;add_child(_hud_layer)
	_hud_layer.visible=false
	_hud=TDGameHUD.new();_hud_layer.add_child(_hud)
	_hud.action_requested.connect(_open_management)

func _build_title() -> void:
	if is_instance_valid(_hud_layer): _hud_layer.visible=false
	if is_instance_valid(_title_screen): _title_screen.queue_free()
	_title_screen=Control.new();_title_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(_title_screen)
	var art:=TextureRect.new();art.texture=TITLE_ART;art.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;art.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED;art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);art.mouse_filter=Control.MOUSE_FILTER_IGNORE;_title_screen.add_child(art)
	var shade:=Panel.new();shade.add_theme_stylebox_override("panel",TDUI.wood());shade.position=Vector2(40,60);shade.size=Vector2(360,670);shade.mouse_filter=Control.MOUSE_FILTER_IGNORE;_title_screen.add_child(shade)
	var column:=VBoxContainer.new();column.position=Vector2(76,108);column.size=Vector2(288,560);column.add_theme_constant_override("separation",18);_title_screen.add_child(column)
	column.add_child(TDUI.label("小 镇 食 堂",48,TDUI.INK))
	column.add_child(TDUI.label("一餐烟火，一日小镇",TDUI.FONT_BODY,TDUI.MUTED))
	var space:=Control.new();space.custom_minimum_size.y=28;column.add_child(space)
	column.add_child(TDUI.button("开始游戏",start_game))
	var resume:=TDUI.button("继续游戏",continue_game);resume.disabled=slots.latest().is_empty();column.add_child(resume)
	column.add_child(TDUI.button("载入存档",func()->void:show_slots(false)))
	column.add_child(TDUI.button("设置",show_settings))
	column.add_child(TDUI.button("退出游戏",request_quit))
	column.add_child(TDUI.label("WASD 移动 · Shift 疾跑  ·  E 交互",TDUI.FONT_CAPTION,Color("b7c6b8")))
	_title_notice=TDUI.label("",TDUI.FONT_BODY,TDUI.INK);_title_notice.position=Vector2(440,660);_title_notice.size=Vector2(780,100)
	_title_notice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_title_screen.add_child(_title_notice)

func _process(_delta: float) -> void:
	if _quitting: return
	var story_frozen:=profile!=null and town!=null and town.story_dialogue_open()
	if story_frozen!=_story_frozen:
		_story_frozen=story_frozen
		if kitchen_view!=null: kitchen_view.set_paused(_story_frozen or get_tree().paused)
		if restaurant!=null: restaurant.story_frozen=_story_frozen
	if music!=null:
		var cooking:bool=kitchen_view!=null and kitchen_view.kitchen.music_audible()
		if atlas!=null and atlas.trial!=null and atlas.trial.lesson!=null: cooking=atlas.trial.lesson.kitchen.music_audible()
		var opening_film: bool=guide!=null and guide.presenting() and guide.dialogue.talk.context.get("scene")=="intro"
		music.select_context("silent" if cooking else ("service" if profile!=null and not profile.at_boundary() else "casual"),get_tree().paused or (_story_frozen and not opening_film) or (opening_film and guide.dialogue.presentation_paused))
	if profile==null: return
	if restaurant!=null and restaurant.layout!=null and profile.commerce!=null and profile.world!=null and profile.world.catalog!=null:
		profile.commerce.interior_effect=float(TDEconomyMath.decor_of(restaurant.layout.pieces(),profile.world.catalog.wildcards).effect)
	# Kitchen emits the single monotonic active-game time, even when its room is hidden.
	var minute: float=profile.characters.clock.minute
	if town!=null: town.set_day_minute(minute)
	if visiting!=null: visiting.set_day_minute(minute)
	if branch_visit!=null: branch_visit.set_day_minute(minute)
	if kitchen_view!=null: kitchen_view.staff_away=location in ["town","voyage","cottage","branch"]
	if cottage!=null: cottage.set_day_minute(minute)
	if restaurant!=null and restaurant._iso!=null: restaurant._iso.set_day_minute(minute)
	if kitchen_view!=null and kitchen_view.kitchen!=null: kitchen_view.kitchen.world.set_day_minute(minute)
	var state:=profile.shop.snapshot()
	_hud.update_profile(profile,state)
	_hud.set_toast(_toast if Time.get_ticks_msec()<_toast_until else "")
	_hud.set_menu_enabled(not _menu_blocked())
	if kitchen_view!=null: kitchen_view.day_clock_label.text=profile.characters.clock.label()+" · 全天时间"
	_hud_layer.visible=atlas==null and not (guide!=null and guide.presenting()) and not (location=="kitchen" and kitchen_view.kitchen.stage.visible)

	if town!=null:
		town.shop_open=state.phase in ["OPEN","DRAINING"]
		town.chapter_ready=state.phase=="SETTLED" or int(state.day)>=2
		_fill_story_board(state)
	_story_purse()
	_story_supplies()
	profile.characters.observe_orders(state.orders)
	if state.phase!=_last_phase:
		_last_phase=state.phase
		profile.world.day=int(state.day)
		profile.world.day_phase="morning" if state.phase=="PREPARE" else ("evening" if state.phase=="SETTLED" else "service")
		if profile.story!=null and profile.story.started():
			if state.phase in ["OPEN","DRAINING"]: profile.story.note_opened()
			elif state.phase=="SETTLED": profile.story.note_served()
		if state.phase=="SETTLED":
			var result:=profile.settle_progression()
			if not result.ok: _message("日结等级结算失败："+result.code)
			elif not profile.progression.snapshot().recent.is_empty():
				var growth: Dictionary=profile.progression.snapshot().recent.back()
				if int(growth.day)==int(state.day) and not growth.rewards.is_empty():
					if _modal==null and atlas==null: show_levels()
					else: _message("经营等级提升至 Lv.%d，灵感已到账，可在账本查看奖励。"%int(growth.level_after))
			if town!=null: town.show_quest()

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree(): return
	if _entry_busy or _quitting:
		get_viewport().set_input_as_handled();return
	if event.is_action_pressed("debug_console") and not event.is_echo():
		if _console!=null: _close_dialog()
		else: show_console()
		get_viewport().set_input_as_handled();return
	# Esc closes a modal even while its text field owns keyboard focus.
	if event.is_action_pressed("pause") and not event.is_echo() and _modal!=null:
		_close_dialog();get_viewport().set_input_as_handled();return
	if guide!=null and guide.presenting():
		if event.is_action_pressed("pause") and not event.is_echo(): guide.dialogue.toggle_presentation_pause()
		if event.is_action_pressed("pause") or event.is_action_pressed("recipe_book") or event.is_action_pressed("quest_journal"): get_viewport().set_input_as_handled()
		return
	var focus:=get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit: return
	var shortcuts: Dictionary={"employees_menu":"employees","recipe_book":"recipes","quest_journal":"quests","world_map":"map","branches_menu":"branches","suppliers_menu":"suppliers","relationships_menu":"relationships"}
	for action: String in shortcuts:
		if event.is_action_pressed(action) and not event.is_echo() and profile!=null:
			_open_management(str(shortcuts[action]));get_viewport().set_input_as_handled();return
	if guide!=null and event.is_action_pressed("quest_track") and not event.is_echo() and _modal==null and atlas==null:
		profile.story.tracked=not profile.story.tracked;get_viewport().set_input_as_handled();return

	if event.is_action_pressed("pause") and not event.is_echo():
		if _modal!=null: _close_dialog()
		elif atlas!=null:
			if atlas.trial==null: close_atlas()
			else: atlas.set_paused(not get_tree().paused);get_tree().paused=not get_tree().paused
		elif profile!=null: show_pause()
		get_viewport().set_input_as_handled()

func _menu_blocked() -> bool:
	return profile==null or _entry_busy or _quitting or (guide!=null and guide.presenting()) or (kitchen_view!=null and kitchen_view.kitchen.stage.visible) or (atlas!=null and atlas.trial!=null)

func _open_management(id: String) -> void:
	if _menu_blocked(): return
	if id=="recipes" and atlas!=null: close_atlas();return
	if _modal!=null and _management_action==id: _close_dialog();return
	if atlas!=null: close_atlas()
	if _modal!=null: _close_dialog()
	match id:
		"employees": show_crew()
		"recipes": open_atlas()
		"quests":
			if guide!=null: guide.show_journal()
		"map": show_world_map()
		"branches": show_branch()
		"suppliers": show_supplier()
		"relationships": show_relationships()
	_management_action=id

func _management_panel(title: String, panel: VBoxContainer) -> void:
	var box:=_dialog(title,true)
	_notice.hide()
	box.add_child(panel);panel.call("configure",profile)
	panel.connect("notice",_message)
	panel.connect("changed",func()->void:
		profile.employees.sync_main_crew()
		if kitchen_view!=null: kitchen_view.refresh(true))

func show_relationships() -> void:
	_management_panel("街坊 · 相识的人",TDManagementPanels.RelationshipPanel.new())

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
	var heading:=TDUI.label(title,TDUI.FONT_DISPLAY,TDUI.ORANGE);heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL;top.add_child(heading)
	top.add_child(TDUI.button("返回",_close_dialog))
	_notice=TDUI.label("",TDUI.FONT_BODY,TDUI.ORANGE);_modal_box.add_child(_notice)
	return _modal_box

func _message(text: String) -> void:
	if is_instance_valid(_notice): _notice.text=text
	elif is_instance_valid(_title_notice) and _title_screen.visible: _title_notice.text=text
	else: _toast=text;_toast_until=Time.get_ticks_msec()+4000

func _close_dialog() -> void:
	_management_action=""
	_map_open=false
	if is_instance_valid(_modal):
		remove_child(_modal);_modal.queue_free();_modal=null
		_pause(_prior_pause)
	_console=null;_console_output=null;_notice=null
	_lock_controls(true)

func _lock_controls(value: bool) -> void:
	value=value and not (guide!=null and guide.presenting())
	if branch_visit!=null: branch_visit.set_controls_enabled(value and location=="branch")
	if visiting!=null:
		visiting.player.set_controls_enabled(value and location=="voyage")
		visiting.set_process_unhandled_input(value and location=="voyage")
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
		var label:=TDUI.label("%d · "%[int(row.slot_id.trim_prefix("slot-"))]+("空存档" if row.empty else ("%s · 第%d天 · ¥%.2f · 已学%d道菜"%[row.title,row.day,float(row.money_cents)/100.0,row.unlocked] if row.ok else "存档不可读取："+str(row.code))),TDUI.FONT_BODY)
		label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;line.add_child(label)
		var id:String=row.slot_id
		if new_game and row.empty: line.add_child(TDUI.button("从这里开始",func()->void:_enter_game(create_game.bind(id,name_input.text),"正在创建新生活……")))
		elif not new_game and row.ok: line.add_child(TDUI.button("载入",func()->void:_enter_game(load_game.bind(id),"正在载入存档……")))
		elif not row.ok and not row.empty and row.code!="UNSUPPORTED_VERSION":
			if row.get("backup_available",false): line.add_child(TDUI.button("恢复备份",func()->void:_recover_slot(id,false)))
			if row.get("temporary_available",false): line.add_child(TDUI.button("恢复完整临时档",func()->void:_recover_slot(id,true)))
		if not new_game and not row.empty: line.add_child(TDUI.button("删除",_confirm_delete_slot.bind(id)))
	if new_game: box.add_child(TDUI.button("导入旧进度（原文件保留）",func()->void:_enter_game(import_legacy,"正在导入旧进度……")))
	box.add_child(TDUI.label("每个存档独立保存经营、菜谱、餐厅与小镇。营业期间不保存做菜现场。",TDUI.FONT_CAPTION,TDUI.MUTED))

func _confirm_delete_slot(id: String) -> void:
	if profile!=null or _entry_busy or not slots.valid_id(id): return
	var row: Dictionary={}
	for item: Dictionary in slots.slots():
		if item.slot_id==id: row=item
	if row.is_empty() or row.empty: return
	var box:=_dialog("删除存档？",true)
	box.add_child(TDUI.label(("%s · 第%d天"%[row.title,row.day]) if row.ok else id+" · 无法读取的存档",TDUI.FONT_SECTION))
	box.add_child(TDUI.label("这个存档将从载入列表移除，腾出新游戏的位置。原文件会保留在本机删除归档中。",TDUI.FONT_BODY))
	box.add_child(TDUI.button("取消",func()->void:show_slots(false)))
	box.add_child(TDUI.button("确认删除",func()->void:
		if profile!=null or _entry_busy: return
		_entry_busy=true
		var result:=slots.archive_slot(id)
		_entry_busy=false
		show_slots(false);_outcome(result)))

func start_game() -> void:
	if _entry_busy: return
	for row: Dictionary in slots.slots():
		if row.empty:
			_enter_game(create_game.bind(String(row.slot_id),"小镇食堂"),"正在创建新生活……");return
	_outcome(TDOutcome.new(false,"NO_EMPTY_SLOT","六个存档位已满。请在“载入存档”中删除不需要的存档，再开始新游戏。"))

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
	next.story.begin()
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
	if next.map_migrated_on_load or next.region_migrated_on_load:
		var backup:=slots.backup_map_migration(id,next.region_migrated_on_load)
		if not backup.ok: next.close();return _outcome(backup)
		var migrated_save:=next.save()
		if not migrated_save.ok: next.close();return _outcome(migrated_save)
	_activate(next)
	if next.map_migrated_on_load or next.region_migrated_on_load: _message(result.message+"原档已留迁移前备份。")
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
	visiting_town=str(profile.commerce.state.home)
	_story_supply_checked=false
	_story_frozen=false;_night_closing=false
	_title_screen.hide();_last_phase=str(profile.shop.snapshot().phase)
	town=TDTownWorld.new();town.player_mode=true;town.session=profile.world
	town.transaction_sink=profile.world_transaction;town.external_factory_clock=true;town.management_menus=true
	town.balance_reader=func()->int:return int(profile.shop.snapshot().money_cents)
	town.commercial_refresh=profile.sync_commercial_map
	town.hero_name=profile.title;town.story=profile.story;town.story_effect.connect(_apply_story)
	town.characters=profile.characters;town.homecoming=profile.residence
	town.restaurant_requested.connect(func()->void:travel("restaurant"));town.place_requested.connect(_place);town.pause_requested.connect(show_pause);add_child(town)
	restaurant=TDRestaurantWorld.new();restaurant.player_mode=true;restaurant.floor_service=true;restaurant.session=profile.world;restaurant.layout=profile.layout;restaurant.business=profile.shop
	restaurant.characters=profile.characters
	restaurant.object_requested.connect(_object);restaurant.pause_requested.connect(show_pause);add_child(restaurant)
	restaurant.bind_dining_clock()
	restaurant.restore_visit_boundary()
	cottage=TDCottageWorld.new();cottage.object_requested.connect(_object);add_child(cottage)
	kitchen_view=TDShopView.new();kitchen_view.embedded=true;kitchen_view.shop=profile.shop;kitchen_view.day_san=profile.world.san;kitchen_view.boundary_save=save_game
	kitchen_view.save_path=profile_root.path_join(profile.slot_id+"-runtime")
	kitchen_view.back_requested.connect(func()->void:travel("restaurant"));kitchen_view.pause_requested.connect(show_pause);add_child(kitchen_view)
	kitchen_view.kitchen.auto_advance=automatic_time
	kitchen_view.active_time_advanced.connect(_on_active_time)
	kitchen_view.external_time_boundary=_world_time_boundary
	profile.kitchen_checkpoint=kitchen_view.checkpoint_ready
	town.sync_characters(0.0,profile.shop.snapshot().orders)
	guide=TDStoryGuide.new();guide.shell=self;add_child(guide)
	travel("cottage" if profile.has_residence() and not first_entry else "town",not first_entry)
	if not profile.has_residence() or first_entry: town.spawn_at_harbor()
	if first_entry: guide.begin_arrival()

func travel(destination: String,at_bed:bool=false) -> TDOutcome:
	if profile!=null and profile.characters.clock.closed_day==profile.characters.clock.day:
		var allowed: String="cottage" if profile.has_residence() else "town"
		if destination!=allowed: return _outcome(TDOutcome.new(false,"NIGHT_CLOSED","今天已结束，请跟随阿铃前往小屋，或在床上休息。"))
	if profile==null or destination not in ["town","restaurant","kitchen","cottage"]: return TDOutcome.new(false,"INVALID_DESTINATION")
	if destination=="cottage" and not profile.has_residence(): return _outcome(TDOutcome.new(false,"HOME_LOCKED","小屋还未交到你手中。先完成今日营业，再与阿铃聊聊落脚的事。"))
	if _modal!=null: _close_dialog()
	_clear_branch_visit()
	_clear_visit()
	visiting_town=str(profile.commerce.state.home)
	var previous_location:=location
	if destination=="kitchen": _coach_story_kitchen()
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

func _note_story_plate() -> void:
	# Compatibility entry: leaving a room does not submit a plate.
	pass

func _apply_story(effect: Dictionary) -> void:
	if profile==null or profile.story==null:
		return
	if effect.has("san"):
		var before:=profile.world.san
		var next:=clampi(before+int(effect.san),0,100)
		var changed:=profile.world.set_san(next)
		if not changed.ok:
			profile.world.san=next
		if kitchen_view!=null:
			kitchen_view.day_san=profile.world.san
		_message("SAN %d → %d。这次只影响之后的感知，不改这一下的操作难度。" % [before, profile.world.san])
	if bool(effect.get("pay",false)):
		_story_purse()
	if bool(effect.get("grant",false)):
		_story_supplies()

func _fill_story_board(state: Dictionary) -> void:
	if town==null or profile==null or profile.story==null or not profile.story.started():
		return
	var offer: Dictionary=profile.service.offer("service.tomato_egg")
	var menu: Dictionary=state.menu.get("service.tomato_egg",{})
	var reference:=int(offer.get("reference_cents",0))
	town.story_board={
		"menu": bool(menu.get("enabled",false)),
		"price": reference>0 and int(menu.get("price_cents",0))==reference,
		"stock": profile.shop.menu_available("service.tomato_egg"),
		"served": profile.story.served,
	}

var _story_supply_checked: bool=false

func _story_supplies() -> void:
	if _story_supply_checked: return
	if profile==null or profile.story==null or not (profile.story.supplied or profile.story.owe_pack):
		return
	if not profile.at_boundary():
		return
	var state:=profile.shop.snapshot()
	var token:="story-chen-pack-v2:%s"%str(state.run_id)
	if state.seen.has(token): profile.story.mark_supplied();_story_supply_checked=true;return
	var pack:=profile.service.material_needs(profile.service.cooking,"service.tomato_egg")
	# Give a usable recipe, including the actual oil/starch IDs. Seasoning has
	# a little tolerance for a beginner holding past the target (AI-054).
	for id: String in pack:
		if not profile.service.is_primary(id): pack[id]=ceili(float(pack[id])*1.25)
	# Repair the original 0.001-portion grant without minting another full reward.
	for event: Dictionary in state.ledger:
		if event.reference=="story-chen-pack:%s"%str(state.run_id):
			for id: String in event.inventory_delta:
				if pack.has(id): pack[id]=maxi(0,int(pack[id])-int(event.inventory_delta[id]))
	for id: String in pack.keys():
		if int(pack[id])==0: pack.erase(id)
	var sent:=profile.shop.receive_supply(pack,token,0)
	if sent.ok or sent.code=="DUPLICATE":
		profile.story.mark_supplied()
		_story_supply_checked=true
		if sent.ok:
			var rows: Array[String]=[]
			for id: String in pack: rows.append("%s × %.3f"%[_ingredient_name(id),float(pack[id])/1000.0])
			_message("老陈赠料已入库（免费）："+"、".join(rows)+"。不开门也能进厨房试做。")
	elif sent.code!="NOT_AT_BOUNDARY" and _story_pay_note!=sent.code:
		_story_pay_note=sent.code
		_message("试做食材还没入库："+sent.code)

func _consume_story_plate() -> void:
	if kitchen_view==null or profile.story.paid or not profile.story.owe_pay: return
	for lane: TDCookingLane in kitchen_view.kitchen.lanes:
		var dish:=lane.snapshot()
		if str(dish.recipe_id).ends_with("tomato_egg") and dish.state=="plated":
			if kitchen_view.kitchen.handling.hand==lane.session: kitchen_view.kitchen.handling.clear_dish()
			kitchen_view._reset_pot(lane);kitchen_view._sync_usage()
			return

func _coach_story_kitchen() -> void:
	if profile==null or profile.story==null or kitchen_view==null:
		return
	var coach:=profile.story.waiting_cook() and profile.story.score<0
	for lane: TDCookingLane in kitchen_view.kitchen.lanes:
		lane.story_coach=coach
	if kitchen_view.kitchen.prep!=null:
		kitchen_view.kitchen.prep.story_coach=coach
	if coach and not profile.story.coached:
		profile.story.coached=true
		_message("冰箱 E 取番茄，砧板选大块。灶台 F 开始。调味按住，到量松开。失误不必重来。")

func _story_purse() -> void:
	if profile==null or profile.story==null or profile.story.paid or not profile.story.owe_pay:
		return
	if not profile.at_boundary():
		return
	var offer: Dictionary=profile.service.offer("service.tomato_egg")
	var cents:=int(offer.get("reference_cents",0))
	if cents<=0:
		return
	var token:="story-aling-tomato:%s"%str(profile.shop.snapshot().get("run_id",""))
	var paid:=profile.shop.world_adjustment(cents,token,"阿铃的审判")
	if paid.ok or paid.code=="DUPLICATE":
		profile.story.mark_paid()
		_story_pay_note=""
		if paid.ok:
			_message("阿铃放下了这一盘的钱。")
	elif paid.code!="NOT_AT_BOUNDARY" and _story_pay_note!=paid.code:
		_story_pay_note=paid.code
		_message("阿铃的钱还没入账："+paid.code)

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
	if id.begins_with("player-branch:"): _outcome(enter_branch(id))
	elif kind=="cottage":
		if profile.residence.stage=="door": guide.present_home("home_door")
		else: travel("cottage")
	elif kind=="harbor": show_harbor()
	elif kind in ["urban_village","rich_district"]:
		var box:=_dialog("居民区 · "+str(profile.world._plot_by_id(id).get("name","青瓦巷")))
		box.add_child(TDUI.label("青瓦屋檐下，几户街坊围着小院生活。巷道通往集市和食堂。",TDUI.FONT_SECTION))
		box.add_child(TDUI.label("院门里是街坊的家。沿街走走，也许会遇到熟悉的人。",TDUI.FONT_BODY,TDUI.MUTED))
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
			profile.commerce.attach_map(profile.world.town_map.plots,profile.world.map_version)
			var site:=profile.commerce.geography.cell(Vector2i(int(plot.x),int(plot.y)))
			var quote:=profile.commerce.geography.parcel_quote(id)
			box.add_child(TDUI.label("地块参考总价 ¥%.2f · 日租报价 ¥%.2f\n可见度 %.0f%% · 区位吸引力 %.0f%%\n报价不是当前租约；自有主店免现金房租。"%[float(quote.land_value_cents)/100,float(quote.rent_quote_cents_per_day)/100,100*float(site.visibility),100*float(site.attractiveness)],TDUI.FONT_BODY))
		box.add_child(TDUI.label("这里是"+str(profile.world._plot_by_id(id).get("name","小镇街区"))+"。",TDUI.FONT_SECTION))
		if kind in ["factory_lot","supply_factory","diner_lot"]:
			box.add_child(TDUI.label("地块管理",TDUI.FONT_BODY))
			if kind=="factory_lot": box.add_child(TDUI.label("靠近这块空地，按 E 建设。",TDUI.FONT_BODY))
		elif not TDSanRules.recovery(kind).is_empty():
			var offer:=TDSanRules.recovery(kind)
			box.add_child(TDUI.label("歇歇脚 · %.0f小时 · %d元 · 精神恢复%d"%[offer.hours,offer.cost,offer.san],TDUI.FONT_BODY))
			box.add_child(TDUI.button("在这里逛一逛",func()->void:_outcome(profile.world_transaction(profile.world.visit_zone.bind(kind),"visit:"+kind))))
		else: box.add_child(TDUI.label("走访街区，回店经营。",TDUI.FONT_BODY,TDUI.MUTED))
		var pool:=int(plot.get("pool",0));var shift:=int(plot.get("budget_shift",0))
		if pool!=0 or shift!=0:
			box.add_child(TDUI.label("这个功能区计入客流：人数 %+d，预算 %+d。客人进店时仍会和竞品比较装修、价格和等待。"%[pool,shift],TDUI.FONT_BODY))

func show_harbor() -> void:
	if profile==null: return
	var box:=_dialog("港口 · 小镇间客运",true)
	box.add_child(TDUI.label("客运免费，即时抵达。旅行不会自动开放菜系、采购商路或分店资格。",TDUI.FONT_BODY))
	box.add_child(TDUI.label(kitchen_view.staff_status(),TDUI.FONT_BODY,TDUI.ORANGE))
	for id: String in TDTravelCatalog.IDS:
		if id==visiting_town: continue
		var row:=TDTravelCatalog.info(id)
		box.add_child(TDUI.button("前往 "+str(row.name),func()->void:_outcome(voyage(id))))
	box.add_child(TDUI.label("营业期间订单与耐心继续推进；02:00仍收尾回小屋。",TDUI.FONT_BODY,TDUI.MUTED))

func voyage(destination: String) -> TDOutcome:
	if profile==null or location not in ["town","voyage"]: return TDOutcome.new(false,"NOT_AT_PORT")
	if profile.characters.clock.closed_day==profile.characters.clock.day: return TDOutcome.new(false,"NIGHT_CLOSED","今天已结束，请先休息。")
	if guide!=null and guide.presenting(): return TDOutcome.new(false,"STORY_BUSY")
	var at_port: bool=false
	if visiting!=null: at_port=visiting.nearby().get("kind")=="harbor"
	else:
		var feet: Vector2=(town._player.position-town._origin())/TDTownWorld.CELL
		var booth:=Rect2(70,32,1,1)
		at_port=feet.distance_to(feet.clamp(booth.position,booth.end))<=.65 or feet.distance_to(Vector2(TDHarbor.ARRIVAL)+Vector2.ONE*.5)<=.8
	if not at_port: return TDOutcome.new(false,"NOT_AT_PORT","请到港口柜台乘船。")
	var arrivals: Dictionary={}
	for id: String in TDTravelCatalog.IDS: arrivals[id]="harbor."+id+".arrival"
	var request:=TDHarbor.departure_request(destination,visiting_town,TDTravelCatalog.IDS,arrivals,false)
	if not request.ok: return request
	var next_map:=TDTravelCatalog.map_for(profile,destination)
	if next_map==null: return TDOutcome.new(false,"DESTINATION_NOT_READY")
	_close_dialog();_clear_visit()
	if destination==str(profile.commerce.state.home):
		travel("town");town.spawn_at_harbor()
		town._player.position=town._origin()+Vector2(70.5,33.5)*TDTownWorld.CELL
	else:
		visiting=TDTravelWorld.new();visiting.town_id=destination;visiting.map=next_map
		visiting.harbor_requested.connect(show_harbor);visiting.landmark_requested.connect(_travel_landmark)
		town.set_presented(false);restaurant.set_floor_cover(true);cottage.set_presented(false);kitchen_view.hide()
		location="voyage";add_child(visiting)
	visiting_town=destination;_lock_controls(true)
	return TDOutcome.new(true,"ARRIVED",TDTravelCatalog.info(destination).name)

func _clear_visit() -> void:
	if visiting!=null:
		visiting.close();remove_child(visiting);visiting.queue_free();visiting=null

func _travel_landmark(plot: Dictionary) -> void:
	if plot.has("branch_id"): _outcome(enter_branch(str(plot.branch_id)));return
	var box:=_dialog(TDTravelCatalog.label(plot,visiting_town),true)
	box.add_child(TDUI.label(TDTravelCatalog.info(visiting_town).caption,TDUI.FONT_BODY))
	box.add_child(TDUI.label("这里的街坊经营着自己的生活。当地故事与室内互动将在后续加入。\n采购合作仍需商路推荐；可在主店账本查看世界行情。",TDUI.FONT_BODY,TDUI.MUTED))

func show_world_map() -> void:
	if profile==null: return
	var box:=_dialog("世界地图",true);_map_open=true;_notice.hide()
	var panel: PanelContainer=box.get_parent().get_parent().get_parent()
	panel.position=Vector2(40,42);panel.size=Vector2(1200,716)
	var scroll:=box.get_parent() as ScrollContainer;scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	var view:=TDTravelMapView.new();view.configure(profile);view.town_id=visiting_town
	if branch_visit!=null:
		var branch: Dictionary=profile.branches.state.stores[branch_visit.store_id]
		view.marker=Vector2(branch.rect[0],branch.rect[1])+Vector2(branch.rect[2],branch.rect[3])*.5
	elif visiting!=null: view.marker=visiting.player.position/TDTravelWorld.CELL
	elif location=="town": view.marker=(town._player.position-town._origin())/TDTownWorld.CELL
	else:
		var id: String="player_cottage" if location=="cottage" else "player_diner"
		var p: Dictionary=profile.world._plot_by_id(id)
		if not p.is_empty(): view.marker=Vector2(p.x,p.y)+Vector2(p.w,p.h)*.5
	box.add_child(view)
	var bar:=HBoxContainer.new();box.add_child(bar)
	bar.add_child(TDUI.button("世界全览",view.reset_view));bar.add_child(TDUI.button("当前位置",view.focus_town.bind(visiting_town)))

func show_market() -> void:
	if not profile.can_leave_shop(): _outcome(TDOutcome.new(false,"SHOP_OPEN","营业中不能采购。"));return
	var stall:=profile.world.town_map.market(profile.world.selected_market)
	var title:=String(stall.get("name","街坊菜市")) if not stall.is_empty() else "街坊菜市"
	var box:=_dialog(title+" · 现货采购")
	if profile.shop.snapshot().phase=="SETTLED":
		box.add_child(TDUI.label("今天已经打烊。回店休息后，明早再来挑新鲜食材。",TDUI.FONT_BODY));return
	var forecast:=profile.shop.visitor_forecast()
	box.add_child(TDUI.label("用餐高峰 08–10 / 11–13 / 17–19 · 少量错峰
持续营业至主动打烊或02:00；错过的时段不补客。",TDUI.FONT_BODY,TDUI.MUTED))
	box.add_child(TDUI.label("从现在开门预计 %d—%d 位客人 · 买好食材后回店挂牌营业"%[forecast.min_visitors,forecast.max_visitors],TDUI.FONT_BODY,TDUI.ORANGE))
	box.add_child(TDUI.label("食材按现货供应；调料随菜系开放，共享调料开放任一对应菜系即可购买。",TDUI.FONT_BODY,TDUI.MUTED))
	for id: String in profile.shop.spoiled_today():
		box.add_child(TDUI.label("今日过期：%s %.2f%s，已清理。"%[_ingredient_name(id),float(profile.shop.spoiled_today()[id])/1000,profile.shop.stock_info(id).unit],TDUI.FONT_BODY,TDUI.ORANGE))
	for id: String in profile.shop.market_ids():
		var row:=HBoxContainer.new();box.add_child(row)
		row.add_child(TDIngredientIcon.make(id))
		var market:Dictionary=profile.commerce.state.markets[profile.commerce.state.home]
		var info:=profile.shop.stock_info(id)
		var caption:=TDUI.label(_market_caption(id),TDUI.FONT_BODY)
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
	if profile==null: return
	_management_panel("五镇供应商",TDManagementPanels.SupplierPanel.new())

func _town_name(id: String) -> String:
	if profile.commerce.config.towns.has(id): return str(profile.commerce.config.towns[id].name)
	var town_data:Dictionary=profile.world.catalog.town(id)
	return str(town_data.get("nickname",id))

func show_remote_market(town_id: String) -> void:
	if town_id not in profile.commerce.state.routes: _outcome(TDOutcome.new(false,"ROUTE_LOCKED","尚未收到这条商路的推荐。"));return
	var box:=_dialog(_town_name(town_id)+" · 当日报价")
	var market:Dictionary=profile.commerce.state.markets[town_id]
	for id: String in profile.shop.market_ids():
		var row:=HBoxContainer.new();box.add_child(row)
		row.add_child(TDIngredientIcon.make(id))
		var info:=profile.shop.stock_info(id)
		var label:=TDUI.label("%s · 现货%.1f%s · 含运费¥%.2f/%s"%[_ingredient_name(id),float(market.stock[id])/1000,info.unit,float(int(market.price[id])+profile.commerce.freight(town_id))/100,info.unit],TDUI.FONT_BODY)
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
	profile.commerce.attach_map(profile.world.town_map.plots,profile.world.map_version)
	var state:=profile.shop.snapshot()
	var box:=_dialog("今日菜单 · 营业牌")
	if state.phase in ["OPEN","DRAINING"]:
		box.add_child(TDUI.label("正在营业。打烊后可出门采购、研究菜谱和布置餐厅。",TDUI.FONT_BODY))
		box.add_child(TDUI.button("提前打烊",func()->void:_outcome(profile.shop.close_early());_close_dialog()))
		return
	if state.phase=="SETTLED":
		box.add_child(TDUI.button("查看今日账本",show_ledger))
		box.add_child(TDUI.button("店铺",show_branch))
		return
	box.add_child(TDUI.button("店铺",show_branch))
	for id: String in state.menu:
		if not profile.shop.is_unlocked(profile.shop.family_id(id)): continue
		var row:=HBoxContainer.new();box.add_child(row)
		var enabled:=CheckBox.new();enabled.text=profile.shop.recipe_name(id);enabled.button_pressed=state.menu[id].enabled;enabled.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(enabled)
		var price:=SpinBox.new();price.min_value=.01;price.max_value=10000;price.step=.5;price.value=float(state.menu[id].price_cents)/100;price.prefix="¥ ";price.custom_minimum_size=Vector2(150,52);row.add_child(price)
		enabled.toggled.connect(func(value:bool)->void:_outcome(profile.shop.set_menu(id,value,roundi(price.value*100))))
		price.value_changed.connect(func(value:float)->void:_outcome(profile.shop.set_menu(id,enabled.button_pressed,roundi(value*100))))
		var stock:=TDUI.label("有料" if profile.shop.menu_available(id) else "缺料 / 售罄",TDUI.FONT_BODY,TDUI.MUTED)
		stock.custom_minimum_size.x=125;stock.autowrap_mode=TextServer.AUTOWRAP_OFF;row.add_child(stock)
	box.add_child(TDUI.label("确认菜单和价格后开门。缺料菜自动停售，营业可外出，现货采购仍限筹备。请提前雇好厨师和服务员：厨师在后厨按流程做菜，菜放在出餐口，服务员去取再端到桌上。",TDUI.FONT_BODY,TDUI.MUTED))
	box.add_child(TDUI.label("用餐高峰 08–10 / 11–13 / 17–19 · 少量错峰\n持续营业至主动打烊或02:00；错过的时段不补客。",TDUI.FONT_BODY,TDUI.MUTED))
	var demand:=TDUI.label("",TDUI.FONT_BODY,TDUI.ORANGE);box.add_child(demand)
	var forecast_update:=func()->void:
		var estimated:=profile.shop.visitor_forecast()
		var ready: Array=profile.shop.economic_menu()
		if ready.is_empty():
			demand.text="按现在的冰箱，今天不会有客人进门。菜单上的菜还缺主料或调料。"
			demand.text+="\n补齐后再开门，备足材料预计 %d—%d 位。"%[estimated.min_visitors,estimated.max_visitors]
		else:
			var live: Dictionary=profile.commerce.forecast(ready,profile.characters.clock.minute)
			demand.text="按现在的库存，预计 %d—%d 位客人。预算、路程、排队和竞争会影响实际到店。"%[live.min_visitors,live.max_visitors]
		if estimated.has("excluded_budget_share") and float(estimated.excluded_budget_share)>0 and not ready.is_empty():
			demand.text+="\n目前没有约%.0f%%客群买得起的菜，可试着加入较低价菜品。"%(100*float(estimated.excluded_budget_share))
	forecast_update.call()
	for price_control: SpinBox in box.find_children("*","SpinBox",true,false): price_control.value_changed.connect(func(_v:float)->void:forecast_update.call())
	for check_control: CheckBox in box.find_children("*","CheckBox",true,false): check_control.toggled.connect(func(_v:bool)->void:forecast_update.call())
	box.add_child(TDUI.button("确认菜单，开门营业",start_day))

func start_day() -> TDOutcome:
	if profile.characters.clock.minute>=TDWorldDayClock.END_MINUTE: return _outcome(TDOutcome.new(false,"NIGHT_CLOSED","今天已经结束，请到床上休息。"))
	var result:=profile.shop.open_day()
	if result.ok:
		kitchen_view._sync_usage();kitchen_view.refresh(true)
		profile.world.day_phase="service"
		_close_dialog();_lock_controls(true)
	return _outcome(result)

func _world_time_boundary(seconds: float) -> float:
	if profile==null: return seconds
	var left: float=TDWorldDayClock.END_MINUTE-profile.characters.clock.minute
	return minf(seconds,left) if left>0.0000001 else seconds

func _on_active_time(seconds: float) -> void:
	if not automatic_time or profile==null or atlas!=null or get_tree().paused or (town!=null and town.story_dialogue_open()): return
	profile.world.tick_factories(seconds)
	advance_world_time(seconds)

func advance_world_time(seconds: float) -> void:
	if profile==null or get_tree().paused or atlas!=null or (town!=null and town.story_dialogue_open()): return
	var before: float=profile.characters.clock.minute
	var due:=profile.characters.clock.advance(seconds)
	profile.suppliers.advance_active_time(seconds,maxf(0.0,profile.characters.clock.minute-before))
	if town!=null: town.sync_characters(maxf(0.0,profile.characters.clock.minute-before),profile.shop.snapshot().orders,before)
	if due: finish_night()

func finish_night() -> TDOutcome:
	if profile==null or _night_closing: return TDOutcome.new(false,"BUSY")
	var clock:=profile.characters.clock
	if clock.closed_day==clock.day: return TDOutcome.new(true,"NIGHT_ALREADY_CLOSED")
	if clock.minute<TDWorldDayClock.END_MINUTE: return TDOutcome.new(false,"NOT_NIGHT")
	_night_closing=true
	_close_dialog()
	if atlas!=null: close_atlas()
	town._dismiss_talk();restaurant._dismiss_talk()
	var cleaned:=kitchen_view.finish_night()
	if not cleaned.ok: _night_closing=false;return _outcome(cleaned)
	var settled:=profile.shop.close_for_night()
	if not settled.ok: _night_closing=false;return _outcome(settled)
	profile.characters.observe_orders(profile.shop.snapshot().orders)
	restaurant.finish_night()
	clock.closed_day=clock.day
	if profile.has_residence(): travel("cottage",true)
	else:
		profile.invite_home("late");travel("town");guide.begin_homecoming()
	var saved:=save_game()
	_night_closing=false
	if not saved.ok: return _outcome(TDOutcome.new(false,saved.code,"02:00已结束营业，但保存失败，请在暂停菜单重试保存。"))
	_message(("已到02:00，收摊回小屋。" if profile.has_residence() else "夜深了，阿铃会带你找个落脚处。")+cleaned.message+"日结已保存。")
	return TDOutcome.new(true,"NIGHT_CLOSED")

func show_ledger() -> void:
	var box:=_dialog("食堂账本")
	var growth := profile.progression.progress()
	box.add_child(TDUI.button("经营等级 Lv.%d · 查看等级奖励"%int(growth.level),show_levels))
	box.add_child(TDUI.button("店铺",show_branch))
	var state:=profile.shop.snapshot()
	if state.phase=="SETTLED": kitchen_view._summary_page(box,profile.shop.day_summary())
	else: box.add_child(TDUI.label("第%d天 · 余额 ¥%.2f · 人气%d"%[state.day,float(state.money_cents)/100.0,state.popularity],TDUI.FONT_SECTION))
	var economy:Dictionary=profile.commerce.state
	box.add_child(TDUI.label("未付费用 ¥%.2f · 店铺认知 %.0f%% · 品牌信任 %.0f%%"%[float(economy.debt_cents)/100,float(economy.awareness)*100,float(economy.brand)*100],TDUI.FONT_BODY,TDUI.ORANGE))
	if not economy.books.is_empty():
		var report:Dictionary=economy.books.back()
		box.add_child(TDUI.label("第%d天：耗料成本 ¥%.2f · 水电 ¥%.2f · 房租 ¥%.2f\n经营利润 ¥%.2f（采购是现金换库存，不再次扣利润）\n全镇用餐机会%d · 考虑本店%d · 接待%d · 完成%d · 离开%d"%[report.day,float(report.consumed_cost_cents)/100,float(report.utilities_cents)/100,float(report.rent_cents)/100,float(report.profit_cents)/100,report.funnel.opportunities,report.funnel.considered,report.funnel.admitted,report.funnel.completed,report.funnel.abandoned],TDUI.FONT_BODY))
	for group:Dictionary in profile.commerce.config.groups:
		box.add_child(TDUI.label("%s：味道%.0f / 服务%.0f / 划算%.0f"%[group.name,100*profile.commerce.reputation(group.id,"food"),100*profile.commerce.reputation(group.id,"service"),100*profile.commerce.reputation(group.id,"value")],TDUI.FONT_BODY,TDUI.MUTED))
	for item: Dictionary in state.ledger.slice(maxi(0,state.ledger.size()-16)):
		box.add_child(TDUI.label("第%d天 · %s · %+.2f元"%[item.day,item.extra.get("label",_ledger_name(item.kind)),float(item.cents)/100.0],TDUI.FONT_CAPTION,TDUI.MUTED))
	if profile.at_boundary(): box.add_child(TDUI.button("保存当前进度",func()->void:_outcome(save_game())))
	var account:=profile.commerce.society.bank.account("player")
	box.add_child(TDUI.label("钱庄存款 ¥%.2f · 贷款本金 ¥%.2f · 未付利息 ¥%.2f\n借还本金和存取款不计入经营利润。商业街钱庄可办理。"%[float(account.deposit_cents)/100,float(account.principal_cents)/100,float(account.interest_cents)/100],TDUI.FONT_BODY))
	if not economy.books.is_empty():
		var last: Dictionary=economy.books.back()
		box.add_child(TDUI.label("利润税 ¥%.2f · 本日利息 ¥%.2f · 税前利润 ¥%.2f"%[float(last.get("tax_cents",0))/100,float(last.get("interest_cents",0))/100,float(last.get("profit_before_tax_cents",last.profit_cents))/100],TDUI.FONT_BODY))
	var society: Dictionary=profile.commerce.society.state
	if not society.daily.is_empty(): box.add_child(TDUI.label("五镇家庭：工资 ¥%.2f · 外食 ¥%.2f · 基本生活 ¥%.2f\n未满足基本生活支出 ¥%.2f（没有暗中补款）"%[float(society.daily.wages_cents)/100,float(society.daily.dining_cents)/100,float(society.daily.necessities_cents)/100,float(society.daily.unmet_needs_cents)/100],TDUI.FONT_BODY,TDUI.MUTED))
	box.add_child(TDUI.label("本镇公共账户 ¥%.2f · 工资税与利润税收入分别记账"%(float(society.public[economy.home])/100),TDUI.FONT_BODY,TDUI.MUTED))

func show_levels() -> void:
	if profile==null: return
	var box := _dialog("经营等级 · 升级奖励")
	var view := TDLevelRewardsView.new()
	box.add_child(view);view.setup(profile.progression,int(profile.research.snapshot().points))
	if not profile.at_boundary(): box.add_child(TDUI.label("查阅期间营业继续；按 Esc 返回。",TDUI.FONT_CAPTION,TDUI.MUTED))

func show_bank() -> void:
	if profile==null or not profile.at_boundary(): return
	var target:=profile
	var box:=_dialog("商业街钱庄")
	var bank:=profile.commerce.society.bank
	var account:=bank.account("player")
	box.add_child(TDUI.label("手头 ¥%.2f · 存款 ¥%.2f\n贷款本金 ¥%.2f · 应付利息 ¥%.2f"%[float(profile.shop.snapshot().money_cents)/100,float(account.deposit_cents)/100,float(account.principal_cents)/100,float(account.interest_cents)/100],TDUI.FONT_SECTION))
	box.add_child(TDUI.label("授信上限 ¥%.2f · 借款日息 %.2f%% · 存款日息最高 %.2f%%\n期限%d天；到期日结尽力偿还，逾期停新增贷款，仍可继续经营。"%[float(bank.config.loan_limit_cents)/100,float(bank.config.loan_daily_bps)/100,float(bank.config.deposit_daily_bps)/100,bank.config.term_days],TDUI.FONT_BODY,TDUI.MUTED))
	if int(account.principal_cents)>0: box.add_child(TDUI.label("到期：第%d天%s"%[account.due_day," · 已逾期" if int(profile.shop.snapshot().day)>int(account.due_day) else ""],TDUI.FONT_BODY,TDUI.ORANGE))
	var amount:=SpinBox.new();amount.min_value=.01;amount.max_value=10000;amount.step=.01;amount.value=100;amount.prefix="¥ ";amount.name="BankAmount";box.add_child(amount)
	for action: String in ["deposit","withdraw","borrow","repay"]:
		var labels: Dictionary={"deposit":"存入","withdraw":"取出","borrow":"借款","repay":"还款（先息后本）"}
		var token: String="bank:%s:%d:%s"%[profile.shop.snapshot().run_id,int(profile.shop.snapshot().serial)+1,action]
		box.add_child(TDUI.button(labels[action],func()->void:
			if profile!=target or not target._alive: return
			var result:=target.bank_action(action,roundi(amount.value*100),token)
			_outcome(result)
			if result.ok: show_bank()))
	box.add_child(TDUI.label("存取借还只在筹备或日结办理，随当前存档保存。利率是游戏内可调参数。",TDUI.FONT_CAPTION,TDUI.MUTED))

func show_competitor(parcel_id: String) -> void:
	var box:=_dialog("街坊餐馆 · 经营告示")
	var economy:=profile.commerce
	var firms: Array=economy.state.competitors[economy.state.home]
	var selected:=firms.filter(func(f:Dictionary)->bool:return f.parcel_id==parcel_id)
	if selected.is_empty(): selected=firms
	for firm: Dictionary in selected:
		box.add_child(TDUI.label("%s · %s\n售价 ¥%.2f · 今日接待%d/%d · 在岗%d人\n最近经营利润 ¥%.2f · 现金 ¥%.2f"%[firm.name,"第%d天开业"%int(firm.open_day) if firm.status=="construction" else "营业中",float(firm.price_cents)/100,firm.served,firm.capacity,economy.society.staff(firm.id).size(),float(firm.last_profit_cents)/100,float(firm.cash_cents)/100],TDUI.FONT_BODY))
	box.add_child(TDUI.label("商业街可交易商铺剩余%d处。竞争者按盈利、人员和资金决定投资，不增加全镇用餐机会。"%economy.expansion.candidates(economy.state.home).size(),TDUI.FONT_BODY,TDUI.MUTED))
	var decor:=TDEconomyMath.decor_of(profile.layout.pieces(),profile.world.catalog.wildcards)
	box.add_child(TDUI.label("每个用餐机会只选择一次：比较本店菜单、这些竞品和在家吃饭。预算、菜价、路程、等待、品牌和装修一起决定。\n你的装修效果 %.0f（统一 %.0f，高端 %.0f）。到店后的改价不改已经生成的订单。"%[float(decor.effect),float(decor.unity),float(decor.luxury)],TDUI.FONT_BODY))
	var stats:Dictionary=economy.state.day_stats
	if int(stats.get("opportunities",0))>0:
		box.add_child(TDUI.label("今日用餐机会 %d · 选本店 %d · 选竞品 %d · 在家或没买成 %d"%[int(stats.opportunities),int(stats.considered),int(stats.competitor),int(stats.outside)],TDUI.FONT_BODY,TDUI.ORANGE))
	for event: Dictionary in economy.expansion.state.events:
		if event.town_id==economy.state.home: box.add_child(TDUI.label("第%d天买地建店 · 支出 ¥%.2f · 第%d天开业"%[event.day,float(event.cost_cents)/100,event.open_day],TDUI.FONT_CAPTION,TDUI.MUTED))

func _ledger_name(id: String) -> String:
	return {"purchase":"采购","consumption":"食材消耗","prepayment":"菜款","tip":"小费","refund_cancel":"取消退款","refund_served":"退菜退款","settlement":"日结","emergency_grant":"应急补助","world_adjustment":"小镇支出 / 收入","supply_delivery":"预订原料到货","operating_payment":"水电税费 / 偿还欠费","bank_transfer":"钱庄存取 / 借还","wage":"雇员工资"}.get(id,id)

func show_crew() -> void:
	if profile==null: return
	_management_panel("雇员 · 招聘与仓库",TDManagementPanels.EmployeePanel.new())

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
	_outcome(hired)
	show_crew()

func _dismiss_crew(id: String) -> void:
	if profile == null or not profile.at_boundary():
		_outcome(TDOutcome.new(false, "SHOP_OPEN", "打烊后才能辞退。"))
		return
	var result := profile.layout.crew.dismiss(id)
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
	_outcome(result)
	show_crew()

func show_branch() -> void:
	if profile == null: return
	var box := _dialog("店铺管理",true)
	_notice.hide()
	var frame: PanelContainer=box.get_parent().get_parent().get_parent()
	frame.position=Vector2(40,28);frame.size=Vector2(1200,744)
	var panel := TDBranchPanel.new()
	box.add_child(panel)
	panel.configure(profile)
	panel.changed.connect(func()->void:
		_refresh_branch_maps()
		if kitchen_view!=null: kitchen_view.refresh(true))

func _open_branch(town_id: String) -> void:
	var result := profile.world_transaction(func() -> TDOutcome: return profile.world.open_branch_in_town(town_id), "开分店")
	if result.ok:
		if profile.residence.get("plot") is Dictionary:
			profile.world.town_map.install_cottage(profile.residence.plot)
		profile.sync_commercial_map()
		profile.world.map_revision += 1
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
	_outcome(result)
	show_branch()

func show_rest() -> void:
	if profile==null or location!="cottage" or not profile.has_residence(): return
	var box:=_dialog("小屋 · 床")
	if profile.shop.snapshot().phase!="SETTLED":
		box.add_child(TDUI.label("完成营业并打烊后，可以休息到下一天。读档会回到床边。",TDUI.FONT_BODY))
		if profile.at_boundary(): box.add_child(TDUI.button("保存进度",func()->void:_outcome(save_game())))
		return
	box.add_child(TDUI.label("今日进度将保存，明早可以去集市重新备货。",TDUI.FONT_BODY))
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
	box.add_child(TDUI.label("睡觉或主动保存才记录进度（新档与02:00强制收尾除外）。退出不自动保存；未保存的装修、库存、金钱和研习都会回退。营业中及厨房未整理时不能保存。",TDUI.FONT_CAPTION,TDUI.MUTED))

func show_settings() -> void:
	var box:=_dialog("设置",true)
	box.add_child(TDUI.label("主音量",TDUI.FONT_BODY))
	var volume:=HSlider.new();volume.min_value=0;volume.max_value=1;volume.step=.05;volume.value=preferences.values.volume;volume.custom_minimum_size=Vector2(600,35);box.add_child(volume)
	var fullscreen:=CheckBox.new();fullscreen.text="全屏显示";fullscreen.button_pressed=preferences.values.fullscreen;box.add_child(fullscreen)
	box.add_child(TDUI.button("应用并保存",func()->void:_outcome(preferences.change(volume.value,fullscreen.button_pressed))))
	if profile!=null:
		box.add_child(TDUI.label("研习输入校准（毫秒）",TDUI.FONT_BODY))
		var offset:=SpinBox.new();offset.min_value=-200;offset.max_value=200;offset.step=5;offset.value=profile.research.snapshot().input_offset_sec*1000;box.add_child(offset)
		box.add_child(TDUI.button("应用校准（随进度保存）",func()->void:_outcome(profile.research.calibrate(offset.value/1000.0))))
	box.add_child(TDUI.label("WASD 移动 · Shift 疾跑 · E 交互 / 放取 · F 开灶 · Q 取锅料 · B 菜谱 · Esc 暂停",TDUI.FONT_BODY,TDUI.MUTED))

func request_title() -> void:
	if profile==null: return
	var box:=_dialog("放弃未保存的进度？",true)
	box.add_child(TDUI.label("返回主菜单不会自动保存。未保存的装修、金钱、库存、研习与任务进度会一起回到上次存档。",TDUI.FONT_BODY))
	var save:=TDUI.button("保存并返回主菜单",func()->void:
		var result:=save_game()
		if result.ok: go_title()
		else: _outcome(result))
	save.disabled=not profile.at_boundary();box.add_child(save)
	box.add_child(TDUI.button("确认返回主菜单",go_title))

func request_quit() -> void:
	if _quitting: return
	if profile==null: _finish_quit();return
	var box:=_dialog("退出游戏",true)
	box.add_child(TDUI.label("退出不会自动保存。未保存的装修、金钱、库存、研习与任务进度都会回退。需要保留时，请选择保存并退出。",TDUI.FONT_BODY))
	var save:=TDUI.button("保存并退出",func()->void:
		var result:=save_game()
		if result.ok: _finish_quit()
		else: _outcome(result))
	save.disabled=not profile.at_boundary();box.add_child(save)
	box.add_child(TDUI.button("确认退出",_finish_quit))

func _finish_quit() -> void:
	if _quitting: return
	_quitting=true
	_close_dialog();_dispose_game()
	if music!=null: music.shutdown()
	# Let the audio server retire stopped playback before the engine is destroyed.
	await get_tree().create_timer(.15,true,false,true).timeout
	get_tree().quit()

func go_title() -> void:
	_close_dialog();_dispose_game();location="title";_hud.set_toast("");_build_title()

func _dispose_game() -> void:
	debug_enabled=false;_console_lines.clear();_command_history.clear();_history_cursor=0;_history_draft=""
	close_atlas();_pause(false)
	_clear_branch_visit()
	_clear_visit()
	if guide!=null: guide.close();remove_child(guide);guide.queue_free();guide=null
	for scene: Node in [town,restaurant,kitchen_view,cottage]:
		if is_instance_valid(scene): scene.close();remove_child(scene);scene.queue_free()
	town=null;restaurant=null;kitchen_view=null;cottage=null;_rest_busy=false
	if profile!=null: profile.close();profile=null
	_generation+=1

func open_atlas() -> void:
	if profile==null or atlas!=null: return
	_prior_pause=get_tree().paused;_pause(true)
	for scene: Node in [town,restaurant,kitchen_view,cottage,visiting,branch_visit]: _freeze_branch(scene)
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
	var box:=_dialog("调试控制台",true)
	_notice.hide()
	var frame: PanelContainer=box.get_parent().get_parent().get_parent()
	frame.position=Vector2(80,48);frame.size=Vector2(1120,704)
	box.add_child(TDUI.label("反引号 / Esc 返回 · ↑↓历史 · Tab补全 · 修改仅在内存，save主动保存",TDUI.FONT_BODY,TDUI.MUTED))
	_console_output=RichTextLabel.new();_console_output.custom_minimum_size=Vector2(0,380);_console_output.selection_enabled=true;_console_output.scroll_following=true;_console_output.bbcode_enabled=false
	_console_output.add_theme_font_size_override("normal_font_size",TDUI.FONT_BODY);box.add_child(_console_output)
	_console=LineEdit.new();_console.placeholder_text="先输入 debug，再输入 help；例 money add 10000";_console.custom_minimum_size.y=46;box.add_child(_console)
	_console.keep_editing_on_text_submit=true
	_console.max_length=512
	_console.text_submitted.connect(_submit_console)
	_console.gui_input.connect(_console_key)
	_history_cursor=_command_history.size();_history_draft=""
	_append_console("调试模式已开启。help 查看命令。" if debug_enabled else "输入 debug 进入调试模式；help 可先查看帮助。")
	_console.grab_focus()

func _append_console(text: String) -> void:
	if text.is_empty(): return
	_console_lines.append_array(text.split("\n"))
	if _console_lines.size()>240: _console_lines=_console_lines.slice(_console_lines.size()-240)
	if is_instance_valid(_console_output): _console_output.text="\n".join(_console_lines)

func _submit_console(command: String) -> void:
	if command.strip_edges().is_empty(): return
	var input: LineEdit=_console
	var raw: String=command.strip_edges()
	if _command_history.is_empty() or _command_history[-1]!=raw:
		_command_history.append(raw)
		if _command_history.size()>50: _command_history.remove_at(0)
	_history_cursor=_command_history.size();_history_draft=""
	_append_console("> "+raw)
	_append_console(execute_command(raw))
	if is_instance_valid(input) and input==_console: input.clear();input.grab_focus()

func _console_key(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.is_echo(): return
	if event.keycode in [KEY_UP,KEY_DOWN]:
		if _history_cursor==_command_history.size(): _history_draft=_console.text
		_history_cursor=clampi(_history_cursor+(-1 if event.keycode==KEY_UP else 1),0,_command_history.size())
		_console.text=_history_draft if _history_cursor==_command_history.size() else _command_history[_history_cursor]
		_console.caret_column=_console.text.length();_console.accept_event()
	elif event.keycode==KEY_TAB:
		var found:=TDDebugCommands.complete(_console.text,profile)
		if found.size()==1: _console.text=found[0]
		elif not found.is_empty():
			var prefix: String=found[0]
			for value: String in found:
				while not value.begins_with(prefix) and not prefix.is_empty(): prefix=prefix.left(-1)
			if prefix.length()>_console.text.length(): _console.text=prefix
			_append_console("候选："+" · ".join(found.slice(0,20))+("（更多结果请继续输入）" if found.size()>20 else ""))
		else: _append_console("没有匹配的补全。help 查看命令。")
		_console.caret_column=_console.text.length();_console.accept_event()

func execute_command(command: String) -> String:
	var result:=TDDebugCommands.execute(self,command)
	if profile!=null and kitchen_view!=null: kitchen_view.refresh(true)
	return result

func show_debug_tools() -> void:
	if not debug_enabled: return
	var box:=_dialog("调试工具 · 独立试验入口",true)
	box.add_child(TDUI.label("这些旧原型用于复现和检查，与当前存档分开。",TDUI.FONT_BODY))
	for entry: String in ["厨房","营业","小镇","餐厅"]:
		box.add_child(TDUI.button(entry,func()->void:
			# Leave the real slot at a defined boundary; debug prototypes never own it.
			if profile!=null and not profile.at_boundary():
				_message("请先打烊再进入独立调试入口。");return
			# Independent debug entry discards the live slot like returning to title.
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
	next.characters.migrate(int(next.shop.snapshot().day),next.shop.snapshot().phase=="SETTLED")
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

func enter_branch(id: String) -> TDOutcome:
	if profile==null or location not in ["town","voyage"]: return TDOutcome.new(false,"NOT_OUTSIDE")
	if profile.characters.clock.closed_day==profile.characters.clock.day: return TDOutcome.new(false,"NIGHT_CLOSED")
	if not profile.branches.is_built(id): return TDOutcome.new(false,"UNDER_CONSTRUCTION",profile.branches.status_text(id))
	var store: Dictionary=profile.branches.state.stores[id]
	if str(store.town_id)!=visiting_town: return TDOutcome.new(false,"WRONG_TOWN")
	var target: Dictionary=visiting.nearby() if visiting!=null else town.facing_plot()
	if str(target.get("branch_id",""))!=id: return TDOutcome.new(false,"NOT_NEAR_BRANCH","请靠近这家分店，按 E 进入。")
	if guide!=null and guide.presenting(): return TDOutcome.new(false,"STORY_BUSY")
	_close_dialog();_branch_return=visiting.player.position if visiting!=null else town._player.position
	town.set_presented(false);restaurant.set_floor_cover(true);cottage.set_presented(false);kitchen_view.hide()
	if visiting!=null: visiting.set_presented(false)
	branch_visit=TDBranchInterior.new();branch_visit.profile=profile;branch_visit.store_id=id
	branch_visit.exit_requested.connect(exit_branch);branch_visit.management_requested.connect(_branch_management)
	location="branch";add_child(branch_visit);_lock_controls(true)
	return TDOutcome.new(true,"BRANCH_ENTERED","进入 "+str(store.name))

func _branch_management(tab: String) -> void:
	if branch_visit==null: return
	var id: String=branch_visit.store_id
	show_branch()
	var panels:=_modal_box.find_children("*","TDBranchPanel",true,false)
	if not panels.is_empty(): panels[0].manage(id);panels[0].select_tab(tab)

func exit_branch() -> void:
	if branch_visit==null: return
	_close_dialog();_clear_branch_visit()
	if visiting!=null:
		location="voyage";visiting.player.position=_branch_return;visiting.set_presented(true)
	else:
		location="town";town.set_presented(true);town._player.position=_branch_return
	_lock_controls(true)

func _clear_branch_visit() -> void:
	if branch_visit==null: return
	branch_visit.close();remove_child(branch_visit);branch_visit.queue_free();branch_visit=null

func _refresh_branch_maps() -> void:
	if profile==null: return
	profile.sync_commercial_map()
	if branch_visit!=null: branch_visit.refresh_staff()
	if visiting==null: return
	var feet:=visiting.player.position;var id:=visiting_town
	_clear_visit()
	visiting=TDTravelWorld.new();visiting.town_id=id;visiting.map=TDTravelCatalog.map_for(profile,id)
	visiting.harbor_requested.connect(show_harbor);visiting.landmark_requested.connect(_travel_landmark);add_child(visiting)
	if visiting._can_stand(feet): visiting.player.position=feet
	visiting.set_presented(location=="voyage");_lock_controls(_modal==null)
