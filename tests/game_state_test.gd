extends GdUnitTestSuite

# Full-defense laydown (2026-07-09): beach 1 (hex_44_16) is garrisoned by BDE-GDU, so the
# scripted mover is the beach-2 lander starting on its own (ungarrisoned) landing hex — the
# same shape the golden validators use.
const RED_BRIGADE_ID := "PLA-72-5-Amphibious"
const GREEN_BRIGADE_ID := "BDE-GDU"
const RED_START_HEX := "hex_44_15"
const GREEN_START_HEX := "hex_44_16"


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

	await assert_error(func() -> void:
		GameState.add_move_order(Brigade.Team.GREEN, RED_BRIGADE_ID, GREEN_START_HEX, "tactical")
	).is_push_error("Move order team mismatch for PLA-72-5-Amphibious: order=Green brigade=Red")
	assert_int(GameState.orders_for(Brigade.Team.GREEN).size()).is_equal(0)

	await assert_error(func() -> void:
		GameState.add_move_order(Brigade.Team.RED, "UNKNOWN-BRIGADE", GREEN_START_HEX, "tactical")
	).is_push_error("Move order references unknown brigade_id: UNKNOWN-BRIGADE")
	assert_int(GameState.orders_for(Brigade.Team.RED).size()).is_equal(1)

	await assert_error(func() -> void:
		GameState.add_move_order(Brigade.Team.RED, RED_BRIGADE_ID, "unknown_hex", "tactical")
	).is_push_error("Move order references unknown target_hex: unknown_hex")
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


func _ship_reserve_bn_count() -> int:
	var total := 0
	for reserve_entry_value in GameState.ship_reserve:
		var reserve_entry: Dictionary = reserve_entry_value
		total += (reserve_entry["bns"] as Array).size()
	return total


func _reset_fixture() -> void:
	GameData.load_all()
	GameState.reset_to_scenario()
	GameData.set_brigade_hex(RED_BRIGADE_ID, RED_START_HEX)
