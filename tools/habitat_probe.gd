extends SceneTree
## Real renderer/mixer evidence, isolated profiles. Listening and physical input latency remain human checks.
var shell:TDGameShell
var captures:int=0
var failures:Array[String]=[]
var audio_rows:Array[Dictionary]=[]
func _initialize() -> void: call_deferred("run")

func capture(label:String) -> void:
	if paused: shell._close_dialog()
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png("res://artifacts/habitat-"+label+".png")!=OK: failures.append(label)
	captures+=1

func run() -> void:
	root.size=Vector2i(1280,800)
	var app:TDApplication=load("res://src/app/main.tscn").instantiate()
	app.settings_path="res://artifacts/habitat-probe/%d/settings.json"%Time.get_ticks_usec();root.add_child(app)
	shell=app.game_shell;shell.automatic_time=false
	var started:=shell.create_game("slot-01","青瓦小馆")
	if not started.ok: push_error(started.code);quit(1);return
	shell.town.spawn_at_plot("player_cottage");await capture("cottage-outside")
	shell.travel("cottage",true);await capture("bed")
	for face:Vector2i in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:
		shell.cottage.player.position=Vector2(620,450);shell.cottage.player.face(Vector2(face))
		await capture("face-%d-%d"%[face.x,face.y])
	shell.travel("restaurant");await capture("restaurant")
	# Fail only the morning write: the settled-day package must remain recoverable.
	shell.profile.shop.open_day();shell.profile.shop.close_early();shell.travel("cottage",true)
	var store:=shell.slots
	shell.profile.persistence=func(id:String,data:Dictionary)->TDOutcome:
		if int(data.shop.day)==2: return TDOutcome.new(false,"INJECTED_MORNING_WRITE_FAILURE")
		return store.save_slot(id,data)
	shell.show_rest()
	var rest:Button
	for b:Button in shell._modal_box.find_children("*","Button",true,false):
		if b.text=="休息到明天": rest=b
	if rest==null: failures.append("missing-bed-action")
	else:
		var callback:Callable=rest.pressed.get_connections()[0].callable
		callback.call();callback.call()
		if int(shell.profile.shop.snapshot().day)!=2 or shell._rest_busy: failures.append("morning-failure-reentry")
		var disk:=store.load_slot("slot-01")
		if not disk.ok or int(disk.data.shop.day)!=1 or disk.data.shop.phase!="SETTLED": failures.append("lost-evening-recovery")
		shell.profile.persistence=store.save_slot
		if not shell.save_game().ok: failures.append("morning-retry")
		shell.go_title()
		if not shell.load_game("slot-01").ok or shell.location!="cottage" or int(shell.profile.shop.snapshot().day)!=2: failures.append("morning-retry-reload")
		var original:=shell.cottage.player.position
		shell.open_atlas();Input.action_press("world_down")
		await process_frame;await process_frame;Input.action_release("world_down")
		if shell.cottage.player.position!=original: failures.append("atlas-moved-underlying-player")
		shell.close_atlas()
		if shell.cottage.player.position!=original or not shell.cottage.player.controls_enabled: failures.append("atlas-return-location")
	shell.go_title();await process_frame;await process_frame
	# Listen to the actual engine bus rather than just checking file bytes.
	var index:=AudioServer.bus_count;AudioServer.add_bus(index);AudioServer.set_bus_name(index,"HabitatEvidence")
	var effect:=AudioEffectCapture.new();effect.buffer_length=2.0;AudioServer.add_bus_effect(index,effect)
	var player:=TDBeatAudio.new();player.bus="HabitatEvidence";root.add_child(player)
	for id:String in ["casual","service","cooking"]:
		player.stream=TDGameMusic.loop_track(id);player.volume_db=-12;player.play();effect.clear_buffer()
		var energy:float=0;var count:int=0;var peak:float=0
		var start:=Time.get_ticks_msec()
		while Time.get_ticks_msec()-start<1000:
			await process_frame
			for sample:Vector2 in effect.get_buffer(effect.get_frames_available()):
				energy+=sample.length_squared();peak=maxf(peak,sample.length());count+=1
		var passed:bool=count>10000 and energy>0.1 and peak<1.0
		audio_rows.append({"id":id,"frames":count,"energy":energy,"peak":peak,"pass":passed})
		if not passed: failures.append("mixed-audio:"+id)
	player.stop();player.stream=null;player.queue_free();await process_frame;AudioServer.remove_bus(index)
	app.queue_free();await process_frame;await process_frame
	var report:Dictionary={"success":failures.is_empty(),"captures":captures,"audio":audio_rows,"driver":AudioServer.get_driver_name(),"failures":failures,"human_listening":"PENDING","physical_audio_input_sync":"NOT_RUN"}
	var file:=FileAccess.open("res://artifacts/habitat-probe.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)
