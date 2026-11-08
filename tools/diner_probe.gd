extends SceneTree
## Isolated real-renderer dining flow; no player files are read or written.
const OUT="res://artifacts/diner-flow/gpu"
var checks: int=0
var failed: bool=false
var captures: int=0
var room: TDRestaurantWorld
var shop: TDShopSession

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	checks+=1
	print("DINER_CHECK ",checks," ","PASS " if value else "FAIL ",message)
	if not value: failed=true

func capture(id: String) -> void:
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OUT.path_join(id+".png"))==OK,"capture "+id)
	captures+=1

func run() -> void:
	if DisplayServer.get_name()=="headless": quit(1);return
	root.size=Vector2i(1280,800)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var catalog:=TDServiceCatalog.new();check(catalog.load_file().ok,"catalog")
	shop=TDShopSession.new(catalog,"dining-gpu",59)
	var stock: Dictionary=shop.offer("service.tomato_egg").stock.duplicate(true)
	for id: String in stock: stock[id]=int(stock[id])*3
	check(shop.buy(stock,"stock").ok,"real inventory")
	for id: String in shop.snapshot().menu: check(shop.set_menu(id,id=="service.tomato_egg",1200).ok,"menu "+id)
	room=TDRestaurantWorld.new();room.player_mode=true;room.floor_service=true;room.business=shop
	root.add_child(room);room.bind_dining_clock()
	room._iso.follow_player=false
	room._iso._camera.position=TDRestaurantIsoView.project(room.layout.columns*.5,room.layout.rows*.5)+Vector2(0,-60)
	room._iso._camera.zoom=Vector2.ONE*.8
	await process_frame
	check(shop.open_day().ok and shop.advance(1).ok,"actual arrival")
	shop._arrive();room.advance_dining(0)
	check(room.guest_nodes().size()==2 and shop.active_orders().is_empty(),"two walking guests, no kitchen orders yet")
	var guest:=room.guest_nodes()[0]
	for index: int in 8:
		check(shop.advance(.13).ok,"walking tick")
		await process_frame
		await capture("walk-%02d"%index)
	check(shop.advance(guest.walking_seconds()).ok,"arrive at table")
	check(guest.phase=="sitting","begins sitting")
	for index: int in 4:
		check(shop.advance(.175).ok,"sitting tick")
		await process_frame
		await capture("sit-%02d"%index)
	check(guest.seated and shop.active_orders().size()>=1,"seated diner publishes order")
	var label:=shop.order_label(guest.ticket_id)
	check(guest.dish_name.contains(label),"front room identifies the same order")
	room.set_floor_cover(true)
	var kitchen:=TDShopView.new();kitchen.service=catalog;kitchen.shop=shop;kitchen.embedded=true
	kitchen.save_path=OUT.path_join("isolated-save.json");root.add_child(kitchen);kitchen.kitchen.auto_advance=false
	kitchen.refresh();await process_frame;await capture("kitchen-order")
	var text: String=""
	for node: Label in kitchen._sidebar.find_children("*","Label",true,false): text+=node.text
	check(text.contains(label) and text.contains("番茄炒蛋"),"real kitchen sidebar matches diner")
	kitchen.close();kitchen.queue_free();room.set_floor_cover(false);await process_frame
	var gallery:=CanvasLayer.new();gallery.layer=100;root.add_child(gallery)
	var backdrop:=ColorRect.new();backdrop.color=Color("253b34");backdrop.size=Vector2(1280,800);gallery.add_child(backdrop)
	for variant: int in TDDinerArt.VARIANTS:
		var title:=Label.new();title.text=("男食客" if variant%2==0 else "女食客")+" · "+["青绿","赭黄","豆沙"][variant/2]
		title.position=Vector2(30+variant*210,20);gallery.add_child(title)
		for direction: int in 4:
			var sprite:=TextureRect.new();sprite.texture=TDDinerArt.sprite(variant,[Vector2i.DOWN,Vector2i.UP,Vector2i.LEFT,Vector2i.RIGHT][direction],0)
			sprite.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;sprite.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;sprite.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
			gallery.add_child(sprite)
			sprite.position=Vector2(30+variant*210,55+direction*130);sprite.size=Vector2(130,120)
		var seated:=TextureRect.new();seated.texture=TDDinerArt.sprite(variant,Vector2i.DOWN,-1,true)
		seated.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;seated.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;seated.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		gallery.add_child(seated)
		seated.position=Vector2(30+variant*210,590);seated.size=Vector2(130,120)
	await process_frame;await capture("diner-clothing-directions")
	gallery.queue_free();room.close();room.queue_free();await process_frame;await process_frame
	print("DINER_GPU success=",not failed," checks=",checks," captures=",captures)
	quit(1 if failed else 0)
