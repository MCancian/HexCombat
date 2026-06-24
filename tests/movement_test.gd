extends GdUnitTestSuite

const RED_BRIGADE_ID := "PLA-71-2-Amphibious"


func before_test() -> void:
	_reset_fixture()


func after_test() -> void:
	_reset_fixture()


func test_movement_speeds_and_unknown_mode_error() -> void:
	var fast_brigade := Brigade.new()
	fast_brigade.nato_type = "amphibious"
	var fast_battalion := Battalion.new()
	fast_battalion.type = "Armor Battalion"
	fast_battalion.qty = 1
	fast_brigade.composition.append(fast_battalion)

	assert_bool(Movement.is_fast_mobility(fast_brigade)).is_true()
	assert_int(Movement.tactical_speed(fast_brigade)).is_equal(Movement.TACTICAL_FAST)
	assert_int(Movement.administrative_speed(fast_brigade)).is_equal(Movement.ADMIN_FAST)

	var slow_brigade := Brigade.new()
	slow_brigade.nato_type = "reserve"
	var slow_battalion := Battalion.new()
	slow_battalion.type = "Infantry Battalion (Reserve)"
	slow_battalion.qty = 1
	slow_brigade.composition.append(slow_battalion)

	assert_bool(Movement.is_fast_mobility(slow_brigade)).is_false()
	assert_int(Movement.tactical_speed(slow_brigade)).is_equal(Movement.TACTICAL_SLOW)
	assert_int(Movement.administrative_speed(slow_brigade)).is_equal(Movement.ADMIN_SLOW)

	await assert_error(func() -> void:
		assert_int(Movement.move_allowance(slow_brigade, "road-march")).is_equal(0)
	).is_push_error("Unknown movement mode: road-march")


func test_reachable_set_and_tactical_allowance_are_enforced() -> void:
	var brigade: Brigade = GameData.get_brigade(RED_BRIGADE_ID)
	var start_hex := brigade.hex_id
	var allowance := Movement.tactical_speed(brigade)
	var reachable := GameData.find_reachable(start_hex, allowance)
	var valid_target := _first_reachable_hex_at_distance(start_hex, allowance, reachable)
	var invalid_target := _first_hex_at_distance(start_hex, allowance + 1)

	for hex_id in reachable:
		assert_int(_distance(start_hex, String(hex_id))).is_less_equal(allowance)

	GameState.add_move_order(Brigade.Team.RED, RED_BRIGADE_ID, valid_target, Movement.MODE_TACTICAL)
	assert_int(GameState.orders_for(Brigade.Team.RED).size()).is_equal(1)

	_reset_fixture()
	await assert_error(func() -> void:
		GameState.add_move_order(Brigade.Team.RED, RED_BRIGADE_ID, invalid_target, Movement.MODE_TACTICAL)
	).is_push_error("Move order target %s beyond %s allowance for %s" % [invalid_target, Movement.MODE_TACTICAL, RED_BRIGADE_ID])
	assert_int(GameState.orders_for(Brigade.Team.RED).size()).is_equal(0)


func test_re_move_is_blocked() -> void:
	var brigade: Brigade = GameData.get_brigade(RED_BRIGADE_ID)
	var target := _first_reachable_hex_at_distance(brigade.hex_id, Movement.tactical_speed(brigade), GameData.find_reachable(brigade.hex_id, Movement.tactical_speed(brigade)))

	GameState.add_move_order(Brigade.Team.RED, RED_BRIGADE_ID, target, Movement.MODE_TACTICAL)
	assert_int(GameState.orders_for(Brigade.Team.RED).size()).is_equal(1)

	await assert_error(func() -> void:
		GameState.add_move_order(Brigade.Team.RED, RED_BRIGADE_ID, brigade.hex_id, Movement.MODE_TACTICAL)
	).is_push_error("Brigade already has a pending move order this turn: %s" % RED_BRIGADE_ID)
	assert_int(GameState.orders_for(Brigade.Team.RED).size()).is_equal(1)


func test_org_costs_and_admin_flag_are_applied_and_reset() -> void:
	var brigade: Brigade = GameData.get_brigade(RED_BRIGADE_ID)
	var initial_org := brigade.organization

	GameState.add_move_order(Brigade.Team.RED, RED_BRIGADE_ID, brigade.hex_id, Movement.MODE_ADMINISTRATIVE)
	GameState.resolve_turn()

	assert_float(brigade.organization).is_equal(initial_org - Brigade.ADMIN_MOVE_ORG_COST)
	assert_bool(brigade.moved_admin_this_turn).is_true()

	GameState.begin_next_turn()
	assert_bool(brigade.moved_admin_this_turn).is_false()

	_reset_fixture()
	brigade = GameData.get_brigade(RED_BRIGADE_ID)
	initial_org = brigade.organization

	GameState.add_move_order(Brigade.Team.RED, RED_BRIGADE_ID, brigade.hex_id, Movement.MODE_TACTICAL)
	GameState.resolve_turn()

	assert_float(brigade.organization).is_equal(initial_org - Brigade.TACTICAL_MOVE_ORG_COST)
	assert_bool(brigade.moved_admin_this_turn).is_false()


func _first_reachable_hex_at_distance(start_hex: String, distance: int, reachable: Array) -> String:
	var candidates: Array[String] = []
	for hex_id in reachable:
		var typed_hex_id := String(hex_id)
		if _distance(start_hex, typed_hex_id) == distance:
			candidates.append(typed_hex_id)
	candidates.sort()
	assert_bool(candidates.is_empty()).is_false()
	return candidates[0]


func _first_hex_at_distance(start_hex: String, distance: int) -> String:
	var candidates: Array[String] = []
	for hex_id in GameData.hex_lookup.keys():
		var typed_hex_id := String(hex_id)
		if _distance(start_hex, typed_hex_id) == distance:
			candidates.append(typed_hex_id)
	candidates.sort()
	assert_bool(candidates.is_empty()).is_false()
	return candidates[0]


func _distance(hex_id_a: String, hex_id_b: String) -> int:
	var hex_a: Hex = GameData.get_hex(hex_id_a)
	var hex_b: Hex = GameData.get_hex(hex_id_b)
	return HexMath.distance(hex_a.coord, hex_b.coord)


func _reset_fixture() -> void:
	GameData.load_all()
	GameState.reset_to_scenario()
