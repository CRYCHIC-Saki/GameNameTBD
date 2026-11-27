class_name TDChallengeBoard
extends Control

signal cell_pressed(cell: Vector2i)
signal cell_hovered(cell: Vector2i)

const Bursts := preload("res://src/challenge/challenge_bursts.gd")
const Icons := preload("res://src/challenge/challenge_icons.gd")
const TILE_A := Color("#68452f")
const TILE_B := Color("#f0d596")
const GOLD := Color("#e2ba72")
const MINT := Color("#9df5ce")
const CHALK := Color("#fff0d2")
const TOMATO_EDGE := Color("#ffb75b")
const PORTRAIT_BACKGROUNDS := {
	"hero": Color("#ffbb48"),
	"aling": Color("#4546a3"),
	"chen": Color("#e14d4d"),
	"vito": Color("#41c6a5"),
	"hina": Color("#f5e9d4"),
	"luoe": Color("#9b5ec3"),
}
const GUARD_TINTS := {"crowd_cn": Color("#f8a46d"), "crowd_eu": Color("#8eb5f7"), "crowd_jp": Color("#d7aff2")}
var battle: TDChallengeBattle
var hovered := Vector2i(-1, -1)
var preview_action := TDChallengeBattle.Action.NONE
var effects: Bursts

func _ready() -> void:
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	if battle != null and battle.opponent.id == "luoe":
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_exited.connect(_set_hover.bind(Vector2i(-1, -1)))
	effects = Bursts.new()
	effects.board = self
	add_child(effects)
	resized.connect(effects.queue_redraw)

func cell_length() -> float:
	return maxf(1.0, minf(size.x, size.y) / battle.side)

func board_origin() -> Vector2:
	return Vector2.ZERO

func cell_center(cell: Vector2i) -> Vector2:
	return board_origin() + (Vector2(cell) + Vector2.ONE * 0.5) * cell_length()

func animate_strikes(enemy_cells: Dictionary, player_cells: Dictionary) -> void:
	effects.play(enemy_cells, player_cells)

func _gui_input(event: InputEvent) -> void:
	if battle == null: return
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		var cell := Vector2i(((event.position - board_origin()) / cell_length()).floor())
		_set_hover(cell if battle.inside(cell) else Vector2i(-1, -1))
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if battle.inside(cell): cell_pressed.emit(cell)
			accept_event()

func _set_hover(cell: Vector2i) -> void:
	if cell != hovered:
		hovered = cell
		cell_hovered.emit(cell)
		queue_redraw()

func _draw() -> void:
	if battle == null or size.x < 1: return
	var pitch := cell_length()
	var start := board_origin()
	var area := Rect2(start, Vector2.ONE * pitch * battle.side)
	draw_texture_rect(TDUI.WOOD, area, false)
	var rival_id := str(battle.opponent.id)
	var hero_face := Icons.headshot("hero")
	var rival_face := Icons.guarded_luoe_headshot() if battle.luoe_guarded() else Icons.headshot(rival_id)
	var rival_background: Color = PORTRAIT_BACKGROUNDS.get(rival_id, Color("#f1a498"))
	var preview: Dictionary = {}
	for cell: Vector2i in battle.attack_cells(preview_action, battle.direction_toward(hovered)):
		preview[cell] = true
	var tempura_cells: Dictionary = {}
	if battle.opponent.id == "hina":
		for summon: TDChallengeBattle.TimedSummon in battle.timed_summons: tempura_cells[summon.cell] = true
		for summon: TDChallengeBattle.SaladSummon in battle.salad_summons: tempura_cells[summon.cell] = true
	var tomato_stacks: Dictionary = {}
	var orbiting_stacks: Dictionary = {}
	var friendly_stacks: Dictionary = {}
	for tomato: TDChallengeBattle.Tomato in battle.tomatoes:
		var stacks := orbiting_stacks if tomato.motion == TDChallengeBattle.TomatoMotion.LUOE_ORBIT else tomato_stacks
		if not stacks.has(tomato.cell): stacks[tomato.cell] = []
		stacks[tomato.cell].append(tomato.moves_left)
	for tomato: TDChallengeBattle.Tomato in battle.player_tomatoes:
		if not friendly_stacks.has(tomato.cell): friendly_stacks[tomato.cell] = []
		friendly_stacks[tomato.cell].append(tomato.moves_left)
	for y: int in battle.side:
		for x: int in battle.side:
			var cell := Vector2i(x, y)
			var begin := (start + Vector2(cell) * pitch).floor()
			var end := (start + Vector2(cell + Vector2i.ONE) * pitch).floor()
			var rect := Rect2(begin, end - begin - Vector2.ONE)
			var fill := TILE_A if (x + y) % 2 == 0 else TILE_B
			fill.a = .88
			var timers: Array = battle.warnings.get(cell, [])
			var timer := 0 if timers.is_empty() else int(timers.min())
			if timer > 0:
				fill = Color("#ac3936") if timer == 1 else (Color("#99572f") if timer == 2 else Color("#74613b"))
			draw_rect(rect, fill)
			if cell in preview:
				draw_rect(rect.grow(-2), Color("#30564c"), false, 3)
				draw_rect(rect.grow(-3), Color("#c4ffe0"), false, 1)
			if cell in battle.pickups:
				Icons.EnergyIcon.draw_crystal(self, rect.get_center(), pitch * .32)
			var guard := battle.guard_at(cell)
			var occupied := cell == battle.hero or cell == battle.foe or guard != null
			if occupied:
				var player := cell == battle.hero
				var center := rect.get_center()
				draw_circle(center, pitch*.46, Color("#102829"))
				var tint: Color = GUARD_TINTS[guard.id] if guard != null else (PORTRAIT_BACKGROUNDS["hero"] if player else rival_background)
				draw_circle(center, pitch*.40, tint)
				var face := Icons.headshot(guard.id) if guard != null else (hero_face if player else rival_face)
				if face != null:
					draw_texture_rect(face, rect.grow(-pitch*.08), false)
				else:
					_letter("敌", rect, Color("#1a3432"), maxi(10, floori(pitch*.62)))
				if guard != null:
					var life := Rect2(rect.position + Vector2(2, 2), Vector2(pitch * .49, pitch * .31))
					draw_rect(life, Color("#1a3432"))
					_letter(str(guard.hp), life, tint, maxi(10, floori(pitch * .28)))
			if timer > 0:
				if occupied or cell in battle.pickups or cell in tempura_cells or cell in orbiting_stacks or _has_utensil(cell):
					var badge_size := maxf(11, pitch*.48)
					var badge := Rect2(rect.end - Vector2.ONE*badge_size, Vector2.ONE*badge_size)
					draw_rect(badge, Color("#642825"))
					_letter(str(timer), badge, Color.WHITE, floori(badge_size))
				else:
					_letter(str(timer), rect, CHALK, maxi(11, floori(pitch*.65)))
				if timers.size() > 1:
					draw_rect(Rect2(rect.position+Vector2(2,2),Vector2(4,4)), CHALK)
			if cell == hovered: draw_rect(rect, Color.WHITE, false, 2)
	for strike: TDChallengeBattle.Strike in battle.utensils:
		_draw_utensil(strike, pitch)
	for cell: Vector2i in tomato_stacks:
		_draw_tomato(cell, tomato_stacks[cell], area, pitch)
	for cell: Vector2i in orbiting_stacks:
		_draw_tomato(cell, orbiting_stacks[cell], area, pitch, true)
	for cell: Vector2i in friendly_stacks:
		_draw_tomato(cell, friendly_stacks[cell], area, pitch, false, true)
	for ball: TDChallengeBattle.TimedSummon in battle.timed_summons:
		_draw_summon(ball.cell, ball.rounds_left, ball.hits_left, false, pitch)
	for ball: TDChallengeBattle.SaladSummon in battle.salad_summons:
		_draw_summon(ball.cell, 0 if ball.orbits else ball.moves_left, 0, true, pitch)
	draw_rect(area.grow(-1), GOLD.darkened(.48), false, 2)

func _has_utensil(cell: Vector2i) -> bool:
	if battle.utensils.is_empty() or (cell.x != 0 and cell.y != 0): return false
	for strike: TDChallengeBattle.Strike in battle.utensils:
		if strike.anchor == cell: return true
	return false

func _draw_utensil(strike: TDChallengeBattle.Strike, pitch: float) -> void:
	var fork := strike.utensil == TDChallengeBattle.VitoAttack.FORKS
	var center := cell_center(strike.anchor) - Vector2.ONE * pitch * .12
	# Both can occupy the top-left tile. Give each its own part of that tile.
	if not fork and strike.anchor == Vector2i.ZERO: center.y -= pitch * .24
	var metal := Color("#fbebcf")
	draw_set_transform(center, 0 if fork else -PI * .5, Vector2.ONE * pitch * .028)
	draw_line(Vector2(0,-7), Vector2(0,7), Color("#763723"), 4, true)
	draw_line(Vector2(0,-7), Vector2(0,5), metal, 2.6, true)
	if fork:
		for tooth: int in [-3, 0, 3]:
			draw_line(Vector2(tooth,0), Vector2(tooth,7), metal, 1.9, true)
		draw_line(Vector2(-3,1), Vector2(3,1), metal, 2, true)
	else:
		draw_colored_polygon(PackedVector2Array([Vector2(-2,0), Vector2(3,0), Vector2(3,5), Vector2(-2,8)]), metal)
	draw_set_transform_matrix(Transform2D.IDENTITY)

func _draw_tomato(cell: Vector2i, timers: Array, board_rect: Rect2, pitch: float, orbiting: bool = false, friendly: bool = false) -> void:
	var center := cell_center(cell)
	var blast := Rect2(center - Vector2(.5, 1.5) * pitch, Vector2.ONE * pitch * 2.0) if orbiting else \
		Rect2(center - Vector2.ONE * pitch * 1.5, Vector2.ONE * pitch * 3.0)
	var range_rect := blast.intersection(board_rect)
	var inset := range_rect.grow(-3)
	draw_rect(inset, Color(.46,.95,.70,.10) if friendly else Color(.97,.52,.22,.10))
	draw_rect(inset, Color("#5e3025"), false, 4)
	draw_rect(inset, MINT if friendly else TOMATO_EDGE, false, 2)
	var fruit := center + Vector2.ONE * pitch * (.20 if friendly else -.20)
	var radius := pitch * .21
	draw_circle(fruit, radius + 2, Color("#5b2d24"), true, -1, true)
	draw_circle(fruit, radius, Color("#d95736"), true, -1, true)
	draw_circle(fruit - Vector2(radius*.34, radius*.38), radius*.24, Color("#ffb38d"), true, -1, true)
	draw_polyline(PackedVector2Array([fruit+Vector2(-radius*.65,-radius*.9), fruit+Vector2(0,-radius*.55),
		fruit+Vector2(0,-radius*1.12), fruit+Vector2(0,-radius*.55), fruit+Vector2(radius*.65,-radius*.9)]), Color("#b1cf78"), 2, true)
	var badge := Rect2(fruit+Vector2(pitch*.08,-pitch*.10), Vector2.ONE * pitch*.36)
	draw_rect(badge, Color("#244b43") if friendly else Color("#642825"))
	_letter(str(timers.min()), badge, CHALK, maxi(10, roundi(pitch*.30)))
	if timers.size() > 1: draw_rect(Rect2(badge.position + Vector2(2,2), Vector2(3,3)), CHALK)

func _draw_summon(cell: Vector2i, timer: int, hits: int, salad: bool, pitch: float) -> void:
	var advance := pitch * (.17 if salad else -.16)
	var center := cell_center(cell) + Vector2(advance, -pitch * .13)
	if battle.opponent.id == "hina":
		_draw_tempura(center, timer, hits, salad, pitch)
		return
	var radius := pitch * .21
	var sauce := Color("#759d64") if salad else Color("#c64d36")
	draw_circle(center, radius + 2, Color("#513622"))
	draw_circle(center, radius, Color("#e7ad59"))
	draw_rect(Rect2(center - Vector2(radius * .68, radius * .55), Vector2(radius * 1.36, radius * .48)), sauce)
	for i: int in hits:
		draw_rect(Rect2(center + Vector2(radius * (-.54 + i * .64), radius * .35), Vector2.ONE * radius * .34), CHALK)
	var badge := Rect2(center + Vector2(radius * .36, -radius * .52), Vector2.ONE * pitch * .37)
	draw_rect(badge, sauce.darkened(.45))
	_letter(str(timer), badge, Color.WHITE, maxi(10, roundi(pitch*.30)))

func _draw_tempura(center: Vector2, rounds: int, hits: int, salad: bool, pitch: float) -> void:
	var outline := Color("#615952") if salad else Color("#704616")
	var batter := Color("#eee9dd") if salad else Color("#f6ca58")
	var shade := Color("#b3aba0") if salad else Color("#c38730")
	var crust := Color("#fffdf7") if salad else Color("#fff0a0")
	draw_set_transform(center, 0.0, Vector2.ONE * pitch * .032)
	draw_colored_polygon(PackedVector2Array([Vector2(-8, 2), Vector2(-6, -1), Vector2(-3, -2),
		Vector2(-1, -5), Vector2(3, -6), Vector2(6, -9), Vector2(9, -9), Vector2(8, -6),
		Vector2(10, -5), Vector2(6, -2), Vector2(4, 1), Vector2(1, 3), Vector2(-3, 7),
		Vector2(-7, 7), Vector2(-9, 5)]), outline)
	draw_colored_polygon(PackedVector2Array([Vector2(-7, 2), Vector2(-5, 0), Vector2(-2, -1),
		Vector2(0, -4), Vector2(4, -5), Vector2(6, -8), Vector2(8, -8), Vector2(6, -5),
		Vector2(8, -5), Vector2(5, -3), Vector2(3, 0), Vector2(0, 2), Vector2(-3, 6),
		Vector2(-6, 6), Vector2(-8, 4)]), batter)
	draw_polyline(PackedVector2Array([Vector2(-6, 4), Vector2(-4, 5), Vector2(0, 1), Vector2(3, -1)]), shade, 1.6)
	for fleck: Vector2 in [Vector2(-5, 1), Vector2(-2, 0), Vector2(0, -3), Vector2(3, -4)]:
		draw_rect(Rect2(fleck, Vector2(1.8, 1.4)), crust)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	for i: int in hits:
		draw_rect(Rect2(center + Vector2(-.14 + i * .11, .24) * pitch, Vector2.ONE * pitch * .08), crust)
	if rounds > 0:
		var badge := Rect2(center + Vector2(.14, -.16) * pitch, Vector2.ONE * pitch * .35)
		draw_rect(badge, outline)
		_letter(str(rounds), badge, Color.WHITE, maxi(10, roundi(pitch*.30)))

func _letter(value: String, rect: Rect2, ink: Color, font_size: int) -> void:
	var font := TDUI.font()
	var baseline := (rect.size.y - font.get_height(font_size))*.5 + font.get_ascent(font_size)
	draw_string(font, rect.position+Vector2(0,roundf(baseline)), value, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, font_size, ink)
