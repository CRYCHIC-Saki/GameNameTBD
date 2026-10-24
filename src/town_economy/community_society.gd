class_name TDCommunitySociety
extends RefCounted
## Bounded persistent households, counterpart sectors and a cash-funded bank.
## A household owns cash; customer profiles only reference its spending capacity.
var config: Dictionary = {}
var state: Dictionary = {}
var bank: TDCommunityBank
var _employees: Dictionary = {}

func _init(settings: Dictionary = {}, towns: Array = [], groups: Array = [], day: int = 1) -> void:
	config=settings.duplicate(true)
	bank=TDCommunityBank.new(settings.get("bank",{}),day)
	state={"schema_version":1,"households":{},"holds":{},"sectors":{"market":0,"services":0,"construction":0,"land":0},"public":{},"external_net_cents":0,"initial_cash_cents":int(bank.state.reserve_cents),"last_day":day-1,"daily":{},"books":[],"bank":bank.state,"baseline_attached":false}
	for town: String in towns:
		state.public[town]=0
		for group: Dictionary in groups:
			for index: int in int(settings.society.families_per_group):
				var id:=identity(town,str(group.id),index)
				var wage: int=int(group.budget_cents)*int(settings.society.wage_budget_bps)/10000
				var cash:=wage*int(settings.society.starting_cash_days)
				state.households[id]={"id":id,"town_id":town,"group_id":group.id,"cash_cents":cash,"wage_cents":wage,"employer_id":"","employer_wage_cents":0,"wages_due_cents":0,"wage_day":day-1,"paid_today_cents":0,"necessities_cents":wage*int(settings.society.necessities_wage_bps)/10000,"income_tax_today_cents":0,"spent_today_cents":0}
				state.initial_cash_cents+=cash

func identity(town: String, group: String, index: int) -> String:
	return "family:%s:%s:%d"%[town,group,index%int(config.society.families_per_group)]

func available(id: String) -> int:
	if not state.households.has(id): return 0
	var amount: int=int(state.households[id].cash_cents)
	for hold: Dictionary in state.holds.values():
		if hold.family_id==id and hold.status=="reserved": amount-=int(hold.cents)
	return maxi(0,amount)

func reserve(id: String, cents: int, token: String) -> TDOutcome:
	if token.is_empty() or not state.households.has(id) or cents<0: return TDOutcome.new(false,"INVALID_CONSUMER")
	if state.holds.has(token): return TDOutcome.new(false,"DUPLICATE")
	if cents>available(id): return TDOutcome.new(false,"HOUSEHOLD_BUDGET")
	state.holds[token]={"family_id":id,"cents":cents,"status":"reserved","paid_cents":0,"refunded_cents":0}
	return TDOutcome.new(true,"CONSUMER_RESERVED")

func release(token: String) -> void:
	if state.holds.has(token) and state.holds[token].status=="reserved": state.holds[token].status="released"

func pay(token: String, requested_tip: int = 0) -> TDOutcome:
	if not state.holds.has(token) or state.holds[token].status!="reserved": return TDOutcome.new(false,"INVALID_CONSUMER_HOLD")
	var hold: Dictionary=state.holds[token]
	var tip:=mini(maxi(0,requested_tip),available(hold.family_id))
	var total:=int(hold.cents)+tip
	if total>int(state.households[hold.family_id].cash_cents): return TDOutcome.new(false,"HOUSEHOLD_BUDGET")
	state.households[hold.family_id].cash_cents-=total
	state.households[hold.family_id].spent_today_cents+=total
	state.holds[token].status="paid";state.holds[token].paid_cents=total
	return TDOutcome.new(true,"CONSUMER_PAID","",{"cents":int(hold.cents),"tip_cents":tip})

func refund(token: String, cents: int) -> TDOutcome:
	if not state.holds.has(token) or cents<0: return TDOutcome.new(false,"INVALID_REFUND")
	var hold: Dictionary=state.holds[token]
	if hold.status!="paid" or int(hold.refunded_cents)>0: return TDOutcome.new(false,"DUPLICATE")
	if cents>int(hold.paid_cents): return TDOutcome.new(false,"EXCEEDS_CONSUMER_PAYMENT")
	state.households[hold.family_id].cash_cents+=cents
	state.households[hold.family_id].spent_today_cents-=cents
	hold.refunded_cents=cents;hold.status="refunded"
	return TDOutcome.new(true,"CONSUMER_REFUNDED")

func spend(id: String, cents: int) -> bool:
	if cents<0 or cents>available(id): return false
	state.households[id].cash_cents-=cents;state.households[id].spent_today_cents+=cents
	return true

func hire(employer: String, town: String, count: int, wage: int) -> TDOutcome:
	if employer.is_empty() or count<=0 or wage<=0: return TDOutcome.new(false,"INVALID_EMPLOYMENT")
	var candidates: Array=[]
	for family: Dictionary in state.households.values():
		if family.town_id==town and family.employer_id.is_empty() and int(family.wages_due_cents)==0: candidates.append(family.id)
	if candidates.size()<count: return TDOutcome.new(false,"NO_WORKERS")
	var ids:=candidates.slice(0,count)
	for id: String in ids:
		state.households[id].employer_id=employer;state.households[id].employer_wage_cents=wage
	if not _employees.has(employer): _employees[employer]=[]
	_employees[employer].append_array(ids)
	return TDOutcome.new(true,"HIRED","",{"household_ids":ids})

func staff(employer: String) -> Array:
	var result: Array=[]
	for id: String in _employees.get(employer,[]): result.append(state.households[id])
	return result

func payroll(employer: String, available_cash: int, day: int) -> Dictionary:
	var expense: int=0;var paid: int=0
	for family: Dictionary in staff(employer):
		if int(family.wage_day)==day: continue
		expense+=int(family.employer_wage_cents)
		family.wages_due_cents+=int(family.employer_wage_cents)
		var transfer:=mini(maxi(0,available_cash-paid),int(family.wages_due_cents))
		family.wages_due_cents-=transfer;paid+=transfer
		_wage(family,transfer,day)
	return {"expense_cents":expense,"paid_cents":paid}

func _wage(family: Dictionary, gross: int, day: int) -> void:
	var taxable:=maxi(0,gross-int(config.society.daily_wage_allowance_cents))
	var tax:=roundi(float(taxable)*int(config.society.income_tax_bps)/10000)
	family.cash_cents+=gross-tax;family.paid_today_cents=gross
	family.income_tax_today_cents=tax;family.wage_day=day
	state.public[family.town_id]+=tax

func finish_day(day: int) -> TDOutcome:
	if day!=int(state.last_day)+1: return TDOutcome.new(false,"DUPLICATE_SOCIETY_DAY")
	var income: int=0;var necessities: int=0;var shortage: int=0;var taxes: int=0;var meals: int=0
	for family: Dictionary in state.households.values():
		if family.employer_id.is_empty():
			state.external_net_cents+=int(family.wage_cents)
			_wage(family,int(family.wage_cents),day)
		income+=int(family.paid_today_cents);taxes+=int(family.income_tax_today_cents);meals+=int(family.spent_today_cents)
		var required:=int(family.necessities_cents)
		# Savings are accessible for necessities; no hidden welfare or money injection.
		var missing:=maxi(0,required-available(family.id))
		var withdrawal:=mini(missing,mini(int(bank.account(family.id).deposit_cents),int(bank.state.reserve_cents)))
		if withdrawal>0:
			var result:=bank.transact(family.id,"withdraw",withdrawal,int(family.cash_cents),day,"needs:%d:%s"%[day,family.id],true)
			if result.ok: family.cash_cents+=int(result.data.cash_delta_cents)
		var spent:=mini(required,available(family.id))
		family.cash_cents-=spent;state.external_net_cents-=spent;necessities+=spent;shortage+=required-spent
		var excess:=maxi(0,available(family.id)-int(family.wage_cents)*int(config.society.savings_cash_days))
		if excess>0:
			var saved:=bank.transact(family.id,"deposit",excess,int(family.cash_cents),day,"savings:%d:%s"%[day,family.id],true)
			if saved.ok: family.cash_cents+=int(saved.data.cash_delta_cents)
	state.last_day=day
	state.daily={"day":day,"wages_cents":income,"wage_tax_cents":taxes,"necessities_cents":necessities,"unmet_needs_cents":shortage,"dining_cents":meals}
	state.books.append(state.daily.duplicate(true))
	while state.books.size()>28: state.books.pop_front()
	return TDOutcome.new(true,"SOCIETY_DAY","",state.daily.duplicate(true))

func start_day() -> void:
	state.holds.clear()
	for family: Dictionary in state.households.values():
		family.paid_today_cents=0;family.income_tax_today_cents=0;family.spent_today_cents=0

func cash_total() -> int:
	var total: int=int(bank.state.reserve_cents)
	for family: Dictionary in state.households.values(): total+=int(family.cash_cents)
	for cents: Variant in state.sectors.values(): total+=int(cents)
	for cents: Variant in state.public.values(): total+=int(cents)
	return total

func validate(raw: Variant) -> TDOutcome:
	if not raw is Dictionary or raw.get("schema_version")!=1: return TDOutcome.new(false,"INVALID_SOCIETY_VERSION")
	for field: String in ["households","holds","public","sectors","daily"]:
		if not raw.get(field) is Dictionary: return TDOutcome.new(false,"INVALID_SOCIETY_FIELD",field)
	if not raw.get("books") is Array or raw.books.size()>28 or not raw.get("baseline_attached") is bool: return TDOutcome.new(false,"INVALID_SOCIETY_BOOKS")
	for field: String in ["last_day","initial_cash_cents"]:
		if not TDServiceCatalog.integer(raw.get(field),0,9007199254740000): return TDOutcome.new(false,"INVALID_SOCIETY_NUMBER",field)
	if not TDServiceCatalog.integer(raw.get("external_net_cents"),-9007199254740000,9007199254740000): return TDOutcome.new(false,"INVALID_EXTERNAL_FLOW")
	if raw.households.size()!=state.households.size() or raw.public.size()!=state.public.size(): return TDOutcome.new(false,"INVALID_POPULATION")
	for id: String in state.households:
		if not raw.households.get(id) is Dictionary: return TDOutcome.new(false,"INVALID_HOUSEHOLD")
		var value: Dictionary=raw.households[id]
		for field: String in ["id","town_id","group_id"]:
			if value.get(field)!=state.households[id][field]: return TDOutcome.new(false,"INVALID_HOUSEHOLD_ID")
		if not value.get("employer_id") is String: return TDOutcome.new(false,"INVALID_EMPLOYER")
		for field: String in ["cash_cents","wage_cents","employer_wage_cents","wages_due_cents","wage_day","paid_today_cents","necessities_cents","income_tax_today_cents","spent_today_cents"]:
			if not TDServiceCatalog.integer(value.get(field),0,9007199254740000): return TDOutcome.new(false,"INVALID_HOUSEHOLD_BALANCE",field)
	for id: String in state.public:
		if not TDServiceCatalog.integer(raw.public.get(id),0,9007199254740000): return TDOutcome.new(false,"INVALID_PUBLIC_CASH")
	for id: String in state.sectors:
		if not TDServiceCatalog.integer(raw.sectors.get(id),0,9007199254740000): return TDOutcome.new(false,"INVALID_SECTOR_CASH")
	var reservations: Dictionary={}
	for token: Variant in raw.holds:
		var hold: Variant=raw.holds[token]
		if not token is String or not hold is Dictionary or not raw.households.has(hold.get("family_id")) or hold.get("status") not in ["reserved","released","paid","refunded"]: return TDOutcome.new(false,"INVALID_CONSUMER_HOLD")
		for field: String in ["cents","paid_cents","refunded_cents"]:
			if not TDServiceCatalog.integer(hold.get(field),0,100000000): return TDOutcome.new(false,"INVALID_CONSUMER_HOLD")
		if int(hold.refunded_cents)>int(hold.paid_cents): return TDOutcome.new(false,"INVALID_CONSUMER_HOLD")
		if hold.status=="reserved": reservations[hold.family_id]=int(reservations.get(hold.family_id,0))+int(hold.cents)
	for id: String in reservations:
		if int(reservations[id])>int(raw.households[id].cash_cents): return TDOutcome.new(false,"OVERRESERVED_HOUSEHOLD")
	var candidate:=TDCommunityBank.new(config.bank)
	return candidate.restore(raw.get("bank"))

func restore(raw: Dictionary) -> TDOutcome:
	var checked:=validate(raw)
	if not checked.ok: return checked
	state=raw.duplicate(true);bank.restore(state.bank);state.bank=bank.state
	_employees.clear()
	for family: Dictionary in state.households.values():
		if family.employer_id.is_empty(): continue
		if not _employees.has(family.employer_id): _employees[family.employer_id]=[]
		_employees[family.employer_id].append(family.id)
	return TDOutcome.new(true,"SOCIETY_RESTORED")
