extends GdUnitTestSuite

# D3-C mine warfare — GEOMETRIC danger model (port of TaiwanDefenseRefactor/mine_warfare.py).
# Mines are scattered in a length x width field; a randomized straight approach path is taken; only
# mines within danger_radius of the path are "dangerous". Pre-landing sweepers clear a weak few; the
# transiting fleet (decoys first, then ascending value) detonates the rest, decoys sponging multiple.
#
# To make geometry deterministic, the "_ALL" config sets danger_radius huge (every mine is dangerous
# => dangerous == num_mines) with a fixed 45-degree angle and 0.5 entry; "_NONE" sets danger_radius 0.
# resolve_ship_losses draws randf in this order: angle, entry, (x,y) per mine, then one roll per
# detonation. ScriptedDice.randf() pops floats in order, so a transit floats array is:
#   [angle, entry] + [0.5]*(2*num_mines positions) + [neutralization rolls...]

const NEUT := {"high": 0.9, "medium": 0.5, "low": 0.25}
const CFG_ALL := {
	"geometry": {"minefield_length": 1000, "minefield_width": 500, "danger_radius": 100000000.0,
		"incident_angle_min_deg": 45, "incident_angle_max_deg": 45, "entry_point_min": 0.5, "entry_point_max": 0.5},
	"transit": {"prelanding_clear_per_sweeper": 1, "neutralization_probabilities": NEUT},
}
const CFG_NONE := {
	"geometry": {"minefield_length": 1000, "minefield_width": 500, "danger_radius": 0.0,
		"incident_angle_min_deg": 45, "incident_angle_max_deg": 45, "entry_point_min": 0.5, "entry_point_max": 0.5},
	"transit": {"prelanding_clear_per_sweeper": 1, "neutralization_probabilities": NEUT},
}


func _mf(beach_id: int, num_mines: int) -> Minefield:
	var mf := Minefield.new()
	mf.beach_id = beach_id
	mf.num_mines = num_mines
	mf.remaining_mines = num_mines
	mf.mines_per_sweeper_per_day = 1
	return mf


# [angle, entry] + position fillers + the supplied neutralization rolls.
func _floats(num_mines: int, neut_rolls: Array) -> Array:
	var f: Array = [0.5, 0.5]
	for _i in range(num_mines * 2):
		f.append(0.5)
	f.append_array(neut_rolls)
	return f


func _meta_decoy(likelihood: String = "high") -> Dictionary:
	return {"is_decoy": true, "value": 0.0, "likelihood": likelihood}


func _meta_ship(value: float, likelihood: String) -> Dictionary:
	return {"is_decoy": false, "value": value, "likelihood": likelihood}


func test_disabled_beach_skips_losses() -> void:
	# A target beach with no minefield resource is treated as disabled (TIV Enabled=False).
	var res := MineWarfareService.resolve_ship_losses([], [4], {4: 0}, {"LHA": 3}, SeededDice.new(1), {}, CFG_ALL)
	assert_str(res[0]["status"]).is_equal("disabled")
	assert_dict(res[0]["ship_loss_counts"]).is_empty()
	assert_int(int(res[0]["ships_destroyed"])).is_equal(0)


func test_already_cleared_lane_stays_safe() -> void:
	var mf := _mf(2, 100)
	mf.lane_cleared = true
	var pool := {"LHA": 3}
	var res := MineWarfareService.resolve_ship_losses([mf], [2], {2: 0}, pool, SeededDice.new(1), {}, CFG_ALL)
	assert_int(int(res[0]["ships_destroyed"])).is_equal(0)
	assert_dict(res[0]["ship_loss_counts"]).is_empty()
	assert_int(int(pool["LHA"])).is_equal(3)
	assert_str(res[0]["status_color"]).is_equal("green")


func test_zero_danger_radius_means_no_dangerous_mines() -> void:
	var mf := _mf(2, 5)
	var pool := {"LHA": 3}
	var dice := ScriptedDice.new([], [], _floats(5, []))  # only geometry draws, no detonations
	var res := MineWarfareService.resolve_ship_losses([mf], [2], {2: 0}, pool, dice, {"LHA": _meta_ship(1.0, "high")}, CFG_NONE)
	assert_dict(res[0]["ship_loss_counts"]).is_empty()
	assert_int(int(res[0]["dangerous"])).is_equal(0)
	assert_int(int(pool["LHA"])).is_equal(3)


func test_decoys_sponge_dangerous_mines_protecting_amphib() -> void:
	# 3 dangerous mines, 5 decoys lead, 1 amphib trails. Each decoy detonates one mine and is
	# neutralized (roll 0.0 < 0.9); the amphib is never reached.
	var mf := _mf(2, 3)
	var pool := {"Decoys": 5, "LHA": 1}
	var meta := {"Decoys": _meta_decoy("high"), "LHA": _meta_ship(1.0, "high")}
	var dice := ScriptedDice.new([], [], _floats(3, [0.0, 0.0, 0.0]))
	var res := MineWarfareService.resolve_ship_losses([mf], [2], {2: 0}, pool, dice, meta, CFG_ALL)
	assert_dict(res[0]["ship_loss_counts"]).is_equal({"Decoys": 3})
	assert_int(int(pool["Decoys"])).is_equal(2)
	assert_int(int(pool["LHA"])).is_equal(1)  # protected
	assert_int(int(res[0]["dangerous_detonated"])).is_equal(3)


func test_decoy_surviving_a_hit_continues_to_next_mine() -> void:
	# 2 dangerous mines, 1 decoy: it survives the first detonation (roll 0.95 > 0.9) then is
	# neutralized on the second (0.0). One decoy clears BOTH mines; the amphib is untouched.
	var mf := _mf(2, 2)
	var pool := {"Decoys": 1, "LHA": 1}
	var meta := {"Decoys": _meta_decoy("high"), "LHA": _meta_ship(1.0, "high")}
	var dice := ScriptedDice.new([], [], _floats(2, [0.95, 0.0]))
	var res := MineWarfareService.resolve_ship_losses([mf], [2], {2: 0}, pool, dice, meta, CFG_ALL)
	assert_dict(res[0]["ship_loss_counts"]).is_equal({"Decoys": 1})
	assert_int(int(pool["LHA"])).is_equal(1)
	assert_int(int(res[0]["dangerous_detonated"])).is_equal(2)


func test_amphib_at_risk_once_screen_exhausted() -> void:
	# 2 dangerous mines, only 1 decoy: decoy sinks on mine 1, amphib detonates mine 2 and sinks.
	var mf := _mf(2, 2)
	var pool := {"Decoys": 1, "LHA": 1}
	var meta := {"Decoys": _meta_decoy("high"), "LHA": _meta_ship(1.0, "high")}
	var dice := ScriptedDice.new([], [], _floats(2, [0.0, 0.0]))
	var res := MineWarfareService.resolve_ship_losses([mf], [2], {2: 0}, pool, dice, meta, CFG_ALL)
	assert_dict(res[0]["ship_loss_counts"]).is_equal({"Decoys": 1, "LHA": 1})
	assert_int(int(pool["LHA"])).is_equal(0)


func test_ascending_value_order_hits_cheaper_ships_first() -> void:
	# No decoys. 1 dangerous mine, a cheap ship (value 0.1) and an expensive one (value 1.0). The
	# cheaper ship transits first and takes the mine; the expensive one is spared.
	var mf := _mf(2, 1)
	var pool := {"LCU": 1, "LHA": 1}
	var meta := {"LCU": _meta_ship(0.1, "high"), "LHA": _meta_ship(1.0, "high")}
	var dice := ScriptedDice.new([], [], _floats(1, [0.0]))
	var res := MineWarfareService.resolve_ship_losses([mf], [2], {2: 0}, pool, dice, meta, CFG_ALL)
	assert_dict(res[0]["ship_loss_counts"]).is_equal({"LCU": 1})
	assert_int(int(pool["LHA"])).is_equal(1)


func test_prelanding_sweepers_clear_closest_dangerous() -> void:
	# 5 dangerous mines, 2 sweepers * 1 each = 2 cleared pre-landing, leaving 3 for the transit.
	var mf := _mf(2, 5)
	var pool := {"Decoys": 9}
	var meta := {"Decoys": _meta_decoy("high")}
	var dice := ScriptedDice.new([], [], _floats(5, [0.0, 0.0, 0.0]))
	var res := MineWarfareService.resolve_ship_losses([mf], [2], {2: 2}, pool, dice, meta, CFG_ALL)
	assert_int(int(res[0]["dangerous"])).is_equal(5)
	assert_int(int(res[0]["newly_swept"])).is_equal(2)
	assert_int(int(res[0]["dangerous_detonated"])).is_equal(3)
	assert_dict(res[0]["ship_loss_counts"]).is_equal({"Decoys": 3})


func test_neutralization_likelihood_threshold() -> void:
	# A medium-hardness ship (0.5): roll 0.4 < 0.5 sinks, roll 0.6 >= 0.5 is hit-but-survives.
	var mf := _mf(2, 2)
	var pool := {"LST": 2}
	var meta := {"LST": _meta_ship(0.25, "medium")}
	var dice := ScriptedDice.new([], [], _floats(2, [0.4, 0.6]))
	var res := MineWarfareService.resolve_ship_losses([mf], [2], {2: 0}, pool, dice, meta, CFG_ALL)
	assert_dict(res[0]["ship_loss_counts"]).is_equal({"LST": 1})
	assert_int(int(pool["LST"])).is_equal(1)
	assert_int(int(res[0]["dangerous_detonated"])).is_equal(2)


func test_transit_opens_lane_and_sets_status_green() -> void:
	var mf := _mf(2, 3)
	var pool := {"Decoys": 9}
	var meta := {"Decoys": _meta_decoy("high")}
	var dice := ScriptedDice.new([], [], _floats(3, [0.0, 0.0, 0.0]))
	var res := MineWarfareService.resolve_ship_losses([mf], [2], {2: 0}, pool, dice, meta, CFG_ALL)
	assert_bool(mf.lane_cleared).is_true()
	assert_str(res[0]["status_color"]).is_equal("green")


func test_seed_deterministic() -> void:
	var meta := {"Decoys": _meta_decoy("high"), "LST": _meta_ship(0.25, "high")}
	var first := MineWarfareService.resolve_ship_losses(
		[_mf(2, 100)], [2], {2: 1}, {"Decoys": 20, "LST": 20}, SeededDice.new(42), meta, CFG_ALL)
	var second := MineWarfareService.resolve_ship_losses(
		[_mf(2, 100)], [2], {2: 1}, {"Decoys": 20, "LST": 20}, SeededDice.new(42), meta, CFG_ALL)
	assert_dict(first[0]["ship_loss_counts"]).is_equal(second[0]["ship_loss_counts"])


func test_pool_depletion_across_beaches_prevents_double_sink() -> void:
	# Two beaches share one decoy-less pool; the shared pool depletes in ascending beach order.
	var pool := {"LHA": 1, "LST": 1}
	var meta := {"LHA": _meta_ship(1.0, "high"), "LST": _meta_ship(0.25, "high")}
	var dice := ScriptedDice.new([], [],
		_floats(1, [0.0]) + _floats(1, [0.0]))  # beach 2 then beach 3, one dangerous mine each
	var res := MineWarfareService.resolve_ship_losses(
		[_mf(2, 1), _mf(3, 1)], [2, 3], {2: 0, 3: 0}, pool, dice, meta, CFG_ALL)
	var total := 0
	for r in res:
		for c in r["ship_loss_counts"].values():
			total += int(c)
	assert_int(total).is_equal(2)
	assert_int(int(pool["LHA"])).is_equal(0)
	assert_int(int(pool["LST"])).is_equal(0)


func test_status_color_thresholds() -> void:
	assert_str(MineWarfareService.status_color(15, false)).is_equal("red")
	assert_str(MineWarfareService.status_color(5, false)).is_equal("amber")
	assert_str(MineWarfareService.status_color(0, false)).is_equal("green")
	assert_str(MineWarfareService.status_color(99, true)).is_equal("green")
