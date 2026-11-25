extends GutTest

var room: TDRestaurantWorld
var viewport: SubViewport
var storage: String

func before_each() -> void:
	storage="user://decor-options-test-%d-%d.json"%[OS.get_process_id(),Time.get_ticks_usec()]
	viewport=SubViewport.new();viewport.size=Vector2i(1280,800)
	add_child_autofree(viewport)
	room=TDRestaurantWorld.new();room.player_mode=true
	viewport.add_child(room);await wait_process_frames(2)
	room._toggle_edit();await wait_process_frames(3)

func after_each() -> void:
	for suffix: String in ["",".tmp",".bak"]:
		if FileAccess.file_exists(storage+suffix): DirAccess.remove_absolute(storage+suffix)

func test_catalog_exposes_all_five_themes_per_kind_without_mutating_room() -> void:
	var before:=room.layout.to_dict()
	assert_eq(room._decor_panel.find_children("*","OptionButton",true,false).size(),0)
	var seen: Dictionary={}
	for category: String in TDDecorationPanel.CATEGORIES:
		room._decor_panel.select_category(category);await wait_process_frames(1)
		for card: TDDecorationPanel.Card in room._decor_panel._cards.get_children():
			if card.piece.is_empty():
				seen[card.finish]=true
			else:
				seen[str(card.piece.kind)+":"+str(card.piece.style_id)]=true
				assert_true(card.details.contains("×"))
	for theme: String in ["chinese","french","japanese"]:
		assert_true(seen.has("floor_"+theme));assert_true(seen.has("wall_"+theme))
		for kind: String in room.catalog.kinds():
			if kind in ["screen","kiosk"]:
				assert_true(seen.has(kind+":plain_low"))
				assert_false(seen.has(kind+":"+theme+"_low"))
			else: assert_true(seen.has(kind+":"+theme+"_low"),kind+" / "+theme)
	room._decor_panel.select_category("陈设")
	assert_eq(room._decor_panel._cards.get_child_count(),2)
	assert_true(room._decor_panel.furniture_choice("screen__japanese_low").is_empty())
	assert_true(room._decor_panel.furniture_choice("hotpot_table").is_empty())
	assert_eq(room.layout.to_dict(),before,"Browsing never changes the venue or existing furniture")

func test_regional_card_mouse_input_preview_place_rotate_move_and_cancel() -> void:
	var original_pieces:=room.layout.pieces()
	await choose("餐桌","dining_table__japanese_low")
	assert_eq(room._tool,"place");assert_eq(room._armed_kind,"dining_table")
	room._hover_at(Vector2i(8,7))
	assert_true(room._iso.ghost_ok);assert_eq(str(room._iso.ghost_piece.style_id),"japanese_low")
	assert_eq(room.layout.pieces(),original_pieces,"Preview is read-only")
	await click(room._iso.get_global_transform_with_canvas()*TDRestaurantIsoView.project(8.5,7.5))
	var id:=room._selected
	assert_false(room.layout.piece(id).is_empty())
	assert_eq(str(room.layout.piece(id).style_id),"japanese_low")
	var center:=TDFurnitureModel.center(room.layout.piece(id))
	await click(room._iso.get_global_transform_with_canvas()*(center+Vector2(0,-45)))
	assert_true(room._context_menu.visible)
	await click(room._rotate_button.get_global_rect().get_center())
	assert_eq(int(room.layout.piece(id).rotation),270)
	assert_eq(TDFurnitureModel.center(room.layout.piece(id)),center)
	# The existing move transaction must preserve the per-item style.
	assert_true(room.layout.move_piece(id,10,7).ok)
	assert_eq(str(room.layout.piece(id).style_id),"japanese_low")
	for piece: Dictionary in original_pieces: assert_eq(room.layout.piece(piece.id),piece)
	assert_eq(room.layout.culture,"chinese")
	await choose("餐桌","dining_table__japanese_low")
	room._hover_at(Vector2i(8,7));room._cancel_decoration()
	assert_true(room._iso.ghost_piece.is_empty())
	await choose("餐桌","dining_table")
	room._hover_at(Vector2i(8,7))
	assert_eq(str(room._iso.ghost_piece.style_id),"chinese_low","Base card does not inherit the last selected regional style")

func test_real_surface_cards_replace_whole_room_and_resolve_the_selected_theme() -> void:
	var pieces:=room.layout.pieces()
	await choose("地面","floor_french")
	await choose("墙壁","wall_japanese")
	assert_eq(room._tool,"select");assert_true(room._iso.ghost_piece.is_empty())
	for y: int in room.layout.rows:
		for x: int in room.layout.columns:
			assert_eq(room.layout.finish_at(x,y),"wall_japanese" if room.layout.cell_zone(x,y)=="facade" else "floor_french")
	assert_eq(room._iso._wall_style(Vector2i(0,2)),"japanese")
	assert_eq(room._iso._wall_paint(Vector2i(0,2),true),Color("eee3c9"))
	assert_eq(TDRestaurantArt.finish_color("floor_french"),Color("747569"))
	assert_eq(room.layout.pieces(),pieces);assert_eq(room.layout.culture,"chinese")

func test_all_new_finishes_disk_round_trip_and_reject_unknown_or_wrong_surface() -> void:
	var store:=TDRestaurantStore.new(storage)
	for theme: String in ["chinese","french","japanese"]:
		assert_true(room.layout.set_surface_finish("floor_"+theme).ok)
		assert_true(room.layout.set_surface_finish("wall_"+theme).ok)
		assert_true(store.save_layout(room.layout).ok)
		assert_true(store.load_layout(room.catalog).ok)
		assert_eq(store.loaded_layout.to_dict(),room.layout.to_dict())
		assert_eq(store.loaded_layout.finish_at(8,7),"floor_"+theme)
		assert_eq(store.loaded_layout.finish_at(0,0),"wall_"+theme)
	var before:=room.layout.to_dict()
	assert_false(room.layout.set_surface_finish("floor_future").ok)
	assert_false(room.layout.set_finish(8,7,"wall_japanese").ok)
	assert_false(room.layout.set_finish(0,0,"floor_french").ok)
	assert_eq(room.layout.to_dict(),before)
	assert_eq(TDRegionalInterior.finish_style("wall_japanese_extra"),"")
	assert_true(room._decor_panel.furniture_choice("dining_table__japanese_low__extra").is_empty())
	assert_true(room._decor_panel.furniture_choice("dining_table__unknown_low").is_empty())

func test_old_finishes_and_mixed_furniture_remain_compatible_with_saved_layouts() -> void:
	var placed:=room.layout.place("dining_table",8,7,0,"japanese_low")
	assert_true(placed.ok)
	var id:=str(placed.data.id)
	var store:=TDRestaurantStore.new(storage)
	for pair: Array in [["wood","paper"],["tile","stripe"],["stone","floral"],["carpet","brick"]]:
		assert_true(room.layout.set_surface_finish(pair[0]).ok)
		assert_true(room.layout.set_surface_finish(pair[1]).ok)
		assert_true(store.save_layout(room.layout).ok);assert_true(store.load_layout(room.catalog).ok)
		assert_eq(store.loaded_layout.to_dict(),room.layout.to_dict())
		assert_eq(str(store.loaded_layout.piece(id).style_id),"japanese_low")
		assert_eq(int(store.loaded_layout.to_dict().schema_version),1)

func test_last_regional_card_is_reachable_in_small_window_and_has_real_art() -> void:
	viewport.size=Vector2i(1024,720);await wait_process_frames(4)
	await choose("服务台","cashier__japanese_low")
	assert_eq(room._culture,"japanese");assert_eq(room._armed_kind,"cashier")
	var card:=room._decor_panel._cards.get_node("Item_cashier__japanese_low") as TDDecorationPanel.Card
	assert_gt(TDFurnitureModel.bounds(card.piece).size.y,30.0)
	var scroll:=room._decor_panel._cards.get_parent() as ScrollContainer
	assert_gt(scroll.scroll_horizontal,0)
	assert_true(scroll.get_global_rect().has_point(card.get_global_rect().get_center()))
	assert_lte(room._decor_panel.get_global_rect().end.x,1024.0)

func choose(category: String,id: String) -> void:
	room._decor_panel.select_category(category);await wait_process_frames(2)
	var card:=room._decor_panel._cards.get_node("Item_"+id) as Button
	var scroll:=room._decor_panel._cards.get_parent() as ScrollContainer
	scroll.ensure_control_visible(card);await wait_process_frames(2)
	await click(card.get_global_rect().get_center())

func click(point: Vector2) -> void:
	var motion:=InputEventMouseMotion.new();motion.position=point;motion.global_position=point
	viewport.push_input(motion,true);await wait_process_frames(1)
	for pressed: bool in [true,false]:
		var event:=InputEventMouseButton.new();event.position=point;event.global_position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed
		viewport.push_input(event,true);await wait_process_frames(1)
	await wait_process_frames(2)
