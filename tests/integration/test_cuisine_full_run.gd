extends GutTest
## Content acceptance: all 60 authored lessons execute real kitchen objects.
func _twenty(prefix: String, study: bool=true) -> void:
	var atlas:=TDResearchCatalog.new();assert_true(atlas.load_file().ok)
	for i: int in range(1,21):
		var id: String="%s%02d"%[prefix,i]
		var chart:=atlas.chart(id)
		if not study: chart.profile=chart.recipe_id
		var lesson:=TDResearchLesson.new();var configured:=lesson.configure(chart)
		assert_true(configured.ok,id+" "+configured.code)
		lesson.token="full:"+id;add_child(lesson)
		var completed: bool=load("res://tools/test_support/cuisine_input.gd").play(lesson)
		assert_true(completed,id+" must complete real operations")
		var progress:=lesson.update()
		assert_true(progress.ok,id+" "+progress.code)
		assert_true(progress.data.get("ready_to_finish",false),id)
		assert_gte(float(progress.data.get("quality",0)),.8,id+" authored input passes")
		var dish:=lesson._pot().snapshot()
		assert_eq(dish.state,"plated",id)
		assert_eq(dish.missing_required,[],id+" prepared and heated as required")
		assert_gte(float(dish.dish_attributes.completion),70.0,id+" complete good input produces a qualified dish")
		if not study and id in ["C02","E18","J08"]:
			var custom:=lesson._service.compile_plan({"id":"custom."+id,"name":"测试配方","version":1,"plan":dish.custom_plan})
			assert_true(custom.ok,id+" custom plan "+custom.code)
		print("CUISINE_",("LESSON " if study else "COOK "),id," quality=",progress.data.get("quality",0)," dishQ=",dish.dish_attributes.completion)
		lesson.dispose();lesson.queue_free();await wait_process_frames(2)

func test_chinese_twenty() -> void: await _twenty("C")
func test_european_twenty() -> void: await _twenty("E")
func test_japanese_twenty() -> void: await _twenty("J")
func test_southeast_twenty() -> void: await _twenty("S")
func test_latin_twenty() -> void: await _twenty("L")
func test_chinese_daily_twenty() -> void: await _twenty("C",false)
func test_european_daily_twenty() -> void: await _twenty("E",false)
func test_japanese_daily_twenty() -> void: await _twenty("J",false)
func test_southeast_daily_twenty() -> void: await _twenty("S",false)
func test_latin_daily_twenty() -> void: await _twenty("L",false)
