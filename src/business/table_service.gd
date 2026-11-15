class_name TDTableService
extends RefCounted
## Runtime dishes belong to the shop, not to a guest sprite or kitchen lane.
## Boundary saves require an empty pass; this does not add mid-service saves.
var _owner: WeakRef
var _plates: Array[Dictionary]=[]
var _seen: Dictionary={}
var trial_check: Callable
var trial_received: Callable
const TRIAL_ORDER: String="story:trial"

func _init(shop: TDShopSession) -> void:
	_owner=weakref(shop)

func _shop() -> TDShopSession:
	return _owner.get_ref() as TDShopSession

func empty() -> bool: return _plates.is_empty()
func rows() -> Array[Dictionary]: return _plates.duplicate(true)
func get_plate(id: String) -> Dictionary:
	for plate: Dictionary in _plates:
		if plate.id==id: return plate.duplicate(true)
	return {}
func for_order(id: String) -> Dictionary:
	for plate: Dictionary in _plates:
		if plate.order_id==id: return plate.duplicate(true)
	return {}

func place(order_id: String, dish: Dictionary) -> TDOutcome:
	var shop:=_shop()
	if _seen.has(str(dish.get("dish_id",""))): return TDOutcome.new(false,"DUPLICATE_DISH")
	var checked:=shop.can_deliver(order_id,dish)
	if not checked.ok: return checked
	_plates.append({"id":str(dish.dish_id),"order_id":order_id,"carrier":"","dish":dish.duplicate(true)})
	_seen[str(dish.dish_id)]=true
	shop._kitchen_key=""
	return TDOutcome.new(true,"AT_PASS","已放到出餐口，需端到客人桌边才算送达。",{"order_id":order_id,"dish_id":dish.dish_id})

func place_trial(dish: Dictionary) -> TDOutcome:
	if not trial_check.is_valid(): return TDOutcome.new(false,"NOT_STORY_DELIVERY")
	var checked: TDOutcome=trial_check.call(dish)
	if not checked.ok: return checked
	if dish.get("state")!="plated" or str(dish.get("dish_id","")).is_empty(): return TDOutcome.new(false,"INVALID_DISH")
	if _seen.has(str(dish.dish_id)): return TDOutcome.new(false,"DUPLICATE_DISH")
	if not for_order(TRIAL_ORDER).is_empty(): return TDOutcome.new(false,"TRIAL_AT_PASS","阿铃的菜已在出餐口，请先送到她桌边。")
	_plates.append({"id":str(dish.dish_id),"order_id":TRIAL_ORDER,"carrier":"","dish":dish.duplicate(true)})
	_seen[str(dish.dish_id)]=true
	return TDOutcome.new(true,"AT_PASS","已放到出餐口。回餐厅按 E 取菜，再到阿铃桌边按 E 交给她。")

func reconcile() -> void:
	var shop:=_shop()
	for plate: Dictionary in _plates:
		if plate.order_id==TRIAL_ORDER: continue
		if shop.order(plate.order_id).get("status","") not in ["WAITING","COOKING"]: plate.order_id=""
	for plate: Dictionary in _plates:
		if not str(plate.order_id).is_empty(): continue
		var match_order:=shop.first_order_for(plate.dish)
		if not match_order.is_empty(): plate.order_id=str(match_order.id)
	shop._kitchen_key=""

func take(id: String, carrier: String) -> TDOutcome:
	if carrier.is_empty(): return TDOutcome.new(false,"INVALID_CARRIER")
	for other: Dictionary in _plates:
		if other.carrier==carrier: return TDOutcome.new(false,"HANDS_FULL","先送出或放回手上的菜。")
	for plate: Dictionary in _plates:
		if plate.id!=id: continue
		if not str(plate.carrier).is_empty(): return TDOutcome.new(false,"ALREADY_CLAIMED","这盘菜已被端走。")
		plate.carrier=carrier
		return TDOutcome.new(true,"PICKED_UP","已端起菜，走到对应客人桌边按 E。",plate.duplicate(true))
	return TDOutcome.new(false,"UNKNOWN_PLATE")

func put_back(id: String, carrier: String) -> TDOutcome:
	for plate: Dictionary in _plates:
		if plate.id==id and plate.carrier==carrier and not carrier.is_empty():
			plate.carrier=""
			return TDOutcome.new(true,"RETURNED_TO_PASS","已放回出餐口。")
	return TDOutcome.new(false,"NOT_CARRIER")

func serve(id: String, carrier: String, order_id: String) -> TDOutcome:
	var plate:=get_plate(id)
	if plate.is_empty() or carrier.is_empty() or plate.carrier!=carrier: return TDOutcome.new(false,"NOT_CARRIER")
	if plate.order_id!=order_id or order_id.is_empty(): return TDOutcome.new(false,"WRONG_TABLE","这盘菜不属于这位客人。")
	var result: TDOutcome
	if order_id==TRIAL_ORDER:
		if not trial_received.is_valid(): return TDOutcome.new(false,"TRIAL_UNAVAILABLE")
		result=trial_received.call(plate.dish)
	else: result=_shop()._complete_delivery(order_id,plate.dish)
	if result.ok:
		for i: int in _plates.size():
			if _plates[i].id==id: _plates.remove_at(i);break
		_shop()._kitchen_key=""
	return result

func discard(id: String, carrier: String) -> TDOutcome:
	for i: int in _plates.size():
		var plate: Dictionary=_plates[i]
		if plate.id!=id: continue
		if plate.carrier!=carrier: return TDOutcome.new(false,"NOT_CARRIER")
		_shop()._record("pass_waste",0,{},id,{"dish_id":id,"reason":"discarded"})
		_plates.remove_at(i);_shop()._kitchen_key=""
		return TDOutcome.new(true,"DISCARDED","已丢弃这盘菜；原来耗用的食材不返还。")
	return TDOutcome.new(false,"UNKNOWN_PLATE")

func release_missing_waiters(ids: Array) -> void:
	for plate: Dictionary in _plates:
		if plate.carrier!="" and plate.carrier!="player" and plate.carrier not in ids: plate.carrier=""

func clear_for_night() -> void:
	for plate: Dictionary in _plates:
		_shop()._record("pass_waste",0,{},plate.id,{"dish_id":plate.id,"reason":"night_cleanup"})
	_plates.clear();_shop()._kitchen_key=""

func clear_on_restore() -> void:
	_plates.clear();_seen.clear()
