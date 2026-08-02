extends GdUnitTestSuite

# What a SAM does on both sides of the exchange: being engaged, and shooting back. The ORCHESTRATION
# of who engages what moved to IjfsSeadStage on 2026-08-01 (plan 0060 R11) and is covered by
# ijfs_sead_stage_test; these cases pin the per-target and per-airframe arithmetic both stages share.
#
# Uses the shared ScriptedDice helper; scripted randf() draws are its 3rd ctor arg. Draw order: an
# engagement draws a destroy roll then a suppression roll only on survival; return-fire / free-shot
# loops draw once per alive aircraft in squadron (force) order.

const AIR_CLASSES := {"classes": {"X": {"sead_eff": 1.0, "wvr": 0.0, "rcs": 0.0}}}
## Neutral exposure for every role, so the cases below assert the RCS-only arithmetic they were
## written against; role exposure gets its own suite (ijfs_attrition_profile_test).
const NEUTRAL_ROLES := {"red_aircraft_attrition_and_sead":
	{"role_exposure_multipliers": {"isr": 1.0, "sead": 1.0, "strike": 1.0}}}


func _profile() -> IjfsAttritionProfile:
	return IjfsAttritionProfile.build(NEUTRAL_ROLES, AIR_CLASSES)


func _sam(id: String, sam_score: int) -> IjfsTarget:
	var target := IjfsTarget.new()
	target.target_id = id
	target.category = "Static SAMs"
	target.subcategory = "SAM"
	target.sam_score = sam_score
	return target


func _squadron(id: String, alive: int, role: String = "sead") -> IjfsSquadron:
	var squadron := IjfsSquadron.new()
	squadron.squadron_id = id
	squadron.aircraft_class = "X"
	squadron.role = role
	squadron.initial = alive
	squadron.alive = alive
	return squadron


# --- one SAM being engaged ----------------------------------------------------------------------

func test_engagement_destroys_the_target_when_the_roll_is_below_p_destroy() -> void:
	var target := _sam("t1", 10)
	# power 10 vs sam_score 10 -> p_destroy = 10/20 = 0.5; roll 0.4 destroys, and a destroyed target
	# draws no suppression roll.
	var dice := ScriptedDice.new([], [], [0.4])
	var row := IjfsEngagement.engage_sam_target(target, 10.0, dice)
	assert_float(row["p_destroy"]).is_equal_approx(0.5, 0.000001)
	assert_bool(row["destroyed"]).is_true()
	assert_str(target.sead_result).is_equal("destroyed")
	assert_bool(target.destroyed).is_true()
	assert_int(dice._floats.size()).is_equal(0)


func test_a_survivor_draws_a_suppression_roll() -> void:
	var target := _sam("t1", 10)
	# survive (0.6 > 0.5); p_suppress = 0.5 * 0.4 = 0.2; supp roll 0.1 <= 0.2 -> suppressed.
	var dice := ScriptedDice.new([], [], [0.6, 0.1])
	var row := IjfsEngagement.engage_sam_target(target, 10.0, dice)
	assert_bool(row["destroyed"]).is_false()
	assert_bool(row["suppressed"]).is_true()
	assert_float(row["p_suppress"]).is_equal_approx(0.2, 0.000001)
	assert_str(target.sead_result).is_equal("suppressed")
	assert_int(dice._floats.size()).is_equal(0)


func test_a_missed_target_is_marked_unengaged() -> void:
	var target := _sam("t1", 10)
	var row := IjfsEngagement.engage_sam_target(target, 10.0, ScriptedDice.new([], [], [0.6, 0.9]))
	assert_bool(row["destroyed"]).is_false()
	assert_bool(row["suppressed"]).is_false()
	assert_str(target.sead_result).is_equal("unengaged")


# --- surviving SAMs shooting back ---------------------------------------------------------------

func test_unsuppressed_survivors_return_fire_on_every_alive_airframe() -> void:
	var targets: Array[IjfsTarget] = [_sam("t1", 10)]
	var squadron := _squadron("sq1", 10)
	var force: Array[IjfsSquadron] = [squadron]
	# surviving_sam_score 10 -> loss_rate clamp(10 * 0.02) = 0.2; rcs 0 -> no modifier.
	# Ten draws, one per airframe; the first two are hits.
	var dice := ScriptedDice.new([], [], [0.1, 0.1, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5])
	var log := IjfsEngagement.sead_return_fire(force, _profile(), targets, dice)
	assert_int(log.size()).is_equal(1)
	assert_int(log[0]["losses"]).is_equal(2)
	assert_str(log[0]["source"]).is_equal("sead_return_fire")
	assert_int(squadron.alive).is_equal(8)
	assert_int(squadron.losses_today).is_equal(2)
	assert_int(dice._floats.size()).is_equal(0)


func test_a_destroyed_or_suppressed_network_shoots_at_nothing() -> void:
	var destroyed := _sam("t1", 10)
	destroyed.destroyed = true
	var suppressed := _sam("t2", 10)
	suppressed.suppressed = true
	var targets: Array[IjfsTarget] = [destroyed, suppressed]
	var force: Array[IjfsSquadron] = [_squadron("sq1", 10)]
	assert_array(IjfsEngagement.sead_return_fire(
		force, _profile(), targets, ScriptedDice.new([], [], []))).is_empty()


func test_null_force_returns_no_return_fire() -> void:
	var targets: Array[IjfsTarget] = [_sam("t1", 10)]
	assert_array(IjfsEngagement.sead_return_fire(
		null, _profile(), targets, ScriptedDice.new([], [], []))).is_empty()


# --- the post-phase-2 free shot -----------------------------------------------------------------

func test_free_shot_attrition() -> void:
	var squadron := _squadron("sq1", 10)
	var force: Array[IjfsSquadron] = [squadron]
	# raw_sam_health 0.5 -> loss_rate clamp(0.5 * 0.05) = 0.025; rcs 0 -> p_loss 0.025.
	var dice := ScriptedDice.new([], [], [0.01, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5])
	var log := IjfsEngagement.apply_post_phase_2_free_shot(force, _profile(), 0.5, dice)
	assert_int(log.size()).is_equal(1)
	assert_int(log[0]["losses"]).is_equal(1)
	assert_int(squadron.alive).is_equal(9)
	assert_int(dice._floats.size()).is_equal(0)


func test_free_shot_skipped_when_no_sam_health() -> void:
	var squadron := _squadron("sq1", 10)
	var force: Array[IjfsSquadron] = [squadron]
	var log := IjfsEngagement.apply_post_phase_2_free_shot(
		force, _profile(), 0.0, ScriptedDice.new([], [], []))
	assert_array(log).is_empty()
	assert_int(squadron.alive).is_equal(10)
