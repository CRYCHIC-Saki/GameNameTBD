class_name TDKitchenStaffActor
extends Node2D
## Reuses the established ordinary NPC four-direction art. No new economic identity.
var row: Dictionary = {}
var body: Sprite2D
var caption: Label

func _init() -> void:
	body=Sprite2D.new();body.name="Body";add_child(body)
	caption=Label.new();caption.name="Name";caption.position=Vector2(-88,-125)
	caption.size=Vector2(176,42);caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size",14);caption.mouse_filter=Control.MOUSE_FILTER_IGNORE
	caption.add_theme_color_override("font_color",Color("fff0ce"))
	caption.add_theme_color_override("font_outline_color",Color("2a302c"));caption.add_theme_constant_override("outline_size",4)
	add_child(caption)

func present(value: Dictionary) -> void:
	row=value;position=row.point;z_index=1
	var facing: Vector2i=row.facing
	var working: bool=row.phase in ["cut","cook","pickup","drop","take_board","pickup_dish"]
	if working and row.phase not in ["pickup_dish"]: facing=Vector2i.UP
	body.texture=TDDinerArt.sprite(int(row.index)%2,facing,int(row.frame))
	var scale_factor: float=96.0/body.texture.get_height()
	body.scale=Vector2.ONE*scale_factor;body.position=Vector2(0,-48)
	# Small upper-body work beats accompany the actual running cut/stir action, never a timer completion.
	body.rotation=.035*sin(float(row.elapsed)*9.0) if row.phase=="cut" or row.action in ["翻炒","勾芡"] else 0.0
	caption.text="厨师 "+str(row.name)+"\n"+str(row.action)
	queue_redraw()

func _draw() -> void:
	if row.is_empty(): return
	draw_set_transform(Vector2(0,-2),0,Vector2(1,.34));draw_circle(Vector2.ZERO,20,Color(0,0,0,.18));draw_set_transform_matrix(Transform2D.IDENTITY)
	if str(row.carried)!="":
		if row.carried=="dish":
			draw_set_transform(Vector2(22,-36),0,Vector2(1,.55))
			draw_circle(Vector2.ZERO,19,Color("ebe4d5"));draw_circle(Vector2.ZERO,14,Color("d9a65a"));draw_set_transform_matrix(Transform2D.IDENTITY)
		else: TDIngredientIcon.draw_on(self,str(row.carried),Rect2(10,-57,30,30))
	if row.phase=="cut":
		var lift: float=absf(sin(float(row.elapsed)*9.0))*12
		draw_rect(Rect2(19,-65-lift,5,14),Color("715336"));draw_rect(Rect2(19,-75-lift,18,12),Color("c5d8d0"))
	elif row.phase=="cook" and row.action in ["翻炒","勾芡"]:
		var swing: float=sin(float(row.elapsed)*5.0)*9
		draw_line(Vector2(20,-50),Vector2(25+swing,-76),Color("795934"),4)
		draw_circle(Vector2(25+swing,-76),5,Color("9aafa1"))
	elif row.phase=="cook" and row.action=="调味":
		draw_set_transform(Vector2(23,-65),-.5)
		draw_rect(Rect2(-5,-9,10,18),Color("dcb371"));draw_rect(Rect2(-3,-13,6,4),Color("67523a"))
		draw_set_transform_matrix(Transform2D.IDENTITY)
		for i: int in 3: draw_circle(Vector2(32+i*3,-75+i*3+fmod(float(row.elapsed)*12,5)),1.5,Color("f1dc9e"))
	elif row.phase=="cook" and row.action=="蒸制":
		for i: int in 3:
			var rise: float=fmod(float(row.elapsed)*13+i*8,28)
			draw_circle(Vector2(-12+i*12,-108-rise),3,Color(1,1,1,.3*(1-rise/28)))
