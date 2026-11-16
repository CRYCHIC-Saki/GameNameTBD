@tool
extends "res://tools/vn_slides_probe.gd"
const Handoff := preload("res://addons/td_vn_editor/handoff.gd")

func run() -> void:
	output="res://artifacts/vn-handoff-20261116/editor"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	await pause_ms(8000);EditorInterface.set_main_screen_editor("剧情");EditorInterface.set_distraction_free_mode(true)
	var intro_hash:=FileAccess.get_sha256(Document.INTRO);var registry_hash:=FileAccess.get_sha256(TDStoryEvents.PATH)
	var path:=Handoff.DRAFTS+"__handoff_probe_"+str(Time.get_ticks_usec())+".txt"
	panel.document.load_text("# start\n@bg restaurant-v1 with instant 0\n@show hero happy at left with instant\nhero: 这是美术编排的新演出。\n# done\n@end\n")
	panel.selected=3;panel._refresh()
	expect(panel.page_mode and not panel.trigger_button.visible,"artist mode hides technical binding")
	await press("保存")
	var dialog:ConfirmationDialog=panel.handoff_dialog
	expect(dialog.visible,"save opens Chinese handoff form")
	dialog.get_ok_button().pressed.emit();await pause_ms(100)
	expect(dialog.visible and dialog.error_label.text.contains("至少填写"),"missing placement blocks save")
	dialog.get_cancel_button().pressed.emit();await pause_ms(100)
	expect(not dialog.visible and not FileAccess.file_exists(path),"cancel does not save")
	await press("保存")
	dialog.fields.title.text="老陈赠料后的第一道菜"
	dialog.fields.section.text="第一章 · 第一次做番茄炒蛋"
	dialog.fields.placement.text="接在老陈赠送食材之后，玩家去冰箱取料之前。\n播放完成后交还玩家操作。"
	dialog.fields.notes.text="替换原来这一段对话，食材奖励仍由程序处理。"
	await pause_ms(300);RenderingServer.force_draw(true)
	expect(dialog.get_texture().get_image().save_png(output.path_join("01-save-notes.png"))==OK,"capture artist form")
	expect(dialog.size.y<=800,"dialog fits normal desktop height")
	dialog.get_ok_button().pressed.emit();await pause_ms(100)
	expect(panel.file_dialog.visible and panel.file_dialog.current_dir.trim_suffix("/")==Handoff.DRAFTS.trim_suffix("/"),"new save suggests drafts folder")
	panel.file_dialog.hide();panel.file_dialog.file_selected.emit(path);await pause_ms(100)
	expect(FileAccess.file_exists(path) and not panel.document.dirty(),"actual file dialog handler saves native TXT")
	var parsed:=Handoff.read(FileAccess.get_file_as_string(path))
	expect(parsed.error.is_empty() and parsed.data.section=="第一章 · 第一次做番茄炒蛋","notes persist")
	expect(panel.document.lines[panel.selected].begins_with("hero:"),"selected slide survives inserted header")
	panel.controls.text.text="保存交接说明后仍能编辑这一页。";panel.controls.text.text_changed.emit();await pause_ms(800)
	expect(panel.document.text().contains("hero: 保存交接说明后仍能编辑这一页。"),"editing after header affects dialogue")
	await press("保存");expect(dialog.fields.title.text=="老陈赠料后的第一道菜","next save prefills notes")
	dialog.get_ok_button().pressed.emit();await pause_ms(100)
	expect(not panel.document.dirty() and not panel.file_dialog.visible,"existing draft saves without another path picker")
	panel.open_document(path)
	expect(panel.status.text.contains("第一章") and panel.document.text().count(Handoff.BEGIN)==1,"reopen reads handoff without duplicate header")
	await press("保存")
	dialog.fields.placement.text="不保存的修改"
	find_button(dialog,"×").pressed.emit();await pause_ms(100)
	expect(not dialog.visible and not Handoff.read(FileAccess.get_file_as_string(path)).data.placement.contains("不保存"),"visible close discards unconfirmed fields")
	await press("另存为");expect(dialog.visible,"save as asks handoff too")
	dialog.get_ok_button().pressed.emit();await pause_ms(100)
	panel.file_dialog.hide();panel.file_dialog.canceled.emit()
	expect(panel._handoff_pending.is_empty() and panel.document.path==path,"file cancel preserves original draft")
	await shot("02-saved-editor")
	panel.page_mode=false;panel._refresh();expect(panel.trigger_button.visible,"developer binding retained in advanced mode")
	panel.page_mode=true;panel.open_document(Document.INTRO)
	await press("保存")
	expect(dialog.visible and dialog.info.text.contains("另存为待接入副本"),"formal opening save is copy-only")
	dialog.get_ok_button().pressed.emit();await pause_ms(100)
	panel.file_dialog.hide();panel.file_dialog.file_selected.emit(Document.INTRO)
	expect(panel.status.text.contains("另存为待接入副本") and FileAccess.get_sha256(Document.INTRO)==intro_hash,"choosing formal opening path cannot overwrite it")
	expect(FileAccess.get_sha256(TDStoryEvents.PATH)==registry_hash,"artist flow does not register triggers")
	var fixture:=FileAccess.open(output.path_join("fixture.json"),FileAccess.WRITE)
	fixture.store_string(JSON.stringify({"path":path,"hash":FileAccess.get_sha256(path),"intro_hash":intro_hash,"registry_hash":registry_hash},"\t"));fixture.close()
	panel.document.load_text("");panel.field_dirty=false
	var failures:=0
	for item:Dictionary in checks:
		if not item.pass:failures+=1
	var report:=FileAccess.open(output.path_join("report.json"),FileAccess.WRITE);report.store_string(JSON.stringify({"count":checks.size(),"failures":failures,"checks":checks},"\t"));report.close()
	print("VN_HANDOFF_EDITOR checks=%d failures=%d"%[checks.size(),failures]);get_tree().quit(1 if failures else 0)
