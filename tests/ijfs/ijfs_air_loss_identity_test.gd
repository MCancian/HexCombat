extends GdUnitTestSuite

# The accounting identity plan 0060 R10 demands: over a real day, the air force's total shrinkage
# equals the losses the three attrition ledgers claim — SAM return fire + MANPADS kills + the
# post-phase-2 free shot — and nothing else.
#
# This is the check the plan's own measurement section says to make FIRST and not to skip. Its
# 2026-08-01 predecessor reported a mismatch that turned out to be a flaw in the CHECK (the baseline
# was sampled before the lazily-built IJFS state existed, so it read 0), which is exactly why the
# identity is worth having as a test rather than as a one-off script.

const DATA := "res://data/ijfs/"
const SEED := 20260801
const DAYS := 6


func _state() -> IjfsDailyState:
	var state := IjfsDailyState.new()
	state.targets = IjfsLoaders.load_targets(DATA + "targets_master.json", 1)
	state.munitions = IjfsLoaders.load_munitions(DATA + "red_munitions.json")
	state.pairings = IjfsLoaders.load_pairings(DATA + "munition_target_pairings.json")
	state.scenario = IjfsLoaders.load_scenario(DATA + "ijfs_scenario.json")
	state.air_classes = IjfsLoaders.load_air_classes(DATA + "air_classes.json")
	state.squadron_force = IjfsLoaders.expand_oob_to_squadrons(
		IjfsLoaders.load_oob(DATA + "red_air_oob.json"))
	IjfsLoaders.enrich_sam_scores(state.targets, IjfsLoaders.load_sam_capabilities(DATA + "sam_capabilities.json"))
	state.seed = SEED
	return state


func _alive(state: IjfsDailyState) -> int:
	var total := 0
	for squadron: IjfsSquadron in (state.squadron_force as Array):
		total += squadron.alive
	return total


func _sum_losses(log: Array) -> int:
	var total := 0
	for entry in log:
		total += int(entry.get("losses", 0))
	return total


func test_total_air_shrinkage_equals_the_sum_of_the_three_attrition_ledgers() -> void:
	var state := _state()
	var initial := _alive(state)
	assert_int(initial).override_failure_message(
		"the shipped OOB is the 498-airframe force every plan 0060 calibration is fitted against"
	).is_equal(498)

	var claimed := 0
	for day in range(1, DAYS + 1):
		if day > 1:
			IjfsEngine.carry_to_next_day(state)
		var ledgers := IjfsEngine.run_daily(state, SeededDice.new(SEED + day), day)
		claimed += _sum_losses(ledgers["contest_log"])
		claimed += _sum_losses(ledgers["manpads_intercept_log"])
		claimed += _sum_losses(ledgers["free_shot_log"])

	assert_int(initial - _alive(state)).override_failure_message(
		"every airframe that left the OOB must be claimed by exactly one ledger row"
	).is_equal(claimed)


func test_rtb_and_sead_assignment_never_shrink_the_force() -> void:
	var state := _state()
	var initial := _alive(state)
	var campaign_losses := 0
	for day in range(1, DAYS + 1):
		if day > 1:
			IjfsEngine.carry_to_next_day(state)
		IjfsEngine.run_daily(state, SeededDice.new(SEED + day), day)
	for squadron: IjfsSquadron in (state.squadron_force as Array):
		campaign_losses += squadron.losses_campaign
		assert_int(squadron.alive).override_failure_message(
			"%s ended below zero or above its establishment" % squadron.squadron_id
		).is_between(0, squadron.initial)
		assert_int(squadron.rtb_today + squadron.sead_assigned_today).override_failure_message(
			"%s committed more airframes today than it has alive" % squadron.squadron_id
		).is_less_equal(squadron.alive)
	assert_int(initial - _alive(state)).override_failure_message(
		"an airframe driven home or assigned to SEAD is unavailable, not lost"
	).is_equal(campaign_losses)
