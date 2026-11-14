extends GutTest

func test_shared_surfaces_keep_uniform_sibling_tints_and_readable_text() -> void:
	var base:=TDUI.theme()
	var management:=TDManagementPanels.theme()
	for state: String in ["normal","hover","pressed","disabled"]:
		var a:=base.get_stylebox(state,"Button") as TDUI.WoodStyle
		var b:=management.get_stylebox(state,"Button") as TDUI.WoodStyle
		assert_not_null(a);assert_not_null(b)
		assert_same(a.texture,TDUI.WOOD);assert_same(b.texture,TDUI.WOOD)
		assert_eq(a.modulate_color,b.modulate_color,"same button level across screens")
	assert_ne(TDUI.TINTS[TDUI.Surface.FRAME],TDUI.TINTS[TDUI.Surface.CARD])
	assert_ne(TDUI.TINTS[TDUI.Surface.CARD],TDUI.TINTS[TDUI.Surface.INSET])
	var pixels:=TDUI.WOOD.get_image()
	if pixels.is_compressed(): pixels.decompress()
	for tint: Color in TDUI.TINTS:
		for at: Vector2i in [Vector2i(128,128),Vector2i(400,400),Vector2i(800,800)]:
			var surface: Color=pixels.get_pixelv(at)*tint
			assert_gt((_light(surface)+.05)/(_light(TDUI.INK)+.05),4.5,"dark text on every wood depth")

func _light(color: Color) -> float:
	var linear:=color.srgb_to_linear()
	return linear.r*.2126+linear.g*.7152+linear.b*.0722

func test_blackface_family_is_used_by_native_controls_and_dialogue_paper_is_in_front() -> void:
	assert_eq(Array(TDUI.font().font_names),["SimHei"])
	var view:=TDDialogueView.new();add_child_autofree(view)
	var talk:=TDDialogue.new();talk.story_layout("焰子","aling");talk.add_line("阿铃","aling","羊皮纸上的黑体文字。","happy")
	view.present(talk);view.set_process(false)
	var plate:=view._panel.get_theme_stylebox("panel") as StyleBoxTexture
	assert_not_null(plate);assert_same(plate.texture,TDUI.PARCHMENT)
	assert_eq(view._body.get_theme_font("font").get_font_name(),TDUI.font().get_font_name())
	assert_gt(view._panel.z_index,view._portrait.z_index)
	assert_gt(view._panel.z_index,view._right_portrait.z_index)
	view.finish_now()

func test_expression_regions_keep_full_square_compositions_including_original_decorations() -> void:
	for who: String in ["hero","aling","chen","luo"]:
		for i: int in TDRedrawArt.EMOTIONS.size():
			var art:=TDStoryArt.portrait(who,TDRedrawArt.EMOTIONS[i]) as AtlasTexture
			assert_true(art.atlas.resource_path.begins_with("res://assets/ui-wood-v1/portrait-"))
			var dimensions:=Vector2(art.atlas.get_width()/3,art.atlas.get_height()/2)
			assert_eq(art.region,Rect2(Vector2(i%3,i/3)*dimensions,dimensions),"no cutout or alpha trim")

func test_enlarged_reply_choices_do_not_overlap_prompt_or_hint() -> void:
	var viewport:=SubViewport.new();viewport.size=Vector2i(1280,800);add_child_autofree(viewport)
	var view:=TDDialogueView.new();viewport.add_child(view)
	var talk:=TDDialogue.new()
	talk.add_line("阿铃","aling","从集市买回新鲜的蔬菜以后，我们可以先回厨房备菜，然后开门迎接今天的客人。你想先了解哪一件事？")
	talk.add_choice([{"id":"a","label":"先了解今天的食材。"},{"id":"b","label":"看看厨房里的准备工作。"},{"id":"c","label":"聊聊今天来到小镇的客人。"}])
	view.present(talk);view.set_process(false);talk.click();talk.click();view._refresh()
	await wait_process_frames(3)
	assert_true(talk.choices_open)
	assert_lte(view._body.get_rect().end.y,view._choices.position.y)
	assert_lte(view._choices.get_rect().end.y,view._hint.position.y)
	assert_lte(view._hint.get_rect().end.y,view._panel.size.y)
	for reply: Button in view._choices.get_children():
		assert_eq(reply.get_theme_font_size("font_size"),TDUI.FONT_BODY)
	view.finish_now()
