extends SceneTree
## Render real scenes and keyboard movement using an isolated profile, never a player slot.
var output := "res://artifacts/protagonist-diagonal-r1-20261116/gpu"
const FACES: Array[Vector2i] = [Vector2i.DOWN,Vector2i.UP,Vector2i.LEFT,Vector2i.RIGHT,Vector2i(1,1),Vector2i(-1,1),Vector2i(-1,-1),Vector2i(1,-1)]
var captures: Array[String] = []
var checks: int = 0
var failures: Array[String] = []
var samples: Array[Dictionary] = []
class AtlasBoard extends Node2D:
	func _draw() -> void:
		draw_rect(Rect2(0,0,1280,800),Color("202e32"))
		var faces: Array[Vector2i] = [Vector2i.DOWN,Vector2i.UP,Vector2i.LEFT,Vector2i.RIGHT,Vector2i(1,1),Vector2i(-1,1),Vector2i(-1,-1),Vector2i(1,-1)]
		var names := ["S","N","W","E","SE","SW","NW","NE"]
		var font := ThemeDB.fallback_font
		draw_string(font,Vector2(30,32),"MAP SPRITES / EIGHT DIRECTIONS",HORIZONTAL_ALIGNMENT_LEFT,-1,24,Color.WHITE)
		for column: int in 8:
			draw_string(font,Vector2(60+column*155,66),names[column],HORIZONTAL_ALIGNMENT_LEFT,-1,20,Color.WHITE)
			for row: int in 5:
				var texture := TDChefArt.texture(faces[column],row-1)
				var size := TDChefArt.render_size(faces[column],row-1,108.0)
				var feet := Vector2(80+column*155,192+row*143)
				draw_line(feet-Vector2(50,0),feet+Vector2(50,0),Color("738c80"))
				draw_texture_rect(texture,TDChefArt.facing_rect(Rect2(feet-Vector2(size.x*.5,size.y),size),faces[column]),false)
				draw_string(font,feet+Vector2(-24,24),["IDLE","CONTACT A","PASS A","CONTACT B","PASS B"][row],HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color.WHITE)
func _initialize() -> void: call_deferred("run")
func verify(value: bool, label: String) -> void:
	checks+=1
	if value: print("PASS ",label)
	else: failures.append(label);printerr("FAIL ",label)
func settle() -> void:
	for tick: int in 3: await process_frame
func capture(label: String) -> void:
	await settle()
	RenderingServer.force_draw(false)
	verify(root.get_texture().get_image().save_png(output.path_join(label+".png"))==OK,"screenshot:"+label)
	captures.append(label)
func check_pose(body: TDKitchenPlayer, label: String) -> void:
	verify(body.facing==Vector2i(1,1),label+": diagonal face")
	var texture := body.animation_texture() as AtlasTexture
	verify(texture.atlas.resource_path==TDCoarseSpriteArt.DIAGONAL_PATH,label+": map atlas")
	var size := body._sprite.scale * texture.get_size()
	verify(size.is_equal_approx(TDChefArt.render_size(Vector2i.DOWN,-1,body.sprite_height)),label+": matches cardinal standing scale")
	verify(absf(body._sprite.position.y+texture.get_height()*body._sprite.scale.y*.5)<.001,label+": grounded feet")
func diagonal_input(body: TDKitchenPlayer, label: String, restaurant: TDRestaurantWorld = null) -> void:
	for direction: Vector2i in FACES.slice(4):
		body.set_controls_enabled(false)
		if restaurant!=null: restaurant.teleport_player(Vector2i(6,8))
		else: body.position=Vector2(640,470)
		for tick: int in 2: await physics_frame
		body.set_controls_enabled(true)
		var start := body.position
		var actions: Array[String] = ["world_right" if direction.x>0 else "world_left","world_down" if direction.y>0 else "world_up"]
		for action: String in actions: Input.action_press(action)
		for tick: int in 12: await physics_frame
		var offset: Vector2
		if restaurant!=null:
			var cell := float(restaurant.layout.cell_px)
			offset=TDRestaurantIsoView.project(body.position.x/cell,body.position.y/cell)-TDRestaurantIsoView.project(start.x/cell,start.y/cell)
		else: offset=body.position-start
		verify(body.facing==direction,label+": actual two-key direction "+str(direction))
		verify(offset.length()>25 and offset.normalized().dot(Vector2(direction).normalized())>.999,label+": actual diagonal movement")
		verify(body.walk_frame>=0,label+": actual walking pose")
		verify(body._sprite.flip_h==(direction in [Vector2i(-1,1),Vector2i(1,-1)]),label+": paired art orientation")
		if restaurant!=null:
			verify(absf(body._walk_phase*224.0-offset.length())<.01,label+": slow restaurant stride unchanged")
			verify(restaurant._iso.player_facing==direction,label+": projected face synchronized")
		samples.append({"room":label,"facing":str(direction),"distance":offset.length(),"phase":body._walk_phase})
		await capture(label+"-walk-"+str(direction.x)+"-"+str(direction.y))
		for action: String in actions: Input.action_release(action)
		for tick: int in 3: await physics_frame
		verify(body.walk_frame==-1 and body.facing==direction,label+": stop keeps facing")
func run() -> void:
	root.size=Vector2i(1280,800)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--probe-output="): output = arg.trim_prefix("--probe-output=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var board:=AtlasBoard.new();board.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;root.add_child(board)
	await capture("01-eight-directions");board.queue_free();await process_frame
	var app: TDApplication=load("res://src/app/main.tscn").instantiate()
	app.settings_path=output.path_join("isolated-%d/settings.json"%Time.get_ticks_usec());root.add_child(app)
	var shell:=app.game_shell;shell.automatic_time=false
	verify(shell.create_game("slot-01").ok,"real main entry / isolated new profile")
	shell.guide.dialogue.finish_now();shell.profile.story.beat="done"
	shell.profile.residence.stage="door";verify(shell.profile.unlock_residence().ok,"fixture residence unlock")
	await settle()
	for location: String in ["town","restaurant","kitchen","cottage"]:
		verify(shell.travel(location).ok,"travel:"+location)
		var body: TDKitchenPlayer
		match location:
			"town": body=shell.town._player
			"restaurant": body=shell.restaurant._player;shell.restaurant.teleport_player(Vector2i(6,8))
			"kitchen": body=shell.kitchen_view.kitchen.world._player;body.position=Vector2(640,470)
			"cottage": body=shell.cottage.player;body.position=Vector2(600,450)
		body.face(Vector2(1,1));check_pose(body,location)
		await capture(location+"-idle")
		if location in ["kitchen","restaurant"]:
			await diagonal_input(body,location,shell.restaurant if location=="restaurant" else null)
	shell.travel("town");shell.town.spawn_at_harbor()
	verify(shell.voyage("tokyo").ok,"real port to foreign town")
	if shell.visiting!=null:
		shell.visiting.player.face(Vector2(1,1));check_pose(shell.visiting.player,"foreign-town");await capture("tokyo-diagonal")
		verify(shell.voyage("chengdu").ok,"return port")
	verify(shell.profile.shop.world_adjustment(300000,"probe-funds","isolated fixture").ok,"branch fixture funds")
	var opened:=shell.profile.branches.open_store("chengdu",[6,48,3,4],"cn","","probe-build")
	verify(opened.ok,"real branch purchase")
	if opened.ok:
		verify(shell.profile.shop.close_for_night().ok,"real close")
		verify(shell.profile.next_day().ok,"complete construction")
		shell.travel("town")
		var id: String=opened.data.store_id
		var found:=false
		for y: int in range(47,53):
			for x: int in range(5,10):
				if not shell.town._walkable(x,y): continue
				shell.town._player.position=shell.town._origin()+(Vector2(x,y)+Vector2.ONE*.5)*TDTownWorld.CELL
				if shell.town.facing_plot().get("branch_id")==id: found=true;break
			if found: break
		verify(found,"reachable branch door")
		verify(shell.enter_branch(id).ok,"real branch entry")
		if shell.branch_visit!=null:
			var visit:=shell.branch_visit
			visit.player.face(Vector2(1,1));check_pose(visit.player,"branch-restaurant");await capture("branch-restaurant")
			visit.player.position=visit.kitchen_point
			var event:=InputEventAction.new();event.action="world_interact";event.pressed=true;root.push_input(event,true)
			event=InputEventAction.new();event.action="world_interact";event.pressed=false;root.push_input(event,true)
			await settle();verify(visit.room=="kitchen","real branch kitchen interaction")
			visit.kitchen._player.face(Vector2(1,1));check_pose(visit.kitchen._player,"branch-kitchen");await capture("branch-kitchen")
	var report:={"success":failures.is_empty(),"checks":checks,"failures":failures,"captures":captures,"motion":samples,"renderer":RenderingServer.get_current_rendering_method(),"human_acceptance":"PENDING"}
	var file:=FileAccess.open(output.path_join("report.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("PROTAGONIST_PROBE ",JSON.stringify(report))
	shell.go_title();shell.music.shutdown();app.queue_free();await settle();quit(0 if failures.is_empty() else 1)
