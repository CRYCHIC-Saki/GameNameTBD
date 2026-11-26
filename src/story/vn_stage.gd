class_name TDVisualNovelStage
extends Control
## Full VN Engine host. Only CG/name hand-offs and lifecycle belong to our game.
signal block_started(kind: String, args: String)
signal line_started(speaker: String, text: String)
signal completed
const HOST_COMMAND := preload("res://src/story/vn_host_command.gd")
var main: VNEngineMain
var runner: VNEngineStoryRunner
var dialog: VNEngineDialogUI
var viewport: SubViewport
var container: SubViewportContainer
var blocked: String = ""
var block_args: String = ""
var hero_name: String = ""
var needs_name: bool = false
var event_chapter: Dictionary = {}
var source_talk: TDDialogue
var scenario_text: String = ""
var chapter_id: String = "intro"
var _dialog_layer: CanvasLayer
var _generation: int = 0
var _paused: bool = false
var _completed: bool = false

class LedgerTitle extends Control:
	func _draw() -> void:
		var frame := get_parent() as TextureRect
		if frame.texture != null:
			var used := TDStoryArt.fit(frame.texture, Rect2(Vector2.ZERO, size))
			TDStoryArt.paint_ledger_title(self, frame.texture, Rect2(Vector2(0, -(size.y-used.size.y)*.5), size))

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	hide()

static func supports(talk: TDDialogue) -> bool:
	return talk != null and talk.presentation == "story"

func start(name_value: String, request_name: bool) -> void:
	reset()
	_completed = false
	hero_name = name_value
	needs_name = request_name
	chapter_id = str(event_chapter.get("id","intro"))
	container = SubViewportContainer.new()
	container.stretch = true
	add_child(container)
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 800)
	viewport.handle_input_locally = true
	container.add_child(viewport)
	main = VNEngineMain.new()
	main.host_managed = true
	main.content_root = "res://content/story/vn/"
	main.start_mode = "chapter" if event_chapter.is_empty() else "title"
	main.start_chapter = chapter_id
	main.manage_window_scaling = false
	main.return_to_title_on_finish = false
	main.set_meta("host", self)
	main.chapter_finished.connect(_on_completed)
	viewport.add_child(main)
	if not event_chapter.is_empty():
		var game := VNEngineMain.game()
		game.manifest = game.manifest.duplicate(true)
		var chapter := VNEngineChapterDef.new()
		chapter.id = chapter_id; chapter.title = event_chapter.title; chapter.script_path = event_chapter.script_path
		chapter.autosave_on_enter = false; chapter.intro_style = "none"
		game.manifest.chapters.append(chapter)
		main.play_chapter(chapter_id)
	show()

func attach_stage(stage: VNEngineStageScreen) -> void:
	runner = stage.story_runner
	dialog = runner.ctx.dialog_ui
	_dialog_layer = stage.get_node("CanvasLayer")
	for cmd: String in ["td_cg", "td_name", "td_pick"]:
		runner.bus.register(HOST_COMMAND.new(self, cmd))
	if source_talk != null:
		for beat: Dictionary in source_talk._beats:
			_register_speaker(beat)
			for option: Dictionary in beat.get("options", []): _register_speaker(option)
		runner.state.flags["san_before"] = str(source_talk.context.get("san_before", 100))
		runner.state.flags["san_after"] = str(source_talk.context.get("san_after", 95))
	runner.dialog_started.connect(_on_line)
	if not needs_name: _set_name(hero_name)

func _register_speaker(beat: Dictionary) -> void:
	var id := TDVNPresentation.speaker_id(beat)
	if id == "narrator" or runner.ctx.characters.cast.get_entry(id) != null: return
	var member := VNEngineCastMember.new()
	member.id = id
	member.display_name = str(beat.get("speaker", ""))
	member.blip = "off"
	runner.ctx.characters.cast.characters.append(member)

func preparsed_script(path: String) -> VNEngineStoryScript:
	if scenario_text.is_empty() or path != str(event_chapter.get("script_path", "")): return null
	return VNEngineScenarioParser.parse_text(scenario_text, path)

func record_pick(id: String) -> void:
	if source_talk != null and not _completed: source_talk.picks.append(id)

func begin_block(kind: String, args: String, context: VNEngineCommandContext) -> void:
	if context.runner != runner or _completed: return
	blocked = kind
	block_args = args.strip_edges()
	runner.is_input_locked = true
	runner.is_auto = false
	runner.is_skip = false
	runner.mode_changed.emit()
	dialog.auto_timer.stop()
	container.visible = kind == "td_name"
	_dialog_layer.visible = false
	viewport.gui_disable_input = true
	if kind == "td_name" and not needs_name:
		_resume.call_deferred(_generation)
	else: block_started.emit(kind, block_args)

func resume_cg() -> void:
	if blocked == "td_cg" and not _paused: _resume(_generation)

func submit_name(value: String) -> bool:
	var clean := value.strip_edges()
	if blocked != "td_name" or not needs_name or _paused or clean.is_empty() or clean.length() > 20: return false
	_set_name(clean)
	needs_name = false
	_resume.call_deferred(_generation)
	return true

func _set_name(value: String) -> void:
	hero_name = value if not value.is_empty() else "？？？"
	runner.state.flags["hero"] = hero_name
	runner.ctx.characters.cast.get_entry("hero").display_name = hero_name

func _resume(generation: int) -> void:
	if generation != _generation or not is_instance_valid(runner) or blocked.is_empty(): return
	blocked = ""; block_args = ""
	container.show()
	_dialog_layer.show()
	viewport.gui_disable_input = _paused
	runner.is_input_locked = false
	runner.bus.resolve_block()

func _on_line(node: VNEngineStoryNode) -> void:
	# Projection for story/music shell; never a second progression runner.
	for who: String in runner.ctx.characters.active_sprites:
		var actor: VNEngineCharacterSprite = runner.ctx.characters.active_sprites[who]
		if str(actor.get_meta("td_layout", "")).is_empty():
			actor.offset_top = -720.0
			actor.offset_bottom = -115.0
		if who == "aling" and not actor.sprite.has_node("LedgerTitle") and (source_talk == null or source_talk.context.get("kind") not in ["revised_mainline","revised_preview"]):
			var title := LedgerTitle.new()
			title.name = "LedgerTitle"
			title.mouse_filter = Control.MOUSE_FILTER_IGNORE
			actor.sprite.add_child(title)
			title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	line_started.emit(node.speaker_id, runner.current_text)

func _on_completed(chapter: String) -> void:
	if chapter != chapter_id or _completed: return
	_completed = true
	_emit_completed.call_deferred(_generation)

func _emit_completed(generation: int) -> void:
	if generation == _generation and _completed: completed.emit()

func set_paused(value: bool) -> void:
	_paused = value
	if is_instance_valid(main): main.process_mode = Node.PROCESS_MODE_DISABLED if value else Node.PROCESS_MODE_INHERIT
	if is_instance_valid(viewport): viewport.gui_disable_input = value or not blocked.is_empty()

func reset() -> void:
	_generation += 1
	blocked = ""; block_args = ""; _paused = false
	if is_instance_valid(container):
		if is_instance_valid(runner): runner.cancel_host()
		# Detach synchronously: release singleton before another slot/replay.
		remove_child(container)
		container.queue_free()
	main = null; runner = null; dialog = null; container = null; viewport = null
	hide()
