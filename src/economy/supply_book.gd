class_name TDSupplyBook
extends RefCounted

var stock: Dictionary = {}
var incoming: Array = []
var pipeline: bool = false
var nearby_market: bool = false

func duplicate_state() -> Dictionary:
	return {
		"stock": stock.duplicate(true),
		"incoming": incoming.duplicate(true),
		"pipeline": pipeline,
		"nearby_market": nearby_market,
	}

func same_day() -> bool:
	return pipeline or nearby_market

func order(day: int, item_id: String, amount: int) -> Dictionary:
	var copies := maxi(amount, 1)
	var arrive := day if same_day() else day + 1
	incoming.append({"item_id": item_id, "amount": copies, "arrive": arrive, "ordered_on": day})
	var delivered: Array = []
	if arrive <= day:
		delivered = collect(day)
	return {"arrive": arrive, "delivered": delivered}

func collect(day: int) -> Array:
	var arrived: Array = []
	var rest: Array = []
	for item: Variant in incoming:
		var row: Dictionary = item
		if int(row["arrive"]) <= day:
			var item_id := String(row["item_id"])
			var amount := int(row["amount"])
			stock[item_id] = int(stock.get(item_id, 0)) + amount
			arrived.append(row.duplicate(true))
		else:
			rest.append(row)
	incoming = rest
	return arrived

func count(item_id: String) -> int:
	return int(stock.get(item_id, 0))
