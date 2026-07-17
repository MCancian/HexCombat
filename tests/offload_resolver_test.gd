extends GdUnitTestSuite

## Behavioral tests for OffloadResolver (plan 0009, phase B). Deterministic — the resolver
## consumes no dice. Covers: day-1 assault landing + first-landing reporting, day-N throughput,
## the occupancy-valve derivation from the brigades dict, and JLSF pseudo-entry gating.
## Calculator-internal math (costs, carry-over, routing) is pinned in offload_calculator_test.


# --- fixture helpers ----------------------------------------------------------------------------

func _beach(id: int, hex_id: String, offload_rate: float, depth := 2) -> BeachDef:
	var beach := BeachDef.new()
	beach.id = id
	beach.hex_id = hex_id
	beach.offload_rate = offload_rate
	beach.depth = depth
	return beach


func _brigade(id: String, hex_id := "", destroyed := false) -> Brigade:
	var brigade := Brigade.new()
	brigade.id = id
	brigade.team = Brigade.Team.RED
	brigade.hex_id = hex_id
	brigade.destroyed = destroyed
	return brigade


func _bn(id: String, type: String) -> Dictionary:
	return {"id": id, "type": type}


func _entry(brigade_id: String, bns: Array, locked_beach := 1, beach_hex := "hex_b1") -> Dictionary:
	return {
		"brigade_id": brigade_id,
		"locked_beach": locked_beach,
		"beach_hex": beach_hex,
		"offset_bearing": 45.0,
		"bns": bns,
	}


func _jlsf_entry(port_id: String, beach_hex: String, bn_ids: Array) -> Dictionary:
	var bns: Array = []
	for bn_id in bn_ids:
		bns.append(_bn(String(bn_id), JlsfCargo.BN_TYPE))
	return {
		"cargo": "jlsf",
		"port_id": port_id,
		"brigade_id": JlsfCargo.brigade_id_for(port_id),
		"locked_beach": 0,
		"beach_hex": beach_hex,
		"offset_bearing": 0.0,
		"bns": bns,
	}


# --- day 1: assault landing ----------------------------------------------------------------------

func test_day1_maneuver_bns_land_and_first_landing_is_reported() -> void:
	var beaches := {1: _beach(1, "hex_b1", 4400.0)}
	var brigades := {"BdeA": _brigade("BdeA")}  # not yet ashore -> first landing
	var reserve := [_entry("BdeA", [
		_bn("a1", "Combined Arms Battalion"),
		_bn("a2", "Combined Arms Battalion"),
		_bn("a3", "Artillery Battalion"),
	])]

	var result := OffloadResolver.resolve(1, reserve, beaches, brigades)

	var manifest: Dictionary = result["manifest"]
	assert_int(int(manifest["bns_landed"])).is_equal(2)   # maneuver BNs bypass throughput on day 1
	assert_int(int(manifest["bns_waiting"])).is_equal(1)  # support waits offshore
	assert_array(manifest["landed_brigade_ids"]).is_equal(["BdeA"])

	assert_int(result["landings"].size()).is_equal(1)
	var landing: Dictionary = result["landings"][0]
	assert_str(String(landing["beach_hex"])).is_equal("hex_b1")
	assert_float(float(landing["offset_bearing"])).is_equal_approx(45.0, 0.0001)

	# The support BN stays in the reserve entry (mutated in place).
	assert_int(result["remaining_ship_reserve"].size()).is_equal(1)
	var remaining_bns: Array = (result["remaining_ship_reserve"][0] as Dictionary)["bns"]
	assert_int(remaining_bns.size()).is_equal(1)
	assert_str(String((remaining_bns[0] as Dictionary)["id"])).is_equal("a3")


# --- day N: throughput + no duplicate landing report ----------------------------------------------

func test_day_n_lands_by_throughput_and_ashore_brigade_reports_no_landing() -> void:
	var beaches := {1: _beach(1, "hex_b1", 4400.0)}  # 4400 tons = 2 flat-cost BNs per day
	var brigades := {"BdeA": _brigade("BdeA", "hex_inland")}  # already ashore
	var reserve := [_entry("BdeA", [
		_bn("a1", "Artillery Battalion"),
		_bn("a2", "Artillery Battalion"),
		_bn("a3", "Artillery Battalion"),
	])]

	var result := OffloadResolver.resolve(2, reserve, beaches, brigades)

	var manifest: Dictionary = result["manifest"]
	assert_int(int(manifest["bns_landed"])).is_equal(2)
	assert_int(int(manifest["bns_waiting"])).is_equal(1)
	# Already ashore: BNs flow in, but no first-landing placement is emitted.
	assert_array(result["landings"]).is_empty()
	assert_array(manifest["landed_brigade_ids"]).is_empty()
	assert_int((result["remaining_ship_reserve"][0] as Dictionary)["bns"].size()).is_equal(1)


# --- occupancy valve derivation --------------------------------------------------------------------

func test_occupancy_valve_derived_from_landed_brigades_closes_beach() -> void:
	var beaches := {1: _beach(1, "hex_b1", 4400.0, 1)}  # depth 1
	var brigades := {
		"BdeA": _brigade("BdeA", "hex_inland"),
		"BdeHold": _brigade("BdeHold", "hex_b1"),  # RED brigade sitting on the beach hex
	}
	var reserve := [_entry("BdeA", [_bn("a1", "Artillery Battalion")])]

	var result := OffloadResolver.resolve(2, reserve, beaches, brigades)

	var manifest: Dictionary = result["manifest"]
	assert_int(int(manifest["bns_landed"])).is_equal(0)
	assert_int(int(manifest["bns_waiting"])).is_equal(1)


func test_occupancy_valve_ignores_destroyed_brigades() -> void:
	var beaches := {1: _beach(1, "hex_b1", 4400.0, 1)}
	var brigades := {
		"BdeA": _brigade("BdeA", "hex_inland"),
		"BdeDead": _brigade("BdeDead", "hex_b1", true),  # destroyed -> does not block
	}
	var reserve := [_entry("BdeA", [_bn("a1", "Artillery Battalion")])]

	var result := OffloadResolver.resolve(2, reserve, beaches, brigades)

	assert_int(int(result["manifest"]["bns_landed"])).is_equal(1)


# --- JLSF pseudo-entries ----------------------------------------------------------------------------

func test_jlsf_entry_delivers_whole_when_target_hex_is_red() -> void:
	var beaches := {1: _beach(1, "hex_b1", 4400.0)}
	var brigades := {"BdeA": _brigade("BdeA", "hex_inland")}
	var reserve: Array = [
		_entry("BdeA", [_bn("a1", "Artillery Battalion")]),
		_jlsf_entry("port_x", "hex_port", ["j1", "j2"]),
	]

	var result := OffloadResolver.resolve(
		2, reserve, beaches, brigades, [], {}, {}, {"hex_port": "red"})

	assert_int(result["jlsf_arrivals"].size()).is_equal(1)
	var arrival: Dictionary = result["jlsf_arrivals"][0]
	assert_str(String(arrival["port_id"])).is_equal("port_x")
	assert_array(arrival["bn_ids"]).is_equal(["j1", "j2"])
	# Delivered whole: the JLSF entry leaves the reserve; the troop entry stays (its BN landed,
	# entry emptied -> dropped too).
	for remaining_value in result["remaining_ship_reserve"]:
		assert_bool(JlsfCargo.is_jlsf_entry(remaining_value as Dictionary)).is_false()


func test_jlsf_entry_waits_offshore_while_target_hex_not_red() -> void:
	var beaches := {1: _beach(1, "hex_b1", 4400.0)}
	var brigades := {"BdeA": _brigade("BdeA", "hex_inland")}
	var reserve: Array = [
		_entry("BdeA", [_bn("a1", "Artillery Battalion")]),
		_jlsf_entry("port_x", "hex_port", ["j1"]),
	]

	var result := OffloadResolver.resolve(
		2, reserve, beaches, brigades, [], {}, {}, {"hex_port": "green"})

	assert_array(result["jlsf_arrivals"]).is_empty()
	var kept_jlsf := false
	for remaining_value in result["remaining_ship_reserve"]:
		if JlsfCargo.is_jlsf_entry(remaining_value as Dictionary):
			kept_jlsf = true
	assert_bool(kept_jlsf).is_true()
