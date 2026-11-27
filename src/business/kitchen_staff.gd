class_name TDKitchenStaff
extends RefCounted
## Owns employee hands and travel. Food/QTE/stock remain the existing kitchen/Shop objects.
signal action_completed(event: Dictionary)
var shop: TDShopSession
var kitchen: TDFullKitchen
var jobs: Dictionary = {}
var people: Dictionary = {}
var board_owner: String = ""
var note: String = ""
var reset_pot: Callable
var _closed: bool = false
var _serial: int = 0
var _speed: float = 230.0
var _handling_sec: float = .4

func _init(owner: TDShopSession, room: TDFullKitchen, reset: Callable) -> void:
	shop=owner; kitchen=room; reset_pot=reset
	_speed=float(shop.catalog.config.get("staff_workflow",{}).get("walk_speed_px_sec",230.0))
	_handling_sec=float(shop.catalog.config.get("staff_workflow",{}).get("handling_sec",.4))
	kitchen.create_staff_preparation()

func paused() -> bool:
	return _closed or kitchen.shared_clock.paused or kitchen.get_tree().paused

func owns(index: int) -> bool:
	return jobs.has(index) and kitchen.lanes[index].snapshot().session_id==jobs[index].session_id

func tick(seconds: float = 0.0) -> void:
	if paused() or not is_finite(seconds) or seconds<0: return
	var cooks: Array=shop.crew.cooks() if shop.crew!=null else []
	var live: Array=[]
	for i: int in cooks.size():
		var id: String=str(cooks[i].id);live.append(id)
		if not people.has(id):
			var point:=kitchen.world.staff_home(i)
			var gait:=TDNpcGait.new();gait.reset(point)
			people[id]={"id":id,"name":str(cooks[i].name),"cuisine_id":cooks[i].get("cuisine_id","cn"),"appearance_variant":cooks[i].get("appearance_variant",0),"index":i,"point":point,"gait":gait,"route":PackedVector2Array(),"route_at":0,"elapsed":0.0}
	for index: int in jobs.keys():
		var job: Dictionary=jobs[index]
		if not owns(index) or job.cook not in live:
			_release(index);continue
		var person: Dictionary=people[job.cook]
		if seconds>0:
			person.elapsed+=seconds
			_move(person,seconds)
			if job.phase in ["pickup","drop","take_board","pickup_dish"]: job.remaining=maxf(0,float(job.remaining)-seconds)
			var hand: TDCookingSession=job.handling.hand
			if hand!=null and job.handling.hand_kind=="ingredient": hand.advance_time(seconds)
		# Resolve an exact-end QTE before selecting the next outer time boundary.
		# Reading its remaining time can resolve it without completing the lane yet.
		if job.phase in ["cut","cook"]:
			var lane: TDCookingLane=kitchen.staff_prep if job.phase=="cut" else kitchen.lanes[index]
			lane.advance(0)
		_settle(job)
		if seconds>0: (person.gait as TDNpcGait).sample(person.point,false,_arrived(person))
	for id: String in people.keys():
		if id not in live:
			if job_for(id).is_empty(): people.erase(id)
			continue
		if job_for(id).is_empty() and seconds>0:
			var person: Dictionary=people[id]
			var home:=kitchen.world.staff_home(int(person.index))
			if _arrived(person) and person.point.distance_to(home)>.01: _route(person,home)
			_move(person,seconds);(person.gait as TDNpcGait).sample(person.point,false,_arrived(person))
	_assign(cooks)

func next_boundary(maximum: float) -> float:
	var result:=maximum
	for index: int in jobs:
		var job: Dictionary=jobs[index];var person: Dictionary=people[job.cook]
		if bool(person.get("route_blocked",false)): continue
		if not _arrived(person):
			result=minf(result,person.point.distance_to(person.route[person.route_at])/_speed)
		elif job.phase in ["pickup","drop","take_board","pickup_dish"]:
			result=minf(result,float(job.remaining))
		elif job.phase in ["cut","cook"]:
			var lane: TDCookingLane=kitchen.staff_prep if job.phase=="cut" else kitchen.lanes[index]
			result=minf(result,lane.next_boundary_sec())
			var recovery: float=float(lane.snapshot().recovery_sec)
			if recovery>0: result=minf(result,recovery)
	return maxf(.0000001,result)

func _assign(cooks: Array) -> void:
	if shop.snapshot().phase not in ["OPEN","DRAINING"]: return
	if not jobs.is_empty(): return
	var families: Array=[]
	for lane: TDCookingLane in kitchen.lanes:
		if owns(lane.lane_index) or not lane.snapshot().ingredients.is_empty() or lane.qte!=null: families.append(lane.base_recipe_id)
	for order: Dictionary in shop.active_orders():
		if not shop.table_service.for_order(str(order.id)).is_empty(): continue
		var family:=shop.family_id(order.recipe_id)
		if family in families: continue
		var cook_id: String=""
		for cook: Dictionary in cooks:
			if job_for(str(cook.id)).is_empty() and shop.cook_can_prepare(cook,order.recipe_id): cook_id=str(cook.id);break
		if cook_id.is_empty(): continue
		var profile:=shop.profile_for(order)
		var recipe: Dictionary=profile.recipe_data(family)
		var station: String=""
		var lane: TDCookingLane=null
		for candidate: TDCookingLane in kitchen.lanes:
			if kitchen.other_pot_in_use(candidate.lane_index): continue
			if jobs.has(candidate.lane_index) or kitchen.handling.hand==candidate.session: continue
			if not candidate.snapshot().ingredients.is_empty() or candidate.qte!=null or candidate.thermal_qte!=null or (candidate.sheet!=null and candidate.sheet.running): continue
			for target: String in TDCuisineKitchen.IDS:
				if (0 if target=="kitchen.stove.left" else 1)==candidate.lane_index and TDCuisineKitchen.accepts(shop.cuisine_id,target,recipe): station=target;break
			if not station.is_empty(): lane=candidate;break
		if lane==null: continue
		var need: Dictionary=shop.catalog.material_needs(profile,family)
		var enough:=true
		for id: String in need:
			if shop.available(id)<int(need[id]): enough=false
		if not enough: note="食材或调料不足，厨师等待补货。";continue
		lane.catalog=profile;lane.new_session(family);lane.session.set_material_sink(shop.consume_materials,shop.available)
		if not lane.use_recipe_profile(profile,family,order.customer).ok: continue
		lane.session.set_production_mode("automatic")
		lane.station_role=str(recipe.get("workstation","stove"))
		lane.external_operator=cook_id
		_serial+=1
		var handling:=TDKitchenHandling.new(profile)
		handling.session_namespace=lane.session_namespace+":staff-%d:"%_serial
		handling.material_sink=shop.consume_materials
		var job: Dictionary={"cook":cook_id,"lane":lane.lane_index,"session_id":lane.snapshot().session_id,"family":family,"profile":profile,"handling":handling,"ingredients":shop.catalog.offer(family).primary.duplicate(),"ingredient_at":0,"phase":"","remaining":0.0,"station":"","pot_station":station}
		jobs[lane.lane_index]=job;families.append(family)
		_go(job,"to_fridge","kitchen.fridge")
		note="厨师按菜谱逐份取料、切配、入锅。"
		return

func _settle(job: Dictionary) -> void:
	var person: Dictionary=people[job.cook]
	var lane: TDCookingLane=kitchen.lanes[job.lane]
	var hands: TDKitchenHandling=job.handling
	if not _arrived(person): return
	match str(job.phase):
		"to_fridge": _hold(job,"pickup")
		"pickup","wait_stock":
			if float(job.remaining)>0: return
			var id: String=job.ingredients[job.ingredient_at]
			var result:=hands.pick(id,job.family,1.0)
			if not result.ok: job.phase="wait_stock";note="等待补货："+id;return
			hands.hand.set_production_mode("automatic")
			_event(job,"picked",id)
			var recipe: Dictionary=(job.profile as TDCookingCatalog).recipe_data(job.family)
			if str(recipe.get("preparation_sheets",{}).get(id,"")).is_empty(): _go(job,"to_pot",job.pot_station)
			else: _board(job)
		"wait_board": _board(job)
		"to_board":
			if board_owner!=job.cook: _board(job);return
			if not hands.put_board().ok: return
			var started:=kitchen.staff_prep.start_automatic_preparation(hands.board,job.profile)
			if not started.ok:
				note="备菜无法开始："+started.code;hands.take_board();board_owner="";job.phase="wait_board";return
			kitchen.staff_prep_active=true;job.phase="cut";person.elapsed=0.0
			_event(job,"cut_started",job.ingredients[job.ingredient_at])
		"cut":
			if kitchen.staff_prep.qte!=null or kitchen.staff_prep.thermal_qte!=null: return
			if kitchen.staff_prep.sheet!=null and kitchen.staff_prep.sheet.running: return
			if float(kitchen.staff_prep.snapshot().recovery_sec)>0.000001: return
			kitchen.staff_prep_active=false
			_event(job,"cut_finished",job.ingredients[job.ingredient_at]);_hold(job,"take_board")
		"take_board":
			if float(job.remaining)>0: return
			if not hands.take_board().ok: return
			board_owner="";_go(job,"to_pot",job.pot_station)
		"to_pot": _hold(job,"drop")
		"drop":
			if float(job.remaining)>0: return
			var result:=hands.put_pot(lane.session)
			if not result.ok: note="入锅失败："+result.code;return
			_event(job,"ingredient_deposited",job.ingredients[job.ingredient_at])
			job.ingredient_at+=1
			if job.ingredient_at<job.ingredients.size(): _go(job,"to_fridge","kitchen.fridge")
			else:
				var started:=lane.start_automatic()
				if not started.ok: note="开火失败："+started.code;return
				job.phase="cook";person.elapsed=0.0;_event(job,"cook_started")
		"cook":
			if lane.snapshot().state=="plated": _hold(job,"pickup_dish")
		"pickup_dish":
			if float(job.remaining)>0 or not hands.take_dish(lane.session).ok: return
			_event(job,"dish_picked");_go(job,"to_pass","kitchen.serve")
		"to_pass","pass":
			job.phase="pass"
			var order:=shop.first_order_for(lane.snapshot())
			if order.is_empty() or not shop.can_deliver(order.id,lane.snapshot()).ok: note="成品已端到出餐口，等待同菜订单。";return
			var result:=lane.perform("deliver")
			if result.ok:
				_event(job,"dish_deposited");hands.clear_dish();jobs.erase(job.lane)
				reset_pot.call(lane)

func _board(job: Dictionary) -> void:
	if board_owner=="" and kitchen.handling.board==null and kitchen.prep.qte==null:
		board_owner=job.cook;_go(job,"to_board","kitchen.board")
	else:
		job.phase="wait_board";job.station="kitchen.board"
		_route(people[job.cook],kitchen.world.staff_waiting_point(int(people[job.cook].index)))

func _hold(job: Dictionary, phase: String) -> void:
	job.phase=phase;job.remaining=_handling_sec;people[job.cook].elapsed=0.0

func _go(job: Dictionary, phase: String, station: String) -> void:
	job.phase=phase;job.station=station;people[job.cook].elapsed=0.0
	var slot: int=int(people[job.cook].index) if station=="kitchen.fridge" else 0
	_route(people[job.cook],kitchen.world.staff_approach(station,slot))

func _route(person: Dictionary, target: Vector2) -> void:
	var route:=PackedVector2Array()
	var previous: Vector2=person.point
	for point: Vector2 in kitchen.world.staff_route(person.point,target):
		if previous.distance_to(point)>.000001: route.append(point)
		previous=point
	person.route=route;person.route_at=0
	person.route_blocked=route.is_empty() and person.point.distance_to(target)>.01
	if person.route_blocked: note="通往工位的道路不通，厨师暂停操作。"

func _arrived(person: Dictionary) -> bool:
	return not bool(person.get("route_blocked",false)) and int(person.route_at)>=(person.route as PackedVector2Array).size()

func _move(person: Dictionary, seconds: float) -> void:
	if bool(person.get("route_blocked",false)): return
	var remaining: float=seconds*_speed
	while remaining>0.0000001 and not _arrived(person):
		var target: Vector2=person.route[person.route_at]
		var distance: float=person.point.distance_to(target)
		var used:=minf(remaining,distance)
		person.point=person.point.move_toward(target,used);remaining-=used
		if distance<=used+.000001: person.point=target;person.route_at+=1

func job_for(id: String) -> Dictionary:
	for index: int in jobs:
		if jobs[index].cook==id: return jobs[index]
	return {}

func rows() -> Array:
	var result: Array=[]
	for id: String in people:
		var person: Dictionary=people[id];var job:=job_for(id)
		var phase: String=str(job.get("phase","idle"))
		var label: String={"idle":"待命","to_fridge":"去取料","pickup":"取食材","wait_stock":"等待补货","wait_board":"等待砧板","to_board":"送去切配","cut":"切菜","take_board":"拿起切配品","to_pot":"送食材入锅","drop":"放入锅中","cook":"做菜","pickup_dish":"端起成品","to_pass":"端菜去出餐口","pass":"等待出餐"}.get(phase,phase)
		if phase=="cook":
			label=kitchen.lanes[job.lane].cook_step()
			if label in ["取料",""]: label="等待下一拍"
		var carried: String=""
		var held: Dictionary={}
		if not job.is_empty():
			var hands: TDKitchenHandling=job.handling
			held = hands.display().hand
			if not held.is_empty(): carried="dish" if hands.hand_kind=="dish" else str(held.id)
		var gait: TDNpcGait=person.gait
		result.append({"id":id,"name":person.name,"cuisine_id":person.cuisine_id,"appearance_variant":person.appearance_variant,"index":person.index,"point":person.point,"facing":gait.facing,"frame":gait.frame,"phase":phase,"action":label,"elapsed":person.elapsed,"held":held,"carried":carried,"visual_seconds":kitchen.shared_clock.game_sec})
	return result

func extra_snapshots() -> Array:
	var result: Array=[]
	for index: int in jobs:
		var hands: TDKitchenHandling=jobs[index].handling
		for source: TDCookingSession in [hands.hand,hands.board]:
			if source!=null and hands.hand_kind!="dish": result.append({"location":"loose","dish":source.snapshot().to_dict()})
	return result

func _event(job: Dictionary, action: String, ingredient: String="") -> void:
	action_completed.emit({"action":action,"ingredient":ingredient,"cook":job.cook,"lane":job.lane,"session_id":job.session_id,"position":people[job.cook].point,"time":kitchen.shared_clock.game_sec})

func _return_food(hands: TDKitchenHandling) -> TDOutcome:
	if hands.hand==null or hands.hand_kind!="ingredient": return TDOutcome.new(true)
	var food:=hands.hand.portable_data()
	if not food.ok: return food
	var result:=shop.store_food(food.data)
	if result.ok: hands.clear_ingredient()
	return result

func _release(index: int) -> TDOutcome:
	var job: Dictionary=jobs[index];var hands: TDKitchenHandling=job.handling
	if board_owner==job.cook:
		kitchen.staff_prep.cancel_operation();kitchen.staff_prep_active=false
		if hands.board!=null:
			var taken:=hands.take_board()
			if not taken.ok: return taken
		board_owner=""
	var returned:=_return_food(hands)
	if not returned.ok: note="员工食材归还失败："+returned.code;return returned
	if owns(index): kitchen.lanes[index].external_operator=""
	hands.clear_dish();hands.close();jobs.erase(index)
	return TDOutcome.new(true)

func release_all() -> TDOutcome:
	for index: int in jobs.keys():
		var result:=_release(index)
		if not result.ok: return result
	return TDOutcome.new(true)

func close() -> void:
	_closed=true
	for job: Dictionary in jobs.values(): (job.handling as TDKitchenHandling).close()
	jobs.clear();people.clear();board_owner="";reset_pot=Callable()
