class_name TDPlatingView
extends Control
signal moved(piece_id: String, position: Vector2, drop: bool)
var pieces: Array = []
var editable: bool = false
var _drag: String = ""

func _ready() -> void:
	custom_minimum_size = Vector2(380, 158)
	mouse_filter = Control.MOUSE_FILTER_STOP

func show_dish(snapshot: Dictionary) -> void:
	pieces = snapshot.get("plating", []).duplicate(true)
	editable = snapshot.get("state") == "plated"
	if not editable: _drag = ""
	queue_redraw()

func _radius() -> float:
	return minf(size.x * .35, size.y * .44)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("193533"))
	var center: Vector2 = size * .5
	draw_circle(center, _radius() + 7, Color("8fbbb1"))
	draw_circle(center, _radius(), Color("f5e9cd"))
	for index: int in pieces.size():
		var piece: Dictionary = pieces[index]
		var at: Array = piece.get("preview_position", piece.position)
		var point: Vector2 = center + Vector2(float(at[0]), float(at[1])) * _radius()
		draw_rect(Rect2(point - Vector2(10, 7), Vector2(20, 14)), Color("ed7354") if index % 2 == 0 else Color("f5c568"))
		draw_rect(Rect2(point - Vector2(8, 5), Vector2(7, 3)), Color("ffedba"))

func _gui_input(event: InputEvent) -> void:
	if not editable or get_tree().paused: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		for piece: Dictionary in pieces:
			var p: Array = piece.position
			var at := size * .5 + Vector2(float(p[0]), float(p[1])) * _radius()
			if event.position.distance_to(at) < 18:
				_drag = piece.id
				accept_event()
				break

func _input(event: InputEvent) -> void:
	if _drag.is_empty() or get_tree().paused: return
	if event is InputEventMouseMotion or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed):
		var drop: bool = event is InputEventMouseButton
		var identity: String = _drag
		if drop: _drag = ""
		var local_point: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		moved.emit(identity, (local_point - size * .5) / _radius(), drop)
		get_viewport().set_input_as_handled()

func cancel_drag() -> void:
	if _drag.is_empty(): return
	for piece: Dictionary in pieces:
		if piece.id == _drag:
			moved.emit(_drag, Vector2(float(piece.position[0]), float(piece.position[1])), true)
	_drag = ""
