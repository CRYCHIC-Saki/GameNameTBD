extends SceneTree
## Isolated real-renderer dining flow; no player files are read or written.
const OUT="res://artifacts/d059-r4/gpu"
var checks: int=0
var failed: bool=false
var captures: int=0
var room: TDRestaurantWorld
var shop: TDShopSession

func verify_occlusion(guest: TDRestaurantGuest) -> void:
	# Compare the actual renderer against the same frame without diners. Inspect
	# opaque source pixels, independently of the production occluder polygons.
	room.set_process(false)
	var shown: Array=room._iso.actors.duplicate(true)
	room._iso.actors=[];room._iso.queue_redraw()
	await process_frame;await RenderingServer.frame_post_draw
	var background:=root.get_texture().get_image()
	room._iso.actors=shown;room._iso.queue_redraw()
	await process_frame;await RenderingServer.frame_post_draw
	var composed:=root.get_texture().get_image()
	var seat:=room.layout.piece(guest.seat_id)
	var art:=TDDinerArt.occupied_sprite(guest.appearance_id,guest.character_id)
	var pixels:=art.get_image()
	var box:=TDFurnitureModel.occupied_pose_rect(seat,art,TDDinerArt.occupied_base(guest.appearance_id,guest.character_id))
	var transform:=room._iso.get_global_transform_with_canvas()
	var top: Vector2=transform*box.position
	var bottom: Vector2=transform*box.end
	var hidden_legs: int=0;var visible_legs: int=0;var visible_head: int=0
	for y: int in range(ceili(top.y),floori(bottom.y)):
		for x: int in range(ceili(top.x),floori(bottom.x)):
			if x<0 or y<0 or x>=composed.get_width() or y>=composed.get_height(): continue
			var ratio: Vector2=(Vector2(x+.5,y+.5)-top)/(bottom-top)
			if int(seat.rotation) in [90,270]: ratio.x=1-ratio.x
			var source:=pixels.get_pixelv(Vector2i(ratio*Vector2(pixels.get_size())))
			if source.a<.95: continue
			var before:=background.get_pixel(x,y);var after:=composed.get_pixel(x,y)
			var delta: float=Vector3(before.r-after.r,before.g-after.g,before.b-after.b).length()
			var contrast: float=Vector3(before.r-source.r,before.g-source.g,before.b-source.b).length()
			if ratio.y>.70 and ratio.x>.52 and delta<.015 and contrast>.15: hidden_legs+=1
			if ratio.y>.70 and ratio.x>.52 and delta>.15: visible_legs+=1
			if ratio.y<.50 and delta>.15: visible_head+=1
	check(visible_legs>50,"occupied assembly lower region visible: %d (occluded %d)"%[visible_legs,hidden_legs])
	check(visible_head>200,"head remains in front: "+str(visible_head))
	check(room._iso.seat_is_occupied(guest.seat_id),"original empty stool suppressed for occupied seat")
	room.set_process(true)

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
	room._iso._camera.position=TDFurnitureModel.center(room.layout.piece(guest.seat_id))+Vector2(0,-50)
	room._iso._camera.zoom=Vector2.ONE*2.6
	for rotation: int in [0,90]:
		if rotation==90: check(room.layout.rotate_piece(guest.seat_id).ok,"rotate occupied fixture for visual probe")
		room._place_seated(guest)
		for who: String in ["male","female","aling","chen"]:
			guest.character_id=who if who in ["aling","chen"] else ""
			guest.appearance_id=1 if who=="female" else 0
			room._iso.sync(room._player,room.guest_nodes())
			await process_frame;await capture("seat-%s-%d"%[who,rotation])
			await verify_occlusion(guest)
	guest.character_id=""
	room._iso._camera.zoom=Vector2.ONE*.8
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
