extends GutTest
var room: TDRestaurantWorld
var viewport: SubViewport

func before_each() -> void:
	# Keep real GUI input separate from the GUT runner's own controls.
	viewport=SubViewport.new();viewport.size=Vector2i(1280,800)
	add_child_autofree(viewport)
	room=TDRestaurantWorld.new();room.player_mode=true
	viewport.add_child(room);await get_tree().process_frame
	room._toggle_edit();await wait_process_frames(3)

func after_each() -> void:
	get_tree().paused=false

func test_categories_show_all_existing_items_and_do_not_change_layout() -> void:
	assert_eq(room._decor_panel.find_children("*","OptionButton",true,false).size(),0)
	var before:=room.layout.to_dict()
	var seen: Dictionary={}
	for category: String in TDDecorationPanel.CATEGORIES:
		room._decor_panel.select_category(category)
		await get_tree().process_frame
		assert_gt(room._decor_panel._cards.get_child_count(),0)
		for card: TDDecorationPanel.Card in room._decor_panel._cards.get_children():
			if not card.piece.is_empty(): seen[card.piece.kind]=true;assert_true(card.details.contains("×"))
	for kind: String in room.catalog.kinds(): assert_true(seen.has(kind),kind)
	assert_eq(room.layout.to_dict(),before)

func test_real_card_input_ghost_rotation_cancel_and_invalid_preview_are_readonly() -> void:
	room._decor_panel.select_category("陈设");await wait_process_frames(2)
	var card:=room._decor_panel._cards.get_node("Item_kiosk") as Button
	var before:=room.layout.to_dict()
	await click(card.get_global_rect().get_center())
	assert_eq(room._armed_kind,"kiosk");assert_eq(room._tool,"place")
	room._hover_at(Vector2i(8,8))
	assert_false(room._iso.ghost_piece.is_empty());assert_true(room._iso.ghost_ok)
	assert_lt(TDFurnitureModel.bounds(room._iso.ghost_piece).position.y,-70.0)
	room._spin(1);assert_eq(int(room._iso.ghost_piece.rotation),90)
	room._hover_at(Vector2i(0,0));assert_false(room._iso.ghost_ok)
	assert_false(room._iso.ghost_piece.is_empty(),"Invalid placement still shows the model")
	assert_eq(room.layout.to_dict(),before)
	room._click_cell(Vector2i(-1,-1),MOUSE_BUTTON_RIGHT)
	assert_true(room._iso.ghost_piece.is_empty());assert_eq(room.layout.to_dict(),before)

func test_click_upper_model_then_context_buttons_do_not_pass_through() -> void:
	assert_true(room.place_kind("kiosk",8,8).ok)
	var id:=room._selected;room._set_tool("select")
	var piece:=room.layout.piece(id)
	var model_top:=TDFurnitureModel.center(piece)+Vector2(0,-65)
	await click(room._iso.get_global_transform_with_canvas()*model_top)
	assert_eq(room._selected,id);assert_true(room._context_menu.visible)
	assert_eq(room._context_menu.find_children("*","Button",true,false).size(),2)
	assert_lt(room._delete_button.position.x,room._rotate_button.position.x)
	var count:=room.layout.pieces().size()
	await click(room._rotate_button.get_global_rect().get_center())
	assert_eq(int(room.layout.piece(id).rotation),270)
	assert_eq(room.layout.pieces().size(),count)
	await click(room._delete_button.get_global_rect().get_center())
	assert_true(room.layout.piece(id).is_empty());assert_false(room._context_menu.visible)
	assert_eq(room.layout.pieces().size(),count-1)
	assert_eq(room.remove_selected().code,"MISSING")

func test_finish_is_visual_only_and_cover_exit_clear_transients() -> void:
	var before:=room.layout.to_dict()
	for category: String in ["地面","墙壁"]:
		await click(find_button(room._decor_panel,category).get_global_rect().get_center())
		var card:=room._decor_panel._cards.get_node("Item_"+("carpet" if category=="地面" else "floral")) as Button
		await click(card.get_global_rect().get_center())
		assert_eq(room._tool,"select","Finish card applies immediately, never arms a cell brush")
		assert_true(room._iso.ghost_piece.is_empty())
	var whole_surface: bool=true
	for y: int in room.layout.rows:
		for x: int in room.layout.columns:
			whole_surface=whole_surface and room.layout.finish_at(x,y)==("floral" if room.layout.cell_zone(x,y)=="facade" else "carpet")
	assert_true(whole_surface,"Real card input replaces both entire surfaces")
	assert_eq(room.layout.to_dict().pieces,before.pieces)
	var count:=room.layout.pieces().size()
	room._click_cell(Vector2i(8,8))
	assert_eq(room.layout.finish_at(8,8),"carpet");assert_true(room.layout.is_walkable(8,8))
	room._choose_decoration("dining_table",false);room._hover_at(Vector2i(8,8))
	room.set_floor_cover(true)
	assert_true(room._iso.ghost_piece.is_empty());assert_false(room._context_menu.visible)
	room.set_floor_cover(false);room._toggle_edit()
	assert_false(room._decor_panel.visible);assert_eq(room.layout.pieces().size(),count)
	room._toggle_edit();assert_true(room._decor_panel.visible);assert_eq(room._tool,"select")

func test_table_four_corner_rotations_keep_center_footprint_and_restore() -> void:
	assert_true(room.place_kind("dining_table",8,7).ok)
	var id:=room._selected
	var original:=room.layout.piece(id)
	room._select_furniture(id);await wait_process_frames(3)
	var anchor:=TDFurnitureModel.center(original)
	for angle: int in [270,180,90,0]:
		await click(room._rotate_button.get_global_rect().get_center())
		var current:=room.layout.piece(id)
		assert_eq(int(current.rotation),angle)
		assert_eq(TDFurnitureModel.center(current),anchor)
		assert_eq(Vector2i(current.x,current.y),Vector2i(8,7))
		assert_eq(Vector2i(current.w,current.h),Vector2i(2,2))
		assert_false(room.layout.feet_inside(room.layout.cell_center(Vector2i(8,7))))
	assert_eq(room.layout.piece(id),original)

func test_failed_rotation_from_menu_keeps_layout_and_reports_reason() -> void:
	assert_true(room.place_kind("welcome_desk",8,7).ok)
	var id:=room._selected
	assert_true(room.place_kind("stool",8,8).ok)
	room._select_furniture(id);await wait_process_frames(4)
	var before:=room.layout.to_dict()
	await click(room._rotate_button.get_global_rect().get_center())
	assert_eq(room.layout.to_dict(),before)
	assert_eq(int(room.layout.piece(id).rotation),0)
	assert_true(room._context_menu.visible)
	assert_true(room._decor_panel._info.text.contains("重叠"))

func test_catalog_resize_category_cancel_and_pause_input() -> void:
	for dimensions: Vector2i in [Vector2i(1024,720),Vector2i(1600,1000)]:
		viewport.size=dimensions;await wait_process_frames(4)
		var rect:=room._decor_panel.get_global_rect()
		assert_lte(rect.end.x,float(dimensions.x));assert_lte(rect.end.y,float(dimensions.y))
		assert_gt(rect.position.y,300.0)
	room._choose_decoration("kiosk",false);room._hover_at(Vector2i(8,8))
	room._decor_panel.select_category("墙壁")
	assert_eq(room._tool,"select");assert_true(room._iso.ghost_piece.is_empty())
	room._select_furniture("piece-kiosk");await wait_process_frames(4)
	var before:=room.layout.to_dict()
	get_tree().paused=true;await wait_process_frames(2)
	assert_false(room._context_menu.visible)
	assert_true(room._iso.ghost_piece.is_empty())
	var card:=room._decor_panel._cards.get_node("Item_brick") as Button
	await click(card.get_global_rect().get_center())
	assert_eq(room._tool,"select");assert_eq(room.layout.to_dict(),before)
	get_tree().paused=false

func test_move_preview_is_readonly_and_preserves_identity_and_style() -> void:
	assert_true(room.place_kind("welcome_desk",8,7).ok)
	var id:=room._selected
	assert_true(room.layout.restyle_piece(id,"japanese","high").ok)
	var before:=room.layout.to_dict()
	var same:=room.layout.preview_move(id,8,7)
	assert_true(same.ok,"Original footprint does not collide with itself")
	var adjacent:=room.layout.preview_move(id,9,7)
	assert_true(adjacent.ok,"Partial overlap with own old footprint is allowed")
	assert_eq(adjacent.piece.style_id,"japanese_high")
	adjacent.piece.x=100
	assert_eq(room.layout.to_dict(),before)
	assert_eq(room.layout.preview_move("missing",8,7).code,"MISSING")

func test_real_drag_commits_once_and_save_roundtrip_keeps_piece() -> void:
	assert_true(room.place_kind("kiosk",8,7).ok)
	var id:=room._selected;var count:=room.layout.pieces().size()
	var start:=model_point(id)
	await mouse_button(start,true)
	var end:=start+room._iso.get_global_transform_with_canvas().basis_xform(Vector2(96,48))
	await move_mouse(end)
	assert_true(room._dragging);assert_eq(int(room.layout.piece(id).x),8)
	assert_eq(int(room._iso.ghost_piece.x),10)
	await mouse_button(end,true,MOUSE_BUTTON_WHEEL_UP)
	assert_eq(int(room.layout.piece(id).rotation),0,"Wheel during dragging cannot mutate the old piece")
	await mouse_button(end,false)
	assert_false(room._dragging);assert_eq(int(room.layout.piece(id).x),10)
	assert_eq(int(room.layout.piece(id).y),7);assert_eq(room.layout.pieces().size(),count)
	assert_eq(room.layout.piece(id).style_id,"chinese_low")
	var restored:=TDRestaurantLayout.import_dict(room.layout.to_dict(),room.catalog)
	assert_eq(restored.piece(id),room.layout.piece(id))

func test_invalid_drag_ui_release_and_cancellation_leave_layout_unchanged() -> void:
	assert_true(room.place_kind("kiosk",8,7).ok)
	var id:=room._selected;assert_true(room.place_kind("stool",10,7).ok)
	var before:=room.layout.to_dict()
	for action: String in ["overlap","outside","ui","right","pause","cover","exit","focus","resize"]:
		var start:=model_point(id)
		await mouse_button(start,true)
		var delta:=Vector2(96,48) if action=="overlap" else Vector2(-48,24)
		var end:=start+room._iso.get_global_transform_with_canvas().basis_xform(delta)
		if action=="outside": end=Vector2(-100,-100)
		await move_mouse(end)
		assert_true(room._dragging,action)
		match action:
			"ui": end=room._decor_panel.get_global_rect().get_center();await move_mouse(end)
			"right": await mouse_button(end,true,MOUSE_BUTTON_RIGHT)
			"pause": get_tree().paused=true;await wait_process_frames(2);get_tree().paused=false
			"cover": room.set_floor_cover(true);room.set_floor_cover(false)
			"exit": room._toggle_edit();room._toggle_edit()
			"focus": room._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
			"resize": viewport.size=Vector2i(1600,1000);await wait_process_frames(3)
		await mouse_button(end,false)
		assert_false(room._dragging,action);assert_true(room._iso.ghost_piece.is_empty(),action)
		assert_eq(room.layout.to_dict(),before,action)

func model_point(id: String) -> Vector2:
	return room._iso.get_global_transform_with_canvas()*(TDFurnitureModel.center(room.layout.piece(id))+Vector2(0,-45))

func move_mouse(point: Vector2) -> void:
	var event:=InputEventMouseMotion.new();event.position=point;event.global_position=point
	viewport.push_input(event,true);await wait_process_frames(2)

func mouse_button(point: Vector2, pressed: bool, button: MouseButton=MOUSE_BUTTON_LEFT) -> void:
	var event:=InputEventMouseButton.new();event.position=point;event.global_position=point;event.button_index=button;event.pressed=pressed
	viewport.push_input(event,true);await wait_process_frames(2)

func find_button(node: Node, title: String) -> Button:
	if node is Button and node.text==title: return node as Button
	for child: Node in node.get_children():
		var found:=find_button(child,title)
		if found!=null: return found
	return null

func click(point: Vector2) -> void:
	var motion:=InputEventMouseMotion.new();motion.position=point;motion.global_position=point
	viewport.push_input(motion,true);await get_tree().process_frame
	for pressed: bool in [true,false]:
		var event:=InputEventMouseButton.new();event.position=point;event.global_position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed
		viewport.push_input(event,true);await get_tree().process_frame
	await wait_process_frames(2)
