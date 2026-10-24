class_name TDCommunityBank
extends RefCounted
## Cash-funded lending: no money creation. Caller remains authoritative for its cash.
## Amounts are integer cents; rates are basis points per game day.
var config: Dictionary = {}
var state: Dictionary = {}

func _init(settings: Dictionary = {}, day: int = 1) -> void:
	config=settings.duplicate(true)
	state={"schema_version":1,"reserve_cents":int(config.get("reserve_cents",2000000)),"equity_cents":int(config.get("reserve_cents",2000000)),"last_day":day-1,"accounts":{},"seen":{},"journal":[]}

func account(owner: String) -> Dictionary:
	return state.accounts.get(owner,{"deposit_cents":0,"principal_cents":0,"interest_cents":0,"interest_fraction":0,"deposit_fraction":0,"due_day":0,"automatic_days":{}}).duplicate(true)

func transact(owner: String, action: String, cents: int, cash: int, day: int, token: String, automatic: bool = false) -> TDOutcome:
	if owner.is_empty() or token.is_empty() or token.length()>240 or cents<=0 or cents>100000000 or cash<0 or day<1: return TDOutcome.new(false,"INVALID_BANK_REQUEST")
	if state.seen.has(token): return TDOutcome.new(false,"DUPLICATE")
	if state.seen.size()>=100000: return TDOutcome.new(false,"BANK_JOURNAL_FULL")
	var value:=account(owner)
	if automatic and day<=int(value.automatic_days.get(action,0)): return TDOutcome.new(false,"DUPLICATE")
	var delta: int=0
	var interest_paid: int=0
	match action:
		"deposit":
			if cash<cents: return TDOutcome.new(false,"INSUFFICIENT_FUNDS")
			value.deposit_cents+=cents;delta=-cents
		"withdraw":
			if int(value.deposit_cents)<cents: return TDOutcome.new(false,"INSUFFICIENT_DEPOSIT")
			if int(state.reserve_cents)<cents: return TDOutcome.new(false,"BANK_LIQUIDITY")
			value.deposit_cents-=cents;delta=cents
		"borrow":
			if int(value.principal_cents)>0 and day>int(value.due_day): return TDOutcome.new(false,"LOAN_OVERDUE","借款逾期，先还清现有贷款才能再次借款。")
			if int(value.principal_cents)+cents>int(config.get("loan_limit_cents",100000)): return TDOutcome.new(false,"CREDIT_LIMIT")
			if int(state.reserve_cents)-cents<int(config.get("reserve_floor_cents",100000)): return TDOutcome.new(false,"BANK_LIQUIDITY")
			if int(value.principal_cents)==0: value.due_day=day+int(config.get("term_days",28))
			value.principal_cents+=cents;delta=cents
		"repay":
			var owed:=int(value.principal_cents)+int(value.interest_cents)
			if cents>owed: return TDOutcome.new(false,"EXCEEDS_LOAN")
			if cash<cents: return TDOutcome.new(false,"INSUFFICIENT_FUNDS")
			interest_paid=mini(cents,int(value.interest_cents))
			value.interest_cents-=interest_paid;value.principal_cents-=cents-interest_paid;delta=-cents
			if int(value.principal_cents)==0 and int(value.interest_cents)==0: value.due_day=0;value.interest_fraction=0
		_:
			return TDOutcome.new(false,"INVALID_BANK_ACTION")
	state.reserve_cents-=delta
	if automatic: value.automatic_days[action]=day
	else: state.seen[token]=true
	state.accounts[owner]=value
	var result: Dictionary={"owner":owner,"action":action,"day":day,"token":token,"cash_delta_cents":delta,"interest_paid_cents":interest_paid,"automatic":automatic}
	state.journal.append(result)
	while state.journal.size()>64: state.journal.pop_front()
	return TDOutcome.new(true,"BANK_RECORDED","",result.duplicate(true))

func accrue(day: int) -> TDOutcome:
	if day!=int(state.last_day)+1: return TDOutcome.new(false,"DUPLICATE_BANK_DAY")
	var charged: Dictionary={}
	var deposit_paid: int=0
	for owner: String in state.accounts:
		var value: Dictionary=state.accounts[owner]
		var numerator:=int(value.principal_cents)*int(config.get("loan_daily_bps",5))+int(value.interest_fraction)
		var interest: int=numerator/10000
		value.interest_fraction=numerator%10000;value.interest_cents+=interest
		state.equity_cents+=interest;charged[owner]=interest
		var saving_numerator:=int(value.deposit_cents)*int(config.get("deposit_daily_bps",1))+int(value.deposit_fraction)
		var saving: int=mini(saving_numerator/10000,maxi(0,int(state.equity_cents)-int(config.get("reserve_floor_cents",100000))))
		# No unfunded interest promise: unpaid deposit yield is not carried as a hidden liability.
		value.deposit_fraction=saving_numerator%10000
		value.deposit_cents+=saving;state.equity_cents-=saving;deposit_paid+=saving
	state.last_day=day
	return TDOutcome.new(true,"BANK_DAY", "",{"loan_interest":charged,"deposit_interest_cents":deposit_paid})

func audit() -> Dictionary:
	var assets: int=int(state.reserve_cents)
	var liabilities: int=0
	for value: Dictionary in state.accounts.values():
		assets+=int(value.principal_cents)+int(value.interest_cents);liabilities+=int(value.deposit_cents)
	return {"assets_cents":assets,"deposits_cents":liabilities,"equity_cents":int(state.equity_cents),"difference_cents":assets-liabilities-int(state.equity_cents)}

func restore(raw: Variant) -> TDOutcome:
	if not raw is Dictionary or raw.get("schema_version")!=1: return TDOutcome.new(false,"INVALID_BANK_VERSION")
	for key: String in ["reserve_cents","equity_cents","last_day"]:
		if not TDServiceCatalog.integer(raw.get(key),0,9007199254740000): return TDOutcome.new(false,"INVALID_BANK_BALANCE",key)
	if not raw.get("accounts") is Dictionary or raw.accounts.size()>5000 or not raw.get("seen") is Dictionary or raw.seen.size()>100000 or not raw.get("journal") is Array or raw.journal.size()>64: return TDOutcome.new(false,"INVALID_BANK_STATE")
	for owner: Variant in raw.accounts:
		if not owner is String or owner.is_empty() or not raw.accounts[owner] is Dictionary: return TDOutcome.new(false,"INVALID_BANK_ACCOUNT")
		for key: String in ["deposit_cents","principal_cents","interest_cents","interest_fraction","deposit_fraction","due_day"]:
			if not TDServiceCatalog.integer(raw.accounts[owner].get(key),0,9007199254740000): return TDOutcome.new(false,"INVALID_BANK_ACCOUNT",key)
		if int(raw.accounts[owner].interest_fraction)>=10000 or int(raw.accounts[owner].deposit_fraction)>=10000: return TDOutcome.new(false,"INVALID_BANK_FRACTION")
		if not raw.accounts[owner].get("automatic_days") is Dictionary: return TDOutcome.new(false,"INVALID_BANK_ACCOUNT")
		for action: Variant in raw.accounts[owner].automatic_days:
			if action not in ["deposit","withdraw","borrow","repay"] or not TDServiceCatalog.integer(raw.accounts[owner].automatic_days[action],1,1000000000): return TDOutcome.new(false,"INVALID_BANK_ACCOUNT")
	for token: Variant in raw.seen:
		if not token is String or token.is_empty() or raw.seen[token]!=true: return TDOutcome.new(false,"INVALID_BANK_TOKEN")
	for row: Variant in raw.journal:
		if not row is Dictionary or not row.get("automatic") is bool or (not row.automatic and not raw.seen.has(row.get("token"))) or not raw.accounts.has(row.get("owner")) or row.get("action") not in ["deposit","withdraw","borrow","repay"]: return TDOutcome.new(false,"INVALID_BANK_JOURNAL")
		if not TDServiceCatalog.integer(row.get("day"),1,1000000000) or not TDServiceCatalog.integer(row.get("cash_delta_cents"),-100000000,100000000) or not TDServiceCatalog.integer(row.get("interest_paid_cents"),0,100000000): return TDOutcome.new(false,"INVALID_BANK_JOURNAL")
	var previous:=state;state=raw.duplicate(true)
	if int(audit().difference_cents)!=0: state=previous;return TDOutcome.new(false,"BANK_UNBALANCED")
	return TDOutcome.new(true,"BANK_RESTORED")
