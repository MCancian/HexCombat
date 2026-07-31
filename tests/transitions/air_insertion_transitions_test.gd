extends GdUnitTestSuite

## Verifies AirInsertionTransitions (plan 0048) — the lift aggregate's authority. Pure: own fixtures,
## no autoload, no dice.
##
## The characterization suite next door pins what the PHASE does; this one pins what the authority
## does with a request handed to it directly, including the requests it refuses. There is
## deliberately no "a raised cap is refused" case: after plan 0048 the authority derives erosion by
## subtracting losses, so no input expresses a higher cap at all. Testing for the absence of an
## unrepresentable operation is what the manifest's claim on `caps` is for.

const AIRBORNE_CAP := 7
const AIR_ASSAULT_CAP := 2
const DROP_HEX := "hex_5_5"


func _state() -> AirInsertionState:
	var state := AirInsertionState.new()
	state.caps = {LiftClass.AIRBORNE: AIRBORNE_CAP, LiftClass.AIR_ASSAULT: AIR_ASSAULT_CAP}
	state.initial_caps = state.caps.duplicate()
	return state


func _drop(lift_class: String, landed: int, lost: int, brigade_id: String = "ABN-1") -> Dictionary:
	return {
		"brigade_id": brigade_id, "lift_class": lift_class, "hex_id": DROP_HEX,
		"sent": landed + lost, "landed": landed, "lost": lost,
		"attrition_rate": 0.5, "first_landing": landed > 0,
	}


func _request(drops: Array, turn_number: int = 1) -> AirLiftRequest:
	return AirInsertionTransitions.lift_request(turn_number, drops)


# --- the job: erosion and log applied together ----------------------------------------------------

func test_a_recorded_packet_erodes_only_its_own_class_and_appends_one_row() -> void:
	var state := _state()

	AirInsertionTransitions.record_insertions(
		state, _request([_drop(LiftClass.AIRBORNE, 5, 2)]))

	assert_int(state.caps[LiftClass.AIRBORNE]).is_equal(AIRBORNE_CAP - 2)
	assert_int(state.caps[LiftClass.AIR_ASSAULT]).is_equal(AIR_ASSAULT_CAP)
	assert_array(state.history).has_size(1)
	var row: Dictionary = state.history[0]
	assert_int(int(row["turn"])).is_equal(1)
	assert_str(String(row["brigade_id"])).is_equal("ABN-1")
	assert_str(String(row["lift_class"])).is_equal(LiftClass.AIRBORNE)
	assert_str(String(row["hex_id"])).is_equal(DROP_HEX)
	assert_int(int(row["landed"])).is_equal(5)
	assert_int(int(row["lost"])).is_equal(2)
	# Report-only summary keys never reach the log.
	assert_array(row.keys()).not_contains(["sent", "attrition_rate", "first_landing"])


func test_several_packets_erode_cumulatively_and_log_in_order() -> void:
	var state := _state()

	AirInsertionTransitions.record_insertions(state, _request([
		_drop(LiftClass.AIRBORNE, 3, 1, "ABN-1"),
		_drop(LiftClass.AIR_ASSAULT, 1, 1, "AA-1"),
		_drop(LiftClass.AIRBORNE, 0, 2, "ABN-2"),
	]))

	assert_int(state.caps[LiftClass.AIRBORNE]).is_equal(AIRBORNE_CAP - 3)
	assert_int(state.caps[LiftClass.AIR_ASSAULT]).is_equal(AIR_ASSAULT_CAP - 1)
	var ids: Array = []
	for row_value in state.history:
		ids.append(String((row_value as Dictionary)["brigade_id"]))
	assert_array(ids).is_equal(["ABN-1", "AA-1", "ABN-2"])


## Losses beyond the remaining budget floor the cap at zero rather than going negative — the same
## `maxi(0, …)` the resolver applies while flying the packet, so the two cannot disagree.
func test_losses_past_the_budget_floor_the_cap_at_zero() -> void:
	var state := _state()

	AirInsertionTransitions.record_insertions(
		state, _request([_drop(LiftClass.AIR_ASSAULT, 0, AIR_ASSAULT_CAP + 5)]))

	assert_int(state.caps[LiftClass.AIR_ASSAULT]).is_equal(0)


func test_recording_never_touches_the_ceiling_or_the_pool() -> void:
	var state := _state()
	state.pool = [{"brigade_id": "ABN-1", "lift_class": LiftClass.AIRBORNE, "bns": []}]
	state.landed = ["ABN-1"] as Array[String]
	var initial := state.initial_caps.duplicate()

	AirInsertionTransitions.record_insertions(
		state, _request([_drop(LiftClass.AIRBORNE, 1, 1)]))

	assert_dict(state.initial_caps).override_failure_message(
		"initial_caps is the bound cap erosion is measured against; this authority must never move it"
	).is_equal(initial)
	assert_array(state.pool).has_size(1)
	assert_array(state.landed).is_equal(["ABN-1"])


func test_an_empty_request_changes_nothing() -> void:
	var state := _state()
	var caps := state.caps.duplicate()

	AirInsertionTransitions.record_insertions(state, _request([]))

	assert_dict(state.caps).is_equal(caps)
	assert_array(state.history).is_empty()


# --- refusals: nothing is written, and the predicate agrees ---------------------------------------

func test_a_drop_naming_an_unknown_lift_class_is_refused_whole() -> void:
	var state := _state()
	var caps := state.caps.duplicate()
	var request := _request([
		_drop(LiftClass.AIRBORNE, 2, 1, "ABN-1"),
		_drop("hovercraft", 1, 1, "HOV-1"),
	])

	assert_bool(AirInsertionTransitions.can_record_insertions(state, request)).is_false()
	AirInsertionTransitions.record_insertions(state, request)

	assert_dict(state.caps).override_failure_message(
		"one malformed row refuses the whole request — a half-applied ledger is worse than none"
	).is_equal(caps)
	assert_array(state.history).is_empty()


func test_a_lift_class_this_state_does_not_budget_for_is_refused() -> void:
	var state := _state()
	state.caps = {LiftClass.AIRBORNE: AIRBORNE_CAP}
	state.initial_caps = state.caps.duplicate()
	var request := _request([_drop(LiftClass.AIR_ASSAULT, 1, 1)])

	assert_bool(AirInsertionTransitions.can_record_insertions(state, request)).is_false()
	AirInsertionTransitions.record_insertions(state, request)

	assert_array(state.caps.keys()).is_equal([LiftClass.AIRBORNE])
	assert_array(state.history).is_empty()


## A row missing a key the ledger reads is caught by the PREFLIGHT, which is what lets
## `record_insertions` stage its whole result: without this, the malformed row would raise while
## appending history, after the budget had already been assigned.
func test_a_row_missing_a_required_key_is_refused_before_anything_is_written() -> void:
	var state := _state()
	var caps := state.caps.duplicate()
	var incomplete := _drop(LiftClass.AIRBORNE, 2, 1)
	incomplete.erase("hex_id")
	var request := _request([_drop(LiftClass.AIRBORNE, 1, 1, "ABN-1"), incomplete])

	assert_bool(AirInsertionTransitions.can_record_insertions(state, request)).is_false()
	AirInsertionTransitions.record_insertions(state, request)

	assert_dict(state.caps).override_failure_message(
		"a malformed row must be caught before the budget is assigned, not while writing the log"
	).is_equal(caps)
	assert_array(state.history).is_empty()


func test_a_negative_count_is_refused() -> void:
	var state := _state()
	var caps := state.caps.duplicate()
	var request := _request([_drop(LiftClass.AIRBORNE, 1, -3)])

	assert_bool(AirInsertionTransitions.can_record_insertions(state, request)).is_false()
	AirInsertionTransitions.record_insertions(state, request)

	assert_dict(state.caps).is_equal(caps)
	assert_array(state.history).is_empty()


## The preflight and the guard must agree exactly, because the coordinator relies on the preflight to
## decide whether it is safe to let the FORCE authority commit first.
func test_the_preflight_accepts_exactly_what_recording_applies() -> void:
	var state := _state()
	var legal := _request([_drop(LiftClass.AIRBORNE, 4, 3)])

	assert_bool(AirInsertionTransitions.can_record_insertions(state, legal)).is_true()
	AirInsertionTransitions.record_insertions(state, legal)
	assert_int(state.caps[LiftClass.AIRBORNE]).is_equal(AIRBORNE_CAP - 3)

	assert_bool(AirInsertionTransitions.can_record_insertions(null, legal)).is_false()
	assert_bool(AirInsertionTransitions.can_record_insertions(state, null)).is_false()


# --- scenario lifecycle --------------------------------------------------------------------------

func test_rebuild_installs_a_fresh_state_on_the_turn_value_object() -> void:
	var data := GameStateData.new()
	var brigades: Dictionary = {}

	AirInsertionTransitions.rebuild_air_insertion_state(data, {}, brigades)

	assert_object(data.air_insertion_state).is_not_null()
	assert_array(data.air_insertion_state.pool).is_empty()
	assert_array(data.air_insertion_state.history).is_empty()


## The request is a deep copy: mutating the caller's rows afterwards cannot reach the ledger.
func test_the_request_does_not_alias_the_callers_rows() -> void:
	var drops: Array = [_drop(LiftClass.AIRBORNE, 2, 1)]
	var request := _request(drops)

	(drops[0] as Dictionary)["lost"] = 99

	var state := _state()
	AirInsertionTransitions.record_insertions(state, request)
	assert_int(state.caps[LiftClass.AIRBORNE]).is_equal(AIRBORNE_CAP - 1)
