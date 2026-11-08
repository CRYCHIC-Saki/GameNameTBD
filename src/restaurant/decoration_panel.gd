class_name TDDecorationPanel
extends PanelContainer

signal item_chosen(id: String, finish: bool)
signal category_changed
signal done

const CATEGORIES: Array[String]=["地面","墙壁","陈设","餐桌","座椅","服务台"]
const PANEL_HEIGHT: float=288.0
const GROUPS: Dictionary={"陈设":["screen","kiosk"],"餐桌":["dining_table","hotpot_table"],"座椅":["waiting_seat","booth","sofa","stool","child_seat"],"服务台":["welcome_desk","cashier","order_counter"]}
var catalog: TDRestaurantCatalog
var category: String="餐桌"
var culture: String="chinese"
var tier: String="low"
var selected: String=""
var _cards: HBoxContainer
var _tabs: Array[Button]=[]
var _info: Label

class Card extends Button:
	var piece: Dictionary={}
	var finish: String=""
	var details: String=""
	func _draw() -> void:
		if not piece.is_empty():
			var rect:=TDFurnitureModel.bounds(piece)
			var scale_value: float=minf(130/rect.size.x,82/rect.size.y)
			draw_set_transform(Vector2(size.x*.5,92),0,Vector2.ONE*scale_value)
			TDFurnitureModel.draw_model(self,piece)
			draw_set_transform_matrix(Transform2D.IDENTITY)
		else:
			var c:=TDRestaurantArt.finish_color(finish)
			draw_rect(Rect2(25,14,size.x-50,70),c)
			for x in range(4): draw_line(Vector2(25+x*28,14),Vector2(25+x*28,84),c.darkened(.24),2)
			for y in range(3): draw_line(Vector2(25,14+y*23),Vector2(size.x-25,14+y*23),c.darkened(.24),2)
		var font:=get_theme_font("font")
		var lines:=details.split("\n")
		for index in lines.size(): draw_string(font,Vector2(10,112+index*21),lines[index],HORIZONTAL_ALIGNMENT_LEFT,size.x-20,15,Color("f7ecd1"))

func _ready() -> void:
	theme=TDUI.theme()
	process_mode=Node.PROCESS_MODE_PAUSABLE
	var selected_style:=theme.get_stylebox("pressed","Button").duplicate() as StyleBoxFlat
	selected_style.bg_color=Color("4e6656");selected_style.border_color=Color("e9c780")
	selected_style.set_border_width_all(2);theme.set_stylebox("pressed","Button",selected_style)
	var background:=StyleBoxFlat.new();background.bg_color=Color("142c29")
	background.border_color=Color("8c9470");background.border_width_top=2
	add_theme_stylebox_override("panel",background)
	var margin:=MarginContainer.new()
	for side: String in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,12)
	add_child(margin)
	var column:=VBoxContainer.new();margin.add_child(column)
	var row:=HBoxContainer.new();column.add_child(row)
	for title: String in CATEGORIES:
		var tab:=Button.new();tab.text=title;tab.toggle_mode=true;tab.focus_mode=Control.FOCUS_NONE
		tab.custom_minimum_size=Vector2(76,34);tab.pressed.connect(select_category.bind(title));row.add_child(tab);_tabs.append(tab)
	var gap:=Control.new();gap.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(gap)
	var finish_button:=Button.new();finish_button.text="完成布置";finish_button.pressed.connect(func()->void: done.emit());row.add_child(finish_button)
	var scroll:=ScrollContainer.new();scroll.custom_minimum_size.y=178;scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;column.add_child(scroll)
	_cards=HBoxContainer.new();_cards.add_theme_constant_override("separation",10);scroll.add_child(_cards)
	_info=TDUI.label("选择家具放置 · 按住家具拖动 · 左上角删除 / 右上角逆时针旋转 · 右键取消",14)
	# A wrapping label can demand hundreds of pixels while its container is still width 0.
	_info.autowrap_mode=TextServer.AUTOWRAP_OFF
	_info.clip_text=true
	_info.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(_info)
	select_category(category)

func select_category(value: String) -> void:
	category=value;selected=""
	for tab: Button in _tabs: tab.button_pressed=tab.text==category
	refresh_cards()
	category_changed.emit()

func refresh_cards() -> void:
	if _cards==null: return
	for node: Node in _cards.get_children(): _cards.remove_child(node);node.queue_free()
	var ids: Array=[]
	if category=="地面": ids=TDRestaurantLayout.FLOOR_FINISHES.duplicate()
	elif category=="墙壁": ids=TDRestaurantLayout.WALL_FINISHES.duplicate();ids.append("storefront")
	else: ids=GROUPS.get(category,[])
	for value: String in ids:
		var card:=Card.new();card.name="Item_"+value;card.custom_minimum_size=Vector2(178,176);card.toggle_mode=true;card.button_pressed=selected==value;card.focus_mode=Control.FOCUS_NONE
		var definition:=catalog.furniture(value)
		var finish: bool=definition.is_empty()
		if finish:
			card.finish=value;card.details=TDRestaurantLayout.finish_name(value)+"\n整屋"+category+" · 点击替换\n仅改变外观"
		else:
			card.piece={"kind":value,"w":definition.width,"h":definition.height,"rotation":0,"style_id":culture+"_"+tier}
			card.details="%s\n%d×%d · %s · %s\n%s"%[definition.name,int(definition.width),int(definition.height),catalog.culture_name(culture),"精制" if tier=="high" else "朴素",purpose(definition)]
		card.tooltip_text=card.details+("" if finish else "\n参与全店风格统一/档次评价；放置时显示实际效果变化")
		card.pressed.connect(_choose.bind(value,finish));_cards.add_child(card)

func _choose(id: String, finish: bool) -> void:
	selected=id
	for card: Button in _cards.get_children(): card.button_pressed=card.name=="Item_"+id
	item_chosen.emit(id,finish)

func clear_selection() -> void:
	selected=""
	for card: Button in _cards.get_children(): card.button_pressed=false

func show_info(value: String) -> void:
	if _info!=null:
		_info.text=value.replace("\n"," · ")
		_info.tooltip_text=value

static func purpose(definition: Dictionary) -> String:
	match str(definition.id):
		"screen": return "分隔空间 · 风格加成"
		"kiosk": return "自助点餐 · 无需雇员"
		"storefront": return "墙面招牌 · 风格加成"
	if str(definition.seat_use)=="dining": return "用餐座位 · 风格加成"
	if str(definition.seat_use)=="waiting": return "等候座位 · 风格加成"
	return "服务设施 · 风格加成"
