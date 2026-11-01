extends SceneTree
## Isolated real GPU snapshots and continuous frames; no user save access.
const OUT := "res://artifacts/arrival-coast"
var view: TDDialogueView

func _initialize() -> void:
	call_deferred("run")

func capture(name: String) -> void:
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT.path_join(name+".png"))

func run() -> void:
	root.size=Vector2i(1280,800)
	view=TDDialogueView.new();root.add_child(view)
	await process_frame
	var clips: Array=[]
	for id: String in ["arrival","hungry","messenger"]:
		var span: float=TDArrivalCutscene.SPANS[id]
		var folder:=OUT.path_join("frames").path_join(id)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
		var talk:=TDDialogue.new();talk.add_cg(id,"",span);view.present(talk);view.set_process(false)
		var unique: Dictionary={}
		for frame: int in int(span*12):
			talk.cg_elapsed=frame/12.0;view._refresh()
			await process_frame;await RenderingServer.frame_post_draw
			var screenshot:=root.get_texture().get_image()
			if frame%12==0: screenshot.save_png(folder.path_join("key-%03d.png"%frame))
			screenshot.resize(640,400,Image.INTERPOLATE_NEAREST)
			var bytes:=screenshot.save_jpg_to_buffer(.9)
			var file:=FileAccess.open(folder.path_join("frame-%04d.jpg"%frame),FileAccess.WRITE);file.store_buffer(bytes);file.close()
			unique[hash(bytes)]=true
		clips.append({"id":id,"duration":span,"frames":int(span*12),"unique_frames":unique.size(),"fps":12})
		print("CAPTURE ",id," frames=",int(span*12)," unique=",unique.size())
	view.queue_free();await process_frame
	var app:=load("res://src/app/main.tscn").instantiate() as TDApplication
	app.settings_path=OUT.path_join("gpu-slots/%d/settings.json"%Time.get_ticks_usec())
	root.add_child(app);var shell:=app.game_shell;shell.automatic_time=false
	if not shell.create_game("slot-01").ok: quit(2);return
	shell.guide.dialogue.set_process(false);shell.guide.dialogue.talk.cg_elapsed=.2;shell.guide.dialogue._refresh()
	await capture("new-slot-first-frame")
	shell.guide.dialogue.finish_now();shell.profile.story.beat="arrive";shell.town.sync_characters(0);shell.town.spawn_at_harbor()
	await capture("harbor-map")
	shell.profile.story.beat="soup";shell.town.sync_characters(0)
	shell.town._player.position=shell.town._origin()+(Vector2(shell.town._chen_cell())+Vector2(.5,1.25))*shell.town.CELL
	await capture("chen-aling-separated")
	shell.town._interact();await capture("chen-interaction")
	shell.go_title();app.queue_free();await process_frame;await process_frame
	var f:=FileAccess.open(OUT.path_join("visual.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify({"clips":clips,"renderer":RenderingServer.get_current_rendering_method(),"human_playtest":"PENDING"},"\t"));f.close()
	quit(0)
