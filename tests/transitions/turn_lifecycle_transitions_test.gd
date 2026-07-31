extends GdUnitTestSuite

## Plan 0049 step 4 — the `turn_lifecycle` authority. The characterization suite
## (lifecycle_authority_characterization_test.gd) pins the behaviour through the GameState façade;
## this one tests the authority directly, against a GameStateData built by hand, and concentrates on
## the two properties the authority exists to make structural:
##
##   1. an arbitrary phase assignment is INEXPRESSIBLE (no method takes a destination), while a legal
##      edge called from the wrong SOURCE is refused without mutating anything;
##   2. the victory latches come from ONE receipt and the landing latch cannot be disarmed.


func _state(phase: GameStateData.Phase, turn: int = 1) -> GameStateData:
	var state := GameStateData.new()
	state.phase = phase
	state.turn_number = turn
	return state


func _summary(game_over: bool, winner: String, china_bns: int) -> CleanupSummary:
	var summary := CleanupSummary.new()
	summary.game_over = game_over
	summary.winner = winner
	summary.china_battalions_on_taiwan = china_bns
	return summary


# --- 1. every legal edge ---------------------------------------------------------------------------

func test_the_three_legal_edges_walk_a_whole_turn() -> void:
	var state := _state(GameStateData.Phase.PLANNING)

	assert_bool(TurnLifecycleTransitions.begin_resolution(state)).is_true()
	assert_int(state.phase).is_equal(GameStateData.Phase.RESOLUTION)
	assert_int(state.turn_number).is_equal(1)

	assert_bool(TurnLifecycleTransitions.end_resolution(state)).is_true()
	assert_int(state.phase).is_equal(GameStateData.Phase.END)
	assert_int(state.turn_number).override_failure_message(
		"only begin_next_turn moves the counter"
	).is_equal(1)

	assert_bool(TurnLifecycleTransitions.begin_next_turn(state)).is_true()
	assert_int(state.phase).is_equal(GameStateData.Phase.PLANNING)
	assert_int(state.turn_number).is_equal(2)


# --- 2. every illegal edge, from every wrong source ------------------------------------------------
# Six cases: three edges x the two phases each may NOT be called from. Each must refuse AND leave both
# the phase and the counter untouched.

@warning_ignore("unused_parameter")
func test_an_edge_from_the_wrong_source_phase_is_refused(
	from_phase: GameStateData.Phase, edge: String, message: String,
	test_parameters := [
		[GameStateData.Phase.RESOLUTION, "begin_resolution", "Cannot resolve turn outside PLANNING phase"],
		[GameStateData.Phase.END, "begin_resolution", "Cannot resolve turn outside PLANNING phase"],
		[GameStateData.Phase.PLANNING, "end_resolution", "Cannot end turn outside RESOLUTION phase"],
		[GameStateData.Phase.END, "end_resolution", "Cannot end turn outside RESOLUTION phase"],
		[GameStateData.Phase.PLANNING, "begin_next_turn", "Cannot begin next turn outside END phase"],
		[GameStateData.Phase.RESOLUTION, "begin_next_turn", "Cannot begin next turn outside END phase"],
	]
) -> void:
	var state := _state(from_phase, 7)

	await assert_error(func() -> void:
		_invoke_edge(edge, state)
	).is_push_error(message)

	assert_int(state.phase).override_failure_message(
		"a refused edge must not change the phase"
	).is_equal(from_phase)
	assert_int(state.turn_number).override_failure_message(
		"a refused edge must not advance the counter"
	).is_equal(7)


func _invoke_edge(edge: String, state: GameStateData) -> void:
	match edge:
		"begin_resolution":
			TurnLifecycleTransitions.begin_resolution(state)
		"end_resolution":
			TurnLifecycleTransitions.end_resolution(state)
		"begin_next_turn":
			TurnLifecycleTransitions.begin_next_turn(state)


## The structural half of the claim: the authority exposes no way to NAME a destination phase, so
## "PLANNING -> END" is not refused, it cannot be written.
##
## PRIVATE METHODS ARE INCLUDED ON PURPOSE. The first draft of this test filtered out anything
## starting with "_", and that filter hid a real hole: the edges were factored through a private
## `_advance(state, from, to, label)`, and a GDScript underscore is a naming convention, not access
## control — any file could have called it with an arbitrary destination, and the mutation gate would
## have seen an authorized write because the assignment lived in the authority. A test that cannot see
## the back door cannot prove the door is shut. So this pins the COMPLETE method list; adding any
## helper here means updating this list, which puts it in front of a reviewer.
func test_the_authority_exposes_no_destination_taking_method() -> void:
	var offered: Array[String] = []
	for method in TurnLifecycleTransitions.new().get_script().get_script_method_list():
		offered.append(String(method["name"]))

	assert_array(offered).override_failure_message(
		"any method taking a destination phase — public OR private — turns an absent capability " +
		"into a guard someone can argue with. `_refuse_unless_in` takes a REQUIRED phase and writes " +
		"nothing; that is not the same thing."
	).contains_exactly_in_any_order([
		"begin_resolution", "end_resolution", "begin_next_turn",
		"reset_to_turn_one", "apply_cleanup_verdict",
		"_refuse_unless_in", "_phase_name",
	])


# --- 3. scenario reset ------------------------------------------------------------------------------

func test_reset_to_turn_one_is_legal_from_any_phase_and_disarms_the_latches() -> void:
	var state := _state(GameStateData.Phase.RESOLUTION, 9)
	state.game_over = true
	state.winner = "red"
	state._china_has_landed = true

	TurnLifecycleTransitions.reset_to_turn_one(state)

	assert_int(state.turn_number).is_equal(1)
	assert_int(state.phase).is_equal(GameStateData.Phase.PLANNING)
	assert_bool(state.game_over).is_false()
	assert_str(state.winner).is_empty()
	assert_bool(state._china_has_landed).override_failure_message(
		"a new game must not inherit the previous game's landing latch"
	).is_false()


# --- 4. the victory latches -------------------------------------------------------------------------

func test_the_verdict_applies_all_three_latches_from_one_receipt() -> void:
	var state := _state(GameStateData.Phase.END)

	TurnLifecycleTransitions.apply_cleanup_verdict(state, _summary(true, "red", 12))

	assert_bool(state.game_over).is_true()
	assert_str(state.winner).is_equal("red")
	assert_bool(state._china_has_landed).is_true()


## Derived, not accepted: the landing latch comes from the SAME summary's census, so there is no
## second argument that could contradict it.
func test_the_landing_latch_arms_from_the_summarys_own_census() -> void:
	var state := _state(GameStateData.Phase.END)

	TurnLifecycleTransitions.apply_cleanup_verdict(state, _summary(false, "", 0))
	assert_bool(state._china_has_landed).is_false()

	TurnLifecycleTransitions.apply_cleanup_verdict(state, _summary(false, "", 1))
	assert_bool(state._china_has_landed).override_failure_message(
		"one battalion ashore arms the after_first_landing arm"
	).is_true()


func test_the_landing_latch_cannot_be_disarmed_by_a_later_quiet_turn() -> void:
	var state := _state(GameStateData.Phase.END)
	TurnLifecycleTransitions.apply_cleanup_verdict(state, _summary(false, "", 5))
	assert_bool(state._china_has_landed).is_true()

	TurnLifecycleTransitions.apply_cleanup_verdict(state, _summary(false, "", 0))

	assert_bool(state._china_has_landed).override_failure_message(
		"the latch is set with `or` — a turn holding nothing ashore must not re-disarm the loss check"
	).is_true()


func test_a_null_verdict_is_refused_and_changes_nothing() -> void:
	var state := _state(GameStateData.Phase.END)
	state.game_over = true
	state.winner = "green"

	await assert_error(func() -> void:
		TurnLifecycleTransitions.apply_cleanup_verdict(state, null)
	).is_push_error("TurnLifecycleTransitions.apply_cleanup_verdict: no cleanup summary")

	assert_bool(state.game_over).is_true()
	assert_str(state.winner).is_equal("green")


## The authority derives the landing latch from the summary; CleanupResolver independently computes
## its own copy for VictoryConditions. The header claims the two agree — this is that claim, tested,
## because a comment asserting a test exists is worth nothing if the test does not (found in review).
@warning_ignore("unused_parameter")
func test_the_authority_latch_agrees_with_the_resolvers_own(
	latched_before: bool, census: int,
	test_parameters := [[false, 0], [false, 3], [true, 0], [true, 3]]
) -> void:
	GameData.load_all()
	var state := _state(GameStateData.Phase.END)
	state._china_has_landed = latched_before

	var resolver_says: bool = latched_before or census > 0
	TurnLifecycleTransitions.apply_cleanup_verdict(state, _summary(false, "", census))

	assert_bool(state._china_has_landed).override_failure_message(
		"the applied latch must equal CleanupResolver's own `china_has_landed_before or census > 0`"
	).is_equal(resolver_says)


# --- 5. no dice ------------------------------------------------------------------------------------
# A lifecycle operation that drew from the shared stream would scramble every downstream phase's
# rolls. The validators that advance a turn by driving the three edges depend on this.

func test_no_lifecycle_operation_consumes_dice() -> void:
	var dice := SeededDice.new(1234)
	var before: int = dice.roll_d100()
	var state := _state(GameStateData.Phase.PLANNING)

	TurnLifecycleTransitions.begin_resolution(state)
	TurnLifecycleTransitions.end_resolution(state)
	TurnLifecycleTransitions.begin_next_turn(state)
	TurnLifecycleTransitions.apply_cleanup_verdict(state, _summary(false, "", 0))
	TurnLifecycleTransitions.reset_to_turn_one(state)

	var replay := SeededDice.new(1234)
	assert_int(replay.roll_d100()).is_equal(before)
	assert_int(dice.roll_d100()).override_failure_message(
		"the lifecycle authority must not have advanced the shared stream"
	).is_equal(replay.roll_d100())
