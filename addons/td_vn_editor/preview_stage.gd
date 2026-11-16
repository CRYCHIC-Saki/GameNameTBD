extends TDVisualNovelStage
## Editor-only adapter. Duplicate the manifest before pointing at an isolated draft.
var draft_path: String = ""

func start(name_value: String, request_name: bool) -> void:
	reset(); _completed = false
	hero_name = name_value; needs_name = request_name
	container = SubViewportContainer.new(); container.stretch = true
	add_child(container); container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport = SubViewport.new(); viewport.size = Vector2i(1280,800)
	viewport.handle_input_locally = true; container.add_child(viewport)
	main = VNEngineMain.new(); main.host_managed = true
	main.content_root = "res://content/story/vn/"
	main.start_mode = "title"
	main.manage_window_scaling = false; main.return_to_title_on_finish = false
	main.set_meta("host",self); main.chapter_finished.connect(_on_completed)
	viewport.add_child(main)
	var game := VNEngineMain.game()
	game.manifest = game.manifest.duplicate(true)
	game.manifest.find_chapter("intro").script_path = draft_path
	main.play_chapter("intro")
	show()
