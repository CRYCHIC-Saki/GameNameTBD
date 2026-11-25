class_name TDTownArt
extends RefCounted
const Yard := preload("res://src/town/residential_yard.gd")
const StreetPlaces := preload("res://src/town/street_places.gd")
const JiangnanFrontage := preload("res://src/town/jiangnan_frontage.gd")
const JiangnanDistrictProps := preload("res://src/town/jiangnan_district_props.gd")

static func sprite(index: int) -> AtlasTexture:
	return TDEnvironmentArt.sprite(index,true)

static func ground(map: TDTownMap) -> ImageTexture:
	return TDTownScenery.ground(map)

static func prop(canvas: CanvasItem,index: int,feet: Vector2,width: float) -> void:
	TDTownScenery.shadow(canvas,feet,width)
	TDEnvironmentArt.draw_prop(canvas,index,feet,width,true)

static var _housing_key: String=""
static var _housing: Array[Dictionary]=[]

static func facade_plot(map: TDTownMap,plot: Dictionary,cell: float=TDTownWorld.CELL,origin: Vector2=Vector2.ZERO) -> Rect2:
	var rect:=TDInteractionRange.plot_bounds(plot,cell,origin)
	if plot.get("id","")=="market-small" and map.layout_version==2 and map.region_id.is_empty():
		# Fit the wide market art between its side verges. Keep the front
		# threshold at the plot edge where Chen's interaction is anchored.
		return rect.grow_individual(cell*.5,0,cell*.5,0)
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
	if Yard.is_residential(plot.get("kind","")) or plot.get("id","")=="player_cottage":
		return rect
	# Authored courts sometimes stop one grass row before the street. Include
	# that vacant frontage in presentation so steps do not float in the middle.
	var bottom: int=int(plot.y+plot.h)
	for step: int in 2:
		var vacant: bool=true
		for x: int in range(int(plot.x),int(plot.x+plot.w)):
			var at:=Vector2i(x,bottom+step)
			if not map.plot_at(at.x,at.y).is_empty() or str(map.terrain_at(at).surface_type) not in ["grass","lawn","lane","square","earth","quay"]: vacant=false;break
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

static func _draw_housing_label(canvas: CanvasItem, map: TDTownMap, origin: Vector2, cell: float, entries: Array[Dictionary]) -> void:
	var groups := housing_groups(map)
	if map.layout_version==2 and not groups.is_empty():
		var bounds:=Rect2(Vector2(groups[0].at),Vector2.ONE*groups[0]["size"])
		for group: Dictionary in groups: bounds=bounds.merge(Rect2(Vector2(group.at),Vector2.ONE*group["size"]))
		if not map.cottage.is_empty(): bounds=bounds.merge(facade_plot(map,map.cottage,1.0))
		var center:=origin+Vector2(bounds.get_center().x,bounds.position.y-.7)*cell
		for item: Dictionary in entries:
			if item.get("housing_block",false) or item.get("plot",{}).get("kind","")=="player_cottage":
				center.y = minf(center.y,item.rect.position.y-24.0)
		var plate:=Rect2(center-Vector2(112,18),Vector2(224,34))
		canvas.draw_style_box(_label_style(true),plate)
		canvas.draw_string(TDUI.font(),plate.position+Vector2(10,24),"青瓦巷 · 居民区",HORIZONTAL_ALIGNMENT_CENTER,204,TDUI.FONT_SECTION,Color("fff1cd"))

static func facades(map: TDTownMap, cell: float, origin: Vector2, management_menus: bool) -> Array[Dictionary]:
	if TDPlannedTown.approved(map):
		return _reference_facades(map, cell, origin, management_menus)
	var entries: Array[Dictionary] = []
	for group: Dictionary in housing_groups(map):
		var span: int = group["size"]
		var lot := Rect2(origin + Vector2(group.at) * cell, Vector2.ONE * span * cell)
		if span > 1: lot = Yard.facade_lot(lot,cell,false)
		var art: Texture2D = sprite(14) if span == 1 else TDTravelCatalog.facade("chengdu", {"kind":"housing"}, (group.at.x + group.at.y) % 2)
		var kind := "prop" if span==1 else "housing"
		var house := street_entry(art,street_feet(lot),lot.size.x,0.55 if span==1 else 3.5,.28,kind,map,origin,cell)
		house.housing_block = true
		entries.append(house)
		if span > 1 and map.layout_version == 2 and art == JiangnanFrontage.picture(JiangnanFrontage.Piece.GALLERY):
			entries.append(JiangnanFrontage.hanging(JiangnanFrontage.Piece.INDIGO_LAUNDRY,house.rect,Vector2(.34,.47),house.rect.size.x*.26))
	for plot: Dictionary in map.plots:
		var kind := str(plot.kind)
		if plot.get("economic_courtyard", false) or kind in ["diner_lot", "housing"]: continue
		if management_menus and kind in ["factory_lot", "supply_factory"]: continue
		if kind == "plaza" and map.layout_version == 2:
			entries.append_array(StreetPlaces.jiangnan_square(map,plot,cell,origin))
			continue
		var lot := facade_plot(map, plot, cell, origin)
		if Yard.is_residential(kind):
			lot = Yard.facade_lot(lot,cell,Yard.has_yard(plot))
		var art := TDTravelCatalog.facade("chengdu", plot)
		# Taller multi-story art needs more height to give its door the same
		# scale as the single-story houses and street stalls.
		var height := 2.4
		if kind == "player_diner" and not plot.get("construction", false): height = 3.75
		elif kind in ["bank", "hotel"]: height = 2.9
		elif kind in ["market", "snack_street"]: height = 1.8
		var count := 1
		if kind == "snack_street" and plot.id != "snack_street": count = maxi(1,floori(lot.size.x/(2.0*TDTownWorld.HERO_HEIGHT*art.get_size().aspect()+8.0)))
		if kind == "plaza":
			# The tree and benches occupy an island towards the back. The paved square stays open.
			lot = Rect2(lot.get_center() - Vector2(cell*1.8, cell*1.5), Vector2(cell*3.6, cell*1.6))
		if kind == "amusement" and map.layout_version == 2:
			# The garden entrance sits on the north bank. Leave the footbridge in view.
			var inlet: Dictionary = TDPlannedTown.definition().garden_inlet
			var bank := origin + Vector2(inlet.origin[0],inlet.origin[1])*cell
			lot = Rect2(bank+Vector2(3.0,-1.1)*cell,Vector2(2.4,2.05)*cell)
			for planting: Vector4 in [Vector4(.48,2.8,0,2.2), Vector4(.34,4.45,2,.85), Vector4(4.22,5.68,2,.78), Vector4(1.88,3.18,2,.63)]:
				var feet := bank + Vector2(planting.x,planting.y)*cell
				var plant := TDTravelCatalog.plant("chengdu",int(planting.z))
				var rect := TDEnvironmentArt.facade_rect(plant,feet,planting.w*cell,3.0*cell)
				entries.append({"art":plant,"rect":rect,"bases":TDEnvironmentArt.facade_bases(rect,.09)})
		var frontage := Rect2()
		for i: int in count:
			var slot := Rect2(lot.position + Vector2(lot.size.x * i / count, 0), Vector2(lot.size.x / count, lot.size.y))
			var use := "construction" if plot.get("construction",false) else kind
			var feet := street_feet(slot)
			if map.layout_version==2:
				var block := origin+Vector2(plot.x,plot.y)*cell
				match str(plot.id):
					"hotel":
						feet = block+Vector2(2.0,6.1)*cell
						height = 3.65
					"market-mid": feet = block+Vector2(2.5,2.55)*cell
					"snack_street": feet = block+Vector2(3.5,1.65)*cell
					"landmark":
						feet = block+Vector2(.62,3.08)*cell
						height = 2.85
			var item := street_entry(art,feet,slot.size.x,height,.25,use,map,origin,cell,frontage_bias(map,plot),kind=="amusement")
			if map.layout_version==2 and plot.id in ["hotel","landmark","player_diner","commercial_street:bank","market-small","snack_street","market-mid"]:
				item.jiangnan_feature = "courtyard_shadow"
			item.plot = plot
			frontage = item.rect if i==0 else frontage.merge(item.rect)
			item.label_at = Vector2(feet.x, (item.rect as Rect2).end.y) if i == 0 else Vector2.INF
			item.tint = Color(.82,.84,.86) if kind == "factory_lot" else Color.WHITE
			entries.append(item)
			if map.layout_version == 2:
				var hanging := JiangnanFrontage.shop_hanging(plot,item.rect)
				if not hanging.is_empty(): entries.append(hanging)
		entries.append_array(frontage_details("chengdu", plot, map, cell, origin, frontage))
	var port := TDHarbor.facility(map)
	if not port.is_empty():
		var art := TDHarbor.texture(1)
		var rect := TDHarbor.booth_rect(origin, cell)
		entries.append({"art": art, "rect": rect, "bases": TDEnvironmentArt.facade_bases(rect, 0.27)})
	var landings := JiangnanFrontage.river_life(map,cell,origin)
	entries.append_array(landings)
	JiangnanDistrictProps.fixtures(map,cell,origin,entries)
	var walk_ins := JiangnanDistrictProps.Terrain.clear_approaches(map,cell,origin)
	for part: Dictionary in landings:
		if part.has("walk_in"): walk_ins.append(part.walk_in)
	var occupied: Array[Rect2] = []
	for item: Dictionary in entries: occupied.append(item.rect)
	occupied.append_array(walk_ins)
	for item: Dictionary in TDTownScenery.dressing(map):
		var tex := TDTravelCatalog.plant("chengdu",item.index)
		var width: float = item.width*cell
		var rect := TDEnvironmentArt.facade_rect(tex,origin+Vector2(item.feet)*cell,width,width/tex.get_size().aspect())
		if walk_ins.any(func(clear: Rect2)->bool: return clear.intersects(rect)): continue
		var bounds: Rect2 = item.bounds
		entries.append({"art":tex,"rect":rect,"bases":[Rect2(origin+bounds.position*cell,bounds.size*cell)]})
		occupied.append(rect)
	entries.append_array(StreetPlaces.verges("chengdu",map,cell,origin,occupied))
	return entries

static func _reference_facades(map: TDTownMap, cell: float, origin: Vector2, management_menus: bool) -> Array[Dictionary]:
	var entries := TDJiangnanReferenceArt.facades(map, cell, origin)
	for plot: Dictionary in map.plots:
		var kind := str(plot.kind)
		if not plot.has("branch_id") and kind != "player_cottage" and (management_menus or kind != "supply_factory"):
			continue
		var lot := TDInteractionRange.plot_bounds(plot, cell, origin)
		if kind == "player_cottage" and _use_reference_house(entries, plot, lot): continue
		var art := TDTravelCatalog.facade("chengdu", plot)
		var use := "construction" if plot.get("construction", false) else kind
		var item := street_entry(art, street_feet(lot), lot.size.x, 3.0 if kind == "player_cottage" else 3.75,
			.25, use, map, origin, cell)
		item.plot = plot
		if use!="construction": item.walking=TDEnvironmentArt.shop_walls(item.rect,item.bases[0])
		item.label_at = Vector2((item.rect as Rect2).get_center().x, (item.rect as Rect2).end.y)
		entries.append(item)
	return entries

static func _use_reference_house(entries: Array[Dictionary], cottage: Dictionary, lot: Rect2) -> bool:
	var best: Dictionary = {}
	var most_overlap := 0.0
	for part: Dictionary in entries:
		if not String(part.reference_id).contains("house") and not String(part.reference_id).contains("homes"):
			continue
		for base: Rect2 in part.bases:
			var overlap := lot.intersection(base).get_area()
			if overlap > most_overlap:
				most_overlap = overlap
				best = part
	if best.is_empty(): return false
	best.plot = cottage
	return true

## Populate the inside of designated public blocks. Roads, branch lots and
## door approaches remain clear. All pieces have the same depth sorting as houses.
static func frontage_details(town: String, plot: Dictionary, map: TDTownMap, cell: float, origin: Vector2, frontage: Rect2) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var lot := TDInteractionRange.plot_bounds(plot)
	if lot.size.y < 3 or lot.size.x < 2 or plot.get("construction",false): return entries
	var kind := str(plot.kind)
	entries.append_array(Yard.sections(town,plot,cell,origin,frontage))
	var venue := StreetPlaces.venue(town,plot,cell,origin) if map.layout_version==2 else {}
	if not venue.is_empty():
		entries.append(venue)
		var stage: Rect2 = venue.rect
		var garden := TDInteractionRange.plot_bounds(plot,cell,origin).grow(-5)
		for side: int in [-1,1]:
			var plant := TDTravelCatalog.plant(town,1 if side>0 else 2)
			var width := 64.0 if side>0 else 46.0
			var feet := Vector2(stage.get_center().x+side*(stage.size.x*.5+width*.42),stage.end.y-6)
			var bed := TDEnvironmentArt.facade_rect(plant,feet,width,75)
			if garden.encloses(bed) and not bed.intersects(frontage.grow(5)) and not entries.any(func(e: Dictionary)->bool: return e!=venue and bed.intersects(e.rect)):
				entries.append({"art":plant,"rect":bed,"bases":TDEnvironmentArt.facade_bases(bed,.13)})
	var slots: Array = []
	match kind:
		"plaza":
			slots = [[.18,.43,"bench"],[.84,.42,"bench"]]
			if lot.size.x >= 7: slots.append([.78,.34,"canopy",1.8])
		"rich_district","urban_village":
			if lot.size.y >= 5 and lot.size.x >= 4:
				slots = [[.79,.55,"shrub",.76]]
			if Yard.has_yard(plot):
				slots.append([.19,.84,"shrub",.68])
				slots.append([.81,.25,"shrub",.82])
		"hotel","market":
			if lot.size.y >= 4: slots = [[.34,.34,"canopy",1.65],[.84,.54,"shrub",.75]]
		"landmark":
			if lot.size.y >= 4: slots = [[.20,.24,"tree",1.4],[.82,.47,"bench"]]
		"snack_street": slots = [[.25,.32,"canopy",1.8],[.68,.37,"bench"]]
	for slot: Array in slots:
		var door := Vector2(plot.get("approach_x",-10),plot.get("approach_y",-10)) + Vector2.ONE*.5
		var tex: Texture2D
		match str(slot[2]):
			"tree": tex = TDTravelCatalog.prop(town,false) if town=="tokyo" else TDTravelCatalog.plant(town,0)
			"shrub": tex = TDTravelCatalog.plant(town,2)
			_: tex = TDTravelCatalog.street_detail(town,1 if slot[2]=="canopy" else 2)
		var is_bench: bool = slot[2]=="bench"
		var width: float
		if is_bench:
			width = TDTravelCatalog.bench_width(town,tex)
		else:
			width = minf(lot.size.x*.78*cell,slot[3]*52.0)
		var parcel := Rect2(origin+lot.position*cell,lot.size*cell).grow(-6)
		for placement: Vector2 in [Vector2(slot[0],slot[1]),Vector2(.18,.78),Vector2(.83,.70),Vector2(.20,.43),Vector2(.76,.37)]:
			var feet := origin+(lot.position+lot.size*placement)*cell
			if is_bench:
				var height := width/tex.get_size().aspect()
				if width>parcel.size.x or height>parcel.size.y: break
				feet = feet.clamp(parcel.position+Vector2(width*.5,height),parcel.end-Vector2(width*.5,0))
			var at := (feet-origin)/cell
			if door.distance_to(at)<1.0 or map.is_road(floori(at.x),floori(at.y)) or not map.terrain_at(Vector2i(at)).walkable: continue
			var rect := TDEnvironmentArt.facade_rect(tex,feet,width,2.3*TDTownWorld.HERO_HEIGHT)
			if not parcel.encloses(rect) or rect.intersects(frontage.grow(8)): continue
			if is_bench and rect.grow(18).has_point(origin+door*cell): continue
			if entries.any(func(e: Dictionary)->bool: return rect.intersects(e.rect.grow(4))): continue
			entries.append({"art":tex,"rect":rect,"bases":TDEnvironmentArt.facade_bases(rect,.14)})
			break
	return entries

## On a shared street front, extend the eaves towards the unoccupied side.
static func frontage_bias(map: TDTownMap, plot: Dictionary) -> int:
	if plot.kind=="player_cottage" or Yard.has_yard(plot): return 0
	var y := int(plot.y+plot.h)-1
	var left := map.plot_at(int(plot.x)-1,y)
	var right := map.plot_at(int(plot.x+plot.w),y)
	return int(not left.is_empty()) - int(not right.is_empty())

static func street_feet(lot: Rect2) -> Vector2:
	return Vector2(lot.get_center().x,lot.end.y-4.0)

## Roof and doorway share a uniform scale. Only the wall at street level blocks
## walking. Eaves can project over the side verge or a neighbouring frontage.
static func street_entry(art: Texture2D, feet: Vector2, frontage: float, height: float, depth: float, kind: String, map: TDTownMap, origin: Vector2, cell: float, bias: int=0, open_gate: bool=false) -> Dictionary:
	var human := TDTownWorld.HERO_HEIGHT
	var min_heads := 0.0
	match kind:
		"housing","player_cottage","urban_village","rich_district": min_heads = 3.35
		"hotel","bank": min_heads = 3.15
		"player_diner": min_heads = 2.95
		"competitor","commercial_street","supply_factory": min_heads = 2.4
		"market","station","snack_street","landmark": min_heads = 2.0
		"harbor": min_heads = 1.9
	var wall_width := maxf(1.0,frontage-8)
	var rect := TDEnvironmentArt.facade_rect(art,feet,maxf(wall_width,min_heads*human*art.get_size().aspect()),maxf(height,min_heads)*human)
	var excess := maxf(0.0,rect.size.x-wall_width)
	rect.position.x += bias*minf(excess*.5,wall_width*.22)
	# Leave a side alley beside a shared boundary when the facade fits its lot.
	var spare_width := maxf(0.0,wall_width-rect.size.x)
	rect.position.x += bias*minf(cell*.18,spare_width*.5)
	var bases := TDEnvironmentArt.facade_bases(rect,depth,open_gate)
	if excess > 0.0 and not open_gate:
		var wall := bases[0]
		# Keep the complete wall over dry ground. Where a narrow street abuts
		# the lot, slide the house inland before trimming any overhanging eaves.
		var left := _verge_edge(map,origin,cell,wall,feet.x-wall_width*.5,-1,excess)
		var right := _verge_edge(map,origin,cell,wall,feet.x+wall_width*.5,1,excess)
		if right-left>=wall.size.x:
			var shift := clampf(0.0,left-wall.position.x,right-wall.end.x)
			shift = clampf(shift,-cell*.75,cell*.75)
			rect.position.x+=shift
			wall.position.x+=shift
		var frontage_band := Rect2(left,rect.position.y,right-left,rect.size.y)
		bases[0] = wall.intersection(frontage_band)
	return {"art":art,"rect":rect,"bases":bases}

static func _verge_edge(map: TDTownMap, origin: Vector2, cell: float, wall: Rect2, edge: float, side: int, extension: float) -> float:
	var limit := edge+side*extension
	var first_row := floori((wall.position.y-origin.y)/cell)
	var last_row := floori((wall.end.y-origin.y)/cell)
	while (limit-edge)*side>0.01:
		var column := floori((edge+side*.1-origin.x)/cell)
		for row: int in range(first_row,last_row+1):
			if map.is_road(column,row) or not map.terrain_at(Vector2i(column,row)).walkable: return edge
		var boundary := origin.x+(column+int(side>0))*cell
		edge = maxf(limit,boundary) if side<0 else minf(limit,boundary)
	return edge

static func draw_world(canvas: Node2D, session: TDPhase3Session, selected: Dictionary, entries: Array[Dictionary]) -> void:
	var map := session.town_map
	var origin := Vector2(300,24)
	var cell: float = (canvas as TDTownWorld).cell_size() if canvas is TDTownWorld else TDTownWorld.CELL
	if not TDPlannedTown.approved(map):
		canvas.draw_texture_rect(ground(map), Rect2(origin, Vector2.ONE * map.extent * cell), false)
		TDTownScenery.draw_wilds(canvas, origin, cell)
		if JiangnanDistrictProps.enabled(map):
			JiangnanDistrictProps.draw_street_marks(canvas,entries,origin,cell,float(canvas.get("day_minute")))
		_draw_housing_label(canvas, map, origin, cell, entries)
	for item: Dictionary in entries:
		if item.get("label_at", Vector2.INF) == Vector2.INF: continue
		var p: Dictionary = item.plot
		var feet: Vector2 = item.label_at
		var width: float = item.rect.size.x
		var kind := str(p.kind)
		var active: bool=str(selected.get("id",""))==str(p.id)
		var label: String="焰请八方" if p.id=="player_diner" and TDPlannedTown.approved(map) else str(p.name)
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
