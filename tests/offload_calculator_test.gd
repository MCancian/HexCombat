## GdUnit4 tests for OffloadCalculator — mirrors TaiwanInvasionViewer
## tests/python/unit/test_offload_day1_redesign.py and test_offload_brigade_priority.py.
extends GdUnitTestSuite

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Build a fake beach_lookup dictionary {beach_id -> BeachDef}.
func _make_beach_lookup(beach_rates: Dictionary) -> Dictionary:
	var lookup: Dictionary = {}
	for beach_id_var in beach_rates.keys():
		var beach_id := int(beach_id_var)
		var beach := BeachDef.new()
		beach.id = beach_id
		beach.name_en = "Beach %d" % beach_id
		beach.offload_rate = float(beach_rates[beach_id_var])
		beach.floating_piers = 0
		beach.jackup_barge = 0
		lookup[beach_id] = beach
	return lookup


# Build a set of 4 brigades each with 4 maneuver + 5 support BNs (total 36).
func _build_4_brigades_36_bns() -> Array:
	var maneuver_types := [
		"Amphibious Infantry Battalion",
		"Amphibious Infantry Battalion",
		"Amphibious Infantry Battalion",
		"Combined Arms Battalion",
	]
	var support_types := [
		"Support Battalion",
		"Field Artillery Battalion",
		"Engineer Battalion",
		"Reconnaissance Battalion",
		"Air Defense Battalion",
	]
	var brigade_ids := ["BDE-A", "BDE-B", "BDE-C", "BDE-D"]
	var brigades: Array = []
	for bde_id in brigade_ids:
		var bns: Array = []
		for i in range(maneuver_types.size()):
			bns.append({"id": "%s-M%d" % [bde_id, i], "type": maneuver_types[i]})
		for i in range(support_types.size()):
			bns.append({"id": "%s-S%d" % [bde_id, i], "type": support_types[i]})
		brigades.append({"brigade_id": bde_id, "locked_beach": 0, "bns": bns})
	return brigades


func _make_brigade(brigade_id: String, bns: Array, locked_beach: int = 0) -> Dictionary:
	return {"brigade_id": brigade_id, "locked_beach": locked_beach, "bns": bns}


func _make_bn(bn_id: String, bn_type: String) -> Dictionary:
	return {"id": bn_id, "type": bn_type}

# ---------------------------------------------------------------------------
# D1-B: OffloadRates constants
# ---------------------------------------------------------------------------

func test_tons_per_bn_is_2200() -> void:
	assert_float(OffloadRates.TONS_PER_BN).is_equal(2200.0)


func test_beach_base_rate_is_4400() -> void:
	assert_float(OffloadRates.BEACH_BASE).is_equal(4400.0)


func test_floating_pier_rate_is_2200() -> void:
	assert_float(OffloadRates.FLOATING_PIER).is_equal(2200.0)


func test_jackup_barge_rate_is_4400() -> void:
	assert_float(OffloadRates.JACKUP_BARGE).is_equal(4400.0)


func test_operational_port_rate_is_11000() -> void:
	assert_float(OffloadRates.OPERATIONAL_PORT).is_equal(11000.0)


# ---------------------------------------------------------------------------
# OffloadCalculator.is_maneuver_bn
# ---------------------------------------------------------------------------

func test_maneuver_types_are_recognized() -> void:
	for t in ["Combined Arms Battalion", "Amphibious Infantry Battalion",
			"Mechanized Infantry Battalion", "Air Assault Infantry Battalion",
			"Special Forces Battalion"]:
		assert_bool(OffloadCalculator.is_maneuver_bn(t)).is_true()


func test_support_types_are_not_maneuver() -> void:
	for t in ["Support Battalion", "Field Artillery Battalion", "Engineer Battalion",
			"Reconnaissance Battalion", "Air Defense Battalion", "Artillery Battalion"]:
		assert_bool(OffloadCalculator.is_maneuver_bn(t)).is_false()

# ---------------------------------------------------------------------------
# OffloadCalculator.beach_capacity_bns
# ---------------------------------------------------------------------------

func test_beach_capacity_bns_single_beach() -> void:
	# rate=8800 -> 8800/2200 = 4.0 BN-slots
	var lookup := _make_beach_lookup({1: 8800.0})
	var cap := OffloadCalculator.beach_capacity_bns([1], lookup)
	assert_float(cap.get(1, 0.0)).is_equal_approx(4.0, 0.001)


func test_beach_capacity_bns_multiple_beaches() -> void:
	var lookup := _make_beach_lookup({1: 4400.0, 2: 8800.0, 3: 4400.0})
	var cap := OffloadCalculator.beach_capacity_bns([1, 2, 3], lookup)
	assert_float(cap.get(1, 0.0)).is_equal_approx(2.0, 0.001)
	assert_float(cap.get(2, 0.0)).is_equal_approx(4.0, 0.001)
	assert_float(cap.get(3, 0.0)).is_equal_approx(2.0, 0.001)


func test_beach_capacity_bns_with_floating_piers() -> void:
	# rate=4400 + 1 pier * 2200 = 6600 / 2200 = 3.0
	var beach := BeachDef.new()
	beach.id = 1
	beach.offload_rate = 4400.0
	beach.floating_piers = 1
	beach.jackup_barge = 0
	var cap := OffloadCalculator.beach_capacity_bns([1], {1: beach})
	assert_float(cap.get(1, 0.0)).is_equal_approx(3.0, 0.001)

# ---------------------------------------------------------------------------
# resolve_offload_day — Day 1 redesign (mirrors test_offload_day1_redesign.py)
# ---------------------------------------------------------------------------

func test_all_bns_sent_on_day1() -> void:
	# Mirrors: test_all_bns_load_on_day1 — all 36 BNs should be counted as sent.
	var brigades := _build_4_brigades_36_bns()
	var beach_ids := [1, 2, 3]
	var lookup := _make_beach_lookup({1: 8800.0, 2: 8800.0, 3: 8800.0})
	var cap := OffloadCalculator.beach_capacity_bns(beach_ids, lookup)

	var result := OffloadCalculator.resolve_offload_day(1, cap, brigades,
			["BDE-A", "BDE-B", "BDE-C", "BDE-D"])

	assert_int(result["bns_sent"]).is_equal(36)


func test_day1_only_maneuver_bns_land() -> void:
	# Mirrors: test_day1_only_maneuver_bns_land — 4 brigades × 4 maneuver = 16 landed.
	var brigades := _build_4_brigades_36_bns()
	var lookup := _make_beach_lookup({1: 8800.0, 2: 8800.0, 3: 8800.0})
	var cap := OffloadCalculator.beach_capacity_bns([1, 2, 3], lookup)

	var result := OffloadCalculator.resolve_offload_day(1, cap, brigades,
			["BDE-A", "BDE-B", "BDE-C", "BDE-D"])

	assert_int(result["bns_landed"]).is_equal(16)
	for entry in result["manifest_landed"] as Array:
		assert_bool(OffloadCalculator.is_maneuver_bn(String(entry["bn_type"]))).is_true()


func test_day1_support_bns_are_waiting() -> void:
	# Mirrors: test_day1_support_bns_are_waiting — 36 - 16 = 20 waiting.
	var brigades := _build_4_brigades_36_bns()
	var lookup := _make_beach_lookup({1: 8800.0, 2: 8800.0, 3: 8800.0})
	var cap := OffloadCalculator.beach_capacity_bns([1, 2, 3], lookup)

	var result := OffloadCalculator.resolve_offload_day(1, cap, brigades,
			["BDE-A", "BDE-B", "BDE-C", "BDE-D"])

	assert_int(result["bns_waiting"]).is_equal(20)


func test_day1_maneuver_bypass_throughput() -> void:
	# Mirrors: test_day1_maneuver_bypass_throughput.
	# rate=2200 -> 1 brigade slot per beach -> 3 beaches -> 3 brigades -> 12 maneuver BNs land.
	var brigades := _build_4_brigades_36_bns()
	var lookup := _make_beach_lookup({1: 2200.0, 2: 2200.0, 3: 2200.0})
	var cap := OffloadCalculator.beach_capacity_bns([1, 2, 3], lookup)

	var result := OffloadCalculator.resolve_offload_day(1, cap, brigades,
			["BDE-A", "BDE-B", "BDE-C", "BDE-D"])

	assert_int(result["bns_landed"]).is_equal(12)


func test_bns_waiting_formula() -> void:
	# Mirrors: test_bns_waiting_formula — waiting = sent - landed - lost_at_sea.
	var brigades := _build_4_brigades_36_bns()
	var lookup := _make_beach_lookup({1: 8800.0, 2: 8800.0, 3: 8800.0})
	var cap := OffloadCalculator.beach_capacity_bns([1, 2, 3], lookup)

	var result := OffloadCalculator.resolve_offload_day(1, cap, brigades,
			["BDE-A", "BDE-B", "BDE-C", "BDE-D"])

	var expected_waiting: int = int(result["bns_sent"]) - int(result["bns_landed"]) - int(result["lost_at_sea"])
	assert_int(result["bns_waiting"]).is_equal(expected_waiting)

# ---------------------------------------------------------------------------
# resolve_offload_day — beach assignment and locking
# ---------------------------------------------------------------------------

func test_locked_beach_brigade_uses_designated_beach() -> void:
	var bns := [_make_bn("B1", "Amphibious Infantry Battalion")]
	var brigades := [_make_brigade("BDE-1", bns, 2)]
	var lookup := _make_beach_lookup({1: 8800.0, 2: 8800.0})
	var cap := OffloadCalculator.beach_capacity_bns([1, 2], lookup)

	var result := OffloadCalculator.resolve_offload_day(1, cap, brigades, ["BDE-1"])

	assert_int(result["bns_landed"]).is_equal(1)
	var landed: Array = result["manifest_landed"]
	assert_int(int(landed[0]["beach_id"])).is_equal(2)


func test_locked_beach_unavailable_defers_brigade() -> void:
	# Mirrors: test_locked_beach_unavailable_defers_brigade — beach 5 not active.
	var bns := [_make_bn("B1", "Combined Arms Battalion")]
	var brigades := [_make_brigade("BDE-1", bns, 5)]
	var lookup := _make_beach_lookup({1: 8800.0, 2: 8800.0})
	var cap := OffloadCalculator.beach_capacity_bns([1, 2], lookup)

	var result := OffloadCalculator.resolve_offload_day(1, cap, brigades, ["BDE-1"])

	assert_int(result["bns_landed"]).is_equal(0)
	assert_int(result["bns_waiting"]).is_equal(1)


func test_priority_order_fills_beach_slots_in_order() -> void:
	# Lower-priority brigade (BDE-B) gets deferred if all beach slots are taken.
	# rate=2200 -> 1 slot per beach; 1 beach -> 1 slot total -> only first brigade lands.
	var bns_a := [_make_bn("A1", "Amphibious Infantry Battalion")]
	var bns_b := [_make_bn("B1", "Amphibious Infantry Battalion")]
	var brigades := [_make_brigade("BDE-A", bns_a), _make_brigade("BDE-B", bns_b)]
	var lookup := _make_beach_lookup({1: 2200.0})
	var cap := OffloadCalculator.beach_capacity_bns([1], lookup)

	var result := OffloadCalculator.resolve_offload_day(1, cap, brigades, ["BDE-A", "BDE-B"])

	assert_int(result["bns_landed"]).is_equal(1)
	assert_str(result["manifest_landed"][0]["brigade_id"]).is_equal("BDE-A")
	assert_int(result["bns_waiting"]).is_equal(1)


func test_brigades_do_not_split_across_beaches() -> void:
	# Mirrors: test_brigade_battalions_do_not_split_beaches.
	# All BNs of a brigade land at the same beach.
	var bns := [
		_make_bn("B1", "Combined Arms Battalion"),
		_make_bn("B2", "Amphibious Infantry Battalion"),
	]
	var brigades := [_make_brigade("BDE-1", bns)]
	var lookup := _make_beach_lookup({1: 8800.0, 2: 8800.0})
	var cap := OffloadCalculator.beach_capacity_bns([1, 2], lookup)

	var result := OffloadCalculator.resolve_offload_day(1, cap, brigades, ["BDE-1"])

	var beaches_used: Array = []
	for entry in result["manifest_landed"] as Array:
		var bid := int(entry["beach_id"])
		if bid not in beaches_used:
			beaches_used.append(bid)
	assert_int(beaches_used.size()).is_equal(1)

# ---------------------------------------------------------------------------
# resolve_offload_day — Day 2+ throughput gating
# ---------------------------------------------------------------------------

func test_day2_support_bns_land_up_to_throughput() -> void:
	# Day 2: support BNs land up to beach capacity.
	# 1 beach, rate=4400 -> 2 BN slots; 3 support BNs -> 2 land, 1 deferred.
	var bns := [
		_make_bn("S1", "Support Battalion"),
		_make_bn("S2", "Field Artillery Battalion"),
		_make_bn("S3", "Engineer Battalion"),
	]
	var brigades := [_make_brigade("BDE-1", bns)]
	var lookup := _make_beach_lookup({1: 4400.0})
	var cap := OffloadCalculator.beach_capacity_bns([1], lookup)

	var result := OffloadCalculator.resolve_offload_day(2, cap, brigades, ["BDE-1"])

	assert_int(result["bns_landed"]).is_equal(2)
	assert_int(result["bns_waiting"]).is_equal(1)


func test_day2_throughput_exhausted_defers_remaining() -> void:
	# Day 2: first brigade fills capacity, second gets deferred.
	var bns_a := [_make_bn("A1", "Support Battalion"), _make_bn("A2", "Support Battalion")]
	var bns_b := [_make_bn("B1", "Support Battalion")]
	var brigades := [_make_brigade("BDE-A", bns_a), _make_brigade("BDE-B", bns_b)]
	var lookup := _make_beach_lookup({1: 4400.0})  # 2 slots
	var cap := OffloadCalculator.beach_capacity_bns([1], lookup)

	var result := OffloadCalculator.resolve_offload_day(2, cap, brigades, ["BDE-A", "BDE-B"])

	assert_int(result["bns_landed"]).is_equal(2)
	assert_int(result["bns_waiting"]).is_equal(1)
	assert_str(result["manifest_deferred"][0]["brigade_id"]).is_equal("BDE-B")

# ---------------------------------------------------------------------------
# plan 0006: infra routing / cost / occupancy (day N)
# ---------------------------------------------------------------------------

func test_plan0006_defaults_regression() -> void:
	var bns := [
		_make_bn("S1", "Support Battalion"),
		_make_bn("S2", "Field Artillery Battalion"),
		_make_bn("S3", "Engineer Battalion"),
	]
	var brigades := [_make_brigade("BDE-1", bns)]
	var lookup := _make_beach_lookup({1: 4400.0})
	var cap := OffloadCalculator.beach_capacity_bns([1], lookup)

	var result := OffloadCalculator.resolve_offload_day(2, cap, brigades, ["BDE-1"])

	assert_int(result["bns_landed"]).is_equal(2)
	assert_int(result["bns_waiting"]).is_equal(1)


func test_plan0006_occupancy_valve_closes_beach() -> void:
	var bns := [_make_bn("S1", "Support Battalion")]
	var brigades := [_make_brigade("BDE-1", bns)]
	var lookup := _make_beach_lookup({1: 4400.0})
	var cap := OffloadCalculator.beach_capacity_bns([1], lookup)

	var result := OffloadCalculator.resolve_offload_day(2, cap, brigades, ["BDE-1"], [], {}, {1: 2}, {1: 2})

	assert_int(result["bns_landed"]).is_equal(0)
	assert_int(result["bns_waiting"]).is_equal(1)
	assert_str(result["manifest_deferred"][0]["reason"]).is_equal("throughput_limited")


func test_plan0006_occupancy_valve_off_when_not_in_depth() -> void:
	var bns := [_make_bn("S1", "Support Battalion")]
	var brigades := [_make_brigade("BDE-1", bns)]
	var lookup := _make_beach_lookup({1: 4400.0})
	var cap := OffloadCalculator.beach_capacity_bns([1], lookup)

	var result := OffloadCalculator.resolve_offload_day(2, cap, brigades, ["BDE-1"], [], {}, {1: 5})

	assert_int(result["bns_landed"]).is_equal(1)


func test_plan0006_occupancy_below_depth() -> void:
	var bns := [_make_bn("S1", "Support Battalion")]
	var brigades := [_make_brigade("BDE-1", bns)]
	var lookup := _make_beach_lookup({1: 4400.0})
	var cap := OffloadCalculator.beach_capacity_bns([1], lookup)

	var result := OffloadCalculator.resolve_offload_day(2, cap, brigades, ["BDE-1"], [], {}, {1: 1}, {1: 2})

	assert_int(result["bns_landed"]).is_equal(1)


func test_plan0006_beach_full_to_same_to_port() -> void:
	var bns := [_make_bn("S1", "Support Battalion")]
	var brigades := [_make_brigade("BDE-1", bns)]
	var lookup := _make_beach_lookup({1: 4400.0})
	var cap := OffloadCalculator.beach_capacity_bns([1], lookup)
	var infra := [
		{"id": "port1", "kind": "port", "to_number": 42, "rate_tons": 4400.0},
	]

	var result := OffloadCalculator.resolve_offload_day(2, cap, brigades, ["BDE-1"], infra, {}, {1: 1}, {1: 1}, {1: 42})

	assert_int(result["bns_landed"]).is_equal(1)
	var entry: Dictionary = result["manifest_landed"][0]
	assert_int(int(entry["beach_id"])).is_equal(-1)
	assert_str(String(entry["node_id"])).is_equal("port1")
	assert_str(String(entry["node_kind"])).is_equal("port")


func test_plan0006_same_to_port_preferred() -> void:
	# 2 BNs, beach fits 1 => second BN goes to infra with target_beach=1 valid
	var bns := [_make_bn("S1", "Support Battalion"), _make_bn("S2", "Support Battalion")]
	var brigades := [_make_brigade("BDE-1", bns)]
	var lookup := _make_beach_lookup({1: 2200.0})
	var cap := OffloadCalculator.beach_capacity_bns([1], lookup)
	var infra := [
		{"id": "port_any", "kind": "port", "to_number": 99, "rate_tons": 4400.0},
		{"id": "port_same", "kind": "port", "to_number": 42, "rate_tons": 4400.0},
	]

	var result := OffloadCalculator.resolve_offload_day(2, cap, brigades, ["BDE-1"], infra, {}, {}, {}, {1: 42})

	assert_int(result["bns_landed"]).is_equal(2)
	assert_int(int(result["manifest_landed"][0]["beach_id"])).is_equal(1)
	assert_str(String(result["manifest_landed"][1]["node_id"])).is_equal("port_same")


func test_plan0006_port_exhausted_to_airbridge() -> void:
	var bns := [_make_bn("S1", "Support Battalion")]
	var brigades := [_make_brigade("BDE-1", bns)]
	var lookup := _make_beach_lookup({1: 4400.0})
	var cap := OffloadCalculator.beach_capacity_bns([1], lookup)
	var infra := [
		{"id": "port_same", "kind": "port", "to_number": 42, "rate_tons": 1100.0},
		{"id": "ab_same", "kind": "airbridge", "to_number": 42, "rate_tons": 4400.0},
	]

	var result := OffloadCalculator.resolve_offload_day(2, cap, brigades, ["BDE-1"], infra, {}, {1: 1}, {1: 1}, {1: 42})

	assert_str(String(result["manifest_landed"][0]["node_id"])).is_equal("ab_same")
	assert_str(String(result["manifest_landed"][0]["node_kind"])).is_equal("airbridge")


func test_plan0006_same_to_exhausted_any_to_order() -> void:
	var bns := [_make_bn("S1", "Support Battalion"), _make_bn("S2", "Support Battalion")]
	var brigades := [_make_brigade("BDE-1", bns)]
	var lookup := _make_beach_lookup({1: 4400.0})
	var cap := OffloadCalculator.beach_capacity_bns([1], lookup)
	var infra := [
		{"id": "ab_diff", "kind": "airbridge", "to_number": 99, "rate_tons": 4400.0},
		{"id": "port_diff", "kind": "port", "to_number": 99, "rate_tons": 2200.0},
	]

	var result := OffloadCalculator.resolve_offload_day(2, cap, brigades, ["BDE-1"], infra, {}, {1: 1}, {1: 1}, {1: 42})

	assert_int(result["bns_landed"]).is_equal(2)
	assert_str(String(result["manifest_landed"][0]["node_id"])).is_equal("port_diff")
	assert_str(String(result["manifest_landed"][1]["node_id"])).is_equal("ab_diff")


func test_plan0006_all_infra_exhausted_throughput_limited() -> void:
	var bns := [_make_bn("S1", "Support Battalion")]
	var brigades := [_make_brigade("BDE-1", bns)]
	var lookup := _make_beach_lookup({1: 4400.0})
	var cap := OffloadCalculator.beach_capacity_bns([1], lookup)
	var infra := [
		{"id": "port1", "kind": "port", "to_number": 42, "rate_tons": 1100.0},
	]

	var result := OffloadCalculator.resolve_offload_day(2, cap, brigades, ["BDE-1"], infra, {}, {1: 1}, {1: 1}, {1: 42})

	assert_int(result["bns_landed"]).is_equal(0)
	assert_str(result["manifest_deferred"][0]["reason"]).is_equal("throughput_limited")


func test_plan0006_degraded_port_budget_one_bn() -> void:
	var bns := [_make_bn("S1", "Support Battalion"), _make_bn("S2", "Support Battalion")]
	var brigades := [_make_brigade("BDE-1", bns)]
	var lookup := _make_beach_lookup({1: 4400.0})
	var cap := OffloadCalculator.beach_capacity_bns([1], lookup)
	var infra := [
		{"id": "port1", "kind": "port", "to_number": 42, "rate_tons": 2200.0},
	]

	var result := OffloadCalculator.resolve_offload_day(2, cap, brigades, ["BDE-1"], infra, {}, {1: 1}, {1: 1}, {1: 42})

	assert_int(result["bns_landed"]).is_equal(1)
	assert_str(String(result["manifest_landed"][0]["node_id"])).is_equal("port1")


func test_plan0006_flat_cost_empty_config() -> void:
	var bns := [_make_bn("S1", "Support Battalion")]
	var brigades := [_make_brigade("BDE-1", bns)]
	var lookup := _make_beach_lookup({1: 2200.0})
	var cap := OffloadCalculator.beach_capacity_bns([1], lookup)
	var infra := [
		{"id": "port1", "kind": "port", "to_number": 42, "rate_tons": 2200.0},
	]

	var result := OffloadCalculator.resolve_offload_day(2, cap, brigades, ["BDE-1"], infra, {}, {}, {}, {1: 42})
	assert_int(result["bns_landed"]).is_equal(1)
	assert_int(int(result["manifest_landed"][0]["beach_id"])).is_equal(1)

	var result2 := OffloadCalculator.resolve_offload_day(2, cap, brigades, ["BDE-1"], infra, {}, {1: 1}, {1: 1}, {1: 42})
	assert_int(result2["bns_landed"]).is_equal(1)
	assert_str(String(result2["manifest_landed"][0]["node_kind"])).is_equal("port")


func test_plan0006_weight_matrix_tank_cost() -> void:
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/offload_weights.json"))
	var bns := [_make_bn("T1", "Tank Battalion"), _make_bn("T2", "Tank Battalion")]
	var brigades := [_make_brigade("BDE-1", bns)]
	var lookup := _make_beach_lookup({1: 4400.0})
	var cap := OffloadCalculator.beach_capacity_bns([1], lookup)

	var result := OffloadCalculator.resolve_offload_day(2, cap, brigades, ["BDE-1"], [], cfg)

	assert_int(result["bns_landed"]).is_equal(1)
	assert_int(result["bns_waiting"]).is_equal(1)

	var bns_flat := [_make_bn("S1", "Support Battalion"), _make_bn("S2", "Support Battalion")]
	var brigades_flat := [_make_brigade("BDE-2", bns_flat)]
	var result2 := OffloadCalculator.resolve_offload_day(2, cap, brigades_flat, ["BDE-2"])
	assert_int(result2["bns_landed"]).is_equal(2)


func test_plan0006_multiplier_amphibious_military_amphibious() -> void:
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/offload_weights.json"))
	var bns := [
		{"id": "A1", "type": "Amphibious Infantry Battalion", "ship_category": "Military_Amphibious"},
		{"id": "A2", "type": "Amphibious Infantry Battalion", "ship_category": "Military_Amphibious"},
	]
	var brigades := [_make_brigade("BDE-1", bns)]
	var lookup := _make_beach_lookup({1: 2200.0})
	var cap := OffloadCalculator.beach_capacity_bns([1], lookup)

	var result := OffloadCalculator.resolve_offload_day(2, cap, brigades, ["BDE-1"], [], cfg)

	assert_int(result["bns_landed"]).is_equal(2)


func test_plan0006_no_ship_category_default_cost() -> void:
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/offload_weights.json"))
	var bns := [_make_bn("M1", "Mechanized Infantry Battalion")]
	var brigades := [_make_brigade("BDE-1", bns)]
	var lookup := _make_beach_lookup({1: 2200.0})
	var cap := OffloadCalculator.beach_capacity_bns([1], lookup)

	var result := OffloadCalculator.resolve_offload_day(2, cap, brigades, ["BDE-1"], [], cfg)

	assert_int(result["bns_landed"]).is_equal(1)


func test_plan0006_empty_beach_to_to_any_to_port() -> void:
	var bns := [_make_bn("S1", "Support Battalion")]
	var brigades := [_make_brigade("BDE-1", bns)]
	var lookup := _make_beach_lookup({1: 4400.0})
	var cap := OffloadCalculator.beach_capacity_bns([1], lookup)
	var infra := [
		{"id": "port_any", "kind": "port", "to_number": 99, "rate_tons": 4400.0},
	]

	var result := OffloadCalculator.resolve_offload_day(2, cap, brigades, ["BDE-1"], infra, {}, {1: 1}, {1: 1}, {})

	assert_int(result["bns_landed"]).is_equal(1)
	assert_str(String(result["manifest_landed"][0]["node_id"])).is_equal("port_any")


func test_plan0006_day1_unaffected_by_new_args() -> void:
	var bns := [_make_bn("M1", "Mechanized Infantry Battalion")]
	var brigades := [_make_brigade("BDE-1", bns)]
	var lookup := _make_beach_lookup({1: 4400.0})
	var cap := OffloadCalculator.beach_capacity_bns([1], lookup)
	var infra := [
		{"id": "port1", "kind": "port", "to_number": 42, "rate_tons": 4400.0},
	]

	var result_without := OffloadCalculator.resolve_offload_day(1, cap, brigades, ["BDE-1"])
	var result_with := OffloadCalculator.resolve_offload_day(1, cap, brigades, ["BDE-1"], infra, {}, {}, {}, {})

	assert_int(result_without["bns_landed"]).is_equal(result_with["bns_landed"])
	assert_int(result_without["bns_waiting"]).is_equal(result_with["bns_waiting"])
	assert_int(result_without["bns_sent"]).is_equal(result_with["bns_sent"])
