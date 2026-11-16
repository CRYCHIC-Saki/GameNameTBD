@tool
extends RefCounted
## Editor-only import transaction. Originals are read-only; every target is explicit.
const CAST := "content/story/vn/config/characters/_characters.tres"
const BG := "content/story/vn/backgrounds/"
const PORTRAITS := "content/story/vn/portraits/"
const IMAGES := "assets/story/imported/"
const PRESET := "export_presets.cfg"
const BG_LABELS := {"blank":"纯黑","arrival-coast-v1":"港口","soup-stall-v1":"食材铺","restaurant-v1":"餐厅","dining-table-v1":"餐桌"}
var root: String = "res://"
var fail_after_writes: int = -1 # Isolated fault-injection tests only.

func path(relative: String) -> String:
	return root.path_join(relative)

func _files(directory: String) -> PackedStringArray:
	return DirAccess.get_files_at(directory) if DirAccess.dir_exists_absolute(directory) else PackedStringArray()

static func inspect_image(source: String) -> Dictionary:
	if source.get_extension().to_lower() not in ["png","jpg","jpeg","webp"]: return {"error":"请选择 PNG、JPG 或 WebP 图片。"}
	var file := FileAccess.open(source,FileAccess.READ)
	if file == null: return {"error":"无法读取所选图片。"}
	if file.get_length() > 64*1024*1024: return {"error":"图片超过64MB，请先缩小后导入。"}
	var bytes := file.get_buffer(file.get_length()); file.close()
	if bytes.size() < 16: return {"error":"图片文件不完整。"}
	var extension := source.get_extension().to_lower()
	var signature_ok := true
	if extension == "png": signature_ok = bytes.slice(0,8) == PackedByteArray([137,80,78,71,13,10,26,10])
	elif extension in ["jpg","jpeg"]: signature_ok = bytes.slice(0,3) == PackedByteArray([255,216,255])
	elif extension == "webp": signature_ok = bytes.slice(0,4).get_string_from_ascii() == "RIFF" and bytes.slice(8,12).get_string_from_ascii() == "WEBP"
	if not signature_ok: return {"error":"文件内容与图片格式不符，无法导入。"}
	var image := Image.new()
	var error := image.load(source)
	if error != OK or image.is_empty(): return {"error":"图片损坏或无法解码。"}
	if maxi(image.get_width(),image.get_height()) > 8192: return {"error":"图片边长超过8192像素，请先缩小。"}
	return {"error":"","image":image,"bytes":bytes,"extension":source.get_extension().to_lower()}

static func resource_title(resource_path: String, fallback: String) -> String:
	if not FileAccess.file_exists(resource_path): return fallback
	# Read metadata without loading a texture that may still be importing.
	for line: String in FileAccess.get_file_as_string(resource_path).split("\n"):
		if line.begins_with("metadata/td_display_name = "):
			var value: Variant = str_to_var(line.trim_prefix("metadata/td_display_name = ").strip_edges())
			if value is String: return value
	return fallback

func prepare(source: String, kind: String, title: String, character_id: String = "") -> Dictionary:
	title = title.strip_edges()
	if title.is_empty() or title.length() > 60 or title.contains("\n"): return {"error":"请输入1–60字的名称。"}
	if kind not in ["background","character","expression"]: return {"error":"未知素材类型。"}
	var inspected := inspect_image(source)
	if not str(inspected.error).is_empty(): return inspected
	var cast_path := path(CAST)
	if not FileAccess.file_exists(cast_path): return {"error":"角色登记表缺失。"}
	var cast_hash := FileAccess.get_sha256(cast_path)
	var cast: VNEngineCast = ResourceLoader.load(cast_path,"",ResourceLoader.CACHE_MODE_IGNORE)
	if cast == null: return {"error":"角色登记表无法读取。"}
	var actor: VNEngineCastMember
	if kind == "character":
		for entry: VNEngineCastMember in cast.characters:
			if entry.display_name == title: return {"error":"已有同名角色；请选择“角色新表情”，不会覆盖原角色。"}
	elif kind == "expression":
		actor = cast.get_entry(character_id)
		if actor == null or not character_id.is_valid_ascii_identifier(): return {"error":"请先选择已有角色。"}
		for file: String in _files(path(PORTRAITS+character_id)):
			if file.ends_with("_mid.tres"):
				var expression := file.trim_prefix(character_id+"_base_base_").trim_suffix("_mid.tres")
				var fallback := str({"calm":"平静","happy":"愉快"}.get(expression,expression))
				if title in [expression,resource_title(path(PORTRAITS+character_id+"/"+file),fallback)]: return {"error":"这个角色已有同名表情，请换一个名称。"}
	else:
		for file: String in _files(path(BG)):
			var fallback := str(BG_LABELS.get(file.get_basename(),file.get_basename()))
			if file.ends_with(".tres") and title in [file.get_basename(),resource_title(path(BG+file),fallback)]: return {"error":"已有同名背景，请换一个名称。"}
	var prefix := "bg_" if kind == "background" else ("actor_" if kind == "character" else "expr_")
	var token := prefix+(title+FileAccess.get_sha256(source)).sha256_text().left(12)
	var expression := "calm" if kind == "character" else token
	if kind == "character": character_id = token
	var reference := path(BG+token+".tres") if kind == "background" else path(PORTRAITS+character_id+"/"+character_id+"_base_base_"+expression+"_mid.tres")
	var image_path := path(IMAGES+token+"."+str(inspected.extension))
	if FileAccess.file_exists(reference) or FileAccess.file_exists(image_path) or FileAccess.file_exists(image_path+".import") or (kind == "character" and cast.get_entry(character_id) != null): return {"error":"这份素材已导入，或编号冲突；请从现有素材库选择。"}
	var preset_path := path(PRESET)
	var preset := ConfigFile.new()
	if preset.load(preset_path) != OK or preset.get_value("preset.0","name","") != "Windows Framework Demo" or preset.get_value("preset.0","export_filter","") != "resources": return {"error":"发布预设已改变，无法安全登记。请先由集成者核对。"}
	var export_hash := FileAccess.get_sha256(preset_path)
	var exports: PackedStringArray = preset.get_value("preset.0","export_files",PackedStringArray())
	for target: String in [image_path,reference]:
		if target not in exports: exports.append(target)
	var preset_lines := FileAccess.get_file_as_string(preset_path).split("\n")
	var found := false
	var section := ""
	for i in preset_lines.size():
		var line := preset_lines[i].strip_edges()
		if line.begins_with("["): section = line
		if section == "[preset.0]" and line.begins_with("export_files="):
			preset_lines[i] = "export_files="+var_to_str(exports)+( "\r" if preset_lines[i].ends_with("\r") else "")
			found = true; break
	if not found: return {"error":"发布资源列表缺失，未修改任何素材。"}
	var resource_text := "[gd_resource type=\"AtlasTexture\" format=3]\n\n[ext_resource type=\"Texture2D\" path=%s id=\"1\"]\n\n[resource]\natlas = ExtResource(\"1\")\nfilter_clip = true\nmetadata/td_display_name = %s\n" % [var_to_str(image_path),var_to_str("平静" if kind == "character" else title)]
	var writes: Array[Dictionary] = [
		{"path":image_path,"bytes":inspected.bytes,"expected":""},
		{"path":reference,"bytes":resource_text.to_utf8_buffer(),"expected":""}]
	if kind == "character":
		var entry := VNEngineCastMember.new(); entry.id = character_id; entry.display_name = title
		entry.default_outfit = "base"; entry.default_pose = "base"; entry.default_expression = "calm"; entry.default_shot = "mid"
		entry.sprite_scale = .64; entry.side_image = false; entry.blip = "off"
		cast.characters.append(entry)
		var staged := path(".godot/td_vn_editor/import_staging/cast_"+str(Time.get_ticks_usec())+".tres")
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(staged.get_base_dir()))
		if ResourceSaver.save(cast,staged) != OK: return {"error":"无法准备角色登记。"}
		writes.append({"path":cast_path,"bytes":FileAccess.get_file_as_bytes(staged),"expected":cast_hash})
		DirAccess.remove_absolute(ProjectSettings.globalize_path(staged))
	writes.append({"path":preset_path,"bytes":"\n".join(preset_lines).to_utf8_buffer(),"expected":export_hash})
	return {"error":"","kind":kind,"id":token,"character":character_id,"expression":expression,"reference":reference,"image":image_path,"title":title,"writes":writes,"cast_hash":cast_hash}

func commit(plan: Dictionary) -> Dictionary:
	if not str(plan.get("error","")).is_empty() or not plan.has("writes"): return {"error":"素材尚未准备好。"}
	if FileAccess.get_sha256(path(CAST)) != plan.cast_hash: return {"error":"角色登记已被其他操作修改，请重新导入。"}
	for write: Dictionary in plan.writes:
		if _hash(write.path) != write.expected: return {"error":"素材或发布设置已被其他操作修改，请重新导入。"}
	var backups := path(".godot/td_vn_editor/import_backups/"+str(Time.get_unix_time_from_system()).replace(".","-")+"-"+str(Time.get_ticks_usec()))
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(backups)) != OK: return {"error":"无法建立导入备份。"}
	var applied: Array[Dictionary] = []
	var failure := ""
	for write: Dictionary in plan.writes:
		if _hash(write.path) != write.expected: failure = "目标文件发生变化。"; break
		var old := FileAccess.get_file_as_bytes(write.path) if FileAccess.file_exists(write.path) else PackedByteArray()
		if not str(write.expected).is_empty() and _write(backups.path_join(str(applied.size())+".bak"),old) != OK: failure = "无法备份原登记。"; break
		if _write(write.path,write.bytes) != OK: failure = "无法写入素材或登记。"; break
		applied.append({"path":write.path,"old":old,"existed":not str(write.expected).is_empty(),"new_hash":_hash(write.path)})
		if applied.size() == fail_after_writes: failure = "测试注入：导入写入中断。"; break
	if not failure.is_empty():
		var rollback_error := rollback(applied)
		return {"error":failure+(" 已恢复本次导入前的文件。" if rollback_error.is_empty() else " "+rollback_error),"backup":backups}
	var result := plan.duplicate(); result.erase("writes"); result["applied"] = applied; result["backup"] = backups
	return result

func rollback(applied: Array) -> String:
	var entries := applied.duplicate(); entries.reverse()
	for item: Dictionary in entries:
		if _hash(item.path) != item.new_hash: return "恢复时发现他人修改，已保留文件和备份，请人工检查。"
		if item.existed:
			if _write(item.path,item.old) != OK: return "恢复失败，原登记已保存在导入备份中。"
		elif DirAccess.remove_absolute(ProjectSettings.globalize_path(item.path)) != OK: return "无法移除本次新文件，请检查导入备份。"
	return ""

func _hash(target: String) -> String:
	return FileAccess.get_sha256(target) if FileAccess.file_exists(target) else ""

func _write(target: String, bytes: PackedByteArray) -> Error:
	var directory := ProjectSettings.globalize_path(target.get_base_dir())
	var error := DirAccess.make_dir_recursive_absolute(directory)
	if error != OK: return error
	var temp := target+"."+str(Time.get_ticks_usec())+".importing"
	var file := FileAccess.open(temp,FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_buffer(bytes); file.flush(); file.close()
	if FileAccess.get_file_as_bytes(temp) != bytes:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp)); return ERR_FILE_CORRUPT
	error = DirAccess.rename_absolute(ProjectSettings.globalize_path(temp),ProjectSettings.globalize_path(target))
	if error != OK: DirAccess.remove_absolute(ProjectSettings.globalize_path(temp))
	return error
