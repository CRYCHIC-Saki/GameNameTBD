extends SceneTree
## Real rendering of the production cuisine rooms and QTE. Isolated practice only.
const OUT="res://artifacts/cuisine-expansion-20261117/gpu"
var checks:=0
var failures:=0
var shots: Array=[]
func _initialize() -> void: call_deferred("run")
func verify(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1;printerr("FAIL ",label)
func capture(id: String) -> void:
	await process_frame;RenderingServer.force_draw()
	verify(root.get_texture().get_image().save_png(OUT.path_join(id+".png"))==OK,"capture "+id)
	shots.append(id)
func run() -> void:
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i(1280,800)
	DirAccess.make_dir_recursive_absolute(OUT)
	var atlas:=TDResearchCatalog.new();verify(atlas.load_file().ok,"atlas")
	for pair: Array in [["C02","stir"],["E18","bake"],["J09","fry"],["S04","stir"],["L08","steam"],["J08","roll"]]:
		var lesson:=TDResearchLesson.new();verify(lesson.configure(atlas.chart(pair[0])).ok,"configure "+pair[0])
		lesson.token="gpu:"+pair[0];root.add_child(lesson);await process_frame
		var stage:=lesson.kitchen.stage;stage.hide();lesson.kitchen.world.show()
		await capture(pair[0]+"-room")
		stage.show();lesson.kitchen.world.hide()
		var sent: Dictionary={};var captured:=false;var input_checked:=false
		for step: int in 16000:
			var result:=lesson.advance(.05)
			if not result.ok: verify(false,"advance "+pair[0])
			if not result.ok or result.data.ready_to_finish: break
			var lane:=lesson.active_lane()
			if not input_checked and lane.qte!=null and lane.progress.qte_kind=="rhythm" and float(lane.progress.elapsed_sec)>=float(lane.progress.beat_times_sec[0]):
				var key:=InputEventKey.new();key.keycode=KEY_SPACE;key.physical_keycode=KEY_SPACE;key.pressed=true;root.push_input(key,true)
				key=InputEventKey.new();key.keycode=KEY_SPACE;key.physical_keycode=KEY_SPACE;key.pressed=false;root.push_input(key,true)
				verify(lane.qte.update().data.get("cut_hits",0)>0,"viewport cutting key "+pair[0])
				sent[str(lane.progress.operation_id)+":0"]=true;input_checked=true
			load("res://tools/test_support/cuisine_input.gd").drive(lane,sent)
			if not captured and lane.active_technique==pair[1]:
				await capture(pair[0]+"-"+pair[1]);captured=true
		verify(captured,"technique reached "+pair[0]);verify(lesson.update().data.ready_to_finish,"finished "+pair[0])
		lesson.dispose();lesson.queue_free();await process_frame;await process_frame
	var file:=FileAccess.open(OUT.path_join("report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"screenshots":shots},"\t"));file.close()
	print("CUISINE_GPU checks=",checks," failures=",failures," screenshots=",shots.size());quit(0 if failures==0 else 1)
