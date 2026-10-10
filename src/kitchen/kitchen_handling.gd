class_name TDKitchenHandling
extends RefCounted
## Ownership of portable food, separate from scene positions and cooking rules.
var hand: TDCookingSession
var board: TDCookingSession
var hand_kind: String = ""
var _catalog: TDCookingCatalog
var _serial: int = 0
var session_namespace: String = ""
var material_sink: Callable

func _init(catalog: TDCookingCatalog) -> void:
	_catalog = catalog

func pick(ingredient_id: String, recipe_id: String = "tomato_egg", amount: float = 1.0) -> TDOutcome:
	if hand != null: return TDOutcome.new(false, "HANDS_FULL", "手上已有东西，先放到菜板或锅里。")
	var config: Dictionary = _catalog.for_recipe(recipe_id)
	if config.is_empty(): return TDOutcome.new(false,"UNKNOWN_RECIPE")
	_serial += 1
	var identity: String = session_namespace+"portable-%d" % _serial
	var candidate := TDCookingSession.new(identity, _serial, config, {"pc_controls":true,"document_rules":true})
	candidate.set_material_sink(material_sink)
	var request := TDRequest.new(identity, _serial, "pickup-%d" % _serial, "add", 0, {"ingredient_id":ingredient_id,"amount":amount})
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

func take_ingredient(source: TDCookingSession, instance_id: String) -> TDOutcome:
	if hand!=null: return TDOutcome.new(false,"HANDS_FULL")
	_serial+=1
	var candidate:=TDCookingSession.new(session_namespace+"retrieve-%d"%_serial,_serial,_catalog.for_recipe("service.tomato_egg"),{"pc_controls":true,"document_rules":true})
	candidate.set_material_sink(material_sink)
	var result:=source.transfer_to(candidate,instance_id,"retrieve-%d"%_serial)
	if result.ok: hand=candidate; hand_kind="ingredient"
	return result

func take_stored(data: Dictionary) -> TDOutcome:
	if hand!=null: return TDOutcome.new(false,"HANDS_FULL")
	_serial+=1
	var candidate:=TDCookingSession.new(session_namespace+"stored-%d"%_serial,_serial,_catalog.for_recipe("service.tomato_egg"),{"pc_controls":true,"document_rules":true})
	var result:=candidate.restore_portable(data)
	if result.ok:
		candidate.set_material_sink(material_sink); hand=candidate; hand_kind="ingredient"
	return result

func clear_ingredient() -> void:
	if hand_kind=="ingredient": hand.cancel(); hand=null; hand_kind=""

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
