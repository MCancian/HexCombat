extends GdUnitTestSuite


func test_no_win_when_outnumbered() -> void:
	var r: Dictionary = VictoryConditions.evaluate(3, 5, "unconditional", 1, false)
	assert_bool(r["game_over"]).is_false()
	assert_str(r["winner"]).is_equal("")
	assert_str(r["reason"]).is_equal("")


func test_china_majority_wins() -> void:
	var r: Dictionary = VictoryConditions.evaluate(6, 5, "unconditional", 1, true)
	assert_bool(r["game_over"]).is_true()
	assert_str(r["winner"]).is_equal("red")
	assert_str(r["reason"]).is_equal("china_majority")


func test_equal_is_not_a_win() -> void:
	var r: Dictionary = VictoryConditions.evaluate(5, 5, "unconditional", 1, false)
	assert_bool(r["game_over"]).is_false()
	assert_str(r["winner"]).is_equal("")
	assert_str(r["reason"]).is_equal("")


func test_china_eliminated_unconditional() -> void:
	var r: Dictionary = VictoryConditions.evaluate(0, 5, "unconditional", 1, false)
	assert_bool(r["game_over"]).is_true()
	assert_str(r["winner"]).is_equal("green")
	assert_str(r["reason"]).is_equal("china_eliminated")


func test_not_armed_when_after_first_landing_not_landed() -> void:
	var r: Dictionary = VictoryConditions.evaluate(0, 5, "after_first_landing", 1, false)
	assert_bool(r["game_over"]).is_false()
	assert_str(r["winner"]).is_equal("")
	assert_str(r["reason"]).is_equal("")


func test_armed_after_first_landing_landed() -> void:
	var r: Dictionary = VictoryConditions.evaluate(0, 5, "after_first_landing", 1, true)
	assert_bool(r["game_over"]).is_true()
	assert_str(r["winner"]).is_equal("green")
	assert_str(r["reason"]).is_equal("china_eliminated")


func test_after_turn_not_yet_armed() -> void:
	var r: Dictionary = VictoryConditions.evaluate(0, 5, "after_turn:2", 2, false)
	assert_bool(r["game_over"]).is_false()
	assert_str(r["winner"]).is_equal("")
	assert_str(r["reason"]).is_equal("")


func test_after_turn_armed() -> void:
	var r: Dictionary = VictoryConditions.evaluate(0, 5, "after_turn:2", 3, false)
	assert_bool(r["game_over"]).is_true()
	assert_str(r["winner"]).is_equal("green")
	assert_str(r["reason"]).is_equal("china_eliminated")


func test_china_eliminated_with_zero_taiwan() -> void:
	var r: Dictionary = VictoryConditions.evaluate(0, 0, "unconditional", 1, false)
	assert_bool(r["game_over"]).is_true()
	assert_str(r["winner"]).is_equal("green")
	assert_str(r["reason"]).is_equal("china_eliminated")
