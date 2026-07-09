extends GdUnitTestSuite


func test_terrain_types_loaded() -> void:
	assert_int(GameData.terrain_types.size()).is_equal(4)

	var hills_tt: TerrainType = GameData.terrain_types["hills"]
	assert_int(hills_tt.move_cost).is_equal(2)

	var mountain_tt: TerrainType = GameData.terrain_types["mountain"]
	assert_bool(mountain_tt.impassable).is_true()

	var urban_tt: TerrainType = GameData.terrain_types["urban"]
	assert_float(urban_tt.defender_modifier).is_equal(2.0)


func test_all_hexes_classified() -> void:
	for hex in GameData.hexes:
		assert_bool(hex.terrain != "").is_true()
		var tt: TerrainType = GameData.get_terrain(hex.id)
		assert_that(tt).is_not_null()


func test_get_terrain_unknown_hex_returns_null() -> void:
	assert_that(GameData.get_terrain("hex_999_999")).is_null()
