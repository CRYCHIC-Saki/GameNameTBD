class_name TDBranchInterior
extends Node2D
## Branch interior composes its own live kitchen; Branches/Roster retain authority.
signal exit_requested
signal management_requested(tab: String)
signal pause_requested
var profile: TDGameProfile
var store_id: String=""
var room: String="restaurant"
var player: TDKitchenPlayer
var layout: TDRestaurantLayout
var dining: TDRestaurantWorld
var iso: TDRestaurantIsoView
var kitchen: TDKitchenWorld
var shop_view: TDShopView
var kitchen_session: TDBranchKitchenSession
var _kitchen_layer: CanvasLayer
var presented: bool=true
var _floor: Node2D
var _camera: Camera2D
var _layer: CanvasLayer
var _caption: Label
var _hint: Label
var _controls: bool=true
var _closed: bool=false
var _refresh: float=0.0
var _kitchen_day: int=0
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
	player.input_transform=Transform2D.IDENTITY;player.confine_to=_can_stand
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
	kitchen_session=profile.branches.open_kitchen(store_id)
	layout.crew=kitchen_session.crew
	kitchen_session.table_service_enabled=true
	dining=TDRestaurantWorld.new()
	dining.host_dining(layout,kitchen_session,player)
	add_child(dining)

	_kitchen_layer=CanvasLayer.new();_kitchen_layer.layer=23;add_child(_kitchen_layer)
	shop_view=TDShopView.new();shop_view.embedded=true;shop_view.shop=kitchen_session;shop_view.day_san=profile.world.san
	shop_view.save_path="res://artifacts/branch-unused-"+store_id.replace(":","-")
	_kitchen_layer.add_child(shop_view);shop_view.kitchen.auto_advance=false
	shop_view.back_requested.connect(show_room.bind("restaurant"))
	shop_view.pause_requested.connect(func()->void:pause_requested.emit())
	kitchen=shop_view.kitchen.world;kitchen_session.cleanup=shop_view.finish_night
	_kitchen_day=int(kitchen_session._s.day)
	_isolate_physics(kitchen);kitchen._player.sprite_height=100;kitchen._player.face(Vector2.UP)
	_camera=Camera2D.new();_camera.position=Vector2(640,400);add_child(_camera)
	_layer=CanvasLayer.new();_layer.layer=24;add_child(_layer)
	var panel:=PanelContainer.new();panel.position=Vector2(20,670);panel.size=Vector2(1240,110);panel.theme=TDManagementPanels.theme();_layer.add_child(panel)
	var margin:=MarginContainer.new();margin.add_theme_constant_override("margin_left",16);margin.add_theme_constant_override("margin_top",10);panel.add_child(margin)
	var lines:=VBoxContainer.new();margin.add_child(lines)
	_caption=TDUI.label("",TDUI.FONT_SECTION,TDUI.ORANGE);lines.add_child(_caption)
	_hint=TDUI.label("",TDUI.FONT_BODY);lines.add_child(_hint)
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
	room=value;_floor.visible=room=="restaurant";_kitchen_layer.visible=room=="kitchen";shop_view.visible=room=="kitchen"
	iso.set_presented(room=="restaurant");_camera.enabled=false
	if room=="restaurant": player.position=exit_point+Vector2(0,50) if player.position==Vector2.ZERO else kitchen_point-Vector2(60,0)
	else: kitchen._player.position=Vector2(640,520)
	set_controls_enabled(_controls);refresh_staff()

func set_controls_enabled(value: bool) -> void:
	_controls=value and not _closed
	if player!=null: player.set_controls_enabled(_controls and room=="restaurant")
	if kitchen!=null: kitchen.set_controls_enabled(_controls and room=="kitchen" and not shop_view.kitchen.stage.visible)
	if shop_view!=null: shop_view.kitchen.set_process_input(_controls and presented and room=="kitchen")
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
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled();pause_requested.emit();return
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
	if dining==null or not is_instance_valid(iso) or profile==null or not profile._alive: return
	layout.crew.use_external(profile.employees.assigned(store_id).filter(func(person: Dictionary)->bool:return person.role in ["cook","waiter"]),profile.employees._record_growth)
	iso.crew_people=dining._crew_points(0)

func _process(delta: float) -> void:
	if _closed or not presented: return
	_refresh+=delta
	if _refresh>1: _refresh=0;refresh_staff()
	iso.nearby_action={"exit":"town","manage":"ledger"}.get(nearby(),nearby())
	if room=="restaurant":
		iso.crew_people=dining._crew_points(0)
		iso.hatch_plates=dining._hatch_plate_count()
		iso.sync(player,dining.guest_nodes(),get_tree().paused)
	var store: Dictionary=profile.branches.state.stores[store_id]
	_caption.text=str(store.name)+(" · 餐厅" if room=="restaurant" else " · 厨房")+"    "+profile.branches.status_text(store_id)
	var target:=nearby()
	var hint: String={"exit":"E 出门","kitchen":"E 厨房","manage":"E 管理","kitchen.dining":"E 餐厅","kitchen.fridge":"E 冰箱","kitchen.board":"E 备菜"}.get(target,"E 查看" if not target.is_empty() else "")
	_hint.text=hint if _controls else ""
	_hint.visible=not _hint.text.is_empty()

func set_day_minute(value: float) -> void:
	if iso!=null: iso.set_day_minute(value)
	if kitchen!=null: kitchen.set_day_minute(value)

func close() -> void:
	_closed=true;set_controls_enabled(false)
	if dining!=null: dining.close()
	if iso!=null: iso.shutdown()
	if shop_view!=null: shop_view.close()
	if kitchen_session!=null: kitchen_session.cleanup=Callable()
	if _camera!=null: _camera.enabled=false
	if _layer!=null: _layer.hide()
	set_process(false)

func set_presented(value: bool) -> void:
	presented=value;visible=value
	_floor.visible=value and room=="restaurant";_layer.visible=value
	_kitchen_layer.visible=value and room=="kitchen"
	shop_view.visible=value and room=="kitchen"
	shop_view.kitchen.set_process_unhandled_input(value and room=="kitchen")
	iso.set_presented(value and room=="restaurant");set_controls_enabled(value)

func advance(seconds: float) -> void:
	if _closed: return
	kitchen_session.sync_store()
	if _kitchen_day!=int(kitchen_session._s.day):
		dining.finish_night()
		shop_view._make_kitchen();shop_view.kitchen.auto_advance=false
		kitchen=shop_view.kitchen.world;_isolate_physics(kitchen)
		kitchen._player.sprite_height=100;kitchen._player.face(Vector2.UP)
		_kitchen_day=int(kitchen_session._s.day)
		show_room(room);set_presented(presented)
	shop_view.kitchen.advance(seconds)
