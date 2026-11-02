@tool
class_name TDArrivalCutscene
extends Control
## Local editable film stage. AnimationPlayer owns every presentation property.
## The host samples seconds; this scene never changes world, camera, or save state.
const SEGMENTS := {"arrival":"A_arrival","hungry":"B_hungry","messenger":"C_aling"}
const SPANS := {"arrival":14.0,"hungry":6.0,"messenger":10.0}
const HERO: Texture2D=preload("res://assets/story/arrival-hero-v1.png")
const ALING: Texture2D=preload("res://assets/story/arrival-aling-v2.png")
const BACKGROUND: Texture2D=preload("res://assets/story/arrival-coast-v1.png")
const PROPS: Texture2D=preload("res://assets/story/arrival-props-v1.png")

@export_range(1,9) var shot_index: int=1
@export var focus: Vector2=Vector2(640,400)
@export var camera_zoom: float=1.0
@export var hero_position: Vector2=Vector2(475,675)
@export var hero_pose: int=0
@export var hero_height: float=305.0
@export var aling_position: Vector2=Vector2(1167,524)
@export var aling_pose: int=0
@export var aling_visible: bool=false
@export var bus_position: Vector2=Vector2(330,485)
@export var bus_visible: bool=true
@export var detail_mode: int=0
@export var map_zoom: float=1.0
@export var book_open: float=0.0
var segment: String=""
var seconds: float=0.0
var _map_root: Node2D
var _view_transform:=Transform2D.IDENTITY
static var _poses: Dictionary={}

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	clip_contents=true
	_build_map()

func _process(_delta: float) -> void:
	# Also redraw when the Godot editor scrubs AnimationPlayer.
	_sync_map();queue_redraw()

func sample_segment(id: String, elapsed_seconds: float) -> void:
	if not SEGMENTS.has(id) or not is_finite(elapsed_seconds): return
	var timeline:=get_node("AnimationPlayer") as AnimationPlayer
	if segment!=id:
		segment=id;timeline.play(SEGMENTS[id]);timeline.pause()
	seconds=clampf(elapsed_seconds,0.0,SPANS[id])
	timeline.seek(seconds,true)
	_sync_map();queue_redraw()

func _build_map() -> void:
	_map_root=Node2D.new();_map_root.name="MapRoot";add_child(_map_root)
	var name_label:=Label.new();name_label.name="TownName";name_label.text="河口镇"
	name_label.position=Vector2(-60,-20);name_label.add_theme_color_override("font_color",Color("724229"))
	name_label.add_theme_font_size_override("font_size",38);_map_root.add_child(name_label)
	name_label.add_theme_color_override("font_outline_color",Color("f4e6bf"));name_label.add_theme_constant_override("outline_size",7)
	var caption:=Label.new();caption.name="Caption";caption.text="百国商船汇聚，天下千味之港。"
	caption.position=Vector2(-300,175);caption.add_theme_color_override("font_color",Color("563e30"))
	caption.add_theme_font_size_override("font_size",30);_map_root.add_child(caption)
	for i: int in 3:
		var line:=Line2D.new();line.name="RedCircle%d"%(i+1);line.width=3.0;line.default_color=Color("ba493b")
		for n: int in 81:
			var angle:=TAU*n/80.0
			line.add_point(Vector2(15,0)+Vector2(cos(angle)*(122+i*10),sin(angle)*(68+i*7)))
		_map_root.add_child(line)

func _sync_map() -> void:
	if _map_root==null: return
	var fit:=minf(size.x/1280.0,size.y/800.0)
	_map_root.visible=detail_mode==1
	_map_root.position=((size-Vector2(1280,800)*fit)*.5+Vector2(640,400)*fit).round()
	_map_root.scale=Vector2.ONE*fit*map_zoom

static func pose(who: String, index: int) -> Texture2D:
	var key:=who+str(index)
	if not _poses.has(key):
		var art: Texture2D=HERO if who=="hero" else ALING
		var columns:=4 if who=="hero" else 3
		var cell:=Vector2i(art.get_width()/columns,art.get_height()/2)
		_poses[key]=TDStoryArt.cropped_view("arrival:"+key,art,Rect2i(Vector2i(index%columns,index/columns)*cell,cell))
	return _poses[key]

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("0e1722"))
	var fit:=minf(size.x/1280.0,size.y/800.0)
	var origin:=((size-Vector2(1280,800)*fit)*.5).round()
	var frame:=Transform2D(0,Vector2.ONE*fit,0,origin)
	_view_transform=frame*Transform2D(0,Vector2.ONE*camera_zoom,0,(Vector2(640,400)-focus*camera_zoom).round())
	draw_set_transform_matrix(_view_transform)
	draw_texture_rect(BACKGROUND,Rect2(0,0,1280,800),false)
	# The bus travels behind the already disembarked actor, always towards the LEFT.
	if bus_visible:
		var bus:=TDStoryArt.prop(0)
		draw_set_transform_matrix(_view_transform*Transform2D(0,Vector2(-1,1),0,bus_position))
		draw_texture_rect(bus,Rect2(-220,-190,440,190),false)
		draw_set_transform_matrix(_view_transform)
	# A single ordinary painted white threshold; the hero crosses left -> right once.
	draw_colored_polygon(PackedVector2Array([Vector2(531,600),Vector2(538,600),Vector2(556,716),Vector2(546,716)]),Color("f4eedc"))
	_draw_actor("hero",hero_pose,hero_position,hero_height)
	if aling_visible: _draw_actor("aling",aling_pose,aling_position,298.0)
	if detail_mode==1:
		draw_set_transform_matrix(frame)
		draw_rect(Rect2(0,0,1280,800),Color("314554"))
		draw_set_transform_matrix(frame*Transform2D(0,Vector2.ONE*map_zoom,0,Vector2(640,400)))
		_draw_map()
	elif detail_mode==2:
		# Same ledger as the held pose, isolated insert; no extra book on a belt.
		draw_set_transform_matrix(frame)
		draw_rect(Rect2(0,0,1280,800),Color("1f293b"))
		_draw_book(Vector2(640,400),book_open)
	draw_set_transform_matrix(frame)
	draw_rect(Rect2(0,0,1280,40),Color("0e1722"));draw_rect(Rect2(0,760,1280,40),Color("0e1722"))
	draw_set_transform_matrix(Transform2D.IDENTITY)

func _draw_actor(who: String, index: int, feet: Vector2, height: float) -> void:
	var art:=pose(who,index)
	var dimensions:=art.get_size()*(height/art.get_height())
	draw_rect(Rect2(feet+Vector2(-36,-3),Vector2(72,7)),Color(0.14,0.19,0.22,.18))
	draw_texture_rect(art,Rect2((feet-Vector2(dimensions.x*.5,dimensions.y)).round(),dimensions),false)
	if who=="aling":
		# Lettering is a game-rendered cover detail: preserve the source pose atlas.
		var atlas:=art as AtlasTexture
		var labels: Array[Vector2]=[Vector2(193,249),Vector2(729,198),Vector2(1247,213),Vector2(232,728),Vector2(743,728),Vector2(1253,727)]
		var point:=feet-Vector2(dimensions.x*.5,dimensions.y)+(labels[index]-atlas.region.position)*dimensions/atlas.region.size
		var letter_scale:=height/atlas.region.size.y
		draw_set_transform_matrix(_view_transform*Transform2D(.22 if index<2 else -.12,Vector2.ONE*letter_scale,0,point))
		draw_string(ThemeDB.fallback_font,Vector2(-12,0),"密令",HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("f7d77d"))
		draw_set_transform_matrix(_view_transform)

func _draw_map() -> void:
	var art:=TDStoryArt.cropped_view("arrival:map",PROPS,Rect2i(0,0,1030,500))
	draw_texture_rect(art,TDStoryArt.fit(art,Rect2(-520,-280,1040,520)),false)
	# Text and exactly three circles are children of the same MapRoot transform.

func _draw_book(center: Vector2, openness: float) -> void:
	var index:=0 if openness<.12 else (1 if openness<.85 else 2)
	var region: Rect2i=[Rect2i(1030,0,506,500),Rect2i(0,500,750,524),Rect2i(750,500,786,524)][index]
	var art:=TDStoryArt.cropped_view("arrival:book"+str(index),PROPS,region)
	var box:=TDStoryArt.fit(art,Rect2(center-Vector2(400,260),Vector2(800,520)))
	draw_texture_rect(art,box,false)
	if index<2:
		var title_at:=box.position+box.size*(Vector2(.34,.22) if index==0 else Vector2(.74,.25))
		draw_string(ThemeDB.fallback_font,title_at,"密令",HORIZONTAL_ALIGNMENT_LEFT,-1,42 if index==0 else 27,Color("f3d580"))
	if index==0: return
	var pages: Array[Rect2]=[Rect2(.16,.20,.31,.56),Rect2(.53,.20,.32,.56)]
	if index==1: pages.assign([Rect2(.37,.22,.08,.58),Rect2(.515,.22,.10,.58)])
	for page: int in pages.size():
		var area:=pages[page]
		for row: int in 9:
			var points:=PackedVector2Array()
			var width: float=area.size.x*(.75+float((row*3+page)%5)*.05)
			for n: int in 65:
				var x: float=float(n)/64.0
				var wave: float=(sin(x*TAU*(7+row%3)+row)+.4*sin(x*TAU*19))*.003
				var local:=area.position+Vector2(x*width,float(row)/9.0*area.size.y+wave)
				points.append(box.position+local*box.size)
			draw_polyline(points,Color("78583d"),1.6 if index==1 else 2.0,false)
