extends GutTest

var root: String
var store: TDProfileStore
var profiles: Array[TDGameProfile]=[]

func before_each() -> void:
	root="res://artifacts/profile-tests/%d-%d"%[Time.get_ticks_usec(),randi()]
	store=TDProfileStore.new(root,TDGameProfile.validate_save)

func after_each() -> void:
	for profile: TDGameProfile in profiles: profile.close()
	profiles.clear()
	await get_tree().process_frame
	await get_tree().process_frame

func create_profile(id: String) -> TDGameProfile:
	var profile:=TDGameProfile.new()
	profiles.append(profile)
	assert_true(profile.error.ok,profile.error.code)
	profile.slot_id=id;profile.persistence=store.save_slot
	return profile

func test_two_slots_keep_research_stock_and_layout_independent() -> void:
	var a:=create_profile("slot-01");var b:=create_profile("slot-02")
	assert_true(a.buy({"tomato":1000}).ok)
	assert_true(a.research.begin("C03").ok)
	a.research.cancel(str(a.research._active.token))
	assert_true(a.save().ok)
	assert_true(b.save().ok)
	var saved_a:=store.load_slot("slot-01");var saved_b:=store.load_slot("slot-02")
	assert_true(saved_a.ok,saved_a.code);assert_true(saved_b.ok,saved_b.code)
	assert_eq(int(saved_a.data.shop.inventory.tomato),1000)
	assert_eq(int(saved_b.data.shop.inventory.tomato),0)
	assert_has(saved_a.data.research.licensed,"C03")
	assert_false("C03" in saved_b.data.research.licensed)
	assert_eq(saved_b.data.research.unlocked,["C01","C02"])
	assert_eq(store.latest(),"slot-02")

func test_research_candidate_is_persisted_in_same_profile_transaction() -> void:
	var profile:=create_profile("slot-01")
	assert_true(profile.save().ok)
	var before:int=int(profile.research.snapshot().points)
	assert_true(profile.research.begin("C03").ok)
	var saved:=store.load_slot("slot-01")
	assert_true(saved.ok,saved.code)
	assert_eq(int(saved.data.research.points),before-1)
	assert_has(saved.data.research.licensed,"C03")
	assert_eq(saved.data.shop.run_id,profile.shop.snapshot().run_id)

func test_active_business_cannot_save_or_leave_and_research_rewards_stay_buffered() -> void:
	var profile:=create_profile("slot-01")
	assert_true(profile.save().ok)
	assert_true(profile.shop.open_day().ok)
	assert_false(profile.can_leave_shop())
	assert_eq(profile.save().code,"NOT_AT_BOUNDARY")
	assert_eq(profile.buy({"tomato":1000}).code,"SHOP_OPEN")
	var candidate:=profile.research.snapshot();candidate.points+=2
	assert_true(profile._research_candidate(candidate).ok)
	assert_eq(int(store.load_slot("slot-01").data.research.points),3)

func test_interrupted_writes_preserve_last_complete_package_and_allow_explicit_recovery() -> void:
	var profile:=create_profile("slot-01")
	assert_true(profile.save().ok)
	profile.title="第二版"
	store.interrupt_at="partial_write"
	assert_eq(profile.save().code,"INTERRUPTED")
	assert_eq(store.load_slot("slot-01").data.title,"小镇食堂")
	store.interrupt_at="after_backup"
	assert_eq(profile.save().code,"INTERRUPTED")
	assert_eq(store.load_slot("slot-01").code,"INTERRUPTED_SAVE")
	assert_true(store.recover_slot("slot-01",true).ok)
	assert_eq(store.load_slot("slot-01").data.title,"第二版")

func test_unknown_version_and_invalid_slot_never_overwrite() -> void:
	var profile:=create_profile("slot-01")
	assert_true(profile.save().ok)
	var file:=FileAccess.open(store.path_for("slot-01"),FileAccess.WRITE)
	file.store_string('{"schema_version":999}');file.close()
	assert_eq(profile.save().code,"UNSUPPORTED_VERSION")
	assert_eq(store.recover_slot("slot-01").code,"UNSUPPORTED_VERSION")
	assert_eq(store.load_slot("../settings").code,"INVALID_SLOT")
	assert_eq(FileAccess.get_file_as_string(store.path_for("slot-01")),'{"schema_version":999}')
	var other:=create_profile("slot-02");assert_true(other.save().ok)
	DirAccess.copy_absolute(store.path_for("slot-02"),store.path_for("slot-03")+".bak")
	assert_eq(store.recover_slot("slot-03").code,"SLOT_MISMATCH")
	assert_false(FileAccess.file_exists(store.path_for("slot-03")))

func test_world_rng_layout_dimensions_and_map_flags_round_trip() -> void:
	var a:=create_profile("slot-01")
	a.world.san=57
	a.world.town_map.plots[0].enabled=false
	a.world.rng.unit()
	assert_true(a.save().ok)
	var next:float=a.world.rng.unit()
	var b:=create_profile("slot-02")
	assert_true(b.restore(store.load_slot("slot-01").data).ok)
	assert_eq(b.world.san,57)
	assert_false(b.world.town_map.plots[0].enabled)
	assert_eq(b.world.rng.unit(),next)
	assert_eq(b.layout.to_dict(),a.layout.to_dict())

func test_invalid_domain_rejects_whole_load_and_closed_profile_rejects_old_callbacks() -> void:
	var profile:=create_profile("slot-01")
	var before:=profile.shop.snapshot()
	var broken:=profile.snapshot();broken.world.san=101
	assert_false(profile.restore(broken).ok)
	assert_eq(profile.shop.snapshot(),before)
	profile.close()
	assert_eq(profile._research_candidate(profile.research.snapshot()).code,"STALE_PROFILE")

func test_profile_can_save_three_day_boundaries_without_research_leaking() -> void:
	var profile:=create_profile("slot-01")
	for day: int in range(1,4):
		assert_true(profile.shop.open_day().ok)
		profile.shop.close_early()
		assert_true(profile.save().ok)
		var loaded:=store.load_slot("slot-01")
		assert_true(loaded.ok,loaded.code)
		assert_eq(int(loaded.data.shop.day),day)
		assert_eq(int(loaded.data.world.day),day)
		assert_true(profile.restore(loaded.data).ok)
		assert_true(profile.next_day().ok)

func test_world_spending_preserves_cents_and_failed_action_rolls_back() -> void:
	var profile:=create_profile("slot-01")
	profile.shop.world_adjustment(99,"fixture-cents","test")
	var before:int=profile.shop.snapshot().money_cents
	assert_true(profile.world_transaction(profile.world.visit_zone.bind("plaza"),"visit:plaza").ok)
	assert_eq(profile.shop.snapshot().money_cents,before-400)
	assert_eq(profile.shop.snapshot().money_cents%100,99)
	var world:=TDWorldSnapshot.capture(profile.world)
	var business:=profile.shop.snapshot()
	assert_false(profile.world_transaction(func()->TDOutcome:
		profile.world.san=1;profile.world.money=0
		return TDOutcome.new(false,"TEST_REJECTED"),"test-failure").ok)
	assert_eq(profile.shop.snapshot(),business)
	assert_eq(JSON.parse_string(JSON.stringify(TDWorldSnapshot.capture(profile.world))),JSON.parse_string(JSON.stringify(world)))
	assert_true(profile.save().ok)

func test_remote_supply_arrives_next_day_once_across_save_reload() -> void:
	var profile:=create_profile("slot-01")
	assert_eq(profile.order_remote("egg").code,"NO_REMOTE_ROUTE")
	assert_true(profile.recommend_route("paris","story:profile-test:paris").ok)
	var quote:=profile.commerce.quote(profile.commerce.state.routes[1],{"egg":1000})
	assert_true(profile.order_remote("egg").ok)
	assert_eq(profile.shop.available("egg"),0)
	assert_eq(profile.shop.snapshot().money_cents,30000-int(quote.data.total_cents))
	assert_eq(int(profile.commerce.state.shipments[0].arrival_day),int(quote.data.arrival_day))
	assert_true(profile.save().ok)
	assert_true(profile.restore(store.load_slot("slot-01").data).ok)
	while int(profile.shop.snapshot().day)<int(quote.data.arrival_day):
		profile.shop.open_day();profile.shop.close_early()
		assert_true(profile.next_day().ok)
	assert_eq(profile.shop.available("egg"),1000)
	var before:=profile.shop.snapshot()
	assert_true(profile.receive_supplies().ok)
	assert_eq(profile.shop.snapshot(),before)
	assert_true(profile.save().ok)
	assert_true(profile.restore(store.load_slot("slot-01").data).ok)
	assert_eq(profile.shop.available("egg"),1000)

func test_legacy_recipe_definition_and_unlock_survive_without_unlocking_new_slots() -> void:
	var profile:=create_profile("slot-01")
	assert_true(profile.research.inherit_legacy(["kaoya"]).ok)
	assert_true(profile.shop.is_unlocked("phase3.kaoya"))
	assert_true(profile.save().ok)
	var other:=create_profile("slot-02")
	assert_false(other.shop.is_unlocked("phase3.kaoya"))
	assert_true(other.restore(store.load_slot("slot-01").data).ok)
	assert_true(other.shop.is_unlocked("phase3.kaoya"))
	assert_eq(other.research.snapshot().legacy_ids,["kaoya"])

func test_malformed_nested_world_data_cannot_partially_restore() -> void:
	var profile:=create_profile("slot-01")
	var before:=profile.snapshot()
	for field: String in ["wage_paid","branch_stock","prices"]:
		var broken:=before.duplicate(true);broken.world[field]["corrupt"]={"unexpected":true}
		assert_eq(profile.restore(broken).code,"INVALID_WORLD_VALUE")
		assert_eq(profile.snapshot(),before)
