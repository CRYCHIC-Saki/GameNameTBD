extends RefCounted
## Layered, read-only artwork. Coordinates use the guided view's 1280×800 canvas.
static var _art: Texture2D
static var _techniques: Texture2D
const HOME_WALL := preload("res://assets/kitchen/kitchen-background-v2.png")
const TIMBER := preload("res://assets/ui-wood-v1/wood-light.png")
const PARTS := {
	"wok":Rect2(14,95,354,216), "food":Rect2(377,69,337,253), "turner":Rect2(745,38,328,313),
	"burner":Rect2(1122,66,280,266), "basket":Rect2(20,386,320,316), "lid":Rect2(384,418,316,250),
	"board":Rect2(732,405,350,277), "knife":Rect2(1108,400,328,291), "plate":Rect2(5,775,352,256),
	"jug":Rect2(413,761,248,245), "soup":Rect2(711,745,355,300), "grill":Rect2(1088,745,360,302)
}
const TECHNIQUE_PARTS := {
	"bowl":Rect2(8,44,432,393), "paddle":Rect2(462,51,392,365),
	"oven":Rect2(877,8,451,435), "fryer":Rect2(1336,8,436,438),
	"mat":Rect2(0,513,441,308), "roll":Rect2(452,496,423,344),
	"comal":Rect2(877,515,464,322), "cream":Rect2(1371,503,379,336)
}

static func backdrop(view: Control, area: Rect2, cuisine: String) -> void:
	var wall: Texture2D = HOME_WALL
	var region := Rect2(100,8,1380,254)
	if TDRegionalInterior.regional(cuisine):
		wall = TDRegionalInterior.source(TDRegionalInterior.BACKGROUNDS)
		region = TDRegionalInterior.kitchen_regions(cuisine)[0]
	var frame := Rect2(area.position + Vector2(4,4), Vector2(area.size.x-8,309))
	view.draw_texture_rect_region(wall,frame,region,Color("80775d"))
	view.draw_rect(Rect2(frame.position,Vector2(frame.size.x,76)),Color("171e19ba"))
	# Low shelf lip puts the vessel in front of the wall. Keep the note lane quiet.
	view.draw_texture_rect_region(TIMBER,Rect2(frame.position+Vector2(0,241),Vector2(frame.size.x,68)),
			Rect2(Vector2.ZERO,TIMBER.get_size()*Vector2(1.0,.38)),Color("897252"))
	for y: int in [242,246,274,275,303,307]:
		view.draw_line(frame.position+Vector2(0,y),frame.position+Vector2(frame.size.x,y),Color("796044") if y%2==0 else Color("3b362b"),2)

static func part(view: Control, id: String, center: Vector2, width: float, angle: float = 0.0) -> void:
	var source: Rect2 = PARTS[id] if PARTS.has(id) else TECHNIQUE_PARTS[id]
	var size := source.size * (width / source.size.x)
	var scale := view.size / Vector2(1280,800)
	view.draw_set_transform(center.round()*scale,angle,scale)
	if _art == null: _art = load("res://assets/kitchen/cooking-closeups-v1.png") as Texture2D
	if not PARTS.has(id) and _techniques == null: _techniques = load("res://assets/kitchen/cooking-techniques-v1.png") as Texture2D
	view.draw_texture_rect_region(_art if PARTS.has(id) else _techniques,Rect2(-size*.5,size),source)
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

static func action(view: Control, lane: TDCookingLane, p: Dictionary, module: String, c: Vector2, s: float, beats: float) -> void:
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
		part(view,"food",c+pour*s,(57.0+39.0*hold)*s)
		return
	if lane.station_role=="board" or module=="M1":
		part(view,"board",c,267*s)
		var ingredients: Array = lane.snapshot().ingredients.values()
		if ingredients.is_empty(): return
		var cuts := mini(5,int(p.get("cut_hits",0)))
		var food_id := str(ingredients[0].ingredient_id)
		var bounds := Rect2(c+Vector2(-82,-32)*s,Vector2.ONE*87*s)
		var art := TDRedrawArt.ingredient(food_id)
		if art==null or cuts==0:
			TDIngredientIcon.draw_on(view,food_id,bounds)
		else:
			var whole := TDStoryArt.fit(art,bounds)
			var count := cuts+1
			for i: int in count:
				var portion := float(i)/count
				var strip := Rect2(whole.position+Vector2(whole.size.x*portion+i*5*s,i%2*3*s),whole.size*Vector2(1.0/count,1))
				var source := Rect2(Vector2(art.get_width()*portion,0),art.get_size()*Vector2(1.0/count,1))
				view.draw_texture_rect_region(art,strip,source)
		var turn: float = [-.12, .44, .16][int(p.get("cut_direction",0))]
		part(view,"knife",c+Vector2(23,-49+28*hit)*s,111*s,turn-hit*.09)
		return
	if module!="M6" and (lane.station_role=="steamer" or p.get("kind")=="steam"):
		part(view,"basket",c+Vector2(0,19)*s,184*s)
		var lift := (1.0-hold)*26.0+rebound*4.0+hit*10.0
		part(view,"lid",c+Vector2(19,-25-lift)*s,181*s,-.12+hold*.1)
		steam(view,c+Vector2(-12,-25)*s,s,beats,.70)
		return
	if module=="M6" and lane.station_role not in ["wok","skillet","stove","tamago"]:
		var vessel: String = {"oven":"oven","grill":"grill","fryer":"fryer","sushi":"mat","comal":"comal","cold":"bowl","stockpot":"soup","claypot":"soup","steamer":"basket"}.get(lane.station_role,"bowl")
		part(view,vessel,c+Vector2(0,22)*s,211*s)
		_pour(view,c,s,beats,hit,int(p.get("hold_index",-1))>=0)
		return
	if lane.active_technique in ["mix","fold"]:
		part(view,"cream" if lane.station_role=="oven" else "bowl",c+Vector2(0,25)*s,200*s)
		part(view,"paddle",c+Vector2(28+sin(beats*PI)*32,-25+cos(beats*PI)*16-hit*10)*s,95*s,sin(beats*PI)*.3)
		return
	if lane.active_technique in ["shape","roll"] or lane.station_role=="sushi":
		part(view,"mat" if lane.station_role=="sushi" else "board",c+Vector2(0,18)*s,258*s)
		var shaped := "roll" if lane.station_role=="sushi" else "food"
		part(view,shaped,c+Vector2(-9,rebound*13-hit*8)*s,115*s,sin(beats*PI)*.1)
		return
	if lane.station_role=="oven" or lane.active_technique=="bake":
		part(view,"oven",c+Vector2(0,8)*s,208*s)
		steam(view,c-Vector2(0,42)*s,s,beats,.36)
		return
	if lane.station_role=="comal":
		part(view,"comal",c+Vector2(0,10)*s,253*s)
		part(view,"turner",c+Vector2(62,-46-hit*16)*s,81*s,-.36+rebound*.25)
		return
	if lane.station_role=="fryer" or lane.active_technique=="fry":
		part(view,"fryer",c+Vector2(0,16-rebound*3-hit*6)*s,207*s,-hit*.035)
		steam(view,c-Vector2(14,23)*s,s,beats,.52)
		return
	if lane.station_role=="grill" or lane.active_technique=="grill":
		part(view,"grill",c+Vector2(0,13-hit*4)*s,243*s)
		steam(view,c-Vector2(0,37)*s,s,beats,.4)
		return
	if lane.station_role in ["stockpot","claypot"] and module!="M6":
		part(view,"soup",c+Vector2(0,10)*s,221*s)
		steam(view,c-Vector2(0,41)*s,s,beats,.62)
		return
	var stirring: bool = module=="M3" and p.get("kind","")=="stir"
	var lift := (rebound*8+hit*19) if stirring else hit*3
	part(view,"burner",c+Vector2(-24,45)*s,144*s)
	var wok := c+Vector2(13,-12-lift*.36)*s
	part(view,"wok",wok,318*s,-.05-lift*.006)
	if module!="M2":
		var food := wok+Vector2(-48,-6-lift)*s
		part(view,"food",food,(114.0+lift*.28)*s,lift*.009)
		if module=="M6" or p.get("kind","") in ["season","starch"]:
			_pour(view,wok,s,beats,hit,int(p.get("hold_index",-1))>=0 or module=="M3")
		elif stirring:
			part(view,"turner",wok+Vector2(10+29*sin(beats*TAU),-48-12*rebound)*s,99*s,-.24+rebound*.4)
			for i: int in 5:
				var travel := fposmod(phase+i*.13,1.0)
				var arc := sin(travel*PI)
				var garnish := wok+Vector2(-88+travel*89,-16-arc*(22+i*4+hit*40))*s
				var tint: Color = [Color("7c9b43"),Color("edb64f"),Color("d87b43")][i%3]
				view.draw_line(garnish,(garnish+Vector2(4+arc*3,-2)*s).round(),tint,3*s)
		steam(view,food-Vector2(0,24)*s,s,beats,.35)

static func _pour(view: Control, c: Vector2, s: float, beats: float, hit: float, pouring: bool) -> void:
	part(view,"jug",c+Vector2(65,-69)*s,65*s,-.12-hit*.2)
	if pouring:
		for i: int in 5:
			var f := fposmod(beats*1.4+i*.2,1.0)
			view.draw_rect(Rect2(c+Vector2(34-43*f,-48+49*f*f)*s,Vector2(4,5)*s),Color("fbd290"))

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
