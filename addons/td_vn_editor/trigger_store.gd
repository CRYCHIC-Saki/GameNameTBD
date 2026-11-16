@tool
extends RefCounted
const Document := preload("res://addons/td_vn_editor/document.gd")
const Files := preload("res://addons/td_vn_editor/asset_import.gd")
var path: String = TDStoryEvents.PATH
var files := Files.new()

func read() -> Dictionary:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	var error := TDStoryEvents.validate_catalog(raw)
	return {"error":error,"data":raw if error.is_empty() else {},"hash":FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""}

func save(row: Dictionary, expected_hash: String) -> String:
	var loaded := read()
	if not loaded.error.is_empty(): return loaded.error
	if loaded.hash != expected_hash: return "触发设置已被其他操作修改，请关闭后重新打开。"
	var document := Document.new()
	var error := document.open_file(row.script_path)
	if not error.is_empty(): return error
	var issues := document.validate()
	# Host controls remain in the protected opening; no rename or chapter escape.
	var host_issue := TDStoryEvents.validate_authored_source(document.text())
	if not host_issue.is_empty(): issues.append(host_issue)
	if not issues.is_empty(): return "剧本尚未通过检查：\n"+"\n".join(issues)
	var data: Dictionary = loaded.data.duplicate(true)
	var found := false
	for i: int in data.events.size():
		if data.events[i].id == row.id:
			if data.events[i].script_path != row.script_path: return "演出身份不能改绑到其他文件。"
			data.events[i] = row.duplicate(true); found = true
	if not found: data.events.append(row.duplicate(true))
	error = TDStoryEvents.validate_catalog(data)
	if not error.is_empty(): return error
	var backup := "res://.godot/td_vn_editor/trigger_backups/"+str(Time.get_ticks_usec())+".json"
	if files._write(backup,FileAccess.get_file_as_bytes(path)) != OK: return "无法备份原触发设置。"
	if FileAccess.get_sha256(path) != expected_hash: return "触发设置发生变化，已保留原文件。"
	if files._write(path,JSON.stringify(data,"\t").to_utf8_buffer()) != OK: return "无法保存触发设置，原文件保留。"
	return ""
