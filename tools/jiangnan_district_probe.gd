extends SceneTree
## Render the real walkable map from a fresh, disposable game slot.

const CELL: float = TDTownWorld.CELL
const DistrictTerrain := preload("res://src/town/jiangnan_district_terrain.gd")
const VIEWS := {
	"00-live-town": Vector3(32,29,.24),
	"01-south-inn": Vector3(14.10,40.75,.83),
	"02-banyan-square": Vector3(28.8,29.6,.92),
	"03-chen-pickle-lane": Vector3(28.7,19.1,.92),
	"04-diner-court": Vector3(36.5,42.4,.75),
	"04-neighborhood-bank": Vector3(39.8,39.5,.88),
	"05-pavilion-river": Vector3(57.35,40.45,.80),
	"06-produce-fish-market": Vector3(9.45,19.0,.88),
	"07-snack-street-day": Vector3(27.65,43.1,.96),
	"07-snack-street-night": Vector3(27.65,43.1,.96),
	"08-optional-workshops": Vector3(39.3,11.85,.88),
}
const ANCHORS := {
	"diner_lot": Rect2i(6,26,12,18),
	"commercial_street": Rect2i(24,37,18,7),
	"plaza": Rect2i(24,26,10,7),
	"market-small": Rect2i(25,18,2,2),
	"market-mid": Rect2i(6,16,5,5),
	"market-large": Rect2i(35,26,6,4),
	"snack_street": Rect2i(24,42,7,2),
	"hotel": Rect2i(12,35,6,9),
	"landmark": Rect2i(57,38,4,4),
}
const FIXTURES := {
	"inn":["entry_gate","stable","inn_crates","garden_rail","farm_chickens"],
	"square":["stone_bench","story_table"],
	"chen":["pickling_crocks","chen_awning"],
	"diner_bank":["peony","bank_carriage"],
	"pavilion":["pavilion_deck","lotus","peach","willow","river_bench"],
	"produce_market":["fish_stall","meat_stall","produce_stall"],
	"night_market":["old_cart","steam_cart","snack_table"],
	"workshops":["forge","dye_house","millstones"],
}

var _app: TDApplication
var _shell: TDGameShell
var _output := "res://artifacts/jiangnan-district-preview"
var _failures: Array[String] = []
var _captures: Array[String] = []
var _layout := {}
var _sites: Array[Dictionary] = []
var _fixtures := {}
var _checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	for option: String in args:
		if option.begins_with("--probe-output="): _output = option.trim_prefix("--probe-output=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output))
	_app = load("res://src/app/main.tscn").instantiate()
	_app.settings_path = _output.path_join("slot-%d/settings.json" % Time.get_ticks_usec())
	root.add_child(_app)
	_shell = _app.game_shell
	_shell.automatic_time = false
	if not _shell.create_game("slot-01","江南街景检视").ok:
		_failures.append("disposable game creation failed")
		await _finish()
		return
	_shell.guide.dialogue.finish_now()
	_shell.profile.story.beat = "done"
	var world: TDPhase3Session = _shell.profile.world
	if not world.home_built and not world.build_home("chinese").ok:
		_failures.append("Chinese diner unavailable in disposable game")
	_expect(_shell.travel("restaurant").ok,"cannot enter player restaurant")
	_shell._object("town")
	_expect(_shell.location=="town" and _shell.town.visible,"exiting restaurant must lead back to the walking map")
	for frame: int in 10: await process_frame
	if not is_instance_valid(_shell.town):
		_failures.append("could not open the walking map")
		await _finish()
		return
	var map: TDTownMap = world.town_map
	_validate_layout(map)
	_validate_sites(_shell.town,map)
	_validate_fixtures(_shell.town)
	var feet := _shell.town._origin() + Vector2(8.52,19.73)*CELL
	_expect(_shell.town._can_stand(feet),"no room in front of the fresh market hall")
	_shell.town._player.position = feet
	_shell.town._interact()
	_expect(world.selected_market=="market-mid" and is_instance_valid(_shell._modal),"wet market failed to open the shop")
	_shell._close_dialog()
	for at: Vector2i in [Vector2i(55,41),Vector2i(56,41),Vector2i(56,42)]:
		_expect(_shell.town._can_stand(_shell.town._origin()+(Vector2(at)+Vector2.ONE*.5)*CELL),"landing or shore blocked at "+str(at))
	if not "--validate-only" in args:
		var town: TDTownWorld = _shell.town
		town.set_process(false)
		town._player.set_physics_process(false)
		town._player.hide()
		if is_instance_valid(town._status_panel): town._status_panel.hide()
		for id: String in VIEWS:
			await _take(town,id,VIEWS[id],1240.0 if id.ends_with("-night") else 620.0)
		town.set_process(true)
		_shell.show_world_map()
		for frame: int in 4: await process_frame
		var views := _shell.find_children("*","TDTravelMapView",true,false)
		if views.is_empty():
			_failures.append("live map did not open")
		else:
			var atlas := views.front() as TDTravelMapView
			atlas.focus_town("chengdu")
			atlas.zoom_at(atlas.size*.5,1.60)
			await process_frame
			await _save_picture("09-live-map")
			_shell._close_dialog()
	await _finish()

func _validate_layout(map: TDTownMap) -> void:
	_expect(map.layout_version==2 and map.extent==73 and map.region_id.is_empty(),"unexpected home layout")
	for key: String in ANCHORS:
		var plot := map._by_id(key)
		_expect(not plot.is_empty() and Rect2i(plot.x,plot.y,plot.w,plot.h)==ANCHORS[key],"anchor moved: " + key)
	for y: int in [20,21]:
		for x: int in range(24,29):
			var at := Vector2i(x,y)
			var terrain := map.terrain_at(at)
			_expect(map.is_road(x,y) and terrain.walkable and not terrain.buildable and terrain.surface_type=="lawn",
				"Chen grass approach changed at %s" % at)
	for y: int in [10,20,39,52,64]:
		_expect(map.terrain_at(Vector2i(54,y)).surface_type=="water"
			and not map.terrain_at(Vector2i(54,y)).walkable,"dry river gap at y=%d" % y)
	for y: int in [6,7,15,16,23,24,45,46]:
		for x: int in range(53,56):
			var at := Vector2i(x,y)
			_expect(map.is_road(x,y) and map.terrain_at(at).walkable,"bridge disconnected at %s" % at)
	var routes := {
		"inn": Vector2i(14,44),
		"square": Vector2i(29,34),
		"chen": Vector2i(26,20),
		"diner": Vector2i(36,44),
		"landmark": Vector2i(60,42),
		"market": Vector2i(8,15),
		"night_market": Vector2i(27,44),
	}
	var connected := map._connected_roads()
	for id: String in routes:
		_expect(connected.has(routes[id]),"main route detached at " + id)
	_expect(map.roads.size()>1800 and connected.size()==map.roads.size(),"original public road network changed")
	_layout = {"extent":map.extent, "road_cells":map.roads.size(), "connected_roads":connected.size(), "anchors":ANCHORS.keys()}

func _validate_sites(town: TDTownWorld, map: TDTownMap) -> void:
	var recorded := {}
	for site: Dictionary in DistrictTerrain.sites(map):
		var id := str(site.id)
		var rect: Rect2i = site.rect
		var edge: Vector2i = site.edge
		var side: Vector2i = site.side
		var depth := int(site.depth)
		var public_entry := edge+side*depth
		var center_feet := town._origin()+Rect2(rect).get_center()*CELL
		_expect(map.is_road(public_entry.x,public_entry.y),"site lacks a public entrance: "+id)
		_expect(town._can_stand(center_feet),"site center obstructed: "+id)
		for distance: int in range(0,depth):
			var at := edge+side*distance
			var feet := town._origin()+(Vector2(at)+Vector2.ONE*.5)*CELL
			_expect(town._can_stand(feet),"site approach obstructed: %s %s %s" % [id,at,_blocking(town,feet)])
		for y: int in range(rect.position.y,rect.end.y):
			for x: int in range(rect.position.x,rect.end.x):
				var at := Vector2i(x,y)
				_expect(not map.is_road(x,y) and map.terrain_at(at).buildable,
					"site covers road or water: %s %s" % [id,at])
		recorded[id] = true
		_sites.append({"id":id,"role":site.role,"rect":[rect.position.x,rect.position.y,rect.size.x,rect.size.y],
			"road_entry":[public_entry.x,public_entry.y]})
	for id: String in ["inn_farm","square_south","chen_backyard","market_perimeter","snack_court","restaurant_yard","riverfront","workshop_yard"]:
		_expect(recorded.has(id),"planned site not visible: "+id)

func _blocking(town: TDTownWorld, feet: Vector2) -> Array[String]:
	var collisions: Array[String] = []
	for facade: Dictionary in town._facades:
		for bounds: Rect2 in facade.bases:
			if not bounds.grow(TDTownWorld.FOOT_RADIUS).has_point(feet): continue
			var art: Texture2D = facade.art
			var path := art.resource_path
			if art is AtlasTexture and art.atlas != null: path = art.atlas.resource_path
			collisions.append("%s %s %s" % [facade.get("district_fixture",facade.get("jiangnan_feature","original")),path,
				(bounds.get_center()-town._origin())/CELL])
	return collisions

func _validate_fixtures(town: TDTownWorld) -> void:
	for facade: Dictionary in town._facades:
		var key := str(facade.get("district_fixture",""))
		if key != "": _fixtures[key] = int(_fixtures.get(key,0))+1
		if key=="entry_gate":
			var rect: Rect2 = facade.rect
			_expect(town._can_stand(rect.position+rect.size*Vector2(.5,.94)),"entrance arch should admit a player")
			for column: Rect2 in facade.bases:
				_expect(not town._can_stand(column.get_center()),"arch stone pier should block the player")
	for group: String in FIXTURES:
		for id: String in FIXTURES[group]:
			_expect(_fixtures.has(id),"district fixture absent: %s / %s" % [group,id])
	_expect(int(_fixtures.get("pickling_crocks",0))>=20,"fewer than 20 pickling crocks visible")

func _expect(condition: bool, failure: String) -> void:
	_checks += 1
	if not condition: _failures.append(failure)

func _take(town: TDTownWorld, title: String, view: Vector3, minute: float) -> void:
	_shell.profile.characters.clock.minute = minute
	town.set_day_minute(minute)
	# Include a familiar actor for scale in the screenshots of the street scenes.
	var stops := {"01-south-inn":Vector2(13.32,42.0),"02-banyan-square":Vector2(28.48,30.96),
			"03-chen-pickle-lane":Vector2(26.5,20.48),"04-diner-court":Vector2(36.5,44.28),
			"05-pavilion-river":Vector2(55.64,41.69),"06-produce-fish-market":Vector2(8.52,19.73),
			"07-snack-street-day":Vector2(27.70,44.80),"07-snack-street-night":Vector2(27.70,44.80)}
	town._player.visible = stops.has(title)
	if town._player.visible:
		town._player.position = town._origin()+Vector2(stops[title])*CELL
	var world := town._origin()+Vector2(view.x,view.y)*CELL
	town._camera.position = world
	town._camera.offset = Vector2.ZERO
	town._camera.zoom = Vector2.ONE*view.z
	town._camera.force_update_scroll()
	for frame: int in 4:
		town._sample_jiangnan_details()
		town.queue_redraw()
		await process_frame
	await _save_picture(title)

func _save_picture(title: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.save_png(_output.path_join(title+".png")) != OK:
		_failures.append("screenshot failed: " + title)
	else:
		_captures.append(title)

func _finish() -> void:
	if is_instance_valid(_shell):
		_shell.go_title()
		_shell.music.shutdown()
	if is_instance_valid(_app): _app.queue_free()
	for frame: int in 3: await process_frame
	var report := {"checks":_checks,"captures":_captures, "failures":_failures, "layout":_layout, "sites":_sites, "fixtures":_fixtures,
		"renderer":RenderingServer.get_current_rendering_method()}
	var out := FileAccess.open(_output.path_join("report.json"), FileAccess.WRITE)
	if out != null:
		out.store_string(JSON.stringify(report,"\t"))
		out.close()
	print("JIANGNAN_DISTRICT_PROBE ",JSON.stringify(report))
	quit(0 if _failures.is_empty() else 1)
