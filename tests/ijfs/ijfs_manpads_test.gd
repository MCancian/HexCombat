extends GdUnitTestSuite

# MANPADS after plan 0060 R5/R6/R8/R12 (USER rulings 2026-08-01). One mechanic, one trigger: a
# four-airframe manned package striking a Maneuver Unit in a TO that still holds ready launchers.
# The island-wide daily contest and the all-target interception roll are both gone.
#
# The engagement consumes EXACTLY ONE draw, and that draw does two jobs — `u * N` picks the candidate
# and its fractional remainder is that candidate's outcome roll. Every scripted float below is chosen
# against that transform, so the cases double as its specification.

const CLASS_NAME := "4th Gen"
const AIR_CLASSES := {"classes": {CLASS_NAME: {"rcs": 0, "wvr": 0, "isr_value": 0, "sead_eff": 0}}}
const NEUTRAL_ROLES := {"red_aircraft_attrition_and_sead":
	{"role_exposure_multipliers": {"isr": 1.0, "sead": 1.0, "strike": 1.0}}}
const MUNITION := "strike_aircraft_medium"
const TO := 2
## == SATURATION_SYSTEMS, so threat_fraction is exactly 1.0 and the probabilities are the raw factors.
const STOCK := 500


func _bin(id: String, to_number: int, systems: int, destroyed := false, suppressed := false) -> IjfsTarget:
	var target := IjfsTarget.new()
	target.target_id = id
	target.category = IjfsManpads.CATEGORY
	target.metadata = {"to_number": to_number, "systems_represented": systems}
	target.destroyed = destroyed
	target.suppressed = suppressed
	return target


func _maneuver(id: String, to_number: int, destroyed := false) -> IjfsTarget:
	var target := IjfsTarget.new()
	target.target_id = id
	target.category = "Maneuver Units"
	target.metadata = {"to_number": to_number}
	target.destroyed = destroyed
	return target


func _squadron(id: String, alive: int) -> IjfsSquadron:
	var squadron := IjfsSquadron.new()
	squadron.squadron_id = id
	squadron.aircraft_class = CLASS_NAME
	squadron.role = "strike"
	squadron.initial = alive
	squadron.alive = alive
	return squadron


func _munition(vulnerability: float) -> IjfsMunition:
	var munition := IjfsMunition.new()
	munition.munition_id = MUNITION
	munition.category = "Organic"
	munition.manpads_vulnerability = vulnerability
	return munition


## A day with one MANPADS bin in TO2, one manned squadron, and the kill factor the caller wants.
func _state(kill_factor: float) -> IjfsDailyState:
	var state := IjfsDailyState.new()
	var targets: Array[IjfsTarget] = [_bin("m1", TO, STOCK)]
	state.targets = targets
	state.munitions = {MUNITION: _munition(1.0)}
	state.squadron_force = [_squadron("sq1", 24)]
	state.air_classes = AIR_CLASSES
	state.scenario = NEUTRAL_ROLES.duplicate(true)
	state.scenario[IjfsLoaders.MANPADS_KILL_FACTOR_KNOB] = kill_factor
	return state


func _package(state: IjfsDailyState, size: int) -> IjfsAirPackage:
	var members: Array[IjfsSquadron] = []
	for _i in range(size):
		members.append((state.squadron_force as Array)[0])
	var package := IjfsAirPackage.build(IjfsAirPackage.STRIKE, "p1", members)
	package.munition_id = MUNITION
	package.to_number = TO
	return package


func _profile(state: IjfsDailyState) -> IjfsAttritionProfile:
	return IjfsAttritionProfile.build(state.scenario, AIR_CLASSES)


func test_ready_systems_excludes_dead_and_suppressed_bins_and_seeds_stock() -> void:
	var targets: Array[IjfsTarget] = [
		_bin("m1", 2, 50),
		_bin("m2", 2, 50, true),         # destroyed -> 0
		_bin("m3", 3, 50, false, true),  # suppressed -> keeps stock, contributes no threat
	]
	var by_to := IjfsManpads.ready_systems_by_to(targets)
	assert_int(by_to["total"]).is_equal(50)
	assert_int(by_to["2"]).is_equal(50)
	assert_bool(by_to.has("3")).is_false()
	assert_int(int(targets[0].metadata["systems_remaining"])).is_equal(50)


# --- the trigger: exactly one strike shape, and nothing else ------------------------------------

func test_engages_only_a_manpads_eligible_package_striking_a_maneuver_unit() -> void:
	var targets: Array[IjfsTarget] = [_bin("m1", TO, STOCK)]
	var munition := _munition(1.0)
	assert_bool(IjfsManpads.engages(_maneuver("mu1", TO), munition, true, targets)).is_true()

	# Marked MANPADS-ineligible by its capacity row (Attack UCAV under R5) -> never engaged.
	assert_bool(IjfsManpads.engages(_maneuver("mu1", TO), munition, false, targets)).is_false()
	# A different target category — MANPADS protects Maneuver Units and nothing else.
	var sam := IjfsTarget.new()
	sam.target_id = "sam1"
	sam.category = "Moveable SAMs"
	sam.metadata = {"to_number": TO}
	assert_bool(IjfsManpads.engages(sam, munition, true, targets)).is_false()
	# A Maneuver Unit in a TO with no launchers.
	assert_bool(IjfsManpads.engages(_maneuver("mu2", 4), munition, true, targets)).is_false()
	# An invulnerable munition.
	assert_bool(IjfsManpads.engages(_maneuver("mu1", TO), _munition(0.0), true, targets)).is_false()


# --- the three outcomes, each from one draw ------------------------------------------------------

func test_kill_removes_one_member_and_the_survivors_press() -> void:
	var state := _state(0.5)
	var package := _package(state, 4)
	var squadron: IjfsSquadron = (state.squadron_force as Array)[0]
	# draw 0.05 -> scaled 0.2 -> candidate 0, outcome roll 0.2 <= p_kill 0.5.
	var row := IjfsManpads.engage_package(
		package, _maneuver("mu1", TO), state, _profile(state), ScriptedDice.new([], [], [0.05]))
	assert_str(row["outcome"]).is_equal(IjfsManpads.OUTCOME_KILLED)
	assert_int(row["losses"]).is_equal(1)
	assert_int(row["rtb"]).is_equal(0)
	assert_bool(row["strike_executed"]).is_true()
	assert_int(package.size()).is_equal(3)
	assert_float(package.survivor_fraction()).is_equal_approx(0.75, 0.000001)
	assert_int(squadron.alive).is_equal(23)
	assert_int(squadron.rtb_today).override_failure_message(
		"a killed airframe can never also be booked home").is_equal(0)


func test_abort_sends_every_survivor_home_and_denies_the_strike() -> void:
	var state := _state(0.0)   # no kill band at all, so the whole draw space is abort-then-nothing
	var package := _package(state, 4)
	var squadron: IjfsSquadron = (state.squadron_force as Array)[0]
	# draw 0.025 -> scaled 0.1 -> candidate 0, outcome roll 0.1 <= p_abort 0.15.
	var row := IjfsManpads.engage_package(
		package, _maneuver("mu1", TO), state, _profile(state), ScriptedDice.new([], [], [0.025]))
	assert_str(row["outcome"]).is_equal(IjfsManpads.OUTCOME_ABORTED)
	assert_int(row["losses"]).is_equal(0)
	assert_int(row["rtb"]).is_equal(4)
	assert_bool(row["strike_executed"]).is_false()
	assert_int(squadron.alive).override_failure_message(
		"an abort drives the package off; it does not shoot it down").is_equal(24)
	assert_int(squadron.rtb_today).is_equal(4)
	assert_int(squadron.available_today()).override_failure_message(
		"aborted airframes must be excluded from every later package this day").is_equal(20)


func test_unaffected_package_presses_at_full_strength() -> void:
	var state := _state(0.5)
	var package := _package(state, 4)
	# draw 0.2 -> scaled 0.8 -> candidate 0, outcome roll 0.8 > p_kill 0.5 + p_abort 0.15.
	var row := IjfsManpads.engage_package(
		package, _maneuver("mu1", TO), state, _profile(state), ScriptedDice.new([], [], [0.2]))
	assert_str(row["outcome"]).is_equal(IjfsManpads.OUTCOME_UNAFFECTED)
	assert_int(package.size()).is_equal(4)
	assert_float(package.survivor_fraction()).is_equal_approx(1.0, 0.000001)


func test_one_draw_selects_the_candidate_and_decides_the_outcome() -> void:
	var state := _state(0.5)
	var package := _package(state, 4)
	var dice := ScriptedDice.new([], [], [0.55])
	# scaled 2.2 -> candidate 2, outcome roll 0.2 <= 0.5 -> that member dies.
	var row := IjfsManpads.engage_package(package, _maneuver("mu1", TO), state, _profile(state), dice)
	assert_str(row["outcome"]).is_equal(IjfsManpads.OUTCOME_KILLED)
	assert_int(dice._floats.size()).override_failure_message(
		"the engagement must consume exactly one draw — victim selection shares it").is_equal(0)


func test_inclusive_one_draw_clamps_to_the_last_member() -> void:
	var state := _state(0.0)
	var package := _package(state, 4)
	# 1.0 * 4 = 4.0, which would index one past the end; clamped to candidate 3 with roll 1.0.
	var row := IjfsManpads.engage_package(
		package, _maneuver("mu1", TO), state, _profile(state), ScriptedDice.new([], [], [1.0]))
	assert_str(row["outcome"]).is_equal(IjfsManpads.OUTCOME_UNAFFECTED)
	assert_float(row["roll"]).is_equal_approx(1.0, 0.000001)
	assert_int(row["members_before"]).is_equal(4)


func test_role_exposure_reaches_the_kill_band_but_not_the_abort_band() -> void:
	var state := _state(0.5)
	state.scenario["red_aircraft_attrition_and_sead"] = {
		"role_exposure_multipliers": {"isr": 0.7, "sead": 1.0, "strike": 1.2}}
	var package := _package(state, 4)
	var row := IjfsManpads.engage_package(
		package, _maneuver("mu1", TO), state, _profile(state), ScriptedDice.new([], [], [0.99]))
	assert_float(row["p_kill"]).override_failure_message(
		"strike exposure 1.2 must scale the kill probability").is_equal_approx(0.6, 0.000001)
	assert_float(row["p_abort"]).override_failure_message(
		"being driven off is about the launcher, not the airframe — no exposure/RCS modifier"
	).is_equal_approx(IjfsManpads.ABORT_FACTOR, 0.000001)


func test_launchers_are_expended_on_the_attempt_whatever_the_outcome() -> void:
	for draw in [0.05, 0.99]:
		var state := _state(0.5)
		var package := _package(state, 4)
		IjfsManpads.engage_package(
			package, _maneuver("mu1", TO), state, _profile(state), ScriptedDice.new([], [], [draw]))
		assert_int(IjfsManpads.systems_remaining(state.targets[0])).override_failure_message(
			"missiles are spent on the engagement, not on the hit (draw %s)" % draw
		).is_equal(STOCK - IjfsManpads.EXPEND_PER_ENGAGEMENT)


func test_expend_drains_bins_deterministically() -> void:
	var bins: Array[IjfsTarget] = [_bin("m2", TO, 50), _bin("m1", TO, 50)]
	IjfsManpads.expend(bins, TO, 60)
	# lowest target_id first: m1 drained to 0, m2 pays the remaining 10
	assert_int(int(bins[1].metadata["systems_remaining"])).is_equal(0)
	assert_int(int(bins[0].metadata["systems_remaining"])).is_equal(40)


func test_sync_manpads_to_oob_caps_by_to_survival() -> void:
	var state := IjfsDailyState.new()
	state.targets = [
		_maneuver("mu1", 2), _maneuver("mu2", 2, true),  # TO2: 1/2 alive
		_maneuver("mu3", 3),                             # TO3: 1/1 alive
		_bin("mp2", 2, 50),
		_bin("mp3", 3, 50),
	]
	IjfsResolver.sync_manpads_to_oob(state)
	assert_int(state.targets[3].manpads_remaining).is_equal(25)
	assert_int(int(state.targets[3].metadata["systems_remaining"])).is_equal(25)
	assert_int(state.targets[4].manpads_remaining).is_equal(50)
	# monotonic: usage already below the cap stays put. The stock moves through set_remaining —
	# since plan 0046 the metadata key is a serialization mirror, so writing it alone changes nothing.
	IjfsManpads.set_remaining(state.targets[3], 10)
	IjfsResolver.sync_manpads_to_oob(state)
	assert_int(state.targets[3].manpads_remaining).is_equal(10)
	assert_int(int(state.targets[3].metadata["systems_remaining"])).is_equal(10)
