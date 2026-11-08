extends SceneTree
const OUT: String="res://artifacts/travel-r1/gpu"
var shell: TDGameShell
var checks: int=0
var failed: bool=false

func _initialize() -> void: call_deferred("run")
func check(value: bool, note: String) -> void:
	checks+=1;print(("PASS " if value else "FAIL ")+note)
	if not value: failed=true
func capture(name: String) -> void:
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OUT.path_join(name+".png"))==OK,name)
func tap(action: String) -> void:
	var event:=InputEventAction.new();event.action=action;event.pressed=true;root.push_input(event)
	event=InputEventAction.new();event.action=action;event.pressed=false;root.push_input(event)
func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT);root.size=Vector2i(1280,800)
	var app: TDApplication=load("res://src/app/main.tscn").instantiate()
	app.settings_path="res://artifacts/travel-r1/probe/%d/settings.json"%Time.get_ticks_usec();root.add_child(app)
	shell=app.game_shell;shell.automatic_time=false;await process_frame
	check(shell.create_game("slot-01","五镇漫游").ok,"isolated new profile")
	shell.guide.dialogue.finish_now();shell.profile.story.beat="done";shell.travel("town");shell.town.spawn_at_harbor()
	var before:=shell.profile.snapshot()
	tap("world_map");check(shell._map_open,"real M opens home map");await capture("01-home-map");tap("world_map")
	for id: String in ["tokyo","paris","bangkok","mexico_city"]:
		check(shell.voyage(id).ok,"travel "+id);await process_frame
		check(shell.visiting.nearby().get("kind")=="harbor","arrival port reachable "+id)
		tap("world_interact");check(shell._modal!=null,"real E at port "+id);shell._close_dialog()
		await capture(id+"-port")
		var start:=shell.visiting.player.position
		Input.action_press("world_left")
		for frame: int in 20: await physics_frame
		Input.action_release("world_left");await physics_frame
		check(shell.visiting.player.position.distance_to(start)>20,"held walking from arrival "+id)
		var plaza: Dictionary=shell.visiting.map._by_id("plaza")
		shell.visiting.player.position=(Vector2(plaza.approach_x,plaza.approach_y)+Vector2.ONE*.5)*48;shell.visiting.camera.zoom=Vector2.ONE*.75
		await capture(id+"-streets")
		tap("world_map");check(shell._map_open and paused,"real M pause "+id)
		var atlas: TDTravelMapView
		for child: Node in shell._modal_box.get_children():
			if child is TDTravelMapView: atlas=child
		check(atlas!=null and atlas.maps.size()==5,"five towns on atlas "+id)
		await capture(id+"-map")
		var wheel:=InputEventMouseButton.new();wheel.button_index=MOUSE_BUTTON_WHEEL_UP;wheel.pressed=true;wheel.position=atlas.global_position+atlas.size*.5
		root.push_input(wheel);check(atlas.zoom>1,"viewport wheel zoom "+id)
		atlas.focus_town(id);await capture(id+"-detail")
		tap("world_map")
		check(not paused and shell.visiting.player.controls_enabled,"M restores controls "+id)
		shell.visiting.player.position=(Vector2(TDTravelCatalog.port(id))+Vector2.ONE*.5)*48
	check(shell.voyage("chengdu").ok,"return home")
	check(shell.profile.snapshot()==before,"no implicit economic or unlock mutations")
	shell._dispose_game();app.queue_free();await process_frame;await process_frame
	var file:=FileAccess.open(OUT.path_join("summary.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"status":"FAIL" if failed else "PASS","checks":checks,"human_playtest":"PENDING","renderer":"Compatibility"}));file.close()
	quit(1 if failed else 0)
