class_name TDChefArt
extends RefCounted
## Original code-drawn pixel chef. All four poses share the same foot origin.
static var _textures: Dictionary={}

static func texture(facing: Vector2i) -> Texture2D:
	if _textures.has(facing): return _textures[facing]
	var img:=Image.create(32,40,false,Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var side: bool=facing.x!=0
	var back: bool=facing==Vector2i.UP
	box(img,9,30,6,8,"34444a");box(img,18,30,6,8,"34444a")
	box(img,8,37,7,3,"252b30");box(img,18,37,7,3,"252b30")
	box(img,6,18,21,14,"d9dccc");box(img,9,18,15,15,"eee9ce")
	box(img,4,21,4,10,"e8b48a");box(img,25,21,4,10,"e8b48a")
	box(img,10,20,12,11,"a84e3b" if back else "c7714d")
	if not back: box(img,12,23,8,9,"eee9ce");box(img,11,19,10,3,"ab4938")
	box(img,9,8,15,11,"e5b18a");box(img,8,8,17,4,"4a342d")
	box(img,9,2,15,7,"eeeeda");box(img,6,4,21,6,"f4f0d7");box(img,8,10,17,3,"c3ccbc")
	if back:
		box(img,9,13,15,5,"513b32")
	elif side:
		var eye_x:=22 if facing.x>0 else 10
		box(img,eye_x,14,2,2,"2c302d");box(img,24 if facing.x>0 else 7,15,3,3,"edbf94")
	else:
		box(img,11,14,2,2,"2c302d");box(img,20,14,2,2,"2c302d");box(img,15,17,4,1,"925f47")
	var result:=ImageTexture.create_from_image(img);_textures[facing]=result
	return result

static func box(img: Image,x:int,y:int,w:int,h:int,color:String) -> void:
	img.fill_rect(Rect2i(x,y,w,h),Color(color))
