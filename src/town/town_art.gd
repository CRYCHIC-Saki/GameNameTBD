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

static func facade_plot(map: TDTownMap,plot: Dictionary,cell: float=48.0,origin: Vector2=Vector2.ZERO) -> Rect2:
	var rect:=TDInteractionRange.plot_bounds(plot,cell,origin)
	if plot.get("id","")=="market-small" and map.layout_version==2 and map.region_id.is_empty():
		# The small shop can use its clear side margins and half a cell of its
		# existing entrance apron, still within the original interaction reach.
		return Rect2(rect.position-Vector2(cell*.5,0),rect.size+Vector2(cell,cell*.5))
	if plot.get("id","")=="player_cottage" and map.layout_version==2:
		# The cottage occupies the remaining residential court, not a tiny 2x2
		# corner surrounded by five duplicated pots. Ownership stays unchanged.
		for block: Array in TDPlannedTown.definition().housing_blocks:
			var court:=Rect2(float(block[0]),float(block[1]),float(block[2]),float(block[3]))
			if court.encloses(TDInteractionRange.plot_bounds(plot)):
				var occupied: bool=false
				for other: Dictionary in map.plots:
					if other.get("kind","") in ["housing","player_cottage"]: continue
					if court.intersects(TDInteractionRange.plot_bounds(other)): occupied=true;break
				if occupied: continue
				return Rect2(origin+court.position*cell,court.size*cell)
	# Authored courts sometimes stop one grass row before the street. Include
	# that vacant frontage in presentation so steps do not float in the middle.
	var bottom: int=int(plot.y+plot.h)
	for step: int in 2:
		var vacant: bool=true
		for x: int in range(int(plot.x),int(plot.x+plot.w)):
			var at:=Vector2i(x,bottom+step)
			if not map.plot_at(at.x,at.y).is_empty() or str(map.terrain_at(at).surface_type)!="grass": vacant=false;break
		if not vacant: break
		rect.size.y+=cell
	return rect

static func housing_groups(map: TDTownMap) -> Array[Dictionary]:
	var key: String="%d:%d:%d"%[map.layout_version,map.plots.hash(),map.cottage.hash()]
	if key==_housing_key: return _housing.duplicate(true)
	_housing_key=key;_housing=[]
	var available:=map._home_cells()
	if not map.cottage.is_empty():
		var court:=facade_plot(map,map.cottage,1.0)
		for y: int in range(int(court.position.y),int(court.end.y)):
			for x: int in range(int(court.position.x),int(court.end.x)): available.erase(Vector2i(x,y))
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
		# Leftover occupied cells are small planted gardens, not legacy grey roofs.
		var texture: Texture2D=sprite(14) if int(group["size"])==1 else TDEnvironmentArt.residential(1 if int(group["size"])==3 else 0)
		var target:=TDEnvironmentArt.fit_in_plot(texture,rect,0)
		canvas.draw_texture_rect(texture,target,false)
	if map.layout_version==2 and not groups.is_empty():
		var bounds:=Rect2(Vector2(groups[0].at),Vector2.ONE*groups[0]["size"])
		for group: Dictionary in groups: bounds=bounds.merge(Rect2(Vector2(group.at),Vector2.ONE*group["size"]))
		if not map.cottage.is_empty(): bounds=bounds.merge(facade_plot(map,map.cottage,1.0))
		var center:=origin+Vector2(bounds.get_center().x,bounds.position.y-.7)*cell
		var plate:=Rect2(center-Vector2(112,18),Vector2(224,34))
		canvas.draw_style_box(_label_style(true),plate)
		canvas.draw_string(TDUI.font(),plate.position+Vector2(10,24),"青瓦巷 · 居民区",HORIZONTAL_ALIGNMENT_CENTER,204,TDUI.FONT_SECTION,Color("fff1cd"))

static func draw_world(canvas: Node2D, session: TDPhase3Session, selected: Dictionary, management_menus: bool=false) -> void:
	var map:=session.town_map;var origin:=Vector2(300,24);var cell: float=TDTownWorld.CELL
	canvas.draw_texture_rect(ground(map),Rect2(origin,Vector2.ONE*map.extent*cell),false)
	TDTownScenery.draw_wilds(canvas,origin,cell)
	TDTownScenery.draw_dressing(canvas,map,origin,cell)
	var plots: Array=map.plots.duplicate()
	plots.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return int(a.y+a.h)<int(b.y+b.h) or (int(a.y+a.h)==int(b.y+b.h) and int(a.x)<int(b.x)))
	_draw_housing(canvas,map,origin,cell)
	for p: Dictionary in plots:
		if management_menus and p.get("kind","") in ["factory_lot","supply_factory"]: continue
		var rect:=facade_plot(map,p,cell,origin)
		var feet:=rect.position+Vector2(rect.size.x*.5,rect.size.y)
		var kind: String=str(p.kind)
		if p.get("economic_courtyard",false) or kind=="diner_lot": continue
		if kind=="housing": continue
		var index: int={"player_diner":0,"player_cottage":1,"market":2,"competitor":4,"supply_factory":5,"factory_lot":12,"plaza":7,"rich_district":1,"urban_village":4,"landmark":7,"zoo":6,"amusement":10,"snack_street":13,"bank":8,"station":9}.get(kind,4)
		# Chen lives behind this shop door; other markets remain open stalls.
		if p.get("id","")=="market-small": index=1
		if p.get("construction",false): index=12
		var texture: Texture2D=sprite(index)
		if kind in ["urban_village","rich_district"]:
			texture=TDEnvironmentArt.residential(2 if kind=="urban_village" else 3)
		elif kind in ["supply_factory","factory_lot"]:
			texture=TDEnvironmentArt.factory(str(p.get("supply","")))
		elif kind=="player_diner" and not p.get("construction",false):
			texture=TDEnvironmentArt.diner()
		var target:=TDEnvironmentArt.fit_in_plot(texture,rect)
		if kind in ["market","snack_street"] and rect.size.x>=240:
			var count: int=3 if rect.size.x>=400 else 2
			for i: int in count:
				var slot:=Rect2(rect.position+Vector2(rect.size.x*i/count,0),Vector2(rect.size.x/count,rect.size.y))
				canvas.draw_texture_rect(texture,TDEnvironmentArt.fit_in_plot(texture,slot),false)
		else:
			var tint:=Color(.82,.84,.86) if kind=="factory_lot" else Color.WHITE
			canvas.draw_texture_rect(texture,target,false,tint)
		# Captions sit beyond the front of the facade; they must not shrink the building
		# or create an empty gap between its steps and the street.
		feet=Vector2(rect.get_center().x,target.end.y)
		var width: float=target.size.x
		var active: bool=str(selected.get("id",""))==str(p.id)
		var label: String="小镇食堂" if p.id=="player_diner" else str(p.name)
		if p.has("branch_id") and p.get("construction",false): label+=" · 施工至第%d天"%int(p.ready_day)
		if kind in ["urban_village","rich_district"]: label+=" · 居民院落"
		var text_width: float=TDUI.font().get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x
		var plate:=Rect2(feet+Vector2(-text_width*.5-7,5),Vector2(text_width+14,22))
		canvas.draw_style_box(_label_style(active),plate)
		canvas.draw_string(TDUI.font(),plate.position+Vector2(7,16),label,HORIZONTAL_ALIGNMENT_LEFT,-1,TDUI.FONT_CAPTION,Color("fff1cd"))
		if active:
			var at: Vector2=selected.get("interaction_point",feet)
			canvas.draw_circle(at,14,Color("554b39"));canvas.draw_arc(at,15,0,TAU,24,Color("f4d789"),2)
			canvas.draw_string(TDUI.font(),at+Vector2(-5,5),"E",HORIZONTAL_ALIGNMENT_LEFT,-1,TDUI.FONT_CAPTION,Color("fff0c4"))
		if canvas.get("day_minute")!=null: TDDaylight.glow(canvas,feet+Vector2(-width*.3,-width*.35),float(TDDaylight.sample(float(canvas.get("day_minute"))).lamps),30)

static var _labels: Dictionary={}
static func _label_style(active: bool) -> StyleBoxFlat:
	if not _labels.has(active):
		var style:=StyleBoxFlat.new();style.bg_color=Color("6a503cdd") if active else Color("424b3a99")
		style.set_corner_radius_all(3);_labels[active]=style
	return _labels[active]
