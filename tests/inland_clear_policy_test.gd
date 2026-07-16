## GdUnit4 tests for InlandClearPolicy — pure observation-driven decisions over injected
## beach/adjacency data (the plan-0006 research policy promoted into PolicyCatalog).
extends GdUnitTestSuite

const BEACHES := {"hex_b1": true, "hex_b2": true}
const NEIGHBORS := {
	"hex_b1": ["hex_i2", "hex_b2", "hex_i1"],
	"hex_b2": ["hex_b1", "hex_i3"],
}


func _policy() -> InlandClearPolicy:
	return InlandClearPolicy.new(BEACHES, NEIGHBORS)


func _obs(legal_moves: Dictionary) -> Dictionary:
	return {"legal_moves": legal_moves}


func test_red_beach_sitter_moves_to_first_sorted_non_beach_neighbor() -> void:
	var actions := _policy().build_actions(_obs({
		"R1": {"team": "Red", "from_hex": "hex_b1", "tactical": ["hex_i1", "hex_i2", "hex_b2"]},
	}))
	assert_int(actions.size()).is_equal(1)
	var action: Dictionary = actions[0]
	assert_str(String(action["target_hex"])).is_equal("hex_i1")  # sorted: hex_b2 < hex_i1 < hex_i2; b2 is a beach
	assert_str(String(action["type"])).is_equal("move")
	assert_str(String(action["mode"])).is_equal(Movement.MODE_TACTICAL)


func test_green_and_inland_brigades_pass() -> void:
	var actions := _policy().build_actions(_obs({
		"G1": {"team": "Green", "from_hex": "hex_b1", "tactical": ["hex_i1"]},
		"R2": {"team": "Red", "from_hex": "hex_i1", "tactical": ["hex_b1"]},
	}))
	assert_array(actions).is_empty()


func test_illegal_neighbor_skipped_for_next_legal_one() -> void:
	# hex_i1 not in the tactical (legal) set this turn -> falls through to hex_i2.
	var actions := _policy().build_actions(_obs({
		"R1": {"team": "Red", "from_hex": "hex_b1", "tactical": ["hex_i2"]},
	}))
	assert_int(actions.size()).is_equal(1)
	assert_str(String((actions[0] as Dictionary)["target_hex"])).is_equal("hex_i2")


func test_no_non_beach_neighbor_holds() -> void:
	var actions := InlandClearPolicy.new({"hex_b1": true, "hex_b2": true, "hex_i3": true}, NEIGHBORS)\
		.build_actions(_obs({
			"R1": {"team": "Red", "from_hex": "hex_b2", "tactical": ["hex_b1", "hex_i3"]},
		}))
	assert_array(actions).is_empty()


func test_deterministic_brigade_order() -> void:
	var lm := {
		"R2": {"team": "Red", "from_hex": "hex_b2", "tactical": ["hex_i3"]},
		"R1": {"team": "Red", "from_hex": "hex_b1", "tactical": ["hex_i1"]},
	}
	var actions := _policy().build_actions(_obs(lm))
	assert_int(actions.size()).is_equal(2)
	assert_str(String((actions[0] as Dictionary)["brigade_id"])).is_equal("R1")
	assert_str(String((actions[1] as Dictionary)["brigade_id"])).is_equal("R2")
