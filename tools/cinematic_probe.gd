extends SceneTree
## Isolated production-view film capture. No profiles or player save files.
const OUT := "res://artifacts/cg-revision/frames"
var view: TDDialogueView
var rows: Array = []
var record: Array = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size=Vector2i(1280,800)
	view=TDDialogueView.new();root.add_child(view)
	await process_frame
	var found: Dictionary={}
	for sequence: Array in TDOpeningScript.data().scenes.values():
		for row: Dictionary in sequence:
			if row.kind=="cg" and not found.has(row.cg): rows.append(row);found[row.cg]=true
	for row: Dictionary in rows:
		var folder:=OUT.path_join(row.cg)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
		var talk:=TDDialogue.new();talk.add_cg(row.cg,row.text,row.duration);view.present(talk);view.set_process(false)
		var count:=int(ceil(float(row.duration)*12))
		var digests: Dictionary={}
		for frame: int in count:
			talk.cg_elapsed=float(frame)/12;view._refresh()
			await process_frame;await RenderingServer.frame_post_draw
			var shot:=root.get_texture().get_image()
			if frame in [0,count/4,count/2,count*3/4,count-1]:
				if shot.save_png(folder.path_join("key-%03d.png"%frame))!=OK: quit(1);return
			shot.resize(640,400,Image.INTERPOLATE_NEAREST)
			var bytes:=shot.save_jpg_to_buffer(.9)
			var f:=FileAccess.open(folder.path_join("frame-%04d.jpg"%frame),FileAccess.WRITE)
			f.store_buffer(bytes);f.close();digests[hash(bytes)]=true
		record.append({"id":row.cg,"frames":count,"unique_frames":digests.size(),"fps":12,"duration":row.duration})
		view.finish_now();print("FILM ",row.cg," frames=",count," unique=",digests.size())
	var f:=FileAccess.open("res://artifacts/cg-revision/visual.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"clips":record,"renderer":RenderingServer.get_current_rendering_method(),"human_playtest":"PENDING"},"\t"));f.close()
	view.queue_free();await process_frame;quit(0)
