class_name TDRedrawArt
extends RefCounted
## Read-only versioned artwork. IDs and all simulation data remain authoritative elsewhere.
const INDEX: String="res://assets/redraw-v1/index.json"
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
	var key: String = {"焰子":"hero","阿铃":"aling","罗金娜":"chen","灰烬司祭":"chen","罗厄":"luo","维托":"vito","赫兹":"hertz"}.get(who,who)
	if key not in ["hero","aling","chen","luo","vito","hertz"]: return null
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

static func dish(id: String) -> Texture2D:
	var entry: Dictionary=catalog().dishes.get(id,{})
	if entry.is_empty(): return null
	return cell(str(entry.path),int(entry.index),5,4)
