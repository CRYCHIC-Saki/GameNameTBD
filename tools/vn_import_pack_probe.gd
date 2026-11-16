extends SceneTree
## Run with --main-pack and an empty working directory, not the project checkout.
func _initialize() -> void:
	var checks := 0
	var failures := 0
	for argument: String in OS.get_cmdline_user_args():
		if not argument.begins_with("--asset="): continue
		var texture: Texture2D = load(argument.trim_prefix("--asset="))
		checks += 1
		if texture == null or texture.get_width() <= 0 or texture.get_height() <= 0: failures += 1
	if checks != 3: failures += 1
	print("VN_IMPORT_PACK checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)
