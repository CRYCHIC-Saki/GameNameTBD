extends GutTest

const APP := preload("res://src/app/main.tscn")
var app: TDApplication

func before_each() -> void:
	app = APP.instantiate() as TDApplication
	app.settings_path = "res://artifacts/test-storage/cooking-app-%d.json" % Time.get_ticks_usec()
	add_child_autofree(app)
	app.enter_cooking()
	app.cooking_kitchen.automatic_time = false
	app.cooking_kitchen.audio_enabled = false

func after_each() -> void:
	get_tree().paused = false
	await get_tree().process_frame

func key(code: Key, down: bool, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	event.echo = echo
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func cook(shape: String = "chunk", sugar: int = 1, power: float = 0.5) -> Dictionary:
	var kitchen := app.cooking_kitchen
	kitchen.accept_order()
	assert_true(kitchen.perform("add", {"ingredient_id": "tomato"}).ok)
	assert_true(kitchen.perform("add", {"ingredient_id": "egg"}).ok)
	assert_true(kitchen.perform("cut", {"ingredient_id": "tomato", "shape": shape}).ok)
	kitchen.advance_time(1.0)
	for beat: int in 8:
		key(KEY_SPACE, true)
		key(KEY_SPACE, false)
		kitchen.advance_time(0.5 if beat < 7 else 0.15)
	if sugar > 0:
		assert_true(kitchen.perform("season", {"ingredient_id": "sugar", "amount": sugar}).ok)
	assert_true(kitchen.perform("heat").ok)
	kitchen.route_input(power)
	kitchen.advance_time(6.0)
	assert_true(kitchen.perform("plate").ok)
	return kitchen.session.snapshot().to_dict()

func test_real_order_cook_deliver_input_signals_and_two_customer_feedback() -> void:
	var kitchen := app.cooking_kitchen
	watch_signals(kitchen)
	var dish := cook()
	assert_eq(dish["state"], "plated")
	assert_signal_emit_count(kitchen, "dish_delivered", 1)
	assert_true(kitchen.last_feedback()["ok"])
	assert_false(kitchen.perform("heat").ok)
	assert_signal_emit_count(kitchen, "dish_delivered", 1)
	var a := app.scorer.evaluate(dish, kitchen.config["customers"][0])
	var b := app.scorer.evaluate(dish, kitchen.config["customers"][1])
	assert_true(a.ok)
	assert_true(b.ok)
	assert_ne(a.data["satisfaction"], b.data["satisfaction"])
	assert_true(kitchen._history.text.contains("→"))
	assert_true(kitchen._feedback_label.text.contains("满意度"))

func test_fixed_timeline_reproduces_attributes_across_fresh_sessions() -> void:
	var first := cook("dice", 2)
	app.enter_cooking()
	app.cooking_kitchen.automatic_time = false
	app.cooking_kitchen.audio_enabled = false
	var second := cook("dice", 2)
	assert_eq(first["dish_attributes"], second["dish_attributes"])
	assert_eq(first["ingredients"], second["ingredients"])
	assert_ne(first["session_id"], second["session_id"])

func test_feedback_guided_recipe_and_fire_changes_improve_same_customer() -> void:
	cook("dice", 3, 1.0)
	var poor := app.cooking_kitchen.last_feedback()["data"] as Dictionary
	assert_gt(poor["reasons"].size(), 0)
	app.enter_cooking()
	app.cooking_kitchen.automatic_time = false
	app.cooking_kitchen.audio_enabled = false
	cook("chunk", 1, 0.5)
	var improved := app.cooking_kitchen.last_feedback()["data"] as Dictionary
	assert_gt(improved["satisfaction"], poor["satisfaction"])
	assert_lt(improved["deviation"], poor["deviation"])
	assert_gt(improved["quality"], poor["quality"])

func test_pause_focus_echo_cancel_restart_and_old_results() -> void:
	var kitchen := app.cooking_kitchen
	kitchen.accept_order()
	kitchen.perform("add", {"ingredient_id": "tomato"})
	kitchen.perform("cut", {"ingredient_id": "tomato", "shape": "chunk"})
	var old_qte: RefCounted = kitchen._qte
	kitchen.advance_time(1.0)
	key(KEY_SPACE, true, true)
	assert_eq(kitchen._qte.update().data["hits"], 0)
	app.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	var now: float = kitchen.clock.qte_sec
	kitchen.advance_time(2.0)
	assert_eq(kitchen.clock.qte_sec, now)
	assert_true(kitchen.clock.paused)
	key(KEY_SPACE, true)
	assert_eq(kitchen._qte.update().data["hits"], 0)
	app.toggle_pause()
	key(KEY_SPACE, false)
	key(KEY_SPACE, true)
	key(KEY_SPACE, false)
	assert_eq(kitchen._qte.update().data["hits"], 1)
	assert_true(kitchen.cancel_operation().ok)
	assert_false(old_qte.finish().ok)
	assert_eq(kitchen.session.snapshot().to_dict()["ingredients"]["tomato"]["fine"], 0.0)
	for index: int in 3:
		var old := app.cooking_kitchen
		app.enter_cooking()
		app.cooking_kitchen.automatic_time = false
		app.cooking_kitchen.audio_enabled = false
		await get_tree().process_frame
		assert_false(is_instance_valid(old))
		assert_true(app.cooking_kitchen.session.snapshot().to_dict()["ingredients"].is_empty())
	assert_eq(app.get_child_count(), 2)
	app.return_to_menu()
	assert_null(app.cooking_kitchen)
	app.enter_cooking()
	assert_not_null(app.cooking_kitchen)

func test_empty_delivery_explains_missing_and_mouse_uses_input_path() -> void:
	var kitchen := app.cooking_kitchen
	kitchen.accept_order()
	assert_true(kitchen.perform("plate").ok)
	assert_true(kitchen.last_feedback()["data"]["reasons"].size() > 0)
	app.enter_cooking()
	kitchen = app.cooking_kitchen
	kitchen.automatic_time = false
	kitchen.audio_enabled = false
	kitchen.accept_order()
	kitchen.perform("add", {"ingredient_id": "tomato"})
	kitchen.perform("cut", {"ingredient_id": "tomato", "shape": "chunk"})
	kitchen.advance_time(1.0)
	kitchen._tap_button.button_down.emit()
	kitchen._tap_button.button_up.emit()
	assert_eq(kitchen._qte.update().data["perfect"], 1)

func test_audio_track_is_real_resource_with_scheduled_transients() -> void:
	var audio := TDBeatAudio.new()
	add_child_autofree(audio)
	audio.prepare({"beats": 8, "interval_sec": 0.5, "lead_in_sec": 1.0})
	var track := audio.stream as AudioStreamWAV
	assert_not_null(track)
	assert_eq(audio.scheduled_beats.size(), 8)
	assert_eq(track.data.decode_s16(int(0.5 * track.mix_rate) * 2), 0)
	var energy: int = 0
	for sample: int in 400:
		energy += absi(track.data.decode_s16((track.mix_rate + sample) * 2))
	assert_gt(energy, 0)
	assert_almost_eq(audio.scheduled_beats[7], 4.5, 0.000001)
	audio.begin()
	assert_true(audio.playing)
	audio.stream_paused = true
	assert_true(audio.stream_paused)
	audio.stop()
	assert_false(audio.playing)

func test_last_good_edge_survives_scene_auto_finish() -> void:
	var kitchen := app.cooking_kitchen
	kitchen.accept_order()
	kitchen.perform("add", {"ingredient_id": "tomato"})
	kitchen.perform("cut", {"ingredient_id": "tomato", "shape": "chunk"})
	kitchen.advance_time(4.64)
	var hit := kitchen.route_input(1.0)
	assert_true(hit.ok)
	assert_eq(hit.data.get("judgement"), "good")
	kitchen.advance_time(0.001)
	assert_null(kitchen._qte)

func test_long_frame_commits_heat_then_cools_remainder_and_pause_resets_power_display() -> void:
	var temperatures: Array[float] = []
	for long_frame: bool in [true, false]:
		app.enter_cooking()
		var kitchen := app.cooking_kitchen
		kitchen.automatic_time = false
		kitchen.audio_enabled = false
		kitchen.accept_order()
		kitchen.perform("add", {"ingredient_id": "tomato"})
		kitchen.perform("heat")
		if long_frame:
			kitchen.advance_time(10.0)
		else:
			kitchen.advance_time(6.0)
			kitchen.advance_time(4.0)
		temperatures.append(kitchen.session.snapshot().to_dict()["dish_attributes"]["temperature_c"])
	assert_almost_eq(temperatures[0], temperatures[1], 0.000001)
	var kitchen := app.cooking_kitchen
	kitchen.perform("heat")
	kitchen.route_input(1.0)
	app.toggle_pause()
	app.toggle_pause()
	assert_almost_eq(kitchen._power.value, kitchen._qte.update().data["power"], 0.000001)
