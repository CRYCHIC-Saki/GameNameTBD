class_name TDTravelWorld
extends Node2D
## One disposable exploration view; all property comes from the profile's map provider.
signal harbor_requested
signal landmark_requested(plot: Dictionary)
signal crowd_requested(site_id: String)
signal resident_requested(id: String)
var characters: TDCharacterRoster
var crowd_label: Callable
var cell_size: float = TDTownWorld.CELL
const FOOT_RADIUS := 9.0
var town_id: String="tokyo"
var map: TDTownMap
var player: TDKitchenPlayer
var camera: Camera2D
const BuildingNameplate := preload("res://src/town/building_nameplate.gd")
var _building_nameplate: BuildingNameplate
var _layer: CanvasLayer
var _ground: ImageTexture
var _island: Node2D
var _sun_shadows: Node2D
var _hero_shadow: Node2D
var _buildings: Array[Dictionary]=[]
var _harbor_counter: Rect2
var _solids: Array[Rect2]=[]
var _target: Dictionary={}
var _closed: bool=false
var _town_actor: TDStoryArt.TownActor
const CrowdStands := preload("res://src/town/crowd_stands.gd")
var _crowd_stands: CrowdStands

func _ready() -> void:
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	y_sort_enabled=true
	if map.egret: cell_size=TDEgretLayout.WALK_CELL
	if map.shiomi or map.egret:
		_make_native_map()
	else:
		_make_ground()
		_make_buildings()
		_make_dressing()
		var occupied: Array[Rect2] = []
		for child: Node in get_children():
			if child is Sprite2D: occupied.append(child.transform*child.get_rect())
		for item: Dictionary in TDTownArt.StreetPlaces.verges(town_id,map,cell_size,Vector2.ZERO,occupied):
			add_child(TDEnvironmentArt.facade_sprite(item.art,item.rect))
			_solids.append_array(item.bases)
	_make_blockers()
	_place_town_actor()
	_crowd_stands = CrowdStands.new()
	_crowd_stands.name = "CrowdStands"
	_crowd_stands.y_sort_enabled = true
	add_child(_crowd_stands)
	_crowd_stands.refresh(CrowdStands.travel_sites(town_id, _buildings), _can_stand, TDTownWorld.OUTDOOR_PERSON_HEIGHT)
	player=TDKitchenPlayer.new();player.name="Player";player.sprite_height=TDTownWorld.OUTDOOR_PERSON_HEIGHT;player.walk_cycle_distance=96
	player.process_mode=Node.PROCESS_MODE_PAUSABLE
	player.collision_layer=32;player.collision_mask=16;player.confine_to=_confine
	var sprite:=Sprite2D.new();sprite.name="Sprite2D";player.add_child(sprite)
	var shape:=CollisionShape2D.new();var circle:=CircleShape2D.new();circle.radius=FOOT_RADIUS;shape.shape=circle;player.add_child(shape)
	add_child(player);player.position=(Vector2(TDTravelCatalog.port(town_id))+Vector2.ONE*.5)*cell_size
	camera=Camera2D.new();camera.position=player.position;add_child(camera);camera.make_current()
	camera.limit_left=0;camera.limit_top=0;camera.limit_right=int((map.extent+6)*cell_size);camera.limit_bottom=int(map.extent*cell_size)
	if map.egret:
		var corner:=TDEgretLayout.world_point(Vector2.ZERO)
		var end:=TDEgretLayout.world_point(Vector2(TDEgretLayout.SIZE))
		camera.limit_left=roundi(corner.x)
		camera.limit_top=roundi(corner.y)
		camera.limit_right=roundi(end.x)
		camera.limit_bottom=roundi(end.y)
	_layer=CanvasLayer.new();_layer.layer=22;add_child(_layer)
	_building_nameplate = BuildingNameplate.new()
	_layer.add_child(_building_nameplate)
	queue_redraw()

func _make_ground() -> void:
	var style:=TDTravelCatalog.info(town_id);var s:=TDTownScenery.SCALE
	var image:=Image.create((map.extent+6)*s,map.extent*s,false,Image.FORMAT_RGBA8)
	image.fill(Color(style.water))
	var surfaces: Dictionary=TDTownScenery.smooth_surfaces(map,6)
	for y: int in map.extent:
		for x: int in range(map.extent+6):
			var at:=Vector2i(x,y);var surface: String=surfaces[at]
			# Regional swatches already carry the intended palette. An old per-pixel
			# gray tint would erase the new sandstone/terracotta road distinctions.
			TDTownScenery.paint_cell(image,at,surfaces,town_id)
			if surface=="woodland" and map.terrain_at(at+Vector2i.DOWN).terrain_type=="plain":
				var rock:=Color("7a8074")
				image.fill_rect(Rect2i(x*s,y*s+s-7,s,7),rock.darkened(.2))
				image.fill_rect(Rect2i(x*s,y*s+s-8,s,2),rock.lightened(.18))
	TDTownScenery.RiverBridge.paint(image,surfaces,town_id,s)
	TDTownScenery.PublicSquare.paint(image,map,surfaces,town_id,s)
	TDTownArt.Yard.paint_steps(image,map,s,town_id)
	_ground=ImageTexture.create_from_image(image)

func _make_native_map() -> void:
	var sea:=Polygon2D.new()
	sea.polygon=PackedVector2Array([Vector2(-2000,-2000),Vector2(9000,-2000),Vector2(9000,9000),Vector2(-2000,9000)])
	sea.color=Color("10586b")
	sea.z_index=-20
	add_child(sea)
	_island=TDEgretLayout.instance() if map.egret else TDShiomiArt.instance()
	add_child(_island)
	if map.egret:
		_sun_shadows = _island.get_node("Atmosphere/SunShadows")
		_hero_shadow = Node2D.new()
		_hero_shadow.z_index = -1
		add_child(_hero_shadow)
		_hero_shadow.draw.connect(_draw_hero_shadow)
	for child: Node in _island.get_children():
		var sprite:=child as Sprite2D
		if sprite==null or not sprite.visible: continue
		var id:=str(sprite.get_meta("plot_id",""))
		if not sprite.has_meta("base"): continue
		if id.is_empty(): continue
		var footing: Rect2=sprite.get_meta("base")
		# The service range covers the whole front, including steps and open counters.
		var base:=_island.transform*Rect2(sprite.position+footing.position,footing.size)
		var plot:=map._by_id(id)
		if id=="harbor":
			_harbor_counter=base
			plot={"id":id,"kind":"harbor","name":"稀味客港" if map.egret else "和味客港"}
		var rect:=_island.transform*sprite.transform*sprite.get_rect()
		base=base.intersection(rect.grow(-0.01))
		var texture:=AtlasTexture.new()
		texture.atlas=sprite.texture
		texture.region=sprite.region_rect
		_buildings.append({"plot":plot,"feet":Vector2(rect.get_center().x,rect.end.y)/cell_size,"base":base,"rect":rect,"art":texture})
	for plot: Dictionary in map.plots:
		if plot.has("branch_id") or (plot.has("economic_parcel_id") and str(plot.id).begins_with("commercial_street:shop:")):
			var lot:=TDInteractionRange.plot_bounds(plot)
			_add_building(plot,2.6,lot.size.x,TDTravelCatalog.native_frontage_feet(lot))

func _draw_hero_shadow() -> void:
	if not is_instance_valid(player) or not player.visible: return
	var hero := player.get_node("Sprite2D") as Sprite2D
	if hero.texture!=null:
		_sun_shadows.draw_person(_hero_shadow,hero.texture,player.transform*hero.transform*hero.get_rect(),hero.flip_h)

func _make_buildings() -> void:
	_buildings=[]
	var claimed: Dictionary={}
	for p: Dictionary in map.plots:
		if p.get("kind") in ["diner_lot","factory_lot"] or p.get("economic_courtyard",false): continue
		if p.get("kind")=="housing":
			# Group tiny cadastral cells into humane residential blocks.
			var cell:=Vector2i(int(p.x)/3,int(p.y)/3)
			if claimed.has(cell): continue
			claimed[cell]=true
			_add_building(p,2.4,2.7,Vector2(p.x,p.y)+Vector2(1,1), (cell.x + cell.y) % 2)
			continue
		var kind := str(p.kind)
		var height := 2.45
		if kind in ["bank", "hotel", "player_diner", "landmark"]: height = 3.2
		if kind == "market": height = 1.9
		if kind == "plaza": height = 1.25
		var lot := TDInteractionRange.plot_bounds(p)
		var feet := Vector2(lot.get_center().x,lot.end.y-.16)
		if kind=="plaza": feet.y -= lot.size.y*.40
		if TDTownArt.Yard.is_residential(kind):
			lot = TDTownArt.Yard.facade_lot(lot,1.0,TDTownArt.Yard.has_yard(p))
			feet = Vector2(lot.get_center().x,lot.end.y)
		var facade := _add_building(p,height,lot.size.x,feet)
		for detail: Dictionary in TDTownArt.frontage_details(town_id,p,map,cell_size,Vector2.ZERO,facade):
			add_child(TDEnvironmentArt.facade_sprite(detail.art,detail.rect))
			_solids.append_array(detail.bases)
	var at:=Vector2(TDTravelCatalog.port(town_id))
	var port: Dictionary={"id":"harbor","kind":"harbor","name":"港口客运","x":at.x-2,"y":at.y-3,"w":4,"h":3}
	_place_harbor(port,at)

## Moor the boat beside the bank. The passenger arrival cell belongs to the
## path network and must not double as the building's footprint.
func _place_harbor(plot: Dictionary, at: Vector2) -> void:
	var art := TDTravelCatalog.facade(town_id,plot)
	var best := -INF
	var chosen := Rect2()
	var face_left := false
	var entrance := (at+Vector2.ONE*.5)*cell_size
	for dy: int in range(-7,8):
		for dx: int in range(-7,8):
			var feet := entrance+Vector2(dx,dy)*cell_size*.5
			var rect := TDEnvironmentArt.facade_rect(art,feet,5*cell_size,2.3*TDTownWorld.HERO_HEIGHT)
			var area := Rect2i((rect.position/cell_size).floor(),((rect.end/cell_size).ceil()-(rect.position/cell_size).floor()))
			var clear := true
			for y: int in range(area.position.y,area.end.y):
				for x: int in range(area.position.x,area.end.x):
					if map.terrain_at(Vector2i(x,y)).surface_type=="bridge": clear=false;break
				if not clear: break
			if not clear or _buildings.any(func(b:Dictionary)->bool: return rect.intersects(b.rect)): continue
			for flip: bool in [false,true]:
				var direction := -1 if flip else 1
				var boat := Vector2i(((feet+Vector2(direction*rect.size.x*.32,-10))/cell_size).floor())
				var booth := Vector2i(((feet+Vector2(-direction*rect.size.x*.30,-10))/cell_size).floor())
				var shore := map.terrain_at(booth)
				if shore.terrain_type!="plain" or not shore.walkable or map.is_road(booth.x,booth.y): continue
				var score := -feet.distance_to(entrance)/cell_size
				if map.terrain_at(boat).surface_type=="water": score+=10
				if score<=best: continue
				best=score;chosen=rect;face_left=flip
	if not chosen.has_area():
		# In a fully occupied quay the existing public boarding point stays usable.
		_harbor_counter=Rect2(entrance,Vector2.ZERO)
		return
	var sprite := TDEnvironmentArt.facade_sprite(art,chosen)
	sprite.flip_h=face_left
	add_child(sprite)
	_harbor_counter=TDEnvironmentArt.facade_bases(chosen,.19)[0]
	_harbor_counter.size.x*=.46
	if face_left: _harbor_counter.position.x=chosen.end.x-chosen.size.x*.09-_harbor_counter.size.x
	_solids.append(_harbor_counter)
	_buildings.append({"plot":plot,"feet":Vector2(chosen.get_center().x,chosen.end.y)/cell_size,"base":_harbor_counter,"rect":chosen,"art":art})

func _make_blockers() -> void:
	var body:=StaticBody2D.new();body.collision_layer=16;body.collision_mask=0;add_child(body)
	for rect: Rect2 in _solids:
		var collision:=CollisionShape2D.new();var shape:=RectangleShape2D.new();shape.size=rect.size
		collision.shape=shape;collision.position=rect.get_center();body.add_child(collision)

func _add_building(plot: Dictionary,height: float,width: float,feet: Vector2,variation: int = 0) -> Rect2:
	var art := TDTravelCatalog.facade(town_id,plot,variation)
	var kind: String = "construction" if plot.get("construction",false) else plot.kind
	var rect: Rect2
	var base: Rect2
	if plot.get("preset_storefront", false) and kind != "construction":
		var diner := TDJiangnanReferenceArt.diner_facade()
		var original: Rect2 = diner.rect
		var shift := feet * cell_size - Vector2(original.get_center().x, original.end.y)
		rect = Rect2(original.position + shift, original.size)
		var original_base: Rect2 = diner.bases[0]
		base = Rect2(original_base.position + shift, original_base.size)
		base.end = Vector2(base.end.x, rect.end.y)
		for wall: Rect2 in diner.walking:
			_solids.append(Rect2(wall.position + shift, wall.size))
	else:
		# Keep the existing frontage and contact geometry when changing the sprite.
		var footprint := TDTravelCatalog.facade(town_id, plot, variation, false) if plot.has("branch_id") else art
		var entry := TDTownArt.street_entry(footprint,feet*cell_size,width*cell_size,height,.25,kind,map,Vector2.ZERO,cell_size,TDTownArt.frontage_bias(map,plot))
		rect = entry.rect
		base = entry.bases[0]
		if (map.egret or map.shiomi) and kind != "construction":
			_solids.append_array(TDEnvironmentArt.shop_walls(rect, base))
		else:
			_solids.append(base)
	var sprite := TDEnvironmentArt.facade_sprite(art, rect)
	if plot.get("kind")=="harbor" and town_id=="paris": sprite.flip_h=true
	add_child(sprite)
	if _sun_shadows!=null: _sun_shadows.register_caster(sprite)
	if map.shiomi:
		var local_rect: Rect2=_island.transform.affine_inverse()*rect
		_island.get_node("Weather").register_ground_shadow(sprite,Vector2(local_rect.get_center().x,local_rect.end.y),local_rect.size)
	_buildings.append({"plot":plot.duplicate(true),"feet":Vector2(rect.get_center().x,rect.end.y)/cell_size,"base":base,"rect":rect,"art":art})
	return rect

func _walkable(cell: Vector2i) -> bool:
	return cell.x>=0 and cell.y>=0 and cell.x<map.extent and cell.y<map.extent and bool(map.terrain_at(cell).walkable)

func _make_dressing() -> void:
	for item: Dictionary in TDTownScenery.dressing(map):
		var tex := TDTravelCatalog.plant(town_id,item.index)
		var feet: Vector2 = item.feet*cell_size
		var width: float = item.width*cell_size
		var rect := TDEnvironmentArt.facade_rect(tex,feet,width,width/tex.get_size().aspect())
		if _buildings.any(func(entry:Dictionary)->bool: return rect.intersects(entry.rect.grow(6))): continue
		add_child(TDEnvironmentArt.facade_sprite(tex,rect))
		var base: Rect2 = item.bounds
		_solids.append(Rect2(base.position*cell_size,base.size*cell_size))
	# The wooded hills are inaccessible and have their own denser canopy.
	var salt := 2+TDTravelCatalog.IDS.find(town_id)*5
	for y: int in ceili(map.extent/3.0):
		for x: int in ceili(map.extent/3.0):
			var point := TDTownScenery.planting_at(Vector2i(x,y),salt)
			var at := Vector2i(point)
			var surface := str(map.terrain_at(at).surface_type)
			if surface!="woodland" or not TDTownScenery.wooded_patch(point,surface,salt): continue
			if not map.plot_at(at.x,at.y).is_empty(): continue
			var feet := point*cell_size
			if _solids.any(func(r:Rect2)->bool:return r.grow(36).has_point(feet)): continue
			var sample := TDTownScenery.noise(x,y,salt)
			var index := sample%3
			var width: float = [106.0,86.0,34.0][index]
			width *= .82+.06*(sample%7)
			var tex := TDTravelCatalog.plant(town_id,index)
			var sprite_size := tex.get_size() * (width/tex.get_width())
			var rect := Rect2(feet-Vector2(width*.5,sprite_size.y),sprite_size)
			add_child(TDEnvironmentArt.facade_sprite(tex,rect))

func _confine(candidate: Vector2) -> bool:
	if player==null: return _can_stand(candidate)
	return TDInteractionRange.ground_segment_clear(player.position,candidate,_can_stand) \
		and _other_people_clear(player.position,candidate,null)

func _other_people_clear(from: Vector2, to: Vector2, mover: TDStoryArt.TownActor) -> bool:
	var spacing := TDInteractionRange.NPC_SPACING
	if mover!=null and not TDInteractionRange.npc_clear(from,to,player.position,spacing): return false
	var escort := get_meta("revised_escort",null) as TDStoryArt.TownActor if has_meta("revised_escort") else null
	for actor: TDStoryArt.TownActor in [_town_actor,escort]:
		if is_instance_valid(actor) and actor!=mover and actor.visible and not TDInteractionRange.npc_clear(from,to,actor.position,spacing): return false
	return _crowd_stands==null or _crowd_stands.clear_step(from,to,spacing)

func npc_step_clear(from: Vector2, to: Vector2, actor: TDStoryArt.TownActor) -> bool:
	return TDInteractionRange.ground_segment_clear(from,to,_npc_can_stand) and _other_people_clear(from,to,actor)

func _place_town_actor() -> void:
	var actor := "vito" if town_id == "paris" else "hina" if town_id == "tokyo" else ""
	if actor.is_empty(): return
	var plot := map._by_id("plaza" if actor == "vito" else "competitor:shop:2")
	if plot.is_empty() or not plot.has("approach_x") or not plot.has("approach_y"): return
	var anchor := (Vector2(float(plot.approach_x), float(plot.approach_y)) + Vector2.ONE * .5) * cell_size
	_town_actor = TDStoryArt.TownActor.new()
	_town_actor.name = actor.capitalize()
	# The opposite side of the Shiomi entrance is under a pine canopy.
	var side := Vector2.LEFT if actor == "hina" else Vector2.RIGHT
	_town_actor.place(actor, TDTownWorld.OUTDOOR_PERSON_HEIGHT, anchor, _npc_can_stand, side)
	add_child(_town_actor)

func _can_stand(candidate: Vector2) -> bool:
	return _ground_clear(candidate,FOOT_RADIUS)

func _npc_can_stand(candidate: Vector2) -> bool:
	return _ground_clear(candidate,TDTownWorld.NPC_FOOT_RADIUS)

func _ground_clear(candidate: Vector2, radius: float) -> bool:
	for offset: Vector2 in TDEnvironmentArt.FOOT_SAMPLES:
		var p:=candidate+offset*radius
		if map.egret:
			if not TDEgretLayout.can_stand(_island.to_local(p)): return false
		elif _island!=null:
			if not TDShiomiArt.can_stand(_island,p): return false
		elif not _walkable(Vector2i(floori(p.x/cell_size),floori(p.y/cell_size))): return false
	for solid: Rect2 in _solids:
		if TDEnvironmentArt.overlaps_base(candidate, solid, radius): return false
	return true

func nearby() -> Dictionary:
	return _target_at(player.position)

func _target_at(feet: Vector2) -> Dictionary:
	var at:=feet/cell_size
	var port_rect:=TDTravelCatalog.harbor_rect(town_id)
	if at.distance_to(at.clamp(port_rect.position,port_rect.end))<=.65 or feet.distance_to(feet.clamp(_harbor_counter.position,_harbor_counter.end))<=cell_size*.65: return {"id":"harbor","kind":"harbor","name":"港口客运"}
	var best:=.65;var found: Dictionary={}
	for entry: Dictionary in _buildings:
		var p: Dictionary=entry.plot
		if not TDInteractionRange.facility(p) or p.kind == "harbor": continue
		var rect: Rect2=entry.base
		var distance: float=feet.distance_to(feet.clamp(rect.position,rect.end))/cell_size
		if distance<best: best=distance;found=p
	return found.duplicate(true)

func landmark_access(kind: String, id: String = "") -> Vector2:
	for entry: Dictionary in _buildings:
		var plot: Dictionary=entry.plot
		if plot.get("kind")!=kind or (not id.is_empty() and plot.get("id")!=id): continue
		var base: Rect2=entry.base
		for fraction: float in [0.0,-.30,.30,-.48,.48]:
			for distance: float in [.25,.38,.50,.60]:
				for door: Vector2 in [Vector2(base.get_center().x+base.size.x*fraction,base.end.y+cell_size*distance),
					Vector2(base.position.x-cell_size*distance,base.get_center().y+base.size.y*fraction),
					Vector2(base.end.x+cell_size*distance,base.get_center().y+base.size.y*fraction)]:
					if not _can_stand(door): continue
					if _target_at(door).get("id")==plot.id: return door
	return Vector2.INF

func _process(_delta: float) -> void:
	if _closed: return
	camera.position=player.position
	if visible and player.controls_enabled:
		if _town_actor != null: _town_actor.face_nearby(player.position)
		_crowd_stands.face_nearby(player.position)
	if _hero_shadow!=null: _hero_shadow.queue_redraw()
	_target = nearby() if visible and player.controls_enabled else {}
	if not _target.is_empty():
		camera.force_update_scroll()
		_track_building()
	else:
		_building_nameplate.hide()

func _track_building() -> void:
	for entry: Dictionary in _buildings:
		var plot: Dictionary = entry.plot
		if plot.get("id") != _target.id:
			continue
		var title := str(plot.name) if plot.kind == "harbor" else TDTravelCatalog.label(plot, town_id)
		_building_nameplate.track(self, entry.rect, title)
		return
	_building_nameplate.hide()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("world_interact") and not event.is_echo() and player.controls_enabled:
		var resident := _nearby_resident()
		if not resident.is_empty():
			resident_requested.emit(resident)
			get_viewport().set_input_as_handled()
			return
		if not _nearby_crowd().is_empty():
			crowd_requested.emit(_crowd_site())
			get_viewport().set_input_as_handled()
			return
		var target:=nearby()
		if not target.is_empty():
			if target.kind=="harbor": harbor_requested.emit()
			else: landmark_requested.emit(target)
		get_viewport().set_input_as_handled()

func _nearby_resident() -> String:
	if characters==null or _town_actor==null or not _town_actor.visible: return ""
	var id := _town_actor.actor_id
	if characters.can_chat(id) and TDInteractionRange.faces(player.position,player.facing,_town_actor.position,76.0): return id
	return ""

func _crowd_site() -> String:
	return _crowd_stands.talk_site(player.position, player.facing) if _crowd_stands != null else ""

func _nearby_crowd() -> String:
	if crowd_label.is_valid() and not _crowd_site().is_empty():
		return str(crowd_label.call())
	return ""

func set_day_minute(minute: float) -> void:
	if _island!=null: _island.get_node("Atmosphere").set_minute(minute)
	if map.egret:
		modulate=TDDaylight.sample(minute).tint
		return
	if _island!=null:
		_island.get_node("Weather").set_minute(minute)
		player.modulate=TDDaylight.sample(minute).tint
		if _town_actor != null: _town_actor.modulate = player.modulate
		_crowd_stands.modulate = player.modulate
		return
	self_modulate=TDDaylight.sample(minute).tint
	if _town_actor != null: _town_actor.modulate = self_modulate
	_crowd_stands.modulate = self_modulate

func close() -> void:
	_closed=true
	if player!=null: player.set_controls_enabled(false)
	set_process(false);set_process_unhandled_input(false)

func _draw() -> void:
	if _ground==null: return
	draw_texture_rect(_ground,Rect2(Vector2.ZERO,Vector2(map.extent+6,map.extent)*cell_size),false)

func set_presented(value: bool) -> void:
	visible=value
	if _layer!=null: _layer.visible=value
	if camera!=null:
		camera.enabled=value
		if value: camera.make_current()
	if player!=null: player.set_controls_enabled(value)
	set_process_unhandled_input(value)
