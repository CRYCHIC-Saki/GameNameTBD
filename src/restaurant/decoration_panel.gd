class_name TDDecorationPanel
extends PanelContainer

signal item_chosen(id: String, finish: bool)
signal category_changed
signal done

const CATEGORIES: Array[String]=["地面","墙壁","陈设","餐桌","座椅","服务台"]
const PANEL_HEIGHT: float=320.0
const GROUPS: Dictionary={"陈设":["screen","kiosk"],"餐桌":["dining_table"],"座椅":["waiting_seat","booth","sofa","stool","child_seat"],"服务台":["welcome_desk","cashier","order_counter"]}
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
			TDRegionalInterior.draw_finish_sample(self,finish,Rect2(25,14,size.x-50,70))
		var font:=get_theme_font("font")
		var lines:=details.split("\n")
		for index in lines.size(): draw_string(font,Vector2(10,118+index*24),lines[index],HORIZONTAL_ALIGNMENT_LEFT,size.x-20,TDUI.FONT_CAPTION,TDUI.INK)

func _ready() -> void:
	theme=TDUI.theme()
	process_mode=Node.PROCESS_MODE_PAUSABLE
	add_theme_stylebox_override("panel",TDUI.wood(TDUI.Surface.FRAME,0))
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
	var scroll:=ScrollContainer.new();scroll.custom_minimum_size.y=190;scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;column.add_child(scroll)
	_cards=HBoxContainer.new();_cards.add_theme_constant_override("separation",10);scroll.add_child(_cards)
	_info=TDUI.label("选择家具放置 · 按住家具拖动 · 左上角删除 / 右上角逆时针旋转 · 右键取消",TDUI.FONT_CAPTION)
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
	# Keep original cards first and append individually selectable regional models.
	# No global style selector: each card carries its own placement style.
	ids=ids.duplicate()
	for base: String in ids.duplicate():
		if catalog.furniture(base).is_empty() or TDRestaurantLayout.shared_accent(base): continue
		for theme_id: String in TDRegionalInterior.DECOR_STYLES:
			if theme_id!=culture: ids.append(base+"__"+theme_id+"_"+tier)
	for value: String in ids:
		var card:=Card.new();card.name="Item_"+value;card.custom_minimum_size=Vector2(224,188);card.toggle_mode=true;card.button_pressed=selected==value;card.focus_mode=Control.FOCUS_NONE
		var choice:=furniture_choice(value)
		var definition:=catalog.furniture(str(choice.get("kind",value)))
		var finish: bool=definition.is_empty()
		if finish:
			card.finish=value;card.details=TDRestaurantLayout.finish_name(value)+"\n整屋"+category+" · 点击替换\n仅改变外观"
		else:
			var picked_style: String=choice.style_id
			var theme_id:=picked_style.get_slice("_",0)
			card.piece={"kind":definition.id,"w":definition.width,"h":definition.height,"rotation":0,"style_id":picked_style}
			var region_label := "通用" if TDRestaurantLayout.shared_accent(definition.id) else str(TDRegionalInterior.STYLE_NAMES.get(theme_id,catalog.culture_name(theme_id)))
			card.details="%s · %s\n%d×%d · %s\n%s"%[region_label,definition.name,int(definition.width),int(definition.height),"精制" if tier=="high" else "标准",purpose(definition)]
		card.tooltip_text=card.details+("" if finish else "\n参与全店风格统一/档次评价；放置时显示实际效果变化")
		card.pressed.connect(_choose.bind(value,finish));_cards.add_child(card)

func furniture_choice(id: String) -> Dictionary:
	var parts:=id.split("__")
	if parts.size()>2 or catalog.furniture(parts[0]).is_empty(): return {}
	var style_id:=culture+"_"+tier if parts.size()==1 else str(parts[1])
	if TDRestaurantLayout.shared_accent(parts[0]):
		if parts.size()!=1: return {}
		style_id="plain_"+tier
	var style_parts:=style_id.split("_")
	if style_parts.size()!=2 or not catalog.has_style(style_parts[0],style_parts[1]): return {}
	return {"kind":str(parts[0]),"style_id":style_id}

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
