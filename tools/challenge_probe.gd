extends SceneTree
## Drive the shipped HUD, modal and board with actual viewport inputs.
var shell: TDGameShell
var output := "user://challenge-probe"
var checks := 0
var failures := 0
const Action := TDChallengeBattle.Action
const Skills := TDChallengeBattle.Skills

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, description: String) -> bool:
	checks += 1
	if not value: failures += 1
	print(("PASS " if value else "FAIL ") + description)
	return value

func tap(key: Key) -> void:
	for down: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = key
		event.physical_keycode = key
		event.pressed = down
		root.push_input(event, true)

func square_attack() -> void:
	tap(KEY_F)
	tap(KEY_F)

func click(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, true)
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.global_position = point
		event.pressed = down
		root.push_input(event, true)

func drag(from: Vector2, to: Vector2, preview_source: Button = null, shot: String = "") -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = from
	press.global_position = from
	press.pressed = true
	root.push_input(press, true)
	var previous := from
	for step: int in range(1, 9):
		var motion := InputEventMouseMotion.new()
		motion.position = from.lerp(to, float(step) / 8.0)
		motion.global_position = motion.position
		motion.relative = motion.position - previous
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		previous = motion.position
		root.push_input(motion, true)
		await process_frame
		if step == 4 and preview_source != null:
			var ghost := root.find_child("SkillDragPreview", true, false) as Button
			check(root.gui_is_dragging() and ghost != null and ghost.get("skill_id") == preview_source.get("skill_id")
				and ghost.size.is_equal_approx(preview_source.size) and is_equal_approx(ghost.self_modulate.a, .72)
				and ghost.get("warehouse_slot") == preview_source.get("warehouse_slot"),
				"drag retains the original circular icon at reduced opacity")
			if not shot.is_empty(): await frame(shot)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = to
	release.global_position = to
	root.push_input(release, true)
	await process_frame

func stage_skills(profile: TDGameProfile) -> void:
	profile.record_challenge_result(TDChallengeBattle.Phase.WON,"aling","","")
	profile.record_challenge_result(TDChallengeBattle.Phase.LOST,"chen","","")
	profile.complete_rojin_advice()
	profile.record_challenge_result(TDChallengeBattle.Phase.WON,"hina","","")
	check(Skills.unlocked(profile.story,profile.challenge_progress)==[Skills.BEAM,Skills.DELAY,Skills.HEAL],"skill warehouse follows battle outcomes")

func stage_board(panel: TDChallengePanel) -> void:
	panel.should_teach = Callable()
	panel._close_cooking()
	panel.preparation = TDChallengeBattle.Rules.compare(55,55)
	panel._enter_battle()

func finish_recipe(panel: TDChallengePanel) -> bool:
	var lesson := panel.lesson
	if not check(lesson!=null and panel.battle==null,"the real cooking scene precedes the combat board"): return false
	var driver := TDResearchSession.new(shell.profile.research.catalog)
	driver.controller=lesson
	driver._active={"token":"fixture"}
	var inputs := preload("res://tools/test_support/research_input.gd")
	var sent := {}
	for tick: int in 6000:
		if lesson.update().data.get("ready_to_finish",false): break
		inputs.tick(driver,"fixture",sent,root)
	var status := lesson.update()
	if not check(status.data.get("ready_to_finish",false),"finish the full recipe chart"):
		print("Preparation diagnostic ", status.code, " tree paused=",paused, " clock paused=",lesson.clock.paused,
			" elapsed=",lesson.clock.game_sec, " preparation=",lesson._preparing," lane=",lesson.active_lane().progress)
		return false
	var score := roundi(clampf(float(lesson.update().data.quality),0,1)*100)
	panel.advance_cooking(0)
	return check(panel.battle==null and panel.preparation.player_score==score,"display the score from the cooked dish")

func check_preparation() -> void:
	shell.automatic_time=false
	tap(KEY_C)
	await process_frame
	var panel := shell._challenge
	if not check(panel!=null,"challenge shortcut opens the roster"): return
	var card := panel.selection.get_child(0) as Button
	click(card.get_global_rect().get_center())
	await process_frame
	await frame("01-menu-cooking")
	if not finish_recipe(panel): return
	await process_frame
	await frame("02-cooking-score")
	await confirm_pages(panel)
	if not check(panel.battle!=null and panel.battle.foe_max_hp==20,"the scored contest opens the matching opponent"): return
	await frame("03-aling-movement")
	var battle := panel.battle
	const Tutorial := TDChallengeBattle.Tutorial
	for key: Key in [KEY_W,KEY_A,KEY_S,KEY_D]: tap(key)
	if not check(battle.tutorial==Tutorial.ALING_LINE,"four moves advance the movement tutorial"): return
	for step: int in 4:
		tap(KEY_SPACE)
		check(panel.tutorial_hint.text=="使用鼠标左键确定攻击方向","the line lesson requests left click")
		click(panel.board.get_global_transform_with_canvas() * panel.board.cell_center(battle.foe))
	for step: int in 4: square_attack()
	for key: Key in [KEY_W,KEY_A,KEY_S,KEY_D]: tap(key)
	if not check(battle.tutorial==Tutorial.ALING_DODGE,"four paid actions cast the practice warning"): return
	await frame("04-aling-dodge")
	tap(KEY_W)
	tap(KEY_W)
	if not check(battle.tutorial==Tutorial.NONE and battle.round_number==1,"dodging starts the real battle"): return
	battle.foe = battle.hero + Vector2i.RIGHT
	battle.foe_hp = 2
	square_attack()
	await process_frame
	if not check(panel.notice!=null and panel.notice.body.text.begins_with("获得技能 · 驱遣夜鸦"),"Aling's victory shows the reward"): return
	await frame("05-aling-reward")
	await confirm_pages(panel)
	shell._close_dialog()
	shell._show_challenge({"opponent":1},func(_phase: int)->void:shell._close_dialog())
	panel=shell._challenge
	await process_frame
	if not check(panel.skill_setup!=null and panel.lesson==null,"story starts at the skill warehouse before cooking"): return
	click(panel.warehouse_slots[0].get_global_rect().get_center())
	await process_frame
	check(panel.loadout[0].is_empty() and "伤害 5" in panel._skill_details.text,"click reads the skill without equipping it")
	click(panel._quick_equip.get_global_rect().get_center())
	await process_frame
	check(panel.loadout[0]==Skills.BEAM,"the separate equip button equips the skill")
	await frame("06-story-skill-setup")
	var enter: Button=panel.skill_setup.find_children("*","Button",true,false).filter(func(button: Button)->bool:return button.text=="开始做菜")[0]
	click(enter.get_global_rect().get_center())
	await process_frame
	if not finish_recipe(panel): return
	await confirm_pages(panel)
	battle=panel.battle
	if not check(battle!=null and battle.tutorial==Tutorial.CHEN_CAST,"first Chen duel starts with the crow tutorial"): return
	tap(KEY_E)
	await frame("07-chen-crow")
	click(panel.board.get_global_transform_with_canvas() * panel.board.cell_center(battle.foe))
	for step: int in 5: square_attack()
	if not check(battle.tutorial==Tutorial.CHEN_PICKUP and battle.ap==3 and battle.energy==5,"five hits refill energy without spending AP"): return
	await frame("08-chen-pickup")
	var pickup := battle.pickups[0]
	for step: int in 3:
		if battle.tutorial != Tutorial.CHEN_PICKUP: break
		if pickup.x != battle.hero.x: tap(KEY_D if pickup.x > battle.hero.x else KEY_A)
		else: tap(KEY_S if pickup.y > battle.hero.y else KEY_W)
	check(battle.tutorial==Tutorial.NONE and battle.energy==7 and battle.skill_slots[0]==Skills.BEAM,"the crystal completes the lesson and preserves the chosen loadout")

func confirm_pages(panel: TDChallengePanel) -> void:
	for pages: int in 3:
		if not is_instance_valid(panel.notice): return
		await process_frame
		click(panel.notice.confirm_button.get_global_rect().get_center())
		await process_frame

func check_all_recipes() -> void:
	shell.automatic_time=false
	var rules := TDChallengeBattle.Rules
	var encounters: Array[Dictionary] = []
	for index: int in rules.OPPONENTS.size():
		encounters.append({"opponent":index})
	for town: String in rules.CROWD_RECIPES:
		for site: String in rules.CROWD_RECIPES[town]:
			encounters.append({"crowd_town":town,"crowd_site":site})
	var seen: Array[String] = []
	for encounter: Dictionary in encounters:
		var recipe := rules.recipe(int(encounter.get("opponent",0)),str(encounter.get("crowd_town","")),str(encounter.get("crowd_site","")))
		if not check(not recipe.is_empty() and recipe not in seen,"unique encounter recipe "+recipe): return
		seen.append(recipe)
		shell._show_challenge(encounter)
		await process_frame
		if not finish_recipe(shell._challenge): return
		await confirm_pages(shell._challenge)
		check(shell._challenge.battle!=null,"cooking hands off to "+recipe+"'s opponent")
		shell._close_dialog()
		await process_frame

func frame(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(name+".png")) == OK, "capture "+name)

func wait_for_turn(panel: TDChallengePanel) -> bool:
	for i: int in 60:
		if panel.battle.phase != panel.battle.Phase.OPPONENT: return true
		await create_timer(.05, true).timeout
	return false

func open_skill_setup(panel: TDChallengePanel) -> void:
	var button := panel.find_child("SkillAdjustment", true, false) as Button
	click(button.get_global_rect().get_center())
	await process_frame
	await process_frame

func close_skill_setup(panel: TDChallengePanel, by_button: bool = false) -> void:
	if by_button:
		var header := shell._modal_box.get_child(0)
		var back_button := header.find_children("*", "Button", true, false)[0] as Button
		click(back_button.get_global_rect().get_center())
	else:
		tap(KEY_ESCAPE)
	await process_frame
	await process_frame
	check(panel.skill_setup == null and panel.selection.is_visible_in_tree(), "return from skill adjustment to the roster")

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(output)
	var app := load("res://src/app/main.tscn").instantiate() as TDApplication
	app.settings_path = output.path_join("session-%d/settings.json" % Time.get_ticks_usec())
	root.add_child(app)
	await process_frame
	shell = app.game_shell
	if not check(shell.create_game("slot-01","对局验证",false).ok, "isolated profile"): quit(1); return
	shell.guide.dialogue.finish_now()
	shell.profile.story.beat = "follow"
	shell.profile.story.completed_scenes.clear()
	shell.travel("town")
	await process_frame
	await process_frame
	if "--prep-only" in OS.get_cmdline_user_args() or "--all-recipes" in OS.get_cmdline_user_args():
		if "--all-recipes" in OS.get_cmdline_user_args(): await check_all_recipes()
		else: await check_preparation()
		print("CHALLENGE ", checks, " checks / ", failures, " failures")
		quit(1 if failures else 0)
		return
	if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw
	var launch := shell._hud.button_for("challenge")
	check(launch != null and launch.is_visible_in_tree(), "challenge button in live HUD")
	click(launch.get_global_rect().get_center())
	await process_frame
	await process_frame
	if not check(shell._challenge != null, "HUD mouse opens roster"): quit(1); return
	check(shell.music.context == "casual", "choosing a rival keeps everyday music")
	var panel := shell._challenge
	var scroller := shell._modal_box.get_parent() as ScrollContainer
	check(not scroller.get_v_scroll_bar().visible, "entire roster fits without scrolling")
	check(panel.find_children("*", "OptionButton", true, false).is_empty(), "the roster has no board size selector")
	var clock_start := shell.profile.characters.clock.minute
	var shop_start := shell.profile.shop.snapshot()
	var feet := shell.town._player.position
	check(panel.selection.get_child_count() == 5, "exactly five rivals")
	var titles := ["阿铃", "罗金娜", "维托", "日奈", "罗厄"]
	var rivals := ["aling", "chen", "vito", "hina", "luoe"]
	for i: int in 5:
		var card := panel.selection.get_child(i) as Button
		var title := card.find_child("FighterName", true, false) as Label
		var standing := card.get_node_or_null("StandingArt") as TextureRect
		check(card.name == rivals[i] and title != null and title.text == titles[i], "rival card in the requested order "+str(i))
		check(standing != null and standing.texture.get_height() > 1900
			and standing.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED, "authored full-body art "+str(i))
		if standing != null:
			check(standing.scale.is_equal_approx(Vector2.ONE * (.9 if i == 0 else 1.0)), "standing art scale "+str(i))
			if i == 0: check(standing.pivot_offset.is_equal_approx(standing.size * .5), "Aling scales around the center of her art area")
	check(panel.skill_setup == null and panel.find_child("SkillWarehouse", true, false) == null, "the roster only contains an entry to skill adjustment")
	await frame("roster")
	check(panel.find_child("SkillAdjustment",true,false)==null,"the warehouse opens after the first skill")
	tap(KEY_ESCAPE)
	check(shell._challenge == null and not shell.get_tree().paused, "roster closes and resumes town")
	stage_skills(shell.profile)
	tap(KEY_C)
	await process_frame
	await process_frame
	panel = shell._challenge
	if not check(panel != null, "C opens roster"): quit(1); return
	scroller = shell._modal_box.get_parent() as ScrollContainer
	await open_skill_setup(panel)
	var beam_card := panel.warehouse_slots[0]
	var heal_card := panel.warehouse_slots[2]
	check(beam_card.skill_id == Skills.BEAM and heal_card.skill_id == Skills.HEAL and panel.warehouse_slots[1].skill_id == Skills.DELAY,
		"only unlocked skills occupy the warehouse")
	click(heal_card.get_global_rect().get_center())
	await process_frame
	check(panel.loadout == ["",""] and "恢复 10 点生命" in panel._skill_details.text,"warehouse click shows the effect without changing either slot")
	var diamond := panel.skill_setup.find_child("SkillDiamond", true, false) as Control
	var line := diamond.get_child(0) as Button
	var square := diamond.get_child(1) as Button
	var f_slot := panel.equip_slots[0]
	var g_slot := panel.equip_slots[1]
	check(line.position.x < f_slot.position.x and square.position.x > f_slot.position.x and g_slot.position.y < f_slot.position.y
		and is_equal_approx(line.position.y, square.position.y) and g_slot.position.x == f_slot.position.x,
		"skill adjustment uses the battle diamond geometry")
	await drag(beam_card.get_global_rect().get_center(), line.get_global_rect().get_center())
	check(panel.loadout == ["",""], "normal attacks do not accept drops")
	await drag(beam_card.get_global_rect().get_center(), panel.equip_slots[0].get_global_rect().get_center(), beam_card, "drag-warehouse-skill")
	await drag(heal_card.get_global_rect().get_center(), panel.equip_slots[1].get_global_rect().get_center())
	check(panel.loadout == [Skills.BEAM, Skills.HEAL] and shell.profile.challenge_loadout == panel.loadout, "drag equips both skill slots in the live profile")
	click(heal_card.get_global_rect().get_center())
	await process_frame
	check("已装配至 Q" in panel._skill_details.text and not panel._quick_equip.visible,"an equipped skill remains inspectable")
	await drag(panel.equip_slots[1].get_global_rect().get_center(), panel.equip_slots[0].get_global_rect().get_center(), panel.equip_slots[1], "drag-equipped-skill")
	check(panel.loadout == [Skills.HEAL, Skills.BEAM], "dragging to an occupied slot swaps existing skills")
	await drag(panel.equip_slots[1].get_global_rect().get_center(), panel.equip_slots[0].get_global_rect().get_center())
	check(panel.loadout == [Skills.BEAM, Skills.HEAL], "slot swap can be reversed")
	await frame("skill-adjustment")
	await close_skill_setup(panel, true)
	for i: int in 5:
		if i == 1:
			await open_skill_setup(panel)
			check(panel.equip_slots[0].skill_id == Skills.BEAM and panel.equip_slots[1].skill_id == Skills.HEAL,
				"reopening skill adjustment shows the existing loadout")
			await drag(panel.warehouse_slots[1].get_global_rect().get_center(), panel.equip_slots[1].get_global_rect().get_center())
			check(panel.loadout == [Skills.BEAM, Skills.DELAY], "a third skill replaces the target slot")
			await close_skill_setup(panel)
		if i == 2:
			await open_skill_setup(panel)
			for slot: int in 2:
				await drag(panel.equip_slots[slot].get_global_rect().get_center(), panel.warehouse_slots[8].get_global_rect().get_center())
			check(panel.loadout == ["",""], "dragging equipped skills back to the warehouse empties both slots")
			await close_skill_setup(panel)
		var expected_size: int = [12, 13, 13, 13, 15][i]
		var card := panel.selection.get_child(i) as Button
		click(card.get_global_rect().get_center())
		await process_frame
		await process_frame
		check(panel.lesson!=null and panel.battle==null,"the opponent card first opens real cooking")
		stage_board(panel)
		await process_frame
		var b := panel.battle
		if not check(b != null and b.opponent == TDChallengeBattle.OPPONENTS[i], "enter rival "+str(i)): quit(1); return
		var portrait := panel.enemy_bar.get_parent().get_child(0) as TDChallengePanel.Icons.Portrait
		var original_id := "luo" if b.opponent.id == "luoe" else str(b.opponent.id)
		var face := portrait.face as AtlasTexture
		check(face != null and face.atlas.resource_path == "res://assets/characters/mainline-20261126/%s/calm.png" % original_id,
			"duel uses the original rival headshot")
		var main_face := (panel.hero_bar.get_parent().get_child(0) as TDChallengePanel.Icons.Portrait).face as AtlasTexture
		check(main_face != null and main_face.atlas.resource_path == "res://assets/characters/mainline-20261126/hero/calm.png",
			"duel uses the original hero headshot")
		var expected_track := "boss" if b.opponent.id == "luoe" else "cooking"
		var battle_track := shell.music.player.stream as AudioStreamWAV
		check(shell.music.context == expected_track and battle_track != null
			and battle_track.data == TDGameMusic.TRACKS[expected_track].data
			and not shell.music.player.stream_paused, "%s plays %s.wav" % [b.opponent.name,expected_track])
		check(b.side == expected_size and b.ap == (4 if i<3 else 5) and b.phase == b.Phase.PLAYER, "fresh battle uses the rival's grid and the earned action budget")
		check(not panel.skill_buttons[0].is_processing() and not panel.skill_buttons[1].is_processing(), "both empty skill icons are still")
		var viewport_size := root.get_visible_rect().size
		var edge := minf(viewport_size.y, viewport_size.x - 244.0)
		var board_rect := panel.board.get_global_rect()
		check(board_rect.size.is_equal_approx(Vector2.ONE * edge) and board_rect.position.x == 0,
			"the board is a left-aligned square sized with the viewport")
		check(panel.sidebar.get_global_rect().position.x == board_rect.end.x and not scroller.is_visible_in_tree(),
			"the battle sidebar starts at the board edge and the roster frame is hidden")
		check(panel.sidebar.get_theme_stylebox("panel") is TDUI.WoodStyle, "the right panel uses the shared wood material")
		check(panel.line_button.position.x < panel.skill_buttons[0].position.x
			and panel.skill_buttons[1].position.y < panel.skill_buttons[0].position.y
			and panel.square_button.position.x > panel.skill_buttons[0].position.x
			and panel.skill_buttons[0].position.y > panel.line_button.position.y,
			"four circular controls form a diamond")
		check(panel.ap_label.text == "%d/%d" % [b.max_ap,b.max_ap] and panel.hero_bar.value == b.max_hp and panel.enemy_bar.value == b.foe_max_hp,
			"action point counter and portrait health bars match the battle")
		check(panel.ap_label.get_line_count() == 1, "the action point counter stays on one line")
		var energy_row := panel.energy_bar.get_parent()
		check(energy_row.get_child_count() == 2 and energy_row.get_child(0) is TDChallengePanel.Icons.EnergyIcon
			and energy_row.get_child(1) == panel.energy_bar and not panel.energy_bar.show_percentage,
			"the shared energy display consists of a crystal icon and a bar")
		check(not (panel.sidebar.get_child(0) as ScrollContainer).get_v_scroll_bar().visible,
			"the desktop battle sidebar fits without scrolling")
		if i == 2:
			tap(KEY_E)
			tap(KEY_Q)
			check(panel.skill_buttons[0].skill_id.is_empty() and panel.skill_buttons[1].skill_id.is_empty()
				and panel.skill_buttons[0].disabled and panel.skill_buttons[1].disabled and b.ap == 4
				and panel.aiming == Action.NONE, "empty battle slots show locks and reject the hotkeys")
			await frame("battle-locked")
		if i == 0:
			b.pickups.assign([b.hero + Vector2i.RIGHT])
			var before := b.hero
			click(panel.board.get_global_transform() * panel.board.cell_center(b.hero+Vector2i.RIGHT))
			check(b.hero == before+Vector2i.RIGHT and b.ap == 3, "mouse moves exactly one cell")
			check(b.pickups.is_empty() and b.energy == 2 and panel.energy_bar.value == 2
				and not panel.skill_buttons[0].is_processing() and not panel.skill_buttons[1].is_processing(),
				"picking up a crystal restores exactly two energy and updates the bar and skills")
			tap(KEY_C)
			tap(KEY_SPACE)
			check(panel.confirming and b.ap == 3, "quit prompt freezes pending input")
			tap(KEY_ESCAPE)
			check(not panel.confirming and b.ap == 3, "resume current match")
			tap(KEY_SPACE)
			check(panel.board.preview_action == Action.LINE and b.ap == 3, "directional preview spends no action point")
			tap(KEY_ESCAPE)
			check(panel.aiming == Action.NONE and b.ap == 3, "escape cancels targeting before opening the quit prompt")
			tap(KEY_SPACE)
			click(panel.board.get_global_transform() * panel.board.cell_center(b.foe))
			check(b.foe_hp == b.foe_max_hp-2 and b.energy == 3 and b.ap == 2, "mouse aims and fires the line attack")
			check(panel.energy_bar.value == 3 and panel.energy_bar.tooltip_text == "3 / 10"
				and panel.ap_label.text == "2/4", "the shared energy bar and action counter reflect the player hit")
			check(not panel.skill_buttons[1].is_processing(), "a skill without enough energy does not pulse")
			check(panel.board.effects._player.has(b.foe), "a player attack animates the struck tile")
			await frame("player-burst")
		for point: int in b.ap: square_attack()
		check(b.enemy_ap == b.foe_max_ap and b.enemy_ap == [3,4,5,4,5][i], "opponent receives its own action budget")
		if not check(await wait_for_turn(panel), "automatic opponent turn completes"): quit(1); return
		check(not panel.board.effects.is_processing(), "the short burst clears before the next player turn")
		check(not b.warnings.is_empty(), "opponent placed delayed cells")
		if i < 2:
			await frame("aling-cross" if i == 0 else "chen-first")
			if i == 1:
				var outer_ring := b.foe + Vector2i.RIGHT * 2
				tap(KEY_LEFT)
				tap(KEY_UP)
				var replay_center := b.hero
				check(not panel.board.effects._enemy.is_empty(), "an expired enemy countdown starts a burst")
				await frame("countdown-burst")
				check(b.ap == 2 and b.warnings.get(replay_center, []) == [2], "the cross replays immediately on the second player move")
				check(b.warnings.get(outer_ring, []) == [3], "the expanded ring appears on the same player action as the explosion")
				square_attack()
				square_attack()
				check(b.phase == b.Phase.OPPONENT and b.warnings.get(outer_ring, []) == [1], "paid actions tick the expanded ring immediately")
				if not check(await wait_for_turn(panel), "Chen completes the next opponent turn"): quit(1); return
				check(b.warnings.get(outer_ring, []) == [1], "the ring countdown holds through all opponent actions")
				check(Rect2i(3, 3, 7, 7).has_point(b.foe), "Chen retreats within the center seven by seven")
			# Deterministic combat fixture. Real viewport actions still spend or preserve AP.
			b.hero = Vector2i(3,3)
			b.foe = Vector2i(9,4)
			b.energy = b.MAX_ENERGY if i == 0 else 9
			panel._refresh()
			check(panel.skill_buttons[0].is_processing() and panel.skill_buttons[1].is_processing(),
				"both equipped skills glow when the shared pool covers each cost")
			if i == 0: await frame("skill-glow")
			var starting_ap := b.ap
			var starting_hp := b.foe_hp
			var starting_energy := b.energy
			click(panel.skill_buttons[0].get_global_rect().get_center())
			check(panel.aiming == Action.SLOT_1 and b.ap == starting_ap, "beam aims through the real skill slot")
			await frame("skill-aim-" + str(i))
			click(panel.board.get_global_transform() * panel.board.cell_center(b.foe))
			check(b.ap == starting_ap-1 and b.foe_hp == starting_hp-5 and b.energy == starting_energy-5
				and panel.energy_bar.value == b.energy and panel.skill_buttons[0].is_processing() == (i == 0)
				and panel.skill_buttons[1].is_processing() == (i == 1),
				"beam spends five shared energy and immediately updates both skills")
			if i == 0:
				b.hp = 3
				tap(KEY_Q)
				check(b.hp == 3 and b.energy == 5, "heal stays unavailable after beam spends its shared energy")
				b.energy = b.MAX_ENERGY
				panel._refresh()
			var old_ap := b.ap
			var old_foe_hp := b.foe_hp
			var old_warnings := b.warnings.duplicate(true)
			tap(KEY_Q)
			check(b.foe_hp == old_foe_hp and b.ap == old_ap and b.energy == 0 and panel.energy_bar.value == 0
				and not panel.skill_buttons[1].is_processing() and panel.aiming == Action.NONE,
				"the equipped utility skill casts immediately without a point")
			if i == 0:
				check(b.hp == 13 and b.warnings == old_warnings, "heal restores ten without affecting any warnings")
			else:
				var delayed := not old_warnings.is_empty()
				for cell: Vector2i in old_warnings:
					var timers: Array = old_warnings[cell].map(func(n: int) -> int: return n + 1)
					delayed = delayed and b.warnings[cell] == timers
				check(delayed, "delay adds one to every active warning")
				b.foe_hp = 10
				b.foe = b.hero + Vector2i.RIGHT
				square_attack()
				check(b.second_phase and b.foe == Vector2i(6,6), "Chen teleports immediately below half health")
				for point: int in b.ap: square_attack()
				if not check(await wait_for_turn(panel), "Chen completes all four phase two casts"): quit(1); return
				check(b.warnings.has(Vector2i(12,12)) and b.warnings.has(Vector2i(1,1)), "phase two marks both corner casts")
				await frame("chen-second")
		if i == 2:
			check(b.utensils.size() == 14 and b.tomatoes.is_empty(), "Vito opens with a fork and knife on every other lane")
			await frame("vito-utensils")
			tap(KEY_LEFT)
			tap(KEY_UP)
			check(b.utensils.size() == 6, "only the slow utensil lanes remain after two player actions")
			square_attack()
			square_attack()
			if not check(await wait_for_turn(panel), "Vito finishes his second turn"): quit(1); return
			check(b.utensils.size() == 7 and b.tomatoes.size() == 4, "Vito's second turn summons knives and four tomatoes")
			await frame("vito-tomatoes")
			var tomato := b.tomatoes[0]
			var previous := tomato.cell
			square_attack()
			check(b.distance(tomato.cell, previous) == 1 and tomato.moves_left in [1,2],
				"a paid player attack moves a tomato and advances its fuse")
			b.hero = Vector2i(2,11)
			b.foe = Vector2i(4,11)
			b.foe_hp = b.foe_max_hp / 2 + 2
			square_attack()
			check(b.foe_hp == b.foe_max_hp / 2 and b.second_phase, "Vito changes tactics at exactly half health")
			for point: int in b.ap: square_attack()
			if not check(await wait_for_turn(panel), "Vito finishes his first phase two turn"): quit(1); return
			check(Rect2i(b.hero - Vector2i.ONE, Vector2i(3,3)).has_point(b.foe)
				and b.tomatoes.size() == 4 and b.utensils.size() == 7,
				"phase two stays close and combines tomatoes with one set of utensils")
			await frame("vito-second-phase")
		if i == 3:
			check(b.side == 13 and b.timed_summons.size() == 2 and b.salad_summons.size() == 4,
				"Hina has a 13 by 13 board and summons both types of tempura")
			panel._describe_cell(b.timed_summons[0].cell)
			check(panel.cell_details.text.contains("柠檬汁天妇罗") and panel.cell_details.text.contains("2 回合")
				and panel.cell_details.text.contains("2 次命中"), "lemon tempura hint names the round countdown and required hits")
			panel._describe_cell(b.salad_summons[0].cell)
			check(panel.cell_details.text.contains("沙拉酱天妇罗 · 本回合结束时消失"), "salad tempura hint shows round-end expiry")
			await frame("hina-tempura")
		b.foe_hp = 2
		b.foe = b.hero + Vector2i.RIGHT
		square_attack()
		check(b.phase == b.Phase.WON, "victory through actual input against "+str(b.opponent.name))
		await confirm_pages(panel)
		if i == 0:
			await frame("result")
			var replay := panel.decision.find_children("*", "Button", true, false).front() as Button
			click(replay.get_global_rect().get_center())
			await process_frame
			check(panel.battle==null and panel.lesson!=null,"replay starts with a fresh cooking round")
			stage_board(panel)
			check(panel.battle != b and panel.battle.round_number == 1, "replay starts a fresh duel")
			for step: int in 4: square_attack()
			tap(KEY_ESCAPE)
			check(panel.confirming and panel.enemy_clock.is_stopped(), "enemy sequence pauses at quit prompt")
			await process_frame
			var leave := panel.decision.find_children("*", "Button", true, false).back() as Button
			click(leave.get_global_rect().get_center())
		else:
			panel.back()
		await process_frame
		await process_frame
		check(shell.music.context == "casual", "returning to the roster restores everyday music")
	check(shell.profile.characters.clock.minute == clock_start, "town clock held throughout challenge")
	check(shell.profile.shop.snapshot() == shop_start, "duels leave shop ledger untouched")
	tap(KEY_C)
	check(shell._challenge == null and not shell.get_tree().paused and shell.location == "town" and shell.town._player.position == feet, "return to same town and position")
	shell.profile.story.revised.clear()
	for town: String in ["chengdu", "paris", "tokyo"]:
		if not check(shell._arrive(town).ok, "arrive at the crowd's town"): quit(1); return
		var world: Node = shell.town if town == "chengdu" else shell.visiting
		var player: TDKitchenPlayer = shell.town._player if town == "chengdu" else shell.visiting.player
		var actor := world.get_node("CrowdStands").get_child(0) as TDStoryArt.TownActor
		player.position = actor.position + Vector2.DOWN * 48.0
		player.face(Vector2.UP)
		tap(KEY_E)
		await process_frame
		panel = shell._challenge
		if not check(panel != null, "talking on the map starts a duel outside the story"): quit(1); return
		check(panel.lesson!=null and panel.battle==null,"the town resident starts their own cooking recipe")
		stage_board(panel)
		check(panel.selection == null and panel.battle.opponent.id == TDChallengeBattle.CROWD_RIVALS[town].id,
			"the local crowd battle opens without a roster")
		var face := (panel.enemy_bar.get_parent().get_child(0) as TDChallengePanel.Icons.Portrait).face as AtlasTexture
		check(face != null and face.atlas.resource_path == "res://assets/characters/crowd/crowd-original-neutral.png",
			"the crowd battle uses the original headshot")
		for point: int in panel.battle.ap: square_attack()
		if not check(await wait_for_turn(panel), "the crowd opponent completes its turn"): quit(1); return
		await frame("crowd-" + town)
		shell._close_dialog()
	print("CHALLENGE ", checks, " checks / ", failures, " failures")
	quit(1 if failures else 0)
