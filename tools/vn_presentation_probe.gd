extends SceneTree
const OUT := "res://artifacts/vn-presentation-20261122/gpu"
var checks: int = 0
var failures: int = 0
var view: TDDialogueView

func _initialize() -> void:
	run.call_deferred()

func verify(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ", label)
	else: print("PASS ", label)

func capture(label: String) -> void:
	await process_frame; await RenderingServer.frame_post_draw
	verify(root.get_texture().get_image().save_png(OUT.path_join(label + ".png")) == OK, "capture " + label)

func next_page() -> void:
	view._vn_stage.dialog._reveal_to_end()
	view._vn_stage.dialog._advance_dialog()
	await process_frame; await process_frame

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.size = Vector2i(1280, 800)
	var app := load("res://src/app/main.tscn").instantiate() as TDApplication
	app.settings_path = OUT.path_join("isolated-%d/settings.json" % Time.get_ticks_usec())
	root.add_child(app)
	var shell := app.game_shell; shell.automatic_time = false
	verify(shell.create_game("slot-01").ok, "isolated real new game")
	view = shell.guide.dialogue
	await process_frame; await process_frame
	verify(view._native and not view._cg.visible, "native opening, no old film")
	verify(not shell.town.visible, "story backdrop hides map")
	view._vn_stage.dialog._reveal_to_end()
	await capture("01-arrival-narration")
	await next_page()
	view._vn_stage.dialog._reveal_to_end()
	await capture("02-harbor-hero")
	for _i: int in 14:
		if view.awaiting_name(): break
		await next_page()
	verify(view.awaiting_name(), "real name entry preserved")
	await capture("03-name")
	view._hero_input.text = "海风"; view._confirm_hero_name()
	await process_frame
	for _i: int in 8:
		if view.talk == null: break
		await next_page()
	verify(shell.profile.story.beat == "follow", "real opening task handoff")
	verify(shell.profile.story.hero_name == "海风", "real profile name")
	verify(shell.town.visible and shell.town._player.controls_enabled, "map restored")
	await capture("04-map-preserved")
	for scene: String in ["soup", "after_taste", "awaken", "verdict_good", "home_door"]:
		var talk := TDOpeningScript.home_conversation(scene, "海风") if scene == "home_door" else TDOpeningScript.conversation(scene, "海风", 80)
		view.present(talk)
		await process_frame; await process_frame
		verify(view._native and view._vn_stage.runner is VNEngineStoryRunner, scene + " native")
		view._vn_stage.dialog._reveal_to_end()
		await capture("05-" + scene)
		await next_page()
		view._vn_stage.dialog._reveal_to_end()
		await capture("06-" + scene + "-dialogue")
		view.dismiss()
		await process_frame; await process_frame
	verify(VNEngineMain.instance() == null, "no leftover native singleton")
	shell.go_title(); app.queue_free()
	await process_frame; await process_frame
	var sheet := Control.new(); sheet.theme = TDUI.theme(); root.add_child(sheet)
	var paper := ColorRect.new(); paper.color = Color("f2eddf"); paper.size = Vector2(1280, 800); sheet.add_child(paper)
	var presentation: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/story/vn/presentation.json"))
	var i := 0
	for id: String in presentation.backgrounds:
		var picture := TextureRect.new(); picture.texture = load("res://content/story/vn/backgrounds/%s.tres" % id)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.position = Vector2((i % 3) * 426, (i / 3) * 195)
		picture.size = Vector2(426, 170); sheet.add_child(picture)
		var title := Label.new(); title.text = str(presentation.backgrounds[id].title)
		title.position = picture.position + Vector2(8, 170); sheet.add_child(title)
		i += 1
	await capture("background-catalog")
	print("VN_PRESENTATION_GPU checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
