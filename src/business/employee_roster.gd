class_name TDEmployeeRoster
extends RefCounted
## Slot-owned employees. Shop owns all cash; this object owns identity and assignment.
const SOURCE := "res://content/employees.json"
const HOME := "player_diner"
const ROLES := ["manager", "cook", "waiter"]
const GENERATED_PREFIX := "employee.v1."
var _surnames: Dictionary = {}
var _given_names: Dictionary = {}
var _generated_defs: Dictionary = {}
var _fixed_defs: Dictionary = {}
var config: Dictionary = {}
var state: Dictionary = {"schema_version":3,"contracts":{},"seed":0,"draw_count":0,"pity_count":0,"owned":{},"legacy_defs":{},"duties":{},"seen":{},"migrated":false,"migration_note":""}
var error := TDOutcome.new(true)
var enabled: bool = false
var _owner: WeakRef

func _init() -> void:
	var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
	error=validate_config(raw)
	if error.ok:
		config=raw
		for row: Dictionary in config.fixed_employees: _fixed_defs[row.id]=row.duplicate(true)
		for row: Dictionary in config.name_generator.surnames: _surnames[row.id]=row.text
		for row: Dictionary in config.name_generator.given_names: _given_names[row.id]=row

static func validate_config(raw: Variant, templates_only: bool=false) -> TDOutcome:
	if not raw is Dictionary or raw.get("schema_version")!=2: return TDOutcome.new(false,"EMPLOYEE_CONFIG_VERSION")
	if not TDServiceCatalog.integer(raw.get("draw_cost_cents"),1,1000000) or not TDServiceCatalog.integer(raw.get("pity_draws"),1,100): return TDOutcome.new(false,"EMPLOYEE_CONFIG_PRICE")
	if not raw.get("copies_per_star") is Array or raw.copies_per_star.size()!=3 or not raw.get("star_stat_scales") is Array or raw.star_stat_scales.size()!=3: return TDOutcome.new(false,"EMPLOYEE_CONFIG_STARS")
	for index: int in 3:
		if not TDServiceCatalog.integer(raw.copies_per_star[index],1,9) or int(raw.copies_per_star[index])!=[1,3,9][index]: return TDOutcome.new(false,"EMPLOYEE_CONFIG_STARS")
	for value: Variant in raw.star_stat_scales:
		if not TDEconomicCustomer.finite_range(value,.1,4): return TDOutcome.new(false,"EMPLOYEE_CONFIG_SCALE")
	if not raw.get("templates") is Array or raw.templates.is_empty() or not raw.get("role_caps") is Dictionary: return TDOutcome.new(false,"EMPLOYEE_CONFIG_POOL")
	for role: String in ROLES:
		if not TDServiceCatalog.integer(raw.role_caps.get(role),1,2): return TDOutcome.new(false,"EMPLOYEE_CONFIG_CAP")
	var generator: Variant=raw.get("name_generator")
	if not generator is Dictionary or generator.get("version")!=1: return TDOutcome.new(false,"EMPLOYEE_CONFIG_NAMES")
	for field: String in ["surnames","given_names"]:
		if not generator.get(field) is Array or generator[field].is_empty() or generator[field].size()>1000: return TDOutcome.new(false,"EMPLOYEE_CONFIG_NAMES")
		var component_ids: Dictionary={}; var texts: Dictionary={}
		for part: Variant in generator[field]:
			if not part is Dictionary or not part.get("id") is String or not part.get("text") is String: return TDOutcome.new(false,"EMPLOYEE_CONFIG_NAMES")
			if not part.id.is_valid_identifier() or component_ids.has(part.id) or part.text.length()!=(1 if field=="surnames" else 2) or texts.has(part.text): return TDOutcome.new(false,"EMPLOYEE_CONFIG_NAMES")
			if field=="given_names" and part.get("role") not in ROLES: return TDOutcome.new(false,"EMPLOYEE_CONFIG_NAMES")
			component_ids[part.id]=true; texts[part.text]=true
	for role: String in ROLES:
		if not generator.given_names.any(func(part:Dictionary)->bool:return part.role==role): return TDOutcome.new(false,"EMPLOYEE_CONFIG_NAMES")
	var weights: Variant=raw.get("star_weights")
	if not weights is Array or weights.size()!=3: return TDOutcome.new(false,"EMPLOYEE_CONFIG_PROBABILITY")
	for value: Variant in weights:
		if not TDServiceCatalog.integer(value,1,1000000): return TDOutcome.new(false,"EMPLOYEE_CONFIG_PROBABILITY")
	if not (int(weights[0])>int(weights[1]) and int(weights[1])>int(weights[2])): return TDOutcome.new(false,"EMPLOYEE_CONFIG_PROBABILITY")
	var ids: Dictionary={}
	for row: Variant in raw.templates:
		if not row is Dictionary or not row.get("id") is String or row.id.is_empty() or (row.id.begins_with("legacy.") or row.id.begins_with(GENERATED_PREFIX)) or ids.has(row.id): return TDOutcome.new(false,"EMPLOYEE_CONFIG_ID")
		if row.get("role") not in ROLES or not row.get("name") is String or not row.get("description") is String or row.get("buff") not in ["","faster_service","secondary","tip"]: return TDOutcome.new(false,"EMPLOYEE_CONFIG_ROLE")
		if not TDServiceCatalog.integer(row.get("weight"),1,1000) or not row.get("wages_cents") is Array or row.wages_cents.size()!=3: return TDOutcome.new(false,"EMPLOYEE_CONFIG_WAGE")
		for wage: Variant in row.wages_cents:
			if not TDServiceCatalog.integer(wage,1,100000): return TDOutcome.new(false,"EMPLOYEE_CONFIG_WAGE")
		for key: String in ["attraction","operations","quality","economy"]:
			if not TDEconomicCustomer.finite_range(row.get(key),0,100): return TDOutcome.new(false,"EMPLOYEE_CONFIG_STAT")
		if row.role=="manager":
			if not row.get("special_bonuses") is Array or row.special_bonuses.size()!=3: return TDOutcome.new(false,"EMPLOYEE_CONFIG_BONUS")
			for bonuses: Variant in row.special_bonuses:
				if not bonuses is Dictionary: return TDOutcome.new(false,"EMPLOYEE_CONFIG_BONUS")
				for key: Variant in bonuses:
					if key not in ["service_bonus","quality_bonus","utility_discount"] or not TDEconomicCustomer.finite_range(bonuses[key],0,.5): return TDOutcome.new(false,"EMPLOYEE_CONFIG_BONUS")
		ids[row.id]=true
	if not generator.get("archetypes") is Dictionary: return TDOutcome.new(false,"EMPLOYEE_CONFIG_ARCHETYPES")
	for role: String in ROLES:
		var choices: Variant=generator.archetypes.get(role)
		if not choices is Array or choices.is_empty(): return TDOutcome.new(false,"EMPLOYEE_CONFIG_ARCHETYPES")
		var seen: Dictionary={}
		for id: Variant in choices:
			if not id is String or seen.has(id) or not raw.templates.any(func(row:Dictionary)->bool:return row.id==id and row.role==role): return TDOutcome.new(false,"EMPLOYEE_CONFIG_ARCHETYPES")
			seen[id]=true
	return TDOutcome.new(true,"VALID") if templates_only else _validate_recruitment(raw)

static func _validate_recruitment(raw: Dictionary) -> TDOutcome:
	var market: Variant=raw.get("recruitment")
	if not market is Dictionary or market.get("version")!=1 or not TDServiceCatalog.integer(market.get("rotation_days"),1,30) or not TDServiceCatalog.integer(market.get("fee_salary_days"),1,30): return TDOutcome.new(false,"EMPLOYEE_MARKET_CONFIG")
	if not market.get("towns") is Array or market.towns.size()!=5 or not market.get("candidate_slots") is Array or market.candidate_slots.size()!=3: return TDOutcome.new(false,"EMPLOYEE_MARKET_CONFIG")
	var towns: Dictionary={}
	for town: Variant in market.towns:
		if town not in ["chengdu","tokyo","paris","bangkok","mexico_city"] or towns.has(town): return TDOutcome.new(false,"EMPLOYEE_MARKET_TOWN")
		towns[town]=true
	for value: Variant in market.candidate_slots:
		if not TDServiceCatalog.integer(value,1,20): return TDOutcome.new(false,"EMPLOYEE_MARKET_SLOTS")
	if not (market.candidate_slots[0]>market.candidate_slots[1] and market.candidate_slots[1]>market.candidate_slots[2]): return TDOutcome.new(false,"EMPLOYEE_MARKET_SLOTS")
	if not raw.get("fixed_employees") is Array or raw.fixed_employees.is_empty() or raw.fixed_employees.size()>2000: return TDOutcome.new(false,"EMPLOYEE_FIXED_POOL")
	# Reuse the established full definition validator, retaining the legacy archetype table unchanged.
	var augmented:=raw.duplicate(true);augmented.templates.append_array(raw.fixed_employees)
	augmented.erase("recruitment");augmented.erase("fixed_employees")
	var ids: Dictionary={};var names: Dictionary={}
	for row: Variant in raw.fixed_employees:
		if not row is Dictionary or not row.get("id") is String or not row.id.begins_with("staff.") or ids.has(row.id) or not row.get("name") is String or row.name.is_empty() or names.has(row.name): return TDOutcome.new(false,"EMPLOYEE_FIXED_ID")
		if row.get("town") not in towns or not TDServiceCatalog.integer(row.get("stars"),1,3): return TDOutcome.new(false,"EMPLOYEE_FIXED_ORIGIN")
		if not row.get("wages_cents") is Array or row.wages_cents.size()!=3 or not TDServiceCatalog.integer(row.get("sign_fee_cents"),1,3000000): return TDOutcome.new(false,"EMPLOYEE_FIXED_FEE")
		for wage: Variant in row.wages_cents:
			if not TDServiceCatalog.integer(wage,1,100000) or int(wage)!=int(row.wages_cents[0]): return TDOutcome.new(false,"EMPLOYEE_FIXED_WAGE")
		if int(row.sign_fee_cents)!=int(row.wages_cents[0])*int(market.fee_salary_days): return TDOutcome.new(false,"EMPLOYEE_FIXED_FEE")
		ids[row.id]=true;names[row.name]=true
	# Only the shared template pass is needed here; prevent recursive market validation.
	return validate_config(augmented, true)

func attach(profile: TDGameProfile) -> void:
	_owner=weakref(profile); enabled=true
	if int(state.seed)==0: state.seed=maxi(1,str(profile.shop.snapshot().run_id).sha256_text().substr(0,8).hex_to_int() ^ int(profile.shop.snapshot().seed))
	sync_main_crew()

func _profile() -> TDGameProfile:
	return _owner.get_ref() as TDGameProfile if _owner!=null else null

func snapshot() -> Dictionary:
	return state.duplicate(true)

func _template(id: String, source: Dictionary={}) -> Dictionary:
	if _fixed_defs.has(id): return _fixed_defs[id].duplicate(true)
	var data: Dictionary=state if source.is_empty() else source
	if id.begins_with(GENERATED_PREFIX):
		if _generated_defs.has(id): return _generated_defs[id].duplicate(true)
		var parts:=id.split(".")
		if parts.size()!=4 or not _surnames.has(parts[2]) or not _given_names.has(parts[3]): return {}
		var given: Dictionary=_given_names[parts[3]]
		# v1 archetype membership is explicit: adding a future template cannot remap existing people.
		var archetypes: Array=config.name_generator.archetypes[given.role].duplicate();archetypes.sort()
		var chosen: String=str(archetypes[id.sha256_text().substr(0,8).hex_to_int()%archetypes.size()])
		var result: Dictionary=_template(chosen,data)
		result.template_id=result.id; result.id=id; result.name=str(_surnames[parts[2]])+str(given.text)
		result.generated=true
		_generated_defs[id]=result.duplicate(true)
		return result
	var legacy: Dictionary=data.get("legacy_defs",{}).get(id,{})
	var key: String=str(legacy.get("template_id",id))
	for row: Dictionary in config.get("templates",[]):
		if row.id==key:
			var result:=row.duplicate(true)
			if not legacy.is_empty(): result.id=id; result.name=legacy.name; result.description="旧档保留员工 · "+str(result.description)
			return result
	return {}

static func stars_for(copies: int) -> int:
	return 3 if copies>=9 else (2 if copies>=3 else 1)

func employee_info(id: String) -> Dictionary:
	var row:=_template(id)
	if row.is_empty(): return {}
	var owned: Dictionary=state.owned.get(id,{})
	var copies: int=int(owned.get("copies",0)); var stars: int=int(row.stars) if _fixed_defs.has(id) else stars_for(copies)
	row.owned=not owned.is_empty(); row.copies=copies; row.stars=stars
	row.assigned=str(owned.get("assigned","")); row.xp=int(owned.get("xp",0)); row.legacy=state.legacy_defs.has(id)
	row.wage_cents=int(row.wages_cents[stars-1]); row.wage_yuan=float(row.wage_cents)/100.0
	row.store_name=_store_name(row.assigned)
	if not _fixed_defs.has(id):
		for key: String in ["attraction","operations","quality","economy"]: row[key]=mini(100,roundi(float(row[key])*float(config.star_stat_scales[stars-1])))
	row.special=str(row.description); row.service_bonus=0.0; row.quality_bonus=0.0; row.utility_discount=0.0
	if row.role=="manager":
		for key: String in row.special_bonuses[stars-1]: row[key]=float(row.special_bonuses[stars-1][key])
	return row

func definition(id: String) -> Dictionary:
	return employee_info(id)

func manager_info(id: String) -> Dictionary:
	var row:=employee_info(id)
	return row if row.get("owned",false) and row.get("role","")=="manager" else {}

func roster_rows(role: String="", offset: int=0, limit: int=-1) -> Array:
	var rows: Array=[]; var ids: Array=state.owned.keys(); ids.sort()
	var matched: int=0
	for id: String in ids:
		var row:=employee_info(id)
		if not role.is_empty() and row.role!=role: continue
		if matched>=maxi(0,offset) and (limit<0 or rows.size()<limit): rows.append(row)
		matched+=1
		if limit>=0 and rows.size()>=limit: break
	return rows

func roster_count(role: String="") -> int:
	if role.is_empty(): return state.owned.size()
	var count: int=0
	for id: String in state.owned:
		if _template(id).get("role","")==role: count+=1
	return count

func _store_name(id: String) -> String:
	if id.is_empty(): return "待岗"
	if id==HOME: return "主店"
	var p:=_profile()
	return str(p.branches.state.stores.get(id,{}).get("name",id)) if p!=null else id

func assigned(store_id: String, role: String="") -> Array:
	var rows: Array=[]
	var ids: Array=state.owned.keys(); ids.sort()
	for id: String in ids:
		if state.owned[id].assigned!=store_id: continue
		var row:=employee_info(id)
		if role.is_empty() or row.role==role: rows.append(row)
	return rows

func ready_for(store_id: String) -> bool:
	if store_id==HOME: return true # The player can cook and serve by hand.
	if _profile()==null or not _profile().branches.is_built(store_id): return false
	for role: String in ROLES:
		if assigned(store_id,role).is_empty(): return false
	return true

func manager_for(store_id: String) -> Dictionary:
	var managers:=assigned(store_id,"manager")
	return managers[0] if not managers.is_empty() else {}

func wages_for(store_id: String) -> int:
	var total: int=0
	for row: Dictionary in assigned(store_id): total+=int(row.wage_cents)
	return total

func _allowed() -> bool:
	var p:=_profile()
	return p!=null and p._alive and p.at_boundary()

func _valid_store(id: String) -> bool:
	var p:=_profile()
	return id.is_empty() or id==HOME or (p!=null and p.branches.state.stores.has(id))

func draw(_count: int, _role: String, _token: String) -> TDOutcome:
	return TDOutcome.new(false,"RECRUITMENT_REPLACED","请在招聘市场选择具名候选人签约。")

func market_rows(town: String, role: String) -> Array:
	var p:=_profile();var rows: Array=[]
	if p==null or not p._alive or town not in config.recruitment.towns or role not in ROLES: return rows
	var day: int=int(p.shop.snapshot().day)
	var days: int=int(config.recruitment.rotation_days)
	var phase: int=(town+":"+role).sha256_text().substr(0,8).hex_to_int()%days
	var cycle: int=floori(float(day-1+phase)/days)
	var expires: int=(cycle+1)*days-phase
	var offer_key: String="%s:%s:%d"%[town,role,cycle]
	for stars: int in range(1,4):
		var pool: Array=[]
		for id: String in _fixed_defs:
			var def: Dictionary=_fixed_defs[id]
			if def.town==town and def.role==role and int(def.stars)==stars and not state.owned.has(id):
				pool.append({"id":id,"rank":("%d:%s:%s"%[int(state.seed),offer_key,id]).sha256_text()})
		pool.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return a.rank<b.rank)
		for index: int in mini(pool.size(),int(config.recruitment.candidate_slots[stars-1])):
			var row:=employee_info(str(pool[index].id));row.offer_key=offer_key;row.last_day=expires;rows.append(row)
	return rows

func sign_employee(id: String, token: String, offer_key: String) -> TDOutcome:
	if not _allowed(): return TDOutcome.new(false,"NOT_AT_BOUNDARY","筹备或日结后才能签约。")
	if token.is_empty() or token.length()>160 or state.seen.has(token): return TDOutcome.new(false,"DUPLICATE","此签约已处理；没有重复扣款。")
	if state.owned.has(id): return TDOutcome.new(false,"ALREADY_OWNED","这位员工已在仓库中。")
	if not _fixed_defs.has(id): return TDOutcome.new(false,"UNKNOWN_CANDIDATE","请选择当前招聘市场的候选人。")
	var def: Dictionary=_fixed_defs[id];var offer: Dictionary={}
	for row: Dictionary in market_rows(def.town,def.role):
		if row.id==id and row.offer_key==offer_key: offer=row;break
	if offer.is_empty(): return TDOutcome.new(false,"OFFER_EXPIRED","该招聘信息已到期，请刷新市场。")
	var p:=_profile();var fee: int=int(offer.sign_fee_cents)
	var paid:=p.shop.branch_adjustment(-fee,token,"员工签约 · "+str(offer.name),"employee-roster")
	if not paid.ok: return paid
	p.commerce.society.state.sectors.services+=fee
	state.owned[id]={"id":id,"copies":[1,3,9][int(offer.stars)-1],"xp":0,"assigned":""}
	state.contracts[id]={"token":token,"fee_cents":fee,"day":int(p.shop.snapshot().day)}
	state.seen[token]=true
	return TDOutcome.new(true,"EMPLOYEE_SIGNED","%s 已签约入库；待命不计薪，可到员工仓库派驻。"%str(offer.name),{"id":id,"fee_cents":fee})

func assign(employee_id: String, store_id: String) -> TDOutcome:
	if not _allowed(): return TDOutcome.new(false,"NOT_AT_BOUNDARY","筹备或日结后才能调整岗位。")
	if not state.owned.has(employee_id): return TDOutcome.new(false,"EMPLOYEE_NOT_OWNED")
	if not _valid_store(store_id): return TDOutcome.new(false,"UNKNOWN_STORE")
	if not store_id.is_empty() and store_id!=HOME and not _profile().branches.funded(store_id): return TDOutcome.new(false,"UNPAID_SITE","请先确认付款施工。")
	var person: Dictionary=state.owned[employee_id]
	if person.assigned==store_id: return TDOutcome.new(true,"ALREADY_ASSIGNED")
	var role: String=employee_info(employee_id).role
	if not store_id.is_empty() and assigned(store_id,role).size()>=int(config.role_caps[role]): return TDOutcome.new(false,"ROLE_FULL","这个岗位已满；原派驻保持不变。")
	var day: int=int(_profile().shop.snapshot().day)
	record_duties(day)
	person.assigned=store_id
	record_duties(day); sync_main_crew()
	return TDOutcome.new(true,"EMPLOYEE_ASSIGNED","岗位已调整，今天已产生的工资不撤销。")

func auto_assign(store_id: String) -> TDOutcome:
	if not _allowed(): return TDOutcome.new(false,"NOT_AT_BOUNDARY")
	if store_id.is_empty() or not _valid_store(store_id): return TDOutcome.new(false,"UNKNOWN_STORE")
	var filled: Array=[]; var missing: Array=[]
	for role: String in ROLES:
		if store_id==HOME and role=="manager": continue
		if not assigned(store_id,role).is_empty(): continue
		var free:=assigned("",role)
		free.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return a.stars>b.stars if a.stars!=b.stars else str(a.id)<str(b.id))
		if free.is_empty(): missing.append(role); continue
		var result:=assign(free[0].id,store_id)
		if result.ok: filled.append(free[0].id)
		else: missing.append(role)
	return TDOutcome.new(true,"AUTO_ASSIGNED" if missing.is_empty() else "STAFF_SHORTAGE","只分配现有待岗员工，不招募或调走其他店的人。",{"assigned":filled,"missing":missing})

func record_duties(day: int=-1) -> Dictionary:
	var p:=_profile()
	if p==null or not p._alive: return {}
	if day<0: day=int(p.shop.snapshot().day)
	if day!=int(p.shop.snapshot().day): return {}
	var key:=str(day)
	if p.shop.snapshot().phase=="SETTLED": return state.duties.get(key,{}).duplicate(true)
	if not state.duties.has(key): state.duties[key]={}
	var rows: Dictionary=state.duties[key]
	for id: String in state.owned:
		var row:=employee_info(id)
		if str(row.assigned).is_empty() or rows.has(id): continue
		if row.assigned!=HOME and not p.branches.is_built(str(row.assigned)): continue
		rows[id]={"employee_id":id,"store_id":row.assigned,"role":row.role,"cents":int(row.wage_cents),"stars":int(row.stars)}
	return rows.duplicate(true)

func payroll_for(store_id: String, day: int) -> Dictionary:
	var report: Dictionary={"total_cents":0,"manager_cents":0,"crew_cents":0,"workers":[]}
	for row: Dictionary in state.duties.get(str(day),{}).values():
		if row.store_id!=store_id: continue
		report.workers.append(row.duplicate(true)); report.total_cents+=int(row.cents)
		if row.role=="manager": report.manager_cents+=int(row.cents)
		else: report.crew_cents+=int(row.cents)
	return report

func sync_main_crew() -> void:
	var p:=_profile()
	if p==null or not p._alive or p.layout==null: return
	var rows: Array=[]
	for row: Dictionary in assigned(HOME):
		if row.role in ["cook","waiter"]: rows.append(row)
	p.layout.crew.use_external(rows,_record_growth)
	p.shop.crew=p.layout.crew

func _record_growth(id: String, xp: int) -> void:
	var p:=_profile()
	if p==null or not p._alive or not state.owned.has(id): return
	state.owned[id].xp=clampi(xp,0,16)

func migrate_legacy(layout_crew: Array, branches: Dictionary, old_staff: Dictionary) -> TDOutcome:
	if _profile()!=null and not _profile()._alive: return TDOutcome.new(false,"STALE_PROFILE")
	if state.migrated: return TDOutcome.new(true,"ALREADY_MIGRATED")
	var next:=state.duplicate(true)
	for entry: Variant in layout_crew:
		var id: String=str(entry.get("id","")) if entry is Dictionary else str(entry)
		if _template(id).is_empty(): return TDOutcome.new(false,"INVALID_LEGACY_EMPLOYEE")
		var on_duty: bool=bool(entry.get("hired",true)) if entry is Dictionary else true
		next.owned[id]={"id":id,"copies":1,"xp":int(entry.get("xp",0)) if entry is Dictionary else 0,"assigned":HOME if on_duty else ""}
	var stores: Dictionary=branches.get("stores",{})
	var ids: Array=stores.keys(); ids.sort()
	for store_id: String in ids:
		var s: Dictionary=stores[store_id]; var template: String=str(s.manager_id)
		var base:=_template(template)
		if base.is_empty(): return TDOutcome.new(false,"INVALID_LEGACY_MANAGER")
		var manager_id:=template
		if next.owned.has(manager_id): manager_id="legacy.manager."+store_id.trim_prefix("player-branch:")
		if manager_id!=template: next.legacy_defs[manager_id]={"template_id":template,"name":str(base.name)+" · "+str(s.name)}
		var copies: int=9 if template=="manager.master" else (3 if template=="manager.host" else 1)
		next.owned[manager_id]={"id":manager_id,"copies":copies,"xp":0,"assigned":store_id}
		for role: String in ["cook","waiter"]:
			var id: String="legacy."+role+"."+store_id.trim_prefix("player-branch:")
			next.legacy_defs[id]={"template_id":"cook-he" if role=="cook" else "waiter-ning","name":str(s.name)+("原厨师" if role=="cook" else "原服务员")}
			next.owned[id]={"id":id,"copies":1,"xp":0,"assigned":store_id}
	for role: String in ["greeter","cashier","runner"]:
		if not bool(old_staff.get(role,false)): continue
		var id: String="legacy.home."+role
		var active: int=0
		for person: Dictionary in next.owned.values():
			if person.assigned==HOME and _template(person.id,next).get("role")=="waiter": active+=1
		next.legacy_defs[id]={"template_id":"waiter-ning","name":"原前厅"+str({"greeter":"迎宾员","cashier":"收银员","runner":"传菜员"}[role])}
		next.owned[id]={"id":id,"copies":1,"xp":0,"assigned":HOME if active<int(config.role_caps.waiter) else ""}
	next.migrated=true; next.migration_note="旧员工、成长和店长星级已保留；分店原班组转为独立员工。主店超出两名服务员的旧岗位员工保留待岗，现任服务员兼顾前厅。"
	var checked:=validate_save(next,stores.keys(),-1)
	if not checked.ok: return checked
	state=next; sync_main_crew()
	return TDOutcome.new(true,"EMPLOYEES_MIGRATED",state.migration_note)

func validate_save(raw: Variant, store_ids: Variant=null, day: int=-1) -> TDOutcome:
	if not raw is Dictionary or not TDServiceCatalog.integer(raw.get("schema_version"),1,3): return TDOutcome.new(false,"INVALID_EMPLOYEE_VERSION")
	if store_ids!=null and not store_ids is Array: return TDOutcome.new(false,"INVALID_EMPLOYEE_STORES")
	for key: String in ["seed","draw_count","pity_count"]:
		if not TDServiceCatalog.integer(raw.get(key),0,4294967295): return TDOutcome.new(false,"INVALID_EMPLOYEE_COUNTER")
	if int(raw.pity_count)>=int(config.pity_draws): return TDOutcome.new(false,"INVALID_EMPLOYEE_PITY")
	for key: String in ["owned","legacy_defs","duties","seen"]:
		if not raw.get(key) is Dictionary: return TDOutcome.new(false,"INVALID_EMPLOYEE_FIELD",key)
	if raw.owned.size()>int(config.name_generator.surnames.size()*config.name_generator.given_names.size())+6000 or raw.legacy_defs.size()>6000 or raw.seen.size()>100000 or not raw.get("migrated") is bool or not raw.get("migration_note") is String: return TDOutcome.new(false,"INVALID_EMPLOYEE_STATE")
	for id: Variant in raw.legacy_defs:
		var def: Variant=raw.legacy_defs[id]
		if not id is String or not id.begins_with("legacy.") or not def is Dictionary or not def.get("template_id") is String or not def.get("name") is String or def.name.is_empty() or def.name.length()>180: return TDOutcome.new(false,"INVALID_EMPLOYEE_LEGACY")
		if _template(def.template_id,{"legacy_defs":{}}).is_empty() or not raw.owned.has(id): return TDOutcome.new(false,"INVALID_EMPLOYEE_LEGACY")
	if int(raw.schema_version)>=3 and not raw.get("contracts") is Dictionary: return TDOutcome.new(false,"INVALID_EMPLOYEE_CONTRACTS")
	var contracts: Dictionary=raw.get("contracts",{})
	var contract_tokens: Dictionary={}
	for id: Variant in contracts:
		var contract: Variant=contracts[id]
		if int(raw.schema_version)<3 or not id is String or not _fixed_defs.has(id) or not raw.owned.has(id) or not contract is Dictionary: return TDOutcome.new(false,"INVALID_EMPLOYEE_CONTRACT")
		if not contract.get("token") is String or not raw.seen.has(contract.token) or contract_tokens.has(contract.token) or not TDServiceCatalog.integer(contract.get("fee_cents"),1,3000000) or int(contract.fee_cents)!=int(_fixed_defs[id].sign_fee_cents) or not TDServiceCatalog.integer(contract.get("day"),1,1000000) or (day>0 and int(contract.day)>day): return TDOutcome.new(false,"INVALID_EMPLOYEE_CONTRACT")
		contract_tokens[contract.token]=true
	var counts: Dictionary={}
	for id: Variant in raw.owned:
		var person: Variant=raw.owned[id]; var def:=_template(str(id),raw)
		if int(raw.schema_version)==1 and str(id).begins_with(GENERATED_PREFIX): return TDOutcome.new(false,"INVALID_EMPLOYEE")
		if not id is String or def.is_empty() or not person is Dictionary or person.get("id")!=id or not TDServiceCatalog.integer(person.get("copies"),1,9) or not TDServiceCatalog.integer(person.get("xp"),0,16) or not person.get("assigned") is String: return TDOutcome.new(false,"INVALID_EMPLOYEE")
		if _fixed_defs.has(id) and (int(raw.schema_version)<3 or not contracts.has(id) or int(person.copies)!=[1,3,9][int(def.stars)-1]): return TDOutcome.new(false,"INVALID_FIXED_EMPLOYEE")
		var store_id: String=person.assigned
		if not store_id.is_empty():
			if store_id!=HOME and (not store_id.begins_with("player-branch:") or (store_ids!=null and store_id not in store_ids)): return TDOutcome.new(false,"INVALID_EMPLOYEE_STORE")
			var key: String=store_id+":"+str(def.role); counts[key]=int(counts.get(key,0))+1
			if counts[key]>int(config.role_caps[def.role]): return TDOutcome.new(false,"INVALID_EMPLOYEE_CAPACITY")
	for token: Variant in raw.seen:
		if not token is String or token.is_empty() or token.length()>160 or raw.seen[token]!=true: return TDOutcome.new(false,"INVALID_EMPLOYEE_TOKEN")
	for date: Variant in raw.duties:
		if not date is String or not date.is_valid_int() or int(date)<1 or str(int(date))!=date or (day>0 and int(date)>day) or not raw.duties[date] is Dictionary: return TDOutcome.new(false,"INVALID_EMPLOYEE_PAYROLL")
		for id: Variant in raw.duties[date]:
			var row: Variant=raw.duties[date][id]
			if not row is Dictionary or not raw.owned.has(id) or row.get("employee_id")!=id or row.get("role")!=_template(str(id),raw).role or not TDServiceCatalog.integer(row.get("cents"),1,100000) or not TDServiceCatalog.integer(row.get("stars"),1,3): return TDOutcome.new(false,"INVALID_EMPLOYEE_PAYROLL")
			if int(row.stars)>stars_for(int(raw.owned[id].copies)) or int(row.cents)!=int(_template(str(id),raw).wages_cents[int(row.stars)-1]): return TDOutcome.new(false,"INVALID_EMPLOYEE_PAYROLL_WAGE")
			if _fixed_defs.has(id) and (int(date)<int(contracts[id].day) or int(row.stars)!=int(_fixed_defs[id].stars)): return TDOutcome.new(false,"INVALID_EMPLOYEE_PAYROLL_WAGE")
			var store: Variant=row.get("store_id")
			if not store is String or (store!=HOME and (not store.begins_with("player-branch:") or (store_ids!=null and store not in store_ids))): return TDOutcome.new(false,"INVALID_EMPLOYEE_PAYROLL_STORE")
	return TDOutcome.new(true,"VALID_EMPLOYEES")

func restore(raw: Dictionary) -> TDOutcome:
	var p:=_profile()
	if p!=null and not p._alive: return TDOutcome.new(false,"STALE_PROFILE")
	var checked:=validate_save(raw,p.branches.state.stores.keys() if p!=null else null,int(p.shop.snapshot().day) if p!=null else -1)
	if not checked.ok: return checked
	state=raw.duplicate(true); state.schema_version=3
	if not state.has("contracts"): state.contracts={}
	sync_main_crew()
	return TDOutcome.new(true,"EMPLOYEES_RESTORED")
