extends SceneTree
## Capture the actual exploration view and live atlas from a disposable slot.
var destination := "res://artifacts/town-art-d080/streets"
var shell: TDGameShell
var failures: Array[String] = []
var captures: Array[String] = []
var crossings: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func capture(title: String) -> void:
	for frame: int in 6:
		await process_frame
		if shell._modal!=null and not shell._map_open: shell._close_dialog()
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	if picture == null or picture.save_png(destination.path_join(title+".png")) != OK:
		failures.append(title)
	else:
		captures.append(title)

## Find a dry-bank → continuous river deck → dry-bank path in the actual town.
## Prefer a broad crossing with open water visible near the camera.
func capture_crossing(id: String, map: TDTownMap, body: TDKitchenPlayer, origin: Vector2) -> void:
	var ground := TDTownScenery.smooth_surfaces(map)
	var best := -1.0
	var focus := Vector2.ZERO
	for dry: Vector2i in map.roads:
		if ground.get(dry)!="stone": continue
		for axis: Vector2i in [Vector2i.RIGHT]:
			var end := dry+axis
			var n := 0
			while ground.get(end)=="bridge":
				n+=1
				end+=axis
			if n==0 or ground.get(end)!="stone": continue
			var mid := (Vector2(dry+end)+Vector2.ONE)*.5
			var normal := Vector2i(axis.y,axis.x)
			var has_water := false
			var widths: Array[int] = []
			for sign_value: int in [-1,1]:
				var width := 0
				for steps: int in range(1,5):
					var near := Vector2i(mid)+normal*sign_value*steps
					if ground.get(near)=="bridge": width+=1
					elif ground.get(near)=="water": has_water=true; break
					else: break
				widths.append(width)
			if not has_water: continue
			var score := mini(n,5)+mini(widths[0],widths[1])*4.0-absi(widths[0]-widths[1])*2.0-mid.distance_to(Vector2.ONE*36)*.005
			for adjacent: int in [-1,1]:
				var landing:=dry+normal*adjacent
				if ground.get(landing)=="stone" and ground.get(end+normal*adjacent)=="stone" and ground.get(landing+axis)=="bridge": score+=3.0
			if score<=best: continue
			body.position=origin+(Vector2(dry)+Vector2.ONE*.5)*TDTownWorld.CELL
			var destination_feet := origin+(Vector2(end)+Vector2.ONE*.5)*TDTownWorld.CELL
			var clear := shell.town._feet_on_road(destination_feet) if id=="chengdu" else shell.visiting._confine(destination_feet)
			if clear:
				best=score
				focus=mid
				crossings[id]={"from":[dry.x,dry.y],"to":[end.x,end.y],"deck_cells":n}
	if best<0:
		failures.append(id+"-river-crossing")
		return
	body.position=origin+focus*TDTownWorld.CELL
	await capture(id+"-river-bridge")

func capture_market_and_bench(map: TDTownMap, body: Node2D, origin: Vector2) -> void:
	var shop := map._by_id("market-small")
	body.position = origin+(Vector2(shop.x+1,shop.y+shop.h)+Vector2(.5,1.25))*TDTownWorld.CELL
	await capture("chengdu-chen-frontage")
	var plaza := TDInteractionRange.plot_bounds(map._by_id("plaza"),TDTownWorld.CELL,origin)
	var bench_art := TDTravelCatalog.street_detail("chengdu",2)
	for piece: Dictionary in shell.town._facades:
		var rect: Rect2 = piece.rect
		if (piece.art==bench_art or piece.get("jiangnan_feature")=="bench") and plaza.encloses(rect):
			body.position = Vector2(rect.end.x+24,rect.end.y)
			await capture("chengdu-plaza-bench")
			return
	failures.append("chengdu-plaza-bench")

func run() -> void:
	var jiangnan := "--jiangnan-life" in OS.get_cmdline_user_args()
	var fixtures_only := "--street-fixtures-only" in OS.get_cmdline_user_args()
	var streets_only := "--landmark-streets" in OS.get_cmdline_user_args()
	var civic_only := "--civic-riverwalk" in OS.get_cmdline_user_args()
	for option: String in OS.get_cmdline_user_args():
		if option.begins_with("--probe-output="): destination = option.trim_prefix("--probe-output=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destination))
	var app: TDApplication = load("res://src/app/main.tscn").instantiate()
	app.settings_path = destination.path_join("slot-%d/settings.json" % Time.get_ticks_usec())
	root.add_child(app)
	shell = app.game_shell
	shell.automatic_time = false
	if not shell.create_game("slot-01","绘景").ok:
		quit(1)
		return
	shell.guide.dialogue.finish_now()
	shell.profile.story.beat = "done"
	shell.travel("town")
	for id: String in TDTravelCatalog.IDS:
		if fixtures_only and id!="chengdu": continue
		if id != "chengdu":
			shell.town.spawn_at_harbor()
			if not shell.voyage(id).ok:
				failures.append(id)
				continue
		var map: TDTownMap = shell.profile.world.town_map if id == "chengdu" else shell.visiting.map
		var origin := shell.town._origin() if id == "chengdu" else Vector2.ZERO
		var body := shell.town._player if id == "chengdu" else shell.visiting.player
		if jiangnan:
			var camera := shell.town._camera
			var square := TDTownScenery.PublicSquare.bounds(map)
			body.position=origin+(Vector2(square.position)+Vector2(4.48,5.0))*TDTownWorld.CELL
			camera.offset=Vector2(38,-102)
			shell.profile.characters.clock.minute=600
			await capture("square-morning")
			shell.profile.characters.clock.minute=600.7
			await capture("square-next-beat")
			shell.profile.characters.clock.minute=1110
			await capture("square-dusk")
			var morning := Image.load_from_file(destination.path_join("square-morning.png"))
			var motion := Image.load_from_file(destination.path_join("square-next-beat.png"))
			var dusk := Image.load_from_file(destination.path_join("square-dusk.png"))
			var steam: Dictionary = shell.town._facades.filter(func(item: Dictionary)->bool: return item.get("jiangnan_feature")=="tea").front()
			var tea_rect: Rect2 = shell.town.get_global_transform_with_canvas()*Rect2(steam.rect)
			var region := Rect2i(tea_rect).intersection(Rect2i(Vector2i.ZERO,morning.get_size()))
			if not region.has_area() or morning.get_region(region).get_data()==motion.get_region(region).get_data():
				failures.append("tea steam does not move within the stall")
			var sample := Vector2i(morning.get_size().x*.52,morning.get_size().y*.81)
			if morning.get_pixelv(sample).get_luminance()-dusk.get_pixelv(sample).get_luminance()<.04:
				failures.append("court lighting does not change by dusk")
			shell.profile.characters.clock.minute=610
			camera.offset=Vector2(0,-58)
			var home := map._by_id("urban_village")
			body.position=origin+Vector2(home.x+home.w*.5,home.y+home.h+.22)*TDTownWorld.CELL
			await capture("whitewall-lane")
			camera.offset=Vector2(135,0)
			body.position=origin+Vector2(52.55,20.5)*TDTownWorld.CELL
			await capture("washer-landing")
			camera.offset=Vector2.ZERO
			await capture_crossing(id,map,body,origin)
			break
		if civic_only:
			var court := TDTownScenery.PublicSquare.bounds(map)
			var center := TDTownScenery.PublicSquare.meeting_point(court)
			body.position = origin+center*TDTownWorld.CELL
			var camera := shell.town._camera if id=="chengdu" else shell.visiting.camera
			camera.offset.y = -64
			await capture(id+"-civic-square")
			camera.offset.y = 0
			await capture_crossing(id,map,body,origin)
			var mouths := {"chengdu":Vector2(65,70),"tokyo":Vector2(42,66),"paris":Vector2(68,68)}
			var mouth: Vector2 = mouths[id]
			var nearest := INF
			for dy: int in range(-6,7):
				for dx: int in range(-6,7):
					var at := origin+(mouth+Vector2(dx+.5,dy+.5))*TDTownWorld.CELL
					var distance := Vector2(dx,dy).length_squared()
					if distance>=nearest: continue
					if not (shell.town._can_stand(at) if id=="chengdu" else shell.visiting._can_stand(at)): continue
					nearest=distance
					body.position=at
			if is_inf(nearest): failures.append(id+"-estuary-bank")
			camera.zoom=Vector2.ONE*.75
			await capture(id+"-estuary")
			camera.zoom=Vector2.ONE
			var plants := TDTownScenery.dressing(map)
			var best := -INF
			for tree: Dictionary in plants:
				if tree.habitat!="avenue": continue
				var cell := Vector2i(Vector2(tree.feet).floor())
				for d: Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
					var spot := cell+d
					if not map.is_road(spot.x,spot.y): continue
					var at := origin+(Vector2(spot)+Vector2.ONE*.5)*TDTownWorld.CELL
					if not (shell.town._can_stand(at) if id=="chengdu" else shell.visiting._can_stand(at)): continue
					var count := 0
					for p: Dictionary in plants:
						if Vector2(p.feet).distance_squared_to(Vector2(spot))<18: count+=1
					var score := count-.008*Vector2(spot).distance_to(Vector2.ONE*36)
					if score>best:
						best=score
						body.position=at
			if is_inf(best): failures.append(id+"-greenway")
			await capture(id+"-greenway")
			if id!="chengdu":
				body.position=(Vector2(TDTravelCatalog.port(id))+Vector2.ONE*.5)*TDTownWorld.CELL
				if not shell.voyage("chengdu").ok: failures.append(id+"-return")
			continue
		if streets_only:
			for parcel: String in TDTownArt.StreetPlaces.VENUES[id]:
				var venue := TDTownArt.StreetPlaces.venue(id,map._by_id(parcel),TDTownWorld.CELL,origin)
				var rect: Rect2 = venue.rect
				body.position = Vector2(rect.get_center().x,rect.end.y+20)
				await capture(id+"-venue-"+parcel)
			var arcade := map._by_id("commercial_street")
			body.position = origin+Vector2(arcade.x+8.5,arcade.y+arcade.h-.15)*TDTownWorld.CELL
			await capture(id+"-arcade")
			if id in TDRegionalLayout.IDS:
				var corner: Vector2i = {"tokyo":Vector2i(44,45),"paris":Vector2i(59,52)}[id]
				body.position = origin+(Vector2(corner)+Vector2.ONE*.5)*TDTownWorld.CELL
				await capture(id+"-bridgehead")
			await capture_crossing(id,map,body,origin)
			if id=="paris":
				shell.show_world_map()
				await process_frame
				await process_frame
				var atlas := shell.find_children("*","TDTravelMapView",true,false).front() as TDTravelMapView
				atlas.focus_town(id)
				var venue := TDTownArt.StreetPlaces.venue(id,map._by_id("hotel"),TDTownWorld.CELL,Vector2.ZERO)
				var bounds: Rect2 = venue.rect
				var feet := Vector2(bounds.get_center().x,bounds.end.y)/TDTownWorld.CELL
				atlas.zoom_at(atlas.cell_to_screen(id,feet),1.5)
				if not Rect2(0,68,atlas.size.x,atlas.size.y-104).has_point(atlas.cell_to_screen(id,feet)):
					failures.append("paris-venue-atlas-out-of-view")
				await capture("paris-venue-atlas")
				shell._close_dialog()
			if id!="chengdu":
				body.position=(Vector2(TDTravelCatalog.port(id))+Vector2.ONE*.5)*TDTownWorld.CELL
				if not shell.voyage("chengdu").ok: failures.append(id+"-return")
			continue
		if id=="chengdu":
			await capture_market_and_bench(map,body,origin)
			if fixtures_only: break
		await capture_crossing(id,map,body,origin)
		var kinds: Array = ["plaza","hotel","landmark","urban_village","rich_district"] if id=="chengdu" else ["plaza","hotel","urban_village","rich_district"]
		for kind: String in kinds:
			var found := false
			for plot: Dictionary in map.plots:
				if plot.kind != kind: continue
				body.position = origin + (Vector2(plot.approach_x,plot.approach_y)+Vector2.ONE*.5)*TDTownWorld.CELL
				if kind in ["rich_district","urban_village"]:
					body.position = origin + Vector2(plot.x+plot.w*.5,plot.y+plot.h+.22)*TDTownWorld.CELL
				found = true
				break
			if found:
				var camera := shell.town._camera if id=="chengdu" else shell.visiting.camera
				if kind in ["rich_district","urban_village"]: camera.offset.y = -90
				await capture(id+"-"+kind)
				camera.offset.y = 0
			else: failures.append(id+"-"+kind)
		if id == "tokyo":
			shell.show_world_map()
			var panel := shell.find_children("*","TDTravelMapView",true,false)
			if not panel.is_empty(): panel.front().focus_town(id)
			await capture("world-map")
			shell._close_dialog()
		if id == "chengdu":
			for home_id: String in ["south-gate-homes","ferry-homes","player_cottage"]:
				var home := map._by_id(home_id)
				if home.is_empty():
					failures.append(home_id)
					continue
				body.position = origin + Vector2(home.x+home.w*.5,home.y+home.h+.3)*TDTownWorld.CELL
				await capture(id+"-"+home_id)
			body.position = origin + Vector2(60.5,30.5)*TDTownWorld.CELL
			await capture("jiangnan-creek")
		if id != "chengdu":
			body.position = (Vector2(TDTravelCatalog.port(id))+Vector2.ONE*.5)*TDTownWorld.CELL
			if not shell.voyage("chengdu").ok: failures.append(id+"-return")
	shell.go_title()
	shell.music.shutdown()
	app.queue_free()
	for frame: int in 3: await process_frame
	var report := {"captures":captures, "failures":failures, "crossings":crossings, "renderer":RenderingServer.get_current_rendering_method()}
	var out := FileAccess.open(destination.path_join("report.json"),FileAccess.WRITE)
	out.store_string(JSON.stringify(report,"\t"))
	out.close()
	print("DISTRICT_PROBE ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
