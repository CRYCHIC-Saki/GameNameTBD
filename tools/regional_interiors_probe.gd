extends SceneTree
## Production renderers only; no profile writes and no replacement demo rendering.
const OUT="res://artifacts/regional-interiors-20261117/gpu"
var checks:=0
var failures:=0
var shots: Array=[]
func _initialize() -> void: call_deferred("run")
func verify(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1;printerr("FAIL ",label)
func capture(id: String) -> void:
	await process_frame;RenderingServer.force_draw()
	verify(root.get_texture().get_image().save_png(OUT.path_join(id+".png"))==OK,"capture "+id);shots.append(id)
func run() -> void:
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i(1280,800)
	DirAccess.make_dir_recursive_absolute(OUT)
	var catalog:=TDRestaurantCatalog.new();verify(catalog.load_file().ok,"catalog")
	for cuisine: String in TDMaterialCatalog.CUISINES:
		var room:=TDRestaurantLayout.make_sized(catalog,16,16,TDPlayerBranches.CULTURES[cuisine])
		verify(room.furnish_player_home().ok,"furnish "+cuisine)
		verify(room.culture==TDRegionalInterior.STYLES[cuisine],"theme "+cuisine)
		var iso:=TDRestaurantIsoView.new();root.add_child(iso);iso.set_room(room)
		iso._camera.zoom=Vector2.ONE*.76
		iso.player_point=Vector2(7,9)*64
		iso.interaction_markers=[{"action":"town","cell":room.entrance(),"name":"出门"}]
		await capture(cuisine+"-dining")
		# Exercise real placement preview and both seating paths in every theme.
		var seat:=room.piece_by_kind("dining_table")
		var foot:=TDFurnitureModel.dining_feet(seat)
		var grid:=Vector2((foot.x-TDRestaurantIsoView.ORIGIN.x)/96+(foot.y-TDRestaurantIsoView.ORIGIN.y)/48,(foot.y-TDRestaurantIsoView.ORIGIN.y)/48-(foot.x-TDRestaurantIsoView.ORIGIN.x)/96)
		iso.actors=[{"id":"probe-diner","gone":false,"seated":true,"position":grid*64,"label":"","seat_id":seat.id,"character_id":"aling","appearance_id":0,"frame":-1,"facing":Vector2i.RIGHT}]
		iso._camera.zoom=Vector2.ONE*1.1;iso._camera.position=foot+Vector2(0,-45);iso.queue_redraw()
		await capture(cuisine+"-seated")
		iso.shutdown();iso.queue_free();await process_frame;await process_frame
		var world: TDKitchenWorld=load("res://src/world/kitchen_world.tscn").instantiate()
		world.single_fridge=true;world.service_door=true;world.cuisine_id=cuisine;world.station_names=TDCuisineKitchen.names(cuisine)
		root.add_child(world);world._player.position=Vector2(640,505)
		var camera:=Camera2D.new();camera.position=Vector2(640,400);world.add_child(camera);camera.make_current()
		await capture(cuisine+"-kitchen")
		verify(world.stations().size()==7,"real stations "+cuisine)
		verify(world.staff_walkable(Vector2(640,440)),"aisle "+cuisine)
		world._player.position=Vector2(640,694);world.set_controls_enabled(true)
		var event:=InputEventAction.new();event.action="world_interact";event.pressed=true
		var exits: Array=[];world.dining_requested.connect(func()->void:exits.append(true))
		root.push_input(event,true);await process_frame;verify(exits.size()==1,"real door input "+cuisine)
		world.queue_free();await process_frame;await process_frame
	var file:=FileAccess.open(OUT.path_join("report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"screenshots":shots},"\t"));file.close()
	print("REGIONAL_INTERIORS checks=",checks," failures=",failures," screenshots=",shots.size());quit(0 if failures==0 else 1)
