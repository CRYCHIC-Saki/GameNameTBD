extends "res://tools/vn_draft_probe.gd"
const CANVAS_OUT := "res://artifacts/vn-canvas-20261117/runtime-gpu"
const Document := preload("res://addons/td_vn_editor/document.gd")
const Canvas := preload("res://addons/td_vn_editor/composition.gd")

func capture(label: String) -> Image:
	await create_timer(.4).timeout
	RenderingServer.force_draw(true)
	var result := root.get_texture().get_image()
	expect(result.save_png(CANVAS_OUT.path_join(label+".png"))==OK,"capture "+label)
	return result

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CANVAS_OUT))
	root.size = Vector2i(1280,800)
	var doc := Document.new()
	doc.load_text("# first\n@bg restaurant-v1 with instant 0\n@show hero calm at td:.5:1.25625:2 with instant\nhero: 放大后的近景。\n# next\n@move hero to td:2:.9:2 over 0\nhero: 角色已移到画外。\n# end\n@end\n")
	var file := FileAccess.open(CANVAS_OUT.path_join("draft.txt"),FileAccess.WRITE)
	file.store_string(doc.text()); file.close()
	view = load("res://addons/td_vn_editor/preview.tscn").instantiate(); root.add_child(view)
	view.draft = CANVAS_OUT.path_join("draft.txt"); view.replay(); view.set_process(false)
	await process_frame; await process_frame
	var actor: Control = view.stage.runner.ctx.characters.active_sprites.hero
	expect(actor.get_rect().is_equal_approx(Rect2(153.6,-205,972.8,1210)),"native close-up explicit geometry")
	view.stage.dialog._reveal_to_end(); await capture("01-native-close-up")
	await advance(); await create_timer(.5).timeout
	actor = view.stage.runner.ctx.characters.active_sprites.hero
	expect(actor.position.x>1280,"move fully exits game screen")
	expect(view.stage.runner.state.characters.hero.position=="td:2:.9:2","native state retains offscreen position")
	view.stage.dialog._reveal_to_end(); await capture("02-native-offscreen")
	expect(VNEngineMain.save_data().memory_only,"preview does not write player saves")
	root.remove_child(view); view.queue_free(); await process_frame; await process_frame
	expect(VNEngineMain.instance()==null,"native singleton cleanup")
	# Wide thumbnail has side margins. A 5x actor must not leak into them.
	var thumbnail := Canvas.new(); thumbnail.thumbnail=true; root.add_child(thumbnail)
	thumbnail.size = Vector2(1280,600)
	doc.load_text("@bg restaurant-v1 with instant 0\n@show hero calm at td:.5:1.75625:5 with instant\nhero: 缩略图裁切\n")
	thumbnail.assign_state(doc.composition(2))
	var image := await capture("03-thumbnail-crop")
	var shade := Color("161e29")
	for point: Vector2i in [Vector2i(100,150),Vector2i(100,450),Vector2i(1180,150),Vector2i(1180,450)]:
		var color := image.get_pixelv(point)
		expect(absf(color.r-shade.r)<.015 and absf(color.g-shade.g)<.015 and absf(color.b-shade.b)<.015,"thumbnail clips side margin "+str(point))
	thumbnail.queue_free(); await process_frame
	var failures := 0
	for item: Dictionary in checks:
		if not item.pass: failures += 1
	var report := FileAccess.open(CANVAS_OUT.path_join("report.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"count":checks.size(),"failures":failures},"\t")); report.close()
	print("VNE_CANVAS_RUNTIME checks=%d failures=%d" % [checks.size(),failures])
	quit(1 if failures > 0 else 0)
