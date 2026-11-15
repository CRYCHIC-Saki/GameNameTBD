extends SceneTree
## Actual Shell/scenes; isolated profile. Long labels below are presentation-only stress fixtures.
const OUT: String="res://artifacts/quiet-hud-20261115/gpu"
var checks: int=0
var failures: int=0
var captures: Array[String]=[]
func _initialize() -> void: call_deferred("run")
func verify(value: bool, description: String) -> void:
	checks+=1
	if value: print("PASS ",description)
	else: failures+=1;printerr("FAIL ",description)
func settle() -> void:
	for i: int in 5: await process_frame
func tap(key: Key) -> void:
	for down: bool in [true,false]:
		var event:=InputEventKey.new();event.keycode=key;event.physical_keycode=key;event.pressed=down;root.push_input(event,true)
func capture(label: String) -> void:
	await settle();await RenderingServer.frame_post_draw
	verify(root.get_texture().get_image().save_png(OUT.path_join(label+".png"))==OK,"screenshot "+label)
	captures.append(label)
func check_board(shell: TDGameShell) -> void:
	var plate:=shell.restaurant._order_plate
	verify(plate.get_global_rect().position.y>=shell._hud.reserved_bottom()+11,"business board below status / toast")
	verify(plate.get_global_rect().position.y>=shell.guide.reserved_bottom()+11,"business board below quest")
	verify(plate.get_global_rect().end.y<=root.get_visible_rect().size.y-83,"business board above bottom controls")
	verify(shell.restaurant._order_scroll.clip_contents,"long content clipped inside scroll container")
func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT));root.size=Vector2i(1280,800)
	var app:=load("res://src/app/main.tscn").instantiate() as TDApplication
	app.settings_path=OUT.path_join("slots-%d/settings.json"%Time.get_ticks_usec());root.add_child(app)
	var shell:=app.game_shell;shell.automatic_time=false
	verify(shell.create_game("slot-01","文字验证").ok,"production main isolated new profile")
	shell.guide.dialogue.finish_now();shell.profile.story.beat="cook"
	shell.profile.story.tutorials.assign(["M1","M2","M3","M4","M5","M6","M7"])
	shell.town.external_story_frozen=false;shell.restaurant.story_frozen=false
	shell.travel("kitchen");shell.kitchen_view.set_paused(false)
	await settle()
	var world:=shell.kitchen_view.kitchen.world
	world._player.position=Vector2(640,480)
	shell.kitchen_view._sync_usage();shell.kitchen_view.kitchen.refresh_world()
	await settle()
	verify(is_equal_approx(world.scale.x,.71875),"actual embedded kitchen scale")
	verify(not shell.kitchen_view._message.visible,"no duplicate kitchen instruction banner")
	verify(not world._held_label.get_parent().visible,"empty hands have no banner")
	verify(world._pot_panels.all(func(p:PanelContainer)->bool:return not p.visible),"empty pots have no banners")
	verify(not world._near_prompt.get_parent().visible and not world._prompt.get_parent().visible,"idle kitchen has no control list")
	verify(shell.guide._card.size.y<140,"task card contains only current objective")
	for child: Node in world._hud.get_children():
		if str(child.name).begins_with("StationSign_"): verify(not child.visible,"obvious fixture does not need a nameplate")
	await capture("01-kitchen-quest")
	world._player.position=Vector2(200,330);await settle()
	verify(world._near_prompt.get_parent().visible and world._near_prompt.text=="E 冰箱","one nearby fridge action")
	tap(KEY_E);await settle()
	verify(shell.kitchen_view._popup!=null,"real E input still opens fridge")
	shell.kitchen_view._close_popup()
	world._player.position=Vector2(640,330);await settle();tap(KEY_F);await settle()
	verify(shell.kitchen_view.last_result.code=="NO_INGREDIENT","real empty pot action reports missing ingredient")
	verify(world._held_label.get_parent().visible and world._held_label.text.contains("食材"),"failure has a visible recovery message")
	world.set_process(false)
	var remaining:=world._message_left
	root.get_tree().paused=true;world._process(10)
	verify(world._message_left==remaining,"pause preserves feedback time")
	root.get_tree().paused=false;world._process(5)
	verify(not world._held_label.get_parent().visible,"feedback expires without permanent empty strip")
	tap(KEY_F);await settle()
	verify(world._message_left>0 and world._held_label.get_parent().visible,"same failed action can be shown again")
	world.show_feedback("");world._player.position=Vector2(640,480);world._update_prompt()
	# Freeze only presentation refresh for reproducible long-label / night fixtures.
	shell.kitchen_view.set_process(false)
	world.set_context({"hand":{"name":"番茄","shape":"dice","kind":"ingredient"}},"这口锅已经开火，不能取回原料；可以继续烹饪或整锅丢弃。")
	world.pot_contents=[{"title":"左锅 · 待烹饪","materials":"番茄（小丁）＋鸡蛋＋牛肉＋土豆","occupied":true},{"title":"右锅","materials":"","occupied":false}]
	world.simmer_meters=[{"name":"汽锅鸡","ratio":.82,"remaining_sec":38.2},{"name":"第二锅","ratio":.61,"remaining_sec":25.8}]
	world._update_pot_signs()
	await settle()
	for label: Label in [world._held_label,world._pot_materials[0]]:
		verify(label.get_theme_color("font_color")==TDUI.INK,"kitchen text uses dark ink on wood")
		verify((label.get_parent() as Control).get_global_rect().encloses(label.get_global_rect()),"kitchen label stays within panel")
	verify(not shell.guide._card.get_global_rect().intersects(world._held_label.get_parent().get_global_rect()),"quest and held hint do not overlap")
	for panel: PanelContainer in world._pot_panels:
		verify(not shell.guide._card.get_global_rect().intersects(panel.get_global_rect()),"quest and pot hint do not overlap")
	for child: Node in world._hud.get_children():
		if str(child.name).begins_with("StationSign_"):
			verify(not child.is_visible_in_tree() or not child.get_global_rect().intersects(world._held_label.get_parent().get_global_rect()),"visible hint avoids "+str(child.name))
	await capture("02-kitchen-long-hints")
	for panel: PanelContainer in world._simmer_panels:
		verify(not panel.get_global_rect().intersects(world._held_label.get_parent().get_global_rect()),"steam meter avoids held hint")
	world.set_context({"hand":{"name":"番茄","shape":"dice","kind":"ingredient"}},"这口锅已经开火，不能取回原料；可以继续烹饪或整锅丢弃。请先把手上的食材放回冰箱，再领取已完成的菜品，送到出餐口后回餐厅端到客人桌边。")
	await settle()
	verify(not world._held_label.get_parent().get_global_rect().intersects(world._hud.get_node("OperationSign").get_global_rect()),"two-line held warning stays above operation controls")
	shell.profile.characters.clock.minute=1320
	await settle()
	verify(world.day_minute==1320 and world.self_modulate!=Color.WHITE,"real night lighting applied")
	await capture("03-kitchen-night")
	shell.profile.characters.clock.minute=480;shell.kitchen_view.set_process(true);world.set_process(true)
	var shop:=shell.profile.shop;shop.commerce=null
	verify(shop.world_adjustment(500000,"hud-fixture-funds","isolated fixture").ok,"fixture funds")
	verify(shop.buy(shop.offer("service.tomato_egg").stock,"hud-fixture-stock").ok,"real stock purchase")
	for id: String in shop.snapshot().menu: shop.set_menu(id,id=="service.tomato_egg",1200)
	verify(shop.open_day().ok,"real opening")
	shell.travel("restaurant");await settle()
	if root.get_tree().paused and shell._modal!=null: shell._close_dialog()
	shell.kitchen_view.set_paused(false);shell.kitchen_view.kitchen.advance(1)
	await settle()
	verify(shell.restaurant._order_board.is_visible_in_tree() and not shell.restaurant._order_board.text.is_empty(),"actual business update produces visible information")
	verify(not shell.restaurant._order_board.text.contains("装修效果") and not shell.restaurant._order_board.text.contains("出餐口 E"),"restaurant board shows business state, not repeated rules")
	verify(not shell.restaurant._bar.visible,"restaurant has no persistent movement strip")
	check_board(shell);await capture("04-restaurant-quest")
	# Stress a long presentation without inventing orders or altering the business ledger.
	shell.restaurant.set_process(false)
	var before:=shop.snapshot()
	var rows:=PackedStringArray()
	for i: int in 16: rows.append("显示压力样例 %02d · 番茄炒蛋 · 出餐口待取 · 240秒"%(i+1))
	shell.restaurant._order_board.text="\n".join(rows)
	await settle();check_board(shell)
	verify(shell.restaurant._order_scroll.get_v_scroll_bar().visible,"long order text offers scrolling")
	shell.restaurant._order_scroll.scroll_vertical=500
	await settle()
	verify(shell.restaurant._order_scroll.scroll_vertical>0,"long order text actually scrolls")
	verify(shop.snapshot()==before,"presentation stress does not modify business")
	await capture("05-restaurant-scroll")
	shell.restaurant.set_process(true);shell.profile.story.beat="done"
	shell.kitchen_view.kitchen.advance(.2)
	await settle();check_board(shell);await capture("06-restaurant-no-quest")
	root.size=Vector2i(1600,900)
	await settle();check_board(shell);await capture("07-restaurant-resized")
	root.size=Vector2i(1280,800)
	shell.travel("town");shell.town._player.position=shell.town._origin()+Vector2(35.5,36.5)*TDTownWorld.CELL
	await settle()
	verify(not shell.town._status.visible and not shell.town._pack_button.visible,"no duplicate town task or empty backpack")
	verify(not shell.town._target_hint.text.contains("WASD"),"town only describes a nearby target")
	await capture("08-town")
	# Presentation fixture: an already-unlocked home, without writing a real save.
	shell.profile.residence.stage="door";verify(shell.profile.unlock_residence().ok,"fixture home unlocked")
	shell.travel("cottage",true);await settle()
	verify(shell.cottage._prompt.text=="E 保存 / 休息","bed retains save and rest affordance")
	shell.cottage.player.position=Vector2(600,420);await settle()
	verify(shell.cottage._prompt.text.is_empty(),"empty room has no movement instructions")
	await capture("09-cottage")
	shell.travel("town");shell.town.spawn_at_harbor()
	verify(shell.voyage("tokyo").ok,"actual port travel still works")
	await settle()
	verify(shell.visiting._hint.text.contains("港口") and not shell.visiting._hint.text.contains("M 地图"),"travel has one nearby port action")
	await capture("10-travel")
	shell.go_title();app.queue_free();await settle()
	var report:=FileAccess.open(OUT.path_join("report.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures,"captures":captures},"\t"));report.close()
	print("HUD_GPU checks=",checks," failures=",failures," captures=",captures.size())
	quit(0 if failures==0 else 1)
