@tool
extends "res://tools/vn_slides_probe.gd"
## Real editor input, separate scratch scenario; restore author recovery externally.

func run() -> void:
	output = "res://artifacts/vn-canvas-20261117/editor-gpu"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	await pause_ms(8000)
	EditorInterface.set_main_screen_editor("剧情"); EditorInterface.set_distraction_free_mode(true)
	original = FileAccess.get_file_as_string(Document.INTRO)
	await press("新建")
	panel._visual("background","restaurant-v1")
	panel._visual("actor","hero")
	panel.zoom_control.value = 25
	await pause_ms(300)
	var source: String = panel.document.text()
	var start: Vector2 = panel.preview.actor_bounds("hero").get_center()
	var finish := start + Vector2(1500,-900)
	await mouse_at(canvas_point(start),true)
	expect(panel.preview.dragging,"real input selects actor")
	await move_mouse(canvas_point(finish)); await mouse_at(canvas_point(finish),false)
	var token: String = panel.document.composition(panel.selected).actors.hero.position
	var layout := TDVNLayout.parse(token)
	expect(float(layout.x)>1 and float(layout.y)<0,"real drag exits right and top edges")
	await shot("01-offscreen")
	await press("撤销"); expect(panel.document.text()==source,"one undo restores drag")
	await press("重做"); expect(panel.document.composition(panel.selected).actors.hero.position==token,"redo restores offscreen")
	await mouse_at(canvas_point(Vector2(640,400)),true); await mouse_at(canvas_point(Vector2(640,400)),false)
	expect(panel.selected_actor.is_empty(),"deselect fully offscreen actor")
	var picker: OptionButton = panel.actor_picker
	picker.select(1); picker.item_selected.emit(1); await pause_ms(200)
	expect(panel.selected_actor=="hero" and panel.preview.selected_actor=="hero","list recovers hidden actor and selection outline")
	panel.actor_scale.value = 5
	await pause_ms(200)
	var enlarged := TDVNLayout.parse(panel.document.composition(panel.selected).actors.hero.position)
	expect(float(enlarged.scale)==5 and float(enlarged.x)==float(layout.x) and float(enlarged.y)==float(layout.y),"5x preserves offscreen anchor")
	await press("回到画面")
	var bounds: Rect2 = panel.preview.actor_bounds("hero")
	expect(bounds.get_center().distance_to(Vector2(640,400))<.01,"recenter enlarged actor, not only its feet")
	expect(absf(bounds.size.y-3025)<.01,"recenter preserves scale")
	panel.zoom_control.value = 10
	await pause_ms(200)
	await shot("02-five-times")
	panel.actor_scale.value = 2
	await press("回到画面")
	panel.zoom_control.value = 70
	await pause_ms(200)
	await shot("03-close-up")
	source = panel.document.text()
	start = panel.preview.actor_bounds("hero").get_center()
	await mouse_at(canvas_point(start),true); await move_mouse(canvas_point(start+Vector2(-100,0)))
	var escape := InputEventKey.new(); escape.keycode = KEY_ESCAPE; escape.pressed = true
	Input.parse_input_event(escape); await get_tree().process_frame
	await mouse_at(canvas_point(start+Vector2(-100,0)),false)
	expect(panel.document.text()==source,"escape cancels oversized actor drag")
	var path := Document.ROOT + "__canvas_probe_" + str(Time.get_ticks_usec()) + ".txt"
	panel._save(path)
	expect(FileAccess.file_exists(path),"save real native scenario")
	panel.open_document(path)
	expect(panel.document.text()==source,"reopen preserves position and size")
	expect(panel.document.validate().is_empty(),"native scenario validates")
	expect(FileAccess.get_file_as_string(Document.INTRO)==original,"formal opening unchanged")
	panel.document.load_text(""); panel.field_dirty = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var failures := 0
	for check: Dictionary in checks:
		if not check.pass: failures += 1
	var report := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"count":checks.size(),"failures":failures},"\t")); report.close()
	print("VNE_CANVAS_GPU checks=%d failures=%d" % [checks.size(),failures])
	get_tree().quit(1 if failures > 0 else 0)
