extends GutTest
const Store := preload("res://addons/td_vn_editor/trigger_store.gd")
var events: TDStoryEvents

func row(id:String="event_a",kind:String="person",target:String="aling") -> Dictionary:
	return {"id":id,"title":"测试演出","script_path":TDStoryEvents.ROOT+id+".txt","enabled":true,"type":kind,"target":target,"requires":"","milestone_required":"","repeat":false,"effect":{"kind":"none","target":""}}

func before_each() -> void:
	events=TDStoryEvents.new();events.definitions=[row()]

func test_catalog_rejects_cycles_duplicate_identity_missing_targets_and_versions() -> void:
	var a:=row();var b:=row("event_b");a.requires="event_b";b.requires="event_a"
	assert_ne(TDStoryEvents.validate_catalog({"schema_version":1,"events":[a,b]},false),"")
	assert_ne(TDStoryEvents.validate_catalog({"schema_version":1,"events":[row(),row()]},false),"")
	a=row();a.target="missing";assert_ne(TDStoryEvents.validate_catalog({"schema_version":1,"events":[a]},false),"")
	a=row();a.requires="gone";assert_ne(TDStoryEvents.validate_catalog({"schema_version":1,"events":[a]},false),"")
	a=row();a.script_path=TDStoryEvents.ROOT+"../source.txt";assert_ne(TDStoryEvents.validate_catalog({"schema_version":1,"events":[a]},false),"")
	assert_ne(TDStoryEvents.validate_catalog({"schema_version":2,"events":[]}),"")
	assert_eq(TDStoryEvents.validate_catalog({"schema_version":1,"events":[row()]},false),"")

func test_cancel_repeat_and_old_token_cannot_complete_or_grant_twice() -> void:
	events.definitions[0].repeat=true;events.definitions[0].effect={"kind":"cuisine","target":"jp"}
	var effects:Array=[]
	var apply:=func(value:Dictionary)->TDOutcome:effects.append(value.id);return TDOutcome.new(true)
	events.notify("person","aling",{});var cancelled:=events.begin_next({},"town:chengdu",true)
	assert_false(events.finish(cancelled.token,false,apply));assert_eq(effects,[]);assert_eq(events.counts,{})
	events.notify("person","aling",{});var first:=events.begin_next({},"town:chengdu",true)
	assert_false(events.finish(cancelled.token,true,apply));assert_true(events.finish(first.token,true,apply))
	assert_false(events.finish(first.token,true,apply));assert_eq(effects,["event_a"])
	events.notify("person","aling",{});var second:=events.begin_next({},"town:chengdu",true)
	assert_true(events.finish(second.token,true,apply));assert_eq(events.counts,{"event_a":2});assert_eq(effects,["event_a"])

func test_once_dependencies_and_milestone_cancel_do_not_autoloop() -> void:
	var b:=row("event_b","milestone","trial_served");b.requires="event_a";events.definitions.append(b)
	events.observe({"trial_served":true});assert_eq(events.pending,[])
	events.notify("person","aling",{});var first:=events.begin_next({},"",true)
	assert_true(events.finish(first.token,true,Callable()))
	events.observe({"trial_served":true});assert_eq(events.pending,["event_b"])
	var second:=events.begin_next({"trial_served":true},"",true)
	assert_false(events.finish(second.token,false,Callable()))
	events.observe({"trial_served":true});assert_eq(events.pending,[])
	events.notify("person","aling",{});assert_eq(events.pending,[])

func test_place_away_discard_route_boundary_and_profile_isolation() -> void:
	events.definitions=[row("place","place","kitchen")]
	events.notify("place","kitchen",{});assert_eq(events.begin_next({},"restaurant",true),{})
	events.definitions[0].effect={"kind":"route","target":"tokyo"}
	events.notify("place","kitchen",{});assert_eq(events.begin_next({},"kitchen",false),{})
	var active:=events.begin_next({},"kitchen",true);assert_eq(active.id,"place")
	events.finish(active.token,true,func(_x:Dictionary)->TDOutcome:return TDOutcome.new(true))
	var copy:=TDStoryEvents.new();copy.restore(events.snapshot());copy.counts.place=10
	assert_eq(events.counts.place,1)
	assert_eq(TDStoryEvents.new().counts,{})
	events.restore();assert_eq(events.counts,{})
	assert_false(events.finish(active.token,true,Callable()))

func test_progress_strict_validation_preserves_removed_event_ids() -> void:
	assert_true(TDStoryEvents.validate_progress({"schema_version":1,"counts":{"removed_event":2}}))
	for value:Variant in [0,-1,1.5,true,"1",1000001]:
		assert_false(TDStoryEvents.validate_progress({"schema_version":1,"counts":{"event_a":value}}))
	assert_false(TDStoryEvents.validate_progress({"schema_version":9,"counts":{}}))

func test_registration_conflict_invalid_script_and_stable_identity() -> void:
	var root:="res://.godot/td_vn_editor/trigger-tests/"+str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root))
	var store:=Store.new();store.path=root+"/events.json"
	store.files._write(store.path,'{"schema_version":1,"events":[]}'.to_utf8_buffer())
	var script:=TDStoryEvents.ROOT+"__trigger_test_"+str(Time.get_ticks_usec())+".txt"
	store.files._write(script,"# start\nnarrator: 独立测试\n# finish\n@end\n".to_utf8_buffer())
	var a:=row();a.script_path=script
	var original:=store.read()
	assert_eq(store.save(a,original.hash),"")
	a.title="新名字";assert_ne(store.save(a,original.hash),"","optimistic conflict preserves newer registry")
	assert_eq(store.save(a,store.read().hash),"")
	assert_eq(store.read().data.events[0].id,"event_a");assert_eq(store.read().data.events[0].title,"新名字")
	store.files._write(script,"# start\n@td_name hero\n# done\n@end\n".to_utf8_buffer())
	assert_ne(store.save(a,store.read().hash),"")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(script))
