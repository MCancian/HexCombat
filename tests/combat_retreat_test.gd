extends GdUnitTestSuite

const COMBAT_HEX := "hex_43_17"
const RED_ID := "TEST-RETREAT-RED"
const GREEN_ID := "TEST-RETREAT-GREEN"


func before_test() -> void:
	_reset_fixture()


func after_test() -> void:
	_reset_fixture()


func test_feba_threshold_retreat_moves_defender_and_flips_ownership() -> void:
	var retreat_hex := _first_neighbor(COMBAT_HEX)
	var red := _make_brigade(RED_ID, Brigade.Team.RED, [{"type": "Tank Battalion", "qty": 6}])
	var green := _make_brigade(GREEN_ID, Brigade.Team.GREEN, [{"type": "Infantry Battalion (Reserve)", "qty": 6}])
	_register_brigade(red, COMBAT_HEX)
	_register_brigade(green, COMBAT_HEX)
	GameData.hex_states[COMBAT_HEX].feba_km = 9.0
	_mark_neighbors(COMBAT_HEX, HexOwner.RED)
	GameData.hex_states[retreat_hex].owner = HexOwner.GREEN

	GameState.resolve_turn(ScriptedDice.new([50, 50, 100], [[0, 1, 2], [0, 1, 2]]))

	assert_str(green.hex_id).is_equal(retreat_hex)
	assert_str(red.hex_id).is_equal(COMBAT_HEX)
	assert_float(float(GameData.hex_states[COMBAT_HEX].feba_km)).is_equal_approx(0.0, 0.0001)
	assert_str(GameData.hex_states[COMBAT_HEX].owner).is_equal(HexOwner.RED)
	assert_bool(green.destroyed).is_false()
	assert_int(green.get_battalion_count()).is_greater(0)


func test_encircled_retreat_has_no_valid_hex_and_front_holds() -> void:
	var red := _make_brigade(RED_ID, Brigade.Team.RED, [{"type": "Tank Battalion", "qty": 6}])
	var green := _make_brigade(GREEN_ID, Brigade.Team.GREEN, [{"type": "Infantry Battalion (Reserve)", "qty": 6}])
	_register_brigade(red, COMBAT_HEX)
	_register_brigade(green, COMBAT_HEX)
	GameData.hex_states[COMBAT_HEX].feba_km = 9.0
	_mark_neighbors(COMBAT_HEX, HexOwner.RED)

	GameState.resolve_turn(ScriptedDice.new([50, 50, 100], [[0, 1, 2], [0, 1, 2]]))

	assert_str(green.hex_id).is_equal(COMBAT_HEX)
	assert_str(red.hex_id).is_equal(COMBAT_HEX)
	assert_str(GameData.hex_states[COMBAT_HEX].owner).is_equal(HexOwner.CONTESTED)
	assert_float(float(GameData.hex_states[COMBAT_HEX].feba_km)).is_greater_equal(GameStateType.FEBA_RETREAT_THRESHOLD_KM)


func test_combat_resolved_signal_emits_one_summary_for_one_contested_hex() -> void:
	var emitted_summaries: Array = []
	var capture_summaries := func(summaries: Array) -> void:
		emitted_summaries.append_array(summaries)
	EventBus.combat_resolved.connect(capture_summaries, CONNECT_ONE_SHOT)
	var red := _make_brigade(RED_ID, Brigade.Team.RED, [{"type": "Tank Battalion", "qty": 6}])
	var green := _make_brigade(GREEN_ID, Brigade.Team.GREEN, [{"type": "Infantry Battalion (Reserve)", "qty": 6}])
	_register_brigade(red, COMBAT_HEX)
	_register_brigade(green, COMBAT_HEX)

	GameState.resolve_turn(ScriptedDice.new([50, 50, 50], [[0, 1, 2], [0, 1, 2]]))

	assert_int(emitted_summaries.size()).is_equal(1)
	var summary: CombatSummary = emitted_summaries[0]
	assert_str(summary.hex_id).is_equal(COMBAT_HEX)
	assert_int(summary.attacker_losses).is_greater_equal(0)
	assert_int(summary.defender_losses).is_greater_equal(0)
	assert_str(summary.owner_after).is_not_empty()


func test_hex_owner_constants_are_written_by_recompute_ownership() -> void:
	var red_only_hex := COMBAT_HEX
	var green_only_hex := _first_neighbor(COMBAT_HEX)
	var contested_hex := _second_neighbor(COMBAT_HEX)
	_register_brigade(_make_brigade("TEST-OWNER-RED", Brigade.Team.RED, [{"type": "Tank Battalion", "qty": 1}]), red_only_hex)
	_register_brigade(_make_brigade("TEST-OWNER-GREEN", Brigade.Team.GREEN, [{"type": "Infantry Battalion (Reserve)", "qty": 1}]), green_only_hex)
	_register_brigade(_make_brigade("TEST-OWNER-RED-CONTESTED", Brigade.Team.RED, [{"type": "Tank Battalion", "qty": 1}]), contested_hex)
	_register_brigade(_make_brigade("TEST-OWNER-GREEN-CONTESTED", Brigade.Team.GREEN, [{"type": "Infantry Battalion (Reserve)", "qty": 1}]), contested_hex)

	GameData.recompute_hex_ownership()

	assert_str(GameData.hex_states[red_only_hex].owner).is_equal(HexOwner.RED)
	assert_str(GameData.hex_states[green_only_hex].owner).is_equal(HexOwner.GREEN)
	assert_str(GameData.hex_states[contested_hex].owner).is_equal(HexOwner.CONTESTED)


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


func _first_neighbor(hex_id: String) -> String:
	var neighbors := GameData.get_neighbors(hex_id)
	assert_int(neighbors.size()).is_greater(0)
	return String(neighbors[0])


func _second_neighbor(hex_id: String) -> String:
	var neighbors := GameData.get_neighbors(hex_id)
	assert_int(neighbors.size()).is_greater(1)
	return String(neighbors[1])


func _mark_neighbors(hex_id: String, owner: String) -> void:
	for neighbor_id_value in GameData.get_neighbors(hex_id):
		GameData.hex_states[String(neighbor_id_value)].owner = owner


func _reset_fixture() -> void:
	GameData.load_all()
	GameData.brigades.clear()
	GameData.brigades_by_hex.clear()
	for hex_id in GameData.hex_states:
		GameData.hex_states[String(hex_id)].owner = HexOwner.NONE
		GameData.hex_states[String(hex_id)].feba_km = 0.0
	GameState.reset_to_scenario()
	GameData.brigades.clear()
	GameData.brigades_by_hex.clear()
	for hex_id in GameData.hex_states:
		GameData.hex_states[String(hex_id)].owner = HexOwner.NONE
		GameData.hex_states[String(hex_id)].feba_km = 0.0
