extends GdUnitTestSuite

# Plan 0060 R10 (USER ruling 2026-08-01): SAM return fire became package-local and geographically
# explicit. It replaced a POOLED force tax that drew once per alive airframe in the whole OOB, so the
# claims worth pinning are the ones the old shape could not make — that geography matters, that a
# SAM cannot kill more than the package in front of it, and that the destroy/suppress pass is already
# finished before a single return-fire die is thrown.

const CLASS_NAME := "Striker"
const AIR_CLASSES := {"classes": {CLASS_NAME: {"kind": "manned", "rcs": 0, "wvr": 0, "isr_value": 0.4, "sead_eff": 0}}}
const NEUTRAL_ROLES := {"red_aircraft_attrition_and_sead":
	{"role_exposure_multipliers": {"isr": 1.0, "sead": 1.0, "strike": 1.0}}}
## p_loss = factor x sam_score; with score 4 that is 0.4, so a roll of 0.1 hits and 0.9 misses.
const FACTOR := 0.1


func _sam(id: String, to_number: int, score := 4) -> IjfsTarget:
	var target := IjfsTarget.new()
	target.target_id = id
	target.category = "Moveable SAMs"
	target.subcategory = "SAM"
	target.sam_score = score
	target.metadata = {"to_number": to_number}
	return target


func _squadron(id: String, alive: int) -> IjfsSquadron:
	var squadron := IjfsSquadron.new()
	squadron.squadron_id = id
	squadron.aircraft_class = CLASS_NAME
	squadron.role = "strike"
	squadron.initial = alive
	squadron.alive = alive
	return squadron


func _state(targets: Array[IjfsTarget], factor := FACTOR) -> IjfsDailyState:
	var state := IjfsDailyState.new()
	state.targets = targets
	state.air_classes = AIR_CLASSES
	state.scenario = NEUTRAL_ROLES.duplicate(true)
	state.scenario[IjfsEngagement.SAM_RETURN_FIRE_KNOB] = factor
	return state


func _package(squadron: IjfsSquadron, size: int, to_number: int, kind := IjfsAirPackage.STRIKE) -> IjfsAirPackage:
	var members: Array[IjfsSquadron] = []
	for _i in range(size):
		members.append(squadron)
	var package := IjfsAirPackage.build(kind, "p1", members)
	package.to_number = to_number
	package.munition_id = "strike_aircraft_medium" if kind == IjfsAirPackage.STRIKE else ""
	return package


func _profile() -> IjfsAttritionProfile:
	return IjfsAttritionProfile.build(NEUTRAL_ROLES, AIR_CLASSES)


func test_only_sams_in_the_packages_theatre_engage_a_strike_package() -> void:
	var targets: Array[IjfsTarget] = [_sam("sam_a", 2), _sam("sam_b", 4), _sam("sam_c", 2)]
	var state := _state(targets)
	var squadron := _squadron("sq1", 24)
	var package := _package(squadron, 4, 2)
	# Two TO2 SAMs engage, one TO4 SAM does not. Both draws miss, so the count is what is measured.
	var dice := ScriptedDice.new([], [], [0.9, 0.9])
	var log := IjfsEngagement.resolve_package_return_fire(package, state, _profile(), dice)
	assert_int(log.size()).override_failure_message(
		"a SAM outside the struck TO cannot reach the package").is_equal(2)
	assert_int(dice._floats.size()).is_equal(0)


func test_the_sead_package_is_engaged_island_wide() -> void:
	var targets: Array[IjfsTarget] = [_sam("sam_a", 2), _sam("sam_b", 4), _sam("sam_c", 5)]
	var state := _state(targets)
	var package := _package(_squadron("sq1", 24), 10, IjfsAirPackage.NO_THEATRE, IjfsAirPackage.SEAD)
	var dice := ScriptedDice.new([], [], [0.9, 0.9, 0.9])
	var log := IjfsEngagement.resolve_package_return_fire(package, state, _profile(), dice)
	assert_int(log.size()).override_failure_message(
		"suppressing the network is not a local errand; every live SAM shoots at the SEAD package"
	).is_equal(3)
	assert_that(log[0]["munition_id"]).override_failure_message(
		"the SEAD package flies no munition, so the row says so").is_null()
	assert_str(log[0]["package_kind"]).is_equal(IjfsAirPackage.SEAD)


func test_each_hit_kills_at_most_one_member_and_names_the_squadron() -> void:
	var targets: Array[IjfsTarget] = [_sam("sam_a", 2)]
	var state := _state(targets)
	var squadron := _squadron("sq1", 24)
	var package := _package(squadron, 4, 2)
	# 0.0 -> candidate 0, roll 0.0 <= 0.4 -> one kill.
	var log := IjfsEngagement.resolve_package_return_fire(
		package, state, _profile(), ScriptedDice.new([], [], [0.0]))
	assert_int(log[0]["losses"]).is_equal(1)
	assert_str(log[0]["victim_squadron_id"]).is_equal("sq1")
	assert_int(log[0]["members_before"]).is_equal(4)
	assert_int(log[0]["members_after"]).is_equal(3)
	assert_int(package.size()).is_equal(3)
	assert_int(squadron.alive).is_equal(23)


func test_engagement_stops_once_the_package_is_empty() -> void:
	var targets: Array[IjfsTarget] = [
		_sam("sam_a", 2, 1), _sam("sam_b", 2, 1), _sam("sam_c", 2, 1),
		_sam("sam_d", 2, 1), _sam("sam_e", 2, 1)]
	# Score-1 SAMs at factor 1.0 give p_loss exactly 1.0 — the top of the band the engagement
	# asserts — so every contact kills without tripping that assert.
	var state := _state(targets, 1.0)
	var squadron := _squadron("sq1", 24)
	var package := _package(squadron, 4, 2)
	var dice := ScriptedDice.new([], [], [0.0, 0.0, 0.0, 0.0, 0.0])
	var log := IjfsEngagement.resolve_package_return_fire(package, state, _profile(), dice)
	assert_int(log.size()).override_failure_message(
		"five SAMs cannot kill more than the four airframes in front of them").is_equal(4)
	assert_bool(package.is_empty()).is_true()
	assert_int(squadron.alive).is_equal(20)
	assert_int(dice._floats.size()).override_failure_message(
		"the fifth SAM must not draw at all once the package is gone").is_equal(1)


func test_a_destroyed_or_suppressed_sam_does_not_shoot_back() -> void:
	var destroyed := _sam("sam_a", 2)
	destroyed.destroyed = true
	var suppressed := _sam("sam_b", 2)
	suppressed.suppressed = true
	var targets: Array[IjfsTarget] = [destroyed, suppressed]
	var state := _state(targets)
	var package := _package(_squadron("sq1", 24), 4, 2)
	assert_array(IjfsEngagement.resolve_package_return_fire(
		package, state, _profile(), ScriptedDice.new([], [], []))).is_empty()


func test_one_draw_picks_the_victim_and_decides_the_hit() -> void:
	var targets: Array[IjfsTarget] = [_sam("sam_a", 2)]
	var state := _state(targets)
	var first := _squadron("a_first", 10)
	var second := _squadron("b_second", 10)
	var members: Array[IjfsSquadron] = [first, first, second, second]
	var package := IjfsAirPackage.build(IjfsAirPackage.STRIKE, "p1", members)
	package.to_number = 2
	# 0.55 x 4 = 2.2 -> candidate 2 (the first `second` airframe), roll 0.2 <= 0.4 -> hit.
	var dice := ScriptedDice.new([], [], [0.55])
	var log := IjfsEngagement.resolve_package_return_fire(package, state, _profile(), dice)
	assert_str(log[0]["victim_squadron_id"]).is_equal("b_second")
	assert_int(second.alive).is_equal(9)
	assert_int(first.alive).is_equal(10)
	assert_int(dice._floats.size()).override_failure_message(
		"victim selection shares the hit's draw — a second draw would be a second place to drift"
	).is_equal(0)


func test_a_strike_against_a_target_in_no_theatre_meets_no_sam() -> void:
	var targets: Array[IjfsTarget] = [_sam("sam_a", 2), _sam("sam_b", 3)]
	var state := _state(targets)
	var package := _package(_squadron("sq1", 24), 4, IjfsAirPackage.NO_THEATRE)
	assert_array(IjfsEngagement.resolve_package_return_fire(
		package, state, _profile(), ScriptedDice.new([], [], []))).override_failure_message(
		"NO_THEATRE must mean no SAM reaches the package, not island-wide — that sentinel belongs to the SEAD package alone"
	).is_empty()


func test_an_absent_factor_means_no_return_fire_rather_than_a_guess() -> void:
	var targets: Array[IjfsTarget] = [_sam("sam_a", 2)]
	var state := IjfsDailyState.new()
	state.targets = targets
	state.air_classes = AIR_CLASSES
	state.scenario = NEUTRAL_ROLES.duplicate(true)   # knob deliberately absent
	var package := _package(_squadron("sq1", 24), 4, 2)
	assert_array(IjfsEngagement.resolve_package_return_fire(
		package, state, _profile(), ScriptedDice.new([], [], []))).is_empty()


func test_sam_destruction_is_decided_before_any_return_fire_draw() -> void:
	# The ordering R10 requires: the whole destroy/suppress pass finishes, THEN return fire runs on a
	# separate stream. Here the SEAD stage kills the only SAM, so nothing is left to shoot back —
	# which could not be true if return fire were interleaved with the pass.
	var target := _sam("sam_a", 2, 1)
	var targets: Array[IjfsTarget] = [target]
	var state := _state(targets)
	state.squadron_force = [_squadron("sq1", 40)]
	state.munitions = {}
	state.scenario[IjfsLoaders.SEAD_ASSIGNMENT_BLOCK] = {
		"strike_airframe_fraction": 0.25, "ordinary_aircraft_sead_eff": 0.25,
		"sead_undetected_engagement": 1.0}
	var ctx := IjfsStrikePhaseContext.new()
	ctx.attrition = _profile()
	ctx.air_engagement_dice = ScriptedDice.new([], [], [0.0])   # the destroy roll lands
	var result := IjfsSeadStage.resolve(state, ctx, true)
	assert_bool(target.destroyed).is_true()
	assert_array(IjfsEngagement.resolve_package_return_fire(
		result["package"], state, _profile(), ScriptedDice.new([], [], []))).is_empty()
