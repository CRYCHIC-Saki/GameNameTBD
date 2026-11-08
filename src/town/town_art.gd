class_name TDTownArt
extends RefCounted

static func sprite(index: int) -> AtlasTexture:
	return TDEnvironmentArt.sprite(index,true)

static func ground(map: TDTownMap) -> ImageTexture:
	return TDTownScenery.ground(map)

static func prop(canvas: CanvasItem,index: int,feet: Vector2,width: float) -> void:
	TDTownScenery.shadow(canvas,feet,width)
	TDEnvironmentArt.draw_prop(canvas,index,feet,width,true)

static var _housing_key: String=""
static var _housing: Array[Dictionary]=[]
static func housing_groups(map: TDTownMap) -> Array[Dictionary]:
	var key: String="%d:%d:%d"%[map.layout_version,map.plots.hash(),map.cottage.hash()]
	if key==_housing_key: return _housing.duplicate(true)
	_housing_key=key;_housing=[]
	var available:=map._home_cells()
	if not map.cottage.is_empty():
		for y: int in range(int(map.cottage.y),int(map.cottage.y)+2):
			for x: int in range(int(map.cottage.x),int(map.cottage.x)+2): available.erase(Vector2i(x,y))
	var cells: Array=available.keys()
	cells.sort_custom(func(a:Vector2i,b:Vector2i)->bool:return a.y<b.y or (a.y==b.y and a.x<b.x))
	var painted: Dictionary={}
	for at: Vector2i in cells:
		if painted.has(at): continue
		var size: int=1
		for n: int in [3,2]:
			var fits: bool=true
			for dy: int in n:
				for dx: int in n:
					var q:=at+Vector2i(dx,dy)
					if not available.has(q) or painted.has(q): fits=false
			if fits: size=n;break
		for dy: int in size:
			for dx: int in size: painted[at+Vector2i(dx,dy)]=true
		_housing.append({"at":at,"size":size})
	return _housing.duplicate(true)

static func _draw_housing(canvas: CanvasItem,map: TDTownMap,origin: Vector2,cell: float) -> void:
	var groups:=housing_groups(map)
	for group: Dictionary in groups:
		var rect:=Rect2(origin+Vector2(group.at)*cell,Vector2.ONE*int(group["size"])*cell)
		if int(group["size"])==1:
			# Occupied remnants are tiled outbuildings, not walkable-looking grass or giant blank walls.
			canvas.draw_rect(rect,Color("a49a7a"))
			canvas.draw_rect(Rect2(rect.position,Vector2(cell,cell-12)),Color("39494c"))
			for y: int in range(2,int(cell)-12,6):
				for x: int in range(0,int(cell),8):
					canvas.draw_rect(Rect2(rect.position+Vector2(x+1,y),Vector2(6,3)),Color("607476"))
			canvas.draw_rect(Rect2(rect.position+Vector2(0,cell-14),Vector2(cell,4)),Color("293b3f"))
			canvas.draw_rect(Rect2(rect.position+Vector2(5,cell-10),Vector2(10,7)),Color("625840"))
			canvas.draw_rect(Rect2(rect.position+Vector2(cell-14,cell-8),Vector2(8,4)),Color("776e54"))
		else:
			TDTownScenery.fence(canvas,rect.grow(-2))
			TDTownScenery.shadow(canvas,Vector2(rect.get_center().x,rect.end.y),rect.size.x-6)
			TDEnvironmentArt.draw_residential(canvas,1 if int(group["size"])==3 else 0,rect.grow(-3))
			if canvas.get("day_minute")!=null: TDDaylight.glow(canvas,rect.position+Vector2(rect.size.x*.45,rect.size.y*.82),float(TDDaylight.sample(float(canvas.get("day_minute"))).lamps),24)
	if map.layout_version==2 and not groups.is_empty():
		var bounds:=Rect2(Vector2(groups[0].at),Vector2.ONE*groups[0]["size"])
		for group: Dictionary in groups: bounds=bounds.merge(Rect2(Vector2(group.at),Vector2.ONE*group["size"]))
		var center:=origin+Vector2(bounds.get_center().x,bounds.position.y-.7)*cell
		var plate:=Rect2(center-Vector2(112,18),Vector2(224,34))
		canvas.draw_style_box(_label_style(true),plate)
		canvas.draw_string(ThemeDB.fallback_font,plate.position+Vector2(10,24),"青瓦巷 · 居民区",HORIZONTAL_ALIGNMENT_CENTER,204,22,Color("fff1cd"))

static func draw_world(canvas: Node2D, session: TDPhase3Session, selected: Dictionary) -> void:
	var map:=session.town_map;var origin:=Vector2(300,24);var cell: float=TDTownWorld.CELL
	canvas.draw_texture_rect(ground(map),Rect2(origin,Vector2.ONE*map.extent*cell),false)
	TDTownScenery.draw_wilds(canvas,origin,cell)
	TDTownScenery.draw_dressing(canvas,map,origin,cell)
	var plots: Array=map.plots.duplicate()
	plots.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return int(a.y+a.h)<int(b.y+b.h) or (int(a.y+a.h)==int(b.y+b.h) and int(a.x)<int(b.x)))
	_draw_housing(canvas,map,origin,cell)
	for p: Dictionary in plots:
		var rect:=TDInteractionRange.plot_bounds(p,cell,origin)
		var feet:=rect.position+Vector2(rect.size.x*.5,rect.size.y)
		var kind: String=str(p.kind)
		if p.get("economic_courtyard",false) or kind=="diner_lot": continue
		if kind=="housing": continue
		var index: int={"player_diner":0,"player_cottage":1,"market":2,"competitor":4,"supply_factory":5,"factory_lot":12,"plaza":7,"rich_district":1,"urban_village":4,"landmark":7,"zoo":6,"amusement":10,"snack_street":13,"bank":8,"station":9}.get(kind,4)
		var width: float=minf(rect.size.x,rect.size.y*1.3)
		# Chen lives behind this shop door; other markets remain open stalls.
		if p.get("id","")=="market-small": index=1
		if p.get("construction",false): index=12
		if kind in ["urban_village","rich_district"]:
			TDTownScenery.fence(canvas,rect.grow(-2))
			TDTownScenery.shadow(canvas,feet,rect.size.x-6)
			TDEnvironmentArt.draw_residential(canvas,2 if kind=="urban_village" else 3,rect.grow(-3))
		elif kind in ["plaza","amusement","zoo"]:
			TDTownScenery.fence(canvas,rect.grow(-3))
			prop(canvas,3,rect.position+Vector2(rect.size.x*.25,rect.size.y*.65),minf(190,rect.size.x*.43))
			prop(canvas,6,rect.position+Vector2(rect.size.x*.80,rect.size.y*.57),minf(130,rect.size.x*.30))
			prop(canvas,index,rect.position+Vector2(rect.size.x*.60,rect.size.y-8),minf(240,rect.size.x*.54))
			prop(canvas,11,rect.position+Vector2(26,rect.size.y-4),42)
			TDTownScenery.pots(canvas,rect)
		elif kind=="supply_factory" or kind=="factory_lot":
			TDTownScenery.shadow(canvas,feet,width)
			TDEnvironmentArt.draw_factory(canvas,str(p.get("supply","")),feet,width,kind=="factory_lot")
			TDTownScenery.pots(canvas,rect)
		elif kind in ["market","snack_street"] and rect.size.x>=240:
			TDTownScenery.fence(canvas,rect.grow(-3))
			prop(canvas,6,rect.position+Vector2(rect.size.x-55,75),100)
			var count: int=3 if rect.size.x>=400 else 2
			for i: int in count:
				var w: float=rect.size.x/count
				prop(canvas,index,rect.position+Vector2(w*(i+.5),rect.size.y-3),w*.94)
		else:
			if rect.size.y>rect.size.x*1.25:
				TDTownScenery.fence(canvas,rect.grow(-3))
				prop(canvas,3,rect.position+Vector2(rect.size.x*.28,rect.size.y-width*.65),width*.48)
				prop(canvas,6,rect.position+Vector2(rect.size.x*.79,rect.size.y-width*.55),width*.36)
			if kind=="player_diner" and not p.get("construction",false):
				TDTownScenery.shadow(canvas,feet,width)
				TDEnvironmentArt.draw_diner(canvas,feet,width)
			else:
				prop(canvas,index,feet,width)
			TDTownScenery.pots(canvas,rect)
		var active: bool=str(selected.get("id",""))==str(p.id)
		var label: String="小镇食堂" if p.id=="player_diner" else str(p.name)
		if kind in ["urban_village","rich_district"]: label+=" · 居民院落"
		var text_width: float=ThemeDB.fallback_font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x
		var plate:=Rect2(feet+Vector2(-text_width*.5-7,5),Vector2(text_width+14,22))
		canvas.draw_style_box(_label_style(active),plate)
		canvas.draw_string(ThemeDB.fallback_font,plate.position+Vector2(7,16),label,HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("fff1cd"))
		if active:
			var at: Vector2=selected.get("interaction_point",feet)
			canvas.draw_circle(at,14,Color("554b39"));canvas.draw_arc(at,15,0,TAU,24,Color("f4d789"),2)
			canvas.draw_string(ThemeDB.fallback_font,at+Vector2(-5,5),"E",HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("fff0c4"))
		if canvas.get("day_minute")!=null: TDDaylight.glow(canvas,feet+Vector2(-width*.3,-width*.35),float(TDDaylight.sample(float(canvas.get("day_minute"))).lamps),30)

static var _labels: Dictionary={}
static func _label_style(active: bool) -> StyleBoxFlat:
	if not _labels.has(active):
		var style:=StyleBoxFlat.new();style.bg_color=Color("6a503cdd") if active else Color("424b3a99")
		style.set_corner_radius_all(3);_labels[active]=style
	return _labels[active]
