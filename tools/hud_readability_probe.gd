extends SceneTree
## Actual Shell/scenes; isolated profile. Long labels below are presentation-only stress fixtures.
const OUT: String="res://artifacts/hud-readability-20261115/gpu"
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
	verify(is_equal_approx(world.scale.x,.71875),"actual embedded kitchen scale")
	await capture("01-kitchen-quest")
	# Freeze only presentation refresh for reproducible long-label / night fixtures.
	shell.kitchen_view.set_process(false)
	world.set_context({"hand":{"name":"番茄","shape":"dice","kind":"ingredient"}},"这口锅已经开火，不能取回原料；可以继续烹饪或整锅丢弃。")
	world.pot_contents=[{"title":"左锅 · 待烹饪","materials":"番茄（小丁）＋鸡蛋＋牛肉＋土豆"},{"title":"右锅 · 空锅","materials":"E 放入食材 · F 开始"}]
	world.simmer_meters=[{"name":"汽锅鸡","ratio":.82,"remaining_sec":38.2},{"name":"第二锅","ratio":.61,"remaining_sec":25.8}]
	world._update_pot_signs()
	await settle()
	for label: Label in [world._held_label,world._pot_materials[0],world._prompt]:
		verify(label.get_theme_color("font_color")==TDUI.INK,"kitchen text uses dark ink on wood")
		verify((label.get_parent() as Control).get_global_rect().encloses(label.get_global_rect()),"kitchen label stays within panel")
	verify(not shell.guide._card.get_global_rect().intersects(world._held_label.get_parent().get_global_rect()),"quest and held hint do not overlap")
	for panel: PanelContainer in world._pot_panels:
		verify(not shell.guide._card.get_global_rect().intersects(panel.get_global_rect()),"quest and pot hint do not overlap")
	for child: Node in world._hud.get_children():
		if str(child.name).begins_with("StationSign_"):
			verify(not child.get_global_rect().intersects(world._held_label.get_parent().get_global_rect()),"held hint avoids "+str(child.name))
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
	shell.profile.characters.clock.minute=480;shell.kitchen_view.set_process(true)
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
	shell.go_title();app.queue_free();await settle()
	var report:=FileAccess.open(OUT.path_join("report.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures,"captures":captures},"\t"));report.close()
	print("HUD_GPU checks=",checks," failures=",failures," captures=",captures.size())
	quit(0 if failures==0 else 1)
