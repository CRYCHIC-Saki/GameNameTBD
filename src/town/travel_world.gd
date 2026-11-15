class_name TDTravelWorld
extends Node2D
## One disposable exploration view; all property comes from the profile's map provider.
signal harbor_requested
signal landmark_requested(plot: Dictionary)
const CELL:=48.0
var town_id: String="tokyo"
var map: TDTownMap
var player: TDKitchenPlayer
var camera: Camera2D
var _hint: Label
var _layer: CanvasLayer
var _ground: ImageTexture
var _buildings: Array[Dictionary]=[]
var _solids: Array[Rect2]=[]
var _target: Dictionary={}
var _closed: bool=false

func _ready() -> void:
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	y_sort_enabled=true
	_make_ground()
	_make_buildings()
	_make_dressing()
	player=TDKitchenPlayer.new();player.name="Player";player.sprite_height=72;player.walk_cycle_distance=96
	player.process_mode=Node.PROCESS_MODE_PAUSABLE
	player.collision_layer=32;player.collision_mask=16;player.confine_to=_confine
	var sprite:=Sprite2D.new();sprite.name="Sprite2D";player.add_child(sprite)
	var shape:=CollisionShape2D.new();var circle:=CircleShape2D.new();circle.radius=9;shape.shape=circle;player.add_child(shape)
	add_child(player);player.position=(Vector2(TDTravelCatalog.port(town_id))+Vector2.ONE*.5)*CELL
	camera=Camera2D.new();camera.position=player.position;add_child(camera);camera.make_current()
	camera.limit_left=0;camera.limit_top=0;camera.limit_right=int((map.extent+6)*CELL);camera.limit_bottom=int(map.extent*CELL)
	_layer=CanvasLayer.new();_layer.layer=22;add_child(_layer)
	var panel:=PanelContainer.new();panel.position=Vector2(18,690);panel.size=Vector2(1244,92);_layer.add_child(panel)
	_hint=TDUI.label("",TDUI.FONT_BODY);_hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;panel.add_child(_hint)
	var margin:=TDUI.wood();margin.content_margin_left=16;margin.content_margin_top=10;panel.add_theme_stylebox_override("panel",margin)
	queue_redraw()

func _make_ground() -> void:
	var style:=TDTravelCatalog.info(town_id);var s:=24
	var image:=Image.create((map.extent+6)*s,map.extent*s,false,Image.FORMAT_RGBA8)
	image.fill(Color(style.water))
	var surfaces: Dictionary=TDTownScenery.smooth_surfaces(map,6)
	for y: int in map.extent:
		for x: int in range(map.extent+6):
			var at:=Vector2i(x,y);var terrain: Dictionary=map.terrain_at(at);var surface: String=surfaces[at]
			# Regional swatches already carry the intended palette. An old per-pixel
			# gray tint would erase the new sandstone/terracotta road distinctions.
			TDTownScenery.paint_cell(image,at,surfaces,town_id)
			if surface=="bridge":
				var color:=Color("a7784d")
				image.fill_rect(Rect2i(x*s,y*s,s,s),color)
				for line: int in range(0,s,3): image.fill_rect(Rect2i(x*s,y*s+line,s,1),color.darkened(.2))
			if surface=="woodland" and map.terrain_at(at+Vector2i.DOWN).terrain_type=="plain":
				var rock:=Color("9b7759") if town_id=="mexico_city" else Color("7a8074")
				image.fill_rect(Rect2i(x*s,y*s+s-7,s,7),rock.darkened(.2))
				image.fill_rect(Rect2i(x*s,y*s+s-8,s,2),rock.lightened(.18))
	_ground=ImageTexture.create_from_image(image)

func _make_buildings() -> void:
	_buildings=[]
	var claimed: Dictionary={}
	for p: Dictionary in map.plots:
		if p.get("kind") in ["diner_lot","factory_lot","supply_factory"] or p.get("economic_courtyard",false): continue
		if p.get("kind")=="housing":
			# Group tiny cadastral cells into humane residential blocks.
			var cell:=Vector2i(int(p.x)/3,int(p.y)/3)
			if claimed.has(cell): continue
			claimed[cell]=true
			_add_building(p,1,Vector2(2.7,2.5),Vector2(p.x,p.y)+Vector2(1,1))
			continue
		var column:=0
		if str(p.get("kind")) in ["plaza","amusement","rich_district"]: column=2
		elif str(p.get("kind")) in ["urban_village","housing"]: column=1
		# Large zones are composed of several human-scale buildings and open courtyards.
		var width:=minf(float(p.w),5.5)
		var count:=maxi(1,int(p.w)/6)
		for n: int in count:
			_add_building(p,column,Vector2(width,minf(float(p.h),5)),Vector2(p.x+n*6,p.y)+Vector2(width*.5,float(p.h)))
	var at:=Vector2(TDTravelCatalog.port(town_id))
	var port: Dictionary={"id":"harbor","kind":"harbor","name":"港口客运","x":at.x-2,"y":at.y-3,"w":4,"h":3}
	_add_building(port,3,Vector2(5,4),at+Vector2(0,-.5))
	# Ownership parcels are not invisible walls: only rendered building bases collide.
	var body:=StaticBody2D.new();body.collision_layer=16;body.collision_mask=0;add_child(body)
	for rect: Rect2 in _solids:
		var collision:=CollisionShape2D.new();var shape:=RectangleShape2D.new();shape.size=rect.size
		collision.shape=shape;collision.position=rect.get_center();body.add_child(collision)

func _add_building(plot: Dictionary,column: int,span: Vector2,feet: Vector2) -> void:
	var sprite:=Sprite2D.new();sprite.texture=TDTravelCatalog.sprite(town_id,column)
	if plot.get("kind")=="harbor" and town_id in ["paris","bangkok"]: sprite.flip_h=true
	if plot.get("construction",false): sprite.texture=TDTownArt.sprite(12)
	var scale_value:=minf(span.x*CELL/sprite.texture.get_width(),span.y*CELL/sprite.texture.get_height())
	# Restaurant canvases include generous clear margins; give those facades more room.
	var display_scale: float=1.8 if column==0 else (1.25 if column==1 else (1.3 if column==3 else 1.4))
	sprite.scale=Vector2.ONE*scale_value*display_scale;sprite.position=feet*CELL
	sprite.offset=Vector2(0,-sprite.texture.get_height()*.5);add_child(sprite)
	# Keep the existing walking/interaction base; larger roofs must not close streets.
	var size_px:=sprite.texture.get_size()*scale_value
	var base:=Rect2(feet*CELL-Vector2(size_px.x*.43,size_px.y*.38),Vector2(size_px.x*.86,size_px.y*.32))
	if plot.get("kind")!="harbor": _solids.append(base)
	_buildings.append({"plot":plot.duplicate(true),"feet":feet,"base":base})

func _walkable(cell: Vector2i) -> bool:
	return cell.x>=0 and cell.y>=0 and cell.x<map.extent and cell.y<map.extent and bool(map.terrain_at(cell).walkable)

func _make_dressing() -> void:
	for y: int in range(7,70,4):
		for x: int in range(7,69,4):
			var at:=Vector2i(x,y);var feet: Vector2=(Vector2(at)+Vector2.ONE*.5)*CELL
			if map.is_road(x,y) or map.terrain_at(at).terrain_type=="water": continue
			if _solids.any(func(r:Rect2)->bool:return r.grow(45).has_point(feet)): continue
			var plot: Dictionary=map.plot_at(x,y)
			if plot.has("branch_id") or plot.get("kind")=="housing": continue
			var noise:=TDTownScenery.noise(x,y)
			if noise%3==0: continue
			var decoration: bool=not plot.is_empty() or noise%4==0
			var prop:=Sprite2D.new();prop.texture=TDTravelCatalog.prop(town_id,decoration)
			var width: float=58.0 if decoration else (105.0 if town_id=="mexico_city" else 145.0)
			prop.scale=Vector2.ONE*width/prop.texture.get_width();prop.offset=Vector2(0,-prop.texture.get_height()*.5)
			prop.position=feet;add_child(prop)

func _confine(candidate: Vector2) -> bool:
	# Sweep in short steps as well as testing the endpoint, including long physics frames.
	if player==null: return _can_stand(candidate)
	var count:=maxi(1,ceili(player.position.distance_to(candidate)/6.0))
	for i: int in range(1,count+1):
		if not _can_stand(player.position.lerp(candidate,float(i)/count)): return false
	return true

func _can_stand(candidate: Vector2) -> bool:
	# TDKitchenPlayer owns axis sliding; this predicate receives ONE proposed foot point.
	for offset: Vector2 in [Vector2.ZERO,Vector2(-9,0),Vector2(9,0),Vector2(0,-9),Vector2(0,9)]:
		var p:=candidate+offset
		if not _walkable(Vector2i(floori(p.x/CELL),floori(p.y/CELL))): return false
	for solid: Rect2 in _solids:
		if solid.grow(9).has_point(candidate): return false
	return true

func nearby() -> Dictionary:
	var at:=player.position/CELL
	var port_rect:=TDTravelCatalog.harbor_rect(town_id)
	if at.distance_to(at.clamp(port_rect.position,port_rect.end))<=.65: return {"id":"harbor","kind":"harbor","name":"港口客运"}
	var best:=.65;var found: Dictionary={}
	for entry: Dictionary in _buildings:
		var p: Dictionary=entry.plot
		if p.get("kind") in ["housing","diner_lot","harbor"]: continue
		var rect: Rect2=entry.base
		var distance: float=player.position.distance_to(player.position.clamp(rect.position,rect.end))/CELL
		if distance<best: best=distance;found=p
	return found.duplicate(true)

func _process(_delta: float) -> void:
	if _closed: return
	camera.position=player.position
	_target=nearby()
	var text: String="WASD 走动 · Shift 疾跑 · M 地图 · B 菜谱 · 港口可返回或继续旅行"
	if not _target.is_empty(): text="E · "+("港口客运" if _target.kind=="harbor" else TDTravelCatalog.label(_target,town_id))+"　　M 地图"
	_hint.text=TDTravelCatalog.info(town_id).name+"\n"+text

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("world_interact") and not event.is_echo() and player.controls_enabled:
		var target:=nearby()
		if not target.is_empty():
			if target.kind=="harbor": harbor_requested.emit()
			else: landmark_requested.emit(target)
		get_viewport().set_input_as_handled()

func set_day_minute(minute: float) -> void:
	self_modulate=TDDaylight.sample(minute).tint

func close() -> void:
	_closed=true
	if player!=null: player.set_controls_enabled(false)
	set_process(false);set_process_unhandled_input(false)

func _draw() -> void:
	if _ground==null: return
	draw_texture_rect(_ground,Rect2(Vector2.ZERO,Vector2(map.extent+6,map.extent)*CELL),false)

func set_presented(value: bool) -> void:
	visible=value
	if _layer!=null: _layer.visible=value
	if camera!=null:
		camera.enabled=value
		if value: camera.make_current()
	if player!=null: player.set_controls_enabled(value)
	set_process_unhandled_input(value)
