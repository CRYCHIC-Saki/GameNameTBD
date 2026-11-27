class_name TDChallengePanel
extends VBoxContainer
## Owns one optional battle while the management overlay has the town paused.
signal close_requested
signal battle_view_changed(active: bool)
signal loadout_changed(next: Array[String])
signal story_finished(phase: int)
signal cooking_changed(active: bool)
signal match_finished(phase: int, opponent_id: String, town: String, site: String)
signal tutorial_finished(opponent_id: String)
signal cooking_tutorial_finished
const Action := TDChallengeBattle.Action
const Tutorial := TDChallengeBattle.Tutorial
const Skills := TDChallengeBattle.Skills
const Rules := TDChallengeBattle.Rules
const Icons := preload("res://src/challenge/challenge_icons.gd")
const STANDING_ART := {
	"aling": [preload("res://assets/characters/mainline-20261126/aling/calm.png"), Rect2(653, 133, 1118, 2166)],
	"chen": [preload("res://assets/characters/mainline-20261126/chen/calm.png"), Rect2(542, 35, 1265, 2376)],
	"vito": [Icons.VITO_ART, Rect2(862, 274, 652, 2003)],
	"hina": [preload("res://assets/characters/mainline-20261126/hina/calm.png"), Rect2(764, 184, 1016, 2132)],
	"luoe": [preload("res://assets/characters/mainline-20261126/luo/calm.png"), Rect2(270, 84, 2028, 2358)],
}
const PAPER := Color("#f1e4ce")
const MUTED := Color("#acaaa0")
const GOLD := Color("#e7b778")
const JADE := Color("#9dd5bc")
const RUST := Color("#e7a18a")
const SIDEBAR_MIN := 244.0
const FIRST_COOKING_LESSON: Array[String] = [
	"阿铃的战前教学 · 番茄炒蛋\n我备好了食材。先在砧板切番茄，厨房会把切好的料转到锅里。",
	"看屏幕上的按键提示。节奏音符到判定线时按键；遇到长条就按住，直到提示松开。",
	"锅里的步骤也跟着提示做。上盘后会比较两人的料理分数，结果会影响接下来的战斗。",
]
const TRAINING_TEXT := {
	Tutorial.ALING_MOVE:"按下WASD键，操控自己在场上移动吧！",
	Tutorial.ALING_LINE:"按下空格键，释放焰之舌吧！",
	Tutorial.ALING_SQUARE:"按下F键，释放焰之旋吧！",
	Tutorial.ALING_BUDGET:"在每回合战斗中，你拥有4个行动点，每次移动、释放火焰都会消耗一个行动点。现在试着消耗所有的行动点吧！",
	Tutorial.ALING_DODGE:"阿铃释放夜鸦攻击了！观察方格上面的数字，它表示经过以下行动点后，如果你处于该格子上就会受到伤害，伤害值为开始倒计时时显示的数字。使用你的聪明才智躲避吧！",
	Tutorial.CHEN_CAST:"阿铃教会你驱遣夜鸦程度的能力了！按下E键释放夜鸦吧！",
	Tutorial.CHEN_CHARGE:"请注意你的能量值！释放特殊技能会消耗对应的能量，通过焰之攻击命中来恢复能量吧！",
	Tutorial.CHEN_PICKUP:"野生的能量出现了！拾取道具可以恢复能量，现在试试吧！",
}

class Notice:
	extends ColorRect

	var body: Label
	var confirm_button: Button
	var _pages: Array[String]
	var _index := 0
	var _finished: Callable

	func present(pages: Array[String], finished: Callable) -> void:
		_pages = pages.duplicate()
		_finished = finished
		color = Color(0.02, 0.04, 0.03, .70)
		mouse_filter = Control.MOUSE_FILTER_STOP
		theme = TDUI.theme()
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var center := CenterContainer.new()
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(center)
		center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var card := PanelContainer.new()
		card.custom_minimum_size.x = 600
		card.add_theme_stylebox_override("panel", TDUI.wood(TDUI.Surface.CARD, 30))
		center.add_child(card)
		var column := TDUI.column(card, 24)
		body = TDUI.label(_pages[0], TDUI.FONT_SECTION)
		body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		body.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		body.custom_minimum_size.y = 76
		column.add_child(body)
		confirm_button = TDUI.button("确认", _advance)
		confirm_button.custom_minimum_size.x = 150
		confirm_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		confirm_button.focus_mode = Control.FOCUS_ALL
		column.add_child(confirm_button)
		confirm_button.grab_focus()

	func _advance() -> void:
		_index += 1
		if _index < _pages.size():
			body.text = _pages[_index]
			return
		confirm_button.disabled = true
		hide()
		queue_free()
		_finished.call()
var grid_size := 20
var points_per_turn := 4
var unlocked_skills: Array[String] = []
var loadout: Array[String] = ["", ""]
var skill_setup: VBoxContainer
var warehouse_slots: Array[Icons.CommandButton] = []
var _inspected_skill := ""
var _skill_details: Label
var _quick_equip: Button
var equip_slots: Array[Icons.CommandButton] = []
var battlefield: Control
var battle: TDChallengeBattle
var board: TDChallengeBoard
var enemy_clock: Timer
var selection: HBoxContainer
var fight: Control
var sidebar: PanelContainer
var phase_label: Label
var round_label: Label
var hero_bar: ProgressBar
var enemy_bar: ProgressBar
var energy_bar: ProgressBar
var energy_amount: Label
var ap_icon: Icons.Badge
var ap_label: Label
var info: Label
var combat_stats: Label
var cell_details: Label
var commands: Control
var line_button: Icons.CommandButton
var square_button: Icons.CommandButton
var skill_buttons: Array[Icons.CommandButton] = []
var decision: VBoxContainer
var tutorial_card: PanelContainer
var tutorial_text: Label
var tutorial_hint: Label
var confirming := false
var selected_index := 0
var aiming := Action.NONE
var hovered_action := Action.NONE
var story_encounter: Dictionary = {}
var _read_cooking_tutorial := false
var research: TDResearchSession
var permanent_stats: Callable
var boss_rematch: Callable
var automatic_time := true
var lesson: TDResearchLesson
var preparation: Dictionary = {}
var preparation_result: VBoxContainer
var notice: Notice
var reward_pages: Array[String] = []
var should_teach: Callable
var _setup_before_cooking := false
var _tutorial_result_sent := false
var _story_result_sent := false
var _match_result_sent := false

func _ready() -> void:
	enemy_clock = Timer.new()
	enemy_clock.wait_time = 0.28
	enemy_clock.timeout.connect(_enemy_step)
	add_child(enemy_clock)
	if story_encounter.is_empty(): _show_roster()
	else:
		selected_index = int(story_encounter.get("opponent", 0))
		if not story_encounter.has("crowd_town") and not unlocked_skills.is_empty():
			_open_skill_setup(true)
		else: _start(selected_index)

func _process(delta: float) -> void:
	if automatic_time and is_instance_valid(lesson): advance_cooking(minf(delta, .08))

func _show_roster() -> void:
	enemy_clock.stop()
	battle = null
	confirming = false
	var previous := get_node_or_null("Roster")
	if previous != null:
		remove_child(previous)
		previous.queue_free()
	if is_instance_valid(fight):
		battlefield.remove_child(fight)
		fight.queue_free()
	var column := VBoxContainer.new()
	column.name = "Roster"
	column.add_theme_constant_override("separation", 22)
	add_child(column)
	var title := TDUI.label("选择挑战对手", TDUI.FONT_TITLE)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	var heading := HBoxContainer.new()
	column.add_child(heading)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	if not unlocked_skills.is_empty():
		var setup_button := TDUI.button("技能调整", _open_skill_setup)
		setup_button.name = "SkillAdjustment"
		heading.add_child(setup_button)
	var stats: Dictionary = permanent_stats.call()
	column.add_child(TDUI.label("生命上限 %d  ·  基础伤害 %d  ·  行动点 %d" % [stats.hp,stats.damage,stats.ap], TDUI.FONT_CAPTION))
	selection = HBoxContainer.new()
	selection.add_theme_constant_override("separation", 10)
	column.add_child(selection)
	for i: int in TDChallengeBattle.OPPONENTS.size():
		var rival: Dictionary = TDChallengeBattle.OPPONENTS[i]
		var card := Button.new()
		card.name = rival.id
		card.custom_minimum_size = Vector2(182, 298)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.tooltip_text = rival.name + (" · 再战 · %d 生命" % Rules.REMATCH_HP if _is_rematch(i) else "")
		_build_roster_card(card, rival)
		card.pressed.connect(_start.bind(i))
		selection.add_child(card)
	battle_view_changed.emit(false)

func _open_skill_setup(before_cooking: bool = false) -> void:
	var roster := get_node_or_null("Roster") as Control
	if roster != null: roster.hide()
	_setup_before_cooking = before_cooking
	_inspected_skill = ""
	skill_setup = VBoxContainer.new()
	skill_setup.name = "SkillSetup"
	skill_setup.add_theme_constant_override("separation", 14)
	add_child(skill_setup)
	skill_setup.add_child(TDUI.label("战前装配" if before_cooking else "技能调整", TDUI.FONT_TITLE))

	var layout := HBoxContainer.new()
	layout.add_theme_constant_override("separation", 18)
	skill_setup.add_child(layout)
	var warehouse := _setup_column(layout, "技能仓库")
	var center := CenterContainer.new()
	warehouse.add_child(center)
	# Both empty circles and the surrounding warehouse accept skills being unequipped.
	(warehouse.get_parent() as Control).set_drag_forwarding(Callable(), _can_store_skill, _store_skill)
	var grid := GridContainer.new()
	grid.name = "SkillWarehouse"
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 10)
	center.add_child(grid)
	warehouse_slots.clear()
	for slot: int in 9:
		var id := unlocked_skills[slot] if slot < unlocked_skills.size() else ""
		var button := Icons.CommandButton.new()
		button.name = "Warehouse%d" % slot
		button.action = Action.SLOT_1
		button.skill_id = id
		button.warehouse_slot = true
		button.focus_mode = Control.FOCUS_ALL if not id.is_empty() else Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(78,78)
		grid.add_child(button)
		warehouse_slots.append(button)
		button.set_drag_forwarding(_drag_skill.bind(button, id, -1), _can_store_skill, _store_skill)
		if not id.is_empty(): button.pressed.connect(_inspect_skill.bind(id))

	var details := _setup_column(layout, "技能详情")
	details.custom_minimum_size.x = 240
	_skill_details = TDUI.label("", TDUI.FONT_CAPTION)
	_skill_details.name = "SkillDetails"
	_skill_details.add_theme_constant_override("line_spacing", 6)
	details.add_child(_skill_details)
	_quick_equip = TDUI.button("装配", _equip_inspected_skill)
	_quick_equip.name = "QuickEquip"
	details.add_child(_quick_equip)

	var equipped := _setup_column(layout, "战斗按键")
	var diamond := Control.new()
	diamond.name = "SkillDiamond"
	diamond.custom_minimum_size.y = 254
	equipped.add_child(diamond)
	var line := _setup_command(diamond, Action.LINE, "空格", "焰之舌")
	var square := _setup_command(diamond, Action.SQUARE, "F", "焰之旋")
	equip_slots.clear()
	for slot: int in 2:
		var action := Action.SLOT_1 if slot == 0 else Action.SLOT_2
		var button := _setup_command(diamond, action, ["E","Q"][slot], "")
		button.name = "Equip%d" % slot
		equip_slots.append(button)
		button.set_drag_forwarding(_drag_skill.bind(button, "", slot), _can_equip.bind(slot), _drop_skill.bind(slot))
	var slot_one := equip_slots[0]
	var slot_two := equip_slots[1]
	var arrange := func() -> void: Icons.layout_diamond(diamond.size, line, square, slot_one, slot_two)
	diamond.resized.connect(arrange)
	arrange.call()
	skill_setup.add_child(TDUI.label("拖到 E 或 Q 装配。把已装配技能拖回仓库即可卸下。", TDUI.FONT_CAPTION, TDUI.MUTED))
	if before_cooking:
		skill_setup.add_child(TDUI.button("开始做菜", _start.bind(selected_index)))
	_refresh_loadout()

func _setup_column(parent: HBoxContainer, title: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", TDUI.wood(TDUI.Surface.CARD, 14))
	parent.add_child(panel)
	var column := TDUI.column(panel, 8)
	var label := TDUI.label(title, TDUI.FONT_BODY)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(label)
	return column

func _setup_command(diamond: Control, action: TDChallengeBattle.Action, key: String, hint: String) -> Icons.CommandButton:
	var button := Icons.CommandButton.new()
	button.action = action
	button.key_hint = key
	button.tooltip_text = hint
	button.focus_mode = Control.FOCUS_NONE
	diamond.add_child(button)
	return button

func _close_skill_setup() -> void:
	remove_child(skill_setup)
	skill_setup.queue_free()
	skill_setup = null
	var roster := get_node_or_null("Roster") as Control
	if roster != null: roster.show()

func _can_store_skill(_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary: return false
	var origin: Variant = data.get("origin_slot")
	return origin is int and origin in [0,1] and loadout[origin] == data.get("challenge_skill")

func _store_skill(position: Vector2, data: Variant) -> void:
	if _can_store_skill(position, data): _set_skill(data.origin_slot, "")

func _drag_skill(grab_position: Vector2, card: Icons.CommandButton, id: String, slot: int) -> Variant:
	var skill := loadout[slot] if slot >= 0 else id
	if skill.is_empty() or skill not in unlocked_skills: return null
	var preview := Control.new()
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := Icons.CommandButton.new()
	icon.name = "SkillDragPreview"
	icon.action = card.action
	icon.skill_id = skill
	icon.key_hint = card.key_hint
	icon.warehouse_slot = card.warehouse_slot
	icon.warehouse_equipped = card.warehouse_equipped
	icon.aimed = card.is_hovered()
	icon.size = card.size
	icon.position = -grab_position
	icon.self_modulate.a = .72
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.focus_mode = Control.FOCUS_NONE
	preview.add_child(icon)
	card.set_drag_preview(preview)
	return {"challenge_skill":skill, "origin_slot":slot}

func _can_equip(_position: Vector2, data: Variant, slot: int) -> bool:
	if battle != null or not data is Dictionary: return false
	var skill: Variant = data.get("challenge_skill")
	return skill in unlocked_skills and skill != loadout[slot]

func _drop_skill(position: Vector2, data: Variant, slot: int) -> void:
	if _can_equip(position, data, slot): _set_skill(slot, data.challenge_skill)

func _inspect_skill(id: String) -> void:
	_inspected_skill = id
	_refresh_loadout()

func _equip_inspected_skill() -> void:
	var empty := loadout.find("")
	if empty >= 0 and not _inspected_skill.is_empty() and _inspected_skill not in loadout:
		_set_skill(empty, _inspected_skill)

func _set_skill(slot: int, id: String) -> void:
	if battle != null or (not id.is_empty() and id not in unlocked_skills): return
	var original := loadout.find(id)
	if not id.is_empty() and original >= 0: loadout[original] = loadout[slot]
	loadout[slot] = id
	_refresh_loadout()
	loadout_changed.emit(loadout.duplicate())

func _refresh_loadout() -> void:
	for slot: int in equip_slots.size():
		var button := equip_slots[slot]
		button.skill_id = loadout[slot]
		button.tooltip_text = Skills.tooltip(button.skill_id)
		button.queue_redraw()
	for button: Icons.CommandButton in warehouse_slots:
		var id := button.skill_id
		button.warehouse_equipped = not id.is_empty() and id in loadout
		button.aimed = not id.is_empty() and id == _inspected_skill
		button.tooltip_text = "" if id.is_empty() else Skills.tooltip(id)
		if button.warehouse_equipped: button.tooltip_text += "\n已装配至 " + ["E","Q"][loadout.find(id)]
		button.queue_redraw()
	if _inspected_skill.is_empty():
		_skill_details.text = "点击仓库里的技能图标，查看作用和消耗。"
		_quick_equip.hide()
		return
	_skill_details.text = Skills.tooltip(_inspected_skill)
	var equipped_slot := loadout.find(_inspected_skill)
	if equipped_slot >= 0:
		_skill_details.text += "\n已装配至 " + ["E","Q"][equipped_slot]
	var empty := loadout.find("")
	_quick_equip.visible = empty >= 0 and equipped_slot < 0
	if _quick_equip.visible: _quick_equip.text = "装配到 %s" % ["E","Q"][empty]

func _build_roster_card(card: Button, rival: Dictionary) -> void:
	var has_art := STANDING_ART.has(rival.id)
	if has_art:
		var source: Array = STANDING_ART[rival.id]
		var standing := AtlasTexture.new()
		standing.atlas = source[0]
		standing.region = source[1]
		standing.filter_clip = true
		var sprite := TextureRect.new()
		sprite.name = "StandingArt"
		sprite.texture = standing
		sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(sprite)
		sprite.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		sprite.offset_left = 12
		sprite.offset_right = -12
		sprite.offset_top = 12
		sprite.offset_bottom = -66
		if rival.id == "aling":
			sprite.scale = Vector2.ONE * .9
			sprite.pivot_offset = sprite.size * .5
			sprite.resized.connect(func() -> void: sprite.pivot_offset = sprite.size * .5)
	var caption := VBoxContainer.new()
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(caption)
	caption.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if has_art: caption.anchor_top = .79
	var title := TDUI.label(rival.name, TDUI.FONT_BODY)
	title.name = "FighterName"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_child(title)
	if rival.has("side"):
		var dimension := TDUI.label("%d × %d" % [rival.side, rival.side], TDUI.FONT_MICRO, TDUI.MUTED)
		dimension.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.add_child(dimension)

func _start(index: int) -> void:
	if story_encounter.get("cooking_tutorial",false) and not _read_cooking_tutorial:
		_read_cooking_tutorial = true
		_show_notices(FIRST_COOKING_LESSON, _start.bind(index))
		return
	if is_instance_valid(skill_setup): _close_skill_setup()
	enemy_clock.stop()
	var roster := get_node_or_null("Roster") as Control
	if roster != null: roster.hide()
	if is_instance_valid(fight) and fight.get_parent() == battlefield:
		battlefield.remove_child(fight)
		fight.queue_free()
	battle = null
	selected_index = index
	reward_pages.clear()
	preparation.clear()
	var recipe := Rules.recipe(index, str(story_encounter.get("crowd_town","")), str(story_encounter.get("crowd_site","")))
	var chart := research.catalog.chart(recipe, float(research.snapshot().input_offset_sec))
	chart.erase("profile")
	lesson = TDResearchLesson.new()
	var configured := lesson.configure(chart)
	if not configured.ok:
		lesson.free()
		lesson = null
		_show_preparation_error("暂时无法开始这道菜（%s）。" % configured.code)
		return
	lesson.token = "challenge:%s" % recipe
	lesson.cancel_requested.connect(_cancel_preparation)
	lesson.pause_requested.connect(_cancel_preparation)
	cooking_changed.emit(true)
	battlefield.add_child(lesson)
	lesson.kitchen.stage.navigation_hint = "Esc 返回备战"
	lesson.kitchen.stage.requirements_hint = "料理比拼 · %s" % str(research.catalog.node(recipe).get("name", recipe))
	battle_view_changed.emit(true)

func _is_rematch(index: int) -> bool:
	return story_encounter.is_empty() and boss_rematch.is_valid() and boss_rematch.call(str(Rules.OPPONENTS[index].id))

func advance_cooking(delta: float) -> void:
	if not is_instance_valid(lesson): return
	var result := lesson.advance(delta)
	if result.ok and not result.data.get("ready_to_finish", false): return
	if result.ok: result = lesson.finish()
	_close_cooking()
	if not result.ok:
		_show_preparation_error("料理未能结算（%s）。" % result.code)
		return
	if story_encounter.get("cooking_tutorial",false) and result.data.get("dish_state")=="plated":
		cooking_tutorial_finished.emit()
	var player_score := roundi(clampf(float(result.data.quality), 0.0, 1.0) * 100.0)
	var town := str(story_encounter.get("crowd_town",""))
	var opponent: Dictionary = Rules.OPPONENTS[selected_index] if town.is_empty() else Rules.CROWD_RIVALS[town]
	var score: Array = opponent.score
	preparation = Rules.compare(player_score, randi_range(int(score[0]), int(score[1])))
	_show_notices(Rules.cooking_notices(str(opponent.name), preparation), _enter_battle)

func _show_notices(pages: Array[String], finished: Callable) -> void:
	notice = Notice.new()
	notice.name = "ChallengeNotice"
	battlefield.add_child(notice)
	battle_view_changed.emit(true)
	notice.present(pages, func() -> void:
		notice = null
		finished.call())

func _show_preparation_error(message: String) -> void:
	preparation_result = VBoxContainer.new()
	add_child(preparation_result)
	preparation_result.add_child(TDUI.label(message, TDUI.FONT_BODY))
	preparation_result.add_child(TDUI.button("返回", _cancel_preparation))

func _close_cooking() -> void:
	if not is_instance_valid(lesson): return
	lesson.dispose()
	battlefield.remove_child(lesson)
	lesson = null
	cooking_changed.emit(false)
	battle_view_changed.emit(false)

func _discard_preparation_result() -> void:
	if not is_instance_valid(preparation_result): return
	remove_child(preparation_result)
	preparation_result.queue_free()
	preparation_result = null

func _cancel_preparation() -> void:
	_close_cooking()
	_discard_preparation_result()
	if story_encounter.is_empty(): _show_roster()
	else: _finish_story(-1)

func _enter_battle() -> void:
	if preparation.is_empty(): return
	if is_instance_valid(skill_setup): _close_skill_setup()
	_discard_preparation_result()
	var roster := get_node_or_null("Roster")
	if roster != null:
		remove_child(roster)
		roster.queue_free()
	if is_instance_valid(fight) and fight.get_parent() == battlefield:
		battlefield.remove_child(fight)
		fight.queue_free()
	confirming = false
	_match_result_sent = false
	_tutorial_result_sent = false
	aiming = Action.NONE
	hovered_action = Action.NONE
	skill_buttons.clear()
	battle = TDChallengeBattle.new(selected_index, grid_size, points_per_turn, -1, loadout,
		str(story_encounter.get("crowd_town", "")), preparation, permanent_stats.call(), _is_rematch(selected_index))
	if story_encounter.has("opponent_name"):
		battle.opponent.name = story_encounter.opponent_name
	if story_encounter.has("crowd_town"):
		battle.message = "%s：来比试一场吧！" % battle.opponent.name
	if not battle.rematch and should_teach.is_valid() and should_teach.call(str(battle.opponent.id)): battle.begin_tutorial()
	fight = Control.new()
	battlefield.add_child(fight)
	fight.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var backing := ColorRect.new()
	backing.color = Color("#3e281d")
	backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fight.add_child(backing)
	backing.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board = TDChallengeBoard.new()
	board.battle = battle
	board.cell_pressed.connect(_click_cell)
	board.cell_hovered.connect(_describe_cell)
	fight.add_child(board)
	_build_sidebar()
	fight.resized.connect(_layout_fight)
	_layout_fight()
	battle_view_changed.emit(true)
	_refresh()

func _build_sidebar() -> void:
	sidebar = PanelContainer.new()
	sidebar.name = "BattleSidebar"
	sidebar.add_theme_stylebox_override("panel", TDUI.wood(TDUI.Surface.FRAME, 0))
	fight.add_child(sidebar)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sidebar.add_child(scroll)
	var inset := MarginContainer.new()
	inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inset.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for edge: String in ["top", "bottom", "left", "right"]:
		inset.add_theme_constant_override("margin_" + edge, 22)
	scroll.add_child(inset)
	var status := VBoxContainer.new()
	status.add_theme_constant_override("separation", 12)
	inset.add_child(status)
	var top := HBoxContainer.new()
	status.add_child(top)
	round_label = TDUI.label("", TDUI.FONT_CAPTION, TDUI.MUTED)
	round_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	round_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	round_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	round_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(round_label)
	var back_button := Button.new()
	back_button.text = "返回  Esc"
	back_button.focus_mode = Control.FOCUS_NONE
	back_button.add_theme_font_size_override("font_size", TDUI.FONT_MICRO)
	back_button.add_theme_color_override("font_color", PAPER)
	back_button.add_theme_color_override("font_hover_color", GOLD)
	back_button.add_theme_color_override("font_pressed_color", GOLD)
	back_button.add_theme_stylebox_override("normal", _surface(Color("#272b32"), Color("#595057"), 5))
	back_button.add_theme_stylebox_override("hover", _surface(Color("#3a3539"), GOLD.darkened(.35), 5))
	back_button.add_theme_stylebox_override("pressed", _surface(Color("#332c30"), GOLD.darkened(.22), 5))
	back_button.pressed.connect(back)
	top.add_child(back_button)
	hero_bar = _add_health(status, "hero", "玩家", JADE)
	enemy_bar = _add_health(status, battle.opponent.id, battle.opponent.name, RUST)

	var turn := HBoxContainer.new()
	status.add_child(turn)
	phase_label = TDUI.label("", TDUI.FONT_BODY, TDUI.INK)
	phase_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	phase_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	phase_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	turn.add_child(phase_label)
	var ap_tile := PanelContainer.new()
	ap_tile.tooltip_text = "行动点"
	ap_tile.add_theme_stylebox_override("panel", _surface(Color("#2f2a2c"), Color("#62534c"), 6))
	turn.add_child(ap_tile)
	var ap_content := HBoxContainer.new()
	ap_tile.add_child(ap_content)
	ap_icon = Icons.Badge.new()
	ap_icon.custom_minimum_size = Vector2(22, 28)
	ap_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ap_content.add_child(ap_icon)
	ap_label = TDUI.label("", TDUI.FONT_BODY, PAPER)
	ap_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	ap_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ap_content.add_child(ap_label)

	var energy_row := HBoxContainer.new()
	energy_row.add_theme_constant_override("separation", 8)
	status.add_child(energy_row)
	var energy_icon := Icons.EnergyIcon.new()
	energy_icon.custom_minimum_size = Vector2(22, 24)
	energy_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	energy_row.add_child(energy_icon)
	energy_bar = ProgressBar.new()
	energy_bar.name = "SharedEnergyBar"
	energy_bar.custom_minimum_size.y = 14
	energy_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	energy_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	energy_bar.show_percentage = false
	energy_bar.add_theme_stylebox_override("background", _surface(Color("#172c32"), Color("#406268"), 4, 1))
	energy_bar.add_theme_stylebox_override("fill", _surface(Color("#459788"), Color("#a5e4d2"), 4, 1))
	energy_row.add_child(energy_bar)
	energy_amount = TDUI.label("", TDUI.FONT_CAPTION)
	energy_amount.autowrap_mode = TextServer.AUTOWRAP_OFF
	energy_row.add_child(energy_amount)

	_add_spacer(status)
	commands = Control.new()
	commands.mouse_filter = Control.MOUSE_FILTER_IGNORE
	commands.custom_minimum_size.y = 216
	commands.resized.connect(_layout_commands)
	status.add_child(commands)
	line_button = _add_command(Action.LINE, "空格", "")
	square_button = _add_command(Action.SQUARE, "F", "")
	for slot: int in 2:
		var action := Action.SLOT_1 if slot == 0 else Action.SLOT_2
		var button := _add_command(action, ["E", "Q"][slot], Skills.tooltip(battle.skill_slots[slot]))
		button.skill_id = battle.skill_slots[slot]
		skill_buttons.append(button)
	tutorial_card = PanelContainer.new()
	tutorial_card.name = "CombatTutorial"
	tutorial_card.add_theme_stylebox_override("panel", _surface(Color("#24332f"), Color("#83a789"), 7, 12))
	status.add_child(tutorial_card)
	var hints := TDUI.column(tutorial_card, 8)
	tutorial_text = TDUI.label("", TDUI.FONT_CAPTION, PAPER)
	hints.add_child(tutorial_text)
	tutorial_hint = TDUI.label("", TDUI.FONT_CAPTION, JADE)
	hints.add_child(tutorial_hint)
	tutorial_card.hide()
	_add_spacer(status)

	var footer := PanelContainer.new()
	footer.add_theme_stylebox_override("panel", _surface(Color("#1a1f26"), Color("#434046"), 7, 12))
	status.add_child(footer)
	var details := VBoxContainer.new()
	details.add_theme_constant_override("separation", 6)
	footer.add_child(details)
	info = TDUI.label("", TDUI.FONT_CAPTION, PAPER)
	info.custom_minimum_size.y = 46
	details.add_child(info)
	combat_stats = TDUI.label("", TDUI.FONT_MICRO, JADE)
	combat_stats.tooltip_text = preparation.description
	details.add_child(combat_stats)
	cell_details = TDUI.label("", TDUI.FONT_MICRO, RUST)
	cell_details.custom_minimum_size.y = 23
	details.add_child(cell_details)
	details.add_child(TDUI.label("方向键 / WASD / 点击棋盘", TDUI.FONT_MICRO, MUTED))
	decision = VBoxContainer.new()
	details.add_child(decision)

func _layout_fight() -> void:
	var bounds := fight.size
	if bounds.x >= bounds.y:
		var edge := minf(bounds.y, maxf(0, bounds.x - SIDEBAR_MIN))
		board.size = Vector2.ONE * edge
		board.position = Vector2(0, floorf((bounds.y - edge) * .5))
		sidebar.position = Vector2(edge, 0)
		sidebar.size = Vector2(bounds.x - edge, bounds.y)
	else:
		var edge := minf(bounds.x, maxf(0, bounds.y - SIDEBAR_MIN))
		board.size = Vector2.ONE * edge
		board.position = Vector2.ZERO
		sidebar.position = Vector2(0, edge)
		sidebar.size = Vector2(bounds.x, bounds.y - edge)

func _layout_commands() -> void:
	if skill_buttons.size() != 2 or not is_instance_valid(skill_buttons[1]) or skill_buttons[1].get_parent() != commands: return
	Icons.layout_diamond(commands.size, line_button, square_button, skill_buttons[0], skill_buttons[1])

func _add_spacer(parent: VBoxContainer) -> void:
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(spacer)

func _add_command(action: TDChallengeBattle.Action, key: String, tooltip: String) -> Icons.CommandButton:
	var button := Icons.CommandButton.new()
	button.action = action
	button.key_hint = key
	button.tooltip_text = tooltip
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(_choose_action.bind(action))
	button.mouse_entered.connect(_preview.bind(action))
	button.mouse_exited.connect(_preview.bind(Action.NONE))
	commands.add_child(button)
	return button

func _surface(fill: Color, edge: Color, radius: int, padding: int = 7) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	for side: Side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_content_margin(side, padding if radius > 0 else 0)
	return style

func _add_health(parent: Container, character_id: String, character_name: String, tint: Color) -> ProgressBar:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.tooltip_text = character_name
	parent.add_child(row)
	var portrait := Icons.Portrait.new()
	portrait.custom_minimum_size = Vector2(58, 58)
	portrait.tint = tint
	portrait.face = Icons.headshot(character_id)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(portrait)
	if character_id == "luoe": portrait.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var bar := ProgressBar.new()
	bar.custom_minimum_size.y = 20
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.show_percentage = false
	bar.add_theme_stylebox_override("background", _surface(Color("#13191f"), tint.darkened(.66), 4, 1))
	bar.add_theme_stylebox_override("fill", _surface(tint.darkened(.25), tint, 4, 1))
	row.add_child(bar)
	return bar

func _set_bar(bar: ProgressBar, value: int, maximum: int) -> void:
	bar.max_value = maximum
	bar.value = value
	bar.tooltip_text = "%d / %d" % [value, maximum]

func _preview(action: TDChallengeBattle.Action) -> void:
	hovered_action = action
	_update_preview()

func _update_preview() -> void:
	if battle == null or not is_instance_valid(board): return
	board.preview_action = Action.NONE
	if not confirming and battle.phase == battle.Phase.PLAYER:
		board.preview_action = aiming if aiming != Action.NONE else hovered_action
		if not battle.can_use(board.preview_action): board.preview_action = Action.NONE
	board.queue_redraw()

func _describe_cell(cell: Vector2i) -> void:
	if battle == null or not is_instance_valid(cell_details): return
	var tomato_timers: Array[String] = []
	var bomb_timers: Array[String] = []
	for tomato: TDChallengeBattle.Tomato in battle.tomatoes:
		if tomato.cell != cell: continue
		if tomato.motion == TDChallengeBattle.TomatoMotion.LUOE_ORBIT: bomb_timers.append(str(tomato.moves_left))
		else: tomato_timers.append(str(tomato.moves_left))
	var timers: Array = battle.warnings.get(cell, []).duplicate()
	timers.sort()
	var hints: Array[String] = []
	var guard := battle.guard_at(cell)
	if guard != null: hints.append("%s · %d/%d 生命 · 每回合 %d 行动点" % [guard.name, guard.hp, battle.GUARD_HP, battle.GUARD_AP])
	if cell == battle.foe and battle.luoe_guarded(): hints.append("罗厄 · 援兵在场，免疫伤害")
	if not timers.is_empty():
		hints.append("此格预警  ·  %s 行动点" % " / ".join(timers.map(func(n: int) -> String: return str(n))))
	if not tomato_timers.is_empty():
		hints.append("敌方番茄 · 剩 %s 行动点" % " / ".join(tomato_timers))
	if not bomb_timers.is_empty():
		hints.append("番茄炸弹 · 剩 %s 行动点 · 爆炸造成 %d 点伤害" % [" / ".join(bomb_timers), battle._enemy_damage(3) + battle.attack_bonus])
	for tomato: TDChallengeBattle.Tomato in battle.player_tomatoes:
		if tomato.cell == cell: hints.append("友方追踪番茄 · 最多再等 %d 行动点" % tomato.moves_left)
	for ball: TDChallengeBattle.TimedSummon in battle.timed_summons:
		if ball.cell == cell:
			hints.append("%s · 剩 %d 回合 / %d 次命中" % [battle.timed_summon_name(), ball.rounds_left, ball.hits_left])
	for ball: TDChallengeBattle.SaladSummon in battle.salad_summons:
		if ball.cell == cell:
			hints.append("%s · 本回合结束时消失" % battle.salad_summon_name() if ball.orbits
				else "%s · 剩 %d 行动点" % [battle.salad_summon_name(), ball.moves_left])
	cell_details.text = "\n".join(hints)

func _refresh() -> void:
	var player_turn := battle.phase == TDChallengeBattle.Phase.PLAYER
	var enemy_turn := battle.phase == TDChallengeBattle.Phase.OPPONENT
	var ended := not player_turn and not enemy_turn
	var caption := ["你的行动", "对手行动", "挑战胜利", "挑战落败", "平局"]
	round_label.text = "第 %d 回合" % battle.round_number
	if battle.second_phase and not ended: round_label.text += "  ·  二阶段"
	if battle.attack_bonus > 0 and not ended: round_label.text += "  ·  攻击 +%d" % battle.attack_bonus
	if battle.shield_round == battle.round_number and not ended: round_label.text += "  ·  护盾"
	if battle.luoe_guarded() and not ended: round_label.text += "  ·  罗厄免伤"
	if not battle.guards.is_empty() and not ended: round_label.text += "  ·  援兵 %d" % battle.guards.size()
	phase_label.text = "剧情评鉴结束" if ended and story_encounter.get("assessment",false) else caption[battle.phase]
	phase_label.add_theme_color_override("font_color", Color("#882f26") if enemy_turn else TDUI.INK)
	_set_bar(hero_bar, battle.hp, battle.max_hp)
	_set_bar(enemy_bar, battle.foe_hp, battle.foe_max_hp)
	ap_icon.tint = RUST if enemy_turn else GOLD
	ap_icon.queue_redraw()
	if enemy_turn:
		ap_label.text = "%d/%d" % [battle.enemy_ap, battle.GUARD_AP if battle.luoe_guarded() else battle.foe_max_ap]
		if battle.opponent.id == "luoe" and battle.second_phase: ap_label.text = "不限"
	else:
		ap_label.text = "%d/%d" % [battle.ap, battle.player_ap_budget]
	_set_bar(energy_bar, battle.energy, battle.MAX_ENERGY)
	energy_amount.text = "%d / %d" % [battle.energy, battle.MAX_ENERGY]
	var normal_damage := battle.damage_for(Rules.BASE_DAMAGE)
	combat_stats.text = "普通攻击 %d  ·  料理 %d : %d" % [normal_damage, preparation.player_score, preparation.opponent_score]
	line_button.tooltip_text = "焰之舌 · 前方 6 格，伤害 %d" % normal_damage
	square_button.tooltip_text = "焰之旋 · 周围 5 × 5，伤害 %d" % normal_damage
	line_button.disabled = confirming or not battle.can_use(Action.LINE)
	square_button.disabled = confirming or not battle.can_use(Action.SQUARE)
	for button: Icons.CommandButton in skill_buttons:
		button.skill_id = battle.skill_id(button.action)
		button.tooltip_text = Skills.tooltip(button.skill_id)
		button.disabled = confirming or not battle.can_use(button.action)
		button.ready_to_cast = not button.disabled
	for button: Icons.CommandButton in [line_button, square_button, skill_buttons[0], skill_buttons[1]]:
		button.aimed = button.action == aiming
		button.queue_redraw()
	commands.visible = not ended and not confirming
	info.text = "退出本局挑战？" if confirming else battle.message
	if aiming == Action.SQUARE:
		if battle.tutorial != Tutorial.ALING_SQUARE: info.text = "再次按下F键确认后释放攻击"
	elif aiming != Action.NONE and not _mouse_only_aim():
		var title: String = "焰之舌" if aiming == Action.LINE else Skills.DEFINITIONS[battle.skill_id(aiming)].name
		info.text = "选择%s方向。回车确认朝向，Esc 取消。" % title
	_refresh_tutorial()
	_describe_cell(board.hovered)
	_update_preview()
	if ended or confirming:
		enemy_clock.stop()
		if ended and not _match_result_sent:
			_match_result_sent = true
			match_finished.emit(battle.phase, str(battle.opponent.id), str(story_encounter.get("crowd_town","")), str(story_encounter.get("crowd_site","")))
			if not reward_pages.is_empty():
				_show_notices(reward_pages, _refresh)
				return
		if is_instance_valid(notice): return
		if ended and not story_encounter.is_empty() and not story_encounter.has("crowd_town"):
			if TDChallengeBattle.continues_story(battle.phase,story_encounter.get("assessment",false)):
				_finish_story.call_deferred(battle.phase)
				return
		if decision.get_child_count() == 0:
			var options := HFlowContainer.new()
			decision.add_child(options)
			if story_encounter.has("crowd_town") and ended:
				options.add_child(TDUI.button("返回小镇", _finish_story.bind(battle.phase)))
			elif not story_encounter.is_empty() and ended:
				options.add_child(TDUI.button("返回备战", _finish_story.bind(battle.phase)))
			elif confirming:
				options.add_child(TDUI.button("继续挑战", _resume))
				options.add_child(TDUI.button("退出本局", _show_roster if story_encounter.is_empty() else _finish_story.bind(-1)))
			else:
				options.add_child(TDUI.button("再次挑战", _start.bind(selected_index)))
				options.add_child(TDUI.button("重选对手", _show_roster))
	elif enemy_turn and enemy_clock.is_stopped():
		enemy_clock.start()
	elif player_turn:
		enemy_clock.stop()

func _refresh_tutorial() -> void:
	var text := str(TRAINING_TEXT.get(battle.tutorial, ""))
	if not battle.tutorial_completed.is_empty():
		text = "现在阿玲要动真格了！集中注意与她比拼吧！" if battle.tutorial_completed == "aling" else "现在罗金娜要动真格了！集中注意与她比拼吧！"
		if not _tutorial_result_sent:
			_tutorial_result_sent = true
			tutorial_finished.emit(battle.tutorial_completed)
	tutorial_card.visible = not text.is_empty() and not confirming
	tutorial_text.text = text
	var hint := ""
	if aiming != Action.NONE:
		match battle.tutorial:
			Tutorial.ALING_LINE: hint = "使用鼠标左键确定攻击方向"
			Tutorial.ALING_SQUARE: hint = "再次按下F键确认后释放攻击"
			Tutorial.CHEN_CAST: hint = "使用鼠标左键确定攻击方向，使用技能也会消耗行动点"
	tutorial_hint.text = hint
	tutorial_hint.visible = not hint.is_empty()

func _resume() -> void:
	confirming = false
	for node: Node in decision.get_children():
		decision.remove_child(node)
		node.queue_free()
	_refresh()

func _finish_story(phase: int) -> void:
	if _story_result_sent or not is_inside_tree(): return
	_story_result_sent=true
	story_finished.emit(phase)

func back() -> void:
	if is_instance_valid(notice): return
	if battle == null:
		if is_instance_valid(lesson):
			_cancel_preparation()
		elif is_instance_valid(skill_setup):
			if _setup_before_cooking: _finish_story(-1)
			else: _close_skill_setup()
		elif is_instance_valid(preparation_result):
			_cancel_preparation()
		else:
			close_requested.emit()
	elif aiming != Action.NONE:
		aiming = Action.NONE
		_refresh()
	elif confirming:
		_resume()
	elif battle.phase in [battle.Phase.PLAYER, battle.Phase.OPPONENT]:
		confirming = true
		_refresh()
	elif not story_encounter.is_empty():
		_finish_story(battle.phase)
	else:
		_show_roster()

func handle_key(event: InputEventKey) -> bool:
	if is_instance_valid(notice) or battle == null or confirming or battle.phase != battle.Phase.PLAYER: return false
	var key := event.physical_keycode if event.physical_keycode else event.keycode
	if key not in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_UP, KEY_LEFT, KEY_DOWN, KEY_RIGHT, KEY_SPACE, KEY_F, KEY_E, KEY_Q, KEY_ENTER, KEY_KP_ENTER]: return false
	if event.pressed and not event.echo:
		match key:
			KEY_W, KEY_UP: _move(Vector2i.UP)
			KEY_S, KEY_DOWN: _move(Vector2i.DOWN)
			KEY_A, KEY_LEFT: _move(Vector2i.LEFT)
			KEY_D, KEY_RIGHT: _move(Vector2i.RIGHT)
			KEY_SPACE: _choose_action(Action.LINE)
			KEY_F: _choose_action(Action.SQUARE)
			KEY_E: _choose_action(Action.SLOT_1)
			KEY_Q: _choose_action(Action.SLOT_2)
			KEY_ENTER, KEY_KP_ENTER:
				if aiming not in [Action.NONE, Action.SQUARE] and not _mouse_only_aim():
					_perform(aiming, battle.direction_toward(board.hovered))
	return true

func _mouse_only_aim() -> bool:
	return battle.tutorial in [Tutorial.ALING_LINE, Tutorial.CHEN_CAST]

func _click_cell(cell: Vector2i) -> void:
	if is_instance_valid(notice) or confirming or battle.phase != battle.Phase.PLAYER: return
	if aiming != Action.NONE:
		if aiming != Action.SQUARE: _perform(aiming, battle.direction_toward(cell))
	elif battle.enemy_at(cell) and battle.distance(battle.hero, cell) == 1:
		_perform(Action.LINE, cell - battle.hero)
	else:
		_move(cell - battle.hero)

func _move(direction: Vector2i) -> void:
	if aiming != Action.NONE:
		if aiming != Action.SQUARE and not _mouse_only_aim(): _perform(aiming, direction)
	elif battle.move(direction):
		board.animate_strikes(battle.impacts, {})
		_refresh()

func _choose_action(action: TDChallengeBattle.Action) -> void:
	if confirming or not battle.can_use(action): return
	if action == Action.SQUARE:
		if aiming == action: _perform(action, battle.facing)
		else:
			aiming = action
			_refresh()
		return
	if not battle.needs_aim(action):
		_perform(action, battle.facing)
		return
	aiming = action
	_refresh()

func _perform(action: TDChallengeBattle.Action, direction: Vector2i) -> void:
	if battle.use_action(action, direction):
		board.animate_strikes(battle.impacts, battle.player_strike)
		aiming = Action.NONE
		_refresh()

func _enemy_step() -> void:
	if not confirming and battle != null:
		battle.opponent_step()
		_refresh()
