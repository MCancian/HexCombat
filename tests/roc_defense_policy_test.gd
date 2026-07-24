## GdUnit4 tests for RocDefensePolicy (plan 0029 Tier A — concentrating defender).
extends GdUnitTestSuite


func _obs(legal_moves: Dictionary, occupied_hexes: Array = [], brigades: Array = []) -> Dictionary:
	return {
		"legal_moves": legal_moves,
		"occupied_hexes": occupied_hexes,
		"brigades": brigades,
	}


func test_moves_green_toward_nearest_red_owned_hex() -> void:
	var policy := RocDefensePolicy.new()
	# Green brigade at (10,10); threat (red-owned) at (0,0). Of the reachable hexes, (9,9) is nearer
	# the threat than the current hex (10,10) and than (11,11), so the brigade steps to hex_9_9.
	var obs := _obs(
		{"G1": {"team": "Green", "from_hex": "hex_10_10", "tactical": ["hex_9_9", "hex_11_11"]}},
		[{"hex_id": "hex_0_0", "owner": "red"}],
	)
	var actions := policy.build_actions(obs)
	assert_int(actions.size()).is_equal(1)
	assert_str(actions[0]["target_hex"]).is_equal("hex_9_9")
	assert_str(actions[0]["team"]).is_equal("Green")
	assert_str(actions[0]["brigade_id"]).is_equal("G1")


func test_contested_and_red_brigade_hexes_are_threats() -> void:
	var policy := RocDefensePolicy.new()
	# Threat sourced from a contested hex AND a red brigade's hex (not an owned hex).
	var obs := _obs(
		{"G1": {"team": "Green", "from_hex": "hex_10_10", "tactical": ["hex_9_9", "hex_10_11"]}},
		[{"hex_id": "hex_0_0", "owner": "contested"}],
		[{"team": "Red", "hex_id": "hex_0_0"}],
	)
	var actions := policy.build_actions(obs)
	assert_int(actions.size()).is_equal(1)
	assert_str(actions[0]["target_hex"]).is_equal("hex_9_9")


func test_holds_position_when_no_threat_visible() -> void:
	var policy := RocDefensePolicy.new()
	# Pre-landing: no red/contested hexes, no red brigades -> the defence holds, does not wander.
	var obs := _obs(
		{"G1": {"team": "Green", "from_hex": "hex_5_5", "tactical": ["hex_4_4", "hex_6_6"]}},
		[{"hex_id": "hex_5_5", "owner": "green"}],
	)
	assert_array(policy.build_actions(obs)).is_empty()


func test_holds_when_already_closest_to_threat() -> void:
	var policy := RocDefensePolicy.new()
	# The current hex is already nearer the threat than any reachable hex -> no move emitted.
	var obs := _obs(
		{"G1": {"team": "Green", "from_hex": "hex_1_1", "tactical": ["hex_5_5", "hex_6_6"]}},
		[{"hex_id": "hex_0_0", "owner": "red"}],
	)
	assert_array(policy.build_actions(obs)).is_empty()


func test_ignores_non_green_brigades() -> void:
	var policy := RocDefensePolicy.new()
	var obs := _obs(
		{"R1": {"team": "Red", "from_hex": "hex_10_10", "tactical": ["hex_9_9"]}},
		[{"hex_id": "hex_0_0", "owner": "red"}],
	)
	assert_array(policy.build_actions(obs)).is_empty()
