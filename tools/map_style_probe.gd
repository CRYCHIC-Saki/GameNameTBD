extends SceneTree
## Actual isolated map captures plus a palette/asset overview.
const OUT: String="res://artifacts/map-style/gpu"
var checks: int=0
var failed: bool=false
var capture_shell: TDGameShell

func _initialize() -> void: call_deferred("run")
func check(value: bool,note: String) -> void:
	checks+=1;print(("PASS " if value else "FAIL ")+note)
	if not value: failed=true
func capture(name: String) -> void:
	await process_frame;await process_frame
	# Hidden capture windows can receive focus-loss pause notifications.
	# Dismiss only that isolated probe's temporary overlay before the screenshot.
	if capture_shell!=null and capture_shell._modal!=null:
		capture_shell._close_dialog();paused=false;await process_frame
	if capture_shell!=null: check(capture_shell._modal==null,"unobstructed "+name)
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OUT.path_join(name+".png"))==OK,"capture "+name)
func art(parent: Control,texture: Texture2D,rect: Rect2) -> void:
	var view:=TextureRect.new();view.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;view.texture=texture
	view.position=rect.position;view.size=rect.size;view.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	view.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;parent.add_child(view)
func surface(town: String,index: int) -> Texture2D:
	var image:=Image.create(120,120,false,Image.FORMAT_RGBA8)
	TDTownScenery.paint(image,Rect2i(0,0,120,120),index,town)
	return ImageTexture.create_from_image(image)
func patch(parent: Control,texture: Texture2D,rect: Rect2) -> void:
	var view:=TextureRect.new();view.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;view.texture=texture
	view.position=rect.position;view.size=rect.size;view.stretch_mode=TextureRect.STRETCH_TILE
	view.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;parent.add_child(view)
func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED;root.content_scale_size=Vector2i.ZERO
	root.size=Vector2i(1600,760)
	var sheet:=Control.new();sheet.theme=TDUI.theme();root.add_child(sheet)
	var background:=ColorRect.new();background.color=Color("233a34");background.size=Vector2(root.size);sheet.add_child(background)
	var names: Array[String]=["中式 · 青瓦石巷","日式 · 木屋石径","欧式 · 浅石街区","东南亚 · 热带砂岩","墨西哥 · 陶土街区"]
	var i: int=0
	for town: String in TDTravelCatalog.IDS:
		var x: float=i*320+10
		patch(sheet,surface(town,0),Rect2(x,90,300,490))
		patch(sheet,surface(town,1),Rect2(x,580,300,120))
		art(sheet,TDTravelCatalog.RESTAURANTS[town],Rect2(x+15,100,270,300))
		art(sheet,TDEnvironmentArt.residential(0) if town=="chengdu" else TDTravelCatalog.sprite(town,1),Rect2(x+8,390,195,180))
		art(sheet,TDTownArt.sprite(3) if town=="chengdu" else TDTravelCatalog.prop(town,false),Rect2(x+200,390,95,180))
		var label:=Label.new();label.text=names[i];label.position=Vector2(x,35);label.size=Vector2(300,32);label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;sheet.add_child(label)
		check(surface(town,1).get_image().get_pixel(20,20).a==1,"opaque road "+town)
		for column: int in [0,1,2,3]:
			var tex: Texture2D=TDTravelCatalog.sprite(town,column)
			check(is_equal_approx(tex.get_width()/float(tex.get_height()),1.5),"collision canvas "+town+":"+str(column))
		i+=1
	for index: int in 16:
		var texture: AtlasTexture=TDTownArt.sprite(index)
		check(texture.region.has_area() and Rect2(Vector2.ZERO,texture.atlas.get_size()).encloses(texture.region),"main atlas region "+str(index))
	for index: int in 4:
		check(TDEnvironmentArt.residential(index).region.has_area(),"residential region "+str(index))
	for index: int in 2:
		check(TDHarbor.texture(index).get_width()>32,"harbor region "+str(index))
	await capture("five-regions-style")
	sheet.queue_free();await process_frame
	root.size=Vector2i(1280,800)
	var app: TDApplication=load("res://src/app/main.tscn").instantiate()
	app.settings_path="res://artifacts/map-style/isolated/%d/settings.json"%Time.get_ticks_usec();root.add_child(app)
	var shell: TDGameShell=app.game_shell;capture_shell=shell;shell.automatic_time=false;await process_frame
	check(shell.create_game("slot-01","地图画风检查").ok,"isolated profile")
	shell.guide.dialogue.finish_now();shell.profile.story.beat="done";shell.profile.characters.clock.minute=720
	check(shell.travel("town").ok,"enter main town")
	var map: TDTownMap=shell.profile.world.town_map
	var before: Dictionary=shell.profile.snapshot()
	for id: String in ["player_diner","urban_village","rich_district","market-small"]:
		var plot: Dictionary=map._by_id(id)
		shell.town._player.position=shell.town._origin()+Vector2(float(plot.x)+float(plot.w)*.5,float(plot.y)+float(plot.h)+1)*shell.town.CELL
		shell.town._camera.zoom=Vector2.ONE*.75
		await capture("chengdu-"+id)
	shell.town.spawn_at_harbor();await capture("chengdu-harbor")
	for town: String in ["tokyo","paris","bangkok","mexico_city"]:
		check(shell.voyage(town).ok,"travel "+town);await process_frame
		var visitor: TDTravelWorld=shell.visiting
		visitor.camera.zoom=Vector2.ONE*.75
		await capture(town+"-port")
		var plaza: Dictionary=visitor.map._by_id("plaza")
		visitor.player.position=(Vector2(plaza.approach_x,plaza.approach_y)+Vector2.ONE*.5)*48
		await capture(town+"-streets")
		visitor.player.position=(Vector2(TDTravelCatalog.port(town))+Vector2.ONE*.5)*48
	check(shell.voyage("chengdu").ok,"return home")
	check(shell.profile.snapshot()==before,"all map views preserve state")
	shell._dispose_game();app.queue_free();await process_frame;await process_frame
	var file:=FileAccess.open(OUT.path_join("summary.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"status":"FAIL" if failed else "PASS","checks":checks,"human_playtest":"PENDING"}));file.close()
	quit(1 if failed else 0)
