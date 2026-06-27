extends GdUnitTestSuite

# D3-B2 — anti-ship firing plan. Mirrors TIV tests/python/unit/test_antiship_firing_plan.py
# (the two magazine-gating cases), plus direct coverage of allocate_firing_to_rows (proportional
# largest-remainder) and resolve_launch_attrition (scripted-dice draw order + inventory mutation),
# which the pytest exercises only through the calculator/integration path.

const MAG_PATH := "res://data/antiship/antiship_magazine_defaults.json"


func _system(to_number: int, type_id: int, quantity: int) -> AntishipSystem:
	var s := AntishipSystem.new()
	s.to_number = to_number
	s.type_id = type_id
	s.quantity = quantity
	s.original_quantity = quantity
	return s


func _mag(current_counts: Dictionary) -> AntishipMagazine:
	var mag := AntishipMagazine.from_defaults(AntishipLoaders.load_magazines(MAG_PATH))
	mag.current_counts = current_counts.duplicate()
	return mag


# --- build_firing_plan: TIV pytest mirrors -------------------------------------------------------

func test_build_firing_plan_reserves_shared_pool_once_across_locations() -> void:
	var systems: Array = [_system(3, 5, 100), _system(4, 5, 100)]
	var mag := _mag({"block_i": 150})
	var plan := AntishipCalculator.build_firing_plan(
		systems, {}, [3, 4],
		{"3:5": 100.0, "4:5": 100.0}, {}, mag)

	var allocation_plan: Array = plan["allocation_plan"]
	var total_attempted := 0
	for entry in allocation_plan:
		total_attempted += int(entry["attempted_firing"])
	assert_int(total_attempted).is_equal(100)
	assert_int(int(mag.current_counts["block_i"])).is_equal(50)
	assert_int(int(plan["destroyed_firing_plan"]["3:5"])).is_equal(0)
	assert_int(int(plan["destroyed_firing_plan"]["4:5"])).is_equal(0)


func test_build_firing_plan_gates_out_short_magazine_before_row_split() -> void:
	var systems: Array = [_system(3, 24, 2)]
	var mag := _mag({"block_ii_mobile": 7})
	var plan := AntishipCalculator.build_firing_plan(
		systems, {}, [3], {"3:24": 100.0}, {}, mag)

	assert_array(plan["allocation_plan"]).is_empty()
	assert_int(int(mag.current_counts["block_ii_mobile"])).is_equal(7)


func test_build_firing_plan_excludes_c2_systems() -> void:
	var systems: Array = [_system(3, 99, 50)]
	var plan := AntishipCalculator.build_firing_plan(
		systems, {}, [3], {"3:99": 100.0}, {}, null)
	assert_array(plan["allocation_plan"]).is_empty()
	assert_bool(plan["destroyed_firing_plan"].has("3:99")).is_false()


func test_build_firing_plan_no_magazine_fires_full_percentage() -> void:
	var systems: Array = [_system(3, 23, 10)]
	var plan := AntishipCalculator.build_firing_plan(
		systems, {}, [3], {"3:23": 40.0}, {}, null)
	var allocation_plan: Array = plan["allocation_plan"]
	assert_int(allocation_plan.size()).is_equal(1)
	assert_int(int(allocation_plan[0]["attempted_firing"])).is_equal(4)  # int(10 * 0.40)


# --- destroyed-system firing (no surviving launchers) --------------------------------------------

func test_destroyed_systems_fire_via_destroyed_fire_percentage() -> void:
	var sys := _system(3, 5, 0)
	sys.destroyed_this_turn = 10  # all destroyed this turn (e.g. by IJFS), none surviving
	var systems: Array = [sys]
	var plan := AntishipCalculator.build_firing_plan(
		systems, {}, [3], {"3:5": 100.0}, {"3:5": 50.0}, null)

	# No surviving launchers -> no allocation, but destroyed systems still contribute fire.
	assert_array(plan["allocation_plan"]).is_empty()
	assert_int(int(plan["destroyed_firing_plan"]["3:5"])).is_equal(5)  # int(10 * 0.50)

	var dice := ScriptedDice.new([])
	var result := AntishipCalculator.resolve_launch_attrition(
		systems, plan["allocation_plan"], plan["destroyed_firing_plan"], {}, dice)
	var fired: Array = result["systems_fired"]
	assert_int(fired.size()).is_equal(1)
	assert_int(int(fired[0]["available_firing"])).is_equal(0)
	assert_int(int(fired[0]["destroyed_firing"])).is_equal(5)
	assert_int(int(fired[0]["systems_fired"])).is_equal(5)
	assert_array(result["launch_attrition"]).is_empty()  # nothing attempted by survivors


# --- allocate_firing_to_rows: proportional largest-remainder -------------------------------------

func test_allocate_firing_to_rows_largest_remainder_ties_to_earlier_rows() -> void:
	# raw = [1.5, 1.5, 2.0]; floors = [1, 1, 2] (sum 4); deficit 1 -> earliest tied remainder (idx 0).
	assert_array(AntishipCalculator.allocate_firing_to_rows([3, 3, 4], 5)).is_equal([2, 1, 2])


func test_allocate_firing_to_rows_caps_at_row_availability() -> void:
	# raw = [0.4545, 4.5454]; floors = [0, 4]; deficit 1 -> idx 1; capped at availability 10.
	assert_array(AntishipCalculator.allocate_firing_to_rows([1, 10], 5)).is_equal([0, 5])


func test_allocate_firing_to_rows_zero_inputs() -> void:
	assert_array(AntishipCalculator.allocate_firing_to_rows([5, 5], 0)).is_equal([0, 0])
	assert_array(AntishipCalculator.allocate_firing_to_rows([0, 0], 3)).is_equal([0, 0])


# --- resolve_launch_attrition: scripted draw order + inventory mutation --------------------------

func test_resolve_launch_attrition_draw_order_and_inventory() -> void:
	var systems: Array = [_system(3, 23, 10)]
	var plan := AntishipCalculator.build_firing_plan(
		systems, {}, [3], {"3:23": 40.0}, {}, null)  # attempted = 4

	# type 23: p_detect 0.5 * p_destroy_if_detected 0.7 = p_destroy 0.35; p_intercept 0.6.
	var config := {"23": {
		"p_detect": 0.5, "p_destroy_if_detected": 0.7, "p_intercept_before_launch": 0.6}}
	# Shot 1: 0.9 >= 0.35 -> launched.
	# Shot 2: 0.1 < 0.35 destroyed, 0.1 < 0.6 -> prelaunch (not launched).
	# Shot 3: 0.1 < 0.35 destroyed, 0.9 >= 0.6 -> postlaunch (launched).
	# Shot 4: 0.5 >= 0.35 -> launched.
	var dice := ScriptedDice.new([], [], [0.9, 0.1, 0.1, 0.1, 0.9, 0.5])
	var result := AntishipCalculator.resolve_launch_attrition(
		systems, plan["allocation_plan"], plan["destroyed_firing_plan"], config, dice)

	var fired: Array = result["systems_fired"]
	assert_int(fired.size()).is_equal(1)
	assert_int(int(fired[0]["available_firing"])).is_equal(3)   # launched (shots 1, 3, 4)
	assert_int(int(fired[0]["systems_fired"])).is_equal(3)
	assert_int(int(fired[0]["attempted_firing"])).is_equal(4)
	assert_int(int(fired[0]["prelaunch_destroyed"])).is_equal(1)
	assert_int(int(fired[0]["postlaunch_destroyed"])).is_equal(1)

	var attr: Array = result["launch_attrition"]
	assert_int(attr.size()).is_equal(1)
	assert_int(int(attr[0]["launched"])).is_equal(3)
	assert_int(int(attr[0]["prelaunch_destroyed"])).is_equal(1)
	assert_int(int(attr[0]["postlaunch_destroyed"])).is_equal(1)

	# Inventory mutation on the AntishipSystem row.
	var sys: AntishipSystem = systems[0]
	assert_bool(sys.active).is_true()
	assert_int(sys.quantity).is_equal(6)               # 10 - 4 attempted
	assert_int(sys.fired).is_equal(3)
	assert_int(sys.expended).is_equal(3)
	assert_int(sys.destroyed_this_turn).is_equal(2)    # pre + post
	assert_int(sys.destroyed).is_equal(2)
