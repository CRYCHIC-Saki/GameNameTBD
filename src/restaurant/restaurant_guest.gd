class_name TDRestaurantGuest
extends Node2D

var seat_id: String = ""
var ticket_id: String = ""
var walkout: bool = false
var seated: bool = false
var speed: float = 160.0
var finished: bool = false
var goal: Vector2 = Vector2.ZERO
var service_active: bool = false
var phase: String = "idle"
var dish_id: String = ""
var dish_name: String = ""
var off_menu: bool = false
var accepted: bool = true
var quality: float = 0.0
var review_score: float = -1.0
var bob: float = 0.0
var profile: Dictionary = {}
var dining_profile: TDEconomicCustomer
var meal_intent: TDMealIntent
var character_id: String = ""
var appearance_id: int = 0
var frozen: bool = false
var externally_driven: bool=false
var sit_elapsed: float=0.0
var sit_duration: float=0.7
var sit_from: Vector2
var sit_target: Vector2
var sit_facing: Vector2i=Vector2i.DOWN
var _points: PackedVector2Array = PackedVector2Array()
var _index: int = 0
var _stages: Array = []
var _stage: int = 0
var _hold: float = 0.0
var _held: bool = false
var _waiting: bool = false
var _cell_px: int = 64

func set_path(cells: Array, cell_px: int) -> void:
	_points = PackedVector2Array()
	_cell_px = cell_px
	for cell: Variant in cells:
		var point := cell as Vector2i
		_points.append(Vector2((point.x + 0.5) * cell_px, (point.y + 0.5) * cell_px))
	finished = _points.size() <= 1
	goal = _points[-1] if not _points.is_empty() else Vector2.ZERO
	if not _points.is_empty():
		position = _points[0]
	_index = 1 if _points.size() > 1 else _points.size()

func advance(distance: float) -> void:
	if finished or _index >= _points.size() or distance <= 0.0:
		return
	while _index<_points.size() and distance>0.0:
		var target:=_points[_index]
		var remaining:=position.distance_to(target)
		# Vector2 uses float32; do not leave a sub-pixel remainder at a clock boundary.
		if remaining-distance>0.0001:
			position=position.move_toward(target,distance)
			return
		position=target;distance=maxf(0.0,distance-remaining);_index+=1
	finished=_index>=_points.size()
	if finished: position=goal

func walking_seconds() -> float:
	if finished: return 0.0
	var length: float=0.0
	var previous:=position
	for index: int in range(_index,_points.size()):
		length+=previous.distance_to(_points[index]);previous=_points[index]
	return length/maxf(1.0,speed)

func begin_sitting(target: Vector2, duration: float, direction: Vector2i) -> void:
	phase="sitting";sit_from=position;sit_target=target;sit_elapsed=0.0
	sit_duration=maxf(.1,duration);sit_facing=direction;finished=true

func advance_sitting(seconds: float) -> void:
	sit_elapsed=minf(sit_duration,sit_elapsed+maxf(0.0,seconds))
	if sit_duration-sit_elapsed<0.0000001: sit_elapsed=sit_duration
	position=sit_from.lerp(sit_target,smoothstep(0.0,1.0,sit_elapsed/sit_duration))
	seated=sit_elapsed>=sit_duration

func begin_service(stages: Array, cell_px: int, next_dish_id: String, next_dish_name: String, menu_missing: bool, npc: Dictionary) -> void:
	service_active = true
	_stages = stages
	_cell_px = cell_px
	dish_id = next_dish_id
	dish_name = next_dish_name
	off_menu = menu_missing
	accepted = true
	quality = 0.0
	review_score = -1.0
	profile = npc.duplicate(true)
	_stage = 0
	_start_stage()

func is_waiting() -> bool:
	return _waiting

func clear_wait() -> void:
	if _stage < 0 or _stage >= _stages.size():
		return
	(_stages[_stage] as Dictionary)["cleared"] = true
	_waiting = false

func refuse_order() -> void:
	accepted = false
	_waiting = false
	_jump_to_leave()

func leave_hungry() -> void:
	if walkout or phase == "gone" or phase == "leave" or phase == "eat" or phase == "pay":
		return
	walkout = true
	_waiting = false
	_jump_to_leave()

func _jump_to_leave() -> void:
	for index in _stages.size():
		if String((_stages[index] as Dictionary)["phase"]) == "leave":
			_stage = index
			_start_stage()
			return
	phase = "gone"

func service_tick(delta: float) -> void:
	if not service_active or phase == "gone":
		return
	bob += delta
	if not finished:
		advance(speed * delta)
		return
	if _stage < 0 or _stage >= _stages.size():
		phase = "gone"
		return
	var stage: Dictionary = _stages[_stage]
	if phase == "pay" and bool(stage["wait"]) and not bool(stage["cleared"]):
		_waiting = true
		return
	if not _held and float(stage["hold"]) > 0.0:
		_held = true
		_hold = float(stage["hold"])
	if _hold > 0.0:
		_hold = maxf(0.0, _hold - delta)
		return
	if bool(stage["wait"]) and not bool(stage["cleared"]):
		_waiting = true
		return
	_stage += 1
	if _stage >= _stages.size():
		phase = "gone"
		return
	_start_stage()

func _start_stage() -> void:
	_held = false
	_hold = 0.0
	_waiting = false
	var stage: Dictionary = _stages[_stage]
	phase = String(stage["phase"])
	var cells: Array = stage["cells"]
	if cells.is_empty():
		finished = true
		return
	set_path(cells, _cell_px)

func _ready() -> void:
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = TDRestaurantArt.guest_texture()
	sprite.centered = true
	sprite.position = Vector2(0, -18)
	sprite.visible = false
	add_child(sprite)

func _process(delta: float) -> void:
	if service_active or frozen or externally_driven:
		return
	advance(speed * delta)
