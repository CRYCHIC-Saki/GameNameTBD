extends SceneTree
## Build a disposable test PCK from the actual export. Nothing is added to the shipped PCK.
func _initialize() -> void:
	var smoke:bool="--startup-exit" in OS.get_cmdline_user_args()
	var travel:bool="--world-travel" in OS.get_cmdline_user_args()
	var branches:bool="--world-branches" in OS.get_cmdline_user_args()
	var novel:bool="--visual-novel" in OS.get_cmdline_user_args()
	var chef:bool="--chef-workflow" in OS.get_cmdline_user_args()
	var hud:bool="--hud-readability" in OS.get_cmdline_user_args()
	var protagonist:bool="--protagonist" in OS.get_cmdline_user_args()
	var districts:bool="--town-districts" in OS.get_cmdline_user_args()
	var panorama:bool="--jiangnan-panorama" in OS.get_cmdline_user_args()
	var approved:bool="--jiangnan-approved" in OS.get_cmdline_user_args()
	var shiomi:bool="--shiomi" in OS.get_cmdline_user_args()
	var folder:=ProjectSettings.globalize_path("res://artifacts/export/branch-probe" if branches else ("res://artifacts/export/travel-probe" if travel else ("res://artifacts/export/startup-probe" if smoke else "res://artifacts/export/title-probe")))
	if novel: folder=ProjectSettings.globalize_path("res://artifacts/export/novel-probe")
	if chef: folder=ProjectSettings.globalize_path("res://artifacts/export/chef-probe")
	if hud: folder=ProjectSettings.globalize_path("res://artifacts/export/hud-probe")
	if protagonist: folder=ProjectSettings.globalize_path("res://artifacts/export/protagonist-probe")
	if districts: folder=ProjectSettings.globalize_path("res://artifacts/export/district-probe")
	if panorama: folder=ProjectSettings.globalize_path("res://artifacts/export/panorama-probe")
	if approved: folder=ProjectSettings.globalize_path("res://artifacts/export/approved-jiangnan-probe")
	if shiomi: folder=ProjectSettings.globalize_path("res://artifacts/export/shiomi-probe")
	DirAccess.make_dir_recursive_absolute(folder)
	var zip:=ZIPReader.new()
	if zip.open(ProjectSettings.globalize_path("res://artifacts/export/runtime.zip"))!=OK: quit(1);return
	var pack:=PCKPacker.new()
	if pack.pck_start(folder+"/probe.pck")!=OK: quit(1);return
	for path:String in zip.get_files():
		if path=="project.binary": continue
		var temp:=folder+"/resources/"+path
		DirAccess.make_dir_recursive_absolute(temp.get_base_dir())
		var file:=FileAccess.open(temp,FileAccess.WRITE);file.store_buffer(zip.read_file(path));file.close()
		if pack.add_file("res://"+path,temp)!=OK: quit(1);return
	zip.close()
	ProjectSettings.set_setting("application/run/main_scene","res://probe.tscn")
	if ProjectSettings.save_custom(folder+"/project.binary")!=OK: quit(1);return
	if pack.add_file("res://project.binary",folder+"/project.binary")!=OK: quit(1);return
	var script:=FileAccess.get_file_as_string("res://tools/branch_probe.gd" if branches else ("res://tools/travel_probe.gd" if travel else ("res://tools/startup_exit_probe.gd" if smoke else "res://tools/title_input_probe.gd")))
	if novel: script=FileAccess.get_file_as_string("res://tools/visual_novel_probe.gd")
	if chef: script=FileAccess.get_file_as_string("res://tools/chef_workflow_probe.gd")
	if hud: script=FileAccess.get_file_as_string("res://tools/hud_readability_probe.gd")
	if protagonist: script=FileAccess.get_file_as_string("res://tools/protagonist_probe.gd")
	if districts: script=FileAccess.get_file_as_string("res://tools/town_district_probe.gd")
	if panorama: script=FileAccess.get_file_as_string("res://tools/jiangnan_district_probe.gd")
	if approved: script=FileAccess.get_file_as_string("res://tools/jiangnan_approved_probe.gd")
	if shiomi: script=FileAccess.get_file_as_string("res://tools/shiomi_probe.gd")
	script=script.replace("\r\n","\n")
	if branches:
		script=script.replace("res://artifacts/branch-world/gpu",folder+"/screenshots")
		script=script.replace("res://artifacts/branch-world/probe-slots/",folder+"/isolated-profiles/")
	if travel:
		script=script.replace("res://artifacts/travel-r1/gpu",folder+"/screenshots")
		script=script.replace("res://artifacts/travel-r1/probe/",folder+"/isolated-profiles/")
	script=script.replace("extends SceneTree","extends Node\nvar root: Window\nvar paused: bool:\n\tget: return get_tree().paused\nfunc quit(code: int) -> void: get_tree().quit(code)")
	script=script.replace('func _initialize() -> void: call_deferred("run")','func _ready() -> void:\n\troot=get_tree().root\n\tcall_deferred("run")')
	if shiomi:
		script=script.replace("func _initialize() -> void: run.call_deferred()","func _ready() -> void:\n\troot=get_tree().root\n\trun.call_deferred()")
		script=script.replace("res://artifacts/shiomi/",ProjectSettings.globalize_path("res://artifacts/shiomi/windows/"))
	if panorama:
		script=script.replace('func _initialize() -> void:\n\tcall_deferred("_run")','func _ready() -> void:\n\troot=get_tree().root\n\tcall_deferred("_run")')
		script=script.replace("res://artifacts/jiangnan-district-preview",folder+"/screenshots")
	if approved:
		script=script.replace('func _initialize() -> void:\n\tcall_deferred("_run")','func _ready() -> void:\n\troot=get_tree().root\n\tcall_deferred("_run")')
		script=script.replace("res://artifacts/approved-jiangnan/screens",folder+"/screenshots")
	if districts:
		script=script.replace('func _initialize() -> void:\n\tcall_deferred("run")','func _ready() -> void:\n\troot=get_tree().root\n\tcall_deferred("run")')
		script=script.replace("res://artifacts/town-art-d080/streets",folder+"/screenshots")
	if novel:
		script=script.replace("res://artifacts/vn-runtime-20261113/gpu",folder+"/screenshots")
		script=script.replace('func _initialize() -> void:\n\tcall_deferred("run")','func _ready() -> void:\n\troot=get_tree().root\n\tcall_deferred("run")')
	script=script.replace("await process_frame","await get_tree().process_frame")
	script=script.replace("await create_timer(","await get_tree().create_timer(")
	if chef: script=script.replace("res://artifacts/chef-workflow-20261114/gpu",folder+"/screenshots")
	if hud: script=script.replace("res://artifacts/quiet-hud-20261115/gpu",folder+"/screenshots")
	if protagonist: script=script.replace("res://artifacts/protagonist-diagonal-r1-20261116/gpu",folder+"/screenshots")
	# Match the signal only, never the similarly named physics_frames() helper.
	script=script.replace("await physics_frame\n","await get_tree().physics_frame\n")
	var file:=FileAccess.open(folder+"/probe.gd",FileAccess.WRITE);file.store_string(script);file.close()
	if pack.add_file("res://probe.gd",folder+"/probe.gd")!=OK: quit(1);return
	file=FileAccess.open(folder+"/probe.tscn",FileAccess.WRITE)
	file.store_string('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://probe.gd" id="1"]\n[node name="Probe" type="Node"]\nscript = ExtResource("1")\n');file.close()
	if pack.add_file("res://probe.tscn",folder+"/probe.tscn")!=OK: quit(1);return
	var result:=pack.flush();print("PACK_PROBE exit=",result);quit(0 if result==OK else 1)
