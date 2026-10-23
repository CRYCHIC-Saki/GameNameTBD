extends GutTest
var app: TDApplication
var shell: TDGameShell
var layer: CanvasLayer

func before_each() -> void:
	layer=CanvasLayer.new();layer.layer=130;autofree(layer);get_tree().root.add_child(layer)
	app=load("res://src/app/main.tscn").instantiate()
	app.settings_path="res://artifacts/title-tests/%d/settings.json"%Time.get_ticks_usec()
	layer.add_child(app);shell=app.game_shell;shell.automatic_time=false
	shell.legacy_shop_path=app.settings_path+".old-shop";shell.legacy_research_path=app.settings_path+".old-research"
	await frames()

func after_each() -> void:
	shell.go_title();get_tree().paused=false
	await frames()

func frames() -> void:
	for i: int in 4: await get_tree().process_frame

func button(text: String, parent: Node) -> Button:
	for node: Button in parent.find_children("*","Button",true,false):
		if node.text==text: return node
	return null

func mouse(target: Button) -> void:
	assert_not_null(target)
	if target==null: return
	var at:=target.get_global_rect().get_center()
	for down: bool in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;event.position=at;event.global_position=at
		get_tree().root.push_input(event,true)

func test_real_click_start_creates_once_then_reloads_latest_without_slot_dialog() -> void:
	mouse(button("开始游戏",shell._title_screen))
	assert_true(shell._entry_busy);assert_null(shell._modal)
	assert_string_contains(shell._title_notice.text,"创建")
	mouse(button("开始游戏",shell._title_screen))
	await frames()
	assert_not_null(shell.profile)
	if shell.profile==null: return
	assert_eq(shell.profile.slot_id,"slot-01");assert_eq(shell.location,"town")
	assert_eq(shell.slots.slots().filter(func(r:Dictionary)->bool:return r.ok).size(),1)
	shell.go_title()
	assert_true(shell.create_game("slot-02","第二家食堂").ok)
	assert_true(shell.profile.buy({"egg":1000}).ok)
	assert_true(shell.save_game().ok)
	var money:int=shell.profile.shop.snapshot().money_cents
	shell.go_title();await frames()
	mouse(button("开始游戏",shell._title_screen));await frames()
	assert_null(shell._modal);assert_eq(shell.profile.slot_id,"slot-02")
	assert_eq(shell.profile.title,"第二家食堂");assert_eq(shell.profile.shop.snapshot().money_cents,money)
	assert_eq(shell.profile.shop.available("egg"),1000)

func test_real_click_load_new_empty_slot_and_explicit_load_keep_selection() -> void:
	assert_true(shell.create_game("slot-01","已有食堂").ok);shell.go_title();await frames()
	var existing:=FileAccess.get_file_as_bytes(shell.slots.path_for("slot-01"))
	mouse(button("载入存档",shell._title_screen));await frames()
	assert_null(shell.profile);assert_not_null(shell._modal)
	mouse(button("新建存档",shell._modal_box));await frames()
	assert_true(get_tree().paused)
	mouse(button("从这里开始",shell._modal_box));await frames()
	assert_not_null(shell.profile)
	if shell.profile==null: return
	assert_eq(shell.profile.slot_id,"slot-02");assert_false(get_tree().paused)
	assert_eq(FileAccess.get_file_as_bytes(shell.slots.path_for("slot-01")),existing)
	shell.go_title();await frames()
	mouse(button("载入存档",shell._title_screen));await frames()
	mouse(button("载入",shell._modal_box));await frames()
	assert_eq(shell.profile.slot_id,"slot-01");assert_eq(shell.profile.title,"已有食堂")

func write_invalid(id: String) -> PackedByteArray:
	DirAccess.make_dir_recursive_absolute(shell.profile_root)
	var file:=FileAccess.open(shell.slots.path_for(id),FileAccess.WRITE);file.store_string("{broken-save");file.close()
	return FileAccess.get_file_as_bytes(shell.slots.path_for(id))

func test_start_never_overwrites_corrupt_slot_and_uses_next_empty() -> void:
	var original:=write_invalid("slot-01")
	mouse(button("开始游戏",shell._title_screen));await frames()
	assert_not_null(shell.profile)
	if shell.profile!=null: assert_eq(shell.profile.slot_id,"slot-02")
	assert_eq(FileAccess.get_file_as_bytes(shell.slots.path_for("slot-01")),original)

func test_full_invalid_slots_show_error_on_title_without_creating_or_overwriting() -> void:
	for i:int in range(1,7): write_invalid("slot-%02d"%i)
	mouse(button("开始游戏",shell._title_screen));await frames()
	assert_null(shell.profile);assert_false(shell._entry_busy)
	assert_string_contains(shell._title_notice.text,"恢复")
	for row:Dictionary in shell.slots.slots(): assert_eq(row.code,"INVALID_JSON")

func test_write_failure_shows_visible_reason_then_retry_works() -> void:
	shell.slots.interrupt_at="after_temp"
	mouse(button("载入存档",shell._title_screen));await frames()
	mouse(button("新建存档",shell._modal_box));await frames()
	mouse(button("从这里开始",shell._modal_box));await frames()
	assert_null(shell.profile);assert_false(shell._entry_busy)
	assert_string_contains(shell._notice.text,"无法进入游戏")
	assert_string_contains(shell._notice.text,"INTERRUPTED")
	assert_true(shell._notice.is_visible_in_tree())
	assert_eq(shell.slots.load_slot("slot-01").code,"INTERRUPTED_SAVE")
	shell.slots.interrupt_at="";shell.show_slots(true);await frames()
	mouse(button("从这里开始",shell._modal_box));await frames()
	assert_not_null(shell.profile)
	if shell.profile!=null: assert_eq(shell.profile.slot_id,"slot-02")
	assert_eq(shell.slots.load_slot("slot-01").code,"INTERRUPTED_SAVE")
