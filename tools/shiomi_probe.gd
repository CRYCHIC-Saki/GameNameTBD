extends SceneTree
## Render the visitable world including the player at the passenger pier.
var out := "res://artifacts/shiomi/"
var failed := false
var checks := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool,note: String) -> void:
	checks+=1
	print(("PASS " if value else "FAIL ")+note)
	if not value: failed=true

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shiomi-output="): out=arg.trim_prefix("--shiomi-output=").path_join("") + "/"
	DirAccess.make_dir_recursive_absolute(out)
	var p:=TDGameProfile.new()
	check(p.error.ok,"new profile")
	var view:=SubViewport.new()
	view.size=Vector2i(1536,1024)
	view.disable_3d=true
	view.world_2d=World2D.new()
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var world:=TDTravelWorld.new()
	world.map=TDTravelCatalog.map_for(p,"tokyo")
	view.add_child(world)
	check(world.nearby().get("kind")=="harbor","arrival at real harbor")
	var start:=world.player.position
	Input.action_press("world_left")
	for i: int in 20: await physics_frame
	Input.action_release("world_left")
	check(world.player.position.distance_to(start)>15,"real player can walk out of port")
	world.set_process(false)
	world._layer.visible=false


	world.player.position=TDShiomiLayout.world_point(Vector2(1332,567))
	var pier_route: Array[Vector2]=[Vector2(1332,579),Vector2(1332,601),Vector2(1332,627),Vector2(1332,656)]
	check(await walk_route(world,pier_route),"real movement from stone quay onto offshore pier")
	Input.action_press("world_down")
	for tick: int in 36: await physics_frame
	Input.action_release("world_down")
	check((world._island.transform.affine_inverse()*world.player.position).y<668.0,"real movement stops at the pier end")
	world.player.position=start
	world.camera.zoom=Vector2.ONE*TDShiomiLayout.PIXELS_PER_CELL/TDTownWorld.CELL
	world.camera.position=TDShiomiLayout.world_point(Vector2(768,512))
	for minute: int in [510,720,1160]:
		world.set_day_minute(minute)
		await process_frame
		await RenderingServer.frame_post_draw
		var img:=view.get_texture().get_image()
		check(img.save_png(out+"shiomi-%d.png"%minute)==OK,"overview "+str(minute))
	world.camera.zoom=Vector2.ONE
	world.camera.position=TDShiomiLayout.world_point(Vector2(440,566))
	await process_frame
	await RenderingServer.frame_post_draw
	check(view.get_texture().get_image().save_png(out+"shiomi-stage-dusk.png")==OK,"stage walking scale")
	world.set_day_minute(720)
	for detail: Array in [["theatre",Vector2(459,617)],["inn",Vector2(796,794)],["harbor",Vector2(1277,603)],["mill",Vector2(180,813)],["headland",Vector2(1254,845)],["tail",Vector2(1238,274)],["homes",Vector2(570,282)],["fence",Vector2(190,670)],["produce",Vector2(405,456)],["shrine-stairs",Vector2(253,228)],["spring",Vector2(1278,156)],["outfall",Vector2(1464,364)]]:
		if detail[0]=="shrine-stairs":
			world.player.position=TDShiomiLayout.world_point(Vector2(254,315))
		world.camera.zoom=Vector2.ONE*1.30 if detail[0]=="mill" else Vector2.ONE
		world.camera.position=TDShiomiLayout.world_point(detail[1])
		await process_frame
		await RenderingServer.frame_post_draw
		check(view.get_texture().get_image().save_png(out+"shiomi-"+detail[0]+".png")==OK,"noon walking scale "+detail[0])
		if detail[0]=="spring":
			var lip: Vector2=world._island.get_global_transform_with_canvas()*Vector2(1260,184)
			var cascade:=Rect2i(Vector2i(lip)-Vector2i(22,23),Vector2i(44,46))
			var still:=view.get_texture().get_image().get_region(cascade).get_data()
			world.set_day_minute(720.40)
			await process_frame
			await RenderingServer.frame_post_draw
			var moving:=view.get_texture().get_image().get_region(cascade).get_data()
			check(moving!=still,"water moves inside the painted cascade")
			await process_frame
			await RenderingServer.frame_post_draw
			check(moving==view.get_texture().get_image().get_region(cascade).get_data(),"cascade holds when game time is frozen")
			if "--capture-flow" in OS.get_cmdline_user_args():
				var frame_size:=Vector2i(420,330)
				var film:=Image.create_empty(frame_size.x*6,frame_size.y*5,false,Image.FORMAT_RGB8)
				for frame: int in 30:
					world.set_day_minute(720.+frame*.10)
					await process_frame
					await RenderingServer.frame_post_draw
					var shot:=view.get_texture().get_image().get_region(Rect2i(Vector2i(lip)-Vector2i(140,210),frame_size))
					shot.convert(Image.FORMAT_RGB8)
					film.blit_rect(shot,Rect2i(Vector2i.ZERO,frame_size),Vector2i(frame%6,frame/6)*frame_size)
				check(film.save_png(out+"cascade-frames.png")==OK,"captured waterfall motion at walking scale")
			world.set_day_minute(720)
		if detail[0]=="homes":
			var shadows:=world._island.get_node("Weather/GroundShadows") as Node2D
			var house: Sprite2D
			for prop in world._island.get_children():
				if prop.get_meta("plot_id","")=="competitor:shop:0": house=prop
			var patch_center:=world._island.get_global_transform_with_canvas()*(house.position+Vector2(14,7))
			var patch:=Rect2i(Vector2i(patch_center)-Vector2i(24,12),Vector2i(48,24))
			var lit:=view.get_texture().get_image().get_region(patch)
			shadows.hide()
			await process_frame
			await RenderingServer.frame_post_draw
			var bare:=view.get_texture().get_image().get_region(patch)
			var darker:=0
			for y: int in lit.get_height():
				for x: int in lit.get_width():
					if bare.get_pixel(x,y).get_luminance()-lit.get_pixel(x,y).get_luminance()>.025:
						darker+=1
			check(darker>100,"multiply shadow darkens the ground southeast of the house")
			shadows.show()
		if detail[0]=="theatre":
			var center: Vector2=world._island.get_global_transform_with_canvas()*Vector2(395,638)
			var area:=Rect2i(Vector2i(center)-Vector2i(42,30),Vector2i(84,60))
			var at_noon:=view.get_texture().get_image().get_region(area).get_data()
			world.set_day_minute(720)
			await process_frame
			await RenderingServer.frame_post_draw
			check(at_noon==view.get_texture().get_image().get_region(area).get_data(),"feeding birds hold pose at a frozen game minute")
			world.set_day_minute(721)
			await process_frame
			await RenderingServer.frame_post_draw
			check(at_noon!=view.get_texture().get_image().get_region(area).get_data(),"feeding birds change pose as the game clock advances")
			world.set_day_minute(720)
	var bath_sprite := world._island.get_node("Bath011") as Sprite2D
	world.camera.position=TDShiomiLayout.world_point(bath_sprite.position)
	world.set_day_minute(720)
	await process_frame
	await RenderingServer.frame_post_draw
	var basin_center := world._island.get_global_transform_with_canvas()*(bath_sprite.position+Vector2(-15,-39))
	var vapor_area := Rect2i(Vector2i(basin_center)-Vector2i(68,52),Vector2i(136,104))
	var first_vapor := view.get_texture().get_image().get_region(vapor_area).get_data()
	world.set_day_minute(720.85)
	await process_frame
	await RenderingServer.frame_post_draw
	var second_vapor := view.get_texture().get_image().get_region(vapor_area).get_data()
	check(first_vapor!=second_vapor,"steam moves above the relocated pool within one game minute")
	await process_frame
	await RenderingServer.frame_post_draw
	check(second_vapor==view.get_texture().get_image().get_region(vapor_area).get_data(),"steam holds at a frozen game clock")
	check(view.get_texture().get_image().save_png(out+"shiomi-onsen.png")==OK,"onsen and ryokan walking scale")
	if "--capture-steam" in OS.get_cmdline_user_args():
		var frame_size:=Vector2i(640,320)
		var film:=Image.create_empty(frame_size.x*6,frame_size.y*6,false,Image.FORMAT_RGBA8)
		var frame_rect:=Rect2i(Vector2i(basin_center)-Vector2i(390,175),frame_size)
		for frame: int in 36:
			world.set_day_minute(720.0+frame*.10)
			await process_frame
			await RenderingServer.frame_post_draw
			film.blit_rect(view.get_texture().get_image(),frame_rect,Vector2i(frame%6,frame/6)*frame_size)
		check(film.save_png(out+"onsen-frames.png")==OK,"recorded rising steam from the game view")
	world.camera.position=TDShiomiLayout.world_point(Vector2(1264,219))
	await walk_bridge(world)
	world.player.position=TDShiomiLayout.world_point(Vector2(1272,218))
	await process_frame
	await RenderingServer.frame_post_draw
	check(view.get_texture().get_image().save_png(out+"shiomi-bridge.png")==OK,"bridge at player scale with correct depth")
	var descent: Array[Vector2]=[Vector2(1212,855),Vector2(1212,870),Vector2(1212,886)]
	world.player.position=TDShiomiLayout.world_point(descent[0])
	check(await walk_route(world,descent),"walk between the bluff shoulders onto the sand")
	descent.reverse()
	check(await walk_route(world,descent),"return from the beach to the plateau")
	var block:=world._island.get_node("FallenBlock01") as Sprite2D
	check(not world._can_stand(TDShiomiLayout.world_point(block.position-Vector2(0,2))),"fallen boulder has a solid foot on sand")
	world.player.position=TDShiomiLayout.world_point(Vector2(521,930))
	Input.action_press("world_up")
	for tick: int in 30: await physics_frame
	Input.action_release("world_up")
	var stopped:=world._island.transform.affine_inverse()*world.player.position
	check(stopped.y>918 and stopped.y<929,"walking from the sand stops at the shore rock's foot")
	check(await walk_route(world,[Vector2(521,929),Vector2(548,929),Vector2(549,914)]),"the player can walk around the shore rock")
	check_reachability(world,start)
	world.queue_free()
	await process_frame
	var atlas:=TDBranchPanel.SiteMap.new()
	atlas.maps={"tokyo":TDTravelCatalog.map_for(p,"tokyo")}
	atlas.size=Vector2(view.size)
	view.add_child(atlas)
	atlas.choose_town("tokyo")
	await process_frame
	await RenderingServer.frame_post_draw
	check(atlas._textures.tokyo is ViewportTexture,"M and site selection render the native tile scene")
	var sample:=atlas.cell_to_screen("tokyo",Vector2(40,36))
	check(atlas._cell(sample+Vector2(.1,.1))==Vector2i(40,36),"siting click addresses the matching cadastral cell")
	var plots: TDTownMap=atlas.maps.tokyo
	var clear_cell:=Vector2i(-1,-1)
	for y: int in range(32,48):
		for x: int in range(37,54):
			if TDShiomiLayout.visible_lawn(Vector2i(x,y)) and plots.branch_ground_available(Vector2i(x,y)):
				clear_cell=Vector2i(x,y)
				break
		if clear_cell.x>=0: break
	check(clear_cell.x>=0,"an unoccupied meadow is available on the local map")
	var hover_point:=atlas.cell_to_screen("tokyo",Vector2(clear_cell)+Vector2.ONE*.5)
	var pointer:=InputEventMouseMotion.new()
	pointer.position=atlas.cell_to_screen("tokyo",Vector2(63.5,42.5))
	pointer.global_position=pointer.position
	view.push_input(pointer,true)
	atlas.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var unmarked:=view.get_texture().get_image().get_pixelv(Vector2i(hover_point))
	pointer=InputEventMouseMotion.new()
	pointer.position=hover_point
	pointer.global_position=hover_point
	view.push_input(pointer,true)
	atlas.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var highlighted:=view.get_texture().get_image().get_pixelv(Vector2i(hover_point))
	check(atlas._cell(atlas.get_local_mouse_position())==clear_cell,"real pointer is over an eligible meadow")
	check(highlighted==unmarked,"idle pointer leaves the selectable meadow unmarked")
	check(view.get_texture().get_image().save_png(out+"shiomi-siting.png")==OK,"branch siting atlas")
	view.queue_free()
	await process_frame
	p.close()
	print("SHIOMI_VISUAL checks=%d success=%s"%[checks,not failed])
	quit(1 if failed else 0)

func walk_bridge(world: TDTravelWorld) -> void:
	world.player.position=TDShiomiLayout.world_point(Vector2(1217,257))
	var route: Array[Vector2]=[Vector2(1217,257),Vector2(1222,246),Vector2(1227,235),Vector2(1236,231),
		Vector2(1254,222),Vector2(1266,218),Vector2(1280,218),Vector2(1295,224),
		Vector2(1313,233),Vector2(1326,235),Vector2(1344,227)]
	for pass_index: int in 2:
		check(await walk_route(world,route),"real movement from stone approach across the bridge "+str(pass_index+1))
		route.reverse()


func walk_route(world: TDTravelWorld, route: Array[Vector2]) -> bool:
	for point: Vector2 in route:
		var goal:=TDShiomiLayout.world_point(point)
		for tick: int in 40:
			var difference:=goal-world.player.position
			if difference.length()<4.0: break
			if absf(difference.x)>2.1:
				Input.action_press("world_right" if difference.x>=0.0 else "world_left")
			if absf(difference.y)>2.1:
				Input.action_press("world_down" if difference.y>=0.0 else "world_up")
			await physics_frame
			for action: String in ["world_right","world_left","world_down","world_up"]:
				Input.action_release(action)
		if world.player.position.distance_to(goal)>=5.0:
			print("Blocked at ",world._island.transform.affine_inverse()*world.player.position," targeting ",point)
			return false
	return true

# A flood from the actual pier over character-sized collision samples. Identify
# the same interaction as pressing E at reachable feet near each entrance.
func check_reachability(world: TDTravelWorld,start: Vector2) -> void:
	var distance:=30.0
	var pending:Array[Vector2i]=[Vector2i.ZERO]
	var tested:Dictionary={Vector2i.ZERO:true}
	var reachable:Dictionary={}
	var index:=0
	while index<pending.size():
		var cell:=pending[index]
		index+=1
		var feet:=start+Vector2(cell)*distance
		world.player.position=feet
		var nearby:=world.nearby()
		if not nearby.is_empty(): reachable[nearby.id]=true
		for step: Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var other:=cell+step
			if tested.has(other): continue
			var delta:=Vector2(step)*distance
			if not world._can_stand(feet+delta):
				tested[other]=false
				continue
			if not world._can_stand(feet+delta*.5): continue
			tested[other]=true
			pending.append(other)
	for id: String in ["harbor","landmark","market-neighborhood","plaza","commercial_street:bank","market-main","hotel","onsen","workshops","watch","office"]:
		check(reachable.has(id),"connected from harbor to "+id)
	world.player.position=start
