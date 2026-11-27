class_name TDTravelMapView
extends Control
## A single atlas canvas. Navigation changes only the camera, never the player or clock.
# Chart frame in the original illustration, enclosing the three passenger ports.
const ATLAS_SIZE := Vector2(1460,900)
const CHART_ORIGIN := Vector2(415,0)
const WORLD_SIZE := Vector2(1045,510)
const BACKGROUND: Texture2D=preload("res://assets/town/world-atlas-v1.png")
const TOWN_SIZE:=220.0
const ORIGINS:={"paris":Vector2(430,120)-CHART_ORIGIN,"chengdu":Vector2(800,280)-CHART_ORIGIN,"tokyo":Vector2(1175,170)-CHART_ORIGIN}
# The chart illustration and the local survey use different coordinates.
const PALACE_CHART_POINT := Vector2(1075,307) - CHART_ORIGIN
const PALACE_LOCAL_POINT := Vector2(1611,247) / TDPlannedTown.REFERENCE_SIZE.x
const SEA:=Color("137c7b")
const FOG_REGIONS := {"paris":Rect2(-52,-18,470,380), "tokyo":Rect2(665,12,452,458)}
const JiangnanDistrictTerrain := preload("res://src/town/jiangnan_district_terrain.gd")
const CrowdStands := preload("res://src/town/crowd_stands.gd")
static var _fog_texture: ImageTexture
var maps: Dictionary={}
var town_id: String="chengdu"
var marker:=Vector2(TDHarbor.ARRIVAL)+Vector2.ONE*.5
var zoom: float=1.0
var max_zoom: float=5.0
var minimum_view_size:=Vector2(1080,520)
var heading: String="三镇航海图"
var controls_hint: String="滚轮缩放 · 按住拖动 · 双击小镇放大 · M / Esc 返回"
var show_player: bool=true
var pan:=Vector2.ZERO
var _dragging: bool=false
var _textures: Dictionary={}
var _jiangnan_zones: Array[Dictionary] = []
var _hover: String=""
var _map_minute := 720.0
var _locked_towns: Array[String] = []
var _revealing_town := ""
var _reveal_fog := 0.0
var challenge_towns: Array[String] = []
var live_challenge_locations: Dictionary = {}
var tracked_paris_site := ""

func configure(profile: TDGameProfile) -> void:
	if profile.characters!=null: _map_minute=profile.characters.clock.minute
	for id: String in TDTravelCatalog.IDS:
		if profile.town_map_unlocked(id):
			maps[id]=TDTravelCatalog.map_for(profile,id)
		else: _locked_towns.append(id)
	if show_player:
		for id: String in maps:
			if id != "chengdu" or maps.has("paris"): challenge_towns.append(id)

func reveal_story_town(id: String) -> void:
	if not is_inside_tree() or is_queued_for_deletion() or not maps.has(id) or not FOG_REGIONS.has(id): return
	_revealing_town=id
	_reveal_fog=1.0
	reset_view()
	var reveal := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	reveal.tween_method(_set_reveal_fog,1.0,0.0,.8)
	reveal.tween_method(_zoom_to_reveal.bind(id),0.0,1.0,.75).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	reveal.tween_callback(func() -> void: _revealing_town="";queue_redraw())

func _set_reveal_fog(value: float) -> void:
	_reveal_fog=value
	queue_redraw()

func _zoom_to_reveal(value: float, id: String) -> void:
	zoom=lerpf(1.0,3.0,value)
	pan=Vector2.ZERO.lerp(_town_focus_pan(id),value)
	queue_redraw()

func challenge_locations(id: String) -> Dictionary:
	if not maps.has(id): return {}
	if id == town_id and live_challenge_locations.has(id): return live_challenge_locations[id]
	if id not in challenge_towns: return {}
	if live_challenge_locations.has(id): return live_challenge_locations[id]
	var locations := {}
	for site: String in CrowdStands.VISITS.get(id,[]):
		var place: Dictionary=maps[id]._by_id(site)
		if not place.is_empty():
			locations[site]=Vector2(float(place.approach_x),float(place.approach_y))+Vector2.ONE*.5
	return locations

func _ready() -> void:
	custom_minimum_size=minimum_view_size;mouse_filter=Control.MOUSE_FILTER_STOP;clip_contents=true
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	for id: String in maps:
		var overview: SubViewport
		if TDPlannedTown.approved(maps[id]):
			overview = TDJiangnanReferenceArt.make_overview()
		elif maps[id].shiomi or maps[id].egret:
			overview=TDEgretLayout.overview() if maps[id].egret else TDShiomiArt.overview()
		else:
			_textures[id]=_terrain_texture(maps[id],id)
			continue
		add_child(overview)
		var scene := overview.get_child(0) as Node2D
		scene.modulate = TDDaylight.sample(_map_minute).tint
		scene.get_node("Atmosphere").set_minute(_map_minute)
		if scene.has_node("Weather"): scene.get_node("Weather").set_minute(_map_minute)
		if scene.has_node("SunShadows"): scene.get_node("SunShadows").set_day_minute(_map_minute)
		_textures[id]=overview.get_texture()
	if maps.has("chengdu"): _jiangnan_zones = TDPlannedTown.panorama_zones(maps.chengdu)
	resized.connect(queue_redraw)
	queue_redraw()

func scale_factor() -> float:
	return minf(size.x/WORLD_SIZE.x,size.y/WORLD_SIZE.y)*zoom

func world_to_screen(point: Vector2) -> Vector2:
	return size*.5+pan+(point-WORLD_SIZE*.5)*scale_factor()

func screen_to_world(point: Vector2) -> Vector2:
	return (point-size*.5-pan)/scale_factor()+WORLD_SIZE*.5

func zoom_at(point: Vector2, factor: float) -> void:
	if scale_factor() <= 0.0: return
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
	if not maps.has(id): return
	zoom=3.0
	pan=_town_focus_pan(id)
	queue_redraw()

func _town_focus_pan(id: String) -> Vector2:
	var center := Vector2.ONE*.5
	var terrain: Texture2D = _textures.get(id)
	if terrain!=null: center.y /= terrain.get_size().aspect()
	return -(ORIGINS[id]+center*TOWN_SIZE-WORLD_SIZE*.5)*scale_factor()

func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_WINDOW_FOCUS_OUT: _dragging=false

func _gui_input(event: InputEvent) -> void:
	if not _revealing_town.is_empty(): accept_event();return
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
	var ground := TDTownScenery.smooth_surfaces(map)
	for y: int in map.extent:
		for x: int in map.extent:
			var surface: String=ground[Vector2i(x,y)]
			var color:=Color(style.grass)
			if surface=="water": color=SEA.lightened(.08)
			elif surface=="stone": color=Color(style.road).lightened(.08)
			elif surface=="civic_paving": color=Color(TDTownScenery.PublicSquare.PALETTES[id][1])
			elif surface=="bridge": color=Color("c4a071")
			elif surface=="woodland": color=Color(style.leaf).darkened(.2)
			var n:=TDTownScenery.noise(x,y)
			color=color.lightened(float(n%5)*.012)
			# Fine overlays are generated from live geography; the illustration owns scenery.
			color.a=.90 if surface in ["civic_paving","bridge"] else (.68 if surface=="stone" else .53)
			image.fill_rect(Rect2i(x*6,y*6,6,6),color)
			if surface=="stone": image.fill_rect(Rect2i(x*6,y*6+5,6,1),color.darkened(.13))
			elif surface=="bridge":
				for d: Vector2i in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:
					if ground.get(Vector2i(x,y)+d,"water")=="water":
						var edge := Vector2i(x*6,y*6)+Vector2i(maxi(d.x,0),maxi(d.y,0))*5
						image.fill_rect(Rect2i(edge,Vector2i(6,1) if d.y!=0 else Vector2i(1,6)),Color("705f52"))
			elif surface=="woodland": image.fill_rect(Rect2i(x*6+1,y*6+1,3,3),color.lightened(.16))
			elif surface=="water" and n%5==0: image.fill_rect(Rect2i(x*6+1,y*6+2,4,1),color.lightened(.16))
	if id=="chengdu" and show_player: JiangnanDistrictTerrain.paint(image,map,6,true)
	return ImageTexture.create_from_image(image)

func _polygon(points: Array, color: Color) -> void:
	var vertices:=PackedVector2Array()
	for point: Vector2 in points: vertices.append(world_to_screen(point))
	draw_colored_polygon(vertices,color)
	vertices.append(vertices[0]);draw_polyline(vertices,Color("b8b48a"),2,true)

func _text(at: Vector2, value: String, font_size: int=TDUI.FONT_CAPTION, color: Color=Color("f5e4bb")) -> void:
	var font:=get_theme_default_font()
	draw_string_outline(font,at,value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,4,Color("233c3d"))
	draw_string(font,at,value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)

func focused_town() -> String:
	if zoom < 2.4: return ""
	for id: String in maps:
		if Rect2(ORIGINS[id],Vector2.ONE*TOWN_SIZE).has_point(screen_to_world(size*.5)): return id
	return ""

func _draw() -> void:
	var local_id := focused_town()
	var local_island: bool=maps.has("tokyo") and maps.tokyo.shiomi and zoom>=3.0 and Rect2(ORIGINS.tokyo,Vector2.ONE*TOWN_SIZE).has_point(screen_to_world(size*.5))
	draw_rect(Rect2(Vector2.ZERO,size),Color("075968") if local_island else SEA)
	if local_id.is_empty():
		var texels := BACKGROUND.get_size() / ATLAS_SIZE
		draw_texture_rect_region(BACKGROUND,Rect2(world_to_screen(Vector2.ZERO),WORLD_SIZE*scale_factor()),Rect2(CHART_ORIGIN*texels,WORLD_SIZE*texels))
	for id: String in maps:
		if id != local_id: continue
		var origin: Vector2=ORIGINS[id];var rect:=Rect2(world_to_screen(origin),Vector2.ONE*TOWN_SIZE*scale_factor())
		var terrain: Texture2D = _textures[id]
		rect.size.y = rect.size.x/terrain.get_size().aspect()
		var opacity := 1.0 if TDPlannedTown.approved(maps[id]) or maps[id].shiomi or maps[id].egret else clampf((zoom-1)*.6,.25,1)
		draw_texture_rect(terrain,rect,false,Color(1,1,1,opacity))
		_draw_town(id,origin)
	# Passenger routes are independent of economic route unlocks.
	var home:=_port_point("chengdu")
	for id: String in maps:
		if not local_id.is_empty() or id=="chengdu" or (id==_revealing_town and _reveal_fog>0.0): continue
		var dest:=_port_point(id);var delta:=dest-home
		for step: int in range(1,30,2):
			var t:=float(step)/30;var u:=float(step+1)/30
			draw_line(world_to_screen(home+delta*t+Vector2(0,sin(t*PI)*35)),world_to_screen(home+delta*u+Vector2(0,sin(u*PI)*35)),Color(.96,.85,.57,.5),1.4,true)
	_draw_land_overlay()
	if local_id.is_empty():
		for id: String in _locked_towns: _draw_fog(id,1.0)
		if _reveal_fog>0.0: _draw_fog(_revealing_town,_reveal_fog)
		for id: String in maps:
			if id != _revealing_town or _reveal_fog <= 0.0: _draw_town(id,ORIGINS[id])
	if show_player: _draw_challenge_markers(local_id)
	if show_player and maps.has("chengdu") and local_id in ["","chengdu"]:
		_draw_palace_marker(local_id.is_empty())
	if show_player and maps.has(town_id) and (local_id.is_empty() or local_id == town_id):
		var p:=world_to_screen(ORIGINS[town_id]+marker/73.0*TOWN_SIZE)
		draw_circle(p,9,Color("263e40"));draw_circle(p,6,Color("fff3ad"));draw_arc(p,12,0,TAU,24,Color("ffe298"),1.5,true)
		_text(p+Vector2(13,5),"你在这里",TDUI.FONT_CAPTION)
	draw_rect(Rect2(0,0,size.x,68),Color(.08,.16,.18,.88))
	_text(Vector2(20,30),heading,TDUI.FONT_SECTION)
	_text(Vector2(20,54),controls_hint,TDUI.FONT_CAPTION)
	_text(Vector2(size.x-124,30),"N  ↑",TDUI.FONT_BODY)
	_text(Vector2(size.x-124,53),"%d%%"%roundi(zoom*100),TDUI.FONT_CAPTION)
	draw_rect(Rect2(0,size.y-36,size.x,36),Color(.08,.16,.18,.88))
	_text(Vector2(14,size.y-12),caption_text(),TDUI.FONT_CAPTION)

func caption_text() -> String:
	if _hover in _locked_towns: return "随主线开放"
	var viewed := focused_town()
	if viewed.is_empty(): viewed=_hover if not _hover.is_empty() else town_id
	return str(TDTravelCatalog.info(viewed).caption)

func _draw_fog(id: String, opacity: float) -> void:
	if _fog_texture == null: _fog_texture=_make_fog_texture()
	var region: Rect2=FOG_REGIONS[id]
	var rect:=Rect2(world_to_screen(region.position),region.size*scale_factor())
	draw_texture_rect(_fog_texture,rect,false,Color(1,1,1,opacity))
	var label := "迷雾未散"
	var width := get_theme_default_font().get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,TDUI.FONT_BODY).x
	_text(rect.get_center()+Vector2(-width*.5,0),label,TDUI.FONT_BODY,Color(1,1,1,opacity))

static func _make_fog_texture() -> ImageTexture:
	var bitmap := Image.create(128,112,false,Image.FORMAT_RGBA8)
	var clouds := FastNoiseLite.new()
	clouds.seed=1505
	clouds.frequency=.09
	for y: int in bitmap.get_height():
		for x: int in bitmap.get_width():
			var pos := (Vector2(x,y)+Vector2.ONE*.5)/Vector2(bitmap.get_size())*2.0-Vector2.ONE
			var cloud := clouds.get_noise_2d(x,y)
			var edge := pow(pow(absf(pos.x),4.0)+pow(absf(pos.y),4.0),.25)+cloud*.08
			var alpha := 1.0-smoothstep(.84,1.01,edge)
			var color := Color("789ca1").lerp(Color("c5d9d5"),clampf(.48+cloud*.85,0.0,1.0))
			bitmap.set_pixel(x,y,Color(color,alpha))
	return ImageTexture.create_from_image(bitmap)

func _draw_land_overlay() -> void:
	pass

func _draw_challenge_markers(local_id: String) -> void:
	if local_id.is_empty():
		for id: String in challenge_towns:
			if id==_revealing_town and _reveal_fog>0.0: continue
			var tracked := id=="paris" and not tracked_paris_site.is_empty()
			_draw_challenge_marker(world_to_screen(ORIGINS[id]+Vector2(12,10)),false,tracked)
		return
	var pins := PackedVector2Array()
	var locations := challenge_locations(local_id)
	for feet: Vector2 in locations.values(): pins.append(cell_to_screen(local_id,feet))
	var tracked := Vector2.INF
	if local_id=="paris" and locations.has(tracked_paris_site):
		tracked=cell_to_screen(local_id,locations[tracked_paris_site])
	for pin: Vector2 in pins:
		var left := false
		for other: Vector2 in pins:
			if other.x > pin.x and other.x - pin.x < 108 and absf(other.y-pin.y)<24:
				left=true;break
		_draw_challenge_marker(pin,left,pin==tracked)

func _draw_challenge_marker(pin: Vector2, left: bool = false, tracked: bool = false) -> void:
	draw_circle(pin,7,Color("263e40"))
	draw_circle(pin,4,Color("ffd08a"))
	if tracked: draw_arc(pin,10,0,TAU,24,Color("fff0a4"),2,true)
	var label := "任务 · 居民挑战" if tracked else "杂鱼挑战"
	var width:=get_theme_default_font().get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,TDUI.FONT_CAPTION).x
	_text(pin+Vector2(-width-10 if left else 10,-4),label,TDUI.FONT_CAPTION,Color("ffd08a"))

func _draw_palace_marker(world_chart: bool) -> void:
	var anchor := PALACE_CHART_POINT if world_chart else ORIGINS.chengdu + PALACE_LOCAL_POINT * TOWN_SIZE
	var pin := world_to_screen(anchor).round()
	var ink := Color("233c3d")
	var gold := Color("ffdd91")
	draw_circle(pin, 14, ink, true, -1, true)
	draw_arc(pin, 13.5, 0, TAU, 32, gold, 1.5, true)
	draw_colored_polygon(PackedVector2Array([
		pin + Vector2(-9, -1), pin + Vector2(0, -8), pin + Vector2(9, -1),
	]), gold)
	draw_rect(Rect2(pin + Vector2(-6, 1), Vector2(4, 6)), gold)
	draw_rect(Rect2(pin + Vector2(2, 1), Vector2(4, 6)), gold)

	var label := "王宫"
	var font := get_theme_default_font()
	var span := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, TDUI.FONT_CAPTION) + Vector2(14, 4)
	var offset_x := 18.0 if world_chart else -span.x - 18
	var box := Rect2(pin + Vector2(offset_x, -span.y * .5), span)
	draw_rect(box, ink)
	draw_rect(box, gold, false, 1)
	_text(box.position + Vector2(7, 2 + font.get_ascent(TDUI.FONT_CAPTION)), label, TDUI.FONT_CAPTION, gold)

func cell_to_screen(id: String, cell: Vector2) -> Vector2:
	return world_to_screen(ORIGINS[id]+cell*TOWN_SIZE/float(maps[id].extent))

func _port_point(id: String) -> Vector2:
	var point := Vector2(TDTravelCatalog.port(id))
	if id=="paris": point+=Vector2.ONE*.5
	return ORIGINS[id]+point/73.0*TOWN_SIZE

func _draw_town(id: String, origin: Vector2) -> void:
	# At world scale the redrawn chart owns the towns; never paste live rectangles over it.
	if focused_town().is_empty():
		var title_at := world_to_screen(origin+Vector2(0,-14))
		_text(title_at,str(TDTravelCatalog.info(id).name),18 if id==town_id else 16,Color("ffdc8c") if id==town_id else Color("f5e4bb"))
		return
	var map: TDTownMap=maps[id];var unit: float=TOWN_SIZE/73.0
	var reference := TDPlannedTown.approved(map) or map.shiomi or map.egret
	var show_neighborhoods := id=="chengdu" and show_player and zoom>=3.0 and not _jiangnan_zones.is_empty()
	for plot: Dictionary in map.plots:
		if plot.get("economic_courtyard",false) or plot.get("kind")=="diner_lot": continue
		var overlay := plot.has("branch_id") or ((map.shiomi or map.egret) and plot.has("economic_parcel_id"))
		if reference and not overlay and plot.kind != "player_cottage":
			if (map.shiomi or map.egret) and show_player and zoom>=3.5 and plot.kind in ["hotel","bank","plaza","market","landmark"]:
				_text(cell_to_screen(id,Vector2(plot.approach_x,plot.approach_y)),TDTravelCatalog.label(plot,id),TDUI.FONT_MICRO)
			continue
		var at:=origin+Vector2(plot.x,plot.y)*unit
		var rect:=Rect2(world_to_screen(at),Vector2(plot.w,plot.h)*unit*scale_factor())
		var color:=Color("d6ab66") if plot.has("branch_id") else Color("ddcfad")
		if zoom>=2.4 and (overlay or not reference) and not TDTownArt.Yard.is_residential(plot.kind):
			draw_rect(rect.grow(1),Color(.1,.2,.15,.35));draw_rect(rect,Color(color,.45))
		if str(plot.kind) not in ["housing","factory_lot"] and float(plot.w)>=3 and (not reference or overlay):
			var tex := TDTravelCatalog.facade(id,plot)
			if plot.get("preset_storefront", false) and not plot.get("construction", false):
				var diner_bounds: Rect2 = TDJiangnanReferenceArt.diner_facade().rect
				var cell := TDEgretLayout.WALK_CELL if map.egret else float(TDTownWorld.CELL)
				var span := diner_bounds.size * (unit * scale_factor() / cell)
				var feet := cell_to_screen(id, TDTravelCatalog.native_frontage_feet(TDInteractionRange.plot_bounds(plot)))
				draw_texture_rect(tex, Rect2(feet - Vector2(span.x * .5, span.y), span), false)
			else:
				var width:=clampf(float(plot.w)*unit,8,24)*scale_factor();var span:=Vector2(width,width*tex.get_height()/tex.get_width())
				draw_texture_rect(tex,Rect2(rect.get_center()-span*.5,span),false)
		if zoom>=2.4 and plot.kind in ["hotel","landmark","market","plaza","bank","player_diner","player_cottage"]:
			if not show_neighborhoods or plot.kind=="player_cottage" or plot.has("branch_id"):
				_text(rect.position+Vector2(0,-4),TDTravelCatalog.label(plot,id),TDUI.FONT_CAPTION)
	var port:=world_to_screen(_port_point(id));draw_circle(port,4,Color("81d6e6"))
	if zoom>=2.4 and map.layout_version==2 and not reference:
		for parcel_id: String in TDTownArt.StreetPlaces.VENUES.get(id,{}):
			var plot := map._by_id(parcel_id)
			var venue := TDTownArt.StreetPlaces.venue(id,plot,TDTownWorld.CELL,Vector2.ZERO)
			if venue.is_empty(): continue
			var rect: Rect2 = venue.rect
			var feet := Vector2(rect.get_center().x,rect.end.y)/TDTownWorld.CELL
			var point := world_to_screen(origin+feet*unit)
			var span := rect.size/rect.size.y*clampf(zoom*5,14,28)
			draw_texture_rect(venue.art,Rect2(point-Vector2(span.x*.5,span.y),span),false)
			if zoom>=3.5: _text(point+Vector2(8,12),venue.place_name,TDUI.FONT_CAPTION)
	if show_neighborhoods:
		_draw_jiangnan_zones(id)
	if zoom>=1.8: _text(port+Vector2(7,-4),"港口",TDUI.FONT_CAPTION)
	var label:=world_to_screen(origin+Vector2(0,-14))
	_text(label,str(TDTravelCatalog.info(id).name),18 if id==town_id else 16,Color("ffdc8c") if id==town_id else Color("f5e4bb"))

func _draw_jiangnan_zones(id: String) -> void:
	var font := get_theme_default_font()
	var placed: Array[Rect2] = []
	for zone: Dictionary in _jiangnan_zones:
		var pin := cell_to_screen(id,zone.at)
		var text_size := font.get_string_size(zone.label,HORIZONTAL_ALIGNMENT_LEFT,-1,TDUI.FONT_MICRO)
		var box := Rect2(pin+Vector2(7,3),text_size+Vector2(6,3))
		for dy: int in [3,-22,22,-40,40]:
			box.position.y = pin.y + dy
			if not placed.any(func(existing: Rect2)->bool: return existing.intersects(box)): break
		placed.append(box)
		var edge := TDInteractionRange.closest(pin,box)
		draw_line(pin,edge,Color("e3c78b"),1)
		draw_circle(pin,3,Color("f9d99b"))
		draw_rect(box,Color("263b34df"))
		_text(box.position+Vector2(3,font.get_ascent(TDUI.FONT_MICRO)),zone.label,TDUI.FONT_MICRO)
