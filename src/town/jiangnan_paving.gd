extends RefCounted
## 江南 streetwork in terrain-image pixels. The eight neighbours come from the
## same surveyed cells as the walkable map. All weathering sits inside a road.

const DISTRICT_ATLAS := preload("res://assets/town/district-surfaces-v1.png")
const SWATCH_SIZE := 210
const GRASS := ["lawn","woodland","grass"]
const CORNERS := [Vector2i(-1,-1),Vector2i(1,-1),Vector2i(-1,1),Vector2i(1,1)]
const PUDDLES := {
	Vector2i(12,14):1, Vector2i(21,38):3, Vector2i(38,35):5,
	Vector2i(46,24):2, Vector2i(63,39):4, Vector2i(49,46):6,
	Vector2i(58,16):1, Vector2i(36,54):4, Vector2i(12,70):3,
}
# Shallow threshold courses on the street side of the three public crossings.
const BRIDGE_STEPS := [Vector2i(52,15),Vector2i(56,23),Vector2i(52,45)]

static func stone_swatch() -> Image:
	var atlas := DISTRICT_ATLAS.get_image()
	if atlas.is_compressed(): atlas.decompress()
	atlas.convert(Image.FORMAT_RGBA8)
	# First region, lane column. Inset the two-pixel gutter around the print.
	var area := Rect2i(0,0,roundi(atlas.get_width()/4.0),roundi(atlas.get_height()/5.0))
	var stone := atlas.get_region(area.grow(-2))
	stone.resize(SWATCH_SIZE,SWATCH_SIZE,Image.INTERPOLATE_NEAREST)
	# The photographed courses end at different heights on opposite edges.
	# Mirror alternate panels so every slab and every joint crosses the seam.
	var area_local := Rect2i(Vector2i.ZERO,stone.get_size())
	var panel := Image.create(SWATCH_SIZE*2,SWATCH_SIZE*2,false,Image.FORMAT_RGBA8)
	panel.blit_rect(stone,area_local,Vector2i.ZERO)
	stone.flip_x()
	panel.blit_rect(stone,area_local,Vector2i(SWATCH_SIZE,0))
	stone.flip_y()
	panel.blit_rect(stone,area_local,Vector2i(SWATCH_SIZE,SWATCH_SIZE))
	stone.flip_x()
	panel.blit_rect(stone,area_local,Vector2i(0,SWATCH_SIZE))
	return panel

static func finish_cell(image: Image, at: Vector2i, surfaces: Dictionary, grass: Image, size: int) -> void:
	if PUDDLES.has(at): _wet_stone(image,at*size,size,PUDDLES[at])
	for bank: Vector2i in BRIDGE_STEPS:
		if at==bank or at==bank+Vector2i.DOWN: _threshold(image,at,size,bank)
	var left: bool = surfaces.get(at+Vector2i.LEFT) in GRASS
	var right: bool = surfaces.get(at+Vector2i.RIGHT) in GRASS
	var top: bool = surfaces.get(at+Vector2i.UP) in GRASS
	var bottom: bool = surfaces.get(at+Vector2i.DOWN) in GRASS
	var inside_corners: Array[Vector2i]=[]
	for side: Vector2i in CORNERS:
		var horizontal := left if side.x<0 else right
		var vertical := top if side.y<0 else bottom
		if not horizontal and not vertical and surfaces.get(at+side) in GRASS:
			inside_corners.append(side)
	if not (left or right or top or bottom) and inside_corners.is_empty(): return
	var origin := at*size
	var upper := _verge(origin.x,origin.y,-1,size)
	var lower := _verge(origin.x,origin.y+size,1,size)
	var west := _verge(origin.y,origin.x,-1,size)
	var east := _verge(origin.y,origin.x+size,1,size)
	var west_bridge: bool = surfaces.get(at+Vector2i.LEFT)=="bridge"
	var east_bridge: bool = surfaces.get(at+Vector2i.RIGHT)=="bridge"
	# At an abutment the path opens to the complete width of the registered deck.
	for x: int in size:
		var flare := 1.0
		if west_bridge: flare=smoothstep(0.0,float(size-1),x)
		if east_bridge: flare=smoothstep(0.0,float(size-1),size-1-x)
		upper[x]*=flare
		lower[x]*=flare
	var texture_size := grass.get_size()
	for y: int in size:
		var py := origin.y+y
		var left_depth := west[y]
		var right_depth := east[y]
		for x: int in size:
			var across := float(size)
			var along := float(size)
			if left: across=x+.5-left_depth
			if right: across=minf(across,size-x-.5-right_depth)
			if top: along=y+.5-upper[x]
			if bottom: along=minf(along,size-y-.5-lower[x])
			# Rounded outer nose where two lawn edges meet.
			var overlap := maxf(0.0,size*.68-absf(across-along))
			var clearance := minf(across,along)-overlap*overlap/(size*2.72)
			# At a T or L the diagonal lawn curls into the adjoining junction,
			# joining the verges on both sides with a quarter-ellipse.
			for side: Vector2i in inside_corners:
				var dx := x+.5 if side.x<0 else size-x-.5
				var dy := y+.5 if side.y<0 else size-y-.5
				var rx := left_depth if side.x<0 else right_depth
				var ry := upper[x] if side.y<0 else lower[x]
				var u := dx/maxf(.5,rx)
				if u<1.0:
					clearance=minf(clearance,dy-ry*sqrt(1.0-u*u))
			if clearance>4.0: continue
			var pixel := Vector2i(origin.x+x,py)
			var turf := grass.get_pixelv(pixel%texture_size)
			# Grass tips break up the silhouette; a narrow moss seam follows
			# the actual slab faces. Both samplers remain world-aligned.
			var face := image.get_pixelv(pixel)
			var edge := clearance-(turf.get_luminance()-.43)*10.0-(.43-face.get_luminance())*5.0
			if edge<0.0:
				image.set_pixelv(pixel,turf)
			elif edge<2.5:
				var joint := face.lerp(turf.darkened(.30),.80-edge*.24)
				image.set_pixelv(pixel,joint)

static func _verge(start: int, boundary: int, side: int, size: int) -> PackedFloat32Array:
	var depths := PackedFloat32Array()
	depths.resize(size)
	for i: int in size:
		var t := float(start+i)/size
		var phase := float(boundary)/size*.073
		# On opposite sides the offsets run in opposite directions, shifting
		# the path's centre across the public right of way.
		var bend := .225*sin(t*.73+phase)+.079*sin(t*1.64-phase)
		var chips := .016*sin(t*16.0+phase)
		depths[i]=size*(.335+side*bend+chips)
	return depths

static func _wet_stone(image: Image, origin: Vector2i, size: int, seed: int) -> void:
	var center := origin+Vector2i(size/2,size/2)
	var radius := 12+seed
	for dy: int in range(-6,7):
		for dx: int in range(-radius,radius+1):
			var u := float(dx)/radius
			var v := (dy+1.45*sin(3.8*u+seed))/(3.6+.26*seed)
			var depth := 1.0-u*u-v*v
			if depth<=0: continue
			var p := center+Vector2i(dx,dy)
			var reflection := Color("52666b").lerp(Color("99b2b4"),clampf(.45-v*.55+u*.2,0,1))
			var wet := image.get_pixelv(p).lerp(reflection,.67)
			if depth<.23 and v>.0: wet=wet.darkened(.14)
			if (dy==-1 and dx>0 and dx<radius-3) or (dy==1 and dx<-4 and dx>-10):
				wet=wet.lerp(Color("d0dcd8"),.76)
			image.set_pixelv(p,wet)

static func _threshold(image: Image, at: Vector2i, size: int, bank: Vector2i) -> void:
	# Three broad worn treads run across the two-cell bridge entrance.
	var west_bank := bank.x==52
	var origin := at*size
	for y: int in size:
		var along := y+(at.y-bank.y)*size
		if along<5 or along>=2*size-5: continue
		for depth: int in 18:
			var pixel := origin+Vector2i(size-1-depth if west_bank else depth,y)
			var tread := depth/6
			var joint := posmod(along+tread*8,24)
			var cut := image.get_pixelv(pixel).lerp(Color("92958d"),.59)
			if depth%6==5 or joint==0: cut=cut.darkened(.24)
			elif depth%6==4: cut=cut.lightened(.24)
			image.set_pixelv(pixel,cut)
