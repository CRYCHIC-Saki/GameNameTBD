extends GutTest
const Document := preload("res://addons/td_vn_editor/document.gd")
const VALID := "# start\n@bg arrival-coast-v1 with instant 0\n@show hero calm at left with instant\nhero: 你好。\n# finish\n@end\n"
var sandbox_path: String

func before_each() -> void:
	sandbox_path = Document.ROOT + "__test_editor_" + str(Time.get_ticks_usec()) + ".txt"

func after_each() -> void:
	for path: String in [sandbox_path,sandbox_path+".editing"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func test_original_opening_roundtrip_is_byte_exact() -> void:
	var doc := Document.new()
	assert_eq(doc.open_file(Document.INTRO),"")
	assert_eq(doc.text(),FileAccess.get_file_as_string(Document.INTRO))
	assert_false(doc.dirty())
	assert_eq(doc.validate(),PackedStringArray())

func test_preserve_crlf_comments_and_unknown_commands() -> void:
	var source := "// preserve  \r\n# a\r\n@future important=42\r\nhero: abc\r\n"
	var doc := Document.new(); doc.load_text(source)
	assert_eq(doc.text(),source)
	assert_true("\n".join(doc.validate()).contains("Unknown command"))
	assert_eq(Document.describe("// hello").kind,"comment")
	assert_eq(Document.describe("# a").kind,"label")
	assert_eq(Document.describe("hero(happy): abc").kind,"raw")

func test_edit_reorder_undo_redo_has_independent_snapshots() -> void:
	var doc := Document.new(); doc.load_text(VALID)
	doc.replace_line(3,"hero: 改动")
	doc.insert_line(4,"aling: 回答")
	doc.move_line(4,3)
	assert_eq(doc.lines[3],"aling: 回答")
	doc.undo(); assert_eq(doc.lines[3],"hero: 改动")
	doc.undo(); assert_false(doc.text().contains("回答"))
	doc.undo(); assert_eq(doc.text(),VALID)
	doc.redo(); assert_true(doc.text().contains("改动"))
	doc.remove_line(3); assert_false(doc.text().contains("改动"))
	doc.undo(); assert_true(doc.text().contains("改动"))

func test_native_parser_rejects_empty_duplicate_and_missing_target() -> void:
	for source: String in ["", "# a\nhero: a\n# a\n@end", "# a\n@jump missing"]:
		var doc := Document.new(); doc.load_text(source)
		assert_false(doc.validate().is_empty(),source)

func test_asset_and_wait_validation() -> void:
	for source: String in ["# a\n@bg absent\n@end", "# a\n@show hero unknown at left\n@end", "# a\nunknown: abc\n@end", "# a\n@wait -2\n@end"]:
		var doc := Document.new(); doc.load_text(source)
		assert_false(doc.validate().is_empty(),source)

func test_intro_handoffs_and_end_are_protected() -> void:
	var original := FileAccess.get_file_as_string(Document.INTRO)
	for changed: String in [original.replace("@td_name hero",""),original.replace("@td_cg hungry","@td_cg messenger"),original.replace("# hero_name","@end\n# hero_name"),original.replace("{$hero}","fixed")]:
		var doc := Document.new(); doc.load_text(changed,Document.INTRO)
		assert_false(doc.validate().is_empty())

func test_save_roundtrip_conflict_and_backup() -> void:
	var doc := Document.new(); doc.load_text(VALID)
	assert_eq(doc.save_to(sandbox_path),"")
	assert_false(doc.dirty())
	assert_eq(FileAccess.get_file_as_string(sandbox_path),VALID)
	doc.replace_line(3,"hero: changed")
	assert_eq(doc.save_to(sandbox_path),"")
	var file := FileAccess.open(sandbox_path,FileAccess.WRITE); file.store_string(VALID+"// other author\n"); file.close()
	doc.replace_line(3,"hero: overwrite")
	assert_true(doc.save_to(sandbox_path).contains("其他程序修改"))
	assert_true(FileAccess.get_file_as_string(sandbox_path).contains("other author"))

func test_invalid_save_does_not_touch_existing_file() -> void:
	var doc := Document.new(); doc.load_text(VALID)
	assert_eq(doc.save_to(sandbox_path),"")
	doc.insert_line(2,"@unknown")
	assert_false(doc.save_to(sandbox_path).is_empty())
	assert_eq(FileAccess.get_file_as_string(sandbox_path),VALID)
	assert_false(doc.save_to("res://doc/source/test.txt").is_empty())
	assert_false(doc.save_to(Document.ROOT+"../escape.txt").is_empty())

func test_composition_tracks_show_hide_and_dialogue_without_execution() -> void:
	var doc := Document.new(); doc.load_text(VALID.replace("# finish", "@show aling happy at right with fade\naling: 回应\n@hide hero with fade\n# finish"))
	var state := doc.composition(6)
	assert_eq(state.background,"arrival-coast-v1")
	assert_eq(state.speaker,"aling")
	assert_eq(state.actors.size(),1)
	assert_eq(state.actors.aling.position,"right")
	assert_eq(state.actors.aling.expression,"happy")
	assert_eq(doc.text(),doc.saved_text)

func test_choice_authoring_uses_real_native_parser() -> void:
	var doc := Document.new(); doc.load_text("# start\nhero: 选择\n- 去港口 -> harbor\n- 留下 -> finish\n# harbor\nhero: 海风\n# finish\n@end\n")
	assert_eq(doc.validate(),PackedStringArray())
	var parsed := VNEngineScenarioParser.parse_text(doc.text())
	assert_eq(parsed.nodes[0].choices.size(),2)
	assert_true(parsed.labels.has("harbor"))
