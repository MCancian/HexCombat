## GdUnit4 tests for OffloadCostModel — mirrors data-driven weight/multiplier cost model.
extends GdUnitTestSuite

var _config: Dictionary = {}


func before() -> void:
	_config = JSON.parse_string(FileAccess.get_file_as_string("res://data/offload_weights.json"))


# ---------------------------------------------------------------------------
# flat_config
# ---------------------------------------------------------------------------

func test_flat_config_always_returns_tons_per_bn() -> void:
	var flat := OffloadCostModel.flat_config()
	var combos := [
		["Amphibious Infantry Battalion", "Military_Amphibious", "beach"],
		["Tank Battalion", "Civilian_Non_Amphibious", "port"],
		["Combined Arms Battalion", "Weird_Cat", "airbridge"],
		["Air Defense Battalion", "Military_Amphibious", "beach"],
	]
	for combo in combos:
		var cost := OffloadCostModel.bn_cost_tons(combo[0], combo[1], combo[2], flat)
		assert_float(cost).is_equal(OffloadRates.TONS_PER_BN)

# ---------------------------------------------------------------------------
# Beach: amphibious class — Military_Amphibious gets 0.5×
# ---------------------------------------------------------------------------

func test_amphib_bn_mil_amph_beach() -> void:
	var cost := OffloadCostModel.bn_cost_tons("Amphibious Infantry Battalion", "Military_Amphibious", "beach", _config)
	assert_float(cost).is_equal(1100.0)


func test_amphib_bn_civilian_amph_beach() -> void:
	var cost := OffloadCostModel.bn_cost_tons("Amphibious Infantry Battalion", "Civilian_Amphibious", "beach", _config)
	assert_float(cost).is_equal(2200.0)

# ---------------------------------------------------------------------------
# Beach: standard class — Civilian_Non_Amphibious gets 2.0×, Military_Amphibious gets 1.0×
# ---------------------------------------------------------------------------

func test_mech_inf_civ_non_amph_beach() -> void:
	var cost := OffloadCostModel.bn_cost_tons("Mechanized Infantry Battalion", "Civilian_Non_Amphibious", "beach", _config)
	assert_float(cost).is_equal(4400.0)


func test_mech_inf_mil_amph_beach() -> void:
	var cost := OffloadCostModel.bn_cost_tons("Mechanized Infantry Battalion", "Military_Amphibious", "beach", _config)
	assert_float(cost).is_equal(2200.0)

# ---------------------------------------------------------------------------
# Beach: standard class — no ship-category match hits default 1.0×
# ---------------------------------------------------------------------------

func test_tank_bn_mil_amph_beach() -> void:
	var cost := OffloadCostModel.bn_cost_tons("Tank Battalion", "Military_Amphibious", "beach", _config)
	assert_float(cost).is_equal(3300.0)

# ---------------------------------------------------------------------------
# Port / airbridge: all types get weight × 1.0
# ---------------------------------------------------------------------------

func test_port_multiplier_is_1x() -> void:
	var combos := [
		["Amphibious Infantry Battalion", "Military_Amphibious", "port", 2200.0],
		["Tank Battalion", "Civilian_Non_Amphibious", "port", 3300.0],
	]
	for combo in combos:
		var cost := OffloadCostModel.bn_cost_tons(combo[0], combo[1], combo[2], _config)
		assert_float(cost).is_equal(combo[3])


func test_airbridge_multiplier_is_1x() -> void:
	var combos := [
		["Amphibious Infantry Battalion", "Military_Amphibious", "airbridge", 2200.0],
		["Tank Battalion", "Civilian_Non_Amphibious", "airbridge", 3300.0],
	]
	for combo in combos:
		var cost := OffloadCostModel.bn_cost_tons(combo[0], combo[1], combo[2], _config)
		assert_float(cost).is_equal(combo[3])

# ---------------------------------------------------------------------------
# Unknown bn_type: falls back to default_tons with standard-class multipliers
# ---------------------------------------------------------------------------

func test_unknown_bn_type_uses_default_tons() -> void:
	var cost := OffloadCostModel.bn_cost_tons("Some Unknown Type", "Civilian_Non_Amphibious", "beach", _config)
	assert_float(cost).is_equal(4400.0)

# ---------------------------------------------------------------------------
# Unknown ship_category: falls back to class-level "default" multiplier
# ---------------------------------------------------------------------------

func test_unknown_ship_category_uses_class_default() -> void:
	var cost := OffloadCostModel.bn_cost_tons("Amphibious Infantry Battalion", "Weird_Cat", "beach", _config)
	assert_float(cost).is_equal(2200.0)

# ---------------------------------------------------------------------------
# Unknown node_kind: falls back to top-level "default" multiplier
# ---------------------------------------------------------------------------

func test_unknown_node_kind_uses_top_default() -> void:
	var cost := OffloadCostModel.bn_cost_tons("Amphibious Infantry Battalion", "Military_Amphibious", "orbital", _config)
	assert_float(cost).is_equal(2200.0)

# ---------------------------------------------------------------------------
# Empty config: everything falls back to OffloadRates.TONS_PER_BN and 1.0
# ---------------------------------------------------------------------------

func test_empty_config_uses_all_defaults() -> void:
	var cost := OffloadCostModel.bn_cost_tons("Amphibious Infantry Battalion", "Military_Amphibious", "beach", {})
	assert_float(cost).is_equal(OffloadRates.TONS_PER_BN)
