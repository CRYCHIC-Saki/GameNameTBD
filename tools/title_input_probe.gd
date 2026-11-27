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
	if "--sleep-only" in OS.get_cmdline_user_args():
		await check_sleep_animation()
		await finish()
		return
	if "--battle-only" in OS.get_cmdline_user_args():
		check(shell.create_game("slot-01","战后验证",true).ok,"isolated profile for the actual PCK")
		if not failed:
			await finish_harbor_opening()
			await check_battle_handoff()
		await finish()
		return
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
	check(shell.slots.load_slot("slot-01").code=="NOT_FOUND","new game has no checkpoint during the opening")
	await finish_harbor_opening()
	await frames()
	check(not paused,"creation resumes game")
	await capture("new-game")
	var first_path:=shell.slots.path_for("slot-01",TDProfileStore.STORY)
	check(FileAccess.file_exists(first_path),"first mainline scene autosaves")
	var first:=FileAccess.get_file_as_bytes(first_path)
	shell.go_title();await frames()
	await click("载入存档",shell._title_screen)
	await click("新建存档",shell._modal_box)
	await click("从这里开始",shell._modal_box)
	check(shell.profile!=null,"second empty slot creates another profile")
	if failed: await finish();return
	check(shell.profile.slot_id=="slot-02","slot selection keeps stable identity")
	shell.guide.dialogue.finish_now()
	check(FileAccess.get_file_as_bytes(first_path)==first,"first slot remains untouched")
	check(shell.profile.buy({"egg":1000}).ok,"second profile can buy inventory")
	shell._sleep("chengdu",0)
	await finish_sleep_results()
	check(shell.slots.load_slot("slot-02",TDProfileStore.DAILY).ok,"second profile autosaves when sleeping")
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
	await click("剧情存档 · 第 1 场",shell._modal_box)
	check(shell.profile!=null,"explicit load works")
	if shell.profile!=null: check(shell.profile.slot_id=="slot-01","load menu selects the requested older slot")
	if not failed: await check_room_movement()
	shell.go_title();await frames()
	await click("开始游戏",shell._title_screen)
	check(shell.profile!=null and shell.profile.slot_id=="slot-03","start always creates a new empty slot")
	check(shell.guide.presenting() and shell.profile.story.revised.get("cursor",-1)==0,"new start replays revised opening")
	await finish_harbor_opening()
	await frames()
	await check_checkpoint()
	await finish()

func check_checkpoint() -> void:
	var path:=shell.slots.path_for("slot-03",TDProfileStore.STORY)
	var daily:=shell.slots.path_for("slot-03",TDProfileStore.DAILY)
	var original:=FileAccess.get_file_as_bytes(path)
	check(shell.restaurant.layout.set_surface_finish("carpet").ok,"exported unsaved decoration")
	check(shell.profile.research.calibrate(.05).ok,"exported research change stays in memory")
	shell.advance_world_time(120)
	shell.request_title();await frames();await capture("discard-confirmation")
	await click("确认返回主菜单",shell._modal_box)
	check(FileAccess.get_file_as_bytes(path)==original,"actual return does not silently checkpoint decoration or research")
	check(shell.load_game("slot-03").ok,"export reloads last whole checkpoint")
	check(shell.profile.research.snapshot().input_offset_sec==0.0,"unsaved research rolls back")
	check(shell.restaurant.layout.finish_at(2,2)!="carpet","unsaved decoration rolls back with research")
	check(shell.profile.characters.clock.minute==480.0,"unsaved clock returns to 08:00")
	check(shell.restaurant.layout.set_surface_finish("carpet").ok,"new decoration is ready for the sleep checkpoint")
	shell.profile.story.beat="done"
	shell.profile.residence.stage="door"
	check(shell.profile.unlock_residence().ok,"cottage ready for sleep")
	shell.profile.characters.clock.minute=1560.0
	check(shell.finish_night().ok and FileAccess.get_file_as_bytes(path)==original,"02:00 closes without writing")
	shell.show_rest();await frames()
	await click("休息到明天",shell._modal_box)
	await finish_sleep_results()
	check(int(shell.profile.shop.snapshot().day)==2 and FileAccess.get_file_as_bytes(path)==original and FileAccess.file_exists(daily),"sleep commits next morning to a separate checkpoint")
	check(shell.load_game("slot-03").ok and shell.restaurant.layout.finish_at(2,2)=="carpet" and shell.profile.characters.clock.minute==480.0,"sleep checkpoint restores decoration and 08:00")

func finish_sleep_results() -> void:
	if DisplayServer.get_name()=="headless": return
	await root.get_tree().create_timer(5.6).timeout
	if is_instance_valid(shell._sleep_results):
		await click("迎接新的一天",shell._sleep_results)
		await root.get_tree().create_timer(0.9).timeout

func check_sleep_animation() -> void:
	check(DisplayServer.get_name()!="headless","sleep animation uses a real renderer")
	check(shell.create_game("slot-01","休息画面测试",false).ok,"open isolated profile")
	if failed: return
	shell.guide.dialogue.finish_now()
	var profile := shell.profile
	profile.story.beat="done"
	profile.residence.stage="door"
	check(profile.unlock_residence().ok,"unlock the cottage for the sleep probe")
	for day: int in range(1,9):
		check(profile.shop.open_day().ok,"open a real service day")
		profile.shop.advance(360)
		for order: Dictionary in profile.shop.active_orders(): profile.shop.cancel_order(order.id)
		profile.shop.advance(1000)
		var report := profile.level_daily_report()
		check(report.ok,"the settled ledger has a daily experience report")
		if not report.ok: return
		var gain := profile.progression.evaluate(report.data)
		if int(profile.progression.progress().total_xp) + int(gain.data.mapped_xp) >= profile.progression.threshold(2):
			break
		check(profile.next_day().ok,"advance the earlier fixture day")
	check(profile.progression.progress().level==1,"the shop closure leaves the level at one")
	shell._close_dialog()
	check(shell.travel("cottage",true).ok,"enter the cottage")
	shell.show_rest()
	await frames()
	await click("休息到明天",shell._modal_box)
	var overlay := shell._sleep_results
	check(is_instance_valid(overlay) and paused,"sleep freezes gameplay and shows the overlay")
	if not is_instance_valid(overlay): return
	await root.get_tree().create_timer(.8).timeout
	check(is_equal_approx(overlay._black.modulate.a,1.0) and overlay._message.modulate.a > .95,"the first page shows the sleep message on opaque black")
	await capture("01-sleeping")
	await root.get_tree().create_timer(1.9).timeout
	check(overlay._summary.modulate.a > .95 and not overlay._message.visible,"the second page fades in after the sleep message")
	var initial_fill: float = overlay._bar.value
	for frame: int in range(130):
		if overlay._promotion.modulate.a > .8:
			await capture("02-level-up")
			break
		await root.get_tree().create_timer(.025).timeout
	check(FileAccess.file_exists(evidence.path_join("02-level-up.png")),"the level-up animation was displayed")
	check(overlay._bar.value != initial_fill or overlay._level.text=="Lv. 2","the experience bar advances through the next level")
	for frame: int in range(130):
		if overlay._continue.visible: break
		await root.get_tree().create_timer(.025).timeout
	check(overlay._continue.visible and overlay._level.text=="Lv. 2","the results end at level two with a continue button")
	await capture("03-daily-summary")
	await click("迎接新的一天",overlay)
	await root.get_tree().create_timer(.9).timeout
	check(shell.location=="cottage" and not paused and not shell._rest_busy,"waking restores room controls")
	check(shell.slots.load_slot("slot-01",TDProfileStore.DAILY).ok,"the morning checkpoint is readable")

func physics_frames(count: int) -> void:
	for i:int in count: await physics_frame

func finish_harbor_opening() -> void:
	await finish_active_dialogue()
	if shell.profile.story.revised.cursor!=0: return
	var journey := shell.guide.journey
	check(journey.arrival_checked_count()==0 and shell.town.visible,"arrival dialogue unlocks the search at zero of three")
	for index: int in journey.ARRIVAL_SHOPS.size():
		shell.town.spawn_at_plot(journey.ARRIVAL_SHOPS[index])
		var interact := InputEventKey.new()
		interact.physical_keycode=KEY_E
		interact.pressed=true
		Input.parse_input_event(interact)
		await process_frame
		interact=interact.duplicate()
		interact.pressed=false
		Input.parse_input_event(interact)
		check(journey.arrival_checked_count()==index+1,"E checks a distinct shuttered food shop")
	check(not shell.guide.presenting(),"the return dialogue waits until the player is at the harbor")
	shell.town.spawn_at_harbor()
	await process_frame
	await process_frame
	check(shell.guide.presenting() and shell.guide.dialogue.talk.context.scene==TDRevisedMainline.ARRIVAL_RETURN_ID,"the return dialogue loads from the Windows package")
	await finish_active_dialogue()

func finish_active_dialogue() -> void:
	var view := shell.guide.dialogue
	for step: int in 120:
		if not shell.guide.presenting(): return
		if view._vn_stage.runner != null:
			view._vn_stage.dialog._reveal_to_end()
			view._vn_stage.dialog._advance_dialog()
		await process_frame
		await process_frame

func check_room_movement() -> void:
	check(not shell.guide.presenting() and shell.profile.story.revised.cursor==1,"finished harbor dialogue returns control before the first kitchen visit")
	if failed: return
	check(shell.travel("restaurant").ok,"enter the restaurant during the opening chapter")
	await physics_frames(2)
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
	check(travel.x>25.0 and absf(travel.y)<.1,"real movement follows the screen horizontal axis")
	await capture("restaurant-clear-aisle")
	await check_decoration(room)
	await check_battle_handoff()
	await check_dining()
	shell.travel("kitchen");await physics_frames(2)
	var kitchen:=shell.kitchen_view.kitchen.world
	kitchen._player.position=Vector2(500,450)
	check(kitchen._player.move_and_collide(Vector2(300,0))==null,"restaurant and town cannot block kitchen floor")
	kitchen._player.position=Vector2(640,320)
	check(kitchen._player.move_and_collide(Vector2(0,-150))!=null,"kitchen counter remains solid")
	await capture("kitchen-walk")
	# Use the acquired cottage to check its assets and interactions in the release package.
	shell.profile.residence.stage="door";check(shell.profile.unlock_residence().ok,"profile can acquire cottage through its contract")
	check(shell.travel("cottage",true).ok and shell.cottage.target()=="rest","exported cottage bed and interaction are available")
	await capture("cottage-bed")

func check_battle_handoff() -> void:
	var story := shell.profile.story.revised
	check(TDRevisedMainline.complete_dialogue(story,"revised_01",true),"enter the first duel fixture at the real story goal")
	check(shell.travel("kitchen").ok,"first duel starts from its kitchen")
	shell._show_challenge({"opponent":0},shell.guide.journey._battle_finished.bind(2))
	var panel := shell._challenge
	check(panel.lesson!=null and panel.battle==null and panel.lesson.definition.recipe_id=="service.tomato_egg","the packaged story requires cooking before the duel")
	if panel.lesson==null: return
	# The integration test completes the real cooking chart. This probe isolates the post-win handoff.
	panel._close_cooking()
	panel.preparation = TDChallengeBattle.Rules.compare(50,50)
	panel._enter_battle()
	var battle := panel.battle
	check(battle.tutorial==TDChallengeBattle.Tutorial.ALING_MOVE,"the first Aling duel starts with the movement tutorial")
	for key: Key in [KEY_W,KEY_A,KEY_S,KEY_D]: combat_key(key)
	for step: int in 4:
		combat_key(KEY_SPACE)
		await click_at(panel.board.cell_center(battle.foe))
	for step: int in 8: combat_key(KEY_F)
	for key: Key in [KEY_W,KEY_A,KEY_S,KEY_D,KEY_W,KEY_W]: combat_key(key)
	check(battle.tutorial==TDChallengeBattle.Tutorial.NONE,"the packaged tutorial completes through WASD, mouse targeting, F confirmation and dodging")
	battle.foe = battle.hero + Vector2i.RIGHT
	battle.foe_hp = 2
	combat_key(KEY_F)
	combat_key(KEY_F)
	await frames()
	if panel.notice==null:
		check(false,"battle win opens the first skill reward")
		return
	check(panel.notice.body.text.begins_with("获得技能 · 驱遣夜鸦"),"battle win opens the first skill reward")
	check(panel.notice.body.get_line_count()==1,"the skill reward fits on one line")
	await click("确认",panel.notice)
	check(panel.notice!=null and panel.notice.body.text=="下次备战可装配技能。","equipment guidance follows the reward")
	check(panel.notice!=null and panel.notice.body.get_line_count()==1,"the equipment guidance fits on one line")
	if panel.notice!=null: await click("确认",panel.notice)
	await frames()
	var view := shell.guide.dialogue
	check(story.cursor==3 and shell._challenge==null and shell._modal==null,"confirmed reward opens post-battle story")
	var line_loaded := shell.guide.presenting() and view._native and view.talk.body.contains("炒蛋") \
		and view._vn_stage.container.is_visible_in_tree() and view._vn_stage._dialog_layer.visible
	check(line_loaded,"packaged post-battle dialogue loads its first line")
	if not line_loaded: return
	await capture("aling-post-battle")
	await finish_harbor_opening()
	await physics_frames(2)
	var player := shell.town._player
	check(story.cursor==4 and shell.location=="town" and not paused and player.controls_enabled,"ending the battle dialogue returns control")
	check(not shell.kitchen_view.kitchen.shared_clock.paused,"the kitchen pause clears with the post-battle dialogue")
	var feet := player.position
	for direction: Array in [[Vector2.DOWN,"world_down"],[Vector2.LEFT,"world_left"],[Vector2.RIGHT,"world_right"]]:
		if not TDInteractionRange.ground_segment_clear(feet,feet+direction[0]*40.0,shell.town._can_stand,4.0): continue
		Input.action_press(direction[1])
		await physics_frames(10)
		Input.action_release(direction[1])
		break
	check(player.position.distance_to(feet)>8.0,"actual movement input works after dialogue")
	shell.travel("restaurant")

func combat_key(key: Key) -> void:
	for down: bool in [true,false]:
		var event := InputEventKey.new()
		event.physical_keycode=key
		event.pressed=down
		root.push_input(event,true)

func check_dining() -> void:
	var shop := shell.profile.shop
	check(shop.require_seating and shell.restaurant.unified_dining_clock,"formal shell connects the dining clock")
	check(shell.start_day().code=="PORT_CLOSED_BY_STORY","revised port ban blocks public service")
	# Use a valid completed story in this disposable slot so the opening ban and
	# the lawful post-ending service flow are both checked in the same game.
	var story := shell.profile.story.revised
	for index: int in range(int(story.cursor), TDRevisedMainline.data().nodes.size()):
		var node: Dictionary = TDRevisedMainline.data().nodes[index]
		var advanced := TDRevisedMainline.complete_dialogue(story, node.id, true) if node.kind=="dialogue" else TDRevisedMainline.complete_action(story, node.id)
		if not advanced:
			check(false,"advance the isolated ending fixture")
			return
	check(TDRevisedMainline.validate(story) and story.port_reopened,"completed story reopens the port for public service")
	# Keep the first arrival deterministic. Walk, seating and tickets use the
	# exported restaurant and its real shared business clock.
	shop.commerce=null
	shell.kitchen_view.kitchen.auto_advance=false
	var stock: Dictionary=shop.offer("service.tomato_egg").stock.duplicate(true)
	for id: String in stock: stock[id]=int(stock[id])*3
	check(shop.buy(stock,"export-dining-stock").ok,"exported dining inventory")
	for id: String in shop.snapshot().menu: shop.set_menu(id,id=="service.tomato_egg",1200)
	check(shell.start_day().ok and shop.advance(1).ok,"open with the reopened port and admit a diner")
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
		check(shell.profile.save().ok,"capture moved furniture in an isolated serialization fixture")
		var moved_save:=shell.slots.load_slot(shell.profile.slot_id,"")
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
	# Exercise finish placement at the level required by the configured rewards.
	var progression := room.decoration_progression
	var previous_level := int(progression.progress().level)
	progression._state.level = maxi(previous_level,maxi(progression.decoration_level("tile"),progression.decoration_level("brick")))
	for category: String in ["地面","墙壁"]:
		await click(category,room._decor_panel)
		await click_at((room._decor_panel._cards.get_node("Item_"+("tile" if category=="地面" else "brick")) as Button).get_global_rect().get_center())
		var whole: bool=true
		for y: int in room.layout.rows:
			for x: int in room.layout.columns:
				if (room.layout.cell_zone(x,y)=="facade")== (category=="墙壁"):
					whole=whole and room.layout.finish_at(x,y)==("brick" if category=="墙壁" else "tile")
		check(whole and room._tool=="select","exported whole finish card "+category)
	progression._state.level = previous_level
	await capture("decoration-whole-finishes")
	await click("完成布置",room._decor_panel)
	check(not room._editing and not room._context_menu.visible,"finishing restores game controls")
	check(shell.profile.save().ok,"capture decoration in an isolated serialization fixture")
	var restored:=shell.slots.load_slot(shell.profile.slot_id,"")
	check(restored.ok,"saved profile remains readable after decoration")
	# JSON arrays/numbers must pass through the real layout importer before comparison.
	var restored_layout:=TDRestaurantLayout.import_dict(restored.data.layout,room.catalog) if restored.ok else null
	check(restored_layout!=null and restored_layout.to_dict()==room.layout.to_dict(),"isolated disk save preserves whole surfaces and table orientation")
