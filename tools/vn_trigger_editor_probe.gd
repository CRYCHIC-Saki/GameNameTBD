@tool
extends "res://tools/vn_slides_probe.gd"

func run() -> void:
	output="res://artifacts/vn-triggers-20261116/editor"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	await pause_ms(8000);EditorInterface.set_main_screen_editor("剧情")
	panel.page_mode=false;panel._refresh()
	var before:=FileAccess.get_file_as_bytes(TDStoryEvents.PATH)
	var backup:=FileAccess.open(output.path_join("catalog-before.json"),FileAccess.WRITE);backup.store_buffer(before);backup.close()
	var path:=Document.ROOT+"__trigger_probe_"+str(Time.get_ticks_usec())+".txt"
	panel.document.load_text("# start\n@bg restaurant-v1 with instant 0\n@show hero happy at left with instant\nhero: 这段演出由进入餐厅触发。\n# done\n@end\n")
	panel.selected=3;panel._refresh();panel._save(path)
	expect(FileAccess.file_exists(path),"saved new author chapter")
	await press("开发接入")
	var dialog:ConfirmationDialog=panel.trigger_dialog
	expect(dialog.visible,"trigger panel opens")
	dialog.heading.text="餐厅触发示例"
	dialog.select_value(dialog.kind,"place");dialog.kind.item_selected.emit(dialog.kind.selected)
	dialog.select_value(dialog.target,"restaurant")
	dialog.select_value(dialog.milestone,"intro")
	dialog.select_value(dialog.effect,"cuisine");dialog.effect.item_selected.emit(dialog.effect.selected)
	dialog.select_value(dialog.reward,"jp")
	await pause_ms(300);RenderingServer.force_draw(true)
	expect(dialog.get_texture().get_image().save_png(output.path_join("trigger-panel.png"))==OK,"capture configuration")
	dialog.get_ok_button().pressed.emit();await pause_ms(100)
	expect(not dialog.visible,"save trigger closes")
	var catalog:=TDStoryEvents.new();expect(catalog.error.is_empty(),"registered catalog validates")
	var row:Dictionary=catalog.definitions[-1]
	expect(row.type=="place" and row.target=="restaurant" and row.milestone_required=="intro","actual user selections persisted")
	expect(row.effect.kind=="cuisine" and row.effect.target=="jp","unlock uses supported interface")
	await press("开发接入");expect(dialog.heading.text=="餐厅触发示例","reopen title")
	expect(dialog.value(dialog.target)=="restaurant" and dialog.value(dialog.milestone)=="intro","reopen selections")
	dialog.heading.text="未保存名称";dialog.get_cancel_button().pressed.emit();await pause_ms(100)
	expect(TDStoryEvents.new().definitions[-1].title=="餐厅触发示例","cancel preserves registry")
	panel.open_document(Document.INTRO);await press("开发接入")
	expect(not dialog.visible and panel.status.text.contains("固定触发"),"original opening protected")
	var draft_path:=path.trim_suffix(".txt")+"_unpublished.txt"
	var draft:=FileAccess.open(draft_path,FileAccess.WRITE);draft.store_string("# draft\nnarrator: 未发布草稿不能进入导出包。\n# done\n@end\n");draft.close()
	var fixture:=FileAccess.open(output.path_join("fixture.json"),FileAccess.WRITE)
	fixture.store_string(JSON.stringify({"rule":row,"path":path,"draft":draft_path,"registered_hash":FileAccess.get_sha256(TDStoryEvents.PATH),"script_hash":FileAccess.get_sha256(path),"draft_hash":FileAccess.get_sha256(draft_path)},"\t"));fixture.close()
	var failures:=0
	for item:Dictionary in checks:
		if not item.pass:failures+=1
	var report:=FileAccess.open(output.path_join("report.json"),FileAccess.WRITE);report.store_string(JSON.stringify({"count":checks.size(),"failures":failures,"checks":checks},"\t"));report.close()
	print("VN_TRIGGER_EDITOR checks=%d failures=%d"%[checks.size(),failures]);get_tree().quit(1 if failures else 0)
