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
		for i: int in _index.ingredient_ids.size(): _index.ingredients[_index.ingredient_ids[i]]={"path":"res://assets/redraw-v1/ingredients-%d.png"%(i/30),"index":i%30}
		for i: int in _index.dish_ids.size(): _index.dishes[_index.dish_ids[i]]={"path":"res://assets/redraw-v1/dishes-%d.png"%(i/20),"index":i%20}
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

static func portrait(who: String,emotion: String="") -> Texture2D:
	var key: String={"焰子":"hero","阿铃":"aling","灰烬司祭":"chen","罗厄":"luo"}.get(who,who)
	if not catalog().portraits.has(key): return null
	var index: int=maxi(0,EMOTIONS.find(emotion))
	var path: String=catalog().portraits[key]
	var cache_key: String="portrait:"+key+":"+str(index)
	if not _cache.has(cache_key):
		var source:=image(path)
		var dimensions:=Vector2i(source.get_width()/3,source.get_height()/2)
		# Preserve the complete original composition and decorative background.
		var bounds:=Rect2i(Vector2i.ZERO,dimensions)
		for i: int in 6:
			var result:=AtlasTexture.new();result.atlas=load(path)
			result.region=Rect2(Vector2i(i%3,i/3)*dimensions+bounds.position,bounds.size)
			result.filter_clip=true;_cache["portrait:"+key+":"+str(i)]=result
	return _cache[cache_key]

static func ingredient(id: String) -> Texture2D:
	var key: String=id if catalog().ingredients.has(id) else {"peanut_oil":"oil","peppercorn":"pepper","cooking_wine":"wine","shanxi_vinegar":"vinegar"}.get(id,id)
	var entry: Dictionary=catalog().ingredients.get(key,{})
	if entry.is_empty(): return null
	return cell(str(entry.path),int(entry.index),6,5)

static func dish(id: String) -> Texture2D:
	var entry: Dictionary=catalog().dishes.get(id,{})
	if entry.is_empty(): return null
	return cell(str(entry.path),int(entry.index),5,4)
