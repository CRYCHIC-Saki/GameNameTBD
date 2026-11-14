extends SceneTree
## Isolated runtime screenshots; never opens a player's real settings or slots.
const OUT: String="res://artifacts/restaurant-art/gpu"
var checks: int=0
var failed: bool=false

func _initialize() -> void: call_deferred("run")

func check(value: bool, note: String) -> void:
	checks+=1
	print(("PASS " if value else "FAIL ")+note)
	if not value: failed=true

func capture(name: String) -> void:
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OUT.path_join(name+".png"))==OK,"capture "+name)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size=Vector2i.ZERO
	root.size=Vector2i(1600,650)
	var sheet:=Control.new();sheet.theme=TDUI.theme();root.add_child(sheet)
	var background:=ColorRect.new();background.color=Color("263d38");background.size=Vector2(root.size);sheet.add_child(background)
	var names: Array[String]=["中式 · 酒楼","日式 · 居酒屋","欧式 · 饭店","东南亚 · 小馆","墨西哥 · 餐厅"]
	var at: int=0
	for town: String in TDTravelCatalog.IDS:
		var texture: Texture2D=TDTravelCatalog.RESTAURANTS[town]
		var image: Image=texture.get_image()
		if image.is_compressed(): image.decompress()
		check(image.get_pixel(0,0).a==0 and image.get_pixel(image.get_width()-1,image.get_height()-1).a==0,"transparent corners "+town)
		check(image.get_used_rect().has_area(),"nonempty facade "+town)
		var view:=TextureRect.new();view.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		view.texture=texture;view.position=Vector2(at*320+10,70);view.size=Vector2(300,500)
		view.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		view.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;sheet.add_child(view)
		var label:=Label.new();label.text=names[at];label.position=Vector2(at*320+10,590);label.size=Vector2(300,36);label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		sheet.add_child(label)
		var virtual: Texture2D=TDTravelCatalog.sprite(town,0)
		check(is_equal_approx(virtual.get_width()/float(virtual.get_height()),1.5),"legacy collision canvas "+town)
		at+=1
	await capture("five-restaurants")
	sheet.queue_free();await process_frame
	root.size=Vector2i(1280,800)
	var app: TDApplication=load("res://src/app/main.tscn").instantiate()
	app.settings_path="res://artifacts/restaurant-art/isolated/%d/settings.json"%Time.get_ticks_usec();root.add_child(app)
	var shell: TDGameShell=app.game_shell;shell.automatic_time=false
	await process_frame
	check(shell.create_game("slot-01","店铺贴图检查").ok,"isolated new profile")
	shell.guide.dialogue.finish_now();shell.profile.story.beat="done";shell.profile.characters.clock.minute=720
	check(shell.travel("town").ok,"enter main town")
	var plot: Dictionary=shell.profile.world.town_map._by_id("player_diner")
	shell.town._player.position=shell.town._origin()+Vector2(float(plot.x)+float(plot.w)*.5,float(plot.y)+float(plot.h)+1)*shell.town.CELL
	shell.town._camera.zoom=Vector2.ONE
	await capture("chengdu-in-game")
	shell.town.spawn_at_harbor()
	var before: Dictionary=shell.profile.snapshot()
	for town: String in ["tokyo","paris","bangkok","mexico_city"]:
		check(shell.voyage(town).ok,"travel "+town)
		await process_frame
		var visitor: TDTravelWorld=shell.visiting
		var restaurants: Array=visitor._buildings.filter(func(entry:Dictionary)->bool:return entry.plot.get("kind")=="competitor")
		check(not restaurants.is_empty(),"restaurant present "+town)
		if not restaurants.is_empty():
			visitor.player.position=Vector2(restaurants[0].feet)*48+Vector2(0,48)
			visitor.camera.zoom=Vector2.ONE
		await capture(town+"-in-game")
		visitor.player.position=(Vector2(TDTravelCatalog.port(town))+Vector2.ONE*.5)*48
	check(shell.voyage("chengdu").ok,"return home")
	check(shell.profile.snapshot()==before,"travel preserves gameplay state")
	shell._dispose_game();app.queue_free();await process_frame;await process_frame
	var file:=FileAccess.open(OUT.path_join("summary.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"status":"FAIL" if failed else "PASS","checks":checks,"human_playtest":"PENDING"}));file.close()
	quit(1 if failed else 0)
