extends RefCounted
## Composite each connected crossing after both banks and the water are painted.
## All dimensions are ground-image pixels (two world pixels per image pixel).

const SIDES := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
# Deck, railing, edge highlight, shaded support.
const PALETTES := {
	"chengdu": [Color("#a7aaa1"),Color("#929990"),Color("#dedbcc"),Color("#535f60")],
	"paris": [Color("#c4b69c"),Color("#ad9f88"),Color("#eee2c8"),Color("#655f58")],
	"tokyo": [Color("#a87853"),Color("#ad4b36"),Color("#e9b879"),Color("#573c35")],
}

static func paint(image: Image, surfaces: Dictionary, town: String, size: int) -> void:
	var visited := {}
	for start: Vector2i in surfaces:
		if surfaces[start]!="bridge" or visited.has(start): continue
		# The passenger pier has its own timber deck and bollards in TDHarbor.
		if town=="chengdu" and start.x>=71: continue
		var cells: Array[Vector2i] = [start]
		var bounds := Rect2i(start,Vector2i.ONE)
		visited[start] = true
		var cursor := 0
		while cursor<cells.size():
			var at := cells[cursor]
			cursor += 1
			for side: int in SIDES.size():
				var next: Vector2i = at+SIDES[side]
				var surface: String = surfaces.get(next,"water")
				if surface=="bridge":
					if not visited.has(next):
						cells.append(next)
						visited[next] = true
						bounds = bounds.merge(Rect2i(next,Vector2i.ONE))
		var timber := town == "tokyo"
		var colors: Array = PALETTES[town]
		# Preserve the shore under projected rail caps at concave corners.
		var dry_tiles := {}
		for cell: Vector2i in cells:
			_deck(image,cell,size,bounds,timber,colors)
			for dy: int in range(-1,2):
				for dx: int in range(-1,2):
					var at := cell+Vector2i(dx,dy)
					if surfaces.get(at,"water") in ["bridge","water"] or dry_tiles.has(at): continue
					dry_tiles[at] = image.get_region(Rect2i(at*size,Vector2i.ONE*size))
		for cell: Vector2i in cells:
			for side: Vector2i in SIDES:
				var neighbor: String = surfaces.get(cell+side,"water")
				if neighbor=="water":
					_water_edge(image,cell,size,side,bounds,timber,colors,town=="chengdu")
				elif neighbor!="bridge":
					var strip := Vector2i(size,1) if side.y!=0 else Vector2i(1,size)
					var edge := cell*size+Vector2i(maxi(side.x,0),maxi(side.y,0))*(size-1)
					image.fill_rect(Rect2i(edge,strip),colors[3])
					image.fill_rect(Rect2i(edge-side,strip),colors[2])
		for at: Vector2i in dry_tiles:
			image.blit_rect(dry_tiles[at],Rect2i(Vector2i.ZERO,Vector2i.ONE*size),at*size)

static func _deck(image: Image, cell: Vector2i, size: int, bounds: Rect2i, timber: bool, colors: Array) -> void:
	var floor_color: Color = colors[0]
	var joint := floor_color.darkened(.28)
	var course := 6 if timber else 10
	var length := 60 if timber else 33
	var first := bounds.position.x*size
	var span := bounds.size.x*size
	for y: int in size:
		for x: int in size:
			var p := cell*size+Vector2i(x,y)
			var u := p.x
			var v := p.y
			var strip := u/course
			var end := (v+strip*19)%length
			var grain := absi((strip*37+(v+strip*19)/length*53)%13)-6
			var crest := sin(PI*(u-first+.5)/span)
			var grit := posmod((u*41)^(v*29)^(u/3*19),17)
			var tone := floor_color.lightened(grain*.020+crest*.09-.055)
			if u%course==0 or end==0: tone=joint
			elif u%course==1: tone=tone.lightened(.17)
			elif timber and u%course==4 and (end+strip*3)%27<13: tone=tone.darkened(.10)
			elif timber and (u+end/11)%course==2 and end>22: tone=tone.darkened(.10)
			elif not timber and u%course==course-1: tone=tone.darkened(.085)
			elif not timber and (u*23+v*31)%71<2: tone=tone.darkened(.10)
			elif grit<3: tone=tone.darkened(.050)
			elif grit>13: tone=tone.lightened(.045)
			image.set_pixelv(p,tone)

static func _water_edge(image: Image, cell: Vector2i, size: int, side: Vector2i, bounds: Rect2i, timber: bool, colors: Array, mossy: bool) -> void:
	var across := side.y!=0
	var along := Vector2i.RIGHT if across else Vector2i.DOWN
	var start := cell*size
	if side.x>0: start.x+=size-1
	if side.y>0: start.y+=size-1
	var rail: Color = colors[1]
	var cap: Color = colors[2]
	var shadow: Color = colors[3]
	var visible_face := side in [Vector2i.DOWN,Vector2i.RIGHT]
	# A rhythm of arches (or piles under a timber span) leaves water visible
	# under the lip. The phase advances across cells instead of restarting at tile edges.
	var span := (bounds.size.x if across else bounds.size.y)*size
	var first := (bounds.position.x if across else bounds.position.y)*size
	var arches := maxi(1,roundi(span/85.0))
	for i: int in size:
		var p := start+along*i
		var distance := (p.x if across else p.y)-first
		var t := fposmod((distance+.5)*arches/span,1.0)*2-1
		var depth := 3
		if visible_face:
			depth = 17 if timber and distance%24<4 else 4
			if not timber: depth = 9+roundi(17.0*(1.0-sqrt(maxf(0,1.0-t*t))))
		for n: int in range(1,depth+1):
			var q := p+side*n
			if not Rect2i(Vector2i.ZERO,image.get_size()).has_point(q): break
			var tone := shadow
			if n==depth: tone=shadow.darkened(.30)
			elif not timber and n>=depth-4: tone=rail.lightened(.12) if (distance+roundi(t*n*.5))%10!=0 else shadow
			elif not timber and n>2: tone=rail.darkened(.24) if n%5!=0 and (distance+(n/5)*9)%17!=0 else shadow
			elif n==2: tone=rail.darkened(.12)
			if mossy and n>2 and n<depth and sin(distance*.12)+sin(distance*.049+n*.43)>1.19:
				tone=tone.lerp(Color("67774b"),.61)
			image.set_pixelv(q,tone)
	# The guard rail is set on the deck. Edges facing dry land stay open.
	var edge := Rect2i(start-(side if side.x+side.y>0 else Vector2i.ZERO)*2,Vector2i(size,3) if across else Vector2i(3,size))
	image.fill_rect(edge,shadow)
	var foot_line := start-side*2
	for i: int in size:
		var foot := foot_line+along*i
		var t := (float((foot.x if across else foot.y)-first)+.5)/span
		var rise := roundi(5.0*sin(t*PI)) if across else 0
		if mossy and sin(i*.21+cell.x)+sin(i*.07+cell.y)>1.03:
			image.fill_rect(Rect2i(foot-side*2,Vector2i(2,2)), Color("818856"))
		for lift: int in [6,12]:
			var beam := foot+Vector2i.UP*(rise+lift)
			image.fill_rect(Rect2i(beam,Vector2i(1,3) if across else Vector2i(3,1)),shadow)
			image.fill_rect(Rect2i(beam,Vector2i(1,2) if across else Vector2i(2,1)),rail.lightened(.20))
	for i: int in range(3,size,20):
		var foot := foot_line+along*i
		var t := (float((foot.x if across else foot.y)-first)+.5)/span
		var rise := roundi(5.0*sin(t*PI)) if across else 0
		var post := Rect2i(foot-Vector2i(1,15+rise),Vector2i(5,16+rise))
		image.fill_rect(post,shadow)
		image.fill_rect(post.grow(-1),rail)
		image.fill_rect(Rect2i(post.position+Vector2i(1,1),Vector2i(1,13+rise)),cap)
		image.fill_rect(Rect2i(post.position-Vector2i.ONE,Vector2i(7,3)),rail.darkened(.22))
		image.fill_rect(Rect2i(post.position-Vector2i(0,2),Vector2i(5,2)),cap)
