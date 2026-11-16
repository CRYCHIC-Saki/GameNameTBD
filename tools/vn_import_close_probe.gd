@tool
extends "res://tools/vn_slides_probe.gd"

func run() -> void:
	output = "res://artifacts/vn-import-close-20261116"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	await pause_ms(8000)
	EditorInterface.set_main_screen_editor("剧情")
	var original_cast := FileAccess.get_sha256(Document.CAST_PATH)
	var original_export := FileAccess.get_sha256("res://export_presets.cfg")
	await press("导入素材")
	var dialog: ConfirmationDialog = panel.import_dialog
	expect(dialog.close_button.visible and not dialog.close_button.disabled,"visible close button")
	dialog.select_source(ProjectSettings.globalize_path("res://assets/ui-wood-v1/portrait-aling-v2.png"))
	dialog.title_edit.text = "关闭前未提交"
	await pause_ms(100); RenderingServer.force_draw(true)
	expect(dialog.size.y < 800,"dialog remains within normal screen height")
	expect(dialog.get_texture().get_image().save_png(output.path_join("close-button.png")) == OK,"capture visible close")
	# Actual input routed into the popup viewport, not only a pressed signal.
	dialog.grab_focus()
	await pause_ms(200)
	var point: Vector2 = dialog.close_button.get_global_rect().get_center()
	print("CLOSE_GEOMETRY embedded=",dialog.is_embedded()," window=",dialog.get_window_id()," position=",dialog.position," point=",point," size=",dialog.size)
	if dialog.is_embedded(): point += Vector2(dialog.position)
	var motion := InputEventMouseMotion.new(); motion.position = point; motion.global_position = point; motion.window_id = dialog.get_window_id()
	Input.parse_input_event(motion); await get_tree().process_frame
	for down: bool in [true,false]:
		var mouse := InputEventMouseButton.new(); mouse.position = point; mouse.global_position = point; mouse.button_index = MOUSE_BUTTON_LEFT; mouse.pressed = down; mouse.window_id = dialog.get_window_id()
		Input.parse_input_event(mouse); await get_tree().process_frame
	expect(not dialog.visible,"mouse closes popup")
	expect(FileAccess.get_sha256(Document.CAST_PATH) == original_cast,"close does not register cast")
	expect(FileAccess.get_sha256("res://export_presets.cfg") == original_export,"close does not change export")
	await press("导入素材")
	expect(dialog.visible and dialog.source.is_empty() and dialog.title_edit.text.is_empty(),"reopen clears unsubmitted form")
	dialog.get_cancel_button().pressed.emit(); await get_tree().process_frame
	expect(not dialog.visible,"cancel still works")
	await press("导入素材")
	var escape := InputEventKey.new(); escape.pressed = true; escape.keycode = KEY_ESCAPE; escape.window_id = dialog.get_window_id()
	Input.parse_input_event(escape); await get_tree().process_frame
	expect(not dialog.visible,"Esc still works")
	var failures := 0
	for check: Dictionary in checks:
		if not check.pass: failures += 1
	var report := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"count":checks.size(),"failures":failures},"\t")); report.close()
	print("VN_IMPORT_CLOSE checks=%d failures=%d" % [checks.size(),failures])
	get_tree().quit(1 if failures else 0)
