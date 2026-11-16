@tool
extends "res://tools/vn_slides_probe.gd"
var imports: Array[Dictionary] = []
var out := "res://artifacts/vn-import-20261116/gpu"

func remember(result: Dictionary, _insert: bool) -> void:
	var receipt: Dictionary = result.duplicate(true)
	for item: Dictionary in receipt.applied:
		item.old = "" if item.old.is_empty() else Marshalls.raw_to_base64(item.old)
	imports.append(receipt)
	var file := FileAccess.open(out.path_join("imports.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(imports,"\t")); file.close()

func submit_import(kind_index: int, source_path: String, title_value: String, character_id: String = "") -> void:
	await press("导入素材")
	var dialog: ConfirmationDialog = panel.import_dialog
	dialog.kind.select(kind_index); dialog.kind.item_selected.emit(kind_index)
	for i in dialog.character.item_count:
		if dialog.character.get_item_metadata(i) == character_id: dialog.character.select(i)
	dialog.picker.file_selected.emit(source_path)
	dialog.title_edit.text = title_value
	expect(dialog.preview.texture != null,"chosen image preview "+title_value)
	await pause_ms(100); RenderingServer.force_draw(true)
	expect(dialog.get_texture().get_image().save_png(out.path_join("import-"+str(kind_index)+".png")) == OK,"dialog capture "+str(kind_index))
	var count := imports.size()
	dialog.get_ok_button().pressed.emit()
	expect(dialog.busy,"busy protects repeat import")
	dialog._import() # duplicate dispatch is harmless while scan is pending
	var until := Time.get_ticks_msec()+65000
	while dialog.busy and Time.get_ticks_msec()<until: await get_tree().process_frame
	expect(imports.size()==count+1,"one import committed "+title_value)
	expect(not dialog.visible,"import dialog finishes "+title_value)
	print("IMPORT_RESULT ",title_value," ",dialog.feedback.text)

func run() -> void:
	output = out
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	await pause_ms(8000)
	EditorInterface.set_main_screen_editor("剧情"); EditorInterface.set_distraction_free_mode(true)
	panel.import_dialog.imported.connect(remember)
	original = FileAccess.get_file_as_string(Document.INTRO)
	await press("新建")
	# Disposable input fixtures copied from existing registered art. No original changes.
	var background: Texture2D = load(Document.BG_ROOT+"arrival-coast-v1.tres")
	background.get_image().save_png(out.path_join("港口 图片.png"))
	var portrait: Texture2D = load(Document.portrait_path("aling","calm"))
	portrait.get_image().save_png(out.path_join("角色 图片.png"))
	var expression: Texture2D = load(Document.portrait_path("aling","happy"))
	expression.get_image().save_png(out.path_join("表情 图片.png"))
	await press("导入素材")
	panel.import_dialog.picker.file_selected.emit(out.path_join("港口 图片.png"))
	panel.import_dialog.hide()
	expect(imports.is_empty(),"cancel does not import")
	await submit_import(0,out.path_join("港口 图片.png"),"导入示例·港口")
	if imports.size() < 1: await finish(); return
	expect(panel.preview.state.background == imports[0].id,"background immediately inserted")
	expect(Document.background_title(imports[0].id) == "导入示例·港口","background Chinese label")
	await submit_import(1,out.path_join("角色 图片.png"),"示例角色")
	if imports.size() < 2: await finish(); return
	var actor: String = imports[1].character
	expect(Document.cast_names().get(actor,"") == "示例角色","new actor visible despite old cast cache")
	expect(panel.preview.state.actors.has(actor),"new character immediately inserted")
	await submit_import(2,out.path_join("表情 图片.png"),"惊讶",actor)
	if imports.size() < 3: await finish(); return
	expect(Document.expression_title(actor,imports[2].expression) == "惊讶","expression Chinese label")
	expect(panel.preview.state.actors[actor].expression == imports[2].expression,"new expression selected")
	await shot("04-inserted")
	var edit: TextEdit = panel.controls.text; edit.text = "导入的角色和背景可以直接编排、试玩。"; edit.text_changed.emit()
	await pause_ms(800)
	var speaker: OptionButton = panel.controls.speaker
	for i in speaker.item_count:
		if speaker.get_item_metadata(i) == actor: speaker.select(i); speaker.item_selected.emit(i)
	panel._commit_fields()
	var script_file := FileAccess.open(out.path_join("draft.txt"),FileAccess.WRITE)
	script_file.store_string(panel.document.text()); script_file.close()
	expect(panel.check_document(),"native script accepts imported cast and art")
	await press("导入素材")
	panel.import_dialog.kind.select(1); panel.import_dialog.kind.item_selected.emit(1)
	panel.import_dialog.picker.file_selected.emit(out.path_join("角色 图片.png")); panel.import_dialog.title_edit.text="示例角色"
	panel.import_dialog.get_ok_button().pressed.emit()
	expect(panel.import_dialog.feedback.text.contains("同名角色"),"duplicate rejected in real UI")
	expect(imports.size()==3,"no duplicate registration")
	panel.import_dialog.hide()
	expect(FileAccess.get_file_as_string(Document.INTRO)==original,"formal intro unchanged")
	await finish()

func finish() -> void:
	# Keep only explicit test imports for the following native-play/export verification.
	# Their preimages and hashes are in imports.json for guarded restoration afterwards.
	panel.document.load_text(""); panel.field_dirty=false
	var failures := 0
	for item: Dictionary in checks:
		if not item.pass: failures+=1
	var report := FileAccess.open(out.path_join("report.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify({"count":checks.size(),"failures":failures,"checks":checks},"\t")); report.close()
	print("VN_IMPORT_GPU checks=%d failures=%d" % [checks.size(),failures])
	get_tree().quit(1 if failures else 0)
