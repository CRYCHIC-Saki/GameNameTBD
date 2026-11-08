class_name TDBranchPanel
extends VBoxContainer
## Thin intent UI; geometry and all transactions remain in TDPlayerBranches.
var profile: TDGameProfile
var selected_id: String=""
var selected_town: String="chengdu"
var selected_cuisine: String="cn"
var selected_manager: String=""
var selected_rect: Array=[]
var map_view: SiteMap
var quote_label: Label
var status_label: Label
var manager_box: VBoxContainer
var create_button: Button
var site_button: Button
var _site_done: bool=false
var _site_controls: Array[Control]=[]
var _serial: int=0

func configure(value: TDGameProfile) -> void:
	profile=value; selected_town=str(profile.commerce.state.home)
	list_stores()

func _clear() -> void:
	for child: Node in get_children(): remove_child(child); child.queue_free()

func _notice(text: String) -> void:
	if is_instance_valid(status_label): status_label.text=text; status_label.visible=not text.is_empty()

func list_stores() -> void:
	_clear(); map_view=null
	add_child(TDUI.label("分店账簿",26,TDUI.ORANGE))
	add_child(TDUI.label("店长带队经营 · 与主店共享资金及本镇客源 · 独立菜单和原料\n新店明日开始营业；睡觉或主动保存才保留本次修改。",17,TDUI.MUTED))
	status_label=TDUI.label(str(profile.branches.state.legacy.get("migration_notice","")),17,TDUI.ORANGE); add_child(status_label)
	if profile.at_boundary(): add_child(TDUI.button("筹建新分店",begin_site))
	if profile.branches.state.stores.is_empty(): add_child(TDUI.label("还没有分店。筹建时先选菜系与地块，再聘请店长。",20))
	for store: Dictionary in profile.branches.state.stores.values():
		var box:=VBoxContainer.new(); add_child(box)
		var m:=profile.branches.manager(store.manager_id)
		box.add_child(TDUI.label("%s  %s\n%s · %d×%d格 · 接待容量%d人/日"%[store.name,"★".repeat(int(m.stars)),profile.commerce.config.towns[store.town_id].name,int(store.rect[2]),int(store.rect[3]),store.capacity],21))
		box.add_child(TDUI.label("%s · 房租 ¥%.2f/日 · 店长 ¥%.2f/日 · 班组 ¥%.2f/营业日\n采购预算 ¥%.2f/日 · 欠费 ¥%.2f · %s"%[m.name,float(store.rent_cents)/100,float(m.wage_cents)/100,float(store.crew_cents)/100,float(store.budget_cents)/100,float(TDPlayerBranches.debt_total(store))/100,"暂停" if store.paused else ("明日开业" if int(store.start_day)>int(profile.shop.snapshot().day) else "托管营业")],17))
		if not store.books.is_empty(): box.add_child(TDUI.label(report_text(store.books.back()),17,TDUI.MUTED))
		box.add_child(TDUI.button("菜单、预算与账目",manage.bind(str(store.id))))

func begin_site() -> void:
	_clear(); selected_manager=""; selected_rect=[]; _site_done=false; _site_controls=[]
	add_child(TDUI.label("① 菜系与地块 → ② 聘请店长 → ③ 确认开办",22,TDUI.ORANGE))
	var selectors:=HBoxContainer.new(); add_child(selectors)
	_site_controls.append(selectors)
	var cuisine_label:=TDUI.label("餐馆类型",18);cuisine_label.autowrap_mode=TextServer.AUTOWRAP_OFF
	selectors.add_child(cuisine_label)
	var cuisines:=OptionButton.new(); cuisines.custom_minimum_size=Vector2(210,44); selectors.add_child(cuisines)
	var cuisine_ids: Array=[]
	for id: String in TDPlayerBranches.CULTURES:
		if id not in profile.research.snapshot().cuisines or profile.branches.recipes(id).is_empty(): continue
		cuisine_ids.append(id); cuisines.add_item(str(TDPlayerBranches.TITLES[id]))
	selected_cuisine=str(cuisine_ids[0]); cuisines.item_selected.connect(func(index:int)->void:selected_cuisine=str(cuisine_ids[index]); _update_quote())
	var site_help:=TDUI.label("五镇均可开店，进口商路另行开放。每边3–12格、最多108格，须临路且不占已有用地。",16,TDUI.MUTED)
	add_child(site_help); _site_controls.append(site_help)
	var navigation:=HBoxContainer.new(); add_child(navigation); _site_controls.append(navigation)
	map_view=SiteMap.new(); map_view.configure(profile)
	map_view.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	navigation.add_child(TDUI.button("世界全览",map_view.reset_view))
	for id: String in TDTravelCatalog.IDS:
		navigation.add_child(TDUI.button(str(TDTravelCatalog.info(id).name),map_view.choose_town.bind(id)))
	add_child(map_view)
	map_view.town_selected.connect(func(id:String)->void:selected_town=id; selected_rect=[]; selected_manager=""; _update_quote())
	map_view.picked.connect(func(rect:Array)->void:selected_rect=rect; _update_quote())
	quote_label=TDUI.label("拖出范围查看报价。",18,TDUI.ORANGE); quote_label.custom_minimum_size.y=50; add_child(quote_label)
	var footer:=HBoxContainer.new();add_child(footer)
	site_button=TDUI.button("下一步：选择店长",_toggle_site); site_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL; footer.add_child(site_button)
	footer.add_child(TDUI.button("取消筹建",list_stores))
	manager_box=VBoxContainer.new(); add_child(manager_box)
	status_label=TDUI.label("",17,TDUI.ORANGE); status_label.hide(); add_child(status_label)
	create_button=TDUI.button("确认开办（明日营业）",confirm); create_button.disabled=true; add_child(create_button)
	selected_town=""; _update_quote()

func _update_quote() -> void:
	var result:=profile.branches.quote(selected_town,selected_rect,selected_cuisine,selected_manager)
	site_button.disabled=not result.ok
	site_button.text="返回调整位置" if _site_done else "下一步：选择店长"
	manager_box.visible=_site_done
	create_button.visible=_site_done
	for item: Control in _site_controls: item.visible=not _site_done
	create_button.disabled=not result.ok or selected_manager.is_empty()
	map_view.valid=result.ok; map_view.queue_redraw()
	for child: Node in manager_box.get_children(): manager_box.remove_child(child); child.queue_free()
	if not result.ok:
		quote_label.text="先在世界地图点选小镇，再拖出餐馆范围。" if selected_town.is_empty() else (TDTravelCatalog.info(selected_town).name+" · "+(result.message if result.message!="" else "先拖出合法矩形范围。"))
		return
	var q:=result.data
	quote_label.text=TDTravelCatalog.info(selected_town).name+" · "+"占地%d×%d格 · 开办费 ¥%.2f（一次性） · 房租 ¥%.2f/日\n班组 ¥%.2f/营业日 · 容量%d人/日 · 水电按实际接待与出餐计费"%[int(selected_rect[2]),int(selected_rect[3]),float(q.opening_cents)/100,float(q.rent_cents)/100,float(q.crew_cents)/100,int(q.capacity)]
	manager_box.add_child(TDUI.label("② 选择驻店店长",21))
	var cards:=HBoxContainer.new(); manager_box.add_child(cards)
	for m: Dictionary in profile.branches.config.managers:
		var card:=VBoxContainer.new(); card.size_flags_horizontal=Control.SIZE_EXPAND_FILL; cards.add_child(card)
		card.add_child(TDUI.label("★".repeat(int(m.stars))+"\n"+str(m.name),19,TDUI.ORANGE))
		for stat: String in ["attraction","operations","quality","economy"]:
			card.add_child(TDUI.label("%s  %d / 100"%[{"attraction":"招徕","operations":"运营","quality":"品控","economy":"节约"}[stat],m[stat]],16))
		var detail:=TDUI.label("日薪 ¥%.2f\n%s"%[float(m.wage_cents)/100,m.special],16,TDUI.MUTED)
		detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		card.add_child(detail)
		card.add_child(TDUI.button("已选择" if selected_manager==m.id else "聘请此店长",_choose_manager.bind(str(m.id))))

func _toggle_site() -> void:
	_site_done=not _site_done; map_view.visible=not _site_done; _update_quote()
	var container:=get_parent().get_parent() as ScrollContainer
	if container!=null: container.set_deferred("scroll_vertical",0)

func _choose_manager(id: String) -> void:
	selected_manager=id; _update_quote()

func confirm() -> void:
	_serial+=1
	var token: String="branch:open:%s:%d"%[profile.shop.snapshot().run_id,int(profile.shop.snapshot().serial)+1]
	var result:=profile.branches.open_store(selected_town,selected_rect,selected_cuisine,selected_manager,token)
	if result.ok: list_stores()
	_notice(result.message if result.message!="" else result.code)

func manage(id: String) -> void:
	selected_id=id; _clear(); map_view=null
	var s: Dictionary=profile.branches.state.stores[id]
	add_child(TDUI.label(s.name,25,TDUI.ORANGE))
	var m:=profile.branches.manager(s.manager_id)
	add_child(TDUI.label("%s · %s\n招徕影响发现率，运营影响容量/服务，品控影响菜品质量，节约减少真实损耗。"%[m.name,m.special],17,TDUI.MUTED))
	var rows: Dictionary={}
	for dish: Dictionary in profile.branches.recipes(s.cuisine_id):
		var row:=HBoxContainer.new(); add_child(row)
		var check:=CheckBox.new(); check.text=dish.name; check.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(check)
		var current: Array=s.menu.filter(func(d:Dictionary)->bool:return d.id==dish.id)
		check.button_pressed=not current.is_empty()
		var price:=SpinBox.new(); price.min_value=.01; price.max_value=10000; price.step=.5; price.prefix="¥ "; price.value=float(current[0].price_cents if not current.is_empty() else dish.price_cents)/100; price.custom_minimum_size=Vector2(160,42); row.add_child(price)
		check.disabled=not profile.at_boundary(); price.editable=profile.at_boundary()
		rows[dish.id]={"check":check,"price":price}
	add_child(TDUI.label("每日采购预算（不会超过可用现金；采购换成库存，利润按实际耗料算）",17))
	var budget:=SpinBox.new(); budget.min_value=0; budget.max_value=100000; budget.step=10; budget.prefix="¥ "; budget.value=float(s.budget_cents)/100; budget.editable=profile.at_boundary(); add_child(budget)
	var paused:=CheckBox.new(); paused.text="暂停营业（仍支付房租和店长工资）"; paused.button_pressed=s.paused; paused.disabled=not profile.at_boundary(); add_child(paused)
	status_label=TDUI.label("",17,TDUI.ORANGE); add_child(status_label)
	if profile.at_boundary():
		add_child(TDUI.button("应用菜单与预算",func()->void:
			var chosen: Array=[]
			for key: String in rows:
				if rows[key].check.button_pressed: chosen.append({"id":key,"price_cents":roundi(rows[key].price.value*100)})
			var result:=profile.branches.configure_store(id,chosen,roundi(budget.value*100),paused.button_pressed)
			_notice(result.message if result.message!="" else result.code)))
	add_child(TDUI.label("库存（与主店独立，保质期照常流逝）",20))
	var stock: Array[String]=[]
	for item: String in s.inventory:
		if int(s.inventory[item])<=0: continue
		var food:=profile._factory_item(item)
		stock.append("%s %.2f · 第%d天到期"%[food.get("name",item),float(s.inventory[item])/1000,TDFoodStock.first_expiry(s.lots,item)])
	add_child(TDUI.label("\n".join(stock) if not stock.is_empty() else "尚无原料；营业时按预算从当地市场备货。",17))
	add_child(TDUI.label("最近日账",20))
	for book: Dictionary in s.books.slice(maxi(0,s.books.size()-7)): add_child(TDUI.label(report_text(book),17,TDUI.MUTED))
	add_child(TDUI.label("欠费 ¥%.2f"%(float(TDPlayerBranches.debt_total(s))/100),19,TDUI.ORANGE))
	add_child(TDUI.button("返回分店账簿",list_stores))

static func report_text(d: Dictionary) -> String:
	return "第%d天 · 接待%d人 · 销售 ¥%.2f · 净利润 %+.2f元\n采购 %.2f / 耗料 %.2f / 过期 %.2f / 店长 %.2f / 班组 %.2f / 租金 %.2f / 水电 %.2f / 税 %.2f\n%s"%[int(d.day),int(d.served),float(d.sales_cents)/100,float(d.profit_cents)/100,float(d.purchase_cents)/100,float(d.consumed_cents)/100,float(d.spoilage_cents)/100,float(d.manager_cents)/100,float(d.crew_cents)/100,float(d.rent_cents)/100,float(d.utilities_cents)/100,float(d.tax_cents)/100,str(d.reason)]

class SiteMap extends TDTravelMapView:
	## Same atlas as M. Only local view state; TDPlayerBranches owns all land/cash rules.
	signal town_selected(id: String)
	signal picked(rect: Array)
	var selected_town: String=""
	var selection:=Rect2i()
	var valid: bool=false
	var _start:=Vector2i.ZERO
	var _site_drag: bool=false
	var _preview:=Rect2i()
	var _land: ImageTexture
	var _occupied: Dictionary={}

	func _init() -> void:
		minimum_view_size=Vector2(1080,350);max_zoom=12;show_player=false
		heading="分店选址 · 世界全览";controls_hint="点击小镇放大 · 滚轮缩放 · 中键拖动地图"

	func _ready() -> void:
		super._ready()
		resized.connect(_cancel_drag)
		visibility_changed.connect(_cancel_drag)

	func _notification(what: int) -> void:
		super._notification(what)
		if what==NOTIFICATION_WM_WINDOW_FOCUS_OUT: _cancel_drag()

	func _cancel_drag() -> void:
		_site_drag=false;_dragging=false;_preview=Rect2i();queue_redraw()

	func reset_view() -> void:
		_cancel_drag();selected_town="";selection=Rect2i();valid=false
		heading="分店选址 · 世界全览";controls_hint="点击小镇放大 · 滚轮缩放 · 中键拖动地图"
		super.reset_view();town_selected.emit("")

	func choose_town(id: String) -> void:
		if not maps.has(id): return
		_cancel_drag();selected_town=id;selection=Rect2i();valid=false
		zoom=5;pan=-(ORIGINS[id]+Vector2.ONE*TOWN_SIZE*.5-WORLD_SIZE*.5)*scale_factor()
		_limit_pan();_build_land()
		heading="分店选址 · "+str(TDTravelCatalog.info(id).name)
		controls_hint="左键拖出范围 · 中键拖动 / 滚轮缩放 · 浅绿可建 / 深色已占 / 蓝色水域"
		town_selected.emit(id);queue_redraw()

	func _town_at(point: Vector2) -> String:
		if not Rect2(Vector2(0,68),Vector2(size.x,size.y-104)).has_point(point): return ""
		for id: String in maps:
			if Rect2(ORIGINS[id],Vector2.ONE*TOWN_SIZE).has_point(screen_to_world(point)): return id
		return ""

	func _cell(point: Vector2) -> Vector2i:
		if selected_town.is_empty() or _town_at(point)!=selected_town: return Vector2i(-1,-1)
		return Vector2i(((screen_to_world(point)-ORIGINS[selected_town])*float(maps[selected_town].extent)/TOWN_SIZE).floor())

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
				_cancel_drag();zoom_at(event.position,1.22 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.0/1.22);accept_event()
			elif event.button_index==MOUSE_BUTTON_MIDDLE:
				_cancel_drag();_dragging=event.pressed;accept_event()
			elif event.button_index==MOUSE_BUTTON_LEFT:
				if event.pressed:
					var id:=_town_at(event.position)
					if id.is_empty(): _cancel_drag();return
					if selected_town!=id or zoom<4:
						choose_town(id);accept_event();return
					_start=_cell(event.position);_site_drag=true;_preview=Rect2i(_start,Vector2i.ONE)
				elif _site_drag:
					var cell:=_cell(event.position)
					if cell.x>=0:
						_preview_to(cell);selection=_preview;valid=false
						picked.emit([selection.position.x,selection.position.y,selection.size.x,selection.size.y])
					_cancel_drag()
				queue_redraw();accept_event()
		elif event is InputEventMouseMotion:
			if _dragging: pan+=event.relative;_limit_pan()
			if _site_drag:
				var cell:=_cell(event.position)
				if cell.x<0: _cancel_drag()
				else: _preview_to(cell)
			_hover=_town_at(event.position);queue_redraw();accept_event()

	func _preview_to(cell: Vector2i) -> void:
		var origin:=Vector2i(mini(cell.x,_start.x),mini(cell.y,_start.y))
		_preview=Rect2i(origin,Vector2i(absi(cell.x-_start.x)+1,absi(cell.y-_start.y)+1))

	func caption_text() -> String:
		if selected_town.is_empty(): return "五镇均可选址 · 开店与进口商路独立 · 道路、住房和既有建筑不可占用"
		return str(TDTravelCatalog.info(selected_town).caption)

	func _build_land() -> void:
		var map: TDTownMap=maps[selected_town]
		var image:=Image.create(map.extent*6,map.extent*6,false,Image.FORMAT_RGBA8)
		_occupied.clear()
		for plot: Dictionary in map.plots:
			for y: int in range(int(plot.y),int(plot.y+plot.h)):
				for x: int in range(int(plot.x),int(plot.x+plot.w)): _occupied[Vector2i(x,y)]=true
		for y: int in map.extent:
			for x: int in map.extent:
				var at:=Vector2i(x,y);var terrain:=map.terrain_at(at)
				var color:=Color("93b28b") if terrain.buildable else Color("4d755b")
				if terrain.terrain_type=="water": color=Color("327e95")
				elif _occupied.has(at): color=Color("635a4c")
				elif map.is_road(x,y): color=Color("cec2a3")
				elif terrain.surface_type=="sand": color=Color("bcb384")
				image.fill_rect(Rect2i(x*6,y*6,6,6),color)
				image.fill_rect(Rect2i(x*6,y*6+5,6,1),color.darkened(.13))
				image.fill_rect(Rect2i(x*6+5,y*6,1,6),color.darkened(.13))
		_land=ImageTexture.create_from_image(image)

	func _draw_land_overlay() -> void:
		if selected_town.is_empty() or _land==null or zoom<4: return
		var origin: Vector2=ORIGINS[selected_town]
		var area:=Rect2(world_to_screen(origin),Vector2.ONE*TOWN_SIZE*scale_factor())
		draw_texture_rect(_land,area,false)
		# Actual footprints remain visible; illustrative building roofs never hide selectable cells.
		var map: TDTownMap=maps[selected_town]
		var unit: float=TOWN_SIZE/float(map.extent)*scale_factor()
		for plot: Dictionary in map.plots:
			var rect:=Rect2(cell_to_screen(selected_town,Vector2(plot.x,plot.y)),Vector2(plot.w,plot.h)*unit)
			if not Rect2(Vector2.ZERO,size).intersects(rect): continue
			var color:=Color("e8b85d") if plot.has("branch_id") else Color("9b8971")
			draw_rect(rect,color,false,2)
			if rect.size.x>35: _text(rect.position+Vector2(3,15),TDTravelCatalog.label(plot,selected_town),12,color)
		var chosen: Rect2i=_preview if _site_drag else selection
		if chosen.has_area():
			var rect:=Rect2(cell_to_screen(selected_town,Vector2(chosen.position)),Vector2(chosen.size)*unit)
			var color:=Color("f5d58a") if _site_drag else (Color("b6ff9f") if valid else Color("ff7a60"))
			draw_rect(rect,Color(color,.3));draw_rect(rect,color,false,2)
			_text(rect.position+Vector2(0,-6),"%d × %d格"%[chosen.size.x,chosen.size.y],16,color)
