class_name TDCuisineKitchen
extends RefCounted
## Workstation capabilities, not alternate food or inventory rules.
const BAYS: Dictionary={
	"cn":[["炒灶 / 砂锅",["wok","claypot"]],["炒灶 / 汤锅 / 烤炉",["wok","stockpot","oven"]],["蒸笼",["steamer"]]],
	"eu":[["煎锅 / 汤锅",["skillet","stockpot"]],["烤箱",["oven"]],["备餐台",["cold"]]],
	"jp":[["汤锅 / 玉子锅",["stockpot","tamago","skillet"]],["炭烤 / 炸锅",["grill","fryer"]],["寿司料理台",["sushi"]]],
}
const IDS: Array[String]=["kitchen.stove.left","kitchen.stove.right","kitchen.steamer"]

static func preparation_variant(chart: Dictionary, shape: String) -> Dictionary:
	var result:=chart.duplicate(true)
	if shape=="dice":
		# A chosen fine dice needs enough actual cuts, even for an old two-hit strip chart.
		var rows: Array=result.beats.filter(func(row:Dictionary)->bool:return row.get("lanes",{}).has("hand"))
		var cuts: int=rows.filter(func(row:Dictionary)->bool:return row.lanes.hand.input=="primary").size()
		while cuts<6:
			var row: Dictionary=rows.back().duplicate(true)
			row.t=float(rows.back().t)+1.5;row.lanes.hand.input="primary"
			rows.append(row);result.beats.append(row);cuts+=1
		result.beats.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return float(a.t)<float(b.t))
		return result
	var actions: Array={"slice":["primary"],"strip":["primary","primary"],"chunk":["primary","rotate_right","primary"]}.get(shape,[])
	var source: Array=chart.beats.filter(func(row:Dictionary)->bool:return row.get("lanes",{}).has("hand"))
	var notes: Array=[]
	for i: int in actions.size():
		var row: Dictionary=source[mini(i,source.size()-1)].duplicate(true)
		row.t=float(source[0].t)+i*(1.5+fposmod(float(source.back().t),1.5))
		row.lanes.hand.input=actions[i];notes.append(row)
	result.beats=notes
	return result

static func names(cuisine: String) -> Dictionary:
	var result: Dictionary={}
	for i: int in IDS.size(): result[IDS[i]]=BAYS.get(cuisine,BAYS.cn)[i][0]
	return result

static func accepts(cuisine: String, station: String, recipe: Dictionary) -> bool:
	var index:=IDS.find(station)
	if index<0: return false
	if str(recipe.get("cuisine_id","cn"))!=cuisine: return false
	var equipment: String=str(recipe.get("workstation","steamer" if recipe.get("cooking_method")=="steam" else "wok"))
	return equipment in BAYS.get(cuisine,BAYS.cn)[index][1]

static func station_for(cuisine: String, recipe: Dictionary) -> String:
	for id: String in IDS:
		if accepts(cuisine,id,recipe): return id
	return ""

const ART_PATH="res://assets/kitchen/cuisine-workstations-v1.png"
static var _source: Texture2D
const EQUIPMENT: Array[String]=["wok","stockpot","steamer","claypot","oven","skillet","sushi","tamago","grill","fryer","cold","comal"]
static var _art: Dictionary={}

static func equipment_texture(equipment: String) -> AtlasTexture:
	if _art.has(equipment): return _art[equipment]
	var index:=EQUIPMENT.find(equipment)
	if index<0: index=0
	if _source==null: _source=load(ART_PATH) as Texture2D
	var image:=_source.get_image()
	if image.is_compressed(): image.decompress()
	var rows: Array[int]=[0,380,732,1086]
	var row:=int(index/4);var origin:=Vector2i((index%4)*362,rows[row])
	var used:=image.get_region(Rect2i(origin,Vector2i(362,rows[row+1]-rows[row]))).get_used_rect()
	var texture:=AtlasTexture.new();texture.atlas=_source;texture.filter_clip=true
	texture.region=Rect2(origin+used.position,used.size);_art[equipment]=texture
	return texture

static func fixture(canvas: CanvasItem, at: Vector2, cuisine: String, index: int, scale_value: float=1.0) -> void:
	var equipment: String=BAYS.get(cuisine,BAYS.cn)[index][1][0]
	var texture:=equipment_texture(equipment)
	var width:=178.0*scale_value
	var height:=width*texture.get_height()/texture.get_width()
	canvas.draw_texture_rect(texture,Rect2(at-Vector2(width*.5,height),Vector2(width,height)),false)
