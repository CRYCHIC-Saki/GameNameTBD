extends SceneTree
## Follow actual E interactions in the European town, including the resulting money and stock.
var shell: TDGameShell
var output := ""
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
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	if output.is_empty(): output = "user://egret-services"
	DirAccess.make_dir_recursive_absolute(output)
	var app := load("res://src/app/main.tscn").instantiate() as TDApplication
	app.settings_path = output.path_join("session-%s/settings.json" % Time.get_ticks_usec())
	root.add_child(app)
	await process_frame
	shell = app.game_shell
	shell.automatic_time = false
	if not check(shell.create_game("slot-01","白鹭河柜台测试").ok,"create isolated profile"):
		quit(1)
		return
	shell.guide.dialogue.finish_now()
	shell.profile.story.beat = "done"
	var p := shell.profile
	p.shop.world_adjustment(400000,"fixture-funds","测试资金")
	var opened := p.branches.open_store("paris",[43,46,5,4],"cn","","egret-service-fixture")
	var branch_id := str(opened.data.get("store_id",""))
	check(opened.ok,"buy actual frontage for the branch visit")
	check(p.shop.close_for_night().ok and p.next_day().ok,"finish branch construction")
	shell.travel("town")
	shell.town.spawn_at_harbor()
	check(shell.voyage("paris").ok,"arrive at European port")
	if shell.visiting == null:
		quit(1)
		return
	var routes: Array = p.commerce.state.routes.duplicate()
	await purchase("market-main","pasta")
	await purchase("market-neighborhood","tomato")
	await bank()
	if opened.ok and await approach(branch_id):
		var previous := shell.visiting.player.position
		await press_e()
		check(shell.location=="branch" and shell.branch_visit!=null and shell.branch_visit.store_id==branch_id, "E enters this funded European branch")
		if shell.branch_visit!=null:
			shell.exit_branch()
			check(shell.location=="voyage" and shell.visiting.player.position.is_equal_approx(previous),"return to the same storefront")
	if await approach("harbor"):
		await press_e()
		var sail := button("前往 "+str(TDTravelCatalog.info("tokyo").name))
		if check(sail!=null,"ticket counter offers Shiomi"):
			await capture("客运站")
			sail.pressed.emit()
			check(shell.visiting_town=="tokyo" and shell.visiting.nearby().get("kind")=="harbor","arrive on Shiomi passenger landing")
			await press_e()
			sail = button("前往 "+str(TDTravelCatalog.info("paris").name))
			if check(sail!=null,"return ticket available"):
				sail.pressed.emit()
				check(shell.visiting_town=="paris" and shell.visiting.nearby().get("kind")=="harbor","return on European passenger landing")
				await press_e()
				sail = button("前往 "+str(TDTravelCatalog.info("chengdu").name))
				if check(sail!=null,"return ticket to Jiangnan available"):
					sail.pressed.emit()
					check(shell.visiting_town=="chengdu" and shell.visiting==null and shell.location=="town","European ship returns to Jiangnan")
	check(p.commerce.state.routes==routes,"counter purchases and travel preserve freight unlocks")
	var restored := TDGameProfile.new()
	var result := restored.restore(p.snapshot())
	check(result.ok and restored.commerce.society.bank.account("player")==p.commerce.society.bank.account("player") and restored.shop.available("pasta")==p.shop.available("pasta"),"stock and bank balance survive profile round-trip")
	restored.close()
	shell._close_dialog()
	print("EGRET SERVICES ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

func approach(id: String) -> bool:
	var visit := shell.visiting
	var counter: Rect2
	for entry: Dictionary in visit._buildings:
		if entry.plot.id==id:
			counter=entry.base
			break
	if not check(counter.has_area(),id+" has a counter"): return false
	var doorstep := Vector2(counter.get_center().x,counter.end.y+12)
	var start := doorstep+Vector2.DOWN*43
	if not check(visit._can_stand(start),id+" has a clear approach"): return false
	visit.player.position=start
	Input.action_press("world_up")
	for tick: int in 45:
		if visit.player.position.y<=doorstep.y+2: break
		await physics_frame
	Input.action_release("world_up")
	await process_frame
	if not check(visit._can_stand(visit.player.position) and start.distance_to(visit.player.position)>15 and visit.nearby().get("id")==id,id+" reached using movement input"): return false
	check(visit._building_nameplate.visible and visit._target.id == id, id + " uses a nameplate above the facade")
	return true

func press_e() -> void:
	var press := InputEventKey.new()
	press.physical_keycode=KEY_E
	press.keycode=KEY_E
	press.pressed=true
	root.push_input(press,true)
	press=press.duplicate()
	press.pressed=false
	root.push_input(press,true)
	await process_frame

func button(caption: String) -> Button:
	if not is_instance_valid(shell._modal): return null
	for node: Node in shell._modal_box.find_children("*","Button",true,false):
		if node is Button and node.text==caption: return node
	return null

func purchase(id: String, item: String) -> void:
	if not await approach(id): return
	await press_e()
	var p := shell.profile
	var rows := {}
	if is_instance_valid(shell._modal):
		for icon: TDIngredientIcon in shell._modal_box.find_children("*","TDIngredientIcon",true,false):
			rows[icon.item_id]=icon.get_parent()
	if check(rows.has(item) and rows.size()==p.shop.market_ids("paris").size() and not rows.has("udon"),id+" opens European ingredient shelves"):
		var market: Dictionary=p.commerce.state.markets.paris
		var price := int(market.price[item])
		var cash := int(p.shop.snapshot().money_cents)
		var stock := int(market.stock[item])
		var home_stock := int(p.commerce.state.markets.chengdu.stock[item])
		var inventory := p.shop.available(item)
		var shipments: int = p.commerce.state.shipments.size()
		for buy: Button in rows[item].find_children("*","Button",true,false):
			if buy.text=="购买":
				buy.pressed.emit()
				break
		check(p.shop.available(item)==inventory+1000 and p.shop.snapshot().money_cents==cash-price,id+" purchase adds one unit and debits the local price")
		check(market.stock[item]==stock-1000 and p.commerce.state.markets.chengdu.stock[item]==home_stock and p.commerce.state.shipments.size()==shipments,id+" sale draws from Paris stock without freight")
		if id=="market-main": await capture("市集")
	shell._close_dialog()

func bank() -> void:
	if not await approach("commercial_street:bank"): return
	await press_e()
	var p := shell.profile
	var cash := int(p.shop.snapshot().money_cents)
	var deposit := int(p.commerce.society.bank.account("player").deposit_cents)
	if check(button("存入")!=null and button("取出")!=null,"bank opens the real account"):
		var amount := shell._modal_box.find_child("BankAmount",true,false) as SpinBox
		amount.value=25
		button("存入").pressed.emit()
		check(int(p.shop.snapshot().money_cents)==cash-2500 and p.commerce.society.bank.account("player").deposit_cents==deposit+2500,"deposit moves 25 yuan into savings")
		amount=shell._modal_box.find_child("BankAmount",true,false) as SpinBox
		amount.value=10
		button("取出").pressed.emit()
		check(int(p.shop.snapshot().money_cents)==cash-1500 and p.commerce.society.bank.account("player").deposit_cents==deposit+1500,"withdrawal returns 10 yuan to wallet")
		await capture("银行")
		amount=shell._modal_box.find_child("BankAmount",true,false) as SpinBox
		amount.value=9999
		button("取出").pressed.emit()
		check(int(p.shop.snapshot().money_cents)==cash-1500 and p.commerce.society.bank.account("player").deposit_cents==deposit+1500,"insufficient deposit rejects the withdrawal")
	shell._close_dialog()

func capture(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label+".png"))
