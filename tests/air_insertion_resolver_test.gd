## Verifies AirInsertionResolver (plan 0032): the per-lift-class per-turn budget, attrition keyed on
## the air-defence environment, and the permanent cap erosion a loss causes. Pure — own fixtures,
## no autoload, ScriptedDice for roll control. The resolver is compute-only as of plan 0044: state
## mutations are tested in tests/transitions/force_transitions_test.gd.
extends GdUnitTestSuite

const AIRBORNE_CAP := 7
const AIR_ASSAULT_CAP := 2

## Attrition coefficients at their shipped defaults.
const CONFIG := {"max_attrition_at_full_ad": 0.75, "manpads_max_attrition": 0.25}

## A post-warmup turn-1 picture: SAMs mostly beaten down, MANPADS layer still saturated.
const THREAT_TURN_1 := {"ad_health": 0.24, "manpads_ready_systems": 1975}
## Air defences gone entirely.
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


## Every roll lands (1.0 never < rate).
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
	var outcome := AirInsertionResolver.resolve(
		state, [{"brigade_id": "ABN-1", "target_hex": "hex_5_5"}], 1,
		THREAT_CLEAR, CONFIG, _any_hex(), _all_survive())
	var summary: AirInsertionSummary = outcome["summary"]

	assert_int(summary.battalions_landed).is_equal(AIRBORNE_CAP)
	assert_int(summary.battalions_lost).is_equal(0)
	assert_float(summary.attrition_by_class[LiftClass.AIRBORNE]).is_equal_approx(0.0, 0.0001)
	# Resolver is compute-only: state unchanged, summary reports projected caps.
	assert_int(summary.pending_battalions).is_equal(19)
	assert_int(summary.caps_after[LiftClass.AIRBORNE]).is_equal(AIRBORNE_CAP)

	var drop: Dictionary = summary.drops[0]
	assert_int(drop["sent"]).is_equal(AIRBORNE_CAP)
	assert_bool(drop["first_landing"]).is_true()


func test_losses_erode_the_cap_projected_in_summary() -> void:
	var state := _state()
	var outcome := AirInsertionResolver.resolve(
		state, [{"brigade_id": "ABN-1", "target_hex": "hex_5_5"}], 1,
		THREAT_TURN_1, CONFIG, _any_hex(), _all_lost())
	var summary: AirInsertionSummary = outcome["summary"]

	assert_int(summary.battalions_landed).is_equal(0)
	assert_int(summary.battalions_lost).is_equal(AIRBORNE_CAP)
	# caps_after in the summary reflects the projected erosion.
	assert_int(summary.caps_before[LiftClass.AIRBORNE]).is_equal(AIRBORNE_CAP)
	assert_int(summary.caps_after[LiftClass.AIRBORNE]).is_equal(0)

	# Simulate what ReinforcementPhases does: apply caps erosion from summary.
	state.caps = summary.caps_after.duplicate()

	# The next turn's order finds no lift left.
	var next_outcome := AirInsertionResolver.resolve(
		state, [{"brigade_id": "ABN-1", "target_hex": "hex_5_5"}], 2,
		THREAT_CLEAR, CONFIG, _any_hex(), _all_survive())
	var next_summary: AirInsertionSummary = next_outcome["summary"]
	assert_int(next_summary.battalions_landed).is_equal(0)
	assert_str(String((next_summary.rejected[0] as Dictionary)["reason"])).is_equal(
		AirInsertionSummary.REASON_CAP_EXHAUSTED)


func test_the_air_assault_cap_is_separate_from_the_airborne_cap() -> void:
	var state := _state()
	var outcome := AirInsertionResolver.resolve(
		state,
		[{"brigade_id": "ABN-1", "target_hex": "hex_5_5"}, {"brigade_id": "AA-1", "target_hex": "hex_6_6"}],
		1, THREAT_CLEAR, CONFIG, _any_hex(), _all_survive())
	var summary: AirInsertionSummary = outcome["summary"]

	assert_int(summary.drops.size()).is_equal(2)
	assert_int(summary.battalions_landed).is_equal(AIRBORNE_CAP + AIR_ASSAULT_CAP)
	assert_int(int((summary.drops[1] as Dictionary)["sent"])).is_equal(AIR_ASSAULT_CAP)


func test_one_class_budget_is_shared_across_that_class_orders() -> void:
	var state := _state()
	var outcome := AirInsertionResolver.resolve(
		state,
		[{"brigade_id": "ABN-1", "target_hex": "hex_5_5"}, {"brigade_id": "ABN-2", "target_hex": "hex_6_6"}],
		1, THREAT_CLEAR, CONFIG, _any_hex(), _all_survive())
	var summary: AirInsertionSummary = outcome["summary"]

	assert_int(summary.battalions_landed).is_equal(AIRBORNE_CAP)
	assert_int(summary.drops.size()).is_equal(1)
	assert_str(String((summary.rejected[0] as Dictionary)["brigade_id"])).is_equal("ABN-2")
	assert_str(String((summary.rejected[0] as Dictionary)["reason"])).is_equal(
		AirInsertionSummary.REASON_CAP_EXHAUSTED)


func test_rotary_wing_lift_pays_the_manpads_term_on_top_of_ad_health() -> void:
	var airborne := AirInsertionResolver.attrition_rate(
		LiftClass.AIRBORNE, 0.24, 1975, CONFIG)
	var air_assault := AirInsertionResolver.attrition_rate(
		LiftClass.AIR_ASSAULT, 0.24, 1975, CONFIG)
	assert_float(airborne).is_equal_approx(0.18, 0.0001)
	assert_float(air_assault).is_equal_approx(0.43, 0.0001)

	assert_float(AirInsertionResolver.attrition_rate(LiftClass.AIR_ASSAULT, 0.24, 0, CONFIG)) \
		.is_equal_approx(0.18, 0.0001)


func test_intact_air_defences_destroy_three_quarters_of_the_lift() -> void:
	assert_float(AirInsertionResolver.attrition_rate(LiftClass.AIRBORNE, 1.0, 0, CONFIG)) \
		.is_equal_approx(0.75, 0.0001)
	assert_float(AirInsertionResolver.attrition_rate(LiftClass.AIR_ASSAULT, 1.0, 1975, CONFIG)) \
		.is_equal_approx(1.0, 0.0001)


func test_no_orders_consumes_no_dice_and_changes_nothing() -> void:
	var state := _state()
	var outcome := AirInsertionResolver.resolve(
		state, [], 1, THREAT_TURN_1, CONFIG, _any_hex(), ScriptedDice.new([]))
	var summary: AirInsertionSummary = outcome["summary"]

	assert_array(summary.drops).is_empty()
	assert_int(summary.battalions_landed).is_equal(0)
	# Resolver is compute-only: state unchanged.
	assert_int(state.pending_battalions()).is_equal(26)
	assert_int(state.caps[LiftClass.AIRBORNE]).is_equal(AIRBORNE_CAP)


func test_drops_before_the_first_permitted_turn_are_rejected() -> void:
	var state := _state()
	state.first_turn = 3
	var outcome := AirInsertionResolver.resolve(
		state, [{"brigade_id": "ABN-1", "target_hex": "hex_5_5"}], 2,
		THREAT_CLEAR, CONFIG, _any_hex(), ScriptedDice.new([]))
	var summary: AirInsertionSummary = outcome["summary"]

	assert_array(summary.drops).is_empty()
	assert_str(String((summary.rejected[0] as Dictionary)["reason"])).is_equal(
		AirInsertionSummary.REASON_BEFORE_FIRST_TURN)
	assert_int(state.pending_battalions()).is_equal(26)


func test_an_unlandable_hex_is_rejected_without_spending_lift() -> void:
	var state := _state()
	var outcome := AirInsertionResolver.resolve(
		state, [{"brigade_id": "ABN-1", "target_hex": "hex_ocean"}], 1,
		THREAT_CLEAR, CONFIG, func(_hex_id: String) -> bool: return false, ScriptedDice.new([]))
	var summary: AirInsertionSummary = outcome["summary"]

	assert_array(summary.drops).is_empty()
	assert_str(String((summary.rejected[0] as Dictionary)["reason"])).is_equal(
		AirInsertionResolver.REASON_UNKNOWN_HEX)
	assert_int(state.caps[LiftClass.AIRBORNE]).is_equal(AIRBORNE_CAP)
	assert_int(state.pending_battalions()).is_equal(26)


func test_projected_pending_shows_empty_after_full_drop() -> void:
	var state := _state()
	state.pool = [{"brigade_id": "ABN-1", "lift_class": LiftClass.AIRBORNE, "bns": _manifest("ABN-1", 3)}]
	var outcome := AirInsertionResolver.resolve(
		state, [{"brigade_id": "ABN-1", "target_hex": "hex_5_5"}], 1,
		THREAT_CLEAR, CONFIG, _any_hex(), _all_survive())
	var summary: AirInsertionSummary = outcome["summary"]

	assert_int(summary.battalions_landed).is_equal(3)
	assert_int(summary.pending_brigades).is_equal(0)
	assert_int(summary.pending_battalions).is_equal(0)

	# Simulate what ForceTransitions does: drain the sent BNs from pool.
	state.pool = []

	# Now the brigade is empty — the resolver rejects the order.
	var next_outcome := AirInsertionResolver.resolve(
		state, [{"brigade_id": "ABN-1", "target_hex": "hex_5_5"}], 2,
		THREAT_CLEAR, CONFIG, _any_hex(), _all_survive())
	var next_summary: AirInsertionSummary = next_outcome["summary"]
	assert_str(String((next_summary.rejected[0] as Dictionary)["reason"])).is_equal(
		AirInsertionSummary.REASON_POOL_EMPTY)


## A 5-hex line: BEACH - A - B, and C off on its own. Red holds the beach, A and C.
const CORRIDOR := {
	"beach": ["a"],
	"a": ["beach", "b"],
	"b": ["a"],
	"c": ["d"],
	"d": ["c"],
}
const RED_HELD := {"beach": true, "a": true, "c": true}


func _corridor_neighbors() -> Callable:
	return func(hex_id: String) -> Array: return CORRIDOR.get(hex_id, [])


func _corridor_is_red() -> Callable:
	return func(hex_id: String) -> bool: return RED_HELD.has(hex_id)


func test_a_brigade_on_the_corridor_is_supplied() -> void:
	var isolated := AirInsertionResolver.isolated_brigades(
		["ABN-1"], {"ABN-1": "a"}, ["beach"], _corridor_is_red(), _corridor_neighbors())
	assert_dict(isolated).is_empty()


func test_a_brigade_touching_the_corridor_is_supplied() -> void:
	var isolated := AirInsertionResolver.isolated_brigades(
		["ABN-1"], {"ABN-1": "b"}, ["beach"], _corridor_is_red(), _corridor_neighbors())
	assert_dict(isolated).is_empty()


func test_a_brigade_dropped_in_the_deep_rear_is_isolated() -> void:
	var isolated := AirInsertionResolver.isolated_brigades(
		["ABN-1"], {"ABN-1": "c"}, ["beach"], _corridor_is_red(), _corridor_neighbors())
	assert_bool(isolated.has("ABN-1")).is_true()


func test_a_lodgement_green_still_holds_is_not_a_supply_root() -> void:
	var isolated := AirInsertionResolver.isolated_brigades(
		["ABN-1"], {"ABN-1": "a"}, ["nowhere"], _corridor_is_red(), _corridor_neighbors())
	assert_bool(isolated.has("ABN-1")).is_true()


func test_brigades_not_on_the_map_are_not_isolated() -> void:
	var isolated := AirInsertionResolver.isolated_brigades(
		["ABN-1"], {"ABN-1": ""}, ["beach"], _corridor_is_red(), _corridor_neighbors())
	assert_dict(isolated).is_empty()


func test_isolation_only_overrides_supply_for_the_named_brigades() -> void:
	var units: Array = [
		{"brigade_id": "ABN-1", "type": "Airborne Combined Arms Battalion", "supply_effectiveness": 1.0},
		{"brigade_id": "PLA-71-2-Amphibious", "type": "Amphibious Infantry Battalion", "supply_effectiveness": 1.0},
	]
	CombatResolver.inject_supply_effectiveness(units, Brigade.Team.RED, 5000.0, 0.5, {"ABN-1": true})
	assert_float(float((units[0] as Dictionary)["supply_effectiveness"])).is_equal_approx(0.5, 0.0001)
	assert_float(float((units[1] as Dictionary)["supply_effectiveness"])).is_equal_approx(1.0, 0.0001)


## The report and the application manifests are separate return values (the OffloadResolver shape):
## the summary is pure report and serializes whole, the landings carry the battalions to place and
## the battalions to kill.
func test_landings_carry_the_manifests_and_the_summary_stays_report_only() -> void:
	var state := _state()
	var outcome := AirInsertionResolver.resolve(
		state, [{"brigade_id": "ABN-1", "target_hex": "hex_5_5"}], 1,
		THREAT_TURN_1, CONFIG, _any_hex(), _all_lost())

	var summary: AirInsertionSummary = outcome["summary"]
	var landing: Dictionary = (outcome["landings"] as Array)[0]
	assert_int((landing["lost_bns"] as Array).size()).is_equal(AIRBORNE_CAP)
	assert_array(landing["landed_bns"]).is_empty()
	assert_str(String(landing["brigade_id"])).is_equal("ABN-1")

	var drop: Dictionary = (summary.to_dict()["drops"] as Array)[0]
	assert_bool(drop.has("landed_bns")).is_false()
	assert_bool(drop.has("lost_bns")).is_false()
	assert_int(int(drop["lost"])).is_equal(AIRBORNE_CAP)
