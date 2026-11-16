@tool
extends RefCounted
## Author intent travels with the native TXT, but never registers a game trigger.
const BEGIN := "// td_handoff_begin v1"
const END := "// td_handoff_end"
const INTRO := "res://content/story/vn/scenario/intro/script.txt"
const DRAFTS := "res://content/story/vn/scenario/drafts/"

static func read(source: String) -> Dictionary:
	var lines := source.split("\n")
	var starts: Array[int] = []; var ends: Array[int] = []
	for i: int in lines.size():
		if lines[i].strip_edges().begins_with("// td_handoff_begin"): starts.append(i)
		if lines[i].strip_edges() == END: ends.append(i)
	if starts.is_empty() and ends.is_empty(): return {"error":"","data":{},"body":source,"prefix_lines":0}
	if starts.size()!=1 or ends.size()!=1 or starts[0]!=0 or ends[0]<=starts[0] or lines[0].strip_edges()!=BEGIN:
		return {"error":"交接说明的格式或版本不受支持，请保留原文交给开发者检查。"}
	var json_lines := PackedStringArray()
	for i: int in range(1,ends[0]):
		if not lines[i].begins_with("// "): return {"error":"交接说明块损坏，请保留原文。"}
		json_lines.append(lines[i].substr(3).trim_suffix("\r"))
	var json := JSON.new()
	if json.parse("\n".join(json_lines)) != OK: return {"error":"交接说明块不是有效的 JSON，请保留原文。"}
	var data: Variant = json.data
	var error := validate(data)
	if not error.is_empty(): return {"error":error}
	data.schema_version = 1
	return {"error":"","data":data,"body":"\n".join(lines.slice(ends[0]+1)),"prefix_lines":ends[0]+1}

static func validate(data: Variant) -> String:
	if not data is Dictionary or data.get("schema_version")!=1 or data.get("purpose")!="author_handoff": return "交接说明版本或用途无效。"
	if not TDStoryEvents.valid_id(data.get("id")): return "交接说明标识无效。"
	for key: String in ["title","section","placement","notes","source_script","source_sha256"]:
		if not data.get(key) is String: return "交接说明字段无效："+key
	if data.title.strip_edges().is_empty() or data.title.length()>80: return "请填写剧情名称（80字以内）。"
	if data.section.strip_edges().is_empty() and data.placement.strip_edges().is_empty(): return "请至少填写所属章节／段落或插入位置；暂未决定可以写“待定”。"
	if data.section.length()>200 or data.placement.length()>2000 or data.notes.length()>4000: return "说明过长：段落最多200字，插入位置2000字，备注4000字。"
	return ""

static func defaults(source: String, path: String, saved_hash: String, copy: bool) -> Dictionary:
	var parsed := read(source)
	if not parsed.error.is_empty(): return parsed
	var data: Dictionary = parsed.data.duplicate(true)
	if data.is_empty():
		data={"schema_version":1,"purpose":"author_handoff","id":"handoff_"+Crypto.new().generate_random_bytes(8).hex_encode(),"title":"新剧情" if path.is_empty() else path.get_file().get_basename(),"section":"","placement":"","notes":"","source_script":"","source_sha256":""}
		if path==INTRO: data.title="港口开篇";data.section="序章 · 到达港口"
	if copy and not path.is_empty():
		data.id="handoff_"+Crypto.new().generate_random_bytes(8).hex_encode()
		data.source_script=path;data.source_sha256=saved_hash
	return {"error":"","data":data}

static func apply(source: String, data: Dictionary) -> Dictionary:
	var parsed := read(source)
	if not parsed.error.is_empty(): return parsed
	var error := validate(data)
	if not error.is_empty(): return {"error":error}
	var header := PackedStringArray([BEGIN])
	for line: String in JSON.stringify(data,"\t").split("\n"): header.append("// "+line)
	header.append(END)
	return {"error":"","text":"\n".join(header)+"\n"+str(parsed.body),"line_delta":header.size()-int(parsed.prefix_lines)}

static func protected_target(path: String, registry_path: String = TDStoryEvents.PATH) -> Dictionary:
	var normalized := path.replace("\\","/").simplify_path().to_lower()
	if normalized == INTRO: return {"error":"","protected":true}
	var file := FileAccess.open(registry_path, FileAccess.READ)
	if file == null: return {"error":"无法读取剧情触发登记，请交给开发者检查。","protected":true}
	var json := JSON.new()
	var parse_result := json.parse(file.get_as_text()); file.close()
	if parse_result != OK: return {"error":"剧情触发登记损坏，请交给开发者检查。","protected":true}
	var events := TDStoryEvents.new(registry_path)
	if not events.error.is_empty(): return {"error":"无法确认已接入的剧情，请先修复触发登记："+events.error,"protected":true}
	for row: Dictionary in events.definitions:
		if str(row.script_path).replace("\\","/").simplify_path().to_lower()==normalized: return {"error":"","protected":true}
	return {"error":"","protected":false}
