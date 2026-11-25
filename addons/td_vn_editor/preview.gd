extends Control
const Stage := preload("res://addons/td_vn_editor/preview_stage.gd")
const Document := preload("res://addons/td_vn_editor/document.gd")
var stage: TDVisualNovelStage
var cg: TDCutsceneView
var name_panel: PanelContainer
var input: LineEdit
var status: Label
var shot_elapsed: float = 0
var shot_duration: float = 0
var draft: String = ""

func _ready() -> void:
	get_window().title = "剧情试玩 · 不读写玩家存档"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--vn-draft="): draft = arg.trim_prefix("--vn-draft=")
	stage = Stage.new(); add_child(stage)
	cg = TDCutsceneView.new(); cg.top_gutter = 54.0; add_child(cg)
	cg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); cg.hide()
	stage.block_started.connect(_block)
	stage.completed.connect(func() -> void: status.text = "播放结束 · 可重新播放或关闭窗口")
	var bar := HBoxContainer.new(); bar.position = Vector2(14,12); add_child(bar)
	for title: String in ["重新播放","跳过本段 CG","关闭试玩"]:
		var button := Button.new(); button.text = title; bar.add_child(button)
		match title:
			"重新播放": button.pressed.connect(replay)
			"跳过本段 CG": button.pressed.connect(_finish_cg)
			_: button.pressed.connect(func() -> void: get_tree().quit())
	status = Label.new(); status.text = "独立试玩"; bar.add_child(status)
	name_panel = PanelContainer.new(); name_panel.position = Vector2(420,300); name_panel.size = Vector2(440,130)
	add_child(name_panel)
	var box := VBoxContainer.new(); name_panel.add_child(box)
	var label := Label.new(); label.text = "我的名字是……"; box.add_child(label)
	input = LineEdit.new(); input.max_length = 20; box.add_child(input)
	var submit := Button.new(); submit.text = "确认"; box.add_child(submit)
	submit.pressed.connect(_submit_name); input.text_submitted.connect(func(_value: String) -> void: _submit_name())
	name_panel.hide()
	if not draft.is_empty(): replay()
	else: status.text = "请从 Godot 顶部“剧情”面板点击试玩。"

func replay() -> void:
	stage.reset(); cg.hide(); cg.stop_audio(); name_panel.hide()
	var document := Document.new()
	var error := document.open_file(draft)
	if not error.is_empty(): status.text = error; return
	var issues := document.validate()
	if not issues.is_empty(): status.text = "剧本检查失败：" + issues[0]; return
	stage.draft_path = draft
	stage.start("？？？", true)
	status.text = "点击对白继续 · 可使用原生自动 / 快进"

func _block(kind: String, args: String) -> void:
	if kind == "td_cg":
		shot_elapsed = 0; shot_duration = Document.Illustrated.duration_for(args)
		cg.show_shot(args,0,shot_duration)
	else:
		name_panel.show(); input.text = ""; input.grab_focus()

func _submit_name() -> void:
	if stage.submit_name(input.text): name_panel.hide()

func _process(delta: float) -> void:
	if stage != null and stage.blocked == "td_cg":
		shot_elapsed += delta
		cg.show_shot(stage.block_args,shot_elapsed,shot_duration)
		if shot_elapsed >= shot_duration: _finish_cg()

func _finish_cg() -> void:
	if stage.blocked != "td_cg": return
	cg.show_shot("", 0, 1); stage.resume_cg()

func _exit_tree() -> void:
	if is_instance_valid(stage): stage.reset()
	if is_instance_valid(cg): cg.stop_audio()
