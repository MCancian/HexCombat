extends GdUnitTestSuite

# D3-C mine warfare. Mirrors TIV tests/python/unit/test_antiship_mine_warfare_service.py behaviorally.
# This is the geometry-free simplified port (see PLAN.md Decisions 2026-06-27 D3-C): the geometric
# danger model and same-day-rerun baseline are intentionally not ported; ship-type selection runs
# through an injected Dice. dangerous mines == remaining unswept mines.


func _mf(beach_id: int, num_mines: int, mines_per_sweeper: int = 1) -> Minefield:
	var mf := Minefield.new()
	mf.beach_id = beach_id
	mf.num_mines = num_mines
	mf.remaining_mines = num_mines
	mf.dangerous_mines = num_mines
	mf.mines_per_sweeper_per_day = mines_per_sweeper
	return mf


func _total_losses(resolutions: Array) -> int:
	var total := 0
	for r in resolutions:
		for c in r["ship_loss_counts"].values():
			total += int(c)
	return total


func test_one_dangerous_mine_sinks_one_ship() -> void:
	var mf := _mf(2, 1)
	var pool := {"LHA": 3}
	var res := MineWarfareService.resolve_ship_losses([mf], [2], {2: 0}, pool, SeededDice.new(1))
	assert_dict(res[0]["ship_loss_counts"]).is_equal({"LHA": 1})
	assert_int(int(res[0]["ships_destroyed"])).is_equal(1)
	assert_int(int(pool["LHA"])).is_equal(2)
	assert_int(mf.ships_destroyed).is_equal(1)
	assert_int(mf.remaining_mines).is_equal(0)


func test_sweepers_reduce_sinkings() -> void:
	var no_sweep := MineWarfareService.resolve_ship_losses(
		[_mf(2, 2)], [2], {2: 0}, {"LHA": 3}, SeededDice.new(1))
	var with_sweep := MineWarfareService.resolve_ship_losses(
		[_mf(2, 2)], [2], {2: 1}, {"LHA": 3}, SeededDice.new(1))
	assert_int(_total_losses(no_sweep)).is_equal(2)
	assert_int(_total_losses(with_sweep)).is_equal(1)
	assert_int(int(with_sweep[0]["newly_swept"])).is_equal(1)


func test_disabled_beach_skips_losses() -> void:
	# A target beach with no minefield resource is treated as disabled (TIV Enabled=False).
	var res := MineWarfareService.resolve_ship_losses([], [4], {4: 0}, {"LHA": 3}, SeededDice.new(1))
	assert_str(res[0]["status"]).is_equal("disabled")
	assert_dict(res[0]["ship_loss_counts"]).is_empty()
	assert_int(int(res[0]["ships_destroyed"])).is_equal(0)


func test_empty_fleet_pool_means_no_sinkings() -> void:
	var mf := _mf(2, 2)
	var res := MineWarfareService.resolve_ship_losses([mf], [2], {2: 0}, {}, SeededDice.new(1))
	assert_dict(res[0]["ship_loss_counts"]).is_empty()
	assert_int(int(res[0]["ships_destroyed"])).is_equal(0)
	assert_int(mf.remaining_mines).is_equal(2)  # nothing swept, nothing detonated


func test_pool_depletion_across_beaches_prevents_double_sink() -> void:
	var pool := {"LHA": 1, "LST": 1}
	var res := MineWarfareService.resolve_ship_losses(
		[_mf(2, 2), _mf(3, 2)], [2, 3], {2: 0, 3: 0}, pool, SeededDice.new(5))
	assert_int(_total_losses(res)).is_equal(2)
	assert_int(int(pool["LHA"])).is_equal(0)
	assert_int(int(pool["LST"])).is_equal(0)


func test_seed_deterministic_and_damaged_survivors_eligible() -> void:
	var first := MineWarfareService.resolve_ship_losses(
		[_mf(2, 2)], [2], {2: 0}, {"LHA": 2, "LST": 1}, SeededDice.new(42))
	var second := MineWarfareService.resolve_ship_losses(
		[_mf(2, 2)], [2], {2: 0}, {"LHA": 2, "LST": 1}, SeededDice.new(42))
	assert_dict(first[0]["ship_loss_counts"]).is_equal(second[0]["ship_loss_counts"])
	# A pool of a single (possibly damaged) survivor is still eligible to sink.
	var damaged := MineWarfareService.resolve_ship_losses(
		[_mf(2, 1)], [2], {2: 0}, {"LHA": 1}, SeededDice.new(7))
	assert_dict(damaged[0]["ship_loss_counts"]).is_equal({"LHA": 1})


func test_full_sweep_clears_lane_and_sets_status() -> void:
	var mf := _mf(2, 2, 5)  # 1 sweeper * 5 mines/day clears both mines
	var res := MineWarfareService.resolve_ship_losses([mf], [2], {2: 1}, {}, SeededDice.new(1))
	assert_int(int(res[0]["newly_swept"])).is_equal(2)
	assert_bool(mf.lane_cleared).is_true()
	assert_str(res[0]["status_color"]).is_equal("green")


func test_status_color_thresholds() -> void:
	assert_str(MineWarfareService.status_color(15, false)).is_equal("red")
	assert_str(MineWarfareService.status_color(5, false)).is_equal("amber")
	assert_str(MineWarfareService.status_color(0, false)).is_equal("green")
	assert_str(MineWarfareService.status_color(99, true)).is_equal("green")


# --- D3-D (decision 2-iii): bounded per-lane danger + first-transit lane clearing ---------------

func test_large_minefield_danger_is_bounded_per_lane() -> void:
	# 100-mine field (the shipped config) no longer sinks ~100 hulls: the default cap (10) bounds it.
	var mf := _mf(2, 100)
	var pool := {"LST": 50}
	var res := MineWarfareService.resolve_ship_losses([mf], [2], {2: 0}, pool, SeededDice.new(3))
	assert_int(int(res[0]["ships_destroyed"])).is_equal(10)
	assert_dict(res[0]["ship_loss_counts"]).is_equal({"LST": 10})
	assert_int(int(pool["LST"])).is_equal(40)
	assert_int(mf.remaining_mines).is_equal(90)  # 90 mines remain in the wider field
	assert_bool(mf.lane_cleared).is_true()  # but the transit lane is cleared + marked
	assert_str(res[0]["status_color"]).is_equal("green")


func test_cleared_lane_stays_safe_on_next_transit() -> void:
	var mf := _mf(2, 100)
	var pool := {"LST": 50}
	MineWarfareService.resolve_ship_losses([mf], [2], {2: 0}, pool, SeededDice.new(3))  # turn 1 clears lane
	assert_bool(mf.lane_cleared).is_true()
	var res2 := MineWarfareService.resolve_ship_losses([mf], [2], {2: 0}, pool, SeededDice.new(3))  # turn 2
	assert_int(int(res2[0]["ships_destroyed"])).is_equal(0)
	assert_dict(res2[0]["ship_loss_counts"]).is_empty()
	assert_int(int(pool["LST"])).is_equal(40)  # untouched on the cleared lane
	assert_str(res2[0]["status_color"]).is_equal("green")


func test_custom_lane_cap_and_sweepers_within_lane() -> void:
	var mf := _mf(2, 100)
	var pool := {"LST": 50}
	# Cap 5 -> 5 lane mines; 2 sweepers clear 2, the remaining 3 sink ships.
	var res := MineWarfareService.resolve_ship_losses([mf], [2], {2: 2}, pool, SeededDice.new(3), 5)
	assert_int(int(res[0]["newly_swept"])).is_equal(2)
	assert_int(int(res[0]["ships_destroyed"])).is_equal(3)
