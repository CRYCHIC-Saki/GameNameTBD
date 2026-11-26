extends SceneTree
const OUT := "res://artifacts/story-revision-20261126/gpu"
var checks := 0
var failures := 0
var app: TDApplication
var shell: TDGameShell

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, note: String) -> void:
	checks += 1
	if not value: failures += 1
	print("PASS " if value else "FAIL ",note)

func capture(name: String) -> void:
	await process_frame; await process_frame; await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OUT.path_join(name+".png")) == OK,"capture "+name)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	await check_grass_variants()
	root.size = Vector2i(1280,800)
	app = load("res://src/app/main.tscn").instantiate()
	app.settings_path = OUT.path_join("isolated-%d/settings.json" % Time.get_ticks_usec())
	root.add_child(app); shell = app.game_shell; shell.automatic_time = false
	check(shell.create_game("slot-01","新剧本",true).ok,"new revised profile")
	await process_frame; await process_frame
	var view := shell.guide.dialogue
	check(view._native,"native VN opening")
	view._vn_stage.dialog._reveal_to_end()
	await capture("01-opening")
	for viewport_size: Vector2i in [Vector2i(1280,800),Vector2i(1920,1080)]:
		root.size = viewport_size
		await process_frame; await process_frame
		var layer := view._vn_stage.runner.ctx.characters
		for actor: String in ["hero","aling","chen","luo","vito","hertz"]:
			for other: String in layer.active_sprites.keys(): layer.hide_character(other,"instant")
			var token := TDVNLayout.half_body("left" if actor == "hero" else "right",actor)
			layer.show_character(actor,"base","base","cry" if actor=="luo" else "calm","mid",token,"instant")
			await process_frame; await process_frame
			var sprite: VNEngineCharacterSprite=layer.active_sprites[actor]
			var image := TDVNLayout.fit(sprite.sprite.texture,sprite.get_rect())
			var focus: Vector2=TDVNLayout.FACE_FOCUS[actor]
			var face := image.position+image.size*focus
			check(face.y > layer.size.y*.20 and face.y < layer.size.y*.43,"upper-body face framing "+actor+str(viewport_size))
			await capture("framing-%s-%d" % [actor,viewport_size.x])
	root.size=Vector2i(1280,800)
	await process_frame; await process_frame
	view.dismiss(); await process_frame; await process_frame
	var state := shell.profile.snapshot()
	for chapter: Dictionary in TDRevisedMainline.data().chapters:
		var entry := {"id":"revised_preview_%02d" % int(chapter.number),"title":chapter.title,"path":chapter.preview}
		shell.guide.show_talk(TDRevisedMainline.talk(entry,true))
		await process_frame; await process_frame
		var found := false
		for i: int in 30:
			view._vn_stage.dialog._reveal_to_end()
			var actors := view._vn_stage.runner.ctx.characters.active_sprites
			if not actors.is_empty(): found = true; break
			view._vn_stage.dialog._advance_dialog()
			await process_frame; await process_frame
		check(found,"chapter cast "+str(chapter.number))
		if int(chapter.number) == 5:
			var actors := view._vn_stage.runner.ctx.characters.active_sprites
			check(actors.has("hina") and actors.hina.has_node("TextPlaceholder"),"Hina visible text stand-in")
		await capture("chapter-%02d" % int(chapter.number))
		view.dismiss(); await process_frame; await process_frame
	check(TDLevelProgression.same_value(state,shell.profile.snapshot()),"all previews preserve profile")
	# Reproduce the reported chapter-eight speaker switch using the real runner.
	var ending: Dictionary = TDRevisedMainline.data().chapters[7]
	shell.guide.show_talk(TDRevisedMainline.talk({"id":"revised_preview_08","title":ending.title,"path":ending.preview},true))
	await process_frame; await process_frame
	var listeners_checked := false
	var counterpart_seen := false
	for i: int in 100:
		view._vn_stage.dialog._reveal_to_end()
		var runner := view._vn_stage.runner
		var actors: Dictionary = runner.ctx.characters.active_sprites
		if actors.has("luo"): counterpart_seen = true
		if counterpart_seen and runner.state.last_speaker == "hero":
			check(actors.has("luo"),"hero dialogue keeps Luo on stage")
			if actors.has("luo"):
				for frame: int in 20: await process_frame
				check(actors.luo.z_index < actors.hero.z_index,"listener behind speaking hero")
				check(actors.luo.sprite.modulate.r < .6 and actors.hero.sprite.modulate.r > .9,"listener dimmed and hero highlighted")
				await capture("hero-with-dimmed-listener")
			listeners_checked = true
			break
		view._vn_stage.dialog._advance_dialog()
		await process_frame; await process_frame
	check(listeners_checked,"chapter-eight hero speaker switch exercised")
	view.dismiss(); await process_frame; await process_frame
	shell.guide.show_revised_journal()
	await capture("02-story-journal")
	shell._close_dialog()
	shell.guide.continue_revised(); await finish_active()
	shell.guide.continue_revised(); await finish_active()
	check(shell.profile.story.revised.cursor == 2,"real dialogue reaches unfinished first battle")
	shell.guide.show_revised_journal()
	await process_frame; await process_frame
	check(shell.music.context == "cooking","reserved battle soundtrack in placeholder")
	await capture("04-battle-placeholder")
	shell._close_dialog()
	shell.travel("town"); shell.town.spawn_at_harbor()
	await capture("map-jiangnan")
	for id: String in ["tokyo","paris"]:
		var outcome := shell.voyage(id)
		check(outcome.ok,"existing voyage "+id)
		if outcome.ok: await capture("map-"+id)
		shell.voyage("chengdu")
	var map_state := shell.profile.snapshot()
	shell.show_world_map()
	await process_frame; await process_frame
	var atlas: TDTravelMapView
	for child: Node in shell._modal_box.get_children():
		if child is TDTravelMapView: atlas=child
	check(atlas!=null,"native travel chart")
	check(atlas.focused_town().is_empty(),"world chart has no rectangular town overlays")
	await capture("world-chart")
	for id: String in ["chengdu","tokyo","paris"]:
		atlas.focus_town(id)
		check(atlas.focused_town()==id,"chart focus "+id)
		await capture("local-chart-"+id)
	atlas.reset_view()
	check(atlas.focused_town().is_empty(),"chart returns to seamless world illustration")
	shell._close_dialog()
	check(TDLevelProgression.same_value(map_state,shell.profile.snapshot()),"map viewing leaves gameplay unchanged")
	shell.travel("kitchen")
	check(shell.kitchen_view.kitchen._content.pc_operations.bpm == 140,"live kitchen 140 BPM")
	await capture("03-kitchen")
	shell.go_title(); app.queue_free()
	await process_frame; await process_frame
	print("REVISED_STORY_GPU checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)

func check_grass_variants() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(128,128)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var patch := TileMapLayer.new()
	patch.tile_set = load("res://src/town/jiangnan_map_tileset.tres")
	patch.scale = Vector2(16,16)
	var material := ShaderMaterial.new()
	material.shader = load("res://src/town/jiangnan_ground_light.gdshader")
	material.set_shader_parameter("continuous_grass",load("res://assets/town/egret-grass.png"))
	patch.material = material
	viewport.add_child(patch)
	var reference := PackedByteArray()
	var consistent := true
	for y: int in 6:
		for x: int in 6:
			patch.set_cell(Vector2i.ZERO,0,Vector2i(84+x,y))
			await process_frame; await RenderingServer.frame_post_draw
			var pixels := viewport.get_texture().get_image().get_data()
			if reference.is_empty(): reference = pixels
			else: consistent = consistent and pixels == reference
	check(consistent,"all 36 grass atlas variants render identical map-space material, no variant seams")
	print("GRASS_RUNTIME_ATLAS ",patch.tile_set.get_source(0).get_runtime_texture().get_size())
	check(viewport.get_texture().get_image().get_pixel(64,64).g > .1,"continuous grass material is visible")
	viewport.queue_free()
	await process_frame

func finish_active() -> void:
	var view := shell.guide.dialogue
	for i: int in 120:
		if view.talk == null: return
		if view._vn_stage.runner != null:
			view._vn_stage.dialog._reveal_to_end()
			view._vn_stage.dialog._advance_dialog()
		await process_frame; await process_frame
