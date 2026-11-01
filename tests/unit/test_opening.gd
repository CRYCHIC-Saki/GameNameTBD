extends GutTest

func test_the_first_day_follows_the_script_and_keeps_one_payment() -> void:
	var opening:=TDOpening.new();opening.begin()
	var talk:=opening.talk("aling","灶间烟火",false,100);talk.begin()
	assert_true(talk.full_text().contains("长途车"));assert_eq(talk.portrait_id,"page")
	opening.complete_scene("intro");assert_eq(opening.beat,"follow")
	opening.arrive_escort();opening.complete_scene("soup")
	assert_eq(opening.complete_scene("after_taste"),{"san":-5})
	assert_eq(opening.beat,"return");opening.arrive_escort()
	assert_eq(opening.complete_scene("awaken"),{"grant":true});opening.mark_supplied()
	assert_eq(opening.beat,"cook");assert_eq(opening.score,-1)

func test_story_people_do_not_take_the_diner_door() -> void:
	var profile := TDGameProfile.new()
	assert_true(profile.error.ok, profile.error.code)
	profile.story.begin()
	var town := TDTownWorld.new()
	town.player_mode = true
	town.session = profile.world
	town.hero_name = "灶间烟火"
	town.story = profile.story
	add_child_autofree(town)
	await get_tree().process_frame
	var door := town._diner_door()
	for person: Variant in town._story_people():
		assert_ne((person as Dictionary).cell, door)
	var entered := []
	town.restaurant_requested.connect(func() -> void: entered.append(true))
	town._interact()
	var faced := town.facing_plot()
	assert_false(town._talk_open(), "cell %s facing %s plot %s" % [town._player_cell(), town._player.facing, faced.get("id", "")])
	assert_eq(entered.size(), 1, "cell %s facing %s plot %s" % [town._player_cell(), town._player.facing, faced.get("id", "")])
	assert_eq(town.story.beat, "arrive")
	profile.close()

func test_new_portraits_and_a_saved_chapter_roundtrip() -> void:
	var profile := TDGameProfile.new()
	assert_true(profile.error.ok, profile.error.code)
	assert_false(profile.snapshot().has("story"))
	profile.slot_id = "slot-01"
	profile.story.begin()
	profile.world.set_san(75)
	var before := int(profile.shop.snapshot().money_cents)
	var cents := int(profile.service.offer("service.tomato_egg").reference_cents)
	var token := "story-aling-tomato:%s" % str(profile.shop.snapshot().run_id)
	assert_true(profile.shop.world_adjustment(cents, token, "阿铃的审判").ok)
	assert_eq(profile.shop.world_adjustment(cents, token, "阿铃的审判").code, "DUPLICATE")
	assert_eq(int(profile.shop.snapshot().money_cents), before + cents)
	var saved := profile.snapshot()
	assert_eq(String(saved.story.beat), "arrive")
	var other := TDGameProfile.new()
	assert_true(other.restore(saved).ok)
	assert_eq(other.story.beat, "arrive")
	assert_eq(other.world.san, 75)
	var erased := saved.duplicate(true)
	erased.erase("story")
	var legacy := TDGameProfile.new()
	assert_true(legacy.restore(erased).ok)
	assert_false(legacy.story.started())
	profile.close()
	other.close()
	legacy.close()
	var layer := CanvasLayer.new()
	add_child_autofree(layer)
	var view := TDDialogueView.new()
	layer.add_child(view)
	await get_tree().process_frame
	var card := TDDialogue.new()
	card.add_line("罗厄", "luo", "唯有吾赐之味，值得渴求。")
	view.present(card)
	assert_eq(view.get_node("Portrait").get("who"), "luo")
