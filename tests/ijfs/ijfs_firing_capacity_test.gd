extends GdUnitTestSuite


func test_inorganic_budget_uses_floor_and_exhausts_then_unknown_unbounded() -> void:
	var config := {
		"df17": {"firing_units": 2, "sorties_per_unit_per_day": 1.5},
	}
	var budget := IjfsFiringCapacity.FiringCapacityBudget.new(config)
	assert_bool(budget.has_capacity("df17")).is_true()
	assert_bool(budget.try_consume("df17")).is_true()
	assert_bool(budget.try_consume("df17")).is_true()
	assert_bool(budget.try_consume("df17")).is_true()
	assert_bool(budget.has_capacity("df17")).is_false()
	assert_bool(budget.try_consume("df17")).is_false()
	assert_bool(budget.has_capacity("unknown_munition")).is_true()
	assert_bool(budget.try_consume("unknown_munition")).is_true()

	var util: Dictionary = budget.utilization()
	assert_int(util["df17"]["budget"]).is_equal(3)
	assert_int(util["df17"]["used"]).is_equal(3)
	assert_int(util["df17"]["remaining"]).is_equal(0)


func test_firing_capacity_skips_organic_munitions_and_zero_sorties_blocks_inorganic() -> void:
	var munitions := {
		"strike_aircraft_medium": _munition("strike_aircraft_medium", "Organic"),
		"pl15": _munition("pl15", "Inorganic-Fast"),
	}
	var budget := IjfsFiringCapacity.FiringCapacityBudget.new({
		"strike_aircraft_medium": {"firing_units": 1, "sorties_per_unit_per_day": 0.0},
		"pl15": {"firing_units": 10, "sorties_per_unit_per_day": 0.0},
	}, munitions)

	assert_bool(budget.has_capacity("strike_aircraft_medium")).is_true()
	assert_bool(budget.try_consume("strike_aircraft_medium")).is_true()
	assert_bool(budget.has_capacity("pl15")).is_false()
	assert_bool(budget.try_consume("pl15")).is_false()
	assert_bool(budget.utilization().has("strike_aircraft_medium")).is_false()
	assert_bool(budget.utilization().has("pl15")).is_true()


func test_organic_strike_budget_scales_by_matching_platform_kind_only() -> void:
	var scenario := {"red_firing_capacity": {"strike_aircraft_medium": {
		"firing_units": 36,
		"sorties_per_unit_per_day": 0.8,
		"platform_type": "aircraft",
	}}}
	var air_classes := {"classes": {"4.5th Gen": {"kind": "manned"}, "MALE Armed": {"kind": "unmanned"}}}
	var force: Array[IjfsSquadron] = [
		_squadron("s1", "4.5th Gen", "strike", 24, 12),
		_squadron("s2", "MALE Armed", "isr", 24, 0),
	]
	var budget := IjfsFiringCapacity.OrganicStrikeBudget.new(
		scenario,
		force,
		{"strike_aircraft_medium": _munition("strike_aircraft_medium", "Organic")},
		air_classes
	)

	var reduced := 14 # floor(floor(36 * 0.8) * 12 / 24); ISR loss does not dilute manned strike.
	for i in range(reduced):
		assert_bool(budget.try_consume("strike_aircraft_medium")).is_true()
	assert_bool(budget.has_capacity("strike_aircraft_medium")).is_false()
	assert_bool(budget.try_consume("strike_aircraft_medium")).is_false()

	var util: Dictionary = budget.utilization()
	assert_int(util["strike_aircraft_medium"]["budget"]).is_equal(14)
	assert_int(util["strike_aircraft_medium"]["used"]).is_equal(14)


func test_organic_strike_budget_falls_back_to_any_strike_health_when_kind_missing() -> void:
	var scenario := {"red_firing_capacity": {"strike_aircraft_medium": {
		"firing_units": 36,
		"sorties_per_unit_per_day": 0.8,
	}}}
	var force: Array[IjfsSquadron] = [_squadron("s1", "4.5th Gen", "strike", 24, 12)]
	var budget := IjfsFiringCapacity.OrganicStrikeBudget.new(
		scenario,
		force,
		{"strike_aircraft_medium": _munition("strike_aircraft_medium", "Organic")}
	)

	for i in range(14):
		assert_bool(budget.try_consume("strike_aircraft_medium")).is_true()
	assert_bool(budget.try_consume("strike_aircraft_medium")).is_false()
	assert_int(budget.utilization()["strike_aircraft_medium"]["budget"]).is_equal(14)


func test_organic_strike_budget_uses_unscaled_base_when_health_none_and_unknown_inorganic_unbounded() -> void:
	var scenario := {"red_firing_capacity": {"strike_aircraft_medium": {
		"firing_units": 36,
		"sorties_per_unit_per_day": 0.8,
		"platform_type": "aircraft",
	}}}
	var budget := IjfsFiringCapacity.OrganicStrikeBudget.new(
		scenario,
		[],
		{"strike_aircraft_medium": _munition("strike_aircraft_medium", "Organic")},
		{"classes": {}}
	)

	for i in range(28):
		assert_bool(budget.try_consume("strike_aircraft_medium")).is_true()
	assert_bool(budget.try_consume("strike_aircraft_medium")).is_false()
	assert_bool(budget.has_capacity("df17")).is_true()
	assert_bool(budget.try_consume("df17")).is_true()
	assert_int(budget.utilization()["strike_aircraft_medium"]["budget"]).is_equal(28)


func test_organic_strike_budget_zero_alive_blocks_all_and_budget_shape() -> void:
	var scenario := {"red_firing_capacity": {"strike_aircraft_medium": {
		"firing_units": 36,
		"sorties_per_unit_per_day": 0.8,
	}}}
	var force: Array[IjfsSquadron] = [_squadron("s1", "4.5th Gen", "strike", 24, 0)]
	var budget := IjfsFiringCapacity.OrganicStrikeBudget.new(
		scenario,
		force,
		{"strike_aircraft_medium": _munition("strike_aircraft_medium", "Organic")}
	)

	assert_bool(budget.has_capacity("strike_aircraft_medium")).is_false()
	assert_bool(budget.try_consume("strike_aircraft_medium")).is_false()
	var util: Dictionary = budget.utilization()
	assert_int(util["strike_aircraft_medium"]["budget"]).is_equal(0)
	assert_int(util["strike_aircraft_medium"]["used"]).is_equal(0)
	assert_bool(util["strike_aircraft_medium"].has("remaining")).is_false()


func _munition(munition_id: String, category: String) -> IjfsMunition:
	var munition := IjfsMunition.new()
	munition.munition_id = munition_id
	munition.category = category
	return munition


func _squadron(squadron_id: String, aircraft_class: String, role: String, initial: int, alive: int) -> IjfsSquadron:
	var squadron := IjfsSquadron.new()
	squadron.squadron_id = squadron_id
	squadron.aircraft_class = aircraft_class
	squadron.role = role
	squadron.initial = initial
	squadron.alive = alive
	return squadron
