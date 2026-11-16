extends SceneTree
const OUT := "res://artifacts/vn-editor-20261116/runtime-gpu"
var view: Control
var checks: Array[Dictionary] = []

func _initialize() -> void:
	run.call_deferred()

func expect(value: bool, label: String) -> void:
	checks.append({"name":label,"pass":value})
	if not value: printerr("VNE_RUNTIME_FAIL " + label)

func shot(label: String) -> void:
	await create_timer(0.6).timeout
	await process_frame; await RenderingServer.frame_post_draw
	expect(root.get_texture().get_image().save_png(OUT.path_join(label+".png")) == OK,"capture "+label)

func click(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new(); motion.position = point; Input.parse_input_event(motion)
	for pressed: bool in [true,false]:
		var event := InputEventMouseButton.new(); event.position = point
		event.button_index = MOUSE_BUTTON_LEFT; event.pressed = pressed
		Input.parse_input_event(event); await process_frame

func advance() -> void:
	view.stage.dialog._reveal_to_end()
	await click(Vector2(800,700))
	await process_frame

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.size = Vector2i(1280,800)
	var file := FileAccess.open(OUT.path_join("draft.txt"),FileAccess.WRITE)
	file.store_string("# arrival\n@td_cg arrival\n# greeting\n@bg arrival-coast-v1 with instant 0\n@show hero happy at left with instant\n@show aling calm at right with instant\naling: 欢迎来到港口。\n# name\n@td_name hero\n# answer\nhero: 我叫{$hero}。\n- 看看港口 -> harbor\n- 先休息 -> finish\n# harbor\nhero: 海风真舒服。\n# finish\n@end\n"); file.close()
	view = load("res://addons/td_vn_editor/preview.tscn").instantiate(); root.add_child(view)
	view.draft = OUT.path_join("draft.txt"); view.replay(); view.set_process(false)
	await process_frame; await process_frame
	expect(view.stage.blocked == "td_cg","real CG command blocks runner")
	expect(view.cg.visible,"real CG layer visible")
	view.cg.show_shot("arrival",4.0,14.0,true)
	await shot("01-cg")
	await click(Vector2(180,30))
	await process_frame
	expect(view.stage.blocked == "","skip current CG resumes actual runner")
	expect(view.stage.runner.current_text == "欢迎来到港口。","draft dialogue appears")
	view.stage.dialog._reveal_to_end()
	await shot("02-dialogue")
	await advance()
	expect(view.name_panel.visible,"real name control visible")
	view.input.text = "小舟"
	view.input.text_submitted.emit("小舟")
	await process_frame
	expect(view.stage.runner.current_text == "我叫小舟。","name substituted by native engine")
	view.stage.dialog._reveal_to_end()
	await process_frame
	expect(view.stage.runner.current_choices.size() == 2,"native choices available")
	await shot("03-choice")
	# Real mouse input on the first native choice, not a mock dispatcher.
	await click(Vector2(600,240))
	# The native button plays its pick/fade animation before committing the choice.
	await create_timer(0.6).timeout
	expect(view.stage.runner.current_text == "海风真舒服。","native branch reaches destination")
	expect(VNEngineMain.save_data().memory_only,"no player persistence")
	view.replay(); await process_frame; await process_frame
	expect(view.stage.blocked == "td_cg","restart returns to draft beginning")
	expect(view.stage.hero_name == "？？？","restart clears prior name")
	var manifest: VNEngineGameManifest = load("res://content/story/vn/config/game.tres")
	expect(manifest.find_chapter("intro").script_path == "res://content/story/vn/scenario/intro/script.txt","official manifest unchanged")
	root.remove_child(view); view.queue_free(); await process_frame; await process_frame
	expect(VNEngineMain.instance() == null,"close releases native runtime")
	var failures := 0
	for item: Dictionary in checks:
		if not item.pass: failures += 1
	var report := FileAccess.open(OUT.path_join("report.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"count":checks.size(),"failures":failures},"\t")); report.close()
	print("VNE_DRAFT_GPU checks=%d failures=%d" % [checks.size(),failures])
	quit(1 if failures > 0 else 0)
