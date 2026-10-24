extends GutTest

func test_bank_money_is_transferred_not_created_and_requests_are_atomic() -> void:
	var bank:=TDCommunityBank.new({"reserve_cents":10000,"reserve_floor_cents":1000,"loan_limit_cents":2000,"term_days":7,"loan_daily_bps":100,"deposit_daily_bps":0})
	assert_true(bank.transact("player","deposit",1000,1000,1,"save:1").ok)
	assert_eq(int(bank.state.reserve_cents),11000)
	assert_true(bank.transact("player","borrow",2000,0,1,"loan:1").ok)
	assert_eq(int(bank.state.reserve_cents),9000)
	var before:=bank.state.duplicate(true)
	assert_eq(bank.transact("player","borrow",1,0,1,"loan:2").code,"CREDIT_LIMIT")
	assert_eq(bank.transact("player","borrow",2000,0,1,"loan:1").code,"DUPLICATE")
	assert_eq(bank.transact("player","withdraw",1001,0,1,"withdraw:1").code,"INSUFFICIENT_DEPOSIT")
	assert_eq(bank.state,before)
	assert_true(bank.accrue(1).ok)
	assert_eq(int(bank.account("player").interest_cents),20) # 2000 * 1%, independent expected value.
	assert_eq(int(bank.audit().difference_cents),0)
	before=bank.state.duplicate(true);assert_false(bank.accrue(1).ok);assert_eq(bank.state,before)
	var repaid:=bank.transact("player","repay",520,520,2,"repay:1")
	assert_true(repaid.ok);assert_eq(int(repaid.data.interest_paid_cents),20)
	assert_eq(int(bank.account("player").principal_cents),1500)
	assert_eq(int(bank.audit().difference_cents),0)
	assert_eq(bank.transact("player","borrow",1,0,9,"late:loan").code,"LOAN_OVERDUE")
	assert_true(bank.transact("player","withdraw",1000,0,9,"late:withdraw").ok)
	var restored:=TDCommunityBank.new();assert_true(restored.restore(JSON.parse_string(JSON.stringify(bank.state))).ok)
	var broken:=bank.state.duplicate(true);broken.reserve_cents+=1
	assert_eq(restored.restore(broken).code,"BANK_UNBALANCED")

func test_bank_fractional_interest_and_liquidity_limits() -> void:
	var bank:=TDCommunityBank.new({"reserve_cents":1000,"reserve_floor_cents":500,"loan_limit_cents":10000,"term_days":28,"loan_daily_bps":5,"deposit_daily_bps":0})
	assert_eq(bank.transact("a","borrow",501,0,1,"a:1").code,"BANK_LIQUIDITY")
	assert_true(bank.transact("a","borrow",100,0,1,"a:2").ok)
	for day: int in range(1,21): assert_true(bank.accrue(day).ok)
	assert_eq(int(bank.account("a").interest_cents),1) # 100 cents * .0005 * 20 days.
	assert_eq(int(bank.account("a").interest_fraction),0)
	assert_eq(int(bank.audit().difference_cents),0)

func society_fixture() -> TDCommunitySociety:
	var configuration: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(TDWorldEconomy.SOURCE))
	return TDCommunitySociety.new(configuration,configuration.active_towns,configuration.groups)

func test_household_payment_reservation_refund_and_wages_are_real() -> void:
	var society:=society_fixture()
	var id:=society.identity("chengdu","value",0)
	var family: Dictionary=society.state.households[id]
	family.cash_cents=1500
	assert_true(society.reserve(id,1300,"guest:1").ok)
	assert_eq(society.available(id),200)
	assert_eq(society.reserve(id,300,"guest:2").code,"HOUSEHOLD_BUDGET")
	var paid:=society.pay("guest:1",500)
	assert_true(paid.ok);assert_eq(int(paid.data.tip_cents),200)
	assert_eq(int(family.cash_cents),0)
	assert_false(society.pay("guest:1",500).ok)
	assert_true(society.refund("guest:1",1500).ok)
	assert_eq(int(family.cash_cents),1500)
	assert_false(society.refund("guest:1",1500).ok)
	assert_true(society.reserve(id,1300,"guest:3").ok);society.release("guest:3")
	assert_eq(society.available(id),1500)
	var hired:=society.hire("employer","chengdu",1,3000)
	assert_true(hired.ok)
	var worker: Dictionary=society.state.households[hired.data.household_ids[0]]
	var before: int=int(worker.cash_cents)
	var wages:=society.payroll("employer",3000,1)
	assert_eq(int(wages.paid_cents),3000)
	assert_eq(int(worker.cash_cents),before+2950) # 3000 - (3000-2000)*5%.
	assert_eq(int(society.state.public.chengdu),50)
	assert_eq(int(society.payroll("employer",3000,1).paid_cents),0)

func test_household_social_cash_bank_and_daily_flow_conserve() -> void:
	var society:=society_fixture()
	var before:=society.cash_total()
	assert_true(society.finish_day(1).ok)
	assert_eq(society.cash_total()-before,int(society.state.external_net_cents))
	assert_eq(int(society.bank.audit().difference_cents),0)
	var saved:=society.state.duplicate(true)
	assert_false(society.finish_day(1).ok);assert_eq(society.state,saved)
	var loaded:=society_fixture();assert_true(loaded.restore(JSON.parse_string(JSON.stringify(saved))).ok)
	assert_eq(loaded.cash_total(),society.cash_total())
	assert_eq(loaded.state.bank.seen.size(),0,"Automatic daily banking uses bounded account day cursors.")
	var bad:=saved.duplicate(true);bad.households.values()[0].cash_cents=-1
	assert_false(loaded.restore(bad).ok)

func test_five_cuisines_and_story_routes_do_not_unlock_recipes_implicitly() -> void:
	var world:=TDWorldEconomy.new({"tomato":200,"egg":150})
	assert_eq(world.state.markets.size(),5)
	assert_eq(world.state.routes,["chengdu"])
	assert_true(world.open_route("tokyo","story:tokyo").ok)
	assert_eq(world.state.routes,["chengdu","tokyo"])
	var before:=world.snapshot()
	assert_false(world.open_route("tokyo","story:tokyo").ok)
	assert_eq(world.snapshot(),before)
	assert_false(world.open_route("london","old:inactive").ok)
