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
	if app!=null: app.queue_free()
	await frames()
	print("TITLE_PROBE success=",not failed," checks=",checks)
	quit(1 if failed else 0)

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
	check(shell.location=="town" and shell.profile.slot_id=="slot-01","new slot spawns outside restaurant")
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
	check(FileAccess.get_file_as_bytes(shell.slots.path_for("slot-01"))==first,"first slot remains untouched")
	check(shell.profile.buy({"egg":1000}).ok,"second profile can buy inventory")
	check(shell.save_game().ok,"second profile saves")
	var money:int=shell.profile.shop.snapshot().money_cents
	shell.go_title();await frames()
	await click("开始游戏",shell._title_screen)
	check(shell.profile!=null and shell._modal==null,"start enters game without slot chooser")
	if failed: await finish();return
	check(shell.profile.slot_id=="slot-02","start opens most recently saved slot")
	check(shell.profile.shop.snapshot().money_cents==money and shell.profile.shop.available("egg")==1000,"inventory and money survived reload")
	check(shell.slots.slots().filter(func(row:Dictionary)->bool:return row.ok).size()==2,"start did not create a third slot")
	shell.go_title();await frames()
	await click("载入存档",shell._title_screen)
	await capture("saved-slots")
	await click("载入",shell._modal_box)
	check(shell.profile!=null,"explicit load works")
	if shell.profile!=null: check(shell.profile.slot_id=="slot-01","load menu selects the requested older slot")
	if not failed: await check_room_movement()
	await finish()

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
	check(room.player_position().x>before.x+30,"real movement input crosses the clear aisle")
	await capture("restaurant-clear-aisle")
	shell.travel("kitchen");await physics_frames(2)
	var kitchen:=shell.kitchen_view.kitchen.world
	kitchen._player.position=Vector2(500,450)
	check(kitchen._player.move_and_collide(Vector2(300,0))==null,"restaurant and town cannot block kitchen floor")
	kitchen._player.position=Vector2(640,320)
	check(kitchen._player.move_and_collide(Vector2(0,-150))!=null,"kitchen counter remains solid")
	await capture("kitchen-walk")
