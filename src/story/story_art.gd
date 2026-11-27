class_name TDStoryArt
extends RefCounted
const ALING_BUST: Texture2D = preload("res://assets/characters/aling/archive/2026-10-29/aling-dialogue-halfbody.png")
const CHEN_BUST: Texture2D = preload("res://assets/characters/ash-priest/archive/2026-10-29/ash-priest-dialogue-halfbody.png")
const HERO_BUST: Texture2D = preload("res://assets/characters/protagonist/protagonist-dialogue-halfbody-pose-pixel-v7.png")
const MAP_NPCS := ["aling", "chen", "luoe", "hertz", "vito", "hina", "crowd"]
const WALKING_NPCS := ["aling", "chen"]
const EMOTIONS := ["calm","happy","surprised","puzzled","angry","sad"]
const MOODS: Dictionary = {
	"hero":preload("res://assets/story/hero-emotions-v1.png"),
	"aling":preload("res://assets/story/aling-emotions-v1.png"),
	"chen":preload("res://assets/story/chen-emotions-v1.png")}
const ALING_CORRECTIONS: Texture2D=preload("res://assets/story/aling-emotions-corrections-v1.png")
const ACTIONS: Texture2D=preload("res://assets/story/opening-actions-v1.png")
const EXTRA_ACTIONS: Texture2D=preload("res://assets/story/opening-actions-extra-v1.png")
const PROPS: Texture2D=preload("res://assets/redraw-v1/story-props.png")
const BACKGROUNDS: Texture2D=preload("res://assets/redraw-v1/backgrounds.png")
static var _views: Dictionary = {}

static func sprite(who: String, facing: Vector2i = Vector2i.DOWN, walk_frame: int = -1) -> Texture2D:
	var character := "luoe" if who == "luo" else who
	if character not in MAP_NPCS:
		return null
	var index := TDChefArt.direction_index(facing)
	if character in WALKING_NPCS:
		index = TDCoarseSpriteArt.cardinal_index(index, walk_frame)
	return TDCoarseSpriteArt.frame(character, index)


static func four_way_facing(offset: Vector2) -> Vector2i:
	if absf(offset.x) > absf(offset.y):
		return Vector2i.LEFT if offset.x < 0 else Vector2i.RIGHT
	return Vector2i.UP if offset.y < 0 else Vector2i.DOWN

class TownActor extends Sprite2D:
	var actor_id: String
	var display_height: float
	var facing := Vector2i.ZERO
	var _frame := -1

	var _caption: Label

	func configure(id: String, height: float) -> void:
		actor_id = id
		display_height = height * (0.9 if id == "aling" else 1.0)
		centered = false
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		facing = Vector2i.ZERO
		pose(Vector2i.DOWN)

	func place(id: String, height: float, anchor: Vector2, can_stand: Callable,
			preferred: Vector2 = Vector2.RIGHT) -> void:
		configure(id,height)
		visible = false
		# Start beside the destination so the character leaves its entrance clear.
		for step: float in [52.0, 76.0, 100.0, 124.0]:
			for direction: Vector2 in [preferred, -preferred, Vector2.DOWN, Vector2.UP,
				Vector2(1, 1).normalized(), Vector2(-1, 1).normalized(),
				Vector2(1, -1).normalized(), Vector2(-1, -1).normalized()]:
				var feet := anchor + direction * step
				if can_stand.call(feet):
					position = feet
					visible = true
					_set_facing(Vector2i.DOWN)
					return

	func set_caption(value: String) -> void:
		_caption=TDUI.label(value,TDUI.FONT_CAPTION,Color("fff6df"))
		_caption.add_theme_color_override("font_outline_color",Color("21160d"))
		_caption.add_theme_constant_override("outline_size",4)
		_caption.mouse_filter=Control.MOUSE_FILTER_IGNORE
		_caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		add_child(_caption)
		_layout_caption()

	func set_callout(value: String) -> void:
		if _caption==null: return
		var heading := str(_caption.get_meta("heading",_caption.text))
		_caption.set_meta("heading",heading)
		var text := heading if value.is_empty() else value+"\n"+heading
		if _caption.text==text: return
		_caption.text=text
		_layout_caption()

	func _layout_caption() -> void:
		if _caption==null: return
		_caption.scale=Vector2.ONE/scale
		_caption.custom_minimum_size.x=128
		_caption.reset_size()
		_caption.position=Vector2(-64,-display_height-_caption.size.y-6)/scale

	func face_nearby(point: Vector2) -> void:
		if not visible: return
		var delta := point - position
		if delta.length_squared() <= 240.0 * 240.0 and delta.length_squared() > 4.0:
			_set_facing(TDStoryArt.four_way_facing(delta))

	func _set_facing(direction: Vector2i) -> void:
		pose(direction)

	func pose(direction: Vector2i, frame: int = -1) -> void:
		if direction == facing and frame == _frame: return
		facing = direction
		_frame = frame
		texture = TDStoryArt.sprite(actor_id, facing, frame)
		scale = Vector2.ONE * (display_height / texture.get_height())
		offset = Vector2(-texture.get_width() * .5, -texture.get_height())
		_layout_caption()

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
	var reference: Texture2D=TDRedrawArt.portrait(who,emotion)
	if reference!=null: return reference
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

static func paint_ledger_title(canvas: CanvasItem, art: Texture2D, box: Rect2) -> void:
	# Original archive bust already says 密令. New mood poses use the same cover title,
	# at exposed cover coordinates only (never stamped over hands or inner pages).
	if not art is AtlasTexture: return
	var atlas:=art as AtlasTexture
	var point:=Vector2.ZERO;var font_size:=20;var angle:=0.0
	if atlas.atlas==MOODS.aling:
		if atlas.region.position.y<500 and atlas.region.position.x<540: point=Vector2(315,380);angle=.15
		elif atlas.region.position.y>=500 and atlas.region.position.x>530 and atlas.region.position.x<1040: point=Vector2(817,837);font_size=15;angle=.55
	elif atlas.atlas==ALING_CORRECTIONS:
		if atlas.region.position.x<880: point=Vector2(543,524);font_size=27;angle=.08
		else: point=Vector2(1303,768);font_size=24
	if point==Vector2.ZERO: return
	var target:=fit(art,box);var scale_factor:=target.size.x/atlas.region.size.x
	var at:=target.position+(point-atlas.region.position)*scale_factor
	canvas.draw_set_transform_matrix(Transform2D(angle,Vector2.ONE*scale_factor,0,at))
	canvas.draw_string(TDUI.font(),Vector2.ZERO,"密令",HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,Color("f4d382"))
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)

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
	return TDRedrawArt.cell("res://assets/redraw-v1/story-props.png",clampi(index,0,7),4,2)

static func background(index: int) -> Texture2D:
	var size:=BACKGROUNDS.get_size()/2
	return _view("bg:"+str(index),BACKGROUNDS,Rect2(Vector2(index%2,index/2)*size+Vector2(3,3),size-Vector2(6,6)))

static func cropped_view(key: String, source: Texture2D, region: Rect2i) -> Texture2D:
	if _views.has(key): return _views[key]
	var image:=source.get_image()
	if image.is_compressed(): image.decompress()
	var used:=_walk_bounds(image.get_region(region))
	return _view(key,source,Rect2(region.position+used.position,used.size))
