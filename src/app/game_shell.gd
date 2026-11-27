class_name TDGameShell
extends Control
## Presentation and dependency assembly. Economy remains in the existing shop model.
signal debug_entry_requested(entry: String)
const TITLE_ART := preload("res://assets/title/主界面.png")
const SleepResults := preload("res://src/ui/sleep_results.gd")
@export_range(8, 32) var challenge_grid_size: int = 20
@export_range(1, 12) var challenge_action_points: int = 4
var _challenge: TDChallengePanel
var _challenge_notice: TDChallengePanel.Notice
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
var _branch_interiors: Dictionary={}
var _branch_return: Vector2=Vector2.ZERO
var visiting: TDTravelWorld
var visiting_town: String="chengdu"
var _map_open: bool=false
var restaurant: TDRestaurantWorld
var cottage:TDCottageWorld
var music:TDGameMusic
var _rest_busy:bool=false
var _rest_report: Dictionary = {}
var _sleep_results: CanvasLayer
var _saved_story_cursor: int = 0
var _story_save_error: String = ""
var _story_save_retry_at: int = 0
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
	var art := TextureRect.new()
	art.texture = TITLE_ART
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_screen.add_child(art)
	var column := VBoxContainer.new()
	column.anchor_left = .065
	column.anchor_right = .065
	column.anchor_top = .5
	column.anchor_bottom = .5
	column.offset_top = -220
	column.offset_right = 332
	column.add_theme_constant_override("separation", 13)
	_title_screen.add_child(column)
	var title := TDUI.label("幻境臻味焰", 52, Color("#fff9dc"))
	var subtitle := TDUI.label("~ Fight for the best taste!", 22, Color("#fff9dc"))
	for heading: Label in [title, subtitle]:
		heading.add_theme_color_override("font_outline_color", Color("#58281e"))
		heading.add_theme_constant_override("outline_size", 6)
		column.add_child(heading)
	var space := Control.new()
	space.custom_minimum_size.y = 13
	column.add_child(space)
	column.add_child(TDUI.button("开始游戏",start_game))
	var resume:=TDUI.button("继续游戏",continue_game);resume.disabled=slots.latest().is_empty();column.add_child(resume)
	column.add_child(TDUI.button("载入存档",func()->void:show_slots(false)))
	column.add_child(TDUI.button("设置",show_settings))
	column.add_child(TDUI.button("退出游戏",request_quit))
	_title_notice = TDUI.label("", TDUI.FONT_CAPTION, Color("#fff9dc"))
	_title_notice.add_theme_color_override("font_outline_color", Color("#58281e"))
	_title_notice.add_theme_constant_override("outline_size", 5)
	_title_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_title_notice)

func _process(_delta: float) -> void:
	if _quitting: return
	var challenge_kitchen := _challenge!=null and is_instance_valid(_challenge.lesson)
	var story_frozen:=profile!=null and town!=null and (town.story_dialogue_open() or challenge_kitchen)
	if story_frozen!=_story_frozen:
		_story_frozen=story_frozen
		if kitchen_view!=null: kitchen_view.set_paused(_story_frozen or get_tree().paused)
		if restaurant!=null: restaurant.story_frozen=_story_frozen
	if music!=null:
		var cooking:bool=kitchen_view!=null and kitchen_view.kitchen.music_audible()
		if branch_visit!=null: cooking=cooking or branch_visit.shop_view.kitchen.music_audible()
		if atlas!=null and atlas.trial!=null and atlas.trial.lesson!=null: cooking=atlas.trial.lesson.kitchen.music_audible()
		var opening_film: bool=guide!=null and guide.presenting() and guide.dialogue.talk.context.get("scene")=="intro"
		var music_context: String = "silent" if cooking else ("service" if profile!=null and not profile.at_boundary() else "casual")
		if _modal != null and _modal.has_meta("story_music"): music_context = str(_modal.get_meta("story_music"))
		if challenge_kitchen and _challenge.lesson.kitchen.music_audible(): music_context="silent"
		if _challenge != null and _challenge.battle != null:
			music_context = str(_challenge.battle.opponent.get("music","cooking"))
		music.select_context(music_context,_music_should_pause() or (opening_film and guide.dialogue.presentation_paused))
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
	var state:=profile.shop.frame_status()
	_hud.update_profile(profile,state)
	_hud.set_toast(_toast if Time.get_ticks_msec()<_toast_until else "")
	_hud.set_menu_enabled(not _menu_blocked())
	if kitchen_view!=null: kitchen_view.day_clock_label.text=profile.characters.clock.label()+" · 全天时间"
	_hud_layer.visible=atlas==null and not (guide!=null and guide.presenting()) and not (location=="kitchen" and kitchen_view.kitchen.stage.visible)
	if restaurant!=null:
		var top := maxf(_hud.reserved_bottom(),guide.reserved_bottom() if guide!=null else 0.0)
		restaurant.set_info_top(top+12)

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
			if town!=null: town.show_quest()
	if not _rest_busy and not guide.presenting() and _modal==null and atlas==null:
		_update_story_checkpoint()

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree(): return
	if _entry_busy or _quitting:
		get_viewport().set_input_as_handled();return
	if _rest_busy and event is InputEventKey:
		if is_instance_valid(_sleep_results) and event.is_action_pressed("ui_accept") and not event.is_echo():
			_sleep_results.continue_morning()
		get_viewport().set_input_as_handled();return
	if _challenge != null:
		if event.is_action_pressed("pause") or event.is_action_pressed("challenge_menu"):
			if not event.is_echo(): _challenge.back()
			get_viewport().set_input_as_handled()
		elif event is InputEventKey and _challenge.handle_key(event):
			get_viewport().set_input_as_handled()
		return
	if is_instance_valid(_challenge_notice): return
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
	var shortcuts: Dictionary={"employees_menu":"employees","recipe_book":"recipes","quest_journal":"quests","world_map":"map","branches_menu":"branches","suppliers_menu":"suppliers","relationships_menu":"relationships","challenge_menu":"challenge"}
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
	if (id=="challenge" or TDRevisedMainline.EXPANSION_MILESTONES.has(id)) and not profile.story_feature_available(id): return
	if _challenge != null:
		if id == "challenge": _challenge.back()
		return
	if id == "challenge" and branch_visit != null and branch_visit.shop_view.kitchen.stage.visible: return
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
		"challenge": _show_challenge()
	_management_action=id

func _show_challenge(encounter: Dictionary = {}, completion: Callable = Callable()) -> void:
	if profile==null or (encounter.is_empty() and not profile.story_feature_available("challenge")): return
	var title := "挑战"
	if not encounter.is_empty():
		title = "杂鱼挑战" if encounter.has("crowd_town") else "剧情战斗"
	var box := _dialog(title, true, func() -> void: _challenge.back())
	_notice.hide()
	var frame := box.get_parent().get_parent().get_parent() as PanelContainer
	frame.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	frame.offset_left = -566
	frame.offset_right = 566
	_challenge = TDChallengePanel.new()
	_challenge.story_encounter = encounter
	if completion.is_valid(): _challenge.story_finished.connect(completion,CONNECT_ONE_SHOT)
	if encounter.get("cooking_tutorial",false):
		_challenge.cooking_tutorial_finished.connect(func() -> void:
			TDRevisedMainline.mark(profile.story.revised,"aling_cooking_taught"),CONNECT_ONE_SHOT)
	_challenge.grid_size = challenge_grid_size
	_challenge.points_per_turn = challenge_action_points
	_challenge.research = profile.research
	_challenge.automatic_time = automatic_time
	_challenge.permanent_stats = func() -> Dictionary: return TDChallengeBattle.Rules.permanent_stats(profile.story, profile.challenge_progress)
	_challenge.should_teach = func(id: String) -> bool:
		return TDChallengeBattle.Rules.needs_tutorial(profile.story, profile.challenge_progress, id)
	_challenge.tutorial_finished.connect(func(id: String) -> void:
		if id not in profile.challenge_progress.tutorials: profile.challenge_progress.tutorials.append(id))
	_challenge.boss_rematch = func(id: String) -> bool:
		return TDChallengeBattle.Rules.boss_defeated(profile.story, profile.challenge_progress, id) or \
			(id == "chen" and (profile.challenge_progress.rojin_fought or "revised_05" in profile.story.revised.get("resolved", [])))
	_challenge.unlocked_skills = TDChallengeBattle.Skills.unlocked(profile.story, profile.challenge_progress)
	_challenge.loadout = TDChallengeBattle.Skills.normalize(profile.challenge_loadout, _challenge.unlocked_skills)
	_challenge.loadout_changed.connect(func(next: Array[String]) -> void: profile.challenge_loadout = next)
	var battlefield := Control.new()
	battlefield.name = "ChallengeBattlefield"
	battlefield.theme = theme
	battlefield.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal.add_child(battlefield)
	battlefield.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_challenge.battlefield = battlefield
	_challenge.close_requested.connect(_close_dialog)
	_challenge.cooking_changed.connect(func(active: bool) -> void:
		# The cooking input and its QTE clock require a running tree.
		_pause(not active)
		kitchen_view.set_paused(true))
	_challenge.match_finished.connect(func(phase: int, opponent_id: String, town_id: String, site: String) -> void:
		_challenge.reward_pages = profile.record_challenge_result(phase, opponent_id, town_id, site)
		_challenge.unlocked_skills = TDChallengeBattle.Skills.unlocked(profile.story, profile.challenge_progress))
	_challenge.battle_view_changed.connect(func(active: bool) -> void:
		frame.visible = not active)
	frame.offset_top = -335
	frame.offset_bottom = 335
	box.add_child(_challenge)

func _show_challenge_notices(pages: Array[String], finished: Callable) -> void:
	var box := _dialog("", true)
	(box.get_parent().get_parent().get_parent() as PanelContainer).hide()
	_challenge_notice = TDChallengePanel.Notice.new()
	_challenge_notice.name = "ChallengeNotice"
	_modal.add_child(_challenge_notice)
	_challenge_notice.present(pages, func() -> void:
		_close_dialog()
		finished.call())

func _crowd_label(town_id: String) -> String:
	if profile == null or _modal != null or (guide != null and guide.presenting()):
		return ""
	if visiting_town != town_id or location != ("town" if town_id == "chengdu" else "voyage"):
		return ""
	if not profile.town_map_unlocked(town_id):
		return ""
	return str(TDChallengeBattle.CROWD_RIVALS.get(town_id, {}).get("name", ""))

func _talk_to_crowd(site: String, town_id: String) -> void:
	if _crowd_label(town_id).is_empty(): return
	if TDChallengeBattle.Rules.recipe(0, town_id, site).is_empty(): return
	if town_id=="paris" and guide.journey.cursor()==8 and guide.journey.level()<guide.journey.VITO_LEVEL:
		var required := guide.journey.paris_resident_level(site)
		if not TDRevisedMainline.flag(profile.story.revised,"paris_training_complete"):
			_message("先完成餐厅里的经营教学。")
			return
		if guide.journey.level()<required:
			_message("这位厨师会在你的经营等级达到 Lv.%d 后接受挑战。" % required)
			return
	_show_challenge({"crowd_town":town_id, "crowd_site":site}, func(_phase: int) -> void: _close_dialog())

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

func _dialog(title: String, freeze: bool=false, back_action: Callable=Callable()) -> VBoxContainer:
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
	top.add_child(TDUI.button("返回",back_action if back_action.is_valid() else _close_dialog))
	_notice=TDUI.label("",TDUI.FONT_BODY,TDUI.ORANGE);_modal_box.add_child(_notice)
	return _modal_box

func _message(text: String) -> void:
	if is_instance_valid(_notice): _notice.text=text
	elif is_instance_valid(_title_notice) and _title_screen.visible: _title_notice.text=text
	else: _toast=text;_toast_until=Time.get_ticks_msec()+4000

func _close_dialog() -> void:
	_challenge=null
	_challenge_notice=null
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
		elif not new_game and not row.empty:
			for checkpoint: Dictionary in row.checkpoints:
				_add_checkpoint_choice(line, id, checkpoint)
		if not new_game and not row.empty: line.add_child(TDUI.button("删除",_confirm_delete_slot.bind(id)))
	if new_game: box.add_child(TDUI.button("导入旧进度（原文件保留）",func()->void:_enter_game(import_legacy,"正在导入旧进度……")))
	box.add_child(TDUI.label("每场剧情结束或进入断章时更新剧情存档。每次睡下更新每日存档。",TDUI.FONT_CAPTION,TDUI.MUTED))

func _add_checkpoint_choice(line: HBoxContainer, id: String, checkpoint: Dictionary) -> void:
	var kind := str(checkpoint.kind)
	var title_value := "剧情存档" if kind==TDProfileStore.STORY else ("每日存档" if kind==TDProfileStore.DAILY else "旧存档")
	if checkpoint.ok:
		var detail := str(checkpoint.get("story_title", "第 %d 场" % int(checkpoint.chapter))) if kind==TDProfileStore.STORY else "第 %d 天" % int(checkpoint.day)
		line.add_child(TDUI.button(title_value+" · "+detail,func()->void:_enter_game(load_game.bind(id,kind),"正在载入存档……")))
	elif checkpoint.code!="UNSUPPORTED_VERSION":
		if checkpoint.get("backup_available",false):
			line.add_child(TDUI.button("恢复"+title_value+"备份",_recover_slot.bind(id,false,kind)))
		if checkpoint.get("temporary_available",false):
			line.add_child(TDUI.button("恢复"+title_value+"临时档",_recover_slot.bind(id,true,kind)))

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

func create_game(id: String, name_value: String="小镇食堂", use_revised_story: bool = true) -> TDOutcome:
	if slots.load_slot(id).code!="NOT_FOUND": return _outcome(TDOutcome.new(false,"SLOT_OCCUPIED","这个存档位已有内容，请选择空位。"))
	var next:=TDGameProfile.new()
	if not next.error.ok:
		next.close()
		return _outcome(next.error)
	next.slot_id=id;next.title=name_value.strip_edges() if not name_value.strip_edges().is_empty() else "小镇食堂";next.persistence=slots.save_slot
	if use_revised_story or not OS.has_feature("editor"):
		next.use_revised_mainline()
	else: next.story.begin()
	next.branches.install_completed_storefronts()
	_activate(next,true)
	return TDOutcome.new(true,"NEW_GAME")

func load_game(id: String, kind: String = "latest") -> TDOutcome:
	var saved:=slots.load_slot(id,kind)
	if not saved.ok: return _outcome(saved)
	var next:=TDGameProfile.new()
	if not next.error.ok: next.close();return _outcome(next.error)
	var result:=next.restore(saved.data)
	if not result.ok: next.close();return _outcome(result)
	var checkpoint := str(saved.data.get("checkpoint",""))
	var migrated := next.map_migrated_on_load or next.region_migrated_on_load or next.jiangnan_migrated_on_load or next.regions_settled_on_load
	if migrated:
		var backup := slots.backup_map_migration(id, next.region_migrated_on_load, next.jiangnan_migrated_on_load, next.regions_settled_on_load, checkpoint)
		if not backup.ok:
			next.close()
			return _outcome(backup)
	var story_migrated := next.use_revised_mainline()
	next.branches.install_completed_storefronts()
	# Legacy manual saves can contain a time during the preparation day.
	if checkpoint != TDProfileStore.STORY and next.shop.snapshot().phase == "PREPARE":
		next.characters.clock.minute = TDWorldDayClock.START_MINUTE
	next.persistence=slots.save_slot
	_activate(next, story_migrated and next.characters.clock.closed_day!=next.characters.clock.day, checkpoint)
	if migrated: _message(result.message+"原档已留迁移前备份。")
	elif story_migrated: _message("已载入修订主线。旧档的经营进度已保留。")
	return result

func continue_game() -> void:
	if _entry_busy: return
	_enter_game(_load_latest, "正在载入最近的存档……")

func _load_latest() -> TDOutcome:
	var id:=slots.latest()
	if id.is_empty():
		return TDOutcome.new(false, "NO_VALID_SLOT", "没有可继续的存档，请检查载入列表。")
	return load_game(id)

func _recover_slot(id: String, temporary: bool, kind: String = "") -> void:
	var result:=slots.recover_slot(id,temporary,kind)
	if result.ok: load_game(id,kind)
	else: _outcome(result)

func _activate(next: TDGameProfile,first_entry:bool=false,checkpoint_kind: String="") -> void:
	_close_dialog();_dispose_game();profile=next;_generation+=1
	_saved_story_cursor=TDRevisedMainline.checkpoint_cursor(profile.story.revised)
	_story_save_error=""
	_story_save_retry_at=0
	visiting_town=str(profile.commerce.state.home)
	_story_supply_checked=false
	_story_frozen=false;_night_closing=false
	_title_screen.hide();_last_phase=str(profile.shop.snapshot().phase)
	town=TDTownWorld.new();town.player_mode=true;town.session=profile.world
	town.transaction_sink=profile.world_transaction;town.external_factory_clock=true;town.management_menus=true
	town.balance_reader=func()->int:return int(profile.shop.snapshot().money_cents)
	town.commercial_refresh=profile.sync_commercial_map
	town.luo_anchor=func() -> Vector2: return guide.journey._palace() if guide!=null else Vector2.INF
	town.hero_name=profile.title;town.story=profile.story;town.story_effect.connect(_apply_story)
	town.characters=profile.characters;town.homecoming=profile.residence
	town.status_reported.connect(_message)
	town.restaurant_requested.connect(func()->void:travel("restaurant"));town.place_requested.connect(_place);town.pause_requested.connect(show_pause);add_child(town)
	restaurant=TDRestaurantWorld.new();restaurant.player_mode=true;restaurant.floor_service=true;restaurant.session=profile.world;restaurant.layout=profile.layout;restaurant.business=profile.shop
	profile.shop.table_service_enabled=true
	restaurant.characters=profile.characters
	restaurant.decoration_progression=profile.progression
	restaurant.status_reported.connect(_message)
	restaurant.object_requested.connect(_object);restaurant.pause_requested.connect(show_pause);add_child(restaurant)
	restaurant.bind_dining_clock()
	restaurant.restore_visit_boundary()
	cottage=TDCottageWorld.new();cottage.object_requested.connect(_object);add_child(cottage)
	kitchen_view=TDShopView.new();kitchen_view.embedded=true;kitchen_view.shop=profile.shop;kitchen_view.day_san=profile.world.san
	kitchen_view.save_path=profile_root.path_join(profile.slot_id+"-runtime")
	kitchen_view.back_requested.connect(func()->void:travel("restaurant"));kitchen_view.pause_requested.connect(show_pause);add_child(kitchen_view)
	kitchen_view.kitchen.auto_advance=automatic_time
	kitchen_view.active_time_advanced.connect(_on_active_time)
	kitchen_view.external_time_boundary=_world_time_boundary
	kitchen_view.external_interactive=func()->bool: return is_instance_valid(branch_visit) and branch_visit.presented and branch_visit.shop_view.kitchen.music_audible()
	profile.kitchen_checkpoint=_all_kitchens_ready
	town.sync_characters(0.0,profile.shop.snapshot().orders)
	guide=TDStoryGuide.new();guide.shell=self;add_child(guide)
	town.crowd_label=_crowd_label.bind("chengdu")
	town.crowd_requested.connect(_talk_to_crowd.bind("chengdu"))
	kitchen_view.dish_finished.connect(guide.journey.record_practice)
	travel("cottage" if profile.has_residence() and not first_entry else "town",not first_entry)
	if not profile.has_residence() or first_entry: town.spawn_at_harbor()
	if not first_entry: _wake_at_rest_site(checkpoint_kind)
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
	if destination=="kitchen" and previous_location=="restaurant" and guide!=null and guide.journey.cursor()==1:
		var player := kitchen_view.kitchen.world._player
		player.position=TDKitchenWorld.DOOR_POS+Vector2(0,-34)
		player.velocity=Vector2.ZERO
		player.face(Vector2.UP)
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
		"town": travel("town")
		"kitchen":
			if guide!=null and guide.journey.waiting_at_first_kitchen_door():
				_message("等阿铃走到后厨门口。")
				return
			travel(action)
		"menu": show_menu()
		"ledger": show_ledger()
		"decorate":
			if not profile.at_boundary(): _outcome(TDOutcome.new(false,"SHOP_OPEN","打烊后才能布置餐厅。"));return
			restaurant._toggle_edit()
		"rest": show_rest()
		"hire": show_crew()
		"recipes": open_atlas()

func _place(kind: String, id: String) -> void:
	if kind in TDInteractionRange.RESIDENTIAL_KINDS: return
	if not profile.story.revised.is_empty() and guide.journey.home_landmark(id): return
	if id.begins_with("player-branch:"): _outcome(enter_branch(id))
	elif kind=="cottage":
		if profile.residence.stage=="door": guide.present_home("home_door")
		else: travel("cottage")
	elif kind=="harbor": show_harbor()
	elif kind=="hotel":
		_offer_rest(str(profile.world._plot_by_id(id).get("name","南埠客栈")),"chengdu")
	elif kind in TDTravelCatalog.SIGHT_KINDS:
		_show_sight(profile.world._plot_by_id(id),"chengdu")
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
	if profile.characters.clock.closed_day==profile.characters.clock.day:
		_message("今日客运已结束，休息到明早后可再来乘船。")
		return
	var destinations := TDTravelCatalog.IDS.filter(func(id: String) -> bool: return id!=visiting_town and _story_passenger_route(id))
	if destinations.is_empty():
		_message("暂无航线开放。航线随主线解锁，可按 J 查看任务。")
		return
	var box := _dialog("港口 · 小镇间客运",true)
	box.add_child(TDUI.label("客运免费，即时抵达。",TDUI.FONT_BODY))
	for id: String in destinations:
		var row := TDTravelCatalog.info(id)
		box.add_child(TDUI.button("前往 "+str(row.name),func() -> void: _outcome(voyage(id))))
	if profile.shop.current_phase() in ["OPEN","DRAINING"]:
		box.add_child(TDUI.label(kitchen_view.staff_status(),TDUI.FONT_BODY,TDUI.ORANGE))

func _story_passenger_route(destination: String) -> bool:
	if not profile.town_map_unlocked(destination): return false
	var state := profile.story.revised
	if state.is_empty() or state.port_reopened: return true
	return guide.journey.DOCK_TOWN.get(int(state.cursor))==destination

func _story_lodging() -> String:
	var state := profile.story.revised
	if state.is_empty(): return ""
	if state.has("lodging"): return str(state.lodging)
	var chapter := int(state.cursor)
	if chapter in [8,9,10,11,12]: return "paris"
	if chapter in [13,14,15,16]: return "tokyo"
	return ""

func voyage(destination: String) -> TDOutcome:
	if profile==null or location not in ["town","voyage"]: return TDOutcome.new(false,"NOT_AT_PORT")
	if profile.characters.clock.closed_day==profile.characters.clock.day: return TDOutcome.new(false,"NIGHT_CLOSED","今天已结束，请先休息。")
	if guide!=null and guide.presenting(): return TDOutcome.new(false,"STORY_BUSY")
	if not _story_passenger_route(destination): return TDOutcome.new(false,"PASSENGER_ROUTE_LOCKED","请先完成当前主线。")
	if profile.branches.training_open(): return TDOutcome.new(false,"SHOP_OPEN","请先到当地餐厅打烊，再乘船。")
	var at_port: bool=false
	if visiting!=null: at_port=visiting.nearby().get("kind")=="harbor"
	else:
		var feet: Vector2=(town._player.position-town._origin())/town.cell_size()
		at_port=TDHarbor.is_near_departure(town.session.town_map,feet)
	if not at_port: return TDOutcome.new(false,"NOT_AT_PORT","请到港口柜台乘船。")
	var arrivals: Dictionary={}
	for id: String in TDTravelCatalog.IDS: arrivals[id]="harbor."+id+".arrival"
	var request:=TDHarbor.departure_request(destination,visiting_town,TDTravelCatalog.IDS,arrivals,false)
	if not request.ok: return request
	return _arrive(destination)

func _arrive(destination: String) -> TDOutcome:
	if not profile.town_map_unlocked(destination): return TDOutcome.new(false,"PASSENGER_ROUTE_LOCKED","这座小镇还未随主线开放。")
	var next_map:=TDTravelCatalog.map_for(profile,destination)
	if next_map==null: return TDOutcome.new(false,"DESTINATION_NOT_READY")
	_close_dialog();_clear_branch_visit();_clear_visit()
	if destination==str(profile.commerce.state.home):
		travel("town");town.spawn_at_harbor()
	else:
		visiting=TDTravelWorld.new();visiting.town_id=destination;visiting.map=next_map
		visiting.harbor_requested.connect(show_harbor);visiting.landmark_requested.connect(_travel_landmark)
		_connect_visit_residents()
		visiting.crowd_label=_crowd_label.bind(destination)
		visiting.crowd_requested.connect(_talk_to_crowd.bind(destination))
		town.set_presented(false);restaurant.set_floor_cover(true);cottage.set_presented(false);kitchen_view.hide()
		location="voyage";add_child(visiting)
	visiting_town=destination;_lock_controls(true)
	if guide!=null and not profile.story.revised.is_empty(): guide.journey.arrived(destination)
	return TDOutcome.new(true,"ARRIVED",TDTravelCatalog.info(destination).name)

func _connect_visit_residents() -> void:
	visiting.characters = profile.characters
	visiting.resident_requested.connect(guide.show_resident)

func _arrive_at_lodging(destination: String) -> void:
	if not _arrive(destination).ok: return
	var hotel := visiting.landmark_access("hotel")
	if hotel.is_finite():
		visiting.player.position=hotel
		visiting.camera.position=hotel
		visiting.camera.reset_smoothing()

func _enter_story_branch(destination: String) -> void:
	if visiting==null or visiting_town!=destination or location!="voyage": return
	var id := profile.branches.preset_in(destination)
	var door := visiting.landmark_access("player_diner",id)
	if not door.is_finite(): return
	visiting.player.position=door
	_outcome(enter_branch(id))

func _clear_visit() -> void:
	if visiting!=null:
		visiting.close();remove_child(visiting);visiting.queue_free();visiting=null

func _travel_landmark(plot: Dictionary) -> void:
	if not TDInteractionRange.facility(plot): return
	if plot.has("branch_id"): _outcome(enter_branch(str(plot.branch_id)));return
	if plot.get("kind")=="hotel":
		_offer_rest(TDTravelCatalog.label(plot,visiting_town),visiting_town)
		return
	if not profile.story.revised.is_empty() and guide.journey.remote_landmark(plot): return
	if plot.get("kind")=="market" and visiting_town in ["paris","tokyo"]:
		_show_market_counter(TDTravelCatalog.label(plot,visiting_town),visiting_town)
		return
	if visiting_town=="paris" and plot.get("kind")=="bank":
		show_bank(TDTravelCatalog.label(plot,visiting_town))
		return
	if plot.get("kind") in TDTravelCatalog.SIGHT_KINDS:
		_show_sight(plot,visiting_town)
		return
	var box:=_dialog(TDTravelCatalog.label(plot,visiting_town),true)
	box.add_child(TDUI.label(TDTravelCatalog.info(visiting_town).caption,TDUI.FONT_BODY))
	box.add_child(TDUI.label("这里的街坊经营着自己的生活。当地故事与室内互动将在后续加入。\n采购合作仍需商路推荐；可在主店账本查看世界行情。",TDUI.FONT_BODY,TDUI.MUTED))

func _show_sight(plot: Dictionary, town_id: String) -> void:
	var talk := TDDialogue.new()
	talk.context = {"kind":"landmark","zone":str(plot.get("kind",""))}
	talk.add_line(TDTravelCatalog.label(plot,town_id),"",TDTravelCatalog.sight_description(plot,town_id))
	var recovery := TDSanRules.recovery(talk.context.zone)
	if town_id=="chengdu" and not recovery.is_empty() and profile.at_boundary():
		talk.add_choice([
			{"id":"rest","label":"在这里逛一逛 · ¥%d · %.0f 小时" % [recovery.cost,recovery.hours],"text":""},
			{"id":"leave","label":"继续赶路","text":""},
		])
	guide.show_talk(talk)

func show_world_map(reveal_town: String = "") -> TDTravelMapView:
	if profile==null: return null
	var box:=_dialog("世界地图",true);_map_open=true;_notice.hide()
	var panel: PanelContainer=box.get_parent().get_parent().get_parent()
	panel.position=Vector2(40,42);panel.size=Vector2(1200,716)
	var scroll:=box.get_parent() as ScrollContainer;scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	var view:=TDTravelMapView.new();view.configure(profile);view.town_id=visiting_town
	if profile.story.tracked and not profile.story.revised.is_empty():
		view.tracked_paris_site=guide.journey.next_paris_resident()
	if town._crowd_stands!=null:
		view.live_challenge_locations["chengdu"]=town._crowd_stands.map_locations(town._origin(),town.cell_size())
	if visiting!=null and visiting._crowd_stands!=null:
		view.live_challenge_locations[visiting_town]=visiting._crowd_stands.map_locations(Vector2.ZERO,visiting.cell_size)
	if branch_visit!=null:
		var branch: Dictionary=profile.branches.state.stores[branch_visit.store_id]
		view.marker=Vector2(branch.rect[0],branch.rect[1])+Vector2(branch.rect[2],branch.rect[3])*.5
	elif visiting!=null: view.marker=visiting.player.position/visiting.cell_size
	elif location=="town": view.marker=(town._player.position-town._origin())/town.cell_size()
	else:
		var id: String="player_cottage" if location=="cottage" else "player_diner"
		var p: Dictionary=profile.world._plot_by_id(id)
		if not p.is_empty(): view.marker=Vector2(p.x,p.y)+Vector2(p.w,p.h)*.5
	box.add_child(view)
	var bar:=HBoxContainer.new();box.add_child(bar)
	bar.add_child(TDUI.button("世界全览",view.reset_view));bar.add_child(TDUI.button("当前位置",view.focus_town.bind(visiting_town)))
	for id: String in view.challenge_towns:
		bar.add_child(TDUI.button(str(TDTravelCatalog.info(id).name)+"挑战",view.focus_town.bind(id)))
	if not reveal_town.is_empty(): view.call_deferred("reveal_story_town",reveal_town)
	return view

func show_market() -> void:
	var stall:=profile.world.town_map.market(profile.world.selected_market)
	var title:=String(stall.get("name","街坊菜市")) if not stall.is_empty() else "街坊菜市"
	_show_market_counter(title)

func _show_market_counter(title: String, region: String = "") -> void:
	if not profile.can_leave_shop(): _outcome(TDOutcome.new(false,"SHOP_OPEN","营业中不能采购。"));return
	var box:=_dialog(title+" · 现货采购")
	if profile.shop.snapshot().phase=="SETTLED":
		box.add_child(TDUI.label("今天已经打烊。回店休息后，明早再来挑新鲜食材。",TDUI.FONT_BODY));return
	var town_id: String=profile.commerce.state.home if region.is_empty() else region
	var foods:=box
	var spices:=box
	if region.is_empty():
		var forecast:=profile.shop.visitor_forecast()
		box.add_child(TDUI.label("用餐高峰 08–10 / 11–13 / 17–19 · 少量错峰
持续营业至主动打烊或02:00；错过的时段不补客。",TDUI.FONT_BODY,TDUI.MUTED))
		box.add_child(TDUI.label("从现在开门预计 %d—%d 位客人 · 买好食材后回店挂牌营业"%[forecast.min_visitors,forecast.max_visitors],TDUI.FONT_BODY,TDUI.ORANGE))
		box.add_child(TDUI.label("此处只出售本镇有货源、且已解锁的食材与调料。",TDUI.FONT_BODY,TDUI.MUTED))
		var spoiled:=profile.shop.spoiled_today()
		for id: String in spoiled:
			box.add_child(TDUI.label("今日过期：%s %.2f%s，已清理。"%[_ingredient_name(id),float(spoiled[id])/1000,profile.shop.stock_info(id).unit],TDUI.FONT_BODY,TDUI.ORANGE))
	else:
		var tabs:=TabBar.new()
		tabs.add_tab("食材");tabs.add_tab("调料");box.add_child(tabs)
		foods=VBoxContainer.new();spices=VBoxContainer.new()
		box.add_child(foods);box.add_child(spices);spices.hide()
		tabs.tab_changed.connect(func(index:int)->void:
			foods.visible=index==0
			spices.visible=index==1)
	var offered := profile.shop.local_market_ids(town_id)
	if offered.is_empty(): box.add_child(TDUI.label("学会当地菜谱后，可回来采购所需食材。",TDUI.FONT_BODY))
	for id: String in offered:
		var info:=profile.shop.stock_info(id)
		_add_market_row(spices if info.condiment else foods,id,info,town_id,region)
	if region.is_empty():
		box.add_child(TDUI.button("资金困难 · 申请应急补助",func()->void:_outcome(profile.shop.claim_grant())))
		box.add_child(TDUI.button("查看菜单供货",show_supplier))

func _add_market_row(shelf: VBoxContainer, id: String, info: Dictionary, town_id: String, region: String) -> void:
	var local_store := profile.branches.preset_in(town_id) if not region.is_empty() else ""
	var row:=HBoxContainer.new();shelf.add_child(row)
	row.add_child(TDIngredientIcon.make(id))
	var caption:=TDUI.label("",TDUI.FONT_BODY)
	caption.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(caption)
	var amount:=SpinBox.new();amount.min_value=1;amount.max_value=30;amount.step=1;amount.value=1;row.add_child(amount)
	var purchase:=Button.new();purchase.custom_minimum_size.y=48;purchase.focus_mode=Control.FOCUS_NONE;row.add_child(purchase)
	var refresh:=func()->void:
		var market: Dictionary=profile.commerce.state.markets[town_id]
		var stock := profile.shop.available(id)
		var destination := "店内"
		if not local_store.is_empty():
			stock = int(profile.branches.state.stores[local_store].inventory.get(id,0))
			destination = "本地餐厅"
		caption.text="%s · %s %.2f%s · ¥%.2f/%s · 保质%d天"%[_ingredient_name(id),destination,float(stock)/1000,info.unit,float(market.price[id])/100,info.unit,info.shelf_days]
		var packs:=floori(float(market.stock[id])/1000)
		amount.max_value=clampi(packs,1,30)
		purchase.disabled=packs==0
		caption.text+=" · 现货 %d%s"%[packs,info.unit]
		purchase.text="售罄" if purchase.disabled else "购买"
	refresh.call()
	purchase.pressed.connect(func()->void:
		var result:=profile.buy({id:int(amount.value)*1000},region,local_store)
		_outcome(result)
		refresh.call())
	row.tooltip_text="按%s购买，入库起保质%d天；冰箱显示余量和剩余天数。"%[info.unit,info.shelf_days]

func show_supplier() -> void:
	if profile==null: return
	if not profile.story_feature_available("suppliers"):
		_message(_expansion_hint("suppliers"))
		return
	_management_panel("供应商 · 次晨配送",TDManagementPanels.SupplierPanel.new())

func _town_name(id: String) -> String:
	if profile.commerce.config.towns.has(id): return str(profile.commerce.config.towns[id].name)
	var town_data:Dictionary=profile.world.catalog.town(id)
	return str(town_data.get("nickname",id))

func show_remote_market(town_id: String) -> void:
	if town_id not in profile.commerce.state.routes: _outcome(TDOutcome.new(false,"ROUTE_LOCKED","尚未收到这条商路的推荐。"));return
	var box:=_dialog(_town_name(town_id)+" · 当日报价")
	var market:Dictionary=profile.commerce.state.markets[town_id]
	var shipping:=profile.commerce.freight(town_id)
	var state:=profile.shop.snapshot()
	for id: String in profile.shop.market_ids(town_id):
		var row:=HBoxContainer.new();box.add_child(row)
		row.add_child(TDIngredientIcon.make(id))
		var info:=profile.shop.stock_info(id)
		var label:=TDUI.label("%s · 现货%.1f%s · 含运费¥%.2f/%s"%[_ingredient_name(id),float(market.stock[id])/1000,info.unit,float(int(market.price[id])+shipping)/100,info.unit],TDUI.FONT_BODY)
		label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(label)
		var amount:=SpinBox.new();amount.min_value=1;amount.max_value=16;amount.value=1;row.add_child(amount)
		var token: String="remote-ui:%s:%d:%s"%[state.run_id,state.serial+1,id]
		var buy_button:=TDUI.button("预订",func()->void:
			var outcome:=profile.order_remote(id,town_id,int(amount.value)*1000,token)
			_outcome(outcome)
			if outcome.ok: show_remote_market(town_id))
		row.add_child(buy_button)
	box.add_child(TDUI.button("返回商路",show_supplier))

func _ingredient_name(id: String) -> String:
	return str(profile.service.cooking.ingredient_data(id).get("name",id))

func show_menu() -> void:
	profile.commerce.attach_map(profile.world.town_map.plots,profile.world.map_version)
	var state:=profile.shop.snapshot()
	var box:=_dialog("今日菜单 · 营业牌")
	var overview := TDManagementPanels.card(box,Color("ad7745"))
	var phases := {"PREPARE":"筹备中","OPEN":"营业中","DRAINING":"打烊收尾","SETTLED":"已打烊"}
	var clock := "%02d:%02d" % [int(profile.characters.clock.minute)/60%24,int(profile.characters.clock.minute)%60]
	overview.add_child(TDUI.label("第 %d 天  ·  %s  ·  %s" % [int(state.day),clock,phases[state.phase]],TDUI.FONT_SECTION,TDUI.INK))
	if state.phase in ["OPEN","DRAINING"]:
		box.add_child(TDUI.label("正在营业。打烊后可出门采购、研究菜谱和布置餐厅。",TDUI.FONT_BODY))
		box.add_child(TDUI.button("提前打烊",func()->void:_outcome(profile.shop.close_early());_close_dialog()))
		return
	if state.phase=="SETTLED":
		box.add_child(TDUI.button("查看今日账本",show_ledger))
		box.add_child(TDUI.button("店铺",show_branch))
		return
	var demand:=TDUI.label("",TDUI.FONT_BODY,TDUI.INK)
	overview.add_child(demand)
	var table := TDManagementPanels.card(box,Color("ad7745"))
	var columns := HBoxContainer.new()
	table.add_child(columns)
	var names := TDUI.label("供应菜品",TDUI.FONT_BODY,TDUI.INK)
	names.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	columns.add_child(names)
	for header: Array in [["售价",150],["库存",125]]:
		var caption := TDUI.label(header[0],TDUI.FONT_BODY,TDUI.INK)
		caption.custom_minimum_size.x=header[1]
		columns.add_child(caption)
	table.add_child(HSeparator.new())
	for id: String in state.menu:
		if not profile.shop.is_unlocked(profile.shop.family_id(id)): continue
		var row:=HBoxContainer.new();table.add_child(row)
		var enabled:=CheckBox.new();enabled.text=profile.shop.recipe_name(id)
		enabled.add_theme_color_override("font_color",TDUI.INK)
		enabled.add_theme_color_override("font_hover_color",TDUI.INK);enabled.button_pressed=state.menu[id].enabled;enabled.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(enabled)
		var price:=SpinBox.new();price.min_value=.01;price.max_value=10000;price.step=.5;price.value=float(state.menu[id].price_cents)/100;price.prefix="¥ ";price.custom_minimum_size=Vector2(150,52);row.add_child(price)
		enabled.toggled.connect(func(value:bool)->void:_outcome(profile.shop.set_menu(id,value,roundi(price.value*100))))
		price.value_changed.connect(func(value:float)->void:_outcome(profile.shop.set_menu(id,enabled.button_pressed,roundi(value*100))))
		var stock:=TDUI.label("有料" if profile.shop.menu_available(id) else "缺料",TDUI.FONT_BODY,Color("385c41") if profile.shop.menu_available(id) else Color("93492c"))
		stock.custom_minimum_size.x=125;stock.autowrap_mode=TextServer.AUTOWRAP_OFF;row.add_child(stock)
	overview.add_child(TDUI.label("客流高峰 08–10 / 11–13 / 17–19",TDUI.FONT_CAPTION,TDUI.INK))
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
	var actions := HBoxContainer.new()
	box.add_child(actions)
	var open_button := TDUI.button("开门营业",start_day)
	var lock_reason := profile.business_lock_reason(str(profile.commerce.state.home))
	if not lock_reason.is_empty():
		open_button.disabled = true
		box.add_child(TDUI.label(lock_reason, TDUI.FONT_BODY))
	open_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	actions.add_child(open_button)
	actions.add_child(TDUI.button("店铺",show_branch))

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
	seconds=profile.branches.next_live_boundary(seconds,profile.characters.clock.minute)
	return minf(seconds,left) if left>0.0000001 else seconds

func _on_active_time(seconds: float) -> void:
	if not automatic_time or profile==null or atlas!=null or get_tree().paused or (town!=null and town.story_dialogue_open()): return
	if _challenge!=null: return
	profile.world.tick_factories(seconds)
	advance_world_time(seconds)

func advance_world_time(seconds: float) -> void:
	if profile==null or get_tree().paused or atlas!=null or _challenge!=null or (town!=null and town.story_dialogue_open()): return
	var before: float=profile.characters.clock.minute
	for interior: TDBranchInterior in _branch_interiors.values(): interior.advance(seconds)
	var due:=profile.characters.clock.advance(seconds)
	profile.branches.advance_live_markets(profile.characters.clock.minute)
	profile.suppliers.advance_active_time(seconds,maxf(0.0,profile.characters.clock.minute-before),false)
	if town!=null: town.sync_characters(maxf(0.0,profile.characters.clock.minute-before),profile.shop.day_orders(),before)
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
	var cleaned := _settle_for_rest()
	if not cleaned.ok: _night_closing=false;return _outcome(cleaned)
	clock.closed_day=clock.day
	var lodging := visiting_town if location in ["voyage","branch"] and visiting_town in ["paris","tokyo"] else _story_lodging()
	if lodging in ["paris","tokyo"]: _arrive_at_lodging(lodging)
	elif profile.has_residence(): travel("cottage",true)
	else:
		profile.invite_home("late");travel("town");guide.begin_homecoming()
		if profile.has_residence(): travel("cottage",true)
	_night_closing=false
	_message(("已到02:00，请在旅馆休息。" if not lodging.is_empty() else ("已到02:00，回小屋休息后保存。" if profile.has_residence() else "夜深了，阿铃会带你找个落脚处。"))+cleaned.message)
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
	var account:=profile.commerce.society.bank.account("player")
	box.add_child(TDUI.label("钱庄存款 ¥%.2f · 贷款本金 ¥%.2f · 未付利息 ¥%.2f\n借还本金和存取款不计入经营利润。商业街钱庄可办理。"%[float(account.deposit_cents)/100,float(account.principal_cents)/100,float(account.interest_cents)/100],TDUI.FONT_BODY))
	if not economy.books.is_empty():
		var last: Dictionary=economy.books.back()
		box.add_child(TDUI.label("利润税 ¥%.2f · 本日利息 ¥%.2f · 税前利润 ¥%.2f"%[float(last.get("tax_cents",0))/100,float(last.get("interest_cents",0))/100,float(last.get("profit_before_tax_cents",last.profit_cents))/100],TDUI.FONT_BODY))
	var society: Dictionary=profile.commerce.society.state
	if not society.daily.is_empty(): box.add_child(TDUI.label("三镇家庭：工资 ¥%.2f · 外食 ¥%.2f · 基本生活 ¥%.2f\n未满足基本生活支出 ¥%.2f（没有暗中补款）"%[float(society.daily.wages_cents)/100,float(society.daily.dining_cents)/100,float(society.daily.necessities_cents)/100,float(society.daily.unmet_needs_cents)/100],TDUI.FONT_BODY,TDUI.MUTED))
	box.add_child(TDUI.label("本镇公共账户 ¥%.2f · 工资税与利润税收入分别记账"%(float(society.public[economy.home])/100),TDUI.FONT_BODY,TDUI.MUTED))

func show_levels() -> void:
	if profile==null: return
	var box := _dialog("经营等级 · 升级奖励")
	var view := TDLevelRewardsView.new()
	box.add_child(view);view.setup(profile.progression,int(profile.research.snapshot().points))
	if not profile.at_boundary(): box.add_child(TDUI.label("查阅期间营业继续；按 Esc 返回。",TDUI.FONT_CAPTION,TDUI.MUTED))

func show_bank(title: String = "商业街钱庄") -> void:
	if profile==null: return
	if not profile.at_boundary():
		_message("银行在营业筹备或当日结算后办理存取款和借还款。")
		return
	var target:=profile
	var box:=_dialog(title)
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
			if result.ok: show_bank(title)))
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
	if not profile.story_feature_available("employees"):
		_message(_expansion_hint("employees"))
		return
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
	if not profile.story_feature_available("branches"):
		_message(_expansion_hint("branches"))
		return
	_open_store_panel()

func _expansion_hint(id: String) -> String:
	if profile.story.revised.is_empty(): return "按 J 查看当前主线任务。"
	return TDRevisedMainline.expansion_hint(id)

func _open_store_panel(training_id: String = "") -> TDBranchPanel:
	var box := _dialog("店铺管理",true)
	_notice.hide()
	var frame: PanelContainer=box.get_parent().get_parent().get_parent()
	frame.position=Vector2(40,28);frame.size=Vector2(1200,744)
	var panel := TDBranchPanel.new()
	box.add_child(panel)
	panel.configure(profile,training_id)
	if guide!=null: panel.tab_viewed.connect(guide.journey.store_tab_viewed)
	panel.changed.connect(func()->void:
		_refresh_branch_maps()
		if kitchen_view!=null: kitchen_view.refresh(true))
	return panel

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
	_offer_rest("小屋 · 床")

const HOTEL_RATES := {"chengdu": 600, "paris": 1000, "tokyo": 800}

func _hotel_fee(town_id: String) -> int:
	if town_id.is_empty() or (town_id in ["paris","tokyo"] and town_id==_story_lodging()): return 0
	return int(HOTEL_RATES[town_id])

func _offer_rest(title: String, hotel_town: String = "") -> void:
	var box:=_dialog(title,true)
	var fee := _hotel_fee(hotel_town)
	if not hotel_town.is_empty():
		var price := "旅费已由主线行程安排。" if fee==0 else "房费 ¥%.2f / 晚 · 余额 ¥%.2f" % [fee/100.0, float(profile.shop._s.money_cents)/100.0]
		box.add_child(TDUI.label(price,TDUI.FONT_SECTION))
	if profile.shop.current_phase() in ["OPEN","DRAINING"] or profile.branches.training_open():
		box.add_child(TDUI.label("现在休息会提前打烊。未上桌的订单将结束，冷食材退回库存，已经加热的半成品会清理。",TDUI.FONT_BODY))
	box.add_child(TDUI.label("睡觉时结算经营经验与升级，保存进度并休息至明早 08:00。",TDUI.FONT_BODY))
	var owner := profile
	var day := int(owner.shop._s.day)
	var action := TDUI.button("支付 ¥%.2f 并休息" % (fee/100.0) if fee>0 else "休息到明天",func() -> void:
		if not _rest_busy and profile==owner and int(owner.shop._s.day)==day: _sleep(hotel_town,fee))
	action.disabled = int(owner.shop._s.money_cents)<fee
	if action.disabled: box.add_child(TDUI.label("余额不足，无法支付房费。",TDUI.FONT_BODY,TDUI.ORANGE))
	box.add_child(action)

func _settle_for_rest() -> TDOutcome:
	if not profile.research._active.is_empty():
		return TDOutcome.new(false,"RESEARCH_BUSY","请先退出正在进行的研习。")
	for interior: TDBranchInterior in _branch_interiors.values():
		var branch_cleanup := interior.shop_view.finish_night()
		if not branch_cleanup.ok: return branch_cleanup
	var cleaned := kitchen_view.finish_night()
	if not cleaned.ok: return cleaned
	var settled := profile.shop.close_for_night()
	if not settled.ok: return settled
	# The branch network closes live orders and clears their passes during the shared settlement.
	restaurant.finish_night()
	return cleaned

func _sleep(hotel_town: String, fee: int) -> void:
	_rest_busy = true
	var result := _settle_for_rest()
	if not result.ok:
		_rest_busy = false
		_outcome(result)
		return
	var before := profile.shop.snapshot()
	if fee>0:
		result = profile.shop.world_adjustment(-fee,"hotel:%s:%d" % [hotel_town,int(before.day)],"旅馆住宿")
		if not result.ok:
			_rest_busy = false
			_message("日结后余额不足，房费未扣除。")
			return
	_update_story_checkpoint(true)
	result = profile.next_day()
	if not result.ok:
		if fee>0: profile.shop.restore(before)
		_rest_busy = false
		_outcome(result)
		return
	_rest_report = result.data
	profile.rest_town = hotel_town
	kitchen_view._make_kitchen()
	kitchen_view.kitchen.auto_advance = automatic_time
	kitchen_view.refresh(true)
	_save_sleep_checkpoint()

func _wake_at_rest_site(checkpoint_kind: String = "") -> void:
	var lodging := profile.rest_town
	if checkpoint_kind==TDProfileStore.STORY or (checkpoint_kind.is_empty() and lodging.is_empty()):
		lodging = _story_lodging()
	if lodging in ["paris","tokyo"] and profile.town_map_unlocked(lodging):
		_arrive_at_lodging(lodging)
		if checkpoint_kind == TDProfileStore.STORY and TDRevisedMainline.training_town(profile.story.revised) == lodging:
			_enter_story_branch(lodging)
	elif lodging=="chengdu":
		travel("town")
		town.spawn_at_plot("hotel")
	elif profile.has_residence(): travel("cottage",true)
	else:
		travel("town")
		town.spawn_at_harbor()

func _save_sleep_checkpoint() -> void:
	var result := _write_checkpoint(TDProfileStore.DAILY)
	if result.ok:
		_close_dialog()
		if DisplayServer.get_name()=="headless":
			_wake_at_rest_site(TDProfileStore.DAILY)
			_finish_sleep_results()
		else:
			_pause(true)
			_lock_controls(false)
			var results := SleepResults.new()
			_sleep_results = results
			results.morning.connect(_wake_at_rest_site.bind(TDProfileStore.DAILY))
			results.finished.connect(_finish_sleep_results)
			add_child(results)
			results.present(_rest_report, profile.progression)
		return
	var box := _dialog("休息存档失败", true)
	(box.get_child(0).get_child(1) as Button).hide()
	box.add_child(TDUI.label("未能写入每日存档（%s）。可以重试，无需重复结算。" % result.code, TDUI.FONT_BODY))
	box.add_child(TDUI.button("重试保存", _save_sleep_checkpoint))
	box.add_child(TDUI.button("放弃并返回主菜单", go_title))

func _finish_sleep_results() -> void:
	_rest_busy = false
	_rest_report.clear()
	_sleep_results = null
	_pause(false)
	_lock_controls(true)

func _update_story_checkpoint(force: bool = false) -> void:
	var state := profile.story.revised
	var cursor := TDRevisedMainline.checkpoint_cursor(state)
	if cursor <= _saved_story_cursor: return
	var now := Time.get_ticks_msec()
	if not force and now < _story_save_retry_at: return
	var result := _write_checkpoint(TDProfileStore.STORY)
	if result.ok:
		_saved_story_cursor = cursor
		_story_save_error = ""
		_message("%s · 剧情已自动存档。" % TDRevisedMainline.checkpoint_title(state))
	else:
		_story_save_retry_at = now + 1000
		if _story_save_error != result.code:
			_story_save_error = result.code
			_message("剧情存档待写入。"+(result.message if not result.message.is_empty() else "将自动重试（%s）。" % result.code))

func _write_checkpoint(kind: String) -> TDOutcome:
	if profile==null: return TDOutcome.new(false,"NO_PROFILE")
	if profile.branches.training_open(): return TDOutcome.new(false,"SHOP_OPEN","请先结束当地营业，再保存。")
	if restaurant!=null: profile.layout=restaurant.layout
	return profile.save({},slots.save_slot.bind(kind),kind)

func save_game() -> TDOutcome:
	return TDOutcome.new(false,"AUTO_SAVE_ONLY","每场剧情结束、进入断章和睡下时自动存档。")

func _music_should_pause() -> bool:
	# Interaction panels freeze rules, not ambient music. Explicit pause still silences it.
	return get_tree().paused and (_modal==null or bool(_modal.get_meta("pauses_music",false)))

func show_pause() -> void:
	if profile==null: return
	var box:=_dialog("暂停",true)
	_modal.set_meta("pauses_music",true)
	box.add_child(TDUI.button("继续游戏",_close_dialog))
	box.add_child(TDUI.button("设置",show_settings))
	box.add_child(TDUI.button("返回主菜单",request_title))
	box.add_child(TDUI.label("每场剧情结束和睡下时自动存档。",TDUI.FONT_CAPTION,TDUI.MUTED))

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
	box.add_child(TDUI.label("未保存的进度将丢失。",TDUI.FONT_BODY))
	box.add_child(TDUI.button("确认返回主菜单",go_title))

func request_quit() -> void:
	if _quitting: return
	if profile==null: _finish_quit();return
	var box:=_dialog("退出游戏",true)
	box.add_child(TDUI.label("现在退出会回到最近的自动存档。",TDUI.FONT_BODY))
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
	if is_instance_valid(_sleep_results):
		remove_child(_sleep_results)
		_sleep_results.queue_free()
		_sleep_results=null
	_rest_report.clear()
	_clear_branch_visit()
	for interior: TDBranchInterior in _branch_interiors.values():
		interior.close();remove_child(interior);interior.queue_free()
	_branch_interiors.clear()
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
	box.add_child(TDUI.label("反引号 / Esc 返回 · ↑↓历史 · Tab补全 · 剧情结束和睡下时自动存档",TDUI.FONT_BODY,TDUI.MUTED))
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
	next.use_revised_mainline()
	next.branches.install_completed_storefronts()
	next._sync_recipes();next.persistence=slots.save_slot
	_activate(next)
	return TDOutcome.new(true,"LEGACY_IMPORTED")

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
	if not profile.branches.can_visit_store(id): return TDOutcome.new(false,"UNDER_CONSTRUCTION",profile.branches.status_text(id))
	var store: Dictionary=profile.branches.state.stores[id]
	if str(store.town_id)!=visiting_town: return TDOutcome.new(false,"WRONG_TOWN")
	var target: Dictionary=visiting.nearby() if visiting!=null else town.facing_plot()
	if str(target.get("branch_id",""))!=id: return TDOutcome.new(false,"NOT_NEAR_BRANCH","请靠近这家分店，按 E 进入。")
	if guide!=null and guide.presenting(): return TDOutcome.new(false,"STORY_BUSY")
	_close_dialog();_branch_return=visiting.player.position if visiting!=null else town._player.position
	town.set_presented(false);restaurant.set_floor_cover(true);cottage.set_presented(false);kitchen_view.hide()
	if visiting!=null: visiting.set_presented(false)
	if _branch_interiors.has(id): branch_visit=_branch_interiors[id];branch_visit.set_presented(true)
	else:
		branch_visit=TDBranchInterior.new();branch_visit.profile=profile;branch_visit.store_id=id
		branch_visit.exit_requested.connect(exit_branch);branch_visit.management_requested.connect(_branch_management)
		branch_visit.pause_requested.connect(show_pause)
		branch_visit.status_reported.connect(_message)
		add_child(branch_visit);_branch_interiors[id]=branch_visit
	location="branch";_lock_controls(true)
	return TDOutcome.new(true,"BRANCH_ENTERED","进入 "+str(store.name))

func _branch_management(tab: String) -> void:
	if branch_visit==null: return
	var id: String=branch_visit.store_id
	if tab=="decorate":
		if not profile.at_boundary() or profile.branches.training_open(id) or not branch_visit.kitchen_session.pending_orders().is_empty():
			_outcome(TDOutcome.new(false,"SHOP_OPEN","请先打烊，再布置这家餐厅。"))
			return
		branch_visit.dining._toggle_edit()
		return
	if profile.branches.has_local_operation(id):
		if tab in ["staff","menu"]: _show_training_desk(id)
		else: _manage_training_store(id,tab)
		return
	if not profile.story_feature_available("branches"): return
	var panel := _open_store_panel()
	panel.manage(id)
	panel.select_tab(tab)

func _show_training_desk(id: String) -> void:
	var store: Dictionary=profile.branches.state.stores[id]
	var box := _dialog("%s · 营业牌" % store.name,true)
	var already_open := profile.branches.training_open(id)
	if profile.branches.training_store()==id and not TDRevisedMainline.flag(profile.story.revised,"mentors_"+str(store.town_id)):
		box.add_child(TDUI.label("先去市集向当地厨师学几道菜。",TDUI.FONT_BODY))
	elif already_open:
		var close := TDUI.button("打烊并结算",func() -> void:
			var ready := _all_kitchens_ready()
			if not ready.ok: _outcome(ready);return
			if not branch_visit.kitchen_session.pending_orders().is_empty():
				_message("请先为已有的客人上完菜。")
				return
			if guide.journey.cursor()==8 and not TDRevisedMainline.flag(profile.story.revised,"paris_training_complete") and not branch_visit.dining.guest_nodes().is_empty():
				_message("请等客人用餐并离店后再打烊。")
				return
			var result := profile.shop.close_for_night()
			if result.ok: _close_dialog();_message("已打烊。账本可查，睡觉时结算经营经验。")
			else: _outcome(result))
		box.add_child(close)
	elif profile.shop.current_phase()=="PREPARE":
		box.add_child(TDUI.button("开门营业",func() -> void:
			var result := profile.branches.open_training(id)
			if result.ok:
				branch_visit.refresh_staff()
				_close_dialog()
			_outcome(result)))
	box.add_child(TDUI.button("菜单与价格",func() -> void:_manage_training_store(id,"menu")))
	box.add_child(TDUI.button("账本与库存",func() -> void:_manage_training_store(id,"books")))
	if profile.branches.can_manage_store(id):
		box.add_child(TDUI.button("店员与托管",func() -> void: _open_store_panel().manage(id)))

func _manage_training_store(id: String, tab: String) -> void:
	_open_store_panel(id).select_tab(tab)

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
	branch_visit.set_presented(false);branch_visit=null

func _all_kitchens_ready(checkpoint_kind: String = "") -> TDOutcome:
	var completed_recipe := ""
	# The seventh scene ends when the banquet is plated in the practice kitchen.
	if checkpoint_kind==TDProfileStore.STORY and guide.journey.cursor()==22:
		completed_recipe = str(profile.research.catalog.chart("C20").recipe_id)
	var ready:=kitchen_view.checkpoint_ready(completed_recipe)
	if not ready.ok: return ready
	for interior: TDBranchInterior in _branch_interiors.values():
		if not interior.kitchen_session.table_service.empty():
			return TDOutcome.new(false,"PASS_NOT_CLEAR",str(profile.branches.state.stores[interior.store_id].name)+"的出餐口还有待送菜品。")
		ready=interior.shop_view.checkpoint_ready()
		if not ready.ok: return TDOutcome.new(false,ready.code,str(profile.branches.state.stores[interior.store_id].name)+"："+ready.message)
	return TDOutcome.new(true,"KITCHENS_CLEAR")

func _refresh_branch_maps() -> void:
	if profile==null: return
	profile.sync_commercial_map()
	if branch_visit!=null: branch_visit.refresh_staff()
	if visiting==null: return
	var feet:=visiting.player.position;var id:=visiting_town
	_clear_visit()
	visiting=TDTravelWorld.new();visiting.town_id=id;visiting.map=TDTravelCatalog.map_for(profile,id)
	visiting.harbor_requested.connect(show_harbor);visiting.landmark_requested.connect(_travel_landmark)
	_connect_visit_residents()
	visiting.crowd_label=_crowd_label.bind(id)
	visiting.crowd_requested.connect(_talk_to_crowd.bind(id))
	add_child(visiting)
	if visiting._can_stand(feet): visiting.player.position=feet
	visiting.set_presented(location=="voyage");_lock_controls(_modal==null)
