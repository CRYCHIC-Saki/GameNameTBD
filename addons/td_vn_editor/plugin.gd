@tool
extends EditorPlugin
const StoryPanel := preload("res://addons/td_vn_editor/panel.gd")
var panel: Control

func _enter_tree() -> void:
	panel = StoryPanel.new()
	EditorInterface.get_editor_main_screen().add_child(panel)
	_make_visible(false)
	if "--td-vn-handoff-probe" in OS.get_cmdline_user_args():
		var probe: Node = load("res://tools/vn_handoff_editor_probe.gd").new()
		probe.panel = panel; add_child(probe)
	if "--td-vn-trigger-probe" in OS.get_cmdline_user_args():
		var probe: Node = load("res://tools/vn_trigger_editor_probe.gd").new()
		probe.panel = panel; add_child(probe)
	if "--td-vn-editor-probe" in OS.get_cmdline_user_args():
		var probe: Node = load("res://tools/vn_editor_probe.gd").new()
		probe.panel = panel
		add_child(probe)
	if "--td-vn-slides-probe" in OS.get_cmdline_user_args():
		var probe: Node = load("res://tools/vn_slides_probe.gd").new()
		probe.panel = panel
		add_child(probe)
	if "--td-vn-import-probe" in OS.get_cmdline_user_args():
		var probe: Node = load("res://tools/vn_import_probe.gd").new()
		probe.panel = panel
		add_child(probe)
	if "--td-vn-import-close-probe" in OS.get_cmdline_user_args():
		var probe: Node = load("res://tools/vn_import_close_probe.gd").new()
		probe.panel = panel
		add_child(probe)

func _exit_tree() -> void:
	if is_instance_valid(panel):
		panel._commit_fields(); panel._write_recovery(); panel.stop_preview()
		panel.queue_free()

func _has_main_screen() -> bool:
	return true

func _make_visible(value: bool) -> void:
	if is_instance_valid(panel): panel.visible = value

func _get_plugin_name() -> String:
	return "剧情"

func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon("RichTextLabel","EditorIcons")
