## Verifies AirInsertionResolver (plan 0032): the per-lift-class per-turn budget, attrition keyed on
## the air-defence environment, and the permanent cap erosion a loss causes. Pure — own fixtures,
## no autoload, ScriptedDice for roll control.
extends GdUnitTestSuite

const AIRBORNE_CAP := 7
const AIR_ASSAULT_CAP := 2

## Attrition coefficients at their shipped defaults, so the arithmetic in these tests is the
## arithmetic a real game does.
const CONFIG := {"max_attrition_at_full_ad": 0.75, "manpads_max_attrition": 0.25}

## A post-warmup turn-1 picture: SAMs mostly beaten down, MANPADS layer still saturated.
const THREAT_TURN_1 := {"ad_health": 0.24, "manpads_ready_systems": 1975}
## Air defences gone entirely — the free-ride case.
const THREAT_CLEAR := {"ad_health": 0.0, "manpads_ready_systems": 0}


func _manifest(brigade_id: String, count: int) -> Array:
	var bns: Array = []
	for index in range(count):
		bns.append({"id": "%s-AIR-%d" % [brigade_id, index + 1], "type": "Airborne Combined Arms Battalion"})
	return bns


func _state() -> AirInsertionState:
	var state := AirInsertionState.new()
	state.pool = [
		{"brigade_id": "ABN-1", "lift_class": LiftClass.AIRBORNE, "bns": _manifest("ABN-1", 8)},
		{"brigade_id": "ABN-2", "lift_class": LiftClass.AIRBORNE, "bns": _manifest("ABN-2", 8)},
		{"brigade_id": "AA-1", "lift_class": LiftClass.AIR_ASSAULT, "bns": _manifest("AA-1", 10)},
	]
	state.caps = {LiftClass.AIRBORNE: AIRBORNE_CAP, LiftClass.AIR_ASSAULT: AIR_ASSAULT_CAP}
	state.initial_caps = state.caps.duplicate()
	return state


func _any_hex() -> Callable:
	return func(_hex_id: String) -> bool: return true


## Every roll lands (1.0 is never < any rate <= 1.0).
func _all_survive() -> ScriptedDice:
	var floats: Array = []
	for _index in range(64):
		floats.append(1.0)
	return ScriptedDice.new([], [], floats)


## Every roll is a loss (0.0 < any positive rate).
func _all_lost() -> ScriptedDice:
	var floats: Array = []
	for _index in range(64):
		floats.append(0.0)
	return ScriptedDice.new([], [], floats)


func test_clear_skies_land_the_whole_packet_up_to_the_cap() -> void:
	var state := _state()
	var summary := AirInsertionResolver.resolve(
		state, [{"brigade_id": "ABN-1", "target_hex": "hex_5_5"}], 1,
		THREAT_CLEAR, CONFIG, _any_hex(), _all_survive())

	assert_int(summary.battalions_landed).is_equal(AIRBORNE_CAP)
	assert_int(summary.battalions_lost).is_equal(0)
	assert_float(summary.attrition_by_class[LiftClass.AIRBORNE]).is_equal_approx(0.0, 0.0001)
	# 8 BN brigade, 7 flew: one left behind, and the cap is untouched because nothing was shot down.
	assert_int(state.pending_battalions()).is_equal(19)
	assert_int(state.caps[LiftClass.AIRBORNE]).is_equal(AIRBORNE_CAP)
	assert_array(state.landed).contains(["ABN-1"])

	var drop: Dictionary = summary.drops[0]
	assert_int(drop["sent"]).is_equal(AIRBORNE_CAP)
	assert_bool(drop["first_landing"]).is_true()
	assert_int((drop["landed_bns"] as Array).size()).is_equal(AIRBORNE_CAP)


func test_losses_erode_the_cap_permanently() -> void:
	var state := _state()
	var summary := AirInsertionResolver.resolve(
		state, [{"brigade_id": "ABN-1", "target_hex": "hex_5_5"}], 1,
		THREAT_TURN_1, CONFIG, _any_hex(), _all_lost())

	assert_int(summary.battalions_landed).is_equal(0)
	assert_int(summary.battalions_lost).is_equal(AIRBORNE_CAP)
	# Seven airframes down: the airborne budget is gone for the rest of the game.
	assert_int(state.caps[LiftClass.AIRBORNE]).is_equal(0)
	assert_int(summary.caps_before[LiftClass.AIRBORNE]).is_equal(AIRBORNE_CAP)
	assert_int(summary.caps_after[LiftClass.AIRBORNE]).is_equal(0)
	# Nothing landed, so the brigade is still not on the map.
	assert_array(state.landed).is_empty()

	# The next turn's order finds no lift left.
	var next_summary := AirInsertionResolver.resolve(
		state, [{"brigade_id": "ABN-1", "target_hex": "hex_5_5"}], 2,
		THREAT_CLEAR, CONFIG, _any_hex(), _all_survive())
	assert_int(next_summary.battalions_landed).is_equal(0)
	assert_str(String((next_summary.rejected[0] as Dictionary)["reason"])).is_equal(
		AirInsertionSummary.REASON_CAP_EXHAUSTED)


func test_the_air_assault_cap_is_separate_from_the_airborne_cap() -> void:
	var state := _state()
	var summary := AirInsertionResolver.resolve(
		state,
		[{"brigade_id": "ABN-1", "target_hex": "hex_5_5"}, {"brigade_id": "AA-1", "target_hex": "hex_6_6"}],
		1, THREAT_CLEAR, CONFIG, _any_hex(), _all_survive())

	assert_int(summary.drops.size()).is_equal(2)
	assert_int(summary.battalions_landed).is_equal(AIRBORNE_CAP + AIR_ASSAULT_CAP)
	assert_int(int((summary.drops[1] as Dictionary)["sent"])).is_equal(AIR_ASSAULT_CAP)


func test_one_class_budget_is_shared_across_that_class_orders() -> void:
	var state := _state()
	var summary := AirInsertionResolver.resolve(
		state,
		[{"brigade_id": "ABN-1", "target_hex": "hex_5_5"}, {"brigade_id": "ABN-2", "target_hex": "hex_6_6"}],
		1, THREAT_CLEAR, CONFIG, _any_hex(), _all_survive())

	# First order spends the whole 7-BN budget; the second gets nothing this turn.
	assert_int(summary.battalions_landed).is_equal(AIRBORNE_CAP)
	assert_int(summary.drops.size()).is_equal(1)
	assert_str(String((summary.rejected[0] as Dictionary)["brigade_id"])).is_equal("ABN-2")
	assert_str(String((summary.rejected[0] as Dictionary)["reason"])).is_equal(
		AirInsertionSummary.REASON_CAP_EXHAUSTED)


func test_rotary_wing_lift_pays_the_manpads_term_on_top_of_ad_health() -> void:
	# Same air-defence picture, two lift classes: 0.75 x 0.24 = 0.18 for fixed wing, plus
	# 0.25 x 1.0 (saturated MANPADS) = 0.43 for rotary wing.
	var airborne := AirInsertionResolver.attrition_rate(
		LiftClass.AIRBORNE, 0.24, 1975, CONFIG)
	var air_assault := AirInsertionResolver.attrition_rate(
		LiftClass.AIR_ASSAULT, 0.24, 1975, CONFIG)
	assert_float(airborne).is_equal_approx(0.18, 0.0001)
	assert_float(air_assault).is_equal_approx(0.43, 0.0001)

	# Once the MANPADS layer is spent, the two classes face the same environment again.
	assert_float(AirInsertionResolver.attrition_rate(LiftClass.AIR_ASSAULT, 0.24, 0, CONFIG)) \
		.is_equal_approx(0.18, 0.0001)


func test_intact_air_defences_destroy_three_quarters_of_the_lift() -> void:
	# The USER's anchor: an undegraded air-defence system kills 75% of an inserting packet.
	assert_float(AirInsertionResolver.attrition_rate(LiftClass.AIRBORNE, 1.0, 0, CONFIG)) \
		.is_equal_approx(0.75, 0.0001)
	# Rotary wing into that same environment is capped at total loss, not 1.0 + something.
	assert_float(AirInsertionResolver.attrition_rate(LiftClass.AIR_ASSAULT, 1.0, 1975, CONFIG)) \
		.is_equal_approx(1.0, 0.0001)


func test_no_orders_consumes_no_dice_and_changes_nothing() -> void:
	var state := _state()
	# An empty ScriptedDice push_errors on any draw, so this passing IS the no-dice proof.
	var summary := AirInsertionResolver.resolve(
		state, [], 1, THREAT_TURN_1, CONFIG, _any_hex(), ScriptedDice.new([]))

	assert_array(summary.drops).is_empty()
	assert_int(summary.battalions_landed).is_equal(0)
	assert_int(state.pending_battalions()).is_equal(26)
	assert_int(state.caps[LiftClass.AIRBORNE]).is_equal(AIRBORNE_CAP)


func test_drops_before_the_first_permitted_turn_are_rejected() -> void:
	var state := _state()
	state.first_turn = 3
	var summary := AirInsertionResolver.resolve(
		state, [{"brigade_id": "ABN-1", "target_hex": "hex_5_5"}], 2,
		THREAT_CLEAR, CONFIG, _any_hex(), ScriptedDice.new([]))

	assert_array(summary.drops).is_empty()
	assert_str(String((summary.rejected[0] as Dictionary)["reason"])).is_equal(
		AirInsertionSummary.REASON_BEFORE_FIRST_TURN)
	assert_int(state.pending_battalions()).is_equal(26)


func test_an_unlandable_hex_is_rejected_without_spending_lift() -> void:
	var state := _state()
	var summary := AirInsertionResolver.resolve(
		state, [{"brigade_id": "ABN-1", "target_hex": "hex_ocean"}], 1,
		THREAT_CLEAR, CONFIG, func(_hex_id: String) -> bool: return false, ScriptedDice.new([]))

	assert_array(summary.drops).is_empty()
	assert_str(String((summary.rejected[0] as Dictionary)["reason"])).is_equal(
		AirInsertionResolver.REASON_UNKNOWN_HEX)
	assert_int(state.caps[LiftClass.AIRBORNE]).is_equal(AIRBORNE_CAP)
	assert_int(state.pending_battalions()).is_equal(26)


func test_an_emptied_brigade_leaves_the_pool() -> void:
	var state := _state()
	state.pool = [{"brigade_id": "ABN-1", "lift_class": LiftClass.AIRBORNE, "bns": _manifest("ABN-1", 3)}]
	var summary := AirInsertionResolver.resolve(
		state, [{"brigade_id": "ABN-1", "target_hex": "hex_5_5"}], 1,
		THREAT_CLEAR, CONFIG, _any_hex(), _all_survive())

	assert_int(summary.battalions_landed).is_equal(3)
	assert_array(state.pool).is_empty()
	assert_int(summary.pending_brigades).is_equal(0)

	var next_summary := AirInsertionResolver.resolve(
		state, [{"brigade_id": "ABN-1", "target_hex": "hex_5_5"}], 2,
		THREAT_CLEAR, CONFIG, _any_hex(), _all_survive())
	assert_str(String((next_summary.rejected[0] as Dictionary)["reason"])).is_equal(
		AirInsertionSummary.REASON_POOL_EMPTY)


func test_the_serialized_summary_omits_the_application_manifests() -> void:
	var state := _state()
	var summary := AirInsertionResolver.resolve(
		state, [{"brigade_id": "ABN-1", "target_hex": "hex_5_5"}], 1,
		THREAT_CLEAR, CONFIG, _any_hex(), _all_survive())

	var drop: Dictionary = (summary.to_dict()["drops"] as Array)[0]
	assert_bool(drop.has("landed_bns")).is_false()
	assert_bool(drop.has("lost_bns")).is_false()
	assert_int(int(drop["landed"])).is_equal(AIRBORNE_CAP)
