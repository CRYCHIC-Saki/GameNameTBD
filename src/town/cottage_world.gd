class_name TDCottageWorld
extends Node2D
## A physical room. Date, save and business decisions belong to the application.
signal object_requested(action:String)
const FURNITURE: Texture2D=preload("res://assets/cottage/furniture-v1.png")
const ROOM:=Rect2(280,160,720,480)
const BED:=Rect2(796,210,132,172)
const BED_ANCHOR:=Vector2(752,314)
const DOOR:=Vector2(640,616)
var player:TDKitchenPlayer
var camera:Camera2D
var presented:bool=false

func set_day_minute(value: float) -> void:
	self_modulate=TDDaylight.sample(value,true).tint
	if player!=null: player.modulate=self_modulate
var _hud:CanvasLayer
var _prompt:Label

func _ready() -> void:
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	var walls:=StaticBody2D.new();walls.collision_layer=64;walls.collision_mask=0;add_child(walls)
	for rect:Rect2 in [Rect2(248,128,784,32),Rect2(248,640,784,32),Rect2(248,160,32,480),Rect2(1000,160,32,480),BED,Rect2(710,218,54,60)]:
		var collision:=CollisionShape2D.new();var shape:=RectangleShape2D.new();shape.size=rect.size;collision.shape=shape;collision.position=rect.get_center();walls.add_child(collision)
	player=TDKitchenPlayer.new();player.sprite_height=100.0;player.name="Player";player.collision_layer=128;player.collision_mask=64;player.motion_mode=CharacterBody2D.MOTION_MODE_FLOATING
	player.process_mode=Node.PROCESS_MODE_PAUSABLE
	var sprite:=Sprite2D.new();sprite.name="Sprite2D";player.add_child(sprite)
	var feet:=CollisionShape2D.new();var circle:=CircleShape2D.new();circle.radius=11;feet.shape=circle;player.add_child(feet);add_child(player)
	player.position=BED_ANCHOR;player.face(Vector2.RIGHT)
	camera=Camera2D.new();camera.position=Vector2(640,400);add_child(camera)
	_hud=CanvasLayer.new();add_child(_hud)
	_prompt=TDUI.label("",20);_prompt.position=Vector2(290,690);_prompt.size=Vector2(800,60);_hud.add_child(_prompt)
	set_presented(false)

func set_presented(value:bool,at_bed:bool=false) -> void:
	presented=value;visible=value;_hud.visible=value;camera.enabled=value;player.set_controls_enabled(value)
	set_process_unhandled_input(value)
	if value:
		camera.make_current();player.position=BED_ANCHOR if at_bed else DOOR-Vector2(0,65)
		player.face(Vector2.RIGHT if at_bed else Vector2.UP)

func target() -> String:
	if TDInteractionRange.distance(player.position,BED)<65: return "rest"
	if TDInteractionRange.distance(player.position,Rect2(DOOR-Vector2(44,12),Vector2(88,24)))<65: return "town"
	return ""

func _process(_delta:float) -> void:
	if not presented: return
	_prompt.text={"rest":"[ E ] 床 · 保存 / 收工休息","town":"[ E ] 出门去小镇"}.get(target(),"小屋 · WASD 走动 · Shift 疾跑，靠近床或门按 E · B 菜谱 · Esc 暂停")

func _unhandled_input(event:InputEvent) -> void:
	if not presented or get_tree().paused or not player.controls_enabled: return
	if event.is_action_pressed("world_interact") and not event.is_echo() and target()!="":
		object_requested.emit(target());get_viewport().set_input_as_handled()

func close() -> void:
	set_presented(false);set_process(false)

func _furniture(index: int, box: Rect2) -> void:
	var art:=TDStoryArt.grid_view("cottage:"+str(index),FURNITURE,index,3,2)
	draw_texture_rect(art,TDStoryArt.fit(art,box),false)

func _draw() -> void:
	# Physical footprints stay in one coordinate system; wall ornaments are above the floor.
	draw_rect(Rect2(0,0,1280,800),Color("172b2c"))
	draw_rect(Rect2(260,24,760,624),Color("533c2e"))
	draw_rect(Rect2(280,40,720,122),Color("ebcc96"))
	draw_rect(ROOM,Color("b98b57"))
	for row: int in 15:
		var y: float=160+row*32
		for column: int in 13:
			var x: float=280+column*64-(32 if row%2 else 0)
			var plank:=Rect2(Vector2(maxf(x,280),y),Vector2(minf(x+64,1000)-maxf(x,280),32))
			if plank.size.x<=0: continue
			draw_rect(plank,Color("bc8f5e") if (row+column)%3 else Color("c49865"))
			draw_rect(plank.grow(-1),Color("a4774c"),false,1)
			if plank.size.x>30: draw_line(plank.position+Vector2(9,21),plank.end-Vector2(10,11),Color("b48654"),1)
	# Skirting, timber posts and the recessed sill make a room rather than a flat rectangle.
	for x: float in [264.0,994.0]:
		draw_rect(Rect2(x,35,22,610),Color("755031"));draw_rect(Rect2(x+4,35,4,610),Color("a37044"))
	for y: float in [30.0,150.0,635.0]:
		draw_rect(Rect2(270,y,740,14),Color("815631"));draw_line(Vector2(276,y+3),Vector2(1003,y+3),Color("b3834a"),3)
	_furniture(2,Rect2(342,44,180,110))
	_furniture(3,Rect2(560,52,210,103))
	_furniture(5,Rect2(841,42,111,113))
	# A floor rug cannot block movement. Furniture bases coincide with BED/cabinet colliders.
	_furniture(4,Rect2(440,370,260,154))
	_furniture(0,BED)
	_furniture(1,Rect2(710,188,54,90))
	draw_rect(Rect2(DOOR-Vector2(48,12),Vector2(96,48)),Color("543c30"))
	for i: int in 3:
		draw_rect(Rect2(DOOR+Vector2(-44,-7+i*12),Vector2(88,10)),Color("ba9e70"))
	draw_string(ThemeDB.fallback_font,Vector2(545,718),"一盏灯，一处归途",HORIZONTAL_ALIGNMENT_CENTER,190,19,Color("ead7a7"))
