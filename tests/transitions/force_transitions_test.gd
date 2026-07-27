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
	state.cohorts = [{
		"hulls_by_type": {"LST": 1},
		"bn_ids": ids,
		"state": SealiftState.STATE_SENT,
	}]
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
	var request := ForceCrossingCasualtyRequest.from_crossing(
		["bn-missing"], [], _sent_state(["bn-missing"]))
	await assert_error(func() -> void:
		ForceTransitions.apply_crossing_casualties(store, request)
	).is_push_error("ForceTransitions: crossing casualty id bn-missing is missing from reserve")

	var brigade: Brigade = store.get_brigade(BRIGADE_ID)
	assert_int(brigade.get_battalion_count()).is_equal(3)
	store.free()


func test_crossing_casualty_duplicate_lost_id_refuses_roster_change() -> void:
	var store := _store()
	var reserve := _troop_reserve("bn-1")
	var request := ForceCrossingCasualtyRequest.from_crossing(
		["bn-1", "bn-1"], reserve, _sent_state(["bn-1"]))
	await assert_error(func() -> void:
		ForceTransitions.apply_crossing_casualties(store, request)
	).is_push_error("ForceTransitions: crossing casualty id bn-1 appears twice in lost_ids")

	var brigade: Brigade = store.get_brigade(BRIGADE_ID)
	assert_int(brigade.get_battalion_count()).is_equal(3)
	store.free()


func test_crossing_casualty_ignores_jlsf_cargo_ids() -> void:
	var store := _store()
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
		["JLSF:port-a:1"], reserve, _sent_state(["JLSF:port-a:1"]))

	var result := ForceTransitions.apply_crossing_casualties(store, request)

	var brigade: Brigade = store.get_brigade(BRIGADE_ID)
	assert_bool(result.success).is_true()
	assert_array(result.receipts).is_empty()
	assert_int(brigade.get_battalion_count()).is_equal(3)
	store.free()


func test_crossing_casualty_missing_sent_cohort_refuses_roster_change() -> void:
	var store := _store()
	var reserve := [{
		"brigade_id": BRIGADE_ID,
		"locked_beach": 1,
		"beach_hex": HEX_A,
		"offset_bearing": 0.0,
		"bns": [{"id": "bn-1", "type": "infantry"}],
	}]
	var request := ForceCrossingCasualtyRequest.from_crossing(
		["bn-1"], reserve, _sent_state(["some-other-bn"]))
	await assert_error(func() -> void:
		ForceTransitions.apply_crossing_casualties(store, request)
	).is_push_error("ForceTransitions: crossing casualty id bn-1 appears in sent cohorts 0 times")

	var brigade: Brigade = store.get_brigade(BRIGADE_ID)
	assert_int(brigade.get_battalion_count()).is_equal(3)
	store.free()
