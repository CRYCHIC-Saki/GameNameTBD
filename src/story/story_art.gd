class_name TDStoryArt
extends RefCounted
## Original selected idle/portrait art stays read-only; new walking frames complement it.
const ALING: Texture2D = preload("res://assets/characters/aling/archive/2026-10-29/aling-idle-four-directions.png")
const CHEN: Texture2D = preload("res://assets/characters/ash-priest/archive/2026-10-29/ash-priest-idle-four-directions.png")
const ALING_BUST: Texture2D = preload("res://assets/characters/aling/archive/2026-10-29/aling-dialogue-halfbody.png")
const CHEN_BUST: Texture2D = preload("res://assets/characters/ash-priest/archive/2026-10-29/ash-priest-dialogue-halfbody.png")
const HERO_BUST: Texture2D = preload("res://assets/characters/protagonist/protagonist-dialogue-halfbody-pose-pixel-v7.png")
const ALING_WALK: Texture2D = preload("res://assets/characters/aling/aling-walk-four-directions-v1.png")
const CHEN_WALK: Texture2D = preload("res://assets/characters/ash-priest/ash-priest-walk-four-directions-v1.png")
const REGIONS: Dictionary = {
	"aling": [Rect2(180,30,385,593),Rect2(696,30,382,594),Rect2(226,643,275,578),Rect2(738,643,308,578)],
	"chen": [Rect2(183,17,407,609),Rect2(669,17,404,609),Rect2(212,633,380,608),Rect2(698,633,359,608)],
}
const EMOTIONS := ["calm","happy","surprised","puzzled","angry","sad"]
const MOODS: Dictionary = {
	"hero":preload("res://assets/story/hero-emotions-v1.png"),
	"aling":preload("res://assets/story/aling-emotions-v1.png"),
	"chen":preload("res://assets/story/chen-emotions-v1.png")}
const ALING_CORRECTIONS: Texture2D=preload("res://assets/story/aling-emotions-corrections-v1.png")
const ACTIONS: Texture2D=preload("res://assets/story/opening-actions-v1.png")
const EXTRA_ACTIONS: Texture2D=preload("res://assets/story/opening-actions-extra-v1.png")
const PROPS: Texture2D=preload("res://assets/story/opening-props-v1.png")
const BACKGROUNDS: Texture2D=preload("res://assets/story/opening-backgrounds-v1.png")
static var _views: Dictionary = {}

static func sprite(who: String, facing: Vector2i = Vector2i.DOWN, walk_frame: int=-1) -> Texture2D:
	if not REGIONS.has(who): return null
	var index:=TDChefArt.direction_index(facing)
	if walk_frame==0 or walk_frame==2:
		var key: String=who+":walk:"+str(index)+":"+str(walk_frame)
		if not _views.has(key):
			var source: Texture2D=ALING_WALK if who=="aling" else CHEN_WALK
			var size:=Vector2i(source.get_width()/4,source.get_height()/2)
			var origin:=Vector2i(index,walk_frame/2)*size
			var image:=source.get_image()
			if image.is_compressed(): image.decompress()
			var used:=_walk_bounds(image.get_region(Rect2i(origin,size)))
			return _view(key,source,Rect2(origin+used.position,used.size))
		return _views[key]
	return _view(who+str(index),ALING if who=="aling" else CHEN,REGIONS[who][index])

static func _walk_bounds(image: Image) -> Rect2i:
	# Generated transparent gutters contain a few alpha=1 pixels. They must not shift
	# the feet anchor or determine pose scale; source pixels remain untouched.
	var low:=image.get_size();var high:=Vector2i(-1,-1)
	for y: int in image.get_height():
		for x: int in image.get_width():
			if image.get_pixel(x,y).a<.05: continue
			low.x=mini(low.x,x);low.y=mini(low.y,y);high.x=maxi(high.x,x);high.y=maxi(high.y,y)
	return Rect2i(low,high-low+Vector2i.ONE) if high.x>=0 else Rect2i(Vector2i.ZERO,image.get_size())

static func portrait(who: String, emotion: String="", action: String="") -> Texture2D:
	if who=="hero" and action.contains("碗"): return _view("action:put-bowl",EXTRA_ACTIONS,Rect2(0,0,840,887))
	if who=="aling" and action.contains("钱"): return _view("action:pay",EXTRA_ACTIONS,Rect2(840,0,934,887))
	if action.contains("锅柄"): return action_pose(3)
	if action.contains("排风"): return action_pose(4)
	if action.contains("翻开账本"): return action_pose(1)
	if action.contains("吃下一口") or action.contains("认真嚼完"): return action_pose(6)
	if who=="aling" and emotion in ["puzzled","sad"]: return grid_view("aling-corrected:"+emotion,ALING_CORRECTIONS,0 if emotion=="puzzled" else 1,2,1)
	if who=="aling" and emotion in ["calm","surprised","angry"]:
		var regions: Dictionary={"calm":Rect2(0,0,538,506),"surprised":Rect2(1036,0,500,506),"angry":Rect2(538,507,500,517)}
		return _view("aling-mood:"+emotion,MOODS.aling,regions[emotion])
	if MOODS.has(who) and emotion in EMOTIONS and not (who in ["aling","chen"] and emotion=="happy"):
		return grid_view("mood:"+who+emotion,MOODS[who],EMOTIONS.find(emotion),3,2)
	if who=="hero": return HERO_BUST
	if who=="aling": return _view("aling-bust",ALING_BUST,Rect2(112,23,1085,1231))
	if who=="chen": return _view("chen-bust",CHEN_BUST,Rect2(171,35,1046,1194))
	return null

static func _view(key: String, source: Texture2D, region: Rect2) -> Texture2D:
	if not _views.has(key):
		var texture:=AtlasTexture.new()
		texture.atlas=source;texture.region=region;texture.filter_clip=true
		_views[key]=texture
	return _views[key]

static func fit(texture: Texture2D, box: Rect2) -> Rect2:
	var scale:=minf(box.size.x/texture.get_width(),box.size.y/texture.get_height())
	var size:=texture.get_size()*scale
	return Rect2(box.position+Vector2((box.size.x-size.x)*.5,box.size.y-size.y),size)

static func grid_view(key: String, source: Texture2D, index: int, columns: int, rows: int) -> Texture2D:
	if _views.has(key): return _views[key]
	var cell:=Vector2i(source.get_width()/columns,source.get_height()/rows)
	var origin:=Vector2i(index%columns,index/columns)*cell
	var image:=source.get_image()
	if image.is_compressed(): image.decompress()
	var used:=_walk_bounds(image.get_region(Rect2i(origin,cell)))
	return _view(key,source,Rect2(origin+used.position,used.size))

static func action_pose(index: int) -> Texture2D:
	# Measured generated atlas boundaries, not assumed equal panels.
	var cuts: Array=[Rect2(0,0,418,447),Rect2(418,0,505,447),Rect2(923,0,455,447),Rect2(1378,0,380,447),Rect2(0,447,456,440),Rect2(456,447,454,440),Rect2(910,447,432,440),Rect2(1342,447,432,440)]
	return _view("action:"+str(index),ACTIONS,cuts[clampi(index,0,7)])

static func prop(index: int) -> Texture2D:
	var regions: Array=[Rect2(0,0,548,420),Rect2(548,0,398,420),Rect2(955,85,385,330),Rect2(1338,0,436,446),Rect2(0,420,537,449),Rect2(537,420,369,449),Rect2(906,440,432,429),Rect2(1338,446,436,423)]
	return _view("prop:"+str(index),PROPS,regions[clampi(index,0,7)])

static func background(index: int) -> Texture2D:
	var size:=BACKGROUNDS.get_size()/2
	return _view("bg:"+str(index),BACKGROUNDS,Rect2(Vector2(index%2,index/2)*size+Vector2(3,3),size-Vector2(6,6)))

static func cropped_view(key: String, source: Texture2D, region: Rect2i) -> Texture2D:
	if _views.has(key): return _views[key]
	var image:=source.get_image()
	if image.is_compressed(): image.decompress()
	var used:=_walk_bounds(image.get_region(region))
	return _view(key,source,Rect2(region.position+used.position,used.size))
