class_name TDBeatAudio
extends AudioStreamPlayer

## Procedural placeholder click track. One stream avoids frame-scheduled beat drift.
var scheduled_beats: Array[float] = []
var estimated_delay_sec: float = 0.0

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
