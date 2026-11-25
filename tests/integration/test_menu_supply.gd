extends GutTest

const HOME := "player_diner"
const DISH := "service.tomato_egg"
var p: TDGameProfile

func before_each() -> void:
	p=TDGameProfile.new()
	p.slot_id="slot-01"
	assert_true(p.error.ok,p.error.code)

func after_each() -> void:
	p.close()
	await wait_process_frames(2)

func qualify() -> void:
	# Use the real reward and calendar paths with a profitable daily report fixture.
	while p.menu_supply.level()<p.menu_supply.UNLOCK_LEVEL:
		var before: Dictionary=p.progression.snapshot().baselines[HOME]
		var day:=int(p.shop.snapshot().day)
		var row:={"store_id":HOME,"scale_milli":1000,"profit_cents":99999999,
			"popularity_before":before.popularity,"popularity_after":before.popularity,
			"awareness_before":before.awareness,"awareness_after":before.awareness}
		var award:=p.progression.settle({"day":day,"stores":[row]})
		assert_true(award.ok,award.code)
		if not award.ok: return
		for reward: Dictionary in award.data.rewards:
			p.research.grant_inspiration(reward.grant_id,int(reward.inspiration))
		assert_true(p.shop.close_for_night().ok)
		assert_true(p.next_day().ok)
	assert_true(p.menu_supply.set_enabled(true).ok)

func sleep() -> void:
	assert_true(p.shop.close_for_night().ok)
	var result:=p.next_day()
	assert_true(result.ok,result.code)

func test_planning_ui_delivery_prices_actual_ingredients_and_idempotent_save() -> void:
	assert_false(p.menu_supply.set_enabled(true).ok)
	qualify()
	assert_false(p.menu_supply.book(HOME,{DISH:10}).ok)
	p.characters.clock.minute=18*60
	var panel:=TDManagementPanels.SupplierPanel.new()
	add_child_autofree(panel)
	panel.configure(p)
	assert_false(panel.confirm.disabled)
	for spin: SpinBox in panel.inputs.values(): spin.value=0
	panel.inputs[DISH].value=10
	panel.confirm.pressed.emit()
	assert_eq(p.menu_supply.state.plans[HOME],{DISH:10})
	var cash:=int(p.shop.snapshot().money_cents)
	var inventory: Dictionary=p.shop.snapshot().inventory
	assert_false(p.menu_supply.book(HOME,{DISH:-1}).ok)
	assert_false(p.menu_supply.book(HOME,{"missing":1}).ok)
	assert_eq(p.shop.snapshot().inventory,inventory)
	assert_eq(int(p.shop.snapshot().money_cents),cash)
	var before:=p.snapshot()
	var copy:=TDGameProfile.new()
	var restored:=copy.restore(JSON.parse_string(JSON.stringify(before)))
	assert_true(restored.ok,restored.code)
	copy.close()
	assert_true(p.shop.close_for_night().ok)
	cash=int(p.shop.snapshot().money_cents)
	assert_true(p.next_day().ok)
	assert_eq(int(p.menu_supply.state.invoice_day),p.world.day)
	assert_gt(int(p.menu_supply.state.last_invoice),0)
	assert_eq(cash-int(p.shop.snapshot().money_cents),int(p.menu_supply.state.last_invoice))
	assert_eq(int(p.menu_supply.state.debt),0)
	var needs:=p.menu_supply.ingredients(HOME,{DISH:10},p.menu_supply.dishes(HOME))
	for item: String in ["tomato","egg","oil","salt"]:
		assert_gt(int(needs.get(item,0)),0,item)
		assert_gte(p.shop.available(item),int(needs[item]),item)
	assert_true(p.shop.snapshot().menu[DISH].enabled)
	assert_eq(p.menu_supply.quantities(HOME,p.menu_supply.dishes(HOME)),{DISH:10})
	var saved:=p.snapshot()
	var q:=TDGameProfile.new()
	restored=q.restore(JSON.parse_string(JSON.stringify(saved)))
	assert_true(restored.ok,restored.code)
	q.menu_supply.morning()
	assert_eq(q.shop.snapshot().inventory,p.shop.snapshot().inventory)
	assert_eq(int(q.shop.snapshot().money_cents),int(p.shop.snapshot().money_cents))
	q.close()
	var previous:=p.menu_supply.state.last_invoice as int
	sleep()
	assert_eq(int(p.menu_supply.state.last_invoice),previous,"No shortfall means no replacement invoice.")
	assert_lt(int(p.menu_supply.state.invoice_day),p.world.day)

func test_credit_exhaustion_stays_suspended_until_entire_balance_is_paid() -> void:
	qualify()
	p.characters.clock.minute=18*60
	assert_true(p.menu_supply.book(HOME,{DISH:99}).ok)
	assert_true(p.shop.close_for_night().ok)
	var cash:=int(p.shop.snapshot().money_cents)
	assert_true(p.shop.branch_adjustment(1-cash,"fixture-cash","test",HOME).ok)
	assert_true(p.next_day().ok)
	var debt:=int(p.menu_supply.state.debt)
	assert_gte(debt,p.menu_supply.credit())
	assert_eq(debt,int(p.menu_supply.state.last_invoice)-1)
	assert_true(p.menu_supply.state.suspended)
	assert_true(p.shop.world_adjustment(100,"partial","test").ok)
	assert_true(p.menu_supply.repay().ok)
	assert_eq(int(p.menu_supply.state.debt),debt-100)
	assert_true(p.menu_supply.state.suspended)
	assert_true(p.menu_supply.set_enabled(false).ok)
	assert_true(p.menu_supply.set_enabled(true).ok)
	var restored:=TDGameProfile.new()
	var loaded:=restored.restore(JSON.parse_string(JSON.stringify(p.snapshot())))
	assert_true(loaded.ok,loaded.code)
	assert_true(restored.menu_supply.state.suspended)
	assert_eq(int(restored.menu_supply.state.debt),debt-100)
	restored.close()
	assert_true(p.shop.consume_materials(p.shop.day_namespace()+"used",{"egg":1000}).ok)
	var egg:=p.shop.available("egg")
	sleep()
	assert_eq(p.shop.available("egg"),egg)
	assert_true(p.shop.world_adjustment(debt+10000,"clear-balance","test").ok)
	assert_true(p.menu_supply.repay().ok)
	assert_eq(int(p.menu_supply.state.debt),0)
	assert_false(p.menu_supply.state.suspended)
	sleep()
	assert_gt(p.shop.available("egg"),egg)

func test_branch_receives_its_own_fallback_menu_and_switch_off_stops_delivery() -> void:
	qualify()
	assert_true(p.shop.world_adjustment(300000,"branch-cash","test").ok)
	var rect:=TDRegionMigration.find_site(p.branches.town_map("chengdu"),[6,48,3,4])
	var opened:=p.branches.open_store("chengdu",rect,"cn","","real-site")
	assert_true(opened.ok,opened.code)
	if not opened.ok: return
	var id:=str(opened.data.store_id)
	sleep()
	var branch: Dictionary=p.branches.state.stores[id]
	var dish: Dictionary=branch.menu[0]
	for item: String in dish.ingredients:
		assert_gte(int(branch.inventory.get(item,0)),int(dish.ingredients[item])*p.menu_supply.DEFAULT_PORTIONS)
		assert_gt(int(branch.basis[item].value_cents),0)
	assert_true(p.menu_supply.set_enabled(false).ok)
	var billed:=int(p.menu_supply.state.invoice_day)
	sleep()
	assert_eq(int(p.menu_supply.state.invoice_day),billed)
	var legacy:=p.snapshot()
	legacy.erase("menu_supply")
	var q:=TDGameProfile.new()
	var restored:=q.restore(legacy)
	assert_true(restored.ok,restored.code)
	assert_false(q.menu_supply.state.enabled)
	assert_eq(int(q.menu_supply.state.debt),0)
	q.close()
