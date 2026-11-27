class_name TDCoarseSpriteArt
extends RefCounted
## Measured sprite crops share a foot line and a height across all poses of each character.

const DIRECTORY := "res://assets/characters/coarse-pixel-v1/"
const DIAGONAL_PATH := DIRECTORY + "diagonal.png"

static var _sheets: Dictionary = {}
static var _frames: Dictionary = {}
static var _layout: Dictionary = {}

static func frame(character: String, index: int) -> AtlasTexture:
	if _layout.is_empty():
		_layout = JSON.parse_string(FileAccess.get_file_as_string(DIRECTORY + "frames.json"))
	var poses: Array = _layout.get(character, [])
	if index < 0 or index >= poses.size():
		return null
	if not _sheets.has(character):
		_sheets[character] = load(DIRECTORY + character + ".png")
		_frames[character] = {}
	var cache: Dictionary = _frames[character]
	if not cache.has(index):
		var pose: Array = poses[index]
		var texture := AtlasTexture.new()
		texture.atlas = _sheets[character]
		texture.region = Rect2(pose[0], pose[1], pose[2], pose[3])
		# Extra transparent space goes above the art, leaving the feet anchored.
		texture.margin = Rect2(0, pose[4], 0, pose[4])
		texture.filter_clip = true
		cache[index] = texture
	return cache[index]

static func cardinal_index(direction: int, walk_frame: int) -> int:
	match walk_frame:
		0: return 4 + direction
		2: return 8 + direction
	return direction
