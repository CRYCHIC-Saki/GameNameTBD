class_name TDRestaurantIsoView
extends Node2D

const HALF_W := 48.0
const HALF_H := 24.0
const ORIGIN := Vector2(620, 48)
const WALL_HEIGHT := 54.0
const FURNITURE := preload("res://assets/town/diner-furniture-v1.png")
const CHEF_SPRITE := preload("res://assets/kitchen/chef-v1.png")

var day_minute: float=720.0
var nearby_action: String=""

func set_day_minute(value: float) -> void:
	day_minute=value;self_modulate=TDDaylight.sample(value,true).tint;queue_redraw()

var layout: TDRestaurantLayout
var editing: bool = false
var selected_id: String = ""
var ghost_cell := Vector2i(-1, -1)
var ghost_size := Vector2i.ZERO
var ghost_ok: bool = false
var player_point := Vector2.ZERO
var player_moving: bool = false
var player_facing:=Vector2i.DOWN
var player_walk_frame: int = -1
var actors: Array = []
var runner_visible: bool = false
var runner_point := Vector2.ZERO
var runner_label: String = ""
var pass_point := Vector2(-1, -1)
var held_label: String = ""
var interaction_markers: Array[Dictionary] = []
var crew_people: Array = []
var _camera: Camera2D
var _chef_foot_ratio: float=1.0
var _name_font: Font
var _gaits: Dictionary={}
var follow_player: bool=false

func _staff_font() -> Font:
	if _name_font == null:
		var font := SystemFont.new()
		font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC"])
		_name_font = font
	return _name_font

func _ready() -> void:
	z_index = 4
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Transparent texture padding must not shift the visible feet from the body origin.
	_chef_foot_ratio=1.0
	_camera = Camera2D.new()
	_camera.name = "IsoCamera"
	_camera.position = project(10.0, 5.5)
	_camera.enabled = true
	add_child(_camera)
	_camera.make_current()

func shutdown() -> void:
	set_presented(false)

func set_presented(presented: bool) -> void:
	if not presented: _gaits.clear()
	if _camera == null:
		return
	_camera.enabled = presented
	if presented:
		_camera.make_current()

func set_room(next: TDRestaurantLayout) -> void:
	layout = next
	if layout != null and _camera != null:
		_camera.position = project(float(layout.columns) * 0.5, float(layout.rows) * 0.5)
	queue_redraw()

func sync(player: Node2D, guests: Array, frozen: bool=false) -> void:
	if player != null:
		player_point = player.position
		if player is TDKitchenPlayer:
			player_facing = player.facing
			player_walk_frame = player.walk_frame
		player_moving = player_walk_frame >= 0
		if follow_player and _camera!=null and layout!=null:
			var grid:=player_point/float(layout.cell_px)
			_camera.position=project(grid.x,grid.y)+Vector2(0,-70) if not editing else project(layout.columns*.5,layout.rows*.5)
			var zoom: float=minf(1.0,minf(1100.0/((layout.columns+layout.rows)*HALF_W),600.0/((layout.columns+layout.rows)*HALF_H+WALL_HEIGHT))) if editing else 1.0
			_camera.zoom=Vector2.ONE*zoom
	actors = []
	var live: Dictionary={}
	for item: Variant in guests:
		var guest := item as TDRestaurantGuest
		var key: String="guest:"+str(guest.get_instance_id());live[key]=true
		var gait:=_gait(key,guest.position,frozen or guest.frozen,guest.seated or guest.finished)
		actors.append({
			"position": guest.position,
			"phase": guest.phase,
			"bob": guest.bob,
			"gone": guest.phase == "gone",
			"seated": guest.seated,
			"label": guest.dish_name,
			"shirt": [Color("497f92"),Color("a66f44"),Color("82719c")][guest.appearance_id%3],
			"character_id":guest.character_id,
			"appearance_id":guest.appearance_id,
			"facing":gait.facing,"frame":gait.frame,
		})
	for person: Dictionary in crew_people:
		var key: String="staff:"+str(person.actor_id);live[key]=true
		var gait:=_gait(key,person.point,frozen)
		person.facing=gait.facing;person.frame=gait.frame
	if runner_visible: live["runner"]=true;_gait("runner",runner_point,frozen)
	for key: String in _gaits.keys():
		if not live.has(key): _gaits.erase(key)
	queue_redraw()

func _gait(key: String,point: Vector2,frozen: bool,stopped: bool=false) -> TDNpcGait:
	var grid:=point/float(layout.cell_px)
	var screen:=project(grid.x,grid.y)
	if not _gaits.has(key):
		var created:=TDNpcGait.new();created.reset(screen);_gaits[key]=created
	var gait: TDNpcGait=_gaits[key];gait.sample(screen,frozen,stopped)
	return gait

static func pick_cell(local_point: Vector2) -> Vector2i:
	var sx := (local_point.x - ORIGIN.x) / HALF_W
	var sy := (local_point.y - ORIGIN.y) / HALF_H
	return Vector2i(floori((sx + sy) / 2.0), floori((sy - sx) / 2.0))

static func project(grid_x: float, grid_y: float) -> Vector2:
	return ORIGIN + Vector2((grid_x - grid_y) * HALF_W, (grid_x + grid_y) * HALF_H)

static func wall_count(columns: int, rows: int) -> int:
	return columns + rows

func _draw() -> void:
	if layout == null:
		return
	for total in layout.columns + layout.rows:
		for x in layout.columns:
			var y := total - x
			if y < 0 or y >= layout.rows:
				continue
			var cell := Vector2i(x, y)
			if y == 0:
				_wall(cell, true)
			if x == 0:
				_wall(cell, false)
			_floor_cell(cell)
	_draw_kitchen_bay()
	if editing and ghost_size.x > 0 and ghost_size.y > 0:
		_ghost()
	if editing:
		_edit_grid()
	if pass_point.x >= 0.0:
		var pass_grid := Vector2(pass_point.x / float(layout.cell_px), pass_point.y / float(layout.cell_px))
		var pass_at := project(pass_grid.x, pass_grid.y)
		draw_circle(pass_at + Vector2(0, -8), 7.0, Color("#f0cc70"))
		var font := ThemeDB.fallback_font
		if font != null:
			draw_string(font, pass_at + Vector2(-18, -22), "传菜口", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#fff4d2"))
	# Sort by ground position so walking behind a table does not draw the chef on it.
	var entries:Array[Dictionary]=[]
	for item: Dictionary in layout.pieces():
		entries.append({"kind":"furniture","data":item,"depth":float(item.x+item.y)+(item.w+item.h)*.5})
	for marker: Dictionary in interaction_markers:
		entries.append({"kind":"marker","data":marker,"depth":marker.cell.x+marker.cell.y+1.0})
	entries.append(_person_entry(player_point,player_moving,Color("#d86b4a"),held_label,false))
	for item: Variant in actors:
		var actor: Dictionary = item
		if bool(actor["gone"]):
			continue
		var sitting := bool(actor.get("seated", false))
		var shirt := Color("#3f6f8f")
		if actor.get("shirt") is Color:
			shirt = actor.shirt as Color
		var person:=_person_entry(actor["position"],not sitting,shirt,String(actor["label"]),sitting)
		person.character_id=str(actor.get("character_id",""));person.appearance_id=int(actor.get("appearance_id",0))
		person.frame=int(actor.frame);person.facing=actor.facing
		entries.append(person)
	if runner_visible:
		var runner:=_person_entry(runner_point,true,Color("#6f8f4a"),runner_label if runner_label!="" else "传菜",false)
		if _gaits.has("runner"): runner.frame=_gaits.runner.frame;runner.facing=_gaits.runner.facing
		entries.append(runner)
	for person: Dictionary in crew_people:
		var staff := _person_entry(person.point, bool(person.get("moving", false)), person.color, str(person.label), false)
		staff["staff"] = true
		staff.frame=person.get("frame",-1);staff.facing=person.get("facing",Vector2i.DOWN)
		staff["depth"] = float(staff.depth) + 30.0
		entries.append(staff)
	entries.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return a.depth<b.depth)
	for entry:Dictionary in entries:
		match entry.kind:
			"furniture": _furniture(entry.data)
			"marker": _marker(entry.data)
			"person": _person(entry.point,entry.moving,entry.shirt,entry.caption,entry.seated,bool(entry.get("staff", false)),str(entry.get("character_id","")),int(entry.get("appearance_id",0)),int(entry.get("frame",-1)),entry.get("facing",Vector2i.DOWN))

func _person_entry(point:Vector2,moving:bool,shirt:Color,caption:String,seated:bool) -> Dictionary:
	return {"kind":"person","depth":(point.x+point.y)/float(layout.cell_px),"point":point,"moving":moving,"shirt":shirt,"caption":caption,"seated":seated}

func _marker(marker: Dictionary) -> void:
	var point:=project(marker.cell.x+.5,marker.cell.y+.5)
	var label_y:float=-76
	if marker.action=="kitchen":
		var kitchen_edge := _kitchen_door_segment()
		point = (kitchen_edge[0] + kitchen_edge[1]) * 0.5
		label_y = -WALL_HEIGHT - 18
	if marker.action==nearby_action:
		draw_circle(point+Vector2(0,3),11,Color("f2cf7c"))
		draw_string(ThemeDB.fallback_font,point+Vector2(-5,8),"E",HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("5b4735"))
	if marker.action=="ledger":
		var book_at:=point+Vector2(-12,-48 if marker.get("on_counter",false) else -34)
		draw_rect(Rect2(book_at,Vector2(24,16)),Color("634f37"))
		draw_rect(Rect2(book_at+Vector2(2,2),Vector2(20,12)),Color("f3deb1"))
		draw_line(book_at+Vector2(12,2),book_at+Vector2(12,14),Color("8c7452"),2)
		label_y=-78
	elif marker.action in ["decorate","recipes"]:
		# Wall-mounted boards/shelves use the existing wall collision, never an invisible floor table.
		draw_rect(Rect2(point+Vector2(-27,-50),Vector2(54,40)),Color("79533a"))
		draw_rect(Rect2(point+Vector2(-23,-46),Vector2(46,32)),Color("dfcc9f"))
		if marker.action=="recipes":
			for i: int in 5: draw_rect(Rect2(point+Vector2(-20+i*9,-43),Vector2(6,25)),[Color("9e5144"),Color("526d65"),Color("b9985c")][i%3])
		else:
			for i: int in 3: draw_rect(Rect2(point+Vector2(-18+i*13,-39),Vector2(10,18)),Color("8ea7a0"))
		label_y=-65
	elif marker.action=="hire":
		draw_rect(Rect2(point+Vector2(-18,-42),Vector2(36,30)),Color("efe2c4"))
		draw_rect(Rect2(point+Vector2(-18,-42),Vector2(36,30)),Color("6d5334"),false,2)
		label_y=-58
	elif marker.action=="menu":
		draw_rect(Rect2(point+Vector2(-3,-29),Vector2(6,32)),Color("493c2c"))
		draw_rect(Rect2(point+Vector2(-23,-64),Vector2(46,45)),Color("684d31"))
		draw_rect(Rect2(point+Vector2(-20,-61),Vector2(40,39)),Color("272f2a"))
		for line: int in 4: draw_rect(Rect2(point+Vector2(-12,-53+line*7),Vector2(24,2)),Color("dfd2a8"))
	var label_at := point+Vector2(-60,label_y)
	if marker.action=="town":
		var edge := _door_segment(Vector2i(int(marker.cell.x),int(marker.cell.y)))
		label_at=(edge[0]+edge[1])*.5+Vector2(-60,-WALL_HEIGHT-8)
	draw_string(ThemeDB.fallback_font,label_at,str(marker.name),HORIZONTAL_ALIGNMENT_CENTER,120,14,Color("f8e5b8"))

func _floor_cell(cell: Vector2i) -> void:
	var points := _quad(cell.x, cell.y, 1, 1)
	var structural := layout.cell_zone(cell.x, cell.y)
	var shown := "facade" if structural == "facade" else "movement"
	var color := TDRestaurantArt.zone_color(layout.culture, layout.tier, shown, layout.is_entrance(cell.x, cell.y))
	var finish := layout.finish_at(cell.x, cell.y)
	if finish != "":
		color = TDRestaurantArt.finish_color(finish).lerp(color, 0.22)
	if layout.culture=="chinese" and finish=="": color=Color("bd9b72") if (cell.x+cell.y)%2==0 else Color("c6a57d")
	draw_colored_polygon(points, color)
	var facility := layout.facility_zone(cell.x, cell.y)
	if facility != "" and facility != "facade":
		var mark := TDRestaurantArt.zone_color(layout.culture, layout.tier, facility, false)
		draw_polyline(points + PackedVector2Array([points[0]]), mark, 2.4 if editing else 1.4)
	else:
		draw_polyline(points + PackedVector2Array([points[0]]), color.darkened(0.25), 1.0)
	if layout.is_entrance(cell.x, cell.y):
		var edge := _sill_segment(cell)
		var span := edge[1] - edge[0]
		var sill_a := edge[0] + span * 0.18
		var sill_b := edge[1] - span * 0.18
		var inward := _door_inward(cell)
		draw_colored_polygon(PackedVector2Array([sill_a, sill_b, sill_b + inward, sill_a + inward]), Color("8d8274"))
		var step := _exit_step(cell)
		if step == Vector2i(0, 1) or step == Vector2i(1, 0):
			var door_edge := _door_segment(cell)
			_door_in_wall(door_edge[0], door_edge[1], Vector2(0, -WALL_HEIGHT), _wall_paint(cell, true))

func _ghost() -> void:
	var points := _quad(ghost_cell.x, ghost_cell.y, ghost_size.x, ghost_size.y)
	var fill := Color(0.35, 0.78, 0.42, 0.42) if ghost_ok else Color(0.86, 0.28, 0.22, 0.45)
	draw_colored_polygon(points, fill)
	draw_polyline(points + PackedVector2Array([points[0]]), Color("#fff6df"), 2.0)

func _exit_step(cell: Vector2i) -> Vector2i:
	for step: Vector2i in [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(1, 0)]:
		var next := cell + step
		if next.x < 0 or next.y < 0 or next.x >= layout.columns or next.y >= layout.rows:
			return step
		if layout.cell_zone(next.x, next.y) == "facade":
			return step
	return Vector2i(0, -1)

func _door_segment(cell: Vector2i) -> PackedVector2Array:
	var step := _exit_step(cell)
	var x := float(cell.x)
	var y := float(cell.y)
	if step == Vector2i(0, -1):
		return PackedVector2Array([project(x, 0.0), project(x + 1.0, 0.0)])
	if step == Vector2i(-1, 0):
		return PackedVector2Array([project(0.0, y), project(0.0, y + 1.0)])
	if step == Vector2i(0, 1):
		return PackedVector2Array([project(x, y + 1.0), project(x + 1.0, y + 1.0)])
	return PackedVector2Array([project(x + 1.0, y), project(x + 1.0, y + 1.0)])

func _sill_segment(cell: Vector2i) -> PackedVector2Array:
	var step := _exit_step(cell)
	var x := float(cell.x)
	var y := float(cell.y)
	if step == Vector2i(0, -1):
		return PackedVector2Array([project(x, y), project(x + 1.0, y)])
	if step == Vector2i(-1, 0):
		return PackedVector2Array([project(x, y), project(x, y + 1.0)])
	if step == Vector2i(0, 1):
		return PackedVector2Array([project(x, y + 1.0), project(x + 1.0, y + 1.0)])
	return PackedVector2Array([project(x + 1.0, y), project(x + 1.0, y + 1.0)])

func _door_inward(cell: Vector2i) -> Vector2:
	var into := -_exit_step(cell)
	return project(float(into.x) * 0.16, float(into.y) * 0.16) - project(0.0, 0.0)

func _wall_paint(cell: Vector2i, along_north: bool) -> Color:
	var swatch := TDRestaurantArt.swatch(layout.culture, layout.tier)
	var color := Color("efdfbb") if layout.culture == "chinese" else Color(String(swatch["accent"]))
	var paper := layout.finish_at(cell.x, cell.y)
	if TDRestaurantLayout.WALL_FINISHES.has(paper):
		color = TDRestaurantArt.finish_color(paper)
	if not along_north:
		color = color.darkened(0.28)
	if layout.tier == "high":
		color = color.lightened(0.08)
	return color

func _slab(a: Vector2, b: Vector2, rise: Vector2, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array([a, b, b + rise, a + rise]), color)

func _door_in_wall(start: Vector2, finish: Vector2, up: Vector2, wall: Color) -> void:
	var span := finish - start
	var left_jamb := start + span * 0.18
	var right_jamb := finish - span * 0.18
	_slab(start, left_jamb, up, wall)
	_slab(right_jamb, finish, up, wall)
	var lintel := up * 0.14
	_slab(left_jamb + up - lintel, right_jamb + up - lintel, lintel, wall)
	draw_line(start, left_jamb, Color("543723"), 5.0)
	draw_line(right_jamb, finish, Color("543723"), 5.0)
	draw_line(start + up, finish + up, Color("785035"), 5.0)
	draw_line(left_jamb, left_jamb + up - lintel, Color("4a301c"), 3.0)
	draw_line(right_jamb, right_jamb + up - lintel, Color("4a301c"), 3.0)
	var leaf := up - lintel
	var left := left_jamb + span * 0.02
	var right := right_jamb - span * 0.02
	var seam := (left + right) * 0.5
	_slab(left, seam, leaf * 0.98, Color("8b5a34"))
	_slab(seam, right, leaf * 0.98, Color("6d4528"))
	var panel := leaf * 0.62
	var panel_at := leaf * 0.16
	_slab(left + span * 0.03 + panel_at, seam - span * 0.015 + panel_at, panel, Color("5c3a22"))
	_slab(seam + span * 0.015 + panel_at, right - span * 0.03 + panel_at, panel, Color("4a2e1b"))
	draw_line(seam, seam + leaf * 0.98, Color("3a2416"), 2.0)
	draw_circle(left.lerp(seam, 0.78) + leaf * 0.48, 2.2, Color("e2ba69"))
	draw_circle(seam.lerp(right, 0.22) + leaf * 0.48, 2.2, Color("e2ba69"))

func _kitchen_door_segment() -> PackedVector2Array:
	var x := float(layout.columns - 2)
	var y := float(layout.rows)
	return PackedVector2Array([project(x, y), project(x + 1.0, y)])

func _draw_kitchen_bay() -> void:
	# The kitchen sits in the southeast corner. Its door is a real leaf in the south wall,
	# with a short run of wall on either side. The room edge already stops the player there.
	if layout.columns < 3 or layout.rows < 2:
		return
	var door_x := layout.columns - 2
	var up := Vector2(0, -WALL_HEIGHT)
	var paint := _wall_paint(Vector2i(door_x, layout.rows - 2), true)
	for dx: int in [-1, 0, 1]:
		var x: int = door_x + dx
		if x < 0 or x >= layout.columns:
			continue
		var edge := PackedVector2Array([project(float(x), float(layout.rows)), project(float(x + 1), float(layout.rows))])
		if dx == 0:
			_door_in_wall(edge[0], edge[1], up, paint)
			continue
		_slab(edge[0], edge[1], up, paint)
		if interaction_markers.is_empty():
			continue
		draw_line(edge[0], edge[1], Color("543723"), 7.0)
		draw_line(edge[0] + up, edge[1] + up, Color("785035"), 6.0)

func _wall_opens_for_door(cell: Vector2i, along_north: bool) -> bool:
	var door := layout.entrance()
	if door.x < 0:
		return false
	var step := _exit_step(door)
	if along_north:
		return cell.y == 0 and step == Vector2i(0, -1) and cell.x == door.x
	return cell.x == 0 and step == Vector2i(-1, 0) and cell.y == door.y

func _wall(cell: Vector2i, along_north: bool) -> void:
	var up := Vector2(0, -WALL_HEIGHT)
	var color := _wall_paint(cell, along_north)
	if _wall_opens_for_door(cell, along_north):
		var edge := _door_segment(layout.entrance())
		_door_in_wall(edge[0], edge[1], up, color)
		return
	var start := project(float(cell.x), float(cell.y))
	var finish := project(float(cell.x + (1 if along_north else 0)), float(cell.y + (0 if along_north else 1)))
	var quad := PackedVector2Array([start, finish, finish + up, start + up])
	draw_colored_polygon(quad, color)
	if not interaction_markers.is_empty():
		draw_line(start,finish,Color("543723"),7)
		draw_line(start+up,finish+up,Color("785035"),6)
		if (cell.x+cell.y)%3==0:
			draw_line(start,start+up,Color("573b29"),5)
			var lamp:=start+up+Vector2(0,20)
			draw_rect(Rect2(lamp-Vector2(7,8),Vector2(14,18)),Color("b95335"))
			draw_rect(Rect2(lamp-Vector2(3,6),Vector2(6,15)),Color("e9a354"))
			TDDaylight.glow(self,lamp,float(TDDaylight.sample(day_minute,true).lamps),35)

func _furniture(item: Dictionary) -> void:
	var points := _quad(int(item["x"]), int(item["y"]), int(item["w"]), int(item["h"]))
	var center := (points[0] + points[1] + points[2] + points[3]) / 4.0
	if not interaction_markers.is_empty() and item.kind in ["dining_table","booth","sofa","hotpot_table","welcome_desk","cashier","order_counter"]:
		# Show the actual layout footprint underneath the elevated furniture artwork.
		draw_colored_polygon(points,Color("584332"))
		draw_polyline(points+PackedVector2Array([points[0]]),Color("81654a"),1)
		var footprint_width: float=(float(item.w)+float(item.h))*HALF_W
		_prop(0 if item.seat_use=="dining" else 1,center,footprint_width*.94)
		if selected_id==str(item.id): draw_polyline(points+PackedVector2Array([points[0]]),Color("f0cc70"),3)
		return
	for index in points.size():
		points[index] = points[index].lerp(center, 0.14)
	var parts := String(item["style_id"]).split("_")
	var swatch := TDRestaurantArt.swatch(parts[0] if not parts.is_empty() else "plain", parts[1] if parts.size() > 1 else "low")
	var fill := Color(String(swatch["cloth"]))
	if String(item["kind"]) == "screen":
		fill = Color(String(swatch["accent"]))
	draw_colored_polygon(points, fill)
	draw_polyline(points + PackedVector2Array([points[0]]), Color(String(swatch["wood"])), 2.0)
	if String(item["surface"]) == "induction":
		draw_circle(center, 8.0, Color("#d23a32"))
		draw_circle(center, 3.0, Color("#202426"))
	if selected_id == String(item["id"]):
		draw_polyline(points + PackedVector2Array([points[0]]), Color("#f0cc70"), 3.0)
	var font := ThemeDB.fallback_font
	if font != null:
		draw_string(font, center + Vector2(-18, -10), String(item["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)

func _edit_grid() -> void:
	for y in layout.rows:
		for x in layout.columns:
			var points := _quad(x, y, 1, 1)
			draw_polyline(points + PackedVector2Array([points[0]]), Color(1, 1, 1, 0.18), 1.0)

func _person(point: Vector2, _moving: bool, shirt: Color, caption: String, seated: bool = false, staff: bool = false, character_id: String = "", appearance_id: int = 0, walk_frame: int=-1, facing: Vector2i=Vector2i.DOWN) -> void:
	if layout == null:
		return
	var grid := Vector2(point.x / float(layout.cell_px), point.y / float(layout.cell_px))
	var stride: float=[1.0,0.0,-1.0,0.0][walk_frame] if walk_frame>=0 and not seated else 0.0
	var drop := -8.0 if seated else -20.0
	var at := project(grid.x, grid.y) + Vector2(0, drop)
	if character_id!="":
		var art:=TDStoryArt.sprite(character_id,facing,walk_frame)
		if art!=null:
			var ground:=project(grid.x,grid.y)
			draw_texture_rect(art,TDStoryArt.fit(art,Rect2(ground+Vector2(-35,-70),Vector2(70,70))),false)
			if caption!="": draw_string(_staff_font(),ground+Vector2(-25,-78),caption,HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("fff4d2"))
			return
	if not interaction_markers.is_empty() and not staff and shirt==Color("#d86b4a"):
		var ground:=project(grid.x,grid.y)
		draw_colored_polygon(PackedVector2Array([ground+Vector2(-7,0),ground+Vector2(0,-3),ground+Vector2(7,0),ground+Vector2(0,3)]),Color(0,0,0,.25))
		var body:=chef_rect(point)
		# The protagonist shares the physics player's frame; no wall-clock bob during pause.
		draw_texture_rect(CHEF_SPRITE if staff else TDChefArt.texture(player_facing, player_walk_frame),body,false)
		if staff and caption != "":
			var plate := Rect2(body.position + Vector2(-18, -24), Vector2(92, 22))
			draw_rect(plate, Color(0.08, 0.12, 0.1, 0.88))
			draw_rect(plate, shirt, false, 2.0)
			draw_string(_staff_font(), plate.position + Vector2(4, 16), caption, HORIZONTAL_ALIGNMENT_CENTER, 84, 14, Color("#fff4d2"))
		return
	if seated:
		draw_rect(Rect2(at + Vector2(-10, 8), Vector2(20, 5)), Color("#6b4a32"))
	draw_circle(at + Vector2(0, -10), 6.0, Color("#f2d3b5"))
	var hair: Color=[Color("313642"),Color("704d36"),Color("666b72")][appearance_id%3]
	draw_rect(Rect2(at+Vector2(-6,-17),Vector2(12,5)),hair)
	if appearance_id%3==1: draw_rect(Rect2(at+Vector2(-8,-19),Vector2(16,3)),Color("d3bd8b"))
	if appearance_id%3==2: draw_rect(Rect2(at+Vector2(-6,-11),Vector2(12,2)),Color("3c3c45"))
	draw_rect(Rect2(at + Vector2(-7, -4), Vector2(14, 12 if seated else 14)), shirt)
	if facing!=Vector2i.UP:
		var eye_x: float=3.0 if facing==Vector2i.RIGHT else (-4.0 if facing==Vector2i.LEFT else -3.0)
		draw_rect(Rect2(at+Vector2(eye_x,-11),Vector2(2,2)),Color("302c30"))
	if staff: draw_rect(Rect2(at+Vector2(-8,-21),Vector2(16,7)),Color("ede6d2"))
	if not seated:
		for side: int in [-1,1]:
			var swing: float=stride*side*4.0
			draw_rect(Rect2(at+Vector2(side*4-2,10+swing),Vector2(5,8)),Color("37404b"))
			draw_rect(Rect2(at+Vector2(side*9-2,-1-swing),Vector2(4,8)),shirt.lightened(.12))
	if caption != "":
		var font := ThemeDB.fallback_font
		if font != null:
			draw_string(font, at + Vector2(-20, -28), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#fff4d2"))

func chef_rect(point: Vector2) -> Rect2:
	var grid:=point/float(layout.cell_px)
	var texture := TDChefArt.texture(player_facing, player_walk_frame)
	var size := texture.get_size() * 70.0 / texture.get_height()
	return Rect2(project(grid.x,grid.y) - Vector2(size.x * 0.5, size.y), size)

func _prop(index: int, at: Vector2, width: float) -> void:
	TDEnvironmentArt.draw_prop(self,index,at,width)

func _quad(x: int, y: int, width: int, height: int) -> PackedVector2Array:
	return PackedVector2Array([
		project(float(x), float(y)),
		project(float(x + width), float(y)),
		project(float(x + width), float(y + height)),
		project(float(x), float(y + height)),
	])
