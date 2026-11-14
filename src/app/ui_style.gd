class_name TDUI
extends RefCounted
## Sibling surfaces share a material and tint; depth never depends on screen identity.
const INK := Color("30251b")
const MUTED := Color("65503a")
const TEAL := Color("f2d5a6")
const ORANGE := Color("764019")
const BORDER := Color("916d40")
const FONT_MICRO: int = 16
const FONT_CAPTION: int = 18
const FONT_BODY: int = 22
const FONT_SECTION: int = 26
const FONT_TITLE: int = 30
const FONT_DISPLAY: int = 36
const WOOD: Texture2D=preload("res://assets/ui-wood-v1/wood-light.png")
const PARCHMENT: Texture2D=preload("res://assets/ui-wood-v1/parchment.png")
enum Surface { FRAME, CARD, INSET, SELECTED }
const TINTS: Array[Color]=[Color(1,.99,.98),Color(.94,.91,.84),Color(1.04,1.07,1.10),Color(.84,.81,.73)]
static var _font: SystemFont

class WoodStyle extends StyleBox:
	@export var texture: Texture2D
	@export var modulate_color: Color = Color.WHITE
	func _draw(canvas_item: RID, rect: Rect2) -> void:
		RenderingServer.canvas_item_add_nine_patch(canvas_item,rect,Rect2(Vector2.ZERO,texture.get_size()),texture.get_rid(),Vector2(14,14),Vector2(14,14),RenderingServer.NINE_PATCH_STRETCH,RenderingServer.NINE_PATCH_STRETCH,true,modulate_color)
		TDUI.wood_edges(canvas_item,rect)

static func wood_edges(canvas_item: RID, rect: Rect2) -> void:
	# Inward bevel keeps adjacent controls and their hit areas aligned.
	var rim := Color("694325")
	RenderingServer.canvas_item_add_rect(canvas_item,Rect2(rect.position,Vector2(rect.size.x,2)),rim)
	RenderingServer.canvas_item_add_rect(canvas_item,Rect2(rect.position,Vector2(2,rect.size.y)),rim)
	RenderingServer.canvas_item_add_rect(canvas_item,Rect2(rect.position+Vector2(0,rect.size.y-3),Vector2(rect.size.x,3)),rim)
	RenderingServer.canvas_item_add_rect(canvas_item,Rect2(rect.position+Vector2(rect.size.x-3,0),Vector2(3,rect.size.y)),rim)
	var inner := rect.grow(-2)
	RenderingServer.canvas_item_add_rect(canvas_item,Rect2(inner.position,Vector2(inner.size.x-1,3)),Color("ffe5b7"))
	RenderingServer.canvas_item_add_rect(canvas_item,Rect2(inner.position,Vector2(3,inner.size.y-1)),Color("f5d19a"))
	RenderingServer.canvas_item_add_rect(canvas_item,Rect2(inner.position+Vector2(3,inner.size.y-4),Vector2(inner.size.x-4,3)),Color("a87943"))
	RenderingServer.canvas_item_add_rect(canvas_item,Rect2(inner.position+Vector2(inner.size.x-4,3),Vector2(3,inner.size.y-4)),Color("b98b51"))
	var inset := rect.grow(-6)
	RenderingServer.canvas_item_add_line(canvas_item,inset.position,Vector2(inset.end.x,inset.position.y),Color("b78a51"),1,true)
	RenderingServer.canvas_item_add_line(canvas_item,inset.position,Vector2(inset.position.x,inset.end.y),Color("b78a51"),1,true)
	RenderingServer.canvas_item_add_line(canvas_item,Vector2(inset.position.x,inset.end.y),inset.end,Color("ffe5b7"),1,true)

static func font() -> SystemFont:
	if _font==null:
		_font=SystemFont.new();_font.font_names=PackedStringArray(["SimHei"])
		_font.allow_system_fallback=true
	return _font

static func wood(level: int=Surface.FRAME,padding: float=12) -> WoodStyle:
	var result:=WoodStyle.new();result.texture=WOOD
	result.modulate_color=TINTS[clampi(level,0,3)]
	result.content_margin_left=padding;result.content_margin_right=padding
	result.content_margin_top=padding;result.content_margin_bottom=padding
	return result

static func parchment(padding: float=18) -> StyleBoxTexture:
	var result:=StyleBoxTexture.new();result.texture=PARCHMENT;result.modulate_color=Color.WHITE
	result.content_margin_left=padding;result.content_margin_right=padding
	result.content_margin_top=padding;result.content_margin_bottom=padding
	result.texture_margin_left=55;result.texture_margin_right=55
	result.texture_margin_top=35;result.texture_margin_bottom=35
	return result

static func paint_wood(canvas: CanvasItem,rect: Rect2,level: int=Surface.FRAME) -> void:
	canvas.draw_texture_rect(WOOD,rect,false,TINTS[clampi(level,0,3)])
	wood_edges(canvas.get_canvas_item(),rect)

static func theme() -> Theme:
	var result:=Theme.new();result.default_font=font();result.default_font_size=TDUI.FONT_BODY
	result.set_color("default_color","RichTextLabel",INK)
	for type: String in ["Label","RichTextLabel","Button","CheckBox","CheckButton","OptionButton","LineEdit","TextEdit","SpinBox","TabContainer","TabBar","PopupMenu"]:
		for key: String in ["font_color","font_hover_color","font_pressed_color","font_focus_color","font_selected_color","font_unselected_color","font_hovered_color","font_hover_pressed_color"]: result.set_color(key,type,INK)
		result.set_color("font_disabled_color",type,MUTED);result.set_color("font_uneditable_color",type,MUTED)
		result.set_color("font_placeholder_color",type,MUTED)
	for type: String in ["Button","OptionButton"]:
		for state: String in ["normal","hover","pressed","disabled","hover_pressed"]:
			result.set_stylebox(state,type,wood(Surface.SELECTED if state in ["hover","pressed","hover_pressed"] else Surface.INSET,12))
		var focus:=StyleBoxFlat.new();focus.bg_color=Color.TRANSPARENT;focus.border_color=ORANGE;focus.set_border_width_all(2)
		result.set_stylebox("focus",type,focus)
	for type: String in ["Panel","PanelContainer","PopupPanel","PopupMenu","Window"]: result.set_stylebox("panel",type,wood())
	for type: String in ["LineEdit","TextEdit"]:
		result.set_stylebox("normal",type,wood(Surface.INSET,9));result.set_stylebox("focus",type,wood(Surface.INSET,9))
		result.set_stylebox("read_only",type,wood(Surface.CARD,9));result.set_color("caret_color",type,INK)
		result.set_color("selection_color",type,Color("cfaa72"))
	result.set_stylebox("panel","TabContainer",wood())
	result.set_constant("modulate_arrow","OptionButton",1)
	for key: String in ["up_icon_modulate","up_hover_icon_modulate","up_pressed_icon_modulate","up_disabled_icon_modulate","down_icon_modulate","down_hover_icon_modulate","down_pressed_icon_modulate","down_disabled_icon_modulate"]: result.set_color(key,"SpinBox",INK)
	result.set_color("title_color","Window",INK)
	for type: String in ["TabContainer","TabBar"]:
		result.set_stylebox("tab_selected",type,wood(Surface.SELECTED,10));result.set_stylebox("tab_unselected",type,wood(Surface.CARD,10))
	result.set_stylebox("panel","TooltipPanel",wood(Surface.INSET,8))
	result.set_stylebox("background","ProgressBar",wood(Surface.CARD,2))
	var fill:=StyleBoxFlat.new();fill.bg_color=Color("b88d4e");result.set_stylebox("fill","ProgressBar",fill)
	return result

static func label(text: String, size: int=TDUI.FONT_BODY, color: Color=INK) -> Label:
	var node:=Label.new();node.text=text
	node.add_theme_font_override("font",font());node.add_theme_font_size_override("font_size",size)
	node.add_theme_color_override("font_color",color);node.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	return node

static func button(text: String,callback: Callable) -> Button:
	var node:=Button.new();node.text=text;node.custom_minimum_size.y=48
	node.focus_mode=Control.FOCUS_NONE;node.pressed.connect(callback);return node

static func column(parent: Node,spacing: int=16) -> VBoxContainer:
	var node:=VBoxContainer.new();node.add_theme_constant_override("separation",spacing);parent.add_child(node);return node
