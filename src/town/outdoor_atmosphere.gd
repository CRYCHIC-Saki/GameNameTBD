extends Node2D
## Shared outdoor effects sample the simulation clock, including when a map is paused.
const WATER := preload("res://src/town/outdoor_water.gdshader")
const GRADE := preload("res://src/town/outdoor_grade.gdshader")
const FOAM := preload("res://src/town/shore_foam.gdshader")
const FIXTURE := preload("res://src/town/egret_fixture.gdshader")
const SHADOWS := preload("res://src/town/jiangnan_sun_shadows.gd")
const EUROPEAN_BUILDINGS := ["hall","chapel","gable","twins","thatch","inn","shop","mill","passenger-station","forge"]

var clock_materials: Array[ShaderMaterial] = []
var illuminated: Array[ShaderMaterial] = []
var minute := -1.0
var sunlight: Node2D
var chimney := Vector2.ZERO
var pixel_size := 1.0
var has_chimney := false
var _evening := -1.0

func _ready() -> void:
	var scene := get_parent() as Node2D
	var extent: Vector2
	z_index = 2
	if scene.has_node("Sea1"):
		extent = Vector2(2263,1085)
		_add_water(scene, "Sea1", false)
		_european_port(scene)
	elif scene.has_node("Weather"):
		extent = Vector2(1536,1024)
		_add_water(scene, "Sea", false)
		_add_water(scene, "Watercourse", true)
	else:
		pixel_size = 73.0*90/1670
		extent = Vector2(1670,941)*pixel_size
		_add_water(scene, "Water", true)
		_set_chimney(scene.get_node("Props/forge"),Vector2(.78,.06))
	var grade := Polygon2D.new()
	grade.name = "ColorGrade"
	grade.polygon = PackedVector2Array([Vector2.ZERO,Vector2(extent.x,0),extent,Vector2(0,extent.y)])
	grade.material = _ink(GRADE)
	grade.z_index = 50
	add_child(grade)
	set_minute(720)

func _ink(shader: Shader) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = shader
	return mat

func _add_water(scene: Node2D, layer_name: String, river: bool) -> void:
	var water := _ink(WATER)
	water.set_shader_parameter("river", river)
	water.set_shader_parameter("world_per_pixel", scene.global_scale.abs()*pixel_size)
	water.set_shader_parameter("map_origin", scene.global_position)
	scene.get_node(layer_name).material = water
	clock_materials.append(water)

func _european_port(scene: Node2D) -> void:
	sunlight = SHADOWS.new()
	sunlight.name = "SunShadows"
	sunlight.z_index = -2
	sunlight.z_as_relative = false
	add_child(sunlight)
	var foam := _ink(FOAM)
	clock_materials.append(foam)
	var fixtures := {}
	for prop: Node in scene.get_children():
		if prop is Polygon2D:
			var id := String(prop.name)
			if id.begins_with("GroundShade"): prop.self_modulate.a = .49
			if id.begins_with("Seafoam") or id.begins_with("BreakingCrest") or id.begins_with("FoamEddy") or id.begins_with("BrokenFoam") or id.begins_with("Spray"):
				prop.material = foam
		var sprite := prop as Sprite2D
		if sprite==null: continue
		var art := str(sprite.get_meta("art",""))
		if art not in EUROPEAN_BUILDINGS and art not in ["lamp","fountain"]: continue
		if not fixtures.has(art):
			var mat := _ink(FIXTURE)
			var rect := sprite.region_rect
			var pixels := sprite.texture.get_size()
			mat.set_shader_parameter("frame",Vector4(rect.position.x/pixels.x,rect.position.y/pixels.y,rect.size.x/pixels.x,rect.size.y/pixels.y))
			mat.set_shader_parameter("fixture",{"lamp":1,"fountain":2,"forge":3}.get(art,0))
			fixtures[art] = mat
			if art in ["fountain","forge"]: clock_materials.append(mat)
			if art!="fountain": illuminated.append(mat)
		sprite.material = fixtures[art]
		if art=="forge": _set_chimney(sprite,Vector2(.34,.045))

func _set_chimney(sprite: Sprite2D, outlet: Vector2) -> void:
	var bounds := sprite.get_rect()
	chimney = to_local(sprite.to_global(bounds.position + bounds.size* outlet))
	has_chimney = true

func set_minute(value: float) -> void:
	if minute==value: return
	minute = value
	for mat: ShaderMaterial in clock_materials: mat.set_shader_parameter("game_minute",value)
	if sunlight!=null: sunlight.set_day_minute(value)
	var dusk := float(TDDaylight.sample(value).lamps)
	if dusk!=_evening:
		_evening = dusk
		for mat: ShaderMaterial in illuminated: mat.set_shader_parameter("evening",dusk)
	if has_chimney: queue_redraw()

func _draw() -> void:
	if not has_chimney: return
	for i: int in 7:
		var age := fposmod(minute*.088 + i/7.0,1.0)
		var drift := Vector2(17.0*age*age+2.2*sin(6.0*age+i)*age, -30*age)
		var center := chimney + drift.round()*pixel_size
		var r := (1.0+3.8*age)*pixel_size
		var opacity := (.36-.20*age)*sin(PI*age)
		draw_circle(center,r,Color(.88,.89,.86,opacity),true,-1,false)
		draw_circle(center+Vector2(r*.7,-r*.35),r*.72,Color(.96,.95,.88,opacity*.67),true,-1,false)
