extends GutTest
const Handoff := preload("res://addons/td_vn_editor/handoff.gd")
const Document := preload("res://addons/td_vn_editor/document.gd")
const BODY := "# start\n@bg blank with instant 0\nnarrator: 正文保持不变。\n- 接着走 -> done\n# done\n@end\n"
var target:String
func before_each() -> void:
	target=Handoff.DRAFTS+"__handoff_test_"+str(Time.get_ticks_usec())+".txt"
func after_each() -> void:
	if FileAccess.file_exists(target):DirAccess.remove_absolute(ProjectSettings.globalize_path(target))
func notes() -> Dictionary:
	var value:Dictionary=Handoff.defaults(BODY,"","",false).data
	value.title="老陈赠料";value.section="第一章 · 做饭之前";value.placement="跟阿铃进门后\n@td_name hero\n// 并不执行\n他说：\"食材收好\"";value.notes="F:\\素材\\剧本；完成后交还操作"
	return value

func test_native_comments_preserve_dialogue_commands_and_branches() -> void:
	var metadata:=notes();var result:=Handoff.apply(BODY,metadata)
	assert_eq(result.error,"");var parsed:=Handoff.read(result.text)
	assert_eq(parsed.error,"");assert_eq(parsed.body,BODY);assert_eq(parsed.data,metadata)
	var source:=VNEngineScenarioParser.parse_text(BODY);var annotated:=VNEngineScenarioParser.parse_text(result.text)
	assert_false(annotated.has_errors());assert_eq(annotated.nodes.size(),source.nodes.size());assert_eq(annotated.labels,source.labels)
	for i:int in source.nodes.size():
		assert_eq(annotated.nodes[i].text,source.nodes[i].text)
		assert_eq(annotated.nodes[i].choices.size(),source.nodes[i].choices.size())
	var doc:=Document.new();doc.load_text(result.text);assert_eq(doc.validate(),PackedStringArray())

func test_repeat_update_one_header_and_legacy_crlf_body_preserved() -> void:
	var body:=BODY.replace("\n","\r\n");assert_eq(Handoff.read(body).body,body)
	var metadata:=notes();var first:=Handoff.apply(body,metadata);metadata.placement="改放在汤剧情之后"
	var second:=Handoff.apply(first.text,metadata)
	assert_eq(str(second.text).count(Handoff.BEGIN),1);assert_eq(Handoff.read(second.text).body,body)
	assert_eq(Handoff.read(second.text).data.placement,metadata.placement)
	assert_eq(Handoff.read(first.text).data.id,Handoff.read(second.text).data.id)
	assert_eq(second.line_delta,0)

func test_invalid_duplicate_future_or_incomplete_notes_never_silently_overwrite() -> void:
	var valid:=str(Handoff.apply(BODY,notes()).text)
	for bad:String in [valid.replace("begin v1","begin v2"),valid+valid,valid.replace(Handoff.END,""),"// comment\n"+valid]:
		assert_ne(Handoff.read(bad).error,"");assert_ne(Handoff.apply(bad,notes()).error,"")
	var missing:=notes();missing.section="";missing.placement="";assert_ne(Handoff.validate(missing),"")
	missing.placement="待定";assert_eq(Handoff.validate(missing),"")
	missing.title="";assert_ne(Handoff.validate(missing),"")
	assert_ne(Handoff.read(Handoff.BEGIN+"\n// broken\n"+Handoff.END+"\n"+BODY).error,"")

func test_artist_save_cannot_overwrite_opening_and_registered_disabled_paths() -> void:
	var original:=FileAccess.get_sha256(Document.INTRO)
	var doc:=Document.new();doc.load_text(BODY)
	assert_ne(doc.save_for_handoff(Document.INTRO,notes()),"");assert_eq(FileAccess.get_sha256(Document.INTRO),original)
	assert_true(Handoff.protected_target(Document.INTRO.to_upper()).protected)
	var registry:="res://.godot/td_vn_editor/handoff-tests/"+str(Time.get_ticks_usec())+".json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(registry.get_base_dir()))
	var row:={"id":"existing","title":"已接入","script_path":target,"enabled":false,"type":"place","target":"restaurant","requires":"","milestone_required":"","repeat":false,"effect":{"kind":"none","target":""}}
	var file:=FileAccess.open(registry,FileAccess.WRITE);file.store_string(JSON.stringify({"schema_version":1,"events":[row]}));file.close()
	assert_true(Handoff.protected_target(target.to_upper(),registry).protected)
	file=FileAccess.open(registry,FileAccess.WRITE);file.store_string("broken");file.close()
	assert_ne(Handoff.protected_target(target,registry).error,"")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(registry))

func test_save_roundtrip_conflict_undo_and_recovery_text() -> void:
	var registry_hash:=FileAccess.get_sha256(TDStoryEvents.PATH)
	var doc:=Document.new();doc.load_text(BODY)
	assert_eq(doc.save_for_handoff(target,notes()),"");assert_false(doc.dirty())
	var reopened:=Document.new();assert_eq(reopened.open_file(target),"")
	assert_eq(Handoff.read(reopened.text()).data.section,"第一章 · 做饭之前")
	doc.undo();assert_eq(doc.text(),BODY);doc.redo();assert_eq(doc.text(),reopened.text())
	var latest:=notes();latest.id=Handoff.read(reopened.text()).data.id;latest.placement="新版位置"
	var file:=FileAccess.open(target,FileAccess.WRITE);file.store_string(BODY+"// 外部作者修改\n");file.close()
	assert_true(doc.save_for_handoff(target,latest).contains("其他程序修改"))
	assert_true(FileAccess.get_file_as_string(target).ends_with("// 外部作者修改\n"))
	var recovery:Dictionary=JSON.parse_string(JSON.stringify({"text":doc.text()}))
	assert_eq(Handoff.read(recovery.text).data.placement,"新版位置");assert_true(doc.dirty())
	assert_eq(FileAccess.get_sha256(TDStoryEvents.PATH),registry_hash)

func test_copies_keep_source_reference_but_get_independent_identity() -> void:
	var first:=notes();var annotated:=str(Handoff.apply(BODY,first).text)
	var reopened:=Handoff.defaults(annotated,target,"oldhash",false)
	assert_eq(reopened.data.id,first.id)
	var copy:=Handoff.defaults(annotated,target,"oldhash",true)
	assert_ne(copy.data.id,first.id);assert_eq(copy.data.source_script,target);assert_eq(copy.data.source_sha256,"oldhash")
