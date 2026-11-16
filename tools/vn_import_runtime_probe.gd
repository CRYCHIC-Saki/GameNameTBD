extends SceneTree
const PreviewStage := preload("res://addons/td_vn_editor/preview_stage.gd")
const OUT := "res://artifacts/vn-import-20261116/gpu"
var checks: Array[Dictionary] = []

func _initialize() -> void:
	run.call_deferred()

func expect(value: bool, label: String) -> void:
	checks.append({"pass":value,"name":label})
	if not value: printerr("IMPORT_RUNTIME_FAIL "+label)

func run() -> void:
	root.size = Vector2i(1280,800)
	var imported: Array = JSON.parse_string(FileAccess.get_file_as_string(OUT.path_join("imports.json")))
	var stage := PreviewStage.new(); root.add_child(stage)
	stage.draft_path = OUT.path_join("draft.txt"); stage.start("？？？",true)
	await process_frame; await process_frame
	var actor_id: String = imported[1].character
	var expression: String = imported[2].expression
	expect(stage.runner != null,"real native runner")
	expect(stage.runner.current_text == "导入的角色和背景可以直接编排、试玩。","native imported dialogue")
	expect(stage.runner.ctx.characters.active_sprites.has(actor_id),"new cast instantiated")
	expect(stage.runner.state.characters[actor_id].expression == expression,"new expression used")
	expect(stage.runner.ctx.characters.active_sprites[actor_id].sprite.texture != null,"real portrait texture")
	expect(stage.runner.ctx.characters.cast.display_name_of(actor_id) == "示例角色","native displayed name")
	expect(VNEngineMain.save_data().memory_only,"no player persistence")
	stage.dialog._reveal_to_end(); await create_timer(.6).timeout
	RenderingServer.force_draw(true)
	expect(root.get_texture().get_image().save_png(OUT.path_join("05-native-play.png")) == OK,"native screenshot")
	stage.reset(); root.remove_child(stage); stage.queue_free(); await process_frame; await process_frame
	expect(VNEngineMain.instance() == null,"clean close")
	var failures := 0
	for item: Dictionary in checks:
		if not item.pass: failures+=1
	var file := FileAccess.open(OUT.path_join("runtime-report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"count":checks.size(),"failures":failures,"checks":checks},"\t")); file.close()
	print("VN_IMPORT_RUNTIME checks=%d failures=%d" % [checks.size(),failures])
	quit(1 if failures else 0)
