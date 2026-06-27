extends GdUnitTestSuite

# D3-D BN <-> ship mapping. Covers ShipLoadingModel forward (minimum-lift packing) and backward
# (ship loss -> BN loss) per PLAN.md Decisions 2026-06-27 D3-D. Forward is deterministic; backward
# draws the sunk BNs from an injected Dice (uniform shuffle, since every BN is 1.0 BN-equiv).


func _bns(ids: Array) -> Array:
	var out: Array = []
	for id in ids:
		out.append({"id": String(id), "type": "Mechanized Infantry Battalion"})
	return out


# --- forward: build_sent_snapshots -------------------------------------------------------------

func test_minimum_lift_fills_highest_capacity_first() -> void:
	var carriers := [
		{"ship_type": "LHA", "capacity": 1.0, "ready": 4},
		{"ship_type": "LST", "capacity": 0.25, "ready": 17},
	]
	var res := ShipLoadingModel.build_sent_snapshots(3, carriers, [])
	# 3 BN-equiv fit in 3 LHAs (cap 1.0); LSTs untouched.
	assert_dict(res["sent_by_type"]).is_equal({"LHA": 3})
	assert_int(int(res["unliftable_bn"])).is_equal(0)
	assert_float(float(res["bn_equiv_assigned"]["LHA"])).is_equal_approx(3.0, 0.0001)


func test_overflow_spills_to_next_type_with_ready_clamp() -> void:
	var carriers := [
		{"ship_type": "LHA", "capacity": 1.0, "ready": 4},
		{"ship_type": "LPD", "capacity": 1.0, "ready": 8},
	]
	# Tie on capacity -> ship_type order (LHA before LPD). 6 BNs: 4 fill LHA, 2 spill to LPD.
	var res := ShipLoadingModel.build_sent_snapshots(6, carriers, [])
	assert_dict(res["sent_by_type"]).is_equal({"LHA": 4, "LPD": 2})


func test_fractional_capacity_rounds_hulls_up() -> void:
	var carriers := [{"ship_type": "LST", "capacity": 0.25, "ready": 17}]
	# One 1.0 BN-equiv needs four 0.25-capacity LSTs.
	var res := ShipLoadingModel.build_sent_snapshots(1, carriers, [])
	assert_dict(res["sent_by_type"]).is_equal({"LST": 4})


func test_unliftable_when_fleet_capacity_exhausted() -> void:
	var carriers := [{"ship_type": "LST", "capacity": 0.25, "ready": 2}]
	# Total capacity 0.5 BN-equiv; 2 BNs requested -> 1.5 BN-equiv cannot be lifted.
	var res := ShipLoadingModel.build_sent_snapshots(2, carriers, [])
	assert_dict(res["sent_by_type"]).is_equal({"LST": 2})
	assert_int(int(res["unliftable_bn"])).is_equal(2)


func test_screen_sails_on_top_of_carriers() -> void:
	var carriers := [{"ship_type": "LHA", "capacity": 1.0, "ready": 4}]
	var screen := [{"ship_type": "DDG", "ready": 12}, {"ship_type": "Decoys", "ready": 40}]
	var res := ShipLoadingModel.build_sent_snapshots(2, carriers, screen)
	assert_dict(res["sent_by_type"]).is_equal({"LHA": 2, "DDG": 12, "Decoys": 40})
	assert_int((res["snapshots"] as Array).size()).is_equal(3)


func test_no_bns_sends_only_screen() -> void:
	var screen := [{"ship_type": "CG", "ready": 12}]
	var res := ShipLoadingModel.build_sent_snapshots(0, [], screen)
	assert_dict(res["sent_by_type"]).is_equal({"CG": 12})
	assert_int(int(res["unliftable_bn"])).is_equal(0)


# --- backward: resolve_bn_losses ---------------------------------------------------------------

func test_ship_losses_floor_to_bn_count_and_select_via_dice() -> void:
	var dice := ScriptedDice.new([], [], [], [], [[2, 0, 1, 3]])
	var res := ShipLoadingModel.resolve_bn_losses(
		{"LHA": 2}, {"LHA": 1.0}, _bns(["a", "b", "c", "d"]), 0.0, dice)
	# 2 LHA * 1.0 = 2.0 BN-equiv lost -> 2 BNs; shuffle [2,0,..] -> ids c, a.
	assert_int(int(res["bn_equiv_lost"])).is_equal(2)
	assert_array(res["lost_ids"]).is_equal(["c", "a"])
	assert_float(float(res["accumulator"])).is_equal_approx(0.0, 0.0001)


func test_fractional_capacity_carries_accumulator() -> void:
	var dice := ScriptedDice.new([], [], [], [], [[1, 0]])
	var res := ShipLoadingModel.resolve_bn_losses(
		{"LST": 1}, {"LST": 0.25}, _bns(["a", "b"]), 0.8, dice)
	# 0.25 + 0.8 = 1.05 -> 1 BN lost, 0.05 carried.
	assert_int(int(res["bn_equiv_lost"])).is_equal(1)
	assert_array(res["lost_ids"]).is_equal(["b"])
	assert_float(float(res["accumulator"])).is_equal_approx(0.05, 0.0001)


func test_pool_exhaustion_carries_unrealized_capacity() -> void:
	var dice := ScriptedDice.new([], [], [], [], [[0]])
	var res := ShipLoadingModel.resolve_bn_losses(
		{"LHA": 3}, {"LHA": 1.0}, _bns(["a"]), 0.0, dice)
	# 3.0 BN-equiv owed but only 1 BN at sea -> 1 lost, 2.0 carried so nothing is silently dropped.
	assert_int(int(res["bn_equiv_lost"])).is_equal(1)
	assert_array(res["lost_ids"]).is_equal(["a"])
	assert_float(float(res["accumulator"])).is_equal_approx(2.0, 0.0001)


func test_no_ship_losses_draws_no_bns() -> void:
	var dice := ScriptedDice.new([], [], [], [], [])  # shuffle must never be called
	var res := ShipLoadingModel.resolve_bn_losses({}, {}, _bns(["a"]), 0.3, dice)
	assert_int(int(res["bn_equiv_lost"])).is_equal(0)
	assert_array(res["bns_lost"]).is_empty()
	assert_float(float(res["accumulator"])).is_equal_approx(0.3, 0.0001)
