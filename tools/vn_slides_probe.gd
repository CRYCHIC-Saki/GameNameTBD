@tool
extends "res://tools/vn_editor_probe.gd"
## Actual editor viewport input. Never edits the formal opening or player storage.

func pause_ms(milliseconds: int) -> void:
	var until := Time.get_ticks_msec()+milliseconds
	while Time.get_ticks_msec() < until: await get_tree().process_frame

func mouse_at(point: Vector2, down: bool) -> void:
	var motion := InputEventMouseMotion.new(); motion.position = point; motion.global_position = point
	Input.parse_input_event(motion); await get_tree().process_frame
	var event := InputEventMouseButton.new(); event.button_index = MOUSE_BUTTON_LEFT
	event.position = point; event.global_position = point; event.pressed = down
	Input.parse_input_event(event); await get_tree().process_frame

func move_mouse(point: Vector2) -> void:
	var event := InputEventMouseMotion.new(); event.position = point; event.global_position = point
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(event); await get_tree().process_frame

func canvas_point(value: Vector2) -> Vector2:
	return panel.preview.get_global_transform() * panel.preview.canvas_transform() * value

func palette_pick(caption: String) -> void:
	var found: Button
	for child: Node in panel.palette.get_node("AssetGrid").get_children():
		if child is Button and child.tooltip_text == caption: found = child; break
	expect(found != null,"palette " + caption)
	if found != null: found.pressed.emit()
	await pause_ms(120)

func run() -> void:
	output = "res://artifacts/vn-slides-20261116/editor-gpu"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	await pause_ms(8000)
	EditorInterface.set_main_screen_editor("剧情"); EditorInterface.set_distraction_free_mode(true)
	original = FileAccess.get_file_as_string(Document.INTRO)
	expect(panel.page_mode and panel.page_scroll.visible and not panel.rows.visible,"default is slides")
	await press("新建")
	expect(panel.document.path.is_empty(),"new draft")
	await press("插入背景"); await pause_ms(100)
	RenderingServer.force_draw(true)
	expect(panel.palette.get_texture().get_image().save_png(output.path_join("01-backgrounds.png")) == OK,"capture background picker")
	await palette_pick("餐厅")
	expect(panel.preview.state.background == "restaurant-v1","insert registered background")
	await press("插入角色"); await palette_pick("？？？")
	expect(panel.preview.state.actors.has("hero"),"insert hero")
	await press("插入角色"); await palette_pick("阿铃")
	expect(panel.preview.state.actors.size() == 2,"insert two characters")
	var edit: TextEdit = panel.controls.text
	edit.text = "欢迎来到小镇。拖动人物，就能安排这一页的画面。"; edit.text_changed.emit()
	await pause_ms(800)
	expect(panel.document.text().contains("欢迎来到小镇"),"dialogue automatically commits")
	var source: String = panel.document.text()
	var start: Vector2 = panel.preview.actor_bounds("hero").get_center()
	var finish := start + Vector2(150,-50)
	await mouse_at(canvas_point(start),true)
	expect(panel.preview.dragging and panel.selected_actor == "hero","real viewport selects hero")
	await move_mouse(canvas_point(finish))
	await mouse_at(canvas_point(finish),false)
	expect(panel.document.text() != source,"real drag commits")
	var layout := TDVNLayout.parse(panel.document.composition(panel.selected).actors.hero.position)
	expect(absf(float(layout.get("x",0))-.4171875)<.003 and absf(float(layout.get("y",0))-.79375)<.003,"drag uses 2D design coordinates")
	await shot("02-dragged")
	var dragged: String = panel.document.text()
	await press("撤销"); expect(panel.document.text() == source,"drag one undo")
	expect(panel.selected == panel.document.pages()[0].line,"undo keeps selected slide")
	await press("重做"); expect(panel.document.text() == dragged,"drag redo")
	expect(panel.selected == panel.document.pages()[0].line,"redo keeps selected slide")
	await press("复制这一页")
	expect(panel.document.pages().size() == 3,"duplicate plus end page")
	var second_before: Dictionary = panel.document.composition(panel.selected).duplicate(true)
	panel.page_list.get_child(0).pressed.emit(); await pause_ms(100)
	expect(panel.selected == panel.document.pages()[0].line,"thumbnail changes selected page")
	await press("插入背景"); await palette_pick("港口")
	var pages: Array = panel.document.pages()
	expect(panel.document.composition(pages[1].line).background == "restaurant-v1","other page background unchanged")
	expect(panel.document.composition(pages[1].line).actors == second_before.actors,"other page actors unchanged")
	start = panel.preview.actor_bounds("hero").get_center()
	source = panel.document.text()
	await mouse_at(canvas_point(start),true); await move_mouse(canvas_point(start+Vector2(80,30)))
	var escape := InputEventKey.new(); escape.keycode = KEY_ESCAPE; escape.pressed = true
	Input.parse_input_event(escape); await get_tree().process_frame
	await mouse_at(canvas_point(start+Vector2(80,30)),false)
	expect(panel.document.text() == source,"Esc cancels drag without document change")
	await press("缩小")
	expect(float(TDVNLayout.parse(panel.document.composition(panel.selected).actors.hero.position).scale)<1,"uniform resize")
	await shot("03-slides")
	await press("检查"); expect(panel.status.text.contains("检查通过"),"native syntax checks")
	print("SLIDE_VALIDATION ",panel.status.text)
	var debug_source := FileAccess.open(output.path_join("source.txt"),FileAccess.WRITE)
	debug_source.store_string(panel.document.text()); debug_source.close()
	var path := Document.ROOT + "__slides_probe_" + str(Time.get_ticks_usec()) + ".txt"
	panel._save(path)
	expect(FileAccess.file_exists(path),"save native file")
	source = panel.document.text(); panel.open_document(path)
	expect(panel.document.text() == source,"save reopen exact layout")
	panel.play_draft(); await pause_ms(2000)
	expect(panel.preview_pid > 0 and OS.is_process_running(panel.preview_pid),"real native preview process")
	panel.stop_preview()
	panel.page_list.get_child(1).pressed.emit(); await pause_ms(100)
	await press("删除这一页")
	expect(panel.document.pages().size() == 2,"delete authored slide")
	expect(FileAccess.get_file_as_string(Document.INTRO) == original,"original source unchanged")
	panel.document.load_text(""); panel.field_dirty = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(panel.RECOVERY))
	var failures := 0
	for check: Dictionary in checks:
		if not check.pass: failures += 1
	var report := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"count":checks.size(),"failures":failures},"\t")); report.close()
	print("VNE_SLIDES_GPU checks=%d failures=%d" % [checks.size(),failures])
	get_tree().quit(1 if failures > 0 else 0)
