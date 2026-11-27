class_name TDBranchInterior
extends Node2D
## Branch interior composes its own live kitchen; Branches/Roster retain authority.
signal exit_requested
signal management_requested(tab: String)
signal pause_requested
signal status_reported(text: String)
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
var _layer: CanvasLayer
var _caption: Label
var _hint: Label
var _controls: bool=true
var _closed: bool=false
var _refresh: float=0.0
var _kitchen_day: int=0
var exit_point:=Vector2.ZERO
var kitchen_point:=Vector2.ZERO

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_PAUSABLE
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	var catalog:=TDRestaurantCatalog.new();catalog.load_file()
	layout=profile.branches.dining_layout(store_id,catalog)
	kitchen_session=profile.branches.open_kitchen(store_id)
	layout.crew=kitchen_session.crew
	kitchen_session.table_service_enabled=true
	dining=TDRestaurantWorld.new()
	dining.layout=layout
	dining.business=kitchen_session
	dining.player_mode=true
	dining.floor_service=true
	dining.decoration_progression=profile.progression
	dining.status_reported.connect(status_reported.emit)
	dining.object_requested.connect(_object_requested)
	dining.pause_requested.connect(func() -> void: pause_requested.emit())
	dining.layout_changed.connect(func() -> void: profile.branches.record_dining_layout(store_id,layout))
	add_child(dining)
	dining.bind_dining_clock()
	dining.restore_visit_boundary()
	player=dining._player
	iso=dining._iso
	player.collision_layer=512
	player.collision_mask=256
	exit_point=(Vector2(layout.entrance())+Vector2(.5,1.5))*layout.cell_px
	kitchen_point=layout.cell_center(dining.kitchen_door_cell())
	player.position=Vector2.ZERO

	_kitchen_layer=CanvasLayer.new();_kitchen_layer.layer=23;add_child(_kitchen_layer)
	shop_view=TDShopView.new();shop_view.embedded=true;shop_view.shop=kitchen_session;shop_view.day_san=profile.world.san
	shop_view.save_path="res://artifacts/branch-unused-"+store_id.replace(":","-")
	_kitchen_layer.add_child(shop_view);shop_view.kitchen.auto_advance=false
	shop_view.back_requested.connect(show_room.bind("restaurant"))
	shop_view.pause_requested.connect(func()->void:pause_requested.emit())
	kitchen=shop_view.kitchen.world;kitchen_session.cleanup=shop_view.finish_night
	_kitchen_day=int(kitchen_session._s.day)
	_isolate_physics(kitchen);kitchen._player.sprite_height=100;kitchen._player.face(Vector2.UP)
	_layer=CanvasLayer.new();_layer.layer=24;add_child(_layer)
	var panel:=PanelContainer.new();panel.theme=TDManagementPanels.theme();_layer.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left=8; panel.offset_right=-8; panel.offset_top=-54; panel.offset_bottom=-4
	var margin:=MarginContainer.new();margin.add_theme_constant_override("margin_left",16);margin.add_theme_constant_override("margin_top",10);panel.add_child(margin)
	var lines:=HBoxContainer.new();lines.add_theme_constant_override("separation",24);margin.add_child(lines)
	_caption=TDUI.label("",TDUI.FONT_SECTION,TDUI.ORANGE);lines.add_child(_caption)
	_hint=TDUI.label("",TDUI.FONT_BODY);lines.add_child(_hint)
	_caption.autowrap_mode=TextServer.AUTOWRAP_OFF
	_hint.autowrap_mode=TextServer.AUTOWRAP_OFF
	show_room("restaurant");refresh_staff()

func _isolate_physics(node: Node) -> void:
	if node is StaticBody2D: node.collision_layer=1024;node.collision_mask=0
	if node is CharacterBody2D: node.collision_layer=2048;node.collision_mask=1024
	for child: Node in node.get_children(): _isolate_physics(child)

func show_room(value: String) -> void:
	if _closed or value not in ["restaurant","kitchen"]: return
	room=value
	if room=="restaurant": player.position=exit_point if player.position==Vector2.ZERO else kitchen_point-Vector2(60,0)
	else: kitchen._player.position=Vector2(640,520)
	_present_room()
	refresh_staff()

func set_controls_enabled(value: bool) -> void:
	_controls=value and not _closed
	var dining_active := _controls and presented and room=="restaurant"
	if player!=null:
		player.set_controls_enabled(dining_active and not dining._editing and not dining._talk_open())
		dining.set_process_input(dining_active)
		dining.set_process_unhandled_input(dining_active)
	if kitchen!=null: kitchen.set_controls_enabled(_controls and presented and room=="kitchen" and not shop_view.kitchen.stage.visible)
	if shop_view!=null: shop_view.kitchen.set_process_input(_controls and presented and room=="kitchen")

func nearby() -> String:
	if room=="kitchen": return str(kitchen._station_at_player().get("id",""))
	return str(dining.nearby_object().get("action",""))

func _object_requested(action: String) -> void:
	match action:
		"town": exit_requested.emit()
		"kitchen": show_room("kitchen")
		"ledger": management_requested.emit("staff")
		"menu": management_requested.emit("menu")
		"decorate": management_requested.emit("decorate")

func refresh_staff() -> void:
	if dining==null or not is_instance_valid(iso) or profile==null or not profile._alive: return
	layout.crew.use_external(profile.employees.assigned(store_id).filter(func(person: Dictionary)->bool:return person.role in ["cook","waiter"]),profile.employees._record_growth)
	iso.crew_people=dining._crew_points(0)

func _process(delta: float) -> void:
	if _closed or not presented: return
	_refresh+=delta
	if _refresh>1: _refresh=0;refresh_staff()
	_layer.visible=not dining._editing
	var store: Dictionary=profile.branches.state.stores[store_id]
	_caption.text=str(store.name)+(" · 餐厅" if room=="restaurant" else " · 厨房")+"    "+profile.branches.status_text(store_id)
	var target:=nearby()
	var hint: String={"town":"E 出门","kitchen":"E 厨房","ledger":"E 管理","menu":"E 营业牌","decorate":"E 装修","kitchen.dining":"E 餐厅","kitchen.fridge":"E 冰箱","kitchen.board":"E 备菜"}.get(target,"E 查看" if not target.is_empty() else "")
	_hint.text=hint if _controls else ""
	_hint.visible=not _hint.text.is_empty()

func set_day_minute(value: float) -> void:
	if iso!=null: iso.set_day_minute(value)
	if kitchen!=null: kitchen.set_day_minute(value)

func close() -> void:
	_closed=true;set_controls_enabled(false)
	if dining!=null: dining.close()
	if shop_view!=null: shop_view.close()
	if kitchen_session!=null: kitchen_session.cleanup=Callable()
	if _layer!=null: _layer.hide()
	set_process(false)

func set_presented(value: bool) -> void:
	presented=value;visible=value
	_present_room()

func _present_room() -> void:
	var on_floor := presented and room=="restaurant"
	dining.set_floor_cover(not on_floor)
	dining.set_process(on_floor)
	dining._blockers.collision_layer=256 if on_floor else 0
	player.collision_layer=512 if on_floor else 0
	_layer.visible=presented and not dining._editing
	_kitchen_layer.visible=presented and room=="kitchen"
	shop_view.visible=_kitchen_layer.visible
	shop_view.kitchen.set_process_unhandled_input(_kitchen_layer.visible)
	set_controls_enabled(_controls)

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
