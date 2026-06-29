extends GdUnitTestSuite

const TARGET_HEX := "hex_40_16"
const ADJACENT_HEX := "hex_41_16"
const OTHER_ADJACENT_HEX := "hex_40_17"
const NON_ADJACENT_HEX := "hex_44_16"


func before_test() -> void:
	_reset_fixture()


func after_test() -> void:
	_reset_fixture()


func test_add_commit_order_validation_and_one_order_per_brigade() -> void:
	var red_adjacent := _make_brigade("TEST-RED-ADJ", Brigade.Team.RED, ADJACENT_HEX)
	var red_in_hex := _make_brigade("TEST-RED-IN", Brigade.Team.RED, TARGET_HEX)
	var red_far := _make_brigade("TEST-RED-FAR", Brigade.Team.RED, NON_ADJACENT_HEX)
	_register_brigade(red_adjacent)
	_register_brigade(red_in_hex)
	_register_brigade(red_far)

	GameState.add_commit_order(Brigade.Team.RED, red_adjacent.id, TARGET_HEX)
	assert_int(GameState.commitments_for(Brigade.Team.RED).size()).is_equal(1)
	var order: CommitOrder = GameState.commitments_for(Brigade.Team.RED)[0]
	assert_str(order.brigade_id).is_equal(red_adjacent.id)
	assert_str(order.target_hex).is_equal(TARGET_HEX)

	await assert_error(func() -> void:
		GameState.add_commit_order(Brigade.Team.GREEN, red_far.id, TARGET_HEX)
	).is_push_error("Commit order team mismatch for TEST-RED-FAR: order=Green brigade=Red")
	assert_int(GameState.commitments_for(Brigade.Team.GREEN).size()).is_equal(0)

	await assert_error(func() -> void:
		GameState.add_commit_order(Brigade.Team.RED, red_in_hex.id, TARGET_HEX)
	).is_push_error("Commit order brigade is already in target hex: TEST-RED-IN")
	assert_int(GameState.commitments_for(Brigade.Team.RED).size()).is_equal(1)

	await assert_error(func() -> void:
		GameState.add_commit_order(Brigade.Team.RED, red_far.id, TARGET_HEX)
	).is_push_error("Commit order brigade TEST-RED-FAR is not adjacent to target_hex: hex_40_16")
	assert_int(GameState.commitments_for(Brigade.Team.RED).size()).is_equal(1)

	GameState.add_move_order(Brigade.Team.RED, red_far.id, ADJACENT_HEX, Movement.MODE_ADMINISTRATIVE)
	await assert_error(func() -> void:
		GameState.add_commit_order(Brigade.Team.RED, red_far.id, TARGET_HEX)
	).is_push_error("Commit order brigade TEST-RED-FAR is not adjacent to target_hex: hex_40_16")

	var red_move_then_commit := _make_brigade("TEST-RED-MOVE-FIRST", Brigade.Team.RED, OTHER_ADJACENT_HEX)
	_register_brigade(red_move_then_commit)
	GameState.add_move_order(Brigade.Team.RED, red_move_then_commit.id, ADJACENT_HEX, Movement.MODE_TACTICAL)
	await assert_error(func() -> void:
		GameState.add_commit_order(Brigade.Team.RED, red_move_then_commit.id, TARGET_HEX)
	).is_push_error("Brigade already has a pending move order this turn: TEST-RED-MOVE-FIRST")

	var red_commit_then_move := _make_brigade("TEST-RED-COMMIT-FIRST", Brigade.Team.RED, OTHER_ADJACENT_HEX)
	_register_brigade(red_commit_then_move)
	GameState.add_commit_order(Brigade.Team.RED, red_commit_then_move.id, TARGET_HEX)
	var move_count_before := GameState.orders_for(Brigade.Team.RED).size()
	await assert_error(func() -> void:
		GameState.add_move_order(Brigade.Team.RED, red_commit_then_move.id, ADJACENT_HEX, Movement.MODE_TACTICAL)
	).is_push_error("Brigade already has a pending commit order this turn: TEST-RED-COMMIT-FIRST")
	assert_int(GameState.orders_for(Brigade.Team.RED).size()).is_equal(move_count_before)


func test_eligible_commit_brigades_filters_by_adjacency_position_admin_and_orders() -> void:
	var eligible := _make_brigade("TEST-ELIGIBLE", Brigade.Team.RED, ADJACENT_HEX)
	var in_hex := _make_brigade("TEST-IN-HEX", Brigade.Team.RED, TARGET_HEX)
	var far := _make_brigade("TEST-FAR", Brigade.Team.RED, NON_ADJACENT_HEX)
	var admin := _make_brigade("TEST-ADMIN", Brigade.Team.RED, OTHER_ADJACENT_HEX)
	var moved := _make_brigade("TEST-MOVED", Brigade.Team.RED, "hex_39_16")
	admin.moved_admin_this_turn = true
	_register_brigade(eligible)
	_register_brigade(in_hex)
	_register_brigade(far)
	_register_brigade(admin)
	_register_brigade(moved)
	GameState.add_move_order(Brigade.Team.RED, moved.id, "hex_39_15", Movement.MODE_TACTICAL)

	var options := GameState.eligible_commit_brigades(Brigade.Team.RED, TARGET_HEX)

	assert_array(options).contains([eligible.id])
	assert_array(options).not_contains([in_hex.id])
	assert_array(options).not_contains([far.id])
	assert_array(options).not_contains([admin.id])
	assert_array(options).not_contains([moved.id])


func test_committed_forces_affect_combat_and_are_marked_fought() -> void:
	var red_in_hex := _make_brigade("TEST-RED-PRESENT", Brigade.Team.RED, TARGET_HEX, 1)
	var green_in_hex := _make_brigade("TEST-GREEN-PRESENT", Brigade.Team.GREEN, TARGET_HEX, 1)
	var red_committed := _make_brigade("TEST-RED-COMMITTED", Brigade.Team.RED, ADJACENT_HEX, 2)
	_register_brigade(red_in_hex)
	_register_brigade(green_in_hex)
	_register_brigade(red_committed)
	GameState.add_commit_order(Brigade.Team.RED, red_committed.id, TARGET_HEX)
	var red_contributors: Array = GameState._combat_contributors_for(Brigade.Team.RED, TARGET_HEX)
	assert_array(GameState._brigade_ids(red_contributors)).contains([red_committed.id])
	assert_int(CombatForces.maneuver_units(red_contributors).size()).is_equal(3)

	GameState.resolve_turn(ScriptedDice.new([50, 50, 50], [[0], [0]]))

	assert_array(GameState.last_contested_hexes).contains([TARGET_HEX])
	assert_bool(red_committed.fought_this_turn).is_true()


func test_begin_next_turn_clears_commitments() -> void:
	var red_adjacent := _make_brigade("TEST-RED-CLEAR", Brigade.Team.RED, ADJACENT_HEX)
	var red_present := _make_brigade("TEST-RED-CLEAR-PRESENT", Brigade.Team.RED, TARGET_HEX)
	var green_present := _make_brigade("TEST-GREEN-CLEAR-PRESENT", Brigade.Team.GREEN, TARGET_HEX)
	_register_brigade(red_adjacent)
	_register_brigade(red_present)
	_register_brigade(green_present)
	GameState.add_commit_order(Brigade.Team.RED, red_adjacent.id, TARGET_HEX)
	assert_int(GameState.commitments_for(Brigade.Team.RED).size()).is_equal(1)

	GameState.resolve_turn(ScriptedDice.new([50, 50, 50], [[0], [0]]))
	GameState.begin_next_turn()

	assert_int(GameState.commitments_for(Brigade.Team.RED).size()).is_equal(0)
	assert_int(GameState.commitments_for(Brigade.Team.GREEN).size()).is_equal(0)


func _make_brigade(brigade_id: String, team: Brigade.Team, hex_id: String, infantry_qty: int = 1) -> Brigade:
	var brigade := Brigade.new()
	brigade.id = brigade_id
	brigade.name = brigade_id
	brigade.team = team
	brigade.hex_id = hex_id
	var battalion := Battalion.new()
	battalion.type = "Infantry Battalion (Reserve)"
	battalion.qty = infantry_qty
	brigade.composition.append(battalion)
	return brigade


func _register_brigade(brigade: Brigade) -> void:
	GameData.brigades[brigade.id] = brigade
	GameData.set_brigade_hex(brigade.id, brigade.hex_id)


func _reset_fixture() -> void:
	GameData.load_all()
	GameState.reset_to_scenario()
