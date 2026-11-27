class_name TDChefArt
extends RefCounted
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
	if facing.x != 0 and facing.y != 0:
		var row := 0 if facing.y > 0 else 5
		return TDCoarseSpriteArt.frame("diagonal", row + frame + 1)
	return TDCoarseSpriteArt.frame("hero", TDCoarseSpriteArt.cardinal_index(direction_index(facing), frame))
