class_name TDResearchTrialView
extends Control
signal finished(result:TDOutcome)
signal retry_requested(result:TDOutcome)
signal cancelled
signal pause_requested
var session:TDResearchSession
var token:String=""
var recipe_id:String=""
var automated_clock:bool=false
var lesson:TDResearchLesson
var _last_usec:int=0
var _result:TDOutcome
var _paused:bool=false
var _cancel_button:Button
var _continue:Button
var _retry_attempt:Button
var _message:Label
var _retry_save:Button
var _result_panel:Control

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lesson=session.controller; add_child(lesson)
	lesson.pause_requested.connect(func()->void:pause_requested.emit())
	lesson.cancel_requested.connect(_cancel)
	lesson.kitchen.before_input=_sync
	_last_usec=Time.get_ticks_usec()
	_cancel_button=_button("放下研习 · 资格保留",Rect2(1000,48,250,30),_cancel)
	_button("暂停 / 恢复",Rect2(1000,84,250,30),func()->void:pause_requested.emit())
	_message=Label.new(); _message.position=Vector2(260,674); _message.size=Vector2(760,27)
	_message.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;_message.add_theme_font_size_override("font_size",15);add_child(_message)
	_message.text="%s · 烹饪研习 · 80分解锁 · 失败可立即免费重试"%session.catalog.node(recipe_id).name
	_result_panel=Control.new();_result_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(_result_panel);_result_panel.hide()
	_continue=_button("返回图谱",Rect2(518,586,244,52),_return_result);_continue.hide()
	_retry_attempt=_button("立即免费重试",Rect2(654,586,244,52),_retry);_retry_attempt.hide()
	_retry_save=_button("重试保存成绩",Rect2(518,586,244,52),func()->void:set_paused(false));_retry_save.hide()

func _button(text:String,rect:Rect2,action:Callable) -> Button:
	var b:=Button.new();b.text=text;b.position=rect.position;b.size=rect.size;b.pressed.connect(action);add_child(b);return b

func _sync() -> void:
	var now:int=Time.get_ticks_usec();var delta:float=float(now-_last_usec)/1000000.0;_last_usec=now
	if not automated_clock and _result==null and not _paused: session.advance(delta)

func _process(_delta:float) -> void:
	_sync()
	if _result==null and not _paused and session.progress().get("ready_to_finish",false):
		var result:=session.finish(token)
		if result.ok:
			_result=result;_cancel_button.hide();_continue.show();_retry_save.hide()
			_message.text="已保存研习进度 · 研习暂不消耗游戏时间" if result.data.passed else "资格已保留 · 不消耗游戏时间，现在就能再试。"
			if not result.data.passed:
				_continue.position.x=382;_retry_attempt.show()
			_show_result()
		else:
			set_paused(true);_message.text="成绩尚未保存：%s。请处理后重试。"%result.code;_retry_save.show()

func _show_result() -> void:
	_result_panel.show()
	var bg:=ColorRect.new();bg.color=Color("182420");bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);_result_panel.add_child(bg)
	_label("研习成功" if _result.data.passed else "再试一次",Vector2(300,180),42)
	_label("%s   ·   %.1f / 100"%[session.catalog.node(recipe_id).name,float(_result.data.score)],Vector2(200,260),32)
	var names:Dictionary={"M1":"切配","M2":"点火","M3":"翻炒 / 上笼","M4":"控温","M5":"煮制","M6":"调味","M7":"出锅"}
	var lines:Array[String]=[]
	for id:String in _result.data.modules:
		lines.append("%s  %.0f%%"%[names.get(id,id),float(_result.data.modules[id].quality)*100])
	_label("  ·  ".join(lines),Vector2(80,370),19)
	_label("已收录菜谱，可在厨房制作" if _result.data.passed else "按厨房提示操作，80分即可学会",Vector2(200,460),22)
	move_child(_message,get_child_count()-1)

func _label(text:String,at:Vector2,font_size:int) -> void:
	var label:=Label.new();label.text=text;label.position=at;label.size=Vector2(1280-at.x*2,80)
	label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size",font_size);_result_panel.add_child(label)

func set_paused(value:bool) -> void:
	_paused=value;session.set_paused(value);_last_usec=Time.get_ticks_usec()

func _input(event:InputEvent) -> void:
	if _result!=null and event.is_action_pressed("pause") and not event.is_echo():
		pause_requested.emit();get_viewport().set_input_as_handled()

func _cancel() -> void:
	session.cancel(token);cancelled.emit()

func _return_result() -> void:
	if _result!=null: finished.emit(_result)

func _retry() -> void:
	if _result==null or _result.data.passed or _retry_attempt.disabled: return
	_retry_attempt.disabled=true
	retry_requested.emit(_result)

func _exit_tree() -> void:
	if _result==null and session!=null: session.cancel(token)
