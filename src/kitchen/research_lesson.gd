class_name TDResearchLesson
extends Control
## Isolated practice supply; all operation timing, input and food rules are the kitchen's.
signal pause_requested
signal cancel_requested
var clock:=TDClock.new()
var token:String=""
var kitchen:TDFullKitchen
var definition:Dictionary={}
var _service:TDServiceCatalog
var _recipe:Dictionary={}
var _pot_index:int=0
var _remaining:Array=[]
var _preparing:bool=false
var _started:bool=false
var _done:bool=false
var _closed:bool=false
var _error:String=""
var _result:Dictionary={}

func configure(chart:Dictionary) -> TDOutcome:
	definition=chart.duplicate(true)
	_service=TDServiceCatalog.new()
	var loaded:=_service.load_file()
	if not loaded.ok: return loaded
	loaded=TDResearchRuntime.install(_service)
	if not loaded.ok: return loaded
	_recipe=_service.cooking.for_recipe(str(chart.get("recipe_id",""))).get("recipe",{})
	if _recipe.is_empty(): return TDOutcome.new(false,"UNKNOWN_RECIPE")
	_pot_index=1 if _recipe.cooking_method=="steam" else 0
	return TDOutcome.new(true,"CONFIGURED")

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	kitchen=TDFullKitchen.new(); kitchen.catalog=_service.cooking; kitchen.scorer=TDCustomerScorer.new()
	kitchen.shared_clock=clock; kitchen.auto_advance=false; kitchen.lesson_mode=true
	kitchen.day_san=100.0
	kitchen.library_path="res://content/research/no-player-library.json"
	kitchen.pause_requested.connect(func()->void:pause_requested.emit())
	kitchen.back_requested.connect(func()->void:cancel_requested.emit())
	add_child(kitchen)
	kitchen.stage.navigation_hint="E 放下研习   ·   Esc 暂停"
	kitchen.stage.requirements_hint="依照菜谱完成全部工序 · 80分解锁"
	kitchen.stage.show_san=false
	kitchen.handling.session_namespace=token+":"
	for lane:TDCookingLane in kitchen.lanes+[kitchen.prep]:
		lane.session_namespace=token; lane.input_offset_sec=float(definition.get("input_offset_sec",0))
		lane.new_session(definition.recipe_id)
	_remaining=definition.primary.duplicate()
	_started=true
	_next_ingredient()

func _pot() -> TDCookingLane:
	return kitchen.lanes[_pot_index]

func active_lane() -> TDCookingLane:
	if not _started: return null
	return kitchen.prep if _preparing else _pot()

func _next_ingredient() -> void:
	var recipe:Dictionary=_recipe
	while not _remaining.is_empty():
		var ingredient:String=_remaining.pop_front()
		var picked:=kitchen.handling.pick(ingredient,definition.recipe_id)
		if not picked.ok: _error=picked.code; return
		if recipe.preparation_sheets.has(ingredient):
			kitchen.handling.put_board(); kitchen.prep.bind_preparation(kitchen.handling.board)
			var started:=kitchen.prep.start_preparation()
			if not started.ok: _error=started.code; return
			_preparing=true; kitchen.open_station_view("kitchen.board"); return
		var placed:=kitchen.handling.put_pot(_pot().session)
		if not placed.ok: _error=placed.code; return
	_preparing=false
	var result:=_pot().start_sheet(recipe.guided_profile)
	if not result.ok: _error=result.code; return
	kitchen.open_station_view("kitchen.steamer" if recipe.cooking_method=="steam" else "kitchen.stove.left")

func advance(seconds:float) -> TDOutcome:
	if _closed: return TDOutcome.new(false,"CANCELLED")
	if not _started: return TDOutcome.new(false,"NOT_READY")
	if not is_finite(seconds) or seconds<0: return TDOutcome.new(false,"INVALID_TIME")
	if not _done and not clock.paused and _error.is_empty():
		# Bound by authored events so a long frame never skips preparation transfers.
		var remaining:float=seconds
		for iteration:int in 4096:
			var lane:=active_lane()
			var span:float=minf(remaining,maxf(.00001,lane.next_boundary_sec()))
			kitchen.advance(span); remaining-=span
			if lane.sheet!=null and not lane.sheet.running and lane.qte==null and lane.thermal_qte==null:
				if _preparing:
					var taken:=kitchen.handling.take_board()
					if not taken.ok: _error=taken.code; break
					var placed:=kitchen.handling.put_pot(_pot().session)
					if not placed.ok: _error=placed.code; break
					_next_ingredient()
				else:
					_done=true; kitchen.beat_audio.stop(); break
			if remaining<=.00000001 or not _error.is_empty(): break
	return update()

func input_action(action:String,pressed:bool,value:float=1.0) -> TDOutcome:
	if _closed or _done: return TDOutcome.new(false,"ALREADY_FINISHED")
	if not _started: return TDOutcome.new(false,"NOT_READY")
	if clock.paused: return TDOutcome.new(false,"PAUSED")
	return active_lane().input_action(action,pressed,value)

func update() -> TDOutcome:
	if not _error.is_empty(): return TDOutcome.new(false,_error)
	var data:Dictionary={"ready_to_finish":_done,"quality":0.0,"modules":{},"lesson_version":definition.get("version",2)}
	if _started and not _closed:
		data.modules=_pot().session.module_scores()
		var weight:float=0; var weighted:float=0
		for module:Dictionary in data.modules.values():
			weight+=float(module.weight); weighted+=float(module.quality)*float(module.weight)
		data.quality=weighted/weight if weight>0 else 0.0
		var dish:=_pot().snapshot()
		data.steps=dish.steps
		data.dish_state=dish.state
	return TDOutcome.new(true,"PROGRESS","",data)

func finish() -> TDOutcome:
	if _closed: return TDOutcome.new(false,"CANCELLED")
	if not _result.is_empty(): return TDOutcome.new(false,"ALREADY_FINISHED")
	if not _error.is_empty(): return TDOutcome.new(false,_error)
	if not _done: return TDOutcome.new(false,"NOT_FINISHED")
	_result=update().data
	if _result.get("dish_state")!="plated": _result.quality=0.0
	return TDOutcome.new(true,"COMPLETED","",_result)

func set_paused(value:bool) -> void:
	clock.paused=value
	if kitchen!=null: kitchen.set_paused(value)

func dispose() -> void:
	if _closed: return
	_closed=true
	if kitchen!=null: kitchen.close()
	queue_free()

func _exit_tree() -> void:
	if not _closed and kitchen!=null: kitchen.close()
