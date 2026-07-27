extends GdUnitTestSuite

## Plan 0043 — the Green anti-ship establishment across crossings.
##
## Two contracts:
##  1. The ONE-crossing launch-attrition contract — the exact ScriptedDice draw count/order and the
##     fired rows plus typed outcomes. This is the guard on the whole plan: splitting the calculator from the
##     mutation authority must not move a single die.
##  2. The CROSSING-TO-CROSSING contract the plan exists to establish — losses booked by launch
##     attrition are permanent, they add to the IJFS losses rather than replacing them, and neither
##     is disturbed by a quiet crossing or by the end-of-turn reset.
##
## Everything here drives the real seam the engine uses: FiresPhases applies the IJFS effects, the
## calculator rolls and reports, and AntishipTransitions — the only writer of these rows — books it.


# type 23: p_detect 0.5 * p_destroy_if_detected 0.7 = p_destroy 0.35; p_intercept_before_launch 0.6.
const LAUNCH_CONFIG := {"23": {
	"p_detect": 0.5, "p_destroy_if_detected": 0.7, "p_intercept_before_launch": 0.6}}

## Shot 1: 0.9 >= 0.35            -> launched.
## Shot 2: 0.1 < 0.35, 0.1 < 0.6  -> destroyed before launch (no missile away).
## Shot 3: 0.1 < 0.35, 0.9 >= 0.6 -> destroyed after launch (missile away).
## Shot 4: 0.5 >= 0.35            -> launched.
## Six floats for four shots: the second draw happens ONLY when the first one kills.
const SHOT_FLOATS := [0.9, 0.1, 0.1, 0.1, 0.9, 0.5]


## One (TO, type) row plus the state that carries the arsenal and the crossing identity.
func _state(to_number: int, type_id: int, quantity: int) -> GameStateData:
	var system := AntishipSystem.new()
	system.to_number = to_number
	system.type_id = type_id
	system.quantity = quantity
	system.original_quantity = quantity
	var state := GameStateData.new()
	state.antiship_systems = [system]
	state._antiship_built = true
	return state


func _row(state: GameStateData) -> AntishipSystem:
	return state.antiship_systems[0]


## One whole crossing the way the turn engine runs it: last turn's cleanup has cleared the crossing
## flags, FiresPhases applies the IJFS effects, the calculator rolls, and the authority books what it
## reported. `writeback` null = the IJFS killed nothing.
func _crossing(state: GameStateData, floats: Array, writeback: IjfsWriteback = null) -> Dictionary:
	AntishipTransitions.reset_transient_flags(state.antiship_systems)
	state.turn_number += 1
	AntishipTransitions.apply_ijfs_effects(state.antiship_systems, writeback)
	var plan := AntishipCalculator.build_firing_plan(
		state.antiship_systems, {}, [3], {"3:23": 40.0}, {}, null)
	var dice := ScriptedDice.new([], [], floats)
	var result := AntishipCalculator.resolve_launch_attrition(
		plan["allocation_plan"], plan["destroyed_firing_plan"], LAUNCH_CONFIG, dice)
	AntishipTransitions.apply_launch_attrition(state, result["outcomes"])
	result["dice"] = dice
	return result


# --- 1. one crossing: draw order and reports ----------------------------------------------------

func test_one_crossing_draw_order_and_reports_are_pinned() -> void:
	var result := _crossing(_state(3, 23, 10), SHOT_FLOATS)

	# Exactly six randf() draws for four attempted shots — no more (the queue is empty) and no
	# fewer (a short queue push_errors and returns 0.0, which would change the tallies below).
	var dice: ScriptedDice = result["dice"]
	assert_int(dice._floats.size()).is_equal(0)

	var fired: Array = result["systems_fired"]
	assert_int(fired.size()).is_equal(1)
	assert_int(int(fired[0]["attempted_firing"])).is_equal(4)
	assert_int(int(fired[0]["available_firing"])).is_equal(3)   # shots 1, 3, 4 got a missile away
	assert_int(int(fired[0]["destroyed_firing"])).is_equal(0)
	assert_int(int(fired[0]["systems_fired"])).is_equal(3)
	assert_int(int(fired[0]["prelaunch_destroyed"])).is_equal(1)
	assert_int(int(fired[0]["postlaunch_destroyed"])).is_equal(1)

	var outcomes: Array = result["outcomes"]
	assert_int(outcomes.size()).is_equal(1)
	var outcome: AntishipLaunchOutcome = outcomes[0]
	assert_int(outcome.to_number).is_equal(3)
	assert_int(outcome.type_id).is_equal(23)
	assert_int(outcome.attempted).is_equal(4)
	assert_int(outcome.launched).is_equal(3)
	assert_int(outcome.prelaunch_destroyed).is_equal(1)
	assert_int(outcome.postlaunch_destroyed).is_equal(1)


# --- 2. two crossings: launch losses are permanent ----------------------------------------------

## The behaviour plan 0043 exists to fix, and the test that proves it: two launchers die during
## crossing 1 (one before launch, one after), and crossing 2 must find 8 of the original 10 left, not
## 10. Reintroduce the resurrection and this is the assertion that goes red.
func test_launch_destruction_survives_into_the_next_crossing() -> void:
	var state := _state(3, 23, 10)
	_crossing(state, SHOT_FLOATS)
	assert_int(_row(state).destroyed).is_equal(2)

	# Crossing 2 opens against 8 launchers, not 10, and fires 40% of 8 = 3 shots.
	var result := _crossing(state, [0.9, 0.9, 0.9])
	assert_int(int((result["systems_fired"][0] as Dictionary)["attempted_firing"])).is_equal(3)

	assert_int(_row(state).destroyed).is_equal(2)
	assert_int(_row(state).quantity).is_equal(8)
	assert_int(_row(state).original_quantity).is_equal(10)


## The two loss categories add rather than overwriting each other: 3 launchers killed by the IJFS
## plus 2 killed during launch leaves 5 of 10. The IJFS total is cumulative, so re-reporting the
## same 3 on a later crossing must not subtract them twice.
func test_ijfs_and_launch_losses_accumulate_without_double_counting() -> void:
	var state := _state(3, 23, 10)
	_crossing(state, SHOT_FLOATS)

	var writeback := IjfsWriteback.new()
	writeback.antiship_destroyed_by_type = {"3:23": 3}
	AntishipTransitions.apply_ijfs_effects(state.antiship_systems, writeback)
	assert_int(_row(state).destroyed).is_equal(5)
	assert_int(_row(state).quantity).is_equal(5)

	AntishipTransitions.apply_ijfs_effects(state.antiship_systems, writeback)
	assert_int(_row(state).destroyed).is_equal(5)
	assert_int(_row(state).quantity).is_equal(5)


## A crossing that fires nothing must not disturb the establishment.
func test_crossing_with_no_firing_leaves_the_establishment_untouched() -> void:
	var state := _state(3, 23, 10)
	_crossing(state, SHOT_FLOATS)

	state.turn_number += 1
	AntishipTransitions.apply_ijfs_effects(state.antiship_systems, null)
	var plan := AntishipCalculator.build_firing_plan(
		state.antiship_systems, {}, [3], {"3:23": 0.0}, {}, null)
	assert_array(plan["allocation_plan"]).is_empty()
	var result := AntishipCalculator.resolve_launch_attrition(
		plan["allocation_plan"], plan["destroyed_firing_plan"], LAUNCH_CONFIG,
		ScriptedDice.new([], [], []))
	AntishipTransitions.apply_launch_attrition(state, result["outcomes"])

	assert_int(_row(state).destroyed).is_equal(2)
	assert_int(_row(state).quantity).is_equal(8)


## Cleanup clears the crossing flags and leaves the campaign losses alone.
func test_transient_reset_keeps_campaign_losses() -> void:
	var state := _state(3, 23, 10)
	_crossing(state, SHOT_FLOATS)
	assert_int(_row(state).fired).is_equal(3)

	assert_int(AntishipTransitions.reset_transient_flags(state.antiship_systems)).is_equal(1)

	assert_int(_row(state).fired).is_equal(0)
	assert_int(_row(state).destroyed_this_turn).is_equal(0)
	assert_bool(_row(state).active).is_false()
	assert_int(_row(state).destroyed).is_equal(2)
	assert_int(_row(state).quantity).is_equal(8)


# --- 3. the authority's refusals -----------------------------------------------------------------

## A turn that resolves with no IJFS writeback reports nothing — it does not report zero. Reading an
## absent report as "no launchers have ever been destroyed" would resurrect the whole arsenal.
func test_missing_ijfs_report_leaves_the_cumulative_total_alone() -> void:
	var state := _state(3, 23, 10)
	var writeback := IjfsWriteback.new()
	writeback.antiship_destroyed_by_type = {"3:23": 4}
	AntishipTransitions.apply_ijfs_effects(state.antiship_systems, writeback)
	assert_int(_row(state).quantity).is_equal(6)

	AntishipTransitions.apply_ijfs_effects(state.antiship_systems, null)
	assert_int(_row(state).quantity).is_equal(6)

	AntishipTransitions.apply_ijfs_effects(state.antiship_systems, IjfsWriteback.new())
	assert_int(_row(state).quantity).is_equal(6)


## One crossing per turn: booking the same turn twice would kill every launcher a second time.
func test_applying_the_same_crossing_twice_is_refused() -> void:
	var state := _state(3, 23, 10)
	var result := _crossing(state, SHOT_FLOATS)
	assert_int(_row(state).destroyed).is_equal(2)

	await assert_error(func() -> void:
		AntishipTransitions.apply_launch_attrition(state, result["outcomes"])
	).is_push_error("AntishipTransitions: launch attrition for turn 2 already applied")

	assert_int(_row(state).destroyed).is_equal(2)
	assert_int(_row(state).quantity).is_equal(8)


## An outcome naming a row that does not exist means the calculator and the establishment have drifted
## apart. The whole crossing is refused rather than partly applied.
func test_outcome_for_an_unknown_row_refuses_the_whole_crossing() -> void:
	var state := _state(3, 23, 10)
	var known := AntishipLaunchOutcome.new()
	known.to_number = 3
	known.type_id = 23
	known.attempted = 4
	known.launched = 4
	var unknown := AntishipLaunchOutcome.new()
	unknown.to_number = 9
	unknown.type_id = 5
	unknown.attempted = 1
	unknown.prelaunch_destroyed = 1

	await assert_error(func() -> void:
		AntishipTransitions.apply_launch_attrition(state, [known, unknown])
	).is_push_error("AntishipTransitions: refusing the whole crossing — launch outcome names unknown anti-ship row 9:5")

	# The GOOD row in the same request was not applied either.
	assert_int(_row(state).fired).is_equal(0)
	assert_int(_row(state).quantity).is_equal(10)
	assert_int(state._antiship_launch_turn).is_equal(-1)


## A self-inconsistent report — more launchers destroyed than were ever ordered to fire — is a
## calculator bug, and must not become campaign state.
func test_inconsistent_outcome_is_refused() -> void:
	var state := _state(3, 23, 10)
	var bogus := AntishipLaunchOutcome.new()
	bogus.to_number = 3
	bogus.type_id = 23
	bogus.attempted = 1
	bogus.prelaunch_destroyed = 2

	await assert_error(func() -> void:
		AntishipTransitions.apply_launch_attrition(state, [bogus])
	).is_push_error("AntishipTransitions: refusing the whole crossing — outcome 3:23 destroyed 2 of only 1 attempted")

	assert_int(_row(state).quantity).is_equal(10)


## Cumulative IJFS losses may not move backwards: that would mean the source recomputed history, and
## accepting it would put destroyed launchers back on the line.
func test_ijfs_total_moving_backwards_is_refused() -> void:
	var state := _state(3, 23, 10)
	var writeback := IjfsWriteback.new()
	writeback.antiship_destroyed_by_type = {"3:23": 4}
	AntishipTransitions.apply_ijfs_effects(state.antiship_systems, writeback)

	var shrunk := IjfsWriteback.new()
	shrunk.antiship_destroyed_by_type = {"3:23": 1}
	await assert_error(func() -> void:
		AntishipTransitions.apply_ijfs_effects(state.antiship_systems, shrunk)
	).is_push_error("AntishipTransitions: IJFS losses for 3:23 moved backwards, 4 -> 1")

	assert_int(_row(state).quantity).is_equal(6)


## The two sources count different projections of one arsenal, so their SUM may exceed the
## establishment. That is clamped, not refused — surviving strength simply floors at zero.
func test_losses_from_both_sources_clamp_at_the_establishment() -> void:
	var state := _state(3, 23, 10)
	var writeback := IjfsWriteback.new()
	writeback.antiship_destroyed_by_type = {"3:23": 8}
	AntishipTransitions.apply_ijfs_effects(state.antiship_systems, writeback)

	var outcome := AntishipLaunchOutcome.new()
	outcome.to_number = 3
	outcome.type_id = 23
	outcome.attempted = 5
	outcome.prelaunch_destroyed = 5
	state.turn_number += 1
	AntishipTransitions.apply_launch_attrition(state, [outcome])

	assert_int(_row(state).ijfs_destroyed_cumulative).is_equal(8)
	assert_int(_row(state).launch_destroyed_cumulative).is_equal(5)
	assert_int(_row(state).destroyed).is_equal(10)
	assert_int(_row(state).quantity).is_equal(0)
	assert_str(_row(state).establishment_error()).is_equal("")
