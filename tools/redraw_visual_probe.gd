extends SceneTree
## Isolated production renderer acceptance captures. Never opens a real player slot.
const OUT: String="res://artifacts/style-redraw/visual"
var captures: Array[String]=[]
var checks: int=0
var failures: Array[String]=[]
var board: Control

func _initialize() -> void: call_deferred("run")

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures.append(label);push_error(label)

func clear_board() -> void:
	if board!=null: board.free()
	board=Control.new();board.set_anchors_preset(Control.PRESET_FULL_RECT);root.add_child(board)
	var bg:=ColorRect.new();bg.color=Color("24333d");bg.size=Vector2(1280,800);board.add_child(bg)

func label_at(text: String,at: Vector2,width: float=200) -> void:
	var label:=Label.new();label.text=text;label.position=at;label.size.x=width
	label.add_theme_font_size_override("font_size",15);board.add_child(label)

func tile(art: Texture2D,box: Rect2) -> void:
	check(art!=null and art.get_width()>5 and art.get_height()>5,"nonempty art "+str(checks))
	if art==null: return
	var view:=TextureRect.new();view.texture=art;view.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	view.position=box.position;view.size=box.size;view.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
	board.add_child(view)

func capture(id: String) -> void:
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OUT.path_join(id+".png"))==OK,"capture "+id)
	captures.append(id);print("REDRAW_CAPTURE ",id)

func run() -> void:
	root.size=Vector2i(1280,800)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var index:=TDRedrawArt.catalog()
	check(index.ingredient_ids.size()==148,"148 ingredients")
	check(index.dish_ids.size()==100,"100 dishes")
	for who: String in ["hero","aling","chen","luo"]:
		clear_board();label_at(who+" — reference expression variants",Vector2(18,8),800)
		var dimensions:=Vector2.ZERO
		for i: int in 6:
			var art:=TDStoryArt.portrait(who,TDRedrawArt.EMOTIONS[i])
			if i==0: dimensions=art.get_size()
			check(art.get_size()==dimensions,"fixed canvas "+who+str(i))
			tile(art,Rect2(12+i*211,46,198,710));label_at(TDRedrawArt.EMOTIONS[i],Vector2(22+i*211,770))
		await capture("expressions-"+who)
	for category: String in ["ingredients","dishes"]:
		var ids: Array=index.ingredient_ids if category=="ingredients" else index.dish_ids
		var count: int=30 if category=="ingredients" else 20
		var columns: int=6 if category=="ingredients" else 5
		var height: int=150 if category=="ingredients" else 185
		for page: int in 5:
			clear_board();label_at(category+" / "+str(page+1),Vector2(16,4),800)
			for i: int in mini(count,ids.size()-page*count):
				var id: String=ids[page*count+i]
				var art:=TDRedrawArt.ingredient(id) if category=="ingredients" else TDRedrawArt.dish(id)
				var at:=Vector2(12+(i%columns)*(1260/columns),35+(i/columns)*height)
				tile(art,Rect2(at,Vector2(1260/columns-14,height-27)));label_at(id,at+Vector2(0,height-26),1260/columns)
			await capture(category+"-"+str(page))
	clear_board()
	for i: int in 8: tile(TDStoryArt.prop(i),Rect2(18+(i%4)*315,25+(i/4)*385,295,350))
	await capture("story-props")
	clear_board()
	for i: int in 4: tile(TDStoryArt.background(i),Rect2((i%2)*640,(i/2)*400,640,400))
	await capture("backgrounds")
	clear_board()
	for i: int in 12:
		var at:=Vector2(16+(i%4)*315,12+(i/4)*260)
		var who: String=["hero","aling","chen"][i/4]
		var face: Vector2i=[Vector2i.DOWN,Vector2i.UP,Vector2i.LEFT,Vector2i.RIGHT][i%4]
		tile(TDChefArt.texture(face,0) if who=="hero" else TDStoryArt.sprite(who,face,2),Rect2(at,Vector2(280,230)))
	await capture("walking-characters")
	clear_board()
	for i: int in 4: tile(TDDinerArt.occupied_sprite(i%2,"aling" if i==2 else ("chen" if i==3 else "")),Rect2(20+(i%2)*630,10+(i/2)*400,600,370))
	await capture("seated-characters")
	board.free();board=null
	var view:=TDDialogueView.new();root.add_child(view);await process_frame
	for who: String in ["aling","chen","luo"]:
		var talk:=TDDialogue.new();talk.story_layout("焰子",who)
		talk.add_line("焰子","hero","今天也要用热腾腾的料理，迎接来到小镇的每一位客人。","happy")
		talk.add_line({"aling":"阿铃","chen":"灰烬司祭","luo":"罗厄"}[who],who,"那就开始吧！","puzzled")
		view.present(talk);view.set_process(false);talk.click();talk.click();talk.click();view._refresh()
		check(view._panel.z_index>view._portrait.z_index and view._panel.z_index>view._right_portrait.z_index,"portraits behind box "+who)
		check(view._body.position.x==36,"full width text "+who)
		await capture("vn-"+who)
		view.finish_now()
	var seen: Dictionary={}
	for sequence: Array in TDOpeningScript.data().scenes.values():
		for row: Dictionary in sequence:
			if row.kind!="cg" or seen.has(row.cg): continue
			seen[row.cg]=true
			var talk:=TDDialogue.new();talk.add_cg(row.cg,"",row.duration);view.present(talk);view.set_process(false)
			talk.cg_elapsed=row.duration*.55;view._refresh();await capture("cg-"+row.cg);view.finish_now()
	var intro:=TDOpeningScript.conversation("intro","焰子",80);view.present(intro);view.set_process(false)
	intro.tick(14);intro.click();view._refresh()
	check(view._portrait.visible and not view._right_portrait.visible,"intro hides Aling before entrance")
	check(not view._cg.visible and view._vn_background.visible,"intro VN background has no duplicate CG actor")
	await capture("vn-intro");view.finish_now();view.free()
	var app: TDApplication=load("res://src/app/main.tscn").instantiate()
	app.settings_path=OUT.path_join("slot-%d/settings.json"%Time.get_ticks_usec());root.add_child(app)
	await capture("title")
	var shell:=app.game_shell;shell.automatic_time=false
	check(shell.create_game("slot-01","焰请八方").ok,"isolated game")
	shell.guide.dialogue.finish_now();shell.profile.story.beat="done"
	check(shell.travel("kitchen").ok,"kitchen travel");await capture("kitchen")
	check(shell.travel("restaurant").ok,"restaurant travel");await capture("restaurant")
	shell.profile.residence.stage="door";shell.profile.unlock_residence()
	check(shell.travel("cottage").ok,"cottage travel");await capture("cottage")
	shell.go_title();app.free();await process_frame
	var f:=FileAccess.open(OUT.path_join("report.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":checks,"failures":failures,"captures":captures,"renderer":RenderingServer.get_current_rendering_method(),"human_acceptance":"PENDING"},"\t"));f.close()
	print("REDRAW_RESULT checks=",checks," failures=",failures.size()," captures=",captures.size())
	quit(0 if failures.is_empty() else 1)
