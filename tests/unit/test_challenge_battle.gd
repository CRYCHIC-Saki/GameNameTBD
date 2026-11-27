extends GutTest

const Action := TDChallengeBattle.Action
const Vito := TDChallengeBattle.VitoAttack
const Skills := TDChallengeBattle.Skills

func spend_turn(b: TDChallengeBattle) -> void:
	for point: int in b.ap:
		b.use_action(Action.SQUARE, Vector2i.ZERO)

func cast_turn(b: TDChallengeBattle) -> void:
	while b.phase == b.Phase.OPPONENT:
		b.opponent_step()

func tick_without_opponent(b: TDChallengeBattle, count: int) -> void:
	for step: int in count:
		if b.phase == b.Phase.OPPONENT:
			b.ap = b.max_ap
			b.phase = b.Phase.PLAYER
		b.use_action(Action.LINE, Vector2i.LEFT)

func test_cooking_comparison_boundaries_and_fifth_round_penalty() -> void:
	var rules := TDChallengeBattle.Rules
	for row: Array in [[59,50,1,22],[60,50,2,25],[50,50,0,20],[36,50,-1,20],[35,50,-2,20]]:
		var score := rules.compare(row[0],row[1])
		for page: String in rules.cooking_notices("杂鱼一号",score):
			assert_false(page.contains("\n"),page)
			assert_lte(TDUI.font().get_string_size(page,HORIZONTAL_ALIGNMENT_LEFT,-1,TDUI.FONT_SECTION).x,540.0,page)
		var battle := TDChallengeBattle.new(0,20,4,42,[],"",score)
		assert_eq(battle.cooking_tier,row[2])
		assert_eq(battle.max_hp,row[3])
		assert_eq(battle.hp,battle.max_hp)
		assert_eq(battle.damage_for(2),1 if row[2]==-2 else 2)
		battle.round_number=4
		battle.phase=battle.Phase.OPPONENT
		battle.enemy_ap=1
		battle.opponent_step()
		assert_eq(battle.ap,3 if row[2]==-1 else 4)
		battle.phase=battle.Phase.OPPONENT
		battle.enemy_ap=1
		battle.opponent_step()
		assert_eq(battle.ap,4)

func test_rematches_use_final_boss_power_and_one_hundred_health() -> void:
	var rules := TDChallengeBattle.Rules
	for index: int in rules.OPPONENTS.size():
		var first := TDChallengeBattle.new(index,20,4,42)
		var rematch := TDChallengeBattle.new(index,20,4,42,[],"",{},{},true)
		assert_eq(first.foe_hp, int(rules.OPPONENTS[index].hp))
		assert_eq(rematch.foe_hp, 100)
		assert_eq(rematch.foe_max_hp, 100)
		assert_eq(rematch._enemy_damage(3), 3 + int(rules.OPPONENTS.back().damage_offset))
	var resident := TDChallengeBattle.new(0,20,4,42,[],"tokyo",{},{},true)
	assert_false(resident.rematch)
	assert_eq(resident.foe_hp, int(rules.CROWD_RIVALS.tokyo.hp))
	assert_eq(TDChallengeBattle.MAX_ENERGY, 10)

func test_critical_doubles_scaled_damage_and_attacking_summons_does_not_recharge() -> void:
	var rules := TDChallengeBattle.Rules
	var b := TDChallengeBattle.new(4,20,4,3,[],"",rules.compare(90,80),{"damage":4})
	var probe := RandomNumberGenerator.new()
	for seed: int in 1000:
		probe.seed=seed
		if probe.randf()<.05:
			b._rng.seed=seed
			break
	b.foe=b.hero+Vector2i.RIGHT
	assert_true(b.use_action(Action.SQUARE,Vector2i.ZERO))
	assert_eq(b.foe_hp,92)
	assert_eq(b.energy,1)
	b.foe=Vector2i(14,14)
	b.guards.append(TDChallengeBattle.Guard.new("crowd_cn","测试援兵",b.hero+Vector2i.RIGHT))
	assert_true(b.use_action(Action.SQUARE,Vector2i.ZERO))
	assert_eq(b.energy,1)

func test_challenge_wins_stack_by_distinct_residents_and_restore() -> void:
	var profile := TDGameProfile.new()
	profile.slot_id="slot-01"
	var rules := TDChallengeBattle.Rules
	for skill_id: String in Skills.DEFINITIONS:
		var page := Skills.reward_notice(skill_id)
		assert_false(page.contains("\n"),page)
		assert_lte(TDUI.font().get_string_size(page,HORIZONTAL_ALIGNMENT_LEFT,-1,TDUI.FONT_SECTION).x,540.0,page)
	for town: String in rules.CROWD_RECIPES:
		var sites: Array = rules.CROWD_RECIPES[town].keys()
		var rival: String = rules.CROWD_RIVALS[town].id
		profile.record_challenge_result(TDChallengeBattle.Phase.WON,rival,town,sites[0])
		assert_eq(profile.record_challenge_result(TDChallengeBattle.Phase.WON,rival,town,sites[0]),[])
		assert_eq(profile.record_challenge_result(TDChallengeBattle.Phase.WON,rival,town,sites[1]),[
			"生命上限 +10 · 攻击力 +1"])
	assert_eq(rules.permanent_stats(profile.story,profile.challenge_progress),{"hp":50,"damage":5,"ap":4})
	assert_eq(profile.record_challenge_result(TDChallengeBattle.Phase.WON,"vito","",""),[
		"获得技能 · 操纵食材程度的能力","行动点 +1"])
	var restored := TDGameProfile.new()
	assert_true(restored.restore(profile.snapshot()).ok)
	assert_eq(rules.permanent_stats(restored.story,restored.challenge_progress),{"hp":50,"damage":5,"ap":5})
	profile.close()
	restored.close()

func test_friendly_tomatoes_scale_damage_and_shield_only_protects_next_round() -> void:
	var b := TDChallengeBattle.new(0,20,4,42,[Skills.TOMATO,Skills.SHIELD],"",{},{"damage":3})
	b.hero=Vector2i(4,4)
	b.foe=Vector2i(6,4)
	b.energy=10
	assert_true(b.use_action(Action.SLOT_1,Vector2i.ZERO))
	assert_eq(b.player_tomatoes.size(),4)
	assert_eq(b.player_tomatoes[0].moves_left,3)
	b.use_action(Action.LINE,Vector2i.LEFT)
	assert_eq(b.foe_hp,12,"Two nearby tomatoes each deal 3 base damage plus 1")
	assert_eq(b.energy,5)
	b.energy=10
	b._schedule_strike([b.hero],1)
	assert_true(b.use_action(Action.SLOT_2,Vector2i.ZERO))
	assert_eq(b.hp,b.max_hp-1)
	b.ap=0
	b._finish_player_turn()
	cast_turn(b)
	b._schedule_strike([b.hero],1)
	b.use_action(Action.LINE,Vector2i.LEFT)
	assert_eq(b.hp,b.max_hp-1)
	b._strikes.clear()
	b.ap=0
	b._finish_player_turn()
	cast_turn(b)
	b._strikes.clear()
	b._schedule_strike([b.hero],1)
	b.use_action(Action.LINE,Vector2i.LEFT)
	assert_eq(b.hp,b.max_hp-2)

func test_each_opponent_has_its_board_size_and_refills_the_right_action_budget() -> void:
	for i: int in TDChallengeBattle.OPPONENTS.size():
		var b := TDChallengeBattle.new(i, 14, 4, 38)
		assert_eq(b.side, [12, 13, 13, 13, 15][i])
		assert_eq(b.phase, b.Phase.PLAYER)
		assert_ne(b.hero, b.foe)
		spend_turn(b)
		assert_eq(b.phase, b.Phase.OPPONENT)
		assert_eq(b.enemy_ap, [3, 4, 5, 4, 5][i])
		assert_false(b.use_action(Action.SQUARE, Vector2i.ZERO))
		cast_turn(b)
		assert_eq(b.round_number, 2)
		assert_eq(b.phase, b.Phase.PLAYER)
		assert_eq(b.ap, 4)
		assert_ne(b.hero, b.foe)
		assert_false(b.warnings.is_empty())
		for cell: Vector2i in b.warnings: assert_true(b.inside(cell))

func test_normal_attack_shapes_and_hit_charge() -> void:
	var b := TDChallengeBattle.new(4, 20, 4, 20, [Skills.BEAM, Skills.HEAL])
	b.hero = Vector2i(6, 6)
	assert_eq(b.attack_cells(Action.LINE, Vector2i.RIGHT), [
		Vector2i(7,6), Vector2i(8,6), Vector2i(9,6), Vector2i(10,6), Vector2i(11,6), Vector2i(12,6)])
	assert_eq(b.attack_cells(Action.SQUARE, Vector2i.ZERO).size(), 25)
	b.foe = b.hero + Vector2i(7, 0)
	assert_true(b.use_action(Action.LINE, Vector2i.RIGHT))
	assert_eq(b.foe_hp, b.foe_max_hp)
	assert_eq(b.energy, 0)
	b.foe = b.hero + Vector2i(6, 0)
	assert_true(b.use_action(Action.LINE, Vector2i.RIGHT))
	assert_eq(b.foe_hp, b.foe_max_hp-2)
	assert_eq(b.energy, 1)
	b.foe = b.hero + Vector2i(-2, 2)
	assert_true(b.use_action(Action.SQUARE, Vector2i.ZERO))
	assert_eq(b.foe_hp, b.foe_max_hp-4)
	assert_eq(b.energy, 2)
	b.energy = b.MAX_ENERGY
	assert_true(b.use_action(Action.SQUARE, Vector2i.ZERO))
	assert_eq(b.energy, b.MAX_ENERGY)
	b.hero = Vector2i.ZERO
	assert_eq(b.attack_cells(Action.SQUARE, Vector2i.ZERO).size(), 9)
	assert_eq(b.attack_cells(Action.LINE, Vector2i.UP).size(), 0)

func test_move_checks_destination_and_independent_overlapping_warnings() -> void:
	var b := TDChallengeBattle.new()
	b.hero = Vector2i.ZERO
	b.foe = Vector2i.RIGHT
	b._schedule_strike([b.hero], 1)
	b._schedule_strike([Vector2i.DOWN], 1)
	b._schedule_strike([Vector2i.DOWN], 1)
	b._schedule_strike([Vector2i.DOWN], 3)
	b._refresh_warnings()
	assert_false(b.move(Vector2i.LEFT))
	assert_false(b.move(Vector2i.RIGHT))
	assert_false(b.move(Vector2i(1,1)))
	assert_false(b.use_action(Action.SLOT_1, Vector2i.UP))
	assert_eq(b.ap, 4)
	assert_true(b.move(Vector2i.DOWN))
	assert_eq(b.hp, b.max_hp-2 * b._enemy_damage(1))
	assert_eq(b.warnings[b.hero], [2])
	assert_false(b.warnings.has(Vector2i.ZERO))
	assert_eq(b.ap, 3)
	assert_true(b.move(Vector2i.DOWN))
	assert_true(b.use_action(Action.SQUARE, Vector2i.ZERO))
	assert_eq(b.hp, b.max_hp-2 * b._enemy_damage(1))
	assert_true(b.warnings.is_empty())

func test_crystal_respects_energy_cap_and_beam_spends_energy_and_action_point() -> void:
	var b := TDChallengeBattle.new(4, 20, 4, 20, [Skills.HEAL, Skills.BEAM])
	b.hero = Vector2i(3,3)
	b.foe = Vector2i(b.side-1,5)
	b.energy = 8
	b.pickups.assign([b.hero+Vector2i.DOWN])
	assert_true(b.move(Vector2i.DOWN))
	assert_eq(b.energy, b.MAX_ENERGY)
	assert_true(b.pickups.is_empty())
	assert_eq(b.attack_cells(Action.SLOT_2, Vector2i.RIGHT).size(), (b.side - b.hero.x - 1) * 3)
	b._schedule_strike([b.hero], 2)
	assert_false(b.use_action(Action.SLOT_2, Vector2i.ZERO))
	assert_eq(b.energy, b.MAX_ENERGY)
	assert_true(b.use_action(Action.SLOT_2, Vector2i.RIGHT))
	assert_eq(b.ap, 2)
	assert_eq(b.warnings[b.hero], [1])
	assert_eq(b.foe_hp, b.foe_max_hp-5)
	assert_eq(b.energy, 5)
	assert_false(b.can_use(Action.SLOT_1))
	assert_true(b.can_use(Action.SLOT_2))
	assert_true(b.use_action(Action.SLOT_2, Vector2i.UP))
	assert_eq(b.hp, b.max_hp-b._enemy_damage(2))
	assert_eq(b.energy, 0)

func test_crystals_spawn_at_distance_two_and_expire_on_schedule() -> void:
	for town: String in ["", "chengdu"]:
		var b := TDChallengeBattle.new(0, 20, 4, 71, [], town)
		assert_eq(b.pickups.size(), int(not town.is_empty()))
		b.hero = Vector2i(2, 3)
		b.foe = Vector2i(6, 3)
		for turn: int in range(2, 6):
			b.ap = 0
			b._finish_player_turn()
			assert_true(b.pickups.is_empty())
			b.enemy_ap = 1
			b.opponent_step()
			assert_eq(b.round_number, turn)
			assert_eq(b.pickups.size(), int(not town.is_empty() or turn % 2 == 0))
			if not b.pickups.is_empty():
				assert_eq(b.pickups[0], Vector2i(4, 3),"Distance two from both")
		b.pickups.clear()
		b.foe = Vector2i(10, 10)
		b._spawn_pickup()
		assert_eq(b.distance(b.pickups[0], b.hero), 2,"Falls back to the player when the rings do not intersect")

func test_heal_and_delay_are_instant_and_draw_from_the_same_energy_pool() -> void:
	var b := TDChallengeBattle.new(2, 13, 4, 71, [Skills.DELAY, Skills.HEAL])
	b.hp = 2
	b.energy = 10
	b._schedule_strike([b.hero], 1)
	b._schedule_strike([b.hero], 3)
	b.tomatoes.append(TDChallengeBattle.Tomato.new(Vector2i.ZERO))
	b._refresh_warnings()
	assert_true(b.use_action(Action.SLOT_2, Vector2i.ZERO))
	assert_eq(b.hp, 12)
	assert_eq(b.foe_hp, b.foe_max_hp)
	assert_eq(b.ap, b.max_ap)
	assert_eq(b.energy, 0)
	assert_eq(b.warnings[b.hero], [1,3])
	assert_false(b.use_action(Action.SLOT_1, Vector2i.ZERO))
	assert_eq(b.warnings[b.hero], [1,3])
	b.energy = 5
	assert_true(b.use_action(Action.SLOT_1, Vector2i.ZERO))
	assert_eq(b.warnings[b.hero], [2,4])
	assert_eq(b.tomatoes[0].moves_left, 4)
	assert_eq(b.tomatoes[0].cell, Vector2i.ZERO)
	assert_eq(b.energy, 1)
	assert_eq(b.ap, b.max_ap)
	assert_false(b.use_action(Action.SLOT_1, Vector2i.ZERO))
	assert_true(b.use_action(Action.LINE, Vector2i.LEFT))
	assert_eq(b.warnings[b.hero], [1,3])
	assert_eq(b.tomatoes[0].moves_left, 3)
	b.energy = 10
	assert_true(b.use_action(Action.SLOT_2, Vector2i.ZERO))
	assert_eq(b.hp, b.max_hp)

func test_unlocks_follow_completed_matches_and_distinguish_a_loss_from_a_win() -> void:
	var story := TDOpening.new()
	assert_eq(Skills.unlocked(story), [])
	story.revised = TDRevisedMainline.initial()
	var milestones := {0:[], 2:[Skills.BEAM], 5:[Skills.BEAM],6:[Skills.BEAM,Skills.DELAY],10:[Skills.BEAM,Skills.DELAY,Skills.TOMATO],
		13:[Skills.BEAM,Skills.DELAY,Skills.HEAL,Skills.TOMATO],18:[Skills.BEAM,Skills.DELAY,Skills.HEAL,Skills.TOMATO,Skills.SHIELD]}
	for index: int in 19:
		var node := TDRevisedMainline.current(story.revised)
		if node.kind=="dialogue": assert_true(TDRevisedMainline.complete_dialogue(story.revised, node.id, true))
		else: assert_true(TDRevisedMainline.complete_action(story.revised, node.id))
		if milestones.has(index): assert_eq(Skills.unlocked(story), milestones[index])
	story.revised.clear()
	assert_eq(Skills.unlocked(story,{"defeated":[],"rojin_fought":true}), [Skills.DELAY])
	assert_eq(Skills.unlocked(story,{"defeated":["chen"],"rojin_fought":true}), [Skills.DELAY,Skills.SHIELD])
	assert_eq(Skills.unlocked(story,{"defeated":["chen"],"rojin_fought":true,"rojin_advice":false}), [Skills.SHIELD])

func test_loadout_sanitizes_duplicates_and_empty_slots_stay_locked() -> void:
	var b := TDChallengeBattle.new(0, 20, 4, 71, [Skills.BEAM, Skills.BEAM])
	assert_eq(b.skill_slots, [Skills.BEAM,""])
	b.pickups.assign([b.hero + Vector2i.DOWN])
	b.energy = 3
	assert_true(b.move(Vector2i.DOWN))
	assert_eq(b.energy, 5)
	assert_true(b.can_use(Action.SLOT_1))
	assert_false(b.can_use(Action.SLOT_2))
	assert_false(b.use_action(Action.SLOT_2, Vector2i.RIGHT))
	assert_true(b.attack_cells(Action.SLOT_2, Vector2i.RIGHT).is_empty())
	assert_eq(Skills.normalize([Skills.HEAL,Skills.BEAM], [Skills.BEAM]), ["",Skills.BEAM])

func test_loadout_round_trips_with_profile_and_older_saves_keep_empty_slots() -> void:
	var profile := TDGameProfile.new()
	profile.slot_id = "slot-01"
	profile.story.begin()
	profile.story.revised = TDRevisedMainline.initial()
	profile.record_challenge_result(TDChallengeBattle.Phase.WON,"aling","","")
	profile.challenge_loadout.assign(["", Skills.BEAM])
	var saved := profile.snapshot()
	var restored := TDGameProfile.new()
	assert_true(restored.restore(saved).ok)
	assert_eq(restored.challenge_loadout, ["", Skills.BEAM])
	saved.erase("challenge_loadout")
	assert_true(restored.restore(saved).ok)
	assert_eq(restored.challenge_loadout, ["", ""])
	profile.close()
	restored.close()

func test_aling_approaches_distance_five_and_casts_the_small_cross() -> void:
	var b := TDChallengeBattle.new()
	b.hero = Vector2i(3,5)
	b.foe = Vector2i(6,5)
	spend_turn(b)
	b.opponent_step()
	assert_eq(b.distance(b.foe, b.hero), 4)
	b.opponent_step()
	assert_eq(b.distance(b.foe, b.hero), 5)
	assert_true(b.warnings.is_empty())
	b.opponent_step()
	assert_eq(b.warnings.size(), 5)
	assert_eq(b.warnings[b.hero], [2])
	for direction: Vector2i in b.DIRECTIONS:
		assert_eq(b.warnings[b.hero+direction], [2])
	assert_false(b.warnings.has(b.hero+Vector2i(1,1)))
	var position := b.foe
	spend_turn(b)
	cast_turn(b)
	assert_eq(b.foe, position, "holds the preferred distance")

func test_aling_uses_a_ring_when_she_cannot_reach_five() -> void:
	var b := TDChallengeBattle.new()
	b.hero = Vector2i.ZERO
	b.foe = Vector2i(10,10)
	spend_turn(b)
	cast_turn(b)
	assert_gt(b.distance(b.foe, b.hero),5)
	assert_false(b.warnings.has(b.foe))
	for cell: Vector2i in b.warnings:
		assert_eq((cell-b.foe).abs().x == 1 or (cell-b.foe).abs().y == 1, true)
		assert_eq(b.warnings[cell], [2])

func test_regional_crowd_duels_are_separate_from_the_challenge_roster() -> void:
	assert_eq(TDChallengeBattle.OPPONENTS.size(), 5)
	for rival: Dictionary in TDChallengeBattle.OPPONENTS:
		assert_false(str(rival.id).begins_with("crowd_"))
	var aling := TDChallengeBattle.new(0, 20, 4, 46)
	var crowd := TDChallengeBattle.new(0, 20, 4, 46, [], "chengdu")
	spend_turn(aling)
	spend_turn(crowd)
	cast_turn(aling)
	cast_turn(crowd)
	assert_eq(crowd.foe, aling.foe)
	assert_eq(crowd.warnings, aling.warnings)
	assert_eq(crowd.foe_max_ap, aling.foe_max_ap)

func test_european_crowd_combines_six_utensils_and_uses_two_three_step_tomatoes() -> void:
	var b := TDChallengeBattle.new(0, 20, 4, 9, [], "paris")
	b.hero = Vector2i(6, 6)
	b.foe = Vector2i(10, 5)
	spend_turn(b)
	cast_turn(b)
	assert_eq(b.foe_max_ap, 4)
	assert_eq(TDChallengeBattle.distance(b.foe, b.hero), 3)
	assert_eq(b.utensils.size(), 6)
	var fast := 0
	for strike: TDChallengeBattle.Strike in b.utensils:
		if strike.points_left == 1:
			fast += 1
			assert_true(b.hero in strike.cells)
			assert_eq(strike.repeats_left, 1)
		else:
			assert_eq(strike.points_left, 3)
			assert_eq(strike.repeats_left, 0)
	assert_eq(fast, 2)
	assert_eq(b.tomatoes.size(), 2)
	var chasing := b.tomatoes[0]
	var random := b.tomatoes[1]
	assert_ne(chasing.cell, random.cell)
	assert_eq(chasing.motion, b.TomatoMotion.CHASE)
	assert_eq(random.motion, b.TomatoMotion.RANDOM)
	b.hero = Vector2i(0, 0)
	var distance_before := TDChallengeBattle.distance(chasing.cell, b.hero)
	tick_without_opponent(b, 1)
	assert_eq(TDChallengeBattle.distance(chasing.cell, b.hero), distance_before - 1)
	assert_eq(chasing.moves_left, 2)
	assert_eq(random.moves_left, 2)
	assert_eq(b.utensils.size(), 6, "Central lines remain for their repeat")
	tick_without_opponent(b, 1)
	assert_eq(b.utensils.size(), 4)
	assert_eq(b.tomatoes.size(), 2)
	tick_without_opponent(b, 1)
	assert_eq(b.utensils.size(), 0)
	assert_eq(b.tomatoes.size(), 0)

func test_hina_aligns_then_casts_opposite_corners_and_changes_formation_at_half_health() -> void:
	var b := TDChallengeBattle.new(3, 20, 4, 11)
	b.hero = Vector2i(4, 5)
	b.foe = Vector2i(10, 7)
	spend_turn(b)
	cast_turn(b)
	assert_eq(b.foe, Vector2i(10, 5))
	assert_eq(b.timed_summons.size(), 2)
	assert_eq(b.timed_summons[0].cell + b.timed_summons[1].cell, b.hero * 2)
	assert_eq(b._strikes[0].cells.size(), 25)
	assert_eq(b._strikes[0].points_left, 2)
	assert_eq(b._strikes[1].cells.size(), 9)
	assert_eq(b._strikes[1].points_left, 1)
	assert_eq(b.salad_summons.size(), 4)
	assert_eq(b.hp, b.max_hp, "No summoned salad hits before a player's action")
	b.timed_summons.clear()
	b.salad_summons.clear()
	b.foe_hp = b.foe_max_hp / 2
	b._enter_second_phase()
	b._cast_timed_summons()
	b._cast_salad_summons()
	assert_true(b.second_phase)
	assert_eq(b.timed_summons.size(), 3)
	assert_eq(b.salad_summons.size(), 2)
	assert_eq(b.salad_summons[0].cell + b.salad_summons[1].cell, b.foe * 2)

func test_lemon_tempura_takes_two_attacks_and_its_scheduled_strike_outlives_it() -> void:
	var b := TDChallengeBattle.new(3)
	b.hero = Vector2i(3, 5)
	b.hp = 8
	b._add_timed_summon(Vector2i(4, 5), true)
	assert_true(b.use_action(Action.LINE, Vector2i.RIGHT))
	assert_eq(b.timed_summons[0].hits_left, 1)
	assert_eq(b.timed_summons[0].rounds_left, 2)
	assert_true(b.use_action(Action.LINE, Vector2i.RIGHT))
	assert_eq(b.timed_summons.size(), 0)
	assert_true(b.impacts.has(b.hero), "The already scheduled cross still triggers")
	assert_eq(b.hp, 8 + 2 - b._enemy_damage(2))

func test_lemon_tempura_expiration_heals_and_buff_lasts_one_round() -> void:
	var b := TDChallengeBattle.new(3)
	b.hero = Vector2i(2, 2)
	b.foe = Vector2i(11, 10)
	b.foe_hp = 29
	b._enter_second_phase()
	b._add_timed_summon(Vector2i(9, 9), true)
	tick_without_opponent(b, 3)
	assert_eq(b.timed_summons[0].rounds_left, 2)
	tick_without_opponent(b, 1)
	assert_eq(b.timed_summons[0].rounds_left, 1)
	tick_without_opponent(b, 4)
	assert_eq(b.timed_summons.size(), 0)
	assert_eq(b.foe_hp, 32)
	assert_false(b.second_phase)
	assert_eq(b.attack_bonus, 1)
	b._schedule_strike([b.hero], 1)
	tick_without_opponent(b, 1)
	assert_eq(b.hp, b.max_hp - b._enemy_damage(1) - 1)
	tick_without_opponent(b, 3)
	assert_eq(b.attack_bonus, 0)

func test_lemon_tempura_hit_shortens_only_its_own_round_timer() -> void:
	var b := TDChallengeBattle.new(3)
	b.hero = Vector2i(2, 2)
	b._add_timed_summon(Vector2i(2, 9), true)
	b._add_timed_summon(Vector2i(9, 9), true)
	tick_without_opponent(b, 2)
	assert_eq(b.timed_summons[0].rounds_left, 1)
	assert_eq(b.timed_summons[1].rounds_left, 2)

func test_salad_tempura_orbits_and_hina_shields_the_player_on_both_axes() -> void:
	for direction: Vector2i in [Vector2i.LEFT, Vector2i.UP]:
		var b := TDChallengeBattle.new(3)
		b.foe = Vector2i(8, 6)
		b.hero = b.foe + direction * 4 + Vector2i(-direction.y, direction.x)
		b._cast_salad_summons()
		var orbiting := b.salad_summons[0]
		var far_side := b.salad_summons[1 if direction == Vector2i.LEFT else 2]
		assert_eq(orbiting.cell, Vector2i(7, 5))
		assert_eq(b.hp, b.max_hp, "Summoning an aligned tempura costs no life")
		b.hero = b.foe + direction * 4
		tick_without_opponent(b, 1)
		assert_eq(orbiting.cell, Vector2i(8, 5), "One clockwise step per action point")
		assert_eq(far_side.cell, b.foe - direction)
		assert_has(b.salad_summons, far_side, "Hina protects the tile beyond her")
		assert_eq(b.hp, b.max_hp - 3, "Only the tempura on the player's side hits")
		assert_eq(b.salad_summons.size(), 3)

func test_salad_tempura_clears_at_round_end_including_the_last_action() -> void:
	for budget: int in [3, 6]:
		var b := TDChallengeBattle.new(3, 20, budget)
		b.foe = Vector2i(8, 6)
		b.hero = Vector2i(2, 2)
		b._cast_salad_summons()
		tick_without_opponent(b, budget - 1)
		assert_eq(b.salad_summons.size(), 4, "Survives until the last action point")
		var final_cell: Vector2i = b.foe + b.SUMMON_RING[budget % b.SUMMON_RING.size()]
		b.hero = Vector2i(2, final_cell.y)
		tick_without_opponent(b, 1)
		assert_lt(b.hp, b.max_hp, "Still damages the player on the final action")
		assert_eq(b.phase, b.Phase.OPPONENT)
		assert_true(b.salad_summons.is_empty())

func test_japanese_crowd_uses_corner_squares_edge_crosses_and_fixed_salad() -> void:
	for seed: int in 12:
		var b := TDChallengeBattle.new(0, 20, 4, seed, [], "tokyo")
		b.hero = Vector2i(4, 5)
		b.foe = Vector2i(10, 7)
		spend_turn(b)
		cast_turn(b)
		assert_eq(b.foe, Vector2i(10, 5))
		assert_eq(b.timed_summons.size(), 1)
		var offset := (b.timed_summons[0].cell - b.hero).abs()
		var corner := offset == Vector2i.ONE
		assert_eq(b._strikes[0].points_left, 1 if corner else 2)
		assert_eq(b._strikes[0].cells.size(), 9 if corner else 25)
		assert_eq(b.salad_summons.size(), 2)
		var ball := b.salad_summons[0]
		var position := ball.cell
		tick_without_opponent(b, 1)
		assert_eq(ball.cell, position)
		assert_eq(ball.moves_left, 4)
		if seed == 0:
			tick_without_opponent(b, 3)
			assert_has(b.salad_summons, ball, "The crowd summon persists across the round boundary")
			tick_without_opponent(b, 1)
			assert_does_not_have(b.salad_summons, ball)

func test_aling_ring_is_hollow_and_expands_immediately_three_times() -> void:
	var b := TDChallengeBattle.new()
	b.hero = Vector2i.ZERO
	var anchor := Vector2i(6,6)
	b._cast_ring(anchor, false)
	b._refresh_warnings()
	assert_eq(b.warnings.size(), 8)
	assert_false(b.warnings.has(anchor))
	tick_without_opponent(b, 1)
	assert_eq(b.warnings[anchor+Vector2i.RIGHT], [1])
	tick_without_opponent(b, 1)
	for radius: int in range(2,5):
		assert_true((anchor + Vector2i.RIGHT*(radius-1)) in b.impacts)
		assert_eq(b.warnings.size(), 8*radius)
		assert_eq(b.warnings[anchor + Vector2i.RIGHT*radius], [1])
		assert_false(b.warnings.has(anchor + Vector2i.RIGHT*(radius-1)))
		tick_without_opponent(b, 1)
	assert_true(b.warnings.is_empty())
	assert_eq(b.impacts.size(), 32)

func test_chen_retreats_twice_then_casts_a_full_cross_and_a_ring() -> void:
	var b := TDChallengeBattle.new(1)
	spend_turn(b)
	for step: int in 2:
		var old_distance := b.distance(b.foe, b.hero)
		b.opponent_step()
		assert_eq(b.distance(b.foe, b.hero), old_distance+1)
		assert_true(b.warnings.is_empty())
	b.opponent_step()
	assert_eq(b.warnings.size(), 25)
	for x: int in b.side:
		assert_eq(b.warnings[Vector2i(x,b.hero.y)], [2])
	for y: int in b.side:
		assert_eq(b.warnings[Vector2i(b.hero.x,y)], [2])
	b.opponent_step()
	assert_eq(b._strikes.size(), 2)
	assert_eq(b.warnings[b.hero], [2], "the last opponent action does not tick the cross")
	assert_false(b._strikes.back().cells.has(b.foe))

func test_chen_cross_replays_immediately_after_the_second_successful_move() -> void:
	var b := TDChallengeBattle.new(1)
	b.hero = Vector2i(4,4)
	b.foe = Vector2i(9,9)
	b.ap = 3
	b._cast_chen_cross(b.hero, true)
	b._refresh_warnings()
	assert_true(b.use_action(Action.SQUARE, Vector2i.ZERO))
	assert_true(b.move(Vector2i.RIGHT))
	assert_false(b.move(Vector2i.ZERO))
	assert_true(b.use_action(Action.SQUARE, Vector2i.ZERO))
	assert_eq(b.phase, b.Phase.OPPONENT)
	assert_true(b.warnings.is_empty())
	b.opponent_step()
	assert_true(b.warnings.is_empty(), "one successful move did not trigger the replay")
	b.phase = b.Phase.PLAYER
	b.ap = b.max_ap
	assert_true(b.move(Vector2i.DOWN))
	assert_eq(b.phase, b.Phase.PLAYER)
	assert_eq(b.hero, Vector2i(5,5))
	assert_eq(b.warnings.get(Vector2i(5,5)), [2])
	assert_eq(b.warnings.get(Vector2i(12,5)), [2])
	assert_false(b.warnings.has(Vector2i(12,4)))
	assert_true(b.move(Vector2i.RIGHT))
	assert_eq(b.warnings.get(Vector2i(12,5)), [1])
	assert_true(b.move(Vector2i.DOWN))
	assert_true(b.warnings.is_empty())

func test_chen_rings_cap_the_timer_at_five_and_clip_each_edge_until_off_board() -> void:
	var b := TDChallengeBattle.new(1)
	b.hero = Vector2i(6,6)
	var anchor := Vector2i(0,1)
	b._cast_ring(anchor, true)
	b._refresh_warnings()
	assert_eq(b.warnings[Vector2i.ZERO], [2])
	tick_without_opponent(b, 2)
	var delays := [3, 4, 5, 5, 5, 5, 5, 5, 5, 5, 5]
	for radius: int in range(2,13):
		assert_false(b.warnings.is_empty())
		assert_false(b.warnings.has(Vector2i.ZERO))
		var delay: int = delays[radius - 2]
		for cell: Vector2i in b.warnings:
			assert_true(b.inside(cell))
			var delta := (cell-anchor).abs()
			assert_eq(maxi(delta.x,delta.y), radius)
			assert_eq(b.warnings[cell], [delay])
		tick_without_opponent(b, delay)
		if b.phase in [b.Phase.LOST,b.Phase.WON,b.Phase.DRAW]:
			fail_test("fixture must survive every ring")
			return
	assert_true(b.warnings.is_empty())
	assert_eq(b._strikes.size(), 0)

func test_chen_retreat_uses_the_center_seven_by_seven() -> void:
	for quadrant: Vector2i in [Vector2i.ONE, Vector2i(1,-1), Vector2i(-1,1), -Vector2i.ONE]:
		var b := TDChallengeBattle.new(1)
		var center := Vector2i(6,6)
		b.hero = center - quadrant * 6
		b.foe = center + quadrant * 2
		spend_turn(b)
		for step: int in 2:
			var previous_distance := b.distance(b.hero, b.foe)
			b.opponent_step()
			assert_eq(b.distance(b.hero, b.foe), previous_distance + 1)
		var farthest := center + quadrant * 3
		assert_eq(b.foe, farthest)
		cast_turn(b)
		spend_turn(b)
		b.opponent_step()
		assert_eq(b.foe, farthest, "holds the farthest tile in the permitted area")
		assert_eq(b.hero, center - quadrant * 6, "player is free to use the outer board")

func test_chen_threshold_teleport_and_four_casts_use_both_corners() -> void:
	var b := TDChallengeBattle.new(1)
	b.hero = Vector2i(4,4)
	b.foe = Vector2i(5,4)
	b.foe_hp = b.foe_max_hp / 2 + 2
	assert_true(b.use_action(Action.LINE, Vector2i.RIGHT))
	assert_eq(b.foe_hp, 50)
	assert_false(b.second_phase)
	assert_true(b.use_action(Action.LINE, Vector2i.RIGHT))
	assert_eq(b.foe_hp, 48)
	assert_true(b.second_phase)
	assert_eq(b.foe, Vector2i(6,6))
	spend_turn(b)
	cast_turn(b)
	assert_eq(b.foe, Vector2i(6,6))
	assert_eq(b._strikes.size(), 4)
	assert_eq(b.warnings[b.hero], [2])
	assert_eq(b.warnings[Vector2i(7,7)], [2])
	assert_eq(b.warnings[Vector2i(12,12)], [2])
	assert_eq(b.warnings[Vector2i(1,1)], [2])
	assert_false(b.warnings.has(Vector2i.ZERO))
	b.move(Vector2i.RIGHT)
	b.move(Vector2i.DOWN)
	assert_eq(b.warnings.get(Vector2i(12,12)), [2])
	assert_eq(b.warnings.get(Vector2i(12,5)), [2,2])

func test_chen_teleport_never_overlaps_the_player() -> void:
	var b := TDChallengeBattle.new(1)
	b.hero = Vector2i(6,6)
	b.foe = b.hero + Vector2i.RIGHT
	b.foe_hp = 10
	assert_true(b.use_action(Action.LINE, Vector2i.RIGHT))
	assert_true(b.second_phase)
	assert_ne(b.hero, b.foe)
	assert_eq(b.distance(b.hero,b.foe),1)

func test_luoe_opens_with_two_moves_and_three_one_point_waves_that_wait_for_a_move() -> void:
	var b := TDChallengeBattle.new(4, 20, 4, 90)
	var center := Rect2i(5, 5, 5, 5)
	b.hero = Vector2i(3, 7)
	spend_turn(b)
	for step: int in 2:
		var before := b.foe
		b.opponent_step()
		assert_eq(b.distance(before, b.foe), 1)
		assert_true(center.has_point(b.foe) and b.warnings.is_empty())
		assert_ne(b.foe.y, b.hero.y)
	cast_turn(b)
	assert_eq(b._strikes.size(), 3)
	assert_eq(b._luoe_followups.size(), 3)
	for strike: TDChallengeBattle.Strike in b._strikes:
		assert_eq(strike.points_left, 1)
		assert_eq(strike.cells.size(), 30)
		assert_eq(strike.cells.filter(func(cell: Vector2i) -> bool: return cell.y == b.hero.y).size(), 15)
	b.hero += Vector2i.UP
	b.use_action(Action.SQUARE, Vector2i.ZERO)
	assert_true(b._strikes.is_empty())
	var vertical := b._luoe_followups.duplicate()
	assert_true(b.move(Vector2i.LEFT))
	assert_true(b._luoe_followups.is_empty())
	for i: int in b._strikes.size():
		assert_eq(b._strikes[i].points_left, 1)
		for step: int in b.side:
			assert_has(b._strikes[i].cells, Vector2i(b.hero.x, step) if vertical[i] else Vector2i(step, b.hero.y))

func test_luoe_pressure_round_combines_two_full_crosses_and_three_hollow_frames() -> void:
	var b := TDChallengeBattle.new(4, 20, 4, 8)
	b._luoe_round = b.LuoeRound.PRESSURE
	b.hero = Vector2i(3, 7)
	spend_turn(b)
	cast_turn(b)
	assert_eq(b._strikes.size(), 3)
	assert_eq(b._luoe_followups.size(), 1)
	var crosses: Array[Vector2i] = b._strikes[1].cells
	for point: Vector2i in [b.hero, b.foe, Vector2i(0,b.hero.y), Vector2i(14,b.foe.y), Vector2i(b.hero.x,0), Vector2i(b.foe.x,14)]:
		assert_has(crosses, point)
	var frames: Array[Vector2i] = b._strikes[2].cells
	assert_eq(frames.size(), 8 + 24 + 40)
	for delta: Vector2i in [Vector2i(1,0), Vector2i(3,3), Vector2i(-5,5)]: assert_has(frames, b.foe + delta)
	for delta: Vector2i in [Vector2i.ZERO, Vector2i(2,0), Vector2i(4,-4)]: assert_does_not_have(frames, b.foe + delta)

func test_luoe_guards_shield_the_boss_and_clear_into_parallel_lanes_and_bombs() -> void:
	var b := TDChallengeBattle.new(4, 20, 4, 18)
	b._luoe_round = b.LuoeRound.SUMMONING
	b.hero = Vector2i(2, 2)
	spend_turn(b)
	cast_turn(b)
	var locked := b.foe
	assert_eq(b.ap, 2)
	assert_true(b.luoe_guarded())
	assert_eq(b.guards.size(), 3)
	for i: int in 3:
		assert_eq(b.guards[i].cell, locked + [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.DOWN][i] * 2)
		assert_eq(b.guards[i].hp, 15)
	b.hero = locked + Vector2i.UP * 2
	b.use_action(Action.SQUARE, Vector2i.ZERO)
	assert_eq(b.foe_hp, b.foe_max_hp)
	b.hero = Vector2i(1,1)
	spend_turn(b)
	assert_eq(b.enemy_ap, 3)
	cast_turn(b)
	assert_eq(b.foe, locked)
	assert_eq(b.ap, 4, "Action reduction applied for exactly one round")
	for guard: TDChallengeBattle.Guard in b.guards:
		var strikes := b._strikes.filter(func(strike: TDChallengeBattle.Strike) -> bool: return strike.guard == guard)
		var bombs := b.tomatoes.filter(func(tomato: TDChallengeBattle.Tomato) -> bool: return tomato.guard == guard)
		var salads := b.salad_summons.filter(func(salad: TDChallengeBattle.SaladSummon) -> bool: return salad.guard == guard)
		assert_eq(int(not strikes.is_empty()) + int(not bombs.is_empty()) + int(not salads.is_empty()), 1)
		for strike: TDChallengeBattle.Strike in strikes: assert_eq(strike.damage, strike.points_left + 2)
	b._strikes.clear()
	b.tomatoes.clear()
	b.timed_summons.clear()
	b.salad_summons.clear()
	b.hero = locked + Vector2i.DOWN
	for i: int in 3:
		b.guards[i].hp = 2
		b.guards[i].cell = locked + [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.DOWN][i] * 2
	b.use_action(Action.SQUARE, Vector2i.ZERO)
	assert_true(b.guards.is_empty())
	assert_false(b.luoe_guarded())
	assert_eq(b.foe_hp, b.foe_max_hp)
	b.hero = Vector2i(1,1)
	spend_turn(b)
	cast_turn(b)
	assert_eq(b._luoe_followups, [false])
	assert_false(b.tomatoes.is_empty())
	assert_eq(b._luoe_round, b.LuoeRound.OPENING)

func test_luoe_second_phase_takes_damage_with_guards_and_keeps_casting_without_movement() -> void:
	var b := TDChallengeBattle.new(4, 20, 4, 84)
	var center := Vector2i(7,7)
	b.hero = center
	b.foe = center + Vector2i.RIGHT
	b.foe_hp = 12
	b._luoe_round = b.LuoeRound.SUMMONING
	b.use_action(Action.SQUARE, Vector2i.ZERO)
	assert_true(b.second_phase)
	assert_eq(b.foe, center)
	assert_ne(b.hero, center, "Teleport cannot trap the player in the same cell")
	b.hero = Vector2i(1,1)
	spend_turn(b)
	assert_eq(b.enemy_ap, 3, "The summon round adds one cast without a movement budget")
	assert_has(b.LUOE_EXTRA_ATTACKS, b._luoe_actions.back())
	cast_turn(b)
	assert_false(b.luoe_guarded())
	assert_eq(b.guards.size(), 3)
	b.hero = center + Vector2i.UP
	b.use_action(Action.SQUARE, Vector2i.ZERO)
	assert_eq(b.foe_hp, 8)
	b.hero = Vector2i(1,1)
	b._strikes.clear()
	b.tomatoes.clear()
	b._luoe_followups.clear()
	spend_turn(b)
	assert_eq(b.enemy_ap, 4, "Three guard actions and one additional boss attack")
	assert_has(b.LUOE_EXTRA_ATTACKS, b._luoe_actions.back())
	cast_turn(b)
	assert_eq(b.foe, center)
	assert_eq(b.guards.size(), 3)

func test_luoe_corner_bombs_move_clockwise_and_explode_up_and_right_on_third_action() -> void:
	var b := TDChallengeBattle.new(4)
	b.foe = Vector2i(7,7)
	b._cast_luoe_tomatoes()
	assert_eq(b.tomatoes.size(), 28)
	assert_true(b.tomatoes.any(func(tomato: TDChallengeBattle.Tomato) -> bool: return tomato.cell == Vector2i(14,14)))
	var bomb := b.tomatoes[0]
	b.tomatoes.assign([bomb])
	b.hero = Vector2i(9,6)
	assert_eq(bomb.cell, Vector2i(6,6))
	for step: int in 2:
		b.use_action(Action.LINE, Vector2i.RIGHT)
		assert_eq(bomb.cell, Vector2i(7+step,6))
		assert_eq(bomb.moves_left, 2-step)
		assert_eq(b.hp, b.max_hp)
	b.use_action(Action.LINE, Vector2i.RIGHT)
	assert_eq(bomb.cell, Vector2i(8,7))
	assert_true(b.tomatoes.is_empty())
	assert_eq(b.hp, b.max_hp - b._enemy_damage(3))
	assert_eq(b.impacts.size(), 4)
	assert_has(b.impacts, Vector2i(8,7))
	assert_does_not_have(b.impacts, Vector2i(7,7))
	assert_eq(b.luoe_blast_cells(Vector2i(14,0)), [Vector2i(14,0)])

func test_last_paid_action_can_result_in_a_draw() -> void:
	for terminal: int in [TDChallengeBattle.Phase.WON, TDChallengeBattle.Phase.DRAW, TDChallengeBattle.Phase.LOST]:
		var b := TDChallengeBattle.new(4, 20, 1)
		b.foe = b.hero+Vector2i.UP
		b.hp = 1
		if terminal != b.Phase.LOST: b.foe_hp = 1
		if terminal != b.Phase.WON: b._schedule_strike([b.hero], 1)
		b.use_action(Action.SQUARE, Vector2i.ZERO)
		assert_eq(b.phase, terminal)
		assert_eq(b.ap, 0)
		assert_false(b.move(Vector2i.RIGHT))
		b.opponent_step()
		assert_eq(b.round_number, 1)

func test_vito_moves_first_then_cycles_forks_knives_and_tomatoes() -> void:
	var cycle := [Vito.FORKS, Vito.KNIVES, Vito.TOMATOES, Vito.FORKS, Vito.KNIVES]
	for turn: int in range(1, 5):
		var b := TDChallengeBattle.new(2, 20, 4, 38)
		b.round_number = turn
		b.hero = Vector2i(4, 5)
		b.foe = Vector2i(9, 5)
		spend_turn(b)
		for gap: int in [4,3,3]:
			b.opponent_step()
			assert_eq(b.distance(b.hero,b.foe), gap)
			assert_true(b.warnings.is_empty() and b.tomatoes.is_empty())
		for cast: int in 2:
			var previous := b.utensils.size()
			b.opponent_step()
			var expected: int = cycle[turn - 1 + cast]
			if expected == Vito.TOMATOES:
				assert_eq(b.tomatoes.size(), 4)
				for tomato: TDChallengeBattle.Tomato in b.tomatoes:
					assert_eq((tomato.cell-b.foe).abs(), Vector2i.ONE)
					assert_eq(tomato.moves_left, 3)
			else:
				assert_eq(b.utensils.size(), previous + 7)
				assert_eq(b.utensils.back().utensil, expected)

func test_vito_utensils_telegraph_full_lanes_and_only_fast_lanes_repeat() -> void:
	for attack: int in [Vito.FORKS, Vito.KNIVES]:
		var b := TDChallengeBattle.new(2)
		b.hero = Vector2i(1, 1)
		b._cast_utensils(attack)
		b._refresh_warnings()
		for lane: int in range(0,13,2):
			var strike := b.utensils[lane / 2]
			assert_eq(strike.anchor, Vector2i(lane,0) if attack == Vito.FORKS else Vector2i(0,lane))
			assert_eq(strike.cells.size(), 13)
			assert_eq(strike.points_left, 1 if lane % 4 == 0 else 3)
		for step: int in 3:
			tick_without_opponent(b, 1)
			assert_eq(b.impacts.size(), [52,52,39][step])
			assert_eq(b.utensils.size(), [7,3,0][step])
		assert_true(b.warnings.is_empty())

func test_vito_tomato_steps_then_explodes_in_its_last_preview_square() -> void:
	var b := TDChallengeBattle.new(2, 20, 4, 93)
	b.hero = Vector2i.ZERO
	var tomato := TDChallengeBattle.Tomato.new(Vector2i(10,10))
	b.tomatoes.append(tomato)
	for i: int in 3:
		var previous := tomato.cell
		tick_without_opponent(b, 1)
		assert_eq(b.distance(previous, tomato.cell), 1)
		assert_eq(tomato.moves_left, 2-i)
		assert_true(b.inside(tomato.cell))
		if i < 2: assert_true(b.impacts.is_empty())
	assert_eq(b.impacts.keys(), b.square_cells(tomato.cell, 1))
	assert_true(b.tomatoes.is_empty())

func test_vito_tomato_touch_hastens_the_explosion_without_contact_damage() -> void:
	var b := TDChallengeBattle.new(2, 20, 4, 42)
	b.hero = Vector2i.ZERO
	var tomato := TDChallengeBattle.Tomato.new(Vector2i.RIGHT)
	b.tomatoes.append(tomato)
	assert_true(b.move(Vector2i.RIGHT))
	assert_eq(tomato.moves_left, 1)
	assert_eq(b.hp, b.max_hp)
	assert_true(b.inside(tomato.cell))
	assert_true(b.move(tomato.cell - b.hero))
	assert_eq(b.hp, b.max_hp - b._enemy_damage(3))
	assert_true(b.tomatoes.is_empty())
	assert_eq(b.impacts.keys(), b.square_cells(tomato.cell, 1))

func test_vito_tomato_advances_its_fuse_if_it_moves_onto_a_stationary_player() -> void:
	var b := TDChallengeBattle.new(2, 20, 4, 53)
	var tomato := TDChallengeBattle.Tomato.new(Vector2i(6,6))
	b.tomatoes.append(tomato)
	var predictor := RandomNumberGenerator.new()
	predictor.state = b._rng.state
	b.hero = tomato.cell + b.DIRECTIONS[predictor.randi_range(0, 3)]
	tick_without_opponent(b, 1)
	assert_eq(tomato.cell, b.hero)
	assert_eq(tomato.moves_left, 1)
	assert_eq(b.hp, b.max_hp)

func test_vito_only_summons_and_explodes_in_bounds_at_a_corner() -> void:
	var b := TDChallengeBattle.new(2, 20, 4, 71)
	b.round_number = 3
	b.enemy_ap = 2
	b.foe = Vector2i.ZERO
	b._vito_action()
	assert_eq(b.tomatoes.size(), 1)
	assert_eq(b.tomatoes[0].cell, Vector2i.ONE)
	b.tomatoes[0].cell = Vector2i.ZERO
	b.tomatoes[0].moves_left = 1
	b.hero = Vector2i.RIGHT
	b.foe = Vector2i(12,12)
	assert_true(b.move(Vector2i.LEFT))
	assert_eq(b.impacts.size(), 4)
	assert_true(b.impacts.has(Vector2i.ONE))
	assert_true(b.tomatoes.is_empty())

func test_vito_half_health_changes_movement_and_always_summons_tomatoes_first() -> void:
	var kinds_seen := {}
	for seed: int in range(12):
		var b := TDChallengeBattle.new(2, 20, 4, seed)
		b.hero = Vector2i(5,5)
		b.foe = Vector2i(9,5)
		b.foe_hp = 12
		assert_true(b.use_action(Action.LINE, Vector2i.RIGHT))
		assert_eq(b.foe_hp, 10)
		assert_true(b.second_phase)
		assert_eq(b.foe, Vector2i(9,5))
		tick_without_opponent(b, b.ap)
		for gap: int in [3,2,1]:
			b.opponent_step()
			assert_eq(b.distance(b.hero, b.foe), gap)
		b.opponent_step()
		assert_eq(b.tomatoes.size(), 4)
		assert_true(b.utensils.is_empty())
		b.opponent_step()
		assert_eq(b.utensils.size(), 7)
		assert_eq(b.tomatoes[0].moves_left, 3, "opponent actions do not advance tomatoes")
		kinds_seen[b.utensils[0].utensil] = true
	assert_true(kinds_seen.has_all([Vito.FORKS,Vito.KNIVES]))
