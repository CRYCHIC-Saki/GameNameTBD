extends GutTest

var host: Control
var sound: TDSoundEffects
var heard: Array[String] = []

func before_each() -> void:
	host = Control.new(); add_child_autofree(host)
	sound = TDSoundEffects.new(); sound.name = "SoundEffects"; host.add_child(sound)
	heard.clear()
	sound.played.connect(func(id: String, _path: String) -> void: heard.append(id))

func after_each() -> void:
	Input.action_release("world_right")
	get_tree().paused = false
	sound.stop_all()

func test_all_selected_streams_load_with_positive_duration_and_original_licenses() -> void:
	for id: String in TDSoundEffects.EVENTS:
		var stream := TDSoundEffects.stream_for(id)
		assert_not_null(stream,id)
		assert_gt(stream.get_length(),0.0,id)
		assert_true(stream.resource_path.begins_with("res://assets/audio/sfx/"))
	assert_true(FileAccess.file_exists("res://assets/audio/sfx/licenses/kenney_rpg-audio/License.txt"))
	assert_true(FileAccess.file_exists("res://assets/audio/sfx/licenses/cozy-cafe-sfx/cozy-cafe-sfx/LICENSE.txt"))

func test_pause_blocks_world_but_settings_buttons_still_sound() -> void:
	assert_true(sound.play_event("world.step0"))
	sound.set_world_paused(true)
	assert_true(sound._world[0].stream_paused)
	assert_false(sound.play_event("restaurant.serve"))
	get_tree().paused = true
	assert_true(sound.play_event("ui.click"))
	assert_eq(heard,["world.step0","ui.click"])
	get_tree().paused = false
	sound.set_world_paused(false)
	assert_true(sound.play_event("restaurant.serve"))

func test_cooldown_bounded_polyphony_and_scene_shutdown() -> void:
	assert_true(sound.play_event("ui.click"))
	assert_false(sound.play_event("ui.click"))
	assert_false(sound.play_event("not-an-event"))
	for i: int in 35:
		sound._last.clear(); assert_true(sound.play_event("ui.click"))
	assert_eq(sound.get_child_count(),12)
	sound.stop_all()
	for voice: AudioStreamPlayer in sound._ui + sound._world:
		assert_false(voice.playing); assert_null(voice.stream)
	assert_true(sound._last.is_empty())

func test_sound_owner_is_scoped_to_the_ancestor_shell() -> void:
	var button := TDUI.button("test",func() -> void: pass); host.add_child(button)
	assert_eq(TDSoundEffects.owner_of(button),sound)
	var outside := Node.new(); add_child_autofree(outside)
	assert_null(TDSoundEffects.owner_of(outside))
	assert_false(TDSoundEffects.request(outside,"ui.click"))
	var other := Control.new(); add_child_autofree(other)
	var second := TDSoundEffects.new();second.name="SoundEffects";other.add_child(second)
	assert_eq(TDSoundEffects.owner_of(other),second)
	assert_ne(TDSoundEffects.owner_of(other),sound)

func test_real_ui_factory_connects_click_once_before_callback() -> void:
	var called: Array[int] = []
	var button := TDUI.button("test",func() -> void: called.append(heard.size()))
	host.add_child(button)
	button.pressed.emit()
	assert_eq(heard,["ui.click"])
	assert_eq(called,[1])
	button.disabled=true
	button.mouse_entered.emit()
	assert_eq(heard.size(),1)

func test_qte_uses_imported_short_material_sound_and_never_restarts_music() -> void:
	var audio := TDBeatAudio.new();host.add_child(audio)
	audio.play_feedback("perfect","M1")
	assert_true(audio.stream.resource_path.ends_with("chop.ogg"))
	assert_lt(audio.stream.get_length(),60.0/140.0)
	audio.play_feedback("good","M3")
	assert_true(audio.stream.resource_path.ends_with("impactMetal_light_000.ogg"))
	audio.play_feedback("miss","M1")
	assert_true(audio.stream.resource_path.ends_with("error_006.ogg"))
	audio.play_feedback("good","M6","HOLD_STARTED")
	assert_true(audio.stream.resource_path.ends_with("glass_001.ogg"))
	assert_eq(audio.pitch_scale,1.0)
	audio.stop()

func test_trial_pass_take_and_serve_emit_once_without_payment() -> void:
	var catalog := TDServiceCatalog.new();assert_true(catalog.load_file().ok)
	var shop := TDShopSession.new(catalog,"sound-trial",59)
	var events: Array[String] = []
	shop.sound_requested.connect(func(id: String) -> void: events.append(id))
	shop.table_service.trial_check=func(_dish: Dictionary) -> TDOutcome: return TDOutcome.new(true,"OK")
	shop.table_service.trial_received=func(_dish: Dictionary) -> TDOutcome: return TDOutcome.new(true,"OK")
	var money: int = int(shop.snapshot().money_cents)
	var plate: Dictionary = {"dish_id":"sound-plate", "state":"plated"}
	assert_true(shop.table_service.place_trial(plate).ok)
	assert_false(shop.table_service.place_trial(plate).ok)
	assert_true(shop.table_service.take("sound-plate","player").ok)
	assert_false(shop.table_service.take("sound-plate","other").ok)
	assert_false(shop.table_service.serve("sound-plate","player","wrong").ok)
	assert_true(shop.table_service.serve("sound-plate","player",TDTableService.TRIAL_ORDER).ok)
	assert_false(shop.table_service.serve("sound-plate","player",TDTableService.TRIAL_ORDER).ok)
	assert_eq(events,["restaurant.pass_ready","restaurant.plate_take","restaurant.serve"])
	assert_eq(int(shop.snapshot().money_cents),money)

func test_failed_open_and_load_are_silent_and_replayed_purchase_is_not_payment() -> void:
	var catalog := TDServiceCatalog.new();assert_true(catalog.load_file().ok)
	var shop := TDShopSession.new(catalog,"sound-open",22)
	var events: Array[String] = []
	shop.sound_requested.connect(func(id: String) -> void: events.append(id))
	var saved := shop.snapshot()
	assert_true(shop.restore(saved).ok)
	assert_true(events.is_empty())
	assert_true(shop.buy(shop.offer("service.tomato_egg").stock,"stock").ok)
	assert_false(events.has("restaurant.payment"))
	assert_true(shop.open_day().ok)
	shop.open_day()
	assert_eq(events.count("restaurant.open"),1)
	assert_false(events.has("restaurant.payment"))

func test_player_footsteps_require_actual_motion_and_enabled_controls() -> void:
	var player := TDKitchenPlayer.new();player.directional_art=false
	var sprite := Sprite2D.new();sprite.name="Sprite2D";player.add_child(sprite)
	player.confine_to=func(_at: Vector2) -> bool: return true
	host.add_child(player);player.set_physics_process(false)
	player._physics_process(.5)
	assert_true(heard.is_empty())
	Input.action_press("world_right")
	player._physics_process(.5)
	assert_eq(heard,["world.step0"])
	player.confine_to=func(_at: Vector2) -> bool: return false
	player._physics_process(.5)
	assert_eq(heard.size(),1,"Blocked movement is silent")
	player.set_controls_enabled(false)
	player._physics_process(.5)
	assert_eq(heard.size(),1)

func test_native_vn_uses_speaker_mood_once_and_skip_is_silent() -> void:
	var talk := TDDialogue.new();talk.presentation="story";talk.hero_name="音效测试"
	talk.add_line("焰子","hero","第一句疑惑。","puzzled")
	talk.add_line("焰子","hero","第二句仍疑惑。","puzzled")
	talk.add_line("焰子","hero","快进时的生气。","angry")
	var view := TDDialogueView.new();host.add_child(view);view.present(talk)
	await wait_process_frames(3)
	assert_true(view._native)
	assert_eq(heard.count("emotion.puzzled"),1)
	view._vn_stage.dialog._reveal_to_end();view._vn_stage.dialog._advance_dialog()
	await wait_process_frames(2)
	assert_eq(heard.count("emotion.puzzled"),1,"No repeated mood pulse per line")
	var before: int=heard.size()
	view._vn_stage.runner.toggle_skip_to_choice()
	await get_tree().create_timer(.25).timeout
	assert_eq(heard.size(),before,"Skip emits no dialogue or emotion pulses")
	view.finish_now()
	await wait_process_frames(2)

func test_hidden_cooking_stops_inflight_feedback() -> void:
	var app: TDApplication=load("res://src/app/main.tscn").instantiate()
	app.settings_path="res://artifacts/audio-integration-20261126/hidden-kitchen-settings.json"
	host.add_child(app);app.enter_full_kitchen()
	var kitchen: TDFullKitchen=app.full_kitchen
	kitchen.auto_advance=false
	var lane: TDCookingLane=kitchen.prep
	lane._audio.play_feedback("perfect","M1")
	assert_true(lane._audio.playing)
	kitchen.hide();kitchen._process(0)
	assert_false(lane._audio.playing,"Hiding the real kitchen stops an in-flight strike")
	app.return_to_menu()
	await wait_process_frames(2)
