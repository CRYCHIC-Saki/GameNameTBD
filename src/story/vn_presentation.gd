class_name TDVNPresentation
extends RefCounted
## Presentation adapter only. The host still owns tasks, choices and save effects.
const ACTORS: Array[String] = ["hero", "aling", "chen", "luo"]
const MOODS: Array[String] = ["calm", "happy", "surprised", "puzzled", "angry", "sad"]
const CG_BACKGROUNDS := {
	"arrival":"harbor", "hungry":"harbor", "messenger":"harbor",
	"soup_stall":"town-china", "black_soup":"cg-black-soup", "reflection":"cg-black-soup",
	"intervene":"town-china", "ledger":"town-china", "uncover":"cg-kitchen",
	"supplies":"cg-kitchen", "tasting":"restaurant", "broadcast":"restaurant",
	"hesitate":"restaurant", "eat_again":"restaurant", "certificate":"restaurant",
	"sign":"town-china", "fire":"cg-kitchen"
}

static func chapter(id: String) -> Dictionary:
	if not OS.has_feature("editor") and not id.begins_with("revised_"): return {}
	var presentation: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/story/vn/presentation.json"))
	var entry: Dictionary = presentation.chapters.get(id, {})
	if entry.is_empty(): return {}
	return {"id":id, "title":entry.get("title", "小镇纪事"), "script_path":entry.path}

static func background_for(place: String) -> String:
	var towns := {"chengdu":"town-china", "tokyo":"town-japan", "paris":"town-europe", "mexico_city":"town-mexico", "bangkok":"town-seasia"}
	for town: String in towns:
		if place.contains(town): return towns[town]
	if place in ["harbor", "port"]: return "harbor"
	if place in ["restaurant", "kitchen"]: return "restaurant"
	if place == "cottage": return "home"
	for region: String in ["japan", "europe", "mexico", "seasia"]:
		if place.contains(region): return "town-" + region
	return "town-china"

static func text_line(value: String) -> String:
	# Native parser accepts escaped newlines; protect script headers and rich text.
	return value.replace("\\", "\\\\").replace("\r", "").replace("\n", "\\n")

static func speaker_id(beat: Dictionary) -> String:
	var who := str(beat.get("portrait", ""))
	if who in ACTORS: return who
	return "narrator" if who.is_empty() or who == "page" else "voice_" + str(str(beat.get("speaker", who)).sha256_text()).left(12)

static func line(beat: Dictionary, number: int) -> String:
	var result := "# beat_%d\n" % number
	if beat.get("display_kind") == "cg":
		for who: String in ACTORS: result += "@hide %s with instant\n" % who
		result += "@bg %s with instant 0\n" % str(CG_BACKGROUNDS.get(beat.get("cg", ""), "restaurant"))
	elif str(beat.get("portrait", "")) in ACTORS and beat.get("display_kind") != "offscreen":
		var who := str(beat.portrait)
		var mood := str(beat.get("emotion", "calm"))
		if mood not in MOODS: mood = "calm"
		# Keep the protagonist plus one counterpart, never stack overlapping NPCs.
		if who != "hero":
			for other: String in ACTORS:
				if other not in ["hero", who]: result += "@hide %s with instant\n" % other
		result += "@show %s %s at %s with instant\n" % [who, mood, TDVNLayout.half_body("left" if who == "hero" else "right",who)]
	if beat.get("action") == "enter_name": result += "@td_name hero\n"
	result += "%s: %s\n\n" % [speaker_id(beat), text_line(str(beat.get("text", "")))]
	return result

static func compile(talk: TDDialogue) -> String:
	var result := "# start\n@bg %s with instant 0\n\n" % str(talk.context.get("vn_background", "town-china"))
	var branches: Array[Dictionary] = []
	for i: int in talk._beats.size():
		var beat: Dictionary = talk._beats[i]
		if beat.get("kind") != "choice":
			result += line(beat, i)
			continue
		result += "# choice_%d\n" % i
		var options: Array = beat.get("options", [])
		for j: int in options.size():
			var option: Dictionary = options[j]
			var label := "answer_%d_%d" % [i, j]
			result += "- %s -> %s\n" % [text_line(str(option.get("label", option.get("id", "")))), label]
			branches.append({"label":label, "next":"continue_%d" % i, "option":option, "i":i, "j":j})
		result += "\n# continue_%d\n" % i
	result += "# finish\n@end\n\n"
	for branch: Dictionary in branches:
		var option: Dictionary = branch.option
		result += "# %s\n@td_pick %s\n" % [branch.label, str(option.get("id", ""))]
		result += "hero: %s\n\n" % text_line(str(option.get("label", "")))
		result += line({"portrait":option.get("portrait", ""), "speaker":option.get("speaker", ""), "text":option.get("text", "")}, 10000 + int(branch.i)*100 + int(branch.j))
		result += "@jump %s\n\n" % branch.next
	return result
