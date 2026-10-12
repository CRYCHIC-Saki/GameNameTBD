class_name TDRecipeBook
extends RefCounted

var unlocked: Dictionary = {}
var unlock_score: float = 60.0

func learn_starters(dishes: Array) -> void:
	for item: Variant in dishes:
		var dish: Dictionary = item
		if bool(dish.get("starter", false)):
			unlocked[String(dish["id"])] = true

func grant(dish_id: String) -> bool:
	if dish_id == "" or has(dish_id):
		return false
	unlocked[dish_id] = true
	return true

func has(dish_id: String) -> bool:
	return bool(unlocked.get(dish_id, false))

func ids() -> Array[String]:
	var result: Array[String] = []
	for key: Variant in unlocked.keys():
		if bool(unlocked[key]):
			result.append(String(key))
	result.sort()
	return result

func consider(dish_id: String, accepted: bool, presented_score: float) -> Dictionary:
	if dish_id == "":
		return {"learned": false, "code": "NO_DISH"}
	if has(dish_id):
		return {"learned": false, "code": "KNOWN"}
	if not accepted:
		return {"learned": false, "code": "REFUSED"}
	if presented_score < unlock_score:
		return {"learned": false, "code": "LOW_SCORE", "score": presented_score}
	unlocked[dish_id] = true
	return {"learned": true, "code": "LEARNED", "score": presented_score}
