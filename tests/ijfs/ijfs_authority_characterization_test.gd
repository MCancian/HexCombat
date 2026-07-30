extends GdUnitTestSuite

## Plan 0046 step 1 — characterization. These pin the IJFS campaign-state behaviours the plan is
## about to route through `IjfsTransitions`, BEFORE any of them moves. A refactor that changes one of
## these changes the game, and the golden fixtures would only tell you afterwards.
##
## What is deliberately NOT re-tested here: strike/SEAD/MANPADS mechanics already covered by
## ijfs_strike_test, ijfs_engagement_test, ijfs_manpads_test and ijfs_maneuver_sync_test. This suite
## covers only the seams those suites leave open — the ones the authority is about to own.


# --- 1. the SECOND munition decrement path -------------------------------------------------------
# IjfsStrike.gd:124 is the well-covered one. IjfsEngine.gd:218 — the round spent on a strike MANPADS
# intercepted, which delivers nothing — has no test at all, and plan 0046 routes both through one
# authority method. The invariant that must survive that: exactly `rounds` leave the magazine per
# engagement, intercepted or not.

const MANPADS_TO := 2
const STOCK := 500          # == IjfsManpads.SATURATION_SYSTEMS, so threat_fraction is exactly 1.0
const ROUNDS := 4
const START_INVENTORY := 40

## p_intercept = threat_fraction(500) * INTERCEPT_FACTOR * vulnerability = 1.0 * 0.15 * 1.0.
const P_INTERCEPT := 0.15


func test_intercepted_strike_spends_the_round_and_delivers_nothing() -> void:
	var state := _strike_state()
	var dice := ScriptedDice.new([], [], [P_INTERCEPT - 0.05])   # <= p_intercept -> intercepted

	_run_phase(state, dice)

	assert_int(_munition(state).inventory_remaining).override_failure_message(
		"an intercepted strike must still spend its rounds").is_equal(START_INVENTORY - ROUNDS)
	assert_int(dice._floats.size()).override_failure_message(
		"interception must consume exactly one draw and then stop").is_equal(0)

	assert_int(state.manpads_intercept_log.size()).is_equal(1)
	assert_bool(state.manpads_intercept_log[0]["intercepted"]).is_true()

	assert_int(state.strike_log.size()).is_equal(1)
	var row: Dictionary = state.strike_log[0]
	assert_bool(row["attack_executed"]).is_true()
	assert_bool(row["destroyed"]).is_false()
	assert_bool(row["intercepted_by_manpads"]).is_true()
	assert_int(row["rounds_expended"]).is_equal(ROUNDS)


func test_surviving_strike_spends_the_same_round_exactly_once() -> void:
	var state := _strike_state()
	# 0.9 > p_intercept -> not intercepted; then resolve_strike's destroy roll (p_destroy 1.0 always
	# destroys, so no suppression roll follows).
	var dice := ScriptedDice.new([], [], [0.9, 0.5])

	_run_phase(state, dice)

	assert_int(_munition(state).inventory_remaining).override_failure_message(
		"the round must be deducted exactly once, by resolve_strike rather than the engine"
	).is_equal(START_INVENTORY - ROUNDS)
	assert_int(dice._floats.size()).is_equal(0)
	assert_bool(state.strike_log[0]["destroyed"]).is_true()


func test_interception_attempt_drains_manpads_stock_whether_or_not_it_hits() -> void:
	for roll in [P_INTERCEPT - 0.05, 0.9]:
		var state := _strike_state()
		_run_phase(state, ScriptedDice.new([], [], [roll, 0.5]))
		assert_int(IjfsManpads.systems_remaining(_manpads_bin(state))).override_failure_message(
			"launchers are expended on the attempt, not on the hit (roll %s)" % roll
		).is_equal(STOCK - IjfsManpads.EXPEND_PER_INTERCEPT)


# --- 2. squadron counters: what the names promise vs what the code does --------------------------
# `losses_today` is never reset anywhere (carry_to_next_day touches targets only), so it is a
# CAMPAIGN-cumulative total wearing a per-day name — and it is serialized into the air_oob_after
# ledger, which makes changing it a golden-touching decision rather than a rename. `rtb_today` has no
# runtime writer at all. Plan 0046 must preserve both exactly; these tests are what say so.

func test_losses_today_accumulates_across_days_and_is_never_reset() -> void:
	var squadron := _squadron("sq1", 10)
	var force: Array[IjfsSquadron] = [squadron]

	# Two "days" of free-shot attrition, one guaranteed loss each (p_loss > 0, roll 0.0).
	IjfsEngagement.apply_post_phase_2_free_shot(force, null, 1.0, _one_hit_then_misses(10))
	var after_day_1 := squadron.losses_today
	assert_int(after_day_1).is_greater(0)

	var state := IjfsDailyState.new()
	state.targets = []
	IjfsEngine.carry_to_next_day(state)

	IjfsEngagement.apply_post_phase_2_free_shot(force, null, 1.0, _one_hit_then_misses(squadron.alive))

	assert_int(squadron.losses_today).override_failure_message(
		"losses_today is cumulative; a reset here would silently rewrite the air_oob_after ledger"
	).is_greater(after_day_1)
	assert_int(squadron.alive).is_equal(squadron.initial - squadron.losses_today)


func test_rtb_today_has_no_runtime_writer() -> void:
	var squadron := _squadron("sq1", 10)
	var force: Array[IjfsSquadron] = [squadron]

	IjfsEngagement.apply_post_phase_2_free_shot(force, null, 1.0, _one_hit_then_misses(10))
	IjfsManpads.contest_squadrons(_manpads_only_targets(), force, null, _one_hit_then_misses(squadron.alive))

	assert_int(squadron.rtb_today).override_failure_message(
		"nothing in the pipeline writes rtb_today; the authority must not grow a mutator for it"
	).is_equal(0)


# --- 3. destruction is monotonic across every reset path ----------------------------------------

func test_destruction_survives_carry_over_and_maneuver_sync() -> void:
	var state := IjfsDailyState.new()
	var dead := _target("mu#1", "Maneuver Units")
	dead.destroyed = true
	dead.metadata = {"brigade_id": "BDE1", "unit_type": "inf"}
	var live := _target("mu#2", "Maneuver Units")
	live.suppressed = true
	live.suppressed_this_turn = true
	live.sead_result = "suppressed"
	live.metadata = {"brigade_id": "BDE1", "unit_type": "inf"}
	state.targets = [dead, live]

	IjfsEngine.carry_to_next_day(state)

	assert_bool(dead.destroyed).override_failure_message("carry-over must not resurrect").is_true()
	assert_bool(live.suppressed).is_false()
	assert_str(live.sead_result).is_equal("")

	# A sync against a brigade that still fields one battalion of this type must leave the live
	# target alone and must not revive the dead one.
	var brigade := Brigade.new()
	brigade.id = "BDE1"
	var battalion := Battalion.new()
	battalion.type = "inf"
	battalion.qty = 1
	brigade.composition = [battalion]
	IjfsResolver.sync_maneuver_targets_to_oob(state, {"BDE1": brigade})

	assert_bool(dead.destroyed).is_true()
	assert_bool(live.destroyed).override_failure_message(
		"one surviving battalion must keep exactly one live target").is_false()


# --- helpers ------------------------------------------------------------------------------------

## One attackable AD target in TO 2, one MANPADS bin in the same TO, and a vulnerable munition —
## the minimum state that reaches IjfsEngine's interception branch.
func _strike_state() -> IjfsDailyState:
	var state := IjfsDailyState.new()
	state.scenario = {"strike_probability_modifiers": [], "targeting_doctrine": []}

	var victim := _target("t1", "Air Defense Systems")
	victim.metadata = {"to_number": MANPADS_TO}
	var bin := _target("z_manpads1", IjfsManpads.CATEGORY)
	bin.metadata = {"to_number": MANPADS_TO, "systems_represented": STOCK}
	state.targets = [victim, bin]

	var munition := IjfsMunition.new()
	munition.munition_id = "owa"
	munition.category = "Inorganic-Slow"
	munition.inventory_remaining = START_INVENTORY
	munition.rounds_per_engagement_default = ROUNDS
	munition.manpads_vulnerability = 1.0
	state.munitions = {"owa": munition}

	var pairing := IjfsPairing.new()
	pairing.pairing_id = "owa_vs_ad"
	pairing.munition_id = "owa"
	pairing.target_category = "Air Defense Systems"   # deliberately does NOT match the MANPADS bin
	pairing.rounds_expended_per_engagement = ROUNDS
	pairing.probability_destroyed = 1.0
	pairing.probability_suppressed_if_not_destroyed = 0.0
	var pairings: Array[IjfsPairing] = [pairing]
	state.pairings = pairings
	return state


func _run_phase(state: IjfsDailyState, dice: Dice) -> void:
	var ctx := IjfsStrikePhaseContext.new()
	ctx.current_day = 1
	IjfsEngine._run_strike_phase(state, ctx, IjfsEngine.PRE_AD_PHASE, dice)


func _munition(state: IjfsDailyState) -> IjfsMunition:
	return state.munitions["owa"]


func _manpads_bin(state: IjfsDailyState) -> IjfsTarget:
	for target in state.targets:
		if target.category == IjfsManpads.CATEGORY:
			return target
	return null


func _manpads_only_targets() -> Array[IjfsTarget]:
	var bin := _target("m1", IjfsManpads.CATEGORY)
	bin.metadata = {"to_number": MANPADS_TO, "systems_represented": STOCK}
	var targets: Array[IjfsTarget] = [bin]
	return targets


func _target(id: String, category: String) -> IjfsTarget:
	var target := IjfsTarget.new()
	target.target_id = id
	target.source_target_id = id
	target.category = category
	target.mobility = "static"
	target.hardness = "soft"
	target.detected_this_turn = true
	target.known_to_red = true
	return target


func _squadron(id: String, alive: int) -> IjfsSquadron:
	var squadron := IjfsSquadron.new()
	squadron.squadron_id = id
	squadron.aircraft_class = "4th Gen"
	squadron.role = "strike"
	squadron.initial = alive
	squadron.alive = alive
	return squadron


## One guaranteed hit, then misses for the remaining alive aircraft — a bernoulli draw per airframe.
func _one_hit_then_misses(trials: int) -> ScriptedDice:
	var floats: Array = [0.0]
	for _i in range(maxi(0, trials - 1)):
		floats.append(1.0)
	return ScriptedDice.new([], [], floats)
