## Verifies the air_insert order (plan 0032): who may be flown, where, and the rules that keep a
## formation in one hex. Runs against the real GameData autoload (the validator's legality checks
## read the live OOB and map) with an AirInsertionState built by hand, because no shipped scenario
## opts the mechanic in yet.
extends GdUnitTestSuite

const AIRBORNE_BRIGADE := "PLAAF-ABN-127-Airborne"
const AIR_ASSAULT_BRIGADE := "PLAAF-ABN-130-Air-Assault"
const SEA_BRIGADE := "PLA-71-2-Amphibious"
const PASSABLE_HEX := "hex_3_9"        # plains
const OTHER_PASSABLE_HEX := "hex_4_9"  # plains
const IMPASSABLE_HEX := "hex_10_10"    # mountain


func before_test() -> void:
	GameData.load_all()
	GameState.reset_to_scenario()


func after_test() -> void:
	GameData.load_all()
	GameState.reset_to_scenario()


func _state() -> GameStateData:
	var state := GameStateData.new()
	state.phase = GameStateData.Phase.PLANNING
	state.air_insertion_state = AirInsertionStateBuilder.build({"enabled": true}, GameData.brigades)
	return state


func test_the_corps_can_be_ordered_onto_any_passable_hex() -> void:
	var state := _state()
	var result := OrderValidator.add_air_insert_order(
		state, Brigade.Team.RED, AIRBORNE_BRIGADE, PASSABLE_HEX)

	assert_bool(result.ok).is_true()
	assert_int(state.air_insert_orders.size()).is_equal(1)
	assert_str(String((state.air_insert_orders[0] as Dictionary)["target_hex"])).is_equal(PASSABLE_HEX)


func test_a_sea_lifted_brigade_cannot_be_flown() -> void:
	var state := _state()
	var result := OrderValidator.add_air_insert_order(
		state, Brigade.Team.RED, SEA_BRIGADE, PASSABLE_HEX)

	assert_bool(result.ok).is_false()
	assert_int(result.code).is_equal(OrderResult.Code.NOT_AIR_LIFTED)
	assert_array(state.air_insert_orders).is_empty()


func test_green_cannot_issue_the_order() -> void:
	var state := _state()
	var result := OrderValidator.add_air_insert_order(
		state, Brigade.Team.GREEN, AIRBORNE_BRIGADE, PASSABLE_HEX)

	assert_bool(result.ok).is_false()
	assert_int(result.code).is_equal(OrderResult.Code.TEAM_MISMATCH)


func test_impassable_and_unknown_hexes_are_rejected() -> void:
	var state := _state()
	assert_int(OrderValidator.add_air_insert_order(
		state, Brigade.Team.RED, AIRBORNE_BRIGADE, IMPASSABLE_HEX).code) \
		.is_equal(OrderResult.Code.IMPASSABLE_HEX)
	assert_int(OrderValidator.add_air_insert_order(
		state, Brigade.Team.RED, AIRBORNE_BRIGADE, "hex_999_999").code) \
		.is_equal(OrderResult.Code.UNKNOWN_HEX)
	assert_array(state.air_insert_orders).is_empty()


func test_one_order_per_brigade_per_turn() -> void:
	var state := _state()
	assert_bool(OrderValidator.add_air_insert_order(
		state, Brigade.Team.RED, AIRBORNE_BRIGADE, PASSABLE_HEX).ok).is_true()
	var second := OrderValidator.add_air_insert_order(
		state, Brigade.Team.RED, AIRBORNE_BRIGADE, OTHER_PASSABLE_HEX)

	assert_bool(second.ok).is_false()
	assert_int(second.code).is_equal(OrderResult.Code.DUPLICATE_AIR_INSERT)
	assert_int(state.air_insert_orders.size()).is_equal(1)


func test_follow_up_packets_must_reinforce_the_brigade_where_it_stands() -> void:
	var state := _state()
	GameData.set_brigade_hex(AIRBORNE_BRIGADE, PASSABLE_HEX)

	var elsewhere := OrderValidator.add_air_insert_order(
		state, Brigade.Team.RED, AIRBORNE_BRIGADE, OTHER_PASSABLE_HEX)
	assert_bool(elsewhere.ok).is_false()
	assert_int(elsewhere.code).is_equal(OrderResult.Code.BRIGADE_ALREADY_LANDED)

	# Same hex is fine — that is a reinforcement, not a second lodgement.
	assert_bool(OrderValidator.add_air_insert_order(
		state, Brigade.Team.RED, AIRBORNE_BRIGADE, PASSABLE_HEX).ok).is_true()


func test_a_brigade_with_nothing_left_to_fly_is_rejected() -> void:
	var state := _state()
	for entry_value in state.air_insertion_state.pool:
		var entry: Dictionary = entry_value
		if String(entry["brigade_id"]) == AIRBORNE_BRIGADE:
			(entry["bns"] as Array).clear()
	# entry_for only reports entries that still hold battalions once the resolver prunes them, but a
	# drained-but-present entry must be rejected too.
	state.air_insertion_state.pool = state.air_insertion_state.pool.filter(
		func(e: Dictionary) -> bool: return not (e["bns"] as Array).is_empty())

	var result := OrderValidator.add_air_insert_order(
		state, Brigade.Team.RED, AIRBORNE_BRIGADE, PASSABLE_HEX)
	assert_bool(result.ok).is_false()
	assert_int(result.code).is_equal(OrderResult.Code.NO_LIFT_REMAINING)


func test_orders_outside_planning_are_rejected() -> void:
	var state := _state()
	state.phase = GameStateData.Phase.RESOLUTION
	assert_int(OrderValidator.add_air_insert_order(
		state, Brigade.Team.RED, AIRBORNE_BRIGADE, PASSABLE_HEX).code) \
		.is_equal(OrderResult.Code.WRONG_PHASE)


func test_eligible_list_covers_the_corps_and_drops_the_ones_already_ordered() -> void:
	var state := _state()
	var before := OrderValidator.eligible_air_insert_brigades(state)
	var ids: Array[String] = []
	for row_value in before:
		ids.append(String((row_value as Dictionary)["brigade_id"]))
	assert_array(ids).contains([AIRBORNE_BRIGADE, AIR_ASSAULT_BRIGADE])
	assert_int(before.size()).is_equal(6)

	OrderValidator.add_air_insert_order(state, Brigade.Team.RED, AIRBORNE_BRIGADE, PASSABLE_HEX)
	assert_int(OrderValidator.eligible_air_insert_brigades(state).size()).is_equal(5)


func test_eligible_rows_report_the_lift_class_and_the_locked_hex() -> void:
	var state := _state()
	GameData.set_brigade_hex(AIRBORNE_BRIGADE, PASSABLE_HEX)
	for row_value in OrderValidator.eligible_air_insert_brigades(state):
		var row: Dictionary = row_value
		if String(row["brigade_id"]) == AIRBORNE_BRIGADE:
			assert_str(String(row["lift_class"])).is_equal(LiftClass.AIRBORNE)
			assert_str(String(row["locked_hex"])).is_equal(PASSABLE_HEX)
			assert_int(int(row["battalions_waiting"])).is_equal(8)
		elif String(row["brigade_id"]) == AIR_ASSAULT_BRIGADE:
			assert_str(String(row["lift_class"])).is_equal(LiftClass.AIR_ASSAULT)
			assert_str(String(row["locked_hex"])).is_equal("")
			assert_int(int(row["battalions_waiting"])).is_equal(10)
