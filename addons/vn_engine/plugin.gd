@tool
extends EditorPlugin

# Local host patch: reuse native baking, only ship explicitly registered chapters.
const VNEngineExportPluginScript := preload("res://addons/td_vn_editor/export_plugin.gd")

var _export_plugin: EditorExportPlugin


func _enter_tree() -> void:
	_export_plugin = VNEngineExportPluginScript.new()
	add_export_plugin(_export_plugin)


func _exit_tree() -> void:
	remove_export_plugin(_export_plugin)
	_export_plugin = null
