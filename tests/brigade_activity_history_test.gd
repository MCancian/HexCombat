## Verifies prior-turn activity flags (moved_last_turn / fought_last_turn) are latched in cleanup
## before the per-turn flags reset. Foundation for IJFS detection posture (PLAN.md 2026-06-28 D4-H).
extends GdUnitTestSuite


func before_test() -> void:
	GameData.load_all()
	GameState.reset_to_scenario()


func after_test() -> void:
	GameData.load_all()
	GameState.reset_to_scenario()


func _any_brigade() -> Brigade:
	return GameData.brigades.values()[0]


func test_flags_false_at_scenario_start() -> void:
	for brigade_value in GameData.brigades.values():
		var brigade: Brigade = brigade_value
		assert_bool(brigade.moved_last_turn).is_false()
		assert_bool(brigade.fought_last_turn).is_false()


func test_cleanup_latches_moved_and_fought() -> void:
	var brigade := _any_brigade()
	brigade.moved_this_turn = true
	brigade.fought_this_turn = true
	GameState.resolve_cleanup_phase()
	assert_bool(brigade.moved_last_turn).is_true()
	assert_bool(brigade.fought_last_turn).is_true()


func test_admin_move_counts_as_moved_last_turn() -> void:
	var brigade := _any_brigade()
	brigade.moved_this_turn = false
	brigade.moved_admin_this_turn = true
	brigade.fought_this_turn = false
	GameState.resolve_cleanup_phase()
	assert_bool(brigade.moved_last_turn).is_true()
	assert_bool(brigade.fought_last_turn).is_false()


func test_inactive_brigade_stays_false() -> void:
	var brigade := _any_brigade()
	brigade.moved_this_turn = false
	brigade.moved_admin_this_turn = false
	brigade.fought_this_turn = false
	GameState.resolve_cleanup_phase()
	assert_bool(brigade.moved_last_turn).is_false()
	assert_bool(brigade.fought_last_turn).is_false()
