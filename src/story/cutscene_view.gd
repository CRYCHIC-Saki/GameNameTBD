class_name TDCutsceneView
extends Control
## A full-screen deterministic stage. The owning dialogue supplies presentation seconds.
## Full-body action keyframes, walking frames, props and timed scene cuts; no dialogue busts.
const ACTORS: Texture2D = preload("res://assets/story/cinematic-actors-v1.png")
const ARRIVAL_SCENE: PackedScene=preload("res://src/story/arrival_cutscene.tscn")
var arrival_stage: TDArrivalCutscene
var shot: String = ""
var elapsed: float = 0
var duration: float = 1
var _camera := Transform2D.IDENTITY
var _sound: AudioStreamPlayer
var _last_seconds: float = -1
var _paused: bool = false
static var _sounds: Dictionary = {}
const CUES := {
	"arrival":[[1.0,"engine"],[5.4,"paper"],[12.3,"step"],[12.8,"step"]],
	"hungry":[[0.8,"stomach"]],"messenger":[[4.8,"paper"]],
	"soup_stall":[[3.0,"clink"]],"black_soup":[[2.2,"pour"],[4.6,"clink"]],
	"reflection":[[.2,"wind"],[3.8,"unease"]],"intervene":[[1.4,"step"]],
	"ledger":[[1.55,"thud"]],"uncover":[[2.5,"cloth"]],"supplies":[[3.8,"thud"]],
	"tasting":[[2.5,"clink"]],"broadcast":[[1.1,"radio"]],"hesitate":[],
	"eat_again":[[2.0,"clink"],[4.8,"clink"]],"certificate":[[2.1,"paper"]],
	"sign":[[1.8,"paper"],[4.0,"wind"]],"fire":[[.1,"fire"]]}

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	clip_contents=true
	arrival_stage=ARRIVAL_SCENE.instantiate() as TDArrivalCutscene
	add_child(arrival_stage);arrival_stage.hide()
	_sound=AudioStreamPlayer.new();_sound.volume_db=-15;add_child(_sound)

func show_shot(id: String, seconds: float, span: float, silent_seek: bool=false) -> void:
	if id!=shot or seconds<elapsed:
		stop_audio();_last_seconds=-1
	shot=id;elapsed=seconds;duration=maxf(.01,span);visible=id!=""
	if arrival_stage!=null:
		arrival_stage.visible=TDArrivalCutscene.SEGMENTS.has(id)
		if arrival_stage.visible: arrival_stage.sample_segment(id,seconds)
	if not id.is_empty() and not _paused and _sound!=null and not silent_seek and seconds-_last_seconds<=1.5:
		for cue: Array in CUES.get(id,[]):
			if _last_seconds<float(cue[0]) and seconds>=float(cue[0]):
				_sound.stream=sound(str(cue[1]));_sound.play()
	_last_seconds=seconds
	queue_redraw()

func stop_audio() -> void:
	if _sound!=null: _sound.stop()

func set_audio_paused(value: bool) -> void:
	_paused=value
	if _sound!=null: _sound.stream_paused=value

func _draw() -> void:
	if shot.is_empty(): return
	if TDArrivalCutscene.SEGMENTS.has(shot): return
	# Fit the stage without stretching characters. Letterbox both gameplay and dialogue chrome.
	draw_rect(Rect2(Vector2.ZERO,size),Color("090e13"))
	var scale_factor:=minf(size.x/1280.0,size.y/720.0)
	var origin:=(size-Vector2(1280,720)*scale_factor)*.5
	_camera=Transform2D(0,Vector2.ONE*scale_factor,0,origin)
	draw_set_transform_matrix(_camera)
	var t:=clampf(elapsed/duration,0,1)
	var bg:=0 if shot in ["arrival","hungry","messenger"] else (1 if shot in ["soup_stall","black_soup","reflection","intervene","ledger","broadcast"] else (2 if shot in ["uncover","supplies","sign","fire"] else 3))
	draw_texture_rect(TDStoryArt.background(bg),Rect2(0,0,1280,720),false)
	match shot:
		"arrival": arrival(t)
		"hungry":
			actor("hero",Vector2(600,605),340,Vector2i.DOWN,false,0,lerpf(0,-.75,phase(t,.15,.5)),sin(phase(t,.2,.65)*PI)*.12)
			if t>.32 and t<.83: caption("咕——",Vector2(750,500))
		"messenger":
			crate(Rect2(700,535,210,100))
			actor("hero",Vector2(310,630),210,Vector2i.RIGHT)
			# Cape billows independently of the actor; the book cover opens at her hands.
			var flap:=sin(elapsed*5)*12
			draw_colored_polygon(PackedVector2Array([Vector2(760,340),Vector2(900+flap,455),Vector2(865,520),Vector2(780,430)]),Color("2c395b"))
			actor("aling",Vector2(800,540),260,Vector2i.DOWN,false,-.45,.45)
			book(Vector2(800,444),phase(t,.28,.62),0)
		"soup_stall":
			prop(5,Rect2(900,80,180,230))
			var lift:=phase(t,.18,.65)
			actor("chen",Vector2(650,730),530,Vector2i.DOWN,false,-lift*2.2,lift*2.2)
			foreground(1,492)
			var ladle_y:=lerpf(465,345,lift)
			draw_line(Vector2(595,ladle_y),Vector2(720,ladle_y),Color("af9873"),8);bowl(Vector2(740,ladle_y),22)
			crowd(t,false);actor("hero",Vector2(220,770),420,Vector2i.UP);actor("aling",Vector2(1050,770),420,Vector2i.UP)
		"black_soup":
			actor("chen",Vector2(700,730),540,Vector2i.DOWN,false,-.2,lerpf(.5,1.6,phase(t,.12,.55)))
			foreground(1,495);bowl(Vector2(770,485),42)
			var hand:=Vector2(540,390).lerp(Vector2(770,395),phase(t,.2,.48))
			draw_line(Vector2(720,405),hand,Color("b29874"),7);bowl(hand,16)
			if t>.48 and t<.67: draw_line(hand+Vector2(0,13),Vector2(770,465),Color("271a25"),8)
			if t>.7:
				var zoom:=phase(t,.7,1);draw_rect(Rect2(0,0,1280,720),Color(0,0,0,zoom*.6))
				prop(2,Rect2(390,200,500,380).grow(zoom*32))
		"reflection":
			if t<.28:
				actor("hero",Vector2(620,780),520,Vector2i.DOWN,false,-1.0,1.0)
				bowl(Vector2(620,lerpf(450,400,phase(t,0,.15))),70)
			else:
				draw_rect(Rect2(0,0,1280,720),Color(0,0,0,.82));prop(2,Rect2(350,150,580,480))
				var alpha:=phase(t,.32,.5)*.55
				# Reflect the actual hero's face, then animate only its mouth into the wrong smile.
				var face:=TDChefArt.texture(Vector2i.DOWN,-1)
				draw_texture_rect_region(face,Rect2(530,277,210,150),Rect2(0,0,face.get_width(),face.get_height()*.46),Color(.45,.6,.65,alpha))
				draw_arc(Vector2(640,368),28,0,PI,20,Color(.95,.75,.52,alpha),4)
				if t>.52 and t<.77: caption("“好吃。”",Vector2(900,350))
				if t>.78: crowd(1,true)
		"intervene":
			actor("hero",Vector2(260,760),430,Vector2i.RIGHT);actor("chen",Vector2(1010,760),460,Vector2i.LEFT)
			crowd(t,true)
			var travel:=phase(t,.12,.55)
			actor("aling",Vector2(1130,770).lerp(Vector2(640,750),travel),430,Vector2i.DOWN,travel>0 and travel<1,-phase(t,.5,.8)*1.5,phase(t,.5,.8)*1.5)
		"ledger":
			actor("aling",Vector2(640,820),540,Vector2i.DOWN,false,-.5,.5)
			book(Vector2(640,600),1-phase(t,.4,.55),sin(phase(t,.4,.6)*PI)*.15)
		"uncover":
			# The painted room already contains four furnished tables and the old fridge.
			pass # Stove, fridge and four two-seat tables are already in this background.
			actor("aling",Vector2(655,660),390,Vector2i.LEFT,false,-phase(t,.2,.5)*2,0)
			var pull:=phase(t,.25,.55)
			if pull<1:
				var cloth_left:=120+pull*710;var cloth_width:=700*(1-pull)+20
				draw_colored_polygon(PackedVector2Array([Vector2(cloth_left,250-pull*100),Vector2(cloth_left+cloth_width,260-pull*150),Vector2(cloth_left+cloth_width,630-pull*330),Vector2(cloth_left,620-pull*230)]),Color("c7b795"))
			for i: int in 48:
				var p:=phase(t,.3,1);var alpha:=sin(p*PI)*.5
				draw_rect(Rect2(150+(i*97)%720+p*60,570-(i%6)*40-p*(100+(i%4)*25),3,3),Color(1,.94,.72,alpha))
		"supplies":
			actor("hero",Vector2(575,540),290,Vector2i.RIGHT)
			var travel:=phase(t,0,.48);var put:=phase(t,.5,.72)
			var pos:=Vector2(690,560).lerp(Vector2(700,670),travel)
			actor("chen",pos,390,Vector2i.LEFT,travel<1,-.7,.7)
			prop(4,Rect2(Vector2(pos.x-100,pos.y-260).lerp(Vector2(185,380),put),Vector2(200,135)))
			# The basket is set on the existing left table; no second floating table.
		"tasting","hesitate","eat_again": tasting(t)
		"broadcast":
			prop(5,Rect2(420,100,310,430))
			draw_colored_polygon(PackedVector2Array([Vector2(820,160),Vector2(900,130),Vector2(900,235),Vector2(820,205)]),Color("7c888b"))
			for i: int in 3:
				var wave:=fposmod(elapsed*.55+i*.33,1)
				draw_arc(Vector2(905,180),35+wave*130,-.65,.65,24,Color(.95,.85,.52,(1-wave)*.6),3)
			caption("滋……",Vector2(940,300))
		"certificate":
			actor("hero",Vector2(650,730),640,Vector2i.DOWN,false,0,phase(t,.12,.4)*1.2)
			var put:=phase(t,.12,.4)
			foreground(3,530)
			draw_texture_rect(TDStoryArt.prop(7),Rect2(500,lerpf(340,500,put),220,75),false)
			if t>.4:
				var stroke:=phase(t,.45,.8)
				draw_line(Vector2(575,520),Vector2(575+stroke*65,550),Color("f3d5bf"),17)
				draw_circle(Vector2(575+stroke*65,550),12,Color("edb99a"))
				# The bent corner flattens under the moving hand.
				draw_colored_polygon(PackedVector2Array([Vector2(660,530),Vector2(680,530),Vector2(680,530-(1-stroke)*30)]),Color("e0c789"))
		"sign": sign_scene(t)
		"fire":
			draw_rect(Rect2(0,0,1280,720),Color(0,0,0,.7));pot(Vector2(640,400))
			for i: int in 11:
				var x:=530+i*22;var h:=60+sin(elapsed*6+i)*25
				draw_colored_polygon(PackedVector2Array([Vector2(x-17,480),Vector2(x,480-h),Vector2(x+17,480)]),Color(1,.4+i*.035,.08,.95))
			draw_rect(Rect2(0,0,1280,720),Color(0,0,0,phase(t,.75,1)))
	# Cinematic bars replace the dialogue panel. No direction text masquerades as animation.
	draw_rect(Rect2(0,0,1280,48),Color("090e13"));draw_rect(Rect2(0,672,1280,200),Color("090e13"))
	draw_set_transform_matrix(Transform2D.IDENTITY)

func arrival(t: float) -> void:
	var bus:=phase(t,0,.24)
	# Keep the traveller behind the bus until the disembark step.
	var walk:=phase(t,.24,.36)
	var cross:=phase(t,.82,.98)
	actor("hero",Vector2(240,470).lerp(Vector2(390,600),walk)+Vector2(0,cross*70),225,Vector2i.DOWN,(walk>0 and walk<1) or (cross>0 and cross<1))
	prop(0,Rect2(lerpf(20,1420,bus),240,600,350))
	draw_line(Vector2(90,615),Vector2(440,615),Color("ebe2b5"),7)
	if t>.38 and t<.80:
		var open:=phase(t,.38,.56)
		prop(1,Rect2(470,lerpf(670,180,open),370,400))
		if t>.58:
			for i: int in 3: draw_arc(Vector2(660,368),24+i*5,0,TAU,40,Color("a94d3d"),2)
			caption("河口镇",Vector2(845,280))
			caption("百国商船汇聚",Vector2(845,330),24)
			caption("天下千味之港",Vector2(845,368),24)

func tasting(t: float) -> void:
	actor("chen",Vector2(1040,720),620,Vector2i.LEFT,false,-.8,.8)
	actor("aling",Vector2(640,720),640,Vector2i.DOWN,false,-.45,.55)
	foreground(3,530)
	var portions:=3-maxi(0,int(t*3)) if shot=="eat_again" else 10
	plate(Vector2(630,590),portions)
	var lift:=lerpf(.3,.65,phase(t,0,.25))
	if shot=="tasting": lift=phase(t,.18,.58)
	elif shot=="eat_again": lift=sin(phase(t,.08,.95)*PI*2-.7)*.5+.5
	var tip:=Vector2(637,580).lerp(Vector2(637,385),lift)
	var hand:=Vector2(682,460).lerp(Vector2(667,395),lift)
	for dx: int in [0,8]: draw_line(hand+Vector2(dx,0),tip+Vector2(dx,0),Color("b5905f"),5)

	if shot!="hesitate" and lift>.2 and lift<.92: draw_rect(Rect2(tip-Vector2(10,4),Vector2(22,13)),Color("f3cd62"))
	if shot=="eat_again":
		var gaze:=phase(t,0,.25)
		draw_line(Vector2(618,365),Vector2(625,370+gaze*4),Color("30314a"),3)

func sign_scene(t: float) -> void:
	draw_rect(Rect2(330,150,570,165),Color("71503a"));caption("家常菜",Vector2(750,296),37)
	var put:=phase(t,.08,.4)
	actor("aling",Vector2(660,660),390,Vector2i.LEFT,false,-put*1.4,0)
	var y:=lerpf(440,155,put);var fold:=phase(t,.58,.88)
	var a:=Vector2(900,y+150-fold*110);var b:=Vector2(900-fold*290,y+150)
	draw_colored_polygon(PackedVector2Array([Vector2(330,y),Vector2(900,y),a,b,Vector2(330,y+150)]),Color("f4e6b9"))
	caption("讨伐军本部",Vector2(390,y+73),39,Color("60402f"))
	if fold>0: draw_colored_polygon(PackedVector2Array([a,b,b+Vector2(35,-20)*fold]),Color("b7a07e"))

func actor(who: String, feet: Vector2, height: float, facing: Vector2i=Vector2i.DOWN, walking: bool=false, left_arm: float=0, right_arm: float=0, bend: float=0) -> void:
	var frame:=int(elapsed*6)%4 if walking else -1
	var art: Texture2D=TDChefArt.texture(facing,frame) if who=="hero" else TDStoryArt.sprite(who,facing,frame)
	var width:=height*art.get_width()/art.get_height()
	draw_set_transform_matrix(_camera*Transform2D(0,feet))
	draw_ellipse_shadow(Vector2.ZERO,width*.42)
	draw_set_transform_matrix(_camera*Transform2D(bend,feet))
	var pose:=pose_for(who)
	if not walking and pose>=0:
		var row:=int({"hero":0,"aling":1,"chen":2}[who])
		art=TDStoryArt.cropped_view("cinematic:"+who+str(pose),ACTORS,Rect2i(pose*256,[0,338,674][row],256,[338,336,350][row]))
		width=height*art.get_width()/art.get_height()
	draw_texture_rect(art,Rect2(-width*.5,-height,width,height),false)
	draw_set_transform_matrix(_camera)

func pose_for(who: String) -> int:
	var t:=elapsed/duration
	if who=="hero":
		if shot=="hungry": return 0 if t<.23 else 1
		if shot=="arrival" and t>.38 and t<.8: return 2
		if shot=="reflection": return 2
		if shot=="certificate": return 4 if t<.45 else 5
	if who=="aling":
		if shot=="messenger": return 0 if t<.4 else 1
		if shot=="ledger": return 1 if t<.5 else 0
		if shot=="intervene": return 0 if t<.55 else 3
		if shot=="uncover": return 0 if t<.25 else 2
		if shot=="sign": return 0 if t<.2 else 3
		if shot in ["tasting","hesitate","eat_again"]:
			if shot=="hesitate": return 4
			if shot=="tasting": return 4 if t<.55 else 5
			return 5 if t>.35 and t<.58 else 4
	if who=="chen":
		if shot=="soup_stall": return 0 if t<.18 else (1 if t<.42 else 2)
		if shot=="black_soup": return 1 if t<.25 else 4
		if shot=="supplies": return 3 if t<.55 else 4
		if shot in ["tasting","hesitate","eat_again"]: return 5
	return -1

func draw_ellipse_shadow(at: Vector2, radius: float) -> void:
	var pts:=PackedVector2Array()
	for i: int in 32: pts.append(at+Vector2(cos(i*TAU/32)*radius,sin(i*TAU/32)*radius*.2))
	draw_colored_polygon(pts,Color(0,0,0,.25))

func crowd(t: float, turn: bool) -> void:
	for i: int in 5:
		var x:=100+i*240;var y:=840.0 if not turn else 870.0
		var shift:=phase(t,.12+i*.06,.3+i*.06)*8 if turn else 0.0
		draw_circle(Vector2(x,y-260),55,Color("253039"));draw_rect(Rect2(x-58,y-220,116,190),Color("253039"))
		draw_circle(Vector2(x+shift,y-265),5,Color("82939a"))
		bowl(Vector2(x,y-80),40)

func foreground(index: int, y: float) -> void:
	var bg:=TDStoryArt.background(index)
	draw_texture_rect_region(bg,Rect2(0,y,1280,720-y),Rect2(0,y/720*bg.get_height(),bg.get_width(),(720-y)/720*bg.get_height()))

func table(rect: Rect2) -> void:
	draw_rect(Rect2(rect.position+Vector2(12,rect.size.y),Vector2(18,75)),Color("573d31"))
	draw_rect(Rect2(rect.end+Vector2(-30,0),Vector2(18,75)),Color("573d31"))
	draw_rect(rect,Color("936e47"));draw_rect(rect,Color("c6a36d"),false,4)

func crate(rect: Rect2) -> void:
	draw_rect(rect,Color("7c573a"));draw_rect(rect.grow(-5),Color("af8a56"),false,4)
	draw_line(rect.position,rect.end,Color("af8a56"),5)

func book(center: Vector2, openness: float, angle: float) -> void:
	draw_set_transform_matrix(_camera*Transform2D(angle,Vector2.ONE*1.6,0,center))
	var w:=35+openness*27
	draw_rect(Rect2(-w,-28,w*2,55),Color("63462e"))
	draw_rect(Rect2(-w+3,-25,w*2-6,49),Color("c69b55"),false,1.5)
	if openness<.12:
		draw_string(ThemeDB.fallback_font,Vector2(-14,-3),"密",HORIZONTAL_ALIGNMENT_LEFT,-1,23,Color("edce82"))
		draw_string(ThemeDB.fallback_font,Vector2(-14,23),"令",HORIZONTAL_ALIGNMENT_LEFT,-1,23,Color("edce82"))
		draw_set_transform_matrix(_camera);return
	draw_rect(Rect2(-w+4,-24,w*2-8,46),Color("e5d7af"))
	draw_line(Vector2(0,-24),Vector2(0,20),Color("99866a"),3)
	for i: int in 4: draw_line(Vector2(-w+10,-15+i*8),Vector2(-10,-15+i*8),Color("a48c73"),2)
	draw_set_transform_matrix(_camera)

func bowl(center: Vector2, radius: float) -> void:
	draw_arc(center,radius,0,PI,24,Color("d1c6ab"),radius*.5)
	draw_line(center-Vector2(radius,0),center+Vector2(radius,0),Color("302330"),radius*.18)

func pot(center: Vector2) -> void:
	draw_arc(center,95,0,PI,24,Color("2d3338"),50)
	draw_line(center-Vector2(140,0),center+Vector2(140,0),Color("4e4d48"),12)

func plate(center: Vector2, portions: int=10) -> void:
	var points:=PackedVector2Array()
	for i: int in 40: points.append(center+Vector2(cos(i*TAU/40)*100,sin(i*TAU/40)*33))
	draw_colored_polygon(points,Color("d8dfc7"))
	for i: int in portions:
		var at:=center+Vector2((i*29)%100-50,(i*17)%36-18)
		if i%2==0:
			draw_colored_polygon(PackedVector2Array([at+Vector2(-14,3),at+Vector2(-6,-9),at+Vector2(7,-6),at+Vector2(18,4),at+Vector2(5,10)]),Color("efc95a"))
		else: draw_colored_polygon(PackedVector2Array([at+Vector2(-12,6),at+Vector2(-3,-8),at+Vector2(16,5)]),Color("c75937"))

func ladle(center: Vector2, angle: float) -> void:
	draw_set_transform_matrix(_camera*Transform2D(angle,center))
	draw_line(Vector2(0,0),Vector2(48,-110),Color("ad9573"),9);bowl(Vector2.ZERO,30)
	draw_set_transform_matrix(_camera)

func prop(index: int, box: Rect2) -> void:
	var art:=TDStoryArt.prop(index);draw_texture_rect(art,TDStoryArt.fit(art,box),false)

func caption(value: String, at: Vector2, font_size: int=30, color: Color=Color("f1e7c8")) -> void:
	draw_string(ThemeDB.fallback_font,at+Vector2(2,2),value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,Color("151b22"))
	draw_string(ThemeDB.fallback_font,at,value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)

static func phase(t: float, start: float, end: float) -> float:
	return smoothstep(start,end,t)

static func sound(kind: String) -> AudioStreamWAV:
	if _sounds.has(kind): return _sounds[kind]
	# Original small Foley cues. No voice synthesis and no background metronome.
	var span:=1.8 if kind in ["engine","wind","unease","fire"] else .45
	var rate:=22050;var samples:=PackedByteArray();samples.resize(int(span*rate)*2)
	var frequency:=float({"engine":74,"step":105,"paper":900,"stomach":65,"clink":1550,"pour":460,"unease":91,"thud":100,"cloth":650,"radio":420,"wind":350,"fire":510}.get(kind,300))
	for i: int in samples.size()/2:
		var sec:=float(i)/rate;var envelope:=sin(PI*sec/span)*exp(-sec*(4 if span<1 else .8))
		var wave:=sin(TAU*frequency*sec+sin(sec*37)*2)*.5+sin(TAU*frequency*1.413*sec)*.25
		if kind in ["paper","cloth","wind","fire","pour"]: wave=sin(i*1.73+sin(i*.357)*4)*.55
		samples.encode_s16(i*2,int(clampf(wave*envelope,-1,1)*16000))
	var stream:=AudioStreamWAV.new();stream.format=AudioStreamWAV.FORMAT_16_BITS;stream.mix_rate=rate;stream.data=samples
	_sounds[kind]=stream;return stream
