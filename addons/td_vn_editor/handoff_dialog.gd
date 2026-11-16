@tool
extends ConfirmationDialog
const Handoff := preload("res://addons/td_vn_editor/handoff.gd")
signal accepted(data: Dictionary)
var fields: Dictionary = {}
var info: Label
var error_label: Label
var data: Dictionary = {}

func _ready() -> void:
	title="保存剧情 · 交接说明";dialog_hide_on_ok=false
	get_ok_button().text="保存剧情";get_cancel_button().text="取消保存"
	var box:=VBoxContainer.new();box.custom_minimum_size.x=570;box.add_theme_constant_override("separation",7);add_child(box)
	var header:=HBoxContainer.new();box.add_child(header)
	var heading:=Label.new();heading.text="告诉接入者：这段剧情放在哪里？";heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL;header.add_child(heading)
	var close:=Button.new();close.text="×";close.custom_minimum_size=Vector2(36,32);header.add_child(close);close.pressed.connect(hide)
	info=Label.new();info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;info.custom_minimum_size.x=570;box.add_child(info)
	add_field(box,"title","剧情名称","例如：老陈赠送食材")
	add_field(box,"section","所属章节／段落","例如：第一章 · 第一次做番茄炒蛋之前")
	add_field(box,"placement","具体插入位置","例如：阿铃带玩家到老陈家后播放；结束后交还操作，让玩家去冰箱取料。",true)
	add_field(box,"notes","补充备注（可不填）","例如：这是替换原赠料对话的一版；赠送食材仍由游戏逻辑处理。",true)
	error_label=Label.new();error_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;error_label.custom_minimum_size.x=570;box.add_child(error_label)
	confirmed.connect(submit)
	window_input.connect(func(event:InputEvent)->void:
		if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:hide();set_input_as_handled())

func add_field(box:Node,key:String,caption:String,placeholder:String,multiline:bool=false) -> void:
	var label:=Label.new();label.text=caption;box.add_child(label)
	var edit:Control
	if multiline:
		var area:=TextEdit.new();area.placeholder_text=placeholder;area.custom_minimum_size=Vector2(570,90);area.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY;edit=area
	else:
		var line:=LineEdit.new();line.placeholder_text=placeholder;line.max_length=80 if key=="title" else 200;edit=line
	fields[key]=edit;box.add_child(edit)

func open(data_value:Dictionary,save_copy:bool) -> void:
	data=data_value.duplicate(true)
	for key:String in fields: fields[key].text=str(data[key])
	info.text="写中文说明即可；后续由 AI 或开发者接入游戏。"
	if save_copy:info.text+="\n这次会另存为待接入副本，原剧情保留。"
	error_label.text="所属段落和插入位置至少填一项；尚未决定可写“待定”。"
	popup_centered(Vector2i(610,600))

func submit() -> void:
	var next:=data.duplicate(true)
	for key:String in fields:next[key]=str(fields[key].text).strip_edges()
	var error:=Handoff.validate(next)
	if not error.is_empty():error_label.text=error;return
	hide();accepted.emit(next)
