extends SceneTree

var _shell: TDGameShell
var _town: TDTownWorld
var _output: String
var _failures: Array[String] = []
var _checks: int = 0
var _bridge_footprints := {}

const FRAMES := {
	"01-全镇":Vector3(36.5,20.3,.189),
	"02-榕树广场与主店":Vector3(24.1,20.0,.66),
	"03-老陈与菜市":Vector3(13.7,12.2,.70),
	"04-河口港与下桥":Vector3(53.4,27.15,.45),
	"05-滨水集市":Vector3(20.6,29.2,.57),
	"06-北桥与居民区":Vector3(51.5,10.6,.53),
	"08-西南河岸花草":Vector3(12.0,33.0,.67),
	"09-石板与广场桌凳":Vector3(17.8,21.0,.95),
	"10-望江亭栈桥":Vector3(36.4,31.7,.89),
	"11-港口外伸平台":Vector3(61.5,27.6,.65),
	"12-桥面与栏杆":Vector3(41.7,11.2,.84),
	"13-南桥拱洞":Vector3(39.5,25.6,.93),
	"14-工坊与青石街":Vector3(25.0,7.0,.75),
	"15-东岸住宅与汀步":Vector3(55.0,10.5,.75),
	"16-北桥接岸":Vector3(42.2,11.1,.79),
	"17-南桥接岸":Vector3(39.5,25.3,.82),
	"18-西北村落":Vector3(8.3,9.4,.89),
	"19-南桥东接缝":Vector3(43.6,25.65,1.18),
	"20-晨间广场":Vector3(21.8,20.5,.54),
	"21-正午广场":Vector3(21.8,20.5,.54),
	"22-傍晚广场":Vector3(21.8,20.5,.54),
	"23-南食街与木凳":Vector3(26.6,26.5,.92),
	"24-客港石壁与晒网":Vector3(58.0,28.7,.71),
}

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	_checks+=1
	if not ok: _failures.append(message)

func _feet(x: float, y: float) -> Vector2:
	return _town._origin()+Vector2(x,y)*_town.cell_size()

func _pixel_feet(point: Vector2) -> Vector2:
	return _town._origin()+point*_town.cell_size()/TDPlannedTown.REFERENCE_PIXELS_PER_CELL

func _walk(points: Array[Vector2], frame := "") -> bool:
	var player := _town._player
	player.position = _pixel_feet(points[0])
	player.set_controls_enabled(true)
	var axes := {"world_left":Vector2.LEFT, "world_right":Vector2.RIGHT,
		"world_up":Vector2.UP, "world_down":Vector2.DOWN}
	for i: int in range(1,points.size()):
		var goal := _pixel_feet(points[i])
		var reached := false
		for tick: int in 200:
			# An externally launched Windows window may lose focus at start.
			# Resume through the game's own pause dialog before sending input.
			if root.get_tree().paused and is_instance_valid(_shell._modal) and _shell._modal.get_meta("pauses_music",false):
				_shell._close_dialog()
			var delta := goal-player.position
			if delta.length() < 7:
				reached = true
				break
			for action: String in axes:
				if delta.dot(axes[action]) > 3.8: Input.action_press(action)
				else: Input.action_release(action)
			await root.get_tree().physics_frame
		if not reached:
			for action: String in axes: Input.action_release(action)
			print("WALK blocked at ",player.position,", target ",goal,", paused ",root.get_tree().paused,
				", enabled ",player.controls_enabled,", physics ",player.is_physics_processing(),", can process ",player.can_process())
			return false
		if i == 2 and not frame.is_empty(): _bridge_footprints[frame] = player.position
	for action: String in axes: Input.action_release(action)
	return true

func _wharf_material(point: Vector2) -> int:
	var layer := _town._reference_map.get_node("Wharf") as TileMapLayer
	var local := point * TDJiangnanReferenceArt.WORLD_SIZE.x / TDJiangnanReferenceArt.SIZE.x
	var cell := layer.local_to_map(layer.transform.affine_inverse() * local)
	if layer.get_cell_source_id(cell) == 1: return 1
	var tile := layer.get_cell_atlas_coords(cell)
	return floori(tile.y / 6.0)

func _run() -> void:
	_output="res://artifacts/approved-jiangnan/screens"
	for option: String in OS.get_cmdline_user_args():
		if option.begins_with("--probe-output="): _output=option.trim_prefix("--probe-output=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output))
	var app: TDApplication=load("res://src/app/main.tscn").instantiate()
	app.settings_path=_output.path_join("slot-%s/settings.json"%Time.get_ticks_usec())
	root.add_child(app)
	_shell=app.game_shell
	_shell.automatic_time=false
	_check(_shell.create_game("slot-01","江南地图检视").ok,"create")
	if not is_instance_valid(_shell.town):
		quit(1)
		return
	_shell.guide.dialogue.finish_now()
	_shell.profile.story.beat="done"
	_town=_shell.town
	_town.spawn_at_harbor()
	var map := _shell.profile.world.town_map
	var connected := map._connected_roads()
	_check(TDPlannedTown.approved(map),"approved layout active")
	_check(_town._reference_map != null and _town._reference_map.scene_file_path == TDJiangnanReferenceArt.MAP_PATH,"actual Godot map scene mounted")
	for name: String in ["Water","Land","Woodlands","Shore","GroundDetails","ContactShadows","Streets","Squares","Wharf","BridgeDeck","SurfaceDetails"]:
		_check(_town._reference_map.get_node(name) is TileMapLayer,"native layer "+name)
	_check(not _town._reference_map.has_node("StreetVerge"),"stone meets grass directly")
	_check(not _town._reference_map.has_node("Foundations"),"no gravel under buildings")
	_check(not _town._reference_map.has_node("MarketClay"),"markets have no large clay overlays")
	var garden_count := 0
	var house_count := 0
	var wall_growth_count := 0
	var lived_in_detail := 0
	var common_home_art: Rect2
	for sprite: Node in _town._reference_map.get_node("Props").get_children():
		var id := String(sprite.get_meta("scenic_id",""))
		if id.begins_with("lawn-plant-"): garden_count += 1
		if id.begins_with("wall-growth-"): wall_growth_count += 1
		if id.begins_with("door-prop-") or id.begins_with("garden-group-") or id.begins_with("street-life-"):
			lived_in_detail += 1
		if not sprite.get_meta("grass_house",false): continue
		house_count += 1
		if not id.begins_with("east-") and id != "west-lower-upper-house": continue
		var art := (sprite as Sprite2D).texture as AtlasTexture
		if not common_home_art.has_area(): common_home_art = art.region
		_check(art.region == common_home_art,"consistent residence art "+id)
	_check(house_count == 23,"all fixed houses have a grass frontage")
	_check(garden_count >= 90,"trees and flowers on open lawns")
	_check(lived_in_detail >= 30,"household and garden details are visible")
	_check(wall_growth_count >= 16,"wall-root vegetation between doorways")
	var street := _town._reference_map.get_node("Streets") as TileMapLayer
	var plaza := _town._reference_map.get_node("Squares") as TileMapLayer
	var shared_cells := 0
	for coord: Vector2i in plaza.get_used_cells():
		if street.get_cell_source_id(coord) >= 0: shared_cells += 1
	_check(shared_cells == 0, "each street and market paving cell has one owner")
	var solar := _town._reference_map.get_node("SunShadows")
	_town.set_day_minute(480)
	var morning: Vector2 = solar.direction
	_town.set_day_minute(720)
	var noon: Vector2 = solar.direction
	_town.set_day_minute(1095)
	var dusk: Vector2 = solar.direction
	_check(morning.x < 0 and dusk.x > 0 and noon.length() < minf(morning.length(),dusk.length())*0.4,
		"the real town clock reverses the sun and shortens the noon shadow")
	_check(solar._casters.size() > 60, "visible buildings, trees and stalls cast shadows")
	_town.set_day_minute(1320)
	_check(is_zero_approx(solar.strength), "sun shadows disappear after sunset")
	_town.set_day_minute(610)
	_check(is_equal_approx(_town._player.sprite_height,108.0), "town player drawn at the requested scale")
	var paving := street.tile_set.get_source(1) as TileSetAtlasSource
	_check(paving != null and paving.texture.resource_path.ends_with("jiangnan-map-paving-v1.png"),"reference paving atlas")
	for sample: Array in [[street,Vector2(1221,296),1],[plaza,Vector2(412,520),1]]:
		var layer: TileMapLayer = sample[0]
		var local: Vector2 = _pixel_feet(sample[1])-_town._origin()
		var cell := layer.local_to_map(layer.transform.affine_inverse()*local)
		_check(layer.get_cell_source_id(cell) == sample[2],"expected stone paving at "+str(sample[1]))
	for point: Vector2 in [Vector2(365,233),Vector2(258,704),Vector2(410,293)]:
		_check(TDJiangnanReferenceArt._contains_tile(plaza,_pixel_feet(point)-_town._origin()),
			"stone under the market stalls "+str(point))
	var shadows := _town._reference_map.get_node("ContactShadows") as TileMapLayer
	_check(shadows.get_used_cells().size() > 175,"contact shadows use independent transparent tiles")
	var deck := _town._reference_map.get_node("BridgeDeck") as TileMapLayer
	var wharf := _town._reference_map.get_node("Wharf") as TileMapLayer
	for x: float in [994.0,1000.0,1004.0]:
		for y: float in [581.0,589.0,597.0]:
			_check(TDJiangnanReferenceArt._contains_tile(wharf,_pixel_feet(Vector2(x,y))-_town._origin()) and
				_town._can_stand(_pixel_feet(Vector2(x,y))), "connected quay throat %s"%Vector2(x,y))
		for y: float in [570.0,608.0]:
			_check(not _town._can_stand(_pixel_feet(Vector2(x,y))), "water beside quay throat %s"%Vector2(x,y))
	for head: Array in [[Vector2(870,262),Vector2(841,252)],[Vector2(1060,270),Vector2(1089,268)],
			[Vector2(814,590),Vector2(786,602)],[Vector2(992,589),Vector2(1023,585)]]:
		var edge: Vector2 = head[0]
		var shore: Vector2 = head[1]
		for i: int in range(1,7):
			var middle := edge.lerp(shore,i/6.0)
			for offset: float in [-4.0,0.0,4.0]:
				var feet := _pixel_feet(middle+Vector2(0,offset))
				var local := feet-_town._origin()
				var stone_path := (
					TDJiangnanReferenceArt._contains_tile(street,local)
					or TDJiangnanReferenceArt._contains_tile(wharf,local)
					or TDJiangnanReferenceArt._contains_tile(deck,local)
				)
				_check(stone_path and _town._can_stand(feet),"continuous bridgehead "+str(middle)+"/"+str(offset))
	var wear := _town._reference_map.get_node("SurfaceDetails") as TileMapLayer
	_check(wear.get_used_cells().size() >= 90,"wear, tide foam and bridge shadow mounted")
	_check(connected.size()==map.roads.size(),"connected street graph %d/%d"%[connected.size(),map.roads.size()])
	_check(_town._can_stand(_feet(58.5,27.5)),"port arrival stand")
	var north: Array[Vector2] = [Vector2(879,262),Vector2(921,250),Vector2(953,242),Vector2(990,247),Vector2(1048,269)]
	var south: Array[Vector2] = [Vector2(827,589),Vector2(857,579),Vector2(895,568),Vector2(930,572),Vector2(981,588)]
	for bridge: Array[Vector2] in [north,south]:
		for segment: int in range(1, bridge.size()):
			for index: int in 5:
				var pixel := bridge[segment-1].lerp(bridge[segment], index/4.0)
				var cell := pixel / TDPlannedTown.REFERENCE_PIXELS_PER_CELL
				_check(_town._can_stand(_feet(cell.x,cell.y)),"bridge blocked at %s"%pixel)
	for point: Vector2 in [Vector2(46.5,2.5),Vector2(41.5,13.6),Vector2(71.4,36.0),Vector2(47.1,28.5)]:
		_check(not _town._can_stand(_feet(point.x,point.y)),"water collision "+str(point))
	for id: String in ["market-small","market-mid","player_diner","commercial_street:bank"]:
		var plot := map._by_id(id)
		var at := Vector2(float(plot.get("approach_x",0))+.5,float(plot.get("approach_y",0))+.5)
		_town._player.position=_feet(at.x,at.y)
		_check(_town._can_stand(_town._player.position),"door blocked "+id+str(at))
		var facing := _town.facing_plot()
		_check(facing.get("id")==id,"interaction mismatch "+id+" -> "+str(facing.get("id")))
	_check(not map.terrain_at(Vector2i(65,12)).buildable,"existing willow footprint protects east lawn")
	for region: Vector2i in [Vector2i(24,12),Vector2i(67,12)]:
		var grass := map.terrain_at(region)
		_check(grass.buildable and grass.surface_type=="lawn","ordinary lawn "+str(region))
	var found := {}
	var scenic := {}
	for item: Dictionary in _town._facades:
		var key: String = item.get("reference_id", "")
		scenic[key] = item
		if key.begins_with("detail-") or key.begins_with("grove-") or key.begins_with("bank-detail-"): continue
		found[key]=int(found.get(key,0))+1
	for id: String in ["plaza_banyan","square-stage","south-entrance-gate","inn-stable","market-blue-fish-stall",
			"market-cream-produce-stall","dyers-and-tofu-makers","waterfront-blue-stall","waterfront-show-stage",
			"river-pier-stall","east-tea-dock","diner","bank","chen-food-shop","harbor-terminal"]:
		_check(found.has(id),"missing "+id)
	var unit := TDJiangnanReferenceArt.world_scale(map, _town.cell_size())
	for id: String in ["diner","bank","chen-food-shop","inn","harbor-terminal"]:
		var part: Dictionary = scenic[id]
		var bounds: Rect2 = part.rect
		_town._player.position = Vector2(bounds.get_center().x,bounds.end.y+16)
		_check(_town._can_stand(_town._player.position),"dry frontage "+id)
		_check(_town.facing_plot().get("id","") == part.plot.id,"service at visible entrance "+id)
	if scenic.has("plaza_banyan") and scenic.has("square-stage"):
		var canopy: Rect2 = scenic.plaza_banyan.rect
		var stage: Rect2 = scenic["square-stage"].rect
		_check(stage.position.x - canopy.end.x >= 10.0 * unit,"stage leaves air beside the banyan")
	for id: String in ["north_arch","south_arch"]:
		var bridge := _town._reference_map.get_node("Waterfront/"+id)
		_check(bridge.get_node("BackRail").z_index < 0 and bridge.get_node("FrontRail").z_index > 0,
			"bridge occlusion "+id)
		_check(bridge.get_node("ArchStonework") is Sprite2D,"textured arch and deck "+id)
	for point: Vector2 in [Vector2(956,272),Vector2(903,603)]:
		_check(not _town._can_stand(_pixel_feet(point)),"arch opening remains water "+str(point))
	for y: int in range(801,827,5):
		_check(not _town._can_stand(_pixel_feet(Vector2(844,y))),"open channel below pavilion at "+str(y))
	for id: String in ["waterfront-blue-stall","waterfront-cream-stall","waterfront-orange-stall","waterfront-red-stall","waterfront-blue-kiosk","waterfront-gold-stall"]:
		_check(scenic.has(id) and scenic[id].rect.size.x >= 56.0 * unit * (80.0 / 90.0),"human scale waterfront stall "+id)
	for x: int in range(225,755,18):
		_check(_town._can_stand(_town._origin()+Vector2(x,746)*unit),"clear waterfront promenade at %d"%x)
	for point: Vector2 in [Vector2(1171,625),Vector2(1274,631),Vector2(1328,635),Vector2(1426,619),Vector2(1513,598)]:
		_check(_wharf_material(point) == 1,"uniform stone apron at %s"%point)
	for point: Vector2 in [Vector2(1035,577), Vector2(1144,503), Vector2(802,722)]:
		_check(_wharf_material(point) == 1, "stone landing "+str(point))
	for point: Vector2 in [Vector2(1360,673), Vector2(809,769)]:
		_check(_wharf_material(point) == 7, "timber extension "+str(point))
		_check(_town._can_stand(_town._origin()+point*unit), "walkable extension "+str(point))
	var bank_bounds: Rect2 = scenic.bank.rect
	for x: float in [bank_bounds.position.x+2.0,bank_bounds.end.x-2.0]:
		_check(_town._walkable_point(Vector2(x,bank_bounds.end.y-2.0)),"bank corners stand on dry ground")
	if not "--validate-only" in OS.get_cmdline_user_args():
		_shell.set_process(false)
		_shell._hud_layer.hide()
		_town.set_process(false)
		_check(await _walk(north,"12-桥面与栏杆"),"walk across north bridge with movement input")
		_check(await _walk(south,"13-南桥拱洞"),"walk across south bridge with movement input")
		north.push_front(Vector2(841,252))
		north.push_back(Vector2(1089,268))
		south.push_front(Vector2(786,602))
		south.push_back(Vector2(1023,585))
		north.reverse()
		south.reverse()
		_check(await _walk(north),"return across north bridge with movement input")
		_check(await _walk(south),"return across south bridge with movement input")
		_check(await _walk([Vector2(757,743),Vector2(783,749),Vector2(802,759),Vector2(828,778)]),"walk from promenade onto pavilion jetty")
		_check(await _walk([Vector2(1360,626),Vector2(1360,650),Vector2(1360,681)]),"walk from quay onto harbor pier")
		_town._player.set_physics_process(false)
		_town._player.hide()
		_town.set_day_minute(610.0)
		for id: String in FRAMES:
			var view: Vector3 = FRAMES[id]
			if id.begins_with("19-"):
				_bridge_footprints[id] = _pixel_feet(Vector2(997,589))
			if id.begins_with("20-") or id.begins_with("21-") or id.begins_with("22-"):
				_town.set_day_minute(480.0 if id.begins_with("20-") else (720.0 if id.begins_with("21-") else 1095.0))
				_bridge_footprints[id] = _pixel_feet(Vector2(464,537))
			if id.begins_with("23-") or id.begins_with("24-"):
				_town.set_day_minute(660.0)
				_bridge_footprints[id] = _pixel_feet(Vector2(603,634) if id.begins_with("23-") else Vector2(1330,638))
			if _bridge_footprints.has(id):
				_town._player.position = _bridge_footprints[id]
				_town._player.face(Vector2.RIGHT)
				_town._player.show()
			else: _town._player.hide()
			_town._camera.position=_feet(view.x,view.y)
			_town._camera.zoom=Vector2.ONE*view.z
			_town._camera.offset=Vector2.ZERO
			_town._camera.force_update_scroll()
			_town.queue_redraw()
			await process_frame
			await process_frame
			await _capture(id)
		_shell.show_world_map()
		await process_frame
		var maps := _shell.find_children("*","TDTravelMapView",true,false)
		_check(not maps.is_empty(),"M map created")
		if not maps.is_empty():
			var view := maps[0] as TDTravelMapView
			view.focus_town("chengdu")
			view.zoom_at(view.size*.5,1.6)
			await process_frame
			await _capture("07-世界地图")
	_shell.go_title()
	_shell.music.shutdown()
	app.queue_free()
	await process_frame
	await process_frame
	print("JIANGNAN_APPROVED ",JSON.stringify({"checks":_checks,"failures":_failures,"fixtures":found,"roads":map.roads.size()}))
	quit(0 if _failures.is_empty() else 1)

func _capture(id: String) -> void:
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	_check(picture!=null and picture.save_png(_output.path_join(id+".png"))==OK,"capture "+id)
