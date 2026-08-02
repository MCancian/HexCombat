extends GdUnitTestSuite

# Plan 0060 R5/R8: what a four-airframe package meets between the ramp and the target, and what the
# strike log says afterwards. Three outcomes have to stay distinguishable — the strike pressed at
# reduced effect, MANPADS denied it, or it never launched for want of airframes — because they cost
# Red different things.

const CLASS_NAME := "Manned"
const AIR_CLASSES := {"classes": {CLASS_NAME: {"kind": "manned", "rcs": 0, "wvr": 0, "isr_value": 0.4, "sead_eff": 0}}}
const MUNITION := "strike_aircraft_medium"
const TO := 2
const STOCK := 500   # == SATURATION_SYSTEMS, so threat_fraction is 1.0


func _state(kill_factor: float, alive: int) -> IjfsDailyState:
	var state := IjfsDailyState.new()
	var bin := IjfsTarget.new()
	bin.target_id = "m1"
	bin.category = IjfsManpads.CATEGORY
	bin.metadata = {"to_number": TO, "systems_represented": STOCK}
	var targets: Array[IjfsTarget] = [bin]
	state.targets = targets

	var munition := IjfsMunition.new()
	munition.munition_id = MUNITION
	munition.category = "Organic"
	munition.manpads_vulnerability = 1.0
	munition.rounds_per_engagement_default = 4
	state.munitions = {MUNITION: munition}

	var squadron := IjfsSquadron.new()
	squadron.squadron_id = "sq1"
	squadron.aircraft_class = CLASS_NAME
	squadron.role = "strike"
	squadron.initial = alive
	squadron.alive = alive
	state.squadron_force = [squadron]
	state.air_classes = AIR_CLASSES
	state.scenario = {
		"red_aircraft_attrition_and_sead": {
			"role_exposure_multipliers": {"isr": 1.0, "sead": 1.0, "strike": 1.0}},
		"red_firing_capacity": {MUNITION: {
			"firing_units": 36, "sorties_per_unit_per_day": 0.8, "platform_type": "aircraft",
			"attrition_link": [CLASS_NAME], "package_size": 4, "manpads_eligible": true}},
	}
	state.scenario[IjfsManpads.KILL_FACTOR_KNOB] = kill_factor
	return state


func _maneuver(id: String, to_number: int) -> IjfsTarget:
	var target := IjfsTarget.new()
	target.target_id = id
	target.source_target_id = id
	target.category = "Maneuver Units"
	target.metadata = {"to_number": to_number}
	return target


func _ctx(state: IjfsDailyState, dice: Dice) -> IjfsStrikePhaseContext:
	var ctx := IjfsStrikePhaseContext.new()
	ctx.current_day = 1
	ctx.attrition = IjfsAttritionProfile.build(state.scenario, AIR_CLASSES)
	ctx.air_engagement_dice = dice
	return ctx


func test_assemble_produces_a_four_airframe_package_bound_to_its_target() -> void:
	var state := _state(0.0, 24)
	var target := _maneuver("mu1", TO)
	var package: Variant = IjfsPackageIngress.assemble(
		state, MUNITION, target, 0, ScriptedDice.new([], [], [0.0, 0.0, 0.0, 0.0]))
	assert_that(package).is_not_null()
	assert_int((package as IjfsAirPackage).size()).is_equal(4)
	assert_str((package as IjfsAirPackage).target_id).is_equal("mu1")
	assert_int((package as IjfsAirPackage).to_number).is_equal(TO)


func test_assemble_returns_null_when_the_linked_pool_is_too_thin() -> void:
	var state := _state(0.0, 3)
	assert_that(IjfsPackageIngress.assemble(
		state, MUNITION, _maneuver("mu1", TO), 0, ScriptedDice.new([], [], [0.0, 0.0, 0.0]))
	).override_failure_message("three airframes cannot man a four-ship package").is_null()


func test_assemble_returns_null_for_a_munition_with_no_attrition_link() -> void:
	var state := _state(0.0, 24)
	assert_that(IjfsPackageIngress.assemble(
		state, "cj10_lacm_glcm", _maneuver("mu1", TO), 0, ScriptedDice.new([], [], []))).is_null()


func test_a_killed_member_presses_at_reduced_effect() -> void:
	var state := _state(0.5, 24)
	var target := _maneuver("mu1", TO)
	var dice := ScriptedDice.new([], [], [0.0, 0.0, 0.0, 0.0, 0.05])
	var package: IjfsAirPackage = IjfsPackageIngress.assemble(state, MUNITION, target, 0, dice)
	var ingress := IjfsPackageIngress.fly_in(state, package, target, _ctx(state, dice), dice)
	assert_str(ingress["outcome"]).is_equal(IjfsPackageIngress.OUTCOME_PRESSED)
	assert_float(ingress["survivor_fraction"]).is_equal_approx(0.75, 0.000001)
	assert_int(state.manpads_intercept_log.size()).is_equal(1)
	assert_str(state.manpads_intercept_log[0]["outcome"]).is_equal(IjfsManpads.OUTCOME_KILLED)


func test_an_abort_denies_the_strike_and_books_every_survivor_home() -> void:
	var state := _state(0.0, 24)
	var target := _maneuver("mu1", TO)
	var dice := ScriptedDice.new([], [], [0.0, 0.0, 0.0, 0.0, 0.025])
	var package: IjfsAirPackage = IjfsPackageIngress.assemble(state, MUNITION, target, 0, dice)
	var ingress := IjfsPackageIngress.fly_in(state, package, target, _ctx(state, dice), dice)
	assert_str(ingress["outcome"]).is_equal(IjfsPackageIngress.OUTCOME_ABORTED)
	var squadron: IjfsSquadron = (state.squadron_force as Array)[0]
	assert_int(squadron.rtb_today).is_equal(4)
	assert_int(squadron.alive).is_equal(24)


func test_a_strike_on_anything_but_a_maneuver_unit_draws_no_manpads_die() -> void:
	var state := _state(0.5, 24)
	var sam := IjfsTarget.new()
	sam.target_id = "sam1"
	sam.source_target_id = "sam1"
	sam.category = "Moveable SAMs"
	sam.metadata = {"to_number": TO}
	var dice := ScriptedDice.new([], [], [0.0, 0.0, 0.0, 0.0])
	var package: IjfsAirPackage = IjfsPackageIngress.assemble(state, MUNITION, sam, 0, dice)
	var ingress := IjfsPackageIngress.fly_in(state, package, sam, _ctx(state, dice), dice)
	assert_str(ingress["outcome"]).is_equal(IjfsPackageIngress.OUTCOME_PRESSED)
	assert_array(state.manpads_intercept_log).is_empty()
	assert_int(dice._floats.size()).override_failure_message(
		"an ineligible target must consume no MANPADS draw at all").is_equal(0)


func test_ad_attrition_disabled_flies_the_package_through_untouched() -> void:
	var state := _state(0.5, 24)
	var target := _maneuver("mu1", TO)
	var dice := ScriptedDice.new([], [], [0.0, 0.0, 0.0, 0.0])
	var package: IjfsAirPackage = IjfsPackageIngress.assemble(state, MUNITION, target, 0, dice)
	var ctx := _ctx(state, dice)
	ctx.ad_attrition_enabled = false
	var ingress := IjfsPackageIngress.fly_in(state, package, target, ctx, dice)
	assert_str(ingress["outcome"]).is_equal(IjfsPackageIngress.OUTCOME_PRESSED)
	assert_array(state.manpads_intercept_log).is_empty()


func test_denied_strike_log_records_a_spent_sortie_that_delivered_nothing() -> void:
	var pairing := IjfsPairing.new()
	pairing.pairing_id = "p1"
	pairing.munition_id = MUNITION
	pairing.rounds_expended_per_engagement = 4
	var row := IjfsStrikePhase.denied_strike_log(
		_maneuver("mu1", TO), pairing, IjfsStrikeContext.for_strike(3, "post_ad_recompute", null, null),
		IjfsPackageIngress.OUTCOME_ABORTED)
	assert_bool(row["attack_executed"]).override_failure_message(
		"the sortie flew; capacity is spent").is_true()
	assert_bool(row["destroyed"]).is_false()
	assert_bool(row["suppressed"]).is_false()
	assert_that(row["skip_reason"]).override_failure_message(
		"a denied sortie is not a skip — a skip never launched").is_null()
	assert_str(row["package_denial"]).is_equal(IjfsPackageIngress.OUTCOME_ABORTED)
	assert_int(row["rounds_expended"]).is_equal(4)
