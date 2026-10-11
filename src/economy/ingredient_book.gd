class_name TDIngredientBook
extends RefCounted

const SOURCE := "res://doc/source/ingredients.json"

var categories: Array = []
var items: Dictionary = {}

func load_file(path: String = SOURCE) -> TDOutcome:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return TDOutcome.new(false, "READ_FAILED", path)
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return TDOutcome.new(false, "INVALID_JSON", "%s:%d" % [path, parser.get_error_line()])
	return load_data(parser.data)

func load_data(raw: Variant) -> TDOutcome:
	if not raw is Dictionary or not (raw as Dictionary).get("categories") is Array:
		return TDOutcome.new(false, "INVALID_CONTENT", "食材表必须含分类")
	var next_categories: Array = []
	var next_items := {}
	for group: Variant in (raw as Dictionary)["categories"]:
		if not group is Dictionary or String(group.get("id", "")) == "" or not group.get("items") is Array:
			return TDOutcome.new(false, "INVALID_CONTENT", "食材分类无效")
		var rows: Array = []
		for item: Variant in group["items"]:
			if not item is Dictionary or String(item.get("id", "")) == "" or String(item.get("name", "")) == "":
				return TDOutcome.new(false, "INVALID_CONTENT", "食材缺少编号或名字")
			var id := String(item["id"])
			if next_items.has(id):
				return TDOutcome.new(false, "DUPLICATE_ID", id)
			var row := {
				"id": id,
				"name": String(item["name"]),
				"category": String(group["id"]),
				"category_name": String(group.get("name", "")),
				"sub": String(item.get("sub", "")),
			}
			next_items[id] = row
			rows.append(id)
		next_categories.append({"id": String(group["id"]), "name": String(group.get("name", "")), "items": rows})
	if next_items.is_empty():
		return TDOutcome.new(false, "INVALID_CONTENT", "食材表是空的")
	categories = next_categories
	items = next_items
	return TDOutcome.new(true, "OK", "")

func get_item(id: String) -> Dictionary:
	if not items.has(id):
		return {}
	return (items[id] as Dictionary).duplicate(true)

func category_ids() -> Array[String]:
	var result: Array[String] = []
	for group: Variant in categories:
		result.append(String((group as Dictionary)["id"]))
	return result

func ids_in(category_id: String) -> Array[String]:
	for group: Variant in categories:
		if String((group as Dictionary)["id"]) == category_id:
			var result: Array[String] = []
			for id: Variant in (group as Dictionary)["items"]:
				result.append(String(id))
			return result
	return []
