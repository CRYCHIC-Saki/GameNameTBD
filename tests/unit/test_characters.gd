extends GutTest

func test_clock_uses_elapsed_time_pause_midnight_and_one_closure() -> void:
	var clock:=TDWorldDayClock.new()
	assert_false(clock.advance(1.5));assert_eq(clock.minute,481.5)
	clock.advance(50,true);assert_eq(clock.minute,481.5)
	clock.advance(-2);clock.advance(NAN);assert_eq(clock.minute,481.5)
	clock.minute=1439.0;clock.advance(1);assert_eq(clock.label(),"00:00")
	assert_true(clock.advance(10000));assert_eq(clock.minute,1560.0)
	clock.closed_day=1;assert_false(clock.advance(1))
	clock.next_day(2);assert_eq(clock.minute,480.0);assert_eq(clock.day,2)

func test_config_rejects_duplicate_identity_overlapping_schedule_and_bad_units() -> void:
	var raw: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(TDCharacterRoster.SOURCE))
	assert_true(TDCharacterRoster.validate_config(raw).ok)
	var broken:=raw.duplicate(true);broken.characters.append(broken.characters[0].duplicate(true))
	assert_false(TDCharacterRoster.validate_config(broken).ok)
	broken=raw.duplicate(true);broken.characters[0].schedule[1].from=500
	assert_false(TDCharacterRoster.validate_config(broken).ok)
	broken=raw.duplicate(true);broken.settings.walk_step_sec=0
	assert_false(TDCharacterRoster.validate_config(broken).ok)

func test_daily_conversation_completes_once_and_has_affection_tiers() -> void:
	var people:=TDCharacterRoster.new()
	var talk:=people.conversation("aling")
	assert_eq(talk.presentation,"interaction")
	assert_eq(people.complete_chat(talk.context,false,["chat"]).code,"CHAT_CANCELLED")
	assert_eq(people.relationship("aling").affection,0)
	assert_true(people.complete_chat(talk.context,true,["chat"]).ok)
	people.complete_chat(talk.context,true,["about"])
	assert_eq(people.relationship("aling").affection,2)
	people.records.aling.affection=20;assert_eq(people.tier("aling"),"friend")
	people.records.aling.affection=60;assert_eq(people.tier("aling"),"close")
	people.next_day(2)
	assert_eq(people.complete_chat(talk.context,true,["chat"]).code,"STALE_CONVERSATION")
	people.complete_chat(people.conversation("aling").context,true,["chat"])
	assert_eq(people.relationship("aling").affection,62)

func test_named_customer_keeps_economic_type_family_and_has_one_daily_opportunity() -> void:
	var people:=TDCharacterRoster.new()
	var catalog:=TDServiceCatalog.new();assert_true(catalog.load_file().ok)
	var economy:=TDWorldEconomy.new(catalog.config.costs)
	var templates: Array=catalog.cooking.data().customers
	var source:=economy.customer(economy.config.groups[0],0,templates).snapshot()
	var before:=source.duplicate(true)
	assert_true(people.candidate(source,templates,16).is_empty(),"08:00 is outside her meal window")
	people.clock.minute=660.0
	var person:=people.candidate(source,templates,16)
	assert_true(TDEconomicCustomer.validate(person).ok)
	assert_eq(person.id,"character:aling");assert_eq(person.household_id,source.household_id)
	assert_eq(source,before)
	assert_true(people.candidate(source,templates,16).is_empty())

func test_meal_affection_uses_real_score_once_and_instances_do_not_share_state() -> void:
	var people:=TDCharacterRoster.new();var other:=TDCharacterRoster.new()
	var order:={"id":"order-a","status":"SERVED","economic_intent":{"day":1},"economic_profile":{"id":"character:aling"},"score":{"satisfaction":80.0}}
	people.observe_orders([order]);people.observe_orders([order])
	assert_eq(people.relationship("aling").affection,3)
	assert_eq(other.relationship("aling").affection,0)
	people.next_day(2);people.observe_orders([order]);assert_eq(people.relationship("aling").affection,3)
	order.economic_intent.day=2;order.id="order-b";order.score.satisfaction=39.0
	people.observe_orders([order]);assert_eq(people.relationship("aling").affection,1)
	people.next_day(3);order.economic_intent.day=3;order.id="order-c";order.score.satisfaction=40.0
	people.observe_orders([order]);assert_eq(people.relationship("aling").affection,1)
	var copy:=people.relationship("aling");copy.affection=99
	assert_eq(people.relationship("aling").affection,1)

func test_character_save_roundtrip_rejects_unknown_version_bad_range_and_clock_day() -> void:
	var people:=TDCharacterRoster.new();people.clock.minute=745.5
	people.complete_chat(people.conversation("chen").context,true,["about"])
	var save:=people.snapshot();var other:=TDCharacterRoster.new()
	assert_true(other.restore(save,1).ok);assert_eq(other.snapshot(),save)
	var broken:=save.duplicate(true);broken.records.chen.affection=101
	assert_false(other.restore(broken,1).ok);assert_eq(other.snapshot(),save)
	broken=save.duplicate(true);broken.schema_version=99
	assert_false(other.restore(broken,1).ok)
	assert_false(other.restore(save,2).ok)

func test_story_choice_shows_player_then_reply_and_narrator_is_not_a_speaker() -> void:
	var talk:=TDDialogue.new();talk.story_layout("主角","aling")
	talk.add_line("旁白","page","风吹过小镇。")
	talk.add_line("阿铃","aling","你好。")
	talk.add_choice([{"id":"hello","label":"你好，阿铃。","speaker":"阿铃","portrait":"aling","text":"又见面了。"}])
	talk.begin();assert_eq(talk.active_side,"")
	talk.click();talk.click();assert_eq(talk.active_side,"right")
	talk.skip();assert_true(talk.pick("hello"))
	assert_eq(talk.portrait_id,"hero");assert_eq(talk.active_side,"left");assert_eq(talk.full_text(),"你好，阿铃。")
	talk.click();talk.click();assert_eq(talk.active_side,"right");assert_eq(talk.full_text(),"又见面了。")

func test_real_dialogue_view_keeps_both_portraits_above_text_and_restores_daily_layout() -> void:
	var view:=TDDialogueView.new();add_child_autofree(view)
	await get_tree().process_frame
	var talk:=TDDialogue.new();talk.story_layout("主角","chen");talk.add_line("老陈","chen","尝尝这道菜。")
	view.present(talk)
	var left:=view.get_node("Portrait") as Control;var right:=view.get_node("RightPortrait") as Control
	assert_true(right.visible);assert_lt(left.modulate.r,right.modulate.r)
	assert_lte(left.get_global_rect().end.y,(view.get_node("Box") as Control).global_position.y)
	var daily:=TDCharacterRoster.new().conversation("chen")
	view.present(daily);assert_false(right.visible);assert_eq(left.modulate,Color.WHITE)
	view.finish_now();assert_false(view.last_completed)

func test_releasing_a_story_position_rebuilds_the_same_schedule_goal() -> void:
	var profile:=TDGameProfile.new();var people:=profile.characters
	people.sync_map(profile.world.town_map)
	people.advance(0)
	var target: Vector2i=people.runtime.chen.goal
	var beside: Array[Vector2i]=people._road_neighbors(target)
	assert_false(beside.is_empty())
	people.pinned.chen=beside[0];people.advance(0)
	people.pinned.clear();people.advance(.35)
	assert_eq(people.runtime.chen.cell,target)
	profile.close()
