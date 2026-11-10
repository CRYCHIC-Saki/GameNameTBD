extends GutTest
var profiles: Array[TDGameProfile]=[]
func make_case() -> Dictionary:
	var p:=TDGameProfile.new();profiles.append(p);assert_true(p.error.ok,p.error.code)
	assert_true(p.shop.world_adjustment(300000,"test-funds","fixture").ok)
	return {"profile":p,"roster":p.employees}
func after_each() -> void:
	for p: TDGameProfile in profiles: p.close()
	profiles.clear()
func own(roster: TDEmployeeRoster, id: String, copies: int=1) -> void:
	roster.state.owned[id]={"id":id,"copies":copies,"xp":0,"assigned":""}
func add_stores(p: TDGameProfile) -> void:
	for id: String in ["player-branch:1","player-branch:2"]:
		p.branches.state.stores[id]={"id":id,"name":id,"start_day":int(p.shop.snapshot().day),"construction":{"kind":"paid"}}
func sign_first(r: TDEmployeeRoster, role: String="cook", token: String="sign") -> Dictionary:
	var offer: Dictionary=r.market_rows("chengdu",role)[0]
	var signed:=r.sign_employee(offer.id,token,offer.offer_key);assert_true(signed.ok,signed.code)
	return offer

func test_assignment_is_unique_capped_and_auto_uses_only_idle_people() -> void:
	var c:=make_case();var r: TDEmployeeRoster=c.roster;var p: TDGameProfile=c.profile;add_stores(p)
	for row: Dictionary in r.config.templates: own(r,row.id)
	assert_true(r.assign("manager.steady","player-branch:1").ok)
	assert_true(r.assign("cook-he","player_diner").ok)
	assert_true(r.assign("cook-zhou","player_diner").ok)
	var before:=r.snapshot()
	assert_eq(r.assign("cook-man","player_diner").code,"ROLE_FULL")
	assert_eq(r.snapshot(),before)
	assert_eq(r.assign("missing","player_diner").code,"EMPLOYEE_NOT_OWNED")
	assert_eq(r.assign("cook-man","unknown").code,"UNKNOWN_STORE")
	assert_true(r.auto_assign("player-branch:1").ok)
	assert_true(r.ready_for("player-branch:1"));assert_true(r.ready_for("player_diner"))
	assert_eq(r.employee_info("cook-he").assigned,"player_diner")
	assert_eq(r.employee_info("cook-zhou").assigned,"player_diner")
	assert_eq(r.assigned("player-branch:1","manager").size(),1)
	assert_eq(r.manager_for("player-branch:1").id,"manager.steady")
	assert_true(r.manager_info("cook-he").is_empty())
	assert_true(r.assign("manager.steady","player-branch:2").ok)
	assert_false(r.ready_for("player-branch:1"));assert_eq(r.assigned("player-branch:2","manager").size(),1)
	before=r.snapshot();assert_true(r.assign("manager.steady","player-branch:2").ok);assert_eq(r.snapshot(),before)
	p.shop._s.phase="OPEN"
	assert_eq(r.assign("cook-he","").code,"NOT_AT_BOUNDARY");assert_eq(r.draw(1,"cook","open").code,"RECRUITMENT_REPLACED")
	assert_eq(r.snapshot(),before)


func test_payroll_freezes_first_assignment_and_survives_transfer_dismissal_and_upgrade() -> void:
	var c:=make_case();var r: TDEmployeeRoster=c.roster;var p: TDGameProfile=c.profile;add_stores(p)
	own(r,"cook-he",2)
	assert_true(r.assign("cook-he","player_diner").ok)
	assert_eq(int(r.payroll_for("player_diner",1).total_cents),2300)
	r.state.owned["cook-he"].copies=3
	assert_true(r.assign("cook-he","player-branch:1").ok)
	assert_true(r.assign("cook-he","").ok)
	assert_eq(r.wages_for("player_diner"),0)
	assert_eq(int(r.payroll_for("player_diner",1).total_cents),2300)
	assert_eq(int(r.payroll_for("player-branch:1",1).total_cents),0)
	var before:=r.snapshot();r.record_duties(1);assert_eq(r.snapshot(),before)
	p.shop._s.day=2
	assert_true(r.assign("cook-he","player-branch:1").ok)
	assert_eq(int(r.payroll_for("player-branch:1",2).crew_cents),3450)
	assert_true(r.validate_save(r.snapshot(),p.branches.state.stores.keys(),2).ok)


func test_external_crew_runs_existing_buffs_and_growth_without_second_save_owner() -> void:
	var c:=make_case();var r: TDEmployeeRoster=c.roster;var p: TDGameProfile=c.profile
	own(r,"cook-man",3);own(r,"waiter-tao",1)
	assert_true(r.assign("cook-man","player_diner").ok);assert_true(r.assign("waiter-tao","player_diner").ok)
	assert_true(p.layout.crew.external)
	assert_eq(p.layout.crew.cooks()[0].id,"cook-man")
	assert_eq(p.layout.crew.level_of("cook-man"),3)
	assert_almost_eq(p.layout.crew.tip_scale(),1.05,.0001)
	p.layout.crew.record_served_order()
	assert_eq(int(r.state.owned["cook-man"].xp),1)
	assert_true(p.layout.crew.export_state().is_empty())
	assert_eq(p.layout.crew.hire("cook-he").code,"ROSTER_MANAGED")
	assert_true(r.assign("cook-man","").ok);assert_true(p.layout.crew.cooks().is_empty())
	var old:=TDRestaurantCrew.new();assert_true(old.hire("cook-he").ok)
	assert_eq(old.export_state(),[{"id":"cook-he","xp":0}],"standalone old crews remain compatible")


func test_after_settlement_assignment_waits_until_next_day_and_future_branch_does_not_bill_early() -> void:
	var c:=make_case();var r: TDEmployeeRoster=c.roster;var p: TDGameProfile=c.profile;add_stores(p)
	own(r,"cook-he");own(r,"manager.host",3)
	p.shop._s.phase="SETTLED"
	assert_true(r.assign("cook-he","player_diner").ok)
	assert_eq(int(r.payroll_for("player_diner",1).total_cents),0)
	p.branches.state.stores["player-branch:1"].start_day=3
	assert_true(r.assign("manager.host","player-branch:1").ok)
	p.shop._s.phase="PREPARE";p.shop._s.day=2;r.record_duties(2)
	assert_eq(int(r.payroll_for("player_diner",2).total_cents),2300)
	assert_eq(int(r.payroll_for("player-branch:1",2).total_cents),0)
	p.shop._s.day=3;r.record_duties(3)
	assert_eq(int(r.payroll_for("player-branch:1",3).total_cents),2800)


func test_migration_preserves_existing_stars_names_experience_and_independent_branch_staff() -> void:
	var c:=make_case();var r: TDEmployeeRoster=c.roster;var p: TDGameProfile=c.profile;add_stores(p)
	for store: Dictionary in p.branches.state.stores.values(): store.manager_id="manager.master"
	var before_cash: int=int(p.shop.snapshot().money_cents)
	assert_true(r.migrate_legacy([{"id":"cook-zhou","xp":12}],p.branches.state,{"greeter":true,"cashier":true,"runner":true}).ok)
	assert_eq(int(r.employee_info("cook-zhou").xp),12)
	var one:=r.manager_for("player-branch:1");var two:=r.manager_for("player-branch:2")
	assert_eq(int(one.stars),3);assert_eq(int(two.stars),3);assert_ne(one.id,two.id);assert_ne(one.name,two.name)
	assert_true(r.ready_for("player-branch:1"));assert_true(r.ready_for("player-branch:2"))
	assert_eq(r.assigned("player_diner","waiter").size(),2)
	assert_eq(r.assigned("","waiter").size(),1,"excess old front-desk employee retained idle")
	assert_eq(int(p.shop.snapshot().money_cents),before_cash)
	var before:=r.snapshot();assert_true(r.migrate_legacy([],{},{}).ok);assert_eq(r.snapshot(),before)
	assert_true(r.validate_save(before,p.branches.state.stores.keys(),1).ok)


func test_save_roundtrip_invalid_identity_assignment_payroll_and_version_are_atomic() -> void:
	var c:=make_case();var r: TDEmployeeRoster=c.roster;var p: TDGameProfile=c.profile
	own(r,"cook-he");assert_true(r.assign("cook-he","player_diner").ok)
	var raw: Dictionary=JSON.parse_string(JSON.stringify(r.snapshot()))
	assert_true(r.restore(raw).ok)
	var before:=r.snapshot()
	var bad:=before.duplicate(true);bad.schema_version=99
	assert_eq(r.restore(bad).code,"INVALID_EMPLOYEE_VERSION");assert_eq(r.snapshot(),before)
	bad=before.duplicate(true);bad.owned["cook-he"].copies=10
	assert_false(r.restore(bad).ok);assert_eq(r.snapshot(),before)
	bad=before.duplicate(true);bad.owned["cook-he"].assigned="made-up"
	assert_false(r.restore(bad).ok);assert_eq(r.snapshot(),before)
	bad=before.duplicate(true);bad.duties["1"]["cook-he"].cents=1
	assert_false(r.restore(bad).ok);assert_eq(r.snapshot(),before)
	bad=before.duplicate(true);bad.pity_count=10
	assert_false(r.restore(bad).ok);assert_eq(r.snapshot(),before)
	bad=before.duplicate(true);bad.owned["stranger"]={"id":"stranger","copies":1,"xp":0,"assigned":""}
	assert_false(r.restore(bad).ok);assert_eq(r.snapshot(),before)


func test_old_employee_schema_one_migrates_without_changing_names_or_assignments() -> void:
	var c:=make_case();var r: TDEmployeeRoster=c.roster
	own(r,"cook-he",3);assert_true(r.assign("cook-he","player_diner").ok)
	var before:=r.employee_info("cook-he");var raw:=r.snapshot();raw.schema_version=1
	var checked:=r.restore(JSON.parse_string(JSON.stringify(raw)))
	assert_true(checked.ok,checked.code);assert_eq(int(r.state.schema_version),3)
	assert_eq(r.employee_info("cook-he"),before)
	assert_eq(int(r.payroll_for("player_diner",1).total_cents),3450)


func test_versioned_archetype_membership_does_not_remap_when_new_templates_are_added() -> void:
	var r:=TDEmployeeRoster.new();var id: String="employee.v1.s002.n005"
	var before:=r.employee_info(id)
	var extra: Dictionary=r.config.templates[0].duplicate(true);extra.id="cook-future";extra.wages_cents=[1,2,3]
	r.config.templates.append(extra);r._generated_defs.clear()
	assert_eq(r.employee_info(id),before)
	var copy:=r.employee_info(id);copy.wages_cents[0]=1;copy.name="changed"
	assert_eq(r.employee_info(id),before,"cached definitions remain read-only")
	var bad:=r.config.duplicate(true);bad.name_generator.archetypes.cook.append("missing")
	assert_eq(TDEmployeeRoster.validate_config(bad).code,"EMPLOYEE_CONFIG_ARCHETYPES")

func test_fixed_catalogue_has_360_unique_people_and_descending_star_counts() -> void:
	var r:=TDEmployeeRoster.new();assert_true(r.error.ok,r.error.code)
	assert_eq(r.config.fixed_employees.size(),360)
	var names: Dictionary={};var ids: Dictionary={}
	for town: String in r.config.recruitment.towns:
		for role: String in TDEmployeeRoster.ROLES:
			var hist: Array[int]=[0,0,0]
			for row: Dictionary in r.config.fixed_employees:
				if row.town==town and row.role==role: hist[int(row.stars)-1]+=1
			assert_eq(hist,[8,3,1] if role=="manager" else [20,7,3])
	for row: Dictionary in r.config.fixed_employees:
		assert_false(ids.has(row.id));assert_false(names.has(row.name));ids[row.id]=true;names[row.name]=true
		var info:=r.employee_info(row.id)
		assert_eq(int(info.stars),int(row.stars));assert_eq(info.quality,row.quality,"fixed attributes cannot be multiplied again")
		assert_eq(int(info.sign_fee_cents),int(info.wage_cents)*2)
	var before:=r.employee_info("staff.cn.001");r.config.fixed_employees.reverse()
	assert_eq(r.employee_info("staff.cn.001"),before)

func test_invalid_fixed_catalogue_rejected() -> void:
	var r:=TDEmployeeRoster.new()
	for field: String in ["id","name"]:
		var bad:=r.config.duplicate(true);bad.fixed_employees[1][field]=bad.fixed_employees[0][field];assert_false(r.validate_config(bad).ok)
	for pair: Array in [["stars",4],["quality",INF],["town","missing"],["role","magic"],["sign_fee_cents",1],["buff","infinite_money"]]:
		var bad:=r.config.duplicate(true);bad.fixed_employees[0][pair[0]]=pair[1];assert_false(r.validate_config(bad).ok)
	var bad:=r.config.duplicate(true);bad.recruitment.candidate_slots=[1,2,5];assert_false(r.validate_config(bad).ok)
	bad=r.config.duplicate(true);bad.fixed_employees[0].wages_cents=[-1,-1,-1];assert_false(r.validate_config(bad).ok)

func test_market_is_read_only_deterministic_and_has_5_2_1_per_town_role() -> void:
	var a:=make_case();var b:=make_case();a.roster.state.seed=714;b.roster.state.seed=714
	var before: Dictionary=a.profile.snapshot()
	for town: String in a.roster.config.recruitment.towns:
		for role: String in TDEmployeeRoster.ROLES:
			var offers: Array=a.roster.market_rows(town,role);var hist: Array[int]=[0,0,0]
			assert_eq(offers,b.roster.market_rows(town,role));assert_eq(offers.size(),8)
			for row: Dictionary in offers:
				hist[int(row.stars)-1]+=1;assert_eq(row.town,town);assert_eq(row.role,role);assert_false(row.owned)
			assert_eq(hist,[5,2,1])
	assert_eq(a.profile.snapshot(),before)
	assert_true(a.roster.market_rows("bad","cook").is_empty());assert_true(a.roster.market_rows("chengdu","bad").is_empty())

func test_named_contract_pays_once_enters_idle_warehouse_and_balances_cash() -> void:
	var c:=make_case();var r:TDEmployeeRoster=c.roster;var p:TDGameProfile=c.profile
	var cash: int=int(p.shop.snapshot().money_cents);var audit:=p.commerce.cash_audit(cash)
	var offer:=sign_first(r)
	assert_eq(int(p.shop.snapshot().money_cents),cash-int(offer.sign_fee_cents))
	assert_eq(p.commerce.cash_audit(int(p.shop.snapshot().money_cents)),audit)
	assert_eq(r.employee_info(offer.id).assigned,"");assert_eq(r.wages_for("player_diner"),0)
	assert_eq(int(r.payroll_for("player_diner",1).total_cents),0)
	var before:=r.snapshot();var shop:=p.shop.snapshot()
	assert_eq(r.sign_employee(offer.id,"sign",offer.offer_key).code,"DUPLICATE")
	assert_eq(r.sign_employee(offer.id,"again",offer.offer_key).code,"ALREADY_OWNED")
	assert_eq(r.draw(10,"cook","obsolete").code,"RECRUITMENT_REPLACED")
	assert_eq(r.snapshot(),before);assert_eq(p.shop.snapshot(),shop)
	assert_false(r.market_rows("chengdu","cook").any(func(row:Dictionary)->bool:return row.id==offer.id))
	assert_eq(r.market_rows("chengdu","cook").size(),8,"replacement uses another actual fixed employee")

func test_broke_stale_invalid_and_closed_signatures_are_atomic() -> void:
	var c:=make_case();var r:TDEmployeeRoster=c.roster;var p:TDGameProfile=c.profile
	var offer: Dictionary=r.market_rows("chengdu","cook")[0]
	var before:=r.snapshot()
	assert_false(r.sign_employee("fake","token",offer.offer_key).ok)
	assert_false(r.sign_employee(offer.id,"",offer.offer_key).ok)
	assert_eq(r.sign_employee(offer.id,"stale","old-offer").code,"OFFER_EXPIRED")
	p.shop.world_adjustment(-int(p.shop.snapshot().money_cents),"broke","fixture")
	var shop:=p.shop.snapshot();assert_false(r.sign_employee(offer.id,"broke",offer.offer_key).ok)
	assert_eq(p.shop.snapshot(),shop);assert_eq(r.snapshot(),before)
	p.shop._s.phase="OPEN";assert_eq(r.sign_employee(offer.id,"open",offer.offer_key).code,"NOT_AT_BOUNDARY")
	p.close();assert_eq(r.sign_employee(offer.id,"closed",offer.offer_key).code,"NOT_AT_BOUNDARY");assert_eq(r.snapshot(),before)

func test_market_staggered_rotation_rejects_old_offer_and_keeps_fixed_stats() -> void:
	var c:=make_case();var r:TDEmployeeRoster=c.roster;var p:TDGameProfile=c.profile
	var first: Array=r.market_rows("chengdu","cook");var offer: Dictionary=first[0];var info:=r.employee_info(offer.id)
	p.shop._s.day=int(offer.last_day);assert_eq(r.market_rows("chengdu","cook"),first)
	p.shop._s.day=int(offer.last_day)+1
	var next: Array=r.market_rows("chengdu","cook");assert_ne(next[0].offer_key,offer.offer_key)
	assert_eq(r.sign_employee(offer.id,"expired",offer.offer_key).code,"OFFER_EXPIRED")
	assert_eq(r.employee_info(offer.id),info)
	var groups: Dictionary={}
	for town: String in r.config.recruitment.towns:
		for role: String in r.ROLES: groups[int(r.market_rows(town,role)[0].last_day)]=true
	assert_gt(groups.size(),1,"not all market groups rotate on one day")

func test_fixed_star_never_merges_and_exhausted_tier_stays_empty() -> void:
	var c:=make_case();var r:TDEmployeeRoster=c.roster
	var offers:=r.market_rows("chengdu","manager");var high: Dictionary=offers.back()
	assert_eq(int(high.stars),3);assert_true(r.sign_employee(high.id,"high",high.offer_key).ok)
	assert_eq(r.market_rows("chengdu","manager").size(),7,"only one fixed three-star manager in this town")
	assert_false(r.market_rows("chengdu","manager").any(func(row:Dictionary)->bool:return int(row.stars)==3))
	var low:=sign_first(r,"manager","low");var raw:=r.snapshot();raw.owned[low.id].copies=9
	assert_eq(r.validate_save(raw).code,"INVALID_FIXED_EMPLOYEE")
	assert_eq(int(r.employee_info(low.id).stars),1)

func test_fixed_assignment_dismissal_daily_wage_and_contract_save_validation() -> void:
	var c:=make_case();var r:TDEmployeeRoster=c.roster;var p:TDGameProfile=c.profile;add_stores(p)
	var offer:=sign_first(r);var wage: int=int(offer.wage_cents)
	assert_true(r.assign(offer.id,"player_diner").ok);assert_eq(int(r.payroll_for("player_diner",1).total_cents),wage)
	assert_true(r.assign(offer.id,"player-branch:1").ok);assert_eq(int(r.payroll_for("player-branch:1",1).total_cents),0)
	assert_true(r.assign(offer.id,"").ok);assert_eq(int(r.payroll_for("player_diner",1).total_cents),wage)
	p.shop._s.day=2;r.record_duties(2);assert_eq(int(r.payroll_for("player_diner",2).total_cents),0)
	var raw: Dictionary=JSON.parse_string(JSON.stringify(r.snapshot()));assert_true(r.restore(raw).ok)
	var baseline:=r.snapshot()
	for field: String in ["token","fee_cents","day"]:
		var bad:=baseline.duplicate(true);bad.contracts[offer.id][field]="not-paid" if field=="token" else -1
		assert_false(r.restore(bad).ok);assert_eq(r.snapshot(),baseline)
	var bad:=baseline.duplicate(true);bad.contracts.clear();assert_false(r.restore(bad).ok)

func test_old_schema_two_generated_identity_keeps_abilities_and_salary() -> void:
	var c:=make_case();var r:TDEmployeeRoster=c.roster;var id: String="employee.v1.s002.n005"
	own(r,id,9);assert_true(r.assign(id,"player_diner").ok)
	var info:=r.employee_info(id);var raw:=r.snapshot();raw.schema_version=2;raw.erase("contracts")
	assert_true(r.restore(JSON.parse_string(JSON.stringify(raw))).ok)
	assert_eq(r.employee_info(id),info);assert_eq(r.state.contracts,{})
	assert_eq(int(r.state.schema_version),3)
