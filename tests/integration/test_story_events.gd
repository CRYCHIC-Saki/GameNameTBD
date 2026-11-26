extends GutTest
var app: TDApplication
var shell: TDGameShell
var script_path: String

func before_each() -> void:
	app=load("res://src/app/main.tscn").instantiate()
	app.settings_path="res://artifacts/vn-triggers-20261116/tests/%d/settings.json"%Time.get_ticks_usec()
	add_child_autofree(app);shell=app.game_shell;shell.automatic_time=false
	assert_true(shell.create_game("slot-01","触发测试",false).ok);shell.guide.dialogue.finish_now()
	shell.profile.story.beat="done";shell.profile.residence.stage="door"
	assert_true(shell.profile.unlock_residence().ok)
	shell.guide.set_process(false)
	script_path=TDStoryEvents.ROOT+"__trigger_integration_"+str(Time.get_ticks_usec())+".txt"
	var file:=FileAccess.open(script_path,FileAccess.WRITE)
	file.store_string("# start\n@bg restaurant-v1 with instant 0\n@show hero calm at left with instant\nhero: 新演出，{$hero}\n# done\n@end\n");file.close()
	shell.profile.story_events.definitions=[rule()]
	await wait_process_frames(2)

func rule(kind:String="person",target:String="chen") -> Dictionary:
	return {"id":"event_test","title":"老陈的新对话","script_path":script_path,"enabled":true,"type":kind,"target":target,"requires":"","milestone_required":"","repeat":false,"effect":{"kind":"cuisine","target":"jp"}}

func after_each() -> void:
	get_tree().paused=false;shell.go_title()
	await wait_process_frames(2)
	if FileAccess.file_exists(script_path):DirAccess.remove_absolute(ProjectSettings.globalize_path(script_path))

func finish_real() -> void:
	for _i:int in 6:
		if not shell.guide.presenting(): break
		shell.guide.dialogue._vn_stage.dialog._advance_dialog()
		await wait_process_frames(1)
	await wait_process_frames(2)

func test_person_plays_real_native_chapter_cancel_then_success_and_reward_once() -> void:
	var old:=shell.profile.story.export_state()
	assert_true(shell.town.authored_interaction.call("chen"))
	await wait_process_frames(2)
	var view:=shell.guide.dialogue
	assert_true(view._vn_stage.runner is VNEngineStoryRunner)
	assert_eq(view._vn_stage.runner.script_res.source_path,script_path)
	assert_eq(view._chapter.text,"老陈的新对话")
	assert_true(shell.town.external_story_frozen);assert_false(shell.town._player.controls_enabled)
	assert_eq(shell.save_game().code,"STORY_PLAYING")
	view.finish_now();assert_eq(shell.profile.story_events.counts,{})
	assert_false("jp" in shell.profile.research.snapshot().cuisines)
	assert_true(shell.town.authored_interaction.call("chen"));await wait_process_frames(2)
	await finish_real()
	assert_false(shell.guide.presenting());assert_eq(shell.profile.story_events.counts,{"event_test":1})
	assert_true("jp" in shell.profile.research.snapshot().cuisines)
	assert_eq(shell.profile.story.export_state(),old,"does not advance or overwrite the existing tutorial")
	assert_false(shell.town.authored_interaction.call("chen"))
	assert_true(shell.town._player.controls_enabled)

func test_place_milestone_and_modal_gate_use_real_shell() -> void:
	shell.profile.story_events.definitions=[rule("place","restaurant")]
	shell._dialog("阻塞测试",true)
	shell.profile.story_events.notify("place","restaurant",{})
	assert_false(shell.guide.play_authored());shell._close_dialog()
	assert_true(shell.travel("restaurant").ok);shell.guide._process(0)
	await wait_process_frames(2);assert_true(shell.guide.presenting())
	shell.guide.dialogue.finish_now()
	shell.profile.story_events.definitions=[rule("milestone","trial_served")]
	shell.profile.story.served_dish_id="real-test-plate"
	shell.guide._process(0);await wait_process_frames(2)
	assert_true(shell.guide.presenting());await finish_real()
	assert_eq(shell.profile.story_events.counts,{"event_test":1})

func test_original_opening_has_priority_and_world_pause_blocks_new_events() -> void:
	shell.profile.story.beat="arrive"
	shell.profile.story_events.definitions=[rule("person","aling")]
	assert_false(shell.town.authored_interaction.call("aling"))
	shell.profile.story.beat="done";get_tree().paused=true
	assert_false(shell.town.authored_interaction.call("aling"));get_tree().paused=false
	assert_true(shell.town.authored_interaction.call("aling"));await wait_process_frames(2)
	var profile:=shell.profile
	shell.go_title();assert_eq(profile.story_events.counts,{})
	assert_true(profile.story_events.active.is_empty());assert_eq(profile.story_events.pending,[])

func test_explicit_save_roundtrip_old_profiles_and_unsaved_exit() -> void:
	assert_true(shell.town.authored_interaction.call("chen"));await wait_process_frames(2);await finish_real()
	assert_eq(shell.slots.load_slot("slot-01").data.story_events.counts,{},"completion never writes implicitly")
	var saved:=shell.save_game();assert_true(saved.ok,saved.code)
	var stored:=shell.slots.load_slot("slot-01").data
	assert_eq(stored.story_events.counts.keys(),["event_test"]);assert_eq(int(stored.story_events.counts.event_test),1)
	var other:=TDGameProfile.new();assert_true(other.restore(stored).ok)
	assert_eq(other.story_events.counts,{"event_test":1});assert_true("jp" in other.research.snapshot().cuisines)
	other.story_events.counts.event_test=2;assert_eq(shell.profile.story_events.counts.event_test,1)
	var legacy:=stored.duplicate(true);legacy.erase("story_events")
	assert_true(other.restore(legacy).ok);assert_eq(other.story_events.counts,{})
	var invalid:=stored.duplicate(true);invalid.story_events.schema_version=42
	assert_eq(other.restore(invalid).code,"INVALID_STORY_EVENTS");assert_eq(other.story_events.counts,{})
	other.close()

func test_actual_restaurant_guest_interaction_uses_same_event_host() -> void:
	shell.travel("restaurant")
	var floor:=shell.restaurant
	floor.teleport_player(Vector2i(6,6))
	var guest:=TDRestaurantGuest.new();guest.character_id="chen";guest.ticket_id="event-test-guest";guest.phase="wait_serve"
	floor._guests.add_child(guest);guest.position=floor._player.position
	assert_eq(floor._faced_guest(),guest)
	assert_true(floor.request_interaction())
	await wait_process_frames(2)
	assert_true(shell.guide.presenting());assert_false(floor._talk_open())
	assert_eq(shell.guide.dialogue._chapter.text,"老陈的新对话")
	guest.queue_free()

func test_foreign_town_entry_plays_after_actual_port_transfer() -> void:
	shell.profile.story_events.definitions=[rule("place","town:tokyo")]
	shell.town.spawn_at_harbor()
	var travelled:=shell.voyage("tokyo");assert_true(travelled.ok,travelled.code)
	shell.guide._process(0);await wait_process_frames(2)
	assert_eq(shell.location,"voyage");assert_true(shell.guide.presenting())
	shell.guide.dialogue.finish_now();assert_eq(shell.profile.story_events.counts,{})

func test_existing_modal_dialogue_and_decoration_do_not_lose_control_to_event() -> void:
	shell.travel("restaurant")
	var talk:=shell.profile.characters.conversation("chen")
	shell.restaurant._open_talk(talk)
	assert_false(shell.guide.request_authored_person("chen"))
	shell.restaurant._dismiss_talk();shell.restaurant._toggle_edit()
	assert_false(shell.guide.request_authored_person("chen"))
	shell.restaurant._toggle_edit()
	assert_true(shell.guide.request_authored_person("chen"));await wait_process_frames(2)
	assert_true(shell.guide.presenting())
