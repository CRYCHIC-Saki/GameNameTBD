extends RefCounted
## Paving, shoulders and door paths on the real Jiangnan cadastral road network.
## All measurements are in world grid cells, shared by town and M.
const Paving := preload("res://src/town/jiangnan_paving.gd")
static var _stone: Image
static var _lawn: Image

static func _materials() -> void:
	if _stone != null: return
	_stone=Paving.stone_swatch()
	# Recut the mirrored 420px panel at the scale of dressed street stones.
	_stone.resize(136,136,Image.INTERPOLATE_LANCZOS)
	_lawn=TDTownScenery.surface_texture(0).get_image()

static func walk_stone() -> Image:
	_materials()
	return _stone

# At avenue widths of 3–4 cells the paved ribbon admits two passing carts.
# Large bends use the available roadbed. The surveyed road remains walkable.
static func _cross_center(rect: Rect2i,along: float,horizontal: bool) -> float:
	var narrow := float(rect.size.y if horizontal else rect.size.x)
	var edge := float(rect.position.y if horizontal else rect.position.x)
	var phase := edge*.18
	var sway := (sin(along*.43+phase)*.69+sin(along*.19-phase)*.31)
	return edge+narrow*.5+sway*maxf(0.0,narrow*.5-1.04)

static func _half_width(rect: Rect2i,horizontal: bool) -> float:
	return clampf(float(rect.size.y if horizontal else rect.size.x)*.247,.68,1.0)

static func _street_rows() -> Array[Rect2i]:
	var result: Array[Rect2i]=[]
	for row: Array in TDLegacyJiangnanLayout.definition().roads:
		var street:=Rect2i(row[0],row[1],row[2],row[3])
		var joined:=false
		for i: int in result.size():
			var same_course:=result[i].position.y==street.position.y and result[i].size.y==street.size.y
			var adjacent:=result[i].end.x>=street.position.x and street.end.x>=result[i].position.x
			if same_course and adjacent and street.size.x>street.size.y:
				result[i]=result[i].merge(street)
				joined=true
				break
		if not joined: result.append(street)
	return result

static func _ends(rect: Rect2i,rows: Array[Rect2i]) -> Vector2:
	var h:=rect.size.x>rect.size.y
	var near:=float(rect.position.x if h else rect.position.y)
	var far:=float(rect.end.x if h else rect.end.y)
	var trim:=_half_width(rect,h)*.80
	var ends:=Vector2(near+trim,far-trim)
	var axis:=float(rect.position.y+rect.size.y*.5 if h else rect.position.x+rect.size.x*.5)
	for street: Rect2i in rows:
		if (street.size.x>street.size.y)==h: continue
		var lo:=street.position.y if h else street.position.x
		var hi:=street.end.y if h else street.end.x
		if axis<lo-1.5 or axis>hi+1.5: continue
		var junction:=_cross_center(street,axis,not h)
		if absf(junction-near)<=2.6: ends.x=junction
		if absf(junction-far)<=2.6: ends.y=junction
	return ends

static func paint_streets(image: Image,map: TDTownMap,size: int,miniature: bool=false) -> void:
	if not map.region_id.is_empty() or map.layout_version!=2: return
	_materials()
	var roads := _street_rows()
	var caps: Array[Vector2]=[]
	for rect: Rect2i in roads: caps.append(_ends(rect,roads))
	var bridge_ends := {}
	for row: Array in TDLegacyJiangnanLayout.definition().bridge_spans:
		var bridge:=Rect2i(row[0],row[1],row[2],row[3])
		for y: int in range(bridge.position.y-2,bridge.end.y+2):
			for x: int in range(bridge.position.x-3,bridge.end.x+3):
				bridge_ends[Vector2i(x,y)]=bridge
	var grid := {}
	for i: int in roads.size():
		var strip := roads[i]
		var horizontal := strip.size.x>strip.size.y
		# Adjacent, separately registered streets can meet at a T without
		# overlapping in the survey. Extend their centre lines into the junction.
		var ext := Vector2i(2,0) if horizontal else Vector2i(0,2)
		var reach := Rect2i(strip.position-ext,strip.size+ext*2)
		for y: int in range(reach.position.y,reach.end.y):
			for x: int in range(reach.position.x,reach.end.x):
				var at := Vector2i(x,y)
				if not map.is_road(x,y) or map.terrain_at(at).surface_type!="stone": continue
				var ids: Vector2i=grid.get(at,Vector2i(-1,-1))
				if horizontal: ids.x=i
				else: ids.y=i
				grid[at]=ids
	var turf_size := _lawn.get_size()
	var paving_size := _stone.get_size()
	for at: Vector2i in grid:
		var ids: Vector2i=grid[at]
		var h := PackedFloat32Array()
		var v := PackedFloat32Array()
		var he := PackedFloat32Array()
		var ve := PackedFloat32Array()
		var hw := PackedFloat32Array()
		var vw := 0.0
		if ids.x>=0:
			h.resize(size)
			he.resize(size)
			hw.resize(size)
			var bridge: Rect2i=bridge_ends.get(at,Rect2i())
			for dx: int in size:
				var along:=at.x+(dx+.5)/size
				he[dx]=maxf(0,maxf(caps[ids.x].x-along,along-caps[ids.x].y))*size
				var mid:=_cross_center(roads[ids.x],along,true)
				var width:=_half_width(roads[ids.x],true)
				if bridge.has_area():
					var approach:=maxf(bridge.position.x-along,along-bridge.end.x)
					var flare:=1.0-smoothstep(0,3.0,approach)
					mid=lerpf(mid,bridge.position.y+bridge.size.y*.5,flare)
					width=lerpf(width,bridge.size.y*.5+.035,flare)
				h[dx]=(mid-at.y)*size
				hw[dx]=width*size
		if ids.y>=0:
			vw=_half_width(roads[ids.y],false)*size
			v.resize(size)
			ve.resize(size)
			for dy: int in size:
				var along:=at.y+(dy+.5)/size
				v[dy]=(_cross_center(roads[ids.y],along,false)-at.x)*size
				ve[dy]=maxf(0,maxf(caps[ids.y].x-along,along-caps[ids.y].y))*size
		for y: int in size:
			var ry := (at.y*size+y)*40/size
			for x: int in size:
				var rx := (at.x*size+x)*40/size
				var dh := absf(y+.5-h[x])-hw[x] if not h.is_empty() else 1e4
				var dv := absf(x+.5-v[y])-vw if not v.is_empty() else 1e4
				if not h.is_empty() and he[x]>0: dh=Vector2(he[x],y+.5-h[x]).length()-hw[x]
				if not v.is_empty() and ve[y]>0: dv=Vector2(ve[y],x+.5-v[y]).length()-vw
				var margin := minf(dh,dv)
				if not h.is_empty() and not v.is_empty():
					# Quarter-round at a street corner, enough room to turn a cart.
					var arc := maxf(0.0,size*.44-absf(dh-dv))
					margin-=arc*arc/(1.76*size)
				margin*=40.0/size
				var grain := absi((rx*73856093)^(ry*19349663))%11
				margin+=(grain-5)*.22
				var ink: Color
				if margin < -1.4:
					ink=_stone.get_pixel(rx%paving_size.x,ry%paving_size.y)
				else:
					var turf := _lawn.get_pixel(rx%turf_size.x,ry%turf_size.y)
					if margin>6.0:
						ink=turf
					else:
						var brick := _stone.get_pixel(rx%paving_size.x,ry%paving_size.y)
						var shoulder := Color("8f8766") if grain%4==0 else brick.lerp(turf,.40)
						ink=shoulder.lerp(turf,clampf((margin+.7)/6.5,0,1))
				if miniature: ink.a=.71 if margin<0.0 else .53
				image.set_pixel(at.x*size+x,at.y*size+y,ink)
	if not miniature and size==TDTownScenery.SCALE:
		for base: Vector2i in Paving.BRIDGE_STEPS:
			for at: Vector2i in [base,base+Vector2i.DOWN]:
				if grid.has(at): Paving._threshold(image,at,size,base)
		for at: Vector2i in Paving.PUDDLES:
			if not grid.has(at): continue
			var uv:=at*size+Vector2i.ONE*(size/2)
			if image.get_pixelv(uv)==_stone.get_pixelv(uv%paving_size):
				Paving._wet_stone(image,at*size,size,Paving.PUDDLES[at])

static func paint_doors(image: Image,map: TDTownMap,size: int) -> void:
	_materials()
	var rows:=_street_rows()
	for id: String in ["hotel","player_diner","commercial_street:bank","market-mid","market-large","snack_street","landmark","competitor"]:
		var plot:=map._by_id(id)
		if plot.is_empty(): continue
		var foot:=Vector2(float(plot.x)+float(plot.w)*.5,float(plot.y+plot.h)-.12)
		var width:=.48
		match id:
			"hotel":
				foot=Vector2(plot.x,plot.y)+Vector2(2.05,6.05)
				width=.65
			"market-mid":
				foot=Vector2(plot.x,plot.y)+Vector2(2.5,2.50)
				width=.48
			"competitor":
				foot=Vector2(plot.x,plot.y)+Vector2(16.0,4.05)
				width=.44
			"snack_street": width=.74
			"player_diner": width=.63
		var best:=99.0
		var goal:=foot
		for rect: Rect2i in rows:
			if rect.size.x<=rect.size.y or foot.x<rect.position.x+.4 or foot.x>rect.end.x-.4: continue
			var y:=_cross_center(rect,foot.x,true)
			if y>=foot.y and y-foot.y<best:
				goal=Vector2(foot.x,y)
				best=y-foot.y
		if best<7.5:
			_door_path(image,map,foot,goal,size,width,.32 if id!="snack_street" else -.26,id)
			if id=="hotel":
				var gate:=Vector2(plot.x+.5,plot.y+9.28)
				var street_goal:=Vector2(gate.x,goal.y)
				for rect: Rect2i in rows:
					if rect.size.x>rect.size.y and Rect2(rect).has_point(goal):
						street_goal.y=_cross_center(rect,gate.x,true)
						break
				_door_path(image,map,foot,gate,size,.42,-.33,id)
				_door_path(image,map,gate,street_goal,size,.46,.12,id)
		if id=="landmark":
			var deck:=TDPlannedTown.pavilion_landing()
			var landing:=Vector2(deck.end.x,deck.position.y+.53)
			_door_path(image,map,foot,landing,size,.34,.26,id)

static func connect_site(image: Image,map: TDTownMap,site: Dictionary,size: int,roads: Array[Rect2i]) -> void:
	var side: Vector2i=site.side
	var curb: Vector2i=site.edge+side*site.depth
	var start:=Vector2(curb)+Vector2.ONE*.5-Vector2(side)*.49
	for rect: Rect2i in roads:
		var horizontal:=rect.size.x>rect.size.y
		if horizontal!=(side.y!=0) or not rect.has_point(curb): continue
		var goal:=start
		if horizontal: goal.y=_cross_center(rect,start.x,true)
		else: goal.x=_cross_center(rect,start.y,false)
		_door_path(image,map,start,goal,size,.21,.10,"")
		return

static func square_gates(image: Image,map: TDTownMap,size: int,roads: Array[Rect2i]) -> void:
	var court:=TDTownScenery.PublicSquare.bounds(map)
	for gate: Dictionary in TDTownScenery.PublicSquare.entrances(map,court):
		var side: Vector2i=gate.side
		var start:=Vector2(gate.edge)+Vector2.ONE*.5+Vector2(side)*.12
		var curb: Vector2i=gate.edge+side*gate.depth
		var throat:=Vector2(curb)+Vector2.ONE*.5
		_door_path(image,map,start,throat,size,.56,0.0,"plaza")
		for rect: Rect2i in roads:
			var horizontal:=rect.size.x>rect.size.y
			if not rect.has_point(curb): continue
			var goal:=throat
			if horizontal: goal.y=_cross_center(rect,throat.x,true)
			else: goal.x=_cross_center(rect,throat.y,false)
			_door_path(image,map,throat,goal,size,.54,.055,"plaza")
			break

static func _door_path(image: Image,map: TDTownMap,start: Vector2,finish: Vector2,size: int,half_width: float,bend: float,id: String) -> void:
	var axis:=finish-start
	var length:=axis.length()
	if length<.08: return
	var dir:=axis.normalized()
	var side:=dir.orthogonal()
	var bounds:=Rect2(start,Vector2.ZERO).expand(finish).grow(half_width+absf(bend)+.22)
	var cells:=Rect2i(Vector2i(bounds.position.floor()),Vector2i(bounds.end.ceil()-bounds.position.floor()))
	var ink_size:=_stone.get_size()
	for y: int in range(cells.position.y,cells.end.y):
		for x: int in range(cells.position.x,cells.end.x):
			var at:=Vector2i(x,y)
			var info:=map.terrain_at(at)
			if info.terrain_type!="plain" or (map.is_road(x,y) and info.surface_type!="stone"): continue
			var blocked:=false
			for plot: Dictionary in map.plots:
				if plot.id in [id,"diner_lot","commercial_street"]: continue
				if Rect2i(plot.x,plot.y,plot.w,plot.h).has_point(at):
					blocked=true
					break
			if blocked: continue
			for py: int in size:
				for px: int in size:
					var pos:=Vector2(at)+(Vector2(px,py)+Vector2.ONE*.5)/size
					var rel:=pos-start
					var along:=rel.dot(dir)
					var t:=clampf(along/length,0.0,1.0)
					var perpendicular:=absf(rel.dot(side)-bend*sin(PI*t))
					var cap:=maxf(0.0,maxf(-along,along-length))
					if cap>0.0: perpendicular=Vector2(perpendicular,cap*1.35).length()
					var p:=at*size+Vector2i(px,py)
					var uv:=Vector2i(floori(float(p.x)*40/size),floori(float(p.y)*40/size))
					var chips:=absi((uv.x*73856093)^(uv.y*19349663))%7
					var edge:=(half_width-perpendicular)*40.0+(chips-3)*.33
					if edge < -2.0: continue
					var fresh:=_stone.get_pixelv(uv%ink_size)
					if id in ["market-mid","market-large","competitor"]:
						fresh=fresh.lerp(Color("967656"),.36)
					var under:=image.get_pixelv(p)
					var alpha:=clampf((edge+2.0)/3.8,0,1)
					image.set_pixelv(p,fresh if alpha>=1.0 else under.lerp(fresh,alpha))
