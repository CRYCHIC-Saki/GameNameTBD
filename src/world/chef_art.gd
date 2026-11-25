class_name TDChefArt
extends RefCounted
## Read-only atlas views; approved PNGs are never rewritten or resized on disk.
const IDLE_ATLAS: Texture2D = preload("res://assets/characters/protagonist/protagonist-idle-four-directions-v1.png")
const WALK_PATH := "res://assets/characters/protagonist/protagonist-walk-four-directions-v1.png"
const DIAGONAL_FRONT_PATH := "res://assets/characters/protagonist/protagonist-diagonal-front-v2.png"
const DIAGONAL_BACK_PATH := "res://assets/characters/protagonist/protagonist-diagonal-back-v2.png"
const IDLE_REGIONS: Array[Rect2] = [
	Rect2(214,30,312,595), Rect2(728,30,307,595),
	Rect2(255,649,254,576), Rect2(746,649,259,576),
]
# Measured opaque bounds: direction DOWN/UP/LEFT/RIGHT, then opposite stride.
# The original idle pose supplies the two passing beats of each four-beat cycle.
const WALK_REGIONS: Array[Rect2] = [
	Rect2(104,20,236,466), Rect2(104,515,236,468),
	Rect2(460,20,232,464), Rect2(460,515,232,467),
	Rect2(842,22,229,462), Rect2(840,517,232,462),
	Rect2(1219,22,222,463), Rect2(1217,517,229,464),
]
static var _textures: Dictionary = {}
static var _walk_atlas: Texture2D
static var _diagonal_front: Texture2D
static var _diagonal_back: Texture2D
# Each strip: idle, contact A, passing A, contact B, passing B.
# Pair directions at draw time so left/right cannot acquire different foot cycles.
# Constant height within each strip avoids rescaling the head on a bent-knee pose.
const DIAGONAL_FRONT_REGIONS: Array[Rect2] = [
	Rect2(78,55,311,584), Rect2(510,55,312,584), Rect2(942,54,312,584),
	Rect2(1362,57,312,584), Rect2(1783,57,312,584),
]
const DIAGONAL_BACK_REGIONS: Array[Rect2] = [
	Rect2(86,35,290,604), Rect2(514,38,293,604), Rect2(949,38,288,604),
	Rect2(1379,38,289,604), Rect2(1810,38,289,604),
]

static func render_size(facing: Vector2i, frame: int, height: float) -> Vector2:
	var art := texture(facing, frame)
	var idle := texture(facing)
	# The separately authored sheets use different body proportions. Match the
	# standing silhouette to the cardinal reference and preserve each stride's spread.
	var silhouette := 0.52 if facing.y != 0 else 0.45
	if facing.y < 0: silhouette = 0.51
	var stride_width := float(art.get_width()) / art.get_height()
	var idle_width := float(idle.get_width()) / idle.get_height()
	return Vector2(height * silhouette * stride_width / idle_width, height)

static func mirrored(facing: Vector2i) -> bool:
	return facing.x != 0 and facing.y != 0 and ((facing.y > 0 and facing.x < 0) or (facing.y < 0 and facing.x > 0))

static func facing_rect(rect: Rect2, facing: Vector2i) -> Rect2:
	# CanvasItem negative texture width flips UVs without shifting the destination.
	if mirrored(facing): rect.size.x = -rect.size.x
	return rect

static func direction_index(facing: Vector2i) -> int:
	match facing:
		Vector2i.UP: return 1
		Vector2i.LEFT: return 2
		Vector2i.RIGHT: return 3
	return 0

static func texture(facing: Vector2i, walk_frame: int = -1) -> Texture2D:
	var frame := clampi(walk_frame, -1, 3)
	# Keep direction_index four-way: NPC sheets share that public helper.
	var diagonal := facing.x != 0 and facing.y != 0
	if not diagonal and frame in [1, 3]: frame = -1
	var direction := direction_index(facing)
	if diagonal:
		direction = (0 if facing.x > 0 else 1) if facing.y > 0 else (2 if facing.x < 0 else 3)
	var key := Vector2i(direction + (4 if diagonal else 0), frame)
	if _textures.has(key): return _textures[key]
	var result := AtlasTexture.new()
	if diagonal:
		if facing.y > 0:
			if _diagonal_front == null: _diagonal_front = load(DIAGONAL_FRONT_PATH)
			result.atlas = _diagonal_front
			result.region = DIAGONAL_FRONT_REGIONS[frame + 1]
		else:
			if _diagonal_back == null: _diagonal_back = load(DIAGONAL_BACK_PATH)
			result.atlas = _diagonal_back
			result.region = DIAGONAL_BACK_REGIONS[frame + 1]
	elif frame < 0:
		result.atlas = IDLE_ATLAS
		result.region = IDLE_REGIONS[direction]
	else:
		if _walk_atlas == null: _walk_atlas = load(WALK_PATH)
		result.atlas = _walk_atlas
		result.region = WALK_REGIONS[direction * 2 + (frame >> 1)]
	result.filter_clip = true
	_textures[key] = result
	return result
