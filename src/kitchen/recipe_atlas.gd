class_name TDRecipeAtlas
extends Control
signal back_requested
signal pause_requested
signal result_ready(result:TDOutcome)
var session:TDResearchSession
var begin_handler:Callable
var recovery_handler:Callable
var active_cuisine:String="cn"
var selected_id:String="C02"
var canvas:TDRecipeTreeCanvas
var trial:TDResearchTrialView
var _tree_scroll:ScrollContainer
var _detail:VBoxContainer
var _wallet:Label
var _heading:Label
var _subtitle:Label
var _notice:Label
var _tabs:Dictionary={}
var _zoom:float=.94
var _shell:Control
var _lock_icon:Texture2D
const GOLD:=Color("d3b477")
const INK:=Color("36392d")

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS; set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var lock_image:=Image.new()
	lock_image.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24"><path d="M7 10V7a5 5 0 0 1 10 0v3" fill="none" stroke="#c6c2a5" stroke-width="2"/><rect x="4" y="10" width="16" height="12" rx="2" fill="#c6c2a5"/><circle cx="12" cy="15" r="2" fill="#263027"/><path d="M12 15v4" stroke="#263027" stroke-width="2"/></svg>')
	_lock_icon=ImageTexture.create_from_image(lock_image)
	_shell=Control.new(); _shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(_shell)
	var bg:=ColorRect.new(); bg.color=Color("151c19"); bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); bg.mouse_filter=Control.MOUSE_FILTER_IGNORE; _shell.add_child(bg)
	_label(_shell,"小 镇 食 堂",Rect2(28,22,238,36),28,GOLD)
	_label(_shell,"TOWN DINER  /  RECIPE ATLAS",Rect2(28,61,300,18),10,Color("99a08a"))
	_label(_shell,"菜 谱 研 习",Rect2(320,32,270,32),23,Color("e4d9bc"))
	_wallet=_label(_shell,"",Rect2(850,30,215,40),24,GOLD)
	_button(_shell,"返回 B",Rect2(1148,25,98,43),func()->void:back_requested.emit())
	_label(_shell,"料 理 卷 宗",Rect2(28,111,150,24),13,Color("99a08a"))
	for i:int in session.catalog.data.cuisines.size():
		var c:Dictionary=session.catalog.data.cuisines[i]
		var tab:=_button(_shell,"%s   %s"%[c.seal,c.name],Rect2(25,152+i*83,158,67),func()->void:switch_cuisine(c.id))
		tab.add_theme_font_size_override("font_size",14); _tabs[c.id]=tab
	_label(_shell,"一火一味\n循谱而行",Rect2(35,626,132,70),19,Color("99a08a"))
	_heading=_label(_shell,"",Rect2(209,108,680,39),28,Color("e4d9bc"))
	_subtitle=_label(_shell,"",Rect2(209,151,680,31),13,Color("99a08a"))
	var search:=LineEdit.new(); search.placeholder_text="搜索菜名 / 食材 / 编号"; search.position=Vector2(209,193); search.size=Vector2(310,34); search.text_changed.connect(func(q:String)->void:canvas.query=q;canvas.queue_redraw()); _shell.add_child(search)
	_button(_shell,"−",Rect2(662,193,34,34),func()->void:set_zoom(_zoom-.1))
	_button(_shell,"+",Rect2(704,193,34,34),func()->void:set_zoom(_zoom+.1))
	_button(_shell,"定位当前",Rect2(754,193,129,34),reveal_selection)
	_tree_scroll=ScrollContainer.new(); _tree_scroll.position=Vector2(204,241); _tree_scroll.size=Vector2(696,471); _shell.add_child(_tree_scroll)
	canvas=TDRecipeTreeCanvas.new(); canvas.session=session; canvas.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	canvas.selected.connect(select_recipe); _tree_scroll.add_child(canvas)
	var paper:=PanelContainer.new(); paper.position=Vector2(926,108); paper.size=Vector2(328,608)
	var style:=StyleBoxFlat.new(); style.bg_color=Color("e9dfc4"); style.border_color=Color("b9ad86"); style.set_border_width_all(2); style.content_margin_left=21; style.content_margin_right=21; style.content_margin_top=20; style.content_margin_bottom=20
	paper.add_theme_stylebox_override("panel",style); _shell.add_child(paper)
	var ds:=ScrollContainer.new(); ds.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; paper.add_child(ds)
	_detail=VBoxContainer.new(); _detail.size_flags_horizontal=Control.SIZE_EXPAND_FILL; _detail.add_theme_constant_override("separation",11); ds.add_child(_detail)
	_label(_shell,"金线：当前菜谱的前置   绿线：已掌握关系   · 全部前置均需掌握",Rect2(209,723,690,26),12,Color("99a08a"))
	_notice=_label(_shell,"",Rect2(28,765,1220,28),13,GOLD)
	session.changed.connect(_refresh)
	_refresh()

func _label(parent:Node,text:String,rect:Rect2,font_size:int,color:Color) -> Label:
	var l:=Label.new(); l.text=text; l.position=rect.position;l.size=rect.size;l.add_theme_font_size_override("font_size",font_size);l.add_theme_color_override("font_color",color);parent.add_child(l);return l

func _button(parent:Node,text:String,rect:Rect2,action:Callable) -> Button:
	var b:=Button.new();b.text=text;b.position=rect.position;b.size=rect.size;b.pressed.connect(action)
	for state:String in ["normal","hover","pressed","focus"]:
		var style:=StyleBoxFlat.new();style.bg_color=Color("273426") if state=="normal" else Color("3b4931");style.border_color=Color("657153");style.set_border_width_all(1);style.content_margin_left=10;style.content_margin_right=10;style.content_margin_top=9;style.content_margin_bottom=9;b.add_theme_stylebox_override(state,style)
	b.add_theme_color_override("font_color",Color("e4d9bc"));b.add_theme_font_size_override("font_size",15);parent.add_child(b);return b

func _detail_label(text:String,size:int=16,color:Color=INK) -> Label:
	var l:=Label.new();l.text=text;l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;l.add_theme_font_size_override("font_size",size);l.add_theme_color_override("font_color",color);_detail.add_child(l);return l

func _refresh() -> void:
	if not is_instance_valid(canvas): return
	var state:=session.snapshot();_wallet.text="✦  %02d  灵感"%int(state.points)
	for c:Dictionary in session.catalog.data.cuisines:
		if c.id==active_cuisine: _heading.text=c.name;_subtitle.text=c.desc
		var unlocked:bool=c.id in state.cuisines
		_tabs[c.id].disabled=not unlocked
		_tabs[c.id].icon=null if unlocked else _lock_icon
		_tabs[c.id].text=(str(c.seal)+"   " if unlocked else "")+str(c.name)
		_tabs[c.id].tooltip_text="等待剧情推荐，尚未开放" if not unlocked else ""
		_tabs[c.id].modulate=Color.WHITE if c.id==active_cuisine else Color(.7,.75,.65)
	canvas.cuisine=active_cuisine;canvas.selection=selected_id;canvas.zoom=_zoom;canvas.rebuild()
	for child:Node in _detail.get_children(): _detail.remove_child(child);child.queue_free()
	var r:=session.catalog.node(selected_id);var status:=session.status(selected_id)
	_detail_label("RECIPE  /  %s     ·     TIER %d"%[selected_id,int(r.tier)],11,Color("797c63"))
	_detail_label(r.name,28)
	_detail_label(r.flavor,13,Color("797c63"))
	var icon:=TextureRect.new();icon.texture=load("res://assets/kitchen/recipe-icons/%s.png"%selected_id);icon.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;icon.custom_minimum_size=Vector2(250,118);icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;_detail.add_child(icon)
	_detail_label(r.description,16)
	_detail_label("食材线索",12,Color("797c63"));_detail_label(r.ingredients,15)
	_detail_label("做法与解锁",12,Color("797c63"))
	for line: String in TDPrepGuide.recipe_lines(session, selected_id):
		_detail_label(line,14)
	_detail_label("研习资格     %d 灵感"%int(r.cost),19)
	_detail_label("前置菜谱 · ALL",12,Color("797c63"))
	if r.prerequisites.is_empty(): _detail_label("入门菜谱，无需前置。",14)
	for parent:String in r.prerequisites:
		_button(_detail,("✓ " if session.has(parent) else "◇ ")+String(session.catalog.node(parent).name)+" →",Rect2(),func()->void:select_recipe(parent);reveal_selection())
	var descriptions:Dictionary={"UNLOCKED":"已掌握 · 已收录菜谱","STORY_LOCKED":"等待剧情推荐此菜系","PREREQUISITES":"请先掌握全部前置菜谱","CHART_PENDING":"研习谱面尚未开放","POINTS_SHORT":"灵感不足","AVAILABLE":"投入灵感 · 开始研习","RESEARCHABLE":"开始研习 · 免费重试"}
	var begin:=_button(_detail,descriptions.get(status,status),Rect2(),start_selected)
	begin.disabled=status not in ["AVAILABLE","RESEARCHABLE"] or session.load_error!=""
	_detail_label("80分解锁 · 失败立即免费重试\n研习暂不消耗游戏时间",13,Color("6d705c"))
	if status=="CHART_PENDING": _detail_label("本次可体验：阳春面、蒸水蛋。此节点暂不扣灵感。",13)
	if state.best.has(selected_id): _detail_label("最佳成绩  %.1f"%float(state.best[selected_id]),16)
	var offset:=HSlider.new();offset.min_value=-200;offset.max_value=200;offset.step=5;offset.value=float(state.input_offset_sec)*1000;offset.custom_minimum_size.y=24
	_detail_label("判定校准 %d ms（正值延后）"%int(offset.value),12,Color("6d705c"));_detail.add_child(offset)
	offset.drag_ended.connect(func(changed_value:bool)->void:if changed_value: session.calibrate(offset.value/1000.0))
	if session.load_error!="":
		_notice.text="进度读取失败：%s，已保留原文件，暂停研习写入。"%session.load_error
		if recovery_handler.is_valid():
			_button(_detail,"恢复校验有效的备份",Rect2(),func()->void:_recover(false))
			_button(_detail,"恢复校验有效的临时文件",Rect2(),func()->void:_recover(true))
	else: _notice.text="永久研习资格 · 每菜每日首次80分可获1灵感 · 原型谱与图标，实际手感待试玩"

func select_recipe(id:String) -> void:
	if session.catalog.node(id).is_empty(): return
	if session.catalog.node(id).cuisine_id not in session.snapshot().cuisines: return
	selected_id=id;active_cuisine=session.catalog.node(id).cuisine_id;_refresh()

func switch_cuisine(id:String) -> void:
	if id not in session.snapshot().cuisines: return
	active_cuisine=id
	for r:Dictionary in session.catalog.data.recipes:
		if r.cuisine_id==id: selected_id=r.id;break
	_refresh();_tree_scroll.scroll_vertical=0

func set_zoom(value:float) -> void:
	_zoom=clampf(value,.7,1.3);canvas.zoom=_zoom;canvas.rebuild();reveal_selection()

func reveal_selection() -> void:
	if canvas.positions.has(selected_id): _tree_scroll.scroll_vertical=maxi(0,int(canvas.positions[selected_id].y*_zoom-_tree_scroll.size.y+148))

func start_selected() -> void:
	if trial!=null: return
	if get_tree().paused: _notice.text="已暂停 · 按 Esc 恢复后再开始研习";return
	if session.load_error!="": _refresh();return
	var result:TDOutcome=begin_handler.call(selected_id) if begin_handler.is_valid() else session.begin(selected_id)
	if not result.ok:
		_notice.text="暂不能研习："+(result.message if not result.message.is_empty() else {"SHOP_OPEN":"营业中只能查看，请打烊后研习"}.get(result.code,result.code));return
	trial=TDResearchTrialView.new();trial.session=session;trial.token=result.data.token;trial.recipe_id=selected_id
	trial.pause_requested.connect(func()->void:pause_requested.emit());trial.cancelled.connect(_end_trial);trial.finished.connect(_finished)
	trial.retry_requested.connect(_retry_trial)
	_shell.hide();add_child(trial)

func _retry_trial(result:TDOutcome) -> void:
	_finished(result)
	start_selected()

func _finished(result:TDOutcome) -> void:
	result_ready.emit(result);_end_trial()

func _end_trial() -> void:
	if trial!=null:
		trial.cancelled.disconnect(_end_trial);trial.finished.disconnect(_finished);trial.retry_requested.disconnect(_retry_trial)
		remove_child(trial);trial.queue_free();trial=null
	_shell.show();_refresh()

func set_paused(value:bool) -> void:
	if trial!=null: trial.set_paused(value)
	elif value: _notice.text="已暂停 · 按 Esc 恢复"
	else: _refresh()

func _recover(temporary:bool) -> void:
	var result:TDOutcome=recovery_handler.call(temporary);_refresh()
	if not result.ok: _notice.text="恢复失败："+result.code

func close() -> void:
	if trial!=null: session.cancel(trial.token)
