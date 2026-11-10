extends GutTest
var profiles: Array[TDGameProfile]=[]
func make_profile() -> TDGameProfile:
	var p:=TDGameProfile.new();profiles.append(p);p.slot_id="slot-01"
	assert_true(p.error.ok,p.error.code)
	p.shop.world_adjustment(300000,"fixture","test funding")
	for person: Dictionary in p.employees.config.templates:
		p.employees.state.owned[person.id]={"id":person.id,"copies":1,"xp":0,"assigned":""}
	return p
func after_each() -> void:
	for p: TDGameProfile in profiles: p.close()
	profiles.clear()
func cross_day(p: TDGameProfile) -> void:
	assert_true(p.shop.close_for_night().ok)
	var result:=p.next_day();assert_true(result.ok,result.code)
func test_unpaid_preview_and_failed_payment_leave_no_store_or_land() -> void:
	var p:=make_profile();var before:=p.snapshot()
	assert_true(p.branches.quote("chengdu",[6,48,3,4],"cn").ok)
	assert_eq(p.snapshot(),before)
	p.shop.world_adjustment(-int(p.shop.snapshot().money_cents),"empty","fixture")
	before=p.snapshot()
	assert_false(p.branches.open_store("chengdu",[6,48,3,4],"cn","","payment").ok)
	assert_eq(p.snapshot(),before)
func test_payment_without_manager_builds_next_day_then_requires_real_staff() -> void:
	var p:=make_profile();var before: int=int(p.shop.snapshot().money_cents)
	var result:=p.branches.open_store("chengdu",[6,48,3,4],"cn","","payment")
	assert_true(result.ok,result.code)
	if not result.ok: return
	var id: String=result.data.store_id
	assert_eq(int(p.shop.snapshot().money_cents),before-30800)
	assert_false(p.branches.is_built(id));assert_true(p.branches.plots("chengdu")[0].construction)
	assert_false(p.branches.open_store("chengdu",[6,48,3,4],"cn","","payment").ok)
	assert_eq(p.branches.state.stores.size(),1)
	assert_eq(p.branches.set_management(id,true).code,"UNDER_CONSTRUCTION")
	var saved:=p.snapshot();assert_true(TDGameProfile.validate_save(saved).ok)
	var q:=make_profile();assert_true(q.restore(saved).ok);assert_false(q.branches.is_built(id))
	cross_day(p)
	assert_true(p.branches.is_built(id));assert_false(p.branches.plots("chengdu")[0].construction)
	assert_eq(p.branches.set_management(id,true).code,"MANAGER_REQUIRED")
	assert_false(p.employees.ready_for(id));assert_true(p.branches.candidates("chengdu",{}).is_empty())
	assert_true(p.employees.assign("manager.steady",id).ok)
	assert_true(p.branches.set_management(id,true).ok)
	assert_true(p.employees.ready_for(id))
	assert_true(p.employees.assign("manager.steady","").ok)
	assert_false(p.employees.ready_for(id));assert_true(p.branches.candidates("chengdu",{}).is_empty())
func test_payment_proof_corruption_and_missing_construction_rejected() -> void:
	var p:=make_profile();var result:=p.branches.open_store("chengdu",[6,48,3,4],"cn","manager.steady","payment")
	assert_true(result.ok)
	var raw:=p.snapshot();var id: String=result.data.store_id
	assert_true(TDGameProfile.validate_save(raw).ok)
	var bad:=raw.duplicate(true);bad.branches.stores[id].construction.token="fake"
	assert_eq(TDGameProfile.validate_save(bad).code,"INVALID_BRANCH_PAYMENT")
	bad=raw.duplicate(true);bad.branches.stores[id].construction.paid_cents=1
	assert_eq(TDGameProfile.validate_save(bad).code,"INVALID_BRANCH_CONSTRUCTION")
	bad=raw.duplicate(true);bad.branches.stores[id].erase("construction")
	assert_false(TDGameProfile.validate_save(bad).ok)
	bad=raw.duplicate(true);bad.branches.stores[id].construction.ready_day=1
	assert_false(TDGameProfile.validate_save(bad).ok)
func test_old_paid_receipt_is_reused_without_recharging() -> void:
	var p:=make_profile();var result:=p.branches.open_store("chengdu",[6,48,3,4],"cn","manager.steady","old-paid")
	assert_true(result.ok);var raw:=p.snapshot();var id: String=result.data.store_id
	raw.branches.schema_version=1;raw.branches.stores[id].erase("construction")
	var q:=make_profile();assert_true(q.restore(raw).ok)
	assert_eq(q.branches.state.stores[id].construction.token,"old-paid")
	assert_eq(q.shop.snapshot().money_cents,raw.shop.money_cents)
	assert_true(TDGameProfile.validate_save(q.snapshot()).ok)
func test_unproven_legacy_record_is_preserved_but_cannot_operate_or_occupy_map() -> void:
	var p:=make_profile()
	assert_true(p.world.open_branch_in_town("paris").ok) # Old flag changed without Shop payment.
	var raw:=p.snapshot();raw.schema_version=7;raw.erase("branches")
	var q:=make_profile();var restored:=q.restore(raw);assert_true(restored.ok,restored.code)
	if not restored.ok: return
	var id: String=q.branches.state.stores.keys()[0]
	assert_eq(q.branches.state.stores[id].construction.kind,"unverified")
	assert_eq(q.shop.snapshot().money_cents,raw.shop.money_cents)
	assert_true(q.branches.plots("paris").is_empty());assert_true(q.branches.paid_ids().is_empty())
	assert_false(q.branches.is_built(id));assert_false(q.employees.ready_for(id))
	assert_true(q.branches.candidates("paris",{}).is_empty())
	assert_true(TDGameProfile.validate_save(q.snapshot()).ok)
	var before:=q.snapshot();var again:=make_profile();assert_true(again.restore(before).ok)
	assert_eq(again.branches.snapshot(),q.branches.snapshot())
	var rect: Array=again.branches.state.stores[id].rect
	var repaired: TDOutcome=again.branches.fund_unverified(id,"repair")
	assert_true(repaired.ok,repaired.code)
	assert_eq(again.branches.state.stores[id].rect,rect)
	assert_eq(again.branches.paid_ids().size(),1);assert_false(again.branches.is_built(id))
	assert_true(TDGameProfile.validate_save(again.snapshot()).ok)
func test_construction_charges_no_wage_or_utility_and_closed_staff_charges_only_rent() -> void:
	var p:=make_profile();var result:=p.branches.open_store("chengdu",[6,48,3,4],"cn","manager.steady","payment")
	assert_true(result.ok);var id: String=result.data.store_id
	p.employees.record_duties();assert_eq(p.employees.payroll_for(id,1).total_cents,0)
	p.branches.settle();assert_true(p.branches.state.stores[id].books.is_empty())
	cross_day(p)
	p.branches.prepare();p.branches.settle()
	var book: Dictionary=p.branches.state.stores[id].books.back()
	assert_gt(int(book.rent_cents),0);assert_eq(int(book.utilities_cents),0)
	var money: int=int(p.shop.snapshot().money_cents);p.branches.settle();assert_eq(p.shop.snapshot().money_cents,money)

func test_all_five_towns_share_paid_construction_projection_and_json_roundtrip() -> void:
	var p:=make_profile()
	for town: String in TDTravelCatalog.IDS:
		var rect: Array=[]
		for y: int in range(4,68):
			for x: int in range(2,68):
				if p.branches.quote(town,[x,y,3,4],"cn").ok: rect=[x,y,3,4];break
			if not rect.is_empty(): break
		var result:=p.branches.open_store(town,rect,"cn","","pay:"+town);assert_true(result.ok,result.code)
		var map:=TDTravelCatalog.map_for(p,town)
		var plots: Array=map.plots.filter(func(plot:Dictionary)->bool:return plot.has("branch_id"))
		assert_eq(plots.size(),1);assert_true(plots[0].construction)
	var raw: Dictionary=JSON.parse_string(JSON.stringify(p.snapshot()))
	var checked:=TDGameProfile.validate_save(raw);assert_true(checked.ok,checked.code)
	var q:=make_profile();assert_true(q.restore(raw).ok);cross_day(q)
	for town: String in TDTravelCatalog.IDS:
		var plots: Array=TDTravelCatalog.map_for(q,town).plots.filter(func(plot:Dictionary)->bool:return plot.has("branch_id"))
		assert_eq(plots.size(),1);assert_false(plots[0].construction)
	assert_true(TDGameProfile.validate_save(q.snapshot()).ok)

func test_unverified_archive_never_reserves_land_or_claims_an_unrelated_payment() -> void:
	var p:=make_profile();assert_true(p.world.open_branch_in_town("paris").ok)
	var raw:=p.snapshot();raw.schema_version=7;raw.erase("branches")
	var q:=make_profile();assert_true(q.restore(raw).ok)
	var old_id: String=q.branches.state.stores.keys()[0];var old: Dictionary=q.branches.state.stores[old_id]
	var opened:=q.branches.open_store(old.town_id,old.rect,old.cuisine_id,"","different-store-payment")
	assert_true(opened.ok,opened.code)
	assert_ne(opened.data.store_id,old_id);assert_false(q.branches.funded(old_id))
	assert_eq(q.branches.fund_unverified(old_id,"repair-now").code,"OCCUPIED")
	assert_true(TDGameProfile.validate_save(q.snapshot()).ok)
	assert_true(q.branches.state.legacy.unverified_archive.has(old_id))
