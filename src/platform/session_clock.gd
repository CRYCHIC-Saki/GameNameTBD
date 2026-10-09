class_name TDClock
extends RefCounted

var real_sec: float = 0.0
var game_sec: float = 0.0
var qte_sec: float = 0.0
var paused: bool = false

func advance(delta_sec: float) -> bool:
	if not is_finite(delta_sec) or delta_sec < 0.0:
		return false
	real_sec += delta_sec
	if not paused:
		game_sec += delta_sec
		qte_sec += delta_sec
	return true
