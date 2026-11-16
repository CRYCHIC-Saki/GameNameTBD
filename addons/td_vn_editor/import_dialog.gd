@tool
extends ConfirmationDialog
const Importer := preload("res://addons/td_vn_editor/asset_import.gd")
const Document := preload("res://addons/td_vn_editor/document.gd")
signal imported(result: Dictionary, insert: bool)
var importer := Importer.new()
var kind: OptionButton
var character: OptionButton
var title_edit: LineEdit
var preview: TextureRect
var details: Label
var feedback: Label
var choose: Button
var insert: CheckBox
var picker: FileDialog
var source: String = ""
var source_hash: String = ""
var busy: bool = false
var result: Dictionary = {}
var deadline: int = 0
var attempted: bool = false
var close_button: Button

func _ready() -> void:
	title = "导入素材"; dialog_hide_on_ok = false
	get_ok_button().text = "导入"; get_cancel_button().text = "取消"
	var box := VBoxContainer.new(); box.custom_minimum_size.x = 440; box.add_theme_constant_override("separation",10); add_child(box)
	# Editor popup decorations may be hidden. Keep close inside the actual content.
	var header := HBoxContainer.new(); box.add_child(header)
	var heading := Label.new(); heading.text = "导入素材"; heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL; header.add_child(heading)
	close_button = Button.new(); close_button.text = "×"; close_button.tooltip_text = "关闭导入窗口"
	close_button.custom_minimum_size = Vector2(36,32); header.add_child(close_button)
	close_button.pressed.connect(_dismiss)
	window_input.connect(_window_input)
	kind = OptionButton.new(); box.add_child(kind)
	for item: String in ["背景","新角色","角色新表情"]: kind.add_item(item)
	kind.item_selected.connect(func(_index: int) -> void: _kind_changed())
	character = OptionButton.new(); box.add_child(character)
	title_edit = LineEdit.new(); title_edit.placeholder_text = "名称（例如：黄昏港口）"; title_edit.max_length = 60; box.add_child(title_edit)
	choose = Button.new(); choose.text = "选择图片…"; box.add_child(choose)
	choose.pressed.connect(func() -> void: picker.popup_centered_ratio(.7))
	preview = TextureRect.new(); preview.custom_minimum_size = Vector2(440,220)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; box.add_child(preview)
	details = Label.new(); details.custom_minimum_size.x = 440; details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; box.add_child(details)
	insert = CheckBox.new(); insert.text = "导入后插入当前页"; insert.button_pressed = true; box.add_child(insert)
	feedback = Label.new(); feedback.custom_minimum_size.x = 440; feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; box.add_child(feedback)
	picker = FileDialog.new(); picker.title = "选择背景或立绘图片"; picker.access = FileDialog.ACCESS_FILESYSTEM
	picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE; picker.filters = PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp ; 图片"])
	picker.file_selected.connect(select_source); add_child(picker)
	confirmed.connect(_import)
	_kind_changed()

func _dismiss() -> void:
	if busy: return
	picker.hide()
	hide()

func _window_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and not busy:
		_dismiss(); set_input_as_handled()

func open(can_insert: bool) -> void:
	if busy: return
	source = ""; source_hash = ""; preview.texture = null; title_edit.text = ""; feedback.text = ""
	insert.disabled = not can_insert; insert.button_pressed = can_insert
	character.clear()
	for id: String in Document.cast_names():
		if id.is_empty(): continue
		character.add_item("主角" if id == "hero" else str(Document.cast_names()[id]))
		character.set_item_metadata(character.item_count-1,id)
	_kind_changed(); popup_centered(Vector2i(500,550))

func _kind_changed() -> void:
	character.visible = kind.selected == 2
	title_edit.placeholder_text = ["背景名称（例如：黄昏港口）","角色姓名（例如：小李）","表情名称（例如：惊讶）"][kind.selected]
	details.text = "PNG / JPG / WebP · 复制入库，原文件保留。"
	if kind.selected != 0: details.text += "\n建议使用单张透明立绘；不同表情保持相同画布。"

func select_source(value: String) -> void:
	if busy: return
	var inspected := Importer.inspect_image(value)
	if not str(inspected.error).is_empty(): feedback.text = inspected.error; source = ""; source_hash = ""; preview.texture = null; return
	source = value; source_hash = FileAccess.get_sha256(value)
	preview.texture = ImageTexture.create_from_image(inspected.image)
	feedback.text = "%s · %d × %d" % [value.get_file(),inspected.image.get_width(),inspected.image.get_height()]
	if title_edit.text.is_empty() and kind.selected != 2: title_edit.text = value.get_file().get_basename().left(60)

func _set_busy(value: bool) -> void:
	busy = value; get_ok_button().disabled = value; get_cancel_button().disabled = value
	close_button.disabled = value
	close_button.tooltip_text = "正在导入，请等待完成" if value else "关闭导入窗口"
	choose.disabled = value; kind.disabled = value; character.disabled = value; title_edit.editable = not value

func _import() -> void:
	if busy: return
	if source.is_empty(): feedback.text = "请先选择图片。"; return
	if FileAccess.get_sha256(source) != source_hash: feedback.text = "所选图片已改变，请重新选择后确认。"; return
	var target: String = str(character.get_selected_metadata()) if character.selected >= 0 else ""
	var plan := importer.prepare(source,["background","character","expression"][kind.selected],title_edit.text,target)
	if not str(plan.error).is_empty(): feedback.text = plan.error; return
	_set_busy(true)
	result = importer.commit(plan)
	if not str(result.error).is_empty(): feedback.text = result.error; _set_busy(false); return
	feedback.text = "正在导入并登记素材…"
	deadline = Time.get_ticks_msec()+60000; attempted = false
	EditorInterface.get_resource_filesystem().scan()

func _process(_delta: float) -> void:
	if not busy or result.is_empty(): return
	var filesystem := EditorInterface.get_resource_filesystem()
	if Time.get_ticks_msec() >= deadline:
		_fail("导入超时。"); return
	if filesystem.is_scanning() or filesystem.is_importing(): return
	if not FileAccess.file_exists(str(result.image)+".import"): return
	if attempted: return
	attempted = true
	var texture: Texture2D = ResourceLoader.load(result.reference,"",ResourceLoader.CACHE_MODE_REPLACE)
	if texture == null or texture.get_width() < 1 or texture.get_height() < 1:
		_fail("导入图片未能正确加载。"); return
	ResourceLoader.load(Document.CAST_PATH,"",ResourceLoader.CACHE_MODE_REPLACE)
	_set_busy(false); hide()
	imported.emit(result,insert.button_pressed)
	result = {}

func _fail(message: String) -> void:
	var failure := importer.rollback(result.get("applied",[]))
	feedback.text = message+(" 本次修改已撤回，可重试。" if failure.is_empty() else failure)
	ResourceLoader.load(Document.CAST_PATH,"",ResourceLoader.CACHE_MODE_REPLACE)
	result = {}; _set_busy(false); EditorInterface.get_resource_filesystem().scan()
