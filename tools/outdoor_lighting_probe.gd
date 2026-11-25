extends SceneTree
## Draw the production map scenes with an isolated camera at a fixed game minute.
var output := "res://artifacts/three-town-outdoors/frames"
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func verify(condition: bool, label: String) -> void:
	print(("PASS " if condition else "FAIL ")+label)
	if not condition: failures+=1

func run() -> void:
	for option: String in OS.get_cmdline_user_args():
		if option.begins_with("--output="): output=option.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(output)
	for town: String in ["chengdu","tokyo","paris"]:
		await capture(town)
	var profile := TDGameProfile.new()
	for town: String in ["paris","tokyo"]:
		await walk_hover(profile,town)
	profile.close()
	quit(1 if failures else 0)

func walk_hover(profile: TDGameProfile,town: String) -> void:
	var view := SubViewport.new()
	view.disable_3d=true
	view.world_2d=World2D.new()
	view.size=Vector2i(800,540)
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var world := TDTravelWorld.new()
	world.town_id=town
	world.map=TDTravelCatalog.map_for(profile,town)
	view.add_child(world)
	world.set_day_minute(720)
	var cell := Vector2i(-1,-1)
	for y: int in range(5,66):
		for x: int in range(5,66):
			if world.map.branch_ground_available(Vector2i(x,y)) and world.map.branch_ground_available(Vector2i(x+1,y+1)):
				cell=Vector2i(x,y)
				break
		if cell.x>=0: break
	verify(cell.x>=0,town+" free grass in walking map")
	var grass := (Vector2(cell)+Vector2.ONE*.5)*world.cell_size
	world.player.position=grass+Vector2(1.2,1.0)*world.cell_size
	world.camera.position=world.player.position
	world.camera.reset_smoothing()
	await frame(view)
	var screen := world.get_global_transform_with_canvas()*grass
	var patch := Rect2i(Vector2i(screen)-Vector2i(18,18),Vector2i(36,36))
	verify(Rect2i(Vector2i.ZERO,view.size).encloses(patch),town+" grass visible under camera")
	var event := InputEventMouseMotion.new()
	event.position=screen+Vector2(250,0)
	event.global_position=event.position
	view.push_input(event,true)
	var before := (await frame(view)).get_region(patch)
	event=InputEventMouseMotion.new()
	event.position=screen
	event.global_position=screen
	view.push_input(event,true)
	var after := (await frame(view)).get_region(patch)
	verify(Vector2i((world.get_global_mouse_position()/world.cell_size).floor())==cell,town+" real walking cursor over eligible grass")
	verify(before.get_data()==after.get_data(),town+" walking grass stays unchanged under the cursor")
	view.queue_free()
	await process_frame

func frame(view: SubViewport) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return view.get_texture().get_image()

func set_clock(scene: Node2D, value: float) -> void:
	scene.modulate = TDDaylight.sample(value).tint
	scene.get_node("Atmosphere").set_minute(value)
	if scene.has_node("Weather"): scene.get_node("Weather").set_minute(value)
	if scene.has_node("SunShadows"): scene.get_node("SunShadows").set_day_minute(value)

func different(a: Image,b: Image) -> int:
	var count := 0
	for y: int in range(0,a.get_height(),4):
		for x: int in range(0,a.get_width(),4):
			if a.get_pixel(x,y)!=b.get_pixel(x,y): count+=1
	return count

func capture(town: String) -> void:
	var scene: Node2D
	var extent: Vector2
	var layer: String
	match town:
		"chengdu":
			scene=TDJiangnanReferenceArt.make_scene()
			extent=TDJiangnanReferenceArt.WORLD_SIZE
			layer="Water"
		"tokyo":
			scene=TDShiomiArt.instance()
			extent=Vector2(TDShiomiLayout.MAP_SIZE)
			layer="Sea"
		"paris":
			scene=TDEgretLayout.instance()
			extent=Vector2(TDEgretLayout.SIZE)
			layer="Sea1"
	var view := SubViewport.new()
	view.disable_3d=true
	view.world_2d=World2D.new()
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	view.size=Vector2i(1580,roundi(1580*extent.y/extent.x))
	scene.position=Vector2.ZERO
	scene.scale=Vector2.ONE*(1580/extent.x)
	view.add_child(scene)
	root.add_child(view)
	set_clock(scene,720)
	var noon := await frame(view)
	verify(noon.save_png(output.path_join(town+"-noon.png"))==OK,town+" noon panorama")
	verify(noon.get_data()==(await frame(view)).get_data(),town+" frozen clock holds identical pixels")
	var grade: Polygon2D=scene.get_node("Atmosphere/ColorGrade")
	grade.hide()
	var before := await frame(view)
	var changed := different(before,noon)
	verify(changed>1000,town+" grade affects map pixels "+str(changed))
	grade.show()
	var water: ShaderMaterial=scene.get_node(layer).material
	water.set_shader_parameter("game_minute",721.7)
	var ripples := await frame(view)
	changed=different(noon,ripples)
	verify(changed>50,town+" moving water changes pixels "+str(changed))
	water.set_shader_parameter("game_minute",720)
	var atmosphere: Node2D=scene.get_node("Atmosphere")
	if atmosphere.has_chimney:
		var base: Vector2 = scene.transform*atmosphere.chimney
		var scale_px := scene.scale.x*float(atmosphere.pixel_size)
		var plume := Rect2i(Rect2(base+Vector2(-5,-36)*scale_px,Vector2(34,38)*scale_px)).intersection(Rect2i(Vector2i.ZERO,view.size))
		set_clock(scene,720.9)
		var motion := await frame(view)
		verify(noon.get_region(plume).get_data()!=motion.get_region(plume).get_data(),town+" moving chimney plume")
	if town=="paris":
		var shadow: Node2D=atmosphere.sunlight
		set_clock(scene,480)
		var morning: float=shadow.direction.x
		set_clock(scene,1080)
		verify(morning<0 and shadow.direction.x>0 and shadow.strength>0,"European sun changes cast direction")
		var evening := await frame(view)
		verify(evening.save_png(output.path_join(town+"-dusk.png"))==OK,"European dusk panorama")
	set_clock(scene,1320)
	var night := await frame(view)
	verify(night.save_png(output.path_join(town+"-night.png"))==OK,town+" night panorama")
	verify(different(noon,night)>1000,town+" clock changes outdoor lighting")
	if town=="paris":
		verify(atmosphere.sunlight.strength==0 and scene.get_node("TownHall").material.get_shader_parameter("evening")>.99,"European windows lit after sundown")
	view.queue_free()
	await process_frame
