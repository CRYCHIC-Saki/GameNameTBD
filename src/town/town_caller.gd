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

func conversation() -> TDDialogue:
	var talk := TDDialogue.new()
	talk.add_line(NAME, "linxia", line())
	var ask := "林夏：等你开门我再决定吃什么。现在先在镇上走走。"
	var stroll := "林夏：好，我在镇上逛。你开门我就过来点菜。"
	if phase == "to_diner":
		ask = "林夏：想吃你们今天的热菜。我走到门口就进去，不另下一单。"
		stroll = "林夏：店开着我还是会过来。先让我走到门口。"
	elif phase == "home":
		if ate:
			ask = "林夏：吃好了。钱已经在店里结过，我沿街回去。"
			stroll = "林夏：好，我自己走回去。"
		else:
			ask = "林夏：今天没吃成。你下次开门我再来。"
			stroll = "林夏：那我先回家。"
	elif ate:
		ask = "林夏：今天已经吃过了。明天开门我再点。"
		stroll = "林夏：我再逛一圈。明天才再来吃。"
	talk.add_choice([
		{"id": "ask", "label": "今天想吃点什么？", "text": ask, "speaker": NAME, "portrait": "linxia"},
		{"id": "stroll", "label": "你先在镇上逛逛吧。", "text": stroll, "speaker": NAME, "portrait": "linxia"},
	])
	return talk

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
