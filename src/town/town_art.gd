class_name TDTownArt
extends RefCounted
const SPRITES := preload("res://assets/town/town-sprites-v1.png")

static func sprite(index: int) -> AtlasTexture:
	var tile:=AtlasTexture.new();tile.atlas=SPRITES
	var side:float=SPRITES.get_width()/2.0
	tile.region=Rect2(Vector2(index%2,index/2)*side,Vector2.ONE*side)
	return tile

static func draw_world(canvas: Node2D, session: TDPhase3Session, selected: Dictionary) -> void:
	var origin:=Vector2(300,24);var cell:float=TDTownWorld.CELL
	var housing:Dictionary={};var drawn_houses:Dictionary={}
	var home_rect:=Rect2i()
	if not session.town_map.cottage.is_empty():
		var home:Dictionary=session.town_map.cottage;home_rect=Rect2i(home.x,home.y,home.w,home.h)
	for plot:Dictionary in session.town_map.plots:
		if plot.kind=="housing" and not home_rect.has_point(Vector2i(plot.x,plot.y)): housing[Vector2i(plot.x,plot.y)]=true
	canvas.draw_rect(Rect2(origin,Vector2.ONE*TDTownMap.SIZE*cell),Color("526f50"))
	for y: int in TDTownMap.SIZE:
		for x: int in TDTownMap.SIZE:
			var area:=Rect2(origin+Vector2(x,y)*cell,Vector2.ONE*cell)
			if session.town_map.is_road(x,y):
				canvas.draw_rect(area,Color("b5a78a"))
				for row: int in 4:
					canvas.draw_line(area.position+Vector2(0,row*12),area.position+Vector2(cell,row*12),Color("a2977c"),1)
				canvas.draw_line(area.position+Vector2(24 if y%2==0 else 12,0),area.position+Vector2(24 if y%2==0 else 12,cell),Color("a2977c"),1)
			elif (x*7+y*11)%9==0:
				canvas.draw_rect(Rect2(area.position+Vector2(8,20),Vector2(7,3)),Color("6e874e"))
	for plot: Dictionary in session.town_map.plots:
		var rect:=Rect2(origin+Vector2(plot.x,plot.y)*cell,Vector2(plot.w,plot.h)*cell)
		var kind:=str(plot.kind)
		if kind=="housing" and home_rect.has_point(Vector2i(plot.x,plot.y)): continue
		if kind=="diner_lot":
			canvas.draw_rect(rect,Color("8b8661"))
			continue
		if kind in ["factory_lot","supply_factory"]:
			var built: bool = kind=="supply_factory"
			var fill: Color = TDTownMap.supply_color(str(plot.get("supply","")), built)
			canvas.draw_rect(rect.grow(-2), fill)
			canvas.draw_rect(rect.grow(-4), fill.lightened(0.18 if built else 0.08), false, 2)
			if built:
				canvas.draw_rect(Rect2(rect.position+Vector2(6,6), Vector2(rect.size.x-12, 14)), fill.darkened(0.25))
				canvas.draw_rect(Rect2(rect.position+Vector2(rect.size.x-22, -8), Vector2(10, 22)), Color("4a3a32"))
				canvas.draw_rect(Rect2(rect.position+Vector2(rect.size.x-24, -12), Vector2(14, 6)), Color("3a2c26"))
		elif kind=="housing" or kind=="competitor":
			if kind=="housing":
				var block:=Vector2i(plot.x,plot.y)
				if drawn_houses.has(block): continue
				var span:int=1
				for size:int in [3,2]:
					var fits:bool=true
					for dy:int in size:
						for dx:int in size:
							var point:=block+Vector2i(dx,dy)
							if not housing.has(point) or drawn_houses.has(point): fits=false
					if fits: span=size;break
				for dy:int in span:
					for dx:int in span: drawn_houses[block+Vector2i(dx,dy)]=true
				if span==1:
					# Narrow leftover lots are courtyard walls/planting, not miniature houses.
					canvas.draw_rect(rect.grow(-3),Color("777b59"))
					canvas.draw_rect(Rect2(rect.position+Vector2(3,3),Vector2(cell-6,9)),Color("6b6f64"))
					if (block.x+block.y)%3==0: canvas.draw_texture_rect(sprite(3),rect.grow(2),false)
					continue
				canvas.draw_rect(Rect2(origin+Vector2(block)*cell,Vector2.ONE*cell*span).grow(-2),Color("92916f"))
				var house_size:float=cell*2.6 if span==3 else cell*2
				rect=Rect2(origin+Vector2(block)*cell+Vector2.ONE*(cell*span-house_size)*.5,Vector2.ONE*house_size)
			canvas.draw_texture_rect(sprite(1),rect.grow(3),false)
		elif kind=="player_cottage":
			canvas.draw_rect(rect,Color("8c8364"));canvas.draw_texture_rect(sprite(1),rect,false)
		elif kind=="player_diner":
			canvas.draw_rect(rect,Color("ac9973"))
			canvas.draw_texture_rect(sprite(0),rect,false)
		elif kind=="market":
			canvas.draw_rect(rect,Color("c5b18c"))
			canvas.draw_texture_rect(sprite(2),rect,false)
		else:
			canvas.draw_rect(rect.grow(-4),Color("82906a"))
			for row: int in range(0,int(plot.h),3):
				for column: int in range(0,int(plot.w),3):
					canvas.draw_texture_rect(sprite(3),Rect2(rect.position+Vector2(column,row)*cell,Vector2.ONE*minf(3*cell,rect.size.x)),false)
		if kind!="housing":
			var font:=ThemeDB.fallback_font
			var label: String="小镇食堂" if plot.id=="player_diner" else str(plot.name)
			var panel:=Rect2(rect.position+Vector2(3,rect.size.y-24),Vector2(maxf(80,rect.size.x-6),23))
			canvas.draw_rect(panel,Color("342b25"))
			canvas.draw_string(font,panel.position+Vector2(5,17),label,HORIZONTAL_ALIGNMENT_CENTER,panel.size.x-10,14,Color("f0dbab"))
		if str(plot.id)==str(selected.get("id","")): canvas.draw_rect(rect,Color("e8bd6f"),false,2)
