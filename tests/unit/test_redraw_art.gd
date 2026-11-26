extends GutTest

func test_all_active_catalogue_ids_have_redrawn_icons_and_unknown_ids_have_no_false_mapping() -> void:
	var materials: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/culinary_materials.json"))
	var recipes: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/research/recipe_atlas.json"))
	var index:=TDRedrawArt.catalog()
	assert_eq(index.ingredient_ids.size(),materials.items.size())
	assert_eq(index.dish_ids.size(),recipes.recipes.size())
	for id: String in materials.items:
		assert_true(index.ingredients.has(id),id)
		assert_not_null(TDRedrawArt.ingredient(id),id)
		assert_gt(TDRedrawArt.ingredient(id).get_width(),5,id)
	for row: Dictionary in recipes.recipes: assert_true(index.dishes.has(row.id),row.id)
	assert_null(TDRedrawArt.ingredient("missing"));assert_null(TDRedrawArt.dish("missing"))
	assert_same(TDRedrawArt.ingredient("oil"),TDRedrawArt.ingredient("peanut_oil"))

func test_expression_changes_keep_one_canvas_and_pose_while_actions_do_not_replace_the_portrait() -> void:
	for who: String in ["hero","aling","chen","luo"]:
		var seen: Dictionary={}
		var neutral:=TDStoryArt.portrait(who) as AtlasTexture
		for mood: String in ["calm","happy","angry","proud","cry","puzzled","troubled","speechless"]:
			var art:=TDStoryArt.portrait(who,mood) as AtlasTexture
			assert_eq(art.get_size(),neutral.get_size(),who+" stationary canvas")
			assert_same(art,TDStoryArt.portrait(who,mood,"握住锅柄"))
			assert_true(Rect2(Vector2.ZERO,art.atlas.get_size()).encloses(art.region))
			seen[art.atlas.resource_path]=true
		assert_eq(seen.size(),8)

func test_vn_portraits_are_behind_the_full_width_text_panel_and_expression_refreshes() -> void:
	var view:=TDDialogueView.new();add_child_autofree(view)
	var talk:=TDDialogue.new();talk.story_layout("焰子","aling")
	talk.add_line("焰子","hero","测试。","happy");talk.add_line("焰子","hero","下一句。","sad")
	view.present(talk);view.set_process(false)
	await wait_process_frames(2)
	assert_gt(view._panel.z_index,view._portrait.z_index)
	assert_gt(view._panel.z_index,view._right_portrait.z_index)
	assert_gt(view._vn_stage.dialog.background_box.size.x,1100.0)
	assert_eq(view._portrait.offset_bottom,0.0)
	await wait_process_frames(2)
	view._vn_stage.dialog._reveal_to_end();view._vn_stage.dialog._advance_dialog()
	await wait_process_frames(2)
	var actor := view._vn_stage.runner.ctx.characters.active_sprites.hero as VNEngineCharacterSprite
	assert_eq((actor.sprite.texture as AtlasTexture).region,(TDStoryArt.portrait("hero","sad") as AtlasTexture).region)
	view.finish_now()
	await wait_process_frames(2)


func test_active_dish_slots_preserve_original_art_identity_after_region_filtering() -> void:
	var index := TDRedrawArt.catalog()
	for id: String in index.dish_ids:
		var slot: int = int(index.dish_slots[id])
		assert_eq(index.dishes[id].path, "res://assets/redraw-v1/dishes-%d.png" % (slot / 20), id)
		assert_eq(index.dishes[id].index, slot % 20, id)
		assert_not_null(TDRedrawArt.dish(id), id)
