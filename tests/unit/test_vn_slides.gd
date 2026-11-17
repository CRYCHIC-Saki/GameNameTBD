extends GutTest
const Document := preload("res://addons/td_vn_editor/document.gd")
const Canvas := preload("res://addons/td_vn_editor/composition.gd")
const SOURCE := "# first\n@bg arrival-coast-v1 with instant 0\n@show hero calm at left with instant\nhero: 第一页\n# second\nhero: 第二页\n# finish\n@end\n"

func test_narrator_pages_use_native_speaker_without_parser_warning() -> void:
	var doc := Document.new()
	doc.load_text("# slide_start\n@bg blank with instant 0\n"+Document.dialogue_line("","旁白。")+"\n# finish\n@end\n")
	assert_eq(doc.validate(),PackedStringArray())
	assert_eq(doc.composition(2).speaker,"")
	doc.new_page(2,true)
	assert_eq(doc.validate(),PackedStringArray())
	assert_eq(doc.text().count("narrator: 旁白。"),2)

func test_native_legacy_and_two_dimensional_geometry() -> void:
	assert_eq(TDVNLayout.rect("left"),Rect2(76.8,80,486.4,605))
	var rect := TDVNLayout.rect("td:0.6:0.8:0.8")
	assert_almost_eq(rect.position.x,573.44,.001)
	assert_almost_eq(rect.position.y,156.0,.001)
	assert_almost_eq(rect.size.x,389.12,.001)
	assert_almost_eq(rect.size.y,484.0,.001)
	assert_eq(TDVNLayout.rect("td:0.6:0.8:0.8",.64,Vector2(640,400)),Rect2(rect.position*.5,rect.size*.5))

func test_reject_invalid_layout_tokens() -> void:
	for token: String in ["td:x:.5:1","td:11.1:.5:1","td:.5:-10.1:1","td:.5:.5:5.01","td:.5:.5:.24","td:.5:nan:1","td:.5:.5", "td:.5:inf:1"]:
		assert_true(TDVNLayout.parse(token).is_empty(),token)
		var doc := Document.new(); doc.load_text(SOURCE.replace("at left","at "+token))
		assert_false(doc.validate().is_empty(),token)
	assert_eq(TDVNLayout.encode(NAN,.5,1.0),"")
	assert_eq(TDVNLayout.encode(.5,INF,1.0),"")

func test_offscreen_large_layout_roundtrip_and_page_independence() -> void:
	var doc := Document.new(); doc.load_text(SOURCE)
	var next_before := doc.composition(5)
	var anchor := doc.set_page_visual(3,"position","hero","td:-.3:1.4:5")
	assert_eq(doc.validate(),PackedStringArray())
	var rect := TDVNLayout.rect(doc.composition(anchor).actors.hero.position)
	assert_almost_eq(rect.position.x,-1600.0,.001)
	assert_almost_eq(rect.position.y,-1905.0,.001)
	assert_almost_eq(rect.size.x,2432.0,.001)
	assert_almost_eq(rect.size.y,3025.0,.001)
	var reloaded := Document.new(); reloaded.load_text(doc.text())
	assert_eq(reloaded.composition(reloaded.pages()[0].line).actors.hero.position,"td:-.3:1.4:5")
	assert_eq(reloaded.composition(reloaded.pages()[1].line),next_before)
	assert_eq(doc.undo_stack.size(),1)
	doc.undo(); assert_eq(doc.text(),SOURCE)
	for token: String in ["td:1.1:.5:1","td:.5:-1:1","td:-10:11:5","td:11:-10:.25"]:
		assert_false(TDVNLayout.parse(token).is_empty(),token)

func test_drag_outside_each_edge_at_different_editor_zooms() -> void:
	var canvas := Canvas.new(); add_child_autofree(canvas)
	canvas.size = Vector2(640,400); canvas.editable = true
	var doc := Document.new(); doc.load_text(SOURCE)
	var moved: Array = []
	canvas.actor_moved.connect(func(who: String,token: String) -> void: moved.append([who,token]))
	for zoom: float in [.1,.5,1.0]:
		canvas.set_view_zoom(zoom)
		for delta: Vector2 in [Vector2(-1000,0),Vector2(1500,0),Vector2(0,-1000),Vector2(0,1000)]:
			canvas.assign_state(doc.composition(3))
			var start := TDVNLayout.fit(canvas.actor_texture("hero"),canvas.actor_bounds("hero")).get_center()
			var down := InputEventMouseButton.new(); down.button_index=MOUSE_BUTTON_LEFT; down.pressed=true; down.position=canvas.canvas_transform()*start
			canvas._gui_input(down)
			var motion := InputEventMouseMotion.new(); motion.position=canvas.canvas_transform()*(start+delta)
			canvas._gui_input(motion)
			var up := InputEventMouseButton.new(); up.button_index=MOUSE_BUTTON_LEFT; up.position=motion.position
			canvas._gui_input(up)
			var rect := canvas.actor_bounds("hero")
			assert_almost_eq(rect.position.x,76.8+delta.x,.002)
			assert_almost_eq(rect.position.y,80.0+delta.y,.002)
	assert_eq(moved.size(),12)
	canvas.assign_state(doc.composition(3))
	var down := InputEventMouseButton.new(); down.button_index=MOUSE_BUTTON_LEFT; down.pressed=true; down.position=canvas.canvas_transform()*canvas.actor_bounds("hero").get_center()
	canvas._gui_input(down)
	var motion := InputEventMouseMotion.new(); motion.position=down.position+Vector2(400,0)
	canvas._gui_input(motion)
	canvas.set_view_zoom(.3)
	assert_false(canvas.dragging)
	assert_eq(canvas.state.actors.hero.position,"left","changing editor zoom cancels uncommitted drag")
	assert_eq(moved.size(),12)

func test_edit_one_slide_preserves_next_slide_and_undo_is_one_step() -> void:
	var doc := Document.new(); doc.load_text(SOURCE)
	var old_next := doc.composition(5)
	var anchor := doc.set_page_visual(3,"position","hero","td:0.6:0.8:0.8")
	assert_eq(doc.composition(anchor).actors.hero.position,"td:0.6:0.8:0.8")
	assert_eq(doc.composition(doc.pages()[1].line),old_next)
	assert_eq(doc.validate(),PackedStringArray())
	assert_eq(doc.undo_stack.size(),1)
	doc.undo(); assert_eq(doc.text(),SOURCE)
	doc.redo(); assert_eq(doc.composition(doc.pages()[0].line).actors.hero.position,"td:0.6:0.8:0.8")

func test_repeated_edits_replace_generated_block_without_bloat() -> void:
	var doc := Document.new(); doc.load_text(SOURCE)
	var anchor := doc.set_page_visual(3,"position","hero","td:.6:.8:1")
	var count := doc.lines.size()
	for i in 10: anchor = doc.set_page_visual(anchor,"position","hero",TDVNLayout.encode(.4+i*.01,.8))
	assert_eq(doc.lines.size(),count)
	assert_eq(doc.text().count(Document.CANVAS_BEGIN),2)
	assert_eq(doc.composition(doc.pages()[1].line).actors.hero.position,"left")

func test_insert_remove_background_actor_and_expression_are_page_local() -> void:
	var doc := Document.new(); doc.load_text(SOURCE)
	var anchor := doc.set_page_visual(3,"background","restaurant-v1")
	anchor = doc.set_page_visual(anchor,"actor","aling")
	anchor = doc.set_page_visual(anchor,"expression","aling","happy")
	assert_eq(doc.composition(anchor).background,"restaurant-v1")
	assert_eq(doc.composition(anchor).actors.aling.expression,"happy")
	var next := doc.composition(doc.pages()[1].line)
	assert_eq(next.background,"arrival-coast-v1")
	assert_false(next.actors.has("aling"))
	anchor = doc.set_page_visual(anchor,"remove","hero")
	assert_false(doc.composition(anchor).actors.has("hero"))
	assert_true(doc.composition(doc.pages()[1].line).actors.has("hero"))
	assert_eq(doc.validate(),PackedStringArray())

func test_new_duplicate_delete_and_protected_original_pages() -> void:
	var doc := Document.new(); doc.load_text(SOURCE)
	assert_eq(doc.remove_page(3),-1)
	var anchor := doc.new_page(3,true)
	assert_eq(doc.pages().size(),4)
	assert_eq(doc.composition(anchor).text,"第一页")
	assert_eq(doc.composition(anchor).actors.hero.position,"left")
	assert_eq(doc.validate(),PackedStringArray())
	assert_true(doc.remove_page(anchor) >= 0)
	assert_eq(doc.text(),SOURCE)

func test_custom_layout_survives_save_roundtrip_and_original_handoffs() -> void:
	var doc := Document.new(); doc.open_file(Document.INTRO)
	var anchor := int(doc.pages()[1].line)
	doc.set_page_visual(anchor,"position","hero","td:.55:.9:1")
	assert_eq(doc.validate(),PackedStringArray())
	var other := Document.new(); other.load_text(doc.text(),Document.INTRO)
	assert_eq(other.composition(other.pages()[1].line).actors.hero.position,"td:.55:.9:1")
	assert_eq(other.text().count("@td_name hero"),1)

func test_drag_coordinates_cancel_and_window_scaling() -> void:
	var canvas := Canvas.new(); add_child_autofree(canvas)
	canvas.size = Vector2(640,400); canvas.editable = true
	var doc := Document.new(); doc.load_text(SOURCE)
	canvas.assign_state(doc.composition(3))
	var moved: Array = []
	canvas.actor_moved.connect(func(who: String,token: String) -> void: moved.append([who,token]))
	var start := TDVNLayout.fit(canvas.actor_texture("hero"),canvas.actor_bounds("hero")).get_center()*.5
	var down := InputEventMouseButton.new(); down.button_index=MOUSE_BUTTON_LEFT; down.pressed=true; down.position=start
	canvas._gui_input(down)
	var motion := InputEventMouseMotion.new(); motion.position=start+Vector2(100,-15)
	canvas._gui_input(motion)
	assert_true(canvas.dragging)
	assert_ne(canvas.state.actors.hero.position,"left")
	canvas.cancel_drag(); assert_eq(canvas.state.actors.hero.position,"left"); assert_eq(moved.size(),0)
	for notification: int in [Control.NOTIFICATION_APPLICATION_FOCUS_OUT,Control.NOTIFICATION_VISIBILITY_CHANGED,Control.NOTIFICATION_RESIZED]:
		canvas._gui_input(down); canvas._gui_input(motion)
		canvas._notification(notification)
		assert_false(canvas.dragging)
		assert_eq(canvas.state.actors.hero.position,"left")
		assert_eq(moved.size(),0)
	canvas._gui_input(down); canvas._gui_input(motion)
	var up := InputEventMouseButton.new(); up.button_index=MOUSE_BUTTON_LEFT; up.position=motion.position
	canvas._gui_input(up)
	assert_eq(moved.size(),1)
	var layout := TDVNLayout.parse(moved[0][1])
	assert_almost_eq(float(layout.x),.40625,.00001)
	assert_almost_eq(float(layout.y),.81875,.00001)
