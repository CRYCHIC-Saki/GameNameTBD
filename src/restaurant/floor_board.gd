class_name TDFloorBoard
extends RefCounted

const PATIENCE_SEC := 180.0
const PHASE_NAME := {
	"welcome": "迎宾",
	"order": "点单",
	"seat": "走向座位",
	"wait_serve": "等上菜",
	"eat": "用餐",
	"pay": "结账",
	"leave": "离开",
	"gone": "已走",
	"idle": "未入场",
}

var tickets: Array = []
var _serial: int = 0

func open_ticket(dish_id: String, dish_name: String, off_menu: bool, seat_id: String, npc_id: String) -> String:
	_serial += 1
	var id := "floor-%d" % _serial
	tickets.append({
		"id": id,
		"serial": _serial,
		"dish_id": dish_id,
		"dish_name": dish_name,
		"off_menu": off_menu,
		"seat_id": seat_id,
		"npc_id": npc_id,
		"phase": "welcome",
		"waiting": false,
		"accepted": true,
		"quality": -1.0,
		"review": -1.0,
		"patience": PATIENCE_SEC,
		"served": false,
		"walkout": false,
		"refused": false,
	})
	return id

func sync(id: String, phase: String, waiting: bool, accepted: bool, quality: float, review: float) -> void:
	var ticket := _ticket(id)
	if ticket.is_empty():
		return
	ticket["phase"] = phase
	ticket["waiting"] = waiting
	ticket["accepted"] = accepted
	ticket["quality"] = quality
	ticket["review"] = review
	if phase == "gone":
		_drop(id)

func mark_refused(id: String) -> void:
	var ticket := _ticket(id)
	if ticket.is_empty():
		return
	ticket["refused"] = true
	ticket["accepted"] = false

func serve(dish_id: String, quality: float) -> TDOutcome:
	var chosen := _earliest_queued(dish_id)
	if chosen.is_empty():
		var why := "没有坐下等这道菜的客人。" if dish_id != "" else "没有客人在等上菜。"
		return TDOutcome.new(false, "NO_GUEST", why)
	chosen["served"] = true
	chosen["quality"] = quality
	chosen["waiting"] = false
	return TDOutcome.new(true, "SERVED", String(chosen["dish_name"]), {
		"id": String(chosen["id"]),
		"dish_id": String(chosen["dish_id"]),
		"npc_id": String(chosen["npc_id"]),
		"quality": quality,
	})

func revert_serve(id: String) -> void:
	var ticket := _ticket(id)
	if ticket.is_empty():
		return
	ticket["served"] = false
	ticket["quality"] = -1.0
	ticket["waiting"] = true

func tick(delta: float) -> Array[String]:
	var expired: Array[String] = []
	if delta <= 0.0:
		return expired
	for item: Variant in tickets:
		var ticket: Dictionary = item
		if not _queued(ticket):
			continue
		ticket["patience"] = maxf(0.0, float(ticket["patience"]) - delta)
		if float(ticket["patience"]) <= 0.0:
			ticket["walkout"] = true
			ticket["waiting"] = false
			expired.append(String(ticket["id"]))
	return expired

func status_of(ticket: Dictionary) -> String:
	if bool(ticket.get("refused", false)):
		return "refused"
	if bool(ticket.get("walkout", false)):
		return "timed_out"
	if _queued(ticket):
		return "queued"
	if String(ticket.get("phase", "")) == "order" and bool(ticket.get("waiting", false)) and bool(ticket.get("off_menu", false)) and bool(ticket.get("accepted", false)):
		return "deciding"
	if bool(ticket.get("served", false)) and String(ticket.get("phase", "")) == "wait_serve":
		return "served"
	return String(ticket.get("phase", ""))

func describe(ticket: Dictionary) -> String:
	var phase := String(ticket.get("phase", ""))
	var phase_name := String(PHASE_NAME.get(phase, phase))
	var state := status_of(ticket)
	var detail := phase_name
	if state == "queued":
		detail = "等上菜，还可等%d秒" % int(ceili(float(ticket["patience"])))
	elif state == "deciding":
		detail = "菜单上没有，等你接下或拒绝"
	elif state == "timed_out":
		detail = "等不及，没吃就走了"
	elif state == "refused":
		detail = "这单已拒绝"
	elif state == "served" or phase == "eat":
		detail = "正在吃，质量%.0f" % float(ticket.get("quality", 0))
	elif phase == "pay":
		detail = "去结账"
	elif phase == "leave":
		detail = "正在离开"
	return "%s · %s · %s · 座位%s" % [String(ticket.get("npc_id", "客人")), String(ticket.get("dish_name", "")), detail, String(ticket.get("seat_id", ""))]

func live_lines() -> PackedStringArray:
	if tickets.is_empty():
		return PackedStringArray(["餐厅里还没有客人。"])
	var lines := PackedStringArray()
	for item: Variant in tickets:
		lines.append(describe(item))
	return lines

func clear() -> void:
	tickets.clear()

func _earliest_queued(dish_id: String) -> Dictionary:
	var chosen: Dictionary = {}
	var best := 1 << 30
	for item: Variant in tickets:
		var ticket: Dictionary = item
		if not _queued(ticket):
			continue
		if dish_id != "" and String(ticket["dish_id"]) != dish_id:
			continue
		if int(ticket["serial"]) < best:
			best = int(ticket["serial"])
			chosen = ticket
	return chosen

func _queued(ticket: Dictionary) -> bool:
	if String(ticket.get("phase", "")) != "wait_serve":
		return false
	if not bool(ticket.get("waiting", false)) or not bool(ticket.get("accepted", false)):
		return false
	if bool(ticket.get("served", false)) or bool(ticket.get("walkout", false)) or bool(ticket.get("refused", false)):
		return false
	return true

func _ticket(id: String) -> Dictionary:
	for item: Variant in tickets:
		var ticket: Dictionary = item
		if String(ticket["id"]) == id:
			return ticket
	return {}

func _drop(id: String) -> void:
	var kept: Array = []
	for item: Variant in tickets:
		var ticket: Dictionary = item
		if String(ticket["id"]) != id:
			kept.append(ticket)
	tickets = kept
