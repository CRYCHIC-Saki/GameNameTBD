extends SceneTree
const OUT := "res://artifacts/vn-runtime-20261113/gpu"
var checks: int = 0
var failures: int = 0
var view: TDDialogueView

func _initialize() -> void:
	call_deferred("run")

func verify(value: bool, description: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("FAIL ", description)
	else: print("PASS ", description)

func capture(label: String) -> void:
	await process_frame; await RenderingServer.frame_post_draw
	verify(root.get_texture().get_image().save_png(OUT.path_join(label+".png")) == OK, "screenshot "+label)

func click_at(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new(); motion.position = point
	Input.parse_input_event(motion)
	await process_frame
	for pressed: bool in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT; click.pressed = pressed; click.position = point
		Input.parse_input_event(click)
		await process_frame

func next_line() -> void:
	view._vn_stage.dialog._reveal_to_end()
	await click_at(Vector2(760, 658))
	await process_frame

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.size = Vector2i(1280,800)
	var app := load("res://src/app/main.tscn").instantiate() as TDApplication
	app.settings_path = OUT.path_join("slots-%d/settings.json" % Time.get_ticks_usec())
	root.add_child(app)
	var shell := app.game_shell; shell.automatic_time = false
	verify(shell.create_game("slot-01").ok, "new isolated profile")
	view = shell.guide.dialogue; view.set_process(false)
	await process_frame; await process_frame
	verify(view._vn_stage.main is VNEngineMain and view._vn_stage.runner is VNEngineStoryRunner, "actual plugin Main and Runner")
	view.talk.cg_elapsed = 3.0; view._refresh()
	verify(not shell.town.visible and view._cg.visible, "film before map")
	await capture("01-arrival-film")
	view._process(11.0)
	await create_timer(.6).timeout
	verify(view._vn_stage.container.visible and not view._cg.visible, "independent background")
	verify(view._vn_stage.runner.ctx.characters.active_sprites.has("hero") and not view._vn_stage.runner.ctx.characters.active_sprites.has("aling"), "hero only")
	view._vn_stage.dialog._reveal_to_end()
	await capture("02-harbor-dialogue")
	await next_line()
	verify(view.talk.cg_id == "hungry", "real mouse advances plugin dialogue to second film")
	view._process(6.0)
	await process_frame
	await next_line()
	verify(view._vn_stage.runner.current_text == "背锅的旅人，止步！" and not view._vn_stage.runner.ctx.characters.active_sprites.has("aling"), "offscreen arrival protected")
	view._vn_stage.dialog._reveal_to_end()
	await capture("03-offscreen")
	await next_line(); view._process(10.0)
	await create_timer(.7).timeout
	view._vn_stage.dialog._reveal_to_end()
	verify(view._vn_stage.runner.ctx.characters.active_sprites.has("aling"), "Aling introduced")
	await capture("04-two-portraits")
	# Actual plugin auto toggle; the following name command must block it.
	view._vn_stage.runner.is_auto = true; view._vn_stage.runner.mode_changed.emit()
	await create_timer(2.3).timeout
	verify(view.awaiting_name(), "automatic playback stops at nickname gate")
	verify(not view._vn_stage.runner.is_auto, "auto reset at host block")
	view.toggle_presentation_pause(); verify(view.presentation_paused, "pause")
	view.toggle_presentation_pause()
	await capture("05-name")
	view._hero_input.text = "海风"; view._confirm_hero_name()
	await process_frame
	verify(view._vn_stage.dialog.speaker_label.text == "海风", "native speaker rename")
	await next_line(); await next_line()
	await process_frame; await process_frame
	verify(shell.profile.story.beat == "follow" and shell.profile.story.hero_name == "海风", "real story handoff")
	verify(shell.town.visible and shell.town._player.controls_enabled, "map control restored")
	verify(not view.visible and VNEngineMain.instance() == null, "plugin singleton cleaned")
	await capture("06-map-return")
	shell.go_title(); app.queue_free(); await process_frame; await process_frame
	print("VN_GPU checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
