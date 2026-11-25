extends SceneTree
## Check E-key shelves against the material manifest, including two-town shared stock.
var shell: TDGameShell
var out := "user://regional-counter-probe"
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, detail: String) -> bool:
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ")+detail)
	return ok

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): out=arg.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(out)
	var app:=load("res://src/app/main.tscn").instantiate() as TDApplication
	app.settings_path=out.path_join("session-%d/settings.json"%Time.get_ticks_usec())
	root.add_child(app)
	await process_frame
	shell=app.game_shell
	shell.automatic_time=false
	if not check(shell.create_game("slot-01","菜市验证").ok,"create isolated profile"):
		quit(1)
		return
	shell.guide.dialogue.finish_now()
	shell.profile.story.beat="done"
	shell.profile.shop.world_adjustment(500000,"funds","测试资金")
	shell.travel("town")
	var p := shell.profile
	var routes: Array=p.commerce.state.routes.duplicate()
	for town: String in ["chengdu","tokyo","paris"]:
		if shell.visiting==null: shell.town.spawn_at_harbor()
		else: shell.visiting.player.position=(Vector2(TDTravelCatalog.port(shell.visiting_town))+Vector2.ONE*.5)*shell.visiting.cell_size
		if town!="chengdu" and not check(shell.voyage(town).ok,"sail to "+town): continue
		var sites: Array = ["market-small","market-mid","market-large"] if town=="chengdu" else ["market-main","market-neighborhood"]
		for id: String in sites: await at_market(town,id)
		if town=="chengdu":
			for id: String in ["plaza","landmark","snack_street","hotel","competitor:shop:0"]:
				await inspect(id)
		else:
			for id: String in ["plaza","landmark","hotel","competitor:shop:0","workshops","commercial_street:bank"]:
				await inspect(id)
			if town=="tokyo": await inspect("onsen")
	check(p.commerce.state.routes==routes,"walk-in purchases do not unlock freight")
	check(p.research.recommend_cuisine("counter-eu","eu").ok and p.research.recommend_cuisine("counter-jp","jp").ok,"unlock condiment cuisines")
	for town: String in ["chengdu","paris","tokyo"]:
		var shelf:=p.shop.market_ids(town)
		check(("oliveoil" in shelf)==(town=="paris") and ("miso" in shelf)==(town=="tokyo") and "salt" in shelf,town+" unlocked spices still respect their sources")
		var item: String={"chengdu":"oliveoil","paris":"miso","tokyo":"oliveoil"}[town]
		var before:=p.snapshot()
		var rejected:=p.buy({"salt":1000,item:1000},"" if town=="chengdu" else town)
		check(not rejected.ok and before==p.snapshot(),town+" refuses foreign spice without a partial sale")
	print("REGIONAL COUNTERS ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

func face(id: String) -> bool:
	if shell.visiting!=null:
		for entry: Dictionary in shell.visiting._buildings:
			if entry.plot.get("id")!=id: continue
			var base: Rect2=entry.base
			for dx: float in [0.0,-.24,.24]:
				var point:=Vector2(base.get_center().x+base.size.x*dx,base.end.y+12)
				shell.visiting.player.position=point
				if shell.visiting._can_stand(point) and shell.visiting.nearby().get("id")==id: return true
		return false
	var t:=shell.town
	var plot:=t.session.town_map._by_id(id)
	if plot.is_empty(): return false
	var cell:=float(t.cell_size())
	var approach: Vector2 = t._origin()+(Vector2(plot.approach_x,plot.approach_y)+Vector2.ONE*.5)*cell
	var bounds:=TDInteractionRange.plot_bounds(plot,cell,t._origin()).grow(30)
	var positions: Array[Vector2]=[approach,bounds.get_center()]
	for y: int in range(ceili(bounds.position.y),ceili(bounds.end.y),12):
		for x: int in range(ceili(bounds.position.x),ceili(bounds.end.x),12):
			positions.append(Vector2(x,y))
	for point: Vector2 in positions:
		if not t._can_stand(point): continue
		t._player.position=point
		if t.facing_plot().get("id")==id: return true
	return false

func press_e() -> void:
	var key:=InputEventKey.new()
	key.keycode=KEY_E
	key.physical_keycode=KEY_E
	key.pressed=true
	root.push_input(key,true)
	key=key.duplicate()
	key.pressed=false
	root.push_input(key,true)
	await process_frame

func at_market(town: String,id: String) -> void:
	var p:=shell.profile
	if not check(face(id),town+" faces "+id): return
	await press_e()
	var rows: Dictionary={}
	if is_instance_valid(shell._modal):
		for icon: TDIngredientIcon in shell._modal_box.find_children("*","TDIngredientIcon",true,false):
			rows[icon.item_id]=icon.get_parent()
	var expected: Array=[]
	for item: String in p.service.config.costs:
		var row:=TDMaterialCatalog.item(item)
		if town not in row.get("supply_regions",[]): continue
		if row.has("unlock_cuisines") and "cn" not in row.unlock_cuisines: continue
		expected.append(item)
	check(rows.size()==expected.size() and expected.all(func(item): return rows.has(item)),town+" "+id+" every shelf item matches source and initial cuisine")
	check(rows.has("salt") and rows.has("tomato") and rows.has("pastry")==(town!="tokyo") and rows.has("char_siu")==(town!="paris"),town+" "+id+" shared materials")
	var local: String={"chengdu":"aspic","paris":"pasta","tokyo":"udon"}[town]
	if rows.has(local):
		var market: Dictionary=p.commerce.state.markets[town]
		var stock:=int(market.stock[local])
		var cash:=int(p.shop.snapshot().money_cents)
		var count:=p.shop.available(local)
		for buy: Button in rows[local].find_children("*","Button",true,false):
			if buy.text=="购买":
				buy.pressed.emit()
				break
		check(p.shop.available(local)==count+1000 and market.stock[local]==stock-1000 and p.shop.snapshot().money_cents==cash-int(market.price[local]),town+" "+id+" paid for "+local+" and received stock")
	shell._close_dialog()
	var blocked: String="udon" if town=="paris" else "pasta"
	var before:=p.snapshot()
	var result:=p.buy({"tomato":1000,blocked:1000},"" if town=="chengdu" else town)
	check(not result.ok and p.snapshot()==before,town+" blocks mixed cart atomically")

func inspect(id: String) -> void:
	if not face(id):
		print("VENUE ",shell.visiting_town," ",id," unavailable at tested frontage")
		return
	await press_e()
	var actions: Array[String]=[]
	var labels: Array[String]=[]
	if is_instance_valid(shell._modal):
		for label: Label in shell._modal_box.find_children("*","Label",true,false):
			labels.append(label.text)
		for node: Button in shell._modal_box.find_children("*","Button",true,false):
			if not node.text.is_empty(): actions.append(node.text)
	print("VENUE ",shell.visiting_town," ",id," ",JSON.stringify(actions)," ",JSON.stringify(labels).left(180))
	shell._close_dialog()
