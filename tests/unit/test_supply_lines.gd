extends GutTest
var profiles: Array[TDGameProfile]=[]
func make_profile() -> TDGameProfile:
	var p:=TDGameProfile.new();profiles.append(p);p.slot_id="slot-01"
	assert_true(p.error.ok,p.error.code)
	p.shop.world_adjustment(300000,"line-fixture","test funding")
	for town: String in TDSupplierNetwork.TOWNS:
		p.commerce.state.markets[town].price.tomato=100
	return p
func line(p: TDGameProfile, amount: int=2000, town: String="chengdu", item: String="tomato") -> String:
	var outcome:=p.suppliers.create_line(town,"player_diner",item,p.suppliers._on_hand("player_diner",item)+amount)
	assert_true(outcome.ok,outcome.code);return str(outcome.data.get("line_id",""))
func after_each() -> void:
	for p: TDGameProfile in profiles: p.close()
	profiles.clear()

func test_continuous_batches_real_money_source_stock_target_and_business_delivery() -> void:
	var p:=make_profile();var n:=p.suppliers;line(p)
	var stock: int=p.shop.available("tomato");var cash: int=int(p.shop.snapshot().money_cents);var source: int=int(p.commerce.state.markets.chengdu.stock.tomato)
	assert_true(p.shop.open_day().ok)
	n.advance_game_minutes(29)
	assert_eq(p.shop.available("tomato"),stock);assert_eq(int(p.shop.snapshot().money_cents),cash-100)
	n.advance_game_minutes(1)
	assert_eq(p.shop.available("tomato"),stock+1000);assert_eq(int(p.shop.snapshot().money_cents),cash-200)
	n.advance_game_minutes(30)
	assert_eq(p.shop.available("tomato"),stock+2000);assert_eq(int(p.commerce.state.markets.chengdu.stock.tomato),source-2000)
	var before:=p.snapshot();n.advance_game_minutes(300);assert_eq(p.snapshot(),before)
	assert_true(p.shop.consume_materials(p.shop.day_namespace()+"test-eaten",{"tomato":500}).ok)
	n.advance_game_minutes(15)
	assert_eq(p.shop.available("tomato"),stock+2000);assert_eq(int(p.shop.snapshot().money_cents),cash-250)

func test_budget_and_shortage_fail_atomically_and_recover() -> void:
	var p:=make_profile();var n:=p.suppliers;line(p)
	n.set_automation("player_diner",false,99)
	var cash: int=int(p.shop.snapshot().money_cents);var stock: int=int(p.commerce.state.markets.chengdu.stock.tomato)
	n.advance_game_minutes(100)
	assert_true(n.state.orders.is_empty());assert_eq(int(p.shop.snapshot().money_cents),cash);assert_eq(int(p.commerce.state.markets.chengdu.stock.tomato),stock)
	n.set_automation("player_diner",false,100);p.commerce.state.markets.chengdu.stock.tomato=0;n.advance_game_minutes(100)
	assert_true(n.state.orders.is_empty())
	p.commerce.state.markets.chengdu.stock.tomato=stock;n.advance_game_minutes(300)
	assert_eq(n.state.orders.size(),1);assert_eq(int(n.state.automation.player_diner.spent_cents),100)
	assert_eq(n.line_rows()[0].status,"每日预算不足")

func test_transport_is_separate_and_does_not_occupy_capacity_or_double_charge() -> void:
	var p:=make_profile();var n:=p.suppliers;line(p,2000,"tokyo")
	var stock: int=p.shop.available("tomato");n.advance_game_minutes(30)
	assert_eq(p.shop.available("tomato"),stock);assert_eq(n.state.orders.size(),2,"Second batch starts while first is in transit")
	assert_eq(n.in_transit("player_diner","tomato"),2000)
	var cash: int=int(p.shop.snapshot().money_cents);n.advance_game_minutes(300)
	assert_eq(p.shop.available("tomato"),stock+2000);assert_eq(int(p.shop.snapshot().money_cents),cash)

func test_priorities_shared_capacity_pause_and_deleted_paid_batches() -> void:
	var p:=make_profile();var n:=p.suppliers
	var first:=line(p,1000);var second:=line(p,1000,"chengdu","egg")
	n.move_line(second,-1);n.advance_game_minutes(0)
	assert_eq(n.state.orders[0].jobs[0].item_id,"egg");assert_eq(n.state.orders.size(),1)
	n.remove_line(second);n.configure_line(first,int(n._line(first).target_units),1,false)
	var eggs: int=p.shop.available("egg");n.advance_game_minutes(60)
	assert_eq(p.shop.available("egg"),eggs+1000);assert_eq(n.state.orders.size(),1)
	n.configure_line(first,int(n._line(first).target_units),1,true);n.advance_game_minutes(30)
	assert_eq(n.state.orders.size(),2)

func test_slots_speed_and_no_capacity_creation() -> void:
	var p:=make_profile();var n:=p.suppliers;n.state.levels.chengdu=2
	var id:=line(p,1000);assert_true(n.configure_line(id,int(n._line(id).target_units),2,true).ok)
	assert_false(n.configure_line(id,1000,3,true).ok)
	var stock: int=p.shop.available("tomato");n.advance_game_minutes(11.24)
	assert_eq(p.shop.available("tomato"),stock)
	n.advance_game_minutes(.01);assert_eq(p.shop.available("tomato"),stock+1000,"30 minutes × 0.75 / 2 slots")

func test_partitions_legacy_clock_and_no_offline_restore_production() -> void:
	var p:=make_profile();var n:=p.suppliers;line(p,2500,"tokyo")
	var baseline:=p.snapshot();var q:=make_profile();assert_true(q.restore(baseline).ok)
	n.advance_game_minutes(300)
	for i: int in 600: q.suppliers.advance_game_minutes(.5)
	assert_eq(q.suppliers.snapshot(),n.snapshot());assert_eq(q.shop.snapshot(),p.shop.snapshot())
	assert_true(p.suppliers.order("chengdu","player_diner",{"egg":1000},"legacy").ok)
	var job: Dictionary=p.suppliers.state.orders.back().jobs[0]
	n.advance_game_minutes(1000);assert_eq(float(job.elapsed),0.0)
	n.advance(60);assert_eq(float(job.elapsed),60.0)
	var raw:=p.snapshot();var checked:=TDGameProfile.validate_save(raw);assert_true(checked.ok,checked.code)
	assert_true(q.restore(raw).ok);assert_eq(q.suppliers.snapshot(),raw.suppliers)

func test_internal_v1_migration_future_invalid_and_payment_cross_references() -> void:
	var p:=make_profile();var raw:=p.snapshot();raw.suppliers.schema_version=1;raw.suppliers.erase("lines");raw.suppliers.erase("line_serial")
	var q:=make_profile();assert_true(q.restore(raw).ok);assert_eq(int(q.suppliers.state.schema_version),2)
	line(p,1000);p.suppliers.advance_game_minutes(1)
	raw=p.snapshot();var checked:=TDGameProfile.validate_save(raw);assert_true(checked.ok,checked.code)
	for kind: String in ["version","slots","target","travel","unpaid"]:
		var bad:=raw.duplicate(true)
		match kind:
			"version": bad.suppliers.schema_version=3
			"slots": bad.suppliers.lines[0].slots=999
			"target": bad.suppliers.lines[0].store_id="missing"
			"travel": bad.suppliers.orders[0].jobs[0].transit_elapsed=5
			"unpaid": bad.suppliers.orders[0].total_cents+=1
		assert_false(TDGameProfile.validate_save(bad).ok,kind)

func test_sleep_completes_game_time_lines_but_not_legacy_and_respects_next_budget() -> void:
	var p:=make_profile();var n:=p.suppliers;line(p,2000,"tokyo")
	assert_true(n.order("chengdu","player_diner",{"egg":1000},"legacy-night").ok)
	var tomato: int=p.shop.available("tomato");var eggs: int=p.shop.available("egg")
	n.set_automation("player_diner",false,200)
	p.characters.clock.minute=1560
	assert_true(p.shop.close_for_night().ok);assert_true(p.next_day().ok)
	assert_eq(int(p.shop.snapshot().day),2);assert_eq(p.characters.clock.minute,480.0)
	assert_eq(p.shop.available("tomato"),tomato+1000,"Only one distance-priced batch fits 200 cents")
	assert_eq(p.shop.available("egg"),eggs)
	assert_eq(int(n.state.automation.player_diner.spent_day),2)
	var checked:=TDGameProfile.validate_save(p.snapshot());assert_true(checked.ok,checked.code)

func test_two_sources_count_same_stock_and_branch_budget_does_not_touch_home() -> void:
	var p:=make_profile();var n:=p.suppliers;line(p,1000);line(p,1000,"tokyo")
	n.advance_game_minutes(300);assert_eq(n.state.orders.size(),1)
	p.branches.managed=false
	var result:=p.branches.open_store("chengdu",[6,48,3,4],"cn","manager.steady","branch-test");assert_true(result.ok,result.code)
	var id: String=result.data.store_id
	p.branches.state.stores[id].budget_cents=100
	assert_true(n.create_line("chengdu",id,"tomato",2000).ok)
	var home: int=p.shop.available("tomato");n.advance_game_minutes(300)
	assert_eq(p.shop.available("tomato"),home);assert_eq(int(p.branches.state.stores[id].inventory.tomato),1000)
	assert_eq(int(p.branches.state.stores[id].daily.purchase_cents),100)

func test_automation_manual_ownership_closed_profile_and_nonfinite_time() -> void:
	var p:=make_profile();var n:=p.suppliers;var id:=line(p,1000)
	n.configure_line(id,int(n._line(id).target_units),1,false)
	n.set_automation("player_diner",true,5000);n.automate()
	assert_false(n._line(id).enabled);assert_false(n._line(id).managed)
	assert_gt(n.state.lines.size(),1)
	var before:=n.snapshot();n.advance_game_minutes(NAN);n.advance_game_minutes(-1);assert_eq(n.snapshot(),before)
	p.close();n.advance_game_minutes(1000);n.automate()
	assert_false(n.create_line("chengdu","player_diner","salt",1000).ok)
	assert_eq(n.snapshot(),before)

func test_mixed_legacy_and_continuous_clocks_are_partition_independent() -> void:
	var p:=make_profile();var n:=p.suppliers
	assert_true(n.order("chengdu","player_diner",{"tomato":1000},"legacy-mixed").ok)
	n.advance(1790);line(p,2000)
	var q:=make_profile();assert_true(q.restore(p.snapshot()).ok)
	n.advance_active_time(40,40)
	for i: int in 40: q.suppliers.advance_active_time(1,1)
	assert_eq(n.snapshot(),q.suppliers.snapshot());assert_eq(p.shop.snapshot(),q.shop.snapshot())

func test_zero_cash_rejection_and_readonly_views() -> void:
	var p:=make_profile();var n:=p.suppliers;line(p)
	p.shop.world_adjustment(-int(p.shop.snapshot().money_cents),"empty-cash","fixture")
	var before:=p.shop.snapshot();n.advance_game_minutes(100)
	assert_eq(p.shop.snapshot(),before);assert_true(n.state.orders.is_empty())
	assert_eq(n.line_rows()[0].status,"现金不足")
	var rows:=n.line_rows();rows[0].target_units=99999
	assert_ne(int(n.state.lines[0].target_units),99999)
