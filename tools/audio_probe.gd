extends Node
## Runs in a disposable pack using the actual shipped game resources.
var checks: int = 0
var failed: bool = false
var heard: Array[String] = []
var capture: AudioEffectCapture
var app: TDApplication
var folder: String

func check(value: bool, note: String) -> void:
	checks += 1
	print("AUDIO_CHECK ",checks," ","PASS " if value else "FAIL ",note)
	if not value: failed = true

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	run.call_deferred()

func run() -> void:
	folder=OS.get_executable_path().get_base_dir().path_join("audio-probe-data")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--probe-root="): folder=arg.trim_prefix("--probe-root=")
	DirAccess.make_dir_recursive_absolute(folder)
	app=load("res://src/app/main.tscn").instantiate()
	app.settings_path=folder.path_join("settings.json")
	get_tree().root.add_child(app)
	var shell: TDGameShell=app.game_shell
	shell.automatic_time=false
	shell.set_process(false)
	shell.music.select_context("silent",false)
	shell.sfx.played.connect(func(id: String,_path: String)->void:heard.append(id))
	for id: String in TDSoundEffects.EVENTS:
		var stream:=TDSoundEffects.stream_for(id)
		check(stream!=null and stream.get_length()>0,"exported stream: "+id)
	check(FileAccess.file_exists("res://assets/audio/sfx/licenses/cozy-cafe-sfx/cozy-cafe-sfx/LICENSE.txt"),"Cozy original license shipped")
	check(FileAccess.file_exists("res://assets/audio/sfx/licenses/kenney_rpg-audio/License.txt"),"Kenney original license shipped")
	# Capture only this isolated game's mixed output, never microphone or system audio.
	capture=AudioEffectCapture.new();capture.buffer_length=2.0
	AudioServer.add_bus_effect(0,capture)
	var button:=TDUI.button("音效测试",func()->void:pass);shell.add_child(button)
	button.pressed.emit()
	check(heard.has("ui.click"),"real UI callback requests audio")
	await get_tree().create_timer(.25).timeout
	var frames: int=capture.get_frames_available()
	var pcm:=capture.get_buffer(frames)
	var peak: float=0
	for sample: Vector2 in pcm: peak=maxf(peak,maxf(absf(sample.x),absf(sample.y)))
	check(frames>0,"audio mixer produced sample frames")
	check(peak>0.00001,"imported click reached the output mix")
	if frames>0:
		var data:=PackedByteArray();data.resize(pcm.size()*4)
		for i: int in pcm.size():
			data.encode_s16(i*4,roundi(clampf(pcm[i].x,-1,1)*32767))
			data.encode_s16(i*4+2,roundi(clampf(pcm[i].y,-1,1)*32767))
		var wav:=AudioStreamWAV.new();wav.format=AudioStreamWAV.FORMAT_16_BITS;wav.stereo=true;wav.mix_rate=AudioServer.get_mix_rate();wav.data=data
		wav.save_to_wav(folder.path_join("engine-click-capture.wav"))
	AudioServer.remove_bus_effect(0,AudioServer.get_bus_effect_count(0)-1)
	shell.sfx.set_world_paused(true)
	check(not shell.sfx.play_event("restaurant.serve"),"world sounds blocked while paused")
	check(shell.sfx.play_event("ui.confirm"),"pause controls remain audible")
	shell.sfx.stop_all()
	var stopped: bool=true
	for voice: AudioStreamPlayer in shell.sfx._ui+shell.sfx._world: stopped=stopped and not voice.playing and voice.stream==null
	check(stopped,"all voices stop on lifecycle cleanup")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(folder.path_join("game-title.png"))
	shell.music.shutdown();shell.sfx.stop_all();app.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	var result: Dictionary={"success":not failed,"checks":checks,"mixer_frames":frames,"captured_peak":peak,"headless":DisplayServer.get_name()=="headless","human_listening":"PENDING"}
	var file:=FileAccess.open(folder.path_join("summary.json"),FileAccess.WRITE);file.store_string(JSON.stringify(result,"\t"));file.close()
	print("AUDIO_PROBE success=",not failed," checks=",checks," peak=",peak)
	get_tree().quit(1 if failed else 0)
