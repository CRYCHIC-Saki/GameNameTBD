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

func test_real_click_start_creates_once_and_continue_reloads_latest() -> void:
	mouse(button("开始游戏",shell._title_screen))
	assert_true(shell._entry_busy);assert_null(shell._modal)
	assert_string_contains(shell._title_notice.text,"创建")
	mouse(button("开始游戏",shell._title_screen))
	await frames()
	assert_not_null(shell.profile)
	if shell.profile==null: return
	assert_eq(shell.profile.slot_id,"slot-01");assert_eq(shell.location,"town")
	assert_eq(shell.slots.slots().filter(func(r:Dictionary)->bool:return r.ok).size(),0)
	shell.guide.dialogue.finish_now()
	shell._sleep("chengdu",0)
	shell.go_title()
	assert_true(shell.create_game("slot-02","第二家食堂",false).ok);shell.guide.dialogue.finish_now()
	assert_true(shell.profile.buy({"egg":1000}).ok)
	shell._sleep("chengdu",0)
	var money:int=shell.profile.shop.snapshot().money_cents
	shell.go_title();await frames()
	mouse(button("继续游戏",shell._title_screen));await frames()
	assert_null(shell._modal);assert_eq(shell.profile.slot_id,"slot-02")
	assert_eq(shell.profile.title,"第二家食堂");assert_eq(shell.profile.shop.snapshot().money_cents,money)
	assert_eq(shell.profile.shop.available("egg"),1000)
	shell.go_title();await frames()
	mouse(button("开始游戏",shell._title_screen));await frames()
	assert_eq(shell.profile.slot_id,"slot-03");assert_eq(shell.profile.story.revised.cursor,0)

func test_real_click_load_new_empty_slot_and_explicit_load_keep_selection() -> void:
	assert_true(shell.create_game("slot-01","已有食堂",false).ok);shell.guide.dialogue.finish_now()
	shell._sleep("chengdu",0);shell.go_title();await frames()
	var path := shell.slots.path_for("slot-01",TDProfileStore.DAILY)
	var existing:=FileAccess.get_file_as_bytes(path)
	mouse(button("载入存档",shell._title_screen));await frames()
	assert_null(shell.profile);assert_not_null(shell._modal)
	mouse(button("新建存档",shell._modal_box));await frames()
	assert_true(get_tree().paused)
	mouse(button("从这里开始",shell._modal_box));await frames()
	assert_not_null(shell.profile)
	if shell.profile==null: return
	assert_eq(shell.profile.slot_id,"slot-02");assert_false(get_tree().paused)
	assert_eq(FileAccess.get_file_as_bytes(path),existing)
	shell.go_title();await frames()
	mouse(button("载入存档",shell._title_screen));await frames()
	mouse(button("每日存档 · 第 2 天",shell._modal_box));await frames()
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
	assert_string_contains(shell._title_notice.text,"删除")
	for row:Dictionary in shell.slots.slots(): assert_eq(row.code,"INVALID_JSON")

func test_start_has_no_write_then_sleep_failure_can_retry() -> void:
	shell.slots.interrupt_at="after_temp"
	mouse(button("载入存档",shell._title_screen));await frames()
	mouse(button("新建存档",shell._modal_box));await frames()
	mouse(button("从这里开始",shell._modal_box));await frames()
	assert_not_null(shell.profile);assert_false(shell._entry_busy)
	assert_eq(shell.slots.load_slot("slot-01").code,"NOT_FOUND")
	shell.guide.dialogue.finish_now()
	shell._sleep("chengdu",0)
	assert_not_null(button("重试保存",shell._modal_box))
	assert_eq(shell.slots.load_slot("slot-01").code,"INTERRUPTED_SAVE")

	shell.slots.interrupt_at=""
	await frames()
	mouse(button("重试保存",shell._modal_box));await frames()
	assert_not_null(shell.profile)
	if shell.profile!=null: assert_eq(shell.profile.slot_id,"slot-01")
	assert_true(shell.slots.load_slot("slot-01",TDProfileStore.DAILY).ok)

func test_load_menu_delete_confirmation_cancel_and_freed_slot() -> void:
	assert_true(shell.create_game("slot-01","临海小店",false).ok);shell.guide.dialogue.finish_now()
	shell._sleep("chengdu",0);shell.go_title();await frames()
	var path := shell.slots.path_for("slot-01",TDProfileStore.DAILY)
	var bytes:=FileAccess.get_file_as_bytes(path)
	shell.show_slots(false);await frames();mouse(button("删除",shell._modal_box));await frames()
	assert_not_null(button("确认删除",shell._modal_box))
	mouse(button("取消",shell._modal_box));await frames()
	assert_eq(FileAccess.get_file_as_bytes(path),bytes)
	mouse(button("删除",shell._modal_box));await frames();mouse(button("确认删除",shell._modal_box));await frames()
	assert_eq(shell.slots.load_slot("slot-01").code,"NOT_FOUND")
	assert_null(button("删除",shell._modal_box))
	shell._close_dialog();mouse(button("开始游戏",shell._title_screen));await frames()
	assert_eq(shell.profile.slot_id,"slot-01");assert_eq(shell.profile.story.revised.cursor,0)
