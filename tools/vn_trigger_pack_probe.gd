extends SceneTree
## Standalone check against --main-pack from an empty directory.
func _initialize() -> void:
	var checks:=0;var failures:=0
	var data:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://content/story/events.json"))
	checks+=1
	if not data is Dictionary or data.events.size()!=1:failures+=1
	else:
		var path:String=data.events[0].script_path
		var baked:Resource=load(path+".res")
		checks+=1
		if baked==null or baked.nodes.is_empty() or baked.source_path!=path:failures+=1
		checks+=1
		if ResourceLoader.exists(path.trim_suffix(".txt")+"_unpublished.txt.res"):failures+=1
		checks+=1
		if FileAccess.file_exists(path):failures+=1
	print("VN_TRIGGER_PACK checks=%d failures=%d"%[checks,failures]);quit(1 if failures else 0)
