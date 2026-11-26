extends SceneTree
## Generated art only; retain source atlas footprints, masks and all map geometry.
const ROOT := "res://artifacts/pixel-map-20261126/"

func crop_white_bars(image: Image) -> Image:
	var first := -1
	var last := -1
	for y: int in image.get_height():
		var painted := 0
		for x: int in range(0,image.get_width(),8):
			var c := image.get_pixel(x,y)
			if c.a>.1 and minf(c.r,minf(c.g,c.b)) < .90 and maxf(c.r,maxf(c.g,c.b))>.10: painted += 1
		if painted > image.get_width()/24:
			if first < 0: first=y
			last=y
	return image.get_region(Rect2i(0,first,image.get_width(),last-first+1)) if first>=0 else image

func join_edges(image: Image) -> void:
	# Shared boundary pixels guarantee exact four-way repetition of individual materials.
	for y: int in image.get_height():
		var c := image.get_pixel(0,y).lerp(image.get_pixel(image.get_width()-1,y),.5)
		c.a=minf(image.get_pixel(0,y).a,image.get_pixel(image.get_width()-1,y).a)
		image.set_pixel(0,y,c); image.set_pixel(image.get_width()-1,y,c)
	for x: int in image.get_width():
		var c := image.get_pixel(x,0).lerp(image.get_pixel(x,image.get_height()-1),.5)
		c.a=minf(image.get_pixel(x,0).a,image.get_pixel(x,image.get_height()-1).a)
		image.set_pixel(x,0,c); image.set_pixel(x,image.get_height()-1,c)

func pack_material(size_value: Vector2i, source: String, cell: int) -> Image:
	var tile := Image.load_from_file(source)
	tile.convert(Image.FORMAT_RGBA8)
	# One broad material patch per logical cell, rather than aliasing a whole sheet
	# into eight noisy pixels. Repeated edge pixels remain identical after packing.
	var patch := maxi(cell,mini(tile.get_width(),tile.get_height())/8)
	tile=tile.get_region(Rect2i((tile.get_width()-patch)/2,(tile.get_height()-patch)/2,patch,patch))
	tile.resize(maxi(2,cell/2),maxi(2,cell/2),Image.INTERPOLATE_NEAREST)
	tile.resize(cell,cell,Image.INTERPOLATE_NEAREST)
	join_edges(tile)
	var canvas := Image.create(size_value.x,size_value.y,false,Image.FORMAT_RGBA8)
	for y: int in range(0,size_value.y,cell):
		for x: int in range(0,size_value.x,cell):
			canvas.blit_rect(tile,Rect2i(Vector2i.ZERO,Vector2i(cell,cell)),Vector2i(x,y))
	return canvas

func _initialize() -> void:
	var rows: Array = JSON.parse_string(FileAccess.get_file_as_string(ROOT+"generated-assets.json"))
	for row: Dictionary in rows:
		var target: String="res://"+row.target
		var name: String=target.get_file()
		var original := Image.load_from_file(ROOT+"before/"+name)
		var generated := Image.load_from_file(row.generated)
		if original==null or generated==null: quit(1);return
		original.convert(Image.FORMAT_RGBA8); generated.convert(Image.FORMAT_RGBA8)
		if row.has("material"):
			generated=pack_material(original.get_size(),row.material,8)
		elif row.has("material_bands"):
			var canvas := Image.create(original.get_width(),original.get_height(),false,Image.FORMAT_RGBA8)
			for band: Dictionary in row.material_bands:
				var part := pack_material(Vector2i(original.get_width(),int(band.height)),band.source,8)
				canvas.blit_rect(part,Rect2i(Vector2i.ZERO,part.get_size()),Vector2i(0,int(band.y)))
			generated=canvas
		elif row.has("strips"):
			var canvas := Image.create(original.get_width(),original.get_height(),false,Image.FORMAT_RGBA8)
			for strip: Array in row.strips:
				var part := generated.get_region(Rect2i(0,int(strip[0]*generated.get_height()),generated.get_width(),maxi(1,int((strip[1]-strip[0])*generated.get_height()))))
				part.resize(original.get_width(),int(strip[3]),Image.INTERPOLATE_NEAREST)
				canvas.blit_rect(part,Rect2i(Vector2i.ZERO,part.get_size()),Vector2i(0,int(strip[2])))
			generated=canvas
		elif row.get("world_chart",false):
			var canvas := Image.create(original.get_width(),original.get_height(),false,Image.FORMAT_RGBA8)
			canvas.fill(Color("18aaa9"))
			var chart := Rect2i(437,0,1099,580)
			generated.resize(chart.size.x,chart.size.y,Image.INTERPOLATE_NEAREST)
			canvas.blit_rect(generated,Rect2i(Vector2i.ZERO,chart.size),chart.position)
			generated=canvas
		elif row.get("fit_visible",false):
			generated=generated.get_region(generated.get_used_rect())
			var bounds := original.get_used_rect()
			generated.resize(bounds.size.x,bounds.size.y,Image.INTERPOLATE_NEAREST)
			var canvas := Image.create(original.get_width(),original.get_height(),false,Image.FORMAT_RGBA8)
			canvas.blit_rect(generated,Rect2i(Vector2i.ZERO,bounds.size),bounds.position)
			generated=canvas
		else:
			if original.get_width()>original.get_height()*4: generated=crop_white_bars(generated)
			generated.resize(original.get_width(),original.get_height(),Image.INTERPOLATE_NEAREST)
		var grid: int=row.get("grid",1)
		if grid>1:
			generated.resize(maxi(1,original.get_width()/grid),maxi(1,original.get_height()/grid),Image.INTERPOLATE_NEAREST)
			generated.resize(original.get_width(),original.get_height(),Image.INTERPOLATE_NEAREST)
		# Earlier unpainted masks remove pre-existing generation fringe outside real sprites.
		var mask_path := "res://artifacts/story-revision-20261126/original-atlases/"+name
		var mask := Image.load_from_file(mask_path) if FileAccess.file_exists(mask_path) else original
		mask.convert(Image.FORMAT_RGBA8)
		var bytes := generated.get_data()
		var alpha := mask.get_data()
		if not row.get("world_chart",false):
			for a: int in range(3,bytes.size(),4):
				if row.get("preserve_alpha",false): bytes[a]=alpha[a]
				else: bytes[a]=mini(bytes[a],alpha[a]) if alpha[a]>=32 else 0
		generated=Image.create_from_data(original.get_width(),original.get_height(),false,Image.FORMAT_RGBA8,bytes)
		if row.get("seamless",false): join_edges(generated)
		if generated.save_png(target)!=OK: quit(1);return
		print("PIXEL_MAP ",name," size=",generated.get_size()," preserved_canvas=true")
	quit(0)
