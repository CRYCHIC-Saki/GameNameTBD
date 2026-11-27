extends RefCounted
## Edible portions and empty cookware have independent artwork. A stage is
## vessel:portion+topping, optionally followed by > and the cooked result.
const FOOD := preload("res://assets/kitchen/cooking-process.png")
const VESSELS := preload("res://assets/kitchen/closeup-cookware-v2.png")
const CUTS := preload("res://assets/kitchen/ingredient-cuts.png")
const PORTIONS := [
	"chicken","chicken_seared","pork","pork_seared","mince","mince_seared","beef","beef_seared","steak","steak_seared",
	"fillet","fish_grilled","shrimp","pink_shrimp","shells","sausage","peppers","mushrooms","onion","onion_brown",
	"tofu","peanuts","raw_chicken","half_chicken","confit","rice","fried_rice","yellow_rice","noodles","udon",
	"pasta","pasta_sheet","layers","potatoes","pastry","dough","pizza_base","pretzel","wellington","puffs",
	"dumplings","buns","egg","curds","omelet_sheet","omelet_roll","batter","crepe","whites","souffle_mix",
	"triangle","nigiri","nori","sheet_filled","sushi_roll","salmon","tuna","scallop","raw_fish","eel_grilled",
	"breaded","cutlet_blond","cutlet_crisp","tempura_wet","tempura_blond","tempura_crisp","cheese","tomatoes","scallion","basil",
	"butter","corn","duck_slices","wrapper","berries","belly","belly_brown","duck_leg","raw_duck","roast_duck",
	"knuckle","crisp_knuckle","toast","thigh","thigh_seared","eel","eel_steamed","wood_ear","tuna_loin","scallop_slice",
	"seafood","char_siu","open_pastry","duck_wrap","ramekin","risen","onigiri","egg_roll_layer","crumbs","chashu",
	"carrot","cucumber","chili","eggplant","ham","peas","lemon","radish","sea_cucumber","squid",
	"strawberries","tofu_wedge","tomato_dice","potato_chunks","ginger","pork_fat","nori_strips","clam","onion_strips","salt",
	"tomato_sauce","soy","cream","stock","dark_stock",
	"raw_buns","open_bun","raw_layers","cutlet","bream","steamed_bream","half_mackerel","fish_flesh","tied_bird","roasting_bird",
	"sushi_rice","folded_maki","pork_filling","salt_pretzel","half_pretzel","crepe_bubbles","soft_egg","half_steak","fried_shrimp","eel_skin",
	"wasabi","miso","marinade","egg_layers","dry_rice",
]
const CUT_FOODS := ["beef","beefsteak","bellpepper","carrot","char_siu","chicken","chinese_sausage","clam","cucumber","duck",
	"eel","eggplant","fish","ham","lemon","mushroom","onion","pea","pork","pork_knuckle",
	"porkbelly","potato","radish","salmon","scallop","seacucumber","shrimp","squid","strawberry","tomato",
	"tuna","woodear","scallion","ginger","garlic","nori"]
const CUT_SHAPES := ["slice","strip","chunk","dice"]
const EQUIPMENT := {
	"wok":Rect2(23,77,256,182), "pot":Rect2(293,67,261,190), "basket":Rect2(582,58,231,214),
	"bowl":Rect2(850,62,238,199), "oven":Rect2(1138,46,224,231), "fryer":Rect2(39,335,224,218),
	"grill":Rect2(298,353,254,198), "tamago":Rect2(578,326,237,228), "skillet":Rect2(836,332,262,215),
	"clay":Rect2(1116,357,268,190), "tray":Rect2(13,631,269,165), "lid":Rect2(308,615,233,194),
	"board":Rect2(564,643,264,149), "knife":Rect2(846,600,243,224), "mat":Rect2(1112,633,270,159),
	"jug":Rect2(39,884,208,203), "turner":Rect2(298,870,237,221), "paddle":Rect2(575,871,229,221),
	"burner":Rect2(852,870,220,218), "plate":Rect2(1114,895,256,178),
}
# Centre of the empty cooking surface, food width, and overall vessel width.
# All coordinates are measured in a single close-up canvas.
const SURFACES := {
	"oven": [Vector2(0,15),94,235], "pot":[Vector2(0,-14),136,215],
	"basket":[Vector2(0,-13),126,202], "bowl":[Vector2(0,-13),127,216],
	"fryer":[Vector2(-3,-10),99,216], "grill":[Vector2(-3,-16),141,222],
	"tamago":[Vector2(-20,19),89,234], "skillet":[Vector2(-26,17),115,248],
	"clay":[Vector2(0,-18),112,202], "tray":[Vector2(0,3),150,240],
	"mat":[Vector2(0,1),142,247], "board":[Vector2(-10,2),134,250],
	"wok":[Vector2(-52,17),135,314],
}
const TINTED := {"milky_stock":["cream",Color("fff4dc")],
	"vinegar":["stock",Color("fffae194")],"oil":["stock",Color("f9c553ba")],
	"ramen":["noodles",Color("ffdf94")],"sugar":["salt",Color("fff3de")]}
static var portions: Dictionary = {}

static func cell(texture: Texture2D, slot: int, columns: int, cell_size: Vector2i) -> AtlasTexture:
	var result := AtlasTexture.new()
	result.atlas = texture
	result.region = Rect2(Vector2i(slot % columns, slot / columns) * cell_size, cell_size)
	result.filter_clip = true
	return result

static func lookup(id: String) -> Texture2D:
	if portions.has(id): return portions[id]
	var result: Texture2D
	if EQUIPMENT.has(id):
		var equipment := AtlasTexture.new()
		equipment.atlas=VESSELS; equipment.region=EQUIPMENT[id]; equipment.filter_clip=true
		result=equipment
	elif id in PORTIONS:
		result = cell(FOOD, PORTIONS.find(id), 10, Vector2i(128,96))
	elif TINTED.has(id):
		result = lookup(TINTED[id][0])
	elif id == "gratin":
		result = TDRedrawArt.cooking_food("E07")
	if result != null: portions[id] = result
	return result

static func cut(id: String, shape: String) -> Texture2D:
	var row := CUT_FOODS.find(id)
	var col := CUT_SHAPES.find(shape)
	if row < 0 or col < 0: return null
	var key := id + "." + shape
	if not portions.has(key):
		var index := row * 4 + col
		portions[key] = cell(CUTS,index,12,Vector2i(112,84))
	return portions[key]

static func show_texture(view: CanvasItem, texture: Texture2D, center: Vector2, width: float, tint: Color = Color.WHITE) -> void:
	var size := texture.get_size() * (width / texture.get_width())
	view.draw_texture_rect(texture,Rect2((center - size*.5).round(),size),false,tint)

static func portion(view: Control, id: String, dish: Dictionary, center: Vector2, width: float, opacity: float) -> void:
	if id == "empty": return
	var texture: Texture2D
	if id == "dish":
		texture = TDRedrawArt.cooking_food(str(dish.get("recipe",{}).get("art_recipe_id",dish.recipe_id)))
		if texture == null: texture=TDRedrawArt.dish(str(dish.recipe_id))
		if texture == null: texture=TDRedrawArt.serving_art()
	else:
		texture = lookup(id)
	if texture == null: return
	var tint: Color = TINTED[id][1] if TINTED.has(id) else Color.WHITE
	tint.a *= opacity
	show_texture(view,texture,center,width,tint)

static func food(view: Control, composition: String, dish: Dictionary, center: Vector2, width: float, opacity: float = 1.) -> void:
	var items := composition.split("+")
	portion(view,items[0],dish,center,width,opacity)
	for i in range(1,items.size()):
		var id := items[i]
		if id in ["salt","sugar"]:
			for fleck in [Vector2(-.2,0),Vector2(-.14,-.1),Vector2(.06,.07),Vector2(.19,-.08),Vector2(.24,.03)]:
				view.draw_rect(Rect2(center+Vector2(fleck)*width,Vector2.ONE*maxf(1.,width*.015)),Color(1.,.96,.83,opacity))
			continue
		if id == "cheese" and items[0] in ["pizza_base","potatoes"]:
			for spot in [Vector2(-.19,-.01),Vector2(.12,-.08),Vector2(.09,.09)]:
				portion(view,id,dish,center+Vector2(spot)*width,width*.34,opacity)
			continue
		var size := .62
		var offset := Vector2((-.11 if i == 1 else .18),-.06)
		if id in ["stock","dark_stock","vinegar","soy","cream","tomato_sauce"]:
			size = .72
			offset = Vector2(0,-.025)
		elif id in ["salt","sugar","basil","scallion","ginger","chili","butter"]:
			size = .34
		elif items[0] == "nigiri" and id in ["salmon","tuna","scallop"]:
			size = .87
			offset = Vector2(0,-.07)
		portion(view,id,dish,center+offset*width,width*size,opacity)

static func transition(view: Control, combination: String, dish: Dictionary, center: Vector2, width: float, progress: float) -> void:
	var phases := combination.split(">")
	if phases.size() == 1 or progress <= .42:
		food(view,phases[0],dish,center,width)
	elif progress >= .70:
		food(view,phases[1],dish,center,width)
	else:
		var mix := smoothstep(.42,.70,progress)
		food(view,phases[0],dish,center,width,1.-mix)
		food(view,phases[1],dish,center,width,mix)
