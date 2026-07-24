## GdUnit4 tests for AntishipResolver._append_off_island_strikes (plan 0028 — off-island fleet strikes).
extends GdUnitTestSuite


func test_no_config_leaves_plan_unchanged() -> void:
	var plan: Array = [{"to": 3, "type": "16", "systems_fired": 2}]
	AntishipResolver._append_off_island_strikes(plan, {})
	assert_int(plan.size()).is_equal(1)


func test_zero_systems_per_turn_appends_nothing() -> void:
	# Default (byte-stable) config: shooters present but 0/turn -> golden untouched.
	var plan: Array = []
	var config := {"off_island_strike": {"shooters": [
		{"type": "6", "systems_per_turn": 0},
		{"type": "3", "systems_per_turn": 0},
	]}}
	AntishipResolver._append_off_island_strikes(plan, config)
	assert_array(plan).is_empty()


func test_appends_locationless_rows_for_each_armed_shooter() -> void:
	var plan: Array = [{"to": 3, "type": "16", "systems_fired": 2}]
	var config := {"off_island_strike": {"shooters": [
		{"type": "6", "systems_per_turn": 4},
		{"type": "3", "systems_per_turn": 0},
		{"type": "3", "systems_per_turn": 6},
	]}}
	AntishipResolver._append_off_island_strikes(plan, config)
	# Original row kept; two armed shooters appended, the zero one skipped.
	assert_int(plan.size()).is_equal(3)
	var sub: Dictionary = plan[1]
	assert_str(sub["type"]).is_equal("6")
	assert_int(sub["systems_fired"]).is_equal(4)
	# No location/to key -> AntishipCrossing skips the range gate (global reach).
	assert_bool(sub.has("location") or sub.has("to")).is_false()
	assert_int(plan[2]["systems_fired"]).is_equal(6)
