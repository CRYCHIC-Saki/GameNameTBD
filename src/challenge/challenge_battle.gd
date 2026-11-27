class_name TDChallengeBattle
extends RefCounted
## A single duel. Pending strikes advance only when the player spends an action point.

enum Phase { PLAYER, OPPONENT, WON, LOST, DRAW }

static func continues_story(phase: int, assessment: bool = false) -> bool:
	return phase==Phase.WON or (assessment and phase in [Phase.LOST,Phase.DRAW])

enum Action { NONE, LINE, SQUARE, SLOT_1, SLOT_2 }
enum Tutorial { NONE, ALING_MOVE, ALING_LINE, ALING_SQUARE, ALING_BUDGET, ALING_DODGE, CHEN_CAST, CHEN_CHARGE, CHEN_PICKUP }
enum VitoAttack { FORKS, KNIVES, TOMATOES }
enum TomatoMotion { VITO, RANDOM, CHASE, LUOE_ORBIT }
enum LuoeAction { MOVE, PERPENDICULAR, PARALLEL, CROSSES, FRAMES, SUMMON, TOMATOES, REDUCE_AP, GUARDS }
enum LuoeRound { OPENING, PRESSURE, SUMMONING, GUARD_ENCOUNTER }
const Skills := preload("res://src/challenge/challenge_skills.gd")
const Rules := preload("res://src/challenge/challenge_rules.gd")
const OPPONENTS := Rules.OPPONENTS
const CROWD_RIVALS := Rules.CROWD_RIVALS
const DIRECTIONS := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
const MAX_ENERGY := 10
const CRYSTAL_ENERGY := 2
const LINE_LENGTH := 6
const ALING_GAP := 5
const CHEN_MOVEMENT_SIDE := 7
const CHEN_RING_MAX_DELAY := 5
const VITO_GAP := 3
const GUARD_HP := 15
const GUARD_AP := 3
const LUOE_EXTRA_ATTACKS := [LuoeAction.PERPENDICULAR, LuoeAction.PARALLEL, LuoeAction.CROSSES,
	LuoeAction.FRAMES, LuoeAction.TOMATOES]
const SUMMON_RING := [
	Vector2i(-1,-1), Vector2i(0,-1), Vector2i(1,-1), Vector2i(1,0),
	Vector2i(1,1), Vector2i(0,1), Vector2i(-1,1), Vector2i(-1,0),
]

class Guard:
	var id: String
	var name: String
	var cell: Vector2i
	var hp := GUARD_HP
	var attack_bonus := 0
	var next_attack_bonus := 0

	func _init(style: String, title: String, position: Vector2i) -> void:
		id = style
		name = title
		cell = position

class TimedSummon:
	var cell: Vector2i
	var rounds_left := 2
	var hits_left := 2
	var guard: Guard

	func _init(position: Vector2i) -> void:
		cell = position

class SaladSummon:
	var cell: Vector2i
	var ring_index: int
	# The stationary crowd summon lasts for five player actions.
	var moves_left := 5
	var orbits: bool
	var guard: Guard

	func _init(position: Vector2i, slot: int, moving: bool) -> void:
		cell = position
		ring_index = slot
		orbits = moving

class Strike:
	var cells: Array[Vector2i]
	var points_left: int
	var source: TimedSummon
	var anchor := Vector2i.ZERO
	var radius := 0
	var max_radius := 0
	var expanding_slowly := false
	var utensil := -1
	var repeats_left := 0
	var damage := 0
	var guard: Guard

	func _init(cells_to_hit: Array[Vector2i], delay: int) -> void:
		cells = cells_to_hit
		points_left = delay

class Tomato:
	var cell: Vector2i
	var moves_left := 3
	var delay_steps := 0
	var motion: TomatoMotion
	var guard: Guard
	var orbit_center := Vector2i.ZERO

	func _init(position: Vector2i, behavior: TomatoMotion = TomatoMotion.VITO) -> void:
		cell = position
		motion = behavior

class CrossRepeat:
	var anchor: Vector2i
	var tracks_player: bool
	var moves_left := 2

	func _init(center: Vector2i, track: bool) -> void:
		anchor = center
		tracks_player = track

var side: int
var max_ap: int
var foe_max_ap: int
var round_number := 1
var phase := Phase.PLAYER
var ap: int
var enemy_ap := 0
var hero: Vector2i
var foe: Vector2i
var facing := Vector2i.RIGHT
var hp: int
var max_hp: int
var foe_hp: int
var foe_max_hp: int
var base_damage: int
var preparation: Dictionary
var cooking_tier: int
var player_attack_bonus := 0
var shield_round := -1
var skill_slots: Array[String]
var energy := 0
var opponent: Dictionary
var rematch := false
var second_phase := false
var attack_bonus := 0
# Projection of the scheduled strikes for the board. Overlap retains every countdown.
var warnings: Dictionary = {}
var utensils: Array[Strike] = []
var tomatoes: Array[Tomato] = []
var player_tomatoes: Array[Tomato] = []
var timed_summons: Array[TimedSummon] = []
var salad_summons: Array[SaladSummon] = []
var guards: Array[Guard] = []
var pickups: Array[Vector2i] = []
var impacts: Dictionary = {}
var player_strike: Dictionary = {}
var message := "你先行动。选择条形或方形普攻。"
var _strikes: Array[Strike] = []
var _cross_repeats: Array[CrossRepeat] = []
var _rng := RandomNumberGenerator.new()
var _next_attack_bonus := 0
var _luoe_round := LuoeRound.OPENING
var _luoe_actions: Array[LuoeAction] = []
var _luoe_followups: Array[bool] = []
var _player_ap_penalty := 0
var player_ap_budget: int
var tutorial := Tutorial.NONE
var tutorial_completed := ""
var _practice_actions := 0
var _practice_hero: Vector2i
var _practice_foe: Vector2i
var _practice_loadout: Array[String] = []

func _init(opponent_index: int = 0, board_size: int = 20, points: int = 4, battle_seed: int = -1, loadout: Array = [], story_crowd: String = "", scores: Dictionary = {}, stats: Dictionary = {}, boss_rematch: bool = false) -> void:
	opponent = (CROWD_RIVALS[story_crowd] if CROWD_RIVALS.has(story_crowd) else OPPONENTS[opponent_index]).duplicate()
	rematch = boss_rematch and story_crowd.is_empty()
	if rematch:
		opponent.hp = Rules.REMATCH_HP
		opponent.damage_offset = Rules.REMATCH_DAMAGE_OFFSET
	preparation = scores.duplicate()
	cooking_tier = int(preparation.get("tier", 0))
	var extra_hp := 5 if cooking_tier == 2 else (2 if cooking_tier == 1 else 0)
	max_hp = int(stats.get("hp", Rules.BASE_HP)) + extra_hp
	hp = max_hp
	foe_max_hp = int(opponent.hp)
	foe_hp = foe_max_hp
	base_damage = int(stats.get("damage", Rules.BASE_DAMAGE))
	skill_slots = Skills.normalize(loadout, Skills.DEFINITIONS.keys())
	side = int(opponent.get("side", clampi(board_size, 8, 32)))
	max_ap = clampi(int(stats.get("ap", points)), 1, 12)
	foe_max_ap = int(opponent.get("ap", max_ap))
	ap = max_ap
	player_ap_budget = max_ap
	if battle_seed >= 0:
		_rng.seed = battle_seed
	else:
		_rng.randomize()
	hero = Vector2i(floori(side * 0.32), floori(side * 0.53))
	foe = Vector2i(floori(side * 0.67), hero.y)
	if opponent.id == "luoe": foe.x = side / 2 + 2
	if opponent.id.begins_with("crowd_"): _spawn_pickup()

func begin_tutorial() -> void:
	if opponent.id not in ["aling", "chen"]: return
	_practice_hero = hero
	_practice_foe = foe
	ap = Rules.BASE_AP
	player_ap_budget = ap
	if opponent.id == "aling":
		tutorial = Tutorial.ALING_MOVE
	else:
		tutorial = Tutorial.CHEN_CAST
		_practice_loadout = skill_slots.duplicate()
		skill_slots[0] = Skills.BEAM
		if skill_slots[1] == Skills.BEAM: skill_slots[1] = ""
		energy = int(Skills.DEFINITIONS[Skills.BEAM].energy_cost)
		foe = hero + Vector2i.RIGHT * 2

func _finish_tutorial() -> void:
	tutorial = Tutorial.NONE
	tutorial_completed = str(opponent.id)
	hero = _practice_hero
	foe = _practice_foe
	hp = max_hp
	ap = max_ap
	player_ap_budget = max_ap
	if tutorial_completed == "chen": skill_slots.assign(_practice_loadout)
	facing = Vector2i.RIGHT
	impacts.clear()
	player_strike.clear()
	message = "你先行动。"

func inside(cell: Vector2i) -> bool:
	return Rect2i(0, 0, side, side).has_point(cell)

func guard_at(cell: Vector2i) -> Guard:
	for guard: Guard in guards:
		if guard.cell == cell: return guard
	return null

func enemy_at(cell: Vector2i) -> bool:
	return cell == foe or guard_at(cell) != null

func luoe_guarded() -> bool:
	return opponent.id == "luoe" and not second_phase and not guards.is_empty()

static func distance(a: Vector2i, b: Vector2i) -> int:
	var offset := (a - b).abs()
	return offset.x + offset.y

func direction_toward(cell: Vector2i) -> Vector2i:
	var offset := cell - hero
	if offset == Vector2i.ZERO or not inside(cell):
		return facing
	if absi(offset.x) >= absi(offset.y):
		return Vector2i(signi(offset.x), 0)
	return Vector2i(0, signi(offset.y))

func attack_cells(action: Action, direction: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if action == Action.SQUARE: return square_cells(hero, 2)
	if not needs_aim(action) or direction not in DIRECTIONS: return cells
	var across := Vector2i(-direction.y, direction.x)
	var width := 0 if action == Action.LINE else 1
	var length := LINE_LENGTH if action == Action.LINE else side - 1
	for step: int in range(1, length + 1):
		var row := hero + direction * step
		if not inside(row): break
		for offset: int in range(-width, width + 1):
			var cell := row + across * offset
			if inside(cell): cells.append(cell)
	return cells

func skill_id(action: Action) -> String:
	return skill_slots[action - Action.SLOT_1] if action in [Action.SLOT_1, Action.SLOT_2] else ""

func needs_aim(action: Action) -> bool:
	return action == Action.LINE or bool(Skills.DEFINITIONS.get(skill_id(action), {}).get("aim", false))

func can_use(action: Action) -> bool:
	if phase != Phase.PLAYER or action == Action.NONE: return false
	match tutorial:
		Tutorial.ALING_MOVE, Tutorial.CHEN_PICKUP: return false
		Tutorial.ALING_LINE: return action == Action.LINE
		Tutorial.ALING_SQUARE: return action == Action.SQUARE
		Tutorial.ALING_BUDGET, Tutorial.ALING_DODGE, Tutorial.CHEN_CHARGE:
			return action in [Action.LINE, Action.SQUARE] and ap > 0
		Tutorial.CHEN_CAST: return action == Action.SLOT_1
	if action in [Action.LINE, Action.SQUARE]: return ap > 0
	var id := skill_id(action)
	if id.is_empty(): return false
	var skill: Dictionary = Skills.DEFINITIONS[id]
	return energy >= skill.energy_cost and ap >= skill.ap

func square_cells(center: Vector2i, radius: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y: int in range(maxi(0, center.y-radius), mini(side, center.y+radius+1)):
		for x: int in range(maxi(0, center.x-radius), mini(side, center.x+radius+1)):
			cells.append(Vector2i(x, y))
	return cells

func move(direction: Vector2i) -> bool:
	if tutorial in [Tutorial.ALING_LINE, Tutorial.ALING_SQUARE, Tutorial.CHEN_CAST]: return false
	var target := hero + direction
	if phase != Phase.PLAYER or direction not in DIRECTIONS or not inside(target) or enemy_at(target):
		return false
	hero = target
	facing = direction
	player_strike.clear()
	message = "移动一格。"
	if hero in pickups:
		pickups.erase(hero)
		var restored := mini(CRYSTAL_ENERGY, MAX_ENERGY - energy)
		energy += restored
		message = "拾取充能晶石，恢复 %d 点能量。" % restored
	_spend_point(true)
	return true

func use_action(action: Action, direction: Vector2i) -> bool:
	if not can_use(action) or (needs_aim(action) and direction not in DIRECTIONS): return false
	var id := skill_id(action)
	var skill: Dictionary = Skills.DEFINITIONS.get(id, {})
	if not id.is_empty(): energy -= int(skill.energy_cost)
	if id in [Skills.DELAY, Skills.HEAL]:
		player_strike.clear()
		impacts.clear()
		if id == Skills.DELAY:
			for strike: Strike in _strikes: strike.points_left += 1
			for tomato: Tomato in tomatoes + player_tomatoes:
				tomato.moves_left += 1
				tomato.delay_steps += 1
			for ball: TimedSummon in timed_summons: ball.rounds_left += 1
			for ball: SaladSummon in salad_summons:
				if not ball.orbits: ball.moves_left += 1
			_refresh_warnings()
			message = "延时：场上的倒计时增加 1。"
		else:
			var recovered := mini(max_hp - hp, skill.healing)
			hp += recovered
			player_attack_bonus = 1
			message = "疗愈：恢复 %d 点生命，本回合伤害 +1。" % recovered
		return true
	if id == Skills.SHIELD or id == Skills.TOMATO:
		player_strike.clear()
		if id == Skills.SHIELD:
			shield_round = round_number + 1
			message = "免伤护盾：下一回合免疫伤害。"
		else:
			message = "追踪番茄已布下，将朝敌人移动。"
		_spend_point(false)
		if id == Skills.TOMATO and phase in [Phase.PLAYER, Phase.OPPONENT]:
			for diagonal: Vector2i in [SUMMON_RING[0], SUMMON_RING[2], SUMMON_RING[4], SUMMON_RING[6]]:
				var cell := hero + diagonal
				if inside(cell): player_tomatoes.append(Tomato.new(cell, TomatoMotion.CHASE))
		return true
	var cells := attack_cells(action, direction)
	if needs_aim(action): facing = direction
	player_strike.clear()
	for cell: Vector2i in cells: player_strike[cell] = true
	var title: String = skill.get("name", "焰之舌" if action == Action.LINE else "焰之旋")
	if tutorial != Tutorial.NONE:
		message = "%s已释放。" % title
		if tutorial == Tutorial.CHEN_CHARGE:
			if foe in cells:
				energy = mini(energy + 1, MAX_ENERGY)
				message = "命中练习目标，恢复 1 点能量。"
			else:
				message = "未命中练习目标。"
		_spend_point(false)
		return true
	var hit := _hit_enemies(cells, damage_for(int(skill.get("damage", Rules.BASE_DAMAGE))))
	message = "%s命中，造成 %d 点伤害。" % [title, hit.damage] if hit.damage > 0 else "%s未命中。" % title
	if hit.critical: message += " 暴击！"
	if hit.shielded: message += " 援兵保护着罗厄。"
	if hit.foe and id.is_empty(): energy = mini(energy + 1, MAX_ENERGY)
	if hit.foe: _enter_second_phase()
	_hit_timed_summons(cells)
	_spend_point(false)
	return true

func damage_for(standard: int) -> int:
	return maxi(1, standard + base_damage - Rules.BASE_DAMAGE + player_attack_bonus - int(cooking_tier == -2))

func _hit_enemies(cells: Array[Vector2i], power: int) -> Dictionary:
	var shielded := foe in cells and luoe_guarded()
	var hit_foe := foe in cells and foe_hp > 0 and not shielded
	var critical := cooking_tier == 2 and (hit_foe or guards.any(func(guard: Guard) -> bool: return guard.cell in cells)) and _rng.randf() < 0.05
	if critical: power *= 2
	var dealt := mini(foe_hp, power) if hit_foe else 0
	foe_hp -= dealt
	var guard_damage := 0
	for guard: Guard in guards.duplicate():
		if guard.cell not in cells: continue
		var damage := mini(guard.hp, power)
		guard.hp -= damage
		guard_damage += damage
		if guard.hp == 0: guards.erase(guard)
	return {"damage":dealt + guard_damage, "foe":dealt > 0, "shielded":shielded, "critical":critical}

func _enter_second_phase() -> void:
	if opponent.id == "hina":
		var next := foe_hp > 0 and foe_hp * 2 <= foe_max_hp
		if next != second_phase and foe_hp > 0:
			message += " 日奈进入二阶段。" if next else " 日奈恢复一阶段。"
		second_phase = next
		return
	if second_phase or foe_hp == 0: return
	if opponent.id == "vito" and foe_hp * 2 <= foe_max_hp:
		second_phase = true
		message += " 维托进入二阶段，开始贴身追击。"
	elif opponent.id == "chen" and foe_hp * 2 < foe_max_hp:
		second_phase = true
		foe = Vector2i(side / 2, side / 2)
		if foe == hero:
			foe += Vector2i.UP
		message += " 罗金娜进入二阶段，瞬移到中央。"
	elif opponent.id == "luoe" and foe_hp * 2 <= foe_max_hp:
		second_phase = true
		foe = Vector2i.ONE * (side / 2)
		_displace_hero_on_enemy()
		message += " 罗厄进入二阶段，回到棋盘中央。"

func _spend_point(moved: bool) -> void:
	if tutorial != Tutorial.NONE and tutorial != Tutorial.ALING_DODGE:
		_spend_tutorial_action()
		return
	tutorial_completed = ""
	ap -= 1
	impacts.clear()
	var continuing: Array[Strike] = []
	var damage := 0
	for strike: Strike in _strikes:
		strike.points_left -= 1
		if strike.points_left > 0:
			continuing.append(strike)
			continue
		var hit := _impact_damage(strike.cells, strike.damage + (attack_bonus if strike.guard == null else strike.guard.attack_bonus))
		damage += hit
		if hit > 0 and shield_round != round_number and strike.source != null and strike.source in timed_summons:
			_tick_timed_summon(strike.source)
		if strike.repeats_left > 0:
			strike.repeats_left -= 1
			strike.points_left = 1
			strike.damage = _enemy_damage(1, strike.guard)
			continuing.append(strike)
		if strike.radius < strike.max_radius:
			strike.radius += 1
			strike.cells = _ring_cells(strike.anchor, strike.radius)
			strike.points_left = mini(strike.radius + 1, CHEN_RING_MAX_DELAY) if strike.expanding_slowly else 1
			strike.damage = _enemy_damage(strike.points_left, strike.guard)
			if not strike.cells.is_empty(): continuing.append(strike)
	_strikes = continuing
	if not tomatoes.is_empty(): damage += _advance_tomatoes(moved)
	damage += _advance_salad_summons()
	if not player_tomatoes.is_empty(): _advance_player_tomatoes()
	if damage > 0:
		if shield_round == round_number: message += " 护盾抵挡了 %d 点伤害。" % damage
		else:
			hp = maxi(1 if tutorial == Tutorial.ALING_DODGE else 0, hp - damage)
			message += " 踩中预警，生命 −%d。" % damage
	if moved and hp > 0:
		_advance_cross_repeats()
		_advance_luoe_followups()
	_refresh_warnings()
	if tutorial == Tutorial.ALING_DODGE:
		if _strikes.is_empty():
			if damage > 0: _cast_practice_crow()
			else: _finish_tutorial()
		return
	_check_result()
	if phase == Phase.PLAYER and ap == 0: _finish_player_turn()

func _spend_tutorial_action() -> void:
	impacts.clear()
	match tutorial:
		Tutorial.ALING_MOVE, Tutorial.ALING_LINE, Tutorial.ALING_SQUARE:
			_practice_actions += 1
			if _practice_actions < 4: return
			_practice_actions = 0
			match tutorial:
				Tutorial.ALING_MOVE: tutorial = Tutorial.ALING_LINE
				Tutorial.ALING_LINE: tutorial = Tutorial.ALING_SQUARE
				Tutorial.ALING_SQUARE: tutorial = Tutorial.ALING_BUDGET
		Tutorial.ALING_BUDGET:
			ap -= 1
			if ap == 0:
				tutorial = Tutorial.ALING_DODGE
				_cast_practice_crow()
		Tutorial.CHEN_CAST:
			ap -= 1
			tutorial = Tutorial.CHEN_CHARGE
		Tutorial.CHEN_CHARGE:
			if energy >= int(Skills.DEFINITIONS[Skills.BEAM].energy_cost):
				tutorial = Tutorial.CHEN_PICKUP
				_spawn_pickup()
		Tutorial.CHEN_PICKUP:
			if pickups.is_empty(): _finish_tutorial()

func _cast_practice_crow() -> void:
	ap = Rules.BASE_AP
	_schedule_strike(_cross_cells(hero, 1), 2)
	_refresh_warnings()

func _finish_player_turn() -> void:
	pickups.clear()
	player_attack_bonus = 0
	for ball: TimedSummon in timed_summons.duplicate(): _tick_timed_summon(ball)
	attack_bonus = _next_attack_bonus
	_next_attack_bonus = 0
	for guard: Guard in guards:
		guard.attack_bonus = guard.next_attack_bonus
		guard.next_attack_bonus = 0
	phase = Phase.OPPONENT
	if opponent.id == "luoe": _prepare_luoe_turn()
	else: enemy_ap = foe_max_ap

func _impact_damage(cells: Array[Vector2i], power: int) -> int:
	for cell: Vector2i in cells: impacts[cell] = true
	return power if hero in cells else 0

func _enemy_damage(delay: int, guard: Guard = null) -> int:
	return delay + (2 if guard != null else int(opponent.damage_offset))

func _check_result() -> void:
	if hp == 0 and foe_hp == 0: phase = Phase.DRAW
	elif hp == 0: phase = Phase.LOST
	elif foe_hp == 0: phase = Phase.WON

func opponent_step() -> void:
	if phase != Phase.OPPONENT: return
	impacts.clear()
	player_strike.clear()
	match opponent.id:
		"aling", "crowd_cn": _aling_action()
		"chen": _chen_action()
		"vito": _vito_action()
		"crowd_eu": _european_crowd_action()
		"hina", "crowd_jp": _summon_action()
		"luoe": _luoe_action()
	_refresh_warnings()
	enemy_ap -= 1
	if enemy_ap == 0:
		round_number += 1
		phase = Phase.PLAYER
		var cooking_penalty := int(cooking_tier == -1 and round_number % 5 == 0)
		player_ap_budget = maxi(0, max_ap - _player_ap_penalty - cooking_penalty)
		_player_ap_penalty = 0
		ap = player_ap_budget
		if opponent.id.begins_with("crowd_") or round_number % 2 == 0: _spawn_pickup()
		if ap == 0: _finish_player_turn()

func _aling_action() -> void:
	if enemy_ap > 1:
		_move_opponent(ALING_GAP)
	elif distance(foe, hero) == ALING_GAP:
		_schedule_strike(_cross_cells(hero, 1), 2)
		message = "%s以你为中心布下小十字，2 个行动点后触发。" % ("阿铃" if opponent.id == "aling" else opponent.name)
	else:
		_cast_ring(foe, false)

func _chen_action() -> void:
	if second_phase:
		match enemy_ap:
			4: _cast_chen_cross(hero, true)
			3: _cast_ring(foe, true)
			2: _cast_chen_cross(Vector2i(side-1, side-1), false)
			1: _cast_ring(Vector2i.ZERO, true)
	elif enemy_ap > 2:
		_move_opponent(side * 2)
	elif enemy_ap == 2:
		_cast_chen_cross(hero, true)
	else:
		_cast_ring(foe, true)

func _vito_action() -> void:
	if enemy_ap > 2:
		_move_opponent(1 if second_phase else VITO_GAP)
		return
	var attack: int
	if second_phase:
		attack = VitoAttack.TOMATOES if enemy_ap == 2 else _rng.randi_range(VitoAttack.FORKS, VitoAttack.KNIVES)
	else:
		attack = (round_number - 1 + 2 - enemy_ap) % VitoAttack.size()
	if attack == VitoAttack.TOMATOES:
		for offset: Vector2i in [Vector2i(-1,-1), Vector2i(1,-1), Vector2i(-1,1), Vector2i(1,1)]:
			var cell := foe + offset
			if inside(cell): tomatoes.append(Tomato.new(cell))
		message = "维托召唤了番茄。番茄移动三次后爆炸，碰到玩家会提前引爆。"
	else:
		_cast_utensils(attack)

func _cast_utensils(attack: int) -> void:
	for lane: int in range(0, side, 2):
		_schedule_utensil(lane, attack, lane % 4 == 0)
	message = "维托召唤了餐叉。" if attack == VitoAttack.FORKS else "维托召唤了餐刀。"

func _schedule_utensil(lane: int, attack: int, fast: bool, guard: Guard = null) -> void:
	var cells: Array[Vector2i] = []
	for i: int in side:
		cells.append(Vector2i(lane, i) if attack == VitoAttack.FORKS else Vector2i(i, lane))
	var strike := _schedule_strike(cells, 1 if fast else 3, guard)
	strike.anchor = cells[0]
	strike.utensil = attack
	strike.repeats_left = 1 if fast else 0

func _european_crowd_action() -> void:
	match enemy_ap:
		4, 3: _move_opponent(VITO_GAP)
		2: _cast_crowd_utensils()
		1: _cast_crowd_tomatoes()

func _cast_crowd_utensils(guard: Guard = null) -> void:
	for attack: int in [VitoAttack.FORKS, VitoAttack.KNIVES]:
		var middle := hero.x if attack == VitoAttack.FORKS else hero.y
		var lanes: Array[int] = [middle]
		for offset: int in [-2, 2, -1, 1, -3, 3]:
			if lanes.size() == 3: break
			if middle + offset >= 0 and middle + offset < side: lanes.append(middle + offset)
		for lane: int in lanes: _schedule_utensil(lane, attack, lane == middle, guard)
	message = "三把餐叉和三把餐刀交错落下，中央两条会再触发一次。"

func _cast_crowd_tomatoes(guard: Guard = null) -> void:
	var center := foe if guard == null else guard.cell
	var spots: Array[Vector2i] = []
	for direction: Vector2i in DIRECTIONS:
		var spot := center + direction
		if inside(spot): spots.append(spot)
	for motion: TomatoMotion in [TomatoMotion.CHASE, TomatoMotion.RANDOM]:
		var chosen := _rng.randi_range(0, spots.size() - 1)
		var tomato := Tomato.new(spots[chosen], motion)
		tomato.guard = guard
		tomatoes.append(tomato)
		spots.remove_at(chosen)
	message = "一个番茄追踪你，另一个随机走动。两者都在移动三次后爆炸。"

func _advance_tomatoes(moved: bool) -> int:
	var continuing: Array[Tomato] = []
	var damage := 0
	for tomato: Tomato in tomatoes:
		if _tick_tomato_delay(tomato):
			continuing.append(tomato)
			continue
		if tomato.motion == TomatoMotion.LUOE_ORBIT:
			_step_luoe_tomato(tomato)
			tomato.moves_left -= 1
			if tomato.moves_left > 0: continuing.append(tomato)
			else: damage += _impact_damage(luoe_blast_cells(tomato.cell), _enemy_damage(3) + attack_bonus)
			continue
		var touched := tomato.motion == TomatoMotion.VITO and moved and tomato.cell == hero
		if touched: tomato.moves_left -= 1
		if tomato.moves_left > 0:
			var neighbors: Array[Vector2i] = []
			for direction: Vector2i in DIRECTIONS:
				var next := tomato.cell + direction
				if inside(next): neighbors.append(next)
			if tomato.motion == TomatoMotion.CHASE and tomato.cell != hero:
				neighbors = neighbors.filter(func(cell: Vector2i) -> bool: return distance(cell, hero) < distance(tomato.cell, hero))
			tomato.cell = neighbors[_rng.randi_range(0, neighbors.size() - 1)]
			tomato.moves_left -= 2 if tomato.motion == TomatoMotion.VITO and not touched and tomato.cell == hero else 1
		if tomato.moves_left > 0:
			continuing.append(tomato)
		else:
			var bonus := attack_bonus if tomato.guard == null else tomato.guard.attack_bonus
			damage += _impact_damage(square_cells(tomato.cell, 1), _enemy_damage(3, tomato.guard) + bonus)
	tomatoes = continuing
	return damage

func _tick_tomato_delay(tomato: Tomato) -> bool:
	if tomato.delay_steps == 0: return false
	tomato.delay_steps -= 1
	tomato.moves_left -= 1
	return true

func _advance_player_tomatoes() -> void:
	var remaining: Array[Tomato] = []
	for tomato: Tomato in player_tomatoes:
		if foe_hp == 0: break
		if _tick_tomato_delay(tomato):
			remaining.append(tomato)
			continue
		var target := foe
		if luoe_guarded():
			target = guards[0].cell
			for guard: Guard in guards:
				if distance(tomato.cell, guard.cell) < distance(tomato.cell, target): target = guard.cell
		if target not in square_cells(tomato.cell, 1):
			var offset := target - tomato.cell
			var horizontal := absi(offset.x) >= absi(offset.y)
			tomato.cell += Vector2i(signi(offset.x), 0) if horizontal else Vector2i(0, signi(offset.y))
		tomato.moves_left -= 1
		var blast := square_cells(tomato.cell, 1)
		if target not in blast and tomato.moves_left > 0:
			remaining.append(tomato)
			continue
		for cell: Vector2i in blast: player_strike[cell] = true
		var hit := _hit_enemies(blast, damage_for(int(Skills.DEFINITIONS[Skills.TOMATO].damage)))
		if hit.damage > 0: message += " 追踪番茄造成 %d 点伤害。%s" % [hit.damage, "暴击！" if hit.critical else ""]
		if hit.foe: _enter_second_phase()
		_hit_timed_summons(blast)
	player_tomatoes = remaining

func _summon_action() -> void:
	match enemy_ap:
		4, 3: _move_to_alignment()
		2: _cast_timed_summons()
		1: _cast_salad_summons()

func _move_to_alignment(guard: Guard = null) -> void:
	var current := foe if guard == null else guard.cell
	var best := current
	var gap := (current - hero).abs()
	var best_score := mini(gap.x, gap.y)
	for direction: Vector2i in DIRECTIONS:
		var candidate := current + direction
		if not inside(candidate) or candidate == hero or (guard != null and enemy_at(candidate)): continue
		gap = (candidate - hero).abs()
		var score := mini(gap.x, gap.y)
		if score < best_score:
			best = candidate
			best_score = score
	if guard == null: foe = best
	else: guard.cell = best
	message = "%s试图和你站在同一行或列。" % (opponent.name if guard == null else guard.name)

func _formation_center(cell: Vector2i) -> Vector2i:
	# Keep all positions on the board when the center is at a wall.
	return cell.clamp(Vector2i.ONE, Vector2i.ONE * (side - 2))

func timed_summon_name() -> String:
	return "柠檬汁天妇罗" if opponent.id == "hina" else "番茄酱小丸子"

func salad_summon_name() -> String:
	return "沙拉酱天妇罗" if opponent.id == "hina" else "沙拉酱小丸子"

func _cast_timed_summons(guard: Guard = null) -> void:
	var center := _formation_center(hero)
	if opponent.id == "crowd_jp" or guard != null:
		var offset: Vector2i = SUMMON_RING[_rng.randi_range(0, 7)]
		_add_timed_summon(center + offset, offset.x == 0 or offset.y == 0, guard)
	else:
		var corner := _rng.randi_range(0, 3) * 2
		_add_timed_summon(center + SUMMON_RING[corner], true)
		_add_timed_summon(center + SUMMON_RING[(corner + 4) % 8], false)
		if second_phase:
			var extra := (corner + (2 if _rng.randi_range(0, 1) == 0 else 6)) % 8
			_add_timed_summon(center + SUMMON_RING[extra], _rng.randi_range(0, 1) == 0)
	message = "%s已布下预警。攻击两次可消灭并恢复 2 点生命。" % timed_summon_name()

func _add_timed_summon(cell: Vector2i, cross: bool, guard: Guard = null) -> void:
	var ball := TimedSummon.new(cell)
	ball.guard = guard
	timed_summons.append(ball)
	var cells := _cross_cells(cell, side - 1) if cross else square_cells(cell, 1)
	var strike := _schedule_strike(cells, 2 if cross else 1, guard)
	strike.source = ball

func _hit_timed_summons(cells: Array[Vector2i]) -> void:
	var defeated := 0
	for ball: TimedSummon in timed_summons.duplicate():
		if ball.cell not in cells: continue
		ball.hits_left -= 1
		if ball.hits_left == 0:
			timed_summons.erase(ball)
			defeated += 1
	if defeated > 0:
		var healed := mini(max_hp - hp, defeated * 2)
		hp += healed
		message += " 消灭 %d 个%s，恢复 %d 点生命。" % [defeated, timed_summon_name(), healed]

func _tick_timed_summon(ball: TimedSummon) -> void:
	ball.rounds_left -= 1
	if ball.rounds_left > 0: return
	timed_summons.erase(ball)
	if ball.guard != null:
		if ball.guard.hp > 0:
			var recovered := mini(GUARD_HP - ball.guard.hp, 3)
			ball.guard.hp += recovered
			ball.guard.next_attack_bonus += 1
			message += " 小丸子为%s恢复 %d 点生命，并增加下回合攻击。" % [ball.guard.name, recovered]
		return
	if foe_hp == 0: return
	var healed := mini(foe_max_hp - foe_hp, 3)
	foe_hp += healed
	_next_attack_bonus += 1
	message += " %s为%s恢复 %d 点生命，并增加下回合攻击。" % [timed_summon_name(), opponent.name, healed]
	_enter_second_phase()

func _cast_salad_summons(guard: Guard = null) -> void:
	var orbits: bool = opponent.id == "hina"
	var slots: Array[int] = [0, 2, 4, 6]
	if not orbits or second_phase:
		var start := _rng.randi_range(0, 1) * 2
		slots.assign([start, start + 4])
	var center := _formation_center(foe if guard == null else guard.cell)
	for slot: int in slots:
		var ball := SaladSummon.new(center + SUMMON_RING[slot], slot, orbits)
		ball.guard = guard
		salad_summons.append(ball)
	message = ("沙拉酱天妇罗会随你的行动顺时针移动。日奈能挡住直线攻击，本回合结束后天妇罗消失。"
		if orbits else "沙拉酱小丸子会在你消耗行动点后判定同一行或列。")

func _advance_salad_summons() -> int:
	var damage := 0
	var center := _formation_center(foe)
	for ball: SaladSummon in salad_summons.duplicate():
		var summon_power := _enemy_damage(3) if rematch else 3
		var power := summon_power + attack_bonus if ball.guard == null else _enemy_damage(5, ball.guard) + ball.guard.attack_bonus
		if ball.orbits:
			ball.ring_index = (ball.ring_index + 1) % SUMMON_RING.size()
			ball.cell = center + SUMMON_RING[ball.ring_index]
		else:
			ball.moves_left -= 1
		var hit := _salad_has_clear_shot(ball)
		if hit:
			impacts[hero] = true
			damage += power
		var expired := ap == 0 if ball.orbits else ball.moves_left == 0
		if hit or expired: salad_summons.erase(ball)
	return damage

func _salad_has_clear_shot(ball: SaladSummon) -> bool:
	var row := hero.y == ball.cell.y
	var column := hero.x == ball.cell.x
	if not ball.orbits: return row or column
	if row and foe.y == hero.y and (foe.x - hero.x) * (foe.x - ball.cell.x) < 0:
		return false
	if column and foe.x == hero.x and (foe.y - hero.y) * (foe.y - ball.cell.y) < 0:
		return false
	return row or column

func _prepare_luoe_turn() -> void:
	_luoe_actions.clear()
	match _luoe_round:
		LuoeRound.OPENING:
			for cast: int in 3: _luoe_actions.append(_random_luoe_lane())
			_luoe_round = LuoeRound.PRESSURE
		LuoeRound.PRESSURE:
			_luoe_actions.assign([_random_luoe_lane(), LuoeAction.CROSSES, LuoeAction.FRAMES])
			_luoe_round = LuoeRound.SUMMONING
		LuoeRound.SUMMONING:
			_luoe_actions.assign([LuoeAction.REDUCE_AP, LuoeAction.SUMMON])
			if second_phase: _luoe_actions.append(LUOE_EXTRA_ATTACKS[_rng.randi_range(0, LUOE_EXTRA_ATTACKS.size() - 1)])
			_luoe_round = LuoeRound.GUARD_ENCOUNTER
		LuoeRound.GUARD_ENCOUNTER:
			if not guards.is_empty():
				for point: int in GUARD_AP: _luoe_actions.append(LuoeAction.GUARDS)
				if second_phase: _luoe_actions.append(LUOE_EXTRA_ATTACKS[_rng.randi_range(0, LUOE_EXTRA_ATTACKS.size() - 1)])
				enemy_ap = _luoe_actions.size()
				return
			_luoe_actions.assign([LuoeAction.PARALLEL, LuoeAction.TOMATOES])
			_luoe_round = LuoeRound.OPENING
	if not second_phase:
		for point: int in foe_max_ap - _luoe_actions.size(): _luoe_actions.push_front(LuoeAction.MOVE)
	enemy_ap = _luoe_actions.size()

func _random_luoe_lane() -> LuoeAction:
	return LuoeAction.PERPENDICULAR if _rng.randi_range(0, 1) == 0 else LuoeAction.PARALLEL

func _luoe_action() -> void:
	var action: LuoeAction = _luoe_actions.pop_front()
	match action:
		LuoeAction.MOVE: _move_luoe()
		LuoeAction.PERPENDICULAR, LuoeAction.PARALLEL:
			_schedule_strike(_luoe_lane_pair(hero, false), 1)
			_luoe_followups.append(action == LuoeAction.PERPENDICULAR)
			message = "罗厄封锁两行。你下一次移动后，她会追放%s预警。" % ("双列" if action == LuoeAction.PERPENDICULAR else "双行")
		LuoeAction.CROSSES:
			var cells := _cross_cells(hero, side - 1)
			for cell: Vector2i in _cross_cells(foe, side - 1):
				if cell not in cells: cells.append(cell)
			_schedule_strike(cells, 1)
			message = "罗厄以双方为中心布下贯穿棋盘的十字。"
		LuoeAction.FRAMES:
			var cells: Array[Vector2i] = []
			for radius: int in [1, 3, 5]: cells.append_array(_ring_cells(foe, radius))
			_schedule_strike(cells, 1)
			message = "罗厄以自己为中心布下三层空心方框。"
		LuoeAction.SUMMON: _summon_luoe_guards()
		LuoeAction.TOMATOES: _cast_luoe_tomatoes()
		LuoeAction.REDUCE_AP:
			_player_ap_penalty = 2
			message = "罗厄压制你的行动，下回合行动点减少 2。"
		LuoeAction.GUARDS:
			for guard: Guard in guards: _luoe_guard_action(guard, LuoeAction.GUARDS in _luoe_actions)

func _move_luoe() -> void:
	var room := Rect2i(Vector2i.ONE * (side / 2 - 2), Vector2i(5, 5))
	var best := foe
	var best_score := -side * 4
	for direction: Vector2i in DIRECTIONS:
		var candidate := foe + direction
		if candidate == hero or not room.has_point(candidate): continue
		var aligned := int(candidate.x == hero.x) + int(candidate.y == hero.y)
		var score := distance(candidate, hero) - aligned * side * 2
		if score > best_score:
			best = candidate
			best_score = score
	foe = best
	message = "罗厄在中央区域调整站位，避开你的行列。"

func _luoe_lane_pair(at: Vector2i, vertical: bool) -> Array[Vector2i]:
	var near := at.x if vertical else at.y
	# A separation of two leaves an adjacent escape tile, even when several casts overlap.
	var far := near + (2 if _rng.randi_range(0, 1) == 0 else -2)
	if far < 0 or far >= side: far = near * 2 - far
	var cells: Array[Vector2i] = []
	for i: int in side:
		cells.append(Vector2i(near, i) if vertical else Vector2i(i, near))
		cells.append(Vector2i(far, i) if vertical else Vector2i(i, far))
	return cells

func _advance_luoe_followups() -> void:
	if _luoe_followups.is_empty(): return
	for vertical: bool in _luoe_followups:
		_schedule_strike(_luoe_lane_pair(hero, vertical), 1)
	_luoe_followups.clear()
	message += " 罗厄追放行列预警。"

func _summon_luoe_guards() -> void:
	guards.append(Guard.new("crowd_cn", "中式杂兵", foe + Vector2i.LEFT * 2))
	guards.append(Guard.new("crowd_eu", "欧式杂兵", foe + Vector2i.RIGHT * 2))
	guards.append(Guard.new("crowd_jp", "日式杂兵", foe + Vector2i.DOWN * 2))
	_displace_hero_on_enemy()
	message = "罗厄召来三名援兵。"
	if luoe_guarded(): message += " 援兵在场期间，罗厄免疫伤害。"
	if _player_ap_penalty > 0: message += " 下回合行动点减少 2。"

func _displace_hero_on_enemy() -> void:
	if not enemy_at(hero): return
	for direction: Vector2i in DIRECTIONS:
		var next := hero + direction
		if inside(next) and not enemy_at(next):
			hero = next
			return

func _luoe_guard_action(guard: Guard, moving: bool) -> void:
	if moving:
		if guard.id == "crowd_jp": _move_to_alignment(guard)
		else: _move_opponent(ALING_GAP if guard.id == "crowd_cn" else VITO_GAP, guard)
		return
	var first := _rng.randi_range(0, 1) == 0
	match guard.id:
		"crowd_cn":
			if first: _schedule_strike(_cross_cells(hero, 1), 2, guard)
			else: _cast_ring(guard.cell, false, guard)
		"crowd_eu":
			if first: _cast_crowd_utensils(guard)
			else: _cast_crowd_tomatoes(guard)
		"crowd_jp":
			if first: _cast_timed_summons(guard)
			else: _cast_salad_summons(guard)
	message = "援兵各自布下了一种攻击。" if guards.size() > 1 else "%s布下攻击。" % guard.name

func _cast_luoe_tomatoes() -> void:
	for radius: int in range(1, side):
		for diagonal: Vector2i in [Vector2i(-1,-1), Vector2i(1,-1), Vector2i(1,1), Vector2i(-1,1)]:
			var corner := foe + diagonal * radius
			if not inside(corner): continue
			var tomato := Tomato.new(corner, TomatoMotion.LUOE_ORBIT)
			tomato.orbit_center = foe
			tomatoes.append(tomato)
	message = "罗厄放出沿方框顺时针移动的番茄炸弹，3 个行动点后引爆。"

func _step_luoe_tomato(tomato: Tomato) -> void:
	var offset := tomato.cell - tomato.orbit_center
	var radius := maxi(absi(offset.x), absi(offset.y))
	var direction := Vector2i.UP
	if offset.y == -radius and offset.x < radius: direction = Vector2i.RIGHT
	elif offset.x == radius and offset.y < radius: direction = Vector2i.DOWN
	elif offset.y == radius and offset.x > -radius: direction = Vector2i.LEFT
	if inside(tomato.cell + direction): tomato.cell += direction

func luoe_blast_cells(anchor: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for offset: Vector2i in [Vector2i.ZERO, Vector2i.RIGHT, Vector2i.UP, Vector2i(1,-1)]:
		if inside(anchor + offset): cells.append(anchor + offset)
	return cells

func _move_opponent(target_gap: int, guard: Guard = null) -> void:
	var movement_area := Rect2i(0, 0, side, side)
	if opponent.id == "chen":
		var start := (side - CHEN_MOVEMENT_SIDE) / 2
		movement_area = Rect2i(start, start, CHEN_MOVEMENT_SIDE, CHEN_MOVEMENT_SIDE)
	var current := foe if guard == null else guard.cell
	var best := current
	var best_score := absi(distance(current, hero) - target_gap)
	for i: int in DIRECTIONS.size():
		var candidate: Vector2i = current + DIRECTIONS[(i + round_number) % DIRECTIONS.size()]
		if candidate == hero or not movement_area.has_point(candidate) or (guard != null and enemy_at(candidate)): continue
		var score := absi(distance(candidate, hero) - target_gap)
		if score < best_score:
			best = candidate
			best_score = score
	var name: String = opponent.name if guard == null else guard.name
	message = "%s保持站位。" % name if best == current else "%s移动了一格。" % name
	if guard == null: foe = best
	else: guard.cell = best

func _schedule_strike(cells: Array[Vector2i], delay: int, guard: Guard = null) -> Strike:
	var strike := Strike.new(cells, delay)
	strike.guard = guard
	strike.damage = _enemy_damage(delay, guard)
	_strikes.append(strike)
	return strike

func _refresh_warnings() -> void:
	warnings.clear()
	utensils.clear()
	for strike: Strike in _strikes:
		if strike.utensil >= 0: utensils.append(strike)
		for cell: Vector2i in strike.cells:
			if not warnings.has(cell): warnings[cell] = []
			warnings[cell].append(strike.points_left)

func _cast_chen_cross(anchor: Vector2i, tracks_player: bool) -> void:
	_schedule_strike(_cross_cells(anchor, side - 1), 2)
	_cross_repeats.append(CrossRepeat.new(anchor, tracks_player))
	message = "罗金娜布下贯穿棋盘的十字，你移动两次后会再出现一次。"

func _advance_cross_repeats() -> void:
	var remaining: Array[CrossRepeat] = []
	var repeated := false
	for echo: CrossRepeat in _cross_repeats:
		echo.moves_left -= 1
		if echo.moves_left > 0:
			remaining.append(echo)
			continue
		_schedule_strike(_cross_cells(hero if echo.tracks_player else echo.anchor, side - 1), 2)
		repeated = true
	_cross_repeats = remaining
	if repeated: message += " 十字预警再次出现。"

func _cast_ring(anchor: Vector2i, unlimited: bool, guard: Guard = null) -> void:
	var strike := _schedule_strike(_ring_cells(anchor, 1), 2, guard)
	strike.anchor = anchor
	strike.radius = 1
	strike.max_radius = side - 1 if unlimited else 4
	strike.expanding_slowly = unlimited
	message = "%s布下向外扩散的方框，首圈 2 个行动点后触发。" % opponent.name

func _cross_cells(anchor: Vector2i, reach: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = [anchor]
	for direction: Vector2i in DIRECTIONS:
		for step: int in range(1, reach + 1):
			var cell := anchor + direction * step
			if not inside(cell): break
			cells.append(cell)
	return cells

func _ring_cells(anchor: Vector2i, radius: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y: int in range(maxi(0, anchor.y-radius), mini(side, anchor.y+radius+1)):
		for x: int in range(maxi(0, anchor.x-radius), mini(side, anchor.x+radius+1)):
			var cell := Vector2i(x, y)
			var delta := (cell - anchor).abs()
			if maxi(delta.x, delta.y) == radius: cells.append(cell)
	return cells

func _spawn_pickup() -> void:
	if not pickups.is_empty(): return
	var fallback: Array[Vector2i] = []
	var preferred: Array[Vector2i] = []
	for cell: Vector2i in square_cells(hero, 2):
		if distance(cell, hero) != 2 or enemy_at(cell): continue
		if timed_summons.any(func(ball: TimedSummon) -> bool: return ball.cell == cell): continue
		if salad_summons.any(func(ball: SaladSummon) -> bool: return ball.cell == cell): continue
		if (tomatoes + player_tomatoes).any(func(tomato: Tomato) -> bool: return tomato.cell == cell): continue
		fallback.append(cell)
		if distance(cell, foe) == 2: preferred.append(cell)
	var valid := fallback if preferred.is_empty() else preferred
	if not valid.is_empty(): pickups.append(valid[_rng.randi_range(0, valid.size() - 1)])
