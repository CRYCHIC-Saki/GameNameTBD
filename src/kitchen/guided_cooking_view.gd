class_name TDGuidedCookingView
extends Control
## Player presentation only. Every symbol reads the real lane/controller.
signal spice_clicked(lane: int, ingredient: String)
signal spice_input(lane: int, ingredient: String, pressed: bool)
const INK := Color("f6e8c6")
const GOLD := Color("eabe79")
const GREEN := Color("9fc48f")
const RED := Color("de755d")
const BG := Color("202c29")
const SPICES := ["salt","sugar","vinegar","soy_sauce","oil","wine","ginger","garlic","pepper","scallion"]
const SPICE_NAMES := ["盐","糖","醋","酱油","油","料酒","姜","蒜","花椒","葱"]
var lanes: Array = []
var beat_sec: float = 0
var bpm: float = 120
var feedback: String = ""
var customer_feedback: Array=[]
var simmer_meters: Array=[]
var font: SystemFont
var _boxes: Array = []
var _held_spice: String = ""
var _held_lane: int = -1

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and _held_lane >= 0:
		spice_input.emit(_held_lane,_held_spice,false)
		_held_lane = -1; _held_spice = ""
		get_viewport().set_input_as_handled()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	font = SystemFont.new(); font.font_names = PackedStringArray(["Microsoft YaHei UI","Microsoft YaHei"])
	mouse_filter = Control.MOUSE_FILTER_STOP

func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT or not event.pressed: return
	for lane: TDCookingLane in lanes:
		if lane.qte==null or lane.progress.get("pc_module")!="M6": continue
		for id: String in SPICES:
			if spice_rect(lane.lane_index,id).has_point(event.position+global_position):
				if lane.progress.has("hold_durations_sec") or lane.progress.get("free_seasoning",false):
					_held_lane=lane.lane_index; _held_spice=id; spice_input.emit(_held_lane,id,true)
				else: spice_clicked.emit(lane.lane_index,id)
				accept_event(); return

func spice_rect(index: int, ingredient: String) -> Rect2:
	for i: int in lanes.size():
		if lanes[i].lane_index!=index: continue
		var area: Rect2=_area(i)
		var slot: int=SPICES.find(ingredient)
		if slot<0: return Rect2()
		var r: Rect2=_spice_box(area,slot)
		return Rect2(r.position/Vector2(1280,800)*size+global_position,r.size/Vector2(1280,800)*size)
	return Rect2()

func _spice_box(area: Rect2,slot: int) -> Rect2:
	var center: Vector2=area.position+Vector2(area.size.x*.5,232)
	var angle: float=-PI*.5+slot*TAU/SPICES.size()
	var dimensions:=Vector2(76 if lanes.size()>1 else 88,48)
	return Rect2(center+Vector2(cos(angle)*area.size.x*.36,sin(angle)*156)-dimensions*.5,dimensions)

func thermal_rect(index: int) -> Rect2:
	var slot: int = 0
	for i: int in lanes.size():
		if lanes[i].lane_index == index: slot = i
	var area: Rect2 = _area(slot)
	var bar := Rect2(area.position+Vector2(35,area.size.y-65),Vector2(area.size.x-70,30))
	if lanes.size()>1: bar=Rect2(165,605+slot*32,900,20)
	return Rect2(bar.position/Vector2(1280,800)*size+global_position,bar.size/Vector2(1280,800)*size)

func _area(index: int) -> Rect2:
	return Rect2(46+index*620,157,588,504) if lanes.size()>1 else Rect2(210,151,860,520)

func _draw() -> void:
	if font == null: return
	draw_set_transform(Vector2.ZERO,0,size/Vector2(1280,800))
	draw_rect(Rect2(0,0,1280,800),Color("182420"))
	# Warm wooden surround, with restrained grain. The work area remains quiet.
	for y: int in range(0,800,80):
		draw_rect(Rect2(0,y,1280,78),Color("34413a") if y%160==0 else Color("303d36"))
		for x: int in range(0,1280,160): draw_line(Vector2(x+13,y+18),Vector2(x+128,y+18),Color("3a483f"),2)
	draw_rect(Rect2(0,0,1280,119),Color("17231f"))
	draw_line(Vector2(28,119),Vector2(1252,119),Color("816945"),2)
	_text("小 镇 食 堂",Vector2(32,34),20,GOLD)
	_text("E 返回厨房   ·   Esc 暂停",Vector2(994,34),15,Color("9daa94"))
	_boxes.clear()
	if not feedback.is_empty():
		_draw_feedback()
	else:
		for index: int in lanes.size(): _draw_lane(lanes[index],_area(index),index)
		if lanes.size()>1 and lanes.any(func(lane:TDCookingLane)->bool:return lane.thermal_qte!=null): _dual_thermal()
	_draw_beat()

func _draw_feedback() -> void:
	_text("已送达 · 客人反馈",Vector2(32,85),26,GOLD)
	for i: int in mini(2,customer_feedback.size()):
		var result: Dictionary=customer_feedback[i]
		var r:=Rect2(46+i*620,157,588,510); _panel(r,Color("283a31"))
		_text(str(result.customer_name),r.position+Vector2(25,43),22,INK)
		_text("%.1f"%float(result.satisfaction),r.position+Vector2(25,102),42,GOLD)
		_text("分   ·   %d 星"%int(result.stars),r.position+Vector2(138,99),18,GOLD)
		_text("完成度 %.0f  ·  搭配度 %.0f"%[result.quality,result.harmony],r.position+Vector2(25,140),17,Color("b3c1a5"))
		draw_line(r.position+Vector2(25,164),r.position+Vector2(562,164),Color("536049"),1)
		var reasons: Array=result.reasons.duplicate(true)
		reasons.sort_custom(func(a:Dictionary,b:Dictionary)->bool: return float(a.get("penalty",0))>float(b.get("penalty",0)))
		var y: float=r.position.y+198
		for j: int in mini(4,reasons.size()):
			var reason: Dictionary=reasons[j]; var message: String=str(reason.message)
			if reason.source=="requirements":
				message=str(reason.label)+"未达到期待（影响 %.1f 分）。"%float(reason.penalty)
			else:
				var labels: Dictionary={"QTE_M1":"切菜节拍不稳","QTE_M2":"点火偏离目标","QTE_M3":"翻炒指令有失误","QTE_M4":"控温不够稳定","QTE_M5":"炖煮温度不稳","QTE_M6":"调味顺序或节拍出错","QTE_M7":"出锅时机偏早或偏晚","NEGATIVE_AROMA":"出现焦糊或油脂异味","MISSING_REQUIRED":"菜谱必需食材或工序缺失","EXTRA_INGREDIENTS":"加入了配方之外的材料","MISSING_AROMA":"还未做出菜谱期待的香气"}
				message=labels.get(str(reason.id),str(reason.label))+"，影响了菜品品质。"
			y+=_wrapped("• "+message,Vector2(r.position.x+25,y),530,18,2)*27+13
		if reasons.is_empty(): _text("这次做法符合客人的期待。",r.position+Vector2(25,208),19,GREEN)
	_text("E 返回厨房 · 再做一份，试试调整落刀、翻炒与控温的表现",Vector2(46,692),16,INK)

func _wrapped(value: String,at: Vector2,width: float,font_size: int,max_lines: int) -> int:
	var line: String=""; var count: int=0
	for character: String in value:
		if font.get_string_size(line+character,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x>width:
			_text(line,at+Vector2(0,count*27),font_size,INK); count+=1; line=""
			if count>=max_lines: return count
		line+=character
	if not line.is_empty(): _text(line,at+Vector2(0,count*27),font_size,INK); count+=1
	return count

func _draw_lane(lane: TDCookingLane, area: Rect2, slot: int) -> void:
	var dish: Dictionary = lane.snapshot()
	if dish.is_empty(): return
	var attrs: Dictionary = dish.dish_attributes
	var p: Dictionary = lane.progress if lane.qte != null else (lane.thermal_progress if lane.thermal_qte != null else (lane.progress if lane.feedback_remaining()>0 else {}))
	var module: String = str(p.get("pc_module",""))
	var top_x: float = 32+slot*620 if lanes.size()>1 else 32
	_text(("左锅 · " if lane.lane_index==0 else ("右锅 · " if lane.lane_index==1 else "砧板 · "))+str(dish.recipe_name),Vector2(top_x,71),24,INK)
	_text("要求："+_requirements(lane),Vector2(top_x,99),15,Color("c0c8b0"))
	_panel(area,Color("283a31"))
	var label: String = lane.stage_label
	if lane.qte==null and lane.thermal_qte!=null: label="炖煮控温" if p.get("kind")=="boil" else "炒制控温"
	if module=="M1" and not dish.ingredients.is_empty(): label="切配 · "+str(dish.ingredients.values()[0].name)
	if lane.qte != null and lane.thermal_qte != null: label += "  /  控温"
	if p.is_empty(): label = "准备 · " + _next_label(lane)
	if dish.state=="plated": label="已出锅 · 返回灶台端起"
	_text(label,area.position+Vector2(24,34),21,GOLD)
	if not lane.last_result.ok and lane.last_result.code=="INSUFFICIENT_STOCK": _text("调料不足 · 本次加料未生效",area.position+Vector2(24,62),18,Color("ef9371"))
	var fine: float = 0
	for item: Dictionary in dish.ingredients.values(): fine=maxf(fine,float(item.fine))
	if module=="M1" and lane.qte != null: fine=minf(1,fine+float(p.get("cut_hits",0))/8)
	var stats: Vector2 = area.position+Vector2(area.size.x-150,64)
	_text("%.0f ℃"%float(attrs.temperature_c),stats,20,INK)
	draw_rect(Rect2(stats+Vector2(100,-18),Vector2(7,66)),Color("455b4c"))
	var h: float=clampf(float(attrs.temperature_c)/200,0,1)*62
	draw_rect(Rect2(stats+Vector2(102,46-h),Vector2(3,h)),RED)
	_text("细碎  %d / 8"%roundi(fine*8),stats+Vector2(0,24),14,Color("b3c1a5"))
	for i: int in 8: _rect(stats+Vector2(i*11,31),Vector2(8,4),GREEN if i<roundi(fine*8) else Color("455949"))
	var taste: float=0
	var dominant: int=0
	for i: int in attrs.flavor.size():
		if float(attrs.flavor[i][1])/100>taste: taste=float(attrs.flavor[i][1])/100; dominant=i
	draw_arc(stats+Vector2(36,55),14,-PI*.5,TAU-PI*.5,32,Color("465949"),4)
	draw_arc(stats+Vector2(36,55),14,-PI*.5,TAU*clampf(taste,0.01,1)-PI*.5,32,GOLD,4)
	_text(["酸","甜","苦","辣","咸","鲜","麻"][dominant],stats+Vector2(58,60),14,INK)
	var center: Vector2=area.position+Vector2(area.size.x*(.5 if module=="M6" else .46),232 if module=="M6" else 200)
	var s: float=.78 if lanes.size()>1 else 1.0
	if module=="M6": s *= .68
	_draw_food_action(center,s,lane,p,module)
	if module=="M6": _cabinet(lane,area,p)
	else: _symbols(lane,area,p)
	if module=="M1":
		_text("切面："+["横切","竖切","斜切"][int(p.get("cut_direction",0))]+"  ·  连击 ×%d"%int(p.get("combo",0)),area.position+Vector2(25,61),15,GREEN)
	elif module=="M3" and p.get("qte_kind")=="sequence":
		_text("连击 ×%d"%int(p.get("combo",0)),area.position+Vector2(25,68),16,GREEN)
	if lane.thermal_qte != null:
		if lanes.size()==1: _thermal(area,lane.thermal_progress)
	elif not p.is_empty() and module!="M6":
		var instruction: String={"M1":"按菜谱打谱  ·  空格落刀 / A、D 转向","M2":"游标到绿区中心时按空格","M3":"按谱按键  ·  最后一拍空格收势","M6":"左键按住调料 → 到量松开 · 无需控温","M7":"看提示按住空格  →  绿区中心松开"}.get(module,"跟随拍点")
		if p.get("qte_kind")=="charge" and module=="M3": instruction="长按空格 · 上笼八拍后松开"
		_text(instruction,area.position+Vector2(26,area.size.y-23),17,Color("c7cfb5"))
	_draw_judgement(lane,area)

func _requirements(lane: TDCookingLane) -> String:
	if lane.station_role=="board": return lane.stage_label if lane.sheet != null else "依照目标菜谱备菜，再端到锅中"
	var customers: Array=lane.customer_profiles()
	if customers.is_empty(): return "依照菜谱制作"
	var labels: Array[String]=[]
	for req: Dictionary in customers[mini(lane.lane_index,customers.size()-1)].requirements: labels.append(str(req.label))
	return " · ".join(labels).left(53 if lanes.size()==1 else 27)

func _next_label(lane: TDCookingLane) -> String:
	if lane.sheet == null: return "即将开始"
	var state: Dictionary=lane.sheet.snapshot()
	if state.next < state.events.size(): return str(state.events[state.next].get("label","下一拍"))
	return "完成"

func _draw_food_action(c: Vector2,s: float,lane: TDCookingLane,p: Dictionary,module: String) -> void:
	var elapsed: float=float(p.get("elapsed_sec",0))
	var beat: float=fposmod(elapsed*2,1)
	if module=="M1" or lane.station_role=="board":
		_rect(c+Vector2(-155,-80)*s,Vector2(310,174)*s,Color("674630"))
		_rect(c+Vector2(-150,-85)*s,Vector2(300,161)*s,Color("bf985e"))
		for y: int in range(0,150,12): draw_line(c+Vector2(-140,-77+y)*s,c+Vector2(137,-77+y)*s,Color("ae8451"),2)
		var hits: int=int(p.get("cut_hits",0))
		var count: int=maxi(1,hits+1)
		if hits==0:
			_ellipse(c+Vector2(-32,5)*s,Vector2(43,37)*s,Color("a64031")); _ellipse(c+Vector2(-34,-1)*s,Vector2(39,33)*s,RED)
			_rect(c+Vector2(-54,-19)*s,Vector2(10,7)*s,Color("f2a072"))
			for i: int in 5: draw_line(c+Vector2(-32,-25)*s,c+(Vector2(-32,-25)+Vector2(13,0).rotated(i*TAU/5))*s,Color("6e8c4c"),5*s)
		for i: int in (mini(count,8) if hits>0 else 0):
			var v: Vector2=c+Vector2(-65+(i%4)*37,-20+floori(float(i)/4)*29)*s
			_rect(v,Vector2(29,26)*s,Color("ad4232")); _rect(v+Vector2(2,-3)*s,Vector2(25,20)*s,RED)
		var angle: float=[0.0,PI*.5,PI*.25][int(p.get("cut_direction",0))]
		var dir:=Vector2.RIGHT.rotated(angle)
		var hit: Dictionary=lane.judgement_feedback
		var age: float=lane.clock.qte_sec-float(hit.get("shown_at_sec",-10))
		var strike: float=sin(clampf(age/.24,0,1)*PI) if hit.get("action")=="primary" and hit.get("grade") in ["perfect","good"] and age<.24 else 0.0
		var knife: Vector2=c+Vector2(10,-64+strike*30)*s
		draw_line(knife-dir*38*s,knife+dir*40*s,Color("8b9c95"),22*s)
		draw_line(knife-dir*36*s-Vector2(0,3),knife+dir*36*s-Vector2(0,3),Color("d8ded1"),17*s)
		draw_line(knife+dir*42*s,knife+dir*84*s,Color("664133"),15*s)
		return
	if lane.station_role=="steamer" or p.get("kind")=="steam":
		_ellipse(c+Vector2(0,25)*s,Vector2(124,61)*s,Color("59432e"))
		_rect(c+Vector2(-120,-45)*s,Vector2(240,75)*s,Color("aa814c"))
		for y: int in 5: _rect(c+Vector2(-120,-40+y*14)*s,Vector2(240,4)*s,Color("705332"))
		_ellipse(c-Vector2(0,47)*s,Vector2(121,57)*s,Color("d0ac6f"))
		for x: int in range(-90,100,18): draw_line(c+Vector2(x,-83)*s,c+Vector2(x,-13)*s,Color("aa8048"),3)
		_steam(c,s,elapsed); return
	if module=="M7":
		var progress: float=clampf(float(p.get("held_sec",0))/maxf(.001,float(p.get("target_max_sec",1))),0,1)
		_ellipse(c+Vector2(65,34)*s,Vector2(130,54)*s,Color("48594d"))
		_ellipse(c+Vector2(65,26)*s,Vector2(124,51)*s,Color("d7d7b8"))
		_ellipse(c+Vector2(65,23)*s,Vector2(102,38)*s,Color("b6c5a6"))
		_ellipse(c+Vector2(-107,-38)*s,Vector2(81,48)*s,Color("17251f"))
		draw_line(c+Vector2(-168,-51)*s,c+Vector2(-206,-96)*s,Color("956f48"),15*s)
		for i: int in 10:
			var at: Vector2=Vector2(-97+sin(i*2.7)*35,-41+cos(i)*18).lerp(Vector2(48+sin(i*2.7)*59,12+cos(i)*22),progress)
			_rect(c+at*s,Vector2(23,16)*s,GOLD if i%2==0 else RED)
		_steam(c,s,elapsed); return
	var toss: float=sin(elapsed*8)*9 if module=="M3" else 0
	_ellipse(c+Vector2(0,64)*s,Vector2(142,37)*s,Color("15231e"))
	for i: int in 7:
		var flame: float=14+sin(elapsed*12+i)*6
		_rect(c+Vector2(-75+i*24,92-flame)*s,Vector2(12,flame)*s,Color("e6a754"))
	_rect(c+Vector2(111,-5)*s,Vector2(88,18)*s,Color("684537"))
	_ellipse(c,Vector2(138,75)*s,Color("131e1b")); _ellipse(c-Vector2(0,4)*s,Vector2(128,67)*s,Color("52615a")); _ellipse(c-Vector2(0,8)*s,Vector2(116,57)*s,Color("27342d"))
	for i: int in 12:
		var x: float=sin(i*2.7)*82
		var y: float=cos(i*1.9)*35+toss
		_rect(c+Vector2(x,y-11)*s,Vector2(22+(i%3)*3,16)*s,Color("dfbb6b") if i%2==0 else RED)
	if module=="M3" and p.get("kind")!="season":
		var tip: Vector2=c+Vector2(sin(elapsed*6)*45,-25+cos(elapsed*6)*14)*s
		draw_line(tip,tip+Vector2(67,-79)*s,Color("b29165"),10*s)
		_rect(tip-Vector2(16,4)*s,Vector2(42,13)*s,Color("d3b27b"))
	if module=="M6" or (module=="M3" and p.get("kind") in ["season","starch"]):
		_rect(c+Vector2(88,-117)*s,Vector2(28,41)*s,INK if p.get("kind")=="starch" else Color("b9c295"))
		_rect(c+Vector2(83,-83)*s,Vector2(31,8)*s,GOLD)
		for i: int in 4: _rect(c+Vector2(75-i*13,-65+fposmod(elapsed*60+i*13,45))*s,Vector2(3,4)*s,GOLD if module=="M3" and p.get("kind")=="season" else INK)
	_steam(c,s,elapsed)

func _steam(c: Vector2,s: float,t: float) -> void:
	for i: int in 4:
		var y: float=fposmod(t*27+i*18,68)
		_rect(c+Vector2(-55+i*31+sin(t*3+i)*5,-66-y)*s,Vector2(6,18)*s,Color(.84,.87,.76,(1-y/75)*.35))

func _symbols(lane: TDCookingLane,area: Rect2,p: Dictionary) -> void:
	var c: Vector2=area.position+Vector2(area.size.x*.5,area.size.y-122)
	var kind: String=p.get("qte_kind","")
	var elapsed: float=float(p.get("elapsed_sec",0))
	if kind=="rhythm":
		_draw_notes(area,p,p.get("cut_actions",[]),lane.lane_index)
	elif kind=="sequence":
		_draw_notes(area,p,p.get("sequence",[]),lane.lane_index)
	elif kind in ["window","charge"]:
		var bar:=Rect2(c-Vector2(minf(240,area.size.x*.39),14),Vector2(minf(480,area.size.x*.78),28))
		draw_rect(bar,Color("455345"))
		var position: float=float(p.get("cursor",0))
		var low: float=float(p.get("target_min",.43)); var high: float=float(p.get("target_max",.57))
		if kind=="charge":
			var max_time: float=float(p.get("target_max_sec",1.1))*1.6
			low=float(p.get("target_min_sec",.9))/max_time; high=float(p.get("target_max_sec",1.1))/max_time
			position=clampf(float(p.get("held_sec",0))/max_time,0,1)
			draw_rect(Rect2(bar.position,Vector2(bar.size.x*position,bar.size.y)),Color("8b8b5e"))
			var preview: float=float(p.get("preview_remaining_sec",0))
			var hint: String="准备  %.1f 秒后按住空格"%preview if preview>0 else ("现在按住空格" if not p.get("charge_started",false) else "保持按住  ·  到中心松开")
			if p.get("ready_to_finish",false): hint="本步完成"
			_text(hint,c+Vector2(-155,-43),20,GOLD)
		draw_rect(Rect2(bar.position+Vector2(bar.size.x*low,0),Vector2(bar.size.x*(high-low),bar.size.y)),GREEN)
		draw_line(bar.position+Vector2(bar.size.x*(low+high)*.5,-6),bar.position+Vector2(bar.size.x*(low+high)*.5,34),GOLD,2)
		draw_rect(Rect2(bar.position+Vector2(bar.size.x*position-3,-5),Vector2(6,38)),INK)

func _cabinet(lane: TDCookingLane,area: Rect2,p: Dictionary) -> void:
	var status: Dictionary=season_prompt(p)
	var next: String=str(status.spice)
	var color: Color=GREEN if status.phase in ["press","release","holding"] else GOLD
	if status.phase=="late": color=RED
	for i: int in SPICES.size():
		var r: Rect2=_spice_box(area,i)
		var active: bool=SPICES[i]==next
		_panel(r,Color("54834b") if active else Color("344536"))
		if active: draw_rect(r.grow(4),color,false,4)
		_rect(r.position+Vector2(12,16),Vector2(15,22),[INK,GOLD,Color("a77550"),Color("79553b"),Color("c5b36b"),Color("b6c59f"),GOLD,INK,RED,GREEN][i])
		_rect(r.position+Vector2(11,12),Vector2(17,5),Color("917350"))
		_text(SPICE_NAMES[i],r.position+Vector2(32,31),16,INK)
		if active and bool(p.get("hold_pressed",false)):
			draw_circle(r.end-Vector2(9,9),6,GREEN)
		_boxes.append({"rect":r,"lane":lane.lane_index,"id":SPICES[i]})
	var width: float=minf(460,area.size.x*.8)
	var center: Vector2=area.position+Vector2(area.size.x*.5,435)
	_panel(Rect2(center-Vector2(width*.5,22),Vector2(width,91)),Color("142a25"))
	var headline: String=str(status.title)
	_text(headline,center+Vector2(-font.get_string_size(headline,HORIZONTAL_ALIGNMENT_LEFT,-1,26).x*.5,-5),26,color)
	var sub: String=str(status.detail)
	_text(sub,center+Vector2(-font.get_string_size(sub,HORIZONTAL_ALIGNMENT_LEFT,-1,16).x*.5,24),16,INK)
	var bar:=Rect2(center+Vector2(-width*.5+18,44),Vector2(width-36,22))
	draw_rect(bar,Color("3c4d45"))
	if int(p.get("hold_index",-1))>=0 and not p.get("free_seasoning",false):
		var target: float=float(p.hold_durations_sec[int(p.hold_index)])
		var tolerance: float=float(p.get("good_sec",.1))
		var span: float=target*1.5
		draw_rect(Rect2(bar.position+Vector2(bar.size.x*(target-tolerance)/span,0),Vector2(bar.size.x*tolerance*2/span,22)),GREEN)
		draw_rect(Rect2(bar.position,Vector2(bar.size.x*clampf(float(p.note_held_sec)/span,0,1),22)),Color(1,.8,.4,.6))
		draw_line(bar.position+Vector2(bar.size.x*target/span,-5),bar.position+Vector2(bar.size.x*target/span,27),INK,3)
	else:
		draw_rect(Rect2(bar.position,Vector2(bar.size.x*float(status.ratio),22)),color)
	if p.get("free_seasoning",false):
		_text("任意调料 · 剩余 %.1f秒"%float(p.remaining_sec),area.position+Vector2(24,61),17,GOLD)
	else:
		var names: Array[String]=[]
		for command: String in p.get("sequence",[]):
			var slot: int=SPICES.find(command.trim_prefix("spice:")); names.append(SPICE_NAMES[slot] if slot>=0 else "?")
		_text("左键按住 · 绿灯松开   "+" → ".join(names),area.position+Vector2(24,61),17,GOLD)

static func season_prompt(p: Dictionary) -> Dictionary:
	var index: int=int(p.get("sequence_index",-1))
	var commands: Array=p.get("sequence",[])
	var spice: String=str(commands[index]).trim_prefix("spice:") if index>=0 and index<commands.size() else ""
	var held: bool=int(p.get("hold_index",-1))>=0
	if held: spice=str(p.get("hold_action","")).trim_prefix("spice:")
	var name_index: int=SPICES.find(spice)
	var label: String=SPICE_NAMES[name_index] if name_index>=0 else "调料"
	var out: Dictionary={"phase":"waiting","title":"准备 · "+label,"detail":"等待下一份调料","spice":spice,"ratio":0.0}
	if p.get("free_seasoning",false):
		out.title="自由调味"; out.detail="按住任意调料添加"
		if held: out.title="正在添加 · "+label; out.detail="已加 %.3f份"%float(p.get("poured_amount",0)); out.phase="holding"
		return out
	var times: Array=p.get("beat_times_sec",[])
	if index<0 or index>=times.size(): out.title="调味完成"; return out
	var remaining: float=float(times[index])-float(p.get("elapsed_sec",0))+float(p.get("input_offset_sec",0))
	var tolerance: float=float(p.get("good_sec",.1))
	if held:
		var target: float=float(p.hold_durations_sec[int(p.hold_index)])
		var elapsed: float=float(p.get("note_held_sec",0))
		out.phase="holding"; out.title="按住已接收 · "+label; out.detail="再保持 %.2f秒"%maxf(0,target-elapsed)
		if not p.get("hold_pressed",false): out.title="重新按住 · "+label; out.detail="暂停后需重新按下"
		elif elapsed>=target-tolerance:
			out.phase="release" if elapsed<=target+tolerance else "late"; out.title="现在松开！" if out.phase=="release" else "已过量 · 松开"
			out.detail="已添加 %.3f份"%float(p.get("poured_amount",0))
	elif remaining<=tolerance and remaining>=-tolerance:
		out.phase="press"; out.title="现在按住 · "+label; out.detail="鼠标左键 · 保持按住"; out.ratio=1.0
	else:
		out.detail="%.1f秒后按下"%maxf(0,remaining); out.ratio=clampf(1.0-remaining/2.0,0,1)
	return out

func _thermal(area: Rect2,p: Dictionary) -> void:
	var bar:=Rect2(area.position+Vector2(35,area.size.y-65),Vector2(area.size.x-70,25))
	draw_rect(bar,Color("405346"))
	draw_rect(Rect2(bar.position+Vector2(bar.size.x*float(p.target_min),0),Vector2(bar.size.x*(float(p.target_max)-float(p.target_min)),25)),Color("5f916a"))
	draw_circle(bar.position+Vector2(bar.size.x*float(p.get("power",.5)),12),8,GOLD)
	var hint: String="调味中 · 火候托管，不计控温分" if p.get("control_suspended",false) else "鼠标吸引  ·  稳定 %d%%"%roundi(float(p.get("inside_sec",0))/maxf(.001,float(p.get("assessed_sec",p.elapsed_sec)))*100)
	_text(hint,bar.position+Vector2(0,48),15,INK)
	_text("%.1fs"%float(p.remaining_sec),bar.position+Vector2(bar.size.x-60,48),15,GOLD)

func _dual_thermal() -> void:
	_panel(Rect2(46,589,1208,81),Color("20322a"))
	for i: int in lanes.size():
		var lane: TDCookingLane=lanes[i]
		if lane.thermal_qte==null: continue
		var p: Dictionary=lane.thermal_progress
		var bar:=Rect2(165,605+i*32,900,20)
		_text(("左锅" if lane.lane_index==0 else "右锅")+(" · 托管" if p.get("control_suspended",false) else " · 鼠标"),Vector2(63,bar.position.y+15),14,INK)
		draw_rect(bar,Color("405346"))
		draw_rect(Rect2(bar.position+Vector2(bar.size.x*float(p.target_min),0),Vector2(bar.size.x*(float(p.target_max)-float(p.target_min)),20)),Color("5f916a"))
		draw_circle(bar.position+Vector2(bar.size.x*float(p.get("power",.5)),10),7,GOLD)
		if float(p.get("attraction",0))>0:
			var x: float=bar.position.x+bar.size.x*float(p.control)
			draw_line(Vector2(x,bar.position.y-3),Vector2(x,bar.end.y+3),INK,1)
		_text("暂停判分" if p.get("control_suspended",false) else "稳定 %d%% · %.1fs"%[roundi(float(p.inside_sec)/maxf(.001,float(p.get("assessed_sec",p.elapsed_sec)))*100),float(p.remaining_sec)],Vector2(1082,bar.position.y+15),13,INK)

func _draw_notes(area: Rect2,p: Dictionary,actions: Array,lane_index: int) -> void:
	var times: Array=p.get("beat_times_sec",[])
	var judged: Array=p.get("judgements",[])
	var elapsed: float=float(p.get("elapsed_sec",0))-float(p.get("input_offset_sec",0))
	var spacing: float=minf(100,(area.size.x-90)/maxi(1,actions.size()))
	var center: Vector2=area.position+Vector2(area.size.x*.5,area.size.y-125)
	var next: int=judged.find("pending")
	for i: int in actions.size():
		var point: Vector2=center+Vector2((i-(actions.size()-1)*.5)*spacing,0)
		var grade: String=str(judged[i]) if i<judged.size() else "pending"
		var color: Color=GREEN if grade=="perfect" else (GOLD if grade=="good" else (RED if grade=="miss" else Color("4d6249")))
		draw_circle(point,26,color)
		var label: String={"primary":"空格","rotate_left":"A","rotate_right":"D","up":"W","left":"A","down":"S","right":"D"}.get(actions[i],"?")
		if lane_index==1: label={"up":"↑","left":"←","down":"↓","right":"→","primary":"空格"}.get(actions[i],label)
		_text(label,point-Vector2(font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,20).x*.5,-7),20,BG if grade!="pending" else INK)
		var caption: String={"primary":"落刀","rotate_left":"左转","rotate_right":"右转"}.get(actions[i],"") if p.get("pc_module")=="M1" else ""
		if grade!="pending": caption={"perfect":"完美","good":"良好","miss":"失误"}[grade]
		_text(caption,point+Vector2(-16,47),15,color if grade!="pending" else INK)
		if i==next and i<times.size():
			var until: float=float(times[i])-elapsed
			draw_arc(point,26+clampf(until,0,1)*28,0,TAU,48,GOLD,3)
			if until>.1: _text("%.1f 秒"%until,point+Vector2(-25,-65),17,GOLD)

func _draw_judgement(lane: TDCookingLane,area: Rect2) -> void:
	if lane.feedback_remaining()<=0: return
	var event: Dictionary=lane.judgement_feedback
	var grade: String=str(event.get("grade","miss"))
	var color: Color=GREEN if grade=="perfect" else (GOLD if grade=="good" else RED)
	var reason: String=str(event.get("reason",""))
	if reason=="HOLD_STARTED":
		_text("保持按住",area.position+Vector2(25,100),25,GOLD)
		_text("到目标用量再松开",area.position+Vector2(27,125),16,GOLD)
		return
	var detail: String={"WRONG_KEY":"按键不对","WRONG_DIRECTION":"漏了转向，切面不对","MISSED_NOTE":"漏拍","OUTSIDE_WINDOW":"没有到落点","TIMEOUT":"未完成操作","EARLY_RELEASE":"松手早了","OVERCHARGED":"松手晚了"}.get(reason,"")
	if reason=="THERMAL_RESULT": detail="控温阶段完成"
	if reason=="HOLD_DURATION":
		var deviation: float=float(event.get("error_sec",0))
		detail="用量正好" if absf(deviation)<.001 else (("少倒 %.2f 秒" if deviation<0 else "多倒 %.2f 秒")%absf(deviation))
	if detail.is_empty():
		var error: float=float(event.get("error_sec",0))*1000
		detail="正中拍点" if absf(error)<1 else ("早了 %.0f 毫秒"%absf(error) if error<0 else "晚了 %.0f 毫秒"%error)
	_text({"perfect":"PERFECT  完美","good":"GOOD  良好","miss":"MISS  失误"}.get(grade,grade),area.position+Vector2(25,100),27,color)
	_text(detail,area.position+Vector2(27,125),16,color)

func _draw_beat() -> void:
	draw_rect(Rect2(0,702,1280,98),Color("17231f"))
	var phase: float=fposmod(beat_sec*bpm/60,4)
	for index: int in 5:
		var x: float=64+index*288
		var pulse: bool=absf(phase-index)<.14
		draw_line(Vector2(x,733),Vector2(x,761),GOLD if index%4==0 else (INK if pulse else Color("6b7e68")),4 if index%4==0 else 2)
	draw_line(Vector2(64,747),Vector2(1216,747),Color("63705c"),1)
	draw_circle(Vector2(64+phase/4*1152,747),7,INK)
	_text("共用节拍  %d BPM"%bpm,Vector2(64,785),14,Color("abb79c"))
	for index: int in mini(2,simmer_meters.size()):
		var meter: Dictionary=simmer_meters[index]; var x: float=445+index*395
		_text(str(meter.name),Vector2(x,785),14,INK)
		draw_rect(Rect2(x+102,774,132,10),Color("42533f")); draw_rect(Rect2(x+102,774,132*float(meter.ratio),10),GREEN)
		_text("%d%% · %.1fs"%[roundi(float(meter.ratio)*100),float(meter.remaining_sec)],Vector2(x+246,785),13,GOLD)

func _panel(rect: Rect2,color: Color) -> void:
	var box:=StyleBoxFlat.new(); box.bg_color=color; box.border_color=Color("74674a"); box.set_border_width_all(1); box.set_corner_radius_all(8); box.shadow_color=Color(0,0,0,.15); box.shadow_size=6
	draw_style_box(box,rect)
func _text(value: String,at: Vector2,font_size: int=18,color: Color=INK) -> void: draw_string(font,at,value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)
func _rect(at: Vector2,dimensions: Vector2,color: Color) -> void: draw_rect(Rect2(at.round(),dimensions.round()),color)
func _ellipse(at: Vector2,radius: Vector2,color: Color) -> void:
	var points:=PackedVector2Array()
	for i: int in 48: points.append(at+Vector2(cos(i*TAU/48)*radius.x,sin(i*TAU/48)*radius.y))
	draw_colored_polygon(points,color)
