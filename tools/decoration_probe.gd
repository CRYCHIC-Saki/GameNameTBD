extends SceneTree
## Actual renderer and input probe; never opens a player save.
var OUT: String="res://artifacts/decoration-r2/gpu"
var room: TDRestaurantWorld
var checks: int=0
var failed: bool=false
var captures: int=0

class ModelSample extends Node2D:
	var piece: Dictionary
	func _draw() -> void:
		TDFurnitureModel.draw_model(self,piece)

func check_rotation_pixels() -> void:
	var viewport:=SubViewport.new();viewport.size=Vector2i(768,320)
	viewport.transparent_bg=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var model:=ModelSample.new();model.position=Vector2(384,240);viewport.add_child(model)
	var catalog:=TDRestaurantCatalog.new()
	check(catalog.load_file().ok,"pixel probe catalog loads")
	for kind: String in ["dining_table","hotpot_table","welcome_desk","cashier","order_counter"]:
		var definition:=catalog.furniture(kind)
		var original:=Rect2i()
		for rotation: int in [0,270,180,90]:
			model.piece={"kind":kind,"w":definition.width,"h":definition.height,"rotation":rotation,"style_id":"chinese_low"}
			model.queue_redraw();await frames();await RenderingServer.frame_post_draw
			var rendered:=viewport.get_texture().get_image()
			var pixels:=rendered.get_used_rect()
			if rotation==0: original=pixels
			print("MODEL_PIXELS ",kind," rotation=",rotation," bounds=",pixels)
			check(pixels.size.x>30 and absi(pixels.position.x-original.position.x)<=2 and absi(pixels.size.x-original.size.x)<=2,"rendered pivot stays fixed: "+kind+" "+str(rotation))
			check(rendered.save_png(OUT.path_join("model-"+kind+"-"+str(rotation)+".png"))==OK,"save rendered rotation evidence")
			captures+=1
	viewport.queue_free();await frames()

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks+=1
	print("DECOR_CHECK ",checks," ","PASS " if value else "FAIL ",message)
	if not value: failed=true

func frames() -> void:
	for index: int in 5: await process_frame

func capture(id: String) -> void:
	await frames();await RenderingServer.frame_post_draw
	var error:=root.get_texture().get_image().save_png(OUT.path_join(id+".png"))
	if error!=OK: failed=true
	captures+=1

func click(point: Vector2, button: MouseButton=MOUSE_BUTTON_LEFT) -> void:
	var motion:=InputEventMouseMotion.new();motion.position=point;motion.global_position=point
	root.push_input(motion,true);await process_frame
	for pressed: bool in [true,false]:
		var event:=InputEventMouseButton.new()
		event.position=point;event.global_position=point;event.button_index=button;event.pressed=pressed
		root.push_input(event,true);await process_frame
	await frames()

func find_button(title: String, parent: Node) -> Button:
	for node: Button in parent.find_children("*","Button",true,false):
		if node.text==title: return node
	return null

func run() -> void:
	if DisplayServer.get_name()=="headless":
		print("DECOR_GPU requires a real renderer");quit(1);return
	root.size=Vector2i(1280,800)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--probe-output="): OUT=arg.trim_prefix("--probe-output=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	await check_rotation_pixels()
	if OS.get_cmdline_user_args().has("--rotation-only"):
		print("DECOR_ROTATION success=",not failed," checks=",checks," captures=",captures)
		quit(1 if failed else 0);return
	room=TDRestaurantWorld.new();room.player_mode=true;root.add_child(room)
	await frames();room._toggle_edit();await frames()
	var before:=room.layout.to_dict()
	for category: String in TDDecorationPanel.CATEGORIES:
		await click(find_button(category,room._decor_panel).get_global_rect().get_center())
		check(room._decor_panel.category==category and room._decor_panel._cards.get_child_count()>0,"category "+category)
		await capture("category-"+str(TDDecorationPanel.CATEGORIES.find(category)))
	check(room.layout.to_dict()==before,"browsing does not modify furniture")
	check(room._decor_panel.find_children("*","OptionButton",true,false).is_empty(),"no culture or tier dropdown")
	await click(find_button("陈设",room._decor_panel).get_global_rect().get_center())
	var card:=room._decor_panel._cards.get_node("Item_kiosk") as Button
	await click(card.get_global_rect().get_center())
	check(room._tool=="place" and room._armed_kind=="kiosk","real card click arms furniture")
	room._hover_at(Vector2i(8,8));await capture("ghost")
	check(room._iso.ghost_ok and not room._iso.ghost_piece.is_empty(),"raised valid ghost")
	room._spin(1);await capture("rotated")
	check(int(room._iso.ghost_piece.get("rotation",-1))==90,"ghost rotates")
	room._hover_at(Vector2i(0,0));await capture("invalid")
	check(not room._iso.ghost_ok and not room._iso.ghost_piece.is_empty(),"invalid ghost remains visible")
	var point:=room._iso.get_global_transform_with_canvas()*TDRestaurantIsoView.project(8.5,8.5)
	await click(point,MOUSE_BUTTON_RIGHT)
	check(room._iso.ghost_piece.is_empty() and room.layout.to_dict()==before,"right click cancels without mutation")
	await click(card.get_global_rect().get_center());await click(point)
	var id:=room._selected
	check(room.layout.pieces().size()==before.pieces.size()+1 and room._tool=="select","real placement commits once and returns to selection")
	if not room.layout.piece(id).is_empty():
		var model:=room.layout.piece(id)
		await click(room._iso.get_global_transform_with_canvas()*(TDFurnitureModel.center(model)+Vector2(0,-65)))
		check(room._selected==id and room._context_menu.visible,"click raised model selects correct furniture")
		await capture("context")
		check(room._context_menu.find_children("*","Button",true,false).size()==2,"only two corner icons")
		await click(room._rotate_button.get_global_rect().get_center())
		check(int(room.layout.piece(id).get("rotation",-1))==270,"corner rotates counterclockwise once")
		await capture("context-rotated")
		var start:=room._iso.get_global_transform_with_canvas()*(TDFurnitureModel.center(room.layout.piece(id))+Vector2(0,-45))
		var end:=start+room._iso.get_global_transform_with_canvas().basis_xform(Vector2(96,48))
		var press:=InputEventMouseButton.new();press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true;press.position=start;press.global_position=start;root.push_input(press,true);await frames()
		var motion:=InputEventMouseMotion.new();motion.position=end;motion.global_position=end;root.push_input(motion,true);await frames()
		check(room._dragging and int(room.layout.piece(id).x)==8,"drag preview leaves original state unchanged")
		await capture("drag-preview")
		var release:=InputEventMouseButton.new();release.button_index=MOUSE_BUTTON_LEFT;release.pressed=false;release.position=end;release.global_position=end;root.push_input(release,true);await frames()
		check(not room._dragging and int(room.layout.piece(id).x)==10 and int(room.layout.piece(id).y)==8,"release moves same furniture")
		await capture("drag-committed")
		await click(room._delete_button.get_global_rect().get_center())
		check(room.layout.piece(id).is_empty() and not room._context_menu.visible,"popup deletes and closes")
	await click(find_button("餐桌",room._decor_panel).get_global_rect().get_center())
	await click((room._decor_panel._cards.get_node("Item_dining_table") as Button).get_global_rect().get_center())
	room._hover_at(Vector2i(8,7));await capture("table-ghost-0")
	room._spin(-1);await capture("table-ghost-270")
	await click(room._iso.get_global_transform_with_canvas()*TDRestaurantIsoView.project(8.5,7.5))
	var table_id:=room._selected
	check(not room.layout.piece(table_id).is_empty(),"table placed through actual input")
	if not room.layout.piece(table_id).is_empty():
		var anchor:=TDFurnitureModel.center(room.layout.piece(table_id))
		await click(room._iso.get_global_transform_with_canvas()*(anchor+Vector2(0,-80)))
		check(room._selected==table_id and room._context_menu.visible,"placed table selected through actual input")
		for angle: int in [180,90,0,270]:
			await click(room._rotate_button.get_global_rect().get_center())
			check(int(room.layout.piece(table_id).rotation)==angle and TDFurnitureModel.center(room.layout.piece(table_id))==anchor,"table corner rotation preserves anchor "+str(angle))
			await capture("table-room-"+str(angle))
	for category: String in ["地面","墙壁"]:
		await click(find_button(category,room._decor_panel).get_global_rect().get_center())
		await click((room._decor_panel._cards.get_node("Item_"+("tile" if category=="地面" else "brick")) as Button).get_global_rect().get_center())
		var complete: bool=true
		for y: int in room.layout.rows:
			for x: int in room.layout.columns:
				if (room.layout.cell_zone(x,y)=="facade")== (category=="墙壁"):
					complete=complete and room.layout.finish_at(x,y)==("brick" if category=="墙壁" else "tile")
		check(complete and room._tool=="select","whole surface on card click "+category)
		await capture("whole-"+("floor" if category=="地面" else "wall"))
	for dimensions: Vector2i in [Vector2i(1024,720),Vector2i(1600,1000)]:
		root.size=dimensions;await frames()
		var rect:=room._decor_panel.get_global_rect()
		check(rect.end.x<=root.get_visible_rect().size.x and rect.end.y<=root.get_visible_rect().size.y,"catalog inside window "+str(dimensions))
		await capture("resize-"+str(dimensions.x))
	room._toggle_edit();await capture("normal")
	var report:={"status":"FAIL" if failed else "PASS","checks":checks,"captures":captures,"renderer":RenderingServer.get_video_adapter_name(),"human_playtest":"PENDING"}
	var file:=FileAccess.open(OUT.path_join("summary.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"));file.close()
	print("DECOR_GPU success=",not failed," checks=",checks," captures=",captures)
	room.close();room.queue_free();await process_frame;quit(1 if failed else 0)
