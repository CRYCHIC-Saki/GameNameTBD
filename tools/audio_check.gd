extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var index: int = AudioServer.bus_count
	AudioServer.add_bus(index)
	AudioServer.set_bus_name(index, "Phase1AudioEvidence")
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 4.0
	AudioServer.add_bus_effect(index, capture)
	var player := TDBeatAudio.new()
	player.bus = "Phase1AudioEvidence"
	root.add_child(player)
	player.prepare({"beats": 2, "interval_sec": 0.5, "lead_in_sec": 0.3})
	var delay: float = player.begin()
	var origin: int = Time.get_ticks_usec()
	var samples: Array[Vector2] = []
	var positions: Array[Dictionary] = []
	while Time.get_ticks_usec() - origin < 1500000:
		await process_frame
		var count: int = capture.get_frames_available()
		if count > 0:
			var block := capture.get_buffer(count)
			for sample: Vector2 in block:
				samples.append(sample)
		if positions.size() < 12 and Time.get_ticks_usec() - origin > positions.size() * 100000:
			positions.append({"wall_sec": float(Time.get_ticks_usec() - origin) / 1000000.0, "audible_sec": player.audible_position_sec()})
	var peaks: Array[float] = []
	var last_peak: int = -1000000
	var rate: float = AudioServer.get_mix_rate()
	for sample: int in samples.size():
		if samples[sample].length() > 0.01 and sample - last_peak > int(rate * 0.15):
			peaks.append(float(sample) / rate)
			last_peak = sample
	var passed: bool = peaks.size() == 2 and absf((peaks[1] - peaks[0]) - 0.5) < 0.03
	var evidence := {"status": "PASS" if passed else "FAIL", "driver": AudioServer.get_driver_name(), "device": AudioServer.output_device, "mix_rate": rate, "captured_frames": samples.size(), "detected_transients_sec": peaks, "estimated_start_delay_sec": delay, "positions": positions, "physical_speaker_keyboard_sync": "NOT_RUN", "scope": "Engine mixer capture; not a physical loopback or human timing test"}
	var file := FileAccess.open("res://artifacts/phase1-audio.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(evidence, "\t"))
	file.close()
	print(JSON.stringify(evidence))
	player.stop()
	player.stream = null
	player.queue_free()
	AudioServer.remove_bus(index)
	capture = null
	await create_timer(0.15).timeout
	quit(0 if passed else 1)
