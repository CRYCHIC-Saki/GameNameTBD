class_name TDChefArt
extends RefCounted
## Read-only atlas views; approved PNGs are never rewritten or resized on disk.
const IDLE_ATLAS: Texture2D = preload("res://assets/characters/protagonist/protagonist-idle-four-directions-v1.png")
const WALK_PATH := "res://assets/characters/protagonist/protagonist-walk-four-directions-v1.png"
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

static func direction_index(facing: Vector2i) -> int:
	match facing:
		Vector2i.UP: return 1
		Vector2i.LEFT: return 2
		Vector2i.RIGHT: return 3
	return 0

static func texture(facing: Vector2i, walk_frame: int = -1) -> Texture2D:
	var row: int=1 if walk_frame==0 else (2 if walk_frame==2 else 0)
	return TDRedrawArt.cell("res://assets/redraw-v1/walker-hero.png",row*4+direction_index(facing),4,3)
