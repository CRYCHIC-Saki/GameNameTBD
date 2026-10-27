class_name TDGameMusic
extends Node
## Application-owned music; cooking owns its uninterrupted, chart-aligned stream.
const TRACKS:Dictionary={
	"casual":preload("res://assets/audio/casual.wav"),
	"service":preload("res://assets/audio/service.wav"),
	"cooking":preload("res://assets/audio/cooking.wav")}
var context:String=""
var player:AudioStreamPlayer

static func loop_track(id:String) -> AudioStreamWAV:
	var track:AudioStreamWAV=TRACKS[id].duplicate()
	track.loop_mode=AudioStreamWAV.LOOP_FORWARD;track.loop_begin=0
	track.loop_end=roundi(track.get_length()*track.mix_rate)
	return track

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	player=AudioStreamPlayer.new();player.volume_db=-16;add_child(player)
	select_context("casual",false)

func select_context(value:String,paused:bool) -> void:
	if value!=context:
		context=value
		if value=="silent": player.stop()
		else:
			player.stream=loop_track(value);player.play()
	player.stream_paused=paused

func shutdown() -> void:
	if is_instance_valid(player):
		player.stop();player.stream=null

func _exit_tree() -> void:
	shutdown()
