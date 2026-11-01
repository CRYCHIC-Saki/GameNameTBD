class_name TDDaylight
extends RefCounted
## The application supplies game minutes. No wall-clock timer or visual random source.
static func sample(minute: float, interior: bool = false) -> Dictionary:
	var points: Array=[480.0,600.0,960.0,1080.0,1170.0,1320.0,1560.0]
	var colors: Array[Color]=[Color("ffe5c1"),Color.WHITE,Color.WHITE,Color("edb795"),Color("969ac0"),Color("7585ac"),Color("66769a")]
	var at: float=clampf(minute,480,1560)
	var tint: Color=colors.back()
	for i: int in points.size()-1:
		if at<=float(points[i+1]):
			var t: float=smoothstep(float(points[i]),float(points[i+1]),at)
			tint=colors[i].lerp(colors[i+1],t);break
	if interior: tint=tint.lerp(Color("fff1d9"),0.6)
	return {"tint":tint,"lamps":smoothstep(1020.0,1170.0,at),"period":"晨间" if at<600 else ("白昼" if at<1020 else ("黄昏" if at<1170 else "夜晚"))}

static func glow(canvas: CanvasItem, at: Vector2, strength: float, radius: float = 32.0) -> void:
	if strength<=0: return
	var tint: Color=canvas.self_modulate
	var light:=Color(1.0/maxf(.1,tint.r),.72/maxf(.1,tint.g),.32/maxf(.1,tint.b),1)
	for i: int in range(3,0,-1):
		light.a=strength*.07;canvas.draw_circle(at,radius*i/3.0,light)
	light.a=strength;canvas.draw_rect(Rect2(at-Vector2(4,5),Vector2(8,10)),light)
