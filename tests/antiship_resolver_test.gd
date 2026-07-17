extends GdUnitTestSuite

## Behavioral tests for AntishipResolver (plan 0009, phase B): the no-wave early return, the
## pure helpers (snapshots, reserve pruning, minesweeper distribution, mine metadata precedence),
## and one seeded full-pipeline smoke over the real data catalogs. The crossing/mine math itself
## is pinned in antiship_crossing_test / mine_warfare_test and the golden validator.


# --- fixture helpers ----------------------------------------------------------------------------

func _ship_def(name: String, category: String, capacity := 0.0, is_decoy := false, likelihood := "") -> ShipDef:
	var ship_def := ShipDef.new()
	ship_def.name = name
	ship_def.id = name.hash()
	ship_def.category = category
	ship_def.carrying_capacity_bn_equiv = capacity
	ship_def.is_decoy = is_decoy
	ship_def.mine_neutralization_likelihood = likelihood
	return ship_def


# --- early return -----------------------------------------------------------------------------

func test_no_crossing_wave_returns_null_summary_and_preserves_accumulator() -> void:
	var result := AntishipResolver.resolve(
		3, [], [], null, {}, {}, {}, [], {}, 0.75, {}, SeededDice.new(1))
	assert_that(result["summary"]).is_null()
	assert_array(result["lost_ids"]).is_empty()
	assert_int(int(result["bn_equiv_lost"])).is_equal(0)
	assert_float(float(result["accumulator"])).is_equal_approx(0.75, 0.0001)


# --- pure helpers -----------------------------------------------------------------------------

func test_snapshots_from_sent_sorted_and_skips_zero_counts() -> void:
	var snapshots := AntishipResolver._snapshots_from_sent({"LST": 2, "Cargo": 0, "Barge": 5})
	assert_int(snapshots.size()).is_equal(2)
	assert_str(String((snapshots[0] as Dictionary)["ship_type"])).is_equal("Barge")
	assert_int(int((snapshots[0] as Dictionary)["surviving_sent"])).is_equal(5)
	assert_str(String((snapshots[1] as Dictionary)["ship_type"])).is_equal("LST")


func test_remaining_reserve_after_losses_prunes_bns_and_empty_entries() -> void:
	var reserve := [
		{"brigade_id": "A", "bns": [{"id": "a1"}, {"id": "a2"}]},
		{"brigade_id": "B", "bns": [{"id": "b1"}]},
	]
	var kept := AntishipResolver.remaining_reserve_after_losses(reserve, ["a1", "b1"])
	assert_int(kept.size()).is_equal(1)
	assert_str(String((kept[0] as Dictionary)["brigade_id"])).is_equal("A")
	assert_int(((kept[0] as Dictionary)["bns"] as Array).size()).is_equal(1)


func test_distribute_minesweepers_round_robin_ascending() -> void:
	var assignments := AntishipResolver.distribute_minesweepers(5, [8, 2])
	assert_int(int(assignments[2])).is_equal(3)  # beach 2 first (ascending), gets the odd sweeper
	assert_int(int(assignments[8])).is_equal(2)
	assert_dict(AntishipResolver.distribute_minesweepers(0, [2])).is_empty()
	assert_dict(AntishipResolver.distribute_minesweepers(3, [])).is_empty()


func test_mine_ship_meta_likelihood_precedence() -> void:
	var ship_defs := {
		"Decoy": _ship_def("Decoy", "Civilian", 0.0, true, "low"),  # decoy override wins over per-hull
		"Tanker": _ship_def("Tanker", "Civilian", 2.0, false, "medium"),  # per-hull beats category
		"LST": _ship_def("LST", "Military_Amphibious", 1.0),  # category table
		"Tug": _ship_def("Tug", "Unlisted"),  # fallback "high"
	}
	var transit := {
		"decoy_neutralization_likelihood": "certain",
		"neutralization_likelihood_by_category": {"Civilian": "low", "Military_Amphibious": "medium"},
	}
	var meta := AntishipResolver.mine_ship_meta(ship_defs, transit)
	assert_str(String((meta["Decoy"] as Dictionary)["likelihood"])).is_equal("certain")
	assert_bool(bool((meta["Decoy"] as Dictionary)["is_decoy"])).is_true()
	assert_str(String((meta["Tanker"] as Dictionary)["likelihood"])).is_equal("medium")
	assert_str(String((meta["LST"] as Dictionary)["likelihood"])).is_equal("medium")
	assert_str(String((meta["Tug"] as Dictionary)["likelihood"])).is_equal("high")
	assert_float(float((meta["Tanker"] as Dictionary)["value"])).is_equal_approx(2.0, 0.0001)


func test_ship_capacity_by_type_maps_defs() -> void:
	var caps := AntishipResolver.ship_capacity_by_type({"LST": _ship_def("LST", "x", 1.5)})
	assert_float(float(caps["LST"])).is_equal_approx(1.5, 0.0001)


# --- seeded full pipeline over real catalogs ----------------------------------------------------

func test_full_resolve_seeded_smoke_produces_consistent_summary() -> void:
	# Real arsenal + real catalogs; wave of 4 BNs on beach 1. Assertions are invariants, not pins
	# (pins live in the golden validator).
	var arsenal := AntishipSystemsBuilder.build()
	var crossing_reserve := [{
		"brigade_id": "BdeA",
		"locked_beach": 1,
		"beach_hex": "hex_b1",
		"offset_bearing": 0.0,
		"bns": [{"id": "a1", "type": "Combined Arms Battalion"}, {"id": "a2", "type": "Combined Arms Battalion"},
			{"id": "a3", "type": "Artillery Battalion"}, {"id": "a4", "type": "Artillery Battalion"}],
	}]
	var sent_by_type := {"LST": 6, "Cargo": 4}
	var ship_defs := {
		"LST": _ship_def("LST", "Military_Amphibious", 1.0),
		"Cargo": _ship_def("Cargo", "Civilian_Cargo", 1.0),
	}

	var result := AntishipResolver.resolve(
		2, crossing_reserve, arsenal["systems"], null, sent_by_type, ship_defs,
		{1: 1}, [1], {1: [1]}, 0.0, {}, SeededDice.new(20260716))

	var summary: AntishipSummary = result["summary"]
	assert_that(summary).is_not_null()
	assert_int(summary.resolved_turn).is_equal(2)
	assert_array(summary.target_beaches).is_equal([1])
	assert_array(summary.target_tos).is_equal([1])
	assert_int(summary.systems_fired_count).is_greater(0)

	# Conservation: BN losses reported never exceed the wave, lost_ids matches the count, and the
	# carried accumulator is never negative (it may exceed 1 when hull losses outrun the wave).
	var bn_equiv_lost := int(result["bn_equiv_lost"])
	assert_int(bn_equiv_lost).is_between(0, 4)
	assert_int(result["lost_ids"].size()).is_equal(bn_equiv_lost)
	assert_float(float(result["accumulator"])).is_greater_equal(0.0)

	# Hull losses never exceed the hulls that sailed.
	for ship_type in result["destroyed_by_type"].keys():
		assert_int(int(result["destroyed_by_type"][ship_type])) \
			.is_between(0, int(sent_by_type.get(ship_type, 0)))

	# Determinism: same seed, same fresh arsenal -> identical outcome.
	var arsenal2 := AntishipSystemsBuilder.build()
	var result2 := AntishipResolver.resolve(
		2, crossing_reserve.duplicate(true), arsenal2["systems"], null, sent_by_type, ship_defs,
		{1: 1}, [1], {1: [1]}, 0.0, {}, SeededDice.new(20260716))
	assert_int(int(result2["bn_equiv_lost"])).is_equal(bn_equiv_lost)
	assert_that(result2["destroyed_by_type"]).is_equal(result["destroyed_by_type"])
