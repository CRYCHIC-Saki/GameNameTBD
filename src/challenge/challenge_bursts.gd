extends Control
## Draws short pixel bursts independently of the board's cached grid and portraits.

const FRAME_COUNT := 10
const FRAME_EDGE := 32
const DURATION := .34
const FIRE := Color("#ffab62")
const PLAYER := Color("#8ee8e1")
static var _frames: Array[ImageTexture] = []

var board: Control
var _time := 0.0
var _enemy: Dictionary = {}
var _player: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_process(false)

func play(enemy_cells: Dictionary, player_cells: Dictionary) -> void:
	if enemy_cells.is_empty() and player_cells.is_empty(): return
	if _frames.is_empty(): _make_frames()
	for cell: Vector2i in enemy_cells: _enemy[cell] = _time
	for cell: Vector2i in player_cells: _player[cell] = _time
	set_process(true)
	queue_redraw()

func _process(delta: float) -> void:
	_time += delta
	for cells: Dictionary in [_enemy, _player]:
		for cell: Vector2i in cells.keys():
			if _time - float(cells[cell]) >= DURATION: cells.erase(cell)
	set_process(not _enemy.is_empty() or not _player.is_empty())
	queue_redraw()

func _draw() -> void:
	if _enemy.is_empty() and _player.is_empty(): return
	var pitch: float = board.cell_length()
	_draw_cells(_player, PLAYER, pitch)
	_draw_cells(_enemy, FIRE, pitch)

func _draw_cells(cells: Dictionary, tint: Color, pitch: float) -> void:
	for cell: Vector2i in cells:
		var progress := (_time - float(cells[cell])) / DURATION
		var frame := clampi(int(progress * FRAME_COUNT), 0, FRAME_COUNT - 1)
		var span := Vector2.ONE * pitch * (1.42 if tint == FIRE else 1.17)
		var center: Vector2 = board.cell_center(cell)
		draw_texture_rect(_frames[frame], Rect2((center - span * .5).floor(), span.round()), false, tint)

static func _make_frames() -> void:
	# Build the pixel sprites once. Each occupied cell needs one textured quad per frame.
	for frame: int in FRAME_COUNT:
		var progress := float(frame) / FRAME_COUNT
		var spread := 5.0 + 8.0 * sin(progress * PI * .5)
		var image := Image.create_empty(FRAME_EDGE, FRAME_EDGE, false, Image.FORMAT_RGBA8)
		for y: int in FRAME_EDGE:
			for x: int in FRAME_EDGE:
				var offset := Vector2(x - 15.5, y - 15.5)
				var angle := offset.angle()
				var radius := offset.length()
				var edge := spread * (.77 + .14 * sin(angle * 7.0 + frame * .22) + .09 * cos(angle * 13.0))
				var thickness := lerpf(8.0, 1.8, progress)
				var intensity := 1.0 - absf(radius - edge + thickness * .42) / thickness
				if progress < .4 and radius < spread * .5:
					intensity = maxf(intensity, 1.4 - progress * 1.8 - radius / spread)
				if radius >= edge and radius - edge <= 5.0 and sin(angle * 9.0 + .4) > .87:
					intensity = maxf(intensity, .63)
				if intensity <= .1: continue
				var shade := 1.0 if intensity > .73 else (.82 if intensity > .42 else .61)
				var opacity := (1.0 - smoothstep(.27, 1.0, progress)) * minf(1, intensity * 1.55)
				image.set_pixel(x, y, Color(shade, shade, shade, opacity))
		_frames.append(ImageTexture.create_from_image(image))
