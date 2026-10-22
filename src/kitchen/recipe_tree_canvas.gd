class_name TDRecipeTreeCanvas
extends Control
signal selected(id: String)
var session: TDResearchSession
var cuisine: String="cn"
var selection: String="C02"
var query: String=""
var positions: Dictionary={}
var icons: Dictionary={}
var zoom: float=1.0
var _routes: Dictionary={}
const GOLD:=Color("d3b477")
const JADE:=Color("9cc5a0")
const TEXT:=Color("e4d9bc")
const ROW_HEIGHT:float=208.0

func rebuild() -> void:
	positions.clear()
	var rows:Dictionary={}; var assigned:Dictionary={}
	var remaining:Array=session.catalog.data.recipes.filter(func(r:Dictionary)->bool:return r.cuisine_id==cuisine)
	while not remaining.is_empty():
		var moved:bool=false
		for r:Dictionary in remaining.duplicate():
			var ready:bool=true; var row:int=int(r.tier)-1
			for p:String in r.prerequisites:
				if not assigned.has(p): ready=false; break
				row=maxi(row,int(assigned[p])+1)
			if not ready: continue
			while rows.get(row,[]).size()>=4: row+=1
			if not rows.has(row): rows[row]=[]
			rows[row].append(r.id); assigned[r.id]=row; remaining.erase(r); moved=true
		if not moved: break
	var last_row:int=0
	for row:int in rows:
		var ids:Array=rows[row]; last_row=maxi(last_row,row)
		for i:int in ids.size(): positions[ids[i]]=Vector2(360+(float(i)-(ids.size()-1)*.5)*168,88+row*ROW_HEIGHT)
	_build_routes(assigned)
	custom_minimum_size=Vector2(720,(last_row+1)*ROW_HEIGHT+90)*zoom
	size=custom_minimum_size; mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	queue_redraw()

func _draw() -> void:
	draw_set_transform(Vector2.ZERO,0,Vector2.ONE*zoom)
	draw_rect(Rect2(Vector2.ZERO,size/zoom),Color("19221c"))
	for y:int in range(0,int(size.y/zoom),20):
		for x:int in range(0,720,20): draw_circle(Vector2(x,y),.7,Color("2e3829"))
	var font:=ThemeDB.fallback_font
	draw_string(font,Vector2(248,32),"食 谱 研 习  ·  前 置 图 谱",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("99a08a"))
	# Draw focus last so inactive crossings cannot obscure the selected relation.
	for pass_index:int in 3:
		for id:String in positions:
			for p:String in session.catalog.node(id).prerequisites:
				var focused:bool=edge_selected(p,id)
				var active:bool=edge_active(p,id)
				var layer:int=2 if focused else (1 if active else 0)
				if layer!=pass_index: continue
				var path:=edge_path(p,id)
				var col:Color=GOLD if focused else (Color(JADE,.65) if active else Color("2e382e"))
				if focused: draw_polyline(path,Color("19221c"),8,true)
				draw_polyline(path,col,3 if focused else 1.4,true)
				if focused:
					draw_circle(path[0],3,GOLD)
					var tip:Vector2=path[-1]
					draw_colored_polygon(PackedVector2Array([tip,tip+Vector2(-4,-7),tip+Vector2(4,-7)]),GOLD)
	for id:String in positions:
		var row:=session.catalog.node(id); var point:Vector2=positions[id]; var state:=session.status(id)
		var known:bool=state=="UNLOCKED"; var ready:bool=state in ["AVAILABLE","RESEARCHABLE"]
		var color:Color=JADE if known else (GOLD if ready else Color("67745c"))
		var matches:bool=query.is_empty() or (row.name+row.ingredients+id).to_lower().contains(query.to_lower())
		var alpha:float=1.0 if matches else .22
		var prerequisite:bool=edge_selected(id,selection)
		var rect:=Rect2(point-Vector2(36,36),Vector2(72,72))
		draw_rect(Rect2(rect.position+Vector2(4,5),rect.size),Color("101712"))
		draw_rect(rect,Color("334b36") if known else Color("263027")); draw_rect(rect,Color(color,alpha),false,2)
		draw_rect(rect.grow(-5),Color(color,alpha*.45),false,1)
		if id==selection: draw_rect(rect.grow(5),GOLD,false,2)
		elif prerequisite: draw_rect(rect.grow(4),Color(GOLD,.75),false,1)
		if not icons.has(id): icons[id]=load("res://assets/kitchen/recipe-icons/%s.png"%id)
		if icons[id]!=null: draw_texture_rect(icons[id],Rect2(point-Vector2(27,22),Vector2(54,45)),false,Color(1,1,1,alpha if known or ready or id==selection or prerequisite else alpha*.5))
		var title:String=row.name
		draw_string(font,point+Vector2(-72,58),title,HORIZONTAL_ALIGNMENT_CENTER,144,15,Color(GOLD if prerequisite else color,alpha))
		var tag:String="已掌握" if known else ("可研习" if ready else ("待谱面" if state=="CHART_PENDING" else "未解锁"))
		draw_string(font,point+Vector2(-72,80),"%s · %s · %d SP"%[id,tag,int(row.cost)],HORIZONTAL_ALIGNMENT_CENTER,144,10,Color(color,alpha*.8))
	draw_set_transform(Vector2.ZERO)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
		var p:Vector2=event.position/zoom
		for id:String in positions:
			if card_bounds(id).has_point(p):
				selected.emit(id); accept_event(); return

func card_bounds(id:String) -> Rect2:
	return Rect2(positions[id]-Vector2(72,42),Vector2(144,128))

func edge_active(parent_id:String,child_id:String) -> bool:
	return parent_id in session.catalog.node(child_id).get("prerequisites",[]) and session.has(parent_id) and session.has(child_id)

func edge_selected(parent_id:String,child_id:String) -> bool:
	return child_id==selection and parent_id in session.catalog.node(child_id).get("prerequisites",[])

func edge_path(parent_id:String,child_id:String) -> PackedVector2Array:
	return _routes.get(parent_id+":"+child_id,PackedVector2Array()).duplicate()

func _build_routes(rows:Dictionary) -> void:
	_routes.clear()
	var outgoing:Dictionary={};var gaps:Dictionary={};var edges:Array[Dictionary]=[]
	for id:String in positions:
		for p:String in session.catalog.node(id).prerequisites:
			if not outgoing.has(p): outgoing[p]=[]
			outgoing[p].append(id)
			var key:String=p+":"+id
			var first:int=rows[p];var last:int=int(rows[id])-1
			edges.append({"parent":p,"child":id,"key":key,"first":first,"last":last})
			for gap:int in ([first] if first==last else [first,last]):
				if not gaps.has(gap): gaps[gap]=[]
				gaps[gap].append(key)
	var trunks:Array[Dictionary]=[]
	for edge:Dictionary in edges:
		var children:Array=outgoing[edge.parent]
		var parents:Array=session.catalog.node(edge.child).prerequisites
		var from:Vector2=positions[edge.parent]+Vector2((children.find(edge.child)-(children.size()-1)*.5)*7,89)
		var to:Vector2=positions[edge.child]+Vector2((parents.find(edge.parent)-(parents.size()-1)*.5)*10,-44)
		var start_y:float=_gap_y(edge.first,edge.key,gaps)
		var end_y:float=_gap_y(edge.last,edge.key,gaps)
		var path:PackedVector2Array
		if edge.first==edge.last:
			path=PackedVector2Array([from,Vector2(from.x,start_y),Vector2(to.x,start_y),to])
		else:
			var trunk_x:float=_choose_trunk(from.x,to.x,start_y,end_y,trunks)
			trunks.append({"x":trunk_x,"start":start_y,"end":end_y})
			path=PackedVector2Array([from,Vector2(from.x,start_y),Vector2(trunk_x,start_y),Vector2(trunk_x,end_y),Vector2(to.x,end_y),to])
		_routes[edge.key]=path

func _gap_y(row:int,key:String,gaps:Dictionary) -> float:
	var list:Array=gaps[row]
	# Allocate distinct tracks inside the 76px gap below labels and above cards.
	return 88+row*ROW_HEIGHT+98+float(list.find(key)+1)*54.0/float(list.size()+1)

func _choose_trunk(from_x:float,to_x:float,start_y:float,end_y:float,used:Array[Dictionary]) -> float:
	var best_x:float=20;var best_cost:float=INF
	for x:float in [20,32,44,183,192,201,351,360,369,519,528,537,676,688,700]:
		var blocked:bool=false
		for id:String in positions:
			var rect:=card_bounds(id).grow(3)
			if x>=rect.position.x and x<=rect.end.x and end_y>rect.position.y and start_y<rect.end.y:
				blocked=true;break
		if blocked: continue
		var cost:float=absf(x-from_x)+absf(x-to_x)
		for trunk:Dictionary in used:
			if absf(x-trunk.x)<7 and end_y>trunk.start and start_y<trunk.end: cost+=2000
		if cost<best_cost: best_cost=cost;best_x=x
	return best_x
