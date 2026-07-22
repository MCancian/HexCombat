## GdUnit4 tests for GarrisonDrawPolicy
extends GdUnitTestSuite

const BEACH_TO_TO := {
	"hex_0_0": 1,
}

const BRIGADE_TO_TO := {
	"G1": 1,
	"G2": 2,
	"G3": 2,
	"G4": 3,
}

func _obs(legal_moves: Dictionary, occupied_hexes: Array = [], brigades: Array = []) -> Dictionary:
	return {
		"legal_moves": legal_moves,
		"occupied_hexes": occupied_hexes,
		"brigades": brigades,
	}

func test_identify_landing_to_from_owner() -> void:
	var policy := GarrisonDrawPolicy.new(BEACH_TO_TO, BRIGADE_TO_TO, 1.0)
	var obs := _obs(
		{
			"G2": {"team": "Green", "from_hex": "hex_5_5", "tactical": ["hex_4_4", "hex_4_5"]}
		},
		[
			{"hex_id": "hex_0_0", "owner": "red"}
		]
	)
	var actions := policy.build_actions(obs)
	# TO 1 is landing. G2 is in TO 2. G2 should move towards hex_0_0.
	assert_int(actions.size()).is_equal(1)
	# from (5,5) towards (0,0).
	# dist(4,4) to (0,0):
	# oddr(4,4) -> q = 4-2=2, r=4 -> (2, 4, -6)
	# oddr(0,0) -> (0, 0, 0)
	# dist = (2 + 4 + 6) / 2 = 6
	# dist(4,5) to (0,0):
	# oddr(4,5) -> q = 4-2=2, r=5 -> (2, 5, -7)
	# dist = (2 + 5 + 7) / 2 = 7
	assert_str(String(actions[0]["target_hex"])).is_equal("hex_4_4")

func test_draw_fraction() -> void:
	# 3 brigades in non-landing TOs: G2, G3, G4.
	# With 0.5 draw fraction, ceil(3 * 0.5) = 2 drawn.
	# G2, G3 drawn. G4 holds.
	var policy := GarrisonDrawPolicy.new(BEACH_TO_TO, BRIGADE_TO_TO, 0.5)
	var obs := _obs(
		{
			"G2": {"team": "Green", "from_hex": "hex_5_5", "tactical": ["hex_4_4"]},
			"G3": {"team": "Green", "from_hex": "hex_5_5", "tactical": ["hex_4_4"]},
			"G4": {"team": "Green", "from_hex": "hex_5_5", "tactical": ["hex_4_4"]},
		},
		[
			{"hex_id": "hex_0_0", "owner": "red"}
		]
	)
	var actions := policy.build_actions(obs)
	assert_int(actions.size()).is_equal(2)
	assert_str(String((actions[0] as Dictionary)["brigade_id"])).is_equal("G2")
	assert_str(String((actions[1] as Dictionary)["brigade_id"])).is_equal("G3")

func test_local_defense_in_landing_to() -> void:
	# G1 is in landing TO. It should move towards nearest Red brigade.
	var policy := GarrisonDrawPolicy.new(BEACH_TO_TO, BRIGADE_TO_TO, 1.0)
	var obs := _obs(
		{
			"G1": {"team": "Green", "from_hex": "hex_2_2", "tactical": ["hex_1_1", "hex_1_2"]}
		},
		[],
		[
			{"team": "Red", "id": "R1", "hex_id": "hex_0_0"}
		]
	)
	var actions := policy.build_actions(obs)
	assert_int(actions.size()).is_equal(1)
	assert_str(String((actions[0] as Dictionary)["brigade_id"])).is_equal("G1")
	# dist(1,1) to (0,0) -> 2
	# dist(1,2) to (0,0):
	# oddr(1,2) -> q = 1-1=0, r=2 -> (0, 2, -2)
	# dist = (0+2+2)/2 = 2
	# They have the same distance, tie break alphabetically -> hex_1_1
	assert_str(String((actions[0] as Dictionary)["target_hex"])).is_equal("hex_1_1")
