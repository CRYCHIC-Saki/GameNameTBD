@tool
extends "res://addons/vn_engine/src/editor/vn_export_plugin.gd"
## Local host adapter: native baking, explicit runtime chapter allowlist.
const Document := preload("res://addons/td_vn_editor/document.gd")

func _add_scenario_files(scenario_root: String) -> void:
	if scenario_root != TDStoryEvents.ROOT:
		super._add_scenario_files(scenario_root); return
	var events := TDStoryEvents.new()
	if not events.error.is_empty(): push_error(events.error); return
	var presentation: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/story/vn/presentation.json"))
	var paths: Array[String] = ["res://content/story/vn/scenario/host/script.txt"]
	for chapter: Dictionary in presentation.chapters.values(): paths.append(chapter.path)
	var builtins := paths.duplicate()
	for row: Dictionary in events.definitions:
		if row.enabled: paths.append(row.script_path)
	for path: String in paths:
		var doc := Document.new()
		var error := doc.open_file(path)
		var issues := doc.validate() if error.is_empty() else PackedStringArray([error])
		if path not in builtins:
			var host_issue := TDStoryEvents.validate_authored_source(doc.text())
			if not host_issue.is_empty(): issues.append(host_issue)
		if not issues.is_empty(): push_error("VN export: "+path+" / "+"; ".join(issues)); continue
		if not _seen_txt.has(path): _seen_txt[path]=true; _bake_scenario(path)
