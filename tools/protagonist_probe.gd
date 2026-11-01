extends SceneTree
## Real rendered frames and isolated profiles; never touches player save slots.
var shell: TDGameShell
var captures: Array[String] = []
var failures: Array[String] = []
var display_heights: Dictionary = {}
var restaurant_stride_samples: Array[Dictionary] = []
const OUTPUT := "res://artifacts/protagonist-stride-r2"

class AtlasBoard extends Node2D:
	func _draw() -> void:
		draw_rect(Rect2(0,0,1280,800), Color("202e32"))
		var font := ThemeDB.fallback_font
		var faces: Array[Vector2i] = [Vector2i.DOWN,Vector2i.UP,Vector2i.LEFT,Vector2i.RIGHT]
		var names: Array[String] = ["DOWN", "UP", "LEFT", "RIGHT"]
		draw_string(font, Vector2(32,36), "PROTAGONIST / ORIGINAL IDLE + FOUR-FRAME WALK", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("ffe2ae"))
		for row: int in 4:
			var base_y := 196.0 + row * 180.0
			draw_string(font, Vector2(32,base_y-70), names[row], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
			for column: int in 5:
				var frame := column - 1
				var texture := TDChefArt.texture(faces[row], frame)
				var size := texture.get_size() * 136.0 / texture.get_height()
				var feet := Vector2(210+column*210, base_y)
				draw_line(feet-Vector2(65,0), feet+Vector2(65,0), Color("526860"))
				draw_texture_rect(texture, Rect2(feet-Vector2(size.x*.5,size.y),size), false)
				draw_string(font, feet+Vector2(-27,23), "IDLE" if frame<0 else "WALK %d"%(frame+1), HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("bed0c3"))

func _initialize() -> void: call_deferred("run")

func capture(label: String) -> void:
	print("PROTAGONIST_CAPTURE ", label)
	await process_frame
	await process_frame
	# Render explicitly so a background/minimized probe does not wait indefinitely
	# for an automatic frame. This still uses the real GPU scene and viewport.
	RenderingServer.force_draw(false)
	var path := OUTPUT.path_join(label + ".png")
	if root.get_texture().get_image().save_png(path) != OK: failures.append("capture:"+label)
	captures.append(path)

func run() -> void:
	root.size = Vector2i(1280,800)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var board := AtlasBoard.new()
	board.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	root.add_child(board)
	await capture("atlas-preview")
	board.queue_free()
	await process_frame
	var app: TDApplication = load("res://src/app/main.tscn").instantiate()
	app.settings_path = OUTPUT.path_join("probe-%d/settings.json"%Time.get_ticks_usec())
	print("PROTAGONIST_APP add")
	root.add_child(app)
	shell = app.game_shell
	shell.automatic_time = false
	print("PROTAGONIST_APP create isolated slot")
	if not shell.create_game("slot-01").ok: push_error("Cannot create isolated profile"); quit(1); return
	for location: String in ["town", "restaurant", "kitchen", "cottage"]:
		if not shell.travel(location).ok: failures.append("travel:"+location); continue
		var body: TDKitchenPlayer
		match location:
			"town": body=shell.town._player
			"restaurant":
				body=shell.restaurant._player
				shell.restaurant.teleport_player(Vector2i(6,8))
			"kitchen":
				body=shell.kitchen_view.kitchen.world._player
				body.position=Vector2(640,430)
			"cottage":
				body=shell.cottage.player
				body.position=Vector2(600,450)
		body.face(Vector2.DOWN)
		await capture(location+"-idle")
		if location == "restaurant":
			display_heights[location] = shell.restaurant._iso.chef_rect(body.position).size.y
		else:
			display_heights[location] = body._sprite.get_global_transform_with_canvas().basis_xform(Vector2(0,body._sprite.texture.get_height())).length()
		if location in ["kitchen", "restaurant"]:
			var seen: Dictionary = {}
			Input.action_press("world_right")
			for tick: int in 50:
				await physics_frame
				if body.walk_frame>=0 and not seen.has(body.walk_frame):
					seen[body.walk_frame]=true
					await capture(location+"-walk-%d"%body.walk_frame)
			Input.action_release("world_right")
			if seen.size()<3: failures.append("insufficient-walk-frames:"+location)
			# physics_frame is emitted before bodies process input; allow the released
			# input to reach physics and then the restaurant's separate draw sync.
			await physics_frame
			await physics_frame
			await physics_frame
			await capture(location+"-stopped")
			if body.walk_frame!=-1: failures.append("not-idle:"+location)
		if location == "restaurant":
			for action: String in ["world_right", "world_up", "world_down"]:
				body.set_controls_enabled(false)
				shell.restaurant.teleport_player(Vector2i(6,8))
				await physics_frame
				body.set_controls_enabled(true)
				var before := body.position / float(shell.restaurant.layout.cell_px)
				var screen_before := TDRestaurantIsoView.project(before.x, before.y)
				Input.action_press(action)
				for tick: int in 7: await physics_frame
				# Independent draw projection; do not reuse the production conversion.
				var after := body.position / float(shell.restaurant.layout.cell_px)
				var traveled := TDRestaurantIsoView.project(after.x, after.y).distance_to(screen_before)
				restaurant_stride_samples.append({"action":action,"screen_distance":traveled,"observed_cycle_fraction":body._walk_phase})
				Input.action_release(action)
				for tick: int in 3: await physics_frame
				await capture("restaurant-facing-"+action)
	var result := {"success":failures.is_empty(),"captures":captures,"failures":failures,"display_heights":display_heights,"restaurant_stride_samples":restaurant_stride_samples,"renderer":RenderingServer.get_current_rendering_method(),"human_art_acceptance":"PENDING"}
	var file := FileAccess.open(OUTPUT.path_join("visual-report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"));file.close()
	print("PROTAGONIST_PROBE ",JSON.stringify(result))
	if failures.is_empty():
		shell.go_title()
		shell.request_quit()
	else:
		shell.go_title()
		shell.music.shutdown()
		app.queue_free()
		await create_timer(.15, true).timeout
		quit(1)
