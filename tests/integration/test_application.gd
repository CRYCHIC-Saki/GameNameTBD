extends GutTest
const APP := preload("res://src/app/main.tscn")
var app: TDApplication

func before_each() -> void:
	app = APP.instantiate() as TDApplication
	app.settings_path = "res://artifacts/test-storage/app-%d.json" % Time.get_ticks_usec()
	add_child_autofree(app)
	await get_tree().process_frame

func after_each() -> void:
	get_tree().paused = false

func press_key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func test_real_scene_signal_input_pipeline_and_restart() -> void:
	app.enter_kitchen()
	var first := app.kitchen
	first.automatic_time = false
	assert_true(first.start_operation().ok)
	watch_signals(first)
	press_key(KEY_SPACE, true)
	first.advance_time(0.5)
	assert_almost_eq(first.session.snapshot().to_dict()["work_units"], 5.0, 0.0001)
	first.advance_time(2.0)
	press_key(KEY_SPACE, false)
	assert_signal_emit_count(first, "result_displayed", 1)
	assert_eq(first.last_result()["code"], "COMPLETED")
	assert_eq(first.last_result()["scoring"]["code"], "NOT_IMPLEMENTED")
	first.advance_time(1.0)
	assert_eq(first.result_count(), 1)
	var old_session := first.session
	app.return_to_menu()
	await get_tree().process_frame
	assert_false(is_instance_valid(first))
	app.enter_kitchen()
	assert_ne(app.kitchen.session_id, old_session.snapshot().to_dict()["session_id"])
	assert_eq(app.kitchen.session.snapshot().to_dict()["work_units"], 0.0)

func test_pause_freezes_input_and_requires_new_press() -> void:
	app.enter_kitchen()
	var kitchen := app.kitchen
	kitchen.automatic_time = false
	kitchen.start_operation()
	press_key(KEY_SPACE, true)
	kitchen.advance_time(0.2)
	press_key(KEY_ESCAPE, true)
	press_key(KEY_ESCAPE, false)
	assert_true(get_tree().paused)
	kitchen.advance_time(2.0)
	press_key(KEY_SPACE, false)
	press_key(KEY_SPACE, true)
	assert_almost_eq(kitchen.session.snapshot().to_dict()["work_units"], 2.0, 0.0001)
	press_key(KEY_ESCAPE, true)
	press_key(KEY_ESCAPE, false)
	assert_false(get_tree().paused)
	kitchen.advance_time(0.2)
	assert_almost_eq(kitchen.session.snapshot().to_dict()["work_units"], 2.0, 0.0001)
	press_key(KEY_SPACE, false)
	press_key(KEY_SPACE, true)
	kitchen.advance_time(0.2)
	assert_almost_eq(kitchen.session.snapshot().to_dict()["work_units"], 4.0, 0.0001)
	press_key(KEY_SPACE, false)

func test_repeat_entry_and_cancelled_old_callbacks_do_not_leak() -> void:
	for index in 5:
		app.enter_kitchen()
		var old := app.kitchen
		old.automatic_time = false
		old.start_operation()
		var session := old.session
		var sid := old.session_id
		var gen := old.generation
		app.enter_kitchen()
		assert_eq(session.accept(TDFrame.new(sid, gen, "hold-1", 1, 1.5, 1.5, "completed")).code, "CANCELLED")
		assert_eq(app.kitchen.result_count(), 0)
		await get_tree().process_frame
		assert_false(is_instance_valid(old))
	assert_eq(app.get_child_count(), 2, "One menu and one active kitchen only")

func test_mouse_button_signal_uses_same_input_path() -> void:
	app.enter_kitchen()
	var kitchen := app.kitchen
	kitchen.automatic_time = false
	kitchen.start_operation()
	kitchen._hold_button.button_down.emit()
	kitchen.advance_time(0.3)
	kitchen._hold_button.button_up.emit()
	kitchen.advance_time(0.2)
	assert_almost_eq(kitchen.session.snapshot().to_dict()["work_units"], 3.0, 0.0001)

func test_independent_module_scene_instantiates_real_application() -> void:
	var packed := load("res://dev/module_test.tscn") as PackedScene
	var isolated := packed.instantiate() as TDApplication
	isolated.settings_path = "res://artifacts/test-storage/module-%d.json" % Time.get_ticks_usec()
	add_child_autofree(isolated)
	assert_not_null(isolated.kitchen)
	assert_eq(isolated.kitchen.session.snapshot().to_dict()["state"], "ready")

func test_focus_loss_releases_control_and_keyboard_echo_does_not_start_it() -> void:
	app.enter_kitchen()
	var kitchen := app.kitchen
	kitchen.automatic_time = false
	kitchen.start_operation()
	var echo_event := InputEventKey.new()
	echo_event.keycode = KEY_SPACE
	echo_event.physical_keycode = KEY_SPACE
	echo_event.pressed = true
	echo_event.echo = true
	Input.parse_input_event(echo_event)
	Input.flush_buffered_events()
	kitchen.advance_time(0.2)
	assert_eq(kitchen.session.snapshot().to_dict()["work_units"], 0.0)
	press_key(KEY_SPACE, true)
	kitchen.advance_time(0.2)
	app.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert_true(get_tree().paused)
	kitchen.advance_time(1.0)
	app.toggle_pause()
	kitchen.advance_time(0.2)
	assert_almost_eq(kitchen.session.snapshot().to_dict()["work_units"], 2.0, 0.0001)
	press_key(KEY_SPACE, false)
