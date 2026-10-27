class_name TDCottageWorld
extends Node2D
## A physical room. Date, save and business decisions belong to the application.
signal object_requested(action:String)
const ROOM:=Rect2(280,160,720,480)
const BED:=Rect2(796,210,132,172)
const BED_ANCHOR:=Vector2(752,314)
const DOOR:=Vector2(640,616)
var player:TDKitchenPlayer
var camera:Camera2D
var presented:bool=false
var _hud:CanvasLayer
var _prompt:Label

func _ready() -> void:
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	var walls:=StaticBody2D.new();walls.collision_layer=64;walls.collision_mask=0;add_child(walls)
	for rect:Rect2 in [Rect2(248,128,784,32),Rect2(248,640,784,32),Rect2(248,160,32,480),Rect2(1000,160,32,480),BED,Rect2(710,218,54,60)]:
		var collision:=CollisionShape2D.new();var shape:=RectangleShape2D.new();shape.size=rect.size;collision.shape=shape;collision.position=rect.get_center();walls.add_child(collision)
	player=TDKitchenPlayer.new();player.name="Player";player.collision_layer=128;player.collision_mask=64;player.motion_mode=CharacterBody2D.MOTION_MODE_FLOATING
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
	if player.position.distance_to(BED_ANCHOR)<65 and player.faces_target(BED.get_center()): return "rest"
	if player.position.distance_to(DOOR)<85 and player.faces_target(DOOR): return "town"
	return ""

func _process(_delta:float) -> void:
	if not presented: return
	_prompt.text={"rest":"[ E ] 床 · 保存 / 收工休息","town":"[ E ] 出门去小镇"}.get(target(),"小屋 · WASD 走动，面向床或门按 E · B 菜谱 · Esc 暂停")

func _unhandled_input(event:InputEvent) -> void:
	if not presented or get_tree().paused or not player.controls_enabled: return
	if event.is_action_pressed("world_interact") and not event.is_echo() and target()!="":
		object_requested.emit(target());get_viewport().set_input_as_handled()

func close() -> void:
	set_presented(false);set_process(false)

func _draw() -> void:
	draw_rect(Rect2(0,0,1280,800),Color("1c2927"));draw_rect(ROOM,Color("a58659"))
	for y:int in range(160,640,32):
		draw_line(Vector2(280,y),Vector2(1000,y),Color("816444"),2)
		for x:int in range(280+(16 if y%64 else 0),1000,64): draw_line(Vector2(x,y),Vector2(x,y+32),Color("92714b"),1)
	draw_rect(Rect2(272,130,736,35),Color("654830"));draw_rect(ROOM,Color("59402d"),false,12)
	# Chinese timber window, red paper decoration and a simple bedside cabinet.
	draw_rect(Rect2(380,170,148,100),Color("5a4432"));draw_rect(Rect2(388,178,132,84),Color("9ac4b4"))
	for x:int in range(388,521,22): draw_line(Vector2(x,178),Vector2(x,262),Color("654b35"),4)
	draw_line(Vector2(388,220),Vector2(520,220),Color("654b35"),4)
	draw_rect(Rect2(604,172,44,44),Color("a94d38"));draw_rect(Rect2(618,186,16,16),Color("dfb56e"))
	draw_rect(BED.grow(6),Color("664833"));draw_rect(BED,Color("b34e3d"));draw_rect(Rect2(BED.position,Vector2(132,44)),Color("e6dab5"))
	draw_rect(Rect2(810,222,104,24),Color("f1e5c5"));draw_rect(Rect2(808,278,108,8),Color("e0ad62"));draw_rect(Rect2(808,344,108,8),Color("e0ad62"))
	draw_rect(Rect2(710,218,54,60),Color("795738"));draw_rect(Rect2(725,195,24,30),Color("dfad5d"))
	draw_rect(Rect2(DOOR-Vector2(44,12),Vector2(88,36)),Color("674733"));draw_rect(Rect2(DOOR-Vector2(40,8),Vector2(80,10)),Color("b39660"))
	draw_string(ThemeDB.fallback_font,Vector2(595,124),"自 家 小 屋",HORIZONTAL_ALIGNMENT_CENTER,130,22,Color("ead7a7"))
