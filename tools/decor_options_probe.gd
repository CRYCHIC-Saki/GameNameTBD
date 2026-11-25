extends SceneTree
## Real production catalog / room / input; never loads a player profile.
const OUT="res://artifacts/d080-decor/gpu"
var room: TDRestaurantWorld
var checks:=0
var failures:=0
var shots: Array=[]
func _initialize() -> void: call_deferred("run")
func verify(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1;printerr("FAIL ",label)
func frames() -> void:
	for i: int in 4: await process_frame
func capture(id: String) -> void:
	await frames();await RenderingServer.frame_post_draw
	verify(root.get_texture().get_image().save_png(OUT.path_join(id+".png"))==OK,"capture "+id);shots.append(id)
func click(point: Vector2) -> void:
	var motion:=InputEventMouseMotion.new();motion.position=point;motion.global_position=point
	root.push_input(motion,true);await process_frame
	for pressed: bool in [true,false]:
		var event:=InputEventMouseButton.new();event.position=point;event.global_position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed
		root.push_input(event,true);await process_frame
	await frames()
func choose(category: String,id: String) -> void:
	room._decor_panel.select_category(category);await frames()
	var card:=room._decor_panel._cards.get_node("Item_"+id) as Button
	(room._decor_panel._cards.get_parent() as ScrollContainer).ensure_control_visible(card)
	await frames();await click(card.get_global_rect().get_center())
	verify(room._decor_panel.selected==id,"real card "+id)
func run() -> void:
	if DisplayServer.get_name()=="headless": quit(1);return
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i(1280,800)
	DirAccess.make_dir_recursive_absolute(OUT)
	room=TDRestaurantWorld.new();room.player_mode=true;root.add_child(room);await frames();room._toggle_edit();await frames()
	verify(room._decor_panel.visible,"real decor panel")
	await capture("01-catalog-tables")
	room._decor_panel.select_category("陈设");await frames()
	verify(room._decor_panel._cards.get_child_count()==2,"only one shared card for each accent")
	await capture("shared-accent-cards")
	await choose("陈设","screen")
	room._hover_at(Vector2i(8,7));await capture("screen-preview")
	await choose("陈设","kiosk")
	room._hover_at(Vector2i(8,7));await capture("kiosk-preview")
	for theme: String in TDRegionalInterior.DECOR_STYLES:
		await choose("地面","floor_"+theme)
		verify(room.layout.finish_at(8,7)=="floor_"+theme,"whole floor "+theme)
		await capture("floor-"+theme)
		await choose("墙壁","wall_"+theme)
		verify(room._iso._wall_style(Vector2i(0,2))==theme,"render wall "+theme)
		await capture("wall-"+theme)
	for pair: Array in [["wood","paper"],["tile","stripe"],["stone","floral"],["carpet","brick"]]:
		await choose("地面",pair[0]);await choose("墙壁",pair[1]);await capture("legacy-"+pair[0])
	await choose("地面","floor_chinese");await choose("墙壁","wall_chinese")
	await choose("餐桌","dining_table__japanese_low")
	room._hover_at(Vector2i(8,7));await capture("02-japanese-preview")
	verify(str(room._iso.ghost_piece.style_id)=="japanese_low","ghost style")
	await click(room._iso.get_global_transform_with_canvas()*TDRestaurantIsoView.project(8.5,7.5))
	var id:=room._selected
	verify(str(room.layout.piece(id).get("style_id",""))=="japanese_low","placed style")
	var center:=TDFurnitureModel.center(room.layout.piece(id))
	await click(room._iso.get_global_transform_with_canvas()*(center+Vector2(0,-45)))
	verify(room._context_menu.visible,"corner controls")
	await click(room._rotate_button.get_global_rect().get_center())
	verify(int(room.layout.piece(id).rotation)==270,"CCW rotation")
	verify(TDFurnitureModel.center(room.layout.piece(id))==center,"rotation anchor")
	await capture("03-mixed-furniture")
	# Real saved layout, isolated from the game's profile slots.
	var store:=TDRestaurantStore.new(OUT.path_join("layout.json"))
	verify(store.save_layout(room.layout).ok,"isolated save")
	verify(store.load_layout(room.catalog).ok,"isolated load")
	verify(store.loaded_layout.to_dict()==room.layout.to_dict(),"roundtrip")
	verify(room.layout.culture=="chinese","venue cuisine unchanged")
	root.size=Vector2i(1024,720);root.content_scale_size=Vector2i(1024,720);await frames()
	await choose("服务台","cashier__japanese_low")
	verify(room._culture=="japanese","last catalog item reachable")
	await capture("04-small-window")
	room._cancel_decoration();room._toggle_edit()
	await capture("05-play-mode")
	room.queue_free();await frames()
	var file:=FileAccess.open(OUT.path_join("report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"screenshots":shots},"\t"));file.close()
	print("DECOR_OPTIONS checks=",checks," failures=",failures," screenshots=",shots.size());quit(0 if failures==0 else 1)
