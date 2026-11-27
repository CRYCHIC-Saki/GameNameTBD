class_name TDTownWorld
extends Node2D
var management_menus: bool=false
const BuildingNameplate := preload("res://src/town/building_nameplate.gd")
var _building_nameplate: BuildingNameplate

signal back_requested
signal pause_requested
signal restaurant_requested
signal place_requested(kind: String, id: String)
signal story_effect(effect: Dictionary)
signal story_requested(who: String)
signal status_reported(text: String)
var external_story_frozen: bool=false
var _escort_leg: String=""
var _escort_waiting: bool=false
var player_mode: bool = false
var day_minute: float = 720.0

func set_day_minute(value: float) -> void:
	day_minute=value
	self_modulate=TDDaylight.sample(value).tint
	if _player!=null: _player.modulate=self_modulate
	if _resident_layer!=null: _resident_layer.modulate=self_modulate
	if _hertz != null: _hertz.modulate = self_modulate
	if _luo != null: _luo.modulate = self_modulate
	if _crowd_stands != null: _crowd_stands.modulate = self_modulate
	if _facade_layer!=null: _facade_layer.modulate=self_modulate
	if _reference_map!=null:
		_reference_map.modulate=self_modulate
		_reference_map.get_node("Atmosphere").set_minute(value)
		if _sun_shadows != null: _sun_shadows.set_day_minute(value)
var transaction_sink: Callable
var external_factory_clock: bool = false
var balance_reader: Callable
var commercial_refresh: Callable
var shop_open: bool = false
var chapter_ready: bool = false
var hero_name: String = ""
var story: TDOpening
var story_board: Dictionary = {}
var _escort := Vector2i(-99, -99)
var _escort_gate_index: int=0
const FIRST_GATE_ROUTE := [Vector2i(64,34),Vector2i(64,29)]
var _escort_wait: float = 0.0
var _escort_facing := Vector2i.DOWN
var homecoming: Dictionary={}
var _escort_next:=Vector2i(-99,-99)
var _reference_escort_goal := Vector2i(-99, -99)
var _reference_escort_stop := Vector2.ZERO
var _reference_escort_path := PackedVector2Array()
var _reference_escort_index := 0
var _reference_navigation: AStar2D
var _npc_gaits: Dictionary={}
var _resident_sprites: Dictionary = {}
var _resident_layer: Node2D
const NPC_FOOT_RADIUS := 12.0
var _hertz: TDStoryArt.TownActor
var _luo: TDStoryArt.TownActor
var luo_anchor: Callable
const CrowdStands := preload("res://src/town/crowd_stands.gd")
var _crowd_stands: CrowdStands

const CELL := 80
const JiangnanAmbience := preload("res://src/town/jiangnan_ambience.gd")
const HERO_HEIGHT := 72.0
const OUTDOOR_PERSON_HEIGHT := HERO_HEIGHT * 1.5
const FOOT_RADIUS := 10.0
const ESCORT_STEP_SEC: float = float(CELL) / TDKitchenPlayer.WALK_SPEED
const BUILDING_REACH := CELL*0.65
const PERSON_REACH := CELL*0.85
const BOWL_REACH := 32.0
const BAR_HEIGHT := 92.0
const GLASS := Color(0.07, 0.15, 0.30, 0.78)
const GLASS_CARD := Color(0.20, 0.36, 0.62, 0.38)
const GLASS_EDGE := Color(0.74, 0.88, 1.0, 0.48)
const GLASS_INK := Color(0.95, 0.97, 1.0)
const GLASS_MUTED := Color(0.76, 0.86, 0.98, 0.86)
const GLASS_BLUE := Color(0.45, 0.74, 1.0, 0.95)
const GLASS_DIM := Color(0.03, 0.08, 0.18, 0.42)

var session: TDPhase3Session
var _player: TDKitchenPlayer
var _camera: Camera2D
var _status: Label
var _status_panel: Panel
var _selected: Dictionary = {}
var _closed: bool = false
var _blockers: StaticBody2D
var _facade_layer: Node2D
var _reference_map: Node2D
var _sun_shadows: Node
var _facades: Array[Dictionary] = []
var _interactable_facades: Dictionary = {}
var _reference_doorways: Array[Dictionary] = []
var _jiangnan_details: Array[JiangnanAmbience] = []
var _solid_bases: Array[Rect2] = []
var _contact_bins: Dictionary = {}
const CONTACT_BIN := 192.0
var _seen_revision: int = -1
var _venue_layer: CanvasLayer
var _factory_layer: CanvasLayer
var _factory_dim: ColorRect
var _factory_shell: PanelContainer
var _pack_layer: CanvasLayer
var _factory_plot: String = ""
var _factory_rows: Dictionary = {}
var _factory_hover: Label
var _factory_hover_id: String = ""
var _factory_cash: Label
var _factory_time: Label
var _factory_pack: Label
var _pack_button: Button
var _factory_level_label: Label
var _factory_upgrade: Button
var _factory_mill: FactoryMill
var _qty_layer: CanvasLayer
var _qty_item: String = ""
var _qty_line: int = 0
var _qty_count: int = 1
var _qty_summary: Label
var _factory_accent: Color = Color("#ecb36e")
var _entering_diner: bool = false
var characters: TDCharacterRoster
var _talk_layer: CanvasLayer
var _talk_view: TDDialogueView

func cell_size() -> int:
	if player_mode and session != null and TDPlannedTown.approved(session.town_map):
		return TDJiangnanReferenceArt.CELL_SIZE
	return CELL

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	y_sort_enabled = player_mode
	if session == null:
		session = TDPhase3Session.new()
		var loaded := session.load_default()
		if not loaded.ok:
			_status_bar()
			_set_status(loaded.message)
			return
	elif not session.ready:
		session.load_default()
	_player = TDKitchenPlayer.new()
	_player.name = "Player"
	_player.process_mode = Node.PROCESS_MODE_PAUSABLE
	_player.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	_player.collision_layer = 32
	_player.collision_mask = 16
	_player.directional_art=player_mode
	_player.sprite_height=OUTDOOR_PERSON_HEIGHT if player_mode else HERO_HEIGHT
	_player.walk_cycle_distance=96.0
	var sprite := Sprite2D.new()
	sprite.name = "Sprite2D"
	sprite.texture = preload("res://assets/redraw-v1/chef.png") if player_mode else TDRestaurantArt.guest_texture()
	if player_mode: sprite.scale=Vector2(.055,.055)
	_player.add_child(sprite)
	_player.body_lift = 24.0 if player_mode else 0.0
	_player.confine_to = _player_step_clear
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = FOOT_RADIUS
	shape.shape = circle
	_player.add_child(shape)
	_player.position = _origin() + Vector2((TDTownMap.CENTER + 0.5) * cell_size(), (TDTownMap.CENTER + 0.5) * cell_size())
	add_child(_player)
	_camera = Camera2D.new()
	_camera.name = "TownCamera"
	_camera.zoom = Vector2.ONE * _overview_zoom()
	_camera.position_smoothing_enabled = false
	_camera.enabled = true
	add_child(_camera)
	_camera.make_current()
	_follow_camera()
	_resident_layer=Node2D.new()
	_resident_layer.name="WalkingResidents"
	_resident_layer.y_sort_enabled=true
	add_child(_resident_layer)
	_build_blockers()
	_seen_revision = session.map_revision
	_status_bar()
	if player_mode: spawn_at_home()
	if not player_mode: _set_status(_enter_hint())
	queue_redraw()

func _process(delta: float) -> void:
	_follow_camera()
	if player_mode and visible and not get_tree().paused and not _talk_open() and not external_story_frozen:
		_tick_escort(delta)
		if _hertz != null: _hertz.face_nearby(_player.position)
		if _luo==null and luo_anchor.is_valid() and characters!=null and characters.has_met("luo"):
			var anchor: Vector2 = luo_anchor.call()
			if anchor.is_finite():
				_luo = TDStoryArt.TownActor.new()
				_luo.name = "Luoe"
				_luo.place("luo",OUTDOOR_PERSON_HEIGHT,anchor,_npc_can_stand)
				_luo.modulate = self_modulate
				add_child(_luo)
		if _luo != null: _luo.face_nearby(_player.position)
		if _crowd_stands != null: _crowd_stands.face_nearby(_player.position)
	if not _jiangnan_details.is_empty() and is_visible_in_tree() and not _closed and not get_tree().paused and not story_dialogue_open():
		_sample_jiangnan_details()
	_refresh_npc_gaits()
	if not player_mode: _try_enter_diner()
	if _closed:
		return
	if session != null and not get_tree().paused:
		var finished: Array = [] if external_factory_clock else session.tick_factories(clampf(delta, 0.0, 0.25))
		for item: Variant in finished:
			var job: Dictionary = item
			_set_status("%s做好了一份，已放入背包，现在有%d。" % [String(job.get("name", "")), int(job.get("stock", 0))])
		if not finished.is_empty() and _factory_cash != null and is_instance_valid(_factory_cash):
			_refresh_factory_panel()
		elif _factory_mill != null and is_instance_valid(_factory_mill):
			_paint_factory_job()
		if not finished.is_empty() and _pack_layer != null and is_instance_valid(_pack_layer):
			_open_backpack()
		if is_visible_in_tree():
			_paint_backpack_count()
	if session != null and session.map_revision != _seen_revision:
		_seen_revision = session.map_revision
		if commercial_refresh.is_valid(): commercial_refresh.call()
		_build_blockers()
		_keep_player_on_map()
	if player_mode and _building_nameplate != null:
		_update_building_nameplate()
	queue_redraw()

func _update_building_nameplate() -> void:
	if _player == null or not is_visible_in_tree() or not _player.controls_enabled:
		_building_nameplate.hide()
		return
	_selected = facing_plot()
	var facade: Dictionary = _interactable_facades.get(_selected.get("id", ""), {})
	if facade.is_empty():
		_building_nameplate.hide()
		return
	_camera.force_update_scroll()
	_building_nameplate.track(self, facade.rect, TDTravelCatalog.label(_selected, "chengdu"))

func _overview_zoom() -> float:
	if player_mode: return 1.0
	var view := get_viewport().get_visible_rect().size
	if view.x < 8.0 or view.y < 8.0:
		return 1.0
	var map_px := float(session.town_map.extent * cell_size())
	var usable_height := maxf(1.0, view.y - (80.0 if player_mode else BAR_HEIGHT))
	return maxf(0.05, minf(view.x / map_px, usable_height / map_px) * 0.96 * 2.0)

func _follow_camera() -> void:
	if _player == null or _camera == null:
		return
	var zoom := _overview_zoom()
	_camera.zoom = Vector2(zoom, zoom)
	var view := get_viewport().get_visible_rect().size / zoom
	var map_size := Vector2(session.town_map.extent * cell_size(), session.town_map.extent * cell_size())
	if player_mode and TDPlannedTown.approved(session.town_map):
		map_size.y=TDJiangnanReferenceArt.SIZE.y * TDJiangnanReferenceArt.world_scale(session.town_map, cell_size())
	elif player_mode and session.town_map.layout_version==2:
		map_size.x+=cell_size()*14
	var origin := _origin()
	var half := view * 0.5
	var target := _player.position + Vector2(0, -70 if player_mode else BAR_HEIGHT * 0.5 / zoom)
	if map_size.x > view.x:
		target.x = clampf(target.x, origin.x + half.x, origin.x + map_size.x - half.x)
	else:
		target.x = origin.x + map_size.x * 0.5
	if map_size.y > view.y:
		target.y = clampf(target.y, origin.y + half.y, origin.y + map_size.y - half.y)
	else:
		target.y = origin.y + map_size.y * 0.5
	_camera.position = target

func _draw() -> void:
	if session == null or session.town_map.plots.is_empty():
		return
	if player_mode:
		TDTownArt.draw_world(self,session,_facades)
		if not TDPlannedTown.approved(session.town_map):
			TDHarbor.draw(self,session.town_map,_origin(),cell_size())
		for detail: JiangnanAmbience in _jiangnan_details:
			detail.draw_ground(self)
		# Property visuals now use the same atlas renderer.
		_draw_story()
		return
	var origin := _origin()
	for y in session.town_map.extent:
		for x in session.town_map.extent:
			var ground := Rect2(origin + Vector2(x * cell_size(), y * cell_size()), Vector2(cell_size() - 1, cell_size() - 1))
			var color := Color("#2c3338")
			if session.town_map.is_road(x, y):
				color = Color("#c8b48a")
			draw_rect(ground, color)
	for item: Variant in session.town_map.plots:
		var plot: Dictionary = item
		var width := int(plot.get("w", 1))
		var height := int(plot.get("h", 1))
		var rect := Rect2(origin + Vector2(int(plot["x"]) * cell_size() + 2, int(plot["y"]) * cell_size() + 2), Vector2(width * cell_size() - 4, height * cell_size() - 4))
		var fill := _kind_color(String(plot["kind"]), bool(plot["enabled"]))
		if String(plot.get("venue", "")) == "western":
			fill = Color("#3f6f99")
		elif String(plot.get("venue", "")) == "chinese":
			fill = Color("#b84a3c")
		elif String(plot.get("supply", "")) != "":
			fill = _supply_color(String(plot.get("supply", "")), String(plot["kind"]) == "supply_factory")
		draw_rect(rect, fill)
		if String(plot["id"]) == String(_selected.get("id", "")) and String(plot["kind"]) != "housing":
			draw_rect(rect, Color("#f0cc70"), false, 3.0)
		if String(plot["kind"]) == "housing":
			continue
		if String(plot["kind"]) == "diner_lot":
			draw_rect(rect, Color("#f4e27a"), false, 3.0)
		var font := TDUI.font()
		if font != null:
			var at := rect.position + Vector2(6, maxf(18.0, rect.size.y * 0.55))
			draw_string(font, at, "%s  %d×%d" % [String(plot["name"]), width, height], HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 8, TDUI.FONT_CAPTION, Color.WHITE)
	if session != null:
		var shade := TDSanRules.vignette_alpha(float(session.san))
		if shade > 0.01:
			draw_rect(Rect2(_origin(), Vector2(session.town_map.extent * cell_size(), session.town_map.extent * cell_size())), Color(0, 0, 0, shade))

func _draw_economic_places() -> void:
	for plot: Dictionary in session.town_map.plots:
		if not plot.get("economic_courtyard",false): continue
		var floor_at:=_origin()+Vector2(plot.x,plot.y)*cell_size()
		for y: int in int(plot.h):
			for x: int in int(plot.w):
				var tile:=Rect2(floor_at+Vector2(x,y)*cell_size(),Vector2.ONE*cell_size())
				draw_rect(tile,Color("a99d7c"));draw_rect(tile.grow(-2),Color("b4a789"))
	for plot: Dictionary in session.town_map.plots:
		if str(plot.kind)=="bank":
			var bank_at:=_origin()+Vector2(plot.x,plot.y)*cell_size()
			var bank_size:=Vector2(plot.w,plot.h)*cell_size()
			draw_rect(Rect2(bank_at,bank_size),Color("a98f5e"))
			draw_rect(Rect2(bank_at,Vector2(bank_size.x,14)),Color("514837"))
			draw_rect(Rect2(bank_at+Vector2(bank_size.x*.5-9,bank_size.y-18),Vector2(18,16)),Color("483b2a"))
			draw_rect(Rect2(bank_at+Vector2(0,16),Vector2(bank_size.x,20)),Color("483b2a"))
			draw_string(TDUI.font(),bank_at+Vector2(2,31),"钱庄",HORIZONTAL_ALIGNMENT_CENTER,bank_size.x-4,TDUI.FONT_CAPTION,Color("f6d88a"))
		if not plot.has("economic_parcel_id"): continue
		var rect:=Rect2(_origin()+Vector2(plot.x,plot.y)*cell_size(),Vector2(plot.w,plot.h)*cell_size()).grow(-3)
		var constructing: bool=plot.get("construction",false)
		draw_rect(rect,Color("94744c") if constructing else Color("c5a57d"))
		if constructing:
			for x: int in range(4,int(rect.size.x),12): draw_rect(Rect2(rect.position+Vector2(x,4),Vector2(4,rect.size.y-8)),Color("564b39"))
		else:
			draw_rect(Rect2(rect.position,Vector2(rect.size.x,18)),Color("754937"))
			var door_height:=minf(34,rect.size.y*.42)
			draw_rect(Rect2(rect.position+Vector2(rect.size.x*.5-9,rect.size.y-door_height-2),Vector2(18,door_height)),Color("46392f"))
		var plate:=Rect2(rect.position+Vector2(0,20),Vector2(rect.size.x,22))
		draw_rect(plate,Color("443a2b"))
		draw_string(TDUI.font(),plate.position+Vector2(2,16),"施工中" if constructing else ("食堂" if plate.size.x<60 else "街坊食堂"),HORIZONTAL_ALIGNMENT_CENTER,plate.size.x-4,TDUI.FONT_MICRO,Color("f0d392"))

func _unhandled_input(event: InputEvent) -> void:
	if _closed or session == null:
		return
	if event.is_action_pressed("pause") and not event.is_echo():
		pause_requested.emit()
		get_viewport().set_input_as_handled()
		return
	if get_tree().paused:
		return
	if _talk_open():
		if event.is_action_pressed("pause") and not event.is_echo():
			_talk_view.finish_now()
			get_viewport().set_input_as_handled()
		return
	if not player_mode and event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT and not mouse.is_echo():
			_click_build(mouse)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("world_interact") and not event.is_echo():
		_interact()
		get_viewport().set_input_as_handled()

func close() -> void:
	_closed = true
	_dismiss_talk()
	if _camera != null:
		_camera.enabled = false
	set_process_unhandled_input(false)
	if _player != null:
		_player.set_controls_enabled(false)
	_close_venue_choice()
	_close_factory_panel()
	_close_backpack()

var authored_interaction: Callable
var crowd_label: Callable
signal crowd_requested(site_id: String)

func _crowd_site() -> String:
	return _crowd_stands.talk_site(_player.position, _player.facing) if _crowd_stands != null else ""

func _nearby_crowd() -> String:
	if crowd_label.is_valid() and not _crowd_site().is_empty():
		return str(crowd_label.call())
	return ""

func _interact() -> void:
	if external_story_frozen: return
	if at_chen_door():
		story_requested.emit("bowl" if story.beat=="bowl" else "chen");return
	var cell := _player_cell()
	var plot := session.town_map.plot_at(cell.x, cell.y)
	if player_mode:
		plot=facing_plot()
	elif plot.is_empty() or plot.get("economic_courtyard",false):
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var neighbor := session.town_map.plot_at(cell.x + step.x, cell.y + step.y)
			if not neighbor.is_empty() and String(neighbor["kind"]) != "housing" and not neighbor.get("economic_courtyard",false):
				plot = neighbor
				break
	var is_at_service_door := false
	if player_mode and not plot.is_empty() and plot.has("approach_x") and plot.has("approach_y"):
		var approach := _origin() + (Vector2(plot.approach_x,plot.approach_y) + Vector2.ONE * .5) * cell_size()
		is_at_service_door = _player.position.distance_to(approach) < CrowdStands.DOOR_CLEARANCE * .8
	var story_person := _story_faced() if player_mode and not is_at_service_door else ""
	if player_mode and not is_at_service_door and story_person.is_empty() and not _nearby_crowd().is_empty():
		crowd_requested.emit(_crowd_site())
		return
	if not story_person.is_empty():
		if authored_interaction.is_valid() and authored_interaction.call(story_person): return
		if story_requested.has_connections() and story!=null and not story.revised.is_empty():
			story_requested.emit(story_person)
		elif story!=null and story.started() and not story.finished():
			if story_requested.has_connections(): story_requested.emit(story_person)
			else: _open_talk(story.talk(story_person, hero_name, chapter_ready, session.san, story_board))
		elif characters!=null:
			characters.mark_met(story_person)
			_open_talk(characters.conversation(story_person))
		queue_redraw()
		return
	if plot.is_empty() or String(plot.kind) in TDInteractionRange.RESIDENTIAL_KINDS:
		return
	_selected = plot
	var kind := String(plot["kind"])
	if management_menus and kind in ["factory_lot","supply_factory"]: return
	if player_mode:
		if kind=="player_cottage": place_requested.emit("cottage",str(plot.id));return
		if kind=="player_diner" and String(plot.get("id",""))=="player_diner":
			restaurant_requested.emit()
			return
		if kind=="supply_factory":
			_open_factory_panel(plot)
			return
		if kind=="factory_lot":
			var built := session.click_build_at(Vector2i(int(plot["x"]), int(plot["y"])))
			_set_status(built.message if built.message != "" else built.code)
			queue_redraw()
			return
		if kind=="diner_lot":
			_open_venue_choice()
			return
		place_requested.emit(kind, String(plot.get("id", "")))
		return
	if kind == "diner_lot":
		_set_status("餐厅建设区还是空地。点击这块地，选择中餐厅或西餐厅。")
		return
	if kind == "factory_lot":
		var built := session.click_build_at(Vector2i(int(plot["x"]), int(plot["y"])))
		_set_status(built.message if built.message != "" else built.code)
		queue_redraw()
		return
	if kind == "supply_factory":
		_open_factory_panel(plot)
		return
	if kind == "player_diner":
		var size_id := String(plot.get("size", session.home_size))
		if size_id == "":
			size_id = "small"
		var room := TDRestaurantSizes.interior(size_id)
		if String(plot.get("id", "")) == "branch_diner":
			_set_status("这是分店，地图%d×%d，店内%d×%d。菜单、员工和库存跟主店分开。" % [int(plot["w"]), int(plot["h"]), room.x, room.y])
		else:
			_set_status("这是%s，地图%d×%d。走到店里就能进去。" % [String(plot.get("name", "餐厅")), int(plot["w"]), int(plot["h"])])
		return
	if kind == "market":
		var picked := session.select_market(String(plot["id"]))
		_set_status(picked.message if picked.message != "" else picked.code)
		return
	if kind == "competitor":
		var names := ""
		if not session.competitors.is_empty():
			var rival: Dictionary = session.competitors[0]
			names = String(rival["name"])
		_set_status("竞品%s。客人会比较你和两家竞品菜单上的每一道菜。" % names)
		return
	var enabled := "计入客流" if bool(plot["enabled"]) else "不计入客流"
	var offer := TDSanRules.recovery(kind)
	var visit := ""
	if not offer.is_empty():
		visit = " 花%d元、%.0f小时可回复%d点SAN。" % [int(offer["cost"]), float(offer["hours"]), int(offer["san"])]
	var near := ""
	if kind == "amusement" or kind == "landmark":
		near = " 离餐厅%d格，预计人气加成%d。" % [session.town_map.distance_to(String(plot["id"])), TDSanRules.near_bonus(session.town_map.distance_to(String(plot["id"])))]
	_set_status("%s，%s。人数贡献%d，预算平移%d。%s%s" % [String(plot["name"]), enabled, int(plot["pool"]), int(plot["budget_shift"]), visit, near])

func _walkable(x: int, y: int) -> bool:
	if player_mode and session.town_map.layout_version == 2:
		return x >= 0 and y >= 0 and x < session.town_map.extent and y < session.town_map.extent and bool(session.town_map.terrain_at(Vector2i(x, y)).walkable)
	if management_menus:
		var plot:=session.town_map.plot_at(x,y)
		if plot.get("kind","") in ["factory_lot","supply_factory"]: return session.town_map.terrain_at(Vector2i(x,y)).walkable
	return session.town_map.is_walkable(x,y)

func _build_blockers() -> void:
	if _blockers != null and is_instance_valid(_blockers):
		remove_child(_blockers)
		_blockers.queue_free()
	if _facade_layer != null:
		remove_child(_facade_layer)
		_facade_layer.queue_free()
	_solid_bases.clear()
	_interactable_facades.clear()
	_contact_bins.clear()
	_reference_doorways.clear()
	_reference_navigation = null
	_jiangnan_details.clear()
	if player_mode:
		if TDPlannedTown.approved(session.town_map) and _reference_map == null:
			_reference_map = TDJiangnanReferenceArt.make_scene()
			_reference_map.position = _origin()
			_reference_map.modulate = self_modulate
			add_child(_reference_map)
			_reference_map.get_node("Atmosphere").set_minute(day_minute)
			_sun_shadows = _reference_map.get_node_or_null("SunShadows")
			if _sun_shadows != null: _sun_shadows.set_day_minute(day_minute)
		_facades = TDTownArt.facades(session.town_map, cell_size(), _origin(), management_menus)
		_facade_layer = Node2D.new()
		_facade_layer.y_sort_enabled = true
		_facade_layer.modulate = self_modulate
		add_child(_facade_layer)
		var local_detail := session.town_map.region_id.is_empty() and session.town_map.layout_version == 2 \
			and not TDPlannedTown.approved(session.town_map)
		for item: Dictionary in _facades:
			_solid_bases.append_array(item.get("walking",item.bases))
			var plot: Dictionary = item.get("plot", {})
			if TDInteractionRange.facility(plot) and not _interactable_facades.has(plot.id):
				var rect: Rect2 = item.rect
				var frontage := Rect2(Vector2(rect.position.x, rect.end.y - 12.0), Vector2(rect.size.x, 12.0))
				if not item.bases.is_empty():
					frontage = item.bases[0]
					for base: Rect2 in item.bases:
						frontage = frontage.merge(base)
				item.interaction_frontage = frontage
				_interactable_facades[plot.id] = item
			if item.get("reference_id","") in ["diner","bank","chen-food-shop","inn","harbor-terminal"]:
				var service: Dictionary = item.get("plot",{})
				if not service.is_empty():
					var bounds: Rect2 = item.rect
					_reference_doorways.append({
						"plot":service,"point":Vector2(bounds.get_center().x,bounds.end.y+FOOT_RADIUS+2.0)})
			if item.has("reference_id"): continue
			var feature: String = item.get("jiangnan_feature", "") if local_detail else ""
			if feature != "cloth_sign":
				var sprite := TDEnvironmentArt.facade_sprite(item.art, item.rect, item.get("tint", Color.WHITE))
				if item.has("sort_y"):
					sprite.offset.y += (sprite.position.y - float(item.sort_y)) / sprite.scale.y
					sprite.position.y = float(item.sort_y)
				_facade_layer.add_child(sprite)
				if local_detail:
					if item.get("plot",{}).get("id","")=="hotel":
						TDTownArt.JiangnanDistrictProps.add_inn_banner(sprite)
			if feature in JiangnanAmbience.FEATURES:
				var detail := JiangnanAmbience.new()
				detail.configure(item)
				_facade_layer.add_child(detail)
				_jiangnan_details.append(detail)
		if not _jiangnan_details.is_empty(): _sample_jiangnan_details()
	var body := StaticBody2D.new()
	_blockers = body
	body.collision_layer = 16
	body.collision_mask = 0
	add_child(body)
	# Merge solid horizontal spans, keeping topology exact without thousands of bodies.
	# The approved shoreline uses swept foot samples instead of whole tiles.
	if not (player_mode and TDPlannedTown.approved(session.town_map)):
		for y: int in session.town_map.extent:
			var x: int=0
			while x<session.town_map.extent:
				if _walkable(x,y): x+=1;continue
				var first: int=x
				while x<session.town_map.extent and not _walkable(x,y): x+=1
				var shape:=RectangleShape2D.new();shape.size=Vector2((x-first)*cell_size(),cell_size())
				var collider:=CollisionShape2D.new();collider.shape=shape
				collider.position=_origin()+Vector2((first+x)*.5*cell_size(),(y+.5)*cell_size())
				body.add_child(collider)
	for bounds: Rect2 in _solid_bases:
		var expanded := bounds.grow(NPC_FOOT_RADIUS)
		var first := Vector2i((expanded.position/CONTACT_BIN).floor())
		var last := Vector2i((expanded.end/CONTACT_BIN).floor())
		for y: int in range(first.y,last.y+1):
			for x: int in range(first.x,last.x+1):
				var bin := Vector2i(x,y)
				if not _contact_bins.has(bin): _contact_bins[bin]=[]
				_contact_bins[bin].append(bounds)
		var shape:=RectangleShape2D.new();shape.size=bounds.size
		var collision:=CollisionShape2D.new();collision.shape=shape;collision.position=bounds.get_center()
		body.add_child(collision)
	if characters != null:
		characters.foot_clear = _reference_escort_can_stand if player_mode else Callable()
		characters.step_clear = _resident_step_clear if player_mode else Callable()
		characters.sync_map(session.town_map)
	if player_mode and TDPlannedTown.approved(session.town_map):
		if _hertz == null:
			_hertz = TDStoryArt.TownActor.new()
			_hertz.name = "Hertz"
			add_child(_hertz)
		var harbor := _origin() + (Vector2(TDHarbor.ARRIVAL) + Vector2.ONE * .5) * cell_size()
		_hertz.place("hertz", OUTDOOR_PERSON_HEIGHT, harbor, _npc_can_stand)
		_hertz.modulate = self_modulate
		if _crowd_stands == null:
			_crowd_stands = CrowdStands.new()
			_crowd_stands.name = "CrowdStands"
			_crowd_stands.y_sort_enabled = true
			add_child(_crowd_stands)
		_crowd_stands.refresh(CrowdStands.jiangnan_sites(_facades), _can_stand, OUTDOOR_PERSON_HEIGHT)
		_crowd_stands.modulate = self_modulate

func _sample_jiangnan_details() -> void:
	var view_rect := get_global_transform_with_canvas().affine_inverse() * get_viewport_rect()
	var daylight := TDDaylight.sample(day_minute)
	for detail: JiangnanAmbience in _jiangnan_details:
		detail.sample(view_rect, day_minute, daylight)

func _status_bar() -> void:
	var layer := CanvasLayer.new()
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	var view := get_viewport().get_visible_rect().size
	if view.x < 8.0 or view.y < 8.0:
		return
	_pack_button = _button("背包 0", _open_backpack)
	if player_mode:
		_building_nameplate = BuildingNameplate.new()
		layer.add_child(_building_nameplate)
		layer.add_child(_pack_button)
		_pack_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
		_pack_button.offset_left = 16
		_pack_button.offset_top = -52
		_paint_backpack_count()
		return
	_status_panel = Panel.new()
	_status_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar := _glass(18)
	bar.set_corner_radius_all(0)
	bar.border_color = Color(0.74, 0.88, 1.0, 0.28)
	_status_panel.add_theme_stylebox_override("panel", bar)
	_status_panel.theme = _glass_theme()
	layer.add_child(_status_panel)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.position = Vector2(16, 8)
	box.size = Vector2(maxf(1.0, view.x - 32.0), BAR_HEIGHT - 16.0)
	_status_panel.add_child(box)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(view.x - 32.0, 28)
	_status.add_theme_font_size_override("font_size", TDUI.FONT_CAPTION)
	_status.add_theme_color_override("font_color", GLASS_INK)
	box.add_child(_status)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	row.add_child(_button("返回", func() -> void: back_requested.emit()))
	row.add_child(_pack_button)
	_paint_backpack_count()
	_place_status_bar()
	if not get_viewport().size_changed.is_connected(_place_status_bar):
		get_viewport().size_changed.connect(_place_status_bar)

func _place_status_bar() -> void:
	if _status_panel == null or not is_instance_valid(_status_panel):
		return
	var view := get_viewport().get_visible_rect().size
	if view.x < 8.0 or view.y < 8.0:
		return
	var bar_h := float(BAR_HEIGHT)
	_status_panel.position = Vector2(0, maxf(0.0, view.y - bar_h))
	_status_panel.size = Vector2(view.x, minf(bar_h, view.y))
	var box := _status_panel.get_child(0) as Control
	if box != null:
		box.size = Vector2(maxf(1.0, view.x - 32.0), minf(bar_h, view.y) - 16.0)
	_layout_factory_panel()
	_follow_camera()

func _keep_player_on_map() -> void:
	if _player == null or session == null:
		return
	var cell := _player_cell()
	if _can_stand(_player.position):
		return
	var best := Vector2i(TDTownMap.CENTER, TDTownMap.CENTER)
	var distance := INF
	for y: int in session.town_map.extent:
		for x: int in session.town_map.extent:
			if not _can_stand(_origin() + (Vector2(x,y) + Vector2(0.5,0.5)) * cell_size()):
				continue
			var score := Vector2(x, y).distance_squared_to(Vector2(cell))
			if score < distance:
				distance = score
				best = Vector2i(x, y)
	_player.position = _origin() + (Vector2(best) + Vector2(0.5, 0.5)) * cell_size()
	_player.velocity = Vector2.ZERO

func _player_step_clear(at: Vector2) -> bool:
	return _feet_on_road(at) and _other_people_clear(_player.position,at,"",null)

func _feet_on_road(at: Vector2) -> bool:
	return session!=null and TDInteractionRange.ground_segment_clear(_player.position,at,_can_stand)

func _can_stand(at: Vector2) -> bool:
	return _ground_clear(at,FOOT_RADIUS)

func _npc_can_stand(at: Vector2) -> bool:
	return _ground_clear(at,NPC_FOOT_RADIUS)

func _ground_clear(at: Vector2, radius: float) -> bool:
	if not player_mode:
		var cell := _cell_at(at)
		return _walkable(cell.x, cell.y)
	for offset: Vector2 in TDEnvironmentArt.FOOT_SAMPLES:
		if not _walkable_point(at + offset * radius): return false
	for bounds: Rect2 in _contact_bins.get(Vector2i((at/CONTACT_BIN).floor()),[]):
		if TDEnvironmentArt.overlaps_base(at,bounds,radius): return false
	return true

func _other_people_clear(from: Vector2, to: Vector2, own_id: String, mover: TDStoryArt.TownActor) -> bool:
	var spacing := TDInteractionRange.NPC_SPACING
	if not own_id.is_empty() and visible and not TDInteractionRange.npc_clear(from,to,_player.position,spacing): return false
	for actor: TDStoryArt.TownActor in [_hertz,_luo]:
		if actor!=null and actor!=mover and actor.visible and not TDInteractionRange.npc_clear(from,to,actor.position,spacing): return false
	var escort := get_meta("revised_escort",null) as TDStoryArt.TownActor if has_meta("revised_escort") else null
	if is_instance_valid(escort) and escort!=mover and escort.visible and not TDInteractionRange.npc_clear(from,to,escort.position,spacing): return false
	for person: Dictionary in _story_people():
		if person.id==own_id or int(person.cell.x)<0: continue
		if not TDInteractionRange.npc_clear(from,to,_person_feet(person),spacing): return false
	return _crowd_stands==null or _crowd_stands.clear_step(from,to,spacing)

func npc_step_clear(from: Vector2, to: Vector2, actor: TDStoryArt.TownActor) -> bool:
	return TDInteractionRange.ground_segment_clear(from,to,_npc_can_stand) and _other_people_clear(from,to,actor.actor_id,actor)

func _resident_step_clear(id: String, from: Vector2, to: Vector2) -> bool:
	return _other_people_clear(_origin()+from*cell_size(),_origin()+to*cell_size(),id,null)

func _walkable_point(at: Vector2) -> bool:
	if _reference_map != null:
		return TDJiangnanReferenceArt.terrain_walkable(_reference_map, at - _origin())
	var cell := _cell_at(at)
	return _walkable(cell.x, cell.y)

func _player_cell() -> Vector2i:
	return _cell_at(_player.position)

func _cell_at(at: Vector2) -> Vector2i:
	var local := at - _origin()
	return Vector2i(floori(local.x / cell_size()), floori(local.y / cell_size()))

func _origin() -> Vector2:
	return Vector2(300, 24)

func _click_build(mouse: InputEventMouse) -> void:
	if session == null or _player == null:
		return
	_click_plot(_plot_under(_world_from_pointer(mouse)))

func _click_plot(plot: Dictionary) -> void:
	var kind := String(plot.get("kind", ""))
	if player_mode or kind in TDInteractionRange.RESIDENTIAL_KINDS:
		return
	if kind == "factory_lot" or kind == "supply_factory":
		_selected = plot
		_set_status("靠近%s，按 E %s。" % [String(plot.get("name", "原料厂")), "建设" if kind == "factory_lot" else "安排生产"])
		queue_redraw()
		return
	if kind == "diner_lot":
		_selected = plot
		_open_venue_choice()
		return
	if kind == "player_diner" and String(plot.get("id", "")) == "player_diner":
		_selected = plot
		_set_status("走到%s上就能进去。" % String(plot.get("name", "餐厅")))
		return
	if not plot.is_empty() and kind != "housing":
		_selected = plot
		_set_status("选中了%s。餐厅建设区请点空地；原料厂请靠近后按 E。" % String(plot.get("name", kind)))

func _world_from_pointer(_mouse: InputEventMouse) -> Vector2:
	if _camera != null and _camera.has_method("force_update_scroll"):
		_camera.force_update_scroll()
	return get_global_mouse_position()

func _buildable(plot: Dictionary) -> bool:
	var kind := String(plot.get("kind", ""))
	return kind == "factory_lot" or kind == "supply_factory" or kind == "diner_lot" or kind == "player_diner"

func _plot_under(world: Vector2) -> Dictionary:
	if session == null:
		return {}
	var direct := session.town_map.plot_at(_cell_at(world).x, _cell_at(world).y)
	if _buildable(direct):
		return direct
	for item: Variant in session.town_map.plots:
		var plot: Dictionary = item
		var rect := Rect2(_origin() + Vector2(float(int(plot["x"])) * cell_size(), float(int(plot["y"])) * cell_size()), Vector2(float(int(plot["w"])) * cell_size(), float(int(plot["h"])) * cell_size()))
		if not rect.grow(12.0).has_point(world):
			continue
		if _buildable(plot):
			return plot.duplicate(true)
	return direct

func _kind_color(kind: String, enabled: bool) -> Color:
	var color := Color("#888888")
	match kind:
		"diner_lot":
			color = Color("#e08a5a")
		"factory_lot":
			color = Color("#8fbf5a")
		"supply_factory":
			color = Color("#3d7a45")
		"player_diner":
			color = Color("#c45b4a")
		"competitor":
			color = Color("#8d5a3c")
		"market":
			color = Color("#d4a017")
		"urban_village":
			color = Color("#6f8f71")
		"rich_district":
			color = Color("#e6c98a")
		"commercial_street":
			color = Color("#7a1e2b")
		"snack_street":
			color = Color("#e07a3d")
		"amusement":
			color = Color("#3f6f8f")
		"zoo":
			color = Color("#3e5160")
		"landmark":
			color = Color("#6a1b2a")
		"housing":
			color = Color("#9a7b5a")
		_:
			color = Color("#888888")
	if not enabled:
		color = color.darkened(0.45)
	return color

func _supply_color(supply: String, built: bool) -> Color:
	return TDTownMap.supply_color(supply, built)

func _enter_hint() -> String:
	if session == null or session.town_map.diner_lot().is_empty():
		return "小镇已进入，但餐厅建设区没生成。看底部栏能否返回。"
	return "已进入小镇。点击橙色餐厅建设区，选择中餐厅或西餐厅。原料厂分四类：金色调料、绿色蔬菜、红色肉类、橙色水果，各两块，靠近空地按 E 建设。"

func _open_venue_choice() -> void:
	if session == null:
		return
	if session.home_built:
		_set_status("餐厅已经建好。走到店里就能进去。")
		return
	if session.town_id != session.home_town_id:
		_set_status("只能在主小镇的餐厅建设区建店。")
		return
	_close_venue_choice()
	_venue_layer = CanvasLayer.new()
	_venue_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_venue_layer)
	var panel := Panel.new()
	panel.position = Vector2(390, 180)
	panel.size = Vector2(500, 150)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.theme = _glass_theme()
	var shell := _glass(16)
	panel.add_theme_stylebox_override("panel", shell)
	_venue_layer.add_child(panel)
	var box := VBoxContainer.new()
	box.position = Vector2(16, 12)
	box.size = Vector2(468, 126)
	panel.add_child(box)
	var title := Label.new()
	title.text = "在建设区建立哪一类餐厅？初始只占这块地的四分之一。"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	row.add_child(_button("中餐厅", func() -> void: _pick_venue("chinese")))
	row.add_child(_button("西餐厅", func() -> void: _pick_venue("western")))
	row.add_child(_button("取消", _close_venue_choice))

func _pick_venue(venue: String) -> void:
	_close_venue_choice()
	if session == null:
		return
	var result := session.build_venue(venue)
	_set_status(result.message if result.message != "" else result.code)
	queue_redraw()

func _close_venue_choice() -> void:
	if _venue_layer != null and is_instance_valid(_venue_layer):
		_venue_layer.queue_free()
	_venue_layer = null

func _open_factory_panel(plot: Dictionary) -> void:
	_close_factory_panel()
	_close_backpack()
	_close_venue_choice()
	if session == null:
		return
	var supply := String(plot.get("supply", ""))
	var products := session.factory_products(supply)
	_factory_plot = String(plot.get("id", ""))
	_factory_rows = {}
	_factory_hover_id = ""
	_factory_accent = _supply_color(supply, true)
	var view := get_viewport().get_visible_rect().size
	var panel_size := Vector2(minf(1100.0, view.x - 36.0), minf(620.0, view.y - BAR_HEIGHT - 28.0))
	_factory_layer = CanvasLayer.new()
	_factory_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_factory_layer)
	var dim := ColorRect.new()
	_factory_dim = dim
	dim.color = GLASS_DIM
	dim.size = view
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_factory_dim_input)
	_factory_layer.add_child(dim)
	var panel := PanelContainer.new()
	_factory_shell = panel
	panel.position = Vector2((view.x - panel_size.x) * 0.5, maxf(16.0, (view.y - BAR_HEIGHT - panel_size.y) * 0.45))
	panel.size = panel_size
	panel.custom_minimum_size = panel_size
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.theme = _glass_theme()
	var shell := _glass(18)
	shell.content_margin_left = 22
	shell.content_margin_right = 22
	shell.content_margin_top = 18
	shell.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", shell)
	_factory_layer.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var stripe := ColorRect.new()
	stripe.custom_minimum_size = Vector2(0, 4)
	stripe.color = GLASS_BLUE
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(stripe)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	box.add_child(header)
	var title := Label.new()
	title.text = String(plot.get("name", "原料厂"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_override("font", _glass_font(600))
	title.add_theme_font_size_override("font_size", TDUI.FONT_TITLE)
	title.add_theme_color_override("font_color", GLASS_INK)
	header.add_child(title)
	_factory_level_label = Label.new()
	_factory_level_label.add_theme_font_size_override("font_size", TDUI.FONT_CAPTION)
	_factory_level_label.add_theme_color_override("font_color", GLASS_BLUE)
	header.add_child(_factory_level_label)
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 8)
	box.add_child(stats)
	_factory_cash = _stat_chip(stats, "现金")
	_factory_time = _stat_chip(stats, "产线")
	_factory_pack = _stat_chip(stats, "背包")
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(body)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_stretch_ratio = 1.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	body.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)
	for item: Variant in products:
		var row_item: Dictionary = item
		grid.add_child(_factory_card(String(row_item.get("id", ""))))
	if products.is_empty(): grid.add_child(TDUI.label("暂无可供货原料\n解锁相关菜谱后会增加品种。",TDUI.FONT_BODY))
	_factory_hover = Label.new()
	_factory_hover.text = "拖到右侧产线"
	_factory_hover.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_factory_hover.add_theme_font_size_override("font_size", TDUI.FONT_CAPTION)
	_factory_hover.add_theme_color_override("font_color", GLASS_MUTED)
	box.add_child(_factory_hover)
	body.add_child(_factory_status_panel())
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	box.add_child(actions)
	_factory_upgrade = _factory_button("升级厂房", _upgrade_open_factory, _factory_accent, 220)
	actions.add_child(_factory_upgrade)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)
	actions.add_child(_factory_button("关闭", _close_factory_panel, GLASS_BLUE, 120))
	_refresh_factory_panel()

func _stat_chip(parent: Node, caption: String) -> Label:
	var chip := PanelContainer.new()
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := _glass_card(10)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	chip.add_theme_stylebox_override("panel", style)
	parent.add_child(chip)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	chip.add_child(column)
	var cap := Label.new()
	cap.text = caption
	cap.add_theme_font_size_override("font_size", TDUI.FONT_CAPTION)
	cap.add_theme_color_override("font_color", GLASS_MUTED)
	column.add_child(cap)
	var value := Label.new()
	value.add_theme_font_size_override("font_size", TDUI.FONT_BODY)
	value.add_theme_color_override("font_color", GLASS_INK)
	column.add_child(value)
	return value

func _factory_card(item_id: String) -> FactoryDrag:
	var card := FactoryDrag.new()
	card.item_id = item_id
	card.item_name = String(session._supply_item(item_id).get("name", item_id))
	card.host = self
	card.custom_minimum_size = Vector2(76, 76)
	card.mouse_entered.connect(_hover_factory_goods.bind(item_id))
	card.mouse_exited.connect(_leave_factory_goods.bind(item_id))
	var style := _glass_card(12)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	card.add_theme_stylebox_override("panel", style)
	var icon := _product_icon(item_id, 64)
	icon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	icon.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_child(icon)
	_factory_rows[item_id] = {"card": card}
	return card

func _hover_factory_goods(item_id: String) -> void:
	_factory_hover_id = item_id
	_paint_factory_row(item_id)

func _leave_factory_goods(item_id: String) -> void:
	if _factory_hover_id != item_id:
		return
	_factory_hover_id = ""
	if _factory_hover != null and is_instance_valid(_factory_hover):
		_factory_hover.text = "拖到右侧产线"
		_factory_hover.add_theme_color_override("font_color", GLASS_MUTED)

func _factory_button(text: String, callback: Callable, _accent: Color, width: int) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(width, 40)
	button.add_theme_font_size_override("font_size", TDUI.FONT_CAPTION)
	button.add_theme_color_override("font_color", GLASS_INK)
	button.add_theme_color_override("font_disabled_color", Color(0.78, 0.86, 0.96, 0.55))
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		var bg := Color(0.22, 0.42, 0.74, 0.5)
		var edge := GLASS_EDGE
		if state == "hover":
			bg = Color(0.34, 0.58, 0.92, 0.72)
		elif state == "pressed":
			bg = Color(0.16, 0.34, 0.64, 0.82)
		elif state == "disabled":
			bg = Color(0.14, 0.2, 0.32, 0.35)
			edge = Color(1, 1, 1, 0.12)
		var style := _flat(bg, edge, 10, 1)
		style.content_margin_left = 8
		style.content_margin_right = 8
		style.content_margin_top = 4
		style.content_margin_bottom = 4
		button.add_theme_stylebox_override(state, style)
	button.pressed.connect(callback)
	return button

func _flat(bg: Color, border: Color, radius: int, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	return style

func _glass(radius: int) -> StyleBoxFlat:
	var style := _flat(GLASS, GLASS_EDGE, radius, 1)
	style.shadow_color = Color(0.04, 0.1, 0.24, 0.32)
	style.shadow_size = 18
	style.shadow_offset = Vector2(0, 8)
	return style

func _glass_card(radius: int) -> StyleBoxFlat:
	return _flat(GLASS_CARD, Color(1, 1, 1, 0.18), radius, 1)

func _glass_font(weight: int = 400) -> Font:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["SimHei"])
	font.font_weight = weight
	font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	font.hinting = TextServer.HINTING_LIGHT
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	return font

func _glass_theme() -> Theme:
	var theme := TDUI.theme()
	var body := _glass_font(400)
	theme.default_font = body
	theme.default_font_size = TDUI.FONT_BODY
	theme.set_font("font", "Label", body)
	theme.set_font("font", "Button", body)
	theme.set_font_size("font_size", "Label", TDUI.FONT_BODY)
	theme.set_font_size("font_size", "Button", TDUI.FONT_CAPTION)
	theme.set_color("font_color", "Label", GLASS_INK)
	theme.set_color("font_color", "Button", GLASS_INK)
	theme.set_constant("line_spacing", "Label", 3)
	return theme

func _on_factory_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			_close_factory_panel()

func _refresh_factory_panel() -> void:
	if session == null or _factory_cash == null or not is_instance_valid(_factory_cash):
		return
	var level := session.factory_level_of(_factory_plot)
	_factory_level_label.text = "%d级 · %d条产线" % [level, session.factory_lines(_factory_plot)]
	_factory_cash.text = "¥%.2f" % (float(balance_reader.call())/100.0) if balance_reader.is_valid() else "%d元" % session.money
	_paint_factory_pack()
	_paint_factory_job()
	if _factory_upgrade != null and is_instance_valid(_factory_upgrade):
		if level >= TDTownMap.FACTORY_LEVEL_MAX:
			_factory_upgrade.text = "厂房已满级"
			_factory_upgrade.disabled = true
		else:
			_factory_upgrade.text = "升级 +1条产线   %d元" % [30 * level]
			_factory_upgrade.disabled = false
	for item_id: Variant in _factory_rows.keys():
		_paint_factory_row(String(item_id))

func _paint_factory_row(item_id: String) -> void:
	var row: Dictionary = _factory_rows.get(item_id, {})
	if row.is_empty():
		return
	var unit := session.factory_quote(item_id)
	var each := session.factory_hours(_factory_plot, item_id, 1)
	var card := row["card"] as Control
	var name := String(session._supply_item(item_id).get("name", item_id))
	var package: String=str(session._supply_item(item_id).get("unit","份"))
	var cost := "%s\n%d元/%s\n%.1f小时/%s" % [name, unit,package, each,package]
	if card != null:
		card.tooltip_text = cost
	if _factory_hover_id == item_id and _factory_hover != null and is_instance_valid(_factory_hover):
		_factory_hover.text = "%s    %d元/%s    %.1f小时/%s" % [name, unit,package, each,package]
		_factory_hover.add_theme_color_override("font_color", GLASS_INK)

func _factory_status_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 2.0
	var style := _glass_card(12)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	var title := Label.new()
	title.text = "正在生产"
	title.add_theme_font_override("font", _glass_font(600))
	title.add_theme_font_size_override("font_size", TDUI.FONT_BODY)
	title.add_theme_color_override("font_color", GLASS_INK)
	column.add_child(title)
	_factory_mill = FactoryMill.new()
	_factory_mill.host = self
	_factory_mill.custom_minimum_size = Vector2(0, 220)
	_factory_mill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_factory_mill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_factory_mill)
	return panel

func _paint_factory_job() -> void:
	if session == null or _factory_mill == null or not is_instance_valid(_factory_mill):
		return
	var lines := session.factory_lines(_factory_plot)
	var running := session.factory_running(_factory_plot)
	if _factory_time != null and is_instance_valid(_factory_time):
		_factory_time.text = "%d / %d" % [running.size(), lines]
	var by_line := {}
	for item: Variant in running:
		var loaded: Dictionary = item
		by_line[int(loaded.get("line", 0))] = loaded
	var lanes: Array = []
	for line in lines:
		var number := line + 1
		var job: Dictionary = by_line.get(number, {})
		var unit_hours := float(job.get("unit_hours", 0.0))
		var unit_elapsed := float(job.get("unit_elapsed", 0.0))
		if unit_hours <= 0.001 and not job.is_empty():
			var pieces := maxi(int(job.get("qty", 1)), 1)
			unit_hours = float(job.get("total_hours", 0.0)) / float(pieces)
			unit_elapsed = float(job.get("elapsed_hours", 0.0))
		var ratio := 0.0 if unit_hours <= 0.001 else clampf(unit_elapsed / unit_hours, 0.0, 1.0)
		lanes.append({
			"running": not job.is_empty(),
			"ratio": ratio,
			"left": int(job.get("qty", 0)),
			"item_id": String(job.get("item_id", "")),
		})
	_factory_mill.lanes = lanes
	_paint_factory_pack()

func _paint_factory_pack() -> void:
	_paint_backpack_count()
	if _factory_pack == null or not is_instance_valid(_factory_pack) or session == null:
		return
	var parts: PackedStringArray = []
	for item: Variant in session.factory_goods():
		var row: Dictionary = item
		parts.append("%s×%d" % [String(row.get("name", "")), int(row.get("qty", 0))])
	_factory_pack.text = "空" if parts.is_empty() else "  ".join(parts)
	_factory_pack.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _paint_backpack_count() -> void:
	if _pack_button == null or not is_instance_valid(_pack_button) or session == null:
		return
	var total := 0
	for item: Variant in session.factory_goods():
		total += int((item as Dictionary).get("qty", 0))
	_pack_button.text = "背包 %d" % total
	if player_mode: _pack_button.visible=total>0

func _ask_factory_qty(line_no: int, item_id: String) -> void:
	if session == null or item_id == "":
		return
	for item: Variant in session.factory_running(_factory_plot):
		var job: Dictionary = item
		if int(job.get("line", 0)) == line_no:
			_set_status("产线%d正在生产%s。" % [line_no, String(job.get("name", ""))])
			return
	_close_qty_dialog()
	_qty_item = item_id
	_qty_line = line_no
	_qty_count = TDTownMap.FACTORY_QTY_MIN
	var view := get_viewport().get_visible_rect().size
	_qty_layer = CanvasLayer.new()
	_qty_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	_qty_layer.layer = 20
	add_child(_qty_layer)
	var dim := ColorRect.new()
	dim.color = GLASS_DIM
	dim.size = view
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_qty_layer.add_child(dim)
	var panel := PanelContainer.new()
	var panel_size := Vector2(420, 220)
	panel.position = Vector2((view.x - panel_size.x) * 0.5, (view.y - BAR_HEIGHT - panel_size.y) * 0.45)
	panel.size = panel_size
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.theme = _glass_theme()
	var shell := _glass(16)
	shell.content_margin_left = 20
	shell.content_margin_right = 20
	shell.content_margin_top = 16
	shell.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", shell)
	_qty_layer.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var name := String(session._supply_item(item_id).get("name", item_id))
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 10)
	heading.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(heading)
	heading.add_child(_product_icon(item_id, 40))
	var title := Label.new()
	title.text = "产线%d 生产%s" % [line_no, name]
	title.add_theme_font_override("font", _glass_font(600))
	title.add_theme_font_size_override("font_size", TDUI.FONT_SECTION)
	title.add_theme_color_override("font_color", GLASS_INK)
	heading.add_child(title)
	var stepper := HBoxContainer.new()
	stepper.add_theme_constant_override("separation", 8)
	stepper.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(stepper)
	stepper.add_child(_factory_button("−", _lower_factory_qty, GLASS_BLUE, 48))
	var count := Label.new()
	count.name = "QtyCount"
	count.custom_minimum_size = Vector2(48, 0)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count.add_theme_font_size_override("font_size", TDUI.FONT_SECTION)
	count.add_theme_color_override("font_color", GLASS_INK)
	stepper.add_child(count)
	stepper.add_child(_factory_button("+", _raise_factory_qty, GLASS_BLUE, 48))
	_qty_summary = Label.new()
	_qty_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_qty_summary.add_theme_font_size_override("font_size", TDUI.FONT_CAPTION)
	_qty_summary.add_theme_color_override("font_color", GLASS_MUTED)
	box.add_child(_qty_summary)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	box.add_child(actions)
	actions.add_child(_factory_button("确定", _confirm_factory_qty, GLASS_BLUE, 120))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)
	actions.add_child(_factory_button("取消", _close_qty_dialog, GLASS_BLUE, 120))
	_paint_qty_dialog()

func _raise_factory_qty() -> void:
	_qty_count = mini(_qty_count + 1, TDTownMap.FACTORY_QTY_MAX)
	_paint_qty_dialog()

func _lower_factory_qty() -> void:
	_qty_count = maxi(_qty_count - 1, TDTownMap.FACTORY_QTY_MIN)
	_paint_qty_dialog()

func _paint_qty_dialog() -> void:
	if _qty_layer == null or not is_instance_valid(_qty_layer) or session == null:
		return
	var count := _qty_layer.find_child("QtyCount", true, false) as Label
	if count != null:
		count.text = str(_qty_count)
	if _qty_summary != null and is_instance_valid(_qty_summary):
		var unit := session.factory_quote(_qty_item)
		var each := session.factory_hours(_factory_plot, _qty_item, 1)
		var package: String=str(session._supply_item(_qty_item).get("unit","份"))
		_qty_summary.text = "共%d%s，%d元。每%s%.1f小时，完成后送入库存。" % [_qty_count,package,unit * _qty_count,package,each]

func _confirm_factory_qty() -> void:
	if session == null:
		return
	var result: TDOutcome = transaction_sink.call(session.produce_factory.bind(_factory_plot, _qty_item, _qty_count, _qty_line),"工厂生产") if transaction_sink.is_valid() else session.produce_factory(_factory_plot, _qty_item, _qty_count, _qty_line)
	_set_status(result.message if result.message != "" else result.code)
	_close_qty_dialog()
	_refresh_factory_panel()

func _close_qty_dialog() -> void:
	if _qty_layer != null and is_instance_valid(_qty_layer):
		_qty_layer.queue_free()
	_qty_layer = null
	_qty_summary = null

func _upgrade_open_factory() -> void:
	var result: TDOutcome = transaction_sink.call(session.upgrade_factory.bind(_factory_plot),"工厂升级") if transaction_sink.is_valid() else session.upgrade_factory(_factory_plot)
	_set_status(result.message if result.message != "" else result.code)
	_refresh_factory_panel()

func _layout_factory_panel() -> void:
	if _factory_layer == null or not is_instance_valid(_factory_layer):
		return
	var view := get_viewport().get_visible_rect().size
	if view.x < 8.0 or view.y < 8.0:
		return
	if _factory_dim != null and is_instance_valid(_factory_dim):
		_factory_dim.size = view
	if _factory_shell != null and is_instance_valid(_factory_shell):
		var panel_size := Vector2(minf(1100.0, maxf(320.0, view.x - 36.0)), minf(620.0, maxf(240.0, view.y - BAR_HEIGHT - 28.0)))
		_factory_shell.custom_minimum_size = panel_size
		_factory_shell.size = panel_size
		_factory_shell.position = Vector2((view.x - panel_size.x) * 0.5, maxf(16.0, (view.y - BAR_HEIGHT - panel_size.y) * 0.45))

func _close_factory_panel() -> void:
	if _factory_layer != null and is_instance_valid(_factory_layer):
		_factory_layer.queue_free()
	_factory_layer = null
	_factory_dim = null
	_factory_shell = null
	_factory_rows = {}
	_factory_hover = null
	_factory_hover_id = ""
	_factory_cash = null
	_factory_time = null
	_factory_pack = null
	_factory_level_label = null
	_factory_upgrade = null
	_factory_mill = null
	_close_qty_dialog()

func _open_backpack() -> void:
	_close_backpack()
	_close_factory_panel()
	_close_venue_choice()
	if session == null:
		return
	var view := get_viewport().get_visible_rect().size
	_pack_layer = CanvasLayer.new()
	_pack_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_pack_layer)
	var dim := ColorRect.new()
	dim.color = GLASS_DIM
	dim.size = view
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_pack_dim_input)
	_pack_layer.add_child(dim)
	var panel := PanelContainer.new()
	var panel_size := Vector2(640, 520)
	panel.position = Vector2((view.x - panel_size.x) * 0.5, 48)
	panel.size = panel_size
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.theme = _glass_theme()
	var shell := _glass(18)
	shell.content_margin_left = 22
	shell.content_margin_right = 22
	shell.content_margin_top = 18
	shell.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", shell)
	_pack_layer.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title := Label.new()
	title.text = "背包"
	title.add_theme_font_override("font", _glass_font(600))
	title.add_theme_font_size_override("font_size", TDUI.FONT_TITLE)
	title.add_theme_color_override("font_color", GLASS_INK)
	box.add_child(title)
	var note := Label.new()
	note.text = "这里是已经生产完成的一级原料。"
	note.add_theme_font_size_override("font_size", TDUI.FONT_CAPTION)
	note.add_theme_color_override("font_color", GLASS_MUTED)
	box.add_child(note)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 360)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)
	var goods := session.factory_goods()
	if goods.is_empty():
		var empty := Label.new()
		empty.text = "背包是空的。原料厂做完的货会放进这里。"
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_color_override("font_color", GLASS_MUTED)
		list.add_child(empty)
	else:
		var grouped := {"seasoning": [], "vegetable": [], "meat": [], "fruit": []}
		for item: Variant in goods:
			var row: Dictionary = item
			var supply := String(row.get("supply", ""))
			if grouped.has(supply):
				(grouped[supply] as Array).append(row)
		for supply_id: String in ["seasoning", "vegetable", "meat", "fruit"]:
			var rows: Array = grouped[supply_id]
			if rows.is_empty():
				continue
			var head := Label.new()
			var label := TDTownMap.supply_name(supply_id, true)
			if label.ends_with("厂"):
				label = label.substr(0, label.length() - 1)
			head.text = label
			head.add_theme_font_size_override("font_size", TDUI.FONT_BODY)
			head.add_theme_color_override("font_color", _supply_color(supply_id, true))
			list.add_child(head)
			for item: Variant in rows:
				var row: Dictionary = item
				var line := HBoxContainer.new()
				line.add_theme_constant_override("separation", 8)
				line.alignment = BoxContainer.ALIGNMENT_CENTER
				list.add_child(line)
				line.add_child(_product_icon(String(row.get("id", "")), 32))
				var caption := Label.new()
				caption.text = "%s    ×%d" % [String(row.get("name", "")), int(row.get("qty", 0))]
				caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				caption.add_theme_font_size_override("font_size", TDUI.FONT_CAPTION)
				caption.add_theme_color_override("font_color", GLASS_INK)
				line.add_child(caption)
	var actions := HBoxContainer.new()
	box.add_child(actions)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)
	actions.add_child(_factory_button("关闭", _close_backpack, GLASS_BLUE, 120))

func _on_pack_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			_close_backpack()

func _close_backpack() -> void:
	if _pack_layer != null and is_instance_valid(_pack_layer):
		_pack_layer.queue_free()
	_pack_layer = null

func _try_enter_diner() -> void:
	if _closed or _entering_diner or session == null or _player == null or get_tree().paused:
		return
	var plot := session.town_map.plot_at(_player_cell().x, _player_cell().y)
	if String(plot.get("id", "")) != "player_diner":
		return
	_entering_diner = true
	_close_venue_choice()
	restaurant_requested.emit()

func _set_status(text: String) -> void:
	if _status != null:
		_status.text = text
	elif not text.is_empty():
		status_reported.emit(text)

func _product_icon(item_id: String, side: int) -> FactoryIcon:
	var icon := FactoryIcon.new()
	icon.item_id = item_id
	icon.custom_minimum_size = Vector2(side, side)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon

func _button(text: String, callback: Callable) -> Button:
	var button := _factory_button(text, callback, GLASS_BLUE, 110)
	button.custom_minimum_size = Vector2(110, 36)
	return button

func set_presented(value: bool) -> void:
	visible = value
	if _camera != null:
		_camera.enabled = value
		if value:
			_camera.make_current()
	if value:
		show_quest()
	if not value:
		_dismiss_talk()
	if _player != null:
		_player.set_controls_enabled(value and not _talk_open())
	for child: Node in get_children():
		if child is CanvasLayer:
			child.visible = value
	set_process_unhandled_input(value)

func spawn_at_home() -> void:
	spawn_at_plot("player_diner")

func _talk_open() -> bool:
	return _talk_view != null and is_instance_valid(_talk_view) and _talk_view.visible

func _ensure_talk() -> void:
	if _talk_view != null and is_instance_valid(_talk_view):
		return
	_talk_layer = CanvasLayer.new()
	_talk_layer.layer = 40
	_talk_layer.name = "DialogueLayer"
	add_child(_talk_layer)
	_talk_view = TDDialogueView.new()
	_talk_layer.add_child(_talk_view)
	_talk_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_talk_view.closed.connect(_on_talk_closed)

func _open_talk(next: TDDialogue) -> void:
	if characters!=null and next.context.get("kind")=="resident": characters.hold(str(next.context.character_id),true)
	_ensure_talk()
	_talk_view.present(next)
	if _player != null:
		_player.set_controls_enabled(false)

func _on_talk_closed(last_text: String, picks: Array) -> void:
	var context: Dictionary=_talk_view.last_context
	if context.get("kind")=="resident" and characters!=null:
		characters.hold(str(context.character_id),false)
		characters.complete_chat(context,_talk_view.last_completed,picks)
		_set_status("%s · 好感 %d/100"%[characters.definition(str(context.character_id)).name,int(characters.relationship(str(context.character_id)).affection)])
	elif context.get("kind")=="story" and story != null and story.started():
		var effect := story.complete_scene(str(context.get("scene","")),_talk_view.last_completed) if context.has("scene") else story.resolve(picks, _story_ready())
		if not effect.is_empty():
			story_effect.emit(effect)
		if not story.finished():
			_set_status(story.quest(chapter_ready, story_board))
		elif last_text != "":
			_set_status(last_text)
	elif last_text != "":
		_set_status(last_text)
	if _closed or _player == null or not visible or get_tree().paused:
		return
	_player.set_controls_enabled(true)

func show_quest() -> void:
	if management_menus: return # The formal shell already owns the task card.
	if story == null or not story.started() or story.finished() or _talk_open():
		return
	_set_status(story.quest(chapter_ready, story_board))

func _story_ready() -> bool:
	if story_board.has("served"):
		return bool(story_board.served)
	return chapter_ready

func _story_positions() -> Array:
	var people: Array = []
	if story == null or not story.started() or (story.finished() and homecoming.get("stage","") not in ["invited","following","door"]) or session == null:
		return people
	var diner := session._plot_by_id("player_diner")
	var door := _diner_door()
	var blocked := {door: true}
	var diner_roads := _open_roads(_rim_roads(diner), blocked)
	var chen := _chen_cell()
	if chen.x >= 0:
		blocked[chen] = true
	var aling := TDHarbor.GUIDE_STOP if session.town_map.layout_version==2 else _road_near_door(3)
	if escort_leg() in ["follow","return","home"] and _escort.x >= 0:
		aling = _escort
	elif story.beat in ["awaken","cook", "verdict", "founded", "done"] and not diner_roads.is_empty():
		aling = diner_roads[0]
	elif story.beat in ["soup","bowl"]:
		aling = _aling_market_cell()
	if homecoming.get("stage","")=="door": aling=Vector2i(homecoming.plot.approach_x,homecoming.plot.approach_y)+Vector2i.RIGHT
	if characters!=null:
		if homecoming.get("stage","") not in ["following","door"] and story.beat not in ["arrive","follow","return","soup","bowl"]: aling=characters.safe_stop_near(aling,"aling",[chen])
	if characters!=null:
		chen=characters.clear_story_stop(chen)
		if escort_leg() not in ["follow","return","home"]:
			aling=characters.clear_story_stop(aling)
	people.append({"id": "chen", "name": "老陈", "cell": chen, "color": Color("#8a6238")})
	people.append({"id": "aling", "name": "阿铃", "cell": aling, "color": Color("#24344a")})
	return people

func _person_feet(item: Dictionary) -> Vector2:
	var escort: bool = item.id=="aling" and _uses_reference_escort() and escort_leg() in ["follow","return","home"]
	return _origin() + (Vector2(item.get("position",Vector2(item.cell))) + Vector2(.5,.5 if escort else .62)) * cell_size()

func _story_faced() -> String:
	if _player==null: return ""
	var candidates := {}
	for item: Dictionary in _story_people():
		if int(item.cell.x)>=0 and _npc_can_stand(_person_feet(item)): candidates[item.id]=_person_feet(item)
	for actor: TDStoryArt.TownActor in [_hertz,_luo]:
		if actor!=null and actor.visible: candidates[actor.actor_id]=actor.position
	var nearest := ""
	var distance := PERSON_REACH
	for id: String in candidates:
		if characters!=null and not characters.can_chat(id): continue
		var feet: Vector2 = candidates[id]
		if not TDInteractionRange.faces(_player.position,_player.facing,feet,PERSON_REACH) and story!=null and not story.revised.is_empty(): continue
		var gap := _player.position.distance_to(feet)
		if gap<distance:
			distance=gap
			nearest=id
	return nearest

func _draw_story() -> void:
	_draw_stall_sign()
	if _sun_shadows != null and _player.visible:
		var hero := _player.get_node("Sprite2D") as Sprite2D
		var hero_bounds := (_player.transform * hero.transform) * hero.get_rect()
		_sun_shadows.draw_person(self,hero.texture,hero_bounds,hero.flip_h)
	if story!=null and story.beat in ["soup","bowl"]:
		var point:=chen_door_point()
		draw_string(TDUI.font(),point+Vector2(-36,-103),"老陈家",HORIZONTAL_ALIGNMENT_LEFT,-1,TDUI.FONT_CAPTION,Color("ffdfa2"))
	for actor: TDStoryArt.TownActor in _resident_sprites.values():
		if _sun_shadows!=null and actor.visible:
			_sun_shadows.draw_person(self,actor.texture,actor.transform*actor.get_rect())

func _draw_stall_sign() -> void:
	if story == null or story.beat not in ["founded", "done"] or session == null:
		return
	var diner := session._plot_by_id("player_diner")
	if diner.is_empty():
		return
	var at := _origin() + Vector2(int(diner.x), int(diner.y)) * cell_size() + Vector2(8, 8)
	var sign := story.stall_sign
	draw_rect(Rect2(at, Vector2(120, 36)), Color("#f6f1e4"))
	draw_string(TDUI.font(), at + Vector2(6, 16), "讨伐军本部", HORIZONTAL_ALIGNMENT_LEFT, -1, TDUI.FONT_CAPTION, Color("#6a2a2a"))
	draw_string(TDUI.font(), at + Vector2(6, 32), sign, HORIZONTAL_ALIGNMENT_LEFT, -1, TDUI.FONT_MICRO, Color("#5c4630"))

func chen_door_point() -> Vector2:
	var shop:=_plot_of_kind("market")
	if shop.is_empty(): return _origin()+(Vector2(_any_road({}))+Vector2(.5,.5))*cell_size()
	if TDPlannedTown.approved(session.town_map):
		return _origin()+(Vector2(shop.approach_x,shop.approach_y)+Vector2.ONE*.5)*cell_size()
	return _origin()+Vector2(float(shop.x)+float(shop.w)*.5,float(shop.y+shop.h))*cell_size()

func _chen_cell() -> Vector2i:
	if TDPlannedTown.approved(session.town_map):
		return _cell_at(chen_door_point())
	var at:=Vector2i((chen_door_point()-_origin())/cell_size())+Vector2i.LEFT*2
	if session.town_map.is_road(at.x,at.y): return at
	return _any_road({_diner_door():true})

func at_chen_door() -> bool:
	return _player!=null and story!=null and story.beat in ["soup","bowl"] and _player.position.distance_to(chen_door_point())<=BOWL_REACH

func _aling_market_cell() -> Vector2i:
	var chen:=_chen_cell()
	if TDPlannedTown.approved(session.town_map):
		return chen + Vector2i.RIGHT * 2
	if characters!=null: return characters.safe_stop_near(chen+Vector2i(2,0),"aling",[chen])
	for at: Vector2i in _rim_roads(_plot_of_kind("market")):
		if at.distance_to(chen)>=2.0 and at!=_diner_door(): return at
	return _road_near_door(3)

func _road_near_door(min_distance: int) -> Vector2i:
	var door := _diner_door()
	var best := Vector2i(-99, -99)
	var best_distance := 999999
	if session == null:
		return best
	for y: int in session.town_map.extent:
		for x: int in session.town_map.extent:
			if not session.town_map.is_road(x, y):
				continue
			var cell := Vector2i(x, y)
			if cell == door:
				continue
			var distance := absi(x - door.x) + absi(y - door.y)
			if distance < min_distance or distance >= best_distance:
				continue
			best = cell
			best_distance = distance
	if best.x < 0:
		return _any_road({door: true})
	return best

func bowl_point() -> Vector2:
	# Historical API now points to the shop threshold; no meal table in the street.
	return chen_door_point()

func escort_leg() -> String:
	return "home" if homecoming.get("stage","")=="following" else (story.beat if story!=null else "")

func _nearest_road(cell: Vector2i) -> Vector2i:
	var best:=cell;var gap:=INF
	for y: int in session.town_map.extent:
		for x: int in session.town_map.extent:
			var at:=Vector2i(x,y)
			if session.town_map.is_road(x,y) and Vector2(at-cell).length_squared()<gap:
				best=at;gap=Vector2(at-cell).length_squared()
	return best

func escort_position() -> Vector2:
	if _uses_reference_escort() and _reference_escort_goal.x >= 0:
		return _origin() + _reference_escort_stop * cell_size()
	return _origin()+(Vector2(_escort).lerp(Vector2(_escort_next),clampf(_escort_wait/ESCORT_STEP_SEC,0,1))+Vector2(.5,.5))*cell_size()

func _uses_reference_escort() -> bool:
	return player_mode and session != null and TDPlannedTown.approved(session.town_map)

func _tick_escort(delta: float) -> void:
	if story==null or escort_leg() not in ["follow","return","home"] or session==null or external_story_frozen or get_tree().paused: return
	if _escort_leg!=escort_leg():
		_escort_leg=escort_leg()
		_escort=(TDHarbor.GUIDE_STOP if session.town_map.layout_version==2 else _road_near_door(3)) if story.beat=="follow" else _aling_market_cell()
		if escort_leg()=="home": _escort=_nearest_road(_player_cell()+Vector2i(2,0))
		_escort_next=_escort;_escort_wait=0;_escort_waiting=false;_escort_gate_index=0
		_reference_escort_stop = Vector2(_escort) + Vector2.ONE * .5
		_reference_escort_goal = Vector2i(-99, -99)
	var final_goal:=_aling_market_cell() if story.beat=="follow" else _road_near_door(3)
	if escort_leg()=="home": final_goal=Vector2i(homecoming.plot.approach_x,homecoming.plot.approach_y)
	if _uses_reference_escort():
		_tick_reference_escort(delta, final_goal)
		return
	var through_gate: bool=story.beat=="follow" and session.town_map.layout_version==2 and not TDPlannedTown.approved(session.town_map)
	var goal: Vector2i=FIRST_GATE_ROUTE[_escort_gate_index] if through_gate and _escort_gate_index<FIRST_GATE_ROUTE.size() else final_goal
	if goal.x<0: return
	var remaining:=maxf(0,delta)
	while remaining>0:
		var distance:=escort_position().distance_to(_player.position)
		if distance>cell_size()*6: _escort_waiting=true
		elif distance<cell_size()*4: _escort_waiting=false
		if _escort_waiting:
			var offset:=_player.position-escort_position()
			_escort_facing=Vector2i(signf(offset.x),0) if absf(offset.x)>absf(offset.y) else Vector2i(0,signf(offset.y))
			break
		if _escort==goal and _escort_next==_escort:
			if through_gate and _escort_gate_index<FIRST_GATE_ROUTE.size():
				_escort_gate_index+=1
				goal=FIRST_GATE_ROUTE[_escort_gate_index] if _escort_gate_index<FIRST_GATE_ROUTE.size() else final_goal
			else:
				if distance<cell_size()*3:
					if escort_leg()=="home": homecoming.stage="door"
					else: story.arrive_escort()
				break
		if _escort_next==_escort: _escort_next=_step_road(_escort,goal)
		if _escort_next==_escort: break
		_escort_facing=_escort_next-_escort
		var step:=minf(remaining,.05);remaining-=step;_escort_wait+=step
		if _escort_wait>=ESCORT_STEP_SEC:
			_escort_wait-=ESCORT_STEP_SEC;_escort=_escort_next;_escort_next=_step_road(_escort,goal)
	queue_redraw()

func _tick_reference_escort(delta: float, goal: Vector2i) -> void:
	if goal.x < 0: return
	if _reference_escort_goal != goal:
		_reference_escort_goal = goal
		_reference_escort_stop = _reference_escort_stand_near(_reference_escort_stop)
		_reference_escort_path = reference_walk_path(_reference_escort_stop, Vector2(goal) + Vector2.ONE * .5)
		_reference_escort_index = 1
	if _reference_escort_path.is_empty(): return
	var step_sec := float(cell_size()) / TDKitchenPlayer.WALK_SPEED
	var remaining := maxf(delta, 0.0)
	while remaining > 0:
		var offset := _player.position - escort_position()
		var distance := offset.length()
		if distance > CELL * 6: _escort_waiting = true
		elif distance < CELL * 4: _escort_waiting = false
		if _escort_waiting:
			_escort_facing = _reference_escort_facing(offset)
			break
		if _reference_escort_index >= _reference_escort_path.size():
			if distance < CELL * 3:
				if escort_leg() == "home": homecoming.stage = "door"
				else: story.arrive_escort()
			break
		var destination := _reference_escort_path[_reference_escort_index]
		var to_stop := destination - _reference_escort_stop
		if to_stop.length_squared() <= .000001:
			_reference_escort_index += 1
			continue
		_escort_facing = _reference_escort_facing(to_stop)
		var step := minf(minf(remaining, .05), to_stop.length() * step_sec)
		var candidate := _reference_escort_stop.move_toward(destination, step / step_sec)
		if not _reference_escort_can_stand(candidate):
			_reference_escort_goal = Vector2i(-99, -99)
			break
		if not _resident_step_clear("aling",_reference_escort_stop,candidate):
			var clear_step := func(from: Vector2, to: Vector2) -> bool:
				return TDPlannedTown._reference_segment_clear(from,to,_reference_escort_can_stand) and _resident_step_clear("aling",from,to)
			var detour := TDInteractionRange.route_detour(_reference_escort_path,_reference_escort_index,_reference_escort_stop,clear_step,1.0/cell_size())
			if not detour.is_empty():
				_reference_escort_path=detour
				_reference_escort_index=0
			break
		_reference_escort_stop = candidate
		_escort = Vector2i(candidate.floor())
		remaining -= step
	queue_redraw()

func _reference_escort_facing(offset: Vector2) -> Vector2i:
	if absf(offset.x) > absf(offset.y): return Vector2i(signf(offset.x), 0)
	return Vector2i(0, signf(offset.y))

func _reference_escort_can_stand(at: Vector2) -> bool:
	return _npc_can_stand(_origin() + at * cell_size())

func reference_walk_path(start: Vector2, goal: Vector2) -> PackedVector2Array:
	if _reference_navigation == null:
		_reference_navigation = TDPlannedTown.reference_road_graph(_reference_escort_can_stand)
	return TDPlannedTown.reference_escort_path(
		_reference_escort_stand_near(start), _reference_escort_stand_near(goal),
		_reference_escort_can_stand, _reference_navigation
	)

func _reference_escort_stand_near(at: Vector2) -> Vector2:
	if _reference_escort_can_stand(at): return at
	for radius: float in [.25, .5, .75, 1.0]:
		for direction: Vector2 in [Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT, Vector2.UP]:
			var candidate := at + direction * radius
			if _reference_escort_can_stand(candidate): return candidate
	return at

func _step_road(start: Vector2i, goal: Vector2i) -> Vector2i:
	if start==goal:
		return start
	var door := _diner_door()
	var occupied:=_chen_cell()
	var parent := {}
	var queue: Array[Vector2i] = [start]
	var seen := {start: true}
	var head := 0
	while head < queue.size():
		var here: Vector2i = queue[head]
		head += 1
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var nxt := here + step
			if seen.has(nxt) or nxt == door or nxt==occupied:
				continue
			if nxt != goal and not session.town_map.is_road(nxt.x, nxt.y):
				continue
			parent[nxt] = here
			if nxt == goal:
				var first := nxt
				while parent.has(first) and parent[first] != start:
					first = parent[first]
				return first
			seen[nxt] = true
			queue.append(nxt)
	return start

func _plot_of_kind(kind: String) -> Dictionary:
	for plot: Variant in session.town_map.plots:
		var item: Dictionary = plot
		if String(item.get("kind", "")) == kind:
			return item
	return {}

func _open_roads(cells: Array[Vector2i], blocked: Dictionary) -> Array[Vector2i]:
	var open: Array[Vector2i] = []
	for cell: Vector2i in cells:
		if not blocked.has(cell):
			open.append(cell)
	return open

func _any_road(blocked: Dictionary) -> Vector2i:
	for y: int in session.town_map.extent:
		for x: int in session.town_map.extent:
			var cell := Vector2i(x, y)
			if session.town_map.is_road(x, y) and not blocked.has(cell):
				return cell
	return Vector2i(-99, -99)

func _rim_roads(plot: Dictionary) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	if plot.is_empty():
		return found
	var x0 := int(plot.x)
	var y0 := int(plot.y)
	var width := int(plot.w)
	var height := int(plot.h)
	for y in range(y0 - 1, y0 + height + 1):
		for x in range(x0 - 1, x0 + width + 1):
			var outside := x < x0 or x >= x0 + width or y < y0 or y >= y0 + height
			if outside and session.town_map.is_road(x, y):
				found.append(Vector2i(x, y))
	return found

func _dismiss_talk() -> void:
	if _talk_view != null and is_instance_valid(_talk_view):
		if characters!=null and _talk_view.talk!=null and _talk_view.talk.context.get("kind")=="resident": characters.hold(str(_talk_view.talk.context.character_id),false)
		_talk_view.dismiss()

func _diner_door() -> Vector2i:
	var plot := session._plot_by_id("player_diner")
	if plot.is_empty():
		return Vector2i(-1, -1)
	if TDPlannedTown.approved(session.town_map):
		return Vector2i(plot.approach_x,plot.approach_y)
	var x0 := int(plot.x)
	var y0 := int(plot.y)
	var width := int(plot.w)
	var height := int(plot.h)
	var best := Vector2i(-1, -1)
	var best_distance := 999999
	for y in range(y0 - 1, y0 + height + 1):
		for x in range(x0 - 1, x0 + width + 1):
			if not session.town_map.is_road(x, y):
				continue
			if x >= x0 and x < x0 + width and y >= y0 and y < y0 + height:
				continue
			var distance := absi(x - (x0 + width / 2)) + absi(y - (y0 + height))
			if distance < best_distance:
				best_distance = distance
				best = Vector2i(x, y)
	return best

func facing_plot() -> Dictionary:
	# Historical name retained; use the full object perimeter, not a doorway point.
	if _player==null or session==null: return {}
	var best: Dictionary={};var shortest: float=INF
	var approved := TDPlannedTown.approved(session.town_map)
	if approved:
		var cottage := session._plot_by_id("player_cottage")
		if not cottage.is_empty():
			var door := _origin() + _reference_escort_stand_near(
				Vector2(cottage.approach_x, cottage.approach_y) + Vector2.ONE * .5
			) * cell_size()
			if _player.position.distance_to(door) <= BUILDING_REACH and _feet_on_road(door):
				cottage.interaction_point = door
				return cottage
		for doorway: Dictionary in _reference_doorways:
			var entrance: Vector2 = doorway.point
			var distance: float = _player.position.distance_to(entrance)
			if distance < shortest and distance <= BUILDING_REACH and _feet_on_road(entrance):
				best = doorway.plot.duplicate(true)
				best.interaction_point = entrance
				shortest = distance
	var facilities: Array=session.town_map.plots.duplicate()
	var harbor:=TDHarbor.facility(session.town_map)
	if not harbor.is_empty(): facilities.append(harbor)
	for p: Dictionary in facilities:
		if management_menus and p.get("kind","") in ["factory_lot","supply_factory"]: continue
		if not TDInteractionRange.facility(p): continue
		var bounds:=TDInteractionRange.plot_bounds(p,cell_size(),_origin())
		var facade: Dictionary = _interactable_facades.get(p.id, {})
		if approved and not facade.is_empty() and p.kind != "harbor":
			var frontage: Rect2 = facade.interaction_frontage
			if TDInteractionRange.distance(_player.position, frontage) < TDInteractionRange.distance(_player.position, bounds):
				bounds = frontage
		var at:=TDInteractionRange.closest(_player.position,bounds)
		var distance: float=_player.position.distance_to(at)
		if distance>BUILDING_REACH: continue
		# The walkable plaza overlaps the shop's doorstep; it should yield to a
		# real service counter before opening its neighbourhood notice.
		var score := distance
		if approved and p.kind in ["plaza","public_walk","amusement"]: score+=cell_size()*.7
		if score>shortest: continue
		if is_equal_approx(score,shortest) and not best.is_empty() and str(p.id)>str(best.id): continue
		var clear: bool=true
		for step: int in range(1,5):
			var point:=_player.position.lerp(at,step/5.0)
			if not _walkable_point(point) and not bounds.has_point(point): clear=false;break
		if clear:
			best=p.duplicate(true);best.interaction_point=at;shortest=score
	if best.is_empty() and TDHarbor.is_near_departure(session.town_map,(_player.position-_origin())/cell_size()):
		return harbor
	return best

func spawn_at_plot(identity:String) -> void:
	if session == null or _player == null:
		return
	var home: Dictionary = session._plot_by_id(identity)
	if home.is_empty():
		return
	if TDPlannedTown.approved(session.town_map):
		var approach := Vector2(home.approach_x,home.approach_y) + Vector2.ONE * .5
		_player.position = _origin() + _reference_escort_stand_near(approach) * cell_size()
		_player.velocity = Vector2.ZERO
		_player.face(_origin()+Vector2(home.x+home.w*.5,home.y+home.h*.5)*cell_size()-_player.position)
		_follow_camera()
		return
	var goal := Vector2i(int(home.x) + int(home.w) / 2, int(home.y) + int(home.h))
	var best := Vector2i(TDTownMap.CENTER, TDTownMap.CENTER)
	var distance: float = INF
	for y: int in session.town_map.extent:
		for x: int in session.town_map.extent:
			if not session.town_map.is_road(x, y):
				continue
			var at := Vector2i(x, y)
			var score := Vector2(at).distance_squared_to(Vector2(goal))
			if score < distance:
				best = at
				distance = score
	_player.position = _origin() + (Vector2(best) + Vector2(0.5, 0.5)) * cell_size()
	if identity=="player_cottage":
		_player.position=_origin()+(Vector2(home.approach_x,home.approach_y)+Vector2(.5,.5))*cell_size()
	_player.face(_origin()+Vector2(home.x+home.w*.5,home.y+home.h*.5)*cell_size()-_player.position)
	_player.velocity = Vector2.ZERO
	_follow_camera()

func spawn_at_harbor() -> void:
	if _player==null or session.town_map.layout_version!=2: return
	_player.position=_origin()+(Vector2(TDHarbor.ARRIVAL)+Vector2(.5,.5))*cell_size()
	_player.velocity=Vector2.ZERO;_player.face(Vector2.LEFT);_follow_camera()

class FactoryMill extends Control:
	var phase: float = 0.0
	var lanes: Array = []
	var host: TDTownWorld

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		mouse_filter = Control.MOUSE_FILTER_STOP
		clip_contents = true

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return data is Dictionary and String((data as Dictionary).get("item_id", "")) != ""

	func _drop_data(at: Vector2, data: Variant) -> void:
		if host == null:
			return
		host._ask_factory_qty(_lane_at(at.y), String((data as Dictionary).get("item_id", "")))

	func _lane_at(y: float) -> int:
		var count := maxi(lanes.size(), 1)
		var lane_h := maxf(1.0, (size.y - 36.0) / float(count))
		return clampi(int((y - 22.0) / lane_h), 0, count - 1) + 1

	func _process(delta: float) -> void:
		if _moving() and get_tree() != null and not get_tree().paused:
			phase += delta
		queue_redraw()

	func _moving() -> bool:
		for item: Variant in lanes:
			if bool((item as Dictionary).get("running", false)):
				return true
		return false

	func _draw() -> void:
		var bounds := size
		if bounds.x < 16.0 or bounds.y < 16.0:
			return
		draw_rect(Rect2(Vector2.ZERO, bounds), Color(0.05, 0.1, 0.18, 0.72))
		_draw_machine(bounds)
		_draw_belts(bounds)

	func _draw_machine(bounds: Vector2) -> void:
		var moving := _moving()
		var body := Rect2(18, 36, 78, bounds.y - 58)
		draw_rect(body, Color(0.13, 0.24, 0.4, 0.95))
		draw_rect(Rect2(18, 36, 78, 8), Color(0.45, 0.68, 0.92, 0.85))
		var lift := 0.0
		if moving:
			lift = sin(phase * 2.4) * 10.0
		draw_rect(Rect2(48, 16 + lift, 18, 22), Color(0.72, 0.86, 1.0, 0.9))
		draw_line(Vector2(57, 38 + lift), Vector2(57, body.position.y + 18), Color(0.75, 0.88, 1.0, 0.7), 3.0)
		var center := Vector2(57, body.position.y + body.size.y * 0.55)
		var spin := 0.0
		if moving:
			spin = phase * 1.8
		draw_circle(center, 16, Color(0.28, 0.48, 0.72, 1.0))
		for tooth in 8:
			var angle := spin + float(tooth) * TAU / 8.0
			var dir := Vector2(cos(angle), sin(angle))
			draw_line(center + dir * 12.0, center + dir * 24.0, Color(0.78, 0.9, 1.0, 0.95), 4.0)
		draw_circle(center, 5, Color(0.08, 0.14, 0.22, 1.0))
		if moving:
			for puff in 3:
				var rise := fmod(phase * 28.0 + float(puff) * 16.0, 42.0)
				var alpha := 1.0 - rise / 42.0
				draw_circle(Vector2(86, 28 - rise), 3.0 + float(puff), Color(0.8, 0.9, 1.0, alpha * 0.45))

	func _draw_belts(bounds: Vector2) -> void:
		var count := maxi(lanes.size(), 1)
		var left := 112.0
		var right := bounds.x - 16.0
		var top := 22.0
		var lane_h := (bounds.y - 36.0) / float(count)
		var font := TDUI.font()
		for index in count:
			var lane: Dictionary = lanes[index] if index < lanes.size() else {}
			var running := bool(lane.get("running", false))
			var y := top + lane_h * float(index) + lane_h * 0.62
			var belt_w := maxf(40.0, right - left)
			var queued := 0
			if running:
				queued = maxi(int(lane.get("left", 0)) - 1, 0)
			var gap := 4.0
			var box_w := 22.0
			if queued > 0:
				box_w = minf(22.0, (belt_w * 0.42 - gap * float(queued)) / float(queued))
				box_w = maxf(14.0, box_w)
			var track_h := 26.0
			var line_no := index + 1
			var remain := int(lane.get("left", 0))
			var left_w := 108.0
			var belt_rect: Rect2 = Rect2(left, y - track_h * 0.5, belt_w, track_h)
			draw_rect(belt_rect, Color(0.04, 0.08, 0.14, 0.98))
			draw_rect(Rect2(belt_rect.position, Vector2(belt_w, 2.0)), Color(0.82, 0.92, 1.0, 0.7))
			draw_rect(Rect2(Vector2(left, y + track_h * 0.5 - 2.0), Vector2(belt_w, 2.0)), Color(0.82, 0.92, 1.0, 0.7))
			draw_string(font, Vector2(left, y - track_h * 0.5 - 4.0), "产线 %d" % line_no, HORIZONTAL_ALIGNMENT_LEFT, left_w, TDUI.FONT_CAPTION, Color(0.82, 0.9, 1.0, 0.9))
			var goods := String(lane.get("item_id", ""))
			if not running:
				draw_string(font, Vector2(left + left_w + 12.0, y + 7.0), "拖到这里", HORIZONTAL_ALIGNMENT_LEFT, belt_w - left_w - 24.0, TDUI.FONT_CAPTION, Color(0.76, 0.86, 0.98, 0.55))
				continue
			var ratio := clampf(float(lane.get("ratio", 0.0)), 0.0, 1.0)
			var badge_w := 72.0
			var fill_left := left + left_w
			var fill_room := maxf(24.0, belt_w - left_w - badge_w)
			var fill_w := fill_room * ratio
			if fill_w > 1.0:
				draw_rect(Rect2(fill_left, y - track_h * 0.5, fill_w, track_h), Color(0.22, 0.62, 1.0, 0.96))
				draw_rect(Rect2(fill_left, y - track_h * 0.5, fill_w, 5.0), Color(0.9, 0.97, 1.0, 0.95))
				draw_line(Vector2(fill_left + fill_w, y - track_h * 0.5), Vector2(fill_left + fill_w, y + track_h * 0.5), Color(1, 1, 1, 1), 4.0)
			var qx := fill_left + 8.0
			var queue_limit := fill_left + fill_room - 8.0
			for _box in queued:
				if qx + box_w > queue_limit:
					break
				FactoryIcon.draw_on(self, goods, Rect2(qx, y - box_w - 18.0, box_w, box_w))
				qx += box_w + gap
			var travel_left := fill_left + 8.0
			var span := maxf(20.0, fill_room - 44.0)
			var box_x := travel_left + span * ratio
			FactoryIcon.draw_on(self, goods, Rect2(box_x, y - 44.0, 34.0, 34.0))
			var waiting := Rect2(left, y - track_h * 0.5, left_w, track_h)
			draw_rect(waiting, Color(0.1, 0.24, 0.46, 1.0))
			draw_string(font, Vector2(waiting.position.x, y + 8.0), "还剩 %d" % remain, HORIZONTAL_ALIGNMENT_CENTER, left_w, TDUI.FONT_BODY, Color(0.97, 0.99, 1.0, 1.0))
			var badge := Rect2(fill_left + fill_room, y - track_h * 0.5, badge_w, track_h)
			draw_rect(badge, Color(0.08, 0.16, 0.3, 1.0))
			draw_string(font, Vector2(badge.position.x, y + 8.0), "%d%%" % int(round(ratio * 100.0)), HORIZONTAL_ALIGNMENT_CENTER, badge_w, TDUI.FONT_BODY, Color(0.95, 0.98, 1.0, 1.0))

class FactoryDrag extends PanelContainer:
	var item_id: String = ""
	var item_name: String = ""
	var host: TDTownWorld

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _get_drag_data(_at: Vector2) -> Variant:
		var preview := FactoryIcon.new()
		preview.item_id = item_id
		preview.custom_minimum_size = Vector2(48, 48)
		preview.size = Vector2(48, 48)
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_drag_preview(preview)
		return {"item_id": item_id}

class FactoryIcon extends TDIngredientIcon:
	pass

func sync_characters(seconds: float, orders: Array = [], minute_from: float = -1.0) -> void:
	if characters==null or session==null: return
	if characters.runtime.is_empty() or (player_mode and not characters.foot_clear.is_valid()):
		characters.foot_clear = _reference_escort_can_stand if player_mode else Callable()
		characters.step_clear = _resident_step_clear if player_mode else Callable()
		characters.sync_map(session.town_map)
	characters.pinned.clear()
	for person: Dictionary in _story_positions(): characters.pinned[str(person.id)]=person.cell
	characters.advance(seconds,orders,minute_from)
	queue_redraw()

func _story_people() -> Array:
	var people: Array=characters.visible_people() if characters!=null else _story_positions()
	if has_meta("revised_escort"): people=people.filter(func(person: Dictionary) -> bool: return person.id!="aling")
	if story!=null and escort_leg() in ["follow","return","home"] and _escort.x>=0 and _escort_next.x>=0:
		for person: Dictionary in people:
			if person.id=="aling":
				person.position=(escort_position()-_origin())/cell_size()-Vector2.ONE*.5
				person.facing=_escort_facing
	return people

func _refresh_npc_gaits() -> void:
	if not is_visible_in_tree(): return
	var live := {}
	for person: Dictionary in _story_people():
		var id := str(person.id)
		if int(person.cell.x)<0: continue
		var point := _person_feet(person)
		if player_mode and not _npc_can_stand(point): continue
		var facing: Vector2i = person.get("facing",Vector2i.DOWN)
		if not _resident_sprites.has(id):
			var sprite := TDStoryArt.TownActor.new()
			sprite.configure(id,OUTDOOR_PERSON_HEIGHT)
			sprite.set_caption(str(person.name))
			_resident_layer.add_child(sprite)
			_resident_sprites[id]=sprite
			var walk := TDNpcGait.new()
			walk.reset(point,facing)
			_npc_gaits[id]=walk
		var actor: TDStoryArt.TownActor = _resident_sprites[id]
		var gait: TDNpcGait = _npc_gaits[id]
		gait.sample(point,get_tree().paused or story_dialogue_open())
		actor.position=point
		actor.pose(gait.facing if gait.frame>=0 else facing,gait.frame)
		actor.set_callout("快跟上来" if id=="aling" and _escort_waiting and escort_leg() in ["follow","return","home"] else "")
		live[id]=true
	for id: String in _resident_sprites.keys():
		if live.has(id): continue
		_resident_layer.remove_child(_resident_sprites[id])
		_resident_sprites[id].queue_free()
		_resident_sprites.erase(id)
		_npc_gaits.erase(id)

func story_dialogue_open() -> bool:
	return external_story_frozen or (_talk_open() and _talk_view.talk!=null and _talk_view.talk.presentation=="story")
