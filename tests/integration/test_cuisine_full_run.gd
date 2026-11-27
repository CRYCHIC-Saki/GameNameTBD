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
		var seen: Array[String] = []
		var completed: bool=load("res://tools/test_support/cuisine_input.gd").play(lesson,func(lane:TDCookingLane)->void:
			if lane != null and lane == lesson._pot() and not lane.food_stage.is_empty():
				if seen.is_empty() or seen.back() != lane.food_stage: seen.append(lane.food_stage))
		var sheet := lesson._service.cooking.sheet_data(chart.profile)
		var timeline := TDBeatSheet.new()
		assert_true(timeline.configure(sheet,lesson._service.cooking.data().operations).ok,id)
		var expected: Array[String] = [sheet.initial_food_stage]
		for event: Dictionary in timeline.snapshot().events:
			if event.has("food_stage") and expected.back() != event.food_stage: expected.append(event.food_stage)
		assert_eq(seen,expected,id+" visual sequence through live operations")
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
func test_chinese_daily_twenty() -> void: await _twenty("C",false)
func test_european_daily_twenty() -> void: await _twenty("E",false)
func test_japanese_daily_twenty() -> void: await _twenty("J",false)

func test_retired_cuisines_have_no_playable_lessons_or_kitchen_recipes() -> void:
	var catalog := TDResearchCatalog.new()
	assert_true(catalog.load_file().ok)
	for prefix: String in ["S","L"]:
		for index: int in range(1,21):
			var id := "%s%02d" % [prefix,index]
			assert_true(catalog.node(id).is_empty(),id)
			assert_true(catalog.chart(id).is_empty(),id)
