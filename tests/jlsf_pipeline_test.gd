extends GdUnitTestSuite

# JlsfCargo pure builder tests + end-to-end sealift pipeline ride.
# Inline InfrastructureDef/BeachDef/ShipDef fixtures; no GameData/autoload access.

var _beaches: Dictionary = {}
var _beach_to_to: Dictionary = {}


func before() -> void:
	var b1 := BeachDef.new()
	b1.id = 1
	b1.to_number = 3
	b1.hex_id = "hex1"
	var b5 := BeachDef.new()
	b5.id = 5
	b5.to_number = 5
	b5.hex_id = "hex5"
	var b8 := BeachDef.new()
	b8.id = 8
	b8.to_number = 2
	b8.hex_id = "hex8"
	_beaches = {1: b1, 5: b5, 8: b8}
	_beach_to_to = {1: 3, 5: 5, 8: 2}


func _port_def(id: String, to_number: int, hex_id: String) -> InfrastructureDef:
	var d := InfrastructureDef.new()
	d.id = id
	d.kind = "port"
	d.hex_id = hex_id
	d.to_number = to_number
	return d


func _ship_def(name: String, category := "", capacity := 0.0) -> ShipDef:
	var d := ShipDef.new()
	d.name = name
	d.id = name.hash()
	d.category = category
	d.carrying_capacity_bn_equiv = capacity
	return d


# --- 1. Entry shape ------------------------------------------------------------------------------

func test_entry_shape() -> void:
	var port := _port_def("taichung", 5, "hex5")
	var entry := JlsfCargo.build_pool_entry(port, _beaches, _beach_to_to, 4)
	assert_int(entry.size()).is_equal(7)
	assert_str(String(entry.get("brigade_id", ""))).is_equal("JLSF:taichung")
	assert_str(String(entry.get("cargo", ""))).is_equal("jlsf")
	assert_str(String(entry.get("port_id", ""))).is_equal("taichung")
	assert_int(int(entry.get("locked_beach", -1))).is_equal(5)
	assert_str(String(entry.get("beach_hex", ""))).is_equal("hex5")
	assert_float(float(entry.get("offset_bearing", -1.0))).is_equal(0.0)
	var bns: Array = entry.get("bns", [])
	assert_int(bns.size()).is_equal(4)
	for i in range(4):
		var bn: Dictionary = bns[i] as Dictionary
		assert_str(String(bn.get("id", ""))).is_equal("JLSF:taichung:%d" % [i + 1])
		assert_str(String(bn.get("type", ""))).is_equal("JLSF Detachment")


# --- 2. Same-TO beach preferred ------------------------------------------------------------------

func test_same_to_beach_preferred() -> void:
	var p5 := _port_def("p5", 5, "h5")
	var e5 := JlsfCargo.build_pool_entry(p5, _beaches, _beach_to_to, 1)
	assert_int(int(e5.get("locked_beach", -1))).is_equal(5)

	var p2 := _port_def("p2", 2, "h2")
	var e2 := JlsfCargo.build_pool_entry(p2, _beaches, _beach_to_to, 1)
	assert_int(int(e2.get("locked_beach", -1))).is_equal(8)

	var p3 := _port_def("p3", 3, "h3")
	var e3 := JlsfCargo.build_pool_entry(p3, _beaches, _beach_to_to, 1)
	assert_int(int(e3.get("locked_beach", -1))).is_equal(1)


# --- 3. Fallback to lowest beach -----------------------------------------------------------------

func test_fallback_no_beach_in_to() -> void:
	var p4 := _port_def("p4", 4, "h4")
	var entry := JlsfCargo.build_pool_entry(p4, _beaches, _beach_to_to, 1)
	assert_int(int(entry.get("locked_beach", -1))).is_equal(1)


# --- 4. is_jlsf_entry ----------------------------------------------------------------------------

func test_is_jlsf_entry() -> void:
	var port := _port_def("test", 5, "h5")
	var entry := JlsfCargo.build_pool_entry(port, _beaches, _beach_to_to, 1)
	assert_bool(JlsfCargo.is_jlsf_entry(entry)).is_true()
	assert_bool(JlsfCargo.is_jlsf_entry({"brigade_id": "x", "bns": []})).is_false()


# --- 5. bn_count 1 -------------------------------------------------------------------------------

func test_bn_count_one() -> void:
	var port := _port_def("x", 5, "h5")
	var entry := JlsfCargo.build_pool_entry(port, _beaches, _beach_to_to, 1)
	var bns: Array = entry.get("bns", [])
	assert_int(bns.size()).is_equal(1)
	var bn: Dictionary = bns[0] as Dictionary
	assert_str(String(bn.get("id", ""))).is_equal("JLSF:x:1")


# --- 6. Determinism ------------------------------------------------------------------------------

func test_determinism() -> void:
	var port := _port_def("det", 5, "h5")
	var e1 := JlsfCargo.build_pool_entry(port, _beaches, _beach_to_to, 3)
	var e2 := JlsfCargo.build_pool_entry(port, _beaches, _beach_to_to, 3)
	assert_that(e1).is_equal(e2)


# --- 7. End-to-end sealift ride ------------------------------------------------------------------

func test_end_to_end_sealift_ride() -> void:
	# Build a JLSF entry for a TO-3 port and ride it through the sealift pipeline.
	var port := _port_def("keelung", 3, "hex3")
	var entry := JlsfCargo.build_pool_entry(port, _beaches, _beach_to_to, 4)

	var state := SealiftState.new()
	state.mainland_pool = [entry]

	var defs := {"LPD": _ship_def("LPD", "Military_Amphibious", 1.0)}
	var ready := {"LPD": 4}

	var result := SealiftResolver.resolve(state, [], ready, defs)

	# Cohort holds all 4 JLSF BN ids
	assert_int(state.cohorts.size()).is_equal(1)
	var cohort: Dictionary = state.cohorts[0] as Dictionary
	var bn_ids: Array = cohort.get("bn_ids", [])
	assert_int(bn_ids.size()).is_equal(4)
	for i in range(4):
		assert_str(String(bn_ids[i])).is_equal("JLSF:keelung:%d" % [i + 1])

	# NOTE: _embark_followon (SealiftResolver.gd:191-197) copies only brigade_id,
	# locked_beach, beach_hex, offset_bearing, bns into embarked entries. cargo and
	# port_id are NOT carried through. Assert the fields it preserves.
	var emb: Array = result["embarked_reserve_entries"]
	assert_int(emb.size()).is_equal(1)
	var e0: Dictionary = emb[0]
	assert_int(int(e0.get("locked_beach", -1))).is_equal(1)
	assert_str(String(e0.get("beach_hex", ""))).is_equal("hex3")
