class_name TDNpcGait
extends RefCounted
## Per-view presentation state: actual screen travel, never a simulation clock or save field.
var facing: Vector2i=Vector2i.DOWN
var frame: int=-1
var cycle_pixels: float=112.0
var _last: Vector2
var _ready: bool=false
var _travel: float=0.0

func reset(point: Vector2, direction: Vector2i=Vector2i.DOWN) -> void:
	_last=point;_ready=true;_travel=0.0;facing=direction;frame=-1

func sample(point: Vector2, frozen: bool=false, stopped: bool=false) -> void:
	if not _ready: reset(point);return
	var delta:=point-_last;_last=point
	if frozen: return
	if stopped or delta.length_squared()<.000001 or delta.length()>160.0:
		frame=-1;return
	if absf(delta.x)>absf(delta.y): facing=Vector2i.RIGHT if delta.x>0 else Vector2i.LEFT
	else: facing=Vector2i.DOWN if delta.y>0 else Vector2i.UP
	_travel=fposmod(_travel+delta.length(),cycle_pixels)
	frame=int(_travel/cycle_pixels*4.0)%4
