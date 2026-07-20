extends GdUnitTestSuite

# Scripted-turn shape shared with the golden validators — tools/GoldenScript.gd.
const RED_BRIGADE_ID := GoldenScript.RED_MOVER_ID
const GREEN_BRIGADE_ID := GoldenScript.GREEN_DEFENDER_ID
const RED_START_HEX := GoldenScript.START_HEX
const GREEN_START_HEX := GoldenScript.TARGET_HEX


func before_test() -> void:
	_reset_fixture()


func after_test() -> void:
	_reset_fixture()


func test_reset_to_scenario_initializes_turn_phase_days_and_empty_buffers() -> void:
	GameState.reset_to_scenario()

	assert_int(GameState.turn_number).is_equal(1)
	assert_int(GameState.phase).is_equal(GameStateType.Phase.PLANNING)
	assert_int(GameState.turn_length_days).is_equal(1)
	assert_int(GameState.orders_for(Brigade.Team.RED).size()).is_equal(0)
	assert_int(GameState.orders_for(Brigade.Team.GREEN).size()).is_equal(0)
	assert_int(GameState.ship_reserve.size()).is_equal(4)
	assert_array(GameState.ship_reserve_priority_order()).is_equal([
		"PLA-71-2-Amphibious",
		"PLA-72-5-Amphibious",
		"PLA-73-14-Amphibious",
		"PLA-74-1-Amphibious"
	])
	assert_int(GameState.fleet.size()).is_equal(27)
	var cg_state: ShipState = GameState.fleet["CG"]
	var cg_def: ShipDef = GameData.get_ship_def(1)
	assert_float(cg_def.carrying_capacity_bn_equiv).is_equal(0.0)
	assert_int(cg_state.ready).is_equal(cg_def.total_count)
	assert_bool(cg_state.validate()).is_true()
	var lha_state: ShipState = GameState.fleet["LHA"]
	var lha_def: ShipDef = GameData.get_ship_def(5)
	assert_float(lha_def.carrying_capacity_bn_equiv).is_equal(1.0)
	assert_int(lha_state.ready).is_equal(lha_def.total_count)
	assert_bool(lha_state.validate()).is_true()


func test_add_move_order_collects_valid_orders_and_rejects_invalid_orders() -> void:
	GameState.add_move_order(Brigade.Team.RED, RED_BRIGADE_ID, GREEN_START_HEX, "tactical")

	assert_int(GameState.orders_for(Brigade.Team.RED).size()).is_equal(1)
	assert_int(GameState.orders_for(Brigade.Team.GREEN).size()).is_equal(0)
	var order: MoveOrder = GameState.orders_for(Brigade.Team.RED)[0]
	assert_str(order.brigade_id).is_equal(RED_BRIGADE_ID)
	assert_str(order.target_hex).is_equal(GREEN_START_HEX)
	assert_str(order.mode).is_equal("tactical")

	var mismatch := GameState.add_move_order(Brigade.Team.GREEN, RED_BRIGADE_ID, GREEN_START_HEX, "tactical")
	assert_bool(mismatch.ok).is_false()
	assert_int(mismatch.code).is_equal(OrderResult.Code.TEAM_MISMATCH)
	assert_int(GameState.orders_for(Brigade.Team.GREEN).size()).is_equal(0)

	var unknown_brigade := GameState.add_move_order(Brigade.Team.RED, "UNKNOWN-BRIGADE", GREEN_START_HEX, "tactical")
	assert_bool(unknown_brigade.ok).is_false()
	assert_int(unknown_brigade.code).is_equal(OrderResult.Code.UNKNOWN_BRIGADE)
	assert_int(GameState.orders_for(Brigade.Team.RED).size()).is_equal(1)

	var unknown_hex := GameState.add_move_order(Brigade.Team.RED, RED_BRIGADE_ID, "unknown_hex", "tactical")
	assert_bool(unknown_hex.ok).is_false()
	assert_int(unknown_hex.code).is_equal(OrderResult.Code.UNKNOWN_HEX)
	assert_int(GameState.orders_for(Brigade.Team.RED).size()).is_equal(1)


func test_resolve_turn_applies_all_movement_before_contested_detection() -> void:
	GameState.add_move_order(Brigade.Team.RED, RED_BRIGADE_ID, GREEN_START_HEX, "tactical")

	GameState.resolve_turn()

	var red_brigade: Brigade = GameData.get_brigade(RED_BRIGADE_ID)
	var green_brigade: Brigade = GameData.get_brigade(GREEN_BRIGADE_ID)
	assert_str(red_brigade.hex_id).is_equal(GREEN_START_HEX)
	assert_str(green_brigade.hex_id).is_equal(GREEN_START_HEX)
	assert_array(GameState.last_contested_hexes).contains([GREEN_START_HEX])
	assert_int(GameState.phase).is_equal(GameStateType.Phase.END)


func test_resolve_turn_skips_disabled_movement_and_ground_combat() -> void:
	var phases: Array[String] = ["movement", "ground_combat"]
	GameData.disabled_phases = phases
	GameState.add_move_order(Brigade.Team.RED, RED_BRIGADE_ID, GREEN_START_HEX, "tactical")

	GameState.resolve_turn()

	var red_brigade: Brigade = GameData.get_brigade(RED_BRIGADE_ID)
	assert_str(red_brigade.hex_id).is_equal(RED_START_HEX)
	assert_bool(red_brigade.moved_this_turn).is_false()
	assert_int(GameState.last_contested_hexes.size()).is_equal(0)
	assert_int(GameState.last_combat_summaries.size()).is_equal(0)
	assert_int(GameState.phase).is_equal(GameStateType.Phase.END)


func test_load_scenario_rejects_unknown_disable_phases_entry() -> void:
	await assert_error(func() -> void:
		GameData.disabled_phases = GameData._parse_disabled_phases(["teleport"])
	).is_push_error("Unknown disable_phases entry 'teleport' (allowed: movement, ground_combat)")
	assert_int(GameData.disabled_phases.size()).is_equal(0)


func test_begin_next_turn_resets_flags_buffers_turn_and_phase() -> void:
	GameState.add_move_order(Brigade.Team.RED, RED_BRIGADE_ID, GREEN_START_HEX, "tactical")
	GameState.resolve_turn()

	var moved_brigade: Brigade = GameData.get_brigade(RED_BRIGADE_ID)
	assert_bool(moved_brigade.moved_this_turn).is_true()

	GameState.begin_next_turn()

	for brigade in GameData.brigades.values():
		var typed_brigade: Brigade = brigade
		assert_bool(typed_brigade.moved_this_turn).is_false()
		assert_bool(typed_brigade.fought_this_turn).is_false()
	assert_int(GameState.orders_for(Brigade.Team.RED).size()).is_equal(0)
	assert_int(GameState.orders_for(Brigade.Team.GREEN).size()).is_equal(0)
	assert_int(GameState.turn_number).is_equal(2)
	assert_int(GameState.phase).is_equal(GameStateType.Phase.PLANNING)


func _reset_fixture() -> void:
	GameData.load_all()
	GameState.reset_to_scenario()
	GameData.set_brigade_hex(RED_BRIGADE_ID, RED_START_HEX)
