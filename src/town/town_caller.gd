class_name TDTownCaller
extends RefCounted
## One resident who walks the town roads, enters the diner while it is open, then goes home.

const NAME := "林夏"

var phase: String = "wander"
var cell := Vector2i.ZERO
var home := Vector2i.ZERO
var ate: bool = false
var meal_done: bool = false
var _heading: int = 0

func boot(start: Vector2i, house: Vector2i) -> void:
	cell = start
	home = house
	phase = "wander"
	ate = false
	meal_done = false

func line() -> String:
	if phase == "to_diner":
		return "林夏：店开门了，我这就过去点菜。"
	if phase == "dining":
		return "林夏已经进了你的食堂。"
	if phase == "home":
		if ate:
			return "林夏：吃好了，我沿街回去。"
		return "林夏：今天没吃成，我先回去。"
	if ate:
		return "林夏：今天已经吃过了。明天开门我再来。"
	return "林夏：我在镇上走走。你开门后，我会进来点菜。"

func tick(is_road: Callable, door: Vector2i, shop_open: bool) -> void:
	if phase == "dining":
		if meal_done:
			ate = true
			meal_done = false
			phase = "home"
		elif not shop_open:
			phase = "home"
		else:
			return
	if phase == "home":
		if cell == home:
			phase = "wander"
		else:
			_step(is_road, home)
		return
	if shop_open and phase == "wander" and door.x >= 0:
		phase = "to_diner"
	if phase == "to_diner":
		if not shop_open or door.x < 0:
			phase = "wander"
			return
		if _beside(cell, door):
			phase = "dining"
			return
		_step(is_road, door)
		if _beside(cell, door):
			phase = "dining"
		return
	_step(is_road, home)

func _beside(a: Vector2i, b: Vector2i) -> bool:
	return absi(a.x - b.x) + absi(a.y - b.y) <= 1

func _step(is_road: Callable, goal: Vector2i) -> void:
	var dirs: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
	var best := cell
	var best_distance := _manhattan(cell, goal)
	for direction: Vector2i in dirs:
		var next := cell + direction
		if not bool(is_road.call(next.x, next.y)):
			continue
		var distance := _manhattan(next, goal)
		if distance < best_distance:
			best = next
			best_distance = distance
	if best != cell:
		cell = best
		return
	if cell == goal:
		return
	var slide := cell + dirs[_heading % 4]
	_heading += 1
	if bool(is_road.call(slide.x, slide.y)):
		cell = slide

func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)
