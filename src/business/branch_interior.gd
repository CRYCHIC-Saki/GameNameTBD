class_name TDBranchInterior
extends Node2D
## A disposable inspection view. Branches/Roster own all business state.
signal exit_requested
signal management_requested(tab: String)
var profile: TDGameProfile
var store_id: String=""
var room: String="restaurant"
var player: TDKitchenPlayer
var layout: TDRestaurantLayout
var iso: TDRestaurantIsoView
var kitchen: TDKitchenWorld
var _floor: Node2D
var _camera: Camera2D
var _layer: CanvasLayer
var _caption: Label
var _hint: Label
var _controls: bool=true
var _closed: bool=false
var _refresh: float=0.0
var exit_point:=Vector2.ZERO
var kitchen_point:=Vector2.ZERO
var desk_point:=Vector2.ZERO

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_PAUSABLE
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	var catalog:=TDRestaurantCatalog.new();catalog.load_file()
	layout=TDRestaurantLayout.make_sized(catalog,16,16,TDPlayerBranches.CULTURES[profile.branches.state.stores[store_id].cuisine_id])
	layout.furnish_player_home()
	_floor=Node2D.new();add_child(_floor)
	player=TDKitchenPlayer.new();player.name="BranchPlayer";player.process_mode=Node.PROCESS_MODE_PAUSABLE
	player.collision_layer=512;player.collision_mask=256;player.walk_speed=180;player.vertical_stride_multiplier=1.6
	player.motion_transform=Transform2D(Vector2(TDRestaurantIsoView.HALF_W,TDRestaurantIsoView.HALF_H)/layout.cell_px,Vector2(-TDRestaurantIsoView.HALF_W,TDRestaurantIsoView.HALF_H)/layout.cell_px,Vector2.ZERO).affine_inverse()
	player.input_transform=player.motion_transform.affine_inverse();player.confine_to=_can_stand
	var art:=Sprite2D.new();art.name="Sprite2D";player.add_child(art)
	var collision:=CollisionShape2D.new();var shape:=CircleShape2D.new();shape.radius=12;collision.shape=shape;player.add_child(collision)
	_floor.add_child(player);art.hide()
	var walls:=StaticBody2D.new();walls.collision_layer=256;walls.collision_mask=0;_floor.add_child(walls)
	for y: int in layout.rows:
		for x: int in layout.columns:
			if layout.is_walkable(x,y): continue
			var block:=CollisionShape2D.new();var box:=RectangleShape2D.new();box.size=Vector2.ONE*layout.cell_px
			block.shape=box;block.position=(Vector2(x,y)+Vector2.ONE*.5)*layout.cell_px;walls.add_child(block)
	iso=TDRestaurantIsoView.new();iso.follow_player=true;_floor.add_child(iso);iso.set_room(layout)
	exit_point=(Vector2(layout.entrance())+Vector2(.5,1.5))*layout.cell_px
	kitchen_point=Vector2(layout.columns-1.5,layout.rows-1.5)*layout.cell_px
	var cashier:=layout.piece_by_kind("cashier")
	desk_point=Vector2(float(cashier.x)+float(cashier.w)*.5,float(cashier.y)+float(cashier.h)+.5)*layout.cell_px
	iso.interaction_markers=[{"action":"town","cell":layout.entrance(),"name":"出门"},{"action":"kitchen","cell":Vector2i(kitchen_point/layout.cell_px),"name":"厨房"},{"action":"ledger","cell":Vector2i(int(cashier.x),int(cashier.y)),"name":"本店管理","on_counter":true}]
	kitchen=load("res://src/world/kitchen_world.tscn").instantiate();kitchen.single_fridge=true;kitchen.service_door=true;kitchen.process_mode=Node.PROCESS_MODE_PAUSABLE
	kitchen.station_names={"kitchen.fridge":"本店库存","kitchen.board":"查看菜单","kitchen.stove.left":"查看厨师","kitchen.stove.right":"查看厨师","kitchen.steamer":"查看厨师","kitchen.serve":"本店账本","kitchen.trash":"员工负责清理"}
	add_child(kitchen);_isolate_physics(kitchen);kitchen._player.sprite_height=100;kitchen._player.face(Vector2.UP)
	kitchen.cooking_requested.connect(_inspect_station);kitchen.station_action.connect(func(id:String,_action:String)->void:_inspect_station(id))
	kitchen.dining_requested.connect(show_room.bind("restaurant"));kitchen.back_requested.connect(show_room.bind("restaurant"));kitchen.set_return_visible(false);kitchen._hud.hide()
	_camera=Camera2D.new();_camera.position=Vector2(640,400);add_child(_camera)
	_layer=CanvasLayer.new();_layer.layer=24;add_child(_layer)
	var panel:=PanelContainer.new();panel.position=Vector2(20,670);panel.size=Vector2(1240,110);panel.theme=TDManagementPanels.theme();_layer.add_child(panel)
	var margin:=MarginContainer.new();margin.add_theme_constant_override("margin_left",16);margin.add_theme_constant_override("margin_top",10);panel.add_child(margin)
	var lines:=VBoxContainer.new();margin.add_child(lines)
	_caption=TDUI.label("",21,TDUI.ORANGE);lines.add_child(_caption)
	_hint=TDUI.label("",17);lines.add_child(_hint)
	show_room("restaurant");refresh_staff()

func _isolate_physics(node: Node) -> void:
	if node is StaticBody2D: node.collision_layer=1024;node.collision_mask=0
	if node is CharacterBody2D: node.collision_layer=2048;node.collision_mask=1024
	for child: Node in node.get_children(): _isolate_physics(child)

func _can_stand(at: Vector2) -> bool:
	var count:=maxi(1,ceili(player.position.distance_to(at)/6.0))
	for step: int in range(1,count+1):
		var point:=player.position.lerp(at,float(step)/count)
		for delta: Vector2 in [Vector2.ZERO,Vector2(-12,0),Vector2(12,0),Vector2(0,-12),Vector2(0,12)]:
			var cell:=Vector2i(((point+delta)/layout.cell_px).floor())
			if cell.x<1 or cell.y<1 or cell.x>=layout.columns-1 or cell.y>=layout.rows-1 or not layout.is_walkable(cell.x,cell.y): return false
	return true

func show_room(value: String) -> void:
	if _closed or value not in ["restaurant","kitchen"]: return
	room=value;_floor.visible=room=="restaurant";kitchen.visible=room=="kitchen"
	iso.set_presented(room=="restaurant");_camera.enabled=room=="kitchen"
	if room=="restaurant": player.position=exit_point+Vector2(0,50) if player.position==Vector2.ZERO else kitchen_point-Vector2(60,0)
	else: kitchen._player.position=Vector2(640,620);_camera.make_current()
	set_controls_enabled(_controls);refresh_staff()

func set_controls_enabled(value: bool) -> void:
	_controls=value and not _closed
	if player!=null: player.set_controls_enabled(_controls and room=="restaurant")
	if kitchen!=null: kitchen.set_controls_enabled(_controls and room=="kitchen")
	set_process_unhandled_input(_controls)

func nearby() -> String:
	if room=="kitchen": return str(kitchen._station_at_player().get("id",""))
	var best: float=78;var action: String=""
	for pair: Array in [["exit",exit_point],["kitchen",kitchen_point],["manage",desk_point]]:
		var delta: Vector2=player.motion_transform.affine_inverse().basis_xform(player.position-pair[1])
		if delta.length()<best: best=delta.length();action=pair[0]
	return action

func _unhandled_input(event: InputEvent) -> void:
	if _closed or not _controls or get_tree().paused or room!="restaurant": return
	if event.is_action_pressed("world_interact") and not event.is_echo():
		var action:=nearby()
		if action.is_empty(): return
		get_viewport().set_input_as_handled()
		if action=="exit": exit_requested.emit()
		elif action=="kitchen": show_room("kitchen")
		else: management_requested.emit("staff")

func _inspect_station(id: String) -> void:
	set_controls_enabled(false)
	management_requested.emit("books" if id in ["kitchen.fridge","kitchen.serve","kitchen.trash"] else ("menu" if id=="kitchen.board" else "staff"))

func refresh_staff() -> void:
	if not is_instance_valid(iso) or profile==null or not profile._alive: return
	iso.crew_people=[]
	for node: Node in kitchen.get_children():
		if node.has_meta("branch_staff"): kitchen.remove_child(node);node.queue_free()
	var floor_index: int=0;var cook_index: int=0
	for person: Dictionary in profile.employees.assigned(store_id):
		if person.role=="cook":
			var sprite:=Sprite2D.new();sprite.set_meta("branch_staff",true);sprite.texture=TDDinerArt.sprite(TDDinerArt.appearance(person.id))
			sprite.scale=Vector2.ONE*96/sprite.texture.get_height();sprite.offset=Vector2(0,-sprite.texture.get_height()*.5);sprite.position=Vector2(640+cook_index*210,385);sprite.z_index=1;kitchen.add_child(sprite);cook_index+=1
		else:
			iso.crew_people.append({"actor_id":person.id,"point":Vector2(2.5+floor_index*3,layout.rows-4.5)*layout.cell_px,"moving":false,"color":Color("548ca5"),"label":str(person.name)+(" · 店长" if person.role=="manager" else " · 服务员")});floor_index+=1

func _process(delta: float) -> void:
	if _closed: return
	_refresh+=delta
	if _refresh>1: _refresh=0;refresh_staff()
	iso.nearby_action={"exit":"town","manage":"ledger"}.get(nearby(),nearby())
	iso.sync(player,[],get_tree().paused)
	var store: Dictionary=profile.branches.state.stores[store_id]
	_caption.text=str(store.name)+(" · 餐厅巡视" if room=="restaurant" else " · 厨房巡视")+"    "+profile.branches.status_text(store_id)
	var target:=nearby()
	var hint: String={"exit":"[E] 返回小镇","kitchen":"[E] 进入本店厨房","manage":"[E] 管理本店","kitchen.dining":"[E] 返回餐厅","kitchen.fridge":"[E] 查看本店库存","kitchen.board":"[E] 查看本店菜单"}.get(target,"[E] 查看本店员工 / 账本" if not target.is_empty() else "WASD 走动 · Shift 疾跑 · 靠近门或设施按 E")
	_hint.text=hint+" · G 店铺管理 · 员工沿原流程经营，巡视不接管做菜"

func set_day_minute(value: float) -> void:
	if iso!=null: iso.set_day_minute(value)
	if kitchen!=null: kitchen.set_day_minute(value)

func close() -> void:
	_closed=true;set_controls_enabled(false)
	if iso!=null: iso.shutdown()
	if kitchen!=null: kitchen.close()
	if _camera!=null: _camera.enabled=false
	if _layer!=null: _layer.hide()
	set_process(false)
