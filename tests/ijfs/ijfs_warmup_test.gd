extends GdUnitTestSuite

# Mirrors ijfs_standalone warmup_profiles.py behavior.


func test_profile_multiplier_even_and_single_day_is_identity() -> void:
	assert_float(IjfsWarmup.profile_multiplier("even", 1, 5)).is_equal_approx(1.0, 0.000001)
	assert_float(IjfsWarmup.profile_multiplier("front_loaded", 3, 1)).is_equal_approx(1.0, 0.000001)
	assert_float(IjfsWarmup.profile_multiplier("back_loaded", 3, 0)).is_equal_approx(1.0, 0.000001)


func test_profile_multiplier_front_and_back_loaded() -> void:
	# total_days=5 -> denominator total_days+1 = 6
	assert_float(IjfsWarmup.profile_multiplier("front_loaded", 1, 5)).is_equal_approx(10.0 / 6.0, 0.000001)
	assert_float(IjfsWarmup.profile_multiplier("front_loaded", 5, 5)).is_equal_approx(2.0 / 6.0, 0.000001)
	assert_float(IjfsWarmup.profile_multiplier("back_loaded", 1, 5)).is_equal_approx(2.0 / 6.0, 0.000001)
	assert_float(IjfsWarmup.profile_multiplier("back_loaded", 5, 5)).is_equal_approx(10.0 / 6.0, 0.000001)


func test_scale_firing_capacity_scales_sorties_and_is_immutable_at_identity() -> void:
	var config := {
		"m1": {"firing_units": 3, "sorties_per_unit_per_day": 2.0},
		"m2": {"firing_units": 1, "sorties_per_unit_per_day": 0.5},
	}
	var scaled := IjfsWarmup.scale_firing_capacity(config, 2.0)
	assert_float(scaled["m1"]["sorties_per_unit_per_day"]).is_equal_approx(4.0, 0.000001)
	assert_float(scaled["m2"]["sorties_per_unit_per_day"]).is_equal_approx(1.0, 0.000001)
	assert_int(scaled["m1"]["firing_units"]).is_equal(3)
	# input not mutated
	assert_float(config["m1"]["sorties_per_unit_per_day"]).is_equal_approx(2.0, 0.000001)


func test_scale_firing_capacity_identity_multiplier_returns_config() -> void:
	var config := {"m1": {"firing_units": 3, "sorties_per_unit_per_day": 2.0}}
	assert_dict(IjfsWarmup.scale_firing_capacity(config, 1.0)).is_equal(config)
	assert_dict(IjfsWarmup.scale_firing_capacity({}, 2.0)).is_empty()
