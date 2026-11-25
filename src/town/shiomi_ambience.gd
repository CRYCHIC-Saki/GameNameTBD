extends Node2D
## Clock-driven scenery. The atlas can render the same scene once at noon.
var minute := 720.0
var daylight := 0.0
var lamps: Array[Sprite2D]=[]
var tidal_feet: Array[Vector2]=[]
var wheel: Sprite2D
var trees: Array[Sprite2D]=[]
var bath: Sprite2D
var steam: ShaderMaterial
var shadow_layer: Node2D
var shadow_materials: Dictionary = {}
var shadow_tail := Vector2(.38,.23)
const CASTERS := ["house","produce","inn","stage","office","port","bank","tower","fish","bath","shrine","torii","mill","wheel","pine","sakura","bamboo","dwarf","lantern"]
const SHADOW_SHADER := preload("res://src/town/shiomi_shadow.gdshader")
var last_shadow_minute := -1
var wildlife: Node2D
var bird_art: Sprite2D
const FEEDING_SPOTS := [Vector2(395,641), Vector2(543,641), Vector2(569,730), Vector2(1020,461)]
const WINDOW_SHADER := preload("res://src/town/shiomi_windows.gdshader")
const SHORE_SHADER := preload("res://src/town/shiomi_waterside.gdshader")
var cascades: Array[ShaderMaterial]=[]
const CURRENT_RUNS := [
	[Vector2(1284,142),Vector2(1277,151),Vector2(1257,164)],
	[Vector2(1270,255),Vector2(1268,268),Vector2(1256,275)],
	[Vector2(136,819),Vector2(145,823),Vector2(152,825)],
	[Vector2(200,845),Vector2(207,854),Vector2(202,867)]]

func _ready() -> void:
	shadow_layer=Node2D.new()
	shadow_layer.name="GroundShadows"
	shadow_layer.z_index=-3
	add_child(shadow_layer)
	shadow_layer.z_as_relative=false
	wildlife=Node2D.new()
	wildlife.name="FoamAndBirds"
	wildlife.z_as_relative=false
	wildlife.z_index=-1
	add_child(wildlife)
	wildlife.draw.connect(_draw_wildlife)
	var shore_inks: Dictionary={}
	for node: Node in get_parent().get_children():
		if node is Polygon2D and str(node.name).begins_with("TidalPile"):
			tidal_feet.append(node.position)
		var sprite:=node as Sprite2D
		if sprite==null: continue
		var art:=str(sprite.get_meta("art",""))
		if sprite.visible and art in ["fall","reef","shore","outcrop","ledge","crag","zen","basin","housewares"]:
			var size_on_ground: Vector2i=Vector2i((sprite.region_rect.size*sprite.scale.abs()).round())
			var key: Array=[art,size_on_ground]
			if not shore_inks.has(key):
				var ink:=ShaderMaterial.new()
				ink.shader=SHORE_SHADER
				var uv:=Rect2(sprite.region_rect.position/sprite.texture.get_size(),sprite.region_rect.size/sprite.texture.get_size())
				ink.set_shader_parameter("atlas_rect",Vector4(uv.position.x,uv.position.y,uv.size.x,uv.size.y))
				ink.set_shader_parameter("map_size",Vector2(size_on_ground))
				ink.set_shader_parameter("cascade",art=="fall")
				if art=="fall": cascades.append(ink)
				shore_inks[key]=ink
			sprite.material=shore_inks[key]
		if sprite.visible and art in CASTERS:
			var bounds:=sprite.get_rect()
			var foot:=sprite.position+Vector2(0,bounds.end.y*sprite.scale.y)
			register_ground_shadow(sprite,foot,bounds.size*sprite.scale.abs())
		if art=="pigeons":
			bird_art=sprite
			sprite.hide()
		if art in ["house","produce","inn","stage","office","port","bank"]:
			var material:=ShaderMaterial.new()
			material.shader=WINDOW_SHADER
			var r:=sprite.region_rect
			var size:=sprite.texture.get_size()
			material.set_shader_parameter("atlas_rect",Vector4(r.position.x/size.x,r.position.y/size.y,r.size.x/size.x,r.size.y/size.y))
			material.set_shader_parameter("max_window_y",.60 if art=="produce" else .85)
			sprite.material=material
			lamps.append(sprite)
		if art=="sakura": trees.append(sprite)
		if art=="wheel": wheel=sprite
		if art=="bath":
			bath=sprite
			var pool_size := sprite.get_rect().size*sprite.scale
			var plume := Polygon2D.new()
			plume.name="OnsenSteam"
			plume.position=sprite.position+pool_size*Vector2(-.39,-.26)-Vector2(0,54)
			plume.polygon=PackedVector2Array([Vector2.ZERO,Vector2(70,0),Vector2(70,54),Vector2(0,54)])
			steam=ShaderMaterial.new()
			steam.shader=preload("res://src/town/shiomi_steam.gdshader")
			plume.material=steam
			add_child(plume)
	set_minute(minute)

func set_minute(value: float) -> void:
	if value==minute and last_shadow_minute>=0: return
	minute=value
	var light:=TDDaylight.sample(value)
	get_parent().modulate=light.tint
	if daylight!=light.lamps:
		daylight=light.lamps
		for sprite: Sprite2D in lamps:
			(sprite.material as ShaderMaterial).set_shader_parameter("lamps",daylight)
	if wheel!=null: wheel.rotation=fmod(value*.48,TAU)
	if steam!=null: steam.set_shader_parameter("game_minute",value)
	for ink: ShaderMaterial in cascades: ink.set_shader_parameter("game_minute",value)
	queue_redraw()
	if wildlife!=null: wildlife.queue_redraw()
	if shadow_layer!=null and int(minute)!=last_shadow_minute:
		last_shadow_minute=int(minute)
		var low_sun:=smoothstep(0,360,absf(minute-735))
		shadow_tail=Vector2(.38+.25*low_sun,.23+.14*low_sun)
		shadow_layer.modulate.a=lerpf(.44,.13,daylight)
		for shadow: Node2D in shadow_layer.get_children():
			shadow.transform=Transform2D(Vector2.RIGHT,-shadow_tail,shadow.position)

func register_ground_shadow(sprite: Sprite2D,foot: Vector2,size: Vector2) -> void:
	var texture:=sprite.texture
	var region:=sprite.region_rect if sprite.region_enabled else Rect2(Vector2.ZERO,texture.get_size())
	if texture is AtlasTexture:
		var sub:=texture as AtlasTexture
		region.position+=sub.region.position
		texture=sub.atlas
	var extent:=texture.get_size()
	var uv_rect:=Rect2(region.position/extent,region.size/extent)
	if not shadow_materials.has(uv_rect):
		var ink:=ShaderMaterial.new()
		ink.shader=SHADOW_SHADER
		ink.set_shader_parameter("atlas_rect",Vector4(uv_rect.position.x,uv_rect.position.y,uv_rect.size.x,uv_rect.size.y))
		shadow_materials[uv_rect]=ink
	var shadow:=Polygon2D.new()
	shadow.texture=texture
	shadow.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
	shadow.material=shadow_materials[uv_rect]
	var vertices:=PackedVector2Array()
	var uv:=PackedVector2Array()
	# Pad the silhouette so its softened tips can reach outside the sprite frame.
	for point: Vector2 in [Vector2(-.55,-1.09),Vector2(.55,-1.09),Vector2(.55,.09),Vector2(-.55,.09)]:
		vertices.append(point*size)
		var u:=.5-point.x if sprite.flip_h else .5+point.x
		uv.append(region.position+Vector2(u,point.y+1)*region.size)
	shadow.polygon=vertices
	shadow.uv=uv
	shadow.transform=Transform2D(Vector2.RIGHT,-shadow_tail,foot)
	shadow_layer.add_child(shadow)

# Feeding and splashing use the same clock as the wheel. The atlas can hold
# exactly the same pose as a paused walking scene at a particular minute.
func _draw_wildlife() -> void:
	for i: int in FEEDING_SPOTS.size():
		var t:=minute*.64+i*2.7
		var cycle:=sin(t*.35)
		var facing:=-1.0 if cos(t*.35)>0 else 1.0
		var foot: Vector2=(FEEDING_SPOTS[i]+Vector2(6*cycle,2*cos(t*.53))).round()
		wildlife.draw_set_transform(foot,0,Vector2(facing,1))
		wildlife.draw_rect(Rect2(-4,0,8,1),Color("#404e496a"))
		if bird_art!=null:
			var crop:=bird_art.region_rect
			crop.size.x=floorf(crop.size.x*.49)
			var peck:=smoothstep(.18,.93,sin(t*2.5))
			var h:=10.0-2.2*peck
			var w:=h*crop.size.x/crop.size.y+peck*2
			wildlife.draw_set_transform(foot,-.58*peck*facing,Vector2(facing,1))
			wildlife.draw_texture_rect_region(bird_art.texture,Rect2(-w*.39,-h,w,h),crop)
	wildlife.draw_set_transform_matrix(Transform2D.IDENTITY)
	for foot: Vector2 in tidal_feet:
		for ring: int in 2:
			var age:=fposmod(minute*.26+foot.x*.014+ring*.49,1.0)
			wildlife.draw_set_transform(foot,0,Vector2(1,.33))
			wildlife.draw_arc(Vector2.ZERO,3+age*8,.09,PI-.28,12,Color(.73,.87,.83,.65*sin(age*PI)),1)
	wildlife.draw_set_transform_matrix(Transform2D.IDENTITY)
	for at: Vector2 in [Vector2(1288,675),Vector2(1168,632),Vector2(1162,757),Vector2(1047,733),Vector2(726,980),Vector2(312,934),Vector2(49,851)]:
		for i: int in 4:
			var phase:=fposmod(minute*.19+i*.27+at.x*.1,1.0)
			var p:=(at+Vector2(i*5,phase*3+sin(i))).round()
			wildlife.draw_rect(Rect2(p,Vector2(2+i%3,1)),Color(.76,.89,.85,sin(phase*PI)*.68))

func _draw() -> void:
	if bath==null: return
	for i: int in trees.size():
		var anchor:=trees[i].position
		for j: int in 3:
			var t:=fposmod(minute*.13+i*.317+j*.38,1.0)
			var p:=anchor+Vector2((j-1)*16+sin(t*6+i)*11+t*14,-48+t*55)
			draw_rect(Rect2(p.round(),Vector2(2,1.3)),Color(1,.67,.78,sin(PI*t)))
	for run: Array in CURRENT_RUNS:
		var start: Vector2=run[0]
		for i: int in 2:
			var age:=fposmod(minute*.19+start.x*.031+i*.5,1.)
			var tip:=start.bezier_interpolate(run[1],run[1],run[2],age)
			var tail:=start.bezier_interpolate(run[1],run[1],run[2],maxf(0.,age-.12))
			draw_line(tail.round(),tip.round(),Color(.72,.83,.74,.36*sin(age*PI)),1.)
	for basin: Vector3 in [Vector3(1284,140,9),Vector3(1260,200,11),Vector3(1500,397,15),Vector3(214,929,12),Vector3(177,806,5)]:
		for i: int in 3:
			var age:=fposmod(minute*.33+i/3.+basin.x*.019,1.)
			var center:=Vector2(basin.x+sin(i*2.5),basin.y+age*2.)
			draw_set_transform(center,0,Vector2(1,.32))
			var radius:=2.+age*basin.z
			draw_arc(Vector2.ZERO,radius,.28+i*.12,1.35+i*.31,10,Color(.75,.85,.79,sin(age*PI)*.38),1)
	draw_set_transform_matrix(Transform2D.IDENTITY)
