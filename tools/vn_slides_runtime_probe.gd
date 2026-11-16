extends "res://tools/vn_draft_probe.gd"
const Document := preload("res://addons/td_vn_editor/document.gd")
const Canvas := preload("res://addons/td_vn_editor/composition.gd")
const SLIDES_OUT := "res://artifacts/vn-slides-20261116/runtime-gpu"

func capture(label: String) -> void:
	await create_timer(.6).timeout
	RenderingServer.force_draw(true)
	expect(root.get_texture().get_image().save_png(SLIDES_OUT.path_join(label+".png")) == OK,"capture "+label)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SLIDES_OUT))
	root.size = Vector2i(1280,800)
	var doc := Document.new()
	doc.load_text("# first\n@bg restaurant-v1 with instant 0\n@show hero calm at left with instant\n@show aling calm at right with instant\nhero: 拖动角色，安排这一页的画面。\n# second\naling: 下一页保留自己的位置。\n# finish\n@end\n")
	doc.set_page_visual(4,"position","hero","td:.4171875:.79375:.9")
	var first: Dictionary = doc.composition(doc.pages()[0].line)
	var file := FileAccess.open(SLIDES_OUT.path_join("draft.txt"),FileAccess.WRITE)
	file.store_string(doc.text()); file.close()
	view = load("res://addons/td_vn_editor/preview.tscn").instantiate(); root.add_child(view)
	view.draft = SLIDES_OUT.path_join("draft.txt"); view.replay(); view.set_process(false)
	await process_frame; await process_frame
	var actor: Control = view.stage.runner.ctx.characters.active_sprites.hero
	expect(actor.position.distance_to(Vector2(315.12,90.5))<.03,"runtime authored X Y")
	expect(actor.size.distance_to(Vector2(437.76,544.5))<.03,"runtime uniform size")
	var canvas := Canvas.new(); canvas.state = first
	expect(actor.get_rect().is_equal_approx(canvas.actor_bounds("hero")),"editor and native runtime share geometry")
	canvas.free()
	view.stage.dialog._reveal_to_end(); await capture("01-authored-playback")
	await advance()
	expect(view.stage.runner.current_text == "下一页保留自己的位置。","real click advances page")
	actor = view.stage.runner.ctx.characters.active_sprites.hero
	expect(actor.get_rect().is_equal_approx(Rect2(76.8,80,486.4,605)),"next page retains original geometry")
	view.stage.dialog._reveal_to_end(); await capture("02-next-page")
	view.replay(); await process_frame; await process_frame
	expect(view.stage.runner.ctx.characters.active_sprites.hero.get_rect().is_equal_approx(Rect2(315.12,90.5,437.76,544.5)),"restart restores authored coordinates")
	expect(VNEngineMain.save_data().memory_only,"preview never accesses real saves")
	root.remove_child(view); view.queue_free(); await process_frame; await process_frame
	expect(VNEngineMain.instance() == null,"native singleton released")
	var failures := 0
	for item: Dictionary in checks:
		if not item.pass: failures += 1
	var report := FileAccess.open(SLIDES_OUT.path_join("report.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"count":checks.size(),"failures":failures},"\t")); report.close()
	print("VNE_SLIDES_RUNTIME checks=%d failures=%d" % [checks.size(),failures])
	quit(1 if failures > 0 else 0)
