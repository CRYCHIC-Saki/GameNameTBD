class_name TDOpeningScript
extends RefCounted
## Read-only runtime transcription. Paragraph numbers refer to the supplied DOCX.
const PATH := "res://content/story/opening.json"
static var _data: Dictionary = {}

static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary: _data=parsed
	return _data.duplicate(true)

static func conversation(scene: String, hero: String, san: int) -> TDDialogue:
	var talk:=TDDialogue.new()
	talk.story_layout(hero,"aling")
	talk.context={"kind":"story","scene":scene}
	var sequences: Dictionary=data().get("scenes",{})
	var rows: Array=sequences.get(scene,[]).duplicate(true)
	if scene in ["verdict_good","verdict_bad"]: rows.append_array(sequences.verdict_tail)
	for row: Dictionary in rows:
		var text: String=str(row.text).replace("{hero}",hero).replace("{san_before}",str(san)).replace("{san_after}",str(maxi(0,san-5)))
		if row.kind=="cg": talk.add_cg(str(row.cg),text,float(row.duration))
		elif row.kind=="ui": talk.add_line("提示","",text,"calm","","ui")
		else:
			var speaker: String="玩家" if row.portrait=="hero" else str(row.speaker)
			talk.add_line(speaker,str(row.portrait),text,str(row.emotion),str(row.action),str(row.get("display_kind","line")))
	return talk
