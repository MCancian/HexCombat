extends GdUnitTestSuite

## Plan 0046 step 1 — characterization. These pin the IJFS campaign-state behaviours the plan is
## about to route through `IjfsTransitions`, BEFORE any of them moves. A refactor that changes one of
## these changes the game, and the golden fixtures would only tell you afterwards.
##
## What is deliberately NOT re-tested here: strike/SEAD/MANPADS mechanics already covered by
## ijfs_strike_test, ijfs_engagement_test, ijfs_manpads_test and ijfs_maneuver_sync_test. This suite
## covers only the seams those suites leave open — the ones the authority is about to own.


# --- 1. the strike package's availability arithmetic ---------------------------------------------
# Plan 0060 R8 made an Organic strike cost four REAL airframes drawn from real squadrons, and gave
# `rtb_today` its first runtime writer after a year with none. The invariant that has to survive: an
# airframe is committed at most once a day, by exactly one route.

const MANPADS_TO := 2
const STOCK := 500          # == IjfsManpads.SATURATION_SYSTEMS, so threat_fraction is exactly 1.0


func test_availability_subtracts_both_per_day_ledgers() -> void:
	var squadron := _squadron("sq1", 10)
	assert_int(squadron.available_today()).is_equal(10)

	IjfsTransitions.book_rtb(squadron, 3)
	assert_int(squadron.available_today()).is_equal(7)
	IjfsTransitions.assign_to_sead(squadron, 2)
	assert_int(squadron.available_today()).override_failure_message(
		"an airframe home for the day and one booked to SEAD are both unavailable"
	).is_equal(5)
	assert_int(squadron.alive).override_failure_message(
		"neither ledger is a loss — the airframes are alive").is_equal(10)


func test_neither_availability_ledger_can_overcommit_a_squadron() -> void:
	var squadron := _squadron("sq1", 4)
	IjfsTransitions.book_rtb(squadron, 4)
	assert_error(func() -> void: IjfsTransitions.book_rtb(squadron, 1)).is_push_error(
		"IjfsTransitions: sq1 sent 1 home with only 0 available today")
	assert_error(func() -> void: IjfsTransitions.assign_to_sead(squadron, 1)).is_push_error(
		"IjfsTransitions: sq1 assigned 1 to SEAD with only 0 available today")
	assert_int(squadron.rtb_today).is_equal(4)
	assert_int(squadron.sead_assigned_today).is_equal(0)


func test_package_assembly_never_reuses_an_airframe_or_overdraws_the_pool() -> void:
	var small := _squadron("sq_small", 1)
	var big := _squadron("sq_big", 3)
	# Exactly four available airframes, so the package must take BOTH of sq_small's... it has one.
	var members := IjfsAirPackage.reserve([small, big], 4, ScriptedDice.new([], [], [0.0, 0.0, 0.0, 0.0]))
	assert_int(members.size()).is_equal(4)
	var counts: Dictionary = {}
	for squadron in members:
		counts[squadron.squadron_id] = int(counts.get(squadron.squadron_id, 0)) + 1
	assert_int(int(counts["sq_small"])).override_failure_message(
		"a 1-airframe squadron cannot supply two slots of one package").is_equal(1)
	assert_int(int(counts["sq_big"])).is_equal(3)

	# One airframe home for the day leaves three, and three cannot man a four-ship package.
	IjfsTransitions.book_rtb(big, 1)
	assert_array(IjfsAirPackage.reserve([small, big], 4, ScriptedDice.new([], [], [0.0, 0.0, 0.0]))
		).override_failure_message("a short package must not launch at all").is_empty()


# --- 2. squadron counters: what the names promise vs what the code does --------------------------
# Since 2026-08-01 the two loss counters have two lifetimes (USER call): `losses_today` is genuinely
# per-day, zeroed by carry_to_next_day at the head of each day, and `losses_campaign` is the running
# total it used to carry under the wrong name. Both ship in the air_oob_after ledger, which is
# model_version 4 for that reason. `rtb_today` still has no runtime writer — plan 0059 is the mechanic
# that would give it one, and until that lands a writer appearing here is a bug.
#
# NOTE the state below MUST carry the force. An earlier version of this test built an IjfsDailyState
# with targets only, so carry_to_next_day had no squadrons to touch and the test would have passed
# whether or not the reset existed.

func test_losses_today_resets_each_day_while_losses_campaign_accumulates() -> void:
	var squadron := _squadron("sq1", 10)
	var force: Array[IjfsSquadron] = [squadron]
	var state := IjfsDailyState.new()
	state.targets = []
	state.squadron_force = force

	# Day 1: one guaranteed loss (p_loss > 0, roll 0.0).
	IjfsEngagement.apply_post_phase_2_free_shot(force, IjfsAttritionProfile.build(null, null), 1.0, _one_hit_then_misses(10))
	var day_1_losses := squadron.losses_today
	assert_int(day_1_losses).is_greater(0)
	assert_int(squadron.losses_campaign).is_equal(day_1_losses)

	# The day boundary clears the per-day counter and leaves the campaign total alone.
	IjfsEngine.carry_to_next_day(state)
	assert_int(squadron.losses_today).override_failure_message(
		"carry_to_next_day must zero losses_today, or the ledger's daily number reports the campaign"
	).is_equal(0)
	assert_int(squadron.losses_campaign).override_failure_message(
		"losses_campaign must survive the day boundary — it is the running total"
	).is_equal(day_1_losses)

	# Day 2: the per-day counter starts from zero again, the campaign total keeps climbing.
	IjfsEngagement.apply_post_phase_2_free_shot(force, IjfsAttritionProfile.build(null, null), 1.0, _one_hit_then_misses(squadron.alive))
	assert_int(squadron.losses_today).is_greater(0)
	assert_int(squadron.losses_today).override_failure_message(
		"day 2's per-day count must not include day 1's losses"
	).is_less(squadron.losses_campaign)
	assert_int(squadron.alive).is_equal(squadron.initial - squadron.losses_campaign)


func test_the_day_boundary_clears_both_availability_ledgers() -> void:
	var squadron := _squadron("sq1", 10)
	var force: Array[IjfsSquadron] = [squadron]
	var state := IjfsDailyState.new()
	state.targets = []
	state.squadron_force = force

	IjfsTransitions.book_rtb(squadron, 2)
	IjfsTransitions.assign_to_sead(squadron, 3)

	IjfsEngine.carry_to_next_day(state)

	assert_int(squadron.rtb_today).override_failure_message(
		"an airframe driven home yesterday flies again today").is_equal(0)
	assert_int(squadron.sead_assigned_today).override_failure_message(
		"leaving SEAD assignments set would retire the whole air force over a campaign").is_equal(0)
	assert_int(squadron.available_today()).is_equal(10)


# --- 3. the typed MANPADS stock and its serialization mirror ------------------------------------
# Plan 0046 commit 3 moved the stock out of the free-form `metadata` dictionary, where the mutation
# gate could not see it, onto `IjfsTarget.manpads_remaining`. `metadata["systems_remaining"]`
# survives as a MIRROR only, because metadata is aliased live into the ledger rows.

func test_typed_stock_and_metadata_mirror_never_disagree() -> void:
	var bin := _target("m1", IjfsManpads.CATEGORY)
	bin.metadata = {"to_number": MANPADS_TO, "systems_represented": STOCK}
	var targets: Array[IjfsTarget] = [bin]

	assert_int(bin.manpads_remaining).override_failure_message(
		"stock is unseeded until seed_manpads runs — the sentinel survives a pure read").is_equal(-1)
	assert_int(IjfsManpads.systems_remaining(bin)).is_equal(STOCK)
	assert_int(bin.manpads_remaining).override_failure_message(
		"systems_remaining is now a pure read — it must NOT write the field").is_equal(-1)

	# seed_manpads is the day-boundary call that stamps the typed field.
	IjfsManpads.seed_manpads(targets)
	assert_int(bin.manpads_remaining).is_equal(STOCK)
	assert_int(bin.metadata["systems_remaining"]).is_equal(STOCK)

	IjfsManpads.expend(targets, MANPADS_TO, 7)

	assert_int(bin.manpads_remaining).is_equal(STOCK - 7)
	assert_int(bin.metadata["systems_remaining"]).override_failure_message(
		"the mirror is what the ledger serializes; it must track the typed field exactly"
	).is_equal(STOCK - 7)
	assert_int(bin.to_dict()["metadata"]["systems_remaining"]).is_equal(STOCK - 7)


func test_a_bin_rebuilt_from_its_dict_keeps_its_depleted_stock() -> void:
	var bin := _target("m1", IjfsManpads.CATEGORY)
	bin.metadata = {"to_number": MANPADS_TO, "systems_represented": STOCK}
	var targets: Array[IjfsTarget] = [bin]
	IjfsManpads.expend(targets, MANPADS_TO, 400)

	# A target rebuilt mid-campaign carries its stock in metadata and its typed field unseeded. The
	# declarative systems_represented must NOT win, or a round-trip silently refills every bin.
	var rebuilt := IjfsLoaders._target_from_dict(bin.to_dict())

	assert_int(rebuilt.manpads_remaining).is_equal(-1)
	assert_int(IjfsManpads.systems_remaining(rebuilt)).override_failure_message(
		"a round-tripped bin must resume from its remaining stock, not from systems_represented"
	).is_equal(STOCK - 400)


# --- 4. destruction is monotonic across every reset path ----------------------------------------

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
