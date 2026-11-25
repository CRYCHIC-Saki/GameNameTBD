@tool
extends RefCounted
## A lossless line document; the native parser, never this model, owns playback.
const Illustrated := preload("res://src/story/illustrated_cg.gd")
const INTRO := "res://content/story/vn/scenario/intro/script.txt"
const ROOT := "res://content/story/vn/scenario/"
const BG_ROOT := "res://content/story/vn/backgrounds/"
const CAST_PATH := "res://content/story/vn/config/characters/_characters.tres"
const AssetImport := preload("res://addons/td_vn_editor/asset_import.gd")
const Handoff := preload("res://addons/td_vn_editor/handoff.gd")
var path: String = ""
var lines: PackedStringArray = []
var saved_text: String = ""
var disk_hash: String = ""
var undo_stack: Array[PackedStringArray] = []
var redo_stack: Array[PackedStringArray] = []

func open_file(value: String) -> String:
	if not FileAccess.file_exists(value): return "找不到剧本文件。"
	var file := FileAccess.open(value, FileAccess.READ)
	if file == null: return "无法读取剧本。"
	load_text(file.get_as_text(), value)
	return ""

func load_text(value: String, source: String = "") -> void:
	path = source
	saved_text = value
	disk_hash = value.sha256_text()
	lines = value.split("\n")
	undo_stack.clear(); redo_stack.clear()

func text() -> String:
	return "\n".join(lines)

func dirty() -> bool:
	return text() != saved_text

func _remember() -> void:
	undo_stack.append(lines.duplicate())
	if undo_stack.size() > 100: undo_stack.pop_front()
	redo_stack.clear()

func replace_line(index: int, value: String) -> void:
	if index < 0 or index >= lines.size() or lines[index] == value: return
	_remember()
	var parts := value.split("\n")
	lines.remove_at(index)
	for i in parts.size(): lines.insert(index + i, parts[i])

func insert_line(index: int, value: String) -> void:
	_remember()
	var at := clampi(index, 0, lines.size())
	for item: String in value.split("\n"):
		lines.insert(at, item); at += 1

func remove_line(index: int) -> void:
	if index < 0 or index >= lines.size(): return
	_remember(); lines.remove_at(index)

func move_line(index: int, destination: int) -> void:
	if index < 0 or destination < 0 or index >= lines.size() or destination >= lines.size() or index == destination: return
	_remember()
	var line := lines[index]
	lines.remove_at(index); lines.insert(destination, line)

func undo() -> void:
	if undo_stack.is_empty(): return
	redo_stack.append(lines.duplicate()); lines = undo_stack.pop_back()

func redo() -> void:
	if redo_stack.is_empty(): return
	undo_stack.append(lines.duplicate()); lines = redo_stack.pop_back()

static func describe(raw: String) -> Dictionary:
	var line := raw.strip_edges()
	if line.is_empty(): return {"kind":"blank", "label":""}
	if line.begins_with("//"): return {"kind":"comment", "value":line.substr(2).strip_edges(), "label":"注释  " + line.substr(2)}
	if line.begins_with("#"): return {"kind":"label", "value":line.substr(1).strip_edges(), "label":"◆  " + line.substr(1).strip_edges()}
	if line.begins_with("@"):
		var words := line.substr(1).split(" ", false, 1)
		var kind := words[0]
		var args := words[1] if words.size() > 1 else ""
		var captions := {"bg":"背景", "show":"立绘", "hide":"退场", "wait":"等待", "td_cg":"CG 演出", "td_name":"输入姓名", "end":"结束", "jump":"跳转"}
		return {"kind":kind, "value":args, "label":str(captions.get(kind,"原生命令")) + "  " + args}
	if line.begins_with("-") and line.contains("->"):
		var parts := line.substr(1).split("->", true, 1)
		return {"kind":"choice", "text":parts[0].strip_edges(), "target":parts[1].strip_edges(), "label":"选项  " + parts[0].strip_edges()}
	if line.contains(":") and not line.begins_with("-"):
		var parts := line.split(":", true, 1)
		# Inline expressions/animations remain raw to avoid losing native semantics.
		if parts[0].contains("(") or parts[0].contains("["): return {"kind":"raw", "value":raw, "label":"高级对白  " + line}
		var speaker := parts[0].strip_edges()
		return {"kind":"dialogue", "speaker":"" if speaker == "narrator" else speaker, "text":parts[1].strip_edges(), "label":parts[0] + "  " + parts[1].strip_edges()}
	return {"kind":"raw", "value":raw, "label":"原文  " + line}

static func portrait_path(who: String, expression: String, outfit: String = "base", pose: String = "base", shot: String = "mid") -> String:
	return "res://content/story/vn/portraits/%s/%s_%s_%s_%s_%s.tres" % [who, who, outfit, pose, expression, shot]

static func backgrounds() -> PackedStringArray:
	var result := PackedStringArray()
	for file: String in DirAccess.get_files_at(BG_ROOT):
		if file.ends_with(".tres"): result.append(file.get_basename())
	result.sort(); return result

static func background_title(id: String) -> String:
	return AssetImport.resource_title(BG_ROOT+id+".tres",str(AssetImport.BG_LABELS.get(id,id)))

static func expression_title(who: String, expression: String) -> String:
	return AssetImport.resource_title(portrait_path(who,expression),str({"calm":"平静","happy":"愉快"}.get(expression,expression)))

static func cast_names() -> Dictionary:
	var result := {"":"旁白"}
	var cast: Resource = load(CAST_PATH)
	for entry: Resource in cast.characters: result[entry.id] = entry.display_name
	return result

static func expressions(who: String) -> PackedStringArray:
	var result := PackedStringArray()
	var prefix := who + "_base_base_"
	for file: String in DirAccess.get_files_at("res://content/story/vn/portraits/" + who):
		if file.begins_with(prefix) and file.ends_with("_mid.tres"): result.append(file.trim_prefix(prefix).trim_suffix("_mid.tres"))
	result.sort(); return result

func validate() -> PackedStringArray:
	var issues := PackedStringArray()
	var script := VNEngineScenarioParser.parse_text(text(), path if not path.is_empty() else "<draft>")
	for diagnostic: VNEngineParseDiagnostic in script.diagnostics:
		if diagnostic.severity != VNEngineParseDiagnostic.INFO: issues.append(diagnostic.format())
	if script.nodes.is_empty(): issues.append("[ERROR] 剧本至少需要一个节点和一个可播放步骤。")
	var names := cast_names()
	var handoffs := PackedStringArray()
	var substantive := PackedStringArray()
	for i in lines.size():
		var item := describe(lines[i])
		var kind: String = item.kind
		var args: String = item.get("value", "")
		var error := ""
		if kind not in ["blank", "comment", "label"]: substantive.append(lines[i].strip_edges())
		match kind:
			"bg":
				if not args.get_slice(" ",0) in backgrounds(): error = "背景不存在：" + args.get_slice(" ",0)
			"show":
				var p := VNEngineCmdShow.parse_show_args(args)
				if p.is_empty() or not names.has(p.get("id", "")): error = "角色未注册。"
				else:
					var expr: String = p.expression if not str(p.expression).is_empty() else "calm"
					var asset := portrait_path(p.id, expr, p.outfit if p.outfit != "" else "base", p.pose if p.pose != "" else "base", p.shot if p.shot != "" else "mid")
					if not ResourceLoader.exists(asset): error = "立绘不存在：" + asset
					if str(p.position).begins_with("td:") and TDVNLayout.parse(p.position).is_empty(): error = "人物画布位置无效。"
			"move":
				var tokens := args.split(" ",false)
				if tokens.size() >= 3 and tokens[2].begins_with("td:") and TDVNLayout.parse(tokens[2]).is_empty(): error = "人物画布位置无效。"
			"dialogue":
				if not names.has(item.speaker): error = "说话角色未注册：" + item.speaker
			"hide":
				if not names.has(args.get_slice(" ",0)): error = "退场角色未注册。"
			"wait":
				if not args.is_valid_float() or float(args) < 0: error = "等待时间必须是非负秒数。"
			"td_cg":
				handoffs.append("td_cg " + args)
				if not Illustrated.TITLES.has(args): error = "CG 片段不存在：" + args
			"td_name":
				handoffs.append("td_name " + args)
				if args != "hero": error = "当前姓名输入仅支持主角 hero。"
		if not error.is_empty(): issues.append("[ERROR] Line %d: %s" % [i+1, error])
	if path == INTRO:
		if handoffs != PackedStringArray(["td_cg arrival","td_cg hungry","td_cg messenger","td_name hero"]): issues.append("[ERROR] 开篇必须保留三段 CG 和一次命名，且顺序不变。")
		if substantive.is_empty() or substantive[-1] != "@end" or substantive.count("@end") != 1: issues.append("[ERROR] 开篇只能在最后结束。")
		if not text().contains("{$hero}"): issues.append("[ERROR] 开篇必须保留姓名变量 {$hero}。")
		for item: String in substantive:
			if item.begins_with("@jump") or item.begins_with("- ") or item.begins_with("@goto_chapter") or item.begins_with("@return") or item.begins_with("@call"):
				issues.append("[ERROR] 开篇教学为线性流程，不能添加跳过交接的分支。请在新章节中编写分支。")
	return issues

func save_for_handoff(target: String, notes: Dictionary) -> String:
	var protection := Handoff.protected_target(target)
	if not protection.error.is_empty(): return protection.error
	if protection.protected: return "这是已接入游戏的剧情。请另存为待接入副本，由开发者合入。"
	var annotated := Handoff.apply(text(),notes)
	if not annotated.error.is_empty(): return annotated.error
	if str(annotated.text)!=text(): _remember(); lines=str(annotated.text).split("\n")
	return save_to(target)

func save_to(target: String) -> String:
	# Never overwrite user source files or another author's concurrent edit.
	if not target.begins_with(ROOT) or not target.ends_with(".txt") or target.contains(".."):
		return "请保存到 content/story/vn/scenario 内的 .txt 剧本。"
	var old_path := path
	path = target
	var issues := validate()
	path = old_path
	var registered := TDStoryEvents.new()
	for event: Dictionary in registered.definitions:
		if event.script_path == target:
			var host_issue := TDStoryEvents.validate_authored_source(text())
			if not host_issue.is_empty(): issues.append(host_issue)
	# Warnings are also blocking: unknown text must not silently become lost playback.
	if not issues.is_empty(): return "请先修复检查结果：\n" + "\n".join(issues)
	if FileAccess.file_exists(target):
		if target != path: return "同名文件已存在，请换一个名字。"
		if FileAccess.get_file_as_string(target).sha256_text() != disk_hash: return "文件已被其他程序修改。请另存草稿，再重新打开合并。"
	var directory := ProjectSettings.globalize_path(target.get_base_dir())
	if DirAccess.make_dir_recursive_absolute(directory) != OK: return "无法创建目录。"
	var payload := text()
	var tmp := target + ".editing"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null: return "无法写入临时文件。"
	file.store_string(payload); file.flush(); file.close()
	if FileAccess.get_file_as_string(tmp) != payload: return "临时文件校验失败，原文件保留。"
	if FileAccess.file_exists(target):
		var backup := "res://.godot/td_vn_editor/backups/" + str(Time.get_unix_time_from_system()).replace(".","-") + "-" + target.get_file()
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(backup.get_base_dir()))
		if DirAccess.copy_absolute(ProjectSettings.globalize_path(target), ProjectSettings.globalize_path(backup)) != OK: return "备份失败，原文件保留。"
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(target)) != OK: return "替换失败，原文件与临时文件保留。"
	path = target; saved_text = payload; disk_hash = payload.sha256_text()
	return ""

func composition(index: int) -> Dictionary:
	var state := {"background":"", "actors":{}, "speaker":"", "text":"", "cg":""}
	for i in mini(index + 1, lines.size()):
		var item := describe(lines[i])
		match item.kind:
			"bg": state.background = str(item.value).get_slice(" ",0); state.cg = ""
			"show":
				var p := VNEngineCmdShow.parse_show_args(item.value)
				if not p.is_empty():
					var previous: Dictionary = state.actors.get(p.id,{})
					for key: String in ["position","expression","outfit","pose","shot"]:
						if str(p[key]).is_empty(): p[key] = previous.get(key,{"position":"center","expression":"calm","outfit":"base","pose":"base","shot":"mid"}[key])
					state.actors[p.id] = p
			"move":
				var tokens := str(item.value).split(" ",false)
				if tokens.size() >= 3 and state.actors.has(tokens[0]): state.actors[tokens[0]].position = tokens[2]
			"hide": state.actors.erase(str(item.value).get_slice(" ",0))
			"dialogue": state.speaker = item.speaker; state.text = item.text; state.cg = ""
			"td_cg": state.cg = item.value
	return state

# The page view projects native lines. Generated canvas blocks remain ordinary VN commands.
const CANVAS_BEGIN := "// td_canvas_begin v1"
const CANVAS_END := "// td_canvas_end"

func pages() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for i in lines.size():
		var item := describe(lines[i])
		if item.kind in ["dialogue","td_cg","td_name","end","raw"]:
			if item.kind == "raw" and not lines[i].contains(":"): continue
			result.append({"line":i,"kind":item.kind,"title":item.label})
	return result

static func cast_scale(who: String) -> float:
	var cast: VNEngineCast = load(CAST_PATH)
	var member := cast.get_entry(who)
	return member.sprite_scale if member != null else 1.0

static func show_line(actor: Dictionary) -> String:
	return "@show %s %s outfit=%s pose=%s shot=%s at %s with instant" % [actor.id,actor.get("expression","calm"),actor.get("outfit","base"),actor.get("pose","base"),actor.get("shot","mid"),actor.get("position","center")]

static func dialogue_line(speaker: String, value: String) -> String:
	return (speaker if not speaker.is_empty() else "narrator") + ": " + value.replace("\n","\\n")

func _canvas_lines(state: Dictionary) -> PackedStringArray:
	var output := PackedStringArray([CANVAS_BEGIN,"@bg " + (str(state.background) if not str(state.background).is_empty() else "blank") + " with instant 0"])
	for who: String in cast_names():
		if not who.is_empty(): output.append("@hide " + who + " with instant")
	for who: String in state.actors: output.append(show_line(state.actors[who]))
	output.append(CANVAS_END)
	return output

func _write_canvas(anchor: int, state: Dictionary) -> int:
	var begin := anchor
	if anchor > 0 and lines[anchor-1].strip_edges() == CANVAS_END:
		begin = anchor-1
		while begin > 0 and lines[begin].strip_edges() != CANVAS_BEGIN: begin -= 1
		if lines[begin].strip_edges() != CANVAS_BEGIN: begin = anchor
	for i in anchor-begin: lines.remove_at(begin)
	var block := _canvas_lines(state)
	for i in block.size(): lines.insert(begin+i,block[i])
	return begin + block.size()

func set_page_visual(anchor: int, kind: String, value: String, extra: String = "") -> int:
	if anchor < 0 or anchor >= lines.size() or describe(lines[anchor]).kind != "dialogue": return anchor
	var state := composition(anchor).duplicate(true)
	match kind:
		"background": state.background = value
		"actor":
			if not state.actors.has(value):
				state.actors[value] = {"id":value,"expression":"calm","outfit":"base","pose":"base","shot":"mid","position":TDVNLayout.encode(.3 if state.actors.is_empty() else .7,.85625)}
		"position":
			if not state.actors.has(value) or TDVNLayout.parse(extra).is_empty(): return anchor
			state.actors[value].position = extra
		"expression":
			if not state.actors.has(value): return anchor
			state.actors[value].expression = extra
		"remove": state.actors.erase(value)
		_: return anchor
	_remember()
	# Freeze the next visual page before changing this one, like independent PPT slides.
	for i in range(anchor+1,lines.size()):
		if describe(lines[i]).kind == "dialogue":
			_write_canvas(i,composition(i))
			break
	return _write_canvas(anchor,state)

func _header_start(anchor: int) -> int:
	var start := anchor
	while start > 0 and not lines[start].strip_edges().begins_with("#"): start -= 1
	return start

func _header_end(anchor: int) -> int:
	var finish := anchor+1
	while finish < lines.size() and not lines[finish].strip_edges().begins_with("#"): finish += 1
	return finish

func new_page(anchor: int, copy_dialogue: bool = false) -> int:
	var state := composition(anchor)
	var at := _header_end(anchor)
	if anchor < lines.size() and describe(lines[anchor]).kind == "end": at = _header_start(anchor)
	var block := PackedStringArray(["# slide_"+str(Time.get_ticks_usec())])
	block.append_array(_canvas_lines(state))
	block.append(dialogue_line(state.speaker,state.text) if copy_dialogue else "hero: 在这里写对白。")
	block.append("")
	_remember()
	for i in block.size(): lines.insert(at+i,block[i])
	return at+block.size()-2

func remove_page(anchor: int) -> int:
	var start := _header_start(anchor)
	if not lines[start].strip_edges().begins_with("# slide_"): return -1
	var finish := _header_end(anchor)
	_remember()
	for i in finish-start: lines.remove_at(start)
	return mini(start,lines.size()-1)
