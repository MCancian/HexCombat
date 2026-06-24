extends GdUnitTestSuite


func before_test() -> void:
	GameData.load_all()
	GameState.reset_to_scenario()


func after_test() -> void:
	GameData.load_all()
	GameState.reset_to_scenario()


func test_is_mechanized_bn_known_mechanized_types() -> void:
	for unit_type in DosConsumption.KNOWN_MECHANIZED_BATTALION_TYPES:
		assert_bool(DosConsumption.is_mechanized_bn(unit_type)).is_true()


func test_is_mechanized_bn_known_non_mechanized_types() -> void:
	for unit_type in DosConsumption.KNOWN_NON_MECHANIZED_BATTALION_TYPES:
		assert_bool(DosConsumption.is_mechanized_bn(unit_type)).is_false()


func test_is_mechanized_bn_substring_fallbacks() -> void:
	for unit_type in [
		"Some Mechanized Thing",
		"Heavy Tank Battalion",
		"Armor Support Battalion",
		"Combined Arms Unit",
		"Amphibious Assault Battalion",
	]:
		assert_bool(DosConsumption.is_mechanized_bn(unit_type)).is_true()

	for unit_type in ["Random Infantry", "Logistics Battalion", ""]:
		assert_bool(DosConsumption.is_mechanized_bn(unit_type)).is_false()


func test_is_mechanized_bn_brigade_type_hints() -> void:
	assert_bool(DosConsumption.is_mechanized_bn("Unknown Type", "mech-infantry")).is_true()
	assert_bool(DosConsumption.is_mechanized_bn("Unknown Type", "armor")).is_true()
	assert_bool(DosConsumption.is_mechanized_bn("Unknown Type", "amphibious")).is_true()
	assert_bool(DosConsumption.is_mechanized_bn("Unknown Type", "motorized-infantry")).is_false()
	assert_bool(DosConsumption.is_mechanized_bn("Unknown Type", "artillery")).is_false()


func test_compute_unit_tons_all_combinations() -> void:
	assert_int(DosConsumption.compute_unit_tons(false, false, false)).is_equal(50)
	assert_int(DosConsumption.compute_unit_tons(false, true, false)).is_equal(100)
	assert_int(DosConsumption.compute_unit_tons(false, false, true)).is_equal(100)
	assert_int(DosConsumption.compute_unit_tons(false, true, true)).is_equal(150)
	assert_int(DosConsumption.compute_unit_tons(true, false, false)).is_equal(100)
	assert_int(DosConsumption.compute_unit_tons(true, true, false)).is_equal(200)
	assert_int(DosConsumption.compute_unit_tons(true, false, true)).is_equal(200)
	assert_int(DosConsumption.compute_unit_tons(true, true, true)).is_equal(300)


func test_calculate_consumption_empty_units_zeroed_summary() -> void:
	var summary := DosConsumption.calculate_consumption([], [], [], 7)
	assert_bool(summary["applied"]).is_false()
	assert_int(summary["day"]).is_equal(7)
	assert_int(summary["unit_count"]).is_equal(0)
	assert_int(summary["mechanized_unit_count"]).is_equal(0)
	assert_int(summary["non_mechanized_unit_count"]).is_equal(0)
	assert_int(summary["moved_unit_count"]).is_equal(0)
	assert_int(summary["combat_unit_count"]).is_equal(0)
	assert_int(summary["baseline_dos_equivalent"]).is_equal(0)
	assert_int(summary["red_dos_consumed_tons"]).is_equal(0)
	assert_float(summary["activity_dos_equivalent_exact"]).is_equal(0.0)
	assert_float(summary["activity_delta_exact"]).is_equal(0.0)
	assert_int(summary["activity_delta_rounded"]).is_equal(0)
	assert_float(summary["activity_delta_rounding_residual"]).is_equal(0.0)
	assert_int((summary["by_brigade"] as Dictionary).size()).is_equal(0)


func test_calculate_consumption_per_combo_non_mechanized() -> void:
	_assert_single_unit_consumption("Special Forces Battalion", [], [], 50, 50.0 / 150.0)
	_assert_single_unit_consumption("Special Forces Battalion", ["B1"], [], 100, 100.0 / 150.0)
	_assert_single_unit_consumption("Special Forces Battalion", [], ["B1"], 100, 100.0 / 150.0)
	_assert_single_unit_consumption("Special Forces Battalion", ["B1"], ["B1"], 150, 1.0)


func test_calculate_consumption_per_combo_mechanized() -> void:
	_assert_single_unit_consumption("Combined Arms Battalion", [], [], 100, 100.0 / 150.0)
	_assert_single_unit_consumption("Combined Arms Battalion", ["B1"], [], 200, 200.0 / 150.0)
	_assert_single_unit_consumption("Combined Arms Battalion", [], ["B1"], 200, 200.0 / 150.0)
	_assert_single_unit_consumption("Combined Arms Battalion", ["B1"], ["B1"], 300, 2.0)


func test_calculate_consumption_net_delta_baseline_for_two_sf_active() -> void:
	var units := [
		_unit("B1", "Special Forces Battalion"),
		_unit("B2", "Special Forces Battalion"),
	]
	var summary := DosConsumption.calculate_consumption(units, ["B1", "B2"], ["B1", "B2"])
	assert_int(summary["red_dos_consumed_tons"]).is_equal(300)
	assert_float(summary["activity_delta_exact"]).is_equal_approx(0.0, 0.0001)
	assert_int(summary["activity_delta_rounded"]).is_equal(0)


func test_calculate_consumption_above_baseline_one_mech_active() -> void:
	var summary := DosConsumption.calculate_consumption([_unit("B1", "Combined Arms Battalion")], ["B1"], ["B1"])
	assert_float(summary["activity_delta_exact"]).is_equal_approx(1.0, 0.0001)
	assert_int(summary["activity_delta_rounded"]).is_equal(1)


func test_calculate_consumption_below_baseline_one_sf_idle_rounds_to_zero() -> void:
	var summary := DosConsumption.calculate_consumption([_unit("B1", "Special Forces Battalion")], [], [])
	assert_float(summary["activity_delta_exact"]).is_equal_approx((50.0 / 150.0) - 1.0, 0.0001)
	assert_int(summary["activity_delta_rounded"]).is_equal(0)


func test_calculate_consumption_aggregate_rounding_positive() -> void:
	var units := [
		_unit("B1", "Combined Arms Battalion"),
		_unit("B2", "Combined Arms Battalion"),
		_unit("B3", "Combined Arms Battalion"),
	]
	var summary := DosConsumption.calculate_consumption(units, ["B1", "B2", "B3"], ["B1", "B2", "B3"])
	assert_float(summary["activity_delta_exact"]).is_equal_approx(3.0, 0.0001)
	assert_int(summary["activity_delta_rounded"]).is_equal(3)


func test_calculate_consumption_by_brigade_breakdown() -> void:
	var units := [
		_unit("B1", "Combined Arms Battalion", "amphibious"),
		_unit("B2", "Special Forces Battalion", "airborne"),
	]
	var summary := DosConsumption.calculate_consumption(units, ["B1"], ["B1", "B2"])
	var by_brigade: Dictionary = summary["by_brigade"]
	var b1: Dictionary = by_brigade["B1"]
	var b2: Dictionary = by_brigade["B2"]

	assert_str(b1["brigade_id"]).is_equal("B1")
	assert_str(b1["brigade_type"]).is_equal("amphibious")
	assert_int(b1["unit_count"]).is_equal(1)
	assert_int(b1["mechanized_count"]).is_equal(1)
	assert_int(b1["non_mechanized_count"]).is_equal(0)
	assert_bool(b1["moved"]).is_true()
	assert_bool(b1["in_combat"]).is_true()
	assert_int(b1["tons"]).is_equal(300)

	assert_str(b2["brigade_id"]).is_equal("B2")
	assert_str(b2["brigade_type"]).is_equal("airborne")
	assert_int(b2["unit_count"]).is_equal(1)
	assert_int(b2["mechanized_count"]).is_equal(0)
	assert_int(b2["non_mechanized_count"]).is_equal(1)
	assert_bool(b2["moved"]).is_false()
	assert_bool(b2["in_combat"]).is_true()
	assert_int(b2["tons"]).is_equal(100)


func test_calculate_consumption_count_fields() -> void:
	var units := [
		_unit("B1", "Combined Arms Battalion"),
		_unit("B1", "Special Forces Battalion"),
		_unit("B2", "Tank Battalion"),
	]
	var summary := DosConsumption.calculate_consumption(units, ["B1"], ["B2"])
	assert_int(summary["unit_count"]).is_equal(3)
	assert_int(summary["mechanized_unit_count"]).is_equal(2)
	assert_int(summary["non_mechanized_unit_count"]).is_equal(1)
	assert_int(summary["moved_unit_count"]).is_equal(2)
	assert_int(summary["combat_unit_count"]).is_equal(1)


func test_reset_to_scenario_initializes_red_dos_supply_state() -> void:
	GameData.load_all()
	GameState.reset_to_scenario()
	assert_float(GameState.supply_state.current_dos_tons).is_equal(15000.0)
	assert_int(GameState.supply_state.day_history.size()).is_equal(0)


func _assert_single_unit_consumption(unit_type: String, moved: Array, engaged: Array, expected_tons: int, expected_dos: float) -> void:
	var summary := DosConsumption.calculate_consumption([_unit("B1", unit_type)], moved, engaged)
	assert_int(summary["red_dos_consumed_tons"]).is_equal(expected_tons)
	assert_float(summary["activity_dos_equivalent_exact"]).is_equal_approx(expected_dos, 0.0001)


func _unit(brigade_id: String, unit_type: String, brigade_type: String = "") -> Dictionary:
	return {
		"brigade_id": brigade_id,
		"type": unit_type,
		"brigade_type": brigade_type,
	}
