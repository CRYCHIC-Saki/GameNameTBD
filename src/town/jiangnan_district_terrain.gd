extends RefCounted
## Low ground marks are presentation-only. Every site and path is screened
## against the live town; buying or building clears the corresponding marks.
const GROUNDS := preload("res://assets/town/jiangnan-district-grounds-v2.png")
const Pedestrian := preload("res://src/town/panorama_ground.gd")
const SWATCH := 192
const BRUSH_INDEX := {"mud":0,"pickles":1,"slab_stone":2,"slate":3,"old_stone":3,"soil":4,"gravel":4,"forge":5}
const DIRECTIONS: Array[Vector2i] = [Vector2i.DOWN, Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT]

static var _ground_sheet: Image

static func sites(map: TDTownMap) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if map.layout_version != 2 or not map.region_id.is_empty(): return result
	if TDPlannedTown.approved(map): return result
	var panorama: Dictionary = TDLegacyJiangnanLayout.definition().panorama
	for record: Dictionary in panorama.sites:
		var r: Array = record.rect
		var side: Array = record.side
		_offer(result,map,record.id,Rect2i(r[0],r[1],r[2],r[3]),"future",record.surface,
			Vector2i(side[0],side[1]),record.get("allow_plot",""))
	for parcel: Dictionary in map.commercial_parcels():
		if not parcel.tradable or not map._by_id(str(parcel.id)).is_empty(): continue
		_offer(result, map, str(parcel.id), Rect2i(parcel.x,parcel.y,parcel.w,parcel.h), "available", "gravel", Vector2i.DOWN, str(parcel.parent_id))
	if map._by_id("player_diner").is_empty():
		var frontage: Array = panorama.home_front
		_offer(result,map,"diner_lot",Rect2i(frontage[0],frontage[1],frontage[2],frontage[3]),
			"available","gravel",Vector2i.DOWN,"commercial_street")
	return result

static func _offer(result: Array[Dictionary], map: TDTownMap, id: String, area: Rect2i, role: String, surface: String, side: Vector2i, allow_plot: String = "") -> void:
	# A visit map can contain a branch inside a larger parent plot. plot_at()
	# may return the parent first, so also check all physical footprints.
	for plot: Dictionary in map.plots:
		if str(plot.id) == allow_plot: continue
		if area.intersects(Rect2i(plot.x,plot.y,plot.w,plot.h)): return
	for y: int in range(area.position.y, area.end.y):
		for x: int in range(area.position.x, area.end.x):
			var at := Vector2i(x,y)
			if not map.terrain_at(at).buildable or map.is_road(x,y): return
			var plot := map.plot_at(x,y)
			if not plot.is_empty() and str(plot.id) != allow_plot: return
	var entrance := _entrance(map, area, side, allow_plot)
	if entrance.is_empty(): return
	result.append({"id":id,"rect":area,"role":role,"surface":surface,"side":entrance.side,"edge":entrance.edge,"depth":entrance.depth})

static func _entrance(map: TDTownMap, area: Rect2i, preferred: Vector2i, allow_plot: String) -> Dictionary:
	var result: Dictionary = {}
	var best := INF
	for side: Vector2i in DIRECTIONS:
		var size := area.size.x if side.y != 0 else area.size.y
		for offset: int in size:
			var edge := area.position + (Vector2i(offset,0) if side.y != 0 else Vector2i(0,offset))
			if side.x > 0: edge.x = area.end.x-1
			if side.y > 0: edge.y = area.end.y-1
			for depth: int in range(1,5):
				var at := edge + side*depth
				if at.x < 0 or at.y < 0 or at.x >= map.extent or at.y >= map.extent: break
				var terrain := map.terrain_at(at)
				if terrain.terrain_type != "plain" or not terrain.walkable: break
				if map.is_road(at.x,at.y):
					if terrain.surface_type != "stone": break
					var score := float(depth)*1.5 + absf(offset+.5-size*.5) + (0.0 if side == preferred else 7.0)
					if score < best:
						best = score
						result = {"side":side,"edge":edge,"depth":depth}
					break
				if _other_plot_contains(map,at,allow_plot): break
	return result

static func _other_plot_contains(map: TDTownMap, at: Vector2i, allow_plot: String) -> bool:
	for plot: Dictionary in map.plots:
		if str(plot.id) != allow_plot and Rect2i(plot.x,plot.y,plot.w,plot.h).has_point(at): return true
	return false

static func reserve_planting(reserved: Dictionary, map: TDTownMap) -> void:
	for site: Dictionary in sites(map):
		var area: Rect2i = site.rect.grow(1)
		for y: int in range(area.position.y,area.end.y):
			for x: int in range(area.position.x,area.end.x):
				reserved[Vector2i(x,y)] = true
		for i: int in range(1,int(site.depth)):
			reserved[Vector2i(site.edge)+Vector2i(site.side)*i] = true

## Reserve the actual walking line, not the full sprite silhouette of a prop.
## Fixed buildings are kept by the caller; small procedural fixtures may move.
static func clear_approaches(map: TDTownMap,cell: float,origin: Vector2) -> Array[Rect2]:
	var result: Array[Rect2] = []
	for site: Dictionary in sites(map):
		var lot: Rect2i = site.rect
		var start := origin + (Vector2(site.edge)+Vector2.ONE*.5)*cell
		var finish := start + Vector2(site.side)*float(site.depth)*cell
		result.append(Rect2(start,Vector2.ZERO).expand(finish).grow(cell*.29))
		result.append(Rect2(origin+Vector2(lot.position)*cell,Vector2(lot.size)*cell).grow(-cell*.09))
	return result

static func paint(image: Image, map: TDTownMap, size: int, miniature: bool = false) -> void:
	if map.layout_version != 2 or not map.region_id.is_empty() or size <= 0: return
	if miniature: Pedestrian.paint_streets(image,map,size,true)
	# Treat only the approaches, preserving earlier paving and measured walkways.
	_apron(image,map,"hotel",size,"gravel",false)
	_apron(image,map,"market-mid",size,"mud",true)
	_apron(image,map,"snack_street",size,"old_stone",false)
	_landmark_ground(image,map,size)
	_pickling_and_workshop(image,map,size)
	_shore_verge(image,map,size)
	_market_verge(image,map,size)
	Pedestrian.paint_doors(image,map,size)
	var street_rows := Pedestrian._street_rows()
	for site: Dictionary in sites(map):
		var area: Rect2i = site.rect
		var brush := str(site.surface)
		var seed := _noise(area.position.x,area.position.y,67)
		_paint_patch(image,area,size,brush,seed)
		var direction: Vector2i = site.side
		var edge: Vector2i = site.edge
		var entry := edge*size + Vector2i.ONE*floori(size*.5) + direction*floori(size*.40)
		_path(image,entry,direction,int(site.depth)*size,size,brush,seed)
		Pedestrian.connect_site(image,map,site,size,street_rows)
		if brush == "turf" and area.size.x >= 3:
			var center := Vector2(area.get_center())+Vector2(.3,.6)
			_stepping_curve(image,Vector2(entry)/size,center,Vector2(-direction.y,direction.x)*.46,size,seed)
		if not miniature:
			_edges(image,area,size,entry,direction,site.role == "available",brush,seed)
			if site.id == "inn_farm":
				_timber_run(image,area.position*size+Vector2i(floori(size*.31),floori(size*.41)),size,2.35)
				_timber_run(image,Vector2i(area.position.x*size,area.end.y*size)+Vector2i(floori(size*1.51),-floori(size*.24)),size,2.11)
			if site.id in ["market_perimeter","workshop_yard","restaurant_garden","snack_court"]:
				_old_footing(image,area,size,entry,Vector2i(-direction.y,direction.x),site.id=="snack_court",seed)
	Pedestrian.square_gates(image,map,size,street_rows)

static func paint_approved_market(image: Image, map: TDTownMap, size: int) -> void:
	var market := map._by_id("market-mid")
	if market.is_empty(): return
	var yard := Rect2i(int(market.x),int(market.y),int(market.w),int(market.h))
	_paint_patch(image,yard,size,"slab_stone",53)
	for point: Vector2 in [Vector2(1.35,2.5),Vector2(7.7,3.7),Vector2(6.7,3.95)]:
		_oval(image,Vector2i((Vector2(yard.position)+point)*size),
			Vector2i(roundi(size*.62),roundi(size*.30)),62,"wet",.80)

static func _landmark_ground(image: Image,map: TDTownMap,size: int) -> void:
	# Surface only: these strips occupy the established stall and front-door plots.
	for id: String in ["market-mid","market-large"]:
		var market := map._by_id(id)
		if market.is_empty(): continue
		var pad := Rect2i(int(market.x),int(market.y)+1,int(market.w),int(market.h)-1)
		_paint_patch(image,pad,size,"mud",48+int(market.x))
		for i: int in range(pad.size.x-1):
			var foot := (pad.position+Vector2i(i,pad.size.y-1))*size
			var at := foot + Vector2i(floori(size*(.65+.14*(i%2))),floori(size*(.62 if i%3==0 else .37)))
			_oval(image,at,Vector2i(maxi(2,roundi(size*.33)),maxi(1,roundi(size*.10))),53+i,"wet",.78)
			if size>=15:
				for j: int in 4:
					var grain := _noise(i,j,79)
					var flash := at+Vector2i((grain%13)-6,(grain/13%7)-3)
					image.set_pixelv(flash,image.get_pixelv(flash).lerp(Color("a9b9a9"),.55))
	var alley := map._by_id("snack_street")
	if not alley.is_empty():
		var width := int(alley.w)*size
		var start := Vector2i(int(alley.x)*size,roundi(float(alley.y+alley.h)*size-size*1.37))
		for x: int in range(0,width):
			var mid := roundi(sin(float(x)/maxf(3.0,size*.83))*size*.31)
			var breadth := roundi(size*.54*sin(PI*float(x)/width)**.38)+_noise(x/2,2,61)%3-1
			for y: int in range(-breadth,breadth+1):
				var at := start + Vector2i(x,mid+y)
				var stone := _sample("slate",at,size,43)
				var weight := .77 if absi(y) >= breadth-1 else .96
				image.set_pixelv(at,image.get_pixelv(at).lerp(stone,weight))
			if x % maxi(2,size) == 0:
				_oval(image,start+Vector2i(x,mid+roundi(size*.22)),Vector2i(maxi(2,roundi(size*.12)),maxi(1,roundi(size*.08))),x,"rut",.76)
	var inn := map._by_id("hotel")
	if not inn.is_empty():
		var court := Rect2i(int(inn.x),int(inn.y+inn.h)-2,int(inn.w),2)
		_paint_patch(image,court,size,"slab_stone",53)

static func _pickling_and_workshop(image: Image, map: TDTownMap, size: int) -> void:
	var shop := map._by_id("market-small")
	if not shop.is_empty():
		# The story uses grass immediately SOUTH of the shop. Keep the wet
		# broken-brick lane between the crock rows on the two sides instead.
		var alley := Rect2i(int(shop.x)-2,int(shop.y),int(shop.w)+4,int(shop.h))
		_paint_patch(image,alley,size,"pickles",735,_blocked_cells(map,alley,["market-small"]))
	var trade := map._by_id("competitor")
	if not trade.is_empty():
		# The back trades occupy the eastern heel of the commercial row.
		var yard := Rect2i(int(trade.x+trade.w)-3,int(trade.y+trade.h)-3,4,3)
		_paint_patch(image,yard,size,"forge",278,_blocked_cells(map,yard,["competitor"]))

static func _blocked_cells(map: TDTownMap, area: Rect2i, allowed: Array) -> Dictionary:
	var blocked := {}
	for y: int in range(area.position.y,area.end.y):
		for x: int in range(area.position.x,area.end.x):
			var at := Vector2i(x,y)
			if map.is_road(x,y) or not map.terrain_at(at).buildable:
				blocked[at] = true
	for plot: Dictionary in map.plots:
		if plot.id in allowed: continue
		var occupied := area.intersection(Rect2i(plot.x,plot.y,plot.w,plot.h))
		for y: int in range(occupied.position.y,occupied.end.y):
			for x: int in range(occupied.position.x,occupied.end.x):
				blocked[Vector2i(x,y)] = true
	return blocked

static func _stepping_curve(image: Image, start: Vector2, finish: Vector2, bulge: Vector2, size: int, seed: int) -> void:
	var count := maxi(2,roundi(start.distance_to(finish)*3.35))
	for i: int in range(1,count):
		var t := float(i)/count
		var middle := start.lerp(finish,t)+bulge*sin(PI*t)
		var wobble := Vector2(_noise(i,4,seed)%5-2,_noise(i,7,seed)%5-2)*.012
		_oval(image,Vector2i(((middle+wobble)*size).round()),
			Vector2i(maxi(2,roundi(size*.14)),maxi(1,roundi(size*.085))),seed+i,"slab",.87)

static func _shore_verge(image: Image,map: TDTownMap,size: int) -> void:
	var view := map._by_id("landmark")
	if view.is_empty(): return
	# Boulders and reeds follow actual dry banks. A rented plot, road or quay
	# never gets a rocky border pasted across its entry or across a bridge.
	var stretch := Rect2i(int(view.x)-2,int(view.y)-1,3,int(view.h)+3)
	var blocked := _blocked_cells(map,stretch,["landmark"])
	for y: int in range(stretch.position.y,stretch.end.y):
		for x: int in range(stretch.position.x,stretch.end.x):
			var at := Vector2i(x,y)
			if blocked.has(at): continue
			for side: Vector2i in DIRECTIONS:
				if map.terrain_at(at+side).surface_type != "water": continue
				var tangent := Vector2(-side.y,side.x)
				for i: int in 5:
					var seed := _noise(i+x,y,541)
					var foot := Vector2(at)+Vector2.ONE*.5+Vector2(side)*(.38+.02*(seed%4))+tangent*(float(i)*.19-.38)
					var point := Vector2i((foot*size).round())
					_oval(image,point,Vector2i(maxi(1,roundi(size*(.060+(seed%4)*.014))),maxi(1,roundi(size*.052))),seed,"slab",.85)
					if i%2==0 and size>=15: _tuft(image,point-Vector2i(side)*roundi(size*.06),size,seed)

static func _old_footing(image: Image, area: Rect2i, size: int, entry: Vector2i, tangent: Vector2i, charred: bool,seed: int) -> void:
	# One incomplete course reads as reusable foundation, with a missing bay
	# toward the path. There is deliberately no collision inside the survey.
	var start := area.position*size+Vector2i(roundi(size*.18),roundi(size*.25))
	var along := Vector2i.RIGHT if area.size.x>=area.size.y else Vector2i.DOWN
	var count := mini(13,roundi(maxi(area.size.x,area.size.y)*4.2))
	for i: int in count:
		if _noise(i,3,seed)%8<2: continue
		var brick := start+along*roundi(i*.19*size)
		if absf(Vector2(brick-entry).dot(Vector2(tangent)))<size*.37 and brick.distance_to(entry)<size*.62: continue
		var w := roundi(size*(.19 if along.x==1 else .11))
		var h := roundi(size*(.08 if along.x==1 else .14))
		var edge := Rect2i(brick,Vector2i(maxi(2,w),maxi(2,h)))
		image.fill_rect(edge,Color("5b5040") if charred else Color("71695b"))
		edge.position.y-=1
		edge.size-=Vector2i.ONE
		image.fill_rect(edge,Color("716451") if charred else Color("ad9a7c").darkened(float(_noise(i,5,seed)%5)*.035))
		if i%4==0: _tuft(image,brick+Vector2i(1,h),size,seed+i)

static func _timber_run(image: Image, foot: Vector2i, size: int, length: float) -> void:
	var width := roundi(size*length)
	var height := maxi(3,roundi(size*.16))
	var step := maxi(2,roundi(size*.45))
	var area := Rect2i(Vector2i.ZERO,image.get_size())
	for x: int in range(width):
		var offset := floori(sin(float(x)/size)*2.0)
		var top := foot+Vector2i(x,-height+offset)
		if not area.has_point(top): continue
		image.set_pixelv(top,Color("aa8a58"))
		image.set_pixelv(top+Vector2i.DOWN,Color("74593e"))
		image.set_pixelv(top+Vector2i.DOWN*maxi(2,height/2),Color("876748"))
		if x % step==0 or x==width-1: _post(image,foot+Vector2i(x,offset),size,false,21+x)

static func _market_verge(image: Image,map: TDTownMap,size: int) -> void:
	var market := map._by_id("market-mid")
	if market.is_empty(): return
	var verge := Rect2i(int(market.x),int(market.y+market.h),int(market.w),1)
	for x: int in range(verge.position.x,verge.end.x):
		var cell := Vector2i(x,verge.position.y)
		if map.is_road(cell.x,cell.y) or not map.terrain_at(cell).walkable or not map.plot_at(cell.x,cell.y).is_empty(): return
	_paint_patch(image,verge,size,"mud",43)
	for offset: int in range(3):
		var x := verge.position.x+offset
		var y := verge.position.y
		var center := Vector2i(x*size+floori(size*(.41+.09*offset)),y*size+floori(size*(.51-.12*(offset%2))))
		_oval(image,center,Vector2i(maxi(2,floori(size*.24)),maxi(1,floori(size*.095))),42+offset,"wet",.78)
		_oval(image,center+Vector2i(floori(size*.22),floori(size*.18)),Vector2i(2,1),98+offset,"leaf",.90)
		_oval(image,center+Vector2i(-floori(size*.24),floori(size*.10)),Vector2i(2,2),89+offset,"slab",.85)

static func _apron(image: Image,map: TDTownMap,id: String,size: int,brush: String,wet: bool) -> void:
	var plot := map._by_id(id)
	if plot.is_empty(): return
	var approach := Vector2i(int(plot.approach_x),int(plot.approach_y))
	if not map.is_road(approach.x,approach.y) or map.terrain_at(approach).surface_type != "stone": return
	var boundary := Rect2i(int(plot.x),int(plot.y),int(plot.w),int(plot.h))
	if approach.y < boundary.position.y or approach.y >= boundary.end.y:
		for dx: int in range(-2,3):
			var here := approach + Vector2i(dx,0)
			if not map.is_road(here.x,here.y) or map.terrain_at(here).surface_type != "stone": continue
			var center := here*size + Vector2i.ONE*floori(size*.5)
			var seed := _noise(here.x,here.y,17)
			if id == "hotel":
				for offset: int in [-1,1]:
					var at := center + Vector2i(0,roundi(offset*size*.19))
					_oval(image,at,Vector2i(maxi(2,roundi(size*.48)),maxi(1,roundi(size*.038))),seed,"rut",.64)
			else:
				_oval(image,center+Vector2i(0,roundi(size*.07)),Vector2i(maxi(2,roundi(size*.44)),maxi(1,roundi(size*(.15 if wet else .12)))),seed,brush,.44)
				if wet and dx % 2 == 0:
					_oval(image,center+Vector2i(floori(size*.11),floori(size*.1)),Vector2i(maxi(2,roundi(size*.21)),maxi(1,roundi(size*.08))),seed,"wet",.68)

static func _paint_patch(image: Image, area: Rect2i, size: int, brush: String, seed: int, blocked: Dictionary = {}) -> void:
	var px := Rect2i(area.position*size,area.size*size)
	var taper := minf(float(mini(px.size.x,px.size.y))*.17,size*.40)
	for y: int in px.size.y:
		for x: int in px.size.x:
			var edge_x := mini(x,px.size.x-1-x)
			var edge_y := mini(y,px.size.y-1-y)
			var along_x := .55+.30*sin(float(y)/maxf(4.0,size*.65)+float(seed%37))+.15*sin(float(y)/maxf(2.0,size*.17))
			var along_y := .55+.30*sin(float(x)/maxf(4.0,size*.73)+float(seed%41))+.15*sin(float(x)/maxf(2.0,size*.24))
			# Continuous curvature plus stair steps breaks both long edges and corners.
			var band_x := floori(taper*along_x*.70)+(_noise(x/2,y/2,seed)%3)-1
			var band_y := floori(taper*along_y*.70)+(_noise(y/2,x/2,seed+1)%3)-1
			var distance := minf(edge_x-band_x,edge_y-band_y)
			distance -= maxf(0.0,taper-edge_x-edge_y)*.63
			if brush == "turf":
				if distance > size*.27 or distance < 0.0: continue
				if _noise(x/4,y/4,seed+65)%13 < 4: continue
			elif distance < 0.0: continue
			var point := px.position+Vector2i(x,y)
			if not blocked.is_empty() and blocked.has(Vector2i(floori(float(point.x)/size),floori(float(point.y)/size))): continue
			var underlying := image.get_pixelv(point)
			var texture := _sample(brush,point,size,seed)
			var amount := .43 if brush == "turf" else (.64 if distance < 1.0 else .90)
			image.set_pixelv(point,underlying.lerp(texture,amount))
			if distance <= 1.0 and size>=15 and _noise(x,y,seed)%43==1:
				_tuft(image,point,size,seed+x-y)

static func _tuft(image: Image,at: Vector2i,size: int,seed: int) -> void:
	# Three tiny teeth, each just one or two art pixels wide. Keep them
	# inside the same dry cell so they cannot reach neighboring water.
	var tile := Vector2i(floori(float(at.x)/size),floori(float(at.y)/size))
	var frame := Rect2i(tile*size,Vector2i.ONE*size).intersection(Rect2i(Vector2i.ZERO,image.get_size()))
	var s := 1 if seed%2==0 else -1
	for offset: Vector2i in [Vector2i.ZERO,Vector2i(s,-1),Vector2i(-s,-1),Vector2i(-s,-2)]:
		var tip := at+offset
		if frame.has_point(tip):
			var ink := Color("92964a") if offset.y < -1 else Color("767f41")
			image.set_pixelv(tip,image.get_pixelv(tip).lerp(ink,.82))

static func _path(image: Image, entry: Vector2i, side: Vector2i, length: int, size: int, brush: String, seed: int) -> void:
	var tangent := Vector2i(-side.y,side.x)
	# Only paint up to the sampled kerb, never across the middle of a public road.
	var path_length := maxi(1,length-floori(size*.67))
	for d: int in range(-roundi(size*.42),path_length):
		var bend := roundi(sin(float(d)/maxf(4.0,size*.43))*size*.085)
		var breadth := roundi(size*.18)+(_noise(d/2,seed%29,31)%3)-1
		for c: int in range(-breadth,breadth+1):
			var at := entry+side*d+tangent*(c+bend)
			if not Rect2i(Vector2i.ZERO,image.get_size()).has_point(at): continue
			var seam := absf(c)/maxf(1.0,breadth)
			var weight := .82 if seam < .65 else .52-float(_noise(d,c,seed)%3)*.12
			image.set_pixelv(at,image.get_pixelv(at).lerp(_sample("soil" if brush == "turf" else brush,at,size,seed),weight))
	for d: int in range(-roundi(size*.11),path_length,maxi(3,roundi(size*.24))):
		var step := entry+side*d+tangent*roundi(sin(float(d)/maxf(4.0,size*.43))*size*.085)
		var slab_x := roundi(size*(.13 if side.y != 0 else .08))
		var slab_y := roundi(size*(.08 if side.y != 0 else .13))
		_oval(image,step,Vector2i(maxi(2,slab_x),maxi(1,slab_y)),seed+d,"slab",.90)

static func _edges(image: Image, area: Rect2i, size: int, entry: Vector2i, side: Vector2i, available: bool, brush: String, seed: int) -> void:
	var margin := maxi(3,roundi(size*.12))
	var low := area.position*size + Vector2i.ONE*margin
	var high := area.end*size - Vector2i.ONE*margin
	var stone := brush in ["gravel","old_stone","mud"]
	var pieces: Array[Vector2i] = [low,Vector2i(high.x,low.y),Vector2i(low.x,high.y),high]
	if area.size.x > 2:
		pieces.append(low+Vector2i(roundi(size*.66),2))
		pieces.append(high-Vector2i(roundi(size*.70),3))
	for i: int in pieces.size():
		var foot := (pieces[i] + Vector2i(_noise(i,8,seed)%7-3,_noise(i,12,seed)%5-2)).clamp(low,high)
		var relative := Vector2(foot-entry)
		if absf(relative.dot(Vector2(-side.y,side.x))) < size*.36 and absf(relative.dot(Vector2(side))) < size*.45: continue
		if stone:
			for j: int in range(2 if i % 2 == 0 else 3):
				var center := (foot+Vector2i(j*roundi(size*.11),j%2*2)).clamp(low,high)
				_oval(image,center,Vector2i(maxi(2,roundi(size*.076)),maxi(2,roundi(size*.06))),seed+i+j,"slab",.78)
		if available or (not stone and i < 4):
			_post(image,foot,size,available,seed+i)

static func _post(image: Image, foot: Vector2i, size: int, available: bool, seed: int) -> void:
	var width := maxi(2,roundi(size*.055))
	var height := maxi(3,roundi(size*(.22 if available else .15)))
	var frame := Rect2i(Vector2i.ZERO,image.get_size())
	_oval(image,foot+Vector2i(width,1),Vector2i(width*2,2),seed,"rut",.43)
	image.fill_rect(Rect2i(foot-Vector2i(width/2,height),Vector2i(width,height)).intersection(frame),Color("6b5136"))
	image.fill_rect(Rect2i(foot-Vector2i(width/2,height-1),Vector2i(1,height-1)).intersection(frame),Color("b99a67"))
	image.fill_rect(Rect2i(foot-Vector2i(width/2,height),Vector2i(width,1)).intersection(frame),Color("d0af75"))
	if available:
		image.fill_rect(Rect2i(foot-Vector2i(width/2,height-2),Vector2i(width,1)).intersection(frame),Color("9c5038"))

static func _oval(image: Image, center: Vector2i, radius: Vector2i, seed: int, brush: String, opacity: float) -> void:
	var area := Rect2i(center-radius,radius*2+Vector2i.ONE).intersection(Rect2i(Vector2i.ZERO,image.get_size()))
	for y: int in range(area.position.y,area.end.y):
		for x: int in range(area.position.x,area.end.x):
			var delta := Vector2(Vector2i(x,y)-center)/Vector2(radius)
			var distance := delta.length_squared()
			if distance > .98-float(_noise(x/2,y/2,seed)%5)*.055: continue
			var at := Vector2i(x,y)
			var under := image.get_pixelv(at)
			var n := _noise(x,y,seed)
			var sample := under
			match brush:
				"rut": sample = under.lerp(Color("574836"),.52)
				"wet": sample = Color("535c55").lightened(.18 if n % 21 == 0 and delta.y < -.18 else .0)
				"leaf": sample = Color("637447").lightened(.08 if n % 3 == 0 else .0)
				"slab":
					sample = Color("969482").lightened(float(n%11)*.009)
					if distance > .58: sample = sample.darkened(.25) if delta.y > -.16 else sample.lightened(.13)
				_: sample = _sample(brush,at,2*radius.x,seed)
			image.set_pixelv(at,under.lerp(sample,opacity))

static func _sample(brush: String, point: Vector2i, size: int, seed: int) -> Color:
	if _ground_sheet == null:
		_ground_sheet = GROUNDS.get_image()
		if _ground_sheet.is_compressed(): _ground_sheet.decompress()
	var index := int(BRUSH_INDEX.get(brush,4))
	# The same masonry is about a boot wide in the game and remains in the
	# same place on M. Seed offsets are in texture pixels, not screen pixels.
	var density := 158 if index in [2,3] else 102
	var px := Vector2i(floori(float(point.x)*density/size)+seed%97,floori(float(point.y)*density/size)+seed%83)
	var color := _ground_sheet.get_pixel(index%3*SWATCH+posmod(px.x,SWATCH),index/3*SWATCH+posmod(px.y,SWATCH))
	if brush == "turf": return color.lerp(Color("879342"),.58)
	if brush == "gravel": return color.lerp(Color("ab9a7b"),.17)
	return color

static func _noise(x: int,y: int,salt: int) -> int:
	return absi((x*73856093)^(y*19349663)^(salt*83492791))
