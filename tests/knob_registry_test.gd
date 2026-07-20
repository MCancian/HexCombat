extends GdUnitTestSuite

## KnobRegistry.resolve_all: the per-record knob dump (plan 0018). Proves defaults resolve, an
## active override shows through on the targeted knob while others hold their default, array
## projection works, and captured llm kinds pass through.

const DEFAULT_SCENARIO := "res://data/scenario_default.json"


func after_test() -> void:
	# resolve_all reads the process-wide DataOverrides map; clear it so cases don't leak into
	# each other or into other suites.
	DataOverrides.set_map({})


func test_resolves_defaults() -> void:
	DataOverrides.set_map({})
	var knobs := KnobRegistry.resolve_all(DEFAULT_SCENARIO)

	# JSON numbers parse as floats in Godot; cast for stable comparison.
	assert_float(float(knobs["feba_base_km"])).is_equal(3.5)
	assert_int(int(knobs["ijfs_warmup_days"])).is_equal(3)
	assert_int(int(knobs["missile_group_size"])).is_equal(4)
	assert_int(int(knobs["exquisite_antiship_initial_count"])).is_equal(36)
	assert_float(float(knobs["intel_locked_antiship_strike_bonus"])).is_equal(0.2)


func test_array_projection_dumps_per_beach_capacity() -> void:
	DataOverrides.set_map({})
	var knobs := KnobRegistry.resolve_all(DEFAULT_SCENARIO)
	var capacities: Variant = knobs["beach_capacities"]
	assert_bool(capacities is Array).is_true()
	assert_int((capacities as Array).size()).is_greater(0)
	for capacity in capacities:
		assert_int(int(capacity)).is_greater(0)


func test_override_shows_through_and_others_hold_default() -> void:
	DataOverrides.set_map({
		"data/antiship/antiship_crossing_config.json:missile_group_size": 8,
	})
	var knobs := KnobRegistry.resolve_all(DEFAULT_SCENARIO)

	assert_int(int(knobs["missile_group_size"])).is_equal(8)     # overridden
	assert_int(int(knobs["ijfs_warmup_days"])).is_equal(3)       # untouched -> default
	assert_float(float(knobs["feba_base_km"])).is_equal(3.5)    # untouched -> default


func test_llm_kinds_pass_through() -> void:
	DataOverrides.set_map({})
	var knobs := KnobRegistry.resolve_all(DEFAULT_SCENARIO, "deepseek-v4-flash", "abc123")
	assert_str(knobs["llm_model"]).is_equal("deepseek-v4-flash")
	assert_str(knobs["llm_prompt_hash"]).is_equal("abc123")


func test_registry_version_is_positive() -> void:
	assert_int(KnobRegistry.version()).is_greater(0)
