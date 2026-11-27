extends SceneTree
## Exercise the walking controllers, plus actual sprite depth at the doorway and behind the roof.
var failed := 0
var total := 0
var out := "res://artifacts/building-contacts/source"
var view: SubViewport
var actor: TDKitchenPlayer
var world: Node2D
const ISLAND_BUILDINGS := ["house","hall","chapel","forge","inn","mill","gable","twins","thatch","market","shop","passenger-station",
	"shrine","produce","stage","bank","office","tower","fish","bath","port"]
var cam: Camera2D
var profile: TDGameProfile

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	total+=1
	if not value: failed+=1
	print(("PASS " if value else "FAIL ")+label)

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): out=arg.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(out)
	profile=TDGameProfile.new()
	for town: String in ["paris","tokyo","chengdu"]:
		await visit(town)
	profile.close()
	print("BUILDING_CONTACTS checks=",total," failures=",failed)
	quit(1 if failed else 0)

func visit(town: String) -> void:
	view=SubViewport.new()
	view.size=Vector2i(600,430)
	view.disable_3d=true
	view.world_2d=World2D.new()
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var building: Sprite2D
	if town=="chengdu":
		var home:=TDTownWorld.new()
		home.player_mode=true
		home.session=profile.world
		home.characters=profile.characters
		view.add_child(home)
		actor=home._player
		building=home._reference_map.get_node("Props/west_upper_homes")
		world=home
	else:
		var visit_world:=TDTravelWorld.new()
		visit_world.town_id=town
		visit_world.map=TDTravelCatalog.map_for(profile,town)
		view.add_child(visit_world)
		building=visit_world._island.get_node("TownHall" if town=="paris" else "Bank004")
		visit_world._layer.hide()
		actor=visit_world.player
		world=visit_world
	world.set_process(false)
	for layer: Node in world.get_children():
		if layer is CanvasLayer: layer.visible=false
	world.set_day_minute(720)
	check_walls(town)
	if town=="chengdu":
		var props := (world as TDTownWorld)._reference_map.get_node("Props")
		var home := world as TDTownWorld
		var walkers := home.characters
		var edges := 0
		var all_clear := true
		for quarter: int in range(8,22):
			walkers.clock.minute = quarter*60
			for n: int in 80:
				walkers.advance(.24)
				for person: Dictionary in walkers.visible_people():
					if person.route.is_empty(): continue
					edges+=1
					var feet := Vector2(person.position)+TDCharacterRoster.FOOT_OFFSET
					if not home._reference_escort_can_stand(feet): all_clear=false
		check(edges>20 and all_clear,"resident feet cleared the same obstacles on "+str(edges)+" moving samples")
		for sample: Array in [
				["plaza_banyan",Vector2(.50,.89),true], ["plaza_banyan",Vector2(.20,.54),false],
				["square_cart",Vector2(.56,.81),true],
				["square_storyteller_desk",Vector2(.48,.62),true],
				["square_storyteller_desk",Vector2(.10,.83),true],
				["square_storyteller_desk",Vector2(.89,.83),true]]:
			var prop := props.get_node(str(sample[0])) as Sprite2D
			var visual := prop.global_transform * prop.get_rect()
			check(world._can_stand(visual.position+visual.size*Vector2(sample[1]))!=sample[2],
				"Jiangnan fixture "+str(sample[0])+" "+str(sample[1]))
	var bounds:=building.global_transform*building.get_rect()
	cam=Camera2D.new()
	world.add_child(cam)
	cam.global_position=bounds.get_center()+Vector2(0,16)
	cam.zoom=Vector2.ONE*minf(1.1,335.0/bounds.size.y)
	cam.make_current()
	# Sample masonry in the middle of the facade, above the old one-row foundation.
	for uv: Vector2 in [Vector2(.24,.67),Vector2(.5,.65),Vector2(.76,.67)]:
		check(not world._can_stand(bounds.position+uv*bounds.size),town+" closed wall "+str(uv))
	for dir: Vector2 in [Vector2.RIGHT,Vector2.LEFT,Vector2.DOWN,Vector2.UP]:
		var target:=bounds.position+bounds.size*Vector2(.50,.68)
		if dir==Vector2.UP: target.y=bounds.end.y-9
		# Start at clear ground directly outside this wall on the same approach line.
		var start:=target
		var found:=false
		for n: int in range(1,ceili(bounds.size.length()/2)+30):
			start=target-dir*(n*2.0)
			if not world._can_stand(start): continue
			if not world._can_stand(start-dir*14): continue
			found=true
			break
		check(found,town+" approach exists "+str(dir))
		if not found: continue
		actor.position=start-dir*12
		var origin:=actor.position
		var action:=str({Vector2.RIGHT:"world_right",Vector2.LEFT:"world_left",Vector2.DOWN:"world_down",Vector2.UP:"world_up"}[dir])
		Input.action_press(action)
		Input.action_press("world_sprint")
		for tick: int in 24: await physics_frame
		Input.action_release(action)
		Input.action_release("world_sprint")
		await physics_frame
		check((actor.position-origin).dot(dir)>3,town+" real input advanced "+str(dir))
		check(world._can_stand(actor.position) and not world._can_stand(actor.position+dir*7),town+" sprint stops at a solid boundary "+str(dir))
		check((target-actor.position).dot(dir)>0,town+" stops outside the masonry sample "+str(dir))
		if dir==Vector2.RIGHT:
			(await frame()).save_png(out.path_join(town+"-side.png"))
		if dir==Vector2.UP:
			(await frame()).save_png(out.path_join(town+"-front.png"))
	await depth(town,building,bounds,true)
	await depth(town,building,bounds,false)
	view.queue_free()
	await process_frame

func check_walls(town: String) -> void:
	var home := world as TDTownWorld
	var visit_world := world as TDTravelWorld
	var props := home._reference_map.get_node("Props") if home!=null else visit_world._island
	var seen:=0
	for node: Node in props.get_children():
		var sprite:=node as Sprite2D
		if sprite==null or not sprite.visible: continue
		var art:=str(sprite.get_meta("art",""))
		if home!=null:
			if not sprite.get_meta("enclosed",false): continue
		elif art not in ISLAND_BUILDINGS: continue
		var bounds:=sprite.global_transform*sprite.get_rect()
		var height:=.59 if art=="port" else .76
		for u: float in [.35,.50,.65]:
			check(not world._can_stand(bounds.position+Vector2(u,height)*bounds.size),town+" wall "+str(sprite.name)+" "+str(u))
		seen+=1
	check(seen>=12,town+" checked individual buildings "+str(seen))
	if visit_world!=null:
		for entry: Dictionary in visit_world._buildings:
			if not entry.plot.has("economic_parcel_id") and not entry.plot.has("branch_id"): continue
			if entry.plot.get("construction",false): continue
			var rect: Rect2=entry.rect
			check(not world._can_stand(rect.position+rect.size*Vector2(.5,.61)),town+" occupied storefront "+str(entry.plot.id))

func frame() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return view.get_texture().get_image()

func visible_difference(a: Color,b: Color) -> bool:
	return maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))>.035

func depth(town: String, building: Sprite2D, bounds: Rect2, behind: bool) -> void:
	actor.position=Vector2(bounds.get_center().x,bounds.position.y+bounds.size.y*.32 if behind else bounds.end.y+12)
	if not behind:
		for gap: int in range(12,48,2):
			actor.position.y=bounds.end.y+gap
			if world._can_stand(actor.position): break
	actor.face(Vector2.DOWN if behind else Vector2.UP)
	check(world._can_stand(actor.position),town+" clear ground "+("behind" if behind else "in front"))
	var hero:=actor.get_node("Sprite2D") as Sprite2D
	# Hide only the visual, so its shadow, camera, input and terrain remain identical.
	actor.reset_physics_interpolation()
	await frame()
	var both:=await frame()
	if behind: both.save_png(out.path_join(town+"-behind.png"))
	hero.hide()
	var building_only:=await frame()
	if behind: building_only.save_png(out.path_join(town+"-empty.png"))
	building.hide()
	var neither:=await frame()
	hero.show()
	var hero_only:=await frame()
	building.show()
	var overlap:=0
	var see_hero:=0
	var region:=Rect2i(hero.get_global_transform_with_canvas()*hero.get_rect()).intersection(Rect2i(Vector2i.ZERO,view.size))
	for y: int in range(region.position.y,region.end.y):
		for x: int in range(region.position.x,region.end.x):
			var vacant:=neither.get_pixel(x,y)
			if not visible_difference(hero_only.get_pixel(x,y),vacant) or not visible_difference(building_only.get_pixel(x,y),vacant): continue
			overlap+=1
			if visible_difference(both.get_pixel(x,y),building_only.get_pixel(x,y)): see_hero+=1
	check(overlap>50,town+" actual painted overlap for depth check")
	var ratio:=float(see_hero)/maxi(1,overlap)
	check(ratio<.07 if behind else ratio>.93,town+" "+("roof hides hero" if behind else "customer visible at door")+" ratio="+str(snappedf(ratio,.001)))
