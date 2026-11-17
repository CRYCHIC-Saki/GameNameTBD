@tool
extends VBoxContainer
const Document := preload("res://addons/td_vn_editor/document.gd")
const Composition := preload("res://addons/td_vn_editor/composition.gd")
const ImportDialog := preload("res://addons/td_vn_editor/import_dialog.gd")
const Handoff := preload("res://addons/td_vn_editor/handoff.gd")
const RECOVERY := "res://.godot/td_vn_editor/recovery.json"
const PREVIEW_SCENE := "res://addons/td_vn_editor/preview.tscn"
var document := Document.new()
var selected: int = 0
var rows: ItemList
var preview: Control
var fields: VBoxContainer
var controls: Dictionary = {}
var path_label: Label
var status: RichTextLabel
var file_dialog: FileDialog
var confirm: ConfirmationDialog
var recover_button: Button
var action_menu: MenuButton
var preview_pid: int = -1
var pending_action: Callable
var field_dirty: bool = false
var _building: bool = false
var _recovery_payload: Dictionary = {}
var page_mode: bool = true
var page_list: VBoxContainer
var page_scroll: ScrollContainer
var step_tools: HBoxContainer
var insert_bar: HBoxContainer
var palette: AcceptDialog
var selected_actor: String = ""
var edit_deadline: int = 0
var page_cards: Dictionary = {}
var import_dialog: ConfirmationDialog
var trigger_dialog: ConfirmationDialog
var handoff_dialog: ConfirmationDialog
var trigger_button: Button
var _handoff_pending: Dictionary = {}
var _handoff_copy: bool = false
var zoom_control: SpinBox
var actor_picker: OptionButton
var actor_scale: SpinBox

func _ready() -> void:
	name = "TownDinerStoryEditor"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var bar := HBoxContainer.new(); add_child(bar)
	_button(bar,"新建",_request_new)
	_button(bar,"打开",func() -> void: _guard(_open_picker))
	_button(bar,"保存",save_document)
	_button(bar,"另存为",func() -> void: _request_handoff_save(true))
	_button(bar,"导入素材",_open_import)
	_button(bar,"撤销",func() -> void: _undo(false))
	_button(bar,"重做",func() -> void: _undo(true))
	_button(bar,"检查",check_document)
	_button(bar,"▶ 试玩",play_draft)
	_button(bar,"■ 停止",stop_preview)
	recover_button = _button(bar,"恢复草稿",restore_recovery)
	var advanced := CheckButton.new(); advanced.text = "高级步骤"; bar.add_child(advanced)
	advanced.toggled.connect(func(value: bool) -> void: _commit_fields(); page_mode = not value; _refresh())
	path_label = Label.new(); path_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(path_label)
	insert_bar = HBoxContainer.new(); add_child(insert_bar)
	_button(insert_bar,"＋ 新的一页",func() -> void: add_page(false))
	_button(insert_bar,"复制这一页",func() -> void: add_page(true))
	_button(insert_bar,"删除这一页",delete_page)
	_button(insert_bar,"插入背景",func() -> void: show_palette("background"))
	_button(insert_bar,"插入角色",func() -> void: show_palette("actor"))
	trigger_button=_button(bar,"开发接入",_open_trigger);trigger_button.hide()
	var split := HSplitContainer.new(); split.size_flags_vertical = Control.SIZE_EXPAND_FILL; add_child(split)
	var left := VBoxContainer.new(); left.custom_minimum_size.x = 230; split.add_child(left)
	var tools := HBoxContainer.new(); left.add_child(tools)
	step_tools = tools
	action_menu = MenuButton.new(); action_menu.text = "＋ 添加步骤"; tools.add_child(action_menu)
	for title: String in ["对白", "背景", "角色入场 / 表情", "角色退场", "等待", "节点", "选项", "跳转", "结束", "CG 演出", "输入姓名", "注释"]: action_menu.get_popup().add_item(title)
	action_menu.get_popup().id_pressed.connect(add_step)
	_button(tools,"↑",func() -> void: move_step(-1))
	_button(tools,"↓",func() -> void: move_step(1))
	_button(tools,"×",remove_step)
	rows = ItemList.new(); rows.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.custom_minimum_size.y = 250; rows.auto_height = false
	rows.item_selected.connect(_select_row); left.add_child(rows)
	page_scroll = ScrollContainer.new(); page_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; left.add_child(page_scroll)
	page_list = VBoxContainer.new(); page_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL; page_scroll.add_child(page_list)
	var right_split := HSplitContainer.new(); split.add_child(right_split)
	var middle := VBoxContainer.new(); middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL; right_split.add_child(middle)
	var view_bar := HBoxContainer.new(); middle.add_child(view_bar)
	var note := Label.new(); note.text = "画布"; view_bar.add_child(note)
	zoom_control = SpinBox.new(); zoom_control.min_value = 10; zoom_control.max_value = 100
	zoom_control.step = 5; zoom_control.value = 70; zoom_control.suffix = "%"; view_bar.add_child(zoom_control)
	zoom_control.tooltip_text = "只缩放编辑视图；暗区是屏幕外，可拖入角色。"
	var hint := Label.new(); hint.text = "暗区为画外 · Esc 取消拖动"; view_bar.add_child(hint)
	preview = Composition.new(); middle.add_child(preview)
	preview.set_view_zoom(zoom_control.value / 100.0)
	zoom_control.value_changed.connect(func(value: float) -> void: preview.set_view_zoom(value / 100.0))
	preview.actor_selected.connect(_select_actor)
	preview.actor_moved.connect(func(who: String, token: String) -> void: _visual("position",who,token))
	status = RichTextLabel.new(); status.custom_minimum_size.y = 95; status.fit_content = false; status.scroll_active = true; middle.add_child(status)
	var scroll := ScrollContainer.new(); scroll.custom_minimum_size.x = 270
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; right_split.add_child(scroll)
	fields = VBoxContainer.new(); fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.add_child(fields)
	file_dialog = FileDialog.new(); file_dialog.access = FileDialog.ACCESS_RESOURCES
	file_dialog.filters = PackedStringArray(["*.txt ; VN 剧本"])
	file_dialog.file_selected.connect(_file_selected); add_child(file_dialog)
	confirm = ConfirmationDialog.new(); confirm.title = "保留未保存的修改"
	confirm.dialog_text = "未保存的修改会保留为恢复草稿。仍要切换剧本吗？"
	confirm.confirmed.connect(func() -> void: if pending_action.is_valid(): pending_action.call())
	add_child(confirm)
	palette = AcceptDialog.new(); palette.title = "插入素材"; palette.get_ok_button().text = "关闭"; add_child(palette)
	import_dialog = ImportDialog.new(); add_child(import_dialog)
	import_dialog.imported.connect(_asset_imported)
	trigger_dialog = preload("res://addons/td_vn_editor/trigger_dialog.gd").new(); add_child(trigger_dialog)
	trigger_dialog.registered.connect(func()->void: status.text="触发已保存 · 重新运行游戏后生效；导出游戏请重新打包。")
	handoff_dialog=preload("res://addons/td_vn_editor/handoff_dialog.gd").new();add_child(handoff_dialog)
	handoff_dialog.accepted.connect(_handoff_accepted)
	file_dialog.canceled.connect(func()->void: _handoff_pending.clear())
	if FileAccess.file_exists(RECOVERY):
		var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(RECOVERY))
		if value is Dictionary: _recovery_payload = value
	recover_button.visible = not _recovery_payload.is_empty()
	open_document(Document.INTRO)

func _exit_tree() -> void:
	_commit_fields()
	_write_recovery()
	stop_preview()

func _button(parent: Node, caption: String, callback: Callable) -> Button:
	var button := Button.new(); button.text = caption; parent.add_child(button)
	button.pressed.connect(callback); return button

func _open_import() -> void:
	_commit_fields(); preview.cancel_drag()
	import_dialog.open(not document.lines.is_empty() and Document.describe(document.lines[selected]).kind == "dialogue")

func _open_trigger() -> void:
	_commit_fields(); preview.cancel_drag()
	if document.path == Document.INTRO:
		status.text="港口开篇已有固定触发，保留原教学。请新建或另存为一段演出，再设置游戏触发。"; return
	if document.path.is_empty() or document.dirty():
		status.text="请先保存这段演出，再设置游戏触发。"; return
	trigger_dialog.open_script(document.path)

func _asset_imported(result: Dictionary, insert_asset: bool) -> void:
	preview.textures.clear()
	if insert_asset:
		if result.kind == "background": _visual("background",result.id)
		else:
			_visual("actor",result.character)
			if result.kind == "expression": _visual("expression",result.character,result.expression)
	else: _refresh()
	status.text = "已导入“%s” · 已加入素材库和游戏导出清单" % str(result.title)

func _guard(action: Callable) -> void:
	_commit_fields()
	if document.dirty():
		_write_recovery(); pending_action = action; confirm.popup_centered(Vector2i(470,180))
	else: action.call()

func _open_picker() -> void:
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.current_dir = Document.ROOT
	file_dialog.popup_centered_ratio(.7)

func _save_picker() -> void:
	_commit_fields()
	file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(Handoff.DRAFTS))
	file_dialog.current_dir = Handoff.DRAFTS
	file_dialog.current_file = "剧情_"+Time.get_datetime_string_from_system().replace(":","-").replace("T","_")+".txt"
	file_dialog.popup_centered_ratio(.7)

func _file_selected(path: String) -> void:
	if file_dialog.file_mode == FileDialog.FILE_MODE_OPEN_FILE: open_document(path)
	elif not _handoff_pending.is_empty(): _save_handoff(path)
	else: status.text="请点击保存，填写交接说明后保存剧情。"

func open_document(path: String) -> void:
	var error := document.open_file(path)
	if not error.is_empty(): status.text = error; return
	selected = 0
	for page: Dictionary in document.pages():
		if page.kind == "dialogue": selected = page.line; break
	field_dirty = false; _refresh()
	var handoff:=Handoff.read(document.text())
	status.text = "已打开 · Ctrl+S 保存并填写交接说明 · Ctrl+Enter 试玩"
	if not handoff.error.is_empty(): status.text=handoff.error
	elif not handoff.data.is_empty(): status.text="交接说明："+str(handoff.data.section).replace("\n"," ").left(45)+" · "+str(handoff.data.placement).replace("\n"," ").left(75)+"（保存时可查看／修改）"

func _request_new() -> void:
	_guard(func() -> void:
		if page_mode:
			document.load_text("# slide_start\n@bg blank with instant 0\nnarrator: 在这里写对白。\n\n# finish\n@end\n"); selected = 2
		else:
			document.load_text("# start\n@bg arrival-coast-v1 with fade 0.5\n@show hero calm at left with fade\nhero: 在这里写下一句对白。\n\n# finish\n@end\n"); selected = 3
		field_dirty = false; _refresh()
		status.text = "编排好后点保存，用中文写明这段剧情放在哪里，交给 AI 或开发者接入。")

func _refresh() -> void:
	selected = clampi(selected,0,maxi(0,document.lines.size()-1))
	if not document.lines.is_empty() and document.lines[selected].strip_edges().is_empty():
		while selected > 0 and document.lines[selected].strip_edges().is_empty(): selected -= 1
	if page_mode:
		var all_pages := document.pages()
		var nearest := -1
		for page: Dictionary in all_pages:
			if page.line <= selected: nearest = page.line
		if nearest < 0 and not all_pages.is_empty(): nearest = all_pages[0].line
		if nearest >= 0: selected = nearest
	rows.visible = not page_mode; step_tools.visible = not page_mode
	trigger_button.visible = not page_mode
	page_scroll.visible = page_mode; insert_bar.visible = page_mode
	rows.clear()
	for i in document.lines.size():
		var item := Document.describe(document.lines[i])
		if item.kind == "blank": continue
		rows.add_item("%02d  %s" % [i+1, str(item.label).left(65)])
		rows.set_item_metadata(rows.item_count-1,i)
		rows.set_item_tooltip(rows.item_count-1,document.lines[i])
		if i == selected: rows.select(rows.item_count-1)
	path_label.text = ("● " if document.dirty() else "") + (document.path if not document.path.is_empty() else "新剧本（未保存）")
	_fill_fields(); _show_composition(); _write_recovery()
	if page_mode: _build_pages()

func _select_row(index: int) -> void:
	var next := int(rows.get_item_metadata(index))
	_commit_fields()
	selected = next; _refresh()

func _targets() -> Dictionary:
	var result := {}
	for line: String in document.lines:
		var item := Document.describe(line)
		if item.kind == "label":
			var id := str(item.value).trim_prefix("id:").get_slice("|",0).strip_edges()
			result[id] = id
	return result

func _show_composition() -> void:
	preview.assign_state(document.composition(selected))
	preview.editable = page_mode and not document.lines.is_empty() and Document.describe(document.lines[selected]).kind == "dialogue"
	preview.selected_actor = selected_actor

func _label(caption: String) -> void:
	var label := Label.new(); label.text = caption
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fields.add_child(label)

func _entry(key: String, caption: String, value: String, multiline: bool = false) -> void:
	_label(caption)
	var control: Control
	if multiline:
		var edit := TextEdit.new(); edit.text = value; edit.custom_minimum_size = Vector2(250,140)
		edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		edit.text_changed.connect(_changed); control = edit
	else:
		var edit := LineEdit.new(); edit.text = value
		edit.text_changed.connect(func(_value: String) -> void: _changed())
		edit.text_submitted.connect(func(_value: String) -> void: apply_fields())
		control = edit
	controls[key] = control; fields.add_child(control)

func _choice(key: String, caption: String, options: Dictionary, value: String) -> void:
	_label(caption)
	var button := OptionButton.new(); button.fit_to_longest_item = false
	button.custom_minimum_size.x = 245; controls[key] = button; fields.add_child(button)
	var values := options.duplicate()
	if not values.has(value): values[value] = value
	for id: String in values:
		var item_caption := str(values[id])
		if key in ["speaker","actor"] and id == "hero": item_caption = "主角（玩家姓名）"
		if key == "background" and id == "arrival-coast-v1": item_caption = "港口 · 开篇"
		button.add_item(item_caption); button.set_item_metadata(button.item_count-1,id)
		if id == value: button.select(button.item_count-1)
	button.item_selected.connect(func(_index: int) -> void:
		_changed()
		if key == "actor" and controls.has("expression"):
			var expressions := controls.expression as OptionButton
			expressions.clear()
			for expr: String in Document.expressions(_value("actor")):
				expressions.add_item(Document.expression_title(_value("actor"),expr)); expressions.set_item_metadata(expressions.item_count-1,expr))

func _fill_fields() -> void:
	_building = true; field_dirty = false; controls.clear()
	for child: Node in fields.get_children(): fields.remove_child(child); child.queue_free()
	if document.lines.is_empty(): _building = false; return
	if page_mode:
		_fill_page_fields(); _building = false; return
	var item := Document.describe(document.lines[selected])
	var captions := {"dialogue":"对白","bg":"背景","show":"角色立绘","hide":"角色退场","wait":"等待","label":"节点","choice":"选项","jump":"跳转","end":"结束","td_cg":"CG 演出","td_name":"输入姓名","comment":"注释"}
	_label("步骤 %d · %s" % [selected+1, captions.get(item.kind,"原生语句")])
	match item.kind:
		"dialogue":
			_choice("speaker","说话人",Document.cast_names(),item.speaker)
			_entry("text","对白",str(item.text).replace("\\n","\n"),true)
		"show":
			var p := VNEngineCmdShow.parse_show_args(item.value)
			var cast := Document.cast_names(); cast.erase("")
			_choice("actor","角色",cast,p.get("id","hero"))
			var options := {}; for expr: String in Document.expressions(p.get("id","hero")): options[expr] = Document.expression_title(p.get("id","hero"),expr)
			_choice("expression","表情",options,p.get("expression","calm"))
			_choice("position","位置",{"left":"左侧","center":"中央","right":"右侧"},p.get("position","left"))
			_choice("transition","出场",{"fade":"淡入","instant":"立即"},p.get("transition","fade"))
			# Preserve less common native options when updating a basic show step.
			for key: String in ["outfit","pose","shot"]: controls["native_"+key] = p.get(key,"")
		"bg":
			var options := {}; for id: String in Document.backgrounds(): options[id] = Document.background_title(id)
			_choice("background","背景",options,str(item.value).get_slice(" ",0))
			_choice("transition","切换",{"fade":"淡入","instant":"立即"},"instant" if str(item.value).contains("instant") else "fade")
			var last := str(item.value).split(" ",false)[-1]
			_entry("duration","过渡秒数",last if last.is_valid_float() else "0.5")
		"hide":
			var cast := Document.cast_names(); cast.erase("")
			_choice("actor","角色",cast,str(item.value).get_slice(" ",0))
			var tokens := str(item.value).split(" ",false)
			var transition := "fade"
			if tokens.has("with") and tokens.find("with") + 1 < tokens.size(): transition = tokens[tokens.find("with")+1]
			_choice("transition","退场",{"fade":"淡出","instant":"立即"},transition)
		"choice":
			_entry("text","选项文字",item.text)
			_choice("target","跳转节点",_targets(),item.target)
		"td_cg": _choice("value","CG 片段",{"arrival":"到达港口","hungry":"饥饿","messenger":"阿铃登场"},item.value)
		"td_name": _label("主角姓名输入 · 游戏宿主处理")
		"end": _label("结束当前章节")
		"wait": _entry("value","等待秒数",item.value)
		"label": _entry("value","节点 ID（用于跳转）",item.value)
		"jump": _choice("value","目标节点",_targets(),item.value)
		"comment": _entry("value","注释",item.value,true)
		_: _entry("raw","原生语句（完整保留）",document.lines[selected],true)
	_button(fields,"应用到预览",apply_fields)
	_label("自动保留未保存草稿；保存后才修改剧本。")
	_building = false

func _changed() -> void:
	if _building: return
	field_dirty = true
	if page_mode:
		edit_deadline = Time.get_ticks_msec()+650
		preview.state.speaker = _value("speaker")
		preview.state.text = _value("text")
		preview.queue_redraw()
	# Keep field text recoverable even if the editor is closed before Apply.
	_write_recovery()

func _value(key: String) -> String:
	var control: Variant = controls.get(key)
	if control is OptionButton:
		return str(control.get_selected_metadata()) if control.selected >= 0 else ""
	if control is TextEdit or control is LineEdit: return control.text
	return str(control) if control != null else ""

func _edited_line() -> String:
	if document.lines.is_empty(): return ""
	var item := Document.describe(document.lines[selected])
	match item.kind:
		"dialogue": return Document.dialogue_line(_value("speaker"),_value("text"))
		"show":
			var native := ""
			for key: String in ["outfit","pose","shot"]:
				if not _value("native_"+key).is_empty(): native += " %s=%s" % [key,_value("native_"+key)]
			return "@show %s %s%s at %s with %s" % [_value("actor"),_value("expression"),native,_value("position"),_value("transition")]
		"bg": return "@bg %s with %s %s" % [_value("background"),_value("transition"),_value("duration")]
		"hide": return "@hide " + _value("actor") + " with " + _value("transition")
		"choice": return "- " + _value("text") + " -> " + _value("target")
		"label": return "# " + _value("value")
		"comment": return "// " + _value("value").replace("\n","\n// ")
		"wait", "jump", "td_cg": return "@" + str(item.kind) + " " + _value("value")
		"td_name", "end": return document.lines[selected]
		_: return _value("raw")

func _commit_fields() -> void:
	if field_dirty:
		document.replace_line(selected,_edited_line()); field_dirty = false

func apply_fields() -> void:
	_commit_fields(); _refresh()

func add_step(kind: int) -> void:
	_commit_fields()
	var defaults := ["hero: 新的对白。","@bg arrival-coast-v1 with fade 0.5","@show hero calm at left with fade","@hide hero with fade","@wait 0.5","# node_"+str(Time.get_ticks_usec()),"- 选项文字 -> finish","@jump finish","@end","@td_cg arrival","@td_name hero","// 注释"]
	selected = mini(selected+1,document.lines.size())
	document.insert_line(selected,defaults[kind]); _refresh()

func remove_step() -> void:
	_commit_fields(); document.remove_line(selected); _refresh()

func move_step(direction: int) -> void:
	_commit_fields()
	var destination := selected + direction
	while destination >= 0 and destination < document.lines.size() and document.lines[destination].strip_edges().is_empty(): destination += direction
	if destination < 0 or destination >= document.lines.size(): return
	document.move_line(selected,destination); selected = destination; _refresh()

func check_document() -> bool:
	_commit_fields()
	var issues := document.validate()
	status.text = "检查通过 · 可保存与试玩" if issues.is_empty() else "\n".join(issues)
	return issues.is_empty()

func save_document() -> void:
	_request_handoff_save(false)

func _request_handoff_save(as_copy: bool) -> void:
	if import_dialog.busy: status.text="素材正在导入，请稍后保存。";return
	if handoff_dialog.visible: handoff_dialog.grab_focus();return
	_commit_fields()
	preview.cancel_drag()
	var protection:=Handoff.protected_target(document.path)
	if not protection.error.is_empty():status.text=protection.error;return
	_handoff_copy=as_copy or protection.protected
	var prepared:=Handoff.defaults(document.text(),document.path,document.disk_hash,_handoff_copy)
	if not prepared.error.is_empty():status.text=prepared.error;return
	handoff_dialog.open(prepared.data,_handoff_copy)

func _handoff_accepted(data: Dictionary) -> void:
	_handoff_pending=data.duplicate(true)
	if document.path.is_empty() or _handoff_copy: _save_picker()
	else: _save_handoff(document.path)

func _save_handoff(target: String) -> void:
	var before:=document.lines.size()
	var error:=document.save_for_handoff(target,_handoff_pending)
	selected+=document.lines.size()-before
	if error.is_empty():
		_handoff_pending.clear();_recovery_payload.clear();recover_button.hide()
		if FileAccess.file_exists(RECOVERY): DirAccess.remove_absolute(ProjectSettings.globalize_path(RECOVERY))
	_refresh()
	status.text="已保存剧情及交接说明 · 待 AI／开发者接入游戏。" if error.is_empty() else error

func _save(target: String) -> void:
	var error := document.save_to(target)
	status.text = "已保存。备份位于 .godot/td_vn_editor/backups。" if error.is_empty() else error
	if error.is_empty():
		_recovery_payload.clear(); recover_button.hide()
		if FileAccess.file_exists(RECOVERY): DirAccess.remove_absolute(ProjectSettings.globalize_path(RECOVERY))
	_refresh()

func _write_recovery() -> void:
	if not document.dirty() and not field_dirty: return
	var copy := document.lines.duplicate()
	if field_dirty and selected < copy.size(): copy[selected] = _edited_line()
	var payload := {"path":document.path,"text":"\n".join(copy),"saved_text":document.saved_text,"disk_hash":document.disk_hash}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(RECOVERY.get_base_dir()))
	var file := FileAccess.open(RECOVERY,FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(payload)); file.close()

func restore_recovery() -> void:
	if _recovery_payload.is_empty(): return
	document.load_text(str(_recovery_payload.text),str(_recovery_payload.path))
	document.saved_text = str(_recovery_payload.saved_text)
	document.disk_hash = str(_recovery_payload.disk_hash)
	selected = 0; field_dirty = false; _refresh()
	status.text = "已恢复未保存草稿。检查后保存；原文件若被他人修改会拒绝覆盖。"

func play_draft() -> void:
	if import_dialog.busy: status.text = "素材正在导入，请稍候。"; return
	if not check_document(): return
	stop_preview()
	var path := "res://.godot/td_vn_editor/previews/" + str(Time.get_ticks_usec()) + "/intro/script.txt"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: status.text = "无法创建试玩草稿。"; return
	file.store_string(document.text()); file.close()
	preview_pid = OS.create_process(OS.get_executable_path(),PackedStringArray(["--path",ProjectSettings.globalize_path("res://"),"--resolution","1280x800",PREVIEW_SCENE,"--","--vn-draft="+path]))
	status.text = "试玩已打开 · 独立窗口，不读写玩家存档。" if preview_pid > 0 else "无法启动试玩窗口。"

func stop_preview() -> void:
	if preview_pid > 0 and OS.is_process_running(preview_pid): OS.kill(preview_pid)
	preview_pid = -1

func _shortcut_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey or not event.pressed or event.echo: return
	if handoff_dialog.visible or file_dialog.visible: return
	if event.ctrl_pressed and event.keycode == KEY_S: save_document(); get_viewport().set_input_as_handled()
	if event.ctrl_pressed and event.keycode in [KEY_ENTER,KEY_KP_ENTER]: play_draft(); get_viewport().set_input_as_handled()
	if event.keycode == KEY_DELETE and page_mode and preview.has_focus() and not selected_actor.is_empty():
		_visual("remove",selected_actor); get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if page_mode and field_dirty and Time.get_ticks_msec() >= edit_deadline:
		_commit_fields()
		path_label.text = "● " + (document.path if not document.path.is_empty() else "新剧本（未保存）")
		if page_cards.has(selected): page_cards[selected].assign_state(document.composition(selected))
		_write_recovery()

func _build_pages() -> void:
	page_cards.clear()
	for child: Node in page_list.get_children(): page_list.remove_child(child); child.queue_free()
	var index := 0
	for page: Dictionary in document.pages():
		index += 1
		var button := Button.new(); button.custom_minimum_size = Vector2(205,148)
		button.toggle_mode = true; button.button_pressed = page.line == selected
		page_list.add_child(button)
		var thumb := Composition.new(); thumb.thumbnail = true; button.add_child(thumb)
		thumb.position = Vector2(5,5); thumb.size = Vector2(195,112)
		thumb.assign_state(document.composition(page.line)); page_cards[page.line] = thumb
		var label := Label.new(); label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.position = Vector2(8,119); label.size = Vector2(188,25)
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var title := str(page.title)
		if page.kind == "dialogue": title = str(Document.describe(document.lines[page.line]).text)
		label.text = "%02d  %s" % [index,title]; button.add_child(label)
		button.pressed.connect(_select_page.bind(page.line))

func _select_page(anchor: int) -> void:
	preview.cancel_drag(); _commit_fields(); selected = anchor; selected_actor = ""; _refresh()

func _undo(redo: bool) -> void:
	preview.cancel_drag(); _commit_fields()
	var ordinal := 0
	var before := document.pages()
	for i in before.size():
		if before[i].line == selected: ordinal = i; break
	if redo: document.redo()
	else: document.undo()
	var after := document.pages()
	if page_mode and not after.is_empty(): selected = after[mini(ordinal,after.size()-1)].line
	_refresh()

func _fill_page_fields() -> void:
	var item := Document.describe(document.lines[selected])
	if item.kind != "dialogue":
		_label({"td_cg":"CG 动画页","td_name":"姓名输入页","end":"剧情结束"}.get(item.kind,"特殊剧情页"))
		_label("背景和人物请在对白页编辑。特殊流程可在高级步骤中查看。")
		return
	_choice("speaker","谁在说话",Document.cast_names(),item.speaker)
	_entry("text","对白",str(item.text).replace("\\n","\n"),true)
	_label("直接输入，画面即时更新。")
	var state := document.composition(selected)
	actor_picker = OptionButton.new(); fields.add_child(actor_picker)
	actor_picker.add_item("本页角色（含画外）"); actor_picker.set_item_metadata(0,"")
	for who: String in state.actors:
		actor_picker.add_item(str(Document.cast_names().get(who,who)))
		actor_picker.set_item_metadata(actor_picker.item_count-1,who)
		if who == selected_actor: actor_picker.select(actor_picker.item_count-1)
	actor_picker.item_selected.connect(func(at: int) -> void: _select_actor(str(actor_picker.get_item_metadata(at))))
	if not state.actors.has(selected_actor):
		_label("点击角色或从上方列表选中。")
		return
	_label("选中：" + ("主角" if selected_actor == "hero" else str(Document.cast_names().get(selected_actor,selected_actor))))
	var expressions := OptionButton.new(); fields.add_child(expressions)
	for expr: String in Document.expressions(selected_actor):
		expressions.add_item(Document.expression_title(selected_actor,expr))
		expressions.set_item_metadata(expressions.item_count-1,expr)
		if expr == state.actors[selected_actor].expression: expressions.select(expressions.item_count-1)
	expressions.item_selected.connect(func(at: int) -> void: _visual("expression",selected_actor,str(expressions.get_item_metadata(at))))
	var row := HBoxContainer.new(); fields.add_child(row)
	_button(row,"缩小",func() -> void: _resize_actor(-.1))
	_button(row,"放大",func() -> void: _resize_actor(.1))
	actor_scale = SpinBox.new(); actor_scale.min_value = TDVNLayout.MIN_SCALE; actor_scale.max_value = TDVNLayout.MAX_SCALE
	actor_scale.step = .05; actor_scale.suffix = "倍"
	actor_scale.value = float(TDVNLayout.parse(state.actors[selected_actor].position).get("scale",1.0))
	fields.add_child(actor_scale)
	actor_scale.value_changed.connect(_set_actor_scale)
	_button(fields,"回到画面",_recenter_actor)
	_button(fields,"移除角色",func() -> void: _visual("remove",selected_actor))

func _select_actor(who: String) -> void:
	_commit_fields(); selected_actor = who; preview.selected_actor = who; preview.queue_redraw(); _fill_fields()

func _resize_actor(delta: float) -> void:
	var state := document.composition(selected)
	if not state.actors.has(selected_actor): return
	var scale_value := float(TDVNLayout.parse(state.actors[selected_actor].position).get("scale",1.0))
	_set_actor_scale(scale_value+delta)

func _set_actor_scale(value: float) -> void:
	var state := document.composition(selected)
	if not state.actors.has(selected_actor): return
	var token: String = state.actors[selected_actor].position
	var bounds := TDVNLayout.rect(token,Document.cast_scale(selected_actor))
	_visual("position",selected_actor,TDVNLayout.encode(bounds.get_center().x/1280,bounds.end.y/800,value))

func _recenter_actor() -> void:
	var state := document.composition(selected)
	if not state.actors.has(selected_actor): return
	var scale_value := float(TDVNLayout.parse(state.actors[selected_actor].position).get("scale",1.0))
	# Centre the whole actor, including enlarged close-ups, without changing its scale.
	_visual("position",selected_actor,TDVNLayout.encode(.5,.5+TDVNLayout.BASE_HEIGHT*scale_value/1600.0,scale_value))

func _visual(kind: String, value: String, extra: String = "") -> void:
	_commit_fields()
	if document.lines.is_empty() or Document.describe(document.lines[selected]).kind != "dialogue":
		status.text = "先选择一张对白页。"; return
	selected = document.set_page_visual(selected,kind,value,extra)
	if kind == "actor": selected_actor = value
	if kind == "remove": selected_actor = ""
	_refresh()

func add_page(copy_dialogue: bool) -> void:
	_commit_fields(); selected = document.new_page(selected,copy_dialogue); selected_actor = ""; _refresh()

func delete_page() -> void:
	_commit_fields()
	var next := document.remove_page(selected)
	if next < 0: status.text = "原有剧情页受保护；如需改流程，请使用高级步骤。"; return
	selected = next; selected_actor = ""; _refresh()

func show_palette(kind: String) -> void:
	_commit_fields()
	if document.lines.is_empty() or Document.describe(document.lines[selected]).kind != "dialogue": status.text = "先选一张对白页，再插入素材。"; return
	for child: Node in palette.get_children():
		if child.name == "AssetGrid": palette.remove_child(child); child.queue_free()
	var grid := GridContainer.new(); grid.name = "AssetGrid"; grid.columns = 2
	palette.add_child(grid)
	var names := Document.cast_names(); names.erase("")
	if kind == "background":
		names = {}
		for id: String in Document.backgrounds(): names[id] = Document.background_title(id)
	palette.title = "选择背景" if kind == "background" else "选择角色"
	for id: String in names:
		var button := Button.new(); button.custom_minimum_size = Vector2(200,130); grid.add_child(button)
		button.tooltip_text = str(names[id])
		var image := TextureRect.new(); image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image.position = Vector2(6,5); image.size = Vector2(188,96)
		image.texture = load(Document.BG_ROOT+id+".tres" if kind == "background" else Document.portrait_path(id,"calm"))
		button.add_child(image)
		var label := Label.new(); label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.position = Vector2(5,102); label.size = Vector2(190,25); label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.text = "主角" if id == "hero" else str(names[id]); button.add_child(label)
		button.pressed.connect(func() -> void: palette.hide(); _visual(kind,id))
	palette.popup_centered(Vector2i(440,470 if kind == "background" else 200))
