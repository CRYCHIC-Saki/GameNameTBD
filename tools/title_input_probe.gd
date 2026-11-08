extends SceneTree
## Real mouse regression, also injected into a disposable Windows export test pack.
var app: TDApplication
var shell: TDGameShell
var evidence: String
var checks: int=0
var failed: bool=false

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	checks+=1
	print("TITLE_CHECK ",checks," ","PASS " if value else "FAIL ",message)
	if not value: failed=true

func frames() -> void:
	for i:int in 5: await process_frame

func find_button(text: String, parent: Node) -> Button:
	if not is_instance_valid(parent): return null
	for node: Button in parent.find_children("*","Button",true,false):
		if node.text==text: return node
	return null

func click(text: String, parent: Node) -> void:
	var target:=find_button(text,parent)
	check(target!=null,"button exists: "+text)
	if target==null: return
	var at:=target.get_global_rect().get_center()
	print("CLICK ",target.text," rect=",target.get_global_rect()," paused=",paused)
	for down:bool in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;event.position=at;event.global_position=at
		root.push_input(event,true)
	await frames()

func capture(name: String) -> void:
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(evidence.path_join(name+".png"))

func finish() -> void:
	if shell!=null:
		print("NOTICE ",shell._notice.text if is_instance_valid(shell._notice) else shell._title_notice.text)
		shell.go_title()
	print("TITLE_PROBE success=",not failed," checks=",checks)
	if not failed and is_instance_valid(shell):
		# Use the same audio retirement and exit path as the real title screen.
		# A missing application quit is caught by the process timeout.
		shell.request_quit()
		return
	if is_instance_valid(shell) and is_instance_valid(shell.music): shell.music.shutdown()
	if app!=null: app.queue_free()
	await root.get_tree().create_timer(0.15,true).timeout
	quit(1)

func run() -> void:
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--probe-root="): evidence=argument.trim_prefix("--probe-root=").replace("\\","/")
	# Never fall back to user:// or touch a real save when the harness is misconfigured.
	if not evidence.is_absolute_path() or not "/artifacts/" in evidence:
		print("TITLE_PROBE requires an absolute --probe-root inside artifacts");quit(1);return
	evidence=evidence.path_join("run-%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(evidence)
	root.size=Vector2i(1280,800)
	app=load("res://src/app/main.tscn").instantiate();app.settings_path=evidence.path_join("settings.json")
	root.add_child(app);shell=app.game_shell;shell.automatic_time=false
	shell.legacy_shop_path=evidence.path_join("old-shop.json");shell.legacy_research_path=evidence.path_join("old-research.json")
	await frames()
	await capture("title")
	# Exact reported route: explicitly choose an empty slot with a real mouse click.
	await click("载入存档",shell._title_screen)
	await click("新建存档",shell._modal_box)
	await capture("empty-slots")
	await click("从这里开始",shell._modal_box)
	check(shell.profile!=null,"empty slot created a playable profile")
	if failed: await capture("failure");await finish();return
	check(shell.location=="town" and shell.profile.slot_id=="slot-01","new slot starts in harbor film")
	check(shell.guide.presenting() and not shell.town.visible and shell.town._player_cell()==TDHarbor.ARRIVAL,"film precedes playable harbor map")
	shell.guide.dialogue.finish_now()
	check(not paused,"creation resumes game")
	await capture("new-game")
	var first:=FileAccess.get_file_as_bytes(shell.slots.path_for("slot-01"))
	shell.go_title();await frames()
	await click("载入存档",shell._title_screen)
	await click("新建存档",shell._modal_box)
	await click("从这里开始",shell._modal_box)
	check(shell.profile!=null,"second empty slot creates another profile")
	if failed: await finish();return
	check(shell.profile.slot_id=="slot-02","slot selection keeps stable identity")
	shell.guide.dialogue.finish_now()
	check(FileAccess.get_file_as_bytes(shell.slots.path_for("slot-01"))==first,"first slot remains untouched")
	check(shell.profile.buy({"egg":1000}).ok,"second profile can buy inventory")
	check(shell.save_game().ok,"second profile saves")
	var money:int=shell.profile.shop.snapshot().money_cents
	shell.go_title();await frames()
	await click("继续游戏",shell._title_screen)
	check(shell.profile!=null and shell._modal==null,"continue enters game without slot chooser")
	if failed: await finish();return
	check(shell.profile.slot_id=="slot-02","continue opens most recently saved slot")
	check(shell.profile.shop.snapshot().money_cents==money and shell.profile.shop.available("egg")==1000,"inventory and money survived reload")
	check(shell.slots.slots().filter(func(row:Dictionary)->bool:return row.ok).size()==2,"continue did not create a third slot")
	shell.go_title();await frames()
	await click("载入存档",shell._title_screen)
	await capture("saved-slots")
	await click("载入",shell._modal_box)
	check(shell.profile!=null,"explicit load works")
	if shell.profile!=null: check(shell.profile.slot_id=="slot-01","load menu selects the requested older slot")
	if not failed: await check_room_movement()
	shell.go_title();await frames()
	await click("开始游戏",shell._title_screen)
	check(shell.profile!=null and shell.profile.slot_id=="slot-03","start always creates a new empty slot")
	check(shell.guide.presenting() and shell.profile.story.beat=="arrive","new start replays opening")
	shell.guide.dialogue.finish_now()
	await check_checkpoint()
	await finish()

func check_checkpoint() -> void:
	var path:=shell.slots.path_for("slot-03")
	var original:=FileAccess.get_file_as_bytes(path)
	check(shell.restaurant.layout.set_surface_finish("carpet").ok,"exported unsaved decoration")
	check(shell.profile.research.calibrate(.05).ok,"exported research change stays in memory")
	shell.request_title();await frames();await capture("discard-confirmation")
	await click("确认返回主菜单",shell._modal_box)
	check(FileAccess.get_file_as_bytes(path)==original,"actual return does not silently checkpoint decoration or research")
	check(shell.load_game("slot-03").ok,"export reloads last whole checkpoint")
	check(shell.profile.research.snapshot().input_offset_sec==0.0,"unsaved research rolls back")
	check(shell.restaurant.layout.finish_at(2,2)!="carpet","unsaved decoration rolls back with research")
	check(shell.restaurant.layout.set_surface_finish("carpet").ok,"new decoration can be explicitly saved")
	shell.request_title();await frames()
	await click("保存并返回主菜单",shell._modal_box)
	check(shell.profile==null and FileAccess.get_file_as_bytes(path)!=original,"explicit save and return commits")
	check(shell.load_game("slot-03").ok and shell.restaurant.layout.finish_at(2,2)=="carpet","explicitly saved decoration survives reload")

func physics_frames(count: int) -> void:
	for i:int in count: await physics_frame

func check_room_movement() -> void:
	shell.travel("restaurant");await physics_frames(2)
	var room:=shell.restaurant;var layout:=room.layout
	await capture("restaurant-entry")
	var edges:int=0;var blocked:int=0
	for y:int in range(1,layout.rows-1):
		for x:int in range(1,layout.columns-1):
			if not layout.is_walkable(x,y): continue
			for offset:Vector2i in [Vector2i.RIGHT,Vector2i.DOWN]:
				if not layout.is_walkable(x+offset.x,y+offset.y): continue
				room.teleport_player(Vector2i(x,y));edges+=1
				if room._player.move_and_collide(Vector2(offset)*layout.cell_px)!=null: blocked+=1
	print("EXPORTED_ROOM_PATHS edges=",edges," blocked=",blocked)
	check(edges>100 and blocked==0,"all open restaurant edges clear with other worlds present")
	room.teleport_player(Vector2i(4,3))
	check(room._player.move_and_collide(Vector2(64,0))==null,"empty ordering floor is walkable")
	await capture("restaurant-empty-zone")
	room.teleport_player(Vector2i(2,5))
	check(room._player.move_and_collide(Vector2(128,0))!=null,"actual restaurant table stays solid")
	await capture("restaurant-table-edge")
	room.teleport_player(Vector2i(6,8));await physics_frames(2)
	var before:=room.player_position()
	Input.action_press("world_right");await physics_frames(12);Input.action_release("world_right")
	# Match the player's screen-speed contract even when the interior grid is enlarged.
	var old_screen:=TDRestaurantIsoView.project(before.x/layout.cell_px,before.y/layout.cell_px)
	var after:=room.player_position()
	var travel:=TDRestaurantIsoView.project(after.x/layout.cell_px,after.y/layout.cell_px)-old_screen
	print("EXPORTED_ROOM_TRAVEL screen=",travel)
	check(travel.x>25.0 and absf(travel.y-travel.x*.5)<.1,"real movement follows the 2:1 floor tile edge")
	await capture("restaurant-clear-aisle")
	await check_decoration(room)
	shell.travel("kitchen");await physics_frames(2)
	var kitchen:=shell.kitchen_view.kitchen.world
	kitchen._player.position=Vector2(500,450)
	check(kitchen._player.move_and_collide(Vector2(300,0))==null,"restaurant and town cannot block kitchen floor")
	kitchen._player.position=Vector2(640,320)
	check(kitchen._player.move_and_collide(Vector2(0,-150))!=null,"kitchen counter remains solid")
	await capture("kitchen-walk")
	var home_talk:=TDOpeningScript.home_conversation("home_door","赤焰")
	home_talk.begin()
	check(not home_talk.full_text().is_empty(),"export includes the homecoming script")
	# This export smoke checks acquired-room assets; narrative acquisition is tested separately.
	shell.profile.residence.stage="door";check(shell.profile.unlock_residence().ok,"profile can acquire cottage through its contract")
	check(shell.travel("cottage",true).ok and shell.cottage.target()=="rest","exported cottage bed and interaction are available")
	await capture("cottage-bed")
	await check_dining()

func check_dining() -> void:
	# Controlled arrival timing, actual exported profile/room/kitchen and order authority.
	shell.profile.story.beat="done"
	var shop:=shell.profile.shop;shop.commerce=null
	shell.kitchen_view.kitchen.auto_advance=false
	var stock: Dictionary=shop.offer("service.tomato_egg").stock.duplicate(true)
	for id: String in stock: stock[id]=int(stock[id])*3
	check(shop.buy(stock,"export-dining-stock").ok,"exported dining inventory")
	for id: String in shop.snapshot().menu: shop.set_menu(id,id=="service.tomato_egg",1200)
	shell.travel("restaurant");await frames()
	check(shop.require_seating and shell.restaurant.unified_dining_clock,"formal shell connects the dining clock")
	check(shop.open_day().ok and shop.advance(1).ok,"exported diner arrives")
	check(shop.pending_orders().size()==1 and shop.active_orders().is_empty(),"arriving diner is not a kitchen order")
	if shop.pending_orders().is_empty(): return
	var id: String=shop.pending_orders()[0].id
	var guest:=shell.restaurant._business_guests.get(id) as TDRestaurantGuest
	check(guest!=null,"exported restaurant creates actual diner")
	if guest==null: return
	check(shop.advance(guest.walking_seconds()).ok and guest.phase=="sitting","exported diner walks to its table")
	check(shop.advance(guest.sit_duration).ok and shop.order(id).status=="WAITING","exported diner sits then orders once")
	var before:=shop.order(id)
	check(shop.confirm_seated(id,guest.seat_id).code=="ALREADY_ORDERED" and shop.order(id)==before,"duplicate seating does not reset order")
	shell.restaurant.teleport_player(shell.restaurant.approach_cell(guest.seat_id));await frames()
	await capture("diner-seated")
	shell.travel("kitchen");shell.kitchen_view.refresh();await frames()
	var text: String=""
	for label: Label in shell.kitchen_view._sidebar.find_children("*","Label",true,false): text+=label.text
	check(text.contains(shop.order_label(id)) and text.contains(shop.recipe_name(before.recipe_id)),"exported kitchen shows the same diner and dish")
	await capture("diner-kitchen-order")
	for variant: int in TDDinerArt.VARIANTS:
		check(TDDinerArt.sprite(variant,Vector2i.RIGHT,0).get_height()>10 and TDDinerArt.sprite(variant,Vector2i.LEFT,-1,true).get_height()>10,"exported walking and seated art "+str(variant))
	for who: String in ["","aling","chen"]:
		check(TDDinerArt.dining_sprite(1,who).get_height()>50,"exported aligned dining pose "+who)
	for order: Dictionary in shop.pending_orders(): shop.cancel_order(order.id)
	shop.close_early()

func click_at(point: Vector2, button: MouseButton=MOUSE_BUTTON_LEFT) -> void:
	var motion:=InputEventMouseMotion.new();motion.position=point;motion.global_position=point
	root.push_input(motion,true);await process_frame
	for down: bool in [true,false]:
		var event:=InputEventMouseButton.new()
		event.button_index=button;event.pressed=down;event.position=point;event.global_position=point
		root.push_input(event,true);await process_frame
	await frames()

func check_decoration(room: TDRestaurantWorld) -> void:
	var board: Dictionary=room.interaction_points().filter(func(value: Dictionary)->bool:return value.action=="decorate")[0]
	room.teleport_player(Vector2i(1,int(board.cell.y)));await frames()
	for down: bool in [true,false]:
		var key:=InputEventKey.new();key.physical_keycode=KEY_E;key.pressed=down;root.push_input(key,true)
	await frames()
	check(room._editing and room._decor_panel.visible,"actual decoration board E opens catalog")
	if not room._editing: return
	var count:=room.layout.pieces().size()
	await click("陈设",room._decor_panel)
	var card:=room._decor_panel._cards.get_node("Item_kiosk") as Button
	await click_at(card.get_global_rect().get_center())
	check(room._tool=="place","exported furniture card uses actual input")
	room._hover_at(Vector2i(8,8));await frames()
	check(room._iso.ghost_ok and not room._iso.ghost_piece.is_empty(),"export includes raised preview renderer")
	await capture("decoration-preview")
	var point:=room._iso.get_global_transform_with_canvas()*TDRestaurantIsoView.project(8.5,8.5)
	await click_at(point)
	var id:=room._selected
	check(room.layout.pieces().size()==count+1 and room._tool=="select","exported placement commits once and returns to selection")
	if not room.layout.piece(id).is_empty():
		var top:=TDFurnitureModel.center(room.layout.piece(id))+Vector2(0,-65)
		await click_at(room._iso.get_global_transform_with_canvas()*top)
		check(room._selected==id and room._context_menu.visible,"exported upper model selection")
		check(room._decor_panel.find_children("*","OptionButton",true,false).is_empty(),"removed style selectors stay absent in export")
		await click_at(room._rotate_button.get_global_rect().get_center())
		check(int(room.layout.piece(id).get("rotation",-1))==270,"exported corner rotates counterclockwise once")
		await capture("decoration-actions")
		var start:=room._iso.get_global_transform_with_canvas()*(TDFurnitureModel.center(room.layout.piece(id))+Vector2(0,-45))
		var end:=start+room._iso.get_global_transform_with_canvas().basis_xform(Vector2(96,48))
		var press:=InputEventMouseButton.new();press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true;press.position=start;press.global_position=start;root.push_input(press,true);await frames()
		var motion:=InputEventMouseMotion.new();motion.position=end;motion.global_position=end;root.push_input(motion,true);await frames()
		check(room._dragging and int(room.layout.piece(id).x)==8,"exported drag preview is read-only")
		var release:=InputEventMouseButton.new();release.button_index=MOUSE_BUTTON_LEFT;release.pressed=false;release.position=end;release.global_position=end;root.push_input(release,true);await frames()
		check(int(room.layout.piece(id).x)==10 and int(room.layout.piece(id).y)==8,"exported drag moves existing furniture")
		await capture("decoration-moved")
		check(shell.save_game().ok,"moved furniture saves through the profile boundary")
		var moved_save:=shell.slots.load_slot(shell.profile.slot_id)
		check(moved_save.ok and moved_save.data.layout.pieces.any(func(piece: Dictionary)->bool:return str(piece.id)==id and int(piece.x)==10 and int(piece.y)==8 and int(piece.rotation)==270),"isolated disk save keeps moved identity, position and rotation")
		await click_at(room._delete_button.get_global_rect().get_center())
		check(room.layout.piece(id).is_empty() and room.layout.pieces().size()==count,"exported context deletes once")
	await click("餐桌",room._decor_panel)
	await click_at((room._decor_panel._cards.get_node("Item_dining_table") as Button).get_global_rect().get_center())
	await click_at(room._iso.get_global_transform_with_canvas()*TDRestaurantIsoView.project(8.5,7.5))
	var table_id:=room._selected
	check(not room.layout.piece(table_id).is_empty(),"exported table card places table")
	if not room.layout.piece(table_id).is_empty():
		var original:=room.layout.piece(table_id)
		await click_at(room._iso.get_global_transform_with_canvas()*(TDFurnitureModel.center(original)+Vector2(0,-80)))
		check(room._selected==table_id and room._context_menu.visible,"exported placed table selected")
		for angle: int in [270,180,90,0]:
			await click_at(room._rotate_button.get_global_rect().get_center())
			check(int(room.layout.piece(table_id).rotation)==angle and TDFurnitureModel.center(room.layout.piece(table_id))==TDFurnitureModel.center(original),"exported table rotates at same center "+str(angle))
		await capture("decoration-table-rotated")
	for category: String in ["地面","墙壁"]:
		await click(category,room._decor_panel)
		await click_at((room._decor_panel._cards.get_node("Item_"+("tile" if category=="地面" else "brick")) as Button).get_global_rect().get_center())
		var whole: bool=true
		for y: int in room.layout.rows:
			for x: int in room.layout.columns:
				if (room.layout.cell_zone(x,y)=="facade")== (category=="墙壁"):
					whole=whole and room.layout.finish_at(x,y)==("brick" if category=="墙壁" else "tile")
		check(whole and room._tool=="select","exported whole finish card "+category)
	await capture("decoration-whole-finishes")
	await click("完成布置",room._decor_panel)
	check(not room._editing and not room._context_menu.visible,"finishing restores game controls")
	check(shell.save_game().ok,"decoration persists through the existing profile boundary")
	var restored:=shell.slots.load_slot(shell.profile.slot_id)
	check(restored.ok,"saved profile remains readable after decoration")
	# JSON arrays/numbers must pass through the real layout importer before comparison.
	var restored_layout:=TDRestaurantLayout.import_dict(restored.data.layout,room.catalog) if restored.ok else null
	check(restored_layout!=null and restored_layout.to_dict()==room.layout.to_dict(),"isolated disk save preserves whole surfaces and table orientation")
