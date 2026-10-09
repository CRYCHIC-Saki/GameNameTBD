class_name TDKitchenHandling
extends RefCounted
## Ownership of portable food, separate from scene positions and cooking rules.
var hand: TDCookingSession
var board: TDCookingSession
var hand_kind: String = ""
var _catalog: TDCookingCatalog
var _serial: int = 0

func _init(catalog: TDCookingCatalog) -> void:
	_catalog = catalog

func pick(ingredient_id: String) -> TDOutcome:
	if hand != null: return TDOutcome.new(false, "HANDS_FULL", "手上已有东西，先放到菜板或锅里。")
	_serial += 1
	var candidate := TDCookingSession.new("portable-%d" % _serial, _serial, _catalog.for_recipe("tomato_egg"), {"pc_controls":true})
	var request := TDRequest.new("portable-%d" % _serial, _serial, "pickup-%d" % _serial, "add", 0, {"ingredient_id":ingredient_id,"amount":1})
	request.schema_version = 3
	var result := candidate.begin(request)
	if not result.ok: return result
	hand = candidate; hand_kind = "ingredient"
	return TDOutcome.new(true, "PICKED", "已拿起食材，走到菜板或灶台按 E。")

func put_board() -> TDOutcome:
	if hand == null or hand_kind != "ingredient": return TDOutcome.new(false, "NO_INGREDIENT", "先去料箱拿食材。")
	if board != null: return TDOutcome.new(false, "BOARD_OCCUPIED", "菜板上还有一份食材。")
	board = hand; hand = null; hand_kind = ""
	return TDOutcome.new(true, "ON_BOARD")

func take_board() -> TDOutcome:
	if hand != null: return TDOutcome.new(false, "HANDS_FULL")
	if board == null: return TDOutcome.new(false, "EMPTY_BOARD")
	if board.snapshot().to_dict().state == "operating": return TDOutcome.new(false, "BUSY", "先完成或取消备菜。")
	hand = board; board = null; hand_kind = "ingredient"
	return TDOutcome.new(true, "PICKED", "备料已拿起，走到灶台按 E 入锅。")

func put_pot(destination: TDCookingSession) -> TDOutcome:
	if hand == null or hand_kind != "ingredient": return TDOutcome.new(false, "NO_INGREDIENT")
	var food: Dictionary = hand.snapshot().to_dict().ingredients
	if food.is_empty(): return TDOutcome.new(false, "NO_INGREDIENT")
	_serial += 1
	var result := hand.transfer_to(destination, str(food.keys()[0]), "move-%d" % _serial)
	if result.ok: hand = null; hand_kind = ""
	return result

func take_dish(source: TDCookingSession) -> TDOutcome:
	if hand != null: return TDOutcome.new(false, "HANDS_FULL")
	if source.snapshot().to_dict().state != "plated": return TDOutcome.new(false, "NOT_PLATED")
	hand = source; hand_kind = "dish"
	return TDOutcome.new(true, "DISH_PICKED", "端好盘子，走到出餐台按 E 试吃。")

func clear_dish() -> void:
	if hand_kind == "dish": hand = null; hand_kind = ""

func display() -> Dictionary:
	var held: Dictionary = {}
	if hand != null:
		var dish: Dictionary = hand.snapshot().to_dict()
		held = {"kind":hand_kind,"session_id":dish.session_id,"name":dish.recipe_name if hand_kind == "dish" else dish.ingredients.values()[0].name,"shape":"成品" if hand_kind == "dish" else dish.ingredients.values()[0].shape}
	return {"hand":held,"board_occupied":board != null}

func close() -> void:
	if hand != null and hand_kind == "ingredient": hand.cancel()
	if board != null: board.cancel()
	hand = null; board = null; hand_kind = ""
