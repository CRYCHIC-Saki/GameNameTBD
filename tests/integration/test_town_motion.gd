extends GutTest
var app: TDApplication
var shell: TDGameShell

func before_each() -> void:
	app=load("res://src/app/main.tscn").instantiate()
	app.settings_path="res://artifacts/movement-tests/%d/settings.json"%Time.get_ticks_usec()
	add_child_autofree(app);shell=app.game_shell;shell.automatic_time=false
	assert_true(shell.create_game("slot-01").ok)
	shell.travel("restaurant")
	await wait_physics_frames(2)

func after_each() -> void:
	for action:String in ["world_left","world_right","world_up","world_down"]: Input.action_release(action)
	shell.go_title();get_tree().paused=false
	await get_tree().process_frame

func test_every_open_neighbor_in_real_restaurant_ignores_hidden_worlds() -> void:
	var room:=shell.restaurant;var body:=room._player;var layout:=room.layout
	var blocked:Array[String]=[];var traversed:int=0
	for y:int in range(1,layout.rows-1):
		for x:int in range(1,layout.columns-1):
			if not layout.is_walkable(x,y): continue
			for delta:Vector2i in [Vector2i.RIGHT,Vector2i.DOWN]:
				var destination:=Vector2i(x,y)+delta
				if not layout.is_walkable(destination.x,destination.y): continue
				room.teleport_player(Vector2i(x,y))
				var hit:=body.move_and_collide(Vector2(delta)*layout.cell_px)
				traversed+=1
				if hit!=null:
					blocked.append("%s->%s: %s"%[Vector2i(x,y),destination,hit.get_collider().get_path()])
	assert_gt(traversed,100)
	print("RESTAURANT_WALK_EDGES checked=",traversed," blocked=",blocked.size())
	assert_eq(blocked.size(),0,"Phantom walls (%d): %s"%[blocked.size(),str(blocked.slice(0,8))])

func test_empty_zones_walk_but_tables_walls_and_rebuild_remain_physical() -> void:
	var room:=shell.restaurant;var layout:=room.layout
	# The original new profile leaves an empty ordering cell after removing the kiosk.
	assert_eq(layout.cell_zone(5,3),"ordering")
	assert_true(layout.is_walkable(5,3),"Empty marked floor is not furniture")
	room.teleport_player(Vector2i(4,3))
	assert_null(room._player.move_and_collide(Vector2(64,0)))
	var table:Dictionary=layout.piece_by_kind("dining_table")
	var adjacent:=Vector2i(int(table.x)-1,int(table.y))
	room.teleport_player(adjacent)
	var hit:=room._player.move_and_collide(Vector2(128,0))
	assert_not_null(hit,"Actual table must still block")
	if hit!=null: assert_same(hit.get_collider(),room._blockers)
	assert_lt(room._player.position.x,float(table.x)*64.0)
	assert_true(layout.remove_piece(table.id).ok);room._rebuild()
	await wait_physics_frames(2)
	room.teleport_player(adjacent)
	assert_null(room._player.move_and_collide(Vector2(128,0)),"Removed furniture leaves no ghost collider")
	room.teleport_player(Vector2i(1,8))
	hit=room._player.move_and_collide(Vector2(-90,0))
	assert_not_null(hit,"Room boundary remains solid")
	if hit!=null: assert_same(hit.get_collider(),room._blockers)
	var restored:=TDRestaurantLayout.import_dict(layout.to_dict(),room.catalog)
	assert_not_null(restored)
	if restored!=null: assert_eq(restored.to_dict(),layout.to_dict())
	# Moving a real table updates both its former floor and the new solid footprint.
	var another:Dictionary=layout.piece_by_kind("dining_table")
	for y:int in range(8,10):
		for x:int in range(8,10): assert_true(layout.paint(x,y,"D").ok)
	assert_true(layout.move_piece(another.id,8,8).ok);room._rebuild()
	await wait_physics_frames(2)
	assert_true(layout.is_walkable(int(another.x),int(another.y)))
	room.teleport_player(Vector2i(7,8))
	assert_not_null(room._player.move_and_collide(Vector2(128,0)))

func test_real_input_and_repeated_room_switches_keep_passages_clear() -> void:
	var room:=shell.restaurant;var kitchen:=shell.kitchen_view.kitchen.world
	for cycle:int in 3:
		shell.travel("kitchen");await wait_physics_frames(2)
		kitchen._player.position=Vector2(500,450)
		assert_null(kitchen._player.move_and_collide(Vector2(300,0)),"Other rooms cannot block the kitchen")
		kitchen._player.position=Vector2(640,320)
		assert_not_null(kitchen._player.move_and_collide(Vector2(0,-150)),"Kitchen counter still blocks")
		shell.travel("restaurant");room.teleport_player(Vector2i(6,8));await wait_physics_frames(2)
		var before:=room.player_position()
		Input.action_press("world_right");await wait_physics_frames(12);Input.action_release("world_right")
		assert_gt(room.player_position().x,before.x+30.0,"WASD moves in a clear passage")
		var old_screen:=TDRestaurantIsoView.project(before.x/64.0,before.y/64.0)
		var new_screen:=TDRestaurantIsoView.project(room.player_position().x/64.0,room.player_position().y/64.0)
		assert_almost_eq(new_screen.y,old_screen.y,.1,"D moves horizontally on screen")
		get_tree().paused=true;before=room.player_position()
		Input.action_press("world_down");await wait_physics_frames(3);Input.action_release("world_down")
		assert_eq(room.player_position(),before);get_tree().paused=false

func test_visible_chef_feet_match_physical_origin_projection() -> void:
	var room:=shell.restaurant
	for cell:Vector2i in [Vector2i(1,1),Vector2i(6,8),Vector2i(7,4)]:
		room.teleport_player(cell)
		var rect:=room._iso.chef_rect(room.player_position())
		var texture:=TDChefArt.texture(room._player.facing)
		var used:=texture.get_image().get_used_rect()
		var visible_bottom:=rect.position.y+float(used.end.y)*rect.size.y/texture.get_height()
		var expected:=TDRestaurantIsoView.project(cell.x+.5,cell.y+.5)
		assert_almost_eq(visible_bottom,expected.y,.001)
		assert_almost_eq(rect.get_center().x,expected.x,.001)
