class_name TDBeatAudio
extends AudioStreamPlayer

## Continuous sample clock for QTE; legacy clicks remain only in calibration tests.
var scheduled_beats: Array[float] = []
var estimated_delay_sec: float = 0.0
# Cooking uses the supplied casual track at original pitch.
# Both lanes follow the shared 140 BPM chart; the full song loops.
const RECORDING_BPM := 140.0
const LOOP_BARS := 48
const LOOP_SEC := 166.2946485260771
const PHASE_TOLERANCE_SEC := .065
var _checked_at_usec := -1000000
static var _feedback_tracks: Dictionary = {}

func play_feedback(grade: String, module: String = "", reason: String = "") -> void:
	var event_id: String = "cooking.qte_good"
	if grade == "miss": event_id = "cooking.qte_miss"
	elif reason == "HOLD_STARTED": event_id = "cooking.m6_start" if module == "M6" else "cooking.m1_rotate"
	elif module == "M1": event_id = "cooking.m1_cut_hit"
	elif module == "M2": event_id = "cooking.m2_ignite"
	elif module == "M3": event_id = "cooking.m3_stir_hit"
	elif module == "M6": event_id = "cooking.m6_start"
	elif module == "M7": event_id = "cooking.m7_plate"
	elif grade == "perfect": event_id = "cooking.qte_perfect"
	stop()
	stream = TDSoundEffects.stream_for(event_id)
	volume_db = -15.0 if grade == "perfect" else -18.0
	pitch_scale = 1.0
	play()

func prepare(config: Dictionary) -> void:
	stop()
	scheduled_beats.clear()
	var sample_rate: int = 22050
	var count: int = int(config.get("beats", 8))
	var interval: float = float(config.get("interval_sec", 0.5))
	var lead: float = float(config.get("lead_in_sec", 1.0))
	var duration: float = lead + count * interval + 0.5
	var pcm := PackedByteArray()
	pcm.resize(int(duration * sample_rate) * 2)
	for beat: int in count:
		var at: float = lead + beat * interval
		scheduled_beats.append(at)
		var frequency: float = 1100.0 if beat % 4 == 0 else 760.0
		for sample: int in int(0.035 * sample_rate):
			var time: float = float(sample) / sample_rate
			var amplitude: float = sin(TAU * frequency * time) * exp(-time * 100.0) * 0.22
			var index: int = (int(at * sample_rate) + sample) * 2
			pcm.encode_s16(index, int(amplitude * 32767.0))
	var track := AudioStreamWAV.new()
	track.format = AudioStreamWAV.FORMAT_16_BITS
	track.mix_rate = sample_rate
	track.stereo = false
	track.data = pcm
	stream = track
	volume_db = -6.0

func begin() -> float:
	estimated_delay_sec = maxf(0.0, AudioServer.get_time_to_next_mix() + AudioServer.get_output_latency())
	play()
	return estimated_delay_sec

func audible_position_sec() -> float:
	return maxf(0.0, get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency())

func prepare_loop(bpm: float) -> void:
	prepare({"beats":16,"interval_sec":60.0 / bpm,"lead_in_sec":0.0})
	var track := stream as AudioStreamWAV
	track.loop_mode = AudioStreamWAV.LOOP_FORWARD
	track.loop_begin = 0
	track.loop_end = int(16 * 60.0 / bpm * track.mix_rate)

func prepare_cooking_music(bpm:float) -> void:
	stop();scheduled_beats.clear()
	var track:=TDGameMusic.loop_track("casual")
	track.loop_end = roundi(LOOP_SEC*track.mix_rate)
	pitch_scale = 1.0 # Preserve the original track pitch and tempo.
	stream = track
	_checked_at_usec = -1000000

static func phase_error(song_sec: float, chart_position: float) -> float:
	return wrapf(song_sec-chart_position,-LOOP_SEC*.5,LOOP_SEC*.5)

func follow_chart(chart_sec: float) -> void:
	# Repairs device restarts and hidden/paused external clocks without changing
	# the simulation or regularly restarting music. Compare in recording seconds.
	var now := Time.get_ticks_usec()
	if not playing or stream_paused or chart_sec<0 or now-_checked_at_usec < 750000: return
	_checked_at_usec = now
	var target := fposmod(chart_sec*pitch_scale,LOOP_SEC)
	var heard := get_playback_position()+(AudioServer.get_time_since_last_mix()-AudioServer.get_output_latency())*pitch_scale
	if absf(phase_error(heard,target)) <= PHASE_TOLERANCE_SEC*pitch_scale: return
	var ahead := (AudioServer.get_time_to_next_mix()+AudioServer.get_output_latency())*pitch_scale
	seek(fposmod(target+ahead,LOOP_SEC))
