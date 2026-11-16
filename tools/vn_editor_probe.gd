@tool
extends Node
## Runs only in a separate actual editor process with --td-vn-editor-probe.
const Document := preload("res://addons/td_vn_editor/document.gd")
var panel: Control
var checks: Array[Dictionary] = []
var output := "res://artifacts/vn-editor-20261116/editor-gpu"
var original: String

func _ready() -> void:
	run.call_deferred()

func expect(value: bool, label: String) -> void:
	checks.append({"name":label,"pass":value})
	if not value: printerr("VNE_PROBE_FAIL " + label)

func shot(label: String) -> void:
	await get_tree().process_frame
	# Background editor windows can skip redraw; explicitly render this real viewport.
	RenderingServer.force_draw(true)
	var screenshot := get_viewport().get_texture().get_image()
	expect(screenshot.save_png(output.path_join(label+".png")) == OK,"capture "+label)

func press(caption: String) -> void:
	var button := find_button(panel,caption)
	expect(button != null,"button "+caption)
	if button != null: button.pressed.emit()
	await get_tree().process_frame

func find_button(node: Node, caption: String) -> Button:
	if node is Button and node.text == caption: return node
	for child: Node in node.get_children():
		var found := find_button(child,caption)
		if found != null: return found
	return null

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	# Editor SceneTreeTimers do not tick like a running game. Use the real clock.
	var until := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < until: await get_tree().process_frame
	print("VNE_EDITOR_READY scanning=",EditorInterface.get_resource_filesystem().is_scanning())
	for i in 3: await get_tree().process_frame
	EditorInterface.set_main_screen_editor("剧情")
	EditorInterface.set_distraction_free_mode(true)
	original = FileAccess.get_file_as_string(Document.INTRO)
	expect(panel.is_visible_in_tree(),"native editor tab visible")
	panel.page_mode = false; panel._refresh()
	expect(panel.rows.item_count > 20,"opening steps loaded")
	await press("检查")
	expect(panel.status.text.contains("检查通过"),"native parser in editor")
	panel.selected = 37; panel._refresh()
	await shot("01-opening")
	await press("新建")
	expect(panel.document.path == "","new unsaved document")
	var edit := panel.controls.text as TextEdit
	edit.text = "今天从这里开始。"; edit.text_changed.emit()
	await press("应用到预览")
	expect(panel.document.text().contains("今天从这里开始"),"field updates native txt")
	expect(panel.preview.state.text == "今天从这里开始。","composition updates")
	await press("撤销")
	expect(not panel.document.text().contains("今天从这里开始"),"undo edit")
	await press("重做")
	expect(panel.document.text().contains("今天从这里开始"),"redo edit")
	panel.action_menu.get_popup().id_pressed.emit(2)
	expect(panel.document.lines[panel.selected].begins_with("@show"),"add portrait step")
	await press("×")
	expect(not panel.document.lines[panel.selected].begins_with("@show"),"delete portrait step")
	await press("检查")
	expect(panel.status.text.contains("检查通过"),"new scene passes")
	await shot("02-edit-dialogue")
	panel.action_menu.get_popup().id_pressed.emit(6)
	expect(panel.controls.target is OptionButton,"choice target uses visual dropdown")
	expect(panel._value("target") == "finish","choice targets existing end node")
	panel.controls.text.text = "去港口看看"; panel.controls.text.text_changed.emit("去港口看看")
	await press("应用到预览")
	expect(panel.document.lines[panel.selected] == "- 去港口看看 -> finish","choice form writes native grammar")
	await shot("04-choice-form")
	await press("×")
	var path := Document.ROOT + "__editor_probe_" + str(Time.get_ticks_usec()) + ".txt"
	panel._save(path)
	expect(FileAccess.file_exists(path),"real save creates txt")
	expect(FileAccess.get_file_as_string(path).contains("今天从这里开始"),"saved edited words")
	var saved_hash := FileAccess.get_sha256(path)
	panel.document.replace_line(3,"hero: 未保存试玩。"); panel._refresh()
	var play_key := InputEventKey.new(); play_key.keycode = KEY_ENTER; play_key.ctrl_pressed = true; play_key.pressed = true
	Input.parse_input_event(play_key); await get_tree().process_frame
	play_key = InputEventKey.new(); play_key.keycode = KEY_ENTER; play_key.ctrl_pressed = true; play_key.pressed = false
	Input.parse_input_event(play_key); await get_tree().process_frame
	expect(panel.preview_pid > 0,"Ctrl Enter launches real preview process")
	# Give the independent runtime enough frames to load resources.
	var preview_until := Time.get_ticks_msec() + 2500
	while Time.get_ticks_msec() < preview_until: await get_tree().process_frame
	expect(OS.is_process_running(panel.preview_pid),"preview remains running")
	expect(FileAccess.get_sha256(path) == saved_hash,"preview does not save edits")
	panel.stop_preview()
	var file := FileAccess.open(path,FileAccess.WRITE); file.store_string("// other author\n"); file.close()
	panel.save_document()
	expect(panel.status.text.contains("其他程序修改"),"external edit protected in UI")
	await shot("03-conflict")
	panel._write_recovery()
	var recovery: Variant = JSON.parse_string(FileAccess.get_file_as_string(panel.RECOVERY))
	expect(recovery is Dictionary and str(recovery.get("text","")).contains("未保存试玩"),"recovery captures draft")
	expect(FileAccess.get_file_as_string(Document.INTRO) == original,"official opening unchanged")
	panel.document.load_text(""); panel.field_dirty = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(panel.RECOVERY))
	var failures := 0
	for check: Dictionary in checks:
		if not check.pass: failures += 1
	var report := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"count":checks.size(),"failures":failures},"\t")); report.close()
	print("VNE_EDITOR_GPU checks=%d failures=%d" % [checks.size(),failures])
	get_tree().quit(1 if failures > 0 else 0)
