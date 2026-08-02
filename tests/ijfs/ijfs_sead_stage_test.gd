extends GdUnitTestSuite

# Plan 0060 R11 (USER ruling 2026-08-01): SEAD in three stages — expendable anti-radiation salvos,
# the weighted IADS health they leave behind, and the aircraft Red assigns against it. What these
# cases pin is the arithmetic that makes the sequence mean something: that the magazine really does
# run dry, that health is weighted by CAPABILITY rather than by headcount, and that assignment costs
# Red airframes it can then no longer send on strikes.

const CLASSES := {"classes": {
	"J-16D": {"kind": "manned", "rcs": 0, "wvr": 0, "isr_value": 0.5, "sead_eff": 1},
	"Striker": {"kind": "manned", "rcs": 0, "wvr": 0, "isr_value": 0.4, "sead_eff": 0},
}}
const SALVO_POWER := 4.0
const PER_SALVO := 4
const SALVOS_PER_DAY := 12
const MISSILE_STOCK := 192


func _sam(id: String, score: int) -> IjfsTarget:
	var target := IjfsTarget.new()
	target.target_id = id
	target.category = "Static SAMs"
	target.subcategory = "SAM"
	target.sam_score = score
	target.detected_this_turn = true
	return target


func _squadron(id: String, aircraft_class: String, role: String, alive: int) -> IjfsSquadron:
	var squadron := IjfsSquadron.new()
	squadron.squadron_id = id
	squadron.aircraft_class = aircraft_class
	squadron.role = role
	squadron.initial = alive
	squadron.alive = alive
	return squadron


func _state(sam_count: int, force: Array) -> IjfsDailyState:
	var state := IjfsDailyState.new()
	var targets: Array[IjfsTarget] = []
	for i in range(sam_count):
		targets.append(_sam("sam_%03d" % i, 4))
	state.targets = targets

	var munition := IjfsMunition.new()
	munition.munition_id = "anti_radiation_owa"
	munition.category = "Anti-Radiation"
	munition.inventory_remaining = MISSILE_STOCK
	munition.rounds_per_engagement_default = PER_SALVO
	state.munitions = {"anti_radiation_owa": munition}

	state.squadron_force = force
	state.air_classes = CLASSES
	state.scenario = {
		"red_aircraft_attrition_and_sead": {
			"role_exposure_multipliers": {"isr": 1.0, "sead": 1.0, "strike": 1.0}},
		IjfsLoaders.ANTI_RADIATION_BLOCK: {
			"munition_id": "anti_radiation_owa", "missiles_per_salvo": PER_SALVO,
			"salvos_per_day": SALVOS_PER_DAY, "salvo_effective_power": SALVO_POWER},
		IjfsLoaders.SEAD_ASSIGNMENT_BLOCK: {
			"strike_airframe_fraction": 0.25, "ordinary_aircraft_sead_eff": 0.25,
			"sead_undetected_engagement": 1.0},
	}
	return state


## Every roll misses, so nothing is destroyed or suppressed and the stage's BOOKKEEPING is what the
## case measures. Two floats per engagement: the destroy roll, then the suppression roll on survival.
## `engagements` may over-provide — ScriptedDice only complains when a draw finds the queue empty.
func _all_misses(state: IjfsDailyState, engagements: int) -> IjfsStrikePhaseContext:
	var floats: Array = []
	for _i in range(engagements * 2):
		floats.append(1.0)
	var ctx := IjfsStrikePhaseContext.new()
	ctx.current_day = 1
	ctx.attrition = IjfsAttritionProfile.build(state.scenario, CLASSES)
	ctx.air_engagement_dice = ScriptedDice.new([], [], floats)
	return ctx


func _munition(state: IjfsDailyState) -> IjfsMunition:
	return state.munitions["anti_radiation_owa"]


# --- Stage A: the expendable salvos -------------------------------------------------------------

func test_a_full_capacity_day_spends_forty_eight_missiles_on_twelve_targets() -> void:
	var force: Array[IjfsSquadron] = [_squadron("sead1", "J-16D", "sead", 10)]
	var state := _state(20, force)
	var ctx := _all_misses(state, 20 + SALVOS_PER_DAY)
	var result := IjfsSeadStage.resolve(state, ctx, true)

	var salvos := 0
	for row in result["engagement_log"]:
		if String(row["stage"]) == IjfsSeadStage.STAGE_ANTI_RADIATION:
			salvos += 1
	assert_int(salvos).is_equal(SALVOS_PER_DAY)
	assert_int(_munition(state).inventory_remaining).override_failure_message(
		"twelve four-missile salvos is 48 missiles, spent whether or not they hit"
	).is_equal(MISSILE_STOCK - SALVOS_PER_DAY * PER_SALVO)


func test_fewer_targets_than_salvos_depletes_the_magazine_more_slowly() -> void:
	var force: Array[IjfsSquadron] = [_squadron("sead1", "J-16D", "sead", 10)]
	var state := _state(5, force)
	IjfsSeadStage.resolve(state, _all_misses(state, 5 + 5), true)
	assert_int(_munition(state).inventory_remaining).override_failure_message(
		"the stage fires one salvo per eligible emitter, not one per allowance"
	).is_equal(MISSILE_STOCK - 5 * PER_SALVO)


func test_the_magazine_runs_dry_after_four_full_days_and_fires_no_forty_ninth_salvo() -> void:
	var force: Array[IjfsSquadron] = [_squadron("sead1", "J-16D", "sead", 10)]
	var state := _state(20, force)
	for _day in range(4):
		IjfsSeadStage.resolve(state, _all_misses(state, 20 + SALVOS_PER_DAY), true)
	assert_int(_munition(state).inventory_remaining).override_failure_message(
		"192 missiles is exactly 48 salvos, i.e. four full-capacity days").is_equal(0)

	var fifth := _all_misses(state, 20)
	var result := IjfsSeadStage.resolve(state, fifth, true)
	for row in result["engagement_log"]:
		assert_str(row["stage"]).override_failure_message(
			"an empty magazine must fire no salvo at all").is_equal(IjfsSeadStage.STAGE_AIRCRAFT)


func test_the_warmup_expends_no_anti_radiation_missiles() -> void:
	var force: Array[IjfsSquadron] = [_squadron("sead1", "J-16D", "sead", 10)]
	var state := _state(20, force)
	var ctx := _all_misses(state, 0)
	var result := IjfsSeadStage.resolve(state, ctx, false)
	assert_array(result["engagement_log"]).is_empty()
	assert_int(_munition(state).inventory_remaining).override_failure_message(
		"the prelanding warmup runs no SEAD, so it burns no anti-radiation stock"
	).is_equal(MISSILE_STOCK)


func test_salvos_go_to_the_richest_emitters_first() -> void:
	var force: Array[IjfsSquadron] = [_squadron("sead1", "J-16D", "sead", 10)]
	var state := _state(0, force)
	var targets: Array[IjfsTarget] = [_sam("b_weak", 1), _sam("a_strong", 4), _sam("c_mid", 2)]
	state.targets = targets
	state.scenario[IjfsLoaders.ANTI_RADIATION_BLOCK]["salvos_per_day"] = 2
	var result := IjfsSeadStage.resolve(state, _all_misses(state, 3 + 2), true)
	var struck: Array = []
	for row in result["engagement_log"]:
		if String(row["stage"]) == IjfsSeadStage.STAGE_ANTI_RADIATION:
			struck.append(row["target_id"])
	assert_array(struck).is_equal(["a_strong", "c_mid"])


# --- Stage B: weighted health -------------------------------------------------------------------

func test_health_is_weighted_by_capability_not_by_instance_count() -> void:
	var strong := _sam("patriot", 4)
	var weak_one := _sam("antelope_1", 1)
	var weak_two := _sam("antelope_2", 1)
	var targets: Array[IjfsTarget] = [strong, weak_one, weak_two]
	assert_float(IjfsSeadStage.weighted_iads_health(targets)).is_equal_approx(1.0, 0.000001)

	# Killing the one Patriot removes 4 of 6 score — two thirds of the network, from one instance
	# of three. A headcount would have said one third.
	strong.destroyed = true
	assert_float(IjfsSeadStage.weighted_iads_health(targets)).is_equal_approx(2.0 / 6.0, 0.000001)

	# A suppressed system contributes zero while suppressed, but stays in the denominator.
	weak_one.suppressed = true
	assert_float(IjfsSeadStage.weighted_iads_health(targets)).is_equal_approx(1.0 / 6.0, 0.000001)


# --- Stage C: assignment ------------------------------------------------------------------------

func test_dedicated_sead_fills_its_places_first_then_ordinary_strike_aircraft() -> void:
	var sead := _squadron("sead1", "J-16D", "sead", 10)
	var strike := _squadron("strike1", "Striker", "strike", 420)
	var force: Array[IjfsSquadron] = [sead, strike]
	var state := _state(1, force)
	IjfsSeadStage.resolve(state, _all_misses(state, 4), true)

	# ceil(0.25 x 420 x 1.0) = 105 heads: all 10 J-16Ds, then 95 ordinary strike airframes.
	assert_int(sead.sead_assigned_today).is_equal(10)
	assert_int(strike.sead_assigned_today).is_equal(95)
	assert_int(strike.available_today()).override_failure_message(
		"assigned airframes leave the Organic strike pool for the day").is_equal(420 - 95)
	assert_int(strike.alive).override_failure_message(
		"assignment is an availability transfer, not a loss").is_equal(420)


func test_ordinary_heads_split_across_squadrons_by_alive_strength() -> void:
	var sead := _squadron("sead1", "J-16D", "sead", 0)
	var big := _squadron("b_big", "Striker", "strike", 300)
	var small := _squadron("a_small", "Striker", "strike", 100)
	var force: Array[IjfsSquadron] = [sead, big, small]
	var state := _state(1, force)
	IjfsSeadStage.resolve(state, _all_misses(state, 4), true)

	# ceil(0.25 x 400) = 100 heads, none dedicated: 75 from the 300-strong squadron, 25 from the 100.
	assert_int(big.sead_assigned_today).is_equal(75)
	assert_int(small.sead_assigned_today).is_equal(25)
	assert_int(big.sead_assigned_today + small.sead_assigned_today).override_failure_message(
		"largest-remainder rounding must hand out the whole requirement, not lose a head to floors"
	).is_equal(100)


func test_a_weakened_network_asks_for_fewer_aircraft() -> void:
	var strike := _squadron("strike1", "Striker", "strike", 400)
	var force: Array[IjfsSquadron] = [strike]
	var state := _state(0, force)
	var dead := _sam("dead", 3)
	dead.destroyed = true
	var targets: Array[IjfsTarget] = [_sam("alive", 1), dead]
	state.targets = targets
	# Weighted health is 1/4, so the requirement is ceil(0.25 x 400 x 0.25) = 25 rather than 100.
	IjfsSeadStage.resolve(state, _all_misses(state, 4), true)
	assert_int(strike.sead_assigned_today).is_equal(25)


func test_effective_power_counts_dedicated_and_ordinary_airframes_differently() -> void:
	var sead := _squadron("sead1", "J-16D", "sead", 10)
	var strike := _squadron("strike1", "Striker", "strike", 420)
	var force: Array[IjfsSquadron] = [sead, strike]
	var state := _state(1, force)
	var ctx := _all_misses(state, 4)
	var result := IjfsSeadStage.resolve(state, ctx, true)
	# 10 J-16Ds at sead_eff 1 plus 95 ordinary airframes at 0.25 = 33.75, before WVR/RCS (both 0 here).
	assert_float(IjfsSeadStage.effective_power(result["package"], state, ctx)).is_equal_approx(
		33.75, 0.000001)


func test_the_assigned_package_is_the_one_return_fire_will_shoot_at() -> void:
	var sead := _squadron("sead1", "J-16D", "sead", 10)
	var strike := _squadron("strike1", "Striker", "strike", 400)
	var force: Array[IjfsSquadron] = [sead, strike]
	var state := _state(1, force)
	var result := IjfsSeadStage.resolve(state, _all_misses(state, 4), true)
	var package: IjfsAirPackage = result["package"]
	assert_str(package.kind).is_equal(IjfsAirPackage.SEAD)
	assert_int(package.size()).is_equal(sead.sead_assigned_today + strike.sead_assigned_today)
	assert_int(int(package.members_by_squadron()["sead1"])).is_equal(10)
