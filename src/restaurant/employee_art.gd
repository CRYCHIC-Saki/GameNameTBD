class_name TDEmployeeArt
extends RefCounted

const PORTRAITS := preload("res://assets/characters/staff/regional-portraits.png")
const WALK := preload("res://assets/characters/staff/regional-walk.png")
const REGIONS := {"cn": 0, "jp": 1, "eu": 2}
const ROLES := {"cook": 0, "waiter": 1, "manager": 2}
const VARIANTS := 3
const WALK_COLUMNS := 12
const STEPS := [1, 0, 2, 0]
const CELL_PX := 96.0
const FOOT_Y := 93.0
static var _frames: Dictionary = {}

static func breath_lift(seconds: float, staff_index: int) -> float:
	return roundf(1.0 - cos(TAU * (seconds / 3.2 + staff_index * 0.37)))

static func pose_rect(foot: Vector2, height: float, lift: float) -> Rect2:
	var size := Vector2(height, height + lift)
	return Rect2(foot - Vector2(size.x * 0.5, size.y * FOOT_Y / CELL_PX), size)

static func pose_body(body: Sprite2D, height: float, lift: float) -> void:
	body.centered = false
	body.offset = Vector2(-CELL_PX * 0.5, -FOOT_Y)
	body.scale = Vector2(height, height + lift) / CELL_PX

static func _frame(key: int, atlas: Texture2D, area: Rect2) -> AtlasTexture:
	if not _frames.has(key):
		var texture := AtlasTexture.new()
		texture.atlas = atlas
		texture.region = area
		texture.filter_clip = true
		_frames[key] = texture
	return _frames[key]

static func portrait(region: String, role: String, variant: int = 0) -> AtlasTexture:
	var row: int = REGIONS[region]
	var column: int = int(ROLES[role]) * VARIANTS + variant
	return _frame(-1 - row * 9 - column, PORTRAITS, Rect2(column * 128, row * 144, 128, 144))

static func sprite(region: String, role: String, facing: Vector2i, walk_frame: int, variant: int = 0) -> AtlasTexture:
	if role == "manager": return null
	var row: int = (int(REGIONS[region]) * 2 + int(ROLES[role])) * VARIANTS + variant
	var direction := 0
	match facing:
		Vector2i.LEFT: direction = 1
		Vector2i.RIGHT: direction = 2
		Vector2i.UP: direction = 3
	var step: int = 0 if walk_frame < 0 else STEPS[posmod(walk_frame, STEPS.size())]
	var column := direction * 3 + step
	return _frame(row * WALK_COLUMNS + column, WALK, Rect2(column * 96, row * 96, 96, 96))
