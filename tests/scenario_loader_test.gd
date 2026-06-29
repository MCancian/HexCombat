extends GdUnitTestSuite

const GameDataScript := preload("res://scripts/GameData.gd")


func test_default_scenario_loads_placements_and_meta() -> void:
	var data: GameDataStore = GameDataScript.new()
	data.load_all()

	var placed_brigades := 0
	for brigade in data.brigades.values():
		if not String(brigade.hex_id).is_empty():
			placed_brigades += 1
	assert_int(placed_brigades).is_equal(4)
	assert_int(data.red_ship_reserve.size()).is_equal(4)

	var pla_brigade: Brigade = data.get_brigade("PLA-71-2-Amphibious")
	assert_str(pla_brigade.hex_id).is_empty()
	assert_bool(_reserve_contains(data.red_ship_reserve, "PLA-71-2-Amphibious")).is_true()

	var roc_brigade: Brigade = data.get_brigade("BDE-66")
	assert_str(roc_brigade.hex_id).is_equal("hex_43_16")

	assert_int(data.turn_length_days).is_equal(1)
	assert_int(data.stacking_soft_cap).is_equal(6)

	data.free()


func _reserve_contains(reserve: Array, brigade_id: String) -> bool:
	for entry_value in reserve:
		var entry: Dictionary = entry_value
		if String(entry["brigade_id"]) == brigade_id:
			return true
	return false
