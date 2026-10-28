class_name TDRestaurantIsoView
extends Node2D

const HALF_W := 32.0
const HALF_H := 16.0
const ORIGIN := Vector2(620, 48)
const WALL_HEIGHT := 54.0
const FURNITURE := preload("res://assets/town/diner-furniture-v1.png")
const CHEF_SPRITE := preload("res://assets/kitchen/chef-v1.png")

var layout: TDRestaurantLayout
var editing: bool = false
var selected_id: String = ""
var ghost_cell := Vector2i(-1, -1)
var ghost_size := Vector2i.ZERO
var ghost_ok: bool = false
var player_point := Vector2.ZERO
var player_moving: bool = false
var player_facing:=Vector2i.DOWN
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

func _staff_font() -> Font:
	if _name_font == null:
		var font := SystemFont.new()
		font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC"])
		_name_font = font
	return _name_font

func _ready() -> void:
	z_index = 4
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

func sync(player: Node2D, guests: Array) -> void:
	if player != null:
		player_point = player.position
		if player is TDKitchenPlayer: player_facing=player.facing
		player_moving = player is TDKitchenPlayer and (player as TDKitchenPlayer).velocity.length_squared() > 1.0
	actors = []
	for item: Variant in guests:
		var guest := item as TDRestaurantGuest
		actors.append({
			"position": guest.position,
			"phase": guest.phase,
			"bob": guest.bob,
			"gone": guest.phase == "gone",
			"seated": guest.seated,
			"label": guest.dish_name,
			"shirt": TDGuestVisit.shirt(guest.phase),
		})
	queue_redraw()

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
		entries.append(_person_entry(actor["position"],not sitting,shirt,String(actor["label"]),sitting))
	if runner_visible:
		entries.append(_person_entry(runner_point,true,Color("#6f8f4a"),runner_label if runner_label!="" else "传菜",false))
	for person: Dictionary in crew_people:
		var staff := _person_entry(person.point, bool(person.get("moving", false)), person.color, str(person.label), false)
		staff["staff"] = true
		staff["depth"] = float(staff.depth) + 30.0
		entries.append(staff)
	entries.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return a.depth<b.depth)
	for entry:Dictionary in entries:
		match entry.kind:
			"furniture": _furniture(entry.data)
			"marker": _marker(entry.data)
			"person": _person(entry.point,entry.moving,entry.shirt,entry.caption,entry.seated,bool(entry.get("staff", false)))

func _person_entry(point:Vector2,moving:bool,shirt:Color,caption:String,seated:bool) -> Dictionary:
	return {"kind":"person","depth":(point.x+point.y)/float(layout.cell_px),"point":point,"moving":moving,"shirt":shirt,"caption":caption,"seated":seated}

func _marker(marker: Dictionary) -> void:
	var point:=project(marker.cell.x+.5,marker.cell.y+.5)
	var label_y:float=-76
	if marker.action in ["decorate","rest"]:
		_prop(2 if marker.action=="decorate" else 3,point,120)
		label_y=-118
	elif marker.action in ["kitchen","town"]:
		draw_rect(Rect2(point+Vector2(-23,-86),Vector2(46,86)),Color("39281f"))
		draw_rect(Rect2(point+Vector2(-26,-89),Vector2(52,7)),Color("b57e48"))
		for x: int in [-23,18]: draw_rect(Rect2(point+Vector2(x,-86),Vector2(5,86)),Color("94653d"))
		draw_rect(Rect2(point+Vector2(-17,-80),Vector2(34,60)),Color("704b32"))
		draw_rect(Rect2(point+Vector2(10,-39),Vector2(4,4)),Color("e2ba69"))
		label_y=-99
	elif marker.action=="hire":
		draw_rect(Rect2(point+Vector2(-18,-70),Vector2(36,48)),Color("efe2c4"))
		draw_rect(Rect2(point+Vector2(-18,-70),Vector2(36,48)),Color("6d5334"),false,2)
		draw_rect(Rect2(point+Vector2(-8,-22),Vector2(16,28)),Color("8a6238"))
		label_y=-84
	elif marker.action=="menu":
		draw_rect(Rect2(point+Vector2(-3,-29),Vector2(6,32)),Color("493c2c"))
		draw_rect(Rect2(point+Vector2(-23,-64),Vector2(46,45)),Color("684d31"))
		draw_rect(Rect2(point+Vector2(-20,-61),Vector2(40,39)),Color("272f2a"))
		for line: int in 4: draw_rect(Rect2(point+Vector2(-12,-53+line*7),Vector2(24,2)),Color("dfd2a8"))
	draw_string(ThemeDB.fallback_font,point+Vector2(-60,label_y),str(marker.name),HORIZONTAL_ALIGNMENT_CENTER,120,14,Color("f8e5b8"))

func _floor_cell(cell: Vector2i) -> void:
	var points := _quad(cell.x, cell.y, 1, 1)
	var structural := layout.cell_zone(cell.x, cell.y)
	var shown := "facade" if structural == "facade" else "movement"
	var color := TDRestaurantArt.zone_color(layout.culture, layout.tier, shown, layout.is_entrance(cell.x, cell.y))
	var finish := layout.finish_at(cell.x, cell.y)
	if finish != "":
		color = TDRestaurantArt.finish_color(finish).lerp(color, 0.22)
	draw_colored_polygon(points, color)
	var facility := layout.facility_zone(cell.x, cell.y)
	if facility != "" and facility != "facade":
		var mark := TDRestaurantArt.zone_color(layout.culture, layout.tier, facility, false)
		draw_polyline(points + PackedVector2Array([points[0]]), mark, 2.4 if editing else 1.4)
	else:
		draw_polyline(points + PackedVector2Array([points[0]]), color.darkened(0.25), 1.0)

func _ghost() -> void:
	var points := _quad(ghost_cell.x, ghost_cell.y, ghost_size.x, ghost_size.y)
	var fill := Color(0.35, 0.78, 0.42, 0.42) if ghost_ok else Color(0.86, 0.28, 0.22, 0.45)
	draw_colored_polygon(points, fill)
	draw_polyline(points + PackedVector2Array([points[0]]), Color("#fff6df"), 2.0)

func _wall(cell: Vector2i, along_north: bool) -> void:
	if layout.is_entrance(cell.x,cell.y): return # The visible door marker owns this gap.
	var start := project(float(cell.x), float(cell.y))
	var finish := project(float(cell.x + (1 if along_north else 0)), float(cell.y + (0 if along_north else 1)))
	var up := Vector2(0, -WALL_HEIGHT)
	var quad := PackedVector2Array([start, finish, finish + up, start + up])
	var swatch := TDRestaurantArt.swatch(layout.culture, layout.tier)
	var color := Color(String(swatch["accent"]))
	var paper := layout.finish_at(cell.x, cell.y)
	if TDRestaurantLayout.WALL_FINISHES.has(paper):
		color = TDRestaurantArt.finish_color(paper)
	if not along_north:
		color = color.darkened(0.28)
	if layout.tier == "high":
		color = color.lightened(0.08)
	draw_colored_polygon(quad, color)
	if not interaction_markers.is_empty():
		draw_line(start,finish,Color("543723"),7)
		draw_line(start+up,finish+up,Color("785035"),6)
		if (cell.x+cell.y)%3==0:
			draw_line(start,start+up,Color("573b29"),5)
			var lamp:=start+up+Vector2(0,20)
			draw_rect(Rect2(lamp-Vector2(7,8),Vector2(14,18)),Color("b95335"))
			draw_rect(Rect2(lamp-Vector2(3,6),Vector2(6,15)),Color("e9a354"))

func _furniture(item: Dictionary) -> void:
	var points := _quad(int(item["x"]), int(item["y"]), int(item["w"]), int(item["h"]))
	var center := (points[0] + points[1] + points[2] + points[3]) / 4.0
	if not interaction_markers.is_empty() and item.kind in ["dining_table","booth","sofa","hotpot_table","welcome_desk","cashier","order_counter"]:
		# Show the actual layout footprint underneath the elevated furniture artwork.
		draw_colored_polygon(points,Color("584332"))
		draw_polyline(points+PackedVector2Array([points[0]]),Color("81654a"),1)
		_prop(0 if item.seat_use=="dining" else 1,center,130 if item.seat_use=="dining" else 118)
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

func _person(point: Vector2, moving: bool, shirt: Color, caption: String, seated: bool = false, staff: bool = false) -> void:
	if layout == null:
		return
	var grid := Vector2(point.x / float(layout.cell_px), point.y / float(layout.cell_px))
	var bob := sin(Time.get_ticks_msec() / 140.0) * 3.0 if moving and not seated else 0.0
	var drop := -8.0 if seated else -20.0
	var at := project(grid.x, grid.y) + Vector2(0, drop - absf(bob))
	if not interaction_markers.is_empty() and (staff or shirt==Color("#d86b4a")):
		var ground:=project(grid.x,grid.y)
		draw_colored_polygon(PackedVector2Array([ground+Vector2(-7,0),ground+Vector2(0,-3),ground+Vector2(7,0),ground+Vector2(0,3)]),Color(0,0,0,.25))
		var body:=chef_rect(point)
		body.position.y-=absf(bob)
		draw_texture_rect(CHEF_SPRITE if staff else TDChefArt.texture(player_facing),body,false)
		if staff and caption != "":
			var plate := Rect2(body.position + Vector2(-18, -24), Vector2(92, 22))
			draw_rect(plate, Color(0.08, 0.12, 0.1, 0.88))
			draw_rect(plate, shirt, false, 2.0)
			draw_string(_staff_font(), plate.position + Vector2(4, 16), caption, HORIZONTAL_ALIGNMENT_CENTER, 84, 14, Color("#fff4d2"))
		return
	if seated:
		draw_rect(Rect2(at + Vector2(-10, 8), Vector2(20, 5)), Color("#6b4a32"))
	draw_circle(at + Vector2(0, -10), 6.0, Color("#f2d3b5"))
	draw_rect(Rect2(at + Vector2(-7, -4), Vector2(14, 12 if seated else 14)), shirt)
	if caption != "":
		var font := ThemeDB.fallback_font
		if font != null:
			draw_string(font, at + Vector2(-20, -28), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#fff4d2"))

func chef_rect(point: Vector2) -> Rect2:
	var grid:=point/float(layout.cell_px)
	return Rect2(project(grid.x,grid.y)-Vector2(28,70*_chef_foot_ratio),Vector2(56,70))

func _prop(index: int, at: Vector2, width: float) -> void:
	var side:float=FURNITURE.get_width()/2.0
	var source:=Rect2(Vector2(index%2,index/2)*side,Vector2.ONE*side)
	draw_texture_rect_region(FURNITURE,Rect2(at+Vector2(-width*.5,-width*.82),Vector2.ONE*width),source)

func _quad(x: int, y: int, width: int, height: int) -> PackedVector2Array:
	return PackedVector2Array([
		project(float(x), float(y)),
		project(float(x + width), float(y)),
		project(float(x + width), float(y + height)),
		project(float(x), float(y + height)),
	])
