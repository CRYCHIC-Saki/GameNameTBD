extends SceneTree
func _initialize() -> void:
	var folder:=ProjectSettings.globalize_path("res://artifacts/audio-integration-20261126/export-probe")
	DirAccess.make_dir_recursive_absolute(folder)
	var zip:=ZIPReader.new()
	if zip.open(ProjectSettings.globalize_path("res://artifacts/export/runtime.zip"))!=OK: quit(1);return
	var pack:=PCKPacker.new()
	if pack.pck_start(folder+"/AudioProbe.pck")!=OK: quit(1);return
	for path: String in zip.get_files():
		if path=="project.binary": continue
		var target:=folder+"/resources/"+path
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		var file:=FileAccess.open(target,FileAccess.WRITE);file.store_buffer(zip.read_file(path));file.close()
		if pack.add_file("res://"+path,target)!=OK: quit(1);return
	zip.close()
	ProjectSettings.set_setting("application/run/main_scene","res://audio_probe.tscn")
	ProjectSettings.save_custom(folder+"/project.binary")
	pack.add_file("res://project.binary",folder+"/project.binary")
	var script:=FileAccess.get_file_as_string("res://tools/audio_probe.gd")
	var file:=FileAccess.open(folder+"/audio_probe.gd",FileAccess.WRITE);file.store_string(script);file.close()
	pack.add_file("res://audio_probe.gd",folder+"/audio_probe.gd")
	file=FileAccess.open(folder+"/audio_probe.tscn",FileAccess.WRITE)
	file.store_string('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://audio_probe.gd" id="1"]\n[node name="AudioProbe" type="Node"]\nscript = ExtResource("1")\n');file.close()
	pack.add_file("res://audio_probe.tscn",folder+"/audio_probe.tscn")
	var status:=pack.flush();print("AUDIO_PACK status=",status);quit(0 if status==OK else 1)
