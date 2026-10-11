class_name TDRestaurantService
extends RefCounted

static func plan(layout: TDRestaurantLayout, occupied: Array, off_menu: bool, cashier_ready: bool) -> Dictionary:
	if not layout.staff_hired("greeter"):
		return _fail("NEED_GREETER", "迎宾还没到岗，客人停在门口")
	var desk := layout.piece_by_kind("welcome_desk")
	var kiosk := layout.piece_by_kind("kiosk")
	var counter := layout.piece_by_kind("order_counter")
	var order_piece := kiosk if not kiosk.is_empty() else counter
	var cashier := layout.piece_by_kind("cashier")
	if desk.is_empty() or order_piece.is_empty() or cashier.is_empty():
		return _fail("NO_DESK", "迎宾台、点餐位或收银台缺了")
	var door := layout.entrance()
	var desk_cell := _approach(desk)
	var order_cell := _approach(order_piece)
	var to_desk := layout.path(door, desk_cell)
	var to_order := layout.path(desk_cell, order_cell)
	if to_desk.is_empty() or to_order.is_empty():
		return _fail("UNREACHABLE", "过道走不到迎宾台或点餐位")
	var best_id := ""
	var best_path: Array[Vector2i] = []
	for item: Variant in layout.pieces():
		var seat: Dictionary = item
		if String(seat["seat_use"]) != "dining" or occupied.has(seat["id"]):
			continue
		var to_seat := layout.path(order_cell, _approach(seat))
		if to_seat.is_empty():
			continue
		if best_id == "" or to_seat.size() < best_path.size() or (to_seat.size() == best_path.size() and String(seat["id"]) < best_id):
			best_path = to_seat
			best_id = String(seat["id"])
	if best_id == "":
		return _fail("NO_SEAT", "没有能走到的空位")
	var seat := layout.piece(best_id)
	var seat_cell := _approach(seat)
	var cashier_cell := _approach(cashier)
	var to_cashier := layout.path(seat_cell, cashier_cell)
	var to_exit := layout.path(cashier_cell, door)
	if to_cashier.is_empty() or to_exit.is_empty():
		return _fail("UNREACHABLE", "座位、收银台和门口没有连上")
	return {
		"ok": true,
		"code": "VISIT",
		"message": "客人从门口进迎宾区",
		"seat_id": best_id,
		"stages": [
			_stage("welcome", to_desk, 0.45, false),
			_stage("order", to_order, 0.35, off_menu),
			_stage("seat", best_path, 0.15, false),
			_stage("wait_serve", [], 0.0, true),
			_stage("eat", [], 0.85, false),
			_stage("pay", to_cashier, 0.35, not cashier_ready),
			_stage("leave", to_exit, 0.0, false),
		],
	}

static func _approach(piece: Dictionary) -> Vector2i:
	return Vector2i(int(piece["approach_x"]), int(piece["approach_y"]))

static func _stage(phase: String, cells: Array, hold: float, wait: bool) -> Dictionary:
	var plain: Array = []
	for cell: Variant in cells:
		plain.append(cell)
	return {"phase": phase, "cells": plain, "hold": hold, "wait": wait, "cleared": false}

static func _fail(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message, "seat_id": "", "stages": []}
