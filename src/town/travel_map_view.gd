class_name TDTravelMapView
extends Control
## A single atlas canvas. Navigation changes only the camera, never the player or clock.
const WORLD_SIZE:=Vector2(1460,900)
const BACKGROUND: Texture2D=preload("res://assets/town/world-atlas-v1.png")
const TOWN_SIZE:=220.0
const ORIGINS:={"mexico_city":Vector2(80,380),"paris":Vector2(430,120),"chengdu":Vector2(800,280),"tokyo":Vector2(1175,170),"bangkok":Vector2(930,590)}
const SEA:=Color("137c7b")
var maps: Dictionary={}
var town_id: String="chengdu"
var marker:=Vector2(69.5,34.5)
var zoom: float=1.0
var max_zoom: float=5.0
var minimum_view_size:=Vector2(1080,520)
var heading: String="五镇航海图"
var controls_hint: String="滚轮缩放 · 按住拖动 · 双击小镇放大 · M / Esc 返回"
var show_player: bool=true
var pan:=Vector2.ZERO
var _dragging: bool=false
var _textures: Dictionary={}
var _hover: String=""

func configure(profile: TDGameProfile) -> void:
	for id: String in TDTravelCatalog.IDS: maps[id]=TDTravelCatalog.map_for(profile,id)

func _ready() -> void:
	custom_minimum_size=minimum_view_size;mouse_filter=Control.MOUSE_FILTER_STOP;clip_contents=true
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	for id: String in maps: _textures[id]=_terrain_texture(maps[id],id)
	resized.connect(queue_redraw)
	queue_redraw()

func scale_factor() -> float:
	return minf(size.x/WORLD_SIZE.x,size.y/WORLD_SIZE.y)*zoom

func world_to_screen(point: Vector2) -> Vector2:
	return size*.5+pan+(point-WORLD_SIZE*.5)*scale_factor()

func screen_to_world(point: Vector2) -> Vector2:
	return (point-size*.5-pan)/scale_factor()+WORLD_SIZE*.5

func zoom_at(point: Vector2, factor: float) -> void:
	var anchor:=screen_to_world(point)
	zoom=clampf(zoom*factor,1,max_zoom)
	pan=point-size*.5-(anchor-WORLD_SIZE*.5)*scale_factor()
	_limit_pan();queue_redraw()

func _limit_pan() -> void:
	var limit: Vector2=(WORLD_SIZE*scale_factor()-size).max(Vector2.ZERO)*.5+Vector2(80,65)
	pan=pan.clamp(-limit,limit)

func reset_view() -> void:
	zoom=1;pan=Vector2.ZERO;queue_redraw()

func focus_town(id: String) -> void:
	if not ORIGINS.has(id): return
	zoom=3.0;pan=-(ORIGINS[id]+Vector2.ONE*TOWN_SIZE*.5-WORLD_SIZE*.5)*scale_factor()
	_limit_pan();queue_redraw()

func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_WINDOW_FOCUS_OUT: _dragging=false

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			zoom_at(event.position,1.22 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.0/1.22);accept_event()
		elif event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_MIDDLE]:
			_dragging=event.pressed
			if event.double_click and not _hover.is_empty(): focus_town(_hover)
			accept_event()
	elif event is InputEventMouseMotion:
		if _dragging: pan+=event.relative;_limit_pan()
		_hover=""
		for id: String in ORIGINS:
			if Rect2(ORIGINS[id],Vector2.ONE*TOWN_SIZE).has_point(screen_to_world(event.position)): _hover=id
		queue_redraw();accept_event()

func _terrain_texture(map: TDTownMap,id: String) -> ImageTexture:
	var image:=Image.create(map.extent*6,map.extent*6,false,Image.FORMAT_RGBA8);image.fill(Color.TRANSPARENT)
	var style:=TDTravelCatalog.info(id)
	for y: int in map.extent:
		for x: int in map.extent:
			var surface: String=map.terrain_at(Vector2i(x,y)).surface_type
			var color:=Color(style.grass)
			if surface=="water": color=SEA.lightened(.08)
			elif surface=="stone": color=Color(style.road).lightened(.08)
			elif surface=="bridge": color=Color("c4a071")
			elif surface=="woodland": color=Color(style.leaf).darkened(.2)
			elif surface=="sand": color=Color("dfd1a6")
			var n:=TDTownScenery.noise(x,y)
			color=color.lightened(float(n%5)*.012)
			# Fine overlays are generated from live geography; the illustration owns scenery.
			color.a=.64 if surface in ["stone","bridge"] else (.16 if surface=="sand" else 0.0)
			image.fill_rect(Rect2i(x*6,y*6,6,6),color)
			if surface=="stone": image.fill_rect(Rect2i(x*6,y*6+5,6,1),color.darkened(.13))
			elif surface=="woodland": image.fill_rect(Rect2i(x*6+1,y*6+1,3,3),color.lightened(.16))
			elif surface=="water" and n%5==0: image.fill_rect(Rect2i(x*6+1,y*6+2,4,1),color.lightened(.16))
	return ImageTexture.create_from_image(image)

func _polygon(points: Array, color: Color) -> void:
	var vertices:=PackedVector2Array()
	for point: Vector2 in points: vertices.append(world_to_screen(point))
	draw_colored_polygon(vertices,color)
	vertices.append(vertices[0]);draw_polyline(vertices,Color("b8b48a"),2,true)

func _text(at: Vector2, value: String, font_size: int=16, color: Color=Color("f5e4bb")) -> void:
	var font:=get_theme_default_font()
	draw_string_outline(font,at,value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,4,Color("233c3d"))
	draw_string(font,at,value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),SEA)
	draw_texture_rect(BACKGROUND,Rect2(world_to_screen(Vector2.ZERO),WORLD_SIZE*scale_factor()),false)
	for id: String in maps:
		var origin: Vector2=ORIGINS[id];var rect:=Rect2(world_to_screen(origin),Vector2.ONE*TOWN_SIZE*scale_factor())
		draw_texture_rect(_textures[id],rect,false,Color(1,1,1,clampf((zoom-1)*.6,.25,1)))
		_draw_town(id,origin)
	# Passenger routes are independent of economic route unlocks.
	var home:=_port_point("chengdu")
	for id: String in maps:
		if id=="chengdu": continue
		var dest:=_port_point(id);var delta:=dest-home
		for step: int in range(1,30,2):
			var t:=float(step)/30;var u:=float(step+1)/30
			draw_line(world_to_screen(home+delta*t+Vector2(0,sin(t*PI)*35)),world_to_screen(home+delta*u+Vector2(0,sin(u*PI)*35)),Color(.96,.85,.57,.5),1.4,true)
	_draw_land_overlay()
	if show_player:
		var p:=world_to_screen(ORIGINS[town_id]+marker/73.0*TOWN_SIZE)
		draw_circle(p,9,Color("263e40"));draw_circle(p,6,Color("fff3ad"));draw_arc(p,12,0,TAU,24,Color("ffe298"),1.5,true)
		_text(p+Vector2(13,5),"你在这里",14)
	draw_rect(Rect2(0,0,size.x,68),Color(.08,.16,.18,.88))
	_text(Vector2(20,30),heading,24)
	_text(Vector2(20,54),controls_hint,15)
	_text(Vector2(size.x-124,30),"N  ↑",20)
	_text(Vector2(size.x-124,53),"%d%%"%roundi(zoom*100),15)
	draw_rect(Rect2(0,size.y-36,size.x,36),Color(.08,.16,.18,.88))
	_text(Vector2(14,size.y-12),caption_text(),14)

func caption_text() -> String:
	return str(TDTravelCatalog.info(_hover if not _hover.is_empty() else town_id).caption)

func _draw_land_overlay() -> void:
	pass

func cell_to_screen(id: String, cell: Vector2) -> Vector2:
	return world_to_screen(ORIGINS[id]+cell*TOWN_SIZE/float(maps[id].extent))

func _port_point(id: String) -> Vector2:
	return ORIGINS[id]+Vector2(TDTravelCatalog.port(id))/73.0*TOWN_SIZE

func _draw_town(id: String, origin: Vector2) -> void:
	var map: TDTownMap=maps[id];var unit: float=TOWN_SIZE/73.0
	for plot: Dictionary in map.plots:
		if plot.get("economic_courtyard",false) or plot.get("kind")=="diner_lot": continue
		var at:=origin+Vector2(plot.x,plot.y)*unit
		var rect:=Rect2(world_to_screen(at),Vector2(plot.w,plot.h)*unit*scale_factor())
		var color:=Color("d6ab66") if plot.has("branch_id") else Color("ddcfad")
		if zoom>=2.4:
			draw_rect(rect.grow(1),Color(.1,.2,.15,.35));draw_rect(rect,Color(color,.45))
		if str(plot.kind) not in ["housing","factory_lot"] and float(plot.w)>=3:
			var tex: Texture2D=TDTownArt.sprite(0) if id=="chengdu" else TDTravelCatalog.sprite(id,2 if plot.kind=="plaza" else (1 if plot.kind in ["urban_village","rich_district"] else 0))
			var width:=30.0*scale_factor();var span:=Vector2(width,width*tex.get_height()/tex.get_width())
			draw_texture_rect(tex,Rect2(rect.get_center()-span*.5,span),false)
		if zoom>=1.8 and plot.kind in ["market","plaza","bank","player_diner","cottage"]:
			_text(rect.position+Vector2(0,-4),TDTravelCatalog.label(plot,id),13)
	var port:=world_to_screen(_port_point(id));draw_circle(port,4,Color("81d6e6"))
	if zoom>=1.8: _text(port+Vector2(7,-4),"港口" if id!="mexico_city" else "港站",13)
	var label:=world_to_screen(origin+Vector2(0,-14))
	_text(label,str(TDTravelCatalog.info(id).name),18 if id==town_id else 16,Color("ffdc8c") if id==town_id else Color("f5e4bb"))
