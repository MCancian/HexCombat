extends GdUnitTestSuite

const RED_BRIGADE_ID := "PLA-71-2-Amphibious"
const GREEN_BRIGADE_ID := "BDE-66"
const COMBAT_HEX := "hex_43_16"
const EMPTY_HEX := "hex_40_16"


func before_test() -> void:
	_reset_fixture()


func after_test() -> void:
	_reset_fixture()


func test_combat_forces_split_maneuver_and_support() -> void:
	var brigade := _make_brigade("TEST-SPLIT", Brigade.Team.RED, [
		{"type": "Amphibious Infantry Battalion", "qty": 2},
		{"type": "Mechanized Artillery Battalion", "qty": 1},
		{"type": "Rocket Artillery Battalion", "qty": 2},
		{"type": "Attack Helicopter Battalion", "qty": 1}
	])

	var maneuver := CombatForces.maneuver_units([brigade])
	var support := CombatForces.support_counts([brigade])

	assert_int(maneuver.size()).is_equal(2)
	assert_str(maneuver[0]["brigade_id"]).is_equal("TEST-SPLIT")
	assert_str(maneuver[0]["type"]).is_equal("Amphibious Infantry Battalion")
	assert_int(support["artillery"]).is_equal(1)
	assert_int(support["rocket_artillery"]).is_equal(2)
	assert_int(support["rotary_wing"]).is_equal(1)
	assert_int(support["cas"]).is_equal(0)
	assert_int(support["crbm"]).is_equal(0)


func test_single_hex_combat_applies_casualties_feba_and_fought_flags() -> void:
	var red: Brigade = GameData.get_brigade(RED_BRIGADE_ID)
	var green: Brigade = GameData.get_brigade(GREEN_BRIGADE_ID)
	GameData.set_brigade_hex(RED_BRIGADE_ID, COMBAT_HEX)
	GameData.set_brigade_hex(GREEN_BRIGADE_ID, COMBAT_HEX)
	var start_feba := float(GameData.hex_states[COMBAT_HEX]["feba_km"])

	GameState.resolve_turn(ScriptedDice.new([50, 100, 100], [[0], [0]]))

	assert_int(_battalion_qty(red, "Amphibious Infantry Battalion")).is_equal(3)
	assert_int(_battalion_qty(green, "Amphibious Infantry Battalion")).is_equal(1)
	# FEBA delta scales linearly with GameData.feba_base_km (3.5, TIV value): 1.0 @ base 2.0 → 1.75 @ 3.5.
	assert_float(float(GameData.hex_states[COMBAT_HEX]["feba_km"]) - start_feba).is_equal_approx(1.75, 0.0001)
	assert_bool(red.fought_this_turn).is_true()
	assert_bool(green.fought_this_turn).is_true()


func test_ownership_by_occupancy_after_combat_and_contested_presence() -> void:
	var red := _make_brigade("TEST-RED-OWNER", Brigade.Team.RED, [{"type": "Tank Battalion", "qty": 1}])
	var green := _make_brigade("TEST-GREEN-OWNER", Brigade.Team.GREEN, [{"type": "Infantry Battalion (Reserve)", "qty": 1}])
	_register_brigade(red, EMPTY_HEX)
	_register_brigade(green, EMPTY_HEX)

	GameState.resolve_turn(ScriptedDice.new([50, 100, 100], [[0]]))

	assert_bool(green.destroyed).is_true()
	assert_array(GameData.get_brigades_in_hex(EMPTY_HEX)).not_contains([green.id])
	assert_str(GameData.hex_states[EMPTY_HEX]["owner"]).is_equal("red")

	var contested_hex := "hex_41_16"
	var red_contested := _make_brigade("TEST-RED-CONTESTED", Brigade.Team.RED, [{"type": "Tank Battalion", "qty": 1}])
	var green_contested := _make_brigade("TEST-GREEN-CONTESTED", Brigade.Team.GREEN, [{"type": "Tank Battalion", "qty": 1}])
	_register_brigade(red_contested, contested_hex)
	_register_brigade(green_contested, contested_hex)
	GameData.recompute_hex_ownership()

	assert_str(GameData.hex_states[contested_hex]["owner"]).is_equal("contested")


func test_admin_moved_brigade_is_excluded_and_no_combat_occurs() -> void:
	var red: Brigade = GameData.get_brigade(RED_BRIGADE_ID)
	var green: Brigade = GameData.get_brigade(GREEN_BRIGADE_ID)
	GameData.set_brigade_hex(RED_BRIGADE_ID, COMBAT_HEX)
	GameData.set_brigade_hex(GREEN_BRIGADE_ID, COMBAT_HEX)
	red.moved_admin_this_turn = true
	var red_start_qty := _battalion_qty(red, "Amphibious Infantry Battalion")
	var green_start_qty := _battalion_qty(green, "Amphibious Infantry Battalion")
	var start_feba := float(GameData.hex_states[COMBAT_HEX]["feba_km"])

	GameState.resolve_turn(ScriptedDice.new([]))

	assert_int(_battalion_qty(red, "Amphibious Infantry Battalion")).is_equal(red_start_qty)
	assert_int(_battalion_qty(green, "Amphibious Infantry Battalion")).is_equal(green_start_qty)
	assert_float(float(GameData.hex_states[COMBAT_HEX]["feba_km"])).is_equal_approx(start_feba, 0.0001)
	assert_bool(red.fought_this_turn).is_false()
	assert_bool(green.fought_this_turn).is_false()


func test_seeded_dice_resolution_is_deterministic() -> void:
	var first := _run_seeded_fixture(12345)
	var second := _run_seeded_fixture(12345)

	assert_int(first["red_qty"]).is_equal(second["red_qty"])
	assert_int(first["green_qty"]).is_equal(second["green_qty"])
	assert_float(first["feba"]).is_equal_approx(second["feba"], 0.000001)


func _run_seeded_fixture(seed_value: int) -> Dictionary:
	_reset_fixture()
	var red: Brigade = GameData.get_brigade(RED_BRIGADE_ID)
	var green: Brigade = GameData.get_brigade(GREEN_BRIGADE_ID)
	GameData.set_brigade_hex(RED_BRIGADE_ID, COMBAT_HEX)
	GameData.set_brigade_hex(GREEN_BRIGADE_ID, COMBAT_HEX)
	GameState.resolve_turn(SeededDice.new(seed_value))
	return {
		"red_qty": _battalion_qty(red, "Amphibious Infantry Battalion"),
		"green_qty": _battalion_qty(green, "Amphibious Infantry Battalion"),
		"feba": float(GameData.hex_states[COMBAT_HEX]["feba_km"])
	}


func _make_brigade(brigade_id: String, team: Brigade.Team, battalions: Array) -> Brigade:
	var brigade := Brigade.new()
	brigade.id = brigade_id
	brigade.name = brigade_id
	brigade.team = team
	for battalion_data in battalions:
		var battalion := Battalion.new()
		battalion.type = String(battalion_data["type"])
		battalion.qty = int(battalion_data["qty"])
		brigade.composition.append(battalion)
	return brigade


func _register_brigade(brigade: Brigade, hex_id: String) -> void:
	GameData.brigades[brigade.id] = brigade
	GameData.set_brigade_hex(brigade.id, hex_id)


func _battalion_qty(brigade: Brigade, battalion_type: String) -> int:
	for battalion in brigade.composition:
		if battalion.type == battalion_type:
			return battalion.qty
	return 0


func _reset_fixture() -> void:
	GameData.load_all()
	GameState.reset_to_scenario()
