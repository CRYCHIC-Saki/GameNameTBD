class_name TDGameHUD
extends Control
## Read-only status and intent buttons. The shell owns input, pause and navigation.
signal action_requested(id: String)

const ACTIONS: Array[Dictionary]=[
	{"id":"employees","name":"雇员","key":"H"},{"id":"recipes","name":"菜谱","key":"B"},
	{"id":"quests","name":"任务","key":"J"},{"id":"map","name":"地图","key":"M"},
	{"id":"branches","name":"店铺","key":"G"},{"id":"suppliers","name":"供应商","key":"U"},
	{"id":"relationships","name":"关系","key":"N"}]
const PAPER:=Color("30251b")
const GOLD:=Color("764019")
const JADE:=Color("30251b")
const MUTED:=Color("65503a")
var buttons: Dictionary={}
var values: Dictionary={}
var _tiles: Dictionary={}
var _status: HBoxContainer
var _actions: HBoxContainer
var _toast: Label
var _enabled: bool=true

class IconButton extends Button:
	var action_id: String=""
	var caption: String=""
	var key_hint: String=""
	func _draw() -> void:
		var ink:=TDGameHUD.PAPER if not disabled else TDGameHUD.MUTED.darkened(.35)
		TDGameHUD.draw_icon(self,action_id,Rect2(size.x*.5-12,7,24,24),ink)
		var font:=get_theme_font("font")
		draw_string(font,Vector2(0,58),caption,HORIZONTAL_ALIGNMENT_CENTER,size.x,TDUI.FONT_CAPTION,ink)
		var key_box:=Rect2(size.x-22,5,17,19)
		draw_rect(key_box,Color("d6ad72"))
		draw_string(font,key_box.position+Vector2(0,16),key_hint,HORIZONTAL_ALIGNMENT_CENTER,17,TDUI.FONT_MICRO,TDGameHUD.PAPER)

class StatTile extends Control:
	var stat_id: String=""
	var caption: String=""
	var value: String=""
	func _draw() -> void:
		var font:=get_theme_font("font")
		TDUI.paint_wood(self,Rect2(Vector2.ZERO,size),TDUI.Surface.CARD)
		draw_line(Vector2(0,0),Vector2(size.x,0),Color("9c8860"),2)
		draw_string(font,Vector2(8,25),caption,HORIZONTAL_ALIGNMENT_LEFT,size.x-12,TDUI.FONT_CAPTION,TDGameHUD.MUTED)
		TDGameHUD.draw_icon(self,stat_id,Rect2(7,36,20,20),TDGameHUD.GOLD if stat_id=="money" else TDGameHUD.JADE)
		draw_string(font,Vector2(32,56),value,HORIZONTAL_ALIGNMENT_LEFT,size.x-36,TDUI.FONT_BODY,TDGameHUD.PAPER)

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE;process_mode=Node.PROCESS_MODE_ALWAYS
	theme=TDUI.theme();_build();set_values(values)
	get_viewport().size_changed.connect(_layout)
	_layout()

func _build() -> void:
	_status=HBoxContainer.new();_status.add_theme_constant_override("separation",4);_status.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(_status)
	var specs: Array=[
		["day","日期",78.0],["time","时间",96.0],["level","等级",70.0],
		["money","金币",126.0],["popularity","人气",82.0],["awareness","店名气",82.0]]
	for spec: Array in specs:
		var tile:=StatTile.new();tile.stat_id=spec[0];tile.caption=spec[1]
		tile.name="Stat_"+str(spec[0]);tile.custom_minimum_size=Vector2(spec[2],68)
		tile.mouse_filter=Control.MOUSE_FILTER_IGNORE;_status.add_child(tile);_tiles[spec[0]]=tile
	_actions=HBoxContainer.new();_actions.add_theme_constant_override("separation",5);add_child(_actions)
	for action: Dictionary in ACTIONS:
		var button:=IconButton.new();button.name="Action_"+str(action.id)
		button.action_id=action.id;button.caption=action.name;button.key_hint=action.key
		button.custom_minimum_size=Vector2(72,68);button.focus_mode=Control.FOCUS_NONE
		button.tooltip_text="%s  [%s]"%[action.name,action.key]
		button.disabled=not _enabled
		for state: String in ["normal","hover","pressed","disabled"]:
			button.add_theme_stylebox_override(state,TDUI.wood(TDUI.Surface.SELECTED if state in ["hover","pressed"] else TDUI.Surface.CARD,4))
		button.pressed.connect(_request.bind(str(action.id)))
		_actions.add_child(button);buttons[action.id]=button
	_toast=TDUI.label("",TDUI.FONT_CAPTION,GOLD);_toast.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_toast.clip_text=true;_toast.autowrap_mode=TextServer.AUTOWRAP_OFF;add_child(_toast)

func _layout() -> void:
	if _actions==null: return
	var width: float=get_viewport_rect().size.x
	_status.position=Vector2(14,12);_status.size=Vector2(554,68)
	_actions.position=Vector2(maxf(576,width-548),12);_actions.size=Vector2(534,68)
	_toast.position=Vector2(18,85);_toast.size=Vector2(maxf(500,width-36),28)

func _request(id: String) -> void:
	if _enabled: action_requested.emit(id)

func set_menu_enabled(value: bool) -> void:
	_enabled=value
	for button: Button in buttons.values(): button.disabled=not value;button.queue_redraw()

func button_for(id: String) -> Button:
	return buttons.get(id) as Button

func set_toast(value: String) -> void:
	if _toast!=null: _toast.text=value;_toast.visible=not value.is_empty()

func update_profile(profile: TDGameProfile, current: Dictionary={}) -> void:
	if profile==null or profile.shop==null: return
	var state: Dictionary=profile.shop.snapshot() if current.is_empty() else current
	set_values({"day":str(state.day),"time":profile.characters.clock.label(),"level":str(profile.progression.progress().level),
		"money":money_text(int(state.money_cents)),"popularity":str(roundi(float(state.popularity))),
		"awareness":str(roundi(float(profile.commerce.state.awareness)*100.0))})
	if _tiles.has("money"): (_tiles.money as Control).tooltip_text="金币 %.2f"%(float(state.money_cents)/100.0)

func set_values(next: Dictionary) -> void:
	values=next.duplicate(true)
	for id: String in _tiles:
		var tile: StatTile=_tiles[id];var text: String=str(values.get(id,"—"))
		if tile.value!=text: tile.value=text;tile.queue_redraw()

static func money_text(cents: int) -> String:
	var amount: float=float(cents)/100.0
	if absf(amount)>=100000000.0: return "%.2f亿"%(amount/100000000.0)
	if absf(amount)>=1000000.0: return "%.2f万"%(amount/10000.0)
	return "%.2f"%amount

static func draw_icon(canvas: CanvasItem, id: String, rect: Rect2, ink: Color) -> void:
	# Deliberately drawn silhouettes: no emoji font or external raster dependency.
	canvas.draw_set_transform(rect.position,0,rect.size/Vector2(24,24))
	match id:
		"employees":
			canvas.draw_rect(Rect2(8,3,8,7),ink);canvas.draw_rect(Rect2(5,12,14,9),ink)
			canvas.draw_rect(Rect2(2,6,4,5),ink.darkened(.3));canvas.draw_rect(Rect2(18,6,4,5),ink.darkened(.3))
		"recipes":
			canvas.draw_rect(Rect2(3,3,8,18),ink);canvas.draw_rect(Rect2(13,3,8,18),ink)
			for y: int in [7,11,15]: canvas.draw_line(Vector2(5,y),Vector2(9,y),Color("e9c28b"),1);canvas.draw_line(Vector2(15,y),Vector2(19,y),Color("e9c28b"),1)
		"quests":
			canvas.draw_rect(Rect2(5,3,14,19),ink);canvas.draw_rect(Rect2(9,1,6,4),ink.darkened(.3))
			for y: int in [8,12,16]: canvas.draw_rect(Rect2(8,y,2,2),Color("e9c28b"));canvas.draw_line(Vector2(12,y+1),Vector2(16,y+1),Color("e9c28b"),1)
		"map":
			canvas.draw_polyline(PackedVector2Array([Vector2(2,5),Vector2(8,2),Vector2(16,5),Vector2(22,2),Vector2(22,19),Vector2(16,22),Vector2(8,19),Vector2(2,22),Vector2(2,5)]),ink,2)
			canvas.draw_line(Vector2(8,3),Vector2(8,19),ink,1);canvas.draw_line(Vector2(16,5),Vector2(16,21),ink,1)
		"branches":
			canvas.draw_rect(Rect2(4,9,16,12),ink);canvas.draw_rect(Rect2(9,14,6,7),Color("e9c28b"))
			canvas.draw_colored_polygon(PackedVector2Array([Vector2(1,9),Vector2(7,3),Vector2(17,3),Vector2(23,9)]),ink)
			canvas.draw_line(Vector2(3,11),Vector2(21,11),Color("e9c28b"),2)
		"suppliers":
			canvas.draw_rect(Rect2(3,8,18,13),ink);canvas.draw_rect(Rect2(2,5,20,4),ink.lightened(.15))
			canvas.draw_line(Vector2(8,10),Vector2(8,19),Color("e9c28b"),2);canvas.draw_line(Vector2(16,10),Vector2(16,19),Color("e9c28b"),2)
		"relationships":
			canvas.draw_colored_polygon(PackedVector2Array([Vector2(2,6),Vector2(6,3),Vector2(12,7),Vector2(18,3),Vector2(22,6),Vector2(22,12),Vector2(12,22),Vector2(2,12)]),ink)
		"money":
			canvas.draw_rect(Rect2(5,2,14,20),ink);canvas.draw_rect(Rect2(2,5,20,14),ink)
			canvas.draw_rect(Rect2(9,8,6,8),Color("e9c28b"));canvas.draw_line(Vector2(5,5),Vector2(17,5),ink.lightened(.25),2)
		"popularity":
			canvas.draw_rect(Rect2(9,2,6,6),ink);canvas.draw_rect(Rect2(7,10,10,12),ink)
			canvas.draw_rect(Rect2(1,7,4,5),ink);canvas.draw_rect(Rect2(19,7,4,5),ink)
			canvas.draw_rect(Rect2(0,14,5,7),ink);canvas.draw_rect(Rect2(19,14,5,7),ink)
		"awareness":
			canvas.draw_colored_polygon(PackedVector2Array([Vector2(3,9),Vector2(10,9),Vector2(20,3),Vector2(20,19),Vector2(10,14),Vector2(3,14)]),ink)
			canvas.draw_line(Vector2(8,15),Vector2(10,22),ink,3)
		"time":
			canvas.draw_circle(Vector2(12,12),10,ink,false,2);canvas.draw_line(Vector2(12,5),Vector2(12,12),ink,2);canvas.draw_line(Vector2(12,12),Vector2(17,15),ink,2)
		"day":
			canvas.draw_rect(Rect2(3,5,18,17),ink,false,2);canvas.draw_line(Vector2(3,10),Vector2(21,10),ink,2)
			canvas.draw_line(Vector2(7,2),Vector2(7,7),ink,2);canvas.draw_line(Vector2(17,2),Vector2(17,7),ink,2)
			canvas.draw_rect(Rect2(7,14,4,4),ink)
		"level":
			canvas.draw_colored_polygon(PackedVector2Array([Vector2(12,1),Vector2(22,12),Vector2(12,23),Vector2(2,12)]),ink)
			canvas.draw_polyline(PackedVector2Array([Vector2(8,14),Vector2(12,9),Vector2(16,14)]),Color("e9c28b"),2)
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
