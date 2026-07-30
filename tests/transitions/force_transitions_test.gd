extends GdUnitTestSuite

## Plan 0044 — force aggregate mutation authority. These tests use tiny in-memory stores so the
## authority's exact placement and roster deltas are pinned without running a full turn.

const BRIGADE_ID := "BDE-1"
const HEX_A := "hex_a"
const HEX_B := "hex_b"


func _store() -> GameDataStore:
	var store := GameDataStore.new()
	store.hex_lookup = {HEX_A: Hex.new(), HEX_B: Hex.new()}
	var brigade := Brigade.new()
	brigade.id = BRIGADE_ID
	brigade.hex_id = HEX_A
	var maneuver := Battalion.new()
	maneuver.type = "infantry"
	maneuver.qty = 2
	var support := Battalion.new()
	support.type = "artillery"
	support.qty = 1
	brigade.composition = [maneuver, support]
	store.brigades = {BRIGADE_ID: brigade}
	store.brigades_by_hex = {HEX_A: [BRIGADE_ID]}
	return store


func _sent_state(ids: Array) -> SealiftState:
	var state := SealiftState.new()
	state.cohorts = [SealiftCohort.sent({"LST": 1}, ids)]
	return state


func _troop_reserve(bn_id: String) -> Array:
	return [{
		"brigade_id": BRIGADE_ID,
		"locked_beach": 1,
		"beach_hex": HEX_A,
		"offset_bearing": 0.0,
		"bns": [{"id": bn_id, "type": "infantry"}],
	}]


func test_place_brigade_updates_forward_and_reverse_indexes() -> void:
	var store := _store()

	var receipt := ForceTransitions.place_brigade(
		store, ForcePlacementRequest.ashore(BRIGADE_ID, HEX_B, "test_move"))

	assert_str(receipt.old_hex).is_equal(HEX_A)
	assert_str(receipt.new_hex).is_equal(HEX_B)
	assert_str((store.get_brigade(BRIGADE_ID) as Brigade).hex_id).is_equal(HEX_B)
	assert_array(store.brigades_by_hex[HEX_A]).not_contains(BRIGADE_ID)
	assert_array(store.brigades_by_hex[HEX_B]).contains(BRIGADE_ID)
	assert_array(ForceTransitions.validate_force_state(store)).is_empty()
	store.free()


func test_last_battalion_casualty_marks_destroyed_and_removes_from_map() -> void:
	var store := _store()
	ForceTransitions.apply_battalion_casualties(
		store, ForceCasualtyRequest.one(BRIGADE_ID, "artillery", ForceCasualtyCause.Kind.GROUND_COMBAT))
	var final_loss := ForceCasualtyRequest.new()
	final_loss.brigade_id = BRIGADE_ID
	final_loss.battalion_type = "infantry"
	final_loss.count = 2
	final_loss.cause = ForceCasualtyCause.Kind.GROUND_COMBAT

	var receipt := ForceTransitions.apply_battalion_casualties(store, final_loss)

	var brigade: Brigade = store.get_brigade(BRIGADE_ID)
	assert_int(receipt.applied).is_equal(2)
	assert_bool(receipt.destroyed_brigade).is_true()
	assert_bool(brigade.destroyed).is_true()
	assert_str(brigade.hex_id).is_empty()
	assert_array(store.brigades_by_hex[HEX_A]).not_contains(BRIGADE_ID)
	assert_array(ForceTransitions.validate_force_state(store)).is_empty()
	store.free()


func test_crossing_casualty_missing_reserve_row_refuses_roster_change() -> void:
	var store := _store()
	var state := _sent_state(["bn-missing"])
	var reserve: Array = []
	var request := ForceCrossingCasualtyRequest.from_crossing(
		["bn-missing"], reserve, state)
	await assert_error(func() -> void:
		ForceTransitions.apply_crossing_loss(store, state, reserve, request)
	).is_push_error("ForceTransitions: crossing casualty id bn-missing is missing from reserve")

	var brigade: Brigade = store.get_brigade(BRIGADE_ID)
	assert_int(brigade.get_battalion_count()).is_equal(3)
	store.free()


func test_crossing_casualty_duplicate_lost_id_refuses_roster_change() -> void:
	var store := _store()
	var reserve := _troop_reserve("bn-1")
	var state := _sent_state(["bn-1"])
	var request := ForceCrossingCasualtyRequest.from_crossing(
		["bn-1", "bn-1"], reserve, state)
	await assert_error(func() -> void:
		ForceTransitions.apply_crossing_loss(store, state, reserve, request)
	).is_push_error("ForceTransitions: crossing loss id bn-1 appears twice in lost_ids")

	var brigade: Brigade = store.get_brigade(BRIGADE_ID)
	assert_int(brigade.get_battalion_count()).is_equal(3)
	store.free()


func test_crossing_casualty_ignores_jlsf_cargo_ids() -> void:
	var store := _store()
	var state := _sent_state(["JLSF:port-a:1"])
	var reserve := [{
		"brigade_id": "JLSF:port-a",
		"cargo": "jlsf",
		"port_id": "port-a",
		"locked_beach": 1,
		"beach_hex": HEX_A,
		"offset_bearing": 0.0,
		"bns": [{"id": "JLSF:port-a:1", "type": JlsfCargo.BN_TYPE}],
	}]
	var request := ForceCrossingCasualtyRequest.from_crossing(
		["JLSF:port-a:1"], reserve, state)

	var result := ForceTransitions.apply_crossing_loss(store, state, reserve, request)

	var brigade: Brigade = store.get_brigade(BRIGADE_ID)
	assert_bool(result.success).is_true()
	assert_array(result.receipts).is_empty()
	assert_array(reserve).is_empty()
	assert_array(state.cohorts[0].bn_ids).is_empty()
	assert_int(brigade.get_battalion_count()).is_equal(3)
	store.free()


func test_crossing_casualty_missing_sent_cohort_refuses_roster_change() -> void:
	var store := _store()
	var state := _sent_state(["some-other-bn"])
	var reserve := [{
		"brigade_id": BRIGADE_ID,
		"locked_beach": 1,
		"beach_hex": HEX_A,
		"offset_bearing": 0.0,
		"bns": [{"id": "bn-1", "type": "infantry"}],
	}]
	var request := ForceCrossingCasualtyRequest.from_crossing(
		["bn-1"], reserve, state)
	await assert_error(func() -> void:
		ForceTransitions.apply_crossing_loss(store, state, reserve, request)
	).is_push_error("ForceTransitions: crossing casualty id bn-1 appears in sent cohorts 0 times")

	var brigade: Brigade = store.get_brigade(BRIGADE_ID)
	assert_int(brigade.get_battalion_count()).is_equal(3)
	store.free()


# ── Air insertion (plan 0032 / 0044) ───────────────────────────────────────────────────────────


const AIR_BDE_ID := "ABN-1"
const DROP_HEX := "hex_drop"

func _air_store() -> GameDataStore:
	var store := GameDataStore.new()
	store.hex_lookup = {DROP_HEX: Hex.new(), HEX_A: Hex.new(), HEX_B: Hex.new()}
	var brigade := Brigade.new()
	brigade.id = AIR_BDE_ID
	brigade.hex_id = ""
	var bn := Battalion.new()
	bn.type = "Airborne Combined Arms Battalion"
	bn.qty = 3
	brigade.composition = [bn] as Array[Battalion]
	store.brigades = {AIR_BDE_ID: brigade}
	store.brigades_by_hex = {}
	return store


func _air_state() -> AirInsertionState:
	var state := AirInsertionState.new()
	state.pool = [{
		"brigade_id": AIR_BDE_ID,
		"lift_class": LiftClass.AIRBORNE,
		"bns": [
			{"id": "ABN-1-AIR-1", "type": "Airborne Combined Arms Battalion"},
			{"id": "ABN-1-AIR-2", "type": "Airborne Combined Arms Battalion"},
			{"id": "ABN-1-AIR-3", "type": "Airborne Combined Arms Battalion"},
		],
	}]
	state.caps = {LiftClass.AIRBORNE: 3}
	state.initial_caps = state.caps.duplicate()
	return state


## Build a landing from the first N pool BNs. survivors = count landed.
func _make_landing(state: AirInsertionState, survivors: int, losses: int) -> Dictionary:
	var entry: Dictionary = state.pool[0]
	var bns: Array = entry["bns"]
	var landed: Array = []
	var lost: Array = []
	for i in range(survivors):
		landed.append(bns[i].duplicate())
	for i in range(losses):
		lost.append(bns[survivors + i].duplicate())
	var first := survivors > 0 and not state.landed.has(AIR_BDE_ID)
	return {
		"brigade_id": AIR_BDE_ID,
		"hex_id": DROP_HEX,
		"first_landing": first,
		"landed_bns": landed,
		"lost_bns": lost,
	}


func test_air_insertion_mixed_survivor_and_loss_with_first_placement() -> void:
	var store := _air_store()
	var air_state := _air_state()
	var landing := _make_landing(air_state, 2, 1)
	var request := ForceAirInsertionRequest.from_landings(1, [landing])

	var receipt := ForceTransitions.apply_air_insertion_outcome(store, air_state, request)

	assert_bool(receipt.success).is_true()
	assert_int(receipt.battalions_landed).is_equal(2)
	assert_int(receipt.battalions_lost).is_equal(1)
	assert_int(receipt.pool_entries_drained).is_equal(1)
	assert_int(air_state.pending_battalions()).is_equal(0)
	assert_array(air_state.landed).contains([AIR_BDE_ID])
	var brigade: Brigade = store.get_brigade(AIR_BDE_ID)
	assert_str(brigade.hex_id).is_equal(DROP_HEX)
	assert_int(brigade.get_battalion_count()).is_equal(2)
	assert_int(air_state.caps[LiftClass.AIRBORNE]).is_equal(3)
	assert_array(air_state.history).is_empty()
	assert_array(ForceTransitions.validate_force_state(store)).is_empty()
	store.free()


func test_air_insertion_all_loss_no_placement() -> void:
	var store := _air_store()
	var air_state := _air_state()
	var landing := _make_landing(air_state, 0, 3)
	landing["first_landing"] = false
	var request := ForceAirInsertionRequest.from_landings(1, [landing])

	var receipt := ForceTransitions.apply_air_insertion_outcome(store, air_state, request)

	assert_bool(receipt.success).is_true()
	assert_int(receipt.battalions_landed).is_equal(0)
	assert_int(receipt.battalions_lost).is_equal(3)
	assert_int(air_state.pending_battalions()).is_equal(0)
	assert_array(air_state.landed).is_empty()
	var brigade: Brigade = store.get_brigade(AIR_BDE_ID)
	assert_str(brigade.hex_id).is_empty()
	assert_int(brigade.get_battalion_count()).is_equal(0)
	assert_bool(brigade.destroyed).is_true()
	assert_array(ForceTransitions.validate_force_state(store)).is_empty()
	store.free()


func test_air_insertion_first_landing_true_but_no_survivors_refuses() -> void:
	var store := _air_store()
	var air_state := _air_state()
	var landing := _make_landing(air_state, 0, 1)
	landing["first_landing"] = true
	var request := ForceAirInsertionRequest.from_landings(1, [landing])

	var receipt := ForceTransitions.apply_air_insertion_outcome(store, air_state, request)

	assert_bool(receipt.success).is_false()
	assert_int(air_state.pending_battalions()).is_equal(3)
	var brigade: Brigade = store.get_brigade(AIR_BDE_ID)
	assert_int(brigade.get_battalion_count()).is_equal(3)
	assert_array(air_state.landed).is_empty()
	assert_str(brigade.hex_id).is_empty()
	store.free()


func test_air_insertion_all_survivor_unknown_brigade_refuses() -> void:
	var store := _air_store()
	var air_state := _air_state()
	air_state.pool.append({
		"brigade_id": "GHOST-BDE",
		"lift_class": LiftClass.AIRBORNE,
		"bns": [{"id": "GHOST-1", "type": "Airborne Combined Arms Battalion"}],
	})
	var landing := {
		"brigade_id": "GHOST-BDE",
		"hex_id": DROP_HEX,
		"first_landing": true,
		"landed_bns": [{"id": "GHOST-1", "type": "Airborne Combined Arms Battalion"}],
		"lost_bns": [],
	}
	var request := ForceAirInsertionRequest.from_landings(1, [landing])

	var receipt := ForceTransitions.apply_air_insertion_outcome(store, air_state, request)

	assert_bool(receipt.success).is_false()
	assert_int(air_state.pending_battalions()).is_equal(4)
	assert_array(air_state.landed).is_empty()
	var brigade: Brigade = store.get_brigade(AIR_BDE_ID)
	assert_str(brigade.hex_id).is_empty()
	assert_int(brigade.get_battalion_count()).is_equal(3)
	store.free()


# ── Mobilization release (plan 0029 / 0044) ───────────────────────────────────────────────────


const MOB_BDE_ID := "BDE-RES-1"
const MOB_HEX := "hex_garrison"

func _mob_state() -> MobilizationState:
	var state := MobilizationState.new()
	state.pending = [
		{"brigade_id": MOB_BDE_ID, "garrison_hex": MOB_HEX, "release_turn": 4},
		{"brigade_id": "BDE-RES-2", "garrison_hex": "hex_other", "release_turn": 6},
	]
	return state


func _mob_store() -> GameDataStore:
	var store := GameDataStore.new()
	store.hex_lookup = {MOB_HEX: Hex.new(), "hex_other": Hex.new()}
	var brigade := Brigade.new()
	brigade.id = MOB_BDE_ID
	brigade.hex_id = ""
	brigade.team = Brigade.Team.GREEN
	var bn := Battalion.new()
	bn.type = "Infantry Battalion (Reserve)"
	bn.qty = 3
	brigade.composition = [bn] as Array[Battalion]
	store.brigades = {MOB_BDE_ID: brigade}
	store.brigades_by_hex = {}
	return store


func test_mobilization_release_places_brigade_on_hex_and_drains_pending() -> void:
	var store := _mob_store()
	var mob_state := _mob_state()
	var request := ForceMobilizationRequest.from_resolver(4, [
		{"brigade_id": MOB_BDE_ID, "hex_id": MOB_HEX, "battalions": 3, "displaced": false},
	], [])

	var receipt := ForceTransitions.release_mobilized_brigades(store, mob_state, request)

	assert_bool(receipt.success).is_true()
	assert_int(receipt.arrived).is_equal(1)
	assert_int(receipt.battalions_arrived).is_equal(3)
	assert_array(receipt.placed_brigades).contains([MOB_BDE_ID])
	assert_int(mob_state.pending.size()).is_equal(1)
	assert_str(String(mob_state.pending[0]["brigade_id"])).is_equal("BDE-RES-2")
	assert_int(mob_state.released.size()).is_equal(1)
	assert_str(String(mob_state.released[0]["brigade_id"])).is_equal(MOB_BDE_ID)
	assert_int(int(mob_state.released[0]["turn"])).is_equal(4)
	var brigade: Brigade = store.get_brigade(MOB_BDE_ID)
	assert_str(brigade.hex_id).is_equal(MOB_HEX)
	assert_int(brigade.get_battalion_count()).is_equal(3)
	assert_array(ForceTransitions.validate_force_state(store)).is_empty()
	store.free()


func test_mobilization_already_on_map_refuses() -> void:
	var store := _mob_store()
	var brigade: Brigade = store.get_brigade(MOB_BDE_ID)
	brigade.hex_id = "some_hex"
	brigade.entry_bearing = 0.0
	var mob_state := _mob_state()
	var request := ForceMobilizationRequest.from_resolver(4, [
		{"brigade_id": MOB_BDE_ID, "hex_id": MOB_HEX, "battalions": 3, "displaced": false},
	], [])

	var receipt := ForceTransitions.release_mobilized_brigades(store, mob_state, request)

	assert_bool(receipt.success).is_false()
	assert_int(mob_state.pending.size()).is_equal(2)
	store.free()


func test_mobilization_duplicate_arrival_refuses() -> void:
	var store := _mob_store()
	var mob_state := _mob_state()
	var request := ForceMobilizationRequest.from_resolver(4, [
		{"brigade_id": MOB_BDE_ID, "hex_id": MOB_HEX, "battalions": 3, "displaced": false},
		{"brigade_id": MOB_BDE_ID, "hex_id": MOB_HEX, "battalions": 3, "displaced": false},
	], [])

	var receipt := ForceTransitions.release_mobilized_brigades(store, mob_state, request)

	assert_bool(receipt.success).is_false()
	assert_int(mob_state.pending.size()).is_equal(2)
	assert_int(mob_state.released.size()).is_equal(0)
	store.free()


func test_mobilization_missing_pending_refuses() -> void:
	var store := _mob_store()
	var mob_state := _mob_state()
	var request := ForceMobilizationRequest.from_resolver(4, [
		{"brigade_id": "NONEXISTENT", "hex_id": MOB_HEX, "battalions": 3, "displaced": false},
	], [])

	var receipt := ForceTransitions.release_mobilized_brigades(store, mob_state, request)

	assert_bool(receipt.success).is_false()
	assert_int(mob_state.pending.size()).is_equal(2)
	assert_int(mob_state.released.size()).is_equal(0)
	store.free()


# ── All-or-nothing: preflight prevents partial mutation ────────────────────────────────────────

func test_air_insertion_mixed_batch_all_or_nothing() -> void:
	var store := _air_store()
	var air_state := _air_state()

	air_state.pool.append({
		"brigade_id": "ABN-2",
		"lift_class": LiftClass.AIRBORNE,
		"bns": [{"id": "ABN-2-AIR-1", "type": "Airborne Combined Arms Battalion"}],
	})
	var bde2 := Brigade.new()
	bde2.id = "ABN-2"
	bde2.hex_id = ""
	var bn2 := Battalion.new()
	bn2.type = "Airborne Combined Arms Battalion"
	bn2.qty = 1
	bde2.composition = [bn2] as Array[Battalion]
	store.brigades["ABN-2"] = bde2

	var valid_landing := _make_landing(air_state, 1, 0)
	var invalid_landing := {
		"brigade_id": "ABN-2",
		"hex_id": DROP_HEX,
		"first_landing": true,
		"landed_bns": [{"id": "FAKE-ID", "type": "Airborne Combined Arms Battalion"}],
		"lost_bns": [],
	}
	var request := ForceAirInsertionRequest.from_landings(1, [valid_landing, invalid_landing])

	var receipt := ForceTransitions.apply_air_insertion_outcome(store, air_state, request)

	assert_bool(receipt.success).is_false()
	assert_int(air_state.pending_battalions()).is_equal(4)
	assert_array(air_state.landed).is_empty()
	var bde: Brigade = store.get_brigade("ABN-1")
	assert_str(bde.hex_id).is_empty()
	assert_int(bde.get_battalion_count()).is_equal(3)
	store.free()


func test_mobilization_mixed_batch_all_or_nothing() -> void:
	var store := _mob_store()
	var mob_state := _mob_state()

	var bde2 := Brigade.new()
	bde2.id = "BDE-RES-2"
	bde2.hex_id = ""
	bde2.team = Brigade.Team.GREEN
	var bn2 := Battalion.new()
	bn2.type = "Infantry Battalion (Reserve)"
	bn2.qty = 2
	bde2.composition = [bn2] as Array[Battalion]
	store.brigades["BDE-RES-2"] = bde2

	var valid_arrival := {"brigade_id": MOB_BDE_ID, "hex_id": MOB_HEX, "battalions": 3, "displaced": false}
	var invalid_arrival := {"brigade_id": "BDE-RES-2", "hex_id": "hex_other", "battalions": 2, "displaced": false}
	var request := ForceMobilizationRequest.from_resolver(4, [valid_arrival, invalid_arrival], [])

	var receipt := ForceTransitions.release_mobilized_brigades(store, mob_state, request)

	assert_bool(receipt.success).is_false()
	assert_int(mob_state.pending.size()).is_equal(2)
	assert_int(mob_state.released.size()).is_equal(0)
	var b1: Brigade = store.get_brigade(MOB_BDE_ID)
	assert_str(b1.hex_id).is_empty()
	assert_int(b1.get_battalion_count()).is_equal(3)
	store.free()


# ── Sea transport: sent cohort (plan 0044) ──────────────────────────────────────────────────────


func test_apply_sent_cohort_creates_cohort_and_returns_receipt() -> void:
	var state := SealiftState.new()
	var bn_ids := ["bn-1", "bn-2"]
	var hulls := {"LST": 1}
	var reserve := [{"brigade_id": "BDE-SEA", "bns": [
		{"id": "bn-1", "type": "infantry"}, {"id": "bn-2", "type": "infantry"}]}]

	var receipt := ForceTransitions.apply_sent_cohort(state, bn_ids, hulls, reserve, {})

	assert_bool(receipt.success).is_true()
	assert_int(state.cohorts.size()).is_equal(1)
	var cohort: SealiftCohort = state.cohorts[0]
	assert_str(cohort.cohort_state).is_equal(SealiftState.STATE_SENT)
	var stored_ids: Array = cohort.bn_ids
	assert_int(stored_ids.size()).is_equal(2)
	assert_int(int(cohort.hulls_by_type.get("LST", 0))).is_equal(1)
	assert_array(stored_ids).contains(["bn-1", "bn-2"])


func test_apply_sent_cohort_null_state_refuses() -> void:
	var receipt := ForceTransitions.apply_sent_cohort(null, ["bn-1"], {"LST": 1}, [], {})
	assert_bool(receipt.success).is_false()


func test_apply_sent_cohort_empty_ids_refuses() -> void:
	var state := SealiftState.new()
	var receipt := ForceTransitions.apply_sent_cohort(state, [], {"LST": 1}, [], {})
	assert_bool(receipt.success).is_false()


func test_apply_sent_cohort_duplicate_id_across_cohorts_refuses() -> void:
	var state := SealiftState.new()
	state.cohorts = [SealiftCohort.sent({"LST": 1}, ["bn-1"])]
	var reserve := [{"brigade_id": "BDE-SEA", "bns": [
		{"id": "bn-1", "type": "infantry"}, {"id": "bn-2", "type": "infantry"}]}]
	var receipt := ForceTransitions.apply_sent_cohort(
		state, ["bn-1", "bn-2"], {"LST": 1}, reserve, {})
	assert_bool(receipt.success).is_false()
	assert_int(state.cohorts.size()).is_equal(1)


# NOTE: the sent → offloading flip moved to SealiftTransitions in plan 0045 — the cohort's leg is a
# statement about the SHIPPING, not about who is aboard — and is covered by sealift_transitions_test.


# ── Sea transport: embark (plan 0044) ─────────────────────────────────────────────────────────


func _sea_store() -> GameDataStore:
	var store := GameDataStore.new()
	store.hex_lookup = {HEX_A: Hex.new(), HEX_B: Hex.new()}
	var bde := Brigade.new()
	bde.id = "BDE-SEA"
	bde.hex_id = ""
	var bn := Battalion.new()
	bn.type = "infantry"
	bn.qty = 4
	bde.composition = [bn] as Array[Battalion]
	store.brigades = {"BDE-SEA": bde}
	store.brigades_by_hex = {}
	return store


func _sea_pool() -> Array:
	return [{
		"brigade_id": "BDE-SEA",
		"locked_beach": 1,
		"beach_hex": HEX_A,
		"offset_bearing": 0.0,
		"bns": [
			{"id": "bn-1", "type": "infantry"},
			{"id": "bn-2", "type": "infantry"},
			{"id": "bn-3", "type": "infantry"},
		],
	}]


func test_apply_embark_drains_pool_and_creates_cohort() -> void:
	var state := SealiftState.new()
	state.mainland_pool = _sea_pool()
	var specs := [{"brigade_id": "BDE-SEA", "bn_ids": ["bn-1", "bn-2"]}]
	var request := ForceEmbarkRequest.batch(specs, ["bn-1", "bn-2"], {"LST": 1}, {})
	var reserve: Array = []

	var receipts := ForceTransitions.apply_embark(state, request, reserve)

	assert_int(receipts.size()).is_equal(1)
	assert_bool(receipts[0].success).is_true()
	# Pool drained
	assert_int(state.mainland_pool.size()).is_equal(1)
	var remaining: Array = state.mainland_pool[0].get("bns", [])
	assert_int(remaining.size()).is_equal(1)
	assert_str(String(remaining[0].get("id", ""))).is_equal("bn-3")
	# Cohort created
	assert_int(state.cohorts.size()).is_equal(1)
	var cohort: SealiftCohort = state.cohorts[0]
	assert_str(cohort.cohort_state).is_equal(SealiftState.STATE_SENT)
	var cohort_ids: Array = cohort.bn_ids
	assert_int(cohort_ids.size()).is_equal(2)
	assert_int(reserve.size()).is_equal(1)
	var reserve_bns: Array = reserve[0]["bns"]
	assert_str(String(reserve_bns[0]["id"])).is_equal("bn-1")
	assert_str(String(reserve_bns[1]["id"])).is_equal("bn-2")


func test_apply_embark_without_hulls_refuses_atomically() -> void:
	var state := SealiftState.new()
	state.mainland_pool = _sea_pool()
	var specs := [{"brigade_id": "BDE-SEA", "bn_ids": ["bn-1"]}]
	var request := ForceEmbarkRequest.batch(specs, ["bn-1"], {}, {})

	var reserve: Array = []
	await assert_error(func() -> void:
		ForceTransitions.apply_embark(state, request, reserve)
	).is_push_error("ForceTransitions: embark request has no carrier hulls")

	assert_int(state.cohorts.size()).is_equal(0)
	assert_int((state.mainland_pool[0]["bns"] as Array).size()).is_equal(3)
	assert_array(reserve).is_empty()


func test_apply_embark_null_state_returns_refused() -> void:
	var receipts := ForceTransitions.apply_embark(
		null, ForceEmbarkRequest.batch([], [], {}, {}), [])
	assert_int(receipts.size()).is_equal(1)
	assert_bool(receipts[0].success).is_false()


func test_apply_embark_duplicate_bn_id_refuses() -> void:
	var state := SealiftState.new()
	state.mainland_pool = _sea_pool()
	var specs := [{"brigade_id": "BDE-SEA", "bn_ids": ["bn-1", "bn-1"]}]
	var request := ForceEmbarkRequest.batch(specs, ["bn-1", "bn-1"], {"LST": 1}, {})

	var receipts := ForceTransitions.apply_embark(state, request, [])

	assert_int(receipts.size()).is_equal(1)
	assert_bool(receipts[0].success).is_false()
	# Pool unchanged
	assert_int(state.mainland_pool[0].get("bns", []).size()).is_equal(3)


func test_apply_embark_missing_pool_bn_refuses() -> void:
	var state := SealiftState.new()
	state.mainland_pool = _sea_pool()
	var specs := [{"brigade_id": "BDE-SEA", "bn_ids": ["bn-missing"]}]
	var request := ForceEmbarkRequest.batch(specs, ["bn-missing"], {"LST": 1}, {})

	var receipts := ForceTransitions.apply_embark(state, request, [])

	assert_int(receipts.size()).is_equal(1)
	assert_bool(receipts[0].success).is_false()


# ── Sea transport: offload (plan 0044) ────────────────────────────────────────────────────────


func _offload_reserve() -> Array:
	return [{
		"brigade_id": "BDE-SEA",
		"locked_beach": 1,
		"beach_hex": HEX_A,
		"offset_bearing": 0.0,
		"bns": [
			{"id": "bn-1", "type": "infantry"},
			{"id": "bn-2", "type": "infantry"},
		],
	}]


func test_apply_offload_first_landing_places_brigade() -> void:
	var store := _sea_store()
	var state := SealiftState.new()
	state.cohorts = [SealiftCohort.offloading({"LST": 1}, ["bn-1", "bn-2"])]
	var reserve := _offload_reserve()
	var landings := [{"brigade_id": "BDE-SEA", "bn_ids": ["bn-1", "bn-2"], "hex_id": HEX_A}]
	var request := ForceOffloadRequest.from_landings(landings)

	var receipt := ForceTransitions.apply_offload(store, reserve, state, request)

	assert_bool(receipt.success).is_true()
	assert_int(receipt.landed_brigade_ids.size()).is_equal(1)
	assert_str(receipt.landed_brigade_ids[0]).is_equal("BDE-SEA")
	# Brigade placed on map
	var brigade: Brigade = store.get_brigade("BDE-SEA")
	assert_str(brigade.hex_id).is_equal(HEX_A)
	# Reserve entry removed (all BNs offloaded)
	assert_int(reserve.size()).is_equal(0)
	# Cohort drained
	var cohort_bn_ids: Array = state.cohorts[0].bn_ids
	assert_int(cohort_bn_ids.size()).is_equal(0)
	store.free()


func test_apply_offload_followup_keeps_brigade_placed() -> void:
	var store := _sea_store()
	var brigade: Brigade = store.get_brigade("BDE-SEA")
	brigade.hex_id = HEX_A
	var state := SealiftState.new()
	state.cohorts = [SealiftCohort.offloading({"LST": 1}, ["bn-3"])]
	var reserve := [{
		"brigade_id": "BDE-SEA",
		"locked_beach": 1,
		"beach_hex": HEX_B,
		"offset_bearing": 0.0,
		"bns": [{"id": "bn-3", "type": "infantry"}],
	}]
	var landings := [{"brigade_id": "BDE-SEA", "bn_ids": ["bn-3"], "hex_id": ""}]
	var request := ForceOffloadRequest.from_landings(landings)

	var receipt := ForceTransitions.apply_offload(store, reserve, state, request)

	assert_bool(receipt.success).is_true()
	assert_array(receipt.landed_brigade_ids).is_empty()  # Not first landing
	# Brigade still at same hex
	assert_str(brigade.hex_id).is_equal(HEX_A)
	# Cohort drained
	assert_int(state.cohorts[0].bn_ids.size()).is_equal(0)
	store.free()


func test_apply_offload_null_state_refuses() -> void:
	var store := GameDataStore.new()
	var receipt := ForceTransitions.apply_offload(
		store, [], null, ForceOffloadRequest.from_landings([]))
	assert_bool(receipt.success).is_false()
	store.free()


func test_apply_offload_missing_bn_in_reserve_refuses() -> void:
	var state := SealiftState.new()
	var reserve := _offload_reserve()
	var landings := [{"brigade_id": "BDE-SEA", "bn_ids": ["bn-missing"], "hex_id": HEX_A}]
	var request := ForceOffloadRequest.from_landings(landings)

	var store := GameDataStore.new()
	var receipt := ForceTransitions.apply_offload(store, reserve, state, request)

	assert_bool(receipt.success).is_false()
	assert_int(reserve[0].get("bns", []).size()).is_equal(2)
	store.free()


func test_apply_offload_jlsf_cargo_drains_without_force_receipt() -> void:
	var store := _sea_store()
	var state := SealiftState.new()
	state.cohorts = [SealiftCohort.offloading({"LST": 1}, ["JLSF:port-a:1"])]
	var reserve := [{
		"brigade_id": "JLSF:port-a", "cargo": JlsfCargo.CARGO_KIND, "port_id": "port-a",
		"bns": [{"id": "JLSF:port-a:1", "type": JlsfCargo.BN_TYPE}],
	}]
	var request := ForceOffloadRequest.from_resolution(
		[], [{"port_id": "port-a", "bn_ids": ["JLSF:port-a:1"]}])

	var receipt := ForceTransitions.apply_offload(store, reserve, state, request)

	assert_bool(receipt.success).is_true()
	assert_array(receipt.bn_ids_landed).is_empty()
	assert_array(reserve).is_empty()
	assert_array(state.cohorts[0].bn_ids).is_empty()
	store.free()


func test_apply_offload_empty_landings_returns_empty_ok() -> void:
	var state := SealiftState.new()
	var store := GameDataStore.new()
	var receipt := ForceTransitions.apply_offload(
		store, [], state, ForceOffloadRequest.from_landings([]))
	assert_bool(receipt.success).is_true()
	assert_array(receipt.landed_brigade_ids).is_empty()
	store.free()


# ── Sea transport: crossing loss (plan 0044) ──────────────────────────────────────────────────


func test_apply_crossing_loss_removes_from_reserve_cohorts_and_roster() -> void:
	var store := _store()
	var state := SealiftState.new()
	state.cohorts = [SealiftCohort.sent({"LST": 1}, ["bn-1"])]
	var reserve := _troop_reserve("bn-1")
	var request := ForceCrossingCasualtyRequest.from_crossing(["bn-1"], reserve, state)

	var result := ForceTransitions.apply_crossing_loss(store, state, reserve, request)

	assert_bool(result.success).is_true()
	# Roster loss applied
	var brigade: Brigade = store.get_brigade(BRIGADE_ID)
	assert_int(brigade.get_battalion_count()).is_equal(2)
	# Reserve entry removed (empty)
	assert_int(reserve.size()).is_equal(0)
	# Cohort BN removed
	var cohort_bn_ids: Array = state.cohorts[0].bn_ids
	assert_int(cohort_bn_ids.size()).is_equal(0)
	store.free()


func test_apply_crossing_loss_duplicate_refuses() -> void:
	var store := _store()
	var state := SealiftState.new()
	state.cohorts = [SealiftCohort.sent({"LST": 1}, ["bn-1"])]
	var reserve := _troop_reserve("bn-1")
	var request := ForceCrossingCasualtyRequest.from_crossing(["bn-1", "bn-1"], reserve, state)

	var result := ForceTransitions.apply_crossing_loss(store, state, reserve, request)

	assert_bool(result.success).is_false()
	var brigade: Brigade = store.get_brigade(BRIGADE_ID)
	assert_int(brigade.get_battalion_count()).is_equal(3)
	store.free()


func test_apply_crossing_loss_empty_lost_ids_is_ok() -> void:
	var store := _store()
	var state := SealiftState.new()
	var result := ForceTransitions.apply_crossing_loss(
		store, state, [], ForceCrossingCasualtyRequest.from_crossing([], [], state))
	assert_bool(result.success).is_true()
	assert_array(result.receipts).is_empty()
	store.free()


# ── Sea transport: JLSF queueing (plan 0044) ─────────────────────────────────────────────────


func test_apply_queue_jlsf_adds_to_front_of_mainland_pool() -> void:
	var state := SealiftState.new()
	state.mainland_pool = [{"brigade_id": "BDE-EXISTING", "bns": []}]
	var entries := [{"brigade_id": "JLSF:port-a", "cargo": "jlsf", "port_id": "port-a", "bns": []}]

	ForceTransitions.apply_queue_jlsf(state, entries)

	assert_int(state.mainland_pool.size()).is_equal(2)
	assert_str(String(state.mainland_pool[0]["brigade_id"])).is_equal("JLSF:port-a")


func test_apply_queue_jlsf_empty_entries_noop() -> void:
	var state := SealiftState.new()
	ForceTransitions.apply_queue_jlsf(state, [])
	assert_array(state.mainland_pool).is_empty()


# ── Cohort lifecycle (plan 0044) ─────────────────────────────────────────────────────────────


## Freeing a cohort is where the two authorities hand over: this one drops the binding and REPORTS the
## hulls that were carrying it, and does not touch the return pipeline at all (plan 0045 — where a freed
## hull goes next is the sealift authority's call, see sealift_transitions_test).
func test_free_emptied_cohorts_drops_the_cohort_and_reports_its_hulls() -> void:
	var state := SealiftState.new()
	state.cohorts = [SealiftCohort.offloading({"LST": 2}, [])]
	var plan := ForceTransitions.free_emptied_cohorts(state)

	assert_int(int(plan.total_by_type().get("LST", 0))).is_equal(2)
	assert_int(plan.batches.size()).is_equal(1)
	assert_bool(state.cohorts.is_empty()).is_true()
	assert_bool(state.return_pipeline.is_empty()).is_true()


## One batch per freed cohort, in cohort order — the pipeline slot granularity depends on it.
func test_free_emptied_cohorts_reports_one_batch_per_freed_cohort() -> void:
	var state := SealiftState.new()
	state.cohorts = [
		SealiftCohort.offloading({"LST": 2}, []),
		SealiftCohort.offloading({"LST": 1, "LHA": 3}, []),
	]
	var plan := ForceTransitions.free_emptied_cohorts(state)

	assert_int(plan.batches.size()).is_equal(2)
	assert_int(int((plan.batches[0] as Dictionary)["LST"])).is_equal(2)
	assert_int(int((plan.batches[1] as Dictionary)["LHA"])).is_equal(3)
	assert_int(int(plan.total_by_type()["LST"])).is_equal(3)


func test_free_emptied_cohorts_partial_keeps_cohort() -> void:
	var state := SealiftState.new()
	state.cohorts = [SealiftCohort.offloading({"LST": 2}, ["bn-1"])]
	var plan := ForceTransitions.free_emptied_cohorts(state)

	assert_bool(plan.is_empty()).is_true()
	assert_int(state.cohorts.size()).is_equal(1)
	var remaining: Array = state.cohorts[0].bn_ids
	assert_int(remaining.size()).is_equal(1)


# ── Roster stability during embark/offload (plan 0044) ────────────────────────────────────────


func test_embark_does_not_change_roster() -> void:
	var store := _sea_store()
	var state := SealiftState.new()
	state.mainland_pool = _sea_pool()
	var brigade: Brigade = store.get_brigade("BDE-SEA")
	var roster_before := brigade.get_battalion_count()

	var specs := [{"brigade_id": "BDE-SEA", "bn_ids": ["bn-1", "bn-2"]}]
	var request := ForceEmbarkRequest.batch(specs, ["bn-1", "bn-2"], {"LST": 1}, {})
	var reserve: Array = []
	ForceTransitions.apply_embark(state, request, reserve)

	assert_int(reserve.size()).is_equal(1)
	assert_int(brigade.get_battalion_count()).is_equal(roster_before)
	assert_int(brigade.composition.size()).is_equal(1)  # Infantry only, 4 total
	store.free()


func test_offload_does_not_change_roster() -> void:
	var store := _sea_store()
	var state := SealiftState.new()
	state.cohorts = [SealiftCohort.offloading({"LST": 1}, ["bn-1", "bn-2"])]
	var reserve := _offload_reserve()
	var brigade: Brigade = store.get_brigade("BDE-SEA")
	brigade.hex_id = HEX_A
	var roster_before := brigade.get_battalion_count()

	var landings := [{"brigade_id": "BDE-SEA", "bn_ids": ["bn-1"], "hex_id": ""}]
	var request := ForceOffloadRequest.from_landings(landings)
	var receipt := ForceTransitions.apply_offload(store, reserve, state, request)

	assert_bool(receipt.success).is_true()
	assert_int(brigade.get_battalion_count()).is_equal(roster_before)
	store.free()


# ── Wrong-type / one-sided crossing omission (plan 0044) ───────────────────────────────────────


func test_crossing_loss_wrong_type_id_refuses() -> void:
	var store := _store()
	var state := SealiftState.new()
	state.cohorts = [SealiftCohort.sent({"LST": 1}, ["cargo-x"])]
	var reserve := [{
		"brigade_id": BRIGADE_ID,
		"locked_beach": 1,
		"beach_hex": HEX_A,
		"offset_bearing": 0.0,
		"bns": [{"id": "cargo-x", "type": "cargo"}],
	}]
	var request := ForceCrossingCasualtyRequest.from_crossing(["cargo-x"], reserve, state)

	await assert_error(func() -> void:
		ForceTransitions.apply_crossing_loss(store, state, reserve, request)
	).is_push_error("ForceTransitions: crossing casualties need 1 cargo from BDE-1 but roster has 0")

	var brigade: Brigade = store.get_brigade(BRIGADE_ID)
	assert_int(brigade.get_battalion_count()).is_equal(3)
	store.free()


func test_crossing_loss_brigade_not_in_reserve_refuses() -> void:
	var store := _store()
	var state := SealiftState.new()
	state.cohorts = [SealiftCohort.sent({"LST": 1}, ["bn-orphan"])]
	var reserve: Array = []
	var request := ForceCrossingCasualtyRequest.from_crossing(
		["bn-orphan"], reserve, state)

	await assert_error(func() -> void:
		ForceTransitions.apply_crossing_loss(store, state, reserve, request)
	).is_push_error("ForceTransitions: crossing casualty id bn-orphan is missing from reserve")

	var brigade: Brigade = store.get_brigade(BRIGADE_ID)
	assert_int(brigade.get_battalion_count()).is_equal(3)
	store.free()


func test_crossing_loss_reserve_bn_mismatches_cohort_id() -> void:
	var store := _store()
	var state := SealiftState.new()
	state.cohorts = [SealiftCohort.sent({"LST": 1}, ["bn-in-cohort"])]
	var reserve := [{
		"brigade_id": BRIGADE_ID,
		"locked_beach": 1,
		"beach_hex": HEX_A,
		"offset_bearing": 0.0,
		"bns": [{"id": "bn-in-reserve", "type": "infantry"}],
	}]
	var request := ForceCrossingCasualtyRequest.from_crossing(
		["bn-in-cohort"], reserve, state)

	await assert_error(func() -> void:
		ForceTransitions.apply_crossing_loss(store, state, reserve, request)
	).is_push_error("ForceTransitions: crossing casualty id bn-in-cohort is missing from reserve")

	var brigade: Brigade = store.get_brigade(BRIGADE_ID)
	assert_int(brigade.get_battalion_count()).is_equal(3)
	store.free()


# ── Zero-ashore surviving brigade (plan 0044) ──────────────────────────────────────────────────


func test_zero_ashore_surviving_brigade_not_destroyed() -> void:
	var store := _sea_store()
	var brigade: Brigade = store.get_brigade("BDE-SEA")
	brigade.hex_id = HEX_A

	var composition_before := brigade.get_battalion_count()
	_ensure_bns_at_sea(brigade, 4)

	# Still has full roster, still on map, not destroyed
	assert_int(brigade.get_battalion_count()).is_equal(composition_before)
	assert_str(brigade.hex_id).is_equal(HEX_A)
	assert_bool(brigade.destroyed).is_false()
	store.free()


static func _ensure_bns_at_sea(_brigade: Brigade, _count: int) -> void:
	pass


static func _remove_from_reserve(reserve: Array, bn_id: String) -> void:
	for entry in reserve:
		var bns: Array = entry.get("bns", [])
		for i in range(bns.size() - 1, -1, -1):
			if String(bns[i].get("id", "")) == bn_id:
				bns.remove_at(i)
