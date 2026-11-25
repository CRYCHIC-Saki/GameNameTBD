extends GutTest

func _lesson(id: String) -> void:
	var atlas:=TDResearchCatalog.new();assert_true(atlas.load_file().ok)
	var lesson:=TDResearchLesson.new();var result:=lesson.configure(atlas.chart(id))
	assert_true(result.ok,result.code)
	lesson.token="test:"+id;add_child(lesson)
	assert_true(load("res://tools/test_support/cuisine_input.gd").play(lesson),id)
	var progress:=lesson.update()
	assert_true(progress.ok,progress.code);assert_true(progress.data.ready_to_finish)
	assert_gte(float(progress.data.quality),.8,id+" exact authored input should pass")
	assert_eq(lesson._pot().snapshot().state,"plated")
	assert_false(lesson._pot().snapshot().steps.is_empty())
	lesson.dispose();lesson.queue_free();await wait_process_frames(2)

func test_chinese_tomato_egg_real_input_flow() -> void: await _lesson("C02")
func test_european_souffle_real_input_flow() -> void: await _lesson("E18")
func test_japanese_tempura_real_input_flow() -> void: await _lesson("J09")
func test_cold_sushi_real_input_flow() -> void: await _lesson("J08")

func test_restaurant_workstations_and_ambiguous_same_ingredients() -> void:
	var service:=TDServiceCatalog.new();assert_true(service.load_file().ok);assert_true(TDResearchRuntime.install(service).ok)
	var shop:=TDShopSession.new(service,"cuisine-test");shop.cuisine_id="jp"
	var candidates:=shop.contexts_for_ingredients(["ramen","char_siu","bone_stock"],true,"kitchen.stove.left")
	assert_eq(candidates.map(func(r:Dictionary)->String:return r.recipe_id),["study.j10","study.j16"])
	assert_eq(shop.contexts_for_ingredients(["ramen","char_siu","bone_stock"],true,"kitchen.steamer"),[])
	assert_true(TDCuisineKitchen.accepts("eu","kitchen.stove.right",service.cooking.recipe_data("study.e18")))
	assert_false(TDCuisineKitchen.accepts("cn","kitchen.stove.left",service.cooking.recipe_data("study.e18")))
	assert_eq(TDCuisineKitchen.station_for("jp",service.cooking.recipe_data("study.j08")),"kitchen.steamer")
