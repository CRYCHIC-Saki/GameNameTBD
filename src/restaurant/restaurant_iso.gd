class_name TDRestaurantIsoView
extends Node2D

const HALF_W := 32.0
const HALF_H := 16.0
const ORIGIN := Vector2(620, 48)
const WALL_HEIGHT := 54.0

var layout: TDRestaurantLayout
var editing: bool = false
var selected_id: String = ""
var player_point := Vector2.ZERO
var player_moving: bool = false
var actors: Array = []
var runner_visible: bool = false
var runner_point := Vector2.ZERO
var runner_label: String = ""
var pass_point := Vector2(-1, -1)
var held_label: String = ""
var _camera: Camera2D

func _ready() -> void:
	z_index = 4
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
			"label": guest.dish_name if guest.service_active else "",
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
	for item: Variant in layout.pieces():
		_furniture(item)
	if editing:
		_edit_grid()
	if pass_point.x >= 0.0:
		var pass_grid := Vector2(pass_point.x / float(layout.cell_px), pass_point.y / float(layout.cell_px))
		var pass_at := project(pass_grid.x, pass_grid.y)
		draw_circle(pass_at + Vector2(0, -8), 7.0, Color("#f0cc70"))
		var font := ThemeDB.fallback_font
		if font != null:
			draw_string(font, pass_at + Vector2(-18, -22), "传菜口", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#fff4d2"))
	var player_caption := held_label
	_person(player_point, player_moving, Color("#d86b4a"), player_caption, false)
	for item: Variant in actors:
		var actor: Dictionary = item
		if bool(actor["gone"]):
			continue
		var sitting := bool(actor.get("seated", false))
		_person(actor["position"], not sitting, Color("#3f6f8f"), String(actor["label"]), sitting)
	if runner_visible:
		_person(runner_point, true, Color("#6f8f4a"), runner_label if runner_label != "" else "传菜", false)

func _floor_cell(cell: Vector2i) -> void:
	var points := _quad(cell.x, cell.y, 1, 1)
	var color := TDRestaurantArt.zone_color(layout.culture, layout.tier, layout.cell_zone(cell.x, cell.y), layout.is_entrance(cell.x, cell.y))
	draw_colored_polygon(points, color)
	draw_polyline(points + PackedVector2Array([points[0]]), color.darkened(0.25), 1.0)

func _wall(cell: Vector2i, along_north: bool) -> void:
	var start := project(float(cell.x), float(cell.y))
	var finish := project(float(cell.x + (1 if along_north else 0)), float(cell.y + (0 if along_north else 1)))
	var up := Vector2(0, -WALL_HEIGHT)
	var quad := PackedVector2Array([start, finish, finish + up, start + up])
	var swatch := TDRestaurantArt.swatch(layout.culture, layout.tier)
	var color := Color(String(swatch["accent"]))
	if not along_north:
		color = color.darkened(0.28)
	if layout.tier == "high":
		color = color.lightened(0.08)
	draw_colored_polygon(quad, color)

func _furniture(item: Dictionary) -> void:
	var points := _quad(int(item["x"]), int(item["y"]), int(item["w"]), int(item["h"]))
	var center := (points[0] + points[1] + points[2] + points[3]) / 4.0
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

func _person(point: Vector2, moving: bool, shirt: Color, caption: String, seated: bool = false) -> void:
	if layout == null:
		return
	var grid := Vector2(point.x / float(layout.cell_px), point.y / float(layout.cell_px))
	var bob := sin(Time.get_ticks_msec() / 140.0) * 3.0 if moving and not seated else 0.0
	var drop := -8.0 if seated else -20.0
	var at := project(grid.x, grid.y) + Vector2(0, drop - absf(bob))
	if seated:
		draw_rect(Rect2(at + Vector2(-10, 8), Vector2(20, 5)), Color("#6b4a32"))
	draw_circle(at + Vector2(0, -10), 6.0, Color("#f2d3b5"))
	draw_rect(Rect2(at + Vector2(-7, -4), Vector2(14, 12 if seated else 14)), shirt)
	if caption != "":
		var font := ThemeDB.fallback_font
		if font != null:
			draw_string(font, at + Vector2(-20, -28), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#fff4d2"))

func _quad(x: int, y: int, width: int, height: int) -> PackedVector2Array:
	return PackedVector2Array([
		project(float(x), float(y)),
		project(float(x + width), float(y)),
		project(float(x + width), float(y + height)),
		project(float(x), float(y + height)),
	])
