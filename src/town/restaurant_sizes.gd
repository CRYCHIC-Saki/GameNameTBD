class_name TDRestaurantSizes
extends RefCounted

const IDS: Array[String] = ["small", "medium", "large", "huge"]

static func name_of(size_id: String) -> String:
	match size_id:
		"medium":
			return "中"
		"large":
			return "大"
		"huge":
			return "超大"
		_:
			return "小"

static func footprint(size_id: String) -> Vector2i:
	match size_id:
		"medium":
			return Vector2i(4, 6)
		"large":
			return Vector2i(6, 9)
		"huge":
			return Vector2i(12, 18)
		_:
			return Vector2i(3, 4)

static func interior(size_id: String) -> Vector2i:
	var foot := footprint(size_id)
	return Vector2i(maxi(8, foot.x * 2), maxi(8, foot.y * 2))

static func upkeep(size_id: String) -> int:
	var foot := footprint(size_id)
	return maxi(1, foot.x * foot.y / 2)

static func next(size_id: String) -> String:
	var index := IDS.find(size_id)
	if index < 0:
		return "small"
	return IDS[(index + 1) % IDS.size()]
