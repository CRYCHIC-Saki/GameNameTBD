extends RefCounted
## Layered, read-only artwork. Coordinates use the guided view's 1280×800 canvas.
const PROCESS_ART := preload("res://src/kitchen/recipe_process_art.gd")
const HOME_WALL := preload("res://assets/redraw-v1/kitchen.png")
const REGIONAL_WALLS := preload("res://assets/kitchen/closeup-regions-v2.png")
const EQUIPMENT_ALIASES := {"soup":"pot","cream":"bowl","comal":"skillet"}

static func backdrop(view: Control, area: Rect2, cuisine: String) -> void:
	var size := HOME_WALL.get_size()
	var frame := Rect2(area.position+Vector2(4,4),Vector2(area.size.x-8,318))
	var grade := Color("a69c8b")
	if cuisine in ["jp","eu"]:
		var region_size := REGIONAL_WALLS.get_size()
		var row := region_size.y*.5
		var region := Rect2(0.,1. if cuisine=="eu" else row+1.,region_size.x,row-2.)
		view.draw_texture_rect_region(REGIONAL_WALLS,frame,region,grade)
	else:
		view.draw_texture_rect_region(HOME_WALL,frame,Rect2(size*Vector2(.035,.008),size*Vector2(.93,.34)),grade)
		var counter := Rect2(frame.position+Vector2(0,232),Vector2(frame.size.x,86))
		view.draw_texture_rect_region(HOME_WALL,counter,Rect2(size*Vector2(.08,.19),size*Vector2(.84,.144)),grade)
	view.draw_rect(Rect2(frame.position,Vector2(frame.size.x,77)),Color("191f1ac2"))

static func part(view: Control, id: String, center: Vector2, width: float, angle: float = 0.0) -> void:
	var texture := PROCESS_ART.lookup(EQUIPMENT_ALIASES.get(id,id))
	if texture == null: return
	var size := texture.get_size() * (width/texture.get_width())
	var scale := view.size / Vector2(1280,800)
	view.draw_set_transform(center.round()*scale,angle,scale)
	view.draw_texture_rect(texture,Rect2(-size*.5,size),false)
	view.draw_set_transform(Vector2.ZERO,0.0,scale)

static func impulse(lane: TDCookingLane) -> float:
	var hit := lane.judgement_feedback
	if hit.get("grade","") not in ["perfect","good"] or hit.get("reason","")=="HOLD_STARTED": return 0.0
	var age := lane.clock.qte_sec - float(hit.get("shown_at_sec",-1.0))
	if age < 0.0 or age >= .30: return 0.0
	return sin(age/.30*PI)*(1.0 if hit.grade=="perfect" else .65)

static func steam(view: Control, c: Vector2, s: float, beats: float, strength: float) -> void:
	for i: int in 4:
		var rise := fposmod(beats*.38+i*.27,1.0)
		var x := (i-1.5)*23.0 + sin(rise*TAU+i)*8.0
		var tint := Color(.99,.95,.82,sin(rise*PI)*strength)
		for j: int in 3:
			var at := c+Vector2(x+sin(rise*6.0+j*.8)*4.5,-rise*71-j*5)*s
			view.draw_rect(Rect2(at.round(),Vector2(5,7)*s),tint)

static func action(view: Control, lane: TDCookingLane, p: Dictionary, module: String, c: Vector2, s: float, beats: float, dish: Dictionary = {}) -> void:
	if dish.is_empty(): dish=lane.snapshot()
	if lane.station_role == "board" or module == "M1":
		_cutting(view,lane,dish,p,c,s,impulse(lane))
		return
	if lane.food_stage.contains(":"):
		_authored_action(view,lane,p,c,s,beats,dish)
		return
	if p.is_empty():
		if dish.get("state")=="plated":
			TDIngredientIcon.draw_item(view,TDIngredientIcon.dish_item(dish),Rect2(c-Vector2(95,67)*s,Vector2(190,134)*s))
		else:
			var rest: String = {"board":"board","steamer":"basket","sushi":"mat","stockpot":"soup","claypot":"soup","oven":"oven","grill":"grill","fryer":"fryer","cold":"bowl"}.get(lane.station_role,"wok")
			part(view,rest,c,219*s)
			if not dish.ingredients.is_empty():
				var food_center := c + (Vector2(-48,15) if rest=="wok" else Vector2(0,-7))*s
				_meal(view,dish,food_center,107*s,lane.food_stage)
		return
	var hit := impulse(lane)
	var phase := fposmod(beats,1.0)
	var rebound := sin(PI*phase)
	var hold := clampf(float(p.get("held_sec",0.0))/maxf(.001,float(p.get("perfect_center_sec",1.0))),0,1)
	if module=="M7":
		part(view,"plate",c+Vector2(46,41)*s,209*s)
		var tool := "wok" if lane.station_role in ["wok","stove","skillet","tamago"] else "turner"
		part(view,tool,c+Vector2(-96,-41)*s,136*s,-.3-hold*.6)
		var pour := Vector2(-105,-45).lerp(Vector2(40,33),smoothstep(.16,.9,hold))
		pour.y -= sin(hold*PI)*31
		_meal(view,dish,c+pour*s,(70.0+62.0*hold)*s)
		return
	if module!="M6" and (lane.station_role=="steamer" or p.get("kind")=="steam"):
		part(view,"basket",c+Vector2(0,19)*s,184*s)
		var lift := (1.0-hold)*26.0+rebound*4.0+hit*10.0
		_meal(view,dish,c+Vector2(0,-7)*s,116*s)
		part(view,"lid",c+Vector2(19,-25-lift)*s,181*s,-.12+hold*.1)
		steam(view,c+Vector2(-12,-25)*s,s,beats,.70)
		return
	if module=="M6" and lane.station_role not in ["wok","skillet","stove","tamago"]:
		var vessel: String = {"oven":"oven","grill":"grill","fryer":"fryer","sushi":"mat","comal":"comal","cold":"bowl","stockpot":"soup","claypot":"soup","steamer":"basket"}.get(lane.station_role,"bowl")
		part(view,vessel,c+Vector2(0,22)*s,211*s)
		_meal(view,dish,c,117*s)
		if int(p.get("hold_index",-1))>=0: _pour(view,c,s,beats,hit,str(p.get("hold_action","")).trim_prefix("spice:"))
		return
	if lane.active_technique in ["mix","fold"]:
		part(view,"cream" if lane.station_role=="oven" else "bowl",c+Vector2(0,25)*s,200*s)
		_meal(view,dish,c+Vector2(0,1)*s,122*s)
		part(view,"paddle",c+Vector2(28+sin(beats*PI)*32,-25+cos(beats*PI)*16-hit*10)*s,95*s,sin(beats*PI)*.3)
		return
	if lane.active_technique in ["shape","roll"] or lane.station_role=="sushi":
		part(view,"mat" if lane.station_role=="sushi" else "board",c+Vector2(0,18)*s,258*s)
		_meal(view,dish,c+Vector2(-9,rebound*13-hit*8)*s,128*s)
		return
	if lane.station_role=="oven" or lane.active_technique=="bake":
		part(view,"oven",c+Vector2(0,8)*s,208*s)
		_meal(view,dish,c+Vector2(0,17)*s,96*s)
		steam(view,c-Vector2(0,42)*s,s,beats,.36)
		return
	if lane.station_role=="comal":
		part(view,"comal",c+Vector2(0,10)*s,253*s)
		_meal(view,dish,c+Vector2(0,-8)*s,139*s)
		part(view,"turner",c+Vector2(62,-46-hit*16)*s,81*s,-.36+rebound*.25)
		return
	if lane.station_role=="fryer" or lane.active_technique=="fry":
		part(view,"fryer",c+Vector2(0,16-rebound*3-hit*6)*s,207*s,-hit*.035)
		_meal(view,dish,c+Vector2(0,-5)*s,108*s)
		steam(view,c-Vector2(14,23)*s,s,beats,.52)
		return
	if lane.station_role=="grill" or lane.active_technique=="grill":
		part(view,"grill",c+Vector2(0,13-hit*4)*s,243*s)
		_meal(view,dish,c+Vector2(0,-1)*s,153*s)
		steam(view,c-Vector2(0,37)*s,s,beats,.4)
		return
	if lane.station_role in ["stockpot","claypot"] and module!="M6":
		part(view,"soup",c+Vector2(0,10)*s,221*s)
		_meal(view,dish,c+Vector2(0,-8)*s,142*s)
		steam(view,c-Vector2(0,41)*s,s,beats,.62)
		return
	var stirring: bool = module=="M3" and p.get("kind","")=="stir"
	var lift := (rebound*8+hit*19) if stirring else hit*3
	part(view,"burner",c+Vector2(-24,45)*s,144*s)
	var wok := c+Vector2(13,-12-lift*.36)*s
	part(view,"wok",wok,318*s,-.05-lift*.006)
	if not dish.ingredients.is_empty():
		var food := wok+Vector2(-52,17-lift)*s
		_meal(view,dish,food,(130.0+lift*.28)*s,lane.food_stage)
		if module=="M6" or p.get("kind","") in ["season","starch"]:
			if module=="M3" or int(p.get("hold_index",-1))>=0:
				_pour(view,wok,s,beats,hit,str(p.get("hold_action","")).trim_prefix("spice:"))
		elif stirring:
			part(view,"turner",wok+Vector2(10+29*sin(beats*TAU),-48-12*rebound)*s,99*s,-.24+rebound*.4)
			for i: int in 5:
				var travel := fposmod(phase+i*.13,1.0)
				var arc := sin(travel*PI)
				var garnish := wok+Vector2(-88+travel*89,-16-arc*(22+i*4+hit*40))*s
				var tint: Color = [Color("7c9b43"),Color("edb64f"),Color("d87b43")][i%3]
				view.draw_line(garnish,(garnish+Vector2(4+arc*3,-2)*s).round(),tint,3*s)
		if lane.food_stage not in ["empty","oil"]:
			steam(view,food-Vector2(0,24)*s,s,beats,.35)

# The kitchen atlas contains only food. The pass and carrier bubbles show the plated version.
static func _meal(view: Control, dish: Dictionary, at: Vector2, width: float, food_stage: String = "") -> void:
	if food_stage=="empty": return
	if food_stage=="oil":
		# A thin pool follows the bowl of the wok even between input phrases.
		var pool := PackedVector2Array()
		for i: int in 22:
			var angle := TAU*i/22.0
			pool.append((at+Vector2(cos(angle)*.34,sin(angle)*.13)*width).round())
		view.draw_colored_polygon(pool,Color("dba647a8"))
		view.draw_polyline(pool.slice(2,9),Color("ffe8a6"),maxf(1,width*.014))
		return
	var id := str(dish.get("recipe",{}).get("art_recipe_id",dish.recipe_id))
	var texture := TDRedrawArt.scrambled_egg() if food_stage=="scrambled_egg" else TDRedrawArt.cooking_food(id)
	var size := Vector2(width,width*.75)
	var bounds := Rect2(at-size*.5,size)
	if texture==null: texture=TDRedrawArt.serving_art()
	view.draw_texture_rect(texture,bounds,false,Color("685244") if dish.get("failed_dish",false) else Color.WHITE)

static func _cutting(view: Control,lane: TDCookingLane,dish: Dictionary,p: Dictionary,c: Vector2,s: float,hit: float) -> void:
	part(view,"board",c,267*s)
	var items: Array = dish.ingredients.values()
	if items.is_empty(): return
	var item: Dictionary = dish.ingredients.get(lane.cut_target,items[0])
	var shape: String = item.shape
	var directions: Array = item.get("cut_directions",[]).duplicate()
	directions.append_array(p.get("cut_directions",[]))
	if not directions.is_empty(): shape = TDCookingModel.shape_from_cuts(directions)
	var texture := PROCESS_ART.cut(item.ingredient_id,shape)
	var center := c + Vector2(-28,4)*s
	if texture != null: PROCESS_ART.show_texture(view,texture,center,123*s)
	else: TDIngredientIcon.draw_item(view,{"kind":"ingredient","id":item.ingredient_id,"shape":shape},Rect2(center-Vector2.ONE*49*s, Vector2.ONE*98*s))
	if not p.is_empty():
		var turn: float = [-.12,.44,.16][int(p.get("cut_direction",0))]
		part(view,"knife",c+Vector2(23,-49+28*hit)*s,111*s,turn-hit*.09)

static func _authored_action(view: Control,lane: TDCookingLane,p: Dictionary,c: Vector2,s: float,beats: float,dish: Dictionary) -> void:
	var stage := lane.food_stage.split(":")
	var vessel := stage[0]
	if dish.get("state") == "plated":
		TDIngredientIcon.draw_item(view,TDIngredientIcon.dish_item(dish),Rect2(c-Vector2(100,70)*s,Vector2(200,140)*s))
		return
	var progress := lane.food_progress()
	if vessel == "plate":
		var serving := c+Vector2(46,39)*s
		var source: String = lane.plating_source.get_slice(":",0)
		var source_layout: Array = PROCESS_ART.SURFACES.get(source,PROCESS_ART.SURFACES.wok)
		var vessel_at := c+Vector2(-103,-36)*s
		var transfer := smoothstep(.30,.94,progress)
		part(view,"plate",serving,204*s)
		part(view,source if PROCESS_ART.SURFACES.has(source) else "wok",vessel_at,float(source_layout[2])*.55*s,-.42*transfer)
		var from := vessel_at+Vector2(source_layout[0])*.55*s
		var food_at := from.lerp(serving,transfer)+Vector2(0,-26*sin(transfer*PI))*s
		_meal(view,dish,food_at,lerpf(float(source_layout[1])*.55,125.,transfer)*s)
		return
	var layout: Array = PROCESS_ART.SURFACES[vessel]
	var hit := impulse(lane)
	var stirring: bool = p.get("kind","") == "stir" and vessel in ["wok","skillet","bowl","clay","pot","tamago"]
	var toss := sin(beats*PI)*3.+hit*8. if stirring else 0.
	var base := c + Vector2(0,8.-toss*.3)*s
	if vessel in ["board","mat","wok"]:
		if vessel == "wok": part(view,"burner",c+Vector2(-23,55)*s,144*s)
		part(view,vessel,base,float(layout[2])*s,-toss*.004)
	else:
		PROCESS_ART.show_texture(view,PROCESS_ART.lookup(vessel),base,float(layout[2])*s)
	var center: Vector2 = base + (Vector2(layout[0])-Vector2(0,toss))*s
	var food_width: float = float(layout[1])*s
	if lane.active_technique == "flip" and not p.is_empty():
		# Lift and turn the food about its centre on the same beat as the input.
		var lift := sin(progress*PI)
		center.y -= (lift*20.+hit*8.)*s
		var scale := view.size / Vector2(1280,800)
		view.draw_set_transform(center.round()*scale,0.,scale*Vector2(1.,maxf(.13,absf(cos(progress*PI)))))
		PROCESS_ART.transition(view,stage[1],dish,Vector2.ZERO,food_width,progress)
		view.draw_set_transform(Vector2.ZERO,0.,scale)
	else:
		PROCESS_ART.transition(view,stage[1],dish,center,food_width,progress)
	if vessel == "basket" and stage[1] != "empty":
		var lift := 54.+sin(beats*PI)*2.+(1.-progress)*13.
		part(view,"lid",base+Vector2(26,-lift)*s,137*s,-.18)
	if stage[1] not in ["empty","oil"] and vessel in ["wok","pot","basket","oven","grill","clay","fryer","skillet","tamago"]:
		steam(view,center-Vector2(0,18)*s,s,beats,.36)
	if p.get("kind") in ["season","starch"] and int(p.get("hold_index",-1)) >= 0:
		_pour(view,center,s,beats,hit,str(p.get("hold_action","")).trim_prefix("spice:"))
	elif stirring:
		part(view,"paddle" if vessel == "bowl" else "turner",center+Vector2(40+sin(beats*PI)*15.,-33.-hit*9.)*s,82*s,-.22+sin(beats*PI)*.16)

static func _pour(view: Control, c: Vector2, s: float, beats: float, hit: float, spice: String) -> void:
	var at := c+Vector2(65,-69)*s
	var art := TDRedrawArt.ingredient(spice)
	if art != null:
		PROCESS_ART.show_texture(view,art,at,61*s)
	else: part(view,"jug",at,65*s,-.12-hit*.2)
	var tint: Color = {"salt":Color("fff2da"),"sugar":Color("fff2da"),"soy_sauce":Color("b5693d"),"pepper":Color("947257")}.get(spice,Color("fbd290"))
	for i: int in 5:
		var f := fposmod(beats*1.4+i*.2,1.0)
		view.draw_rect(Rect2(c+Vector2(34-43*f,-48+49*f*f)*s,Vector2(4,5)*s),tint)

static func impact(view: Control, lane: TDCookingLane, center: Vector2, s: float) -> void:
	var burst := impulse(lane)
	if burst<=.01: return
	var perfect: bool = lane.judgement_feedback.grade=="perfect"
	var age := lane.clock.qte_sec-float(lane.judgement_feedback.shown_at_sec)
	var t := age/.3
	var tint := Color("ffe2a0") if perfect else Color("c2edae")
	tint.a = 1.0-t
	for i: int in (7 if perfect else 4):
		var dir := Vector2.RIGHT.rotated(PI+.2+float(i)*2.7/(6 if perfect else 3))
		var at := center+dir*(32.0+76*t)*s
		view.draw_line(at.round(),(at+dir*(12.0-8*t)*s).round(),tint,3.0*s)
