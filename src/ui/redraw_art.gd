class_name TDRedrawArt
extends RefCounted
## Read-only versioned artwork. IDs and all simulation data remain authoritative elsewhere.
const INDEX: String="res://assets/redraw-v1/index.json"
const EMPTY_PLATE_REGION := Rect2(1114,895,256,178)
const EMOTIONS: Array[String]=["calm","happy","surprised","puzzled","angry","sad"]
static var _index: Dictionary={}
static var _cache: Dictionary={}
static var _images: Dictionary={}

static func catalog() -> Dictionary:
	if _index.is_empty():
		_index=JSON.parse_string(FileAccess.get_file_as_string(INDEX))
		_index.regions=JSON.parse_string(FileAccess.get_file_as_string("res://assets/redraw-v1/icon-regions.json"))
		_index.ingredients={};_index.dishes={}
		for id: String in _index.ingredient_ids:
			var cell_index: int = _index.ingredient_slots[id]
			_index.ingredients[id] = {"path":"res://assets/redraw-v1/ingredients-%d.png" % (cell_index/30),"index":cell_index%30}
		for id: String in _index.dish_ids:
			var slot: int = int(_index.get("dish_slots", {}).get(id, _index.dish_ids.find(id)))
			_index.dishes[id] = {"path":"res://assets/redraw-v1/dishes-%d.png" % (slot/20),"index":slot%20}
		var standalone: Dictionary = _index.get("standalone_dishes", {})
		for id: String in standalone:
			if not _index.dishes.has(id): _index.dish_ids.append(id)
			_index.dishes[id] = standalone[id]
	return _index

static func image(path: String) -> Image:
	if not _images.has(path):
		var texture: Texture2D=load(path)
		var source:=texture.get_image()
		if source.is_compressed(): source.decompress()
		_images[path]=source
	return _images[path]

static func cell(path: String,index: int,columns: int,rows: int,trim: bool=true) -> Texture2D:
	var key: String="%s:%d:%d:%d:%s"%[path,index,columns,rows,trim]
	if not _cache.has(key):
		var texture: Texture2D=load(path)
		var start:=Vector2i(roundi((index%columns)*texture.get_width()/float(columns)),roundi((index/columns)*texture.get_height()/float(rows)))
		var end:=Vector2i(roundi((index%columns+1)*texture.get_width()/float(columns)),roundi((index/columns+1)*texture.get_height()/float(rows)))
		var region:=Rect2i(start,end-start)
		if catalog().regions.has(path.get_file()):
			var measured: Array=catalog().regions[path.get_file()][index]
			region=Rect2i(int(measured[0]),int(measured[1]),int(measured[2]),int(measured[3]))
		if trim:
			var used:=TDStoryArt._walk_bounds(image(path).get_region(region))
			region=Rect2i(region.position+used.position,used.size)
		var result:=AtlasTexture.new();result.atlas=texture;result.region=Rect2(region);result.filter_clip=true
		_cache[key]=result
	return _cache[key]

static func portrait(who: String, emotion: String = "") -> Texture2D:
	var key: String = {"焰子":"hero","阿铃":"aling","罗金娜":"chen","灰烬司祭":"chen","罗厄":"luo","维托":"vito","赫兹":"hertz","日奈":"hina","希娜":"hina"}.get(who,who)
	if key not in ["hero","aling","chen","luo","vito","hertz","hina"]: return null
	var mood: String = {"surprised":"puzzled","sad":"troubled","":"calm"}.get(emotion,emotion)
	var path := "res://content/story/vn/portraits/%s/%s_base_base_%s_mid.tres" % [key,key,mood]
	if not ResourceLoader.exists(path): path = "res://content/story/vn/portraits/%s/%s_base_base_calm_mid.tres" % [key,key]
	return load(path) as Texture2D

static func ingredient(id: String) -> Texture2D:
	var key: String=id if catalog().ingredients.has(id) else {"peanut_oil":"oil","peppercorn":"pepper","cooking_wine":"wine","shanxi_vinegar":"vinegar"}.get(id,id)
	var entry: Dictionary=catalog().ingredients.get(key,{})
	if entry.is_empty(): return null
	# Ingredient regions already contain the measured visible bounds of the artwork.
	return cell(str(entry.path),int(entry.index),6,5,false)

static var _recipe_icons: Dictionary = {}

static func _dish_key(id: String) -> String:
	if _recipe_icons.is_empty():
		var atlas: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/research/recipe_atlas.json"))
		for key: String in atlas.runtime_mapping:
			_recipe_icons[str(atlas.runtime_mapping[key])] = key
			_recipe_icons[str(atlas.charts[key].recipe_id)] = key
	var short_id := id.trim_prefix("study.").trim_prefix("service.").trim_prefix("lesson.").trim_prefix("recipe.").trim_prefix("phase3.")
	return _recipe_icons.get(id,_recipe_icons.get(short_id,short_id))

static func dish(id: String) -> Texture2D:
	var key := _dish_key(id)
	var entry: Dictionary = catalog().dishes.get(key,{})
	if entry.is_empty(): return null
	return cell(str(entry.path),int(entry.index),int(entry.get("columns",5)),int(entry.get("rows",4)),bool(entry.get("trim",false)))

static func cooking_food(id: String) -> Texture2D:
	var key := _dish_key(id)
	var entry: Dictionary = catalog().dishes.get(key,{})
	if entry.has("cooking_index"):
		return cell(str(entry.path),int(entry.cooking_index),int(entry.columns),int(entry.rows),bool(entry.trim))
	var ids: Array = catalog().dish_ids
	var slot := ids.find(key)
	if slot < 0:
		return null
	return cell("res://assets/kitchen/cooking-food.png",slot,8,8,false)

static func scrambled_egg() -> Texture2D:
	return cell("res://assets/kitchen/cooking-food.png",63,8,8,false)

# A finished, unrecognised dish still has cooked food and a plate. Pantry icons
# include their containers and only represent ingredients before cooking.
static func serving_art(empty_plate: bool = false) -> Texture2D:
	if not empty_plate: return cooking_food("C01")
	var key := "empty_plate"
	if not _cache.has(key):
		var texture := AtlasTexture.new()
		texture.atlas = preload("res://assets/kitchen/closeup-cookware-v2.png")
		texture.region = EMPTY_PLATE_REGION
		texture.filter_clip = true
		_cache[key] = texture
	return _cache[key]
