class_name TDQuestTrail
extends Control
var points: PackedVector2Array=[]
var phase: float=0

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _draw() -> void:
	if points.size()<2: return
	var color:=Color(1,.85,.44,.16+.13*(sin(phase*2)+1))
	for i: int in range(1,points.size()):
		draw_line(points[i-1],points[i],Color(color,.10),9)
		draw_dashed_line(points[i-1],points[i],color,2,8)
		var at:=points[i-1].lerp(points[i],fmod(phase*.5,1))
		draw_circle(at,2.5,Color(1,.93,.65,.65))
	draw_arc(points[-1],12,0,TAU,24,color,2)
