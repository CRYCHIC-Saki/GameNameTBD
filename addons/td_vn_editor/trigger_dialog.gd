@tool
extends ConfirmationDialog
const Store := preload("res://addons/td_vn_editor/trigger_store.gd")
signal registered
var store := Store.new()
var row: Dictionary = {}
var content_hash: String = ""
var heading: LineEdit
var enabled: CheckBox
var kind: OptionButton
var target: OptionButton
var prerequisite: OptionButton
var milestone: OptionButton
var repeat: OptionButton
var effect: OptionButton
var reward: OptionButton
var feedback: Label

func _ready() -> void:
	title = "游戏触发"; dialog_hide_on_ok = false
	get_ok_button().text = "保存触发"; get_cancel_button().text = "取消"
	var scroll := ScrollContainer.new(); scroll.custom_minimum_size = Vector2(600,525); add_child(scroll)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var box := VBoxContainer.new(); box.custom_minimum_size.x = 570; box.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.add_child(box)
	var top := HBoxContainer.new(); box.add_child(top)
	var title_label := Label.new(); title_label.text = "这段演出在游戏里何时播放？"; title_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL; top.add_child(title_label)
	var close := Button.new(); close.text="×"; top.add_child(close); close.pressed.connect(hide)
	heading = LineEdit.new(); label(box,"演出名称"); box.add_child(heading)
	enabled = CheckBox.new(); enabled.text="在游戏中启用"; box.add_child(enabled)
	kind = option(box,"触发方式",{"person":"与人物交互","place":"进入地点","milestone":"到达任务节点"})
	target = option(box,"触发对象",TDStoryEvents.PEOPLE)
	prerequisite = option(box,"前置演出",{"":"不要求"})
	milestone = option(box,"前置任务",{"":"不要求"}.merged(TDStoryEvents.MILESTONES))
	repeat = option(box,"播放次数",{"once":"每个存档一次","repeat":"再次交互或进入时可重播"})
	effect = option(box,"完成后",{"none":"记录完成，允许后续演出触发","cuisine":"开放菜系（菜谱仍需研习）","route":"开放商路（在筹备或日结时播放）"})
	reward = option(box,"开放目标",{})
	feedback = Label.new(); feedback.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; feedback.custom_minimum_size.x=570; box.add_child(feedback)
	kind.item_selected.connect(func(_i:int)->void:
		fill(target,{"person":TDStoryEvents.PEOPLE,"place":TDStoryEvents.PLACES,"milestone":TDStoryEvents.MILESTONES}[value(kind)])
		repeat.disabled=value(kind)=="milestone"
		if repeat.disabled:select_value(repeat,"once"))
	effect.item_selected.connect(func(_i:int)->void: update_effect())
	confirmed.connect(save_rule)
	window_input.connect(func(event: InputEvent)->void:
		if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE: hide(); set_input_as_handled())

func label(box:Node,text:String) -> void:
	var item:=Label.new();item.text=text;box.add_child(item)

func option(box:Node,title_text:String,values:Dictionary) -> OptionButton:
	label(box,title_text);var item:=OptionButton.new();box.add_child(item);fill(item,values);return item

func fill(item:OptionButton,values:Dictionary,chosen:String="") -> void:
	item.clear()
	for id:String in values:
		item.add_item(values[id]);item.set_item_metadata(item.item_count-1,id)
		if id==chosen:item.select(item.item_count-1)

func value(item:OptionButton) -> String:
	return str(item.get_selected_metadata()) if item.selected>=0 else ""

func select_value(item:OptionButton,chosen:String) -> void:
	for i:int in item.item_count:
		if str(item.get_item_metadata(i))==chosen:item.select(i);return

func update_effect() -> void:
	fill(reward,{"none":{},"cuisine":TDStoryEvents.CUISINES,"route":TDStoryEvents.TOWNS}[value(effect)])
	reward.disabled=value(effect)=="none"

func open_script(path:String) -> void:
	var loaded:=store.read();content_hash=loaded.hash
	row={"id":"event_"+path.sha256_text().left(16),"title":path.get_file().get_basename(),"script_path":path,"enabled":true,"type":"person","target":"aling","requires":"","milestone_required":"","repeat":false,"effect":{"kind":"none","target":""}}
	if loaded.error.is_empty():
		for existing:Dictionary in loaded.data.events:
			if existing.script_path==path:row=existing.duplicate(true)
	heading.text=row.title;enabled.button_pressed=row.enabled
	select_value(kind,row.type);fill(target,{"person":TDStoryEvents.PEOPLE,"place":TDStoryEvents.PLACES,"milestone":TDStoryEvents.MILESTONES}[row.type],row.target)
	var parents:={"":"不要求"}
	if loaded.error.is_empty():
		for existing:Dictionary in loaded.data.events:
			if existing.id!=row.id:parents[existing.id]=existing.title
	fill(prerequisite,parents,row.requires);select_value(milestone,row.milestone_required)
	select_value(repeat,"repeat" if row.repeat else "once");select_value(effect,row.effect.kind);update_effect();select_value(reward,row.effect.target)
	repeat.disabled=row.type=="milestone"
	feedback.text=loaded.error if not loaded.error.is_empty() else "原有教学优先；剧情结束仅更新当前存档内存。保存游戏后才保留进度。"
	get_ok_button().disabled=not loaded.error.is_empty()
	popup_centered(Vector2i(630,610))

func save_rule() -> void:
	row.title=heading.text.strip_edges();row.enabled=enabled.button_pressed
	row.type=value(kind);row.target=value(target);row.requires=value(prerequisite);row.milestone_required=value(milestone)
	row.repeat=value(repeat)=="repeat";row.effect={"kind":value(effect),"target":value(reward)}
	var error:=store.save(row,content_hash)
	if not error.is_empty():feedback.text=error;return
	hide();registered.emit()
